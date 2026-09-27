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
enum OperatorSubState { NONE, AIMING, SELECTING, MARKING, STEERING, TOGGLED, SUMMONING }

## operator → 激活期子态映射（AUTO/PLACE/KEY_JUMP/FP/MIDFLY/COMBO 激活期无子态）
const OPERATOR_SUBSTATE: Dictionary = {
	"OP_AIM": OperatorSubState.AIMING,
	"OP_POINT": OperatorSubState.SELECTING,
	"OP_MARK": OperatorSubState.MARKING,
	"OP_TOGGLE": OperatorSubState.TOGGLED,
	"OP_SUMMON": OperatorSubState.SUMMONING,
}

# 每玩家当前操作上下文 {player_id: {operator, substate, skill_id, slot, midfly_left}}
var _operator_context: Dictionary = {}
var test_ball: Node = null  # 测试注入口（MIDFLY 干预目标球；生产走 controlled_player.ball_ref 链）

# 操2 大点1.5（2026-09-24 规划追加）：操作维度总开关（副系统"可开关"规范）
# 关闭时 get_operator 一律返回 OP_AUTO（子态/干预/跳跃/标记路由全旁路，行为=无此系统）；
# 不改任何接口签名；默认开启
var operator_system_enabled: bool = true

## 读技能 operator（缺省 OP_AUTO；非法值回落 AUTO；总开关关闭时强制 AUTO）
func get_operator(skill_id: String) -> String:
	if not operator_system_enabled:
		return "OP_AUTO"
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

## 左键确认（既有入口，兼容）：普通子态直接释放；再击/召唤走 confirm_substate_at
func confirm_substate(player_id: int) -> bool:
	return confirm_substate_at(player_id, Vector2.ZERO) != ""

## 操1 增补（操控规划/05）：带世界坐标的左键推进（再击两段/三段、召唤、普通确认）
## 返回动作名："released"=真释放 / "selected"=再击第一段仅选中 / "summoned"=召唤指令 / ""=无上下文不消费
## last_confirm_info 留存最近一次推进详情（测试/上层可读）
var last_confirm_info: Dictionary = {}

func confirm_substate_at(player_id: int, world_pos: Vector2) -> String:
	last_confirm_info = {}
	if not _operator_context.has(player_id):
		return ""
	var ctx: Dictionary = _operator_context[player_id]
	var sub: int = int(ctx.get("substate", 0))

	# 项7 SUMMON 基础版：左键地面 = 召唤体移动/出现到指定位置（v1 点击式；无召唤体告警不崩溃）
	if sub == OperatorSubState.SUMMONING:
		ctx["summon_order"] = {"position": world_pos}
		_release_skill(player_id, int(ctx["slot"]))
		_notify_summon_order(player_id, world_pos)
		last_confirm_info = {"action": "summoned", "position": world_pos}
		_operator_context.erase(player_id)
		return "summoned"

	# 项2 左键再击（05 §3.2）：stage1=选中对象不生效；stage2=真释放（direction 型由选中点→当前鼠标定向）
	var stage: int = int(ctx.get("reclick_stage", 0))
	if stage == 1:
		ctx["selected"] = {"position": world_pos}
		ctx["reclick_stage"] = 2
		last_confirm_info = {"action": "selected", "position": world_pos}
		return "selected"
	if stage == 2:
		var sel: Dictionary = ctx.get("selected", {})
		var aim_dir: Vector2 = (world_pos - sel.get("position", world_pos)).normalized()
		if str(ctx.get("reclick_mode", "")) == "direction" and aim_dir.length_squared() > 0.0001:
			sel["direction"] = aim_dir
			ctx["selected"] = sel
		_release_skill(player_id, int(ctx["slot"]))
		last_confirm_info = {"action": "released", "position": world_pos, "selected": sel.duplicate(true)}
		_operator_context.erase(player_id)
		return "released"

	# 普通子态：直接释放（既有行为）
	if sub in [OperatorSubState.AIMING, OperatorSubState.SELECTING, OperatorSubState.MARKING]:
		_release_skill(player_id, int(ctx["slot"]))
		last_confirm_info = {"action": "released", "position": world_pos}
		_operator_context.erase(player_id)
		return "released"
	return ""

