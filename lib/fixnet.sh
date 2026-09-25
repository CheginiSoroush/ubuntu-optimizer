# ============================================================
#   lib/fixnet.sh — ساخت و اجرای اسکریپت fixnet (دو زبانه)
#   نویسنده و طراح: Soroush Chegini (CheginiSoroush)
# ============================================================

create_fixnet_script() {
    header "ساخت اسکریپت fixnet (دو زبانه)"

    cat << 'FIXNET_EOF' > "$HOME/fix-network.sh"
#!/bin/bash
# Fix Network Script v2.0 — دو زبانه
# رفع مشکلات شبکه پس از قطع VPN

# تشخیص خودکار زبان سیستم
case "${LANGUAGE:-${LANG:-en}}" in
    fa*) LNG="fa" ;;
    *)   LNG="en" ;;
esac

# ---------- پیام‌ها ----------
if [ "$LNG" = "en" ]; then
    MSG_START="Starting network repair process..."
    MSG_DONE="Network repair completed!"
    MSG_REMOVE_TUN="Removing leftover TUN interfaces..."
    MSG_TUN_CHECK="TUN interface check completed"
    MSG_DISABLE_PROXY="Disabling system proxy..."
    MSG_PROXY_DISABLED="GNOME proxy disabled"
    MSG_CLEAR_ENV="Clearing proxy environment variables..."
    MSG_ENV_CLEARED="Proxy environment variables cleared"
    MSG_RESTART_NM="Restarting NetworkManager..."
    MSG_NM_RESTARTED="NetworkManager restarted"
    MSG_SET_DNS="Setting DNS to 8.8.8.8 and 1.1.1.1..."
    MSG_DNS_SET="DNS configured"
    MSG_FLUSH_DNS="Flushing DNS cache..."
    MSG_DNS_FLUSHED="DNS cache flushed"
    MSG_DNS_NOT_SUPPORTED="DNS cache management not supported"
    MSG_TESTING="Testing internet connection (multiple attempts)..."
    MSG_WAITING="Waiting for network to stabilize (3 seconds)..."
    MSG_ATTEMPT="Attempt"
    MSG_OF="of"
    MSG_SUCCESS="Internet connection is up!"
    MSG_AVG_PING="Average ping"
    MSG_FAILED="Internet connection is not available!"
    MSG_RETRY="Connection failed, retrying in 2 seconds..."
    MSG_RETRY_MODEM="Please restart your modem or check your network connection."
    MSG_RETRY_SCRIPT="After fixing the issue, run the script again."
    MSG_REMOVED="removed"
else
    MSG_START="شروع فرآیند تعمیر شبکه..."
    MSG_DONE="فرآیند تعمیر شبکه کامل شد!"
    MSG_REMOVE_TUN="حذف اینترفیس‌های TUN باقی‌مانده..."
    MSG_TUN_CHECK="بررسی اینترفیس‌های TUN کامل شد"
    MSG_DISABLE_PROXY="غیرفعال کردن پروکسی سیستمی..."
    MSG_PROXY_DISABLED="پروکسی GNOME غیرفعال شد"
    MSG_CLEAR_ENV="پاک کردن متغیرهای پروکسی..."
    MSG_ENV_CLEARED="متغیرهای پروکسی پاک شدند"
    MSG_RESTART_NM="ری‌استارت NetworkManager..."
    MSG_NM_RESTARTED="NetworkManager ری‌استارت شد"
    MSG_SET_DNS="تنظیم DNS روی 8.8.8.8 و 1.1.1.1..."
    MSG_DNS_SET="DNS تنظیم شد"
    MSG_FLUSH_DNS="فلش کش DNS..."
    MSG_DNS_FLUSHED="کش DNS فلش شد"
    MSG_DNS_NOT_SUPPORTED="سرویس DNS مدیریت کش پشتیبانی نمی‌شود"
    MSG_TESTING="تست اتصال به اینترنت (چند بار تلاش)..."
    MSG_WAITING="منتظر بازیابی شبکه (۳ ثانیه)..."
    MSG_ATTEMPT="تلاش"
    MSG_OF="از"
    MSG_SUCCESS="اتصال به اینترنت برقرار است!"
    MSG_AVG_PING="میانگین تأخیر"
    MSG_FAILED="اتصال به اینترنت برقرار نیست!"
    MSG_RETRY="اتصال برقرار نشد، ۲ ثانیه صبر می‌کنم..."
    MSG_RETRY_MODEM="لطفاً مودم خود را ری‌استارت کنید یا اتصال شبکه را بررسی کنید."
    MSG_RETRY_SCRIPT="پس از رفع مشکل، دوباره اسکریپت را اجرا کنید."
    MSG_REMOVED="حذف شد"
