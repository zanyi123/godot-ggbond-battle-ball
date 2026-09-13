## 球员 3D 视觉代理（battle3d 模块 · Phase 1）
## 移植自 scripts/test/player_3d_test.gd :831-1350 已验证模式：
##   FBX 骨架 mesh（scale=1.0 铁律） + ModelSlot(scale=70 唯一缩放点)
##   + 手动 PBR 贴图 + 共享 Mixamo 动画合并 + Root Motion 剥离
## 只读代理：由 2D 层数据驱动，不回写任何游戏状态。
class_name PlayerProxy3D
extends Node3D

const CFG = preload("res://scripts/battle3d/battle3d_const.gd")

## 共享动画 FBX 场景缓存（全进程一次）
static var _shared_anim_scenes: Dictionary = {}

var char_id: String = ""
var team_color: Color = Color.WHITE

var _anim_player: AnimationPlayer = null
var _body_inst: Node = null
var _root_bone_node: Node3D = null
var _cur_anim: String = "idle"
var _action_lock: bool = false
var _hand_proxy: Node3D = null
var _mesh_ok: bool = false
var _mesh_instances: Array = []  # MeshInstance3D 缓存（击倒透明化用）

## ==================== 构建 ====================

func setup(p_char_id: String, p_team_color: Color) -> void:
	char_id = p_char_id
	team_color = p_team_color
	name = "PlayerProxy3D_" + char_id

	if not CFG.MODEL_MAP.has(char_id):
		push_error("[PlayerProxy3D] 未知 char_id: %s" % char_id)
		return

	var entry: Dictionary = CFG.MODEL_MAP[char_id]

	# ========== ModelSlot（唯一缩放控制点，铁律 scale=70） ==========
	var slot := Node3D.new()
	slot.name = "ModelSlot"
	slot.scale = Vector3(CFG.PROXY_SCALE, CFG.PROXY_SCALE, CFG.PROXY_SCALE)
	add_child(slot)

	# ========== 0. GLB 外观模式（无专属动作 FBX 的角色：用专属 base.glb 的正确网格/材质，静止姿势） ==========
	var mesh_path: String = entry.get("mesh_fbx", "")
	if mesh_path == "" and entry.has("model_glb"):
		var glb_scene: PackedScene = load(entry["model_glb"])
		if glb_scene != null:
			var glb_inst := glb_scene.instantiate()
			slot.add_child(glb_inst)
			# 混元 GLB 材质修正（metallic/roughness）
			for mi in glb_inst.find_children("*", "MeshInstance3D", true, false):
				var m3 := mi as MeshInstance3D
				if m3.mesh == null:
					continue
				for s in range(m3.mesh.get_surface_count()):
					var mat = m3.mesh.surface_get_material(s)
					if mat is StandardMaterial3D:
						var sm := mat as StandardMaterial3D
						if sm.metallic > 0.5:
							sm.metallic = 0.0
						if sm.roughness > 0.8:
							sm.roughness = 0.6
						sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			_mesh_ok = true
			_mesh_instances = glb_inst.find_children("*", "MeshInstance3D", true, false)
			# GLB 自带动画就播放第一个，否则静止
			var gap := glb_inst.find_children("*", "AnimationPlayer", true, false)
			if gap.size() > 0:
				var gap_ap := gap[0] as AnimationPlayer
				if gap_ap.get_animation_list().size() > 0:
					gap_ap.play(gap_ap.get_animation_list()[0])
			print("[PlayerProxy3D] %s GLB 外观模式（无专属动画=静止）" % char_id)
			_build_ring_only()
			var ghand := Node3D.new()
			ghand.name = "HandProxy"
			ghand.position = Vector3(8.0, 30.0, 0.0)
			add_child(ghand)
			_hand_proxy = ghand
			return
		push_error("[PlayerProxy3D] %s GLB 加载失败" % char_id)
		_build_ring_only()
		return

	# ========== 1. 加载专属 idle 媒势 FBX（带骨骼 mesh） ==========
	var mesh_scene: PackedScene = load(mesh_path) if mesh_path != "" else null
	if mesh_scene == null:
		push_error("[PlayerProxy3D] %s 无法加载 mesh FBX: %s" % [char_id, mesh_path])
		_build_ring_only()
		return

	_body_inst = mesh_scene.instantiate()
	if _body_inst == null or not (_body_inst is Node):
		push_error("[PlayerProxy3D] %s mesh FBX 实例化失败" % char_id)
		_build_ring_only()
		return
	slot.add_child(_body_inst)
	# E10 诊断：实际加载的 mesh 资源路径 + 内嵌贴图
	print("[E10诊断] %s mesh源=%s" % [char_id, mesh_path])
	for mi in _body_inst.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh != null:
			var tex_names: Array = []
			for s2 in range(m3.mesh.get_surface_count()):
				var mm = m3.mesh.surface_get_material(s2)
				if mm is StandardMaterial3D and mm.albedo_texture != null:
					tex_names.append(mm.albedo_texture.resource_path.get_file())
				elif mm is StandardMaterial3D:
					tex_names.append("无贴图材质")
			print("[E10诊断]   mesh=%s 内嵌贴图=%s" % [m3.name, str(tex_names)])
	# 缩放铁律：FBX 强制 1.0，由 ModelSlot 的 70 控制大小
	if _body_inst is Node3D:
		(_body_inst as Node3D).scale = Vector3(CFG.PROXY_FBX_SCALE, CFG.PROXY_FBX_SCALE, CFG.PROXY_FBX_SCALE)
	_hide_mixamo_helpers(_body_inst)
	_mesh_ok = true
	_mesh_instances = _body_inst.find_children("*", "MeshInstance3D", true, false)

	# ========== 2. 手动加载 PBR 贴图应用到 FBX mesh ==========
	var pbr_prefix: String = entry.get("pbr_prefix", "")
	if pbr_prefix != "":
		_apply_pbr_textures(_body_inst, pbr_prefix)

	# ========== 3. AnimationPlayer：深拷贝断共享 → idle 重命名 → 剥 Root Motion ==========
	_anim_player = _find_animation_player(_body_inst)
	if _anim_player != null:
		# Godot 4.3+ AnimationMixer 统一后属性名为 playback_process_mode
		_anim_player.playback_process_mode = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		_deep_copy_anim_library(_anim_player)
		_rename_default_anim_to(_anim_player, "idle")
		if _anim_player.has_animation("idle"):
			var idle_anim: Animation = _anim_player.get_animation("idle")
			if idle_anim != null:
				_strip_root_motion(idle_anim)
				idle_anim.loop_mode = Animation.LOOP_LINEAR
		# 合并共享 run/throw/catch
		_merge_shared_animations(_anim_player, slot)
		if not _anim_player.animation_finished.is_connected(_on_action_finished):
			_anim_player.animation_finished.connect(_on_action_finished)
	else:
		push_warning("[PlayerProxy3D] %s 未找到 AnimationPlayer（仅静态模型）" % char_id)

	# ========== 4. 根骨骼节点（运行时强制重置位置，杀 Root Motion 漂移） ==========
	_root_bone_node = _find_root_bone_node(slot)

	# ========== 5. 队伍色脚下环 + 投球手挂接点 ==========
	_build_ring_only()
	var hand := Node3D.new()
	hand.name = "HandProxy"
	hand.position = Vector3(8.0, 30.0, 0.0)
	add_child(hand)
	_hand_proxy = hand

	# ========== 6. 剔除模型内嵌光源（部分 Idle.fbx 带制作残留灯节点）==========
	_strip_embedded_lights(self)

	# 延迟播放 idle（等进树）
	if _anim_player != null and _anim_player.has_animation("idle"):
		call_deferred("_play_initial_idle")

	# E10b 单位归一化：各批次 FBX 导出单位差 100 倍（实测 0.011~1.125），进树后实测
	# 世界身高补偿到标准 49.86（铁律 ModelSlot=70 不动，补偿加在 FBX 根节点单位上）
	_normalize_unit_deferred()

	print("[PlayerProxy3D] ✅ %s 构建 mesh=%s anims=%s" % [char_id, _mesh_ok, get_anim_names()])


