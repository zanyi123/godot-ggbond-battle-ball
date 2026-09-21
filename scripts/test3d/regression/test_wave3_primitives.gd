## 波3 验收：球员管道变体 6 原语（09 工单 §三断言清单，headless 可跑）
## 真实 player.gd 实例（灯系统/take_damage 为纯字典逻辑可脱树跑；PlayerSaveManager 走空 character_id 无副作用）
## 运行：Godot_console.exe --headless --script res://scripts/test3d/regression/test_wave3_primitives.gd
extends SceneTree

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	_run()


func _mk_player() -> CharacterBody2D:
	var p: CharacterBody2D = load("res://scripts/battle/player.gd").new()
	p.max_stamina = 100.0
	p.stamina = 100.0
	p.max_spirit_energy = 100.0
	p.spirit_energy = 100.0
	p.team = "a"
	p.character_id = ""  # 装备耐久走空角色=无副作用
	return p


func _run() -> void:
	print("\n========== 波3 球员管道变体测试 ==========\n")
	# 等 autoload 就位（PlayerSaveManager/DataManager 空转即可）
	for i in range(5):
		await process_frame

	var handler = load("res://scripts/systems/spirit_system/spirit_tag_effect_handler.gd").new()
	root.add_child(handler)
	await process_frame

	# ===== #11 禁疗/禁能 =====
	var p1 := _mk_player()
	p1.turn_on_light("heal_block", 50.0)
	p1.turn_on_light("energy_block", 50.0)
	var stam_before: float = 50.0
	p1.stamina = stam_before
	p1._tick_effects["hp_regen"] = {"type": "regen", "rate": 5.0, "remaining": 50.0}
	var e_before: float = 10.0
	p1.spirit_energy = e_before
	p1._tick_all_timers(1.0)
	_assert("禁疗: regen tick 不回血", absf(p1.stamina - stam_before) < 0.01)
	_assert("禁能: 能量 tick 不回复", absf(p1.spirit_energy - e_before) < 0.01)
	p1.turn_off_light("heal_block")
	p1.turn_off_light("energy_block")
	p1._tick_all_timers(1.0)
	_assert("灯灭后恢复: 回血/回能正常", p1.stamina > stam_before and p1.spirit_energy > e_before)

	# block=heal 单禁（handler 参数语义）
	var p1b := _mk_player()
	p1b.turn_on_light("heal_block", 50.0)
	p1b.spirit_energy = 10.0
	p1b._tick_all_timers(1.0)
	_assert("block=heal 单禁: 能量照常回复", p1b.spirit_energy > 10.0)

	# ===== #5 反伤 =====
	var defender := _mk_player(); defender.team = "b"
	var attacker := _mk_player(); attacker.team = "a"
	defender.turn_on_light("reflect", 5.0, {"value": 10.0, "pct": 0.5})
	var atk_stam_before: float = attacker.stamina
	defender.take_damage(20.0, attacker, "")
	var expected_reflect: float = 10.0 + 20.0 * 0.5  # 防御为0时 actual=20
	_assert("反伤: 攻击者吃反伤 (≈15)", absf(atk_stam_before - attacker.stamina - expected_reflect) < 1.5)
	# 反伤守卫：双方都开反伤 → 链式反伤有界终止（defender 守卫拦截第三跳）
	var def2: float = defender.stamina
	var atk2: float = attacker.stamina
	defender.turn_on_light("reflect", 5.0, {"value": 10.0, "pct": 0.5})
	attacker.turn_on_light("reflect", 5.0, {"value": 5.0, "pct": 0.0})
	defender.take_damage(20.0, attacker, "")
	# 链：defender 掉20 → attacker 吃反伤(10+20×0.5=20) → attacker 反伤5 回 defender → defender 守卫拦截，终止
	_assert("反伤守卫: 链式反伤有界终止 (attacker-20 / defender-25)", absf(atk2 - attacker.stamina - 20.0) < 1.5 and absf(def2 - defender.stamina - 25.0) < 1.5)

	# ===== #16 元素免疫/弱点 =====
	var shielded := _mk_player(); shielded.team = "b"
	shielded.spirit_id = ""  # 防守方无元灵 → counter_mult 不参与
	shielded.turn_on_light("element_immune", 5.0, {"elements": ["雷火"], "multiplier": 0.0})
	shielded.stamina = 100.0
	shielded.take_damage(30.0, null, "雷火")
	_assert("元素免疫: 指定元素伤害=0", absf(shielded.stamina - 100.0) < 0.01)
	shielded.stamina = 100.0
	shielded.take_damage(30.0, null, "冰雪")
	_assert("元素免疫: 非指定元素照常受伤", shielded.stamina < 100.0)
	shielded._status_lights["element_immune"]["multiplier"] = 1.5
	shielded.stamina = 100.0
	shielded.take_damage(20.0, null, "雷火")
	_assert("元素弱点: multiplier=1.5 伤害×1.5 (≈掉30)", absf(100.0 - shielded.stamina - 30.0) < 1.5)

	# ===== #19 能量分摊（trigger._consume_energy）=====
	var trigger = load("res://scripts/systems/spirit_system/spirit_skill_trigger.gd").new()
	root.add_child(trigger)
	await process_frame
	var caster := _mk_player(); caster.team = "a"; caster.spirit_energy = 100.0
	var mate := _mk_player(); mate.team = "a"; mate.spirit_energy = 50.0
	mate.get_instance_id()  # ensure valid
	var roster: Array[Node] = [caster, mate]
	trigger.players = roster
	var mate_id: int = mate.get_instance_id()
	var caster_id: int = caster.get_instance_id()
	# 无灯：全额自付（回归）
	var ok0: bool = trigger._consume_energy(caster_id, 40)
	_assert("无灯回归: 全额自付 40", ok0 and absf(caster.spirit_energy - 60.0) < 0.01)
	# 挂灯：分摊 50%
	mate.turn_on_light("energy_share", 5.0, {"share_pct": 0.5})
	var ok1: bool = trigger._consume_energy(caster_id, 40)
	_assert("能量分摊: 施法者实付 20", ok1 and absf(caster.spirit_energy - 40.0) < 0.01)
	_assert("能量分摊: 分摊者付 20 (50→30)", absf(mate.spirit_energy - 30.0) < 0.01)
	# 分摊者能量不足：付到 0 为止，施法照常
	mate.spirit_energy = 5.0
	caster.spirit_energy = 100.0
	var ok2: bool = trigger._consume_energy(caster_id, 40)
	_assert("分摊不足: 分摊者付到0、施法者照常", ok2 and absf(mate.spirit_energy) < 0.01 and absf(caster.spirit_energy - 80.0) < 0.01)

	# ===== #20 储存多段 =====
	var holder := _mk_player()
	var empty_signal: Array = []
	holder.charge_stock_empty.connect(func(): empty_signal.append(true))
	holder.turn_on_light("charge_stock", 10.0, {"charges": 3})
	_assert("充能: 初始 3 格", holder.get_charge_stock() == 3)
	var c1: bool = holder.consume_charge()
	var c2: bool = holder.consume_charge()
	_assert("充能: 前两次消耗成功", c1 and c2)
	_assert("充能: 剩 1 格", holder.get_charge_stock() == 1)
	var c3: bool = holder.consume_charge()
	_assert("充能: 第3次消耗成功且耗尽→灯灭+信号", c3 and not holder.is_status_active("charge_stock") and empty_signal.size() == 1)
	_assert("充能: 空后 consume=false", holder.consume_charge() == false)

	# ===== #21 受击解除 =====
	# 参数式：状态直带 break_on_hit
	var victim := _mk_player(); victim.team = "b"
	victim.turn_on_light("rooted", 5.0, {"break_on_hit": true})
	victim.turn_on_light("stealthed", 5.0)  # 无标记对照组（非无敌，不吞伤害）
	_assert("受击解除(参数式): 灯已亮", victim.is_status_active("rooted"))
	victim.take_damage(10.0, null, "")
	_assert("受击解除(参数式): 受击后 root 灭、无标记灯保留", not victim.is_status_active("rooted") and victim.is_status_active("stealthed"))
	# 标签式：先 root 再补标记
	var victim2 := _mk_player(); victim2.team = "b"
	victim2.turn_on_light("rooted", 5.0)
	var marked: int = victim2.mark_lights_break_on_hit([])
	_assert("受击解除(标签式): 标记了1个控制灯", marked == 1)
	victim2.take_damage(10.0, null, "")
	_assert("受击解除(标签式): 受击后灯灭", not victim2.is_status_active("rooted"))

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 全部通过！")
	quit(1 if _fail > 0 else 0)


func _assert(test_name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  ✅ PASS: " + test_name)
	else:
		_fail += 1
		print("  ❌ FAIL: " + test_name)
