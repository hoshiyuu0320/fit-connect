/**
 * サイト全体のメタ情報を一元管理する設定。
 * 本番ドメイン確定後は NEXT_PUBLIC_APP_URL を設定するだけで
 * metadataBase / robots / sitemap / OGP の URL が切り替わる。
 */
export const siteConfig = {
  name: 'FIT-CONNECT',
  url: process.env.NEXT_PUBLIC_APP_URL ?? 'https://fit-connect.vercel.app',
  title: 'FIT-CONNECT | パーソナルトレーナーのための顧客管理ツール',
  description:
    'FIT-CONNECTは、個人で活動するパーソナルトレーナーのための一体型顧客管理ツール。顧客とのメッセージ、食事・体重記録、AI食事解析、ワークアウト計画、回数券管理までこれひとつで完結します。',
} as const;
