#!/bin/bash
# 决竞球 - 自动模拟批量跑场脚本（方案A 步骤3 + 优化2 健康检查）
# 用法: ./run_sim.sh [场数] [speed] [seed起始] [半场秒数]
# 示例: ./run_sim.sh 3 6 1 80   → 跑3场，6倍速，种子1-3，每半场80秒(约30秒一场)
#
# 输出:
#   1. 每场 ✓/⚠/✗ 评级（读 sim_results/baseline.json 做健康检查）
#   2. sim_results/summary_时间戳.csv 汇总
#   3. 末尾整体健康结论
# 依赖: git bash + Godot 4 控制台版

# === 配置 ===
GODOT="/e/项目储存/pvz-project/pvz-godot/tools/Godot_v4.6.2-stable_win64_console.exe"
PROJECT="E:/项目储存/决竞球battle-ball"
SCENE="res://scenes/battle/battle_arena.tscn"
RESULT_DIR="$PROJECT/sim_results"
BASELINE="$RESULT_DIR/baseline.json"

COUNT="${1:-3}"
SPEED="${2:-6}"
SEED_START="${3:-1}"
HALF="${4:-80}"

mkdir -p "$RESULT_DIR"
SUMMARY_FILE="$RESULT_DIR/summary_$(date +%Y%m%d_%H%M%S).csv"

# 健康检查阈值（与 baseline.json 的 hard_rules 对应，写死避免 JSON 解析）
HARD_STUCK_MAX=0
HARD_CATCHRATE_MIN=0.8
HARD_HIT_MIN=1
WARN_STATE_MIN=30
WARN_STATE_MAX=130

echo "================================================"
echo "决竞球 自动模拟 - 跑 $COUNT 场 (speed=$SPEED half=$HALF)"
echo "================================================"

# 累计统计（末尾整体判断）
TOTAL_DANGER=0
TOTAL_WARN=0
TOTAL_HARD_PASS=0
TOTAL_MATCHES=0

echo "场次,种子,时长秒,比分A,比分B,同队接球,敌队接球,同队接球率,外场接球,球击中,总伤害,出界,卡死,状态切换,评级" > "$SUMMARY_FILE"

