import type { Metadata } from "next";
import { AppProviders } from "@/components/providers";
import { THEME_INIT_SCRIPT } from "@/lib/theme";
import "./globals.css";

export const metadata: Metadata = {
  title: "ProSellOut",
  description: "Portal de gestão de Sell Out",
  icons: {
    icon: [{ url: "/favicon.png", type: "image/png", sizes: "64x64" }],
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="pt-BR" suppressHydrationWarning>
      <body className="font-sans antialiased">
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }} />
        <AppProviders>{children}</AppProviders>
      </body>
    </html>
  );
}
