#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/root/hpbuild"
SDK_URL="https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/openwrt-sdk-25.12.0-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64.tar.zst"
HP_REF="dev"

echo "== 1/8 安装依赖 =="
apt update
apt install -y \
  build-essential flex bison g++ gawk gettext git \
  libncurses-dev libssl-dev python3 python3-setuptools \
  rsync unzip zlib1g-dev file wget ca-certificates tar zstd swig

echo "== 2/8 清理旧目录 =="
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "== 3/8 下载并解压 SDK =="
wget -O sdk.tar.zst "$SDK_URL"
tar --zstd -xf sdk.tar.zst

SDKDIR="$(find "$WORKDIR" -maxdepth 1 -type d -name 'openwrt-sdk-*Linux-x86_64' | head -n 1)"
if [ -z "${SDKDIR:-}" ]; then
  echo "没找到 SDK 目录"
  exit 1
fi

echo "SDKDIR=$SDKDIR"

echo "== 4/8 改 feeds 为 GitHub 镜像 =="
cd "$SDKDIR"
cat > feeds.conf.default <<'FEEDS'
src-git base https://github.com/openwrt/openwrt.git
src-git packages https://github.com/openwrt/packages.git
src-git routing https://github.com/openwrt/routing.git
src-git telephony https://github.com/openwrt/telephony.git
src-git video https://github.com/openwrt/video.git
src-git luci https://github.com/openwrt/luci.git
FEEDS

echo "== 5/8 更新并安装 feeds =="
./scripts/feeds update -a
./scripts/feeds install -a

echo "== 6/8 拉取 HomeProxy 源码 =="
mkdir -p package
rm -rf package/luci-app-homeproxy
git clone --depth 1 --branch "$HP_REF" https://github.com/immortalwrt/homeproxy.git package/luci-app-homeproxy

if [ ! -f package/luci-app-homeproxy/Makefile ]; then
  echo "HomeProxy Makefile 不存在"
  exit 1
fi

sed -i 's@include ../../luci.mk@include $(TOPDIR)/feeds/luci/luci.mk@' package/luci-app-homeproxy/Makefile || true

echo "== 7/8 编译 HomeProxy =="
make defconfig
make package/luci-app-homeproxy/compile V=s -j"$(nproc)"

echo "== 8/8 收集 apk 产物 =="
mkdir -p "$WORKDIR/out"
find "$SDKDIR" -type f \( -name 'luci-app-homeproxy-*.apk' -o -name 'luci-i18n-homeproxy-zh-cn-*.apk' \) -exec cp -v {} "$WORKDIR/out/" \;

echo
echo "===== 编译结果 ====="
ls -lh "$WORKDIR/out" || true
echo

echo "如果你要让 Windows 直接下载文件，执行："
echo "cp -a $WORKDIR/out /home/zsw/hpbuild/ && chown -R zsw:zsw /home/zsw/hpbuild"
echo
echo "如果你要开 HTTP 下载，执行："
echo "cd $WORKDIR/out && python3 -m http.server 8080 --bind 0.0.0.0"