for ((i=0; i<COUNT; i++)); do
  SEED=$((SEED_START + i))
  echo ""
  echo "--- 第 $((i+1))/$COUNT 场 (seed=$SEED) ---"
  OUTPUT=$("$GODOT" --headless --sim --speed=$SPEED --seed=$SEED --half=$HALF "$SCENE" 2>&1)

  # 提取指标（用报告行独有格式作锚点）
  SCORE_LINE=$(echo "$OUTPUT" | grep "比分: 队A" | head -1)
  DURATION=$(echo "$SCORE_LINE" | sed -nE 's/.*时长: ([0-9.]+)秒.*/\1/p')
  SCORE_A=$(echo "$SCORE_LINE" | sed -nE 's/.*比分: 队A ([0-9]+) - ([0-9]+) 队B.*/\1/p')
  SCORE_B=$(echo "$SCORE_LINE" | sed -nE 's/.*比分: 队A ([0-9]+) - ([0-9]+) 队B.*/\2/p')
  CATCH_SAME=$(echo "$OUTPUT" | grep "传球到位" | grep -oE '[0-9]+$' | head -1)
  CATCH_ENEMY=$(echo "$OUTPUT" | grep "被截断" | grep -oE '[0-9]+$' | head -1)
  CATCH_RATE=$(echo "$OUTPUT" | grep "同队接球率" | grep -oE '[0-9.]+' | head -1)
  OUTER_CATCH=$(echo "$OUTPUT" | grep "外场接球次数" | grep -oE '[0-9]+$' | head -1)
  HIT=$(echo "$OUTPUT" | grep "球击中球员" | sed -nE 's/.*球击中球员: ([0-9]+) 次.*/\1/p' | head -1)
  DAMAGE=$(echo "$OUTPUT" | grep "球击中球员" | sed -nE 's/.*总伤害 ([0-9.]+).*/\1/p' | head -1)
  OUT_BOUND=$(echo "$OUTPUT" | grep "出界次数" | grep -oE '[0-9]+$' | head -1)
  STUCK=$(echo "$OUTPUT" | grep "卡死触发" | sed -nE 's/.*卡死触发: ([0-9]+) 次.*/\1/p' | head -1)
  STATE_CHG=$(echo "$OUTPUT" | grep "状态切换" | sed -nE 's/.*状态切换: ([0-9]+) 次.*/\1/p' | head -1)

  # 兜底
  DURATION=${DURATION:-0}; SCORE_A=${SCORE_A:-0}; SCORE_B=${SCORE_B:-0}
  CATCH_SAME=${CATCH_SAME:-0}; CATCH_ENEMY=${CATCH_ENEMY:-0}; CATCH_RATE=${CATCH_RATE:-0}
  OUTER_CATCH=${OUTER_CATCH:-0}; HIT=${HIT:-0}; DAMAGE=${DAMAGE:-0}; OUT_BOUND=${OUT_BOUND:-0}
  STUCK=${STUCK:-0}; STATE_CHG=${STATE_CHG:-0}

  # === 健康检查 ===
  RATING="✓"
  WARNINGS=""
  DANGER=""
  TOTAL_MATCHES=$((TOTAL_MATCHES+1))

  # 硬规则（✗ 危险）
  if [ "$SCORE_A" = "0" ] && [ "$SCORE_B" = "0" ]; then
    DANGER="$DANGER 比分0-0(僵死)"; RATING="✗"; TOTAL_DANGER=$((TOTAL_DANGER+1))
  fi
  if [ "$STUCK" -gt "$HARD_STUCK_MAX" ]; then
    DANGER="$DANGER 卡死$STUCK次"; RATING="✗"; TOTAL_DANGER=$((TOTAL_DANGER+1))
  fi
  RATE_OK=$(awk "BEGIN{print ($CATCH_RATE>=$HARD_CATCHRATE_MIN)?1:0}")
  if [ "$RATE_OK" = "0" ]; then
    DANGER="$DANGER 传球率${CATCH_RATE}%"; RATING="✗"; TOTAL_DANGER=$((TOTAL_DANGER+1))
  fi
  if [ "$HIT" -lt "$HARD_HIT_MIN" ]; then
    DANGER="$DANGER 零击中"; RATING="✗"; TOTAL_DANGER=$((TOTAL_DANGER+1))
  fi
  if [ "$RATING" = "✓" ]; then TOTAL_HARD_PASS=$((TOTAL_HARD_PASS+1)); fi

  # 正常范围（⚠ 警告）
  STATE_LOW=$(awk "BEGIN{print ($STATE_CHG>=$WARN_STATE_MIN)?1:0}")
  STATE_HIGH=$(awk "BEGIN{print ($STATE_CHG<=$WARN_STATE_MAX)?1:0}")
  if [ "$STATE_LOW" = "0" ]; then
    WARNINGS="$WARNINGS 切换过少($STATE_CHG,可能AI不动)"; RATING="⚠"; TOTAL_WARN=$((TOTAL_WARN+1))
  elif [ "$STATE_HIGH" = "0" ]; then
    WARNINGS="$WARNINGS 切换过多($STATE_CHG,可能抖动)"; RATING="⚠"; TOTAL_WARN=$((TOTAL_WARN+1))
  fi
  if [ "$OUTER_CATCH" = "0" ]; then
    WARNINGS="$WARNINGS 外场接球0(已知现象,可能正常)"; TOTAL_WARN=$((TOTAL_WARN+1))
  fi

  # 输出本场
  echo "  $RATING 比分 $SCORE_A-$SCORE_B | 接球率 $CATCH_RATE% | 击中 $HIT | 卡死 $STUCK | 切换 $STATE_CHG"
  [ -n "$DANGER" ] && echo "     ✗ 危险:$DANGER"
  [ -n "$WARNINGS" ] && echo "     ⚠ 警告:$WARNINGS"

  echo "$((i+1)),$SEED,$DURATION,$SCORE_A,$SCORE_B,$CATCH_SAME,$CATCH_ENEMY,$CATCH_RATE,$OUTER_CATCH,$HIT,$DAMAGE,$OUT_BOUND,$STUCK,$STATE_CHG,$RATING" >> "$SUMMARY_FILE"
done

# === 整体健康结论 ===
echo ""
echo "================================================"
echo "整体健康检查（共 $TOTAL_MATCHES 场）"
echo "================================================"
echo "✓ 硬规则通过: $TOTAL_HARD_PASS / $TOTAL_MATCHES 场"
echo "⚠ 警告总数:   $TOTAL_WARN 项"
echo "✗ 危险总数:   $TOTAL_DANGER 项"
echo ""
if [ "$TOTAL_DANGER" -gt 0 ]; then
  echo "结论: ✗ 有危险项，可能引入bug，必须排查后再交付"
elif [ "$TOTAL_HARD_PASS" = "$TOTAL_MATCHES" ]; then
  echo "结论: ✓ 硬规则全通过，AI行为健康，可交付（警告项需人工判断）"
else
  echo "结论: ⚠ 部分硬规则未过，建议复查"
fi
echo "================================================"
echo "汇总CSV: $SUMMARY_FILE"
