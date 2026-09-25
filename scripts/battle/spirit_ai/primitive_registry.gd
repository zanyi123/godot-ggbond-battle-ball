class_name SpiritAIPrimitiveRegistry
extends RefCounted
## 原语注册表（08集成基建工单）：聚合各波 primitives_*.json + 两层开关单口拦截。
## 工单见 元灵技能AI规划/08_集成基建工单_原语开关.md；开关语义收口在本文件，
## spirit_ai_manager 零感知（接线后查不到描述符=自然走旧评分分支 fallback）。
## 纪律：禁 randf；fail-closed——switches 缺失/损坏/字段非法/未知波次字母一律视同全关，
## 宁可不启用，不可误启用。

const SWITCHES_PATH := "res://data/systems/spirit_ai/switches.json"
## 各波原语表（按字母序聚合，后加载者覆盖同 tag_id 并告警；缺文件自动跳过）
const WAVE_TABLES: Array[String] = [
	"res://data/systems/spirit_ai/primitives_a.json",
	"res://data/systems/spirit_ai/primitives_b.json",
	"res://data/systems/spirit_ai/primitives_c.json",
	"res://data/systems/spirit_ai/primitives_d.json",
	"res://data/systems/spirit_ai/primitives_e.json",
]

static var _agg: Dictionary = {}
static var _agg_loaded: bool = false
static var _switches: Dictionary = {}
static var _switches_loaded: bool = false


## 单口查询：命中描述符后先过波次开关——未开/未命中一律返回 {}（调用方自然走 fallback）
static func get_descriptor(tag_id: String) -> Dictionary:
	_ensure_aggregated()
	var entry: Dictionary = _agg.get(tag_id, {})
	if entry.is_empty():
		return {}
	if not is_wave_enabled(str(entry.get("wave", ""))):
		return {}
	var descriptor: Dictionary = entry.get("descriptor", {})
	return descriptor if descriptor is Dictionary else {}


## 分波开关：master_enabled 且 waves[wave] 严格为 true 才算开
static func is_wave_enabled(wave: String) -> bool:
	_ensure_switches(SWITCHES_PATH)
	if not (_switches.get("master_enabled") is bool and bool(_switches.get("master_enabled"))):
		return false
	var waves = _switches.get("waves", {})
	if not waves is Dictionary:
		return false
	var v = waves.get(wave, false)
	return v is bool and bool(v)


## 重载开关（开发者热改 switches.json 后调用；path 参数供测试注入临时文件）
static func reload_switches(path: String = SWITCHES_PATH) -> void:
	_switches = _load_switches(path)
	_switches_loaded = true


# ===== 内部实现 =====

static func _ensure_aggregated() -> void:
	if _agg_loaded:
		return
	_agg = _aggregate(WAVE_TABLES)
	_agg_loaded = true


static func _ensure_switches(path: String) -> void:
	if _switches_loaded:
		return
	reload_switches(path)


## 聚合各波表：tag_id → {"descriptor": Dictionary, "wave": String}（wave 取各文件顶层字段）
## 同 tag_id 冲突 → 后加载者覆盖 + push_warning 告警
static func _aggregate(paths: Array) -> Dictionary:
	var out: Dictionary = {}
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			push_warning("PrimitiveRegistry: 原语表非法，跳过 " + path)
			continue
		var table: Dictionary = parsed
		var wave: String = str(table.get("wave", ""))
		if wave.is_empty():
			push_warning("PrimitiveRegistry: 原语表缺 wave 字段，跳过 " + path)
			continue
		var descs = table.get("descriptors", {})
		if not descs is Dictionary:
			push_warning("PrimitiveRegistry: 原语表 descriptors 非法，跳过 " + path)
			continue
		for tag_id in descs.keys():
			if out.has(tag_id):
				push_warning("PrimitiveRegistry: tag_id 跨波冲突，后者覆盖 %s（%s ← %s）" % [tag_id, str(out[tag_id].get("wave", "")), wave])
			out[tag_id] = {"descriptor": descs[tag_id], "wave": wave}
	return out


## 读开关文件；缺失/损坏/字段非法 → 一律视同全关（fail-closed）
static func _load_switches(path: String) -> Dictionary:
	var all_off: Dictionary = {"master_enabled": false, "waves": {}}
	if not FileAccess.file_exists(path):
		return all_off
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("PrimitiveRegistry: switches.json 损坏，视同全关 " + path)
		return all_off
	var raw: Dictionary = parsed
	var out: Dictionary = {"master_enabled": false, "waves": {}}
	if raw.get("master_enabled") is bool:
		out["master_enabled"] = bool(raw.get("master_enabled"))
	if raw.get("waves") is Dictionary:
		out["waves"] = raw.get("waves")
	return out
