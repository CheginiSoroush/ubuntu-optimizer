"use client";

import { motion } from "framer-motion";
import { Undo2 } from "lucide-react";
import { useLanguage } from "@/lib/language-context";
import { safetyIcons } from "./icons";
import { SectionHeading, SectionShell } from "./section-heading";
import { CopyableCode } from "./copyable-code";

export function Safety() {
  const { t } = useLanguage();

  return (
    <SectionShell id="safety">
      <SectionHeading kicker={t.safety.kicker} title={t.safety.title} subtitle={t.safety.subtitle} />

      <div className="mt-12 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {t.safety.items.map((item, i) => {
          const Icon = safetyIcons[item.icon] ?? safetyIcons.check;
          return (
            <motion.div
              key={item.title}
              initial={{ opacity: 0, y: 22 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-40px" }}
              transition={{ duration: 0.45, delay: (i % 3) * 0.08 }}
              className="group rounded-2xl border border-border bg-card/70 p-5 shadow-sm backdrop-blur transition-all duration-300 hover:-translate-y-1 hover:border-emerald-500/40 hover:shadow-lg hover:shadow-emerald-500/5"
            >
              <span className="flex size-10 items-center justify-center rounded-xl border border-emerald-500/25 bg-emerald-500/10 text-emerald-500 transition-transform duration-300 group-hover:scale-110">
                <Icon className="size-5" aria-hidden />
              </span>
              <h3 className="mt-3.5 text-[15px] font-bold">{item.title}</h3>
              <p className="mt-1.5 text-[13px] leading-relaxed text-muted-foreground">{item.desc}</p>
            </motion.div>
          );
        })}
      </div>

      <motion.div
        initial={{ opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-40px" }}
        transition={{ duration: 0.55 }}
        className="mt-10"
      >
        <div className="mb-3 flex items-center gap-2 text-sm font-bold text-muted-foreground">
          <Undo2 className="size-4 text-primary" aria-hidden />
          {t.safety.revertTitle}
        </div>
        <CopyableCode code={t.safety.revertCode} label="revert" />
      </motion.div>
    </SectionShell>
  );
}
