"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { motion } from "framer-motion";

type Tone = "cmd" | "ok" | "dim" | "info" | "warn";
type Line = { text: string; tone: Tone };

const SCENES: { cmd: string; lines: Line[] }[] = [
  {
    cmd: "uo --optimize --dry-run -y",
    lines: [
      { text: "[dry-run] preview — nothing will be changed", tone: "info" },
      { text: "✓ BBR congestion control → /etc/sysctl.d/99-ubuntu-optimizer.conf", tone: "ok" },
      { text: "✓ DNS → 8.8.8.8 / 1.1.1.1 (nmcli)", tone: "ok" },
      { text: "✓ TCP fastopen + 16 MB buffers", tone: "ok" },
      { text: "✓ swappiness=10 · noatime (remount now) · journal ≤ 200 MB", tone: "ok" },
      { text: "Done — 24 tweaks previewed · same commands run without --dry-run", tone: "dim" },
    ],
  },
  {
    cmd: "uo --github-install junegunn/fzf",
    lines: [
      { text: "→ resolving latest release for x86_64…", tone: "info" },
      { text: "→ downloading fzf 0.62.0 (linux_amd64.tar.gz)", tone: "dim" },
      { text: "→ checking missing shared libs via ldd…", tone: "dim" },
      { text: "✓ installed to /opt/fzf · desktop entry ready", tone: "ok" },
      { text: "✓ registered in apps.db — updates will find it", tone: "ok" },
    ],
  },
  {
    cmd: "uo --dns shecan",
    lines: [
      { text: "→ shecan — Iranian bypass resolver, free", tone: "info" },
      { text: "→ new resolvers: 178.22.122.100 · 185.51.200.2", tone: "dim" },
      { text: "✓ applied on the NetworkManager connection", tone: "ok" },
      { text: "✓ shecan is active and resolving", tone: "ok" },
      { text: "back to DHCP anytime: uo --dns auto", tone: "dim" },
    ],
  },
  {
    cmd: "uo --cleanup abdownloadmanager --purge-data -y",
    lines: [
      { text: "→ searching apt · snap · flatpak · tar.gz · manual paths", tone: "info" },
      { text: "✓ removed from all sources · user data purged", tone: "ok" },
      { text: "space freed: 412 MB · logged to optimizer.log", tone: "dim" },
    ],
  },
];

const TYPE_SPEED = 55;       // ms per char
const LINE_PAUSE = 320;      // pause between output lines
const SCENE_HOLD = 2600;     // hold after a scene finishes
const RESTART_HOLD = 1400;   // hold before starting over

function toneClass(tone: Tone): string {
  switch (tone) {
    case "ok":
      return "text-emerald-400";
    case "info":
      return "text-orange-400";
    case "warn":
      return "text-amber-400";
    case "dim":
      return "text-zinc-400";
    default:
      return "text-zinc-100";
  }
}

export function Terminal({ title }: { title: string }) {
  const [sceneIdx, setSceneIdx] = useState(0);
  const [typed, setTyped] = useState("");
  const [shownLines, setShownLines] = useState<Line[]>([]);
  const [phase, setPhase] = useState<"typing" | "output" | "hold">("typing");
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const bodyRef = useRef<HTMLDivElement>(null);

  const scene = SCENES[sceneIdx];
  const ariaLines = useMemo(
    () => scene.lines.map((l) => l.text).join("\n"),
    [scene]
  );

  // schedule next step whenever phase/data changes
  useEffect(() => {
    const schedule = (fn: () => void, ms: number) => {
      const id = setTimeout(fn, ms);
      timers.current.push(id);
    };
    const clearAll = () => {
      timers.current.forEach(clearTimeout);
      timers.current = [];
    };
    clearAll();

    if (phase === "typing") {
      if (typed.length < scene.cmd.length) {
        schedule(() => {
          setTyped(scene.cmd.slice(0, typed.length + 1));
        }, TYPE_SPEED);
      } else {
        schedule(() => setPhase("output"), 420);
      }
    } else if (phase === "output") {
      if (shownLines.length < scene.lines.length) {
        schedule(() => {
          setShownLines((prev) => [...prev, scene.lines[prev.length]]);
        }, LINE_PAUSE);
      } else {
        schedule(() => setPhase("hold"), 200);
      }
    } else {
      schedule(() => {
        const next = (sceneIdx + 1) % SCENES.length;
        setSceneIdx(next);
        setTyped("");
        setShownLines([]);
        setPhase("typing");
      }, sceneIdx === SCENES.length - 1 ? RESTART_HOLD : SCENE_HOLD);
    }

    return clearAll;
  }, [phase, typed, shownLines, scene, sceneIdx]);

  // keep the terminal scrolled to bottom
  useEffect(() => {
    const el = bodyRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [typed, shownLines]);

  return (
    <div
      dir="ltr"
      className="relative w-full overflow-hidden rounded-2xl border border-white/10 bg-[#16090f]/95 shadow-2xl shadow-primary/10 ring-1 ring-black/40 backdrop-blur"
      role="img"
      aria-label={`Terminal demo: ${scene.cmd} — ${ariaLines}`}
    >
      {/* window chrome */}
      <div className="flex items-center gap-2 border-b border-white/10 bg-white/[0.04] px-4 py-3">
        <span className="size-3 rounded-full bg-[#ff5f57]" />
        <span className="size-3 rounded-full bg-[#febc2e]" />
        <span className="size-3 rounded-full bg-[#28c840]" />
        <span className="ms-3 select-none font-mono text-xs text-zinc-400">{title}</span>
        <span className="ms-auto rounded-md border border-white/10 bg-white/5 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-zinc-400">
          {phase === "typing" ? "typing…" : "live demo"}
        </span>
      </div>

      {/* body */}
      <div
        ref={bodyRef}
        className="h-[320px] overflow-hidden px-4 py-4 font-mono text-[12.5px] leading-relaxed sm:h-[340px] sm:px-5 sm:text-[13.5px]"
      >
        {/* prompt line */}
        <div className="flex flex-wrap items-center whitespace-pre-wrap break-all">
          <span className="text-orange-400">soroush@ubuntu</span>
          <span className="text-zinc-500">:</span>
          <span className="text-sky-400">~</span>
          <span className="text-zinc-500">$&nbsp;</span>
          <span className="text-zinc-50">{typed}</span>
          {phase === "typing" && (
            <span className="terminal-cursor -mb-0.5 inline-block h-[1.1em] w-[7px] translate-y-[3px] bg-orange-400" />
          )}
        </div>

        {/* output */}
        {shownLines.map((line, i) => (
          <motion.div
            key={`${sceneIdx}-${i}-${line.text.slice(0, 12)}`}
            initial={{ opacity: 0, x: -6 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.25 }}
            className={`whitespace-pre-wrap break-all ${toneClass(line.tone)}`}
          >
            {line.text}
          </motion.div>
        ))}

        {phase !== "typing" && (
          <span className="terminal-cursor -mb-0.5 inline-block h-[1.05em] w-[7px] translate-y-[2px] bg-orange-400/90" />
        )}
      </div>

      {/* subtle top glow */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-16 left-1/2 h-32 w-2/3 -translate-x-1/2 rounded-full bg-primary/20 blur-3xl"
      />
    </div>
  );
}
