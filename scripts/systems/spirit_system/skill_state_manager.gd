extends Node
class_name SkillStateManager
## 技能状态管理器
## 管理技能激活/取消/释放状态，支持连按2下自动释放

signal skill_activated(skill_id: String, player_id: int)
signal skill_cancelled(skill_id: String, player_id: int)
signal skill_released(skill_id: String, player_id: int)

# 技能状态
enum SkillState {
	IDLE,       # 空闲
	ACTIVATED,  # 已激活，等待释放
	RELEASING,  # 释放中
	COOLDOWN    # 冷却中
}

# 每个玩家的激活技能状态 {player_id: {slot: {skill_id, state, activation_time}}}
var _player_skills: Dictionary = {}

# 双击检测时间窗口（毫秒）
const DOUBLE_CLICK_THRESHOLD: int = 300

# 上次每个技能键按下时间 {player_id: {slot: last_press_time}}
var _last_press_times: Dictionary = {}

# 需要鼠标操作的标签（这些技能不能双击自动释放）
var _mouse_required_tags: Array[String] = [
	"ball_lockon",  # 精准锁定需要瞄准（虽然自动瞄准，但需要视觉确认）
	"ball_spread",  # 扩散需要确认
	# 其他需要鼠标操作的标签待补充
]

# 当前每个玩家的激活技能（用于UI显示）{player_id: active_skill_data}
var _active_player_skills: Dictionary = {}

## ==================== 操1（操控规划/04）：operator 子态扩展 ====================

## 12 类操作枚举（schema "operator" 字段合法值；OP_COMBO 仅保留枚举随 S1）
const OPERATORS: Array[String] = [
	"OP_AUTO", "OP_AIM", "OP_POINT", "OP_MARK", "OP_STEER", "OP_MIDFLY",
	"OP_TOGGLE", "OP_KEY_JUMP", "OP_PLACE", "OP_SUMMON", "OP_FP", "OP_COMBO",
]

## 激活后的操作子态
enum OperatorSubState { NONE, AIMING, SELECTING, MARKING, STEERING, TOGGLED }

## operator → 激活期子态映射（AUTO/PLACE/KEY_JUMP/SUMMON/FP/MIDFLY/COMBO 激活期无子态）
const OPERATOR_SUBSTATE: Dictionary = {
	"OP_AIM": OperatorSubState.AIMING,
	"OP_POINT": OperatorSubState.SELECTING,
	"OP_MARK": OperatorSubState.MARKING,
	"OP_TOGGLE": OperatorSubState.TOGGLED,
}

# 每玩家当前操作上下文 {player_id: {operator, substate, skill_id, slot, midfly_left}}
var _operator_context: Dictionary = {}
var test_ball: Node = null  # 测试注入口（MIDFLY 干预目标球；生产走 controlled_player.ball_ref 链）

## 读技能 operator（缺省 OP_AUTO；非法值回落 AUTO）
func get_operator(skill_id: String) -> String:
	var op := str(_get_skill_data(skill_id).get("operator", "OP_AUTO"))
	return op if op in OPERATORS else "OP_AUTO"

## 当前操作子态名（无激活=""/NONE）
func get_operator_substate(player_id: int) -> String:
	if not _operator_context.has(player_id):
		return ""
	var sub: int = _operator_context[player_id].get("substate", 0)
	if sub == OperatorSubState.NONE:
		return ""
	for key in OperatorSubState.keys():
		if OperatorSubState[key] == sub:
			return key
	return ""

## 当前激活技能的 operator 名（无激活=""）
func get_active_operator(player_id: int) -> String:
	if _operator_context.has(player_id):
		return str(_operator_context[player_id].get("operator", "OP_AUTO"))
	return ""

## 左键确认（AIMING/SELECTING/MARKING 子态的左键推进）：释放技能走既有链
func confirm_substate(player_id: int) -> bool:
	if not _operator_context.has(player_id):
		return false
	var ctx: Dictionary = _operator_context[player_id]
	var sub: int = int(ctx.get("substate", 0))
	if sub in [OperatorSubState.AIMING, OperatorSubState.SELECTING, OperatorSubState.MARKING]:
		_release_skill(player_id, int(ctx["slot"]))
		_operator_context.erase(player_id)
		return true
	return false

## 取消（C/再按）：清操作上下文
func _clear_operator_context(player_id: int) -> void:
	_operator_context.erase(player_id)


func _ready() -> void:
	pass


## 设置玩家上场技能
func setup_player_skills(player_id: int, skill_ids: Array[String]) -> void:
	_player_skills[player_id] = {}
	for i in range(skill_ids.size()):
		_player_skills[player_id][i] = {
			"skill_id": skill_ids[i],
			"state": SkillState.IDLE,
			"activation_time": 0.0
		}
	_last_press_times[player_id] = {}