## 项3 拖长击（05 §3.3）：松开时 a 对 b 作用——选中记录 a/b 两端后释放（v1 目标写入 selected 供效果链消费）
func confirm_drag(player_id: int, a_pos: Vector2, b_node: Node2D, b_pos: Vector2) -> bool:
	if not _operator_context.has(player_id):
		return false
	var ctx: Dictionary = _operator_context[player_id]
	ctx["selected"] = {"position": b_pos, "source_position": a_pos, "drag_target": b_node}
	_release_skill(player_id, int(ctx["slot"]))
	last_confirm_info = {"action": "released", "drag": true, "source_position": a_pos, "position": b_pos}
	_operator_context.erase(player_id)
	return true

## 项4 右键=取消选中（05 §3.4）：清选中/重置再击段数，子态保留可重选（不整段取消激活）
func clear_substate_selection(player_id: int) -> bool:
	if not _operator_context.has(player_id):
		return false
	var ctx: Dictionary = _operator_context[player_id]
	if not ctx.has("reclick_stage") and not ctx.has("selected"):
		return false
	ctx.erase("selected")
	if ctx.has("reclick_stage"):
		ctx["reclick_stage"] = 1
	return true

## 项1 按键迁移窗口（05 §1）：STEER 类激活期（操1 设计：STEER 无激活子态，激活即窗口）+ STEERING 子态（前瞻兼容）
## 投出后飞行段由 input_manager 依球 _manual_active 补判；MIDFLY 为按键干预型无向量语义，不进迁移窗口（上报备注）
func is_key_migration_active(player_id: int) -> bool:
	if not operator_system_enabled:
		return false
	if not _operator_context.has(player_id):
		return false
	var ctx: Dictionary = _operator_context[player_id]
	if str(ctx.get("operator", "")) == "OP_STEER":
		return true
	return int(ctx.get("substate", 0)) == OperatorSubState.STEERING

## 项3 拖长击参数：snap 吸附半径（skill params.snap_radius，缺省 80）
func get_drag_snap_radius(player_id: int) -> float:
	if not _operator_context.has(player_id):
		return 80.0
	var sd: Dictionary = _get_skill_data(str(_operator_context[player_id].get("skill_id", "")))
	var p: Dictionary = sd.get("params", {})
	if p.has("snap_radius"):
		return float(p["snap_radius"])
	for tag_id in sd.get("tag_params", {}):
		var tp: Dictionary = sd["tag_params"][tag_id]
		if tp.has("snap_radius"):
			return float(tp["snap_radius"])
	return 80.0

## 项7 召唤指令下发（v1：无召唤体登记时告警不崩溃；实体登记随 S5）
func _notify_summon_order(player_id: int, world_pos: Vector2) -> void:
	var summons: Array = []
	var parent = get_parent()
	if parent != null:
		var cp = parent.get("controlled_player")
		if cp != null and is_instance_valid(cp):
			var s = cp.get("summons")
			if s is Array:
				summons = s
	if summons.is_empty():
		print("[SkillState] SUMMON: 无召唤体可指挥（v1 点击式，实体登记随 S5） pos=%s" % str(world_pos))
		return
	for s in summons:
		if is_instance_valid(s) and s.has_method("order_move_to"):
			s.order_move_to(world_pos)

## 项2 reclick 标记读取：skill params.reclick 或任一 tag_params.reclick（true=两段式；"direction"=三段式定弧口）
func _skill_reclick_mode(skill_id: String) -> String:
	var sd: Dictionary = _get_skill_data(skill_id)
	var p: Dictionary = sd.get("params", {})
	if p.has("reclick"):
		var rv := str(p["reclick"])
		return "true" if rv == "true" else rv
	for tag_id in sd.get("tag_params", {}):
		var tp: Dictionary = sd["tag_params"][tag_id]
		if tp.has("reclick"):
			var tv := str(tp["reclick"])
			return "true" if tv == "true" else tv
	return ""

## 项3 drag 标记读取：skill params.drag 或任一 tag_params.drag == true（str 比较防 JSON 布尔/字符串混型）
func _skill_drag_enabled(skill_id: String) -> bool:
	var sd: Dictionary = _get_skill_data(skill_id)
	if str(sd.get("params", {}).get("drag", "false")) == "true":
		return true
	for tag_id in sd.get("tag_params", {}):
		if str(sd["tag_params"][tag_id].get("drag", "false")) == "true":
			return true
	return false

## 项3：当前激活技能是否启用拖长击（input_manager 路由查询口）
func is_drag_skill(player_id: int) -> bool:
	if not _operator_context.has(player_id):
		return false
	return _skill_drag_enabled(str(_operator_context[player_id].get("skill_id", "")))

