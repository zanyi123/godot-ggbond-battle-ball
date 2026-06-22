#!/bin/bash
# 决竞球 - AI 工具函数单元测试（vibecoding 方案B）
# 用法: ./run_tests.sh
# 依赖: git bash + Godot 4 控制台版
#
# 测试: tests/test_ai_utils.gd（headless 直接跑，不进场景）
# 覆盖: _curve / _utility_carrying / _utility_catch / _ball_in_reachable_half
# 用途: 改 ai_manager 纯函数后跑这个，抓"改 A 坏 B"的逻辑回归

GODOT="/e/项目储存/pvz-project/pvz-godot/tools/Godot_v4.6.2-stable_win64_console.exe"
SCRIPT="res://tests/test_ai_utils.gd"

"$GODOT" --headless -s "$SCRIPT"
EXIT=$?

echo ""
echo "================================================"
if [ "$EXIT" -eq 0 ]; then
  echo "✓ 单测全部通过（exit 0）"
else
  echo "✗ 单测有失败（exit $EXIT），请检查上方输出"
fi
echo "================================================"
exit $EXIT
