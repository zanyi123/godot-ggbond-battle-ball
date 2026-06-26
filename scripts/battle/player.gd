extends CharacterBody2D
## 球员节点 - 2D表示(带背景色的数字头像)
## 处理移动、接球、发球、状态管理

@export var character_id: String = ""
@export var team: String = "a"  # "a" 或 "b"
@export var is_player_controlled: bool = false

# 球员数据(从DataManager加载)
var char_data: Dictionary = {}

# 运行时属性
var stamina: float = 100.0
var max_stamina: float = 100.0
var defense: float = 0.0
var speed: float = 200.0

# 全局速度缩放:角色数据中speed范围50~85
# 缩放后范围150~255,场地760px宽,最快约1.5秒穿半场
const SPEED_SCALE: float = 3.25
var attack_power: float = 0.0
var resilience: float = 50.0
var defense_factor: float = 0.15  # 防御因子(0.1~0.2)
var spirit_energy: float = 0.0
var max_spirit_energy: float = 100.0

# 状态
var is_defeated: bool = false
signal defeated(player: CharacterBody2D)  # 被击败信号
var is_carrying_ball: bool = false
var is_ready_to_catch: bool = false  # 待接球状态
var is_charging_throw: bool = false   # 预发球状态
var charge_start_pos: Vector2 = Vector2.ZERO
var assigned_role: int = 0  # GameManager.PlayerRole
var is_penalized: bool = false  # 是否被惩罚(在外场隔离中)

# 击退状态
var _knockback_timer: float = 0.0  # 击退剩余时间
var _knockback_duration: float = 0.0  # 击退总持续时间
var _knockback_start_velocity: float = 0.0  # 击退初始速度
var knockback_dir: Vector2 = Vector2.ZERO  # 击退方向
var _stagger_timer: float = 0.0  # 僵直持续时间（被击中后无法移动）

# 状态灯（第2步：控制状态系统）
var _status_lights: Dictionary = {}  # { "stunned": { "remaining": 2.0, ... }, ... }

# 闹钟纸条（第3步：持续效果系统）
var _tick_effects: Dictionary = {}  # { "hp_regen": { "type": "regen", "rate": 5.0, "remaining": 5.0 }, ... }

# Buff堆栈（第1步：属性修改器）
var _buffs: Dictionary = {}  # { "buff_1": { "stat": "attack", "mult": 1.3, "flat": 0.0, "source": "...", "duration": 5.0, "remaining": 5.0 } }

# 折扣卡（第4步：技能倍率系统）
var _skill_cost_mults: Dictionary = {}   # { "cost_1": { "mult": 0.5, "remaining": 5.0 } }
var _skill_cd_mults: Dictionary = {}     # { "cd_1": { "mult": 0.5, "remaining": 5.0 } }
var _next_skill_mults: Array = []        # [2.0, 1.5] 效果倍率卡列表，第一个全效，后续1/10
var _skill_bonus_uses: Dictionary = {}   # { skill_id: bonus_count }

# 冲刺状态
var is_sprinting: bool = false
var sprint_timer: float = 0.0      # 冲刺剩余时间
var sprint_cooldown: float = 0.0   # 冷却剩余时间
const SPRINT_SPEED_BONUS: float = 50.0  # 冲刺加速量
const SPRINT_DURATION: float = 3.0      # 冲刺持续3秒
const SPRINT_COOLDOWN: float = 2.0      # 冷却2秒

# 角色(主攻/防御/辅助)
var role: String = "attacker"

# 天赋
var talent_name: String = ""
var talent_desc: String = ""

# 元灵
var spirit_id: String = ""
var equipped_skills: Array[String] = []  # 最多4个技能ID

# 技能CD追踪
var skill_cooldowns: Dictionary = {}

# 视觉节点
var avatar_label: Label
var avatar_bg: ColorRect
var stamina_bar: ProgressBar
var energy_bar: ProgressBar
var state_indicator: ColorRect  # 状态指示(待接球/预发球等)
var facing_direction: Vector2 = Vector2.ZERO  # 由 register_player 或输入设置

# ==================== 2.5D 3D模型挂载 ====================
# 开关:false=2D圆圈占位(默认,AI模拟走此路);true=挂载3D模型(需 player_model_3d.tscn + glb)
# 切换为 true 前请先确认 assets/characters/avatars/ 下有带骨骼动画的 glb
const USE_3D_MODEL := true  # 阶段0:临时开启,验证3D扶正+缩放(2026-06-24)
const MODEL_3D_SCENE_PATH := "res://scenes/battle/player_model_3d.tscn"

# 4 个动作 GLB 路径(2026-06-22 混元+Mixamo 生成,含贴图+骨骼+动画)
# 主模型用 Idle(自带骨骼+基础动画),其余 3 个只取动画库合并进来
const GLB_IDLE_PATH := "res://assets/characters/avatars/Idle.glb"
const GLB_RUN_PATH := "res://assets/characters/avatars/Jog_Forward.glb"
const GLB_THROW_PATH := "res://assets/characters/avatars/Goalie_Throw.glb"
const GLB_CATCH_PATH := "res://assets/characters/avatars/Goalkeeper_Catch.glb"

## 角色专属 3D 模型路径映射(2026-06-26)
## key=character_id, value={ "body":主模型路径, "idle":待机动画(可选), "run":跑步, "throw":投掷, "catch":接球 }
## 未配置的角色自动回落使用上方 GLB_*_PATH 默认路径
const CHAR_3D_MODEL_PATHS := {
	"char_001": {  # 猪猪侠 (player1)
		"body": "res://建模素材库/3D模型素材/2cff3ad734686d14c0118d195a809dbc.glb",
		"idle": "res://建模素材库/3D模型素材/player1动作/Idle.fbx",
		"run": "res://建模素材库/3D模型素材/player1动作/Jog Forward.fbx",
		"throw": "res://建模素材库/3D模型素材/player1动作/Goalie Throw.fbx",
		"catch": "res://建模素材库/3D模型素材/player1动作/Goalkeeper Catch.fbx",
	},
}

## 根据 character_id 返回角色专属模型路径,未配置则回落默认
func _get_model_path(action: String) -> String:
	if CHAR_3D_MODEL_PATHS.has(character_id):
		var paths: Dictionary = CHAR_3D_MODEL_PATHS[character_id]
		if paths.has(action):
			return paths[action]
	# 回落默认路径
	match action:
		"body", "idle":
			return GLB_IDLE_PATH
		"run":
			return GLB_RUN_PATH
		"throw":
			return GLB_THROW_PATH
		"catch":
			return GLB_CATCH_PATH
	return ""

var model_3d_anchor: Node2D  # 3D模型渲染单元(USE_3D_MODEL=true时实例化)
var _visuals_built := false  # 视觉节点是否已构建(幂等保护,避免_ready+initialize重复创建)

# 3D 动画状态
var _animation_player: AnimationPlayer  # 主动画播放器(从主GLB提取)
var _model_slot: Node3D                  # ModelSlot 节点引用(用于旋转朝向)
var _camera_3d: Camera3D                 # SubViewport 内的 Camera3D(用于切视角)
var _current_anim_name: String = ""      # 当前播放的动画名(避免重复 play 抖动)
var _is_3d_moving: bool = false          # 当前是否在移动(缓存,避免每帧切换动画)

# 视角模式常量
const VIEW_MODE_TOP_DOWN: int = 0   # 俯视鸟瞰(看头顶)
const VIEW_MODE_ANGLED: int = 1     # 斜俯视(看全身+正脸)
const VIEW_MODE_FOLLOW: int = 2     # 平视跟随(等高正面看动作)


func _ready() -> void:
	_setup_visuals()


