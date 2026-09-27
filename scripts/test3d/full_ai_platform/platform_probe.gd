extends Node
## 工单12 复杂技能运行时检测层（平台窗口，主人令 2026-09-27）—— 信号判定，非肉眼验收
## 对照《技能规划/21_技能标签UI验收标志对照表》：UI 图标条数据源=判定层只读信号，
## 本探针直接订阅同一批判定层信号自动采集：
##   印记 = player.mark_changed(mark_id, count)（印图标+层数角标的数据源；2/3 层阈值效果）
##   合体 = skill_state_manager.combo_formed/combo_broken（OP_COMBO 协调器信号；就绪表/合体态查询口）
##   释放 = spirit_system.skill_used(skill_id, caster_id, success)
## 场终输出统计+判定（印记链/合体是否在运行时真实发生），auto 模式作为退出依据。

signal verdict_ready(verdict: Dictionary)

var bm: Node2D = null
var probe_enabled: bool = true

# —— 采集容器（场次内）——
var casts: Dictionary = {}            # skill_id -> count（success=true 的释放）
var cast_total: int = 0
var cast_failed: Dictionary = {}      # skill_id -> count（success=false）
var mark_events: Array = []           # [{t, char, team, mark_id, count}]
var mark_max_stack: int = 0           # 场内最大叠层数
var mark_ids_seen: Dictionary = {}    # mark_id -> true
var combo_formed_events: Array = []   # [{t, combo_id, members_desc, params}]
var combo_broken_count: int = 0
var _elapsed: float = 0.0
var _last_report_at: float = 0.0
var _dump_poll_accum: float = 0.0
var _dump_samples: Dictionary = {}    # player_name -> {count, last}（决策 dump 轮询累积）
var _factor_stats: Dictionary = {}    # skill_id -> {samples, score_pos, 各因子归零计数}（赛中采样）
var _cast_times: Dictionary = {}      # skill_id -> Array[float]（释放时刻；麒麟队合击窗口判定用）
var trio_window: float = 5.0          # 合击同窗秒数（麒麟火 ±N 秒内的三味真火计数）

# 工单12 关注技能（打印美化用；未列出也照常采集）
const WATCH_SKILLS := {
	"skill_雷火_5": "麒麟火",
	"skill_雷火_6": "三味真火",
	"skill_金刚_2": "装甲半装",
	"skill_金刚_3": "炮击半装",
	"skill_大地_3": "祖传秘法",
}


func setup(battle_manager: Node2D) -> void:
	bm = battle_manager
	name = "PlatformProbe"

	# —— 释放事件（判定层 success 口）——
	var ss = bm.spirit_system
	if ss != null and ss.has_signal("skill_used"):
		ss.skill_used.connect(_on_skill_used)

	# —— 印记事件（21表通道①「印」图标数据源）——
	for player in bm.team_a_players + bm.team_b_players:
		if player != null and is_instance_valid(player) and player.has_signal("mark_changed"):
			player.mark_changed.connect(_on_mark_changed.bind(player))

	# —— 合体协调器信号（工单12 S1）——
	var ssm: Node = get_tree().get_first_node_in_group("skill_state_managers")
	if ssm == null:
		# 兜底：遍历 spirit_system 子树找（有 register_combo_ready 方法的节点）
		ssm = _find_state_manager(ss)
	if ssm != null:
		if ssm.has_signal("combo_formed"):
			ssm.combo_formed.connect(_on_combo_formed)
		if ssm.has_signal("combo_broken"):
			ssm.combo_broken.connect(_on_combo_broken)
		print("[Probe] 合体协调器已挂接（combo_formed/combo_broken）")
	else:
		print("[Probe] ⚠ 未找到合体协调器（skill_state_managers 组空）——合体检测不可用")

	print("[Probe] 检测层已挂接：释放(skill_used) + 印记(mark_changed) + 合体(combo_formed/broken)")


func _find_state_manager(root_node: Node) -> Node:
	if root_node == null:
		return null
	if root_node.has_method("register_combo_ready"):
		return root_node
	for child in root_node.get_children():
		var found := _find_state_manager(child)
		if found != null:
			return found
	return null


