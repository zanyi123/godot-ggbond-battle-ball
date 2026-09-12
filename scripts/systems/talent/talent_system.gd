## TalentSystem —— 队伍级天赋树（副系统 · E5）
## 四方向（进攻/生存/防御/增益）单实例天赋配置，全队生效：
##   stat 型   → get_team_bonuses() 汇总（player.refresh_bonuses 管道读取）
##   event 型  → 订阅 EventBus 事件 → 条件/CD 校验 → 全队执行 tags
##   manual 型 → 解锁技能进主控球员 equipped_skills（走元灵触发链，battle_manager 应用）
## 大厅点亮 → PlayerSaveManager 存档；对局内只读。
extends Node

const TREE_PATH := "res://data/systems/talent_tree/tree.json"

var tree_data: Dictionary = {}          # tree.json 原始
var unlocked: Array[String] = []        # 已点亮节点 id（存档持久化）

## 事件型天赋运行时状态 {node_id: remaining_cd}
var _event_cooldowns: Dictionary = {}
var _subscribed: bool = false

func _ready() -> void:
	_load_tree()
	unlocked.assign(PlayerSaveManager.get_team_talent_tree())

func _load_tree() -> void:
	if not FileAccess.file_exists(TREE_PATH):
		push_warning("[Talent] 天赋树数据缺失: %s" % TREE_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TREE_PATH))
	if parsed == null or not parsed is Dictionary:
		push_error("[Talent] 天赋树解析失败")
		return
	tree_data = parsed
	print("[Talent] 天赋树加载: %d 节点 / %d 方向 / 总点数 %d" % [
		(tree_data.get("nodes", []) as Array).size(),
		(tree_data.get("directions", []) as Array).size(),
		int(tree_data.get("points_total", 0))])

## ==================== 点亮与校验 ====================

## 大厅点亮入口：校验点数经济 + 前置节点
func try_unlock(node_id: String) -> bool:
	var node := get_node_data(node_id)
	if node.is_empty():
		return false
	if node_id in unlocked:
		return false
	# 前置节点
	for req in node.get("requires", []):
		if not (str(req) in unlocked):
			push_warning("[Talent] 前置未点亮: %s → %s" % [node_id, str(req)])
			return false
	# 点数经济
	if get_used_points() + int(node.get("cost", 1)) > int(tree_data.get("points_total", 0)):
		push_warning("[Talent] 点数不足: %s" % node_id)
		return false
	unlocked.append(node_id)
	PlayerSaveManager.save_team_talent_tree(unlocked)
	print("[Talent] 点亮 %s（%s/%s）已存档" % [node_id, str(node.get("direction")), str(node.get("name"))])
	return true

func get_node_data(node_id: String) -> Dictionary:
	for n in tree_data.get("nodes", []):
		if str(n.get("id")) == node_id:
			return n
	return {}

func get_used_points() -> int:
	var used := 0
	for nid in unlocked:
		used += int(get_node_data(str(nid)).get("cost", 1))
	return used

## ==================== 对局接入（battle_manager 开赛时调用一次）====================

## 对局侧初始化：event 型天赋订阅事件总线
func setup_battle() -> void:
	if _subscribed:
		return
	_subscribed = true
	var bus = BattleEventBus.get_bus(get_tree()) if is_inside_tree() else null
	if bus == null:
		push_warning("[Talent] 事件总线不存在，event 型天赋未生效")
		return
	for nid in unlocked:
		var node := get_node_data(str(nid))
		if str(node.get("type")) == "event":
			var ev := _event_name_to_enum(str(node.get("event", "")))
			if ev < 0:
				push_warning("[Talent] 未知事件: %s (%s)" % [str(node.get("event")), str(nid)])
				continue
			bus.subscribe(ev, _on_talent_event.bind({"node": node, "ev": ev}))
			print("[Talent] event 型天赋订阅: %s ← %s" % [str(nid), str(node.get("event"))])

## ==================== stat 型：队伍加成汇总 ====================

## 全队加成字典（player._recalculate_all_bonuses 读取合并）
func get_team_bonuses() -> Dictionary:
	var bonuses: Dictionary = {}
	for nid in unlocked:
		var node := get_node_data(str(nid))
		if str(node.get("type")) != "stat":
			continue
		var stat := str(node.get("stat", ""))
		if stat == "":
			continue
		bonuses[stat] = float(bonuses.get(stat, 0.0)) + float(node.get("value", 0.0))
	return bonuses

## ==================== event 型：订阅响应 ====================

