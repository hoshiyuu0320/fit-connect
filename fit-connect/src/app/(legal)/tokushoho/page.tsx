/**
 * 特定商取引法に基づく表記ページ
 *
 * 【注意】本文書はドラフトであり、公開前に弁護士等の専門家レビューを推奨します。
 * 【注意】公開前に本文中の「【要記入: ◯◯】」箇所を全て埋めること。
 *   - 【要記入: 事業者氏名（屋号がある場合は屋号および氏名）】
 *   - 【要記入: 住所】
 *   - 【要記入: 電話番号】
 *   - 【要記入: 問い合わせメールアドレス】
 *   - 【要記入: Proプラン月額料金】
 *
 * ※所在地・電話番号について:
 *   個人事業主の場合、消費者庁の解釈により「請求があった場合、遅滞なく開示します」と
 *   記載し、実際の請求時に速やかに開示する方式も選択できます（住所・電話番号の
 *   非公開を希望する場合はこの方式を検討すること）。
 */
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: '特定商取引法に基づく表記 | FIT-CONNECT',
  description: 'FIT-CONNECTの特定商取引法に基づく表記です。',
};

function Row({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="py-5 border-b border-[#E2E8F0] last:border-b-0 sm:grid sm:grid-cols-[200px_1fr] sm:gap-6">
      <dt className="text-sm font-semibold text-[#0F172A]">{label}</dt>
      <dd className="mt-1.5 sm:mt-0 text-sm leading-7 text-[#334155]">
        {children}
      </dd>
    </div>
  );
}

export default function TokushohoPage() {
  return (
    <article className="bg-white border border-[#E2E8F0] rounded-md px-6 py-10 sm:px-10 sm:py-12">
      <h1 className="text-2xl font-bold text-[#0F172A]">
        特定商取引法に基づく表記
      </h1>
      <p className="mt-2 text-xs text-[#94A3B8]">最終更新日: 2026年7月11日</p>

      <dl className="mt-8">
        <Row label="事業者名">
          【要記入: 事業者氏名（屋号がある場合は屋号および氏名）】
        </Row>

        {/* ※「請求があった場合、遅滞なく開示します」という記載方式も選択可能 */}
        <Row label="所在地">【要記入: 住所】</Row>

        {/* ※「請求があった場合、遅滞なく開示します」という記載方式も選択可能 */}
        <Row label="電話番号">【要記入: 電話番号】</Row>

        <Row label="メールアドレス">
          【要記入: 問い合わせメールアドレス】
        </Row>

        <Row label="販売価格">
          Proプラン: 月額【要記入: Proプラン月額料金】円（税込）
        </Row>

        <Row label="商品代金以外の必要料金">
          なし（本サービスの利用に必要なインターネット通信費等は、お客様のご負担となります）
        </Row>

        <Row label="支払方法">クレジットカード決済（Stripe）</Row>

        <Row label="支払時期">申込時および毎月の更新日に課金されます。</Row>

        <Row label="サービスの提供時期">
          決済完了後、直ちにご利用いただけます。
        </Row>

        <Row label="解約・キャンセル">
          いつでも解約いただけます。解約後も次回更新日までサービスをご利用いただけます。なお、期間途中の解約による日割精算・返金は行いません。
        </Row>

        <Row label="動作環境">
          <ul className="list-disc pl-5 space-y-1">
            <li>
              Webアプリ: 最新版の主要ブラウザ（Google Chrome、Safari、Microsoft
              Edge、Firefox）を推奨
            </li>
            <li>
              モバイルアプリ（顧客向け）: iOS／Android（対応バージョンは各アプリストアの記載をご確認ください）
            </li>
          </ul>
        </Row>
      </dl>
    </article>
  );
}
