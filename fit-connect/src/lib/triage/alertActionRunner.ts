/**
 * 「今日の対応」の「対応済み」「元に戻す」の API 呼び出しの流れ（React に依存しない）。
 *
 * - 画面の状態は triageListState の reducer に dispatch する（押したら先に外す → 応答で確定 / 巻き戻し）
 * - 同じアラートへの API は、前の呼び出しが終わってから送る（triageListState の約束）。
 *   「元に戻す」の reopen が acknowledge より先に届くと、サーバーは acknowledged のまま残るため
 * - 成否: API は条件に合わないとき今の status を 200 で返す（冪等）ので、応答の status で決める。
 *   acknowledge は open 以外（acknowledged・その間に解消された resolved）なら成功、reopen は open のときだけ成功
 * - acknowledge の応答待ちの間に「元に戻す」が押されたら、その acknowledge の結果は反映しない
 *   （行はもう戻っていて、続く reopen がサーバーの状態に合わせる。失敗のトーストも出さない）
 * - トーストと取り直しは呼び出し側（TriageSection）のコールバックに任せる
 */

import type { TriageListAction } from '@/lib/triage/triageListState'
import type { AlertPatchAction, AlertStatus } from '@/types/alert'

/** request_failed: 通信・HTTP の失敗 / not_applied: 応答はあったが状態が変わらなかった */
export type AlertActionFailure = 'request_failed' | 'not_applied'

export type AlertActionRunnerDeps = {
  dispatch: (action: TriageListAction) => void
  updateStatus: (
    alertId: string,
    action: AlertPatchAction
  ) => Promise<{ id: string; status: AlertStatus }>
  /** 対応済みにできなかった（行は巻き戻し済み） */
  onAcknowledgeFailed: (alertId: string, reason: AlertActionFailure) => void
  /** 元に戻せなかった（行は再び外し済み） */
  onUndoFailed: (alertId: string, reason: AlertActionFailure) => void
  /** API の応答の後（成否どちらでも）。一覧とバッジの取り直しに使う */
  onSettled: (alertId: string) => void
}

export type AlertActionRunner = {
  /** 「対応済み」を押した */
  acknowledge: (alertId: string) => Promise<void>
  /** トーストの「元に戻す」を押した */
  undo: (alertId: string) => Promise<void>
}

/** 応答の status で、操作が反映されたかを決める */
export function isAlertActionApplied(action: AlertPatchAction, status: AlertStatus): boolean {
  return action === 'acknowledge' ? status !== 'open' : status === 'open'
}

export function createAlertActionRunner(deps: AlertActionRunnerDeps): AlertActionRunner {
  // アラートごとの直前の呼び出し（成否に関わらず、終わると resolve する）
  const tails = new Map<string, Promise<void>>()
  // アラートごとに「元に戻す」が押された回数（acknowledge の後に押されたかを、応答の順序に依らず判定する）
  const undoCounts = new Map<string, number>()

  /** 同じアラートの前の呼び出しが終わってから task を始める。前の呼び出しの失敗では止めない */
  function enqueue<T>(alertId: string, task: () => Promise<T>): Promise<T> {
    const previous = tails.get(alertId) ?? Promise.resolve()
    const result = previous.then(task)
    const tail = result.then(
      () => undefined,
      () => undefined
    )
    tails.set(alertId, tail)
    void tail.then(() => {
      if (tails.get(alertId) === tail) tails.delete(alertId)
    })
    return result
  }

  async function send(alertId: string, action: AlertPatchAction): Promise<AlertActionFailure | null> {
    try {
      const { status } = await enqueue(alertId, () => deps.updateStatus(alertId, action))
      return isAlertActionApplied(action, status) ? null : 'not_applied'
    } catch {
      return 'request_failed'
    }
  }

  async function acknowledge(alertId: string): Promise<void> {
    const undoCountAtStart = undoCounts.get(alertId) ?? 0
    deps.dispatch({ type: 'acknowledge', alertId })

    const failure = await send(alertId, 'acknowledge')
    const undoneSinceStart = (undoCounts.get(alertId) ?? 0) !== undoCountAtStart
    if (!undoneSinceStart) {
      if (failure === null) {
        deps.dispatch({ type: 'acknowledgeSucceeded', alertId })
      } else {
        deps.dispatch({ type: 'acknowledgeFailed', alertId })
        deps.onAcknowledgeFailed(alertId, failure)
      }
    }
    deps.onSettled(alertId)
  }

  async function undo(alertId: string): Promise<void> {
    undoCounts.set(alertId, (undoCounts.get(alertId) ?? 0) + 1)
    deps.dispatch({ type: 'undo', alertId })

    const failure = await send(alertId, 'reopen')
    if (failure === null) {
      deps.dispatch({ type: 'undoSucceeded', alertId })
    } else {
      deps.dispatch({ type: 'undoFailed', alertId })
      deps.onUndoFailed(alertId, failure)
    }
    deps.onSettled(alertId)
  }

  return { acknowledge, undo }
}
