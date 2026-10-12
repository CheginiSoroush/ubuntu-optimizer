"use client";

import { motion } from "framer-motion";
import { useLanguage } from "@/lib/language-context";
import { toolIcons } from "./icons";
import { SectionHeading, SectionShell } from "./section-heading";

export function Tools() {
  const { t } = useLanguage();

  return (
    <SectionShell id="tools">
      <SectionHeading kicker={t.tools.kicker} title={t.tools.title} subtitle={t.tools.subtitle} />

      <div className="mt-12 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {t.tools.items.map((item, i) => {
          const Icon = toolIcons[item.icon] ?? toolIcons.globe;
          const danger = "danger" in item && item.danger;
          return (
            <motion.article
              key={item.title}
              initial={{ opacity: 0, y: 26 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-40px" }}
              transition={{ duration: 0.45, delay: (i % 4) * 0.07, ease: "easeOut" }}
              className={`group relative flex flex-col overflow-hidden rounded-2xl border bg-card/70 p-5 shadow-sm backdrop-blur transition-all duration-300 hover:-translate-y-1.5 hover:shadow-xl ${
                danger
                  ? "border-destructive/25 hover:border-destructive/50 hover:shadow-destructive/10"
                  : "border-border hover:border-primary/40 hover:shadow-primary/10"
              }`}
            >
              {/* hover glow */}
              <span
                aria-hidden
                className={`pointer-events-none absolute -top-10 end-[-20%] size-28 rounded-full opacity-0 blur-2xl transition-opacity duration-500 group-hover:opacity-30 ${
                  danger ? "bg-destructive" : "bg-primary"
                }`}
              />

              <div className="flex items-center justify-between">
                <span
                  className={`flex size-11 items-center justify-center rounded-xl border transition-transform duration-300 group-hover:scale-110 group-hover:-rotate-3 ${
                    danger
                      ? "border-destructive/30 bg-destructive/10 text-destructive"
                      : "border-primary/25 bg-primary/10 text-primary"
                  }`}
                >
                  <Icon className="size-5" aria-hidden />
                </span>
                <span
                  className={`rounded-full px-2.5 py-0.5 text-[10px] font-bold tracking-wide ${
                    danger
                      ? "bg-destructive/10 text-destructive"
                      : "bg-secondary text-secondary-foreground"
                  }`}
                >
                  {item.tag}
                </span>
              </div>

              <h3 className="mt-4 text-[15px] font-bold leading-snug">{item.title}</h3>
              <p className="mt-2 text-[13px] leading-relaxed text-muted-foreground">
                {item.desc}
              </p>
            </motion.article>
          );
        })}
      </div>
    </SectionShell>
  );
}
