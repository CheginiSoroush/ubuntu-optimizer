# 🌐 Ubuntu Optimizer — Website

The official bilingual (فارسی / English) landing page for
**Ubuntu Optimizer & Fixer** — RTL/LTR aware, light & dark themes,
animated terminal demo, built with Next.js 16 + Tailwind CSS 4.

> این پوشه سورس وب‌سایت دوزبانهٔ پروژه است و به‌صورت **خودکار روی GitHub Pages**
> مستقر می‌شود. برای مخزن اصلی (اسکریپت‌های Bash) به
> [`README.md`](../README.md) و [`README.fa.md`](../README.fa.md) مراجعه کنید.

**🔗 Live: https://cheginisoroush.github.io/ubuntu-optimizer/**

## ✨ Features

- **Bilingual** — Persian (RTL, default) & English with a one-click toggle, persisted in localStorage
- **Ambitious design** — Ubuntu aubergine + orange palette, aurora orbs, glassmorphism navbar
- **Animated terminal** — types real `uo` commands with honest output, looping
- **All sections** — stats, 16 tools grid, quick-start, CLI reference, safety & revert guide, FAQ
- **Light & dark mode** — follows the system, manually overridable
- **Fully static** — no database, no API keys, no server; deploys anywhere
- **Responsive** — mobile-first, sticky footer, accessible (semantic HTML + ARIA)

## 🚀 Run locally

```bash
cd website
bun install          # or: npm install
bun run dev          # or: npm run dev
# → http://localhost:3000
```

## 📦 GitHub Pages (automatic)

Deployment is fully automated via [`../.github/workflows/website.yml`](../.github/workflows/website.yml):

1. Push the repository to GitHub (`main` branch).
2. Go to **Settings → Pages → Build and deployment → Source** and select **GitHub Actions**.
3. Done. Every push that touches `website/**` rebuilds and republishes the site at
   `https://<owner>.github.io/<repo>/`.

The workflow builds the site with `output: 'export'` (static HTML) and sets
`NEXT_PUBLIC_BASE_PATH=/<repo-name>` automatically, so all assets resolve
correctly under the project-page sub-path.

### Build the static export manually

```bash
cd website

# for a GitHub project page (site lives under /<repo>/):
NEXT_EXPORT=static NEXT_PUBLIC_BASE_PATH=/ubuntu-optimizer bun run build

# for a root domain / user site / custom domain:
NEXT_EXPORT=static bun run build

bun run preview     # serves ./out — check it before publishing
```

## 📁 Structure

```
website/
├── src/
│   ├── app/                  # layout + single-page site
│   ├── components/site/      # navbar, hero, terminal, sections, footer…
│   ├── components/ui/        # shadcn/ui primitives
│   ├── lib/i18n.ts           # fa/en dictionary (edit copy here)
│   ├── lib/base-path.ts      # GitHub Pages base-path helper
│   └── lib/language-context.tsx
├── public/uo-logo.svg
└── …configs (Tailwind 4, TypeScript, ESLint)
```

---

MIT © [Soroush Chegini](https://github.com/CheginiSoroush)