## 技能键按下
func on_skill_key_pressed(player_id: int, slot: int) -> bool:
	"""返回是否应该自动释放（双击）"""
	var current_time := Time.get_ticks_msec()

	if not _player_skills.has(player_id):
		print("[SkillState] 玩家未设置技能: %d" % player_id)
		return false

	if not _player_skills[player_id].has(slot):
		print("[SkillState] 玩家没有该位置技能: player=%d slot=%d" % [player_id, slot])
		return false

	var skill_info = _player_skills[player_id][slot]
	var skill_id = skill_info.skill_id
	var skill_data = _get_skill_data(skill_id)

	# 检查冷却
	if skill_info.state == SkillState.COOLDOWN:
		print("[SkillState] 技能冷却中: %s" % skill_id)
		return false

	# 操1 OP_MIDFLY：飞行中（RELEASING 态=球已投出）再按同键 → 干预（拉回/推进），次数受限
	if skill_info.state == SkillState.RELEASING and get_operator(skill_id) == "OP_MIDFLY":
		return _trigger_midfly(player_id, skill_id)

	# 检测双击
	if _last_press_times[player_id].has(slot):
		var last_press = _last_press_times[player_id][slot]
		var time_diff = current_time - last_press

		if time_diff <= DOUBLE_CLICK_THRESHOLD:
			# 双击：取消激活状态，直接释放
			print("[SkillState] 双击检测: skill=%s, 自动释放" % skill_id)
			_last_press_times[player_id].erase(slot)

			# 如果之前已激活，先取消激活
			if skill_info.state == SkillState.ACTIVATED:
				_cancel_active_skill(player_id)

			# 直接释放
			_release_skill(player_id, slot)
			return true  # 自动释放

	# 单击：激活技能（如果不是自动释放类型）
	_last_press_times[player_id][slot] = current_time

	# 如果已激活，再次按下表示取消
	if skill_info.state == SkillState.ACTIVATED:
		# 操1 OP_TOGGLE：TOGGLED 态再按 = 切换/关闭（对齐波5 #13 toggle 语义，不复写）
		if _operator_context.get(player_id, {}).get("substate", 0) == OperatorSubState.TOGGLED:
			print("[SkillState] toggle 关闭: skill=%s" % skill_id)
			_release_skill(player_id, slot)
			_operator_context.erase(player_id)
			return false
		print("[SkillState] 取消激活: skill=%s" % skill_id)
		_cancel_active_skill(player_id)
		return false

	# 激活技能
	print("[SkillState] 激活技能: skill=%s" % skill_id)
	_activate_skill(player_id, slot)
	return false  # 不自动释放


## 波操1 OP_MIDFLY：飞行中干预（调 ball 既有 recall_ball/boost_in_flight；次数=midfly_left）
func _trigger_midfly(player_id: int, skill_id: String) -> bool:
	var ctx: Dictionary = _operator_context.get(player_id, {})
	var left: int = int(ctx.get("midfly_left", 0))
	if left <= 0:
		print("[SkillState] MIDFLY 次数耗尽: %s" % skill_id)
		return false
	_operator_context[player_id]["midfly_left"] = left - 1
	# 球引用：经 input_manager(父) 的 controlled_player.ball_ref（P1-1 注入）或 battle_manager.ball_node
	var ball = test_ball  # 测试注入口优先
	var parent = get_parent()
	if parent != null:
		var cp = parent.get("controlled_player")
		if cp != null and is_instance_valid(cp) and cp.get("ball_ref") != null:
			ball = cp.get("ball_ref")
	if ball == null:
		var bm = parent.get("battle_manager") if parent != null else null
		if bm != null:
			ball = bm.get("ball_node")
	if ball == null or not is_instance_valid(ball) or not ball.is_active:
		print("[SkillState] MIDFLY: 球不在飞行中")
		return false
	if ball.has_method("recall_ball"):
		ball.recall_ball(1)
	elif ball.has_method("boost_in_flight"):
		ball.boost_in_flight({})
	print("[SkillState] MIDFLY 干预: %s 剩余次数 %d" % [skill_id, left - 1])
	return true


## 取消当前激活的技能（C键）
func cancel_active_skill(player_id: int) -> bool:
	"""返回是否成功取消"""
	if not _active_player_skills.has(player_id):
		return false

	var active_data = _active_player_skills[player_id]
	var slot = active_data.slot

	_cancel_active_skill(player_id)
	return true


