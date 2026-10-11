import React from "react";
import type { Metadata } from 'next';
import { Plus_Jakarta_Sans, Noto_Sans_JP } from 'next/font/google';
import { GoogleAnalytics } from '@next/third-parties/google';
import { siteConfig } from '@/lib/siteConfig';
import './globals.css';

export const metadata: Metadata = {
  metadataBase: new URL(siteConfig.url),
  title: {
    default: 'FIT-CONNECT | パーソナルトレーナーのための顧客管理ツール',
    template: '%s | FIT-CONNECT',
  },
  description: siteConfig.description,
  openGraph: {
    siteName: 'FIT-CONNECT',
    type: 'website',
    locale: 'ja_JP',
    url: '/',
    title: 'FIT-CONNECT | パーソナルトレーナーのための顧客管理ツール',
    description: siteConfig.description,
  },
  twitter: {
    card: 'summary_large_image',
  },
};

const jakarta = Plus_Jakarta_Sans({
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
  variable: '--font-jakarta',
});

const noto = Noto_Sans_JP({
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
  variable: '--font-noto',
});

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  const gaMeasurementId = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;

  return (
    <html lang="ja" className={`${jakarta.variable} ${noto.variable}`}>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
      </head>
      <body className="font-sans antialiased">
        {children}
        {gaMeasurementId && <GoogleAnalytics gaId={gaMeasurementId} />}
      </body>
    </html>
  );
}
