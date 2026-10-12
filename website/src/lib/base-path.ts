/**
 * Base path of the site, injected at build time.
 * On GitHub Pages project sites this is "/<repo-name>" (e.g. /ubuntu-optimizer);
 * in local dev or a custom domain it is an empty string.
 */
export const BASE_PATH: string = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

/** Prefix a public asset URL with the site base path. */
export function withBasePath(path: string): string {
  if (!BASE_PATH) return path;
  return `${BASE_PATH}${path.startsWith("/") ? path : `/${path}`}`;
}