## 项1 空格迁移语义（05 §1 主人裁决 2026-09-24）：params.space_mode="rise"=飞行类上升增量；缺省=贴地奔跑类跳跃
func get_space_mode(player_id: int) -> String:
	if not _operator_context.has(player_id):
		return "jump"
	var sd: Dictionary = _get_skill_data(str(_operator_context[player_id].get("skill_id", "")))
	var p: Dictionary = sd.get("params", {})
	if p.has("space_mode"):
		return str(p["space_mode"])
	for tag_id in sd.get("tag_params", {}):
		var tp: Dictionary = sd["tag_params"][tag_id]
		if tp.has("space_mode"):
			return str(tp["space_mode"])
	return "jump"

## 取消（C/再按）：清操作上下文
func _clear_operator_context(player_id: int) -> void:
	_operator_context.erase(player_id)


## ==================== 波C（操球窗口 单写者认领）：AI 虚拟输入源（03主题③方案a） ====================
## AI 与玩家走同一激活状态机：ai_input_source.gd 生成与玩家等价的操作意图，
## 经本管理器公开入口（on_skill_key_pressed / confirm_substate_at）推进，禁旁路直调 use_skill。
## 本登记只补状态机不知道的两件事：①AI 施法者节点（_trigger_midfly 球源解析用——
## AI 玩家无 input_manager/controlled_player 链）②AI 虚拟瞄准（steer 意图留档可查）。
## 未登记/未接线时零行为差异（字典恒空=与无此代码等价，sim 逐位不受影响）。
var ai_virtual_inputs: Dictionary = {}  # {player_id: {"caster": Node, "aim_direction": Vector2}}


## 登记 AI 输入源（接线口：集成窗口经 ai_input_source.attach 调用；重复登记覆盖）
func register_ai_input_source(player_id: int, caster: Node) -> void:
	ai_virtual_inputs[player_id] = {"caster": caster, "aim_direction": Vector2.ZERO}


## 写 AI 虚拟瞄准（steer 激活期每周期更新；未登记忽略）
func set_ai_aim(player_id: int, aim: Vector2) -> void:
	if ai_virtual_inputs.has(player_id):
		ai_virtual_inputs[player_id]["aim_direction"] = aim


## 读 AI 虚拟瞄准（未登记返回 Vector2.ZERO，消费方按零向量=不干预处理）
func get_ai_aim(player_id: int) -> Vector2:
	var entry: Dictionary = ai_virtual_inputs.get(player_id, {})
	return entry.get("aim_direction", Vector2.ZERO)


## 注销（cleanup/比赛结束）
func clear_ai_input_source(player_id: int) -> void:
	ai_virtual_inputs.erase(player_id)


## ==================== 工单19任务A：操控族激活链（备案②销项） ====================
## 语义裁定（c 分级，2026-09-28）：简单 AIM 走直调保留；STEER/MIDFLY 必须走操作链——
## 本段交付三件：①激活技能查询口（聚合 operator 上下文）②AI 版激活入口（AI 执行层经此
## 造激活窗上下文，替代按键）③激活窗 tick 驱动（provider 注入感知，ai_input_source 接管）。

## 感知 ctx 注入口（Callable）：由集成接线（manager）或平台实证方设置；
## 签名 = func(caster: Node) -> Dictionary（返回 ai_input_source 所需 ctx：ball_position/
## enemy_goal/visible_enemies 等）。未设置=激活窗 tick 跳过（fail-closed，零行为差异）。
var ai_ctx_provider: Callable = Callable()

## 激活技能查询口（备案②）：返回当前操作上下文副本（operator/substate/skill_id/slot/midfly_left）
## 或空字典（无激活/无上下文）
func get_active_operation(player_id: int) -> Dictionary:
	return _operator_context.get(player_id, {}).duplicate(true)


## AI 版激活入口：AI 执行层（集成接线/平台实证 driver）经此对操控族技能造激活窗上下文——
## 等价于玩家"按键激活→释放"序列（OP_MIDFLY 进 RELEASING 保留 midfly_left 干预次数；
## OP_STEER 进激活窗待球手动态）。只处理有 operator 语义的技能；AUTO 类返回 false（照旧直调）。
func ai_activate_skill(player_id: int, caster: Node, skill_id: String) -> bool:
	var op := get_operator(skill_id)
	if op != "OP_STEER" and op != "OP_MIDFLY":
		return false
	if caster == null or not is_instance_valid(caster):
		return false
	# 单槽登记（AI 侧无按键槽位语义，slot 固定 0）
	if not _player_skills.has(player_id):
		_player_skills[player_id] = {}
		_last_press_times[player_id] = {}
	_player_skills[player_id][0] = {"skill_id": skill_id, "state": SkillState.IDLE, "activation_time": 0}
	# AI 输入源登记（幂等；施法者节点供球源解析）
	if not ai_virtual_inputs.has(player_id):
		register_ai_input_source(player_id, caster)
	# 激活（造 operator 上下文/OP_MIDFLY 初始化 midfly_left）→立即释放（RELEASING=操控窗开）
	_activate_skill(player_id, 0)
	_release_skill(player_id, 0)
	print("[SkillState] AI 激活操控族技能: %s op=%s player=%d" % [skill_id, op, player_id])
	return true


