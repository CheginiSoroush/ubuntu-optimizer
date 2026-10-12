import type { Metadata, Viewport } from "next";
import { Geist, Vazirmatn, JetBrains_Mono } from "next/font/google";
import { ThemeProvider } from "next-themes";
import "./globals.css";
import { Toaster } from "@/components/ui/sonner";
import { LanguageProvider } from "@/lib/language-context";
import { withBasePath } from "@/lib/base-path";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const vazirmatn = Vazirmatn({
  variable: "--font-vazir",
  subsets: ["arabic", "latin"],
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Ubuntu Optimizer & Fixer — یک دستور، اوبونتویی بهتر",
  description:
    "The all-in-one Ubuntu toolbox: 16 tools, 35+ CLI options, honest dry-run preview. Network tuning, disk cleanup, smart app installs, full removal and recovery — pure Bash, fully reversible. جعبه‌ابزار همه‌کارهٔ بهینه‌سازی اوبونتو.",
  keywords: [
    "ubuntu",
    "optimizer",
    "bash",
    "linux",
    "tweak",
    "cleanup",
    "network",
    "bbr",
    "اوبونتو",
    "بهینه‌سازی",
  ],
  authors: [{ name: "Soroush Chegini" }],
  icons: { icon: withBasePath("/uo-logo.svg") },
  openGraph: {
    title: "Ubuntu Optimizer & Fixer",
    description:
      "One command. A faster, cleaner, healthier Ubuntu. — یک دستور؛ اوبونتویی سریع‌تر، تمیزتر و سالم‌تر.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Ubuntu Optimizer & Fixer",
    description: "One command. A faster, cleaner, healthier Ubuntu.",
  },
};

export const viewport: Viewport = {
  themeColor: "#2c001e",
  width: "device-width",
  initialScale: 1,
};

// Applies the saved language before hydration (no dir/lang flash)
const langBootstrap = `(function(){try{var l=localStorage.getItem("uo-site-lang");if(l!=="en"&&l!=="fa")l="fa";var d=document.documentElement;d.lang=l;d.dir=l==="fa"?"rtl":"ltr";}catch(e){}})();`;

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="fa" dir="rtl" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: langBootstrap }} />
      </head>
      <body
        className={`${geistSans.variable} ${vazirmatn.variable} ${jetbrainsMono.variable} antialiased bg-background text-foreground`}
      >
        <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
          <LanguageProvider>{children}</LanguageProvider>
        </ThemeProvider>
        <Toaster position="bottom-center" richColors />
      </body>
    </html>
  );
}