func _process(delta: float) -> void:
	if not probe_enabled:
		return
	_elapsed += delta
	if _elapsed - _last_report_at >= 10.0:
		_last_report_at = _elapsed
		print("[Probe] %4.0fs %s | %s" % [_elapsed, _casts_line(), _marks_combo_line()])
	# 决策 dump 轮询（1s；get_decision_dump=10工单P3集成只读口）+ 关注技因子赛中采样
	_dump_poll_accum += delta
	if _dump_poll_accum >= 1.0:
		_dump_poll_accum = 0.0
		var sam = bm.ai_mgr.spirit_ai_mgr if bm != null and bm.ai_mgr != null else null
		if sam != null and sam.has_method("get_decision_dump"):
			var d: Dictionary = sam.get_decision_dump()
			var pname := str(d.get("player", ""))
			if not pname.is_empty():
				if not _dump_samples.has(pname):
					_dump_samples[pname] = {"count": 0, "last": {}}
				_dump_samples[pname]["count"] = int(_dump_samples[pname]["count"]) + 1
				_dump_samples[pname]["last"] = d
		if sam != null and bm != null:
			for sad in sam.spirit_ai_data:
				var pl = sad.get("player")
				if pl == null or not is_instance_valid(pl):
					continue
				for info in sad.get("skills_analysis", []):
					var sid := str(info.get("skill_id", ""))
					if not WATCH_SKILLS.has(sid):
						continue
					if not _factor_stats.has(sid):
						_factor_stats[sid] = {}
					var total: int = int(_factor_stats[sid].get("samples", 0)) + 1
					_factor_stats[sid]["samples"] = total
					var pos: bool = float(sam._compute_skill_score(sad, info)) > 0.0
					_factor_stats[sid]["score_pos"] = int(_factor_stats[sid].get("score_pos", 0)) + (1 if pos else 0)
					for pair in [["base", float(info.get("base_value", 0))],
							["situ", float(sam._compute_situation_factor(sad, info))],
							["time", float(sam._compute_time_factor(sad, info))],
							["comm", float(sam._compute_communication_factor(sad, info))],
							["elem", float(sam._compute_element_factor(sad, info))],
							["combo", float(sam._compute_combo_factor(sad, info))],
							["team", float(sam._compute_team_factor(sad, info))]]:
						if float(pair[1]) <= 0.0:
							var k := str(pair[0])
							_factor_stats[sid][k] = int(_factor_stats[sid].get(k, 0)) + 1
					if not bool(sam._should_use_energy(sad, info, 100.0)):
						_factor_stats[sid]["energy"] = int(_factor_stats[sid].get("energy", 0)) + 1


# ==================== 信号处理 ====================

func _on_skill_used(skill_id: String, _caster_id: int, success: bool) -> void:
	if success:
		casts[skill_id] = int(casts.get(skill_id, 0)) + 1
		cast_total += 1
		if not _cast_times.has(skill_id):
			_cast_times[skill_id] = []
		_cast_times[skill_id].append(_elapsed)
	else:
		cast_failed[skill_id] = int(cast_failed.get(skill_id, 0)) + 1


## 麒麟队合击判定（主人 09-27 澄清原作设计）：每次麒麟火释放时刻 t0，
## 统计 ±trio_window 秒内三味真火道数；返回最大同窗道数
func best_kirin_trio() -> int:
	var kirin: Array = _cast_times.get("skill_雷火_5", [])
	var sanwei: Array = _cast_times.get("skill_雷火_6", [])
	var best := 0
	for t0 in kirin:
		var count := 0
		for t in sanwei:
			if absf(float(t) - float(t0)) <= trio_window:
				count += 1
		best = maxi(best, count)
	return best


func _on_mark_changed(mark_id: String, count: int, player: Node) -> void:
	var who := "?"
	var team := "?"
	if player != null and is_instance_valid(player):
		who = str(player.char_data.get("name", player.name))
		team = str(player.team).to_upper()
	mark_events.append({"t": _elapsed, "char": who, "team": team, "mark_id": mark_id, "count": count})
	mark_ids_seen[mark_id] = true
	if count > mark_max_stack:
		mark_max_stack = count
	print("[Probe] 印记 %s 落在 %s(%s) → %d 层%s" % [
		mark_id, who, team, count, "（阈值层！）" if count >= 2 else ""])


func _on_combo_formed(combo_id: String, members: Array, params: Dictionary) -> void:
	var desc := _members_desc(members)
	combo_formed_events.append({"t": _elapsed, "combo_id": combo_id, "members": desc, "params": params.duplicate(true)})
	print("[Probe] ✨ 合体成立 %s：成员[%s] 时长%s" % [combo_id, desc, str(params.get("duration", "?"))])


func _on_combo_broken(_combo_id: String, _members: Array) -> void:
	combo_broken_count += 1


# ==================== 报告与判定 ====================

