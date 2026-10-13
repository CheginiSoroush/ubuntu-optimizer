"use client";

import { Github, Star } from "lucide-react";
import { useLanguage } from "@/lib/language-context";
import { REPO_URL, VERSION } from "@/lib/i18n";
import { withBasePath } from "@/lib/base-path";

export function Footer() {
  const { t, dir } = useLanguage();

  return (
    <footer dir={dir} className="mt-auto border-t border-border/70 bg-secondary/30">
      <div className="mx-auto w-full max-w-6xl px-4 py-10 sm:px-6">
        <div className="flex flex-col items-center gap-8 text-center md:flex-row md:items-start md:justify-between md:text-start">
          {/* Brand */}
          <div className="max-w-sm">
            <div className="flex items-center justify-center gap-2.5 md:justify-start">
              <img src={withBasePath("/uo-logo.svg")} alt="Ubuntu Optimizer logo" className="size-9 rounded-lg" />
              <span className="flex flex-col leading-tight">
                <span className="text-sm font-extrabold">Ubuntu Optimizer &amp; Fixer</span>
                <span className="text-[11px] text-muted-foreground">{t.footer.tagline}</span>
              </span>
            </div>
            <p className="mt-4 text-xs leading-relaxed text-muted-foreground">
              {t.footer.starCta}
            </p>
          </div>

          {/* Links */}
          <nav aria-label="Footer" className="grid grid-cols-2 gap-x-10 gap-y-2 text-sm">
            <a href={REPO_URL} target="_blank" rel="noopener noreferrer" className="text-muted-foreground transition-colors hover:text-primary">
              {t.footer.links.repo}
            </a>
            <a href={`${REPO_URL}/issues`} target="_blank" rel="noopener noreferrer" className="text-muted-foreground transition-colors hover:text-primary">
              {t.footer.links.issues}
            </a>
            <a href={`${REPO_URL}/blob/main/CHANGELOG.md`} target="_blank" rel="noopener noreferrer" className="text-muted-foreground transition-colors hover:text-primary">
              {t.footer.links.changelog}
            </a>
            <a href={`${REPO_URL}/blob/main/CONTRIBUTING.md`} target="_blank" rel="noopener noreferrer" className="text-muted-foreground transition-colors hover:text-primary">
              {t.footer.links.contributing}
            </a>
          </nav>

          {/* Author */}
          <div className="flex flex-col items-center gap-2 md:items-end">
            <a
              href="https://github.com/CheginiSoroush"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-2.5 rounded-full border border-border bg-card px-4 py-2 shadow-sm transition-all hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-md"
            >
              <img
                src="https://github.com/CheginiSoroush.png"
                alt="Soroush Chegini avatar"
                width={28}
                height={28}
                className="rounded-full"
              />
              <span className="flex flex-col leading-tight">
                <span className="text-xs font-bold">{t.footer.author}</span>
                <span className="text-[10px] text-muted-foreground">{t.footer.authorRole}</span>
              </span>
              <Github className="size-4 text-muted-foreground" aria-hidden />
            </a>
            <a
              href={REPO_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 text-xs font-semibold text-primary hover:underline"
            >
              <Star className="size-3.5" aria-hidden />
              {t.nav.github} · {VERSION}
            </a>
          </div>
        </div>

        <div className="mt-8 flex flex-col items-center justify-between gap-3 border-t border-border/70 pt-6 text-xs text-muted-foreground sm:flex-row">
          <span className="flex items-center gap-1.5">
            <span>{t.footer.madeWith}</span>
            <span aria-hidden>·</span>
            <span>{t.footer.license} © Soroush Chegini</span>
          </span>
          <span dir="ltr" className="font-mono text-[11px]">
            bash 4.3+ · ubuntu 20.04+ · {VERSION}
          </span>
        </div>
      </div>
    </footer>
  );
}
