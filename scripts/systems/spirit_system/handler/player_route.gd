extends "res://scripts/systems/spirit_system/handler/ball_route.gd"
## handler/player_route.gd —— PLAYER 路线：球员标签 apply（13 拆分步骤3）

## === ①属性类通用 ===
func _apply_player_stat_buff(params: Dictionary, caster_id: int, stat: String, mult: float, flat: float) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		# 读取并消费双倍/减半倍率（来自 player_spirit_double/half 标签）
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		var final_mult: float = 1.0 + (mult - 1.0) * skill_mult
		var final_flat: float = flat * skill_mult
		_effect_counter += 1
		var buff_id: String = "stat_%d_%s_%d" % [_effect_counter, stat, target.get_instance_id()]
		target.add_buff(buff_id, stat, final_mult, final_flat, duration, params.get("_tag_id", ""))
		if skill_mult != 1.0:
			print("[TagEffect] 双倍/减半生效: skill_mult=%.2f -> mult=%.2f flat=%.1f" % [skill_mult, final_mult, final_flat])
		print("[TagEffect] 属性buff: stat=%s mult=%.2f flat=%.1f dur=%.1fs target=%s" % [stat, final_mult, final_flat, duration, target.char_data.get("name", "?")])


## === ②状态类通用 ===
func _apply_player_status(params: Dictionary, caster_id: int, status: String) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 3.0))
	# 波3 #21 受击解除（参数式组合用法）：状态自带 break_on_hit:true → 受击即解
	var extra: Dictionary = {}
	if params.get("break_on_hit", false):
		extra["break_on_hit"] = true
	for target in targets:
		var ok: bool = target.turn_on_light(status, duration, extra)
		if not ok:
			print("[TagEffect] %s 被免控挡住: target=%s" % [status, target.char_data.get("name", "?")])
	print("[TagEffect] 状态: %s dur=%.1fs targets=%d" % [status, duration, targets.size()])


## === 易伤 ===
func _apply_player_vulnerable(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 3.0))
	var mult: float = float(params.get("multiplier", 1.5))
	for target in targets:
		target.turn_on_light("vulnerable", duration, {"multiplier": mult})
	print("[TagEffect] 易伤: mult=%.1f dur=%.1fs targets=%d" % [mult, duration, targets.size()])


## === 显形 ===
func _apply_player_reveal(params: Dictionary, caster_id: int) -> void:
	var caster := _get_caster(caster_id)
	if not caster:
		return
	var enemies := _get_all_enemies(caster)
	var count: int = 0
	for e in enemies:
		if e.is_status_active("stealthed"):
			e.turn_off_light("stealthed")
			count += 1
	print("[TagEffect] 显形: %d个隐身目标" % count)


## ==================== 波3 球员管道变体（09 工单）====================

## #11 禁疗/禁能：block="heal"/"energy"/"both"（默认 both，蝰蛇毒咬口径）
func _apply_player_heal_block(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 3.0))
	var block: String = str(params.get("block", "both"))
	for target in targets:
		if block == "heal" or block == "both":
			target.turn_on_light("heal_block", duration)
		if block == "energy" or block == "both":
			target.turn_on_light("energy_block", duration)
	print("[TagEffect] 禁疗/禁能: block=%s dur=%.1fs targets=%d" % [block, duration, targets.size()])

## #5 反伤：攻击者受伤 = value 固定 + 实际伤害×pct
func _apply_player_reflect(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 4.0))
	var value: float = float(params.get("value", 0.0))
	var pct: float = float(params.get("pct", 0.0))
	for target in targets:
		target.turn_on_light("reflect", duration, {"value": value, "pct": pct})
	print("[TagEffect] 反伤: value=%.0f pct=%.2f dur=%.1fs targets=%d" % [value, pct, duration, targets.size()])

## #16 元素免疫/弱点：对指定元素攻击 ×multiplier（0=免疫，1.5=弱点）
func _apply_player_element_shield(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 4.0))
	var elements: Array = params.get("elements", [])
	var multiplier: float = float(params.get("multiplier", 0.0))
	for target in targets:
		target.turn_on_light("element_immune", duration, {"elements": elements, "multiplier": multiplier})
	print("[TagEffect] 元素免疫/弱点: elements=%s mult=%.1f dur=%.1fs targets=%d" % [str(elements), multiplier, duration, targets.size()])

## #19 能量分摊：队友替施法者分摊能耗（trigger._consume_energy 消费）
func _apply_player_energy_share(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 5.0))
	var share_pct: float = float(params.get("share_pct", 0.5))
	for target in targets:
		target.turn_on_light("energy_share", duration, {"share_pct": share_pct})
	print("[TagEffect] 能量分摊: share=%.0f%% dur=%.1fs targets=%d" % [share_pct * 100.0, duration, targets.size()])

