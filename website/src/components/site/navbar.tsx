"use client";

import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { Github, Star, Menu, X } from "lucide-react";
import { useLanguage } from "@/lib/language-context";
import { REPO_URL } from "@/lib/i18n";
import { withBasePath } from "@/lib/base-path";
import { LanguageToggle } from "./language-toggle";
import { ThemeToggle } from "./theme-toggle";
import { Button } from "@/components/ui/button";

export function Navbar() {
  const { t, dir } = useLanguage();
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const links = [
    { href: "#tools", label: t.nav.tools },
    { href: "#install", label: t.nav.install },
    { href: "#cli", label: t.nav.cli },
    { href: "#safety", label: t.nav.safety },
    { href: "#faq", label: t.nav.faq },
  ];

  return (
    <motion.header
      initial={{ y: -70, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.5, ease: "easeOut" }}
      className={`fixed inset-x-0 top-0 z-50 transition-all duration-300 ${
        scrolled
          ? "glass border-b border-border/60 shadow-sm"
          : "border-b border-transparent bg-transparent"
      }`}
    >
      <nav
        aria-label="Main"
        dir={dir}
        className="mx-auto flex h-16 w-full max-w-6xl items-center justify-between gap-3 px-4 sm:px-6"
      >
        {/* Brand */}
        <a href="#top" className="group flex items-center gap-2.5" aria-label="Ubuntu Optimizer home">
          <span className="relative flex size-9 items-center justify-center overflow-hidden rounded-xl border border-primary/30 bg-primary/10 shadow-inner">
            <img src={withBasePath("/uo-logo.svg")} alt="" className="size-7 transition-transform duration-300 group-hover:scale-110" />
          </span>
          <span className="hidden flex-col leading-tight sm:flex">
            <span className="text-sm font-extrabold tracking-tight">Ubuntu Optimizer</span>
            <span className="text-[10px] font-medium text-muted-foreground">&amp; Fixer · v7.1</span>
          </span>
        </a>

        {/* Desktop links */}
        <div className="hidden items-center gap-1 lg:flex">
          {links.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="rounded-full px-3.5 py-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
            >
              {l.label}
            </a>
          ))}
        </div>

        {/* Actions */}
        <div className="flex items-center gap-2">
          <ThemeToggle />
          <LanguageToggle />
          <Button asChild size="sm" className="hidden rounded-full shadow-md shadow-primary/25 sm:inline-flex">
            <a href={REPO_URL} target="_blank" rel="noopener noreferrer" className="gap-1.5">
              <Github className="size-4" aria-hidden />
              <Star className="size-3.5" aria-hidden />
              {t.nav.github}
            </a>
          </Button>
          {/* Mobile hamburger */}
          <Button
            variant="ghost"
            size="icon"
            className="lg:hidden"
            aria-expanded={open}
            aria-label={open ? "Close menu" : "Open menu"}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <X className="size-5" /> : <Menu className="size-5" />}
          </Button>
        </div>
      </nav>

      {/* Mobile menu */}
      {open && (
        <motion.div
          initial={{ opacity: 0, height: 0 }}
          animate={{ opacity: 1, height: "auto" }}
          className="border-b border-border/60 bg-background/95 shadow-sm backdrop-blur lg:hidden"
        >
          <div dir={dir} className="mx-auto flex max-w-6xl flex-col gap-1 px-4 py-3">
            {links.map((l) => (
              <a
                key={l.href}
                href={l.href}
                onClick={() => setOpen(false)}
                className="rounded-lg px-3 py-2.5 text-sm font-medium text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
              >
                {l.label}
              </a>
            ))}
          </div>
        </motion.div>
      )}
    </motion.header>
  );
}
