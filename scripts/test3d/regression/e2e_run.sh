#!/bin/bash
# 工单01 e2e 一键编排（S11）：起双 worker→等跑完→跑纯断言套件→透传退出码
# 用法：bash scripts/test3d/regression/e2e_run.sh
# 为什么 bash：Godot 内派生进程历坑全灭（GUI exe 挂死/WSL 假 bash/cmd 引号拼接），
# bash 后台派生被反复实证可靠——编排走已验证环境。
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GODOT="E:/项目储存/pvz-project/pvz-godot/tools/Godot_v4.6.2-stable_win64_console.exe"
cd "$ROOT" || exit 2
rm -f sim_results/net_e2e_host.json sim_results/net_e2e_guest.json sim_results/_net_e2e_host.log sim_results/_net_e2e_guest.log
"$GODOT" --headless --path . res://scenes/test/net_e2e_host.tscn > sim_results/_net_e2e_host.log 2>&1 &
H=$!
sleep 3   # host 先建房（防 guest 打空）
"$GODOT" --headless --path . res://scenes/test/net_e2e_guest.tscn > sim_results/_net_e2e_guest.log 2>&1 &
G=$!
wait "$H"; EH=$?
wait "$G"; EG=$?
echo "[e2e] worker exits: host=$EH guest=$EG"
bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_net_e2e_1v1.gd
exit $?
