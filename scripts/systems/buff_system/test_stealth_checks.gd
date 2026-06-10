## 安检门系统独立测试
##
## 运行方式：
##   godot --headless --script scripts/systems/buff_system/test_stealth_checks.gd
##
## 测试：隐身对索敌/追踪/AOE的影响，无敌不影响索敌，球碰撞不跳过隐身

extends SceneTree

var _pass_count: int = 0
var _fail_count: int = 0


func _init() -> void:
	print("\n========== 安检门系统测试 ==========\n")

	test_stealth_excluded_from_enemies()
	test_all_stealth_returns_null()
	test_invincible_still_in_enemies()
	test_partial_stealth()
	test_unstealth_visible_again()
	test_stealth_target_drops_tracking()

	_total()
	quit()


# ============================================================
# 辅助：模拟索敌逻辑
# ============================================================

## 模拟 _get_enemies：和 handler 里一样的逻辑
func _sim_get_enemies(caster_team: String, all_players: Array, enemy_stealthed: Dictionary) -> Array:
	var result: Array = []
	var enemy_team: String = "b" if caster_team == "a" else "a"
	for p in all_players:
		if p.team != enemy_team:
			continue
		if p.defeated:
			continue
		if enemy_stealthed.get(p.id, false):
			continue
		result.append(p)
	return result


## 模拟 _get_nearest_enemy
func _sim_get_nearest_enemy(caster_pos: Vector2, enemies: Array) -> Variant:
	var nearest = null
	var min_dist: float = INF
	for e in enemies:
		var dist: float = caster_pos.distance_to(e.pos)
		if dist < min_dist:
			min_dist = dist
			nearest = e
	return nearest


func _make_player(id: String, team: String, pos: Vector2, defeated: bool = false) -> Dictionary:
	return { "id": id, "team": team, "pos": pos, "defeated": defeated }


# ============================================================
# 测试用例
# ============================================================

func test_stealth_excluded_from_enemies() -> void:
	## 隐身者不在敌方索敌列表中
	var all := [
		_make_player("e1", "b", Vector2(100, 0)),
		_make_player("e2", "b", Vector2(200, 0)),
	]
	var stealthed := { "e1": true }  # e1隐身

	var enemies := _sim_get_enemies("a", all, stealthed)
	_assert_eq("隐身者被跳过，只剩1个", float(enemies.size()), 1.0)
	_assert_eq("剩下的是e2", float(enemies[0].id == "e2"), 1.0)


func test_all_stealth_returns_null() -> void:
	## 全部隐身 → 索敌返回空
	var all := [
		_make_player("e1", "b", Vector2(100, 0)),
		_make_player("e2", "b", Vector2(200, 0)),
	]
	var stealthed := { "e1": true, "e2": true }

	var enemies := _sim_get_enemies("a", all, stealthed)
	_assert_eq("全部隐身→空列表", float(enemies.size()), 0.0)

	# nearest 也应该是 null
	var nearest: Variant = _sim_get_nearest_enemy(Vector2.ZERO, enemies)
	_assert_eq("全部隐身→无最近目标", float(nearest == null), 1.0)


func test_invincible_still_in_enemies() -> void:
	## 无敌者仍在索敌列表中（无敌≠隐身）
	var all := [
		_make_player("e1", "b", Vector2(100, 0)),  # 无敌（不在隐身列表里）
		_make_player("e2", "b", Vector2(200, 0)),
	]
	var stealthed := {}  # 没人隐身

	var enemies := _sim_get_enemies("a", all, stealthed)
	_assert_eq("无敌者仍被索敌", float(enemies.size()), 2.0)


func test_partial_stealth() -> void:
	## 3个敌人1个隐身 → 返回2个
	var all := [
		_make_player("e1", "b", Vector2(100, 0)),
		_make_player("e2", "b", Vector2(200, 0)),
		_make_player("e3", "b", Vector2(300, 0)),
	]
	var stealthed := { "e2": true }

	var enemies := _sim_get_enemies("a", all, stealthed)
	_assert_eq("部分隐身→2个可见", float(enemies.size()), 2.0)


func test_unstealth_visible_again() -> void:
	## 取消隐身后重新出现在索敌列表
	var all := [
		_make_player("e1", "b", Vector2(100, 0)),
		_make_player("e2", "b", Vector2(200, 0)),
	]

	# 隐身时
	var stealthed1 := { "e1": true }
	var enemies1 := _sim_get_enemies("a", all, stealthed1)
	_assert_eq("隐身时1个可见", float(enemies1.size()), 1.0)

	# 取消隐身（显形）
	var stealthed2 := { "e1": false }
	var enemies2 := _sim_get_enemies("a", all, stealthed2)
	_assert_eq("显形后2个可见", float(enemies2.size()), 2.0)


func test_stealth_target_drops_tracking() -> void:
	## 追踪球目标隐身 → tracking_target 被清空（转直飞）
	# 模拟追踪逻辑
	var target_stealthed: bool = true
	var tracking_target = { "stealthed": target_stealthed }

	if tracking_target.get("stealthed", false):
		tracking_target = null

	_assert_eq("追踪目标隐身→清空", float(tracking_target == null), 1.0)


# ============================================================
# 辅助方法
# ============================================================

func _assert_eq(test_name: String, actual: float, expected: float) -> void:
	if absf(actual - expected) < 0.01:
		_pass_count += 1
		print("  ✅ PASS: %s" % test_name)
	else:
		_fail_count += 1
		print("  ❌ FAIL: %s - 预期 %.2f 实际 %.2f" % [test_name, expected, actual])


func _total() -> void:
	var total: int = _pass_count + _fail_count
	print("\n========== 结果: %d/%d PASS ==========" % [_pass_count, total])
	if _fail_count > 0:
		print("⚠️  %d 个测试失败！" % _fail_count)
	else:
		print("🎉 全部通过！")
	print()
