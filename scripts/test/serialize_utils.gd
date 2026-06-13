extends Node
class_name SerializeUtils

## ==================== 字典序列化工具 ====================

func _serialize_mult_dict(mults: Dictionary) -> String:
	"""把倍率字典序列化为字符串,方便快照比较"""
	if mults.is_empty():
		return ""
	var pairs: Array = []
	for key in mults:
		var m: Dictionary = mults[key]
		if m.has("mult") and m.has("remaining"):
			var mult: float = m.get("mult", 1.0)
			var rem: float = m.get("remaining", 0.0)
			pairs.append("%s:%.2f(%.1f)" % [key, mult, rem])
	pairs.sort()
	return ",".join(pairs)


func _serialize_bonus_uses(uses: Dictionary) -> String:
	"""把额外次数字典序列化为字符串"""
	if uses.is_empty():
		return ""
	var pairs: Array = []
	for key in uses:
		var val: int = uses[key]
		pairs.append("%s:%d" % [key, val])
	pairs.sort()
	return ","..join(pairs)