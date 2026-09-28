extends Node
## 11框架一期：团队合击追踪器（同窗爆发型）——主人 0928-2 批"可以开"
## 登记层：监听 spirit_system.skill_used，按 data/skills/team_combos.json 反向索引（零改 skills.json）；
## 聚合层：固定步长周期判定——窗口秒内 distinct 施法者按 role 计数达 required → emit team_combo_formed；
## 结算层：on_formed 条目引用既有标签经 handler.apply_tag_effect 施加（scope 解析成员队伍）；
## 纪律：窗口=累积秒（固定步长确定性），禁墙钟禁全局随机流；成立后同窗冷却防重复；
## 二期挂点：main 登记时发 COMBO_SETUP 邀约（protocol_v2 开波后启用，接口位见 _on_skill_used 注释）。
## 对齐承诺：S1 OP_COMBO 协调器零改动——本文件为独立新增节点，与协调器无代码交叉。

signal team_combo_formed(combo_id: String, members: Array, params: Dictionary)

const COMBO_TABLE := "res://data/skills/team_combos.json"
const CHECK_INTERVAL: float = 0.2  # 判定周期（与 S1 协调器同款）

var _combos: Dictionary = {}        # combo_id -> 定义（trigger/settlement）
var _skill_index: Dictionary = {}   # skill_id -> Array[{combo_id, role}]
var _window_seconds: Dictionary = {}  # combo_id -> float
var _regs: Dictionary = {}          # combo_id -> Array[{t, caster_id, node, role}]
var _formed_until: Dictionary = {}  # combo_id -> float（成立冷却至窗口尾）
var _formed_count: Dictionary = {}  # combo_id -> int（统计）
var _elapsed: float = 0.0
var _accum: float = 0.0
var _ss: Node = null                # SpiritSystemManager（skill_used 信号源）
var _handler: Node = null           # 标签效果处理器（结算出口）
var _bm: Node2D = null              # battle_manager（scope 队伍解析；首个施法者时懒解析）


func _ready() -> void:
	add_to_group("team_combo_trackers")
	_load_table()


## 由 spirit_system_manager 挂载后调用（信号源+结算出口）
func setup(spirit_system_manager: Node) -> void:
	_ss = spirit_system_manager
	if _ss == null:
		return
	if _ss.has_signal("skill_used"):
		_ss.skill_used.connect(_on_skill_used)
	if _ss.get("tag_effect_handler") != null:
		_handler = _ss.tag_effect_handler


