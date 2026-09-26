class_name SpiritAIEventHooks
extends RefCounted
## 波B事件钩子层：受击瞬间反应（0.5s 轮询做不到的时机）。
## 设计依据：docs/副系统-事件触发响应系统方案.md（EventBus 订阅范式——响应器分散实现）。
## 07§② 定位：本波只交付钩子层文件+说明；接入 manager 的方式归集成窗口。
## 确定性纪律（02 工单）：TTL 全部周期计数（set_cycle 注入决策周期），零墙钟、零 randf。
## 说明：instance_id 仅作内存表 key（对象销毁即失效），不进骰子输入，不违反 02"禁 instance_id"
## 的骰子纪律（该禁令针对跨运行确定性输入，内存运行时表无跨运行语义）。

## 受击/被异常状态后的反应热窗口时长（决策周期数；周期时钟由 manager 注入）
const REACTION_TTL_CYCLES := 2

## 波E复制族：敌方释放快照窗口（决策周期数；过期后 skill_copy_last 无快照必失败语义由 manager 消费侧保证）
const COPY_SNAPSHOT_TTL_CYCLES := 4

## 订阅的事件类型（波B 生存场景：受击 + 异常状态施加）
const WATCH_EVENTS: Array = [
	BattleEventBus.GameEvent.HIT_TAKEN,      ## {attacker, defender, damage, ...} → defender 登记
	BattleEventBus.GameEvent.STATUS_APPLIED, ## {target, status_id, duration, source} → target 登记
]

var _cycle: int = 0
var _reaction_until: Dictionary = {}  # 球员 instance_id(int) → 热窗口过期周期(int)
var _bus: BattleEventBus = null

## 波E复制族：各队最近技能释放快照（team → {caster, skill_id, team, cycle}；单槽=最近一条）
var _last_cast_by_team: Dictionary = {}


## 注入决策周期时钟（manager 每个 AI 决策周期调用一次；零墙钟）
func set_cycle(cycle: int) -> void:
	_cycle = cycle


func get_cycle() -> int:
	return _cycle


## 订阅事件总线（battle_manager 场景内取 bus 后调用；重复 attach 幂等——先退订再挂）
func attach(bus: BattleEventBus) -> void:
	if bus == null:
		return
	detach()
	_bus = bus
	for ev in WATCH_EVENTS:
		bus.subscribe(ev, _on_event)


## 退订（场景销毁/测试收尾调用；幂等）
func detach() -> void:
	if _bus != null and is_instance_valid(_bus):
		for ev in WATCH_EVENTS:
			_bus.unsubscribe(ev, _on_event)
	_bus = null


## 事件入口（bus 回调）：从 payload 提取受作用球员，登记反应热窗口
func _on_event(payload: Dictionary) -> void:
	var victim = payload.get("defender", null)
	if victim == null:
		victim = payload.get("target", null)
	if victim == null or not is_instance_valid(victim):
		return
	# 同一球员重复触发 → 窗口顺延（取 max，不回退）
	var until_cycle: int = _cycle + REACTION_TTL_CYCLES
	var key: int = victim.get_instance_id()
	var prev: int = int(_reaction_until.get(key, 0))
	_reaction_until[key] = maxi(prev, until_cycle)


## 查询：该球员是否处于反应热窗口（manager 组装 ctx 时喂 ctx.reaction_hot）
## 窗口过期条目惰性清理（查询时顺手删，无后台扫描）
func is_reaction_hot(player) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var key: int = player.get_instance_id()
	if not _reaction_until.has(key):
		return false
	if _cycle > int(_reaction_until[key]):
		_reaction_until.erase(key)
		return false
	return true


## 热窗口内球员数（测试/调试用）
func pending_count() -> int:
	var alive: int = 0
	for key in _reaction_until.keys():
		if _cycle <= int(_reaction_until[key]):
			alive += 1
	return alive


## 清空（比赛重开/测试隔离用）
func clear() -> void:
	_reaction_until.clear()
	_last_cast_by_team.clear()


# ===== 波E复制族：技能释放快照口（生存窗口机动领域=事件钩子域；向后兼容只增不改）=====

## 记录一次技能释放（manager 接线：监听 player.skill_used 信号后喂入；禁钩子自读感知）
## caster 需带 team 字段；同队重复释放覆盖旧快照（"最近一条"语义）
func record_skill_cast(caster, skill_id: String) -> void:
	if caster == null or not is_instance_valid(caster) or skill_id.is_empty():
		return
	var team: String = str(caster.get("team"))
	if team.is_empty():
		return
	_last_cast_by_team[team] = {"caster": caster, "skill_id": skill_id, "team": team, "cycle": _cycle}


## 查询 viewer 视角的最近敌方释放快照（复制族可放性判定数据源）
## 返回 {caster, skill_id, age_cycles}；无快照/过期/caster 失效 → {}（fail-closed）
func get_recent_enemy_cast(viewer) -> Dictionary:
	if viewer == null or not is_instance_valid(viewer):
		return {}
	var my_team: String = str(viewer.get("team"))
	if _last_cast_by_team.is_empty():
		return {}
	for team in _last_cast_by_team.keys():
		if team == my_team:
			continue
		var snap: Dictionary = _last_cast_by_team[team]
		var caster = snap.get("caster", null)
		if caster == null or not is_instance_valid(caster):
			return {}
		var age: int = _cycle - int(snap.get("cycle", 0))
		if age > COPY_SNAPSHOT_TTL_CYCLES:
			return {}
		return {"caster": caster, "skill_id": str(snap.get("skill_id", "")), "age_cycles": age}
	return {}


# ===== 集成窗口接线说明（本波不接线，只读知悉）=====
# 1. manager 持有实例：var _event_hooks := SpiritAIEventHooks.new()
#    _ready 时 _event_hooks.attach(BattleEventBus.get_bus(get_tree()))
# 2. 每个决策周期：_event_hooks.set_cycle(sad.skill_decide_count)
# 3. 组装 ctx 时：ctx["reaction_hot"] = _event_hooks.is_reaction_hot(ctx.player)
#    ——primitives_b.gd 的 self_threatened/calm_state 已消费该字段（缺省 false fail-closed）
