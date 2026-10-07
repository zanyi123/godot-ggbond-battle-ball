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
const RosterPanelScript := preload("res://scripts/test3d/full_ai_platform/roster_panel.gd")
const PlatformProbeScript := preload("res://scripts/test3d/full_ai_platform/platform_probe.gd")
const TraceRecorderScript := preload("res://scripts/test3d/full_ai_platform/play_trace_recorder.gd")

var battle_manager: Node2D = null
var observe_layer: CanvasLayer = null
var roster_panel: CanvasLayer = null
var probe: Node = null             # 工单12 检测层（信号判定，非肉眼）
var trace_recorder: Node = null    # 22-C S1 轨迹采集器（主人操控模式自动启用）
var auto_matches: int = 0          # --platform-auto=N：headless 自动跑满 N 场后退出（0=交互观战）
var platform_speed: float = 1.0    # --platform-speed=F：Engine.time_scale（auto 未显式指定时默认 6）
var _speed_explicit: bool = false
var shots_interval_cfg: float = 0.0  # --platform-shots=秒间隔（验收截图）
var platform_seed: int = 0         # --platform-seed=N（0=不设种子）
var loadout_path: String = ""      # --platform-loadout=path（缺省用出厂配置）
var force_observe: bool = false    # --platform-force-observe=1：headless 下也构建观测层（UI 冒烟用）
var probe_enabled: bool = true     # --platform-probe=0 关闭检测层（默认开）
var human_slot: int = -1           # --platform-human=N（0-5）：该槽由主人亲自操控（22-C 轨迹采集模式），其余全 AI
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
		if not _speed_explicit:
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

	# === 主人令 09-26：F6 先弹排表确认面板（6槽×元灵，右键查看本次测试技能），点确认才开赛 ===
	# headless 自动模式跳过面板直开
	if auto_matches <= 0 and DisplayServer.get_name() != "headless":
		roster_panel = RosterPanelScript.new()
		add_child(roster_panel)
		roster_panel.setup(battle_manager, stats)
		roster_panel.confirmed.connect(_begin_match)
		print("[Platform] 排表确认面板已弹出——右键元灵行查看技能明细，确认后开赛")
	else:
		_begin_match()


func _begin_match() -> void:
	if battle_manager == null or not is_instance_valid(battle_manager):
		return
	# 主人操控勾选（排表面板）优先于 CLI 参数（F6 无命令行入口；确认时面板尚在）
	if roster_panel != null and is_instance_valid(roster_panel):
		human_slot = int(roster_panel.get("human_slot_choice"))
	# === 控制位：默认双队全 AI（复用 sim 清位路径）；--platform-human=N 时该槽归主人 ===
	if battle_manager.input_mgr:
		if human_slot >= 0:
			var all_p: Array = battle_manager.team_a_players + battle_manager.team_b_players
			if human_slot < all_p.size():
				battle_manager.input_mgr.set_controlled_player(all_p[human_slot])
				print("[Platform] 🎮 主人操控模式：槽位 %s 由您亲自驾驶（其余全 AI），轨迹采集中…" % [
					"A%d" % human_slot if human_slot < 3 else "B%d" % (human_slot - 3)])
			else:
				battle_manager.input_mgr.set_controlled_player(null)
		else:
			battle_manager.input_mgr.set_controlled_player(null)
			print("[Platform] 已清空玩家控制位，双队全 AI")
	# 1001 主人令（平台专属）：驾驶模式下 Tab 切换名册=驾驶队内 3 人（默认），
	# 观测层"跨队遍历"开关开=6 人全队顺序轮转（切不回来的旧问题随名册循环消失）。
	# 零侵入 input_manager——只重设"可切换球员名册"（其本义=玩家可切换名单）。
	if human_slot >= 0 and battle_manager.input_mgr != null:
		set_cross_team_switch(observe_cross_team)
		print("[Platform] Tab 切换名册 = %s（观测层可开跨队遍历）" % [
			"驾驶队内 3 人" if not observe_cross_team else "全队 6 人"])

	GameManager.match_ended.connect(_on_platform_match_ended)
	# === 工单12 检测层：信号判定印记/合体是否运行时真实发生（21表对照信号，非肉眼）===
	# 护栏：探针脚本自身编译失败时跳过挂接（不得中断开赛——实录：new() 异常曾致 _begin_match 中断→比赛不启动→进程挂死）
	var probe_script_ref: GDScript = PlatformProbeScript  # 4.6：preload 常量直调实例方法会被静态拒绝，经变量中转
	if probe_enabled and probe_script_ref != null and probe_script_ref.can_instantiate():
		probe = PlatformProbeScript.new()
		add_child(probe)
		probe.setup(battle_manager)
		if shots_interval_cfg > 0.0:
			probe.shots_interval = shots_interval_cfg
			print("[Platform] 📸 验收截图开启（每 %.0fs 一张 → docs/img/23demo）" % shots_interval_cfg)
	elif probe_enabled:
		print("[Platform] ⚠ 检测层脚本不可实例化（编译失败？）——本场无探针判定，开赛继续")
	battle_manager._on_prep_match_started()
	if auto_matches > 0:
		Engine.time_scale = platform_speed

	# === P3 观测层（headless 默认不建 UI；--platform-force-observe=1 供 headless 冒烟 UI 构建路径）===
	if auto_matches <= 0 and (DisplayServer.get_name() != "headless" or force_observe):
		observe_layer = ObserveLayerScript.new()
		add_child(observe_layer)
		observe_layer.setup(battle_manager)

	print("[Platform] ✅ 3v3 完全体AI观战已就绪（F9 收起/展开观测面板）")


