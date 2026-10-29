#!/bin/bash
# e2e worker launcher (LF only: CRLF breaks bash). PROJ=cwd (parent cwd = project root).
GODOT="../../pvz-project/pvz-godot/tools/Godot_v4.6.2-stable_win64_console.exe"
pwd > /tmp/e2e_diag.txt 2>&1
ls ../../pvz-project/pvz-godot/tools/ >> /tmp/e2e_diag.txt 2>&1
PROJ="$(pwd)"
rm -f "$PROJ/sim_results/net_e2e_host.json" "$PROJ/sim_results/net_e2e_guest.json"
"$GODOT" --headless --path "$PROJ" res://scenes/test/net_e2e_host.tscn > "$PROJ/sim_results/_net_e2e_host.log" 2>&1 &
"$GODOT" --headless --path "$PROJ" res://scenes/test/net_e2e_guest.tscn > "$PROJ/sim_results/_net_e2e_guest.log" 2>&1 &
wait
exit 0
