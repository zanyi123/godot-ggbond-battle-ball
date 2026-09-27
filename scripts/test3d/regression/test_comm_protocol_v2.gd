## 17号通讯协议v2验收套件：负载化/开关单口/新消息/收端因子/纪律
## 覆盖：T1开关fail-closed、T2 post/过期/查询、T3敌队预警、T4 COMBO/预警消费因子、
##       T5 ai_manager/spirit_ai发送端接线存在性、R-纪律
## 运行：Godot_console.exe --headless --path . -s res://scripts/test3d/regression/test_comm_protocol_v2.gd
extends SceneTree

const CommScript = preload("res://scripts/battle/ai_communication.gd")
const SWITCHES_REAL := "res://data/systems/spirit_ai/switches.json"
const SWITCHES_TMP := "user://comm_v2_switches_tmp.json"

var _pass: int = 0
var _fail: int = 0


class StubPlayer extends CharacterBody2D:
	var character_id: String = "t_comm"
	var team: String = "a"
	var char_data: Dictionary = {"name": "测试员"}


class StubBattleManager extends Node2D:
	var comm_system = null


func _initialize() -> void:
	_run()


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		print("  ✗ " + name)


func _write_switches(content: String, comm) -> void:
	var f = FileAccess.open(SWITCHES_TMP, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	comm.reload_protocol_switch(SWITCHES_TMP)


func _run() -> void:
	print("\n========== 17号验收：通讯协议v2 ==========\n")
	for i in range(3):
		await process_frame

	var comm = CommScript.new()
	# spirit_ai_manager 引用 autoload（DataManager 等），须运行期 load（解析期 preload 早于 autoload 注册，02地基套件同款教训）
	var SamScript = load("res://scripts/battle/spirit_ai_manager.gd")

	# ===== T1 开关 fail-closed =====
	comm.reload_protocol_switch("user://__no_switches__.json")
	_check(not comm.protocol_v2_enabled, "T1a 开关文件缺失=关（fail-closed）")
	_write_switches("{ this is not json !!!", comm)
	_check(not comm.protocol_v2_enabled, "T1b 坏 JSON=关")
	_write_switches("{\"master_enabled\": true, \"waves\": {\"A\": true}, \"protocol_v2\": \"yes\"}", comm)
	_check(not comm.protocol_v2_enabled, "T1c protocol_v2 非布尔=关")
	_write_switches("{\"master_enabled\": true, \"protocol_v2\": true}", comm)
	_check(comm.protocol_v2_enabled, "T1d protocol_v2=true 开启")
	# 真实仓库文件默认必须为关（交付态）
	comm.reload_protocol_switch(SWITCHES_REAL)
	_check(not comm.protocol_v2_enabled, "T1e 仓库默认文件 protocol_v2=false（交付态）")

	# ===== T2 负载化 post/过期/查询（开关内）=====
	comm.elapsed_time = 100.0
	_write_switches("{\"protocol_v2\": true}", comm)
	var sender: StubPlayer = StubPlayer.new()
	sender.team = "a"
	var ok_post: bool = comm.post_message(sender, comm.MsgType.SKILL_READY,
			{"urgency": 0.8, "ttl": 5.0, "related_skill_id": "skill_x", "position": Vector2(11, 22)})
	_check(ok_post, "T2a post_message 成功")
	var active: Array[Dictionary] = comm.get_active_messages("a", comm.MsgType.SKILL_READY)
	_check(active.size() == 1 and str(active[0].get("related_skill_id", "")) == "skill_x" \
			and active[0].get("position") == Vector2(11, 22) and float(active[0].get("urgency", 0)) == 0.8,
			"T2b 负载四字段（urgency/ttl/position/related_skill_id）完整")
	_check(comm.is_type_active("a", comm.MsgType.SKILL_READY), "T2c is_type_active 命中")
	_check(comm.get_active_messages("b", comm.MsgType.SKILL_READY).is_empty(), "T2d 队伍隔离（b队查不到a队消息）")
	comm.elapsed_time = 106.0  # 越过 ttl=5s
	_check(comm.get_active_messages("a", comm.MsgType.SKILL_READY).is_empty(), "T2e 过期后查询为空（TTL 生效）")
	_check(comm.get_active_messages("a").is_empty(), "T2f 全类型查询同样过期即清")

	# ===== T3 敌队大招预警 =====
	comm.elapsed_time = 200.0
	comm.v2_messages.clear()
	var foe: StubPlayer = StubPlayer.new()
	foe.team = "b"
	comm.post_message(foe, comm.MsgType.ENEMY_ULT_WARNING, {"urgency": 0.9, "ttl": 4.0})
	_check(comm.is_enemy_ult_warning_hot("a"), "T3a a队可查到b队发出的敌大招预警")
	_check(not comm.is_enemy_ult_warning_hot("b"), "T3b 预警不惊动发出方自己的队伍")
	comm.elapsed_time = 205.0
	_check(not comm.is_enemy_ult_warning_hot("a"), "T3c 预警过期（ttl4s）后窗口关闭")

	# ===== T4 消费因子（spirit_ai_manager 通讯因子）=====
	comm.elapsed_time = 300.0
	comm.v2_messages.clear()
	comm.protocol_v2_enabled = true
	var sam = SamScript.new()
	sam.battle_manager = null
	var stub_p: StubPlayer = StubPlayer.new()
	_check(is_equal_approx(sam._compute_communication_factor({"player": stub_p}, {"intents": {}}), 1.0),
			"T4a battle_manager 空 → 因子恒1（fail-closed 不崩溃）")
	var fake_bm: StubBattleManager = StubBattleManager.new()
	fake_bm.comm_system = comm
	sam.battle_manager = fake_bm
	var atk_info: Dictionary = {"intents": {"attack": 0.8, "defense": 0.0, "support": 0.0, "control": 0.0}}
	var def_info: Dictionary = {"intents": {"attack": 0.0, "defense": 0.6, "support": 0.0, "control": 0.6}}
	comm.inject_message("a", comm.MsgType.COMBO_SETUP, {"ttl": 6.0})
	_check(is_equal_approx(sam._compute_communication_factor({"player": stub_p}, atk_info), 1.25),
			"T4b COMBO_SETUP 窗口内 attack 因子 ×1.25")
	comm.v2_messages.clear()
	comm.inject_message("b", comm.MsgType.ENEMY_ULT_WARNING, {"ttl": 4.0})
	_check(is_equal_approx(sam._compute_communication_factor({"player": stub_p}, def_info), 1.3),
			"T4c 敌大招预警窗口内 defense/control 因子 ×1.3")
	_check(is_equal_approx(sam._compute_communication_factor({"player": stub_p}, atk_info), 1.0),
			"T4d 预警不提升 attack、邀约不提升 defense（语义隔离）")
	comm.protocol_v2_enabled = false
	comm.v2_messages.clear()
	comm.inject_message("a", comm.MsgType.COMBO_SETUP, {"ttl": 6.0})  # 开关关=注入无效
	_check(is_equal_approx(sam._compute_communication_factor({"player": stub_p}, atk_info), 1.0),
			"T4e 开关关 → 消费因子恒1（inject 也被拦，单口一致）")

	# ===== T5 发送端/收端接线存在性（源码审计级）=====
	var sam_src: String = FileAccess.get_file_as_string("res://scripts/battle/spirit_ai_manager.gd")
	_check(sam_src.find("MsgType.COMBO_SETUP") != -1 and sam_src.find("MsgType.ENEMY_ULT_WARNING") != -1,
			"T5a spirit_ai 发送端已接 COMBO_SETUP/ENEMY_ULT_WARNING")
	var aim_src: String = FileAccess.get_file_as_string("res://scripts/battle/ai_manager.gd")
	_check(aim_src.find("SKILL_READY 接应走位") != -1 and aim_src.find("T5.4 补全") != -1,
			"T5b ai_manager 收端已接 SKILL_READY 走位/T5.4 敢进攻")

	# ===== R-纪律 =====
	var comm_src: String = FileAccess.get_file_as_string("res://scripts/battle/ai_communication.gd")
	# 旧文件既有 3 处 randf（_evaluate_single_ai 自动评估，02工单锚内既有、非本单范围）；v2 新增段零随机
	_check(comm_src.count("randf(") == 3,
			"R1 v2 新增段零随机（randf 计数维持既有3处，未新增）")

	print("\n========== 结果: %d/%d PASS ==========" % [_pass, _pass + _fail])
	if _fail > 0:
		print("❌ 有失败项")
	else:
		print("🎉 17号协议v2套件全部通过！")
	quit(1 if _fail > 0 else 0)
