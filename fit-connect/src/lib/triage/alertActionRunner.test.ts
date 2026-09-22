import { describe, it, expect, vi } from 'vitest'
import {
  createAlertActionRunner,
  isAlertActionApplied,
  type AlertActionRunnerDeps,
} from '@/lib/triage/alertActionRunner'
import {
  createTriageListState,
  selectVisibleAlerts,
  triageListReducer,
  type TriageListAction,
  type TriageListState,
} from '@/lib/triage/triageListState'
import type { AlertPatchAction, AlertStatus, ClientAlert } from '@/types/alert'

type Deferred<T> = {
  promise: Promise<T>
  resolve: (value: T) => void
  reject: (reason: unknown) => void
}

function deferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void
  let reject!: (reason: unknown) => void
  const promise = new Promise<T>((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

/** 保留中の Promise の後続（then）をすべて流す */
const flush = () => new Promise<void>((resolve) => setTimeout(resolve, 0))

type Call = { alertId: string; action: AlertPatchAction; response: Deferred<{ id: string; status: AlertStatus }> }

/** API の呼び出しを記録し、応答をテストから返せるようにした deps */
function setup() {
  const calls: Call[] = []
  const dispatched: TriageListAction[] = []
  const deps: AlertActionRunnerDeps = {
    dispatch: vi.fn((action: TriageListAction) => {
      dispatched.push(action)
    }),
    updateStatus: vi.fn((alertId: string, action: AlertPatchAction) => {
      const response = deferred<{ id: string; status: AlertStatus }>()
      calls.push({ alertId, action, response })
      return response.promise
    }),
    onAcknowledgeFailed: vi.fn(),
    onUndoFailed: vi.fn(),
    onSettled: vi.fn(),
  }
  const runner = createAlertActionRunner(deps)
  const types = () => dispatched.map((action) => action.type)
  return { calls, dispatched, deps, runner, types }
}

describe('isAlertActionApplied', () => {
  it('acknowledge は open 以外なら反映済み、reopen は open のときだけ反映済み', () => {
    expect(isAlertActionApplied('acknowledge', 'acknowledged')).toBe(true)
    expect(isAlertActionApplied('acknowledge', 'resolved')).toBe(true)
    expect(isAlertActionApplied('acknowledge', 'open')).toBe(false)
    expect(isAlertActionApplied('reopen', 'open')).toBe(true)
    expect(isAlertActionApplied('reopen', 'acknowledged')).toBe(false)
    expect(isAlertActionApplied('reopen', 'resolved')).toBe(false)
  })
})

describe('対応済み', () => {
  it('API より先に acknowledge を dispatch し、成功したら確定して取り直しを呼ぶ', async () => {
    const { calls, deps, runner, types } = setup()
    const done = runner.acknowledge('a')

    // API の応答前に行を外している
    expect(types()).toEqual(['acknowledge'])
    await flush()
    expect(calls.map((c) => [c.alertId, c.action])).toEqual([['a', 'acknowledge']])

    calls[0].response.resolve({ id: 'a', status: 'acknowledged' })
    await done
    expect(types()).toEqual(['acknowledge', 'acknowledgeSucceeded'])
    expect(deps.onAcknowledgeFailed).not.toHaveBeenCalled()
    expect(deps.onSettled).toHaveBeenCalledTimes(1)
    expect(deps.onSettled).toHaveBeenCalledWith('a')
  })

  it('その間に検知で解消されていた（resolved）場合も成功として扱う', async () => {
    const { calls, deps, runner, types } = setup()
    const done = runner.acknowledge('a')
    await flush()
    calls[0].response.resolve({ id: 'a', status: 'resolved' })
    await done
    expect(types()).toEqual(['acknowledge', 'acknowledgeSucceeded'])
    expect(deps.onAcknowledgeFailed).not.toHaveBeenCalled()
  })

  it('API が失敗したら巻き戻して onAcknowledgeFailed（request_failed）', async () => {
    const { calls, deps, runner, types } = setup()
    const done = runner.acknowledge('a')
    await flush()
    calls[0].response.reject(new Error('HTTP 500'))
    await done
    expect(types()).toEqual(['acknowledge', 'acknowledgeFailed'])
    expect(deps.onAcknowledgeFailed).toHaveBeenCalledWith('a', 'request_failed')
    expect(deps.onSettled).toHaveBeenCalledTimes(1)
  })

  it('200 でも status が open のままなら巻き戻す（not_applied）', async () => {
    const { calls, deps, runner, types } = setup()
    const done = runner.acknowledge('a')
    await flush()
    calls[0].response.resolve({ id: 'a', status: 'open' })
    await done
    expect(types()).toEqual(['acknowledge', 'acknowledgeFailed'])
    expect(deps.onAcknowledgeFailed).toHaveBeenCalledWith('a', 'not_applied')
  })
})

describe('元に戻す', () => {
  it('成功したら undoSucceeded', async () => {
    const { calls, deps, runner, types } = setup()
    const done = runner.undo('a')
    expect(types()).toEqual(['undo'])
    await flush()
    expect(calls.map((c) => c.action)).toEqual(['reopen'])
    calls[0].response.resolve({ id: 'a', status: 'open' })
    await done
    expect(types()).toEqual(['undo', 'undoSucceeded'])
    expect(deps.onUndoFailed).not.toHaveBeenCalled()
    expect(deps.onSettled).toHaveBeenCalledWith('a')
  })

  it('API が失敗したら undoFailed と onUndoFailed（request_failed）', async () => {
    const { calls, deps, runner, types } = setup()
    const done = runner.undo('a')
    await flush()
    calls[0].response.reject(new Error('network'))
    await done
    expect(types()).toEqual(['undo', 'undoFailed'])
    expect(deps.onUndoFailed).toHaveBeenCalledWith('a', 'request_failed')
  })

  it('その間に解消されていた（resolved）なら元に戻せない（not_applied）', async () => {
    const { calls, deps, runner, types } = setup()
    const done = runner.undo('a')
    await flush()
    calls[0].response.resolve({ id: 'a', status: 'resolved' })
    await done
    expect(types()).toEqual(['undo', 'undoFailed'])
    expect(deps.onUndoFailed).toHaveBeenCalledWith('a', 'not_applied')
  })
})

describe('同じアラートへの呼び出しの順序', () => {
  it('acknowledge の応答前に押された「元に戻す」は、応答が来てから reopen を送る', async () => {
    const { calls, runner } = setup()
    const ack = runner.acknowledge('a')
    const undo = runner.undo('a')
    await flush()
    // reopen はまだ送られていない
    expect(calls.map((c) => c.action)).toEqual(['acknowledge'])

    calls[0].response.resolve({ id: 'a', status: 'acknowledged' })
    await flush()
    expect(calls.map((c) => c.action)).toEqual(['acknowledge', 'reopen'])

    calls[1].response.resolve({ id: 'a', status: 'open' })
    await Promise.all([ack, undo])
  })

  it('前の呼び出しが失敗しても、次の呼び出しは送る', async () => {
    const { calls, runner } = setup()
    const ack = runner.acknowledge('a')
    const undo = runner.undo('a')
    await flush()
    calls[0].response.reject(new Error('HTTP 500'))
    await flush()
    expect(calls.map((c) => c.action)).toEqual(['acknowledge', 'reopen'])
    calls[1].response.resolve({ id: 'a', status: 'open' })
    await Promise.all([ack, undo])
  })

  it('別のアラートは待たずに送る', async () => {
    const { calls, runner } = setup()
    const first = runner.acknowledge('a')
    const second = runner.acknowledge('b')
    await flush()
    expect(calls.map((c) => c.alertId)).toEqual(['a', 'b'])
    calls[1].response.resolve({ id: 'b', status: 'acknowledged' })
    calls[0].response.resolve({ id: 'a', status: 'acknowledged' })
    await Promise.all([first, second])
  })

  it('「元に戻す」の後に acknowledge が失敗しても、巻き戻しも失敗の通知もしない', async () => {
    const { calls, deps, runner, types } = setup()
    const ack = runner.acknowledge('a')
    const undo = runner.undo('a')
    await flush()
    calls[0].response.reject(new Error('HTTP 500'))
    await flush()
    // サーバーは open のまま → reopen は条件に合わず、今の status（open）が返る
    calls[1].response.resolve({ id: 'a', status: 'open' })
    await Promise.all([ack, undo])

    expect(types()).toEqual(['acknowledge', 'undo', 'undoSucceeded'])
    expect(deps.onAcknowledgeFailed).not.toHaveBeenCalled()
    expect(deps.onUndoFailed).not.toHaveBeenCalled()
    expect(deps.onSettled).toHaveBeenCalledTimes(2)
  })

  it('「元に戻す」の後に acknowledge が成功しても、確定の dispatch はしない', async () => {
    const { calls, runner, types } = setup()
    const ack = runner.acknowledge('a')
    const undo = runner.undo('a')
    await flush()
    calls[0].response.resolve({ id: 'a', status: 'acknowledged' })
    await flush()
    calls[1].response.resolve({ id: 'a', status: 'open' })
    await Promise.all([ack, undo])
    expect(types()).toEqual(['acknowledge', 'undo', 'undoSucceeded'])
  })

  it('元に戻した後にもう一度対応済みにした分の失敗は、通常どおり巻き戻す', async () => {
    const { calls, deps, runner, types } = setup()
    const ack1 = runner.acknowledge('a')
    await flush()
    calls[0].response.resolve({ id: 'a', status: 'acknowledged' })
    await ack1
    const undo = runner.undo('a')
    await flush()
    calls[1].response.resolve({ id: 'a', status: 'open' })
    await undo

    const ack2 = runner.acknowledge('a')
    await flush()
    calls[2].response.reject(new Error('HTTP 500'))
    await ack2
    expect(types()).toEqual([
      'acknowledge',
      'acknowledgeSucceeded',
      'undo',
      'undoSucceeded',
      'acknowledge',
      'acknowledgeFailed',
    ])
    expect(deps.onAcknowledgeFailed).toHaveBeenCalledTimes(1)
  })
})

describe('reducer と組み合わせた一覧の見え方', () => {
  function makeAlert(id: string): ClientAlert {
    return {
      id,
      client_id: `client-${id}`,
      alert_type: 'record_gap',
      severity: 'medium',
      status: 'open',
      payload: {
        v: 1,
        variant: 'no_data',
        gap_from: '2026-09-09',
        gap_to: '2026-09-12',
        last_activity_on: '2026-09-08',
        last_record_on: '2026-09-08',
        threshold_days: 3,
      },
      first_detected_on: '2026-09-12',
      surfaced_on: '2026-09-12',
      last_detected_on: '2026-09-13',
      acknowledged_at: null,
      reopened_count: 0,
      client_name: `顧客${id}`,
      client_profile_image_url: null,
    }
  }

  function setupWithReducer(alerts: ClientAlert[]) {
    let state: TriageListState = createTriageListState(alerts)
    const base = setup()
    const runner = createAlertActionRunner({
      ...base.deps,
      dispatch: (action) => {
        state = triageListReducer(state, action)
      },
    })
    const visible = () => selectVisibleAlerts(state).map((alert) => alert.id)
    return { ...base, runner, visible, getState: () => state }
  }

  it('失敗した acknowledge は行に戻り、応答待ちの間は外れている', async () => {
    const { calls, runner, visible } = setupWithReducer([makeAlert('a'), makeAlert('b')])
    const done = runner.acknowledge('a')
    expect(visible()).toEqual(['b'])
    await flush()
    calls[0].response.reject(new Error('HTTP 500'))
    await done
    expect(visible()).toEqual(['a', 'b'])
  })

  it('応答待ちの間に元に戻し、acknowledge が失敗・reopen が open を返すと、行は出たまま', async () => {
    const { calls, runner, visible, getState } = setupWithReducer([makeAlert('a')])
    const ack = runner.acknowledge('a')
    const undo = runner.undo('a')
    expect(visible()).toEqual(['a'])
    await flush()
    calls[0].response.reject(new Error('HTTP 500'))
    await flush()
    calls[1].response.resolve({ id: 'a', status: 'open' })
    await Promise.all([ack, undo])
    expect(visible()).toEqual(['a'])
    expect(getState().hidden).toEqual({})
    expect(getState().restoring).toEqual({})
  })

  it('元に戻せなかったら、行は再び外れる', async () => {
    const { calls, runner, visible } = setupWithReducer([makeAlert('a')])
    const ack = runner.acknowledge('a')
    await flush()
    calls[0].response.resolve({ id: 'a', status: 'acknowledged' })
    await ack
    const undo = runner.undo('a')
    expect(visible()).toEqual(['a'])
    await flush()
    calls[1].response.reject(new Error('HTTP 500'))
    await undo
    expect(visible()).toEqual([])
  })
})
