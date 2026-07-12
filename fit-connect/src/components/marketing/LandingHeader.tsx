/**
 * LP ヘッダー（静的・非sticky）
 * ロゴは (user_console) グローバルヘッダーの FC ロゴマーク + ワードマークの流儀を踏襲
 */
import Link from 'next/link'

export function LandingHeader() {
  return (
    <header className="bg-white border-b border-[#E2E8F0]">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between">
        <Link
          href="/"
          className="flex items-center gap-2.5 rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6] focus-visible:ring-offset-2"
        >
          <span className="w-8 h-8 bg-[#0F172A] rounded-md flex items-center justify-center text-[#14B8A6] font-bold text-[11px]">
            FC
          </span>
          <span className="font-bold text-[16px] text-[#0F172A] tracking-tight">
            FitConnect
          </span>
        </Link>

        <nav className="flex items-center gap-2 sm:gap-3">
          <Link
            href="/login"
            className="inline-flex items-center h-9 px-3 sm:px-4 rounded-md text-sm font-medium text-[#475569] hover:text-[#0F172A] hover:bg-[#F8FAFC] transition-colors duration-150 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6] focus-visible:ring-offset-2"
          >
            ログイン
          </Link>
          <Link
            href="/signup"
            className="inline-flex items-center h-9 px-4 rounded-md bg-[#0F172A] text-sm font-medium text-white hover:bg-[#1E293B] transition-colors duration-150 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6] focus-visible:ring-offset-2"
          >
            無料で始める
          </Link>
        </nav>
      </div>
    </header>
  )
}
