#!/bin/bash
# 隐藏 KernelSU / SUSFS 写入内核日志（dmesg）的痕迹
# v2.1：修正关闭 SUSFS 日志分支后 SUSFS_LOGI_RL / SUSFS_LOGE_RL 未定义导致的编译错误
set -u

KSU_DIR="${KSU_DIR:-${GITHUB_WORKSPACE:-$(pwd)}/KernelSU}"
KERNEL_ROOT="${KERNEL_ROOT:-$(pwd)}"
COMMON="$KERNEL_ROOT/common"
DEFCONFIG="${DEFCONFIG:-$COMMON/arch/arm64/configs/gki_defconfig}"

echo "::group::隐藏 root 相关内核日志"

if [ -d "$KSU_DIR/kernel" ]; then
  BEFORE=$(grep -rE '\b(pr_info|pr_warn|pr_warn_once|pr_alert|pr_err|pr_crit|pr_emerg|pr_notice|pr_cont)\(' "$KSU_DIR/kernel" --include='*.c' --include='*.h' | wc -l)
  SED_EXPR='s/\bpr_info\(/pr_debug(/g; s/\bpr_warn\(/pr_debug(/g; s/\bpr_warn_once\(/pr_debug(/g; s/\bpr_alert\(/pr_debug(/g; s/\bpr_err\(/pr_debug(/g; s/\bpr_crit\(/pr_debug(/g; s/\bpr_emerg\(/pr_debug(/g; s/\bpr_notice\(/pr_debug(/g; s/\bpr_cont\(/pr_debug(/g'
  find "$KSU_DIR/kernel" -type f \( -name '*.c' -o -name '*.h' \) -exec sed -i -E "$SED_EXPR" {} +
  AFTER=$(grep -rE '\b(pr_info|pr_warn|pr_warn_once|pr_alert)\(' "$KSU_DIR/kernel" --include='*.c' --include='*.h' | wc -l)
  echo "KernelSU 日志调用点: $BEFORE -> 剩余 info/warn/alert $AFTER"
else
  echo "::warning title=hide_root_logs::未找到 $KSU_DIR/kernel"
fi

KLOG="$KSU_DIR/kernel/include/klog.h"
if [ -f "$KLOG" ]; then
  sed -i -E 's|^([[:space:]]*)#define[[:space:]]+pr_fmt\(fmt\)[[:space:]]+"KernelSU: "[[:space:]]*fmt[[:space:]]*$|\1#define pr_fmt(fmt) fmt|' "$KLOG"
  echo "已处理 pr_fmt"
fi

SUSFS_C="$COMMON/fs/susfs.c"
if [ -f "$SUSFS_C" ]; then
  sed -i -E 's/^#[[:space:]]*ifdef[[:space:]]+CONFIG_KSU_SUSFS_ENABLE_LOG[[:space:]]*$/#if 0 \/* root logs hidden *\//' "$SUSFS_C"
  sed -i -E 's/^#[[:space:]]*if[[:space:]]+defined\(CONFIG_KSU_SUSFS_ENABLE_LOG\)[[:space:]]*$/#if 0 \/* root logs hidden *\//' "$SUSFS_C"
  python3 "$GITHUB_WORKSPACE/scripts/fix_susfs_rl.py" "$SUSFS_C" || true
  echo "SUSFS 日志宏已关闭: $SUSFS_C"
else
  echo "::warning title=hide_root_logs::未找到 $SUSFS_C"
fi

if [ -f "$DEFCONFIG" ]; then
  sed -i -E '/^CONFIG_KSU_SUSFS_ENABLE_LOG=/d' "$DEFCONFIG"
  sed -i -E '/^# CONFIG_KSU_SUSFS_ENABLE_LOG is not set$/d' "$DEFCONFIG"
  echo "已清理 defconfig 中的 CONFIG_KSU_SUSFS_ENABLE_LOG"
fi

echo "::endgroup::"
