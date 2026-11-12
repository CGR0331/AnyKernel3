#!/bin/bash
# KernelSU 编译后置处理：版本标识兼容性校准
# 用途：统一不同 KSU 变体的版本名格式，避免构建产物版本标识不一致

set -e

KSU_DIR="${1:-KernelSU}"
MODE="${2:-auto}"   # auto | bakasu | sukisu

# 版本标识常量（base64 编码，避免明文暴露）
declare -A PATTERNS
PATTERNS[bakasu]=$(echo 'UkVQT19OQU1FIDo9IEJha2FTVQ==' | base64 -d | base64)
PATTERNS[sukisu_branch]=$(echo 'QCQoY2FsbCBnaXRfYnJhbmNoKQ==' | base64 -d | base64)
PATTERNS[finasu_branch]=$(echo 'QCQoS1NVX1ZFUlNJT05fQlJBTkNIKQ==' | base64 -d | base64)
PATTERNS[marker]=$(echo 'QmFrYVNV' | base64 -d | base64)
PATTERNS[finasu_marker]=$(echo 'S1NVX1ZFUlNJT05fQlJBTkNI' | base64 -d | base64)
BRAND=$(echo 'TGluZ0x1bw==' | base64 -d)

apply_bakasu() {
  local kbuild="$KSU_DIR/kernel/Kbuild"
  if [ -f "$kbuild" ]; then
    local pat=$(echo "${PATTERNS[bakasu]}" | base64 -d)
    sed -i "s/^${pat}\$/REPO_NAME := ${BRAND}/" "$kbuild"
    git -C "$KSU_DIR" update-index --skip-worktree kernel/Kbuild
  fi
}

apply_sukisu() {
  local kbuild=""
  for f in "$KSU_DIR/kernel/Kbuild" "$KSU_DIR/kernel/Makefile"; do
    if [ -f "$f" ]; then kbuild="$f"; break; fi
  done
  if [ -n "$kbuild" ]; then
    local pat=$(echo "${PATTERNS[sukisu_branch]}" | base64 -d)
    sed -i "s/${pat}/@${BRAND}/" "$kbuild"
    local rel="${kbuild#${KSU_DIR}/}"
    git -C "$KSU_DIR" update-index --skip-worktree "$rel"
  fi
}

apply_finasu() {
  # FinaSU kernel/Kbuild 以 git rev-parse --abbrev-ref HEAD 取分支名拼进
  # KSU_VERSION_FULL（v<tag>-<sha>@<branch>）；CI 检出的是 detached 提交，
  # 管理器「内核完整版本」因此显示 @HEAD。与 SukiSU 一致把使用点固定为
  # @LingLuo；须在管理器证书注入（awk 重写 Kbuild）之后调用。
  local kbuild="$KSU_DIR/kernel/Kbuild"
  if [ -f "$kbuild" ]; then
    local pat=$(echo "${PATTERNS[finasu_branch]}" | base64 -d)
    sed -i "s/${pat}/@${BRAND}/" "$kbuild"
    git -C "$KSU_DIR" update-index --skip-worktree kernel/Kbuild
  fi
}

case "$MODE" in
  bakasu)   apply_bakasu ;;
  sukisu)   apply_sukisu ;;
  finasu)   apply_finasu ;;
  auto)
    # 自动检测：根据 KSU 目录内容判断变体
    if [ -f "$KSU_DIR/kernel/Kbuild" ] && grep -q "$(echo "${PATTERNS[marker]}" | base64 -d)" "$KSU_DIR/kernel/Kbuild" 2>/dev/null; then
      apply_bakasu
    elif [ -f "$KSU_DIR/kernel/Kbuild" ] && grep -q "$(echo "${PATTERNS[finasu_marker]}" | base64 -d)" "$KSU_DIR/kernel/Kbuild" 2>/dev/null; then
      apply_finasu
    else
      apply_sukisu
    fi
    ;;
  *) echo "未知模式: $MODE" >&2; exit 1 ;;
esac

# ============================================================
# 隐藏 KernelSU 内核符号（防止 /proc/kallsyms 暴露 ksu 字样）
# 由用户追加：把 setup_ksu_cred / is_task_ksu_domain / anon_ksu_*
# 等符号统一改名为 kx7a3 前缀，并对 Kbuild 的 MODULE_NAME 改名。
# ============================================================
hide_ksu_symbols() {
    local kdir=""
    if [ -d "$KSU_DIR/kernel" ]; then
        kdir="$KSU_DIR/kernel"
    elif [ -d "$KSU_DIR" ]; then
        kdir="$KSU_DIR"
    else
        echo "[hide_ksu_symbols] KSU dir not found, skip"
        return 0
    fi

    local n=0
    while IFS= read -r -d '' f; do
        sed -i \
            -e 's/\bsetup_ksu_cred\b/setup_kx7a3_cred/g' \
            -e 's/\bis_task_ksu_domain\b/is_task_kx7a3_domain/g' \
            -e 's/\banon_ksu_ioctl\b/anon_kx7a3_ioctl/g' \
            -e 's/\banon_ksu_release\b/anon_kx7a3_release/g' \
            -e 's/\banon_ksu_fops\b/anon_kx7a3_fops/g' \
            "$f" 2>/dev/null || true
        n=$((n + 1))
    done < <(find "$kdir" -type f \( -name '*.c' -o -name '*.h' -o -name '*.S' -o -name 'Kbuild' -o -name 'Makefile' \) -print0 2>/dev/null)

    # 模块名（决定 __initstub__kmod_ksu_xxx_kernelsu_init 这条符号）
    while IFS= read -r -d '' kb; do
        sed -i -E 's/^MODULE_NAME[[:space:]]*:=[[:space:]]*(ksu|kernelsu|sukisu|bakasu|finasu)[[:space:]]*$/MODULE_NAME := kx7a3/' "$kb" 2>/dev/null || true
    done < <(find "$KSU_DIR" -type f -name 'Kbuild' -print0 2>/dev/null)

    echo "[hide_ksu_symbols] scanned $n files, MODULE_NAME -> kx7a3"
}

set +e
hide_ksu_symbols
set -e
