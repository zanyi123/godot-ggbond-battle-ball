#!/bin/bash
# e2e 3v3 AI（COOP）三进程编排：host + guest1 + guest2
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GODOT="E:/项目储存/pvz-project/pvz-godot/tools/Godot_v4.6.2-stable_win64_console.exe"
cd "$ROOT" || exit 2
rm -f sim_results/net_e2e_3v3_*.json
"$GODOT" --headless --path . res://scenes/test/net_e2e_host_3v3.tscn > sim_results/_net_e2e_3v3_host.log 2>&1 &
H=$!
sleep 3
"$GODOT" --headless --path . res://scenes/test/net_e2e_guest_3v3_g1.tscn > sim_results/_net_e2e_3v3_g1.log 2>&1 &
G1=$!
sleep 3
"$GODOT" --headless --path . res://scenes/test/net_e2e_guest_3v3.tscn > sim_results/_net_e2e_3v3_g2.log 2>&1 &
G2=$!
wait "$H" "$G1" "$G2"
echo "[e2e-3v3] workers done"
bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_net_e2e_3v3_ai.gd
exit $?
