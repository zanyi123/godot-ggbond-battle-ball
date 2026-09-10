@echo off
chcp 65001 >nul
title P1 3D场景复刻验证场
set GODOT=E:\项目储存\pvz-project\pvz-godot\tools\Godot_v4.6.2-stable_win64_console.exe
if not exist "%GODOT%" (
  echo [错误] 找不到 Godot 控制台版: %GODOT%
  echo 请编辑本 bat 里的 GODOT 路径
  pause
  exit /b 1
)
echo 正在启动 P1 验证场（首次加载大模型约 10~30 秒，请稍候）...
echo 手动操作: F4=切相机(UNITY/TOP/ANGLED/FOLLOW)  F5=白线框开关  F6=演示开关  ESC=退出
echo 自动巡检: 加 --p1auto 参数（四模式截图到 docs\img\3d_p1\ 并自动退出）
"%GODOT%" --path . res://scenes/test3d/unity_scene_parity_test.tscn %*
pause
