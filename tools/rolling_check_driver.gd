## 22-3 存量滚动抽检 driver（操球窗口轮值，工单15§六/技能规划22档§二）
## 每轮抽 3~5 条实配技能，AI 完全体真场景释放（battle_arena 全 AI），信号判定对照
## 《技能规划/21_技能标签UI验收标志对照表》通道①数据源（判定层只读信号）——
## 21 表口径："UI 上有图标=判定层确实生效"，headless 下以同一信号源判定，可视终验归主人。
## 红线：测试工单不改玩法；数据零触碰（只装备既有元灵）；发现问题按 bug_fix 另立不顺手修。
## 运行：Godot_console.exe --headless --path . res://tools/rolling_check_launcher.tscn -- --seed=N
extends Node

## 第一轮抽检清单（2026-09-27；候选池=15工单F1诊断基线的已出手3条+BALL两技断点1实证）
## 判定口径（21表）：
##  岩石墙   field_obs_add  FIELD障碍 → 释放成功 且 场上真实障碍产出（11号Q12放置流断裂疑点，本抽检实证）
##  生机护体 player_hp_regen+def_up_pct PLAYER → 释放成功 且 施法者回血/减伤行为（regen=hp上行）
##  虚幻迷踪 player_stealth+spd_up_pct PLAYER → 释放成功 且 "隐"图标判定源（stealthed 状态灯）亮
##  猛虎攻击 ball_dmg_up_pct+ball_range_up BALL → 释放成功（F2记录0出手=断点1实证）
##  雷霆投掷 ball_dmg_up_pct+ball_speed_up_pct BALL → 同上
const CHECK_SKILLS: Dictionary = {
	"skill_大地_1": {"name": "岩石墙", "route": "FIELD", "expect": "释放成功+障碍产出（放墙真实落地）"},
	"skill_草木_1": {"name": "生机护体", "route": "PLAYER", "expect": "释放成功+回血/减伤行为"},
	"skill_梦幻_1": {"name": "虚幻迷踪", "route": "PLAYER", "expect": "释放成功+stealth 状态灯（隐图标判定源）"},
	"skill_金刚_1": {"name": "猛虎攻击", "route": "BALL", "expect": "释放成功（0出手即断点1实证）"},
	"skill_雷火_1": {"name": "雷霆投掷", "route": "BALL", "expect": "释放成功（0出手即断点1实证）"},
}

var bm: Node = null
var casts: Dictionary = {}            # skill_id -> {ok: int, fail: int}
var stealth_seen: bool = false        # 虚幻迷踪判定源：任一球员 stealthed 状态灯亮过
var regen_hp_rise: bool = false       # 生机护体判定源：释放后窗口内任一球员 stamina 上行
var _hou_ok_at: float = -1.0          # 生机护体最近成功释放时刻（waited 秒）
var _stam_last: Dictionary = {}       # {instance_id: float} 上次采样快照
var zone_spawn_seen: bool = false     # 岩石墙判定源：障碍产出信号/计数上行
var zone_count_0: int = -1
var match_over: bool = false
var _waited: float = 0.0            # 赛中 waited 秒（释放窗口判定基准）

