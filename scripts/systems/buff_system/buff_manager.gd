class_name BuffManager
extends Node
## Buff堆栈管理器
## 管理"属性修改纸条"的添加、移除、到期、计算
##
## 规则：最终属性 = 基础值 × 所有pct连乘 + 所有flat求和
## 举例：基础攻击50，+30%纸条，-20%纸条，+10固定纸条
##   → 50 × 1.3 × 0.8 + 10 = 52

## ==================== 数据结构 ====================

## 一张纸条
## { id, stat, type("pct"/"flat"), value, source, duration, remaining }
var _buffs: Array[Dictionary] = []
var _buff_counter: int = 0

## 属性白名单：只有这些stat可以被buff改
const BUFFABLE_STATS: Array[String] = [
	"attack_power", "defense", "speed", "resilience",
	"defense_factor", "spirit_energy", "max_spirit_energy",
]

## ==================== 信号 ====================

signal buff_added(buff_id: String, stat: String, type: String, value: float)
signal buff_removed(buff_id: String, stat: String)
signal buff_expired(buff_id: String, stat: String)

## ==================== 添加Buff ====================

## 添加一条buff纸条
## @param stat     属性名（必须在BUFFABLE_STATS中）
## @param type     "pct"=百分比（0.3表示+30%）, "flat"=固定值（10表示+10）
## @param value    数值（pct为小数比例，flat为具体值，可负）
## @param duration 持续秒数（0=永久，需手动移除）
## @param source   来源标签ID，用于批量移除
## @return buff唯一ID
func add_buff(stat: String, type: String, value: float, duration: float = 0.0, source: String = "") -> String:
	# 安检：属性名必须在白名单里
	if stat not in BUFFABLE_STATS:
		push_warning("[BuffManager] 不允许buff属性: %s" % stat)
		return ""

	_buff_counter += 1
	var bid: String = "buff_%d" % _buff_counter
	_buffs.append({
		"id": bid,
		"stat": stat,
		"type": type,
		"value": value,
		"source": source,
		"duration": duration,
		"remaining": duration,
	})
	buff_added.emit(bid, stat, type, value)
	return bid

## ==================== 移除Buff ====================

## 按ID移除单条
func remove_buff(bid: String) -> void:
	for i in range(_buffs.size() - 1, -1, -1):
		if _buffs[i].id == bid:
			var b: Dictionary = _buffs[i]
			_buffs.remove_at(i)
			buff_removed.emit(bid, b.stat)
			return

## 按来源标签批量移除
func remove_buffs_by_source(source: String) -> void:
	for i in range(_buffs.size() - 1, -1, -1):
		if _buffs[i].source == source:
			var b: Dictionary = _buffs[i]
			_buffs.remove_at(i)
			buff_removed.emit(b.id, b.stat)

## 清空所有buff
func clear_all() -> void:
	_buffs.clear()

## ==================== 计算最终属性 ====================

## 计算某个属性的最终值
## @param base_value 基础值（裸值）
## @param stat       属性名
## @return 最终值 = base_value × pct连乘 + flat求和
func calc_stat(base_value: float, stat: String) -> float:
	var pct_mult: float = 1.0
	var flat_sum: float = 0.0
	for b in _buffs:
		if b.stat == stat:
			if b.type == "pct":
				pct_mult *= (1.0 + b.value)
			elif b.type == "flat":
				flat_sum += b.value
	return base_value * pct_mult + flat_sum

## 获取某个属性当前所有buff的汇总（调试用）
func get_buff_summary(stat: String) -> Dictionary:
	var pct_mult: float = 1.0
	var flat_sum: float = 0.0
	var count: int = 0
	for b in _buffs:
		if b.stat == stat:
			count += 1
			if b.type == "pct":
				pct_mult *= (1.0 + b.value)
			elif b.type == "flat":
				flat_sum += b.value
	return {"pct_mult": pct_mult, "flat_sum": flat_sum, "count": count}

## ==================== 每帧更新 ====================

## 在外部 _process / _physics_process 中调用
func process_buffs(delta: float) -> void:
	for i in range(_buffs.size() - 1, -1, -1):
		var b: Dictionary = _buffs[i]
		if b.duration > 0.0:
			b.remaining -= delta
			if b.remaining <= 0.0:
				_buffs.remove_at(i)
				buff_expired.emit(b.id, b.stat)

## ==================== 查询 ====================

## 当前buff数量
func get_buff_count() -> int:
	return _buffs.size()

## 某属性的buff数量
func get_stat_buff_count(stat: String) -> int:
	var count: int = 0
	for b in _buffs:
		if b.stat == stat:
			count += 1
	return count

## 是否有某个来源的buff
func has_buff_from_source(source: String) -> bool:
	for b in _buffs:
		if b.source == source:
			return true
	return false

## 获取所有buff（调试用，只读）
func get_all_buffs() -> Array[Dictionary]:
	return _buffs.duplicate()
