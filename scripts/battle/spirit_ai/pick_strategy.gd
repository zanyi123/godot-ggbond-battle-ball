class_name SpiritAIPickStrategy
extends RefCounted
## 工单30 S3：联机 AI 自动选角策略（纯函数·零场景依赖·headless 可测）
## 接口逐字照移交单（联机侧已按此调用）：
##   pick_character(available: Array, team_picks: Array) -> String
##   pick_spirit(available: Array, team_picks: Array) -> String
## D16 裁定：队内唯一、敌我可重复；池=7球员/6元灵不扩。
## 策略（可解释打分，禁黑盒）：
##   character：①职位画像补缺硬优先（球员数据无静态职位字段——S3-1 盘点结论，
##     由五维属性推导画像：主攻=attack 主导/防御=defense+resilience 主导/辅助=stamina+speed 主导）
##     ②同画像比属性互补（与已选队友错位）③tie-break=池序第一个
##   spirit：①按已选球员弱点互补（最低维→补该维强的元灵）②元素分布均衡（选角阶段无敌方信息，不猜敌）
##     ③tie-break=池序第一个
## 纪律：全程禁 randf/randi（确定性铁律）；只读 DataManager 数据结构；空池返回 ""（联机侧兜底随机）、
##   池余 1 返回唯一；不改 skills.json/spirits.json（数据红线归主人）。

## 五维属性权重（画像推导用；归一化比较）
const ROLE_DIMS := {
	"attacker": ["attack", "speed"],
	"defender": ["defense", "resilience"],
	"support": ["stamina"],
}
const ALL_DIMS: Array[String] = ["attack", "defense", "resilience", "speed", "stamina"]


## ---------- pick_character：职位画像补缺 + 属性互补 ----------
static func pick_character(available: Array, team_picks: Array) -> String:
	if available.is_empty():
		return ""
	if available.size() == 1:
		return str(available[0])
	# ① 职位画像补缺：统计已选队友的画像，缺哪类补哪类（首轮无队友→三画像均衡=直接②）
	var need_role := _missing_role(team_picks)
	# ② 候选按画像归类，缺类候选优先；同类比属性互补分（与已选队友错位）
	var best: String = ""
	var best_score := -INF
	for cand in available:
		var cid := str(cand)
		var cdata := _character_data(cid)
		if cdata.is_empty():
			continue
		var role := _role_of(cdata)
		var score := 100.0 if (need_role != "" and role == need_role) else 0.0
		score += _complement_score(cdata, team_picks)
		if score > best_score:
			best_score = score
			best = cid
	# ③ tie-break=池序第一个：best_score 严格大于才换（同分保留先遍历者）
	if best == "":
		return str(available[0])
	return best


## ---------- pick_spirit：球员弱点互补 + 元素分布均衡 ----------
static func pick_spirit(available: Array, team_picks: Array) -> String:
	if available.is_empty():
		return ""
	if available.size() == 1:
		return str(available[0])
	# ① 队内弱点：已选球员五维最低维（防/体弱→补防御恢复向元灵）
	var weak_dim := _team_weak_dim(team_picks)
	var best: String = ""
	var best_score := -INF
	for cand in available:
		var sid := str(cand)
		var sdata := _spirit_data(sid)
		if sdata.is_empty():
			continue
		var score := 0.0
		# 元素→补维映射（elements 克制表退化为队内均衡：元素种类未出现者优先）
		var element := str(sdata.get("element", ""))
		score += 5.0 if not _element_seen(team_picks, element) else 0.0
		# 弱点互补：元灵技能标签语义倾向（防御/恢复向技能补防守弱队——按技能 tag 读DataManager）
		if weak_dim != "":
			score += _spirit_dim_affinity(sdata, weak_dim)
		if score > best_score:
			best_score = score
			best = sid
	if best == "":
		return str(available[0])
	return best


# ===== 私有工具（只读 DataManager 数据结构；查不到=0分/fail-closed，不猜） =====

static func _character_data(cid: String) -> Dictionary:
	var dm = Engine.get_main_loop()
	if dm == null or not (dm is SceneTree):
		return {}
	var data_manager = (dm as SceneTree).root.get_node_or_null("DataManager")
	if data_manager == null:
		return {}
	for c in data_manager.characters:
		if c is Dictionary and str(c.get("id", "")) == cid:
			return c
	return {}


static func _spirit_data(sid: String) -> Dictionary:
	var dm = Engine.get_main_loop()
	if dm == null or not (dm is SceneTree):
		return {}
	var data_manager = (dm as SceneTree).root.get_node_or_null("DataManager")
	if data_manager == null:
		return {}
	for s in data_manager.spirits:
		if s is Dictionary and str(s.get("id", "")) == sid:
			return s
	return {}


## 职位画像：五维归一化后三类 argmax（无静态职位字段——S3-1 盘点）。
## 归一基准=DataManager 全表球员各维 min/max（raw 数值 def/res 天然偏高，绝对比会全员防御画像）；
## 基准进程内缓存一次（只读，跨调用稳定=确定性）。
static var _norm_base: Dictionary = {}

