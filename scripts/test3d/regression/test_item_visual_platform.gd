## 24号 B3 增补·平台集成核查：测试平台环境（真实 battle_arena）→ 道具发放→手持模型自动挂载
## 走真实发放链：battle_item_granter.grant_battle_item（同守白球触球口径）→ ITEM_ACQUIRED → 桥挂球员代理手位
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_item_visual_platform.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()

func _assert(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + name)


func _run() -> void:
	print("\n========== 24号 B3 增补：平台手持道具模型链路核查 ==========\n")
	for i in range(3):
		await process_frame
	var ArenaScene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	var arena = ArenaScene.instantiate()
	root.add_child(arena)
	await create_timer(1.5).timeout

	var bridge: Node = arena.get_node_or_null("BattleArena3DBridge")
	var granter: Node = get_first_node_in_group("battle_item_granters")
	var bus: Node = get_first_node_in_group("battle_event_bus")
	_assert(bridge != null, "平台环境: 3D 桥在位")
	_assert(granter != null, "平台环境: battle_item_granter 已挂（23-F3）")
	_assert(bus != null, "平台环境: battle_event_bus 在组")
	if bridge == null or granter == null or bus == null:
		print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
		quit(1)
		return

	await process_frame
	await process_frame
	_assert(bridge._item_bus == bus, "桥订阅: 懒查找已锁定平台事件总线")
	_assert(bus._listeners.get(bus.GameEvent.ITEM_ACQUIRED, []).size() >= 1, "桥订阅: ITEM_ACQUIRED 监听者在列")

	var player: Node2D = arena.team_a_players[0]
	var pid: int = player.get_instance_id()
	var player_proxy: Node3D = bridge._player_proxies.get(player)
	_assert(player_proxy != null and is_instance_valid(player_proxy), "平台环境: 球员 3D 代理在位（手持宿主）")

	# ===== 锅：真实发放→手持挂载到球员 3D 代理手位 =====
	var ok: bool = granter.grant_battle_item(player, granter.PAN_ITEM, "platform_check")
	_assert(ok, "发放: grant_battle_item(锅) 成功（真实 granter 窄口）")
	await process_frame
	await process_frame
	var entry = bridge._item_visuals.get(pid)
	_assert(entry != null, "挂载: 锅代理已挂（ITEM_ACQUIRED 事件生效）")
	if entry != null:
		var proxy: Node3D = entry["proxy"]
		_assert(str(entry["item_id"]) == "fenny_pan", "分型: 显示=fenny_pan")
		_assert(bool(entry.get("held", false)), "手持: held 旗标=true（非地面兜底）")
		_assert(proxy.get_parent() == player_proxy, "手持: 代理父节点=球员 3D 代理（随人移动/转向）")
		_assert(proxy.position == proxy.HAND_LOCAL_POS, "手持: 位置=手位本地 (16,26,0)")
		var tag: Label3D = proxy.get_node_or_null("ItemTag")
		_assert(tag != null and tag.text == "锅", "显示: 字标「锅」")
		_assert(not proxy._used_fallback, "显示: 真实模型（Kenney 锅，非几何兜底）")

	# ===== 换道具：再获药水→显示位替换为最新（依旧手持）=====
	granter.grant_battle_item(player, granter.POTION_ITEM, "platform_check")
	await process_frame
	await process_frame
	var entry2 = bridge._item_visuals.get(pid)
	_assert(entry2 != null and str(entry2["item_id"]) == "fenny_potion", "替换: 一球员一显示位，最新获得（药水）为准")
	if entry2 != null:
		_assert(bool(entry2.get("held", false)) and entry2["proxy"].get_parent() == player_proxy, "替换后: 依旧手持挂球员代理")

	# ===== 药水结算（player.use_pending_item=右键/AI 同口）→ 待用清空=撤除 =====
	var used: bool = player.use_pending_item()
	_assert(used, "使用: use_pending_item(药水) 结算成功（35号S2d 待用语义）")
	await process_frame
	await process_frame
	_assert(not bridge._item_visuals.has(pid), "撤除: pending 清空→手持代理移除")

	# ===== 锅再挂→结算（装备）→待用清空撤除 =====
	granter.grant_battle_item(player, granter.PAN_ITEM, "platform_check")
	await process_frame
	await process_frame
	_assert(bridge._item_visuals.has(pid), "再挂: 锅代理重新挂载（待用中手持显示）")
	player.use_pending_item()   # 结算=锅装备（ready 置位）+待用清空
	await process_frame
	await process_frame
	_assert(not bridge._item_visuals.has(pid), "收口: 锅结算→待用清空→代理撤除（35号S2d 语义）")

	_assert(bridge._item_visuals.is_empty(), "一致性: 生命周期收口后无孤儿代理")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	root.remove_child(arena)
	arena.free()
	if _fail == 0:
		print("🎉 全部通过")
	else:
		print("❌ 有失败项")
	quit(0 if _fail == 0 else 1)
