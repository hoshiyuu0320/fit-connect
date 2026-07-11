/**
 * 法務ページ共通レイアウト（利用規約 / プライバシーポリシー / 特定商取引法に基づく表記）
 *
 * 【注意】各ページの本文はドラフトであり、公開前に弁護士等の専門家レビューを推奨します。
 * 【注意】公開前に本文中の「【要記入: ◯◯】」箇所を全て埋めること。
 */
import Link from 'next/link';

export default function LegalLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <div className="min-h-screen bg-[#F8FAFC] flex flex-col">
      {/* Header */}
      <header className="bg-white border-b border-[#E2E8F0]">
        <div className="max-w-3xl mx-auto px-4 sm:px-6 h-14 flex items-center">
          <Link
            href="/"
            className="text-[#0F172A] text-sm font-bold tracking-widest hover:text-[#334155] transition-colors"
          >
            FIT-CONNECT
          </Link>
        </div>
      </header>

      {/* Content */}
      <main className="flex-1 px-4 sm:px-6 py-10 sm:py-14">
        <div className="max-w-3xl mx-auto">{children}</div>
      </main>

      {/* Footer */}
      <footer className="bg-white border-t border-[#E2E8F0]">
        <div className="max-w-3xl mx-auto px-4 sm:px-6 py-8 flex flex-col sm:flex-row items-center justify-between gap-4">
          <nav className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2">
            <Link
              href="/terms"
              className="text-sm text-[#475569] hover:text-[#0F172A] transition-colors"
            >
              利用規約
            </Link>
            <Link
              href="/privacy"
              className="text-sm text-[#475569] hover:text-[#0F172A] transition-colors"
            >
              プライバシーポリシー
            </Link>
            <Link
              href="/tokushoho"
              className="text-sm text-[#475569] hover:text-[#0F172A] transition-colors"
            >
              特定商取引法に基づく表記
            </Link>
          </nav>
          <p className="text-xs text-[#94A3B8]">© 2026 FIT-CONNECT</p>
        </div>
      </footer>
    </div>
  );
}
