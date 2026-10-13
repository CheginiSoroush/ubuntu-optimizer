"use client";

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { useLanguage } from "@/lib/language-context";
import { SectionHeading, SectionShell } from "./section-heading";

export function Faq() {
  const { t } = useLanguage();

  return (
    <SectionShell id="faq">
      <SectionHeading kicker={t.faq.kicker} title={t.faq.title} />

      <div className="mx-auto mt-10 max-w-3xl">
        <Accordion type="single" collapsible className="w-full">
          {t.faq.items.map((item, i) => (
            <AccordionItem key={item.q} value={`q-${i}`} className="border-border/80">
              <AccordionTrigger className="py-4 text-start text-[15px] font-bold hover:text-primary hover:no-underline">
                {item.q}
              </AccordionTrigger>
              <AccordionContent className="pb-4 text-sm leading-relaxed text-muted-foreground">
                {item.a}
              </AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </div>
    </SectionShell>
  );
}
