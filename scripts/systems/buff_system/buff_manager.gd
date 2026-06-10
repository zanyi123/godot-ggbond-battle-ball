## Buff 堆栈模块
##
## 纯数值层：管理属性修正的添加/移除/到期/计算
## 不依赖任何战斗节点，可独立测试
##
## 公式：最终值 = 基础值 × 所有乘法buff连乘 + 所有加法buff求和
##
## 用法：
##   var buff := BuffManager.new()
##   buff.add_buff("atk_1", "attack", 1.3, 0.0, 5.0)  # +30%攻击, 5秒
##   var atk := buff.get_effective_value("attack", 50.0)  # → 65.0

class_name BuffManager

## 一张纸条的结构：
## { id, stat, mult, flat, source, duration, remaining }
var _buffs: Dictionary = {}  # id -> buff字典

## 添加/覆盖一个buff
## id: 唯一编号，同id重复添加会覆盖旧值
## stat: 属性名 (attack/defense/speed/resilience/max_energy)
## mult: 乘法修正 (1.0=不改, >1提升, <1降低)
## flat: 加法修正 (0.0=不改, >0提升, <0降低)
## duration: 持续时间(秒), <=0 表示永久
## source: 来源标签ID（可选，用于调试）
func add_buff(id: String, stat: String, mult: float, flat: float, duration: float, source: String = "") -> void:
	_buffs[id] = {
		"id": id,
		"stat": stat,
		"mult": mult,
		"flat": flat,
		"source": source,
		"duration": duration,
		"remaining": duration,
	}


## 手动移除一个buff
func remove_buff(id: String) -> bool:
	if _buffs.has(id):
		_buffs.erase(id)
		return true
	return false


## 计算某个属性的最终值
## base_value: 该属性的基础值（如 attack_power = 50）
func get_effective_value(stat: String, base_value: float) -> float:
	var m: float = 1.0
	var f: float = 0.0
	for id in _buffs:
		var b: Dictionary = _buffs[id]
		if b.get("stat", "") == stat:
			m *= b.get("mult", 1.0)
			f += b.get("flat", 0.0)
	# 乘法下限保护：不低于0.01
	m = maxf(m, 0.01)
	return base_value * m + f


## 每帧调用，倒计时并清除过期buff
## delta: _process 传入的帧间隔
func tick(delta: float) -> void:
	var to_remove: PackedStringArray = []
	for id in _buffs:
		var b: Dictionary = _buffs[id]
		# 永久buff（duration<=0）不倒计时
		if b.get("duration", 0.0) <= 0.0:
			continue
		b["remaining"] = b.get("remaining", 0.0) - delta
		if b.get("remaining", 0.0) <= 0.0:
			to_remove.append(id)
	for id in to_remove:
		_buffs.erase(id)


## 查询：当前有多少个buff
func get_buff_count() -> int:
	return _buffs.size()


## 查询：某个属性有多少个buff
func get_stat_buff_count(stat: String) -> int:
	var count: int = 0
	for id in _buffs:
		if _buffs[id].get("stat", "") == stat:
			count += 1
	return count


## 查询：某个buff是否存在
func has_buff(id: String) -> bool:
	return _buffs.has(id)


## 查询：某个buff的剩余时间
func get_remaining(id: String) -> float:
	if _buffs.has(id):
		return _buffs[id].get("remaining", 0.0)
	return 0.0


## 清除所有buff
func clear_all() -> void:
	_buffs.clear()