## 激活窗 tick（_process 驱动）：对每个 AI 输入源登记者，若 provider 可用则组装 ctx
## 交 ai_input_source.tick_activation 接管（STEER 引导注入/MIDFLY 时机干预）。
## provider 未设置=零循环体（fail-closed，行为与无此代码等价）。
func _tick_ai_activations() -> void:
	if ai_virtual_inputs.is_empty() or not ai_ctx_provider.is_valid():
		return
	for pid in ai_virtual_inputs.keys():
		var entry: Dictionary = ai_virtual_inputs[pid]
		var caster: Node = entry.get("caster")
		if caster == null or not is_instance_valid(caster):
			continue
		var ctx: Dictionary = ai_ctx_provider.call(caster)
		if ctx.is_empty():
			continue
		ctx["player"] = caster
		SpiritAIInputSource.tick_activation(self, int(pid), caster, ctx)


## ==================== 工单12 S1：OP_COMBO 合体协调器（主人裁方案a） ====================
## 语义：两队友各持半技能（player_combo_ready 标签登记半装），同队互补 role 且双方存活、
## 距离 < combo_range 时自动合体；合体期=登记 duration（remaining 倒计时，固定步长确定性），
## 到期拆分（combo_broken 信号；增益 buff 时长=合体期自然到期）。
## 本管理器只做状态机（登记/配对判定/信号/拆分），效果施加走标签流（handler 监听 combo_formed）。
## AI 侧协同时机效用=描述符（Q9 待批）；玩家侧 T 键邀请后补（裁决备注）。
signal combo_formed(combo_id: String, members: Array, params: Dictionary)
signal combo_broken(combo_id: String, members: Array)

## 合体判定周期（秒；_process 累计驱动，固定步长下确定性）
const COMBO_CHECK_INTERVAL: float = 0.2
## 合体默认距离与时长（params 未配时兜底；工单12"近距离"口径）
const COMBO_DEFAULT_RANGE: float = 150.0
const COMBO_DEFAULT_DURATION: float = 8.0

var _combo_readies: Dictionary = {}  # {player_id: {player: Node, combo_id, role, params}}
var _combo_states: Dictionary = {}   # {combo_id: {members: Array, remaining: float, params}}
var _combo_check_accum: float = 0.0


## 半装登记（handler 调用；同 player 重复登记覆盖=换半装语义；缺 combo_id/role 拒登 fail-closed）
func register_combo_ready(player_id: int, player: Node, params: Dictionary) -> void:
	var combo_id := str(params.get("combo_id", ""))
	var role := str(params.get("role", ""))
	if combo_id.is_empty() or role.is_empty():
		print("[SkillState] 合体半装拒绝: 缺 combo_id/role player=%d" % player_id)
		return
	if player == null or not is_instance_valid(player):
		return
	_combo_readies[player_id] = {"player": player, "combo_id": combo_id, "role": role, "params": params.duplicate(true)}


## 注销半装（手动取消/异常清理）
func unregister_combo_ready(player_id: int) -> void:
	_combo_readies.erase(player_id)


## 就绪表查询口（测试/观测层）
func get_combo_readies() -> Dictionary:
	return _combo_readies.duplicate(true)


## 合体态查询口（观测层/测试）：{combo_id: {members, remaining, params}}
func get_combo_states() -> Dictionary:
	return _combo_states.duplicate(true)


## 配对判定+合体触发（_process 周期驱动；测试可直调）。返回本次新成合体数。
## 配对规则：同 combo_id + role 互补（同 role 不合）+ 双方存活同队 + 距离 ≤ combo_range；
## 平局/多候选取遍历序首个（确定性）
func try_form_combos() -> int:
	var formed: int = 0
	var ids: Array = _combo_readies.keys()
	for i in range(ids.size()):
		var a_id = ids[i]
		if not _combo_readies.has(a_id):
			continue
		var a: Dictionary = _combo_readies[a_id]
		for j in range(i + 1, ids.size()):
			var b_id = ids[j]
			if not _combo_readies.has(b_id):
				continue
			var b: Dictionary = _combo_readies[b_id]
			if not _pair_compatible(a, b):
				continue
			_form_combo(a_id, a, b_id, b)
			formed += 1
			break
	return formed


