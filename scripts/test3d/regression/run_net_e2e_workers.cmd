@echo off
rem e2e worker launcher (pure ASCII; %~dp0 self-locating; no bash/PATH ambiguity)
cd /d %~dp0..\..\..
start "e2e-host" /B "..\..\pvz-project\pvz-godot\tools\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://scenes/test/net_e2e_host.tscn > sim_results\_net_e2e_host.log 2>&1
start "e2e-guest" /B "..\..\pvz-project\pvz-godot\tools\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://scenes/test/net_e2e_guest.tscn > sim_results\_net_e2e_guest.log 2>&1
exit 0