## 剔除模型 FBX 内嵌光源（部分 Idle.fbx 带制作残留灯节点，球员跳跃升空后灯跟着升空，
## 在地面打出大片异常光斑——2026-09-12 主人实测"持球跳跃变光源"根因）
func _strip_embedded_lights(root: Node) -> void:
	for light in root.find_children("*", "Light3D", true, false):
		(light as Light3D).visible = false
		(light as Node).queue_free()


func _build_ring_only() -> void:
	var ring := MeshInstance3D.new()
	ring.name = "TeamRing"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 25.0
	cyl.bottom_radius = 25.0
	cyl.height = 3.0
	ring.mesh = cyl
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = team_color
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.emission_enabled = true
	ring_mat.emission = team_color
	ring_mat.emission_energy_multiplier = 0.3
	ring.material_override = ring_mat
	ring.position = Vector3(0.0, 2.0, 0.0)
	add_child(ring)


func _play_initial_idle() -> void:
	if _anim_player != null and is_instance_valid(_anim_player):
		if _anim_player.has_animation("idle"):
			_anim_player.play("idle")
			_cur_anim = "idle"
		else:
			# 兜底：播放第一个可用动画
			for lib_key in _anim_player.get_animation_library_list():
				var lib = _anim_player.get_animation_library(lib_key)
				if lib != null and lib.get_animation_list().size() > 0:
					_anim_player.play(lib.get_animation_list()[0])
					_cur_anim = lib.get_animation_list()[0]
					break

