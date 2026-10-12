"use client";

import { motion } from "framer-motion";
import { TerminalSquare } from "lucide-react";
import { useLanguage } from "@/lib/language-context";
import { SectionHeading, SectionShell } from "./section-heading";
import { CopyableCode } from "./copyable-code";

export function Cli() {
  const { t } = useLanguage();
  const examples = [
    "uo --optimize",
    "uo --optimize --dry-run -y",
    "uo --update -y",
    "uo --install-targz ~/Downloads/app.tar.gz myapp",
    "uo --github-install junegunn/fzf",
    "uo --cleanup abdownloadmanager --purge-data -y",
    "uo --doctor",
  ].join("\n");

  return (
    <SectionShell id="cli">
      <SectionHeading kicker={t.cli.kicker} title={t.cli.title} subtitle={t.cli.subtitle} />

      <div className="mt-12 grid items-start gap-8 lg:grid-cols-[1.35fr_1fr]">
        {/* Commands table */}
        <motion.div
          initial={{ opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-40px" }}
          transition={{ duration: 0.5 }}
          className="overflow-hidden rounded-2xl border border-border bg-card/70 shadow-sm backdrop-blur"
        >
          <div className="hidden grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)] gap-4 border-b border-border bg-secondary/50 px-5 py-3 text-xs font-bold uppercase tracking-wide text-muted-foreground sm:grid">
            <span>{t.cli.columns.cmd}</span>
            <span>{t.cli.columns.desc}</span>
          </div>
          <ul className="divide-y divide-border/70">
            {t.cli.commands.map((c, i) => (
              <motion.li
                key={c.cmd}
                initial={{ opacity: 0, x: 14 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true, margin: "-30px" }}
                transition={{ duration: 0.35, delay: i * 0.04 }}
                className="grid gap-1 px-5 py-3.5 transition-colors hover:bg-primary/5 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)] sm:items-center sm:gap-4"
              >
                <code
                  dir="ltr"
                  className="w-fit rounded-md bg-primary/10 px-2 py-1 font-mono text-[12px] font-semibold text-primary"
                >
                  {c.cmd}
                </code>
                <span className="text-[13px] leading-relaxed text-muted-foreground">{c.desc}</span>
              </motion.li>
            ))}
          </ul>
        </motion.div>

        {/* Examples block */}
        <motion.div
          initial={{ opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-40px" }}
          transition={{ duration: 0.5, delay: 0.1 }}
        >
          <div className="mb-3 flex items-center gap-2 text-sm font-bold">
            <TerminalSquare className="size-4 text-primary" aria-hidden />
            {t.cli.examplesTitle}
          </div>
          <CopyableCode code={examples} label="examples" />
        </motion.div>
      </div>
    </SectionShell>
  );
}
