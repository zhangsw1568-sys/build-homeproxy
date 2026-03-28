#!/usr/bin/env bash
set -euo pipefail

SDK_URL="${SDK_URL:-https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/openwrt-sdk-25.12.0-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64.tar.zst}"
HP_REF="${HP_REF:-dev}"
WORKDIR="${WORKDIR:-/root/hpbuild}"
HTTP_PORT="${HTTP_PORT:-8080}"

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

echo "[4/8] 切换 feeds 到 GitHub 镜像"
cd "$SDKDIR"
sed -i 's#https://git.openwrt.org/openwrt/openwrt.git#https://github.com/openwrt/openwrt.git#g' feeds.conf.default || true
sed -i 's#https://git.openwrt.org/feed/packages.git#https://github.com/openwrt/packages.git#g' feeds.conf.default || true
sed -i 's#https://git.openwrt.org/feed/routing.git#https://github.com/openwrt/routing.git#g' feeds.conf.default || true
sed -i 's#https://git.openwrt.org/feed/telephony.git#https://github.com/openwrt/telephony.git#g' feeds.conf.default || true
sed -i 's#https://git.openwrt.org/feed/video.git#https://github.com/openwrt/video.git#g' feeds.conf.default || true
grep -q '^src-git luci ' feeds.conf.default || echo 'src-git luci https://github.com/openwrt/luci.git' >> feeds.conf.default
sed -i 's#https://git.openwrt.org/project/luci.git#https://github.com/openwrt/luci.git#g' feeds.conf.default || true

echo "[5/8] 更新 feeds"
./scripts/feeds update -a
./scripts/feeds install -a

echo "[6/8] 拉取 HomeProxy 源码并编译"
mkdir -p package
rm -rf package/luci-app-homeproxy
git clone --depth 1 --branch "$HP_REF" https://github.com/immortalwrt/homeproxy.git package/luci-app-homeproxy
sed -i 's@include ../../luci.mk@include $(TOPDIR)/feeds/luci/luci.mk@' package/luci-app-homeproxy/Makefile
make defconfig
make package/luci-app-homeproxy/compile V=s -j"$(nproc)"

echo "[7/8] 整理产物并生成本地仓库"
mkdir -p "$WORKDIR/out" "$WORKDIR/repo"
find "$SDKDIR" -type f \( -name 'luci-app-homeproxy-*.apk' -o -name 'luci-i18n-homeproxy-zh-cn-*.apk' \) -exec cp -v {} "$WORKDIR/out/" \;
cp -v "$WORKDIR"/out/*.apk "$WORKDIR/repo/"

make package/index V=s
cp -v ./bin/packages/aarch64_cortex-a53/base/packages.adb "$WORKDIR/repo/"

PUBKEY=""
for f in "$SDKDIR"/key-build.pub "$SDKDIR"/usign/*.pub "$SDKDIR"/*.pub; do
  if [ -f "$f" ]; then
    PUBKEY="$f"
    break
  fi
done

if [ -n "$PUBKEY" ]; then
  cp -v "$PUBKEY" "$WORKDIR/repo/localbuild.pub"
else
  echo "警告：没有找到公钥文件，路由器侧将无法走受信任仓库安装"
fi

echo "[8/8] 完成"
echo
echo "产物目录：$WORKDIR/out"
ls -lh "$WORKDIR/out" || true
echo
echo "仓库目录：$WORKDIR/repo"
ls -lh "$WORKDIR/repo" || true
echo
IP="$(hostname -I | awk '{print $1}')"
echo "如果你要在这台虚拟机上临时开仓库，请执行："
echo "cd $WORKDIR/repo && python3 -m http.server $HTTP_PORT"
echo
echo "路由器里可用的仓库地址："
echo "http://$IP:$HTTP_PORT/packages.adb"
if [ -f "$WORKDIR/repo/localbuild.pub" ]; then
  echo "公钥地址："
  echo "http://$IP:$HTTP_PORT/localbuild.pub"
fi
