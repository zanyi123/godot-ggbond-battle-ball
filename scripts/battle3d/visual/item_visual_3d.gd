extends Node3D
class_name ItemVisual3D
## 24号工单 B3 增补：芬尼守白球三道具（平底锅/药水/烟花）手持模型
## 模型来源（主人令 2026-10-15"必须有道具雏形，宁网上下载不自己瞎拼"）——全 CC0，引进三查记录见
##   assets/game_models/items_handheld/LICENSE_CREDITS.md：
##   锅=Kenney Food Kit frying_pan.glb / 药水=OGA Potion Bottle（Red 色 FBX+贴图代码挂）/ 烟花=Kenney Space Kit rocket 五部件同位叠加
## 挂接=手持：由 bridge 挂到获得者球员 3D 代理的手位（HAND_LOCAL_POS），随球员移动/转向；无代理时退回地面点位同步
## 数据源协议（显示层零判定）：ITEM_ACQUIRED 挂载 / ITEM_USED 即时消耗型撤除 / 锅=装备态随 defend_intercept_ready 复位撤除
## 兜底：真实模型加载失败→降级几何拼形（fail-closed 可见）

const PAN_ID := "fenny_pan"
const POTION_ID := "fenny_potion"
const FIREWORK_ID := "fenny_firework"
const ITEM_IDS: Array[String] = [PAN_ID, POTION_ID, FIREWORK_ID]

const MODEL_DIR := "res://assets/game_models/items_handheld/"
## 真实模型路径表（烟花=五部件同原点叠加，探针实测部件带 (2,0,1.5) 偏移→挂载后整体归零）
const MODEL_PATHS := {
	PAN_ID: ["frying_pan.glb"],
	POTION_ID: ["potion_red.fbx"],
	FIREWORK_ID: ["firework/rocket_baseA.glb", "firework/rocket_finsA.glb", "firework/rocket_fuelA.glb", "firework/rocket_sidesA.glb", "firework/rocket_topA.glb"],
}
const ROCKET_CENTER := Vector3(2.0, 0.8, 1.5)   # 探针实测五部件叠加 bbox 中心（归零用）
## 手持目标尺寸（GD 像素 1:1；锅=全长 / 药=全高 / 烟花=最长边），显示层实例缩放（模型文件不动）
## 卡通可读档：真实游戏机位（ANGLED 距离 1200）下道具需大于写实比例才可辨
const TARGET_MAX_SIZE := {PAN_ID: 26.0, POTION_ID: 22.0, FIREWORK_ID: 30.0}
const HAND_LOCAL_POS := Vector3(20.0, 32.0, -16.0)   # 球员 3D 代理本地手位（右手前侧，-Z=默认相机可视侧）

# 几何兜底配色（真实模型加载失败时可见可辨）
const PAN_BODY_COLOR := Color(0.3, 0.32, 0.38)
const PAN_HANDLE_COLOR := Color(0.5, 0.32, 0.18)
const POTION_LIQUID_COLOR := Color(0.9, 0.25, 0.3, 0.92)
const FW_BODY_COLOR := Color(0.85, 0.2, 0.2)
const FW_CONE_COLOR := Color(1.0, 0.8, 0.2)

const TAG_CHARS := {PAN_ID: "锅", POTION_ID: "药", FIREWORK_ID: "烟花"}

var item_id: String = ""
var held: bool = false             # bridge 挂球员代理手持=true（不再每帧地面同步）
var _holder: Node3D = null
var _used_fallback: bool = false


func setup(p_item_id: String) -> void:
	item_id = p_item_id
	if not ITEM_IDS.has(item_id):
		push_warning("[ItemVisual3D] 未知道具 fail-closed：" + item_id)
		return
	_holder = Node3D.new()
	_holder.name = "HandItem"
	add_child(_holder)
	if not _build_real_model(item_id):
		_used_fallback = true
		_build_fallback(item_id)
	_add_tag(str(TAG_CHARS.get(item_id, "?")))


