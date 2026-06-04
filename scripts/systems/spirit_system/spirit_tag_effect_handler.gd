extends Node
class_name SpiritTagEffectHandler

## 元灵技能标签效果处理器
## 负责执行所有标签的对应效果

signal effect_applied(tag_id: String, effect_data: Dictionary)
signal effect_finished(tag_id: String, effect_data: Dictionary)

# 引用战斗管理器和球节点
var battle_manager: Node
var ball_node: Node
var field_node: Node
var players: Array[Node] = []

# 活跃效果堆栈
var _active_effects: Dictionary = {}  # {effect_id: {tag_id, params, duration, remaining_time}}

func _ready() -> void:
    # 初始化时获取引用
    battle_manager = get_node_or_null("/root/BattleManager")
    if battle_manager:
        ball_node = battle_manager.get("ball_node")
        field_node = battle_manager.get("field_node")

## 主入口：执行标签效果
## @param tag_id 标签ID
## @param params 标签参数
## @param caster_id 施法者ID
## @return 效果结果
func apply_tag_effect(tag_id: String, params: Dictionary, caster_id: int) -> Dictionary:
    print("[SpiritTagEffectHandler] 执行标签效果: ", tag_id)

    # TODO: 根据tag_id调用具体的效果函数
    # 这里目前是框架，具体效果函数待实现

    # 发送UI反馈信号
    var effect_data = {
        "tag_id": tag_id,
        "params": params,
        "caster_id": caster_id
    }
    effect_applied.emit(tag_id, effect_data)

    return {"success": true, "tag_id": tag_id}

## 清除标签效果
func remove_tag_effect(effect_id: String) -> void:
    if _active_effects.has(effect_id):
        var effect = _active_effects[effect_id]
        _active_effects.erase(effect_id)
        effect_finished.emit(effect.tag_id, effect)

## 更新持续效果（每帧调用）
func _process(delta: float) -> void:
    for effect_id in _active_effects.keys():
        var effect = _active_effects[effect_id]
        if effect.duration > 0:
            effect.remaining_time -= delta
            if effect.remaining_time <= 0:
                remove_tag_effect(effect_id)

## ==================== 对球效果 (BALL) ====================

func _apply_ball_dmg_up(params: Dictionary) -> void:
    # TODO: 实现增伤效果
    pass

func _apply_ball_dmg_down(params: Dictionary) -> void:
    # TODO: 实现减伤效果
    pass

func _apply_ball_speed_up(params: Dictionary) -> void:
    # TODO: 实现加速效果
    pass

func _apply_ball_speed_down(params: Dictionary) -> void:
    # TODO: 实现减速效果
    pass

func _apply_ball_range_up(params: Dictionary) -> void:
    # TODO: 实现范围扩大效果
    pass

func _apply_ball_range_down(params: Dictionary) -> void:
    # TODO: 实现范围缩小效果
    pass

func _apply_ball_lockon(params: Dictionary) -> void:
    # TODO: 实现精准锁定效果
    pass

func _apply_ball_spread(params: Dictionary) -> void:
    # TODO: 实现扩散效果
    pass

func _apply_ball_tracking(params: Dictionary) -> void:
    # TODO: 实现追踪效果
    pass

func _apply_ball_avoid(params: Dictionary) -> void:
    # TODO: 实现避障效果
    pass

func _apply_ball_boomerang(params: Dictionary) -> void:
    # TODO: 实现回旋效果
    pass

func _apply_ball_straight(params: Dictionary) -> void:
    # TODO: 实现直行效果
    pass

## ==================== 对场地效果 (FIELD) ====================

func _apply_field_obs_add(params: Dictionary) -> void:
    # TODO: 实现创造障碍效果
    pass

func _apply_field_obs_clear(params: Dictionary) -> void:
    # TODO: 实现清除障碍效果
    pass

func _apply_field_obs_move(params: Dictionary) -> void:
    # TODO: 实现移动障碍效果
    pass

func _apply_field_obs_lock(params: Dictionary) -> void:
    # TODO: 实现固定障碍效果
    pass

func _apply_field_terra_change(params: Dictionary) -> void:
    # TODO: 实现地形改变效果
    pass

func _apply_field_terra_revert(params: Dictionary) -> void:
    # TODO: 实现地形恢复效果
    pass

func _apply_field_zone_mark(params: Dictionary) -> void:
    # TODO: 实现区域标注效果
    pass

func _apply_field_zone_clear(params: Dictionary) -> void:
    # TODO: 实现区域清除效果
    pass

func _apply_field_zone_boost(params: Dictionary) -> void:
    # TODO: 实现加速区效果
    pass

func _apply_field_zone_slow(params: Dictionary) -> void:
    # TODO: 实现减速区效果
    pass

func _apply_field_zone_danger(params: Dictionary) -> void:
    # TODO: 实现危险区效果
    pass

