import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Piedras Cloud",
  description: "Piedras iOS 单主仓云端 API 与 ASR 状态调试页。",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
