"use client";

import { motion } from "framer-motion";
import { useLanguage } from "@/lib/language-context";

type Props = {
  kicker: string;
  title: string;
  subtitle?: string;
  align?: "center" | "start";
};

export function SectionHeading({ kicker, title, subtitle, align = "center" }: Props) {
  const centered = align === "center";
  return (
    <motion.div
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={{ duration: 0.55, ease: "easeOut" }}
      className={`max-w-2xl ${centered ? "mx-auto text-center" : "text-start"}`}
    >
      <span className="inline-flex items-center gap-2 rounded-full border border-primary/30 bg-primary/10 px-4 py-1 text-xs font-semibold tracking-wide text-primary">
        <span className="size-1.5 rounded-full bg-primary" aria-hidden />
        {kicker}
      </span>
      <h2 className="mt-4 text-3xl font-extrabold tracking-tight sm:text-4xl">
        {title}
      </h2>
      {subtitle ? (
        <p className="mt-4 text-base leading-relaxed text-muted-foreground sm:text-lg">
          {subtitle}
        </p>
      ) : null}
    </motion.div>
  );
}

// Small helper so every section sits on the same rhythm
export function SectionShell({
  id,
  children,
  className = "",
}: {
  id: string;
  children: React.ReactNode;
  className?: string;
}) {
  const { dir } = useLanguage();
  return (
    <section
      id={id}
      dir={dir}
      className={`relative mx-auto w-full max-w-6xl scroll-mt-24 px-4 py-20 sm:px-6 sm:py-24 ${className}`}
    >
      {children}
    </section>
  );
}