## 真实模型加载（全路径加载失败才返回 false→几何兜底）
func _build_real_model(p_id: String) -> bool:
	var paths: Array = MODEL_PATHS.get(p_id, [])
	if paths.is_empty():
		return false
	var loaded_nodes: Array = []
	for rel in paths:
		var ps: PackedScene = load(MODEL_DIR + rel)
		if ps == null:
			continue
		var inst: Node3D = ps.instantiate()
		_holder.add_child(inst)
		loaded_nodes.append(inst)
	if loaded_nodes.is_empty():
		return false
	# 烟花五部件整体归零（探针实测 bbox 中心偏移）+ 上色（Space Kit GLTF 无内嵌色，代码赋）
	if p_id == FIREWORK_ID:
		for inst in loaded_nodes:
			var n3 := inst as Node3D
			n3.position -= ROCKET_CENTER
			var nm: String = str(n3.name)
			var col := Color(0.85, 0.2, 0.2)   # 筒身红
			if nm.contains("top"):
				col = Color(1.0, 0.8, 0.2)     # 锥头金
			elif nm.contains("fins"):
				col = Color(0.3, 0.4, 0.85)    # 尾翼蓝
			_override_flat(n3, col)
	# 尺寸归一（探针实测 AABB 最长边 → 目标像素）
	var ab := _merged_aabb(self)
	var max_dim: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	if max_dim > 0.0001:
		var s: float = float(TARGET_MAX_SIZE.get(p_id, 18.0)) / max_dim
		_holder.scale = Vector3.ONE * s
	# 药水贴图挂接（FBX 外置贴图，Unity 系命名，代码挂到材质槽）
	if p_id == POTION_ID:
		_apply_potion_textures()
	return true


## 递归给子 MeshInstance 全 surface 挂纯色材质（unshaded 醒目）
func _override_flat(from: Node, col: Color) -> void:
	var stack: Array = [from]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh := mi.mesh
			if mesh != null:
				for s in range(mesh.get_surface_count()):
					var m := StandardMaterial3D.new()
					m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					m.albedo_color = col
					mi.set_surface_override_material(s, m)
		for c in n.get_children():
			stack.append(c)


## 递归合并 AABB（全局变换）
func _merged_aabb(from: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [from]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var ab: AABB = mi.global_transform * mi.get_aabb()
			if first:
				result = ab
				first = false
			else:
				result = result.merge(ab)
		for c in n.get_children():
			stack.append(c)
	return result


## 药水贴图（Red：albedo+emission；Unity 系打包贴图全 UV 包裹，逐 surface 挂）
func _apply_potion_textures() -> void:
	var albedo: Texture2D = load(MODEL_DIR + "potion_tex/potion_red_albedo.png")
	var emission: Texture2D = load(MODEL_DIR + "potion_tex/potion_red_emission.png")
	if albedo == null:
		return
	var stack: Array = [_holder]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh := mi.mesh
			if mesh == null:
				continue
			for s in range(mesh.get_surface_count()):
				var mat := StandardMaterial3D.new()
				mat.albedo_texture = albedo
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				if emission != null:
					mat.emission_enabled = true
					mat.emission_texture = emission
					mat.emission_energy_multiplier = 1.5
				mi.set_surface_override_material(s, mat)
		for c in n.get_children():
			stack.append(c)


## 几何兜底（真实模型不可用时保可辨）
func _build_fallback(p_id: String) -> void:
	match p_id:
		PAN_ID:
			_fb_cyl(10.0, 9.0, 4.0, Vector3(0.0, 2.0, 0.0), PAN_BODY_COLOR, "PanBody")
			_fb_box(Vector3(14.0, 2.5, 3.0), Vector3(16.0, 3.0, 0.0), PAN_HANDLE_COLOR, "Handle")
		POTION_ID:
			_fb_cyl(8.0, 8.0, 12.0, Vector3(0.0, 6.0, 0.0), Color(0.7, 0.85, 1.0, 0.55), "Bottle")
			_fb_cyl(6.5, 6.5, 9.0, Vector3(0.0, 4.5, 0.0), POTION_LIQUID_COLOR, "Liquid")
		FIREWORK_ID:
			_fb_box(Vector3(1.6, 5.0, 1.6), Vector3(0.0, 2.5, 0.0), Color(0.55, 0.4, 0.25), "Stick")
			_fb_cyl(5.0, 5.0, 9.0, Vector3(0.0, 9.5, 0.0), FW_BODY_COLOR, "FwBody")
			_fb_cyl(0.0, 5.0, 5.0, Vector3(0.0, 16.5, 0.0), FW_CONE_COLOR, "FwCone")


func _fb_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	return m


func _fb_box(size: Vector3, pos: Vector3, col: Color, box_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _fb_mat(col)
	_holder.add_child(mi)


func _fb_cyl(top_r: float, bottom_r: float, h: float, pos: Vector3, col: Color, cyl_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = cyl_name
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = h
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _fb_mat(col)
	_holder.add_child(mi)


func _add_tag(char_txt: String) -> void:
	var tag := Label3D.new()
	tag.name = "ItemTag"
	tag.text = char_txt
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.3
	tag.font_size = 30
	tag.outline_size = 8
	tag.modulate = Color(1.0, 0.95, 0.6)
	tag.position = Vector3(0.0, 30.0, 0.0)
	add_child(tag)


## bridge 兜底分支每帧调用（手持挂球员代理子节点时自动跟随，不走此口）
func sync_from_player(pos: Vector2) -> void:
	global_position = Vector3(pos.x, 0.0, pos.y)