func build_verdict() -> Dictionary:
	var mark_skills_cast: Array[String] = []
	for sid in ["skill_雷火_5", "skill_雷火_6"]:
		if int(casts.get(sid, 0)) > 0:
			mark_skills_cast.append(sid)
	var combo_halves_cast: int = 0
	for sid in ["skill_金刚_2", "skill_金刚_3"]:
		if int(casts.get(sid, 0)) > 0:
			combo_halves_cast += 1
	var mark_ok: bool = not mark_events.is_empty()
	var mark_chain_ok: bool = mark_skills_cast.size() >= 2 and mark_max_stack >= 2
	var combo_ok: bool = not combo_formed_events.is_empty()
	var trio_best := best_kirin_trio()
	return {
		"elapsed": _elapsed,
		"cast_total": cast_total,
		"casts": casts.duplicate(),
		"mark_applied": mark_events.size(),
		"mark_max_stack": mark_max_stack,
		"mark_ids": mark_ids_seen.keys(),
		"mark_skills_cast": mark_skills_cast,
		"mark_chain_ok": mark_chain_ok,
		"combo_formed": combo_formed_events.size(),
		"combo_broken": combo_broken_count,
		"combo_halves_cast": combo_halves_cast,
		"mark_ok": mark_ok,
		"combo_ok": combo_ok,
		"trio_best": trio_best,
		"trio_ok": trio_best >= 2,
		"pass": mark_ok and combo_ok and trio_best >= 2,
	}


func print_final_report() -> Dictionary:
	var v := build_verdict()
	print("[Probe] ========== 场终统计（运行时信号判定） ==========")
	print("[Probe] 技能释放: 总计%d 次%s" % [v["cast_total"], _watch_detail()])
	if not cast_failed.is_empty():
		print("[Probe] 释放失败: %s" % _dict_line(cast_failed))
	print("[Probe] 印记: 事件%d 次 | 最大叠层 %d 层 | mark_id=%s%s" % [
		v["mark_applied"], v["mark_max_stack"], str(v["mark_ids"]),
		" | 印记链(麒麟火+三味真火均释放且≥2层)=%s" % ("✅" if v["mark_chain_ok"] else "—") if v["mark_ok"] else ""])
	print("[Probe] 合体: 成立%d 次 / 拆分%d 次%s%s" % [
		v["combo_formed"], v["combo_broken"],
		" | 成员=" + str(combo_formed_events[0]["members"]) if not combo_formed_events.is_empty() else "",
		"（半装释放 %d/2）" % v["combo_halves_cast"] if int(v["combo_halves_cast"]) > 0 else ""])
	var trio_best := int(v["trio_best"])
	print("[Probe] 麒麟队合击（原作设计：麒麟火+2×三味真火同窗±%0.fs）：最佳同窗=麒麟火+[%d]道三味%s" % [
		trio_window, trio_best, " ✅" if bool(v["trio_ok"]) else " ❌（未达成三人合击）"])
	_dump_player_pools()
	print("[Probe] ---- 赛中因子采样（每秒×全场；score_pos=得分>0 的采样占比）----")
	for sid in WATCH_SKILLS:
		var st: Dictionary = _factor_stats.get(sid, {})
		if st.is_empty() or int(st.get("samples", 0)) == 0:
			continue
		var samples := int(st["samples"])
		var parts: Array[String] = []
		for k in ["base", "situ", "time", "comm", "elem", "combo", "team", "energy"]:
			if int(st.get(k, 0)) > 0:
				parts.append("%s归零%d/%d" % [k, int(st[k]), samples])
		print("[Probe]   · %s: score>0 占比 %d/%d%s" % [
			str(WATCH_SKILLS[sid]), int(st.get("score_pos", 0)), samples,
			" | " + " ".join(parts) if not parts.is_empty() else ""])
	if bool(v["pass"]):
		print("[Probe] ✅ VERDICT: PASS —— 印记/合体/麒麟队合击在运行时均真实发生（信号判定）")
	else:
		var missing: Array[String] = []
		if not bool(v["mark_ok"]):
			missing.append("印记未发生（无 mark_changed 事件——查 麒麟火/三味真火 是否释放与命中）")
		if not bool(v["combo_ok"]):
			missing.append("OP_COMBO 合体未发生（无 combo_formed——查 装甲半/炮击半 是否双登记、同队存活且距离≤150）")
		if not bool(v["trio_ok"]):
			missing.append("麒麟队三人合击未达成（最佳同窗麒麟火+%d 道三味——查能量闸门/独立决策时序）" % trio_best)
		print("[Probe] ❌ VERDICT: FAIL —— " + "；".join(missing))
	return v


