extends Node2D
## 工单10 完全体AI测试平台 —— 平台窗口
## 用法（实机观战）：Godot 编辑器打开 res://scenes/test3d/full_ai_platform.tscn → 按 F6。
## 用法（headless 冒烟）：Godot_console.exe --headless --path . res://scenes/test3d/full_ai_platform.tscn --platform-auto=1 --platform-seed=N
##
## 原理：实例化 battle_arena（auto_simulate=false → 3D 桥接原生开启）→
##   装载 test_loadouts.json（P2）→ set_controlled_player(null) 双队全 AI（复用 sim 清位路径）→
##   _on_prep_match_started 延迟开赛（复用备战完成→开赛既有路径，隐藏备战面板/发球/解锁）。
## 零侵入纪律：不改 battle_manager / ai_manager / skill_state_manager（--fullai CLI flag 归集成窗口）；
##   --sim 路径零触碰（P1 观察模式 flag 落地前，本场景即 --fullai 等效入口）。

const ARENA_SCENE := "res://scenes/battle/battle_arena.tscn"
const LoadoutLoader := preload("res://scripts/test3d/full_ai_platform/loadout_loader.gd")
const ObserveLayerScript := preload("res://scripts/test3d/full_ai_platform/observe_layer.gd")

var battle_manager: Node2D = null
var observe_layer: CanvasLayer = null
var auto_matches: int = 0          # --platform-auto=N：headless 自动跑满 N 场后退出（0=交互观战）
var platform_speed: float = 1.0    # --platform-speed=F：Engine.time_scale（auto 模式默认 6）
var platform_seed: int = 0         # --platform-seed=N（0=不设种子）
var loadout_path: String = ""      # --platform-loadout=path（缺省用出厂配置）
var _finished_matches: int = 0


func _ready() -> void:
	_parse_platform_args()
	if platform_seed > 0:
		seed(platform_seed)
		print("[Platform] 种子=%d" % platform_seed)
	var arena: PackedScene = load(ARENA_SCENE)
	if arena == null:
		push_error("[Platform] battle_arena 场景加载失败")
		get_tree().quit(1)
		return
	battle_manager = arena.instantiate()
	add_child(battle_manager)
	# 延迟启动：让 ai_manager._deferred_init_spirit_ai（同帧更早入队）先完成注册
	call_deferred("_platform_start")


func _platform_start() -> void:
	if battle_manager == null or not is_instance_valid(battle_manager):
		return
	# headless 无 --platform-auto 时按 1 场冒烟跑（防挂机）
	if auto_matches <= 0 and DisplayServer.get_name() == "headless":
		auto_matches = 1
	if auto_matches > 0:
		Engine.physics_ticks_per_second = 60  # 与 sim 同款固定步长
		if platform_speed == 1.0:
			platform_speed = 6.0
		if GameManager.sim_half_duration_override <= 0.0:
			GameManager.sim_half_duration_override = battle_manager.DEFAULT_SIM_HALF
		print("[Platform] 自动模式：场次上限=%d 倍速=%.1f 半场=%.1fs" % [
			auto_matches, platform_speed, GameManager.sim_half_duration_override])

	# === P2 技能装载（无有效装载的槽自动兜底，保证满配可观测）===
	var config := LoadoutLoader.load_config(loadout_path if not loadout_path.is_empty() else LoadoutLoader.LOADOUT_PATH)
	var stats := LoadoutLoader.apply_loadouts(battle_manager, config)
	print("[Platform] 装载完成：有效=%d 兜底=%d 跳过=%s" % [
		int(stats["applied"]), int(stats["fallback"]), str(stats["skipped"])])
	if battle_manager.ai_mgr and battle_manager.ai_mgr.has_method("refresh_spirit_ai_skills"):
		battle_manager.ai_mgr.refresh_spirit_ai_skills()

	# === 双队全 AI（复用 sim 清位路径；否则队A0号位无人操作会僵死）===
	if battle_manager.input_mgr:
		battle_manager.input_mgr.set_controlled_player(null)
		print("[Platform] 已清空玩家控制位，双队全 AI")

	GameManager.match_ended.connect(_on_platform_match_ended)
	battle_manager._on_prep_match_started()
	if auto_matches > 0:
		Engine.time_scale = platform_speed

	# === P3 观测层（headless 不建 UI）===
	if auto_matches <= 0 and DisplayServer.get_name() != "headless":
		observe_layer = ObserveLayerScript.new()
		add_child(observe_layer)
		observe_layer.setup(battle_manager)

	print("[Platform] ✅ 3v3 完全体AI观战已就绪（F9 收起/展开观测面板）")


func _parse_platform_args() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--platform-auto="):
			auto_matches = maxi(1, int(arg.substr(16)))
		elif arg.begins_with("--platform-speed="):
			var s := float(arg.substr(17))
			if s > 0.0:
				platform_speed = s
		elif arg.begins_with("--platform-seed="):
			platform_seed = int(arg.substr(16))
		elif arg.begins_with("--platform-loadout="):
			loadout_path = arg.substr(19)


func _on_platform_match_ended(score_a: int, score_b: int, result: String) -> void:
	_finished_matches += 1
	print("[Platform] 场次#%d 结束 比分 %d-%d（%s）" % [_finished_matches, score_a, score_b, result])
	if auto_matches > 0 and _finished_matches >= auto_matches:
		print("[Platform] 自动模式完成，退出")
		get_tree().quit(0)
