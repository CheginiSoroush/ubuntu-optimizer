# shellcheck shell=bash
# ============================================================
#   lib/fixnet.sh — create and run the fixnet script (bilingual)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
# ============================================================

create_fixnet_script() {
    header "Create the fixnet script (bilingual)"

    cat << 'FIXNET_EOF' > "$HOME/fix-network.sh"
#!/bin/bash
# Fix Network Script v2.2 — bilingual
# Fixes network issues after disconnecting a VPN

# Auto-detect system language
case "${LANGUAGE:-${LANG:-en}}" in
    fa*) LNG="fa" ;;
    *)   LNG="en" ;;
esac

# ---------- Messages ----------
if [ "$LNG" = "en" ]; then
    MSG_START="Starting network repair process..."
    MSG_DONE="Network repair completed!"
    MSG_REMOVE_TUN="Removing leftover TUN interfaces..."
    MSG_TUN_CHECK="TUN interface check completed"
    MSG_DISABLE_PROXY="Disabling system proxy..."
    MSG_PROXY_DISABLED="GNOME proxy disabled"
    MSG_CLEAR_ENV="Clearing proxy environment variables..."
    MSG_ENV_CLEARED="Proxy environment variables cleared"
    MSG_PROXY_STILL_SET="Proxy variables still set in your shell — open a new terminal (remove them from ~/.bashrc if defined there)"
    MSG_RESTART_NM="Restarting NetworkManager..."
    MSG_NM_RESTARTED="NetworkManager restarted"
    MSG_SET_DNS="Setting DNS to 8.8.8.8 and 1.1.1.1..."
    MSG_DNS_SET="DNS configured"
    MSG_FLUSH_DNS="Flushing DNS cache..."
    MSG_DNS_FLUSHED="DNS cache flushed"
    MSG_DNS_NOT_SUPPORTED="DNS cache management not supported"
    MSG_TESTING="Testing internet connection (multiple attempts)..."
    MSG_WAITING="Waiting for the network to come back (may take up to ~30s)..."
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
    MSG_ENV_CLEARED="متغیرهای پروکسی پاک شد"
    MSG_PROXY_STILL_SET="متغیرهای پروکسی هنوز در شل شما فعال‌اند — ترمینال جدید باز کنید (اگر در ~/.bashrc تعریف شده‌اند حذفشان کنید)"
    MSG_RESTART_NM="ری‌استارت NetworkManager..."
    MSG_NM_RESTARTED="NetworkManager ری‌استارت شد"
    MSG_SET_DNS="تنظیم DNS روی 8.8.8.8 و 1.1.1.1..."
    MSG_DNS_SET="DNS تنظیم شد"
    MSG_FLUSH_DNS="فلش کش DNS..."
    MSG_DNS_FLUSHED="کش DNS فلش شد"
    MSG_DNS_NOT_SUPPORTED="سرویس DNS مدیریت کش پشتیبانی نمی‌شود"
    MSG_TESTING="تست اتصال به اینترنت (چند بار تلاش)..."
    MSG_WAITING="منتظر بازگشت شبکه (ممکن است تا ~۳۰ ثانیه طول بکشد)..."
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

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   $MSG_START${NC}"
echo -e "${BLUE}========================================${NC}"

# 1) Remove leftover TUN interfaces from the VPN
echo -e "${YELLOW}[1/7] $MSG_REMOVE_TUN${NC}"
for iface in $(ip -o link show 2>/dev/null | awk -F': ' '$2 ~ /^tun[0-9]+$/ {print $2}'); do
    sudo ip link delete "$iface" 2>/dev/null && echo -e "${GREEN}✓ $iface $MSG_REMOVED${NC}"
done
echo -e "${GREEN}✓ $MSG_TUN_CHECK${NC}"

# 2) Disable the system proxy
echo -e "${YELLOW}[2/7] $MSG_DISABLE_PROXY${NC}"
gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null && echo -e "${GREEN}✓ $MSG_PROXY_DISABLED${NC}"

# 3) Clear proxy environment variables
#    The user's shell variables cannot be changed from inside this script — warn if any are set
echo -e "${YELLOW}[3/7] $MSG_CLEAR_ENV${NC}"
found=""
for v in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY; do
    if [ -n "${!v}" ]; then
        found="$found $v"
        unset "$v"
    fi
done
unset no_proxy NO_PROXY
if [ -n "$found" ]; then
    echo -e "${YELLOW}⚠ $MSG_PROXY_STILL_SET:$found${NC}"
else
    echo -e "${GREEN}✓ $MSG_ENV_CLEARED${NC}"