## 逐球员诊断：技能AI 评分池/可用池/决策数（只读 sad）——定位"未释放"断在哪一环
func _dump_player_pools() -> void:
	if bm == null or bm.ai_mgr == null or bm.ai_mgr.spirit_ai_mgr == null:
		return
	var sam = bm.ai_mgr.spirit_ai_mgr
	var all_players: Array = bm.team_a_players + bm.team_b_players
	print("[Probe] ---- 逐球员池诊断（只读 spirit_ai_data）----")
	for player in all_players:
		if player == null or not is_instance_valid(player):
			continue
		var who := str(player.char_data.get("name", "?"))
		var found := false
		for sad in sam.spirit_ai_data:
			if sad.get("player") != player:
				continue
			found = true
			var pool: Array = sad.get("skills_analysis", [])
			var pool_ids: Array[String] = []
			for info in pool:
				pool_ids.append(str(info.get("skill_id", "?")))
			var watched_in_pool: Array[String] = []
			for sid in WATCH_SKILLS:
				if sid in pool_ids:
					watched_in_pool.append(str(WATCH_SKILLS[sid]))
			var dump_line := ""
			if _dump_samples.has(str(player.name)):
				var sample: Dictionary = _dump_samples[str(player.name)]
				var last: Dictionary = sample["last"]
				var top3: Array = last.get("top3", [])
				var top3_str: Array[String] = []
				for t in top3:
					top3_str.append("%s:%s" % [str(t.get("skill_id", "?")), str(t.get("score", "?"))])
				dump_line = " | 末周期top3=[%s] 阈值%s (采样%d)" % [
					", ".join(top3_str) if not top3_str.is_empty() else "空",
					str(last.get("threshold", "?")), int(sample["count"])]
			print("[Probe] %s[%s] 决策%d次 能量%0.f/%0.f 池%d个 | 池内关注技: %s%s" % [
				who, str(player.team).to_upper(), int(sad.get("skill_decide_count", 0)),
				float(player.spirit_energy), float(player.max_spirit_energy), pool.size(),
				str(watched_in_pool) if not watched_in_pool.is_empty() else "无",
				dump_line])
			# 关注技能逐因子分解（全只读调用 AI 自身因子函数）——定位评分归零因子
			if not watched_in_pool.is_empty() and int(casts.size()) >= 0:
				for info in pool:
					var sid := str(info.get("skill_id", ""))
					if not WATCH_SKILLS.has(sid):
						continue
					var base := float(info.get("base_value", -1))
					var intent := float(sam._compute_intent_match(sad, info))
					var situ := float(sam._compute_situation_factor(sad, info))
					var stam := float(sam._compute_stamina_factor(sad, info))
					var timef := float(sam._compute_time_factor(sad, info))
					var comm := float(sam._compute_communication_factor(sad, info))
					var elem := float(sam._compute_element_factor(sad, info))
					var combo := float(sam._compute_combo_factor(sad, info))
					var teamf := float(sam._compute_team_factor(sad, info))
					var energy_ok: bool = sam._should_use_energy(sad, info, base * 10.0)
					var zeroed: Array[String] = []
					if base <= 0.0:
						zeroed.append("base_value")
					for pair in [["situation", situ], ["time", timef], ["comm", comm], ["element", elem], ["combo", combo], ["team", teamf]]:
						if float(pair[1]) <= 0.0:
							zeroed.append(str(pair[0]))
					if not energy_ok:
						zeroed.append("energy_gate")
					print("[Probe]   · %s: base=%0.1f intent=%0.2f situ=%0.2f stam=%0.2f time=%0.2f comm=%0.2f elem=%0.2f combo=%0.2f team=%0.2f energy_gate=%s%s" % [
						str(WATCH_SKILLS[sid]), base, intent, situ, stam, timef, comm, elem, combo, teamf,
						"过" if energy_ok else "拒",
						"  ←⚠归零因子: " + str(zeroed) if not zeroed.is_empty() else ""])
			break
		if not found:
			print("[Probe] %s[%s] ⚠ spirit_ai_data 无登记（技能AI未挂接该球员）" % [who, str(player.team).to_upper()])


func _dict_line(d: Dictionary) -> String:
	var parts: Array[String] = []
	for k in d:
		parts.append("%s×%d" % [str(k), int(d[k])])
	return " ".join(parts)


func _members_desc(members: Array) -> String:
	var parts: Array[String] = []
	for m in members:
		if m is Node and is_instance_valid(m):
			parts.append(str(m.char_data.get("name", m.name)))
		else:
			parts.append(str(m))
	return ", ".join(parts)


func _casts_line() -> String:
	if casts.is_empty():
		return "释放0"
	var parts: Array[String] = []
	for sid in casts:
		parts.append("%s×%d" % [str(WATCH_SKILLS.get(sid, sid)), int(casts[sid])])
	return "释放" + " ".join(parts)


func _marks_combo_line() -> String:
	return "印记%d(最高%d层) 合体%d" % [mark_events.size(), mark_max_stack, combo_formed_events.size()]


func _watch_detail() -> String:
	var parts: Array[String] = []
	for sid in WATCH_SKILLS:
		var count := int(casts.get(sid, 0))
		parts.append("%s×%d" % [str(WATCH_SKILLS[sid]), count])
	return "（" + " ".join(parts) + "）"