## ==================== 对外 API ====================

## 2D 数据 → 3D 代理同步（每帧由 bridge/测试驱动；坐标 1:1 零换算）
## height_z：M3 跳跃高度（像素，2D 层权威，叠加到模型 y；默认 0 兼容旧调用）
func sync_from_2d(pos2d: Vector2, vel2d: Vector2, facing2d: Vector2, height_z: float = 0.0) -> void:
	var p3d: Vector3 = CFG.game2d_to_3d(pos2d)
	p3d.y += height_z
	global_position = p3d
	rotation.y = CFG.facing_to_rotation_y(facing2d)
	if _action_lock:
		return
	var desired := "run" if vel2d.length() > 10.0 else "idle"
	if desired != _cur_anim:
		play_anim(desired)

## 播放一次性动作（throw/catch），播完自动回 idle/run
func play_action(action: String) -> void:
	if _anim_player == null or not _anim_player.has_animation(action):
		return
	_anim_player.play(action)
	_cur_anim = action
	_action_lock = true

## 手部挂接点（持球时球代理贴这里）
func get_hand_proxy() -> Node3D:
	return _hand_proxy

func get_anim_player() -> AnimationPlayer:
	return _anim_player

## E10b 单位归一化：实测 _body_inst 世界包围盒高，缩放到标准 49.86
## （各批次 FBX 导出单位不一：0.011~1.125；GLB 模式跳过——GLB 单位正确）
func _normalize_unit_deferred() -> void:
	if not _mesh_ok or _body_inst == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if _body_inst == null or not is_instance_valid(_body_inst):
		return
	var height := 0.0
	for mi in _body_inst.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		var ab: AABB = m3.global_transform * m3.mesh.get_aabb()
		height = maxf(height, ab.size.y)
	if height < 0.001 or height > 500.0:
		return  # 异常高度不补偿（防除零/已正确则跳过区间外）
	var k: float = 49.86 / height
	if absf(k - 1.0) < 0.05:
		return  # 已在 ±5% 内视为正确
	_body_inst.scale *= k
	print("[PlayerProxy3D] 单位归一化 %s：世界高%.2f → ×%.3f = 49.86" % [char_id, height, k])


func get_anim_names() -> Array:
	if _anim_player == null:
		return []
	var names: Array = []
	for lib_key in _anim_player.get_animation_library_list():
		var lib = _anim_player.get_animation_library(lib_key)
		if lib != null:
			names.append_array(lib.get_animation_list())
	return names

func is_mesh_ok() -> bool:
	return _mesh_ok

func is_anim_playing() -> bool:
	return _anim_player != null and _anim_player.is_playing()

func get_current_anim() -> String:
	return _cur_anim

## 击倒视觉（半透明——transparency 是 GeometryInstance3D 属性，实例缓存防每帧遍历）
func set_defeated_visual(defeated: bool) -> void:
	if _mesh_instances.is_empty():
		return
	var t := 0.65 if defeated else 0.0
	for mi in _mesh_instances:
		if is_instance_valid(mi):
			mi.transparency = t

## ==================== 每帧：杀 Root Motion 漂移 ====================

func _physics_process(_delta: float) -> void:
	_force_reset_root_bones()

## 只重置模型骨架子树的位置（不动 ring/hand 挂点——对 player_3d_test 的改进收窄）
func _force_reset_root_bones() -> void:
	if _root_bone_node != null and is_instance_valid(_root_bone_node):
		_root_bone_node.position = Vector3.ZERO
	if _body_inst != null and is_instance_valid(_body_inst):
		_reset_positions_in(_body_inst)

func _reset_positions_in(node: Node) -> void:
	if node is Node3D:
		var n3d := node as Node3D
		if not n3d.position.is_equal_approx(Vector3.ZERO):
			n3d.position = Vector3.ZERO
	for child in node.get_children():
		_reset_positions_in(child)