static func _norm_base_ensure() -> void:
	if not _norm_base.is_empty():
		return
	var dims := {"attack": [], "defense": [], "resilience": [], "speed": [], "stamina": []}
	var dm = Engine.get_main_loop()
	if dm != null and (dm is SceneTree):
		var data_manager = (dm as SceneTree).root.get_node_or_null("DataManager")
		if data_manager != null:
			for c in data_manager.characters:
				if c is Dictionary:
					for dim in dims:
						if c.get(dim) != null:
							(dims[dim] as Array).append(float(c.get(dim)))
	for dim in dims:
		var arr: Array = dims[dim]
		if (arr as Array).is_empty():
			_norm_base[dim] = {"min": 0.0, "max": 1.0}
		else:
			var lo: float = (arr as Array).min()
			var hi: float = (arr as Array).max()
			_norm_base[dim] = {"min": lo, "max": hi if hi > lo else lo + 1.0}


static func _norm(cdata: Dictionary, dim: String) -> float:
	_norm_base_ensure()
	var base: Dictionary = _norm_base.get(dim, {"min": 0.0, "max": 1.0})
	var v := float(cdata.get(dim, 0.0))
	return clampf((v - float(base.get("min", 0.0))) / maxf(float(base.get("max", 1.0)) - float(base.get("min", 0.0)), 0.001), 0.0, 1.0)


static func _role_of(cdata: Dictionary) -> String:
	var atk := _norm(cdata, "attack")
	var def := (_norm(cdata, "defense") + _norm(cdata, "resilience")) * 0.5
	var sup := (_norm(cdata, "stamina") + _norm(cdata, "speed")) * 0.5
	if def >= atk and def >= sup:
		return "defender"
	if atk >= sup:
		return "attacker"
	return "support"


## 已选队友缺哪类画像（每类计数，缺最多者；全齐=""）
static func _missing_role(team_picks: Array) -> String:
	if team_picks.is_empty():
		return ""
	var count := {"attacker": 0, "defender": 0, "support": 0}
	for pid in team_picks:
		var cdata := _character_data(str(pid))
		if cdata.is_empty():
			continue
		var r := _role_of(cdata)
		count[r] = int(count.get(r, 0)) + 1
	var need := ""
	var need_n := 99
	for r in count:
		if int(count[r]) < need_n:
			need_n = int(count[r])
			need = str(r)
	return need if need_n < 1 else ""


## 属性互补分：与已选队友五维错位（队友已高的维再高=冗余减分；队友低的维高=互补加分）
static func _complement_score(cdata: Dictionary, team_picks: Array) -> float:
	var score := 0.0
	for pid in team_picks:
		var mate := _character_data(str(pid))
		if mate.is_empty():
			continue
		for dim in ALL_DIMS:
			var mine := float(cdata.get(dim, 0.0))
			var theirs := float(mate.get(dim, 0.0))
			if mine > theirs:
				score += (mine - theirs) * 0.1
	return score


## 队内五维最低维（弱点；平局取 ALL_DIMS 序首=确定性）
static func _team_weak_dim(team_picks: Array) -> String:
	var sums := {}
	for dim in ALL_DIMS:
		sums[dim] = 0.0
	var n := 0
	for pid in team_picks:
		var cdata := _character_data(str(pid))
		if cdata.is_empty():
			continue
		n += 1
		for dim in ALL_DIMS:
			sums[dim] = float(sums[dim]) + float(cdata.get(dim, 0.0))
	if n == 0:
		return ""
	var weak := ""
	var weak_v := INF
	for dim in ALL_DIMS:
		if float(sums[dim]) < weak_v:
			weak_v = float(sums[dim])
			weak = dim
	return weak


## 元素是否已在队内出现（选角阶段无敌方信息→均衡不猜敌）。
## team_picks 传球员 id 时无元灵记录→用球员 spirit_preference（偏好元素）作已定元素代理
static func _element_seen(team_picks: Array, element: String) -> bool:
	for pid in team_picks:
		var sdata := _spirit_data(str(pid))
		if not sdata.is_empty() and str(sdata.get("element", "")) == element:
			return true
		var cdata := _character_data(str(pid))
		if not cdata.is_empty() and str(cdata.get("spirit_preference", "")) == element:
			return true
	return false


## 元灵对弱点的亲和：防御/耐久弱→防御恢复向元灵加分（技能 tag 语义读 DataManager skills）
static func _spirit_dim_affinity(sdata: Dictionary, weak_dim: String) -> float:
	var dm = Engine.get_main_loop()
	if dm == null or not (dm is SceneTree):
		return 0.0
	var data_manager = (dm as SceneTree).root.get_node_or_null("DataManager")
	if data_manager == null:
		return 0.0
	var affinity := 0.0
	for skill_id in sdata.get("skills", []):
		for s in data_manager.skills:
			if s is Dictionary and str(s.get("id", "")) == str(skill_id):
				for tag in s.get("tags", []):
					var t := str(tag)
					if weak_dim == "defense" and (t.begins_with("player_def_up") or t == "player_shield_obstacle" or t == "player_damage_reflect"):
						affinity += 10.0
					elif weak_dim == "resilience" and (t.begins_with("player_res_up") or t == "player_hp_regen"):
						affinity += 8.0
					elif weak_dim == "attack" and t.begins_with("player_atk_up"):
						affinity += 8.0
					elif weak_dim == "stamina" and t == "player_hp_heal_pct":
						affinity += 6.0
	return affinity
