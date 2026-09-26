extends RefCounted
## 工单10 P2 技能装载配置化 —— 平台窗口
## 读取 test_loadouts.json → 校验（fail-closed，非法槽打印+跳过）→ 经既有装备链路上身。
## 白名单纪律：只读 DataManager / 只调既有公开链路（equip_spirit/set_player_skills/HUD 刷新），
## 禁碰 battle_manager / ai_manager / skill_state_manager 的任何字段与逻辑。

const LOADOUT_PATH := "res://data/systems/spirit_ai/test_loadouts.json"

## 纯函数：槽位名 → (队, 队内索引)；非法返回 (-1,-1)
static func slot_to_index(slot: String) -> Vector2i:
	var s := slot.strip_edges().to_upper()
	if s.length() != 2:
		return Vector2i(-1, -1)
	var team := -1
	if s.begins_with("A"):
		team = 0
	elif s.begins_with("B"):
		team = 1
	else:
		return Vector2i(-1, -1)
	var idx := int(s.substr(1))
	if idx < 0 or idx > 2:
		return Vector2i(-1, -1)
	return Vector2i(team, idx)

## 纯函数：按 id / 名字 / 元素 解析元灵；查无返回 {}
static func resolve_spirit(spirit_key: String) -> Dictionary:
	var key := spirit_key.strip_edges()
	if key.is_empty():
		return {}
	for spirit_data in DataManager.spirits:
		if str(spirit_data.get("id", "")) == key or str(spirit_data.get("name", "")) == key or str(spirit_data.get("element", "")) == key:
			return spirit_data
	return {}

## 纯函数：校验技能 id 清单，返回非法项（空数组=全部合法）
static func find_invalid_skills(skill_ids: Array) -> Array[String]:
	var invalid: Array[String] = []
	for sid in skill_ids:
		var found := false
		for skill_data in DataManager.skills:
			if str(skill_data.get("id", "")) == str(sid):
				found = true
				break
		if not found:
			invalid.append(str(sid))
	return invalid

## 读装载配置文件；失败返回 {}（调用方据此走全兜底路径）
static func load_config(path: String = LOADOUT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		print("[Loadout] ⚠ 配置不存在: %s（全部槽位走兜底装备）" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("[Loadout] ⚠ 配置读取失败: %s（全部槽位走兜底装备）" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		print("[Loadout] ⚠ 配置格式非法（非 JSON 对象）: %s" % path)
		return {}
	return parsed

## 主入口：把装载应用到 battle_manager 的 6 名球员上。
## 返回 {applied, fallback, skipped: Array[String], total}
static func apply_loadouts(bm: Node, config: Dictionary) -> Dictionary:
	var stats := {"applied": 0, "fallback": 0, "skipped": [], "total": 6}
	var covered: Dictionary = {}  # slot -> true（本槽已被有效装载覆盖）
	var loadouts: Array = config.get("loadouts", []) if config.get("loadouts", []) is Array else []
	for entry in loadouts:
		if not entry is Dictionary:
			continue
		var slot := str(entry.get("slot", ""))
		var where := slot_to_index(slot)
		if where.x < 0:
			_skip(stats, slot, "槽位名非法")
			continue
		var team_players: Array = bm.team_a_players if where.x == 0 else bm.team_b_players
		if where.y >= team_players.size():
			_skip(stats, slot, "槽位无球员")
			continue
		var player = team_players[where.y]
		if player == null or not is_instance_valid(player):
			_skip(stats, slot, "球员节点无效")
			continue
		# character_id 校验（id 或名字均可；填了且不符 → 跳槽）
		var want_char := str(entry.get("character_id", ""))
		if not want_char.is_empty():
			var got_id := str(player.char_data.get("id", ""))
			var got_name := str(player.char_data.get("name", ""))
			if want_char != got_id and want_char != got_name:
				_skip(stats, slot, "character_id 不符(期望%s 实得%s/%s)" % [want_char, got_id, got_name])
				continue
		# 元灵解析
		var spirit_data := resolve_spirit(str(entry.get("spirit_id", "")))
		if spirit_data.is_empty():
			_skip(stats, slot, "spirit_id 查无: %s" % str(entry.get("spirit_id", "")))
			continue
		# 技能清单校验（在动球员状态之前，任一非法=整槽跳过）
		var raw_skills = entry.get("skills", [])
		if not raw_skills is Array:
			_skip(stats, slot, "skills 字段非数组")
			continue
		var invalid := find_invalid_skills(raw_skills)
		if not invalid.is_empty():
			_skip(stats, slot, "技能id非法: %s" % str(invalid))
			continue
		# === 既有装备链路上身（镜像 battle_manager._on_spirit_changed）===
		player.equip_spirit(spirit_data)
		if not raw_skills.is_empty():
			var skills: Array[String] = []
			for sid in raw_skills:
				skills.append(str(sid))
			player.equipped_skills = skills
			player.skill_cooldowns.clear()
			for sid in skills:
				player.skill_cooldowns[sid] = 0.0
		if bm.spirit_system and bm.spirit_system.has_method("set_player_skills"):
			bm.spirit_system.set_player_skills(player.get_instance_id(), player.get_equipped_skills())
		player.spirit_trigger = bm.spirit_system.skill_trigger
		var hud = bm.ui_layer.get_node_or_null("HUD") if bm.ui_layer else null
		if hud and hud.has_method("_update_player_skill_icons"):
			hud._update_player_skill_icons(where.y if where.x == 0 else 3 + where.y)
		print("[Loadout] %s ← %s(%s) 技能=%s" % [
			slot, str(spirit_data.get("name", "?")), str(spirit_data.get("id", "?")),
			str(player.get_equipped_skills())])
		covered[slot] = true
		stats["applied"] += 1
	# 兜底：未被有效装载覆盖的槽 → sim 同款循环装备（保证平台永远满配可观测）
	var spirit_count := DataManager.spirits.size()
	for team in range(2):
		var team_players: Array = bm.team_a_players if team == 0 else bm.team_b_players
		for i in range(team_players.size()):
			var slot := ("A%d" if team == 0 else "B%d") % i
			if covered.has(slot):
				continue
			var player = team_players[i]
			if player == null or not is_instance_valid(player) or spirit_count == 0:
				continue
			var spirit_data: Dictionary = DataManager.spirits[(team * 3 + i) % spirit_count]
			player.equip_spirit(spirit_data)
			if bm.spirit_system and bm.spirit_system.has_method("set_player_skills"):
				bm.spirit_system.set_player_skills(player.get_instance_id(), player.get_equipped_skills())
			player.spirit_trigger = bm.spirit_system.skill_trigger
			print("[Loadout] %s ← 兜底装备 %s(%s) 技能=%s" % [
				slot, str(spirit_data.get("name", "?")), str(spirit_data.get("id", "?")),
				str(player.get_equipped_skills())])
			stats["fallback"] += 1
	return stats

static func _skip(stats: Dictionary, slot: String, reason: String) -> void:
	var skipped: Array = stats["skipped"]
	skipped.append("%s: %s" % [slot, reason])
	print("[Loadout] ⚠ 跳过槽位 %s —— %s（fail-closed）" % [slot, reason])
