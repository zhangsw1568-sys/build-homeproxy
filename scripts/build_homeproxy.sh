#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/root/hpbuild"
SDK_URL="https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/openwrt-sdk-25.12.0-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64.tar.zst"
HP_REF="dev"
VM_IP="192.168.87.128"
HTTP_PORT="8080"

export DEBIAN_FRONTEND=noninteractive

echo "[1/8] 安装依赖"
apt update
apt install -y build-essential flex bison g++ gawk gettext git libncurses-dev libssl-dev python3 python3-setuptools rsync unzip zlib1g-dev file wget ca-certificates tar zstd swig

echo "[2/8] 准备目录"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[3/8] 下载并解压 SDK"
wget -O sdk.tar.zst "$SDK_URL"
tar --zstd -xf sdk.tar.zst
SDKDIR="$(find "$WORKDIR" -maxdepth 1 -type d -name 'openwrt-sdk-*Linux-x86_64' | head -n 1)"
if [ -z "${SDKDIR:-}" ]; then
  echo "未找到 SDK 目录"
  exit 1
fi

echo "[4/8] 设置 feeds"
cd "$SDKDIR"
cat > feeds.conf.default <<'FEEDS'
src-git base https://github.com/openwrt/openwrt.git
src-git packages https://github.com/openwrt/packages.git
src-git routing https://github.com/openwrt/routing.git
src-git telephony https://github.com/openwrt/telephony.git
src-git video https://github.com/openwrt/video.git
src-git luci https://github.com/openwrt/luci.git
FEEDS

./scripts/feeds update -a
./scripts/feeds install -a

echo "[5/8] 拉取 HomeProxy 源码"
mkdir -p package
rm -rf package/luci-app-homeproxy
git clone --depth 1 --branch "$HP_REF" https://github.com/immortalwrt/homeproxy.git package/luci-app-homeproxy
if [ ! -f package/luci-app-homeproxy/Makefile ]; then
  echo "HomeProxy Makefile 不存在"
  exit 1
fi
sed -i 's@include ../../luci.mk@include $(TOPDIR)/feeds/luci/luci.mk@' package/luci-app-homeproxy/Makefile || true

echo "[6/8] 编译"
make defconfig
make package/luci-app-homeproxy/compile V=s -j"$(nproc)"

echo "[7/8] 整理产物"
mkdir -p "$WORKDIR/out"
APP="$(find "$SDKDIR" -type f -name 'luci-app-homeproxy-*.apk' | sort | tail -n 1)"
I18N="$(find "$SDKDIR" -type f -name 'luci-i18n-homeproxy-zh-cn-*.apk' | sort | tail -n 1)"
if [ -z "${APP:-}" ] || [ -z "${I18N:-}" ]; then
  echo "没有找到编译产物"
  exit 1
fi
cp -f "$APP" "$WORKDIR/out/luci-app-homeproxy.apk"
cp -f "$I18N" "$WORKDIR/out/luci-i18n-homeproxy-zh-cn.apk"

echo "[8/8] 启动下载服务"
pkill -f "python3 -m http.server $HTTP_PORT -d $WORKDIR/out" 2>/dev/null || true
nohup python3 -m http.server "$HTTP_PORT" -d "$WORKDIR/out" > "$WORKDIR/http.log" 2>&1 &

echo
ls -lh "$WORKDIR/out"
echo
echo "虚拟机下载地址："
echo "http://$VM_IP:$HTTP_PORT/luci-app-homeproxy.apk"
echo "http://$VM_IP:$HTTP_PORT/luci-i18n-homeproxy-zh-cn.apk"
echo
echo "路由器上安装："
echo "wget -O /tmp/luci-app-homeproxy.apk http://$VM_IP:$HTTP_PORT/luci-app-homeproxy.apk"
echo "wget -O /tmp/luci-i18n-homeproxy-zh-cn.apk http://$VM_IP:$HTTP_PORT/luci-i18n-homeproxy-zh-cn.apk"
echo "apk add --allow-untrusted /tmp/luci-app-homeproxy.apk /tmp/luci-i18n-homeproxy-zh-cn.apk"
