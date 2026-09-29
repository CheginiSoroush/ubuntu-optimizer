# 🐧 Ubuntu Optimizer & Fixer — مستندات فارسی

ابزار جامع بهینه‌سازی، مدیریت برنامه‌ها و رفع مشکلات اوبونتو

**نویسنده و طراح:** Soroush Chegini ([CheginiSoroush](https://github.com/CheginiSoroush))

**نسخه:** 6.0 | **پیش‌نیاز:** Ubuntu 20.04+ و Bash 4.3+

> 📖 [English documentation](README.md)
>
> **نکته:** از نسخه ۶.۰ رابط کاربری، پیام‌ها و لاگ‌های برنامه **انگلیسی** شده‌اند (نسخه بین‌المللی)؛ این سند، راهنمای فارسی همان برنامه است. اسکریپت fixnet همچنان دوزبانه (فارسی/انگلیسی) است.

---

## ✨ امکانات

| حوزه | قابلیت‌ها |
|---|---|
| 🌐 شبکه | فعال‌سازی BBR، تنظیم DNS، MTU، بهینه‌سازی کامل TCP (fastopen، بافرها)، غیرفعال‌کردن Power Management وای‌فای |
| 💾 سیستم | swappiness و vfs_cache_pressure، noatime (اعمال فوری با remount)، نصب preload و tlp، محدودسازی لاگ |
| 🔐 امنیت | افزایش زمان اعتبار sudo، قانون polkit (اختیاری — فقط نشست محلی) |
| 🕐 زمان | همگام‌سازی زمان با chrony (با fallback اضطراری مستقل) |
| 🛠 fixnet | اسکریپت مستقل دو‌زبانه برای رفع مشکل اینترنت بعد از قطع VPN — بازگردانی resolv.conf و انتظار هوشمند برای بازگشت شبکه |
| 📊 تست | پینگ، DNS، سرعت اینترنت، اطلاعات کامل شبکه |
| 📦 نصب | بسته‌های deb، **نصب هوشمند tar.gz/tgz** (تشخیص اجرایی اصلی + بررسی معماری + نصب خودکار وابستگی‌ها) |
| 🐙 گیت‌هاب | نصب / به‌روزرسانی / حذف برنامه‌ها از GitHub Releases — انتخاب خودکار فایل مناسب معماری |
| 🧹 حذف | **حذف کامل هر برنامه از هر منبعی** (apt/snap/flatpak/tar.gz/دستی) + داده‌های کاربری |
| 🔄 به‌روزرسانی | apt + snap + flatpak + tar.gz (اسکن Downloads یا URL) + گیت‌هاب — با `-y` کاملاً خودکار |
| 🧩 snap/flatpak | لیست، نصب، حذف، پاک‌سازی نسخه‌های قدیمی و ران‌تایم‌های unused |
| 🚑 بازیابی | رفع بسته‌های خراب، نصب مجدد دسکتاپ |
| 📜 لاگ | ثبت خودکار همه عملیات + خلاصه پایان هر اجرا |
| 📊 گزارش | گزارش وضعیت سیستم و سلامت بهینه‌سازی‌ها (فقط خواندنی) |

---

## 🆕 تازه‌های نسخه 6.0

- **نسخه بین‌المللی:** تمام پیام‌ها، کامنت‌ها و لاگ‌ها به انگلیسی؛ مستندات فارسی در همین فایل حفظ شد
- **صفر خطای ShellCheck** در کل پروژه + workflow خودکار CI (shellcheck و bash -n در هر commit)
- **پشتیبانی از توکن GitHub API** (`GH_TOKEN`) — رفع محدودیت نرخ درخواست‌ها
- رفع باگ‌های مهم: Power Management وای‌فای، محافظت از `/opt`، جلوگیری از حذف پوشه‌های پایه داده‌ها، حلقه‌های بی‌نهایت حالت `-y`
- امنیت: قانون polkit فقط برای نشست محلی؛ دانلودهای گیت‌هاب در mktemp امن
- بهبورها: noatime فوری با remount، fastopen و بافرهای 16MB، لاگ‌نویسی بدون fork

(فهرست کامل تغییرات از 5.5 تا 6.0 در [README انگلیسی](README.md))

---

## 🚀 نصب

```bash
mv ubuntu-optimizer ~/.    # مسیر پیشنهادی: ~/ubuntu-optimizer
cd ~/ubuntu-optimizer
./install.sh
```

سپس یک‌بار `source ~/.bashrc` بزنید یا ترمینال جدید باز کنید:

```bash
uo              # منوی تعاملی
uo --report     # گزارش وضعیت سیستم
uo --help       # راهنمای کامل (انگلیسی)
```

> ⚠️ اسکریپت را **بدون sudo** اجرا کنید — خودش هنگام نیاز رمز می‌پرسد.

```bash
./install.sh --check       # بررسی سلامت فایل‌ها و وضعیت نصب
./install.sh --update      # به‌روزرسانی از git
./install.sh --uninstall   # حذف میان‌بر و alias
```

### اختیاری: توکن GitHub API

`--github-update` و `--github-install` از API گیت‌هاب سؤال می‌پرسند که محدود به
**۶۰ درخواست/ساعت به‌ازای IP** است — محدودیتی که با همه‌ی کاربران پشت NAT شرکت
مخابراتی مشترک است! با توکن شخصی به **۵,۰۰۰ در ساعت** می‌رسد:

۱. توکن فقط‌خواندنی بسازید: github.com → Settings → Developer settings →
   Personal access tokens → *Generate new token (classic)* — برای مخازن
   عمومی **هیچ دسترسی‌ای لازم نیست**.
۲. به شل اضافه کنید:

```bash
echo 'export GH_TOKEN="ghp_your_token"' >> ~/.bashrc
source ~/.bashrc
```

هر دو متغیر `GH_TOKEN` و `GITHUB_TOKEN` پشتیبانی می‌شوند. توکن فقط به
`api.github.com` ارسال می‌شود و هرگز در لاگ ثبت نمی‌شود.

---

## ⌨️ حالت CLI

| دستور | کار |
|---|---|
| `uo --report` | گزارش وضعیت سیستم (فقط خواندنی) |
| `uo --github-install OWNER/REPO [NAME]` | نصب برنامه از آخرین release گیت‌هاب |
| `uo --install-targz FILE [NAME]` | نصب برنامه از فایل .tar.gz/.tgz |
| `uo --github-update` / `--github-list` / `--github-remove` | به‌روزرسانی / فهرست / حذف برنامه‌های گیت‌هابی |
| `uo --git-ssh` / `--git-ssh-status` | ویزارد SSH / وضعیت SSH |
| `uo --optimize` / `--network` / `--system` | بهینه‌سازی کامل / شبکه / سیستم |
| `uo --security` / `--time` | امنیت / همگام‌سازی زمان |
| `uo --fixnet` / `--fixnet-run` | ساخت / اجرای fixnet |
| `uo --test` | تست‌های شبکه |
| `uo --update` + حالت‌های خاص | به‌روزرسانی همه منابع یا یک منبع |
| `uo --list-apps` | لیست همه برنامه‌ها از همه منابع |
| `uo --cleanup نام --purge-data` | حذف کامل برنامه + داده‌ها |
| `uo --snap-clean` | پاک‌سازی snap/flatpak قدیمی |
| `uo --log` / `--log-clear` | نمایش / حذف لاگ |
| `uo -y` / `--no-log` / `--no-color` | گزینه‌های سراسری |

---

## 📍 فایل‌ها و مسیرها

| مسیر | توضیح |
|---|---|
| `/etc/sysctl.d/99-ubuntu-optimizer.conf` | پارامترهای کرنل |
| `/etc/systemd/journald.conf.d/99-optimizer.conf` | محدودیت حجم لاگ سیستم |
| `/etc/sudoers.d/99-optimizer-timeout` | زمان اعتبار sudo (۱۲۰ دقیقه) |
| `/etc/polkit-1/rules.d/10-disable-password-timeout.rules` | قانون polkit (فقط با تأیید) |
| `/opt/<نام>` | محل نصب برنامه‌های tar.gz |
| `~/.local/share/ubuntu-optimizer/apps.db` | رجیستری tar.gz |
| `~/.local/share/ubuntu-optimizer/github.db` | بانک گیت‌هاب |
| `~/.local/state/ubuntu-optimizer/optimizer.log` | لاگ فعالیت‌ها |
| `~/fix-network.sh` | fixnet + alias `fixnet` |
| `~/.local/bin/uo` | میان‌بر اجرا |

بک‌آپ: `/etc/fstab.bak` (قبل از noatime)

---

## 🔒 نکات امنیتی

- اجرا با کاربر عادی؛ sudo فقط برای عملیات لازم
- اعتبارسنجی sudoers با `visudo -c -f` — حذف خودکار در صورت خطا
- قانون polkit فقط برای نشست‌های **محلیِ فعال** (SSH شامل نمی‌شود)
- مسیرهای حساس (`/`، `/opt`، `$HOME`...) در حذف مسدودند
- عملیات‌های مخرب همیشه تأیید می‌گیرند (مگر با `-y`)
- `set_dns` و Power Management اتصال را ری‌استارت می‌کنند — روی SSH احتیاط کنید

---

## ⚠️ سلب مسئولیت

این ابزار تنظیمات سیستمی را تغییر می‌دهد؛ مسئولیت نهایی استفاده با شماست. برای undo کامل، فایل‌های جدول بالا را حذف و ری‌استارت کنید.

---

## 🗺 نقشه راه

- [x] GitHub Actions (shellcheck + bash -n)
- [x] توکن GitHub API (`GH_TOKEN` / `GITHUB_TOKEN`)
- [x] bash-completion
- [x] تست‌های خودکار (bats)
- [x] حالت `--dry-run`
