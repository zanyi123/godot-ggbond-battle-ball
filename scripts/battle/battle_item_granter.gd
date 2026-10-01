extends Node
## 23-F3 道具兑换口（工单23，骨架=§二点五 主人钉死：只加"战斗内发放"窄口，复用 items 语义）。
## 挂 battle_manager 下（组 battle_item_granters）；道具=比赛内临时（本实例账本，比赛结束随节点释放，
## 不写存档——23c 待确认点1 落定口径）；事件经 BattleEventBus（23-F2）。
## 纪律：无 randf；行为表内建（三道具=战斗内专属，不复用存档 items 定义，防存档污染）。

const PAN_DURABILITY := 3        # 魔术平底锅：抵御×3（能量强化锅防×3 由强化态覆盖此值）
const PAN_ITEM := "fenny_pan"
const POTION_ITEM := "fenny_potion"
const FIREWORK_ITEM := "fenny_firework"

var _ledger: Dictionary = {}     # player_id -> {item_id: count}（比赛内临时账本）
var _durability: Dictionary = {} # player_id -> 锅剩余耐久
var _subscribed := false


func _ready() -> void:
	add_to_group("battle_item_granters")
	_ensure_subscribed()


func _bus():
	var tree := get_tree()
	return tree.get_first_node_in_group("battle_event_bus") if tree else null


func _ensure_subscribed() -> void:
	if _subscribed:
		return
	var bus = _bus()
	if bus == null:
		return
	bus.subscribe(bus.GameEvent.DEFEND_INTERCEPT, _on_intercept)
	_subscribed = true


## ===== 窄口 API（骨架钉死两方法）=====

## 比赛内即时发放：入临时账本+按型置态+emit ITEM_ACQUIRED
func grant_battle_item(player: CharacterBody2D, item_id: String, source: String = "magic_ball") -> bool:
	if player == null or not is_instance_valid(player) or item_id.is_empty():
		return false
	_ensure_subscribed()
	var pid: int = player.get_instance_id()
	if not _ledger.has(pid):
		_ledger[pid] = {}
	_ledger[pid][item_id] = int(_ledger[pid].get(item_id, 0)) + 1
	match item_id:
		PAN_ITEM:
			# 锅=装备态：置受击拦截标志（take_damage 前置口消费，23-F2）+耐久账
			player.defend_intercept_ready = true
			player.defend_intercept_item = PAN_ITEM
			_durability[pid] = {"left": PAN_DURABILITY, "player": player}
		POTION_ITEM, FIREWORK_ITEM:
			pass   # 即时消耗型：use_battle_item 时结算
		_:
			_ledger[pid].erase(item_id)   # 未知道具 fail-closed（不入账）
			return false
	var bus = _bus()
	if bus:
		bus.emit_event(bus.GameEvent.ITEM_ACQUIRED, {"player": player, "item_id": item_id, "source": source})
	return true


## 使用：药水=双恢复 / 烟花=吸附决竞球+增伤；锅=被动装备态（无主动使用，false）
func use_battle_item(player: CharacterBody2D, item_id: String, target: Variant = null) -> bool:
	if player == null or not is_instance_valid(player) or not _has_item(player, item_id):
		return false
	var bus = _bus()
	match item_id:
		POTION_ITEM:
			# 原作：回血+能量恢复↑（即时消耗；恢复量=参数表内建，平衡随 21号轨道）
			player.stamina = minf(player.max_stamina, player.stamina + 30.0)
			player.spirit_energy = minf(player.max_spirit_energy, player.spirit_energy + 25.0)
		FIREWORK_ITEM:
			# 原作：无条件吸附决竞球+球速伤害增（球走既有公开口改向+BALL_FORCED_CONTROL 通知）
			var ball = target
			if ball != null and is_instance_valid(ball) and bool(ball.get("is_active")):
				var to_player: Vector2 = player.global_position - (ball.global_position as Vector2)
				if to_player.length_squared() > 1.0:
					ball.set("ball_direction", to_player.normalized())
				if bus:
					bus.emit_event(bus.GameEvent.BALL_FORCED_CONTROL, {"ball": ball, "by_player": player, "mode": "adsorb"})
			else:
				return false
		PAN_ITEM:
			return false   # 装备态无主动使用
		_:
			return false
	_consume_item(player, item_id)
	if bus:
		bus.emit_event(bus.GameEvent.ITEM_USED, {"player": player, "item_id": item_id, "target": target})
	return true


## ===== 内部 =====

## 锅耐久消费：DEFEND_INTERCEPT 订阅端（拦截源自管耐久，23a§2.1 口径）；
## 免负面=拦截短路在 take_damage 前置口一并完成（伤害与本次 status 施加均不达——23c§三 落定口径）
func _on_intercept(payload: Dictionary) -> void:
	var defender = payload.get("defender")
	if defender == null or not is_instance_valid(defender) or str(payload.get("item", "")) != PAN_ITEM:
		return
	var pid: int = defender.get_instance_id()
	if not _durability.has(pid):
		return
	var left: int = int(_durability[pid]["left"]) - 1
	if left <= 0:
		defender.defend_intercept_ready = false
		_durability.erase(pid)
	else:
		_durability[pid]["left"] = left


func _has_item(player: CharacterBody2D, item_id: String) -> bool:
	var pid: int = player.get_instance_id()
	return _ledger.has(pid) and int(_ledger[pid].get(item_id, 0)) > 0


func _consume_item(player: CharacterBody2D, item_id: String) -> void:
	var pid: int = player.get_instance_id()
	if _ledger.has(pid):
		var left: int = int(_ledger[pid].get(item_id, 0)) - 1
		if left > 0:
			_ledger[pid][item_id] = left
		else:
			_ledger[pid].erase(item_id)


## 比赛重开清账（battle_manager 重开流调用；实例随场景释放亦自然清零）
func clear_all() -> void:
	for pid in _durability.keys():
		var entry: Dictionary = _durability[pid]
		var pl = entry.get("player")
		if pl != null and is_instance_valid(pl):
			pl.defend_intercept_ready = false   # 复位已置拦截态（防清账后残留）
	_ledger.clear()
	_durability.clear()
