"use client";

import { useState } from "react";
import { Check, Copy } from "lucide-react";
import { toast } from "sonner";
import { useLanguage } from "@/lib/language-context";

export function CopyableCode({ code, label }: { code: string; label?: string }) {
  const { t } = useLanguage();
  const [copied, setCopied] = useState(false);

  const onCopy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      toast.success(t.misc.copied);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      toast.error("Copy failed");
    }
  };

  return (
    <div
      dir="ltr"
      className="group relative overflow-hidden rounded-xl border border-white/10 bg-[#16090f] shadow-inner"
    >
      {label ? (
        <div className="flex items-center border-b border-white/10 bg-white/[0.03] px-4 py-1.5">
          <span className="font-mono text-[10px] uppercase tracking-widest text-zinc-500">
            {label}
          </span>
        </div>
      ) : null}
      <button
        type="button"
        onClick={onCopy}
        aria-label={copied ? t.misc.copied : t.misc.copy}
        className="absolute end-2 top-2 z-10 flex size-8 items-center justify-center rounded-lg border border-white/10 bg-white/5 text-zinc-400 opacity-0 transition-all duration-200 hover:bg-white/10 hover:text-white focus-visible:opacity-100 group-hover:opacity-100"
      >
        {copied ? <Check className="size-4 text-emerald-400" /> : <Copy className="size-4" />}
      </button>
      <pre className="overflow-x-auto p-4 font-mono text-[12.5px] leading-relaxed text-zinc-200 sm:text-[13px]">
        <code>{code}</code>
      </pre>
    </div>
  );
}
