#!/bin/bash
# 决竞球 - 一键验证脚本（单测 + 自动模拟）
# --------------------------------------------------------------------------
# 用法:
#   ./verify.sh            # 默认 full：单测 + 模拟（改完代码标准流程）
#   ./verify.sh unit       # 只跑单测（几秒，改纯函数/AI工具函数时用）
#   ./verify.sh sim        # 只跑模拟（约90秒，改比赛/AI行为时用）
#   ./verify.sh full       # 单测 + 模拟（完整）
#
# 退出码:
#   0 = 全部通过，可以交付/提交
#   1 = 有失败或危险项，禁止交付
#
# 用途:
#   1. AI 改完 .gd 代码后自觉调用（落实"无证据不算完成"）
#   2. 被 git pre-commit 钩子自动调用（提交时强制兜底）
# --------------------------------------------------------------------------

cd "$(dirname "$0")"   # 切到项目根，确保能找到 run_sim.sh / run_tests.sh

MODE="${1:-full}"
LOG_DIR="./sim_results"
mkdir -p "$LOG_DIR"

FAIL=0

# ========== [1] 单元测试 ==========
run_unit() {
  echo "========== [1/2] 单元测试 (run_tests.sh) =========="
  if bash ./run_tests.sh > "$LOG_DIR/_verify_unit.log" 2>&1; then
    echo "✓ 单测通过"
    return 0
  else
    echo "✗ 单测失败，最近 20 行日志："
    echo "------------------------------------------------"
    tail -20 "$LOG_DIR/_verify_unit.log"
    echo "------------------------------------------------"
    return 1
  fi
}

# ========== [2] 自动模拟 ==========
run_sim() {
  echo "========== [2/2] 自动模拟 (run_sim.sh 3场，约90秒) =========="
  # 用 tee 同时显示和存日志
  bash ./run_sim.sh 3 6 1 80 2>&1 | tee "$LOG_DIR/_verify_sim.log"
  # 抓"危险总数"那行的数字
  DANGER=$(grep "危险总数" "$LOG_DIR/_verify_sim.log" | grep -oE '[0-9]+' | head -1)
  DANGER=${DANGER:-0}
  if [ "$DANGER" -gt 0 ]; then
    echo "✗ 模拟出现 $DANGER 项危险，不可交付"
    return 1
  else
    echo "✓ 模拟无危险项"
    return 0
  fi
}

echo "================================================"
echo "决竞球 一键验证   模式: $MODE"
echo "================================================"
echo ""

case "$MODE" in
  unit)
    run_unit || FAIL=1
    ;;
  sim)
    run_sim || FAIL=1
    ;;
  full|"")
    run_unit || { echo "→ 单测未过，跳过模拟（先修单测）"; FAIL=1; }
    if [ "$FAIL" = "0" ]; then
      run_sim || FAIL=1
    fi
    ;;
  *)
    echo "未知模式: $MODE"
    echo "可用: unit / sim / full"
    exit 2
    ;;
esac

echo ""
echo "================================================"
if [ "$FAIL" = "0" ]; then
  echo "✓✓✓ 验证通过，可以交付/提交 ✓✓✓"
  exit 0
else
  echo "✗✗✗ 验证未通过，禁止交付/提交 ✗✗✗"
  echo "（紧急情况提交可加 --no-verify，但请确保你知道在做什么）"
  exit 1
fi
