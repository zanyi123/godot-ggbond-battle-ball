## 物理系统测试脚本
## 挂载到 BattleManager 子节点使用
## 测试场地物理管理器和击退系统

extends Node

## 测试标志
var test_active: bool = false

## 测试计时器
var test_timer: float = 0.0

## 测试阶段
var test_phase: int = 0
var test_phases: Array = [
    "初始化测试",
    "摩擦系数测试",
    "弹性系数测试",
    "击退系统测试",
    "完成"
]


func _ready() -> void:
    """初始化"""
    print("========== 物理系统测试脚本启动 ==========")
    print("按 T 键开始测试")
    print("按 R 键重置测试")
    print("按 P 键打印当前状态")


func _process(delta: float) -> void:
    """每帧检测输入"""
    if Input.is_action_just_pressed("ui_text_newline"):  # Enter键
        start_test()
    
    if Input.is_action_just_pressed("ui_cancel"):  # Esc键
        reset_test()
    
    if Input.is_action_just_pressed("ui_select"):  # Shift键
        print_status()


func _input(event: InputEvent) -> void:
    """输入检测"""
    if event is InputEventKey:
        if event.pressed:
            match event.keycode:
                KEY_T:
                    start_test()
                KEY_R:
                    reset_test()
                KEY_P:
                    print_status()


func start_test() -> void:
    """开始测试"""
    if test_active:
        print("[测试] 测试已在进行中")
        return
    
    test_active = true
    test_phase = 0
    test_timer = 0.0
    
    print("========== 开始测试 ==========")
    _run_test_phase(0)


func reset_test() -> void:
    """重置测试"""
    test_active = false
    test_phase = 0
    test_timer = 0.0
    
    # 恢复默认物理属性
    var battle_manager = get_node_or_null("/root/BattleManager")
    if battle_manager:
        var field_physics = battle_manager.get_node_or_null("FieldPhysicsManager")
        if field_physics and field_physics.has_method("restore_all_defaults"):
            field_physics.restore_all_defaults()
    
    print("========== 测试已重置 ==========")


func print_status() -> void:
    """打印当前状态"""
    var battle_manager = get_node_or_null("/root/BattleManager")
    if not battle_manager:
        print("[状态] 找不到 BattleManager")
        return
    
    var field_physics = battle_manager.get_node_or_null("FieldPhysicsManager")
    if not field_physics:
        print("[状态] 找不到 FieldPhysicsManager")
        return
    
    if field_physics.has_method("get_status_info"):
        print("[状态] " + field_physics.get_status_info())
    
    # 打印击退计算样本
    if field_physics.has_method("get_friction"):
        var mu: float = field_physics.get_friction()
        print("[击退样本] μ=%.2f, 一段击退距离=%.0fpx" % [
            mu, KnockbackPhysics.calculate_distance("knockback1", mu)
        ])


func _run_test_phase(phase: int) -> void:
    """运行测试阶段"""
    if phase >= test_phases.size():
        print("========== 测试完成 ==========")
        test_active = false
        return
    
    test_phase = phase
    print("\n--- 阶段 %d: %s ---" % [phase + 1, test_phases[phase]])
    
    match phase:
        0:
            _test_initialization()
        1:
            _test_friction()
        2:
            _test_bounciness()
        3:
            _test_knockback()
        _:
            print("[测试] 阶段完成")


## ==================== 测试阶段 ====================

func _test_initialization() -> void:
    """测试1：初始化"""
    var battle_manager = get_node_or_null("/root/BattleManager")
    if not battle_manager:
        print("[失败] 找不到 BattleManager")
        _next_phase(3.0)
        return
    
    var field_physics = battle_manager.get_node_or_null("FieldPhysicsManager")
    if not field_physics:
        print("[失败] 找不到 FieldPhysicsManager")
        print("[提示] 请确认 BattleManager._ready() 中调用了 _setup_field_physics_manager()")
        _next_phase(3.0)
        return
    
    # 检查方法存在
    var has_methods: bool = (
        field_physics.has_method("get_friction") and
        field_physics.has_method("set_friction") and
        field_physics.has_method("get_bounciness") and
        field_physics.has_method("set_bounciness")
    )
    
    if not has_methods:
        print("[失败] FieldPhysicsManager 缺少必要方法")
        _next_phase(3.0)
        return
    
    print("[通过] 初始化检查")
    print("  - BattleManager: 存在")
    print("  - FieldPhysicsManager: 存在")
    print("  - 方法: 完整")
    
    print_status()
    _next_phase(2.0)


