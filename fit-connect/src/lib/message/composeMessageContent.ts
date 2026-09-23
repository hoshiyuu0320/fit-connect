/**
 * 送信本文 = 記録の引用（あれば）+ 改行 + 入力。
 * 引用が無いときは入力をそのまま返し、既存の送信挙動を変えない。
 */
export function composeMessageContent(quoteText: string | null | undefined, input: string): string {
  if (!quoteText) return input
  const body = input.trim()
  return body ? `${quoteText}\n${body}` : quoteText
}
