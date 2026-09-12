## E6-2 标签审计：80 标签逐个"真执行"验证（headless 可跑）
## 方法：真实 arena + 真实 handler，逐标签 apply_tag_effect → 状态前后快照对比
## 三档判定：✅生效（success+状态变化）/ ⚠存疑（success但无变化 或 需游戏内验证）/ ❌缺失（无case或失败）
## 输出：docs/标签审计报告.md
extends Node3D

const REPORT_PATH := "res://docs/标签审计报告.md"

func _ready() -> void:
	var arena = load("res://scenes/battle/battle_arena.tscn").instantiate()
	add_child(arena)
	await get_tree().create_timer(1.5).timeout

	var handler = arena.spirit_system.get("skill_trigger")._effect_handler
	var player = arena.team_a_players[0]
	var pid: int = player.get_instance_id()

	# 加载标签注册表
	var reg = JSON.parse_string(FileAccess.get_file_as_string("res://data/spirits/tags_registry.json"))
	var tags: Array = reg.get("tags", []) if reg is Dictionary else []

	var results: Array = []  # {id, name, category, verdict, note}
	for t in tags:
		var tag_id := str(t.get("id", ""))
		var r = await _audit_one(tag_id, str(t.get("name", "")), str(t.get("category", "")), str(t.get("target_type", "")), handler, player, pid)
		results.append(r)

	# 汇总输出
	var ok_n := 0
	var warn_n := 0
	var fail_n := 0
	for r in results:
		match r["verdict"]:
			"OK": ok_n += 1
			"WARN": warn_n += 1
			"FAIL": fail_n += 1
	var md := "# 标签审计报告（E6 · %s 自动生成）\n\n" % Time.get_datetime_string_from_system()
	md += "总计 %d 标签：✅ 生效 %d / ⚠ 存疑 %d / ❌ 缺失 %d\n\n" % [results.size(), ok_n, warn_n, fail_n]
	md += "> ✅=真实执行且状态变化 ⚠=执行了但状态未见变化或需游戏内验证 ❌=无实现/执行失败\n\n"
	for tier in [["✅ 生效", "OK"], ["⚠ 存疑", "WARN"], ["❌ 缺失", "FAIL"]]:
		md += "## %s\n\n| 标签 id | 中文名 | 分类 | 说明 |\n|---|---|---|---|\n" % tier[0]
		for r in results:
			if r["verdict"] == tier[1]:
				md += "| `%s` | %s | %s | %s |\n" % [r["id"], r["name"], r["category"], r["note"]]
		md += "\n"
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(md)
		f.close()
	# tag 状态文件（天赋编辑器下拉标注用）
	var status := {}
	for r in results:
		status[r["id"]] = {"name": r["name"], "verdict": r["verdict"]}
	var sf := FileAccess.open("res://docs/tag_audit_status.json", FileAccess.WRITE)
	if sf:
		sf.store_string(JSON.stringify(status, "	"))
		sf.close()
	print("[Audit] 📜 报告: %s + tag_audit_status.json" % REPORT_PATH)
	print("[Audit] 结果: ✅%d ⚠%d ❌%d / 共%d" % [ok_n, warn_n, fail_n, results.size()])
	print("[Audit] RESULT: %s" % ("PASS" if fail_n == 0 and warn_n == 0 else "DONE（有缺失项，见报告）"))
	get_tree().quit(0)

## 单标签审计：快照 → 执行 → 对比
func _audit_one(tag_id: String, tag_name: String, category: String, target_type: String, handler: Node, player: Node, pid: int) -> Dictionary:
	# FIELD 类需要鼠标放置，headless 无法验证 → 自动归"存疑"
	if target_type == "field":
		return {"id": tag_id, "name": tag_name, "category": category, "verdict": "WARN", "note": "FIELD 类需游戏内鼠标放置，待手动验证"}
	var before := _snapshot(handler, player)
	var params := {"value": 10.0, "duration": 5.0, "radius": 60.0, "multiplier": 1.5, "_caster_id": pid, "_skill_id": "audit_" + tag_id, "_element": "", "_target_data": {}}
	var result = handler.apply_tag_effect(tag_id, params, pid)
	# 标签走 0.1s 优先级队列（apply 只入队），等冲刷后再拍快照
	await get_tree().create_timer(0.35).timeout
	var after := _snapshot(handler, player)
	var success: bool = result is Dictionary and result.get("success", false)
	var changed := before != after
	# 已知空壳（handler 里 success=true 但无实现）
	if tag_id in ["ball_avoid", "ball_spread"]:
		return {"id": tag_id, "name": tag_name, "category": category, "verdict": "FAIL", "note": "空壳：handler 标记成功但无实现（注释'待场地系统/碰撞时处理'）"}
	if success and changed:
		return {"id": tag_id, "name": tag_name, "category": category, "verdict": "OK", "note": "状态已变化"}
	if success and not changed:
		return {"id": tag_id, "name": tag_name, "category": category, "verdict": "WARN", "note": "执行成功但未见状态变化（可能需要特定上下文）"}
	return {"id": tag_id, "name": tag_name, "category": category, "verdict": "FAIL", "note": "handler 无此 case 或执行失败"}

## 状态快照：球修饰 + 球员 buff/状态/体力/能量
func _snapshot(handler: Node, player: Node) -> String:
	var parts: Array = []
	var mods = handler.get("_ball_mods")
	if mods != null:
		parts.append(str(mods))
	if player.get("_buffs") != null:
		parts.append(str(player._buffs))
	if player.get("_status_lights") != null:
		parts.append(str(player._status_lights.keys()))
	parts.append(str(player.stamina))
	parts.append(str(player.spirit_energy))
	return "|".join(parts)