## 合体兼容判定（纯函数可测）
func _pair_compatible(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("combo_id", "")) != str(b.get("combo_id", "")):
		return false
	if str(a.get("role", "")) == str(b.get("role", "")):
		return false  # 互补 role
	var pa: Node = a.get("player")
	var pb: Node = b.get("player")
	if pa == null or pb == null or not is_instance_valid(pa) or not is_instance_valid(pb):
		return false
	if pa == pb:
		return false
	if bool(pa.get("is_defeated")) or bool(pb.get("is_defeated")):
		return false
	if str(pa.get("team")) != str(pb.get("team")):
		return false  # 同队
	var ra := float(a.get("params", {}).get("combo_range", COMBO_DEFAULT_RANGE))
	if pa.global_position.distance_to(pb.global_position) > ra:
		return false
	return true


func _form_combo(a_id: int, a: Dictionary, b_id: int, b: Dictionary) -> void:
	var combo_id := str(a.get("combo_id", ""))
	var params: Dictionary = a.get("params", {})
	var members: Array = [a.get("player"), b.get("player")]
	var dur := float(params.get("duration", COMBO_DEFAULT_DURATION))
	_combo_states[combo_id] = {"members": members, "remaining": dur, "params": params}
	_combo_readies.erase(a_id)
	_combo_readies.erase(b_id)
	combo_formed.emit(combo_id, members, params)
	print("[SkillState] 合体成立: %s members=%d remaining=%.1f" % [combo_id, members.size(), dur])


func _process(delta: float) -> void:
	# 合体期倒计时（固定步长下确定性；到期拆分发信号）
	var broken: Array = []
	for combo_id in _combo_states:
		var st: Dictionary = _combo_states[combo_id]
		st["remaining"] = float(st.get("remaining", 0.0)) - delta
		if float(st["remaining"]) <= 0.0:
			broken.append(combo_id)
	for combo_id in broken:
		var st: Dictionary = _combo_states[combo_id]
		combo_broken.emit(str(combo_id), st.get("members", []))
		_combo_states.erase(combo_id)
		print("[SkillState] 合体拆分: %s" % str(combo_id))
	# 就绪表有效性清扫（死亡/失效节点）
	for pid in _combo_readies.keys():
		var r: Dictionary = _combo_readies[pid]
		var p: Node = r.get("player")
		if p == null or not is_instance_valid(p) or bool(p.get("is_defeated")):
			_combo_readies.erase(pid)
	# 合体判定周期驱动
	_combo_check_accum += delta
	if _combo_check_accum >= COMBO_CHECK_INTERVAL:
		_combo_check_accum = 0.0
		try_form_combos()
	# 工单19：操控族激活窗 tick（AI 输入源接管 STEER 引导/MIDFLY 干预）
	_tick_ai_activations()


func _ready() -> void:
	add_to_group("skill_state_managers")  # 工单12：合体协调器组（handler 经组查找连接信号）
	set_process(true)  # 工单19：激活窗 tick 驱动（_tick_ai_activations，provider 未设=空转）


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
	# 球引用：测试注入口 → AI 虚拟输入源 caster（波C）→ input_manager(父) 的
	# controlled_player.ball_ref（P1-1 注入）或 battle_manager.ball_node
	var ball = test_ball  # 测试注入口优先
	if ball == null:
		# 波C：AI 施法者自己的 ball_ref 次优先（AI 玩家无 input_manager，controlled_player 链不适用）
		var ai_caster = ai_virtual_inputs.get(player_id, {}).get("caster")
		if ai_caster != null and is_instance_valid(ai_caster) and ai_caster.get("ball_ref") != null:
			ball = ai_caster.get("ball_ref")
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
	# 项2 左键再击（05 §3.2）：reclick 技能第一段左键=选中（不生效），第二段=真释放；"direction"=三段式定弧口
	var reclick_mode := _skill_reclick_mode(skill_info.skill_id)
	if reclick_mode != "":
		ctx["reclick_mode"] = reclick_mode
		ctx["reclick_stage"] = 1
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
	ai_virtual_inputs.erase(player_id)  # 波C：AI 输入源登记一并清理
	_combo_readies.erase(player_id)  # 工单12：合体半装登记一并清理
