extends SceneTree

## UiIcon 自检（2026-10-30）
## 验证：20 支 UI 图标能否通过 UiIcon 单例全部加载；同时打印素材实际尺寸。
## 运行：godot --headless --path <项目> --script tools/test_ui_icon.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("\n========== UiIcon 自检（20 支 UI 图标）==========\n")
	var r: Dictionary = UiIcon.self_check()
	print("  总计: %d   可加载: %d   缺失: %d" % [r["total"], r["found"], r["missing"].size()])
	if r["missing"].size() > 0:
		print("  缺失清单: ", r["missing"])

	print("\n  ── 逐项 ──")
	var ok_n := 0
	var fail_n := 0
	for name in UiIcon.list_available():
		var tex: Texture2D = UiIcon.get_tex(name)
		if tex != null:
			ok_n += 1
			print("    [OK]   %-16s %dx%d" % [name, tex.get_width(), tex.get_height()])
		else:
			fail_n += 1
			print("    [MISS] %s" % name)

	print("\n  ── 便捷构造 ──")
	var tr: TextureRect = UiIcon.make_icon_rect("el_jingang", 24)
	print("    make_icon_rect: texture=%s  min_size=%s" % [str(tr.texture != null), str(tr.custom_minimum_size)])
	var hb: Node = UiIcon.make_icon_label("cur_yuanshi", "源石", 20)
	print("    make_icon_label: children=%d" % hb.get_child_count())

	print("\n  ── 元素旧key映射（v5 §7.4）──")
	for ek in ["金刚", "梦幻", "草木", "大地", "冰雪", "雷火"]:
		var t: Texture2D = UiIcon.element_tex(ek)
		print("    %s → %s : %s" % [ek, UiIcon.ELEMENT_ICON[ek], "OK" if t != null else "MISS"])

	print("\n========== 结果 ==========")
	if fail_n == 0:
		print("  全绿：%d/%d PASS" % [ok_n, ok_n + fail_n])
	else:
		print("  失败：%d 支缺失" % fail_n)
	print("")
	quit(0 if fail_n == 0 else 1)