func _test_friction() -> void:
    """测试2：摩擦系数"""
    var battle_manager = get_node_or_null("/root/BattleManager")
    var field_physics = battle_manager.get_node_or_null("FieldPhysicsManager")
    
    if not field_physics:
        print("[跳过] 无 FieldPhysicsManager")
        _next_phase(2.0)
        return
    
    # 测试设置摩擦系数
    print("[测试] 设置摩擦系数为 0.5（冰面）")
    field_physics.set_friction(0.5, "test_ice", 3.0)
    
    var mu: float = field_physics.get_friction()
    print("  读取值: μ=%.2f" % mu)
    
    if abs(mu - 0.5) < 0.01:
        print("[通过] 摩擦系数设置成功")
        print("[计算] 一段击退距离: %.0fpx (标准100px)" % [
            KnockbackPhysics.calculate_distance("knockback1", mu)
        ])
    else:
        print("[失败] 摩擦系数设置失败")
    
    _next_phase(4.0)


func _test_bounciness() -> void:
    """测试3：弹性系数"""
    var battle_manager = get_node_or_null("/root/BattleManager")
    var field_physics = battle_manager.get_node_or_null("FieldPhysicsManager")
    
    if not field_physics:
        print("[跳过] 无 FieldPhysicsManager")
        _next_phase(2.0)
        return
    
    # 测试设置弹性系数
    print("[测试] 设置弹性系数为 0.8（强反弹）")
    field_physics.set_bounciness(0.8, "test_bounce")
    
    var e: float = field_physics.get_bounciness()
    print("  读取值: e=%.2f" % e)
    
    if abs(e - 0.8) < 0.01:
        print("[通过] 弹性系数设置成功")
        
        # 测试球的弹性系数
        var ball_nodes = get_tree().get_nodes_in_group("ball")
        if not ball_nodes.is_empty():
            var ball = ball_nodes[0]
            if ball.has_method("set_bounce_coefficient"):
                ball.set_bounce_coefficient(e)
                print("  球弹性已同步: e=%.2f" % ball.get_bounce_coefficient())
            else:
                print("  [警告] 球没有 set_bounce_coefficient 方法")
    else:
        print("[失败] 弹性系数设置失败")
    
    print_status()
    _next_phase(2.0)


func _test_knockback() -> void:
    """测试4：击退系统"""
    print("[测试] 击退系统需要实际游戏测试")
    print("  请在对战中观察：")
    print("  1. 球员被击中时的击退距离")
    print("  2. 不同摩擦系数下的距离变化")
    print("  3. 控制台输出的击退信息")
    print("")
    print("  手动测试命令：")
    print("  field_physics.set_friction(0.5, \"manual\")")
    print("  然后发球击中球员，观察距离是否翻倍")
    
    _next_phase(2.0)


func _next_phase(delay: float) -> void:
    """延迟进入下一阶段"""
    get_tree().create_timer(delay).timeout.connect(
        func():
            if test_active:
                _run_test_phase(test_phase + 1)
    )


## ==================== 快捷命令 ====================

## 手动设置摩擦系数
func set_friction(mu: float, duration: float = 0.0) -> void:
    """快捷命令：设置摩擦系数"""
    var battle_manager = get_node_or_null("/root/BattleManager")
    if battle_manager:
        var field_physics = battle_manager.get_node_or_null("FieldPhysicsManager")
        if field_physics and field_physics.has_method("set_friction"):
            field_physics.set_friction(mu, "manual", duration)
            print("[命令] 摩擦系数设置为 %.2f" % mu)


## 恢复默认
func restore_defaults() -> void:
    """快捷命令：恢复默认"""
    var battle_manager = get_node_or_null("/root/BattleManager")
    if battle_manager:
        var field_physics = battle_manager.get_node_or_null("FieldPhysicsManager")
        if field_physics and field_physics.has_method("restore_all_defaults"):
            field_physics.restore_all_defaults()
            print("[命令] 已恢复默认")