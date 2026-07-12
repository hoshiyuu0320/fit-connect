/**
 * LP フッター
 */
import Link from 'next/link'

const FOOTER_LINKS = [
  { href: '/terms', label: '利用規約' },
  { href: '/privacy', label: 'プライバシーポリシー' },
  { href: '/tokushoho', label: '特定商取引法に基づく表記' },
  { href: '/login', label: 'ログイン' },
] as const

export function LandingFooter() {
  return (
    <footer className="bg-white border-t border-[#E2E8F0]">
      <div className="max-w-6xl mx-auto flex flex-col items-center gap-6 px-4 py-10 sm:px-6 lg:flex-row lg:justify-between">
        <div className="flex items-center gap-2.5">
          <span className="w-8 h-8 bg-[#0F172A] rounded-md flex items-center justify-center text-[#14B8A6] font-bold text-[11px]">
            FC
          </span>
          <span className="font-bold text-[16px] text-[#0F172A] tracking-tight">
            FitConnect
          </span>
        </div>

        <nav className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2">
          {FOOTER_LINKS.map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              className="text-sm text-[#475569] hover:text-[#0F172A] transition-colors duration-150 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6] focus-visible:ring-offset-2 rounded-sm"
            >
              {label}
            </Link>
          ))}
        </nav>

        <p className="text-xs text-[#94A3B8]">© 2026 FIT-CONNECT</p>
      </div>
    </footer>
  )
}
