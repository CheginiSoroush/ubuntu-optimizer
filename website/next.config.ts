import type { NextConfig } from "next";

/**
 * Two build modes:
 *
 * 1) Normal dev/standalone mode (default) — used by `next dev` locally.
 *
 * 2) GitHub Pages static export mode — used by CI (.github/workflows/website.yml):
 *      NEXT_EXPORT=static NEXT_PUBLIC_BASE_PATH=/<repo-name> next build
 *    → produces a fully static `out/` folder deployable to GitHub Pages.
 *    NEXT_PUBLIC_BASE_PATH must match the repository name, because project
 *    pages are served from https://<user>.github.io/<repo-name>/ .
 */
const isStaticExport = process.env.NEXT_EXPORT === "static";
const basePath = isStaticExport ? process.env.NEXT_PUBLIC_BASE_PATH ?? "" : "";

const nextConfig: NextConfig = {
  ...(isStaticExport
    ? { output: "export" as const, basePath, trailingSlash: true }
    : { output: "standalone" as const }),
  images: { unoptimized: true },
  typescript: {
    ignoreBuildErrors: true,
  },
  reactStrictMode: false,
};

export default nextConfig;