## #20 储存多段：充能容器（消费时机由技能组合层定，本原语只造容器）
func _apply_player_charge_stock(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var duration: float = float(params.get("duration", 10.0))
	var charges: int = maxi(1, int(params.get("charges", 1)))
	for target in targets:
		target.turn_on_light("charge_stock", duration, {"charges": charges})
	print("[TagEffect] 充能容器: charges=%d dur=%.1fs targets=%d" % [charges, duration, targets.size()])

## #21 受击解除：给目标已在亮的匹配状态打 break_on_hit 标记（statuses 空=全部控制类）
func _apply_player_on_hit_expire(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var statuses: Array = params.get("statuses", [])
	var total: int = 0
	for target in targets:
		total += target.mark_lights_break_on_hit(statuses)
	print("[TagEffect] 受击解除标记: statuses=%s marked=%d targets=%d" % [str(statuses), total, targets.size()])


## ==================== 波5（11 工单）====================

## #10 叠层印记：命中目标 +1 层（封顶刷新）；达阈值触发引用标签；触发后按参数清层
func _apply_player_mark_apply(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var mark_id: String = str(params.get("mark_id", "mark"))
	var max_stacks: int = maxi(1, int(params.get("max_stacks", 3)))
	var duration: float = float(params.get("duration", 5.0))
	var threshold_count: int = int(params.get("threshold_count", 0))
	var threshold_tag: String = str(params.get("threshold_tag", ""))
	var clear_on_trigger: bool = bool(params.get("clear_on_trigger", false))
	var threshold_params: Dictionary = params.get("threshold_params", {})
	for target in targets:
		if not target.has_method("apply_mark"):
			continue
		var count: int = target.apply_mark(mark_id, max_stacks, duration)
		print("[TagEffect] 印记: %s 第%d/%d层 target=%s" % [mark_id, count, max_stacks, target.char_data.get("name", "?")])
		if threshold_count > 0 and count >= threshold_count and threshold_tag != "":
			# 阈值触发：对带印记目标触发引用标签（递归走统一入口）
			apply_tag_effect(threshold_tag, threshold_params.duplicate(), target.get_instance_id())
			print("[TagEffect] 印记阈值触发: %s ×%d → %s" % [mark_id, count, threshold_tag])
			if clear_on_trigger:
				target.clear_mark(mark_id)

## #13 toggle：状态标签 → 状态灯名映射（toggle 开关用；v1 仅支持状态灯类标签可精确撤销）
const TOGGLE_STATUS_MAP: Dictionary = {
	"player_stealth": "stealthed",
	"player_invincible": "invincible",
	"player_atk_up_pct": "atk_up_toggle",
	"player_def_up_pct": "def_up_toggle",
	"player_spd_up_pct": "spd_up_toggle",
}


## #3 治疗区：zone_type=4 由 _apply_field_zone_effect 构建映射消费（heal_per_sec）


## === 体力恢复/扣除(%) ===
func _apply_player_hp_heal_pct(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pct: float = float(params.get("value", 20)) / 100.0
	for target in targets:
		if target.is_status_active("heal_block"):
			continue  # 波3 #11 禁疗：灯亮治疗无效
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		var heal: float = target.max_stamina * pct * skill_mult
		target.stamina = min(target.max_stamina, target.stamina + heal)

func _apply_player_hp_damage_pct(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pct: float = float(params.get("value", 20)) / 100.0
	for target in targets:
		if target.is_status_active("invincible"):
			continue
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		var dmg: float = target.max_stamina * pct * skill_mult
		target.stamina = max(0.0, target.stamina - dmg)
		if target.stamina <= 0.0 and not target.is_defeated:
			target._on_defeated()


## === 体力恢复/扣除(固定) ===
func _apply_player_hp_heal_flat(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 30))
	for target in targets:
		if target.is_status_active("heal_block"):
			continue  # 波3 #11 禁疗：灯亮治疗无效
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		target.stamina = min(target.max_stamina, target.stamina + val * skill_mult)

func _apply_player_hp_damage_flat(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 30))
	for target in targets:
		if target.is_status_active("invincible"):
			continue
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		target.stamina = max(0.0, target.stamina - val * skill_mult)
		if target.stamina <= 0.0 and not target.is_defeated:
			target._on_defeated()


## === ③持续类 ===
func _apply_player_hp_regen(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var rate: float = float(params.get("value", 5))
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		# 读取并消费双倍/减半倍率（来自 player_spirit_double/half 标签）
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		target.add_tick_effect("hp_regen_%d" % target.get_instance_id(), "regen", rate * skill_mult, duration)
		if skill_mult != 1.0:
			print("[TagEffect] 持续恢复双倍/减半生效: rate=%.1f × %.2f = %.1f/s" % [rate, skill_mult, rate * skill_mult])
	print("[TagEffect] 持续恢复: rate=%.1f/s dur=%.1fs" % [rate, duration])

func _apply_player_hp_dot(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var rate: float = float(params.get("value", 5))
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		# 读取并消费双倍/减半倍率（来自 player_spirit_double/half 标签）
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		# 思想2：数值层相互影响 - 绑定攻击力属性
		target.add_tick_effect("hp_dot_%d" % target.get_instance_id(), "dot", rate * skill_mult, duration, ["attack"])
		if skill_mult != 1.0:
			print("[TagEffect] 持续掉血双倍/减半生效: rate=%.1f × %.2f = %.1f/s" % [rate, skill_mult, rate * skill_mult])
	print("[TagEffect] 持续掉血: rate=%.1f/s dur=%.1fs" % [rate, duration])


## === 解控 ===
func _apply_player_unroot(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		target.turn_off_light("rooted")
	print("[TagEffect] 解控: targets=%d" % targets.size())


## === 能量恢复/消耗(%) ===
func _apply_player_energy_pct(params: Dictionary, caster_id: int, is_gain: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pct: float = float(params.get("value", 20)) / 100.0
	for target in targets:
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		var amt: float = target.max_spirit_energy * pct * skill_mult
		if is_gain:
			target.spirit_energy = min(target._get_effective_value("max_energy", target.max_spirit_energy), target.spirit_energy + amt)
		else:
			target.spirit_energy = max(0.0, target.spirit_energy - amt)


## === 能量恢复/消耗(固定) ===
func _apply_player_energy_flat(params: Dictionary, caster_id: int, is_gain: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var val: float = float(params.get("value", 20))
	for target in targets:
		var skill_mult: float = target.get_and_consume_next_skill_mult()
		if is_gain:
			target.spirit_energy = min(target._get_effective_value("max_energy", target.max_spirit_energy), target.spirit_energy + val * skill_mult)
		else:
			target.spirit_energy = max(0.0, target.spirit_energy - val * skill_mult)


## === ④折扣类 ===
## multiplier 直接代表最终倍率: down传<1(如0.8减耗20%), up传>1(如1.2增耗20%)
## is_down 仅用于日志显示, 不再反转数值(避免传入>1值时算反)
func _apply_player_spirit_cost(params: Dictionary, caster_id: int, is_down: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var mult: float = float(params.get("multiplier", 0.8 if is_down else 1.2))
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		target.add_skill_cost_mult("spirit_cost_%d" % target.get_instance_id(), max(0.1, mult), duration)
	print("[TagEffect] 消耗%s: mult=%.2f dur=%.1fs" % ["减少" if is_down else "增加", mult, duration])

func _apply_player_spirit_cd(params: Dictionary, caster_id: int, is_down: bool) -> void:
	var targets := _get_player_targets(params, caster_id)
	var mult: float = float(params.get("multiplier", 0.8 if is_down else 1.2))
	var duration: float = float(params.get("duration", 5.0))
	for target in targets:
		target.add_skill_cd_mult("spirit_cd_%d" % target.get_instance_id(), max(0.1, mult), duration)
	print("[TagEffect] CD%s: mult=%.2f dur=%.1fs" % ["缩短" if is_down else "延长", mult, duration])

func _apply_player_spirit_uses(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var bonus: int = int(params.get("bonus_uses", 1))
	var skill_id: String = str(params.get("skill_id", ""))
	for target in targets:
		if skill_id != "":
			target.add_skill_bonus_uses(skill_id, bonus)
		else:
			for sid in target.equipped_skills:
				target.add_skill_bonus_uses(str(sid), bonus)

func _apply_player_spirit_double(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		target.add_next_skill_mult(2.0)
	print("[TagEffect] 下次技能效果翻倍")

func _apply_player_spirit_half(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		target.add_next_skill_mult(0.5)
	print("[TagEffect] 下次技能效果减半")


## === ⑤交互类 ===
func _apply_player_teleport(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	var pos_x: float = float(params.get("pos_x", 0))
	var pos_y: float = float(params.get("pos_y", 0))
	for target in targets:
		if target.has_method("teleport_to"):
			target.teleport_to(Vector2(pos_x, pos_y))

func _apply_player_return(params: Dictionary, caster_id: int) -> void:
	var targets := _get_player_targets(params, caster_id)
	for target in targets:
		if target.has_method("return_to_previous"):
			target.return_to_previous()


