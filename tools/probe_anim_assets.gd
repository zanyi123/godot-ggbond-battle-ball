## 动作资产可用性探针：批量加载 FBX，验证骨架兼容性与动画真实存在
## 用法: godot --headless --path . -s res://tools/probe_anim_assets.gd
## 输出: 每文件一行 = 文件 | 骨数+规格 + Mixamo兼容 | 动画名:时长/轨道数
## ⚠ 骨名判定用 contains（Mixamo 经 Godot 导入带 mixamorig_ 前缀，裸名 "Hips" 找不到——2026-09-19 踩坑）
## 规格分档: 28~33骨=无指版 / 60+骨=全指版（跨规格播动画兼容但 65→33 有轨道丢弃警告）
extends SceneTree

const KEY_BONE_SUBSTRINGS := ["Hips", "Spine", "LeftHand", "RightHand", "Head"]

func _init() -> void:
	var files: Array[String] = [
		"res://assets/characters/avatars/Idle.fbx",
		"res://assets/characters/avatars/Jog_Forward.fbx",
		"res://assets/characters/avatars/Goalie_Throw.fbx",
		"res://assets/characters/avatars/Goalkeeper_Catch.fbx",
	]
	var actions_dir := "res://建模素材库/3D模型素材/actions"
	var dir := DirAccess.open(actions_dir)
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".fbx"):
				files.append(actions_dir + "/" + f)
			f = dir.get_next()
	else:
		print("WARN actions dir not accessible: ", actions_dir)

	print("=== PROBE START ", files.size(), " files ===")
	for path in files:
		var ps: PackedScene = load(path)
		if ps == null:
			print(path, " => LOAD_FAIL")
			continue
		var root: Node = ps.instantiate()
		var skel: Skeleton3D = _find_skel(root)
		var ap: AnimationPlayer = _find_ap(root)
		var info := path.get_file()
		if skel:
			var bone_names: Array[String] = []
			for i in range(skel.get_bone_count()):
				bone_names.append(skel.get_bone_name(i))
			var missing: Array[String] = []
			for kb in KEY_BONE_SUBSTRINGS:
				var found := false
				for bn in bone_names:
					if bn.contains(kb):
						found = true
						break
				if not found:
					missing.append(kb)
			var rig := "FULL_FINGER" if skel.get_bone_count() >= 60 else "NO_FINGER"
			info += " | bones=" + str(skel.get_bone_count()) + " " + rig
			info += (" | MIXAMO_COMPAT=YES" if missing.is_empty() else " | MIXAMO_COMPAT=NO missing:" + ",".join(missing))
		else:
			info += " | NO_SKELETON"
		if ap:
			var anims := ap.get_animation_list()
			var parts: Array[String] = []
			for a in anims:
				var anim: Animation = ap.get_animation(a)
				parts.append(a + ":" + str(snappedf(anim.length, 0.1)) + "s/trk" + str(anim.get_track_count()))
			info += " | anims=" + str(anims.size()) + " [" + ", ".join(parts) + "]"
		else:
			info += " | NO_ANIMATION"
		print(info)
		root.queue_free()
	print("=== PROBE END ===")
	quit(0)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null
