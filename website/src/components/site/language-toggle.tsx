"use client";

import { motion } from "framer-motion";
import { useLanguage } from "@/lib/language-context";
import type { Lang } from "@/lib/i18n";

export function LanguageToggle() {
  const { lang, setLang } = useLanguage();
  const options: { key: Lang; label: string }[] = [
    { key: "fa", label: "فا" },
    { key: "en", label: "EN" },
  ];

  return (
    <div
      role="radiogroup"
      aria-label="Language / زبان"
      className="relative flex items-center rounded-full border border-border bg-secondary/70 p-1 text-xs font-bold"
    >
      {options.map((opt) => {
        const active = lang === opt.key;
        return (
          <button
            key={opt.key}
            role="radio"
            aria-checked={active}
            onClick={() => setLang(opt.key)}
            className={`relative z-10 rounded-full px-3 py-1.5 transition-colors duration-200 ${
              active
                ? "text-primary-foreground"
                : "text-muted-foreground hover:text-foreground"
            }`}
          >
            {active && (
              <motion.span
                layoutId="lang-pill"
                transition={{ type: "spring", stiffness: 400, damping: 30 }}
                className="absolute inset-0 -z-10 rounded-full bg-primary shadow-sm"
              />
            )}
            {opt.label}
          </button>
        );
      })}
    </div>
  );
}