fi

# 4) Restart NetworkManager
echo -e "${YELLOW}[4/7] $MSG_RESTART_NM${NC}"
sudo systemctl daemon-reload
sudo systemctl restart NetworkManager
echo -e "${GREEN}✓ $MSG_NM_RESTARTED${NC}"

# 5) Set DNS
echo -e "${YELLOW}[5/7] $MSG_SET_DNS${NC}"
if command -v resolvectl &> /dev/null; then
    # systemd-resolved active — restore the standard symlink if the VPN replaced it with a regular file
    [ -L /etc/resolv.conf ] || sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    sudo resolvectl flush-caches 2>/dev/null
    echo -e "${GREEN}✓ $MSG_DNS_SET${NC}"
else
    sudo bash -c 'printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /etc/resolv.conf'
    echo -e "${GREEN}✓ $MSG_DNS_SET${NC}"
fi

# 6) Flush the DNS cache
echo -e "${YELLOW}[6/7] $MSG_FLUSH_DNS${NC}"
if command -v resolvectl &> /dev/null; then
    sudo resolvectl flush-caches 2>/dev/null && echo -e "${GREEN}✓ $MSG_DNS_FLUSHED${NC}"
elif command -v systemd-resolve &> /dev/null; then
    sudo systemd-resolve --flush-caches 2>/dev/null && echo -e "${GREEN}✓ $MSG_DNS_FLUSHED${NC}"
else
    echo -e "${YELLOW}⚠ $MSG_DNS_NOT_SUPPORTED${NC}"
fi

# 7) Connectivity test with retries
echo -e "${YELLOW}[7/7] $MSG_TESTING${NC}"
echo -e "${YELLOW}⏳ $MSG_WAITING${NC}"
# After an NM restart Wi-Fi may take tens of seconds to reconnect —
# wait for the default route to come back instead of a blind sleep
n=0
until ip route show default 2>/dev/null | grep -q .; do
    n=$((n + 1))
    [ "$n" -ge 30 ] && break
    sleep 1
done
sleep 3

RETRY_COUNT=5
SUCCESS=0

for i in $(seq 1 $RETRY_COUNT); do
    echo -e "${YELLOW}$MSG_ATTEMPT $i $MSG_OF $RETRY_COUNT...${NC}"
    # -W: reply timeout — avoids hanging on an unresponsive network; fallback to 1.1.1.1
    if ping -c 2 -W 3 8.8.8.8 &> /dev/null || ping -c 2 -W 3 1.1.1.1 &> /dev/null; then
        SUCCESS=1
        echo -e "${GREEN}✓ $MSG_SUCCESS${NC}"
        PING_AVG=$(ping -c 4 -W 3 8.8.8.8 | tail -1 | awk -F '/' '{print $5}')
        echo -e "${GREEN}$MSG_AVG_PING: ${PING_AVG} ms${NC}"
        break
    else
        if [ "$i" -lt "$RETRY_COUNT" ]; then
            echo -e "${YELLOW}⚠ $MSG_RETRY${NC}"
            sleep 2
        fi
    fi
done

echo -e "${BLUE}========================================${NC}"
if [ "$SUCCESS" = "1" ]; then
    echo -e "${GREEN}$MSG_DONE${NC}"
    echo -e "${BLUE}========================================${NC}"
    exit 0
fi

echo -e "${RED}✗ $MSG_FAILED${NC}"
echo -e "${YELLOW}$MSG_RETRY_MODEM${NC}"
echo -e "${YELLOW}$MSG_RETRY_SCRIPT${NC}"
echo -e "${BLUE}========================================${NC}"
exit 1
FIXNET_EOF

    chmod +x "$HOME/fix-network.sh"

    # gsettings must run as a regular user; that is why the alias has no sudo
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] || continue
        if ! grep -q "alias fixnet=" "$rc"; then
            # shellcheck disable=SC2016  # intentional: $HOME expands when the rc is sourced
            echo 'alias fixnet="$HOME/fix-network.sh"' >> "$rc"
        fi
    done

    success "fixnet script created: ~/fix-network.sh"
    info "The 'fixnet' command was added to the shell."
    info "To activate: open a new terminal or run: source ~/.bashrc"
    return 0
}

run_fixnet() {
    if [ -x "$HOME/fix-network.sh" ]; then
        if bash "$HOME/fix-network.sh"; then
            return 0
        fi
        failure "fixnet finished with errors (connection is still down)."
        return 1
    fi
    failure "The fixnet script has not been created yet. Run the 'Create' option first."
    return 1
}