func _apply_field_zone_safe(params: Dictionary) -> void:
    # TODO: 实现安全区效果
    pass

func _apply_field_illusion_add(params: Dictionary) -> void:
    # TODO: 实现幻象生成效果
    pass

func _apply_field_illusion_clear(params: Dictionary) -> void:
    # TODO: 实现幻象破除效果
    pass

## ==================== 对球员效果 (PLAYER) ====================

func _apply_player_atk_up(params: Dictionary) -> void:
    # TODO: 实现攻击提升效果
    pass

func _apply_player_atk_down(params: Dictionary) -> void:
    # TODO: 实现攻击降低效果
    pass

func _apply_player_def_up(params: Dictionary) -> void:
    # TODO: 实现防御提升效果
    pass

func _apply_player_def_down(params: Dictionary) -> void:
    # TODO: 实现防御降低效果
    pass

func _apply_player_spd_up(params: Dictionary) -> void:
    # TODO: 实现速度提升效果
    pass

func _apply_player_spd_down(params: Dictionary) -> void:
    # TODO: 实现速度降低效果
    pass

func _apply_player_res_up(params: Dictionary) -> void:
    # TODO: 实现韧性提升效果
    pass

func _apply_player_res_down(params: Dictionary) -> void:
    # TODO: 实现韧性降低效果
    pass

func _apply_player_invincible(params: Dictionary) -> void:
    # TODO: 实现无敌效果
    pass

func _apply_player_vulnerable(params: Dictionary) -> void:
    # TODO: 实现易伤效果
    pass

func _apply_player_stealth(params: Dictionary) -> void:
    # TODO: 实现隐身效果
    pass

func _apply_player_reveal(params: Dictionary) -> void:
    # TODO: 实现显形效果
    pass

func _apply_player_clone(params: Dictionary) -> void:
    # TODO: 实现分身效果
    pass

func _apply_player_clone_clear(params: Dictionary) -> void:
    # TODO: 实现分身清除效果
    pass

func _apply_player_hp_heal(params: Dictionary) -> void:
    # TODO: 实现恢复效果
    pass

func _apply_player_hp_damage(params: Dictionary) -> void:
    # TODO: 实现掉血效果
    pass

func _apply_player_hp_regen(params: Dictionary) -> void:
    # TODO: 实现持续恢复效果
    pass

func _apply_player_hp_dot(params: Dictionary) -> void:
    # TODO: 实现持续掉血效果
    pass

func _apply_player_move_slow(params: Dictionary) -> void:
    # TODO: 实现减速效果
    pass

func _apply_player_move_boost(params: Dictionary) -> void:
    # TODO: 实现加速效果
    pass

func _apply_player_root(params: Dictionary) -> void:
    # TODO: 实现定身效果
    pass

func _apply_player_unroot(params: Dictionary) -> void:
    # TODO: 实现自由效果
    pass

func _apply_player_energy_gain(params: Dictionary) -> void:
    # TODO: 实现能量恢复效果
    pass

func _apply_player_energy_cost(params: Dictionary) -> void:
    # TODO: 实现能量消耗效果
    pass

func _apply_player_energy_max_up(params: Dictionary) -> void:
    # TODO: 实现最大能量提升效果
    pass

func _apply_player_energy_max_down(params: Dictionary) -> void:
    # TODO: 实现最大能量降低效果
    pass

func _apply_player_spirit_cost_down(params: Dictionary) -> void:
    # TODO: 实现减少消耗效果
    pass

func _apply_player_spirit_cost_up(params: Dictionary) -> void:
    # TODO: 实现增加消耗效果
    pass

func _apply_player_spirit_uses_up(params: Dictionary) -> void:
    # TODO: 实现增加使用次数效果
    pass

func _apply_player_spirit_cd_down(params: Dictionary) -> void:
    # TODO: 实现冷却缩短效果
    pass

func _apply_player_spirit_cd_up(params: Dictionary) -> void:
    # TODO: 实现冷却延长效果
    pass

func _apply_player_spirit_double(params: Dictionary) -> void:
    # TODO: 实现双倍效果
    pass

func _apply_player_spirit_half(params: Dictionary) -> void:
    # TODO: 实现效果减半效果
    pass

func _apply_player_stun(params: Dictionary) -> void:
    # TODO: 实现眩晕效果
    pass

func _apply_player_cc_immune(params: Dictionary) -> void:
    # TODO: 实现免疫控制效果
    pass

func _apply_player_silence(params: Dictionary) -> void:
    # TODO: 实现沉默效果
    pass

func _apply_player_disarm(params: Dictionary) -> void:
    # TODO: 实现缴械效果
    pass

func _apply_player_undisarm(params: Dictionary) -> void:
    # TODO: 实现解除缴械效果
    pass

func _apply_player_teleport(params: Dictionary) -> void:
    # TODO: 实现传送效果
    pass

func _apply_player_return(params: Dictionary) -> void:
    # TODO: 实现返回效果
    pass