func _on_talent_event(payload: Dictionary, ctx: Dictionary) -> void:
	var node: Dictionary = ctx["node"]
	var node_id := str(node.get("id"))
	# 条件
	var cond: Dictionary = node.get("condition", {})
	if not cond.is_empty() and not _check_condition(cond, payload):
		return
	# 内冷却
	var cd := float(node.get("cooldown", 0.0))
	if cd > 0.0 and float(_event_cooldowns.get(node_id, 0.0)) > 0.0:
		return
	# 全队执行 tags（全局事件-效果系统：队伍级响应）
	var tag_ids: Array = node.get("tags", [])
	if tag_ids.is_empty():
		return
	var handler = _find_tag_handler()
	if handler == null:
		push_warning("[Talent] 未找到 TagEffectHandler，%s 效果未执行" % node_id)
		return
	var team_players := _get_all_players()
	if team_players.is_empty():
		return
	for tag_id in tag_ids:
		var params: Dictionary = node.get("tag_params", {}).get(str(tag_id), {}).duplicate()
		for p in team_players:
			var pid: int = p.get_instance_id()
			var p2 := params.duplicate()
			p2["_caster_id"] = pid
			p2["_skill_id"] = "talent_" + node_id
			p2["_element"] = ""
			var result = handler.apply_tag_effect(str(tag_id), p2, pid)
			# 流程化防线：tag 未实现/写错 → 立刻警告（不做静默无效）
			if result is Dictionary and result.get("success") == false:
				push_warning("[Talent] 标签 '%s' 执行失败（未实现或参数错）@ 天赋 %s" % [str(tag_id), node_id])
	if cd > 0.0:
		_event_cooldowns[node_id] = cd
	print("[Talent] event 天赋触发: %s → 全队 %s" % [node_id, str(tag_ids)])

## 每帧内冷却递减
func _process(delta: float) -> void:
	for nid in _event_cooldowns.keys():
		if float(_event_cooldowns[nid]) > 0.0:
			_event_cooldowns[nid] = maxf(0.0, float(_event_cooldowns[nid]) - delta)

## ==================== manual 型：主控球员解锁技能 ====================

## 开赛时由 battle_manager 调用：把 manual 型天赋的 skill_id 塞进主控球员
func apply_manual_skills(controlled_player: Node) -> void:
	if controlled_player == null or not is_instance_valid(controlled_player):
		return
	for nid in unlocked:
		var node := get_node_data(str(nid))
		if str(node.get("type")) == "manual":
			var skill_id := str(node.get("skill_id", ""))
			if skill_id != "" and controlled_player.has_method("unlock_extra_skill"):
				controlled_player.unlock_extra_skill(skill_id)
			elif skill_id != "":
				# 兜底：直接塞 equipped_skills（player 端 unlock_extra_skill 未实现时）
				if not skill_id in controlled_player.equipped_skills:
					controlled_player.equipped_skills.append(skill_id)
					controlled_player.skill_cooldowns[skill_id] = 0.0
					print("[Talent] manual 技能注入: %s → %s（兜底路径）" % [skill_id, str(controlled_player.char_data.get("name", "?"))])

## ==================== 辅助 ====================

func _event_name_to_enum(name: String) -> int:
	var parts := name.split(".")
	if parts.size() != 2:
		return -1
	var prefix := parts[0].to_lower()
	for ev in BattleEventBus.GameEvent.values():
		var key: String = BattleEventBus.GameEvent.keys()[ev]
		if key.to_lower().begins_with(prefix) and key.to_lower().ends_with(parts[1].to_lower()):
			return ev
	return -1

## 首期条件：field/op/value（payload 字段；"ANY_TEAM" 哨兵=任意队受击都触发）
func _check_condition(cond: Dictionary, payload: Dictionary) -> bool:
	var field := str(cond.get("field", ""))
	var op := str(cond.get("op", "eq"))
	var value = cond.get("value")
	if value == "ANY_TEAM":
		return true  # 哨兵：不限制
	var actual = payload.get(field)
	if actual == null:
		return false
	match op:
		"eq": return actual == value
		"ne": return actual != value
		"gt", "lt", "gte", "lte":
			if not (actual is float or actual is int):
				return false
			if not (value is float or value is int):
				return false
			var av := float(actual)
			var vv := float(value)
			match op:
				"gt": return av > vv
				"lt": return av < vv
				"gte": return av >= vv
				_: return av <= vv
	return false

func _find_tag_handler() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	# spirit_system 组成员即 handler 本体（spirit_system_manager 初始化时入组）
	var members := tree.get_nodes_in_group("spirit_system")
	if members.size() > 0:
		return members[0]
	return null

func _get_all_players() -> Array:
	if GameManager == null:
		return []
	var out: Array = []
	var ta = GameManager.get("team_a")
	var tb = GameManager.get("team_b")
	if ta != null:
		out.append_array(ta)
	if tb != null:
		out.append_array(tb)
	return out
