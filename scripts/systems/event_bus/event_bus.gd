## BattleEventBus —— 玩法事件总线（battle3d/副系统 · E1）
## 六大类玩法事件（公平铁律：不含球权/比分/进程——比赛公平规则封闭，见方案 v6）
## 既有 Godot 信号由 wire_sources 接线转发；新判定点直接 emit_event。
## 获取：BattleEventBus.get_bus(get_tree())（group 注册，免逐层注入）
class_name BattleEventBus
extends Node

const GROUP_NAME := "battle_event_bus"

## 六大类玩法事件（前缀=大类：Hit 受击 / Attack 攻击 / Defend 接球防御 / Buff 增益 / Status 状态 / Resource 资源）
enum GameEvent {
	# Hit.* 受击类
	HIT_TAKEN,              ## 命中受击 {attacker, defender, damage, element}
	HIT_COUNTER,            ## 克制命中 {attacker, defender, multiplier}
	HIT_RESILIENCE_ROLLED,  ## 韧性判定完成 {defender, effect, decay_rate}
	HIT_DEFEATED,           ## 被击倒 {player, last_hit_by}
	# Attack.* 攻击类
	ATTACK_LAUNCHED,        ## 发球出手 {attacker, direction, damage, max_dist, skills}
	# Defend.* 接球防御类
	DEFEND_CATCH_STANCE,    ## 进入/退出待接球 {player, entering}
	DEFEND_CAUGHT,          ## 接住来球(球权转换) {player, from_attacker, damage_taken}
	DEFEND_BOUNCED,         ## 韧性弹飞 {defender, direction}
	# Buff.* 增益类
	BUFF_APPLIED,           ## 增益施加 {target, buff_id, stat, value, duration, source}
	BUFF_EXPIRED,           ## 增益到期 {target, buff_id}
	BUFF_TEAM_EFFECT,       ## 全队级效果 {team, effect_desc, source}
	# Status.* 状态效果类
	STATUS_APPLIED,         ## 状态施加 {target, status_id, duration, source}
	STATUS_EXPIRED,         ## 状态到期 {target, status_id}
	# Resource.* 资源类
	RESOURCE_COOLDOWN_READY,     ## 冷却结束 {player, skill_id}
	RESOURCE_ENERGY_THRESHOLD,   ## 能量跨阈值 {player, threshold, energy}
	RESOURCE_STAMINA_THRESHOLD,  ## 体力跨阈值 {player, threshold}
}

## 持久化开关：开启后事件流写入 _log（dump_log 取出；E6 接 sim_results 文件落盘）
var log_enabled: bool = false
var _log: Array = []           # [{tick, event, payload}]
var _listeners: Dictionary = {}  # GameEvent -> Array[Callable]
var _wired_balls: Array = []   # 已接线的球（防重复 connect）
var _wired_players: Array = [] # 已接线的球员

## ==================== 分发 ====================

func emit_event(ev: GameEvent, payload: Dictionary = {}) -> void:
	if log_enabled:
		_log.append({"tick": Time.get_ticks_msec(), "event": GameEvent.keys()[ev], "payload": payload})
	for fn in _listeners.get(ev, []):
		if is_instance_valid(fn.get_object()):
			fn.call(payload)

func subscribe(ev: GameEvent, fn: Callable) -> void:
	if not _listeners.has(ev):
		_listeners[ev] = []
	if not fn in _listeners[ev]:
		_listeners[ev].append(fn)

func unsubscribe(ev: GameEvent, fn: Callable) -> void:
	if _listeners.has(ev):
		_listeners[ev].erase(fn)

## ==================== 既有信号接线转发（公平铁律：只转六大类事实） ====================

## 接线球与球员的既有信号。dev 模式球员晚建，可多次调用（内部防重复）。
func wire_sources(ball: Node, players: Array) -> void:
	if ball != null and is_instance_valid(ball) and not _wired_balls.has(ball):
		_wired_balls.append(ball)
		if ball.has_signal("ball_caught"):
			ball.ball_caught.connect(_on_ball_caught)
	if players != null:
		for p in players:
			if p == null or not is_instance_valid(p) or _wired_players.has(p):
				continue
			_wired_players.append(p)
			if p.has_signal("defeated"):
				p.defeated.connect(_on_player_defeated)  # 信号自带参数 self

func _on_ball_caught(player: Node2D) -> void:
	emit_event(GameEvent.DEFEND_CAUGHT, {"player": player})

func _on_player_defeated(p: Node2D) -> void:
	emit_event(GameEvent.HIT_DEFEATED, {"player": p, "last_hit_by": p.get("_last_hit_by")})

## ==================== 持久化缓冲 ====================

func dump_log() -> Array:
	return _log.duplicate(true)

## E6：按大类聚合统计（事件账本摘要）
func category_stats() -> Dictionary:
	var out: Dictionary = {}
	for entry in _log:
		var ev_name := str(entry.get("event", "?"))
		var category := ev_name.split("_")[0]  # HIT/ATTACK/DEFEND/BUFF/STATUS/RESOURCE
		if not out.has(category):
			out[category] = {}
		out[category][ev_name] = int(out[category].get(ev_name, 0)) + 1
	return out

func clear_log() -> void:
	_log.clear()

## ==================== 静态获取 ====================

static func get_bus(tree: SceneTree) -> BattleEventBus:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP_NAME) as BattleEventBus