## 激活技能
func _activate_skill(player_id: int, slot: int) -> void:
	var skill_info = _player_skills[player_id][slot]
	skill_info.state = SkillState.ACTIVATED
	skill_info.activation_time = Time.get_ticks_msec()

	# 记录激活技能
	_active_player_skills[player_id] = {
		"skill_id": skill_info.skill_id,
		"slot": slot,
		"activation_time": skill_info.activation_time
	}

	# 操1 大点2：按 operator 进入激活期子态
	var operator: String = get_operator(skill_info.skill_id)
	var substate: int = OperatorSubState.NONE
	if OPERATOR_SUBSTATE.has(operator):
		substate = OPERATOR_SUBSTATE[operator]
	var ctx: Dictionary = {"operator": operator, "substate": substate, "skill_id": skill_info.skill_id, "slot": slot}
	# OP_MIDFLY：初始化干预次数（tag_params.ball_recall.max_times）
	if operator == "OP_MIDFLY":
		var midfly_left := 0
		var sd: Dictionary = _get_skill_data(skill_info.skill_id)
		for tag_id in sd.get("tag_params", {}):
			if tag_id == "ball_recall" or tag_id == "ball_in_flight_boost":
				midfly_left = maxi(midfly_left, int(sd["tag_params"][tag_id].get("max_times", 0)))
		ctx["midfly_left"] = midfly_left
	_operator_context[player_id] = ctx

	skill_activated.emit(skill_info.skill_id, player_id)
	print("[SkillState] 技能已激活: %s (玩家:%d, 位置:%d, op=%s)" % [skill_info.skill_id, player_id, slot, operator])


## 取消激活技能
func _cancel_active_skill(player_id: int) -> void:
	if not _active_player_skills.has(player_id):
		return

	var active_data = _active_player_skills[player_id]
	var slot = active_data.slot
	var skill_id = active_data.skill_id

	# 清除激活状态
	_player_skills[player_id][slot].state = SkillState.IDLE
	_active_player_skills.erase(player_id)
	_clear_operator_context(player_id)

	skill_cancelled.emit(skill_id, player_id)
	print("[SkillState] 技能已取消: %s (玩家:%d)" % [skill_id, player_id])


## 释放技能
func _release_skill(player_id: int, slot: int) -> void:
	var skill_info = _player_skills[player_id][slot]
	var skill_id = skill_info.skill_id

	# 设置为释放中
	skill_info.state = SkillState.RELEASING

	# 清除激活记录
	_active_player_skills.erase(player_id)
	# 操1 OP_MIDFLY：保留操作上下文（飞行中再按干预需 midfly_left；球结算时经 _release 时清）
	if get_operator(skill_id) != "OP_MIDFLY":
		_clear_operator_context(player_id)

	skill_released.emit(skill_id, player_id)
	print("[SkillState] 技能已释放: %s (玩家:%d)" % [skill_id, player_id])


## 技能释放完成（冷却开始）
func on_skill_released_complete(player_id: int, skill_id: String, cooldown: float) -> void:
	"""外部调用，表示技能释放完成，进入冷却"""
	if not _player_skills.has(player_id):
		return

	for slot in _player_skills[player_id]:
		if _player_skills[player_id][slot].skill_id == skill_id:
			_player_skills[player_id][slot].state = SkillState.COOLDOWN
			print("[SkillState] 技能进入冷却: %s, 冷却时间: %.1f" % [skill_id, cooldown])
			break


## 冷却结束
func on_cooldown_finished(player_id: int, skill_id: String) -> void:
	"""外部调用，表示技能冷却完成"""
	if not _player_skills.has(player_id):
		return

	for slot in _player_skills[player_id]:
		if _player_skills[player_id][slot].skill_id == skill_id:
			_player_skills[player_id][slot].state = SkillState.IDLE
			print("[SkillState] 技能冷却完成: %s" % skill_id)
			break


## 获取玩家当前激活的技能
func get_active_skill(player_id: int) -> Dictionary:
	"""返回 {skill_id, slot, activation_time} 或空字典"""
	if _active_player_skills.has(player_id):
		return _active_player_skills[player_id]
	return {}


## 检查技能是否需要鼠标操作
func is_mouse_required(skill_id: String) -> bool:
	var skill_data = _get_skill_data(skill_id)
	if skill_data.is_empty():
		return false

	var tags = skill_data.get("tags", [])
	for tag_id in tags:
		if tag_id in _mouse_required_tags:
			return true

	return false


## 获取技能数据
func _get_skill_data(skill_id: String) -> Dictionary:
	if not FileAccess.file_exists("res://data/spirits/skills.json"):
		return {}

	var file = FileAccess.open("res://data/spirits/skills.json", FileAccess.READ)
	if not file:
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		return {}

	var skills_array = json.data.get("skills", [])
	for skill in skills_array:
		if skill.get("id", "") == skill_id:
			return skill

	return {}


## 清理玩家数据
func cleanup_player(player_id: int) -> void:
	_player_skills.erase(player_id)
	_last_press_times.erase(player_id)
	_active_player_skills.erase(player_id)