var observe_cross_team: bool = false  # 观测层"跨队遍历切换"开关（默认关=队内轮转）

## 跨队遍历开关：重设 input_manager 的可切换球员名册
func set_cross_team_switch(on: bool) -> void:
	observe_cross_team = on
	if battle_manager == null or battle_manager.input_mgr == null:
		return
	var arr: Array[CharacterBody2D] = []
	# ⚠ 8a1e117 备案引擎怪癖：assign 无类型数组→强类型属性在 -s 模式死循环——用显式循环
	var src: Array = []
	if on:
		src = battle_manager.team_a_players + battle_manager.team_b_players
	elif human_slot >= 0:
		src = battle_manager.team_a_players if human_slot < 3 else battle_manager.team_b_players
	else:
		src = battle_manager.team_a_players
	for pl in src:
		if pl != null and is_instance_valid(pl) and pl is CharacterBody2D:
			arr.append(pl)
	battle_manager.input_mgr.all_team_players = arr
	# === 22-C S1 轨迹采集（主人操控模式自动启用；终场 finalize 由探针同批退出路径触发）===
	if human_slot >= 0 and battle_manager.input_mgr != null and battle_manager.input_mgr.controlled_player != null:
		trace_recorder = TraceRecorderScript.new()
		add_child(trace_recorder)
		trace_recorder.setup(battle_manager)



func _parse_platform_args() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--platform-auto="):
			auto_matches = maxi(1, int(arg.substr(16)))
		elif arg.begins_with("--platform-speed="):
			var s := float(arg.substr(17))
			if s > 0.0:
				platform_speed = s
				_speed_explicit = true  # 1001 修复：显式 1.0（实时）曾被 auto 默认 6 倍覆盖
		elif arg.begins_with("--platform-seed="):
			platform_seed = int(arg.substr(16))
		elif arg.begins_with("--platform-loadout="):
			loadout_path = arg.substr(19)
		elif arg == "--platform-force-observe=1":
			force_observe = true
		elif arg == "--platform-probe=0":
			probe_enabled = false
		elif arg.begins_with("--platform-shots="):
			shots_interval_cfg = float(arg.substr(17))
		elif arg.begins_with("--platform-human="):
			human_slot = clampi(int(arg.substr(17)), 0, 5)


func _on_platform_match_ended(score_a: int, score_b: int, result: String) -> void:
	_finished_matches += 1
	print("[Platform] 场次#%d 结束 比分 %d-%d（%s）" % [_finished_matches, score_a, score_b, result])
	if trace_recorder != null and is_instance_valid(trace_recorder):
		trace_recorder.finalize_and_save()
	if probe != null and is_instance_valid(probe):
		var verdict: Dictionary = probe.print_final_report()
		if auto_matches > 0:
			# auto 模式：探针判定=退出码（PASS=0 / FAIL=3）——检测数据替代肉眼验收
			var ok := bool(verdict.get("pass", false))
			print("[Platform] 探针判定: %s → 退出码 %d" % ["PASS" if ok else "FAIL", 0 if ok else 3])
			print("[Platform] 自动模式完成，退出")
			get_tree().quit(0 if ok else 3)
			return
	# auto>1 不再重开（一进程一场，多种子=多次调用）——防 RESULTS 相位挂起
	if auto_matches > 0:
		print("[Platform] 自动模式完成，退出")
		get_tree().quit(0)