const WATCH_IDS: Array[String] = ["skill_大地_1", "skill_草木_1", "skill_梦幻_1", "skill_金刚_1", "skill_雷火_1"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_val := 1
	for a in args:
		if a.begins_with("--seed="):
			seed_val = int(a.substr(7))
	seed(seed_val)
	print("[RollingCheck] 22-3 抽检启动 seed=%d 清单=%s" % [seed_val, str(WATCH_IDS)])
	await get_tree().process_frame
	await get_tree().process_frame
	bm = get_tree().root.get_node_or_null("RollingCheck/Arena")
	if bm == null:
		for c in get_tree().root.get_children():
			if c.get_script() and str(c.get_script().resource_path).contains("battle_manager"):
				bm = c
	if bm == null:
		print("[RollingCheck] FAIL: 未找到 battle_manager")
		get_tree().quit(1)
		return
	_connect_signals()
	_run()


func _connect_signals() -> void:
	var ss = bm.get("spirit_system")
	if ss == null:
		return
	if ss.has_signal("skill_used"):
		ss.skill_used.connect(_on_skill_used)


func _on_skill_used(skill_id: String, _caster_id: int, success: bool) -> void:
	var e: Dictionary = casts.get(skill_id, {"ok": 0, "fail": 0})
	if success:
		e["ok"] = int(e["ok"]) + 1
		if skill_id == "skill_草木_1":
			_hou_ok_at = _waited
	else:
		e["fail"] = int(e["fail"]) + 1
	casts[skill_id] = e


func _sample_zone_count() -> void:
	var om = bm.get("obstacle_manager")
	if om == null and is_inside_tree():
		om = get_tree().get_first_node_in_group("obstacle_managers")
	if om != null and om.get("obstacles") != null:
		var n: int = (om.get("obstacles") as Array).size()
		if zone_count_0 < 0:
			zone_count_0 = n
		elif n > zone_count_0:
			zone_spawn_seen = true


func _run() -> void:
	# 装备+开赛全走 --sim 自动链（_parse_sim_args→_auto_equip_spirits_for_sim→自动开赛），
	# driver 只挂信号采样等结束；不再手动 set auto_simulate（球员创建后置位太晚=空装备）
	var gm = get_tree().root.get_node_or_null("GameManager")
	# 双保险：①match_ended deferred 连接（quit() 帧末才生效，deferred 报告先于退出）
	# ②轮询 RESULTS 相位（_set_phase 先于 bm 同步 quit 链，轮询粒度 1s 内必命中其一）
	if gm != null and gm.has_signal("match_ended"):
		gm.match_ended.connect(_on_match_ended, CONNECT_DEFERRED)
	_waited = 0.0
	while not match_over and _waited < 300.0:
		await get_tree().create_timer(1.0).timeout
		_waited += 1.0
		if gm != null and int(gm.get("match_phase")) == 4:  # MatchPhase.RESULTS
			match_over = true
		# 赛中周期采样障碍计数（岩墙可能有寿命）
		_sample_zone_count()
		regen_check()
	_final_report()


## 生机护体判定源：释放后 8s 窗口内任一球员 stamina 上行 ≥1（回血行为；血量字段=stamina）
## 虚幻迷踪判定源：任一球员 stealthed 状态灯亮过（get_status_lights_view=图标条数据源）
func regen_check() -> void:
	# 判定升级（三种子复盘：满血时 stamina 上行不可见）——改为检测 regen tick 效果实体：
	# handler _apply_player_hp_regen → target.add_tick_effect("hp_regen_<id>", "regen", rate, duration)
	# 释放后窗口内任一球员 _tick_effects 含 hp_regen_ 前缀键 = 效果真实落地（21表通道①数据源同级证据）
	var in_window: bool = _hou_ok_at >= 0.0 and (_waited - _hou_ok_at) < 10.0
	if in_window and not regen_hp_rise:
		for arr_name in ["team_a_players", "team_b_players"]:
			var arr = bm.get(arr_name)
			if not arr is Array:
				continue
			for p in arr:
				if p == null or not is_instance_valid(p):
					continue
				var te = p.get("_tick_effects")
				if te is Dictionary:
					for k in (te as Dictionary).keys():
						if str(k).begins_with("hp_regen_"):
							regen_hp_rise = true
							break
			if regen_hp_rise:
				break
	if not stealth_seen:
		for arr_name in ["team_a_players", "team_b_players"]:
			var arr2 = bm.get(arr_name)
			if not arr2 is Array:
				continue
			for p2 in arr2:
				if p2 == null or not is_instance_valid(p2):
					continue
				if p2.has_method("get_status_lights_view") and p2.get_status_lights_view().has("stealthed"):
					stealth_seen = true
					break


func _on_match_ended(_a: int, _b: int, _r: String) -> void:
	match_over = true
	_final_report()


func _final_report() -> void:
	print("\n[RollingCheck] ========== 22-3 第一轮抽检判定（对照21表） ==========")
	var pass_n: int = 0
	var total: int = WATCH_IDS.size()
	for sid in WATCH_IDS:
		var meta: Dictionary = CHECK_SKILLS[sid]
		var c: Dictionary = casts.get(sid, {"ok": 0, "fail": 0})
		var ok_n := int(c.get("ok", 0))
		var fail_n := int(c.get("fail", 0))
		var extra := ""
		var effect_ok := false
		match sid:
			"skill_大地_1":
				effect_ok = zone_spawn_seen
				extra = " 障碍产出=%s" % ("✅" if zone_spawn_seen else "❌（0产出=Q12放置流断裂实证）")
			"skill_草木_1":
				effect_ok = regen_hp_rise
				extra = " 回血行为=%s" % ("✅" if regen_hp_rise else "❓（本场未见 hp 满上行）")
			"skill_梦幻_1":
				effect_ok = stealth_seen
				extra = " stealth灯=%s" % ("✅" if stealth_seen else "❌（隐图标判定源未亮）")
			_:
				effect_ok = ok_n > 0
				extra = ""
		var verdict := "✅" if (ok_n > 0 and effect_ok) else ("⚠释放但无效果实证" if ok_n > 0 else "❌0出手")
		if ok_n > 0 and effect_ok:
			pass_n += 1
		print("[RollingCheck] %s %s[%s] 出手%d/失败%d → %s%s（期望：%s）" % [
			verdict, str(meta.get("name")), str(meta.get("route")), ok_n, fail_n,
			str(meta.get("expect")), extra, ""])
	print("[RollingCheck] 结果: %d/%d 全链通过（出手+效果双证）\n" % [pass_n, total])
	get_tree().quit(0 if pass_n > 0 else 1)