func initialize(data_id: String, team_name: String, controlled: bool) -> void:
	character_id = data_id
	team = team_name
	is_player_controlled = controlled

	# 从DataManager加载数据
	char_data = DataManager.get_character_by_id(character_id)
	if char_data.is_empty():
		push_error("[Player] 找不到角色数据: %s" % character_id)
		return

	# 设置属性
	max_stamina = char_data["stamina"] if char_data.has("stamina") else 100.0
	stamina = max_stamina
	spirit_energy = max_spirit_energy  # 元灵能量初始满（与体力一致，可立即释放技能）
	defense = char_data["defense"] if char_data.has("defense") else 50.0
	# speed 统一从角色数据出发,全局缩放
	# 原始范围50~85,缩放后150~255,让场地移动节奏合理
	var raw_speed: float = char_data["speed"] if char_data.has("speed") else 50.0
	speed = raw_speed * SPEED_SCALE
	attack_power = char_data["attack"] if char_data.has("attack") else 50.0
	resilience = char_data["resilience"] if char_data.has("resilience") else 50.0
	defense_factor = char_data["defense_factor"] if char_data.has("defense_factor") else 0.15
	talent_name = char_data["talent_name"] if char_data.has("talent_name") else ""
	talent_desc = char_data["talent_desc"] if char_data.has("talent_desc") else ""

	# 元灵偏好在 char_data.spirit_preference 中
	# 技能与元灵绑定：球员创建时不自动装备技能，必须在备战面板手动选择元灵后才获得技能
	# 备战面板可据此偏好高亮推荐元灵

	_setup_visuals()

	# 监听比赛阶段切换（中场休息恢复能量）
	if GameManager and not GameManager.phase_changed.is_connected(_on_phase_changed):
		GameManager.phase_changed.connect(_on_phase_changed)


## 中场休息时场上元灵能量恢复20点
func _on_phase_changed(phase) -> void:
	if phase == GameManager.MatchPhase.HALF_TIME:
		spirit_energy = minf(max_spirit_energy, spirit_energy + 20.0)


## ==================== 发球特性 ====================

## 获取该球员的发球基础球速
func get_base_ball_speed() -> float:
	"""返回该球员的发球基础球速
	
	从 char_data 中的 ball_speed 字段读取，
	如果没有配置则返回默认值 400.0
	"""
	if char_data.has("ball_speed"):
		return float(char_data["ball_speed"])
	return 400.0  # 默认值


func _setup_visuals() -> void:
	# 幂等保护:_ready 和 initialize 各会调一次,第二次起先清理旧视觉节点重建
	# (修复历史问题:第一次用默认team="a"建,第二次才用真实数据,导致节点重复+颜色错)
	if _visuals_built:
		_teardown_visuals()
	_visuals_built = true

	# 碰撞区域(无论2D/3D都要建,物理层不动)
	if not has_node("CollisionShape2D"):
		var collision := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 28.0
		collision.shape = circle
		add_child(collision)

	# 分流:2.5D开关
	if USE_3D_MODEL:
		_setup_3d_model()
	else:
		_setup_2d_avatar()


func _setup_2d_avatar() -> void:
	# 创建角色头像:带背景色的数字圆形(原2D占位逻辑,一字未改行为)
	# 背景色圆
	avatar_bg = ColorRect.new()
	avatar_bg.size = Vector2(56, 56)
	avatar_bg.position = Vector2(-28, -28)
	avatar_bg.color = Color.BLUE if team == "a" else Color.RED
	# 圆角模拟
	avatar_bg.add_theme_stylebox_override("normal", _make_circle_style(20))
	add_child(avatar_bg)

	# 数字标签(球员编号)
	avatar_label = Label.new()
	avatar_label.text = _get_display_number()
	avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar_label.position = Vector2(-28, -28)
	avatar_label.size = Vector2(56, 56)
	add_child(avatar_label)

	# 体力条和能量条不再显示在球员头上，只在下方球员栏显示

	# 状态指示器
	state_indicator = ColorRect.new()
	state_indicator.size = Vector2(12, 12)
	state_indicator.position = Vector2(16, -48)
	state_indicator.color = Color.TRANSPARENT
	add_child(state_indicator)


func _setup_3d_model() -> void:
	# 2.5D路径:实例化 player_model_3d.tscn(SubViewport+Camera3D渲染单元)
	# 状态指示器(3D模式下仍保留2D小色块做状态提示)
	state_indicator = ColorRect.new()
	state_indicator.size = Vector2(12, 12)
	state_indicator.position = Vector2(16, -48)
	state_indicator.color = Color.TRANSPARENT
	add_child(state_indicator)

	# 实例化3D渲染单元
	var scene := load(MODEL_3D_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[Player] 无法加载3D模型场景: %s,回退到2D占位" % MODEL_3D_SCENE_PATH)
		_setup_2d_avatar()
		return
	model_3d_anchor = scene.instantiate() as Node2D
	if model_3d_anchor == null:
		push_error("[Player] 3D模型场景根节点非Node2D,回退到2D占位")
		_setup_2d_avatar()
		return
	add_child(model_3d_anchor)

	# 获取 ModelSlot 节点(SubViewport/ModelSlot)
	# ModelSlot 在 player_model_3d.tscn 里设了绕X轴-90°扶正矩阵:
	# basis.x=(1,0,0) basis.y=(0,0,-1) basis.z=(0,1,0)
	# 原因:实测GLB骨骼站立方向(本地+Y)指向世界+Z(躺平,混元导出常见),需扶到世界+Y站立
	# 注意: 不要在 tscn 的 [node] 块内写 # 注释,会让 load() 解析失败回退2D(2026-06-24踩坑)
	_model_slot = model_3d_anchor.get_node_or_null("SubViewport/ModelSlot")
	if _model_slot == null:
		push_error("[Player] 找不到 SubViewport/ModelSlot 节点,3D模型无法挂载")
		return
	# 获取 Camera3D 节点(用于切换视角)
	_camera_3d = model_3d_anchor.get_node_or_null("SubViewport/Camera3D")
	# 关键修复: 显式给 SubViewport 配置 World3D + Environment,
	# 否则 Godot 在某些场景下会冻结 SubViewport 渲染(动态 add_child 进来的 3D 节点不刷新)
	_setup_subviewport_world()

	# 加载主 GLB(Idle)作为模型主体(含骨骼+网格+贴图+idle动画)
	_load_main_glb()
	# 合并其余 3 个动作动画到主动画播放器
	_merge_animation_libraries()

	print("[Player] %s 已挂载3D模型渲染单元(USE_3D_MODEL=true)" % (char_data.get("name", "?")))


## 强制刷新 SubViewport(确保动画渲染不被冻结)
func _setup_subviewport_world() -> void:
	if model_3d_anchor == null:
		return
	var sub_vp: SubViewport = model_3d_anchor.get_node_or_null("SubViewport")
	if sub_vp == null:
		return
	# 1. 创建独立的 World3D(SubViewport 默认 world_3d 可能被共享/优化掉)
	if sub_vp.world_3d == null:
		sub_vp.world_3d = World3D.new()
	# 2. 创建 Environment 并挂到 World3D(确保光照和材质正常)
	if sub_vp.world_3d.environment == null:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.7, 0.7, 0.7)
		env.ambient_light_energy = 0.8
		sub_vp.world_3d.environment = env
	# 3. 关键: 强制每帧更新渲染(防止 Godot 优化掉动态 add_child 节点的渲染)
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	print("[Player] SubViewport world_3d 已配置, update_mode=ALWAYS")