## ==================== 移植自 player_3d_test 的静态辅助 ====================

func _on_action_finished(_anim_name: StringName) -> void:
	_action_lock = false
	_cur_anim = ""

static func play_anim_on(ap: AnimationPlayer, anim_name: String) -> bool:
	if ap != null and ap.has_animation(anim_name):
		ap.play(anim_name)
		return true
	return false

func play_anim(anim_name: String) -> void:
	if play_anim_on(_anim_player, anim_name):
		_cur_anim = anim_name

## 隐藏 Mixamo 残留参考球
static func _hide_mixamo_helpers(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if "Icosphere" in node.name or "Primitive" in node.name:
			node.visible = false

## 手动加载 PBR 贴图（prefix 为 playerN_base_texture_pbr_20250901）
## 并应用到 FBX 所有 mesh surface（metallic=0 / roughness=0.6 Q 版参数）
static func _apply_pbr_textures(fbx_root: Node, pbr_prefix: String) -> void:
	if fbx_root == null:
		return
	var albedo_tex: Texture2D = load(pbr_prefix + ".png")
	var normal_tex: Texture2D = load(pbr_prefix + "_normal.png")
	var mr_tex: Texture2D = load(pbr_prefix + "_metallic-texture_pbr_20250901_roughness.png")
	if albedo_tex == null and normal_tex == null and mr_tex == null:
		push_warning("[PlayerProxy3D] PBR 贴图全部缺失: %s" % pbr_prefix)
		return
	var applied := 0
	for mi in fbx_root.find_children("*", "MeshInstance3D", true, false):
		if not (mi is MeshInstance3D):
			continue
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst.mesh == null:
			continue
		for surf_idx in range(mesh_inst.mesh.get_surface_count()):
			var mat := StandardMaterial3D.new()
			if albedo_tex != null:
				mat.albedo_texture = albedo_tex
			if normal_tex != null:
				mat.normal_enabled = true
				mat.normal_map = normal_tex
			if mr_tex != null:
				mat.metallic_texture = mr_tex
				mat.roughness_texture = mr_tex
			mat.metallic = 0.0
			mat.roughness = 0.6
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			mesh_inst.set_surface_override_material(surf_idx, mat)
			applied += 1
	print("[PlayerProxy3D] PBR 应用 %d surfaces (albedo=%s)" % [applied, albedo_tex != null])

## 深拷贝动画库断共享（instantiate 后 AnimationLibrary 仍是共享资源）
static func _deep_copy_anim_library(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	for lib_key in ap.get_animation_library_list():
		var old_lib: AnimationLibrary = ap.get_animation_library(lib_key)
		var new_lib := AnimationLibrary.new()
		for anim_name in old_lib.get_animation_list():
			var old_anim: Animation = old_lib.get_animation(anim_name)
			new_lib.add_animation(anim_name, old_anim.duplicate(true))
		ap.remove_animation_library(lib_key)
		ap.add_animation_library(lib_key, new_lib)

## 默认库第一个动画重命名为 new_name（duplicate 断共享）
static func _rename_default_anim_to(ap: AnimationPlayer, new_name: String) -> void:
	if ap == null or not ap.has_animation_library(""):
		return
	var default_lib := ap.get_animation_library("")
	var anim_list := default_lib.get_animation_list()
	if anim_list.is_empty():
		return
	var old_name: String = anim_list[0]
	if old_name == new_name:
		return
	var anim := default_lib.get_animation(old_name)
	default_lib.add_animation(new_name, anim.duplicate(true))
	if default_lib.has_animation(old_name):
		default_lib.remove_animation(old_name)

## 合并共享 run/throw/catch（Mixamo 同骨架，duplicate+剥 Root Motion）
func _merge_shared_animations(ap: AnimationPlayer, slot: Node3D) -> void:
	if ap == null or slot == null:
		return
	if not ap.has_animation_library(""):
		ap.add_animation_library("", AnimationLibrary.new())
	var default_lib := ap.get_animation_library("")
	for semantic_name in CFG.SHARED_ANIMS:
		if default_lib.has_animation(semantic_name):
			continue
		var fbx_scene := _get_shared_anim_scene(CFG.SHARED_ANIMS[semantic_name])
		if fbx_scene == null:
			push_warning("[PlayerProxy3D] %s 无法加载共享动画: %s" % [char_id, CFG.SHARED_ANIMS[semantic_name]])
			continue
		var fbx_inst: Node = fbx_scene.instantiate()
		if fbx_inst == null:
			continue
		# 临时挂树才能读 AnimationPlayer
		slot.add_child(fbx_inst)
		var tmp_ap := _find_animation_player(fbx_inst)
		if tmp_ap != null:
			for lib_key in tmp_ap.get_animation_library_list():
				var src_lib := tmp_ap.get_animation_library(lib_key)
				for src_anim_name in src_lib.get_animation_list():
					var anim: Animation = src_lib.get_animation(src_anim_name)
					if anim == null:
						continue
					var anim_copy: Animation = anim.duplicate(true)
					_strip_root_motion(anim_copy)
					default_lib.add_animation(semantic_name, anim_copy)
					var merged: Animation = default_lib.get_animation(semantic_name)
					if merged != null:
						merged.loop_mode = Animation.LOOP_NONE if semantic_name in ["throw", "catch"] else Animation.LOOP_LINEAR
					break
				break
		fbx_inst.queue_free()

static func _get_shared_anim_scene(path: String) -> PackedScene:
	if _shared_anim_scenes.has(path):
		return _shared_anim_scenes[path]
	var scene := load(path) as PackedScene
	_shared_anim_scenes[path] = scene
	return scene

## 彻底剥离 Root Motion（2026-09-10 v2）：
## ① 名字含 root 的位置轨道 → 整条删除
## ② 其余位置轨道首尾净位移 > 阈值（Mixamo 命名是 mixamorig_Hips，v1 只匹配 root 漏掉，
##    导致 run 循环每圈前飘 ~54px 再瞬跳回起点）→ 烘焙为单帧固定轨道（保高度、去位移）
const ROOT_MOTION_BAKE_THRESHOLD := 0.05

static func _strip_root_motion(anim: Animation) -> void:
	if anim == null:
		return
	var track_count: int = anim.get_track_count()
	var remove_idxs: Array[int] = []            # 整条删
	var bake_paths: Array[String] = []          # 烘焙：记录路径+首帧位置
	var bake_positions: Array[Vector3] = []
	for i in range(track_count):
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path_str: String = str(anim.track_get_path(i))
		var path_lower: String = path_str.to_lower()
		var is_root_track := false
		if ":root:" in path_lower or path_lower.ends_with(":root"):
			is_root_track = true
		elif "rootbone" in path_lower or ":root_" in path_lower or "_root:" in path_lower:
			is_root_track = true
		elif path_lower.begins_with(":root") or path_lower.begins_with("root"):
			is_root_track = true
		if is_root_track:
			remove_idxs.append(i)
			continue
		# Mixamo 位移检测：首尾插值位置差 > 阈值 → 前向位移轨道
		if anim.track_get_key_count(i) >= 2:
			var p0: Vector3 = anim.position_track_interpolate(i, 0.0)
			var p1: Vector3 = anim.position_track_interpolate(i, anim.length)
			if p0.distance_to(p1) > ROOT_MOTION_BAKE_THRESHOLD:
				bake_paths.append(path_str)
				bake_positions.append(p0)
				remove_idxs.append(i)
	if remove_idxs.is_empty():
		return
	remove_idxs.sort()
	remove_idxs.reverse()
	for idx in remove_idxs:
		anim.remove_track(idx)
	# 重建烘焙轨道：单关键帧固定在首帧位置（保留 Hips 高度，无前向位移）
	for k in range(bake_paths.size()):
		var new_idx := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(new_idx, bake_paths[k])
		anim.position_track_insert_key(new_idx, 0.0, bake_positions[k])
	if bake_paths.size() > 0:
		print("[PlayerProxy3D] Root Motion 烘焙 %d 条位移轨道（阈值 %.2f）" % [bake_paths.size(), ROOT_MOTION_BAKE_THRESHOLD])

## 递归查找 AnimationPlayer
static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

## 查找根骨骼节点（优先 Skeleton3D）
static func _find_root_bone_node(root_node: Node) -> Node3D:
	if root_node == null:
		return null
	var skeletons := root_node.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() > 0:
		return skeletons[0] as Node3D
	for bone_name in ["root", "Root", "RootBone", "root_bone"]:
		var found := root_node.find_children(bone_name, "Node3D", true, false)
		if found.size() > 0:
			return found[0] as Node3D
	var first_n3d := root_node.find_children("*", "Node3D", true, false)
	if first_n3d.size() > 0:
		return first_n3d[0] as Node3D
	return null