fi

# ---------- رنگ‌ها ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   $MSG_START${NC}"
echo -e "${BLUE}========================================${NC}"

# ۱) حذف اینترفیس‌های TUN باقی‌مانده از VPN
echo -e "${YELLOW}[1/7] $MSG_REMOVE_TUN${NC}"
for iface in $(ip link show | grep -o 'tun[0-9]*'); do
    sudo ip link delete "$iface" 2>/dev/null && echo -e "${GREEN}✓ $iface $MSG_REMOVED${NC}"
done
echo -e "${GREEN}✓ $MSG_TUN_CHECK${NC}"

# ۲) غیرفعال کردن پروکسی سیستمی
echo -e "${YELLOW}[2/7] $MSG_DISABLE_PROXY${NC}"
gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null && echo -e "${GREEN}✓ $MSG_PROXY_DISABLED${NC}"

# ۳) پاک کردن متغیرهای محیطی پروکسی
echo -e "${YELLOW}[3/7] $MSG_CLEAR_ENV${NC}"
unset http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
export http_proxy=""
export https_proxy=""
export all_proxy=""
echo -e "${GREEN}✓ $MSG_ENV_CLEARED${NC}"

# ۴) ری‌استارت NetworkManager
echo -e "${YELLOW}[4/7] $MSG_RESTART_NM${NC}"
sudo systemctl daemon-reload
sudo systemctl restart NetworkManager
echo -e "${GREEN}✓ $MSG_NM_RESTARTED${NC}"

# ۵) تنظیم DNS
echo -e "${YELLOW}[5/7] $MSG_SET_DNS${NC}"
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo bash -c 'echo "nameserver 1.1.1.1" >> /etc/resolv.conf'
echo -e "${GREEN}✓ $MSG_DNS_SET${NC}"

# ۶) فلش کش DNS
echo -e "${YELLOW}[6/7] $MSG_FLUSH_DNS${NC}"
if command -v resolvectl &> /dev/null; then
    sudo resolvectl flush-caches 2>/dev/null && echo -e "${GREEN}✓ $MSG_DNS_FLUSHED${NC}"
elif command -v systemd-resolve &> /dev/null; then
    sudo systemd-resolve --flush-caches 2>/dev/null && echo -e "${GREEN}✓ $MSG_DNS_FLUSHED${NC}"
else
    echo -e "${YELLOW}⚠ $MSG_DNS_NOT_SUPPORTED${NC}"
fi

# ۷) تست اتصال با تلاش مجدد
echo -e "${YELLOW}[7/7] $MSG_TESTING${NC}"
echo -e "${YELLOW}⏳ $MSG_WAITING${NC}"
sleep 3

RETRY_COUNT=5
SUCCESS=0

for i in $(seq 1 $RETRY_COUNT); do
    echo -e "${YELLOW}$MSG_ATTEMPT $i $MSG_OF $RETRY_COUNT...${NC}"
    if ping -c 2 8.8.8.8 &> /dev/null; then
        SUCCESS=1
        echo -e "${GREEN}✓ $MSG_SUCCESS${NC}"
        PING_AVG=$(ping -c 4 8.8.8.8 | tail -1 | awk -F '/' '{print $5}')
        echo -e "${GREEN}$MSG_AVG_PING: ${PING_AVG} ms${NC}"
        break
    else
        if [ $i -lt $RETRY_COUNT ]; then
            echo -e "${YELLOW}⚠ $MSG_RETRY${NC}"
            sleep 2
        fi
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo -e "${RED}✗ $MSG_FAILED${NC}"
    echo -e "${YELLOW}$MSG_RETRY_MODEM${NC}"
    echo -e "${YELLOW}$MSG_RETRY_SCRIPT${NC}"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}$MSG_DONE${NC}"
echo -e "${BLUE}========================================${NC}"