func _load_main_glb() -> void:
	"""加载主 GLB(Idle)并塞进 ModelSlot,提取主动画播放器"""
	# 关键: 用 duplicate() 复制一份独立的 PackedScene, 避免多球员共享同一份
	# AnimationLibrary 资源导致重命名污染(共享资源在 Godot 里是默认行为)
	var body_path := _get_model_path("body")
	var glb_scene := load(body_path) as PackedScene
	if glb_scene == null:
		push_error("[Player] 无法加载主模型: %s" % body_path)
		return
	var glb_scene_copy: PackedScene = glb_scene.duplicate(true)
	if glb_scene_copy == null:
		glb_scene_copy = glb_scene  # duplicate 失败时降级(单球员不受影响)
	var glb_instance := glb_scene_copy.instantiate()
	if glb_instance == null:
		push_error("[Player] 主GLB实例化失败")
		return
	# GLB 根通常是 Node3D 或 AnimationPlayer,直接挂到 ModelSlot 下
	_model_slot.add_child(glb_instance)
	# 隐藏 Mixamo 残留的 Icosphere 参考球(真模型叫 node_0)
	_hide_mixamo_helpers(glb_instance)
	# 在 GLB 实例里找 AnimationPlayer(GLB 通常根或子级)
	_animation_player = _find_animation_player(glb_instance)
	# 兜底: 如果主模型是纯静态(无AnimationPlayer), 尝试用角色专属 idle 动画源替换
	if _animation_player == null:
		var idle_path := _get_model_path("idle")
		if not idle_path.is_empty() and idle_path != body_path:
			push_warning("[Player] 主模型无AnimationPlayer, 替换为idle动画源: %s" % idle_path)
			glb_instance.queue_free()
			var idle_scene := load(idle_path) as PackedScene
			if idle_scene:
				var idle_scene_copy := idle_scene.duplicate(true) if idle_scene else null
				if idle_scene_copy == null:
					idle_scene_copy = idle_scene
				glb_instance = idle_scene_copy.instantiate()
				if glb_instance:
					_model_slot.add_child(glb_instance)
					_hide_mixamo_helpers(glb_instance)
					_animation_player = _find_animation_player(glb_instance)
	if _animation_player == null:
		push_warning("[Player] 主GLB未找到AnimationPlayer,动画功能不可用")
		return
	# 关键: 设为物理帧推进(因为球员走 _physics_process)
	_animation_player.set("process_callback", AnimationPlayer.ANIMATION_PROCESS_PHYSICS)
	# 把主GLB默认库里的动画重命名为 "idle"(原名叫 Armature|mixamo.com|Layer0)
	_rename_default_anim_to("idle")
	print("[Player] 主GLB已加载,动画库列表: ", _animation_player.get_animation_library_list())


func _find_skeleton3d(node: Node) -> Skeleton3D:
	"""递归查找 Skeleton3D"""
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton3d(child)
		if found:
			return found
	return null


func _hide_mixamo_helpers(root: Node) -> void:
	"""隐藏 Mixamo 残留的 Icosphere 参考球(42 顶点,无 parent,不属于角色网格)"""
	for node in root.find_children("*", "MeshInstance3D", true, false):
		# Mixamo 参考球通常叫 "Icosphere" 或 _Primitive 之类
		if "Icosphere" in node.name or "Primitive" in node.name:
			node.visible = false
			print("[Player] 隐藏 Mixamo 参考球: ", node.name)


func _rename_default_anim_to(new_name: String) -> void:
	"""把主动画播放器默认库("")里的第一个动画重命名为 new_name
	背景: Mixamo 导出的 GLB 动画名是 'Armature|mixamo.com|Layer0',
	无法被 _resolve_anim_name 匹配,这里统一重命名为 idle/run/throw/catch
	"""
	if _animation_player == null:
		return
	if not _animation_player.has_animation_library(""):
		return
	var default_lib := _animation_player.get_animation_library("")
	var anim_list := default_lib.get_animation_list()
	if anim_list.is_empty():
		return
	var old_name: String = anim_list[0]
	if old_name == new_name:
		return  # 已经是目标名,不用改
	# 取出原动画,用新名字塞回默认库
	var anim := default_lib.get_animation(old_name)
	default_lib.add_animation(new_name, anim)
	# 删除旧名(避免库里两个动画指向同一数据)
	if default_lib.has_animation(old_name):
		default_lib.remove_animation(old_name)
	print("[Player] 重命名动画 '%s' → '%s'" % [old_name, new_name])


func _find_animation_player(node: Node) -> AnimationPlayer:
	"""递归查找节点树里的 AnimationPlayer"""
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _merge_animation_libraries() -> void:
	"""把其余 3 个 GLB 的动画合并到主动画播放器,并重命名为语义名
	Godot 4.x: 每个 GLB 有自己的 AnimationLibrary,用 add_animation_library 合并
	Mixamo 动画原名 'Armature|mixamo.com|Layer0' → 重命名为 run/throw/catch
	最终主播放器默认库("")里有 4 个动画: idle/run/throw/catch
	"""
	if _animation_player == null:
		return
	if not _animation_player.has_animation_library(""):
		# 主GLB加载失败,补一个空默认库
		_animation_player.add_animation_library("", AnimationLibrary.new())
	var default_lib := _animation_player.get_animation_library("")
	# 把 run/throw/catch 三个 GLB 的动画塞进默认库
	var libs_to_merge := {
		"run": _get_model_path("run"),
		"throw": _get_model_path("throw"),
		"catch": _get_model_path("catch"),
	}
	# 如果 body GLB 没有自带 idle 动画,尝试从角色专属 idle 路径合并
	if not default_lib.has_animation("idle"):
		var idle_path := _get_model_path("idle")
		if not idle_path.is_empty():
			libs_to_merge["idle"] = idle_path
			print("[Player] 主模型缺idle动画,将从 %s 补合并" % idle_path)
	for semantic_name in libs_to_merge:
		var path: String = libs_to_merge[semantic_name]
		var glb_scene := load(path) as PackedScene
		if glb_scene == null:
			push_warning("[Player] 无法加载动画GLB: %s" % path)
			continue
		# 关键: 用 duplicate() 复制独立资源, 避免多球员共享 AnimationLibrary 资源
		var glb_scene_copy: PackedScene = glb_scene.duplicate(true) if glb_scene else null
		if glb_scene_copy == null:
			glb_scene_copy = glb_scene
		var glb_instance := glb_scene_copy.instantiate()
		if glb_instance == null:
			continue
		# 临时挂到树里才能访问其 AnimationPlayer
		_model_slot.add_child(glb_instance)
		var anim_player := _find_animation_player(glb_instance)
		if anim_player == null:
			push_warning("[Player] %s 里没找到AnimationPlayer" % path)
			glb_instance.queue_free()
			continue
		# 取出它的第一个动画(Mixamo 只有一个动作),重命名后塞进默认库
		for lib_key in anim_player.get_animation_library_list():
			var src_lib := anim_player.get_animation_library(lib_key)
			for src_anim_name in src_lib.get_animation_list():
				var anim: Animation = src_lib.get_animation(src_anim_name)
				# 关键: 动画资源也要 duplicate, 否则 add_animation 后多球员共享同一份
				var anim_copy: Animation = anim.duplicate(true) if anim else null
				if anim_copy == null:
					anim_copy = anim
				# 塞进默认库,用语义名覆盖原 Mixamo 命名
				if not default_lib.has_animation(semantic_name):
					default_lib.add_animation(semantic_name, anim_copy)
					print("[Player] 合并动画 '%s' (原名 '%s', track数=%d)" % [semantic_name, src_anim_name, anim_copy.get_track_count()])
				break  # 每个 GLB 只取第一个动画
			break  # 只处理默认库
		# 合并完释放这个 GLB 实例(只要它的动画库)
		glb_instance.queue_free()


