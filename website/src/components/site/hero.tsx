"use client";

import { motion } from "framer-motion";
import { ArrowDown, Github, Star, TerminalSquare, ChevronLeft, ChevronRight } from "lucide-react";
import { useLanguage } from "@/lib/language-context";
import { REPO_URL } from "@/lib/i18n";
import { Button } from "@/components/ui/button";
import { Terminal } from "./terminal";

const fadeUp = {
  hidden: { opacity: 0, y: 26 },
  show: (i: number) => ({
    opacity: 1,
    y: 0,
    transition: { delay: 0.08 * i, duration: 0.6, ease: "easeOut" as const },
  }),
};

export function Hero() {
  const { t, dir } = useLanguage();
  const Arrow = dir === "rtl" ? ChevronLeft : ChevronRight;

  return (
    <div id="top" className="relative overflow-hidden pt-28 sm:pt-32" dir={dir}>
      {/* backdrop: grid + orbs */}
      <div aria-hidden className="absolute inset-0 -z-10 bg-grid [mask-image:radial-gradient(ellipse_70%_60%_at_50%_35%,black,transparent)]" />
      <div aria-hidden className="orb animate-float-slow -top-24 start-[-8%] size-[420px] bg-primary/35" />
      <div aria-hidden className="orb animate-float-slower top-24 end-[-10%] size-[380px] bg-aubergine/60" />
      <div aria-hidden className="orb top-[520px] start-[35%] size-[300px] bg-primary/20" />

      <div className="mx-auto grid w-full max-w-6xl items-center gap-12 px-4 pb-16 sm:px-6 lg:grid-cols-2 lg:gap-8 lg:pb-24">
        {/* Copy */}
        <div className="text-center lg:text-start">
          <motion.div variants={fadeUp} initial="hidden" animate="show" custom={0}>
            <span className="inline-flex items-center gap-2 rounded-full border border-primary/40 bg-primary/10 px-4 py-1.5 text-xs font-bold text-primary shadow-sm">
              <Star className="size-3.5 fill-primary" aria-hidden />
              {t.hero.badge}
            </span>
          </motion.div>

          <motion.h1
            variants={fadeUp}
            initial="hidden"
            animate="show"
            custom={1}
            className="mt-6 text-4xl font-black leading-[1.15] tracking-tight sm:text-5xl lg:text-[3.4rem]"
          >
            {t.hero.titleA}
            <br />
            <span className="text-gradient">{t.hero.titleB}</span>
          </motion.h1>

          <motion.p
            variants={fadeUp}
            initial="hidden"
            animate="show"
            custom={2}
            className="mx-auto mt-6 max-w-xl text-base leading-relaxed text-muted-foreground sm:text-lg lg:mx-0"
          >
            {t.hero.subtitle}
          </motion.p>

          <motion.div
            variants={fadeUp}
            initial="hidden"
            animate="show"
            custom={3}
            className="mt-8 flex flex-wrap items-center justify-center gap-3 lg:justify-start"
          >
            <Button asChild size="lg" className="group rounded-full px-6 shadow-lg shadow-primary/30">
              <a href={REPO_URL} target="_blank" rel="noopener noreferrer">
                <Github className="size-5" aria-hidden />
                {t.hero.ctaGithub}
                <Star className="size-4 transition-transform duration-300 group-hover:scale-125 group-hover:fill-current" aria-hidden />
              </a>
            </Button>
            <Button asChild size="lg" variant="outline" className="rounded-full px-6">
              <a href="#install">
                <TerminalSquare className="size-5" aria-hidden />
                {t.hero.ctaInstall}
                <Arrow className="size-4" aria-hidden />
              </a>
            </Button>
          </motion.div>

          <motion.a
            variants={fadeUp}
            initial="hidden"
            animate="show"
            custom={4}
            href="#stats"
            className="mt-10 inline-flex items-center gap-2 text-xs font-medium text-muted-foreground transition-colors hover:text-foreground"
          >
            <ArrowDown className="size-3.5 animate-bounce" aria-hidden />
            {t.hero.scroll}
          </motion.a>
        </div>

        {/* Terminal */}
        <motion.div
          initial={{ opacity: 0, y: 40, scale: 0.97 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          transition={{ delay: 0.35, duration: 0.7, ease: "easeOut" }}
          className="relative"
        >
          <Terminal title={t.hero.termTitle} />
        </motion.div>
      </div>
    </div>
  );
}
