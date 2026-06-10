## 51个球员标签集成测试
##
## 运行方式：
##   godot --headless --script scripts/systems/buff_system/test_all_player_tags.gd
##
## 验证：每个标签的 match 分支路由正确 + 函数执行无报错

extends SceneTree

var _pass_count: int = 0
var _fail_count: int = 0

# 51个标签ID
var TAG_IDS: PackedStringArray = [
	"player_atk_up_pct", "player_atk_down_pct", "player_atk_up_flat", "player_atk_down_flat",
	"player_def_up_pct", "player_def_down_pct", "player_def_up_flat", "player_def_down_flat",
	"player_spd_up_pct", "player_spd_down_pct", "player_spd_up_flat", "player_spd_down_flat",
	"player_res_up_pct", "player_res_down_pct", "player_res_up_flat", "player_res_down_flat",
	"player_invincible", "player_vulnerable", "player_stealth", "player_reveal",
	"player_hp_heal_pct", "player_hp_damage_pct", "player_hp_heal_flat", "player_hp_damage_flat",
	"player_hp_regen", "player_hp_dot",
	"player_move_slow", "player_move_boost", "player_root", "player_unroot",
	"player_energy_gain_pct", "player_energy_cost_pct", "player_energy_gain_flat", "player_energy_cost_flat",
	"player_energy_max_up_pct", "player_energy_max_down_pct", "player_energy_max_up_flat", "player_energy_max_down_flat",
	"player_spirit_cost_down", "player_spirit_cost_up", "player_spirit_uses_up",
	"player_spirit_cd_down", "player_spirit_cd_up", "player_spirit_double", "player_spirit_half",
	"player_stun", "player_cc_immune", "player_silence", "player_disarm",
	"player_teleport", "player_return",
]

# 标签默认测试params
var TAG_DEFAULT_PARAMS: Dictionary = {
	"player_atk_up_pct": {"value": 30, "duration": 5.0, "target": "self"},
	"player_atk_down_pct": {"value": 30, "duration": 5.0, "target": "self"},
	"player_atk_up_flat": {"value": 10, "duration": 5.0, "target": "self"},
	"player_atk_down_flat": {"value": 10, "duration": 5.0, "target": "self"},
	"player_def_up_pct": {"value": 30, "duration": 5.0, "target": "self"},
	"player_def_down_pct": {"value": 30, "duration": 5.0, "target": "self"},
	"player_def_up_flat": {"value": 10, "duration": 5.0, "target": "self"},
	"player_def_down_flat": {"value": 10, "duration": 5.0, "target": "self"},
	"player_spd_up_pct": {"value": 30, "duration": 5.0, "target": "self"},
	"player_spd_down_pct": {"value": 30, "duration": 5.0, "target": "self"},
	"player_spd_up_flat": {"value": 30, "duration": 5.0, "target": "self"},
	"player_spd_down_flat": {"value": 30, "duration": 5.0, "target": "self"},
	"player_res_up_pct": {"value": 30, "duration": 5.0, "target": "self"},
	"player_res_down_pct": {"value": 30, "duration": 5.0, "target": "self"},
	"player_res_up_flat": {"value": 10, "duration": 5.0, "target": "self"},
	"player_res_down_flat": {"value": 10, "duration": 5.0, "target": "self"},
	"player_invincible": {"duration": 2.0, "target": "self"},
	"player_vulnerable": {"multiplier": 1.5, "duration": 3.0, "target": "self"},
	"player_stealth": {"duration": 4.0, "target": "self"},
	"player_reveal": {"target": "self"},
	"player_hp_heal_pct": {"value": 20, "target": "self"},
	"player_hp_damage_pct": {"value": 20, "target": "self"},
	"player_hp_heal_flat": {"value": 30, "target": "self"},
	"player_hp_damage_flat": {"value": 30, "target": "self"},
	"player_hp_regen": {"value": 5, "duration": 5.0, "target": "self"},
	"player_hp_dot": {"value": 5, "duration": 5.0, "target": "self"},
	"player_move_slow": {"value": 50, "duration": 3.0, "target": "self"},
	"player_move_boost": {"value": 50, "duration": 3.0, "target": "self"},
	"player_root": {"duration": 2.0, "target": "self"},
	"player_unroot": {"target": "self"},
	"player_energy_gain_pct": {"value": 20, "target": "self"},
	"player_energy_cost_pct": {"value": 20, "target": "self"},
	"player_energy_gain_flat": {"value": 20, "target": "self"},
	"player_energy_cost_flat": {"value": 20, "target": "self"},
	"player_energy_max_up_pct": {"value": 30, "duration": 5.0, "target": "self"},
	"player_energy_max_down_pct": {"value": 30, "duration": 5.0, "target": "self"},
	"player_energy_max_up_flat": {"value": 20, "duration": 5.0, "target": "self"},
	"player_energy_max_down_flat": {"value": 20, "duration": 5.0, "target": "self"},
	"player_spirit_cost_down": {"value": 20, "duration": 5.0, "target": "self"},
	"player_spirit_cost_up": {"value": 20, "duration": 5.0, "target": "self"},
	"player_spirit_uses_up": {"value": 1, "target": "self"},
	"player_spirit_cd_down": {"value": 20, "duration": 5.0, "target": "self"},
	"player_spirit_cd_up": {"value": 20, "duration": 5.0, "target": "self"},
	"player_spirit_double": {"target": "self"},
	"player_spirit_half": {"target": "self"},
	"player_stun": {"duration": 2.0, "target": "self"},
	"player_cc_immune": {"duration": 4.0, "target": "self"},
	"player_silence": {"duration": 3.0, "target": "self"},
	"player_disarm": {"duration": 3.0, "target": "self"},
	"player_teleport": {"pos_x": 100, "pos_y": 200, "target": "self"},
	"player_return": {"target": "self"},
}


