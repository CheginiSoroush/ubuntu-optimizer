<div align="center">
  <a href="https://github.com/CheginiSoroush/ubuntu-optimizer">
    <img src="docs/logo.svg" width="130" alt="لوگوی Ubuntu Optimizer &amp; Fixer" />
  </a>

# Ubuntu Optimizer &amp; Fixer

**یک دستور؛ اوبونتویی سریع‌تر، تمیزتر و سالم‌تر.**

جعبه‌ابزار همه‌کارهٔ بهینه‌سازی، مدیریت برنامه‌ها و تعمیر اوبونتو —
۲۲ ابزار در منویی ساده، بیش از ۵۷ گزینهٔ خط فرمان و پیش‌نمایش صادقانهٔ dry-run.

[![CI](https://github.com/CheginiSoroush/ubuntu-optimizer/actions/workflows/lint.yml/badge.svg)](https://github.com/CheginiSoroush/ubuntu-optimizer/actions/workflows/lint.yml)
[![Website](https://img.shields.io/website?url=https%3A%2F%2Fcheginisoroush.github.io%2Fubuntu-optimizer&logo=github&label=website)](https://cheginisoroush.github.io/ubuntu-optimizer/)
[![Version](https://img.shields.io/badge/version-v7.18-E95420?logo=ubuntu)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-007EC6)](LICENSE)
![ShellCheck](https://img.shields.io/badge/ShellCheck-clean-brightgreen)
![Tests](https://img.shields.io/badge/bats-510%20%2F%20510-brightgreen)
![Bash](https://img.shields.io/badge/made%20with-Bash-4EAA25?logo=gnubash&logoColor=white)

[English](README.md) · [فارسی](README.fa.md)

</div>

<p align="center">
  <img src="docs/demo.svg" alt="منوی تعاملی uo" width="620" />
</p>

---

## ✨ چه چیزهایی به دست می‌آورید؟

| حوزه | قابلیت‌ها |
|---|---|
| 🌐 **شبکه** | کنترل ازدحام BBR · DNS سریع (8.8.8.8 / 1.1.1.1) · تنظیم خودکار MTU · تنظیم کامل TCP (fastopen و بافرهای ۱۶ مگابایتی) · خاموش‌کردن صرفه‌جویی انرژی Wi-Fi |
| 💾 **سیستم و حافظه** | swappiness و vfs_cache_pressure · noatime (بلافاصله با remount اعمال می‌شود) · preload · TLP · محدودکردن حجم ژورنال |
| 🔐 **امنیت** | تمدید timeout سودو · قاعدهٔ polkit اختیاری (فقط نشست‌های محلی، همراه با هشدار شفاف) |
| 🕐 **زمان** | همگام‌سازی با chrony به‌همراه راه‌حل اضطراری مستقل |
| 🛠 **fixnet** | اسکریپت مستقل دوزبانه که پس از قطع‌شدن VPN اتصال را تعمیر می‌کند — resolv.conf را بازمی‌گرداند و *منتظر بازگشت شبکه می‌ماند* |
| 💿 **دیسک** | تحلیل مصرف فضا بر اساس دسته‌بندی + پاک‌سازی با یک دستور (کش apt، ژورنال، کرنل‌های قدیمی، نسخه‌های snap، گزارش‌های کرش) · **گزارش HTML قابل‌اشتراک** («--disk-report», v7.12) — صفحهٔ خودکفا با نمودار و جدول‌های قابلمرتب‌سازی، کاملاً آفلاین |
| 📊 **عیب‌یابی** | ping، DNS، تست سرعت اینترنت · گزارش وضعیت سیستم فقط-خواندنی · گزارش JSON ماشین‌خوان (`--report --json`) · لاگ سری‌زمانی JSONL (`--report --json --append --output`, v7.7) |
| ⚙ **فایل کانفیگ** | `~/.config/uo/config.conf` — ماندگارسازی ASSUME_YES / NO_COLOR / NO_LOG / DRY_RUN / DNS_SERVERS / NO_CACHE برای کرون و سیستم‌های مشترک؛ هرگز source یا eval نمی‌شود — هر خط parse و اعتبارسنجی می‌شود (v7.8) |
| ⚡ **کش TTL** | نتایج پرهزینه (بررسی اتصال، به‌روزرسانی لیست apt، استعلام ریلیز GitHub) با زمان انقضا کش می‌شوند — اجراهای پشت‌سرهم منتظر نمی‌مانند؛ بازرسی با --cache-stats، پاک‌سازی با --cache-clear، دورزدن با --no-cache (v7.9) |
| ⏰ **آپدیت زمان‌بندی‌شده** | «uo --timer-install weekly» یک **تایمر systemd** واقعی می‌سازد که هفتگی «uo --update -y --no-color» را بی‌سؤال اجرا می‌کند — با Persistent=true اجرای ازدست‌رفته بعد از خاموشی جبران می‌شود؛ به‌صورت پیش‌فرض دامنهٔ کاربر (بدون روت)، با --timer-system برای سرورها، و --timer-notify-only برای تیک پایش فقط-خواندنی که گزارش JSON را ثبت و هنگام مشکل اعلان می‌دهد (v7.10) |
| 📦 **نصب** | بسته‌های deb · **نصب هوشمند tar.gz/tgz** (تشخیص فایل اجرایی اصلی، بررسی معماری، نصب خودکار وابستگی‌ها) · AppImage |
| 🐙 **GitHub Releases** | نصب / به‌روزرسانی / حذف برنامه‌ها — انتخاب خودکار فایل سازگار با معماری سیستم · **بررسی checksum شی‌آر-۲۵۶** وقتی ریلیز فایل checksum دارد (v7.4) |
| ⬆ **به‌روزرسانی خود ابزار** | **خودکار در هر اجرای `uo`** (v7.13): بررسی نسخه با کش TTL، پیشنهاد نسخه تازه‌تر، اعمال و راه‌اندازی دوباره با کد جدید — یک بنر، یک سؤال، هرگز جلوی کار را نمی‌گیرد (خاموشی با `--no-update` / `UO_AUTO_UPDATE=0`) · `uo --self-update` برای حالت دستی: بررسی نسخه از مخزن رسمی، git pull برای کلون‌ها، آرشیو تأییدشده + پشتیبان خودکار برای کپی‌های ثابت (v7.6) |
| 🥾 **بوت و استارتاپ** | تحلیل زمان بوت با حکم نهایی — کل زمان، ۱۰ یونیت کندترین، زنجیرهٔ بحرانی، یونیت‌های شکست‌خورده (v7.14) · **مدیر استارتاپ XDG**: فهرست و فعال/غیرفعال‌کردن برنامه‌های استارتاپ — هرگز فایل سیستمی لمس نمی‌شود، کاملاً بازگشت‌پذیر با override کاربر (v7.14) |
| 🔍 **پایش و بازرسی** | **عکس سلامت** (`--health`): بار، حکم حافظه، دیسک، دما، باتری، یونیت‌های خراب، آپدیت‌های در انتظار (v7.15) · **یافته‌ندهٔ فایل‌های حجیم** (`--bigfiles`): ۲۰ فایل بزرگ هر مسیر (v7.15) · **پورت‌های گوش‌دهنده** (`--ports`): هر شنونده + صاحبش، اتصال به همهٔ اینترفیس‌ها با ⚠ (v7.15) · **پاک‌سازی کش مرورگر** (`--browser-clean`): کش‌های Chromium/فایرفاکس/بندانگشتی — مرورگر باز رد می‌شود، فایل داده لمس نمی‌شود (v7.15) |
| 🧰 **نگهداشت و سخت‌افزار** | **سوییچر DNS** (`--dns`): شکن · ۴۰۳ · رادار · الکترو (عبور از تحریم) · cloudflare · google · quad9 · adguard · auto — با یک کلمه، سه مکانیزم اعمال (NM / systemd-resolved / resolv.conf)، `auto` برگشت به DHCP (v7.16) · **پاک‌سازی کرنل‌های قدیمی** (`--kernel-clean`): کرنل در حال اجرا و تازه‌ترین همیشه محفوظ، پلن دقیق purge بسته‌ها (v7.16) · **مدیر swap** (`--swap-on` / `--swap-off` / `--swappiness`): حجم پیشنهادی از RAM، ورودی fstab علامت‌دار، پارتیشن/zram دست‌نخورده (v7.16) |
| 🚀 **منوی fzf و رابط دوزبانه** | **منوی تعاملی fzf** (`--fzf`): جست‌وجوی فازی میان همهٔ اقدام‌ها و اجرای انتخاب — در نبود fzf فقط راهنمای دوستانه (v7.17) · **رابط fa/en** (`--lang fa|en`، `--lang-show`، `UO_LANG`): منو/بنر/پیام‌ها به فارسی با بازگشت به انگلیسی (v7.17) |
| 🧹 **حذف کامل** | حذف کامل هر برنامه از **هر منبعی** (apt / snap / flatpak / tar.gz / دستی) — به‌همراه داده‌های کاربر |
| 🔄 **به‌روزرسانی** | apt + snap + flatpak + tar.gz + GitHub در یک دستور، با `-y` کاملاً خودکار |
| 🚑 **بازیابی** | تعمیر بسته‌های خراب، نصب مجدد محیط دسکتاپ |
| 📜 **گزارش‌گیری** | ثبت هر عملکرد در گزارش، با خلاصه‌ای شفاف در پایان هر اجرا |

> 💡 حوصله به‌خاطر‌سپردن فلگ‌ها را ندارید؟ فقط `uo` را اجرا کنید و از منو انتخاب کنید.
> ترمینال جان خانه‌تان است؟ همهٔ امکانات یک فلگ فاصله دارند — `uo --help`.

---

## ⚡ شروع سریع

```bash
git clone https://github.com/CheginiSoroush/ubuntu-optimizer.git
cd ubuntu-optimizer
./install.sh          # بررسی سلامت + دستور `uo` + تنظیم PATH + تکمیل خودکار bash
source ~/.bashrc      # یک‌بار — ترمینال‌های جدید خودکار آماده‌اند
```

```bash
uo                    # منوی تعاملی
uo --report           # گزارش سیستم (فقط خواندن)
uo --report --json | jq '.summary'   # همان گزارش، خروجی ماشین‌خوان (v7.5)
uo --report --json --append --output ~/.local/share/ubuntu-optimizer/report-log.jsonl
                      # هر بار اجرا یک خط JSON → لاگ سری‌زمانی برای داشبوردها (v7.7)
uo --config-show      # بازرسی کانفیگ مؤثر (v7.8)
uo --cache-stats      # چه چیزی کش شده و تا کِی (v7.9)
uo --timer-install weekly   # آپدیت دوره‌ای بدون دخالت کاربر (v7.10)
uo                    # اول خودش را برای نسخه جدید چک می‌کند (کش TTL، v7.13)
uo --no-update        # رد شدن از این بررسی فقط برای همین اجرا
uo --self-update      # خود ابزار را روی آخرین نسخه نگه دارید (v7.6)
uo --optimize --dry-run -y   # پیش‌نمایش همه‌چیز قبل از هر تغییری
```

**پیش‌نیازها:** اوبونتو ۲۰٫۰۴ به بالا (سایر توزیع‌های مبتنی بر Debian هم کار می‌کنند) · Bash 4.3+ · `sudo`
**اختیاری:** `jq` (پارس سریع‌تر GitHub API — بدون آن هم همه‌چیز کار می‌کند) · [`GH_TOKEN`](#-توکن-اختیاری-github-api)

> ⚠️ دستور `uo` را **بدون sudo** اجرا کنید — خودش فقط زمانی که عملیاتی واقعاً نیاز داشته باشد، رمز sudo را می‌خواهد.

<details>
<summary><b>📦 مدیریت نصب</b> (به‌روزرسانی / حذف / بررسی سلامت)</summary>

```bash
./install.sh --check       # سلامت فایل‌ها و وضعیت نصب (کد خروج مناسب CI)
./install.sh --update      # به‌روزرسانی از git (اگر پوشه مخزن git باشد)
./install.sh --uninstall   # حذف میان‌بر، alias و تکمیل خودکار — فایل‌های پروژه می‌مانند
```
</details>

---

## ⚡ پروفایل‌ها — یک فلگ برای کل سناریو

به‌جای حفظ‌کردن مراحل، وضعیت خود را انتخاب کنید — هر پروفایل زیرمجموعه‌ای
ایمن و منتخب از بهینه‌ساز را اجرا می‌کند (اول برنامه نمایش داده می‌شود و با
`uo --undo` قابل بازگشت است):

| پروفایل | اجرا می‌شود | عمداً حذف شده |
|---|---|---|
| `laptop` | حافظه · noatime · TLP · BBR/TCP · خاموشی powersave وای‌فای · سقف ژورنال | preload |
| `server` | حافظه · noatime · سقف ژورنال · BBR/TCP · خاموشی سرویس‌های اضافه | TLP، مراحل وای‌فای، preload |
| `gaming` | حافظه · BBR/TCP · خاموشی powersave وای‌فای · سقف ژورنال | noatime، سرویس‌ها، نصب‌ها |
| `minimal` | حافظه · سقف ژورنال · خاموشی سرویس‌های اضافه | بقیهٔ موارد — هیچ چیزی نصب نمی‌شود |

```bash
uo --profile laptop --dry-run -y   # اول پیش‌نمایش دقیق برنامه
uo --profile server -y             # اعمال بدون سؤال
```

---

## 🌐 وب‌سایت — میزبانی‌شده روی GitHub Pages

این پروژه یک صفحهٔ معرفی دوزبانه (فارسی / English) هم دارد — با پشتیبانی کامل RTL/LTR،
تم روشن و تاریک و دموی ترمینال انیمیشنی — که با Next.js 16 و Tailwind CSS 4 ساخته شده
و **به‌صورت رایگان روی GitHub Pages** میزبانی می‌شود:

> **🔗 https://cheginisoroush.github.io/ubuntu-optimizer/**

- سورس در پوشهٔ [`website/`](website) است و هر تغییری در آن با
  [`.github/workflows/website.yml`](.github/workflows/website.yml) به‌صورت خودکار build و منتشر می‌شود
- تنها تنظیم لازم پس از ساخت مخزن: **Settings → Pages → Source → GitHub Actions**
- بدون سرور، بدون دیتابیس، بدون هزینه — خروجی کاملاً استاتیک (`output: 'export'`)

راهنمای اجرای محلی و build دستی: [`website/README.md`](website/README.md).

---

## 🖥 منوی تعاملی — ۱۸ ابزار، بدون نیاز به حفظ‌کردن هیچ‌چیز

| # | ابزار | چه کاری می‌کند |
|:--:|---|---|
| 1 | 🌐 بهینه‌سازی شبکه | BBR، DNS، MTU، تنظیم TCP، مدیریت انرژی Wi-Fi |
| 2 | 💾 بهینه‌سازی سیستم و حافظه | swappiness، noatime، preload، TLP، محدودکردن ژورنال |
| 3 | 🔐 امنیت و گذرواژه‌ها | timeout سودو + تنظیمات polkit |
| 4 | 🕐 زمان و NTP | همگام‌سازی ساعت سیستم |
| 5 | ⚡ پروفایل‌های بهینه‌سازی | پیش‌تنظیم‌های منتخب: laptop · server · gaming · minimal |
| 6 | 🛠 ساخت و اجرای fixnet | ساخت اسکریپت مستقل تعمیر شبکه |
| 7 | 📊 تست‌های شبکه و سرعت | ping، DNS، سرعت، اطلاعات کامل شبکه |
| 8 | 📦 نصب بسته‌ها و برنامه‌ها | deb · tar.gz · GitHub Releases · AppImage |
| 9 | 🧹 مدیریت و حذف کامل برنامه‌ها | هر برنامه‌ای، از هر منبعی، شامل داده‌های کاربر |
| 10 | 🔄 به‌روزرسانی برنامه‌ها | همهٔ منابع در یک مرحله |
| 11 | 🧩 مدیریت snap و flatpak | فهرست، نصب، حذف، پاک‌سازی نسخه‌ها |
| 12 | 🚑 بازیابی و نجات سیستم | بسته‌های خراب، نصب مجدد دسکتاپ، `--undo` |
| 13 | ☠ ابزارهای پیشرفته *(خطرناک)* | با جدا‌سازی واضح و هشدارهای صریح |
| 14 | 📜 گزارش فعالیت | چه اتفاقی، کِی افتاده است |
| 15 | 📊 گزارش وضعیت سیستم | عکس‌برداری فقط-خواندنی از سلامت و بهینه‌سازی‌ها |
| 16 | 📊 تحلیل فضای دیسک | گیگابایت‌های شما کجا رفته‌اند |
| 17 | 🧹 پاک‌سازی دیسک | پس‌گرفتنشان |
| 18 | ⏰ آپدیت زمان‌بندی‌شده | تایمر systemd برای اجرای بی‌سؤال |
| 19 | 🖥 گزارش دیسک (HTML) | نمودارها و جدول‌های قابل اشتراک |
| 20 | 🥾 بوت و استارتاپ | تحلیل بوت · روشن/خاموش‌کردن استارتاپ |
| 21 | 🔍 پایش و بازرسی | سلامت · فایل‌های حجیم · پورت‌ها · کش مرورگر |
| 22 | 🧰 نگهداشت و سخت‌افزار | DNS · کرنل‌های قدیمی · swap · وضعیت و تعمیر اسپلش بوت |

---

## ⌨ حالت خط فرمان — برای اسکریپت‌ها و اهالی ترمینال

| دستور | کار |
|---|---|
| `uo --optimize` | همهٔ بهینه‌سازی‌های شبکه + سیستم |
| `uo --network` / `--system` / `--security` / `--time` | فقط یک حوزه |
| `uo --undo` | **برگرداندن همه‌چیز** با یک دستور — هر چه بهینه‌ساز تغییر داده |
| `uo --profile laptop\|server\|gaming\|minimal` | اعمال پیش‌تنظیم منتخب برای سناریوی شما |
| `uo --dry-run` | **پیش‌نمایش** دستورات بدون اجرا (به‌همراه شش گزینهٔ بالا) |
| `uo` (استارتاپ) | بررسی خودکار به‌روزرسانی — پیشنهاد ← اعمال ← اجرای دوباره با کد جدید؛ با `--no-update` / `UO_AUTO_UPDATE=0` قابل خاموشی (v7.13) |
| `uo --self-update` | به‌روزرسانی خودِ ابزار — git pull یا آرشیو تأییدشده، با پشتیبان و بازگشت (v7.6) |
| `uo --report` · `--report --json` · `--disk` | گزارش وضعیت · گزارش JSON برای اتوماسیون · تحلیل دیسک · پاک‌سازی |
| `uo --report --json --output FILE [--append]` | نوشتن گزارش در فایل — `--append` یک لاگ سری‌زمانی JSONL برای داشبوردها می‌سازد (v7.7) |
| `uo --config-show` · `--config-example` | بازرسی کانفیگ مؤثر · چاپ قالب کامنت‌گذاری‌شده (v7.8) |
| `uo --config FILE` · `--no-config` | استفاده از فایل کانفیگ جایگزین · نادیده‌گرفتن کانفیگ‌ها برای یک اجرا (v7.8) |
| `uo --cache-stats` · `--cache-clear` | نمایش ورودی‌های کش + زمان باقی‌مانده · پاک‌کردن کش (v7.9) |
| `uo --no-cache` | دورزدن کش TTL برای یک اجرا (v7.9) |
| `uo --timer-install [PERIOD]` | نصب و فعال‌سازی تایمر آپدیت — hourly · daily · weekly (پیش‌فرض) · monthly (v7.10) |
| `uo --timer-remove` · `--timer-status` · `--timer-log [N]` | حذف تایمر · وضعیت · خواندن لاگ اجراها از ژورنال (v7.10) |
| `uo --timer-preview [PERIOD]` | چاپ فایل‌های unit که نصب می‌نویسد — بدون نیاز به systemd (v7.10) |
| `uo --timer-system` · `--timer-notify-only` | (با install/preview) یونیت سراسری سیستم · حالت پایش فقط-خواندنی (v7.10) |
| `uo --disk-report [FILE]` | نوشتن تحلیل دیسک به‌صورت گزارش HTML خودکفا — نمودار + جدول‌های قابلمرتب‌سازی، پیش‌فرض «uo-disk-report.html» (v7.12) |
| `uo --boot` | تحلیل زمان بوت — کل زمان + حکم، ۱۰ یونیت کندترین، زنجیرهٔ بحرانی، یونیت‌های شکست‌خورده (v7.14) |
| `uo --autostart` · `--autostart-on/off NAME` | فهرست برنامه‌های استارتاپ · فعال/غیرفعال‌کردن یکی — override بازگشت‌پذیر کاربر، بدون لمس فایل‌های سیستمی (v7.14) |
| `uo --health` | عکس سلامت سیستم فقط-خواندنی — بار، حکم حافظه، دیسک، دما، باتری، یونیت‌های خراب، آپدیت‌های در انتظار، آپ‌تایم (v7.15) |
| `uo --bigfiles [DIR]` | ۲۰ فایل حجیم یک مسیر — آستانهٔ اندازه با `UO_BIGFILES_MIN_MB` (پیش‌فرض ۱۰۰ مگابایت) (v7.15) |
| `uo --ports` | هر پورت گوش‌دهندهٔ TCP/UDP + پروسهٔ صاحب — اتصال به همهٔ اینترفیس‌ها با ⚠ علامت می‌خورد + راهنمای ufw (v7.15) |
| `uo --browser-clean` | خالی‌کردن کش‌های Chromium/فایرفاکس/تصاویر بندانگشتی — مرورگر در حال اجرا رد می‌شود، فایل‌های داده لمس نمی‌شوند (v7.15) |
| `uo --dns [PRESET]` | تعویض DNS سیستم با یک کلمه — shecan · 403online · radar · electro · cloudflare · google · quad9 · adguard · auto؛ `--dns-list` جدول فقط-خواندنی (v7.16) |
| `uo --kernel-list` · `--kernel-clean` | فهرست کرنل‌های نصب‌شده · حذف قدیمی‌ها (در حال اجرا و تازه‌ترین همیشه محفوظ، تنظیم نگه‌داشت `UO_KERNEL_KEEP`، پیش‌فرض ۲) (v7.16) |
| `uo --swap` · `--swap-on [MB]` · `--swap-off` | وضعیت swap · ساخت و فعال‌سازی `/swapfile` پیشنهادی (ورودی fstab علامت‌دار) · حذف آن — پارتیشن/zram دست‌نخورده (v7.16) |
| `uo --swappiness N` | تنظیم `vm.swappiness` (۱ تا ۱۰۰) از مسیر sysctl قابل-undo (v7.16) |
| `uo --splash` · `--fix-splash` | وضعیت اسپلش بوت (خط فرمان کرنل، پیکربندی GRUB، پلیموث) · بازگرداندن اسپلش گرافیکی: نصب دوبارهٔ `/etc/default/grub` گم‌شده (`--force-confmiss`، فال‌بک دست‌نویس) یا افزودن دوبارهٔ `quiet splash` با بکاپ زمان‌دار و بعد `update-grub` — دراپ‌این‌های kdump/فروشنده لمس نمی‌شوند (v7.18) |
| `uo --fzf` | راه‌انداز تعاملی fzf روی همهٔ اقدام‌ها — Enter=اجرا، Esc=انصراف؛ `UO_FZF_BIN` برای مسیر دلخواه (v7.17) |
| `uo --lang fa\|en` | ذخیرهٔ زبان رابط؛ `--lang-show` زبان فعلی + منبعش را چاپ می‌کند (v7.17) |
| `uo --doctor` | بررسی سلامت و تعمیر همهٔ برنامه‌های نصب‌شده/ردیابی‌شده |
| `uo --github-install OWNER/REPO [NAME]` | نصب برنامه از آخرین ریلیز GitHub |
| `uo --github-update` · `--github-list` · `--github-remove` | به‌روزرسانی · فهرست · حذف برنامه‌های GitHub |
| `uo --install-targz FILE [NAME]` | نصب هوشمند از فایل tar.gz (نام خودکار پیدا می‌شود) |
| `uo --cleanup NAME` (`--purge-data`) | حذف کامل یک برنامه از هر منبعی |
| `uo --update` · `--update-apt/snap/flatpak/targz` | به‌روزرسانی همه یا یک منبع |
| `uo --list-apps` · `--snap-clean` | فهرست برنامه‌ها · پاک‌سازی نسخه‌های قدیمی snap |
| `uo --fixnet` · `--fixnet-run` · `--test` | ساخت · اجرای fixnet · تست‌های شبکه |
| `uo --git-ssh` · `--git-ssh-status` | ویزارد کلید SSH گیت‌هاب · وضعیت |
| `uo --log` · `--log-clear` | نمایش · حذف گزارش فعالیت |
| `uo -y` · `--no-color` · `--no-log` | تأیید خودکار · خروجی ساده · ثبت‌نکردن گزارش |

### مثال‌های واقعی

```bash
uo --optimize                                    # بعد از یک نصب تازهٔ اوبونتو
uo --optimize --dry-run -y                       # احتیاط دارید؟ اول همهٔ دستورات را ببینید
uo --update -y                                   # همه‌چیز را بدون هیچ سؤالی به‌روز کن
uo --install-targz ~/Downloads/app.tar.gz myapp  # نصب از آرشیو
uo --github-install junegunn/fzf                 # نصب از ریلیز GitHub
uo --cleanup abdownloadmanager --purge-data -y   # حذف یک برنامه بدون هیچ ردی
uo --doctor                                      # بررسی سلامت و تعمیر برنامه‌ها
uo --health                                      # بار · حافظه · دیسک · دما · باتری · یونیت‌های خراب
uo --bigfiles ~                                  # فایلم کجا رفته؟ ۲۰ فایل حجیم
uo --ports                                       # چه کسی گوش می‌دهد — و چه چیزی باز است
uo --browser-clean                               # خالی‌کردن کش مرورگرها (داده‌ها دست‌نخورده)
uo --dns shecan                                  # تعویض DNS به رزولور عبور از تحریم
uo --dns auto                                    # …و برگشت به DHCP
uo --kernel-clean                                # خالی‌کردن /boot: حذف کرنل‌های قدیمی
uo --swap-on 4096                                # ساخت swapfile چهار گیگابایتی
uo --swappiness 10                               # نقطهٔ طلای دسکتاپ
```

---

## 🧠 چرا هوشمند به نظر می‌رسد؟

<details open>
<summary><b>نصب هوشمند tar.gz</b> — مراحل کار</summary>

1. آرشیو باز می‌شود و **فایل اجرایی اصلی تشخیص داده می‌شود** (اولویت: AppImage → تطابق نام → تنها گزینه → انتخاب دستی) — فایل‌های کمکی Electron/JVM مثل `chrome_crashpad_handler` و `jspawnhelper` خودکار نادیده گرفته می‌شوند
2. **معماری بسته** با سیستم شما مقایسه می‌شود — دانلودهای اشتباه (مثلاً arm64 روی x86_64) *قبل از نصب* شناسایی می‌شوند
3. **وابستگی‌های غایب** با `ldd` پیدا و خودکار نصب می‌شوند
4. برنامه در `/opt/<name>` با میان‌بر ترمینال و فایل `.desktop` استاندارد نصب می‌شود
5. در **رجیستری** ثبت می‌شود — تا به‌روزرسانی‌ها آن را پیدا کنند و حذف، همهٔ ردها را پاک کند

</details>

<details>
<summary><b>حذف کامل</b> — هر منبعی، هر ردی</summary>

همهٔ منابع جست‌وجو می‌شوند: رجیستری، apt (دقیق و فازی)، snap، flatpak، پوشه‌های `/opt` و فایل‌های desktop. مالکیت deb پوشه‌های `/opt` (مثل Obsidian) تشخیص داده می‌شود تا حذف از **مسیر درست** (apt) انجام شود. با `--purge-data` پوشه‌های داده/پیکربندی کاربر هم حذف می‌شوند — پوشه‌های پایه مثل `~/.config` هرگز پیشنهاد نمی‌شوند.

</details>

<details>
<summary><b>داکتر (Doctor)</b> — معاینهٔ سلامت هر چیزی که این ابزار نصب کرده</summary>

`uo --doctor` همهٔ برنامه‌های ردیابی‌شده را بررسی می‌کند: وجود فایل‌ها، فرمت و مجوزهای باینری، سالم‌بودن symlinkها، درستی desktop entry (شامل wrapper ترمینال) و بارگذاری‌شدن وابستگی‌ها — و هرچه بتواند تعمیر می‌کند.

</details>

---

## 🛡 ایمنی در اولویت است

این ابزار تنظیمات سیستم را تغییر می‌دهد — برای همین طوری ساخته شده که **قابل بازگشت و صادق** باشد:

- 🔍 **پیش‌نمایش dry-run** — دستور `uo --optimize --dry-run` *هر دستوری* را که قرار است اجرا شود چاپ می‌کند. همان چیزی که می‌بینید، دقیقاً همان است که اجرا می‌شود.
- 💾 **پشتیبان‌گیری خودکار** — قبل از ویرایش noatime از `/etc/fstab.bak` ساخته می‌شود؛ ویرایش‌های sudoers در فایلی جداگانه با `visudo -c -f` اعتبارسنجی و در صورت خطا خودکار حذف می‌شوند.
- ⚠️ **هشدار قبل از تغییرات پرخطر** — غیرفعال‌کردن avahi-daemon چاپگرهای شبکه (mDNS) را می‌شکند؛ قاعدهٔ polkit امنیت را کمی پایین می‌آورد؛ تغییر DNS اتصال را قطع می‌کند (**روی SSH اجرا نکنید**) — همه از قبل اعلام می‌شوند.
- 🧹 **نام‌های پاک‌سازی‌شده** — نام برنامه‌ها قبل از هر عملیاتی sanitize می‌شوند؛ مسیرهای حساس (`/`، `/opt`، `$HOME`…) از حذف مسدودند.
- ✅ **تأیید به‌صورت پیش‌فرض** — عملیات‌های مخرب همیشه سؤال می‌کنند (مگر با `-y`).
- 📖 **حالت فقط-خواندنی** — `--report` و `--disk` هیچ چیزی را تغییر نمی‌دهند.

<details>
<summary><b>↩️ بازگرداندن تغییرات</b> — یک دستور، یا هر فایل به‌صورت دستی</summary>

**راه آسان — نسخهٔ 7.2 به بعد:**

```bash
uo --undo                 # برنامهٔ تغییرات را نشان می‌دهد، تأیید می‌گیرد و برمی‌گرداند:
                          # فایل‌های drop-in، پشتیبان fstab، سرویس‌های غیرفعال‌شده و
                          # تنظیمات DNS / مدیریت انرژی وای‌فای
uo --undo --dry-run -y    # اول پیش‌نمایش برنامهٔ تغییرات
```

**راه دستی (همهٔ نسخه‌ها):**

```bash
# پارامترهای کرنل/شبکه (BBR، swappiness، TCP و…)
sudo rm /etc/sysctl.d/99-ubuntu-optimizer.conf && sudo sysctl --system

# fstab (noatime) — بازگرداندن پشتیبان خودکار
sudo cp /etc/fstab.bak /etc/fstab

# محدودیت حجم ژورنال
sudo rm /etc/systemd/journald.conf.d/99-optimizer.conf

# timeout سودو / قاعدهٔ polkit
sudo rm /etc/sudoers.d/99-optimizer-timeout
sudo rm /etc/polkit-1/rules.d/10-disable-password-timeout.rules

# فعال‌سازی مجدد سرویس‌های اختیاری
sudo systemctl enable --now cups-browsed whoopsie avahi-daemon

# سپس یک‌بار ریبوت (یا remount /) برای تغییر fstab.
```

DNS و MTU تنظیمات سطح اتصال (NetworkManager) هستند — از تنظیمات شبکه برگردانید یا گزینهٔ منو را دوباره با مقادیر دلخواه اجرا کنید.

</details>

### 📍 فایل‌ها و مسیرهای ایجادشده یا تغییریافته

| مسیر | کاربرد |
|---|---|
| `/etc/sysctl.d/99-ubuntu-optimizer.conf` | پارامترهای کرنل (BBR، swappiness و…) |
| `/etc/systemd/journald.conf.d/99-optimizer.conf` | محدودیت حجم ژورنال |
| `/etc/sudoers.d/99-optimizer-timeout` | timeout سودو (۱۲۰ دقیقه) |
| `/etc/polkit-1/rules.d/10-disable-password-timeout.rules` | قاعدهٔ polkit (فقط با رضایت کاربر) |
| `/opt/<name>` | محل نصب برنامه‌های tar.gz |
| `~/.local/share/ubuntu-optimizer/apps.db` | رجیستری برنامه‌های tar.gz |
| `~/.local/share/ubuntu-optimizer/github.db` | بانک اطلاعاتی برنامه‌های GitHub |
| `~/.local/state/ubuntu-optimizer/optimizer.log` | گزارش فعالیت |
| `~/fix-network.sh` | اسکریپت fixnet + alias پوسته |
| `~/.local/bin/uo` | میان‌بر اجرا |

---

## 🐙 توکن اختیاری: GitHub API

دستورات `--github-update` و `--github-install` از GitHub API استفاده می‌کنند که محدود به
**۶۰ درخواست در ساعت برای هر IP** است — سهمی که بین همهٔ کاربران پشت NAT ارائه‌دهندهٔ اینترنت شما تقسیم می‌شود.
یک توکن شخصی این سقف را به **۵٬۰۰۰ در ساعت** می‌رساند:

1. یک توکن کلاسیک فقط-خواندنی بسازید: github.com → Settings → Developer settings →
   Personal access tokens → *Generate new token (classic)* — **بدون نیاز به هیچ اسکوپی**.
2. آن را به پوستهٔ خود اضافه کنید:

```bash
echo 'export GH_TOKEN="ghp_your_token"' >> ~/.bashrc
source ~/.bashrc
```

هر دو متغیر `GH_TOKEN` و `GITHUB_TOKEN` پشتیبانی می‌شوند. توکن فقط به `api.github.com`
ارسال می‌شود و هرگز در گزارش ثبت نمی‌شود.

---

## 🌐 اختیاری: سرورهای DNS سفارشی

بهینه‌سازی شبکه (`--network` و `--optimize`) به‌طور پیش‌فرض DNS را روی
`8.8.8.8` و `1.1.1.1` تنظیم می‌کند. اگر ISP یا منطقهٔ شما با این سرورها مشکل دارد،
می‌توانید سرورهای دلخواه خودتان را تعیین کنید:

```bash
echo 'export UO_DNS_SERVERS="1.1.1.1 9.9.9.9"' >> ~/.bashrc
source ~/.bashrc
```

- فقط **آدرس‌های IPv4** جدا شده با فاصله؛ مقدار نامعتبر قبل از هر تغییری رد می‌شود.
- اسکریپت تعمیر شبکه (`fixnet`) هم از همین متغیر استفاده می‌کند (هم در پیش‌نمایش و هم در resolv.conf پشتیبان).

---

## ⚙ اختیاری: فایل کانفیگ

فلگ‌های تکراری جایشان در فایل است. فایل `~/.config/uo/config.conf` را بسازید تا هر اجرا — تعاملی یا کرون — تنظیمات شما را خودکار اعمال کند:

```bash
uo --config-example > ~/.config/uo/config.conf   # از قالب کامنت‌گذاری‌شده شروع کنید
nano ~/.config/uo/config.conf
uo --config-show                                 # بررسی کانفیگ مؤثر
```

```ini
# ~/.config/uo/config.conf — یک ماشین کرونی غیرتعاملی
ASSUME_YES=1
NO_LOG=0
DRY_RUN=0
DNS_SERVERS="1.1.1.1 9.9.9.9"
```

- **کلیدهای پشتیبانی‌شده:** `ASSUME_YES`، `NO_COLOR`، `NO_LOG`، `DRY_RUN`،
  `DNS_SERVERS` — هر مقدار اعتبارسنجی می‌شود؛ کلیدهای ناشناخته و خطوط بدفرم
  گزارش و رد می‌شوند، هرگز مرگبار نیستند.
- **پارس عمداً محتاطانه است:** فایل هرگز `source` یا `eval` نمی‌شود — فقط
  خطوط `KEY=VALUE` خوانده می‌شوند (کامنت و گیومه اختیاری مجاز است)، پس یک
  فایل کانفیگ هرگز نمی‌تواند فرمانی اجرا کند.
- **اولویت:** پیش‌فرض‌های داخلی < فایل کانفیگ < محیط (`UO_DNS_SERVERS`، `UO_NO_CACHE`)
  < فلگ‌های صریح CLI (`-y`، `--dry-run`، `--no-color`، `--no-log`).
- **کنترل برای هر اجرا:** `uo --config FILE` فایل جایگزین را استفاده می‌کند،
  `--no-config` همهٔ کانفیگ‌ها را برای یک اجرا نادیده می‌گیرد، `--config-show`
  کانفیگ مؤثر را با منبع هر مقدار چاپ می‌کند.

---

## ⏰ آپدیت‌های زمان‌بندی‌شده (تایمر systemd)

یک‌بار تایمر را بسازید و یادآوری آپدیت‌کردن را فراموش کنید — ابزار خودش طبق
برنامه کار را انجام می‌دهد (v7.10):

```bash
uo --timer-install weekly            # هفتگی «uo --update -y --no-color» بی‌سؤال
uo --timer-install daily             # hourly · daily · weekly · monthly
uo --timer-preview weekly            # دیدن فایل‌های unit، بدون نصب چیزی
uo --timer-status                    # نصب است؟ فعال است؟ اجرای بعدی کِی؟
```

- **بدون سینتکس کرون، بدون روت:** تایمر پیش‌فرض در `~/.config/systemd/user`
  (دامنهٔ کاربر) ساخته می‌شود. برای سرورهای بدون کاربر لاگین‌شده از
  `--timer-system` استفاده کنید — یونیت‌ها با sudo در `/etc/systemd/system`
  نوشته می‌شوند.
- **اجرای ازدست‌رفته جبران می‌شود:** `Persistent=true` بعد از خاموشی یا
  تعلیق سیستم به آن می‌رسد و `RandomizedDelaySec=15m` مودبانه بار را روی
  آینه‌ها پخش می‌کند.
- **حالت پایش** (`--timer-notify-only`) هیچ چیزی را تغییر نمی‌دهد: طبق
  برنامه، یک اسنپ‌شات فقط-خواندنی از گزارش JSON به
  `~/.local/share/ubuntu-optimizer/report-log.jsonl` اضافه می‌کند — همان
  سری‌زمانی که تب «روندها» داشبورد رسم می‌کشد — و فقط وقتی چیزی به توجه
  نیاز دارد اعلان می‌دهد.
- **چرخهٔ کامل:** `--timer-log 100` لاگ اجراهای گذشته از ژورنال می‌خواند و
  `--timer-remove` همه‌چیز را پاک می‌کند. واژه‌های تقویم whitelist هستند و
  یونیت‌ها از قالب‌های ایستا ساخته می‌شوند — هیچ ورودی‌ای نمی‌تواند وارد
  فایل unit شود.

---

## 🖥 گزارش دیسک (HTML)

تحلیل ترمینالی برای یک نگاه کافی است — برای پوشه‌های سنگین، کل تصویر را به‌صورت
یک صفحهٔ خودکفا به اشتراک بگذارید (v7.12):

```bash
uo --disk-report                     # → ./uo-disk-report.html
uo --disk-report ~/disk.html         # یا هر مسیری که بخواهید
```

نمودار، شدت مصرف رنگی و جدول‌های قابلمرتب‌سازی برای برنامه‌های `/opt` و بسته‌های
deb — بدون CDN، بدون فریمورک، آفلاین در هر مرورگری باز می‌شود.

## 📁 ساختار پروژه

```
ubuntu-optimizer/
├── ubuntu-optimizer.sh        ← تنها فایلی که اجرا می‌کنید (CLI + منو)
├── install.sh                 ← نصب / به‌روزرسانی / حذف خود ابزار
├── completions/uo             ← تکمیل خودکار bash برای دستور uo
├── docs/                      ← لوگو و تصاویر README (SVG)
├── lib/
│   ├── common.sh              ← رنگ‌ها، توابع کمکی، رجیستری، گزارش‌گیری
│   ├── cache.sh               ← کش TTL برای عملیات‌های پرهزینه
│   ├── timer.sh               ← تایمر systemd: آپدیت زمان‌بندی‌شده / تیک پایش
│   ├── htmlreport.sh          ← گزارش HTML خودکفای دیسک («--disk-report»)
│   ├── network.sh             ← بهینه‌سازی و تست‌های شبکه
│   ├── system.sh              ← سیستم، حافظه، امنیت، زمان
│   ├── fixnet.sh              ← ساخت و اجرای اسکریپت دوزبانهٔ fixnet
│   ├── packages.sh            ← نصب بسته‌های deb و ابزارها
│   ├── targz.sh               ← نصب‌کنندهٔ هوشمند tar.gz + AppImage
│   ├── github.sh              ← نصب/به‌روزرسانی از GitHub Releases
│   ├── appmgmt.sh             ← حذف کامل برنامه‌ها از همهٔ منابع
│   ├── snapflatpak.sh         ← مدیریت snap/flatpak و به‌روزرسانی‌ها
│   ├── recovery.sh            ← بازیابی سیستم + ابزارهای پیشرفته
│   ├── undo.sh                ← برگرداندن همهٔ بهینه‌سازی‌ها با یک دستور
│   ├── profile.sh             ← پیش‌تنظیم‌های منتخب: laptop / server / gaming / minimal
│   ├── selfupdate.sh          ← ‪--self-update‬: بررسی نسخه + به‌روزرسانی git/آرشیو
│   ├── boot.sh                ← ‪--boot‬: زمان بوت + کندترین یونیت‌ها
│   ├── autostart.sh           ← ‪--autostart‬: مدیریت استارتاپ‌های XDG
│   ├── health.sh              ← ‪--health‬: عکس سلامت فقط-خواندنی
│   ├── bigfiles.sh            ← ‪--bigfiles‬: حجیم‌ترین فایل‌های یک مسیر
│   ├── ports.sh               ← ‪--ports‬: پورت‌های گوش‌دهنده + پرچم‌های خطر
│   ├── browserclean.sh        ← ‪--browser-clean‬: پاک‌سازی کش مرورگر
│   ├── dnsswitch.sh           ← ‪--dns‬: سوییچر پریست (شکن … adguard · auto)
│   ├── kernels.sh             ← ‪--kernel-list / --kernel-clean‬: پاک‌سازی کرنل قدیمی
│   ├── swap.sh                ← خانوادهٔ ‪--swap‬: مدیر swapfile + swappiness
│   ├── report.sh              ← گزارش وضعیت سیستم
│   ├── jsonreport.sh          ← همان گزارش در قالب یک سند JSON
│   ├── doctor.sh              ← بررسی سلامت و تعمیر برنامه‌ها
│   ├── disk.sh                ← تحلیل فضای دیسک و پاک‌سازی
│   ├── gitssh.sh              ← راه‌اندازی SSH گیت‌هاب
│   └── menus.sh               ← موتور منو و همهٔ منوها
├── test/                      ← تست‌های واحد bats (common، appmgmt، github، undo، profile، jsonreport، selfupdate، reportfile، config، cache، timer، htmlreport، boot، autostart، health، bigfiles، ports، browserclean، dnsswitch، kernels، swap، syntax)
├── completions/               ← uo (bash) · ‪_uo‬ (zsh) — تکمیل تب برای همهٔ فلگ‌ها
├── .github/workflows/
│   ├── lint.yml               ← CI: shellcheck + syntax + bats در هر push
│   └── website.yml            ← CI: build و انتشار وب‌سایت روی GitHub Pages
├── website/                   ← سایت دوزبانه (Next.js 16) → GitHub Pages
├── README.md · README.fa.md · CHANGELOG.md · CONTRIBUTING.md · SECURITY.md · LICENSE
└── .shellcheckrc              ← پیکربندی lint پروژه
```

> فایل‌های `lib/` را مستقیم اجرا نکنید — همیشه از طریق `ubuntu-optimizer.sh` (یا `uo`) کار کنید.

---

## 🧪 مثل یک محصول واقعی تست می‌شود

| گیت کیفیت | وضعیت |
|---|---|
| بررسی سینتکس `bash -n` | ✅ هر ۳۵ فایل شل |
| ShellCheck (سخت‌گیرانه) | ✅ صفر ایراد — در CI اجباری است |
| تست‌های واحد bats | ✅ ۳۶۲ از ۳۶۲ پاس |
| `install.sh --check` | ✅ خودارزیابی سلامت داخلی |
| GitHub Actions CI | ✅ روی هر push و pull request |

اجرای کامل گیت‌های کیفیت به‌صورت محلی:

```bash
sudo apt install shellcheck bats   # یک‌بار
bats test/
shellcheck -x ubuntu-optimizer.sh install.sh lib/*.sh
bash install.sh --check
```

---

## ❓ سؤالات متداول

<details>
<summary><b>اجرای آن ایمن است؟</b></summary>

هر بهینه‌سازی در یک **فایل مستقل قابل‌حذف** نوشته می‌شود، نه در تنظیمات اصلی سیستم. پشتیبان‌ها خودکار ساخته می‌شوند (`fstab.bak`)، ویرایش‌های sudoers قبل از فعال‌شدن اعتبارسنجی می‌شوند، عملیات‌های پرخطر هشدار و تأیید می‌خواهند و `--dry-run` *دقیقاً* نشان می‌دهد چه اتفاقی قرار است بیفتد. بخش [ایمنی در اولویت است](#-ایمنی-در-اولویت-است) را ببینید.

</details>

<details>
<summary><b>کدام توزیع‌ها پشتیبانی می‌شوند؟</b></summary>

برای اوبونتو (۲۰٫۰۴ به بالا) طراحی و تست شده است. سایر توزیع‌های خانوادهٔ Debian معمولاً کار می‌کنند — قابلیت‌های شبکه به NetworkManager (`nmcli`) نیاز دارند که در نصب‌های دسکتاپ استاندارد است.

</details>

<details>
<summary><b>می‌توانم همه‌چیز را برگردانم؟</b></summary>

بله — بخش [بازگرداندن تغییرات](#️-بازگرداندن-تغییرات) را ببینید. هر فایلی که ابزار می‌سازد در [فایل‌ها و مسیرها](#-فایل-ها-و-مسیرهای-ایجادشده-یا-تغییریافته) فهرست شده؛ آن‌ها را حذف و ریبوت کنید.

</details>

<details>
<summary><b>چرا دربارهٔ SSH هشدار می‌دهد؟</b></summary>

مراحل DNS و صرفه‌جویی انرژی Wi-Fi اتصال شبکه را ری‌استارت می‌کنند. اگر با SSH به ماشین وصل باشید، نشست شما قطع می‌شود. ابزار این را تشخیص داده و قبل از اجرا هشدار می‌دهد.

</details>

<details>
<summary><b>آیا به اینترنت نیاز دارد؟</b></summary>

فقط برای نصب/به‌روزرسانی بسته‌ها و تست‌های شبکه. همهٔ بهینه‌سازی‌ها، گزارش‌ها، تحلیل دیسک و مدیریت برنامه‌ها آفلاین کار می‌کنند.

</details>

<details>
<summary><b>English version?</b></summary>

Yes! The full English documentation lives here: [README.md](README.md). fixnet is bilingual at runtime (English/Persian, auto-detected).

</details>

<details>
<summary><b>تازگی‌های نسخهٔ ۷٫۰؟</b></summary>

- لایسنس MIT + زیرساخت کامل مخزن: CI، قالب‌های issue/PR، سیاست مشارکت و امنیت
- توابع پراستفاده حدود ۱۰۰ برابر سریع‌تر (`normalize_name` و دوستانش — بدون پروسهٔ اضافه)
- پیش‌نمایش‌های dry-run صادقانه (خداحافظ موفقیت‌های ساختگی!)
- دستورهای جدید `--doctor`، `--disk` و `--disk-clean` · قابلیت دیسک در منو
- ۶ تست bats جدید · ShellCheck تمیز در کل پروژه

تاریخچهٔ کامل: [CHANGELOG.md](CHANGELOG.md)

</details>

---

## 🗺 نقشه راه

- [x] CI با GitHub Actions (shellcheck + syntax + bats)
- [x] پشتیبانی از توکن GitHub API (`GH_TOKEN` / `GITHUB_TOKEN`)
- [x] تکمیل خودکار bash برای گزینه‌های CLI
- [x] تست‌های خودکار (bats) برای `lib/common.sh`
- [x] حالت `--dry-run`
- [x] نسخهٔ ۷٫۰: زیرساخت مخزن (لایسنس، CI، قالب‌ها، تاریخچه تغییرات)
- [ ] تکمیل خودکار zsh
- [ ] پوشش bats برای همهٔ ماژول‌های `lib/`
- [ ] چارچوب ترجمه (fa / زبان‌های بیشتر)

---

## 🤝 مشارکت · 🔒 گزارش ایراد

- باگ پیدا کردید یا ایده‌ای دارید؟ [یک issue باز کنید](https://github.com/CheginiSoroush/ubuntu-optimizer/issues) — قالب‌های آماده در اختیار شماست
- می‌خواهید روی ابزار کار کنید؟ [CONTRIBUTING.md](CONTRIBUTING.md) راهنمای کامل راه‌اندازی، قوانین و چک‌لیست PR است
- نگرانی‌های امنیتی: [SECURITY.md](SECURITY.md) را ببینید — برای این‌ها issue عمومی باز **نکنید**
- تاریخچهٔ همهٔ نسخه‌ها: [CHANGELOG.md](CHANGELOG.md)

---

<div align="center">

## 👤 نویسنده

**سروش چگینی** · [@CheginiSoroush](https://github.com/CheginiSoroush)

<a href="https://github.com/CheginiSoroush">
  <img src="https://github.com/CheginiSoroush.png" width="90" alt="CheginiSoroush" style="border-radius:50%"/>
</a>

<br/>

اگر `uo` اوبونتوی شما را سریع‌تر و تمیزتر کرد، یک ⭐ بهترین تشویق است!

[![Stargazers](https://img.shields.io/github/stars/CheginiSoroush/ubuntu-optimizer?style=social)](https://github.com/CheginiSoroush/ubuntu-optimizer/stargazers)
[![Forks](https://img.shields.io/github/forks/CheginiSoroush/ubuntu-optimizer?style=social)](https://github.com/CheginiSoroush/ubuntu-optimizer/network/members)

<br/>

با ❤️ و Bash خالص ساخته شده · [MIT](LICENSE) © Soroush Chegini

</div>
