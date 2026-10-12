"use client";

import { motion } from "framer-motion";
import { Info } from "lucide-react";
import { useLanguage } from "@/lib/language-context";
import { SectionHeading, SectionShell } from "./section-heading";
import { CopyableCode } from "./copyable-code";

export function Install() {
  const { t } = useLanguage();

  return (
    <SectionShell id="install">
      <SectionHeading kicker={t.install.kicker} title={t.install.title} subtitle={t.install.subtitle} />

      <div className="mx-auto mt-12 max-w-3xl space-y-6">
        {t.install.steps.map((step, i) => (
          <motion.div
            key={step.title}
            initial={{ opacity: 0, y: 24 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, margin: "-40px" }}
            transition={{ duration: 0.5, delay: i * 0.08 }}
            className="relative"
          >
            <div className="mb-3 flex items-center gap-3">
              <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary font-mono text-sm font-black text-primary-foreground shadow-md shadow-primary/30">
                {i + 1}
              </span>
              <h3 className="text-lg font-bold">{step.title}</h3>
              <span className="h-px flex-1 bg-gradient-to-r from-primary/40 to-transparent" />
            </div>
            <CopyableCode code={step.code} />
          </motion.div>
        ))}

        <motion.div
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={{ once: true }}
          transition={{ duration: 0.5, delay: 0.2 }}
          className="flex items-start gap-3 rounded-xl border border-primary/25 bg-primary/5 p-4 text-sm leading-relaxed text-muted-foreground"
        >
          <Info className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden />
          <p>{t.install.tip}</p>
        </motion.div>
      </div>
    </SectionShell>
  );
}
