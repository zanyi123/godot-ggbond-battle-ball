extends Node
class_name SpiritSystemManager

## 元灵技能系统管理器
## 整合技能触发器、标签效果处理器，提供统一入口

signal skill_used(skill_id: String, caster_id: int, success: bool)
signal effect_applied(tag_id: String, effect_data: Dictionary)
signal ui_feedback(effect_type: String, effect_data: Dictionary)

# 子组件
var skill_trigger: SpiritSkillTrigger
var tag_effect_handler: SpiritTagEffectHandler

# 系统状态
var _initialized: bool = false

func _ready() -> void:
    print("[SpiritSystemManager] 初始化中...")

    # 创建技能触发器
    skill_trigger = SpiritSkillTrigger.new()
    skill_trigger.name = "SpiritSkillTrigger"
    add_child(skill_trigger)

    # 连接信号
    skill_trigger.skill_triggered.connect(_on_skill_triggered)
    skill_trigger.skill_effect_applied.connect(_on_skill_effect_applied)
    skill_trigger.skill_ui_feedback.connect(_on_ui_feedback)

    # 获取标签效果处理器引用
    tag_effect_handler = skill_trigger._effect_handler

    # 连接效果处理器信号
    if tag_effect_handler:
        tag_effect_handler.add_to_group("spirit_system")
        tag_effect_handler.effect_applied.connect(_on_effect_applied_handler)
        tag_effect_handler.effect_finished.connect(_on_effect_finished_handler)

    _initialized = true
    print("[SpiritSystemManager] 初始化完成")

## 初始化系统
## @param battle_manager 战斗管理器节点
## @param players 玩家节点数组
## @param ball_node 球节点
func initialize(battle_manager: Node, players: Array[Node], ball_node: Node) -> void:
    if not _initialized:
        printerr("[SpiritSystemManager] 系统未初始化")
        return

    # 设置战斗引用
    skill_trigger.setup_battle_refs(battle_manager, players, ball_node)

    print("[SpiritSystemManager] 系统已连接战斗场景")

## 设置玩家上场技能
## @param player_id 玩家ID
## @param skill_ids 技能ID列表
func set_player_skills(player_id: int, skill_ids: Array[String]) -> void:
    skill_trigger.set_player_skills(player_id, skill_ids)
    print("[SpiritSystemManager] 玩家", player_id, "上场技能: ", skill_ids)

## 使用技能（主入口）
## @param player_id 玩家ID
## @param skill_id 技能ID
## @param target_data 目标数据（可选）
## @return 是否成功使用
func use_skill(player_id: int, skill_id: String, target_data: Dictionary = {}) -> bool:
    print("[SpiritSystemManager] 使用技能: player_id=", player_id, ", skill_id=", skill_id)

    var success = skill_trigger.trigger_skill(player_id, skill_id, target_data)

    skill_used.emit(skill_id, player_id, success)

    return success

## 获取技能剩余冷却时间
## @param player_id 玩家ID
## @param skill_id 技能ID
## @return 剩余冷却时间（秒）
func get_skill_cooldown(player_id: int, skill_id: String) -> float:
    return skill_trigger.get_skill_cooldown(player_id, skill_id)

## 获取玩家上场技能列表
## @param player_id 玩家ID
## @return 技能ID列表
func get_player_skills(player_id: int) -> Array[String]:
    return skill_trigger.get_player_skills(player_id)

## 检查标签是否存在
## @param tag_id 标签ID
## @return 是否存在
func has_tag(tag_id: String) -> bool:
    return skill_trigger.has_tag(tag_id)

## 获取标签数据
## @param tag_id 标签ID
## @return 标签数据字典
func get_tag_data(tag_id: String) -> Dictionary:
    return skill_trigger.get_tag_data(tag_id)

## ==================== 信号回调 ====================

## 技能触发回调
func _on_skill_triggered(skill_id: String, caster_id: int, target_data: Dictionary) -> void:
    print("[SpiritSystemManager] 技能已触发: ", skill_id, ", 施法者: ", caster_id)

## 技能效果应用回调
func _on_skill_effect_applied(skill_id: String, tag_id: String, effect_result: Dictionary) -> void:
    print("[SpiritSystemManager] 技能效果已应用: ", skill_id, ", 标签: ", tag_id)

## UI反馈回调
func _on_ui_feedback(effect_type: String, effect_data: Dictionary) -> void:
    print("[SpiritSystemManager] UI反馈: ", effect_type, ", 数据: ", effect_data)
    ui_feedback.emit(effect_type, effect_data)

## 效果处理器回调
func _on_effect_applied_handler(tag_id: String, effect_data: Dictionary) -> void:
    effect_applied.emit(tag_id, effect_data)

## 效果结束回调
func _on_effect_finished_handler(tag_id: String, effect_data: Dictionary) -> void:
    print("[SpiritSystemManager] 效果已结束: ", tag_id)