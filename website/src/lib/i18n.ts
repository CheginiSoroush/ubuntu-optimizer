export type Lang = "fa" | "en";

export const REPO_URL = "https://github.com/CheginiSoroush/ubuntu-optimizer";
export const VERSION = "v7.15";

const en = {
  dir: "ltr" as const,
  langName: "English",
  otherLang: "فارسی",
  nav: {
    tools: "Tools",
    install: "Install",
    cli: "CLI",
    safety: "Safety",
    update: "Updates",
    faq: "FAQ",
    github: "GitHub",
  },
  hero: {
    badge: `${VERSION} — 21 tools · 317/317 tests · MIT`,
    titleA: "One command.",
    titleB: "A faster, cleaner, healthier Ubuntu.",
    subtitle:
      "The all-in-one toolbox for optimizing, app management and repairing Ubuntu — 21 tools in a simple menu, 49+ CLI options, and an honest dry-run preview. Pure Bash, fully reversible.",
    ctaGithub: "Star on GitHub",
    ctaInstall: "Get started",
    scroll: "Scroll to explore",
    termTitle: "soroush@ubuntu: ~",
  },
  stats: [
    { value: 21, suffix: "", label: "menu tools" },
    { value: 49, suffix: "+", label: "CLI options" },
    { value: 317, suffix: "/317", label: "tests passing" },
    { value: 0, suffix: "", label: "ShellCheck issues" },
  ],
  tools: {
    kicker: "What's inside",
    title: "21 tools, zero guesswork",
    subtitle:
      "Everything a fresh Ubuntu install needs — from network tuning to full app removal — behind one command and a friendly menu.",
    items: [
      {
        icon: "globe",
        tag: "Network",
        title: "Network optimization",
        desc: "BBR congestion control, fast DNS, auto MTU, full TCP tuning (fastopen + 16 MB buffers), Wi-Fi power-saving off.",
      },
      {
        icon: "memory",
        tag: "System",
        title: "System & memory",
        desc: "swappiness & vfs_cache_pressure, noatime applied instantly via remount, preload, TLP, capped journal size.",
      },
      {
        icon: "shield",
        tag: "Security",
        title: "Security & passwords",
        desc: "Extended sudo timeout + an optional polkit rule (local sessions only, with a transparent warning).",
      },
      {
        icon: "clock",
        tag: "Time",
        title: "Time & NTP",
        desc: "Clock sync with chrony plus a standalone fallback that works even when everything else fails.",
      },
      {
        icon: "wrench",
        tag: "Network",
        title: "fixnet repair script",
        desc: "A standalone bilingual script that repairs the connection after VPN drops — restores resolv.conf and waits for the network to return.",
      },
      {
        icon: "activity",
        tag: "Diagnostics",
        title: "Network tests & speed",
        desc: "Ping, DNS, internet speed test and a full network snapshot — plus a read-only system health report.",
      },
      {
        icon: "package",
        tag: "Apps",
        title: "Package & app install",
        desc: "deb packages, smart tar.gz/tgz installs (main binary detection, arch check, auto dependencies) and AppImage.",
      },
      {
        icon: "github",
        tag: "Apps",
        title: "GitHub Releases",
        desc: "Install / update / remove apps straight from GitHub releases — the right asset for your architecture, picked automatically.",
      },
      {
        icon: "eraser",
        tag: "Apps",
        title: "Complete removal",
        desc: "Fully remove any app from any source (apt / snap / flatpak / tar.gz / manual) — including user data, with sensitive paths blocked.",
      },
      {
        icon: "refresh",
        tag: "Apps",
        title: "One-shot updates",
        desc: "apt + snap + flatpak + tar.gz + GitHub updated in a single command — fully automatic with -y.",
      },
      {
        icon: "boxes",
        tag: "Apps",
        title: "snap & flatpak manager",
        desc: "List, install, remove and clean old snap revisions & flatpak runtimes with one menu.",
      },
      {
        icon: "heart",
        tag: "Rescue",
        title: "System recovery",
        desc: "Fix broken packages, reinstall the desktop environment, bring a broken machine back to life.",
      },
      {
        icon: "skull",
        tag: "Danger",
        title: "Advanced tools",
        desc: "Powerful destructive utilities — clearly separated, loudly warned, never silently executed.",
        danger: true,
      },
      {
        icon: "scroll",
        tag: "Logging",
        title: "Activity log",
        desc: "Every action is logged; a transparent summary closes each run. View or clear it anytime.",
      },
      {
        icon: "harddrive",
        tag: "Disk",
        title: "Disk usage analysis",
        desc: "Find out where your gigabytes went — usage broken down by category, read-only.",
      },
      {
        icon: "sparkles",
        tag: "Disk",
        title: "Disk cleanup",
        desc: "One-command cleanup: apt cache, journal, old kernels, snap revisions, crash reports — honestly reported.",
      },
      {
        icon: "inspect",
        tag: "Monitor",
        title: "Monitor & inspect",
        desc: "Health snapshot (load, memory verdict, temps, battery, failed units), big-file finder, listening ports with exposure flags and safe browser-cache cleanup.",
      },
    ],
  },
  terminal: {
    kicker: "See it in action",
    title: "Honest output, every run",
    subtitle:
      "What you see is exactly what runs. Try every optimization in dry-run before touching the system.",
  },
  install: {
    kicker: "Quick start",
    title: "Up and running in 60 seconds",
    subtitle:
      "Ubuntu 20.04+ (Debian-based distros work too) · Bash 4.3+ · sudo. Optional: jq for faster GitHub API parsing.",
    steps: [
      {
        title: "Clone the repository",
        code: "git clone https://github.com/CheginiSoroush/ubuntu-optimizer.git\ncd ubuntu-optimizer",
      },
      {
        title: "Run the installer",
        code: "./install.sh          # health check + uo command + PATH + bash completion\nsource ~/.bashrc      # once — new terminals are ready automatically",
      },
      {
        title: "Launch it",
        code: "uo                    # interactive menu\nuo --optimize --dry-run -y   # preview everything before any change",
      },
    ],
    tip: "Run uo without sudo — it only asks for the password when an operation truly needs it.",
  },
  safety: {
    kicker: "Safety first",
    title: "Reversible by design, honest by default",
    subtitle:
      "This tool changes system settings — so it is built to be reversible and transparent about everything it does.",
    items: [
      {
        icon: "eye",
        title: "Dry-run preview",
        desc: "uo --optimize --dry-run prints every single command before anything is executed.",
      },
      {
        icon: "backup",
        title: "Automatic backups",
        desc: "fstab.bak is created before noatime edits; sudoers files are validated with visudo and dropped on failure.",
      },
      {
        icon: "alert",
        title: "Warnings up front",
        desc: "DNS changes cut the connection (never over SSH), polkit lowers security a notch, avahi breaks printers — all announced in advance.",
      },
      {
        icon: "lock",
        title: "Sanitized paths",
        desc: "App names are sanitized before any operation; / , /opt and $HOME are blocked from deletion.",
      },
      {
        icon: "check",
        title: "Confirmation by default",
        desc: "Destructive operations always ask first — unless you explicitly pass -y.",
      },
      {
        icon: "book",
        title: "Read-only modes",
        desc: "--report and --disk take a snapshot of your system and change absolutely nothing.",
      },
    ],
    revertTitle: "Every tweak is one file — deleting it reverts the change",
    revertCode: `# kernel/network params (BBR, swappiness, ...)
sudo rm /etc/sysctl.d/99-ubuntu-optimizer.conf && sudo sysctl --system

# fstab (noatime) — restore the automatic backup
sudo cp /etc/fstab.bak /etc/fstab

# sudo timeout / polkit rule
sudo rm /etc/sudoers.d/99-optimizer-timeout
sudo rm /etc/polkit-1/rules.d/10-disable-password-timeout.rules`,
  },
  cli: {
    kicker: "Terminal native",
    title: "Built for scripts & terminal people",
    subtitle:
      "Every feature is one flag away. Prefer clicking? Just run uo and pick from the menu.",
    columns: { cmd: "Command", desc: "What it does" },
    commands: [
      { cmd: "uo --optimize", desc: "All network + system optimizations in one pass" },
      { cmd: "uo --optimize --dry-run -y", desc: "Preview every command before it runs" },
      { cmd: "uo --report", desc: "Read-only system health snapshot" },
      { cmd: "uo --doctor", desc: "Health-check & repair every tracked app" },
      { cmd: "uo --install-targz FILE [NAME]", desc: "Smart install from a tar.gz archive" },
      { cmd: "uo --github-install OWNER/REPO", desc: "Install from the latest GitHub release" },
      { cmd: "uo --cleanup NAME --purge-data", desc: "Full removal from every source, user data too" },
      { cmd: "uo --update -y", desc: "apt + snap + flatpak + tar.gz + GitHub, silently" },
      { cmd: "uo --fixnet", desc: "Build the standalone network repair script" },
      { cmd: "uo --disk / --disk-clean", desc: "Analyze disk usage / clean it up" },
      { cmd: "uo --health", desc: "Read-only health snapshot: load, memory, temps, battery, failed units" },
      { cmd: "uo --bigfiles [DIR]", desc: "The 20 biggest files under a directory (floor: UO_BIGFILES_MIN_MB)" },
      { cmd: "uo --ports", desc: "Listening ports + owners — all-interface binds flagged ⚠" },
      { cmd: "uo --browser-clean", desc: "Empty browser caches — running browsers skipped, data untouched" },
    ],
    examplesTitle: "Real-world examples",
  },
  faq: {
    kicker: "FAQ",
    title: "Questions, answered",
    items: [
      {
        q: "Is it safe to run?",
        a: "Every optimization is written to a separate, removable file instead of core system config. Backups are automatic (fstab.bak), sudoers edits are validated before activation, risky operations warn and ask, and --dry-run shows exactly what will happen.",
      },
      {
        q: "Which distros are supported?",
        a: "Designed and tested on Ubuntu 20.04+. Other Debian-family distros usually work — network features need NetworkManager (nmcli), which is standard on desktop installs.",
      },
      {
        q: "Can I undo everything?",
        a: "Yes. Each optimization is one independent file listed in the README's paths table — delete it and reboot. fstab is restored from its automatic backup.",
      },
      {
        q: "Why does it warn about SSH?",
        a: "The DNS and Wi-Fi power-saving steps restart the network connection. If you are connected over SSH, your session would drop — the tool detects this and warns you before running.",
      },
      {
        q: "Does it need internet?",
        a: "Only for installing/updating packages and network tests. All optimizations, reports, disk analysis and app management work fully offline.",
      },
      {
        q: "What's new in v7.15?",
        a: "The new Monitor & inspect family: uo --health (read-only health snapshot), uo --bigfiles (largest files), uo --ports (listening sockets with exposure flags) and uo --browser-clean (safe browser cache cleanup that skips running browsers and never touches your data). 317/317 tests pass, ShellCheck is clean.",
      },
    ],
  },
  updateCenter: {
    kicker: "Mission Control",
    title: "Update Center",
    subtitle:
      "Live release feed straight from GitHub — see the latest version, read the changelog and grab the newest build.",
    installed: "Installed version",
    latest: "Latest release",
    upToDate: "You are up to date",
    updateAvailable: "Update available",
    refresh: "Check for updates",
    refreshing: "Checking…",
    lastChecked: "Last checked",
    cached: "cached",
    live: "live",
    stale: "stale — network error, showing last snapshot",
    notes: "Release notes",
    downloads: "Downloadable assets",
    downloadCount: "downloads",
    viewRelease: "View on GitHub",
    error: "Could not reach GitHub. Check your connection or GH_TOKEN, then try again.",
    retry: "Try again",
    published: "Published",
    toastRefreshed: "Update Center refreshed",
  },
  footer: {
    tagline: "One command; a faster, cleaner, healthier Ubuntu.",
    madeWith: "Made with ❤️ and pure Bash",
    license: "MIT License",
    author: "Soroush Chegini",
    authorRole: "Author & maintainer",
    links: { repo: "Repository", issues: "Issues", changelog: "Changelog", contributing: "Contributing" },
    starCta: "If uo made your Ubuntu faster and cleaner, a star is the best encouragement!",
  },
  misc: {
    copy: "Copy",
    copied: "Copied to clipboard",
    version: "Version",
  },
};