func _update_3d_animation() -> void:
	"""根据当前 velocity 自动切换 idle/run 动画(在 _physics_process 末尾调)"""
	if _animation_player == null or not is_instance_valid(_animation_player):
		return
	# 强制保证:只要 current_animation 为空,就强制 play idle(每帧检查,暴力兜底)
	if _animation_player.current_animation.is_empty():
		var idle_name := _resolve_anim_name("idle")
		if not idle_name.is_empty():
			var anim := _animation_player.get_animation(idle_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
			_animation_player.play(idle_name)
			_current_anim_name = idle_name
			_is_3d_moving = false
		return
	# 用 velocity 长度判断移动状态(>10 视为在动)
	var moving: bool = velocity.length() > 10.0
	if moving != _is_3d_moving:
		_is_3d_moving = moving
		# 根据移动状态切 idle/run
		var target_anim := _resolve_anim_name("idle" if not moving else "run")
		if not target_anim.is_empty() and _current_anim_name != target_anim:
			var anim := _animation_player.get_animation(target_anim)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
			_animation_player.play(target_anim)
			_current_anim_name = target_anim


func _resolve_anim_name(category: String) -> String:
	"""解析动画名 —— 直接返回 category(合并时已统一重命名为 idle/run/throw/catch)
	如果默认库里确实有这个动画,就返回 category 本身
	"""
	if _animation_player == null:
		return ""
	if not _animation_player.has_animation_library(""):
		return ""
	var default_lib := _animation_player.get_animation_library("")
	if default_lib.has_animation(category):
		return category
	# 容错:大小写不敏感匹配(以防 GLB 内部名首字母大写)
	for anim in default_lib.get_animation_list():
		if anim.to_lower() == category.to_lower():
			return anim
	return ""


func _update_3d_facing() -> void:
	"""根据 velocity 方向旋转 ModelSlot 朝向(只转 Y 轴,Sprite2D 保持不动)
	注意: ModelSlot 在场景里已设 X 轴 -90° 基础旋转(让躺平球员站立,实测GLB骨骼+Z朝上)
	这里在 ModelSlot 现有姿态上叠加 Y 轴朝向(待启用,先确认扶正效果)
	"""
	# 暂时禁用朝向旋转,先让球员稳定站立
	return


## 手动播放指定动作(测试用,F1/F2/F3 切)
func play_3d_action(category: String) -> void:
	"""手动切到 throw/catch 等动作(测试用)"""
	if _animation_player == null:
		return
	var target := _resolve_anim_name(category)
	if target.is_empty():
		print("[Player] 找不到动画: ", category)
		return
	_animation_player.play(target)
	_current_anim_name = target


## 返回当前 3D 模型的实时诊断信息(给测试 UI 显示用)
func get_3d_debug_info() -> Dictionary:
	if _animation_player == null or not is_instance_valid(_animation_player):
		return {"has_anim_player": false}
	# current_animation 为空时访问 current_animation_position 会报错,先取名字
	var cur_anim: String = _animation_player.current_animation
	var anim_pos: float = 0.0
	var anim_len: float = 0.0
	if not cur_anim.is_empty():
		anim_pos = _animation_player.current_animation_position
		anim_len = _animation_player.current_animation_length
	return {
		"has_anim_player": true,
		"current_anim": cur_anim,
		"is_playing": _animation_player.is_playing(),
		"anim_pos": anim_pos,
		"anim_len": anim_len,
		"current_anim_name_cache": _current_anim_name,
		"is_moving": _is_3d_moving,
		"inside_tree": _animation_player.is_inside_tree(),
		"velocity_len": velocity.length(),
	}


## 切换 SubViewport 内 Camera3D 的视角模式(测试用,F4 切)
## 前提: ModelSlot 在场景里已设 X 轴 -90°(实测:GLB骨骼+Z朝上,需扶成+Y站立)
## 扶正后球员正立,相机角度按标准 3D 逻辑设置:
## mode: 0=俯视全场(看头顶) 1=斜俯视全场(2K默认,看全身+正脸) 2=平视跟随(看正脸特写)
func set_view_mode(mode: int) -> void:
	if _camera_3d == null or not is_instance_valid(_camera_3d):
		return
	match mode:
		VIEW_MODE_TOP_DOWN:
			# 俯视全场: 相机在球员正上方 4m,镜头朝下(-Y)
			# 绕 X 轴 -90°,让镜头 -Z 朝向 -Y(下方)
			_camera_3d.transform = Transform3D(
				Basis(Vector3.RIGHT, deg_to_rad(-90.0)),
				Vector3(0.0, 4.0, 0.0)
			)
		VIEW_MODE_ANGLED:
			# 斜视45°(大镜头: ZOY平面+Z逆时针45°; 小镜头: 球员已扶正垂直站立时不另转)
			# 小镜头保持斜俯视位置: -45° 俯角,位置 (0, 1.8, 3.0)
			# 注意: 原-35°改为-45°以匹配阶段2大镜头斜视规格(2026-06-26确认)
			_camera_3d.transform = Transform3D(
				Basis(Vector3.RIGHT, deg_to_rad(-45.0)),
				Vector3(0.0, 1.8, 3.0)
			)
		VIEW_MODE_FOLLOW:
			# 平视跟随: 相机与球员等高(1.0m),正前方 3.5m 平视
			# 单位矩阵(无旋转),镜头朝 -Z 看向球员正脸
			_camera_3d.transform = Transform3D(
				Basis(),
				Vector3(0.0, 1.0, 3.5)
			)
		_:
			pass


func _teardown_visuals() -> void:
	# 释放所有视觉子节点(不含碰撞,碰撞靠 _setup_visuals 里的 has_node 判断保留)
	for node in [avatar_bg, avatar_label, state_indicator, model_3d_anchor]:
		if node and is_instance_valid(node):
			node.queue_free()
	avatar_bg = null
	avatar_label = null
	state_indicator = null
	model_3d_anchor = null
	# 清掉 3D 相关引用(避免悬挂指针,防止幂等重建时复用旧引用)
	_animation_player = null
	_model_slot = null
	_camera_3d = null
	_current_anim_name = ""
	_is_3d_moving = false


func _make_circle_style(radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLUE
	style.set_corner_radius_all(int(radius))
	return style


func _get_display_number() -> String:
	if char_data.is_empty():
		return "#"
	return str(char_data["name"] if char_data.has("name") else "#").substr(0, 1)


func _physics_process(delta: float) -> void:
	# 3D 模式:基于上一帧 velocity 更新动画和朝向(放在函数最前,避开多个 return 出口)
	if USE_3D_MODEL:
		_update_3d_animation()
		_update_3d_facing()
		# 关键: 手动推进动画(SubViewport 内 AnimationPlayer 不会自动推进,必须手动 advance)
		if _animation_player and is_instance_valid(_animation_player) and _animation_player.is_playing():
			_animation_player.advance(delta)

	# 冲刺计时器更新（无论谁控制都要跑）
	if is_sprinting:
		sprint_timer -= delta
		if sprint_timer <= 0.0:
			is_sprinting = false
			sprint_timer = 0.0
			sprint_cooldown = SPRINT_COOLDOWN
	elif sprint_cooldown > 0.0:
		sprint_cooldown -= delta
		if sprint_cooldown < 0.0:
			sprint_cooldown = 0.0

	# 击退中：匀减速到0（不处理输入）
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		_tick_all_timers(delta)

		# 匀减速：速度线性衰减到0
		if _knockback_duration > 0.0:
			var progress: float = 1.0 - (_knockback_timer / _knockback_duration)
			var current_speed: float = _knockback_start_velocity * (1.0 - progress)
			velocity = knockback_dir * current_speed
		else:
			velocity = Vector2.ZERO
		
		move_and_slide()
		
		# 击退结束
		if _knockback_timer <= 0.0:
			_knockback_timer = 0.0
			velocity = Vector2.ZERO
			knockback_dir = Vector2.ZERO
		return

	# 僵直/眩晕/定身：无法移动（站着不动）
	if _stagger_timer > 0.0 or is_status_active("stunned") or is_status_active("rooted"):
		if _stagger_timer > 0.0:
			_stagger_timer -= delta
			if _stagger_timer <= 0.0:
				_stagger_timer = 0.0
		_tick_all_timers(delta)
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# 所有球员（包括AI和非玩家控制）都要更新持续效果
	_tick_all_timers(delta)

	if not is_player_controlled:
		move_and_slide()
		return  # AI控制由AI管理器处理

	# 计算实际移动速度（含冲刺加成）
	var move_speed: float = _get_effective_value("speed", speed)
	if is_sprinting:
		move_speed += SPRINT_SPEED_BONUS

	# 移动（包括外场球员，由隔离墙限制范围即可）
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")

	if input_dir != Vector2.ZERO:
		# W键（上）：朝鼠标方向移动
		if input_dir.y < 0:
			velocity = facing_direction * move_speed
		else:
			velocity = input_dir.normalized() * move_speed
		# 玩家控制时根据移动方向更新朝向
		if velocity.length() > 1.0:
			facing_direction = velocity.normalized()
	else:
		velocity = Vector2.ZERO

	move_and_slide()


func take_damage(amount: float, attacker: CharacterBody2D = null) -> Dictionary:
	"""受到伤害,返回 {damage: int, effect: String}
	effect: "none" / "knockback1" / "knockback2" / "ball_fly" / "knockback_and_fly"

	非待接球: 新体力 = 当前体力 + 防御抗力 - 攻击（无韧性）
	待接球:   新体力 = 当前体力 + 防御抗力 - 攻击×(1-衰减率)（韧性生效+效果判定）
	"""
	if is_defeated:
		return {"damage": 0, "effect": "none"}

	# 无敌检查：灯亮则不受伤
	if is_status_active("invincible"):
		return {"damage": 0, "effect": "none"}

	# 易伤倍率
	var dmg_mult: float = 1.0
	if is_status_active("vulnerable"):
		dmg_mult = _status_lights["vulnerable"].get("multiplier", 1.5)
	var effective_amount: float = amount * dmg_mult

	var defense_resist: float = _get_effective_value("defense", defense) * defense_factor
	var actual_damage: int = 0
	var decay_rate: float = 0.0
	var effect: String = "none"

	if is_ready_to_catch:
		# === 待接球: 韧性系统生效 ===
		# 1. 韧性伤害衰减百分比
		decay_rate = _get_resilience_decay_rate(_get_effective_value("resilience", resilience))
		var reduced_attack: float = effective_amount * (1.0 - decay_rate)
		actual_damage = int(max(0, reduced_attack - defense_resist))

		# 2. 扣血（取整）
		stamina = int(max(0, stamina + defense_resist - reduced_attack))

		# 3. 僵直时间（与韧性反比，四段）
		var base_stagger: float = _get_stagger_by_resilience(_get_effective_value("resilience", resilience))

		# 4. 韧性效果判定（与衰减同时发生，三选一）
		effect = _roll_resilience_effect(_get_effective_value("resilience", resilience))
		if effect == "knockback1":
			_apply_knockback(attacker, 100.0)
			_stagger_timer = max(base_stagger, _knockback_timer)
		elif effect == "knockback2":
			_apply_knockback(attacker, 200.0)
			_stagger_timer = max(base_stagger, _knockback_timer)
		elif effect == "ball_fly" or effect == "knockback_and_fly":
			if effect == "knockback_and_fly":
				_apply_knockback(attacker, 100.0)
				_stagger_timer = max(base_stagger, _knockback_timer)
			else:
				_stagger_timer = max(base_stagger, 0.5)  # 弹飞球飞行约0.5s
		else:
			_stagger_timer = base_stagger
	else:
		# === 非待接球: 新体力 = 当前体力 + 防御抗力 - 攻击 ===
		actual_damage = int(max(0, effective_amount - defense_resist))
		stamina = int(max(0, stamina + defense_resist - effective_amount))
		# 非待接球无韧性保护，但僵直仍按韧性查表
		_stagger_timer = _get_stagger_by_resilience(_get_effective_value("resilience", resilience))

	# 体力条由下方球员栏更新，此处不处理

	# 检查是否被击败
	if stamina <= 0 and not is_defeated:
		_on_defeated()

	var pname: String = char_data["name"] if char_data.has("name") else "?"
	if decay_rate > 0.0:
		print("[Player] %s 待接球受伤 %d(衰减%.0f%% 防御抗力%.1f) 效果=%s 剩余体力%d" % [pname, actual_damage, decay_rate * 100.0, defense_resist, effect, stamina])
	else:
		print("[Player] %s 非接球受伤 %d(防御抗力%.1f) 剩余体力%d" % [pname, actual_damage, defense_resist, stamina])

	return {"damage": actual_damage, "effect": effect}


func _get_resilience_decay_rate(rd: float) -> float:
	"""韧性伤害衰减百分比（查表）"""
	if rd >= 90.0:
		return 0.5 * rd / 100.0
	elif rd >= 80.0:
		return 0.4 * rd / 100.0
	elif rd >= 60.0:
		return 0.3 * rd / 100.0
	elif rd >= 40.0:
		return 0.2 * rd / 100.0
	elif rd >= 30.0:
		return 0.1 * rd / 100.0
	else:
		return 0.0


func _get_stagger_by_resilience(rd: float) -> float:
	"""僵直时间与韧性反比（四段，最小0.3s）
	韧性 0-25 → 0.7s
	韧性 26-50 → 0.5s
	韧性 51-75 → 0.4s
	韧性 76-100 → 0.3s
	"""
	if rd >= 76.0:
		return 0.3
	elif rd >= 51.0:
		return 0.4
	elif rd >= 26.0:
		return 0.5
	else:
		return 0.7


func _roll_resilience_effect(rd: float) -> String:
	"""韧性效果判定（三选一 + 击退分段）"""
	# 查效果概率表
	var p_knockback_and_fly: float
	var p_ball_fly: float
	var p_knockback: float

	if rd < 30.0:
		p_knockback_and_fly = 0.3
		p_ball_fly = 0.45
		p_knockback = 0.25
	elif rd < 70.0:
		p_knockback_and_fly = 0.2
		p_ball_fly = 0.4
		p_knockback = 0.4
	else:
		p_knockback_and_fly = 0.1
		p_ball_fly = 0.4
		p_knockback = 0.5

	var roll: float = randf()

	if roll < p_knockback_and_fly:
		return "knockback_and_fly"
	elif roll < p_knockback_and_fly + p_ball_fly:
		return "ball_fly"
	else:
		# 击退：再分一段/二段
		var p_phase2: float = _get_phase2_knockback_chance()
		if randf() < p_phase2:
			return "knockback2"
		else:
			return "knockback1"


func _get_phase2_knockback_chance() -> float:
	"""二段击退概率 = 体力因子 × 剩余元灵能量因子"""
	# 体力因子
	var stamina_ratio: float = (stamina / max_stamina) * 100.0
	var stamina_factor: float
	if stamina_ratio < 30.0:
		stamina_factor = 0.6
	elif stamina_ratio < 60.0:
		stamina_factor = 0.3
	else:
		stamina_factor = 0.1

	# 元灵能量因子
	var energy_ratio: float = (spirit_energy / max_spirit_energy) * 100.0 if max_spirit_energy > 0.0 else 0.0
	var energy_factor: float
	if energy_ratio < 30.0:
		energy_factor = 0.5
	elif energy_ratio < 60.0:
		energy_factor = 0.3
	else:
		energy_factor = 0.2

	return stamina_factor * energy_factor


## 获取场地摩擦系数
func _get_field_friction() -> float:
	"""获取当前场地摩擦系数 μ
	
	从场地物理管理器读取摩擦系数，用于击退距离计算
	
	查找顺序：
	1. 尝试绝对路径 /root/BattleManager
	2. 尝试绝对路径 /root/BattleArena
	3. 尝试场景树查找
	"""
	# 方法1：尝试绝对路径 /root/BattleManager
	var battle_manager = get_node_or_null("/root/BattleManager")
	if not battle_manager:
		# 方法2：尝试绝对路径 /root/BattleArena
		battle_manager = get_node_or_null("/root/BattleArena")
	
	if not battle_manager:
		# 方法3：场景树查找（向上遍历）
		var parent = get_parent()
		while parent:
			if parent.has_method("has_method") and parent.has_method("get_node"):
				if parent.get_node_or_null("FieldPhysicsManager"):
					battle_manager = parent
					break
			parent = parent.get_parent()
	
	if battle_manager:
		var field_physics = battle_manager.get_node_or_null("FieldPhysicsManager")
		if field_physics and field_physics.has_method("get_friction"):
			return field_physics.get_friction()
		else:
			print("[Player] 警告：找到 BattleManager 但找不到 FieldPhysicsManager")
	else:
		print("[Player] 警告：找不到 BattleManager/BattleArena")
	
	return 1.0  # 默认标准地面


## 击退系统（物理化）
func _apply_knockback(attacker: CharacterBody2D, distance: float = 100.0) -> void:
	"""被击退（物理化版本）
	
	参数：
	- attacker: 攻击者
	- distance: 基准距离（100=一段, 200=二段）
	
	物理逻辑：
	1. 读取场地摩擦系数 μ
	2. 根据 μ 和基准距离计算实际击退距离：d = distance / μ
	3. 根据距离和僵直时间计算初始速度：v = 2 × d / t
	4. 匀减速动画：速度线性衰减到0
	"""
	if attacker == null:
		return
	
	# 1. 确定击退类型
	var knockback_type: String = "knockback1" if distance <= 150.0 else "knockback2"
	
	# 2. 获取僵直时间（已由韧性系统计算，从 _stagger_timer 获取）
	var stagger_duration: float = _get_stagger_by_resilience(resilience)
	
	# 3. 读取场地摩擦系数
	var mu: float = _get_field_friction()
	
	# 4. 物理计算（使用 KnockbackPhysics 模块）
	var result: Dictionary = KnockbackPhysics.calculate_knockback(
		knockback_type,   # 击退类型
		mu,              # 摩擦系数
		stagger_duration, # 僵直时间
		1.0,             # 技能倍率（默认1.0）
		0.0,             # 技能固定加成
		400.0,           # 球速
		false            # 不启用球速加成
	)
	
	# 5. 应用击退
	knockback_dir = (global_position - attacker.global_position).normalized()
	velocity = knockback_dir * result.initial_velocity
	
	# 6. 设置击退计时器（用于匀减速动画）
	_knockback_timer = result.duration
	_knockback_duration = result.duration
	_knockback_start_velocity = result.initial_velocity
	
	var pname: String = char_data.get("name", "?")
	print("[Player] %s 击退! μ=%.2f 僵直%.2fs 距离%.0fpx 初速%.0f" % [
		pname, mu, result.duration, result.distance, result.initial_velocity
	])


func _on_defeated() -> void:
	"""被击败:全属性减半,对手得分,发出信号"""
	is_defeated = true

	# 移除与球的碰撞(layer 1)，球不再击中被击败球员
	collision_layer = 0
	collision_mask = 0

	# 属性减半
	attack_power *= 0.5
	defense *= 0.5
	speed *= 0.5
	max_spirit_energy *= 0.5
	spirit_energy = min(spirit_energy, max_spirit_energy)

	# 视觉变化
	if avatar_bg:
		avatar_bg.color = avatar_bg.color.darkened(0.5)
	if avatar_label:
		avatar_label.add_theme_color_override("font_color", Color.GRAY)

	# 发出被击败信号(通知 battle_manager 移动到外场)
	defeated.emit(self)

	# 对手得分
	var scoring_team := "b" if team == "a" else "a"
	GameManager.add_score(scoring_team)

	print("[Player] %s 被击败! 属性减半" % (char_data["name"] if char_data.has("name") else ""))


func set_penalized(penalized: bool) -> void:
	"""设置惩罚状态(更新碰撞层)"""
	is_penalized = penalized
	var pname: String = char_data["name"] if char_data and char_data.has("name") else "?"
	if penalized:
		# 恢复球员间碰撞 + 与隔离墙碰撞
		collision_layer = 1  # layer 1 (球员)
		collision_mask = 1 | (1 << 4)  # layer 1(球员互碰) + layer 5(隔离墙)
		print("[Player] %s (队%s) 被隔离 pos=%.0f,%.0f layer=%d mask=%d" % [pname, team, global_position.x, global_position.y, collision_layer, collision_mask])
	else:
		# 正常时,恢复标准碰撞
		collision_layer = 1
		collision_mask = 1  # layer 1 only
		print("[Player] %s (队%s) 解除隔离" % [pname, team])


func enter_catch_state() -> void:
	"""进入待接球状态"""
	is_ready_to_catch = true
	if state_indicator:
		state_indicator.color = Color.YELLOW


func exit_catch_state() -> void:
	"""退出待接球状态"""
	is_ready_to_catch = false
	if state_indicator:
		state_indicator.color = Color.TRANSPARENT


func set_carrying_ball(carrying: bool) -> void:
	is_carrying_ball = carrying
	if carrying:
		if state_indicator:
			state_indicator.color = Color.GREEN
		# 持球时显示已激活技能的光环
		_update_ball_skill_aura()
	elif not is_ready_to_catch:
		if state_indicator:
			state_indicator.color = Color.TRANSPARENT
		# 不持球时清除光环
		_clear_ball_skill_aura()


func can_be_scored_against() -> bool:
	"""是否还能被得分(被击败后不能)"""
	return not is_defeated


func use_skill(slot_index: int) -> void:
	"""使用技能"""
	if slot_index >= equipped_skills.size():
		return

	# 沉默检查：灯亮则不能技能
	if is_status_active("silenced"):
		return

	var skill_id: String = equipped_skills[slot_index]
	var skill_data: Dictionary = DataManager.get_skill_by_id(skill_id)
	if skill_data.is_empty():
		return

	# 检查解锁（没有 unlocked 字段默认为已解锁）
	if skill_data.has("unlocked") and not skill_data["unlocked"]:
		print("[Player] 技能未解锁: %s" % (skill_data.get("name", "")))
		return

	# 检查CD
	var current_cd: float = skill_cooldowns[skill_id] if skill_cooldowns.has(skill_id) else 0.0
	if current_cd > 0:
		print("[Player] 技能冷却中: %s" % (skill_data.get("name") if skill_data.has("name") else ""))
		return

	# 检查能量（应用消耗折扣卡）
	# 总能量消耗 = 技能基础消耗 + 所有标签能量消耗
	var base_cost: float = float(skill_data["energy_cost"] if skill_data.has("energy_cost") else 0)
	var tags: Array = skill_data.get("tags", [])
	var tags_cost: float = 0.0

	# 累加标签能量消耗
	for tag_id in tags:
		var tag_data: Dictionary = DataManager.get_tag_by_id(tag_id)
		if not tag_data.is_empty() and tag_data.has("energy_cost"):
			tags_cost += float(tag_data["energy_cost"])

	var total_cost: float = (base_cost + tags_cost) * get_skill_cost_mult()

	if spirit_energy < total_cost:
		print("[Player] 能量不足: %s (需要%.1f, 当前%.1f)" % [(skill_data.get("name") if skill_data.has("name") else ""), total_cost, spirit_energy])
		return

	# 消耗能量
	spirit_energy -= total_cost
	print("[Player] 扣除能量: %.1f (基础:%.1f + 标签:%.1f)" % [total_cost, base_cost, tags_cost])
	# 能量条由下方球员栏更新，此处不处理

	# 设置CD（应用CD折扣卡）
	skill_cooldowns[skill_id] = float(skill_data["cooldown"] if skill_data.has("cooldown") else 5.0) * get_skill_cd_mult()

	print("[Player] %s 使用技能: %s" % [char_data["name"] if char_data.has("name") else "", skill_data.get("name") if skill_data.has("name") else ""])

	# 技能效果由SkillSystem处理
	skill_used.emit(skill_id, skill_data)


signal skill_used(skill_id: String, skill_data: Dictionary)
signal facing_direction_changed()
signal message_bubble_requested(text: String, duration: float)


func start_sprint() -> bool:
	"""尝试开始冲刺，返回是否成功"""
	if is_sprinting or sprint_cooldown > 0.0 or is_carrying_ball:
		return false
	is_sprinting = true
	sprint_timer = SPRINT_DURATION
	return true


func show_message_bubble(text: String, duration: float = 0.5) -> void:
	"""在球员头顶显示消息气泡"""
	message_bubble_requested.emit(text, duration)


## ==================== 技能光环系统（球）====================

var _active_skill_id: String = ""


func set_active_skill(skill_id: String) -> void:
	"""设置当前激活的技能（外部调用）"""
	_active_skill_id = skill_id
	if is_carrying_ball:
		_update_ball_skill_aura()


func clear_active_skill() -> void:
	"""清除当前激活的技能（外部调用）"""
	_active_skill_id = ""
	_clear_ball_skill_aura()


func get_active_skill_id() -> String:
	"""获取当前激活的技能ID"""
	return _active_skill_id


func _update_ball_skill_aura() -> void:
	"""更新球的技能光环显示"""
	if _active_skill_id.is_empty() or not is_carrying_ball:
		return

	var ball_node = _get_ball_node()
	if ball_node and ball_node.has_method("set_active_skill"):
		var skill_data = DataManager.get_skill_by_id(_active_skill_id)
		if not skill_data.is_empty():
			ball_node.set_active_skill(skill_data)
			print("[Player] 显示球技能光环: %s" % _active_skill_id)


func _clear_ball_skill_aura() -> void:
	"""清除球的技能光环"""
	var ball_node = _get_ball_node()
	if ball_node and ball_node.has_method("cancel_active_skill"):
		ball_node.cancel_active_skill()


func _get_ball_node() -> Node:
	"""获取球节点"""
	var tree = get_tree()
	if tree:
		var ball_nodes = tree.get_nodes_in_group("ball")
		if not ball_nodes.is_empty():
			return ball_nodes[0]
	return null


## 通过技能ID使用技能（供外部调用）
func use_skill_by_id(skill_id: String) -> void:
	"""通过技能ID使用技能"""
	for i in range(equipped_skills.size()):
		if equipped_skills[i] == skill_id:
			use_skill(i)
			return
	print("[Player] 未找到技能ID: %s" % skill_id)


## 获取装备的技能ID列表
func get_equipped_skills() -> Array[String]:
	"""返回装备的技能ID列表"""
	var result: Array[String] = []
	for skill_id in equipped_skills:
		result.append(str(skill_id))
	return result


## 返回球员视觉尺寸（半径），用于技能轮廓渲染（2026-06-19）
## 智能识别接口：未来3D化时只需改这里
func get_visual_radius() -> float:
	return 28.0  # 当前2D圆头像半径，与 _setup_visuals 中 circle.radius 一致


## 返回某技能的冷却进度（0=可用，1=刚释放满冷却）
func get_skill_cooldown_ratio(skill_id: String) -> float:
	if not skill_cooldowns.has(skill_id) or skill_cooldowns[skill_id] <= 0.0:
		return 0.0
	var skill_data: Dictionary = DataManager.get_skill_by_id(skill_id)
	var base_cd: float = float(skill_data.get("cooldown", 5.0))
	if base_cd <= 0.0:
		return 0.0
	return clampf(skill_cooldowns[skill_id] / base_cd, 0.0, 1.0)


func load_spirit_by_element(element: String) -> void:
	"""根据元素类型加载元灵及其技能"""
	if not DataManager:
		return
	var spirit_data: Dictionary = {}
	if DataManager.has_method("get_spirit_by_element"):
		spirit_data = DataManager.get_spirit_by_element(element)
	if spirit_data.is_empty():
		# 备用：遍历所有元灵
		for s in DataManager.spirits:
			if str(s.get("element", "")) == element:
				spirit_data = s
				break
	if not spirit_data.is_empty():
		equip_spirit(spirit_data)


func equip_spirit(spirit_data: Dictionary) -> void:
	"""装备元灵，加载其技能到 equipped_skills"""
	spirit_id = str(spirit_data.get("id", ""))
	equipped_skills.clear()
	var skill_ids = spirit_data.get("skills", [])
	for sid in skill_ids:
		equipped_skills.append(sid)
	# 初始化技能冷却
	skill_cooldowns.clear()
	for sid in equipped_skills:
		skill_cooldowns[str(sid)] = 0.0
	print("[Player] %s 装备元灵: %s 技能=%s" % [char_data.get("name", "?"), spirit_data.get("name", "?"), str(skill_ids)])


func unequip_spirit() -> void:
	"""卸下元灵，清空 equipped_skills"""
	spirit_id = ""
	equipped_skills.clear()
	skill_cooldowns.clear()
	print("[Player] %s 卸下元灵" % char_data.get("name", "?"))


## ==================== 状态灯系统（第2步：控制状态）====================

# 控制类状态名列表（受免控灯保护）
const _CC_STATUSES: PackedStringArray = ["stunned", "silenced", "disarmed", "rooted"]

# 互斥状态灯映射：灯名 → 互斥规则
# "block": 互斥灯存在时拒绝点此灯
# "clear": 点此灯时清除互斥灯
const _MUTEX_LIGHTS: Dictionary = {
	"invincible": {"block": ["vulnerable"]},       # 无敌期间易伤无效
	"vulnerable": {"block": ["invincible"]},        # 易伤被无敌阻塞（无敌优先，不破无敌）
	"reveal": {"clear": ["stealthed"]},  # 显形清除隐身
}


func is_status_active(status_name: String) -> bool:
	"""灯亮没亮？"""
	return _status_lights.has(status_name) and _status_lights[status_name].get("on", false)


func turn_on_light(status_name: String, duration: float, extra: Dictionary = {}) -> bool:
	"""点灯（返回true=成功，false=被免控拦截）
	控制类状态（眩晕/沉默/缴械/定身）会被免控灯拦截
	同一盏灯重复点会刷新时间
	互斥灯会清除/拦截对应状态"""
	# 控制类状态，先检查免控灯
	if status_name in _CC_STATUSES:
		if is_status_active("cc_immune"):
			return false

	# 互斥检查
	if _MUTEX_LIGHTS.has(status_name):
		var mutex: Dictionary = _MUTEX_LIGHTS[status_name]
		var block_list: Array = mutex.get("block", [])
		var clear_list: Array = mutex.get("clear", [])
		
		# 检查是否被其他灯阻塞
		for block_light in block_list:
			if is_status_active(block_light):
				return false
		
		# 清除互斥的灯
		for clear_light in clear_list:
			if is_status_active(clear_light):
				turn_off_light(clear_light)

	# 设置状态灯（所有灯都会设置到这里）
	_status_lights[status_name] = {
		"on": true,
		"remaining": duration,
	}
	# 附加额外数据（如易伤倍率）
	for key in extra:
		_status_lights[status_name][key] = extra[key]
	return true


func turn_off_light(status_name: String) -> void:
	"""关灯（手动，如解控）"""
	_status_lights.erase(status_name)


func turn_off_lights_by_type(light_names: PackedStringArray) -> void:
	"""关掉指定类型的所有灯"""
	for name in light_names:
		_status_lights.erase(name)


func _tick_status_lights(delta: float) -> void:
	"""每帧倒计时，到期自动关灯"""
	var to_remove: PackedStringArray = []
	for status in _status_lights:
		var remaining: float = _status_lights[status].get("remaining", 0.0) - delta
		if remaining <= 0.0:
			to_remove.append(status)
		else:
			_status_lights[status]["remaining"] = remaining
	for status in to_remove:
		_status_lights.erase(status)


## ==================== 闹钟纸条系统（第3步：持续效果）====================


func add_tick_effect(id: String, type: String, rate: float, duration: float, affected_stats: Array = []) -> void:
	"""添加一个持续效果（闹钟纸条）
	type: "regen"（持续恢复）或 "dot"（持续掉血）
	rate: 每秒的量
	duration: 持续时间（秒）
	affected_stats: 影响的属性列表 ["attack", "defense"] - tick时动态读这些属性的buff倍率
	同id重复添加会覆盖"""
	_tick_effects[id] = {
		"type": type,
		"rate": rate,
		"remaining": duration,
		"affected_stats": affected_stats,
	}


func remove_tick_effect(id: String) -> bool:
	"""手动撕掉一张纸条"""
	return _tick_effects.erase(id)


func has_tick_effect(id: String) -> bool:
	"""纸条还在不在？"""
	return _tick_effects.has(id)


func get_total_tick_rate(type: String) -> float:
	"""某个类型的总速率（如所有regen加起来每秒回多少）"""
	var total: float = 0.0
	for id in _tick_effects:
		if _tick_effects[id].get("type", "") == type:
			total += _tick_effects[id].get("rate", 0.0)
	return total


func _tick_all_timers(delta: float) -> void:
	"""统一更新所有持续效果计时器（状态灯/闹钟/buff/折扣卡/技能CD）"""
	# 技能冷却递减（每帧）
	if not skill_cooldowns.is_empty():
		for sid in skill_cooldowns:
			var cd: float = skill_cooldowns[sid] - delta
			skill_cooldowns[sid] = cd if cd > 0.0 else 0.0
	# 场上元灵能量每秒恢复1点
	if spirit_energy < max_spirit_energy:
		spirit_energy = minf(max_spirit_energy, spirit_energy + delta)
	_tick_status_lights(delta)
	_process_tick_effects(delta)
	_tick_buffs(delta)
	_process_discount_cards(delta)


func _process_tick_effects(delta: float) -> void:
	"""每帧执行：运行闹钟纸条 + 倒计时 + 撕掉到期的"""
	var to_remove: PackedStringArray = []
	for id in _tick_effects:
		var effect: Dictionary = _tick_effects[id]
		var etype: String = effect.get("type", "")
		var rate: float = effect.get("rate", 0.0)

		# 每帧执行
		if etype == "regen":
			stamina = minf(max_stamina, stamina + rate * delta)
		elif etype == "dot":
			# 无敌灯亮时，不掉血（但倒计时照跑）
			if not is_status_active("invincible"):
				var base_rate: float = rate
				# 思想2：数值层相互影响（buff 栈影响持续效果）
				var affected_stats: Array = effect.get("affected_stats", [])
				for stat in affected_stats:
					if stat == "attack":
						var attack_mult: float = _get_effective_value("attack", attack_power) / attack_power
						base_rate *= attack_mult
				stamina = maxf(0.0, stamina - base_rate * delta)
				if stamina <= 0.0 and not is_defeated:
					_on_defeated()

		# 倒计时
		effect["remaining"] = effect.get("remaining", 0.0) - delta
		if effect.get("remaining", 0.0) <= 0.0:
			to_remove.append(id)

	for id in to_remove:
		_tick_effects.erase(id)


## ==================== 折扣卡系统（第4步：技能倍率）====================


func add_skill_cost_mult(id: String, mult: float, duration: float) -> void:
	"""添加消耗折扣卡，同id覆盖"""
	_skill_cost_mults[id] = { "mult": mult, "remaining": duration }


func get_skill_cost_mult() -> float:
	"""消耗倍率 = 所有卡连乘"""
	var m: float = 1.0
	for id in _skill_cost_mults:
		m *= _skill_cost_mults[id].get("mult", 1.0)
	return m


func add_skill_cd_mult(id: String, mult: float, duration: float) -> void:
	"""添加CD折扣卡，同id覆盖"""
	_skill_cd_mults[id] = { "mult": mult, "remaining": duration }


func get_skill_cd_mult() -> float:
	"""CD倍率 = 所有卡连乘"""
	var m: float = 1.0
	for id in _skill_cd_mults:
		m *= _skill_cd_mults[id].get("mult", 1.0)
	return m


func add_next_skill_mult(mult: float) -> void:
	"""添加效果倍率卡（一次性，技能使用时消费）"""
	_next_skill_mults.append(mult)


func get_and_consume_next_skill_mult() -> float:
	"""读取并消费效果倍率
	第1张卡全效，后续每张只取1/10
	无卡返回1.0"""
	if _next_skill_mults.is_empty():
		return 1.0
	var total: float = 0.0
	for i in range(_next_skill_mults.size()):
		var m: float = _next_skill_mults[i]
		if i == 0:
			total = m
		else:
			total += m * 0.1
	_next_skill_mults.clear()
	return total


func remove_skill_cost_mult(id: String) -> bool:
	return _skill_cost_mults.erase(id)


func remove_skill_cd_mult(id: String) -> bool:
	return _skill_cd_mults.erase(id)


func add_skill_bonus_uses(skill_id: String, bonus: int) -> void:
	"""增加技能使用次数"""
	if not _skill_bonus_uses.has(skill_id):
		_skill_bonus_uses[skill_id] = 0
	_skill_bonus_uses[skill_id] += bonus


func get_skill_bonus_uses(skill_id: String) -> int:
	return _skill_bonus_uses.get(skill_id, 0)


func _process_discount_cards(delta: float) -> void:
	"""每帧倒计时折扣卡，到期收回"""
	_tick_mult_dict(_skill_cost_mults, delta)
	_tick_mult_dict(_skill_cd_mults, delta)


func _tick_mult_dict(d: Dictionary, delta: float) -> void:
	var to_remove: PackedStringArray = []
	for id in d:
		d[id]["remaining"] = d[id].get("remaining", 0.0) - delta
		if d[id].get("remaining", 0.0) <= 0.0:
			to_remove.append(id)
	for id in to_remove:
		d.erase(id)


## ==================== Buff堆栈接口（第1步：属性修改器）====================


func add_buff(id: String, stat: String, mult: float, flat: float, duration: float, source: String = "") -> void:
	"""添加/覆盖属性buff
	stat: attack/defense/speed/resilience/max_energy
	mult: 乘法修正（1.0=不改）
	flat: 加法修正（0.0=不改）
	duration: 持续时间，<=0永久"""
	_buffs[id] = {
		"id": id,
		"stat": stat,
		"mult": mult,
		"flat": flat,
		"source": source,
		"duration": duration,
		"remaining": duration,
	}


func remove_buff(id: String) -> bool:
	return _buffs.erase(id)


func has_buff(id: String) -> bool:
	return _buffs.has(id)


func get_buff_count() -> int:
	return _buffs.size()


func _get_effective_value(stat: String, base_value: float) -> float:
	"""计算某个属性的最终值 = 基础×连乘 + 加法求和"""
	var m: float = 1.0
	var f: float = 0.0
	for id in _buffs:
		var b: Dictionary = _buffs[id]
		if b.get("stat", "") == stat:
			m *= b.get("mult", 1.0)
			f += b.get("flat", 0.0)
	m = maxf(m, 0.01)
	return base_value * m + f


func _tick_buffs(delta: float) -> void:
	var to_remove: PackedStringArray = []
	for id in _buffs:
		var b: Dictionary = _buffs[id]
		if b.get("duration", 0.0) <= 0.0:
			continue
		b["remaining"] = b.get("remaining", 0.0) - delta
		if b.get("remaining", 0.0) <= 0.0:
			to_remove.append(id)
	for id in to_remove:
		_buffs.erase(id)


## ==================== 传送系统 ====================

var _pre_teleport_pos: Vector2 = Vector2.ZERO

func teleport_to(pos: Vector2) -> void:
	"""传送到指定位置"""
	_pre_teleport_pos = global_position
	global_position = pos

func return_to_previous() -> void:
	"""返回传送前位置"""
	if _pre_teleport_pos != Vector2.ZERO:
		global_position = _pre_teleport_pos
		_pre_teleport_pos = Vector2.ZERO
