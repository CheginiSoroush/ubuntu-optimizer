"use client";

import { motion } from "framer-motion";
import { useLanguage } from "@/lib/language-context";
import { Navbar } from "@/components/site/navbar";
import { Hero } from "@/components/site/hero";
import { Stats } from "@/components/site/stats";
import { Tools } from "@/components/site/tools";
import { Install } from "@/components/site/install";
import { Cli } from "@/components/site/cli";
import { Safety } from "@/components/site/safety";
import { Faq } from "@/components/site/faq";
import { Footer } from "@/components/site/footer";
import { SectionHeading, SectionShell } from "@/components/site/section-heading";
import { Terminal } from "@/components/site/terminal";

function TerminalShowcase() {
  const { t } = useLanguage();
  return (
    <SectionShell id="demo" className="max-w-5xl">
      <SectionHeading kicker={t.terminal.kicker} title={t.terminal.title} subtitle={t.terminal.subtitle} />
      <motion.div
        initial={{ opacity: 0, y: 30 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-60px" }}
        transition={{ duration: 0.6 }}
        className="mt-10"
      >
        <Terminal title={t.hero.termTitle} />
      </motion.div>
    </SectionShell>
  );
}

export default function Home() {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex-1">
        <Hero />
        <Stats />
        <Tools />
        <TerminalShowcase />
        <Install />
        <Cli />
        <Safety />
        <Faq />
      </main>
      <Footer />
    </div>
  );
}