const fa: typeof en = {
  dir: "rtl" as const,
  langName: "فارسی",
  otherLang: "English",
  nav: {
    tools: "ابزارها",
    install: "نصب",
    cli: "خط فرمان",
    safety: "ایمنی",
    update: "به‌روزرسانی",
    faq: "سؤالات",
    github: "گیت‌هاب",
  },
  hero: {
    badge: `${VERSION} — ۲۱ ابزار · ۳۱۷/۳۱۷ تست · MIT`,
    titleA: "یک دستور؛",
    titleB: "اوبونتویی سریع‌تر، تمیزتر و سالم‌تر.",
    subtitle:
      "جعبه‌ابزار همه‌کارهٔ بهینه‌سازی، مدیریت برنامه‌ها و تعمیر اوبونتو — ۲۱ ابزار در منویی ساده، بیش از ۴۹ گزینهٔ خط فرمان و پیش‌نمایش صادقانهٔ dry-run. خالص با Bash، کاملاً قابل بازگشت.",
    ctaGithub: "ستاره در گیت‌هاب",
    ctaInstall: "شروع کنید",
    scroll: "برای ادامه اسکرول کنید",
    termTitle: "soroush@ubuntu: ~",
  },
  stats: [
    { value: 21, suffix: "", label: "ابزار در منو" },
    { value: 49, suffix: "+", label: "گزینهٔ خط فرمان" },
    { value: 317, suffix: "/۳۱۷", label: "تست پاس‌شده" },
    { value: 0, suffix: "", label: "خطای ShellCheck" },
  ],
  tools: {
    kicker: "چه چیزهایی به دست می‌آورید؟",
    title: "۲۱ ابزار، بدون حدس‌زدن",
    subtitle:
      "هرچه یک اوبونتوی تازه‌نصب‌شده لازم دارد — از تنظیم شبکه تا حذف کامل برنامه‌ها — پشت یک دستور و یک منوی دوستانه.",
    items: [
      {
        icon: "globe",
        tag: "شبکه",
        title: "بهینه‌سازی شبکه",
        desc: "کنترل ازدحام BBR، DNS سریع، MTU خودکار، تنظیم کامل TCP (fastopen و بافرهای ۱۶ مگابایتی)، خاموش‌کردن صرفه‌جویی انرژی Wi-Fi.",
      },
      {
        icon: "memory",
        tag: "سیستم",
        title: "سیستم و حافظه",
        desc: "swappiness و vfs_cache_pressure، noatime با اعمال فوری از طریق remount، preload، TLP، محدودکردن حجم ژورنال.",
      },
      {
        icon: "shield",
        tag: "امنیت",
        title: "امنیت و گذرواژه‌ها",
        desc: "تمدید timeout سودو + قاعدهٔ polkit اختیاری (فقط نشست‌های محلی، همراه با هشدار شفاف).",
      },
      {
        icon: "clock",
        tag: "زمان",
        title: "زمان و NTP",
        desc: "همگام‌سازی ساعت با chrony به‌همراه راه‌حل اضطراری مستقل که حتی وقتی همه‌چیز خراب است کار می‌کند.",
      },
      {
        icon: "wrench",
        tag: "شبکه",
        title: "اسکریپت fixnet",
        desc: "اسکریپت مستقل دوزبانه که پس از قطع‌شدن VPN اتصال را تعمیر می‌کند — resolv.conf را بازمی‌گرداند و منتظر بازگشت شبکه می‌ماند.",
      },
      {
        icon: "activity",
        tag: "عیب‌یابی",
        title: "تست‌های شبکه و سرعت",
        desc: "ping، DNS، تست سرعت اینترنت و تصویر کامل شبکه — به‌همراه گزارش سلامت فقط-خواندنی سیستم.",
      },
      {
        icon: "package",
        tag: "برنامه‌ها",
        title: "نصب بسته و برنامه",
        desc: "بسته‌های deb، نصب هوشمند tar.gz/tgz (تشخیص فایل اجرایی، بررسی معماری، نصب خودکار وابستگی‌ها) و AppImage.",
      },
      {
        icon: "github",
        tag: "برنامه‌ها",
        title: "GitHub Releases",
        desc: "نصب / به‌روزرسانی / حذف برنامه‌ها مستقیم از ریلیزهای گیت‌هاب — فایل سازگار با معماری سیستم، خودکار انتخاب می‌شود.",
      },
      {
        icon: "eraser",
        tag: "برنامه‌ها",
        title: "حذف کامل",
        desc: "حذف کامل هر برنامه از هر منبعی (apt / snap / flatpak / tar.gz / دستی) — شامل داده‌های کاربر، با مسدود بودن مسیرهای حساس.",
      },
      {
        icon: "refresh",
        tag: "برنامه‌ها",
        title: "به‌روزرسانی یک‌مرحله‌ای",
        desc: "apt + snap + flatpak + tar.gz + GitHub در یک دستور — با -y کاملاً خودکار و بی‌سؤال.",
      },
      {
        icon: "boxes",
        tag: "برنامه‌ها",
        title: "مدیریت snap و flatpak",
        desc: "فهرست، نصب، حذف و پاک‌سازی نسخه‌های قدیمی snap و ران‌تایم‌های flatpak از یک منو.",
      },
      {
        icon: "heart",
        tag: "نجات",
        title: "بازیابی سیستم",
        desc: "تعمیر بسته‌های خراب، نصب مجدد محیط دسکتاپ، برگرداندن ماشین خراب به زندگی.",
      },
      {
        icon: "skull",
        tag: "خطر",
        title: "ابزارهای پیشرفته",
        desc: "ابزارهای مخرب قدرتمند — با جدا‌سازی واضح، هشدارهای صریح و هرگز بدون اجرای بی‌صدا.",
        danger: true,
      },
      {
        icon: "scroll",
        tag: "گزارش",
        title: "گزارش فعالیت",
        desc: "هر عملکرد ثبت می‌شود؛ خلاصه‌ای شفاف هر اجرا را می‌بندد. هر زمان ببینید یا پاک کنید.",
      },
      {
        icon: "harddrive",
        tag: "دیسک",
        title: "تحلیل فضای دیسک",
        desc: "بفهمید گیگابایت‌هایتان کجا رفته‌اند — مصرف فضا بر اساس دسته‌بندی، فقط-خواندنی.",
      },
      {
        icon: "sparkles",
        tag: "دیسک",
        title: "پاک‌سازی دیسک",
        desc: "پاک‌سازی با یک دستور: کش apt، ژورنال، کرنل‌های قدیمی، نسخه‌های snap، گزارش‌های کرش — با گزارش صادقانه.",
      },
      {
        icon: "inspect",
        tag: "پایش",
        title: "پایش و بازرسی",
        desc: "عکس سلامت سیستم (بار، حکم حافظه، دما، باتری، یونیت‌های خراب)، یافته‌ندهٔ فایل‌های حجیم، پورت‌های گوش‌دهنده با پرچم exposure و پاک‌سازی امن کش مرورگر.",
      },
    ],
  },
  terminal: {
    kicker: "در عمل ببینید",
    title: "خروجی صادقانه، در هر اجرا",
    subtitle:
      "همان چیزی که می‌بینید دقیقاً همان است که اجرا می‌شود. قبل از هر تغییری، همه‌چیز را در dry-run امتحان کنید.",
  },
  install: {
    kicker: "شروع سریع",
    title: "در ۶۰ ثانیه آماده است",
    subtitle:
      "اوبونتو ۲۰٫۰۴ به بالا (توزیع‌های مبتنی بر Debian هم کار می‌کنند) · Bash 4.3+ · دسترسی sudo. اختیاری: jq برای پارس سریع‌تر GitHub API.",
    steps: [
      {
        title: "مخزن را کلون کنید",
        code: "git clone https://github.com/CheginiSoroush/ubuntu-optimizer.git\ncd ubuntu-optimizer",
      },
      {
        title: "نصب را اجرا کنید",
        code: "./install.sh          # بررسی سلامت + دستور uo + تنظیم PATH + تکمیل خودکار bash\nsource ~/.bashrc      # یک‌بار — ترمینال‌های جدید خودکار آماده‌اند",
      },
      {
        title: "اجرا کنید",
        code: "uo                    # منوی تعاملی\nuo --optimize --dry-run -y   # پیش‌نمایش همه‌چیز قبل از هر تغییری",
      },
    ],
    tip: "دستور uo را بدون sudo اجرا کنید — خودش فقط وقتی عملیاتی واقعاً نیاز داشته باشد رمز می‌خواهد.",
  },
  safety: {
    kicker: "ایمنی در اولویت",
    title: "قابل بازگشت از طراحی، صادق به‌صورت پیش‌فرض",
    subtitle:
      "این ابزار تنظیمات سیستم را تغییر می‌دهد — برای همین طوری ساخته شده که قابل بازگشت باشد و دربارهٔ همه‌چیز شفاف.",
    items: [
      {
        icon: "eye",
        title: "پیش‌نمایش dry-run",
        desc: "دستور ‎\u2066uo --optimize --dry-run\u2069‎ هر تک‌دستوری را که قرار است اجرا شود، قبل از اجرا چاپ می‌کند.",
      },
      {
        icon: "backup",
        title: "پشتیبان‌گیری خودکار",
        desc: "قبل از ویرایش noatime از fstab بکاپ ساخته می‌شود؛ فایل‌های sudoers با visudo اعتبارسنجی و در خطا حذف می‌شوند.",
      },
      {
        icon: "alert",
        title: "هشدار قبل از تغییر",
        desc: "تغییر DNS اتصال را قطع می‌کند (روی SSH هرگز)، polkit امنیت را کمی پایین می‌آورد، avahi چاپگرهای شبکه را می‌شکند — همه از قبل اعلام می‌شوند.",
      },
      {
        icon: "lock",
        title: "مسیرهای ضدعفونی‌شده",
        desc: "نام برنامه‌ها قبل از هر عملیات sanitize می‌شود؛ / ، /opt و $HOME از حذف مسدودند.",
      },
      {
        icon: "check",
        title: "تأیید پیش‌فرض",
        desc: "عملیات‌های مخرب همیشه اول سؤال می‌کنند — مگر اینکه صریحاً ‎\u2066-y\u2069‎ بدهید.",
      },
      {
        icon: "book",
        title: "حالت فقط-خواندنی",
        desc: "دستورهای ‎\u2066--report\u2069‎ و ‎\u2066--disk\u2069‎ از سیستم عکس می‌گیرند و هیچ چیزی را تغییر نمی‌دهند.",
      },
    ],
    revertTitle: "هر بهینه‌سازی یک فایل است — حذفش یعنی بازگشت تغییر",
    revertCode: `# پارامترهای کرنل/شبکه (BBR، swappiness و…)
sudo rm /etc/sysctl.d/99-ubuntu-optimizer.conf && sudo sysctl --system

# fstab (noatime) — بازگرداندن پشتیبان خودکار
sudo cp /etc/fstab.bak /etc/fstab

# timeout سودو / قاعدهٔ polkit
sudo rm /etc/sudoers.d/99-optimizer-timeout
sudo rm /etc/polkit-1/rules.d/10-disable-password-timeout.rules`,
  },
  cli: {
    kicker: "بومی ترمینال",
    title: "برای اسکریپت‌ها و اهالی ترمینال",
    subtitle:
      "هر قابلیتی یک فلگ فاصله دارد. ترجیح می‌دهید کلیک کنید؟ فقط uo را اجرا کنید و از منو انتخاب کنید.",
    columns: { cmd: "دستور", desc: "چه کاری می‌کند" },
    commands: [
      { cmd: "uo --optimize", desc: "همهٔ بهینه‌سازی‌های شبکه + سیستم در یک اجرا" },
      { cmd: "uo --optimize --dry-run -y", desc: "پیش‌نمایش همهٔ دستورات قبل از اجرا" },
      { cmd: "uo --report", desc: "گزارش سلامت سیستم (فقط-خواندنی)" },
      { cmd: "uo --doctor", desc: "بررسی سلامت و تعمیر همهٔ برنامه‌های ردیابی‌شده" },
      { cmd: "uo --install-targz FILE [NAME]", desc: "نصب هوشمند از آرشیو tar.gz" },
      { cmd: "uo --github-install OWNER/REPO", desc: "نصب از آخرین ریلیز گیت‌هاب" },
      { cmd: "uo --cleanup NAME --purge-data", desc: "حذف کامل از هر منبعی، شامل داده‌های کاربر" },
      { cmd: "uo --update -y", desc: "apt + snap + flatpak + tar.gz + GitHub، بی‌سؤال" },
      { cmd: "uo --fixnet", desc: "ساخت اسکریپت مستقل تعمیر شبکه" },
      { cmd: "uo --disk / --disk-clean", desc: "تحلیل فضای دیسک / پاک‌سازی" },
      { cmd: "uo --health", desc: "عکس سلامت فقط-خواندنی: بار، حافظه، دما، باتری، یونیت‌های خراب" },
      { cmd: "uo --bigfiles [DIR]", desc: "۲۰ فایل حجیم یک مسیر (آستانه: UO_BIGFILES_MIN_MB)" },
      { cmd: "uo --ports", desc: "پورت‌های گوش‌دهنده + صاحبشان — اتصال باز با ⚠" },
      { cmd: "uo --browser-clean", desc: "خالی‌کردن کش مرورگرها — مرورگر باز رد می‌شود، داده‌ها سالم" },
    ],
    examplesTitle: "مثال‌های واقعی",
  },
  faq: {
    kicker: "سؤالات متداول",
    title: "پاسخ به سؤال‌های رایج",
    items: [
      {
        q: "اجرای آن ایمن است؟",
        a: "هر بهینه‌سازی در یک فایل مستقل و قابل‌حذف نوشته می‌شود، نه در تنظیمات اصلی سیستم. پشتیبان‌ها خودکار ساخته می‌شوند (fstab.bak)، ویرایش‌های sudoers قبل از فعال‌شدن اعتبارسنجی می‌شوند، عملیات‌های پرخطر هشدار و تأیید می‌خواهند و ‎\u2066--dry-run\u2069‎ دقیقاً نشان می‌دهد چه اتفاقی خواهد افتاد.",
      },
      {
        q: "کدام توزیع‌ها پشتیبانی می‌شوند؟",
        a: "برای اوبونتو (۲۰٫۰۴ به بالا) طراحی و تست شده است. سایر توزیع‌های خانوادهٔ Debian معمولاً کار می‌کنند — قابلیت‌های شبکه به NetworkManager (nmcli) نیاز دارند که در نصب‌های دسکتاپ استاندارد است.",
      },
      {
        q: "می‌توانم همه‌چیز را برگردانم؟",
        a: "بله. هر بهینه‌سازی یک فایل مستقل است که در جدول مسیرهای README فهرست شده — کافی است حذفش کنید و ریبوت. fstab هم از پشتیبان خودکار بازگردانده می‌شود.",
      },
      {
        q: "چرا دربارهٔ SSH هشدار می‌دهد؟",
        a: "مراحل DNS و صرفه‌جویی انرژی Wi-Fi اتصال شبکه را ری‌استارت می‌کنند. اگر با SSH به ماشین وصل باشید، نشست شما قطع می‌شود — ابزار این را تشخیص می‌دهد و قبل از اجرا هشدار می‌دهد.",
      },
      {
        q: "آیا به اینترنت نیاز دارد؟",
        a: "فقط برای نصب/به‌روزرسانی بسته‌ها و تست‌های شبکه. همهٔ بهینه‌سازی‌ها، گزارش‌ها، تحلیل دیسک و مدیریت برنامه‌ها کاملاً آفلاین کار می‌کنند.",
      },
      {
        q: "تازگی‌های نسخهٔ ۷٫۱۵ چیست؟",
        a: "خانوادهٔ جدید «پایش و بازرسی»: uo --health (عکس سلامت فقط-خواندنی)، uo --bigfiles (بزرگ‌ترین فایل‌ها)، uo --ports (پورت‌های گوش‌دهنده با پرچم exposure) و uo --browser-clean (پاک‌سازی امن کش مرورگر که مرورگرهای باز را رد می‌کند و هیچ داده‌ای را لمس نمی‌کند). ۳۱۷/۳۱۷ تست پاس و ShellCheck تمیز است.",
      },
    ],
  },
  updateCenter: {
    kicker: "مرکز کنترل",
    title: "مرکز به‌روزرسانی",
    subtitle:
      "اطلاع زندهٔ ریلیزها مستقیم از گیت‌هاب — آخرین نسخه را ببینید، تغییرات را بخوانید و جدیدترین بسته را بگیرید.",
    installed: "نسخهٔ نصب‌شده",
    latest: "آخرین ریلیز",
    upToDate: "به‌روز هستید",
    updateAvailable: "به‌روزرسانی در دسترس است",
    refresh: "بررسی به‌روزرسانی",
    refreshing: "در حال بررسی…",
    lastChecked: "آخرین بررسی",
    cached: "کش‌شده",
    live: "زنده",
    stale: "قدیمی — خطای شبکه؛ آخرین تصویر نمایش داده می‌شود",
    notes: "یادداشت‌های ریلیز",
    downloads: "فایل‌های قابل دانلود",
    downloadCount: "دانلود",
    viewRelease: "مشاهده در گیت‌هاب",
    error: "ارتباط با گیت‌هاب برقرار نشد. اتصال یا GH_TOKEN را بررسی کنید و دوباره تلاش کنید.",
    retry: "تلاش دوباره",
    published: "انتشار",
    toastRefreshed: "مرکز به‌روزرسانی به‌روز شد",
  },
  footer: {
    tagline: "یک دستور؛ اوبونتویی سریع‌تر، تمیزتر و سالم‌تر.",
    madeWith: "ساخته‌شده با ❤️ و Bash خالص",
    license: "لایسنس MIT",
    author: "سروش چگینی",
    authorRole: "نویسنده و نگهدارنده",
    links: { repo: "مخزن", issues: "ایرادها", changelog: "تاریخچهٔ تغییرات", contributing: "مشارکت" },
    starCta: "اگر uo اوبونتوی شما را سریع‌تر و تمیزتر کرد، یک ⭐ بهترین تشویق است!",
  },
  misc: {
    copy: "کپی",
    copied: "در کلیپ‌بورد کپی شد",
    version: "نسخه",
  },
};

export const dictionaries: Record<Lang, typeof en> = { en, fa };
export type Dict = typeof en;

export function formatNumber(n: number, lang: Lang): string {
  return n.toLocaleString(lang === "fa" ? "fa-IR" : "en-US");
}
