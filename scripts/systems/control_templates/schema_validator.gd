extends RefCounted
## 工单38 操控出口：模板 schema 校验器（S1）——fail-closed
## 白名单（ctl_ 三维度键空间）/黑名单（tags_registry params 动态生成）/类型校验/三级回落/M1 兜底/版本迁移框架/引用扫描
## 红线：效果数值轴排除（黑名单键出现=报错）；任何情况不崩游戏（坏模板=回落默认+报错登记）。

const REGISTRY_PATH := "res://data/spirits/tags_registry.json"
const SKILLS_PATH := "res://data/spirits/skills.json"
const GOLD_DIR := "res://data/control_templates/"
const DRAFT_DIR := "user://control_drafts/"
const SCHEMA_VERSION := 1

## 12 既有（ssm OPERATORS ssm:40-43）+6 新（37号抽象参考）= enum(18)
const OPERATORS_18 := [
	"OP_AUTO", "OP_AIM", "OP_POINT", "OP_MARK", "OP_STEER", "OP_MIDFLY",
	"OP_TOGGLE", "OP_KEY_JUMP", "OP_PLACE", "OP_SUMMON", "OP_FP", "OP_COMBO",
	"OP_SELECT", "OP_ORIENT", "OP_TRAIL", "OP_GUIDE", "OP_TRANSFORM", "OP_HOLD",
]

## schema 白名单：键 → {type, default, values?}（A8：每键必有默认值；缺键=用默认不报错）
## ctl_input_hover_snap / ctl_input_lock_snap 为 38号§H 表补键名（34号验收实测 120/150）
const SCHEMAS := {
	"ctl_input_operator": {"type": "enum", "default": "OP_AUTO", "values": OPERATORS_18},
	"ctl_input_view_mode": {"type": "enum", "default": "camera", "values": ["camera", "fp_cross"]},
	"ctl_input_hold_key": {"type": "key", "default": "H"},
	"ctl_input_preview_solo": {"type": "bool", "default": true},
	"ctl_input_hover_snap": {"type": "float", "default": 120.0},
	"ctl_input_lock_snap": {"type": "float", "default": 150.0},
	"ctl_visual_model_path": {"type": "res_path", "default": ""},
	"ctl_visual_scale": {"type": "float", "default": 1.0},
	"ctl_visual_rot": {"type": "float", "default": 0.0},
	"ctl_visual_offset": {"type": "vec2", "default": {"x": 0.0, "y": 0.0}},
	"ctl_visual_color": {"type": "color", "default": "#50D4FFE0"},
	"ctl_visual_alpha": {"type": "float", "default": 0.45},
	"ctl_visual_mark_symbol": {"type": "enum", "default": "star", "values": ["pan", "potion", "firework", "star"]},
	"ctl_visual_hover_y": {"type": "float", "default": 75.0},
	"ctl_time_preview_show": {"type": "float", "default": 1.0},
	"ctl_time_spawn_delay": {"type": "float", "default": 0.0},
	"ctl_time_enter_fx": {"type": "enum", "default": "instant", "values": ["instant", "fade", "scale_in"]},
	"ctl_time_hold_timer": {"type": "float", "default": 5.0},
}

static var _blacklist_cache: Dictionary = {}


## ===== 黑名单（A6 动态生成：registry 增参自动跟随） =====
static func blacklist() -> Dictionary:
	if not _blacklist_cache.is_empty():
		return _blacklist_cache
	_blacklist_cache = {}
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if f == null:
		return _blacklist_cache
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null or not (parsed is Dictionary):
		return _blacklist_cache
	for t in parsed.get("tags", []):
		if not (t is Dictionary):
			continue
		var pp: Variant = t.get("params")
		if pp is Array:   # registry 实际结构：params=["value", ...]（键名清单）
			for pk in pp:
				_blacklist_cache[str(pk)] = true
		elif pp is Dictionary:
			for pk in pp:
				_blacklist_cache[str(pk)] = true
	return _blacklist_cache


## ===== 类型校验（A7 类型表）——返回错误串，空串=过 =====
static func _check_type(key: String, value: Variant) -> String:
	var schema: Dictionary = SCHEMAS.get(key, {})
	match str(schema.get("type", "")):
		"float":
			if not (value is float or value is int):
				return "%s: 需 float，实得 %s" % [key, type_string(typeof(value))]
		"int":
			if not (value is int):
				return "%s: 需 int" % key
		"bool":
			if not (value is bool):
				return "%s: 需 bool" % key
		"enum":
			if not (value in schema.get("values", [])):
				return "%s: 非法枚举值 %s（允许 %s）" % [key, str(value), str(schema.get("values", []))]
		"res_path":
			if str(value) == "":
				return ""   # 空=M1 兜底 procedural 占位（38号§2.1 明确语义）
			if not str(value).begins_with("res://"):
				return "%s: res_path 需 res:// 开头" % key
			if not FileAccess.file_exists(ProjectSettings.globalize_path(str(value))):
				return "%s: 路径不存在 %s（M1 兜底）" % [key, str(value)]
		"key":
			if str(value).is_empty():
				return "%s: key 不可为空" % key
		"color":
			var cs := str(value)
			if not (cs.begins_with("#") and cs.length() in [7, 9]):
				return "%s: Color 需 #RRGGBB(AA) 格式" % key
		"vec2":
			if not (value is Dictionary and value.has("x") and value.has("y")):
				return "%s: vec2 需 {x,y}" % key
	return ""