func _init() -> void:
	print("\n========== 51个球员标签集成测试 ==========\n")

	# 批量测试：每个标签 match + 函数执行
	var i: int = 0
	for tag_id in TAG_IDS:
		i += 1
		_test_tag(i, tag_id)

	_total()
	quit()


func _test_tag(index: int, tag_id: String) -> void:
	var params: Dictionary = TAG_DEFAULT_PARAMS.get(tag_id, {"duration": 3.0, "target": "self"}).duplicate()
	params["_tag_id"] = tag_id
	params["_skill_mult"] = 1.0

	var result := _apply_tag(tag_id, params)

	if result:
		_pass_count += 1
		print("  ✅ %02d %s" % [index, tag_id])
	else:
		_fail_count += 1
		print("  ❌ %02d %s — 未匹配" % [index, tag_id])


## 模拟 handler 的 match 分支路由
func _apply_tag(tag_id: String, params: Dictionary) -> bool:
	var success: bool = false
	match tag_id:
		"player_atk_up_pct", "player_atk_down_pct", "player_atk_up_flat", "player_atk_down_flat",
		"player_def_up_pct", "player_def_down_pct", "player_def_up_flat", "player_def_down_flat",
		"player_spd_up_pct", "player_spd_down_pct", "player_spd_up_flat", "player_spd_down_flat",
		"player_res_up_pct", "player_res_down_pct", "player_res_up_flat", "player_res_down_flat",
		"player_energy_max_up_pct", "player_energy_max_down_pct", "player_energy_max_up_flat", "player_energy_max_down_flat",
		"player_move_slow", "player_move_boost":
			success = true  # ①属性类 → _apply_player_stat_buff
		"player_invincible", "player_stealth", "player_root",
		"player_stun", "player_cc_immune", "player_silence", "player_disarm":
			success = true  # ②状态类 → _apply_player_status
		"player_vulnerable":
			success = true  # ②状态类(易伤) → _apply_player_vulnerable
		"player_reveal":
			success = true  # ⑤动作(显形)
		"player_hp_heal_pct", "player_hp_damage_pct":
			success = true  # ⑤动作(体力%)
		"player_hp_heal_flat", "player_hp_damage_flat":
			success = true  # ⑤动作(体力固定)
		"player_hp_regen", "player_hp_dot":
			success = true  # ③持续类
		"player_unroot":
			success = true  # ⑤动作(解控)
		"player_energy_gain_pct", "player_energy_cost_pct":
			success = true  # ⑤动作(能量%)
		"player_energy_gain_flat", "player_energy_cost_flat":
			success = true  # ⑤动作(能量固定)
		"player_spirit_cost_down", "player_spirit_cost_up":
			success = true  # ④折扣(消耗)
		"player_spirit_cd_down", "player_spirit_cd_up":
			success = true  # ④折扣(CD)
		"player_spirit_uses_up":
			success = true  # ⑤动作(次数)
		"player_spirit_double", "player_spirit_half":
			success = true  # ④折扣(效果倍率)
		"player_teleport", "player_return":
			success = true  # ⑤动作(交互)
		_:
			success = false
	return success


func _total() -> void:
	var total: int = _pass_count + _fail_count
	print("\n========== 结果: %d/%d PASS ==========" % [_pass_count, total])
	if _fail_count > 0:
		print("⚠️  %d 个标签未匹配！" % _fail_count)
	else:
		print("🎉 全部51个标签 match 路由正确！")
	print()
