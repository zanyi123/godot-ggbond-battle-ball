class_name SpiritAIDefenseTable
extends RefCounted
## 24号 S1 读取口：防御技判别表（标签→防御动作）——AI 防御决策的数据源
## 数据：data/systems/spirit_ai/defense_table.json（主人裁决口径，可热改）
## 纪律：纯静态无状态（照 13号知识库先例 preload 直查）；禁 randf；表缺失 fail-closed（无防御动作）

const TABLE_PATH := "res://data/systems/spirit_ai/defense_table.json"

static var _cache: Dictionary = {}

static func get_table() -> Dictionary:
	## 读表（进程内缓存一次；坏 JSON 返回 {} fail-closed）
	if _cache.is_empty():
		var txt: String = FileAccess.get_file_as_string(TABLE_PATH)
		var parsed = JSON.parse_string(txt) if not txt.is_empty() else null
		if parsed is Dictionary and parsed.has("tag_actions"):
			_cache = parsed
	return _cache.get("tag_actions", {})

## 查某标签的防御动作（"hard_block"/"soften"/"avoid"/"recover"；表外返回 ""）
static func action_of(tag_id: String) -> String:
	return str(get_table().get(tag_id, ""))

## 扫描一组标签，返回其中最高优先级防御动作（hard_block > soften > avoid > recover）
## 多标签复合技：取最高优先动作（硬挡优先——能挡就别只软化）
static func best_action_for_tags(tags: Array[String]) -> String:
	var priority := {"hard_block": 4, "soften": 3, "avoid": 2, "recover": 1}
	var best: String = ""
	var best_p: int = 0
	for t in tags:
		var a := action_of(t)
		if a != "" and priority.has(a) and int(priority[a]) > best_p:
			best = a
			best_p = int(priority[a])
	return best

static func reload() -> void:
	_cache = {}
