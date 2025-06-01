// app/layout.tsx
import Image from "next/image";
import React, { ReactNode } from "react";
import { Lexend } from 'next/font/google';
import './globals.css';

const lexend = Lexend({
  subsets: ['latin'],
  weight: ['400', '700'], // 必要なウェイトを指定
  variable: '--font-lexend', // カスタムプロパティで使う
});

export const metadata = {
  title: 'Lexend App',
  description: 'Using Lexend with Tailwind',
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ja" className={lexend.variable}>
      <body>
        <header className="fixed shadow z-50 w-full" style={{ display: "flex", backgroundColor: "#FFFFFF", color: "#141414", paddingTop: "12px", paddingBottom: "12px" }}>
          <div style={{ paddingLeft: "40px" }}>
            <Image
              src="/icon.svg"
              alt="logo"
              width={16}
              height={16}
              priority
            />
          </div>
          <h1 style={{ paddingLeft: "16px" }} className="font-bold font-sans">
            FitConnect
          </h1>
        </header>

        <main className="pt-[65px]">
          {children}
        </main>

        {/* <footer style={{ textAlign: "center", padding: "1rem", borderTop: "1px solid #ccc" }}>
          © 2025 あなたのサイト名
        </footer> */}
      </body>
    </html>
  );
}
