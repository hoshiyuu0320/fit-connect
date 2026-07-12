/**
 * プライバシーポリシーページ
 *
 * 【注意】本文書はドラフトであり、公開前に弁護士等の専門家レビューを推奨します。
 * 【注意】公開前に本文中の「【要記入: ◯◯】」箇所を全て埋めること。
 *   - 【要記入: 事業者氏名（屋号がある場合は屋号および氏名）】
 *   - 【要記入: 住所】
 *   - 【要記入: 問い合わせメールアドレス】
 *   - 【要記入: 開示等請求の窓口（メールアドレス等）】
 */
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'プライバシーポリシー | FIT-CONNECT',
  description: 'FIT-CONNECTのプライバシーポリシーです。',
};

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mt-10">
      <h2 className="text-lg font-bold text-[#0F172A]">{title}</h2>
      <div className="mt-3 space-y-3 text-sm leading-7 text-[#334155]">
        {children}
      </div>
    </section>
  );
}

export default function PrivacyPage() {
  return (
    <article className="bg-white border border-[#E2E8F0] rounded-md px-6 py-10 sm:px-10 sm:py-12">
      <h1 className="text-2xl font-bold text-[#0F172A]">
        プライバシーポリシー
      </h1>
      <p className="mt-2 text-xs text-[#94A3B8]">
        制定日: 2026年7月11日 ／ 最終更新日: 2026年7月12日
      </p>

      <p className="mt-8 text-sm leading-7 text-[#334155]">
        【要記入:
        事業者氏名（屋号がある場合は屋号および氏名）】（以下「当方」といいます）は、当方が提供するサービス「FIT-CONNECT」（以下「本サービス」といいます）における利用者の情報の取扱いについて、以下のとおりプライバシーポリシー（以下「本ポリシー」といいます）を定めます。
      </p>
      <p className="mt-3 text-sm leading-7 text-[#334155]">
        なお、顧客（トレーナーの指導を受ける方）の健康関連情報については、個人情報の保護に関する法律における個人情報取扱事業者は各トレーナーであり、当方はトレーナーから取扱いの委託を受ける立場として、本ポリシーに従いこれを取り扱います。
      </p>

      <Section title="1. 事業者情報">
        <ul className="list-disc pl-5 space-y-2">
          <li>
            事業者名: 【要記入: 事業者氏名（屋号がある場合は屋号および氏名）】
          </li>
          <li>所在地: 【要記入: 住所】</li>
          <li>連絡先: 【要記入: 問い合わせメールアドレス】</li>
        </ul>
      </Section>

      <Section title="2. 取得する情報">
        <p>当方は、本サービスの提供にあたり、以下の情報を取得します。</p>
        <div className="space-y-3">
          <div>
            <h3 className="text-sm font-semibold text-[#0F172A]">
              トレーナーに関する情報
            </h3>
            <ul className="mt-1 list-disc pl-5 space-y-1">
              <li>氏名、メールアドレス、プロフィール画像</li>
              <li>
                決済に関する情報（クレジットカード情報は決済代行サービスであるStripe社が取り扱い、当方はカード番号を保持しません）
              </li>
            </ul>
          </div>
          <div>
            <h3 className="text-sm font-semibold text-[#0F172A]">
              顧客に関する情報（健康関連情報を含みます）
            </h3>
            <ul className="mt-1 list-disc pl-5 space-y-1">
              <li>氏名、年齢、性別等の基本情報</li>
              <li>身体情報（身長、体重、体組成等）</li>
              <li>食事、運動、睡眠の記録および写真・画像</li>
              <li>トレーナーとのメッセージの内容</li>
            </ul>
          </div>
          <div>
            <h3 className="text-sm font-semibold text-[#0F172A]">
              自動的に取得する情報
            </h3>
            <ul className="mt-1 list-disc pl-5 space-y-1">
              <li>端末情報、ログ情報、Cookieおよびこれに類する技術による情報</li>
            </ul>
          </div>
        </div>
      </Section>

      <Section title="3. 利用目的">
        <p>取得した情報は、以下の目的で利用します。</p>
        <ol className="list-decimal pl-5 space-y-2">
          <li>本サービスの提供・維持・改善のため</li>
          <li>本人確認および認証のため</li>
          <li>利用料金の請求・決済のため</li>
          <li>AIによる食事解析等の機能提供のため</li>
          <li>お問い合わせへの対応のため</li>
          <li>利用状況の分析および新機能の開発のため</li>
          <li>不正利用の防止のため</li>
          <li>重要なお知らせ・通知の送付のため</li>
        </ol>
      </Section>

      <Section title="4. 外部サービスへの提供・処理委託">
        <p>
          本サービスは、以下の外部サービスを利用しており、本サービスの提供に必要な範囲で、利用者の情報がこれらの外部サービスにおいて処理されます。外国にある事業者への委託を含みます。
        </p>
        <ol className="list-decimal pl-5 space-y-3">
          <li>
            <span className="font-semibold text-[#0F172A]">
              Anthropic Claude API（Anthropic PBC ／ 米国）
            </span>
            <br />
            AIによる食事解析機能の提供のため、利用者が入力した食事の写真・テキスト等がAPIに送信され、処理されます。APIに入力されたデータは、モデルの学習には使用されません。
          </li>
          <li>
            <span className="font-semibold text-[#0F172A]">Supabase</span>
            <br />
            データベース、認証、ストレージ等のデータホスティングのために利用します。
          </li>
          <li>
            <span className="font-semibold text-[#0F172A]">
              Stripe（導入予定）
            </span>
            <br />
            クレジットカード決済の処理のために利用します。
          </li>
          <li>
            <span className="font-semibold text-[#0F172A]">
              Firebase Cloud Messaging（Google LLC）
            </span>
            <br />
            モバイルアプリへのプッシュ通知の配信のために利用します。
          </li>
        </ol>
      </Section>

      <Section title="5. 第三者提供">
        <p>
          当方は、次に掲げる場合を除き、あらかじめ本人の同意を得ることなく、個人情報を第三者に提供しません。
        </p>
        <ol className="list-decimal pl-5 space-y-2">
          <li>法令に基づく場合</li>
          <li>
            人の生命、身体または財産の保護のために必要がある場合であって、本人の同意を得ることが困難であるとき
          </li>
          <li>
            公衆衛生の向上または児童の健全な育成の推進のために特に必要がある場合であって、本人の同意を得ることが困難であるとき
          </li>
          <li>
            国の機関もしくは地方公共団体またはその委託を受けた者が法令の定める事務を遂行することに対して協力する必要がある場合であって、本人の同意を得ることにより当該事務の遂行に支障を及ぼすおそれがあるとき
          </li>
        </ol>
      </Section>

      <Section title="6. 安全管理措置">
        <p>
          当方は、取り扱う個人情報の漏えい、滅失または毀損の防止その他の安全管理のために、通信の暗号化（TLS）、データベースへのアクセス制御（Row
          Level Security等）、アクセス権限の最小化その他の必要かつ適切な措置を講じます。
        </p>
      </Section>

      <Section title="7. 保存期間とアカウント削除">
        <ol className="list-decimal pl-5 space-y-2">
          <li>
            当方は、利用目的の達成に必要な期間に限り、個人情報を保存します。
          </li>
          <li>
            利用者は、アプリ内のアカウント削除機能により、いつでもアカウントを削除できます。アカウントを削除した場合、記録データ（体重・食事・運動・睡眠等の記録）、写真・画像およびアカウント情報は削除されます。
          </li>
          <li>
            法令により保存が義務付けられている情報については、当該法令に定める期間保存した後、削除します。
          </li>
        </ol>
      </Section>

      <Section title="8. 開示・訂正・利用停止等の請求">
        <p>
          利用者は、当方が保有する自己の個人情報について、開示、訂正、追加、削除、利用停止等を請求することができます。請求を希望される場合は、以下の窓口までご連絡ください。ご本人であることを確認のうえ、法令に従い対応します。
        </p>
        <ul className="list-disc pl-5 space-y-2">
          <li>請求窓口: 【要記入: 開示等請求の窓口（メールアドレス等）】</li>
        </ul>
        <p>
          なお、顧客の健康関連情報については、個人情報取扱事業者である各トレーナーに対してもご請求いただけます。
        </p>
      </Section>

      <Section title="9. Cookie等の利用">
        <p>
          本サービスは、ログイン状態の維持等のため、Cookieおよびこれに類する技術を使用しています。ブラウザの設定によりCookieを無効化することができますが、その場合、本サービスの一部の機能が利用できなくなることがあります。
        </p>
        <p>
          また、本サービスは、アクセス解析ツールとして Google Analytics 4（Google
          LLC）を利用しています。Google Analytics
          4は、Cookieおよびこれに類する技術を利用して、利用者に関する以下の情報を収集し、Google
          LLCに送信します。
        </p>
        <ul className="list-disc pl-5 space-y-2">
          <li>Cookie等により生成される識別子</li>
          <li>閲覧したページのURL・閲覧日時</li>
          <li>利用環境・端末に関する情報（ブラウザの種類、OS、画面サイズ、おおよその地域等）</li>
        </ul>
        <p>
          これらの情報は、本サービスの利用状況の分析およびサービス改善の目的で利用します。送信された情報は、Googleのプライバシーポリシーおよび「Googleのサービスを使用するサイトやアプリから収集した情報のGoogleによる使用」（
          https://policies.google.com/technologies/partner-sites
          ）に基づき、Google LLCにおいても取り扱われます。利用者は、Google
          アナリティクス オプトアウト
          アドオンの利用またはブラウザの設定によるCookieの無効化により、Google
          Analytics 4による情報の収集を無効化することができます。
        </p>
      </Section>

      <Section title="10. 本ポリシーの改定">
        <p>
          当方は、法令の変更またはサービス内容の変更等に応じて、本ポリシーを改定することがあります。重要な変更を行う場合には、本サービス上への掲示その他適切な方法により周知します。
        </p>
      </Section>

      <p className="mt-12 text-sm text-[#64748B]">以上</p>
    </article>
  );
}