## ===== 校验+解析（fail-closed 四查）——返回 {ok, errors, resolved, model_ok} =====
## resolved=全键补默认的合法参数集；未知键/黑名单键/类型错=报错（该键用默认，不崩）
static func validate(params: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var resolved: Dictionary = {}
	var bl := blacklist()
	for key in params:
		if str(key).begins_with("_"):
			continue   # 内部标记键（_model_ok 等）不入校验
		if not str(key).begins_with("ctl_"):
			errors.append("非 ctl_ 键混入: %s（白名单制）" % str(key))
			continue
		if bl.has(str(key)):
			errors.append("黑名单键（效果轴参数）: %s——操控模板禁用" % str(key))
			continue
		if not SCHEMAS.has(key):
			errors.append("未知 ctl_ 键（不在 schema 白名单）: %s" % str(key))
			continue
		var err := _check_type(str(key), params[key])
		if err != "":
			errors.append(err)
		else:
			resolved[key] = params[key]
	# 缺键补默认
	for key in SCHEMAS:
		if not resolved.has(key):
			resolved[key] = SCHEMAS[key].get("default")
	# M1 兜底标记（25号闸门：模型缺失/空路径=procedural 占位可测）
	var mp := str(resolved.get("ctl_visual_model_path", ""))
	var model_ok := mp != "" and FileAccess.file_exists(ProjectSettings.globalize_path(mp))
	resolved["_model_ok"] = model_ok
	return {"ok": errors.is_empty(), "errors": errors, "resolved": resolved, "model_ok": model_ok}


## ===== 模板文件读取（含版本迁移框架 A10）→ 校验 → 三级回落由调用方组合 =====
static func read_template_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null or not (parsed is Dictionary):
		return {}
	var tpl: Dictionary = parsed
	var migrated := _migrate(tpl)
	return migrated


## 版本迁移：v0/无 version 旧模板→补 version；后续 schema 升级在此追加迁移步骤
static func _migrate(tpl: Dictionary) -> Dictionary:
	var out := tpl.duplicate(true)
	if not out.has("version"):
		out["version"] = 1
	return out


## 三级回落解析：模板 params → gold_<operator> → 内置默认（A9/D2——任何情况不崩）
## 最后回落=逐键清洗（保留原 params 中单键合法项，剔黑名单/未知/类型错），合法身份键不丢
static func resolve_params(params: Dictionary, operator: String) -> Dictionary:
	var r := validate(params)
	if r.ok:
		return r.resolved
	var gold := _gold_params(operator)
	var merged := params.duplicate(true)
	for key in gold:
		if not merged.has(key):
			merged[key] = gold[key]
	var r2 := validate(merged)
	if r2.ok:
		return r2.resolved
	var cleaned: Dictionary = {}
	for key in params:
		if SCHEMAS.has(str(key)) and _check_type(str(key), params[key]) == "":
			cleaned[key] = params[key]
	var r3 := validate(cleaned)
	r3["errors"] = r.errors + ["模板与 gold 均未整体过校验——已逐键清洗回落"]
	return r3.resolved


static func _gold_params(operator: String) -> Dictionary:
	var tpl := read_template_file(GOLD_DIR + "gold_%s.json" % operator.to_lower())
	if tpl.is_empty():
		return {}
	return tpl.get("params", {})


## ===== 引用扫描（F1：被 ≥1 技能 control_template 引用=实战模板） =====
static func referenced_templates(skills_data: Dictionary = {}) -> Array:
	var out: Array[String] = []
	var data := skills_data
	if data.is_empty():
		var f := FileAccess.open(SKILLS_PATH, FileAccess.READ)
		if f == null:
			return out
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed == null or not (parsed is Dictionary):
			return out
		data = parsed
	for sk in data.get("skills", []):
		if sk is Dictionary and sk.get("control_template", "") != "":
			out.append(str(sk["control_template"]))
	return out


## ===== 存储（S2：草稿区/实战库） =====
## sim 规矩③④：模板集版本清单+引用分级（被引用=实战模板触发门禁；无引用=演示模板不触发）
static func template_version_report() -> Dictionary:
	var referenced := referenced_templates()
	var report := {"templates": [], "referenced": referenced, "demo": [], "total": 0}
	var dir := DirAccess.open(GOLD_DIR)
	if dir == null:
		return report
	for f in dir.get_files():
		if not str(f).ends_with(".json"):
			continue
		var tpl := read_template_file(GOLD_DIR + str(f))
		if tpl.is_empty():
			continue
		var tid := str(f).trim_suffix(".json")
		var entry := {"id": tid, "version": int(tpl.get("version", 0)), "operator": str(tpl.get("operator", "")), "referenced": tid in referenced}
		(report.templates as Array).append(entry)
		if not entry.referenced:
			(report.demo as Array).append(tid)
	report["total"] = (report.templates as Array).size()
	return report


static func save_json(path: String, tpl: Dictionary) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(tpl, "\t"))
	f.close()
	return true


static func save_draft(name: String, tpl: Dictionary) -> bool:
	return save_json(DRAFT_DIR + name + ".json", tpl)


static func save_published(name: String, tpl: Dictionary) -> bool:
	var r := validate(tpl.get("params", {}))
	if not r.ok:
		return false
	return save_json(GOLD_DIR + name + ".json", tpl)
