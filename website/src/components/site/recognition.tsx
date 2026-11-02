"use client";

import { motion } from "framer-motion";
import { Award, ArrowUpRight } from "lucide-react";
import { useLanguage } from "@/lib/language-context";
import { SectionShell } from "./section-heading";

export const XERJ_HUB_URL = "https://hub.xerj.org/contributors/CheginiSoroush";

export function Recognition() {
  const { t } = useLanguage();
  return (
    <SectionShell id="recognition" className="py-12 sm:py-14">
      <motion.a
        href={XERJ_HUB_URL}
        target="_blank"
        rel="noopener noreferrer"
        initial={{ opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-60px" }}
        transition={{ duration: 0.55, ease: "easeOut" }}
        className="group mx-auto block max-w-3xl rounded-2xl border border-primary/25 bg-gradient-to-br from-primary/10 via-card/80 to-card/60 p-6 shadow-sm backdrop-blur transition-all duration-300 hover:-translate-y-1 hover:border-primary/45 hover:shadow-lg hover:shadow-primary/10 sm:p-8"
        aria-label={t.recognition.ariaLabel}
      >
        <div className="flex flex-col items-center gap-5 text-center sm:flex-row sm:gap-6 sm:text-start">
          <span className="flex size-14 shrink-0 items-center justify-center rounded-2xl border border-primary/30 bg-primary/15 text-primary transition-transform duration-300 group-hover:scale-110">
            <Award className="size-7" aria-hidden />
          </span>
          <div className="min-w-0 flex-1">
            <div className="flex items-center justify-center gap-2 text-xs font-semibold tracking-wide text-primary sm:justify-start">
              <span className="size-1.5 rounded-full bg-primary" aria-hidden />
              {t.recognition.kicker}
            </div>
            <h2 className="mt-1.5 text-xl font-extrabold tracking-tight sm:text-2xl">
              {t.recognition.title}
            </h2>
            <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
              {t.recognition.subtitle}
            </p>
          </div>
          <div className="flex shrink-0 flex-col items-center gap-3">
            <img
              src="https://hub.xerj.org/contributors/CheginiSoroush/badge.svg"
              alt={t.recognition.badgeAlt}
              className="h-8 w-auto"
              loading="lazy"
            />
            <span className="inline-flex items-center gap-1 text-xs font-bold text-primary">
              {t.recognition.cta}
              <ArrowUpRight
                className="size-3.5 transition-transform duration-300 group-hover:-translate-y-0.5 group-hover:translate-x-0.5"
                aria-hidden
              />
            </span>
          </div>
        </div>
      </motion.a>
    </SectionShell>
  );
}