func _load_table() -> void:
	if not FileAccess.file_exists(COMBO_TABLE):
		print("[TeamCombo] ⚠ 框架表不存在: %s（合击判定停用）" % COMBO_TABLE)
		return
	var f := FileAccess.open(COMBO_TABLE, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary or not (parsed.get("combos", []) is Array):
		print("[TeamCombo] ⚠ 框架表格式非法")
		return
	for def in parsed["combos"]:
		if not def is Dictionary:
			continue
		var cid := str(def.get("combo_id", ""))
		var trigger: Dictionary = def.get("trigger", {})
		var members = trigger.get("members", [])
		if cid.is_empty() or not members is Array or members.is_empty():
			print("[TeamCombo] ⚠ 合击定义缺 combo_id/members，跳过: %s" % cid)
			continue
		_combos[cid] = def
		_window_seconds[cid] = float(trigger.get("window_seconds", 5.0))
		_regs[cid] = []
		for m in members:
			if not m is Dictionary:
				continue
			var sid := str(m.get("skill_id", ""))
			if sid.is_empty():
				continue
			if not _skill_index.has(sid):
				_skill_index[sid] = []
			_skill_index[sid].append({"combo_id": cid, "role": str(m.get("role", "assist"))})
	print("[TeamCombo] 框架表加载: %d 合击 / %d 技能索引（窗口判定周期 %.1fs）" % [
		_combos.size(), _skill_index.size(), CHECK_INTERVAL])


func _process(delta: float) -> void:
	if _combos.is_empty():
		return
	_elapsed += delta
	_accum += delta
	if _accum < CHECK_INTERVAL:
		return
	_accum = 0.0
	_try_form_combos()


## 聚合判定（public：测试可直调，同 S1 try_form_combos 惯例）。返回本次新成立数。
func _try_form_combos() -> int:
	var formed := 0
	# 窗口过期清理（累积秒；固定步长下确定性）——判定前统一清，直调/信号两路同语义
	for cid in _regs:
		var keep: Array = []
		for reg in _regs[cid]:
			if _elapsed - float(reg["t"]) <= float(_window_seconds[cid]):
				keep.append(reg)
		_regs[cid] = keep
	for cid in _combos:
		if _elapsed < float(_formed_until.get(cid, 0.0)):
			continue  # 同窗冷却中
		var members_def: Array = _combos[cid]["trigger"]["members"]
		var ok := true
		var member_nodes: Array = []
		var used_casters: Dictionary = {}  # 一人只占一个 role（先到先得）
		for mdef in members_def:
			var role := str(mdef.get("role", "assist"))
			var required := int(mdef.get("required", 1))
			var distinct: Array = []
			for reg in _regs[cid]:
				if str(reg["role"]) != role:
					continue
				var cid_cast := int(reg["caster_id"])
				if used_casters.has(cid_cast) or cid_cast in distinct:
					continue
				distinct.append(cid_cast)
				if distinct.size() >= required:
					break
			if distinct.size() < required:
				ok = false
				break
			for cid_cast in distinct:
				used_casters[cid_cast] = role
				for reg in _regs[cid]:
					if int(reg["caster_id"]) == cid_cast and str(reg["role"]) == role:
						member_nodes.append(reg["node"])
						break
		if not ok:
			continue
		# 合击成立
		formed += 1
		_formed_count[cid] = int(_formed_count.get(cid, 0)) + 1
		_formed_until[cid] = _elapsed + float(_window_seconds[cid])
		_regs[cid] = []  # 已消费，清窗防连锁重触
		var params: Dictionary = {
			"window_seconds": float(_window_seconds[cid]),
			"stacks": member_nodes.size(),
		}
		print("[TeamCombo] ✨ 合击成立 %s：成员[%s]" % [cid, _members_desc(member_nodes)])
		_apply_settlement(cid, member_nodes)
		team_combo_formed.emit(cid, member_nodes, params)
	return formed


func _apply_settlement(cid: String, member_nodes: Array) -> void:
	var def: Dictionary = _combos[cid]
	var settlement = def.get("settlement", [])
	if not settlement is Array or settlement.is_empty():
		return
	var team := ""
	if not member_nodes.is_empty() and is_instance_valid(member_nodes[0]):
		team = str(member_nodes[0].get("team"))
		if _bm == null:
			_bm = _resolve_battle_manager(member_nodes[0])
	for entry in settlement:
		if not entry is Dictionary or str(entry.get("timing", "on_formed")) != "on_formed":
			continue  # on_ball_hit/on_caught = 事件总线结算（二期）
		for target in _resolve_scope(str(entry.get("scope", "allies")), team):
			if _handler != null and _handler.has_method("apply_tag_effect"):
				_handler.apply_tag_effect(str(entry["tag"]), (entry.get("params", {}) as Dictionary).duplicate(true), target.get_instance_id())


## scope 解析（一期：allies/enemies；ball/field 载体=二期事件总线结算）
func _resolve_scope(scope: String, team: String) -> Array:
	var out: Array = []
	if _bm == null:
		return out
	var own: Array = _bm.team_a_players if team == "a" else _bm.team_b_players
	var foe: Array = _bm.team_b_players if team == "a" else _bm.team_a_players
	match scope:
		"allies":
			for p in own:
				if p != null and is_instance_valid(p) and not p.is_defeated:
					out.append(p)
		"enemies":
			for p in foe:
				if p != null and is_instance_valid(p) and not p.is_defeated:
					out.append(p)
	return out


func _resolve_battle_manager(caster: Node) -> Node2D:
	var node: Node = caster
	while node != null:
		if node.get("team_a_players") != null and node.get("team_b_players") != null:
			return node as Node2D
		node = node.get_parent()
	return null


func _members_desc(members: Array) -> String:
	var parts: Array[String] = []
	for m in members:
		if m != null and is_instance_valid(m):
			var cd = m.get("char_data")
			parts.append(str(cd.get("name", m.name)) if cd != null else str(m.name))
		else:
			parts.append(str(m))
	return ", ".join(parts)


## 登记入口（测试直调口）
func register_cast(skill_id: String, caster_id: int) -> void:
	var sid := str(skill_id)
	if not _skill_index.has(sid):
		return
	var caster = instance_from_id(caster_id)
	if caster == null or not is_instance_valid(caster):
		return
	if _bm == null:
		_bm = _resolve_battle_manager(caster)
	for entry in _skill_index[sid]:
		var cid := str(entry["combo_id"])
		if not _regs.has(cid):
			continue
		_regs[cid].append({"t": _elapsed, "caster_id": caster_id, "node": caster, "role": str(entry["role"])})
		# 二期挂点：role=="main" 登记时经 protocol_v2 发 COMBO_SETUP 邀约（开波后启用）


## 信号源入口（success 过滤后转登记）
func _on_skill_used(skill_id: String, caster_id: int, success: bool) -> void:
	if success:
		register_cast(skill_id, caster_id)


## 查询口（观测层/测试）
func get_formed_count(combo_id: String = "") -> int:
	if combo_id.is_empty():
		var total := 0
		for cid in _formed_count:
			total += int(_formed_count[cid])
		return total
	return int(_formed_count.get(combo_id, 0))
