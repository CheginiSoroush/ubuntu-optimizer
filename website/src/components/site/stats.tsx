"use client";

import { useEffect, useRef, useState } from "react";
import { motion, useInView } from "framer-motion";
import { useLanguage } from "@/lib/language-context";
import { formatNumber } from "@/lib/i18n";
import { SectionShell } from "./section-heading";

function Counter({ target, suffix }: { target: number; suffix: string }) {
  const { lang } = useLanguage();
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref, { once: true, margin: "-60px" });
  const [value, setValue] = useState(0);

  useEffect(() => {
    if (!inView) return;
    const duration = 1200;
    const start = performance.now();
    let raf = 0;
    const tick = (now: number) => {
      const p = Math.min(1, (now - start) / duration);
      // easeOutCubic
      const eased = 1 - Math.pow(1 - p, 3);
      setValue(Math.round(target * eased));
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [inView, target]);

  return (
    <span ref={ref} className="tabular-nums" dir="ltr">
      {formatNumber(value, lang)}
      <span className="text-primary">{suffix}</span>
    </span>
  );
}

export function Stats() {
  const { t } = useLanguage();
  return (
    <SectionShell id="stats" className="py-12 sm:py-14">
      <motion.div
        initial={{ opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-60px" }}
        transition={{ duration: 0.55 }}
        className="grid grid-cols-2 gap-4 lg:grid-cols-4"
      >
        {t.stats.map((s) => (
          <div
            key={s.label}
            className="group rounded-2xl border border-border bg-card/60 p-6 text-center shadow-sm backdrop-blur transition-all duration-300 hover:-translate-y-1 hover:border-primary/40 hover:shadow-lg hover:shadow-primary/10"
          >
            <div className="text-3xl font-black tracking-tight sm:text-4xl">
              <Counter target={s.value} suffix={s.suffix} />
            </div>
            <div className="mt-2 text-sm font-medium text-muted-foreground">{s.label}</div>
          </div>
        ))}
      </motion.div>
    </SectionShell>
  );
}
