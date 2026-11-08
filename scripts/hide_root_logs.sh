#!/bin/bash
# 隐藏 KernelSU / SUSFS 写入内核日志（dmesg）的痕迹
# 由 build.yml 在「应用 SUSFS 补丁」之后调用；不触碰 KPM / CONFIG_KPM
set -u

KSU_DIR="${KSU_DIR:-${GITHUB_WORKSPACE:-$(pwd)}/KernelSU}"
KERNEL_ROOT="${KERNEL_ROOT:-$(pwd)}"
COMMON="$KERNEL_ROOT/common"
DEFCONFIG="${DEFCONFIG:-$COMMON/arch/arm64/configs/gki_defconfig}"

echo "::group::隐藏 root 相关内核日志"
echo "KSU_DIR     = $KSU_DIR"
echo "KERNEL_ROOT = $KERNEL_ROOT"

if [ -d "$KSU_DIR/kernel" ]; then
  BEFORE=$(grep -rE '\b(pr_info|pr_warn|pr_alert)\(' "$KSU_DIR/kernel" --include='*.c' --include='*.h' | wc -l)
  find "$KSU_DIR/kernel" -type f \( -name '*.c' -o -name '*.h' \) \
    -exec sed -i -E 's/\bpr_info\(/pr_debug(/g; s/\bpr_warn\(/pr_debug(/g; s/\bpr_warn_once\(/pr_debug(/g; s/\bpr_alert\(/pr_debug(/g; s/\bpr_err\(/pr_debug(/g; s/\bpr_crit\(/pr_debug(/g; s/\bpr_emerg\(/pr_debug(/g; s/\bpr_notice\(/pr_debug(/g; s/\bpr_cont\(/pr_debug(/g' {} +
  AFTER=$(grep -rE '\b(pr_info|pr_warn|pr_alert)\(' "$KSU_DIR/kernel" --include='*.c' --include='*.h' | wc -l)
  echo "KernelSU 日志调用点: $BEFORE -> $AFTER"
else
  echo "::warning title=hide_root_logs::未找到 $KSU_DIR/kernel，跳过 KernelSU 部分"
fi

KLOG="$KSU_DIR/kernel/include/klog.h"
if [ -f "$KLOG" ]; then
  sed -i -E 's|^([[:space:]]*)#define[[:space:]]+pr_fmt\(fmt\)[[:space:]]+"KernelSU: "[[:space:]]*fmt[[:space:]]*$|\1#define pr_fmt(fmt) fmt|' "$KLOG"
  echo "已处理 pr_fmt: $KLOG"
fi

SUSFS_C="$COMMON/fs/susfs.c"
if [ -f "$SUSFS_C" ]; then
  sed -i -E 's/^#[[:space:]]*ifdef[[:space:]]+CONFIG_KSU_SUSFS_ENABLE_LOG[[:space:]]*$/#if 0 \/* root logs hidden *\//' "$SUSFS_C"
  sed -i -E 's/^#[[:space:]]*if[[:space:]]+defined\(CONFIG_KSU_SUSFS_ENABLE_LOG\)[[:space:]]*$/#if 0 \/* root logs hidden *\//' "$SUSFS_C"
  echo "SUSFS 日志宏已关闭: $SUSFS_C"
else
  echo "::warning title=hide_root_logs::未找到 $SUSFS_C，跳过 SUSFS 部分"
fi

if [ -f "$DEFCONFIG" ]; then
  sed -i -E '/^CONFIG_KSU_SUSFS_ENABLE_LOG=/d' "$DEFCONFIG"
  sed -i -E '/^# CONFIG_KSU_SUSFS_ENABLE_LOG is not set$/d' "$DEFCONFIG"
  echo "已清理 defconfig 中的 CONFIG_KSU_SUSFS_ENABLE_LOG"
fi

echo "::endgroup::"
