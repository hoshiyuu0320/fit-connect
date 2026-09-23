import { describe, it, expect } from 'vitest'
import { composeMessageContent } from '@/lib/message/composeMessageContent'

describe('composeMessageContent', () => {
  it('引用が無ければ入力をそのまま返す（前後の空白も触らない）', () => {
    expect(composeMessageContent(null, ' こんにちは ')).toBe(' こんにちは ')
    expect(composeMessageContent(undefined, '')).toBe('')
    expect(composeMessageContent('', 'a')).toBe('a')
  })
  it('引用があれば「引用 + 改行 + 入力（前後の空白を除く）」', () => {
    expect(composeMessageContent('【睡眠 9/22(火)】4時間12分', '  昨夜は短かったですね\n早めに休みましょう  '))
      .toBe('【睡眠 9/22(火)】4時間12分\n昨夜は短かったですね\n早めに休みましょう')
  })
  it('引用があって入力が空白だけなら引用だけ（末尾に改行を残さない）', () => {
    expect(composeMessageContent('【睡眠 9/22(火)】4時間12分', '   ')).toBe('【睡眠 9/22(火)】4時間12分')
  })
})
