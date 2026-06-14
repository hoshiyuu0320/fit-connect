import { describe, it, expect } from 'vitest'
import { parseRecordMessage } from '@/components/message/recordCardParser'

describe('parseRecordMessage — tags優先', () => {
  it('tagsが#食事:昼食なら、contentが#始まりでなくてもmeal判定', () => {
    const r = parseRecordMessage('サラダチキン', ['#食事:昼食'])
    expect(r?.type).toBe('meal')
    expect(r?.label).toBe('食事記録 ─ 昼食')
    expect(r?.details).toEqual(['サラダチキン'])
  })
  it('tagsが#体重なら weight 判定（本文はdetailsに）', () => {
    const r = parseRecordMessage('#体重 62.4kg', ['#体重'])
    expect(r?.type).toBe('weight')
    expect(r?.details).toEqual(['62.4kg'])
  })
  it('tagsが#運動:筋トレ なら exercise 判定', () => {
    const r = parseRecordMessage('#運動:筋トレ ベンチ 30分 150kcal', ['#運動:筋トレ'])
    expect(r?.type).toBe('exercise')
    expect(r?.label).toBe('運動記録 ─ 筋トレ')
  })
  it('contentが本日形式ならachievement（content-first path）', () => {
    // content-first（workoutAchievementMatch）で達成判定。parseFromTag には到達しない
    const r = parseRecordMessage('本日のワークアウトプラン「脚の日」を達成しました！', ['#運動:完了'])
    expect(r?.type).toBe('achievement')
  })
  it('tagsが#運動:完了でcontentが本日形式でない場合もachievement判定', () => {
    // content-first を素通りし parseFromTag の #運動:完了 branch を実際に通す
    const r = parseRecordMessage('ジムのワークアウト完了', ['#運動:完了'])
    expect(r?.type).toBe('achievement')
  })
  it('未認識タグ＋#始まりでないcontentは null（graceful fallthrough）', () => {
    // parseFromTag が null → content 判定へフォールスルー → #始まりでないため null
    expect(parseRecordMessage('ただのメモ', ['#栄養'])).toBeNull()
  })
})

describe('parseRecordMessage — content後方互換（tags空）', () => {
  it('#体重 を従来どおり判定', () => {
    expect(parseRecordMessage('#体重 62.4kg')?.type).toBe('weight')
  })
  it('#食事:朝食 テキスト付き', () => {
    expect(parseRecordMessage('#食事:朝食 トースト')?.label).toBe('食事記録 ─ 朝食')
  })
  it('ワークアウト達成のcontentパターン（#なし）', () => {
    expect(parseRecordMessage('本日のワークアウトプラン「脚の日」を達成しました！')?.type).toBe('achievement')
  })
  it('通常メッセージは null', () => {
    expect(parseRecordMessage('こんにちは')).toBeNull()
  })
})
