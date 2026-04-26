'use client';

import React from "react";
import { Plus_Jakarta_Sans, Noto_Sans_JP } from 'next/font/google';
import './globals.css';

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
  return (
    <html lang="ja" className={`${jakarta.variable} ${noto.variable}`}>
      <body className="font-sans antialiased">
        <header className="fixed top-0 left-0 right-0 h-14 z-50 bg-white border-b border-[#E2E8F0] flex items-center justify-between px-6">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 bg-[#0F172A] rounded-md flex items-center justify-center text-[#14B8A6] font-bold text-[11px]">
              FC
            </div>
            <span className="font-bold text-[16px] text-[#0F172A] tracking-tight">FitConnect</span>
          </div>
          <div className="flex items-center gap-2">
            <button className="w-9 h-9 rounded-md border border-[#E2E8F0] bg-white flex items-center justify-center text-[#94A3B8] hover:bg-[#F8FAFC] hover:text-[#475569] transition-all">
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
            </button>
            <button className="w-9 h-9 rounded-md border border-[#E2E8F0] bg-white flex items-center justify-center text-[#94A3B8] hover:bg-[#F8FAFC] hover:text-[#475569] transition-all relative">
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/></svg>
            </button>
          </div>
        </header>

        <main className="pt-14">
          {children}
        </main>
      </body>
    </html>
  );
}
