extends RefCounted
## 工单37 操控标签演示剧本函数库（16 条）+ DemoRunner 状态机
## 剧本三要素（37号§一）：操作序列→占位表现→完成标志；每条 system_entry 抄 02 表「正确归类」原文标注真体系入口。
## 红线：演示控制器自实现输入，不接 input_manager/ssm（方案 B）；占位映射按工单映射表写死。
## headless 可推演：advance(kind,pos,dir)/tick(delta) 为纯状态接口，输入层只做事件翻译。

const DemoPlaceholder := preload("res://scripts/test3d/demo/demo_placeholder.gd")

## ===== 事件种类（输入层翻译后调用 advance） =====
const K_ACTIVATE := "activate"   # 按4：激活/再按
const K_PRESS := "press"         # 左键按下（拖长击开始）
const K_CONFIRM := "confirm"     # 左键确认（单击/松开）
const K_CANCEL := "cancel"       # 右键（cancel_demo 剧本吃掉；其余剧本=横切取消）
const K_SPACE := "space"         # 空格（迁移跳）
const K_AD := "ad"               # A/D 偏转（dir.x=+1/-1）
const K_SHAPE := "shape"         # Q：放置预览切矩形/圆形
const K_T := "t_key"             # T：合体/拆分
const K_E := "e_key"             # E：进出第一人称
const K_TAB := "tab"             # Tab：区域形状切换（19 OP_TRAIL；02表§4 Tab 分流语义）
const K_HOLD := "hold"           # H：OP_HOLD 维持键按住（主控轮询发，松开不发）

## ===== 占位模型 kind 快捷名（映射表断言用） =====
const M_SPHERE := "圆球"
const M_CUBE := "方块"
const M_STAR := "五角星"
const M_PAD := "贴地色块"
const M_LINE := "连线"
const M_COMBO := "组合体"

const K_SPHERE := 0   # DemoPlaceholder.Kind.SPHERE
const K_CUBE := 1
const K_STAR := 2
const K_PAD := 3
const K_LINE := 4
const K_COMBO := 5

## ===== 16 条剧本注册表（面板分组顺序=工单面板描述；行序=工单§一行序） =====
const GROUP_ORDER := ["自动", "瞄准选点", "标记", "引导飞行", "放置召唤", "切换跳跃", "合体FP", "时序横切", "已验收配方剧本"]

const SCRIPTS := [
	{"id": "auto", "group": "自动", "title": "1 OP_AUTO 自动", "model": M_SPHERE,
		"steps": "按技能键(4)→占位原地闪烁1s→消失", "done_text": "闪烁结束消失",
		"system_entry": "02表：蓄力=前摇不单列；按键激活即释放（无子态）"},
	{"id": "aim", "group": "瞄准选点", "title": "2 OP_AIM 瞄准", "model": M_SPHERE,
		"steps": "按4→瞄准态（鼠标方向瞄准线）→左键定方向→飞出", "done_text": "飞行结束（出界消失）",
		"system_entry": "02表3.1 左键单击：确定方向；3.5 方向控制"},
	{"id": "point", "group": "瞄准选点", "title": "3 OP_POINT 选点", "model": M_PAD,
		"steps": "按4→SELECTING→左键选场地点→贴地色块落点", "done_text": "落点完成",
		"system_entry": "02表3.1 左键单击：确定落点/释放点"},
	{"id": "mark", "group": "标记", "title": "4 OP_MARK 标记目标", "model": M_STAR,
		"steps": "按4→MARKING→左键选目标球员→五角星贴附2s", "done_text": "贴附后延时2s消失",
		"system_entry": "02表3.1 左键单击：选中对象（球员）"},
	{"id": "steer", "group": "引导飞行", "title": "5 OP_STEER 引导", "model": M_SPHERE,
		"steps": "按4→占位飞出→鼠标引导+A/D偏转→碰墙/超时/右键结束", "done_text": "受控飞行结束",
		"system_entry": "02表3.5 方向控制＋§1 按键迁移（大相机=左右键偏转增量）"},
	{"id": "midfly", "group": "引导飞行", "title": "6 OP_MIDFLY 飞行干预", "model": M_SPHERE,
		"steps": "按4→占位飞出→再按4=拉回/推进（3次受限）", "done_text": "干预次数尽+飞完",
		"system_entry": "02表3.1 继承；飞行中干预（弹性触手拉回/二段推进）"},
	{"id": "toggle", "group": "切换跳跃", "title": "7 OP_TOGGLE 开关", "model": M_CUBE,
		"steps": "按4→方块持续出现→再按4=关闭", "done_text": "一开一关循环",
		"system_entry": "02表§4 切换快捷键（技能状态切换=再按同键语义）"},
	{"id": "key_jump", "group": "切换跳跃", "title": "8 OP_KEY_JUMP 空格迁移", "model": M_SPHERE,
		"steps": "按4激活→按空格→占位跳起（不控球员）", "done_text": "跳跃落地",
		"system_entry": "02表§1 按键迁移：空格转移到技能（不可改基础标签物理量）"},
	{"id": "place", "group": "放置召唤", "title": "9 OP_PLACE 放置", "model": M_PAD + "+方块",
		"steps": "按4→贴地色块预览跟随鼠标（Q切矩形/圆形）→左键放置→转实体方块持续", "done_text": "放置完成（持续）",
		"system_entry": "02表3.1 左键单击：确定落点（放置类）"},
	{"id": "summon", "group": "放置召唤", "title": "10 OP_SUMMON 召唤", "model": M_SPHERE,
		"steps": "按4→召唤占位实体→左键点地下令移动→寿命尽消失", "done_text": "寿命尽消失",
		"system_entry": "02表3.1 左键单击（下令）＋操控单位（暗影分身/甲虫）"},
	{"id": "fp", "group": "合体FP", "title": "11 OP_FP 第一人称", "model": M_SPHERE,
		"trigger": "e_key",
		"steps": "按E进FP→准星瞄准→左键释放→占位沿准星飞出", "done_text": "出界消失",
		"system_entry": "02表§1 补充：第一视角只迁移左右移动键转视角"},
	{"id": "combo", "group": "合体FP", "title": "12 OP_COMBO 合体", "model": M_COMBO,
		"trigger": "t_key",
		"steps": "T键→双占位合体为增强占位→再按T拆分", "done_text": "合体→拆分循环",
		"system_entry": "02表§2 合体技能标志按键 T（必需一起才能释放）"},
	{"id": "multi_hit", "group": "时序横切", "title": "13 横切：再击(3.2)", "model": M_SPHERE + "→方块→五角星",
		"steps": "按4→第1段→再按4→第2段→再按4→第3段（每段形态变化）", "done_text": "三段走完",
		"system_entry": "02表3.2 左键再击（三段推进；进阶=确定方向）"},
	{"id": "drag", "group": "时序横切", "title": "14 横切：拖长击(3.3)", "model": M_LINE + "+五角星",
		"trigger": "enter_only",
		"steps": "左键按住开始拖动→吸附目标→松开 a对b作用", "done_text": "作用完成",
		"system_entry": "02表3.3 左键拖长击（按下选a→拖动吸附b→松开作用）"},
	{"id": "cancel_demo", "group": "时序横切", "title": "15 横切：右键取消(3.4)", "model": M_SPHERE,
		"trigger": "enter_only",
		"steps": "演示：瞄准中按右键=选错退回重来（占位回退→左键重选确认→走完）", "done_text": "回到激活态",
		"system_entry": "02表3.4 右键单击：取消选中对象（对全部剧本横切生效）"},
	{"id": "migrate", "group": "时序横切", "title": "16 横切：按键迁移(§1)", "model": M_SPHERE,
		"steps": "按4开操控窗→方向键(WASD/A,D)=占位移动 空格=占位跳→按4收窗", "done_text": "迁移响应可见",
		"system_entry": "02表§1 按键迁移（方向键+空格转移到技能，控占位不控球员）"},
	# —— 第 9 组：抽象参考标签（来源配方仅登记出处；平台演示=抽象动作无具体内容——02表口径，主人 10-20 裁） ——
	{"id": "whiteball_select", "group": "抽象参考标签", "title": "17 OP_SELECT 选择", "model": "可选对象+投影环",
		"steps": "按4进选择(光标隐藏,投影环替身)→悬停对象高亮(两种占位均可选)→左键单选→悬停敌(红)/队友(绿)→左键锁定→占位飞向目标(锁敌=作用 锁队友=交付)",
		"done_text": "选择链走完", "trigger": "activate",
		"system_entry": "配方登记：34号六步+配方5/6（演示=抽象选择动作，无具体技能）"},
	{"id": "shark_swim", "group": "抽象参考标签", "title": "18 OP_ORIENT 定向+翻转", "model": "定向占位(圆球)",
		"steps": "按4占位生成→鼠标定向自游(无WASD)→空格下沉/浮起翻转→触碰敌伤害+消失", "done_text": "触碰敌伤害",
		"trigger": "activate", "system_entry": "配方登记：配方8/9（演示=抽象定向动作，无具体技能）"},
	{"id": "fastlane_d14", "group": "抽象参考标签", "title": "19 OP_TRAIL 轨迹", "model": "贴地区域(四形)+占位",
		"steps": "按4以球员为锚预览区域(矩形=球员站宽边)→Tab=切形状(矩形/扇形/环形/圆形)→左键铺开→占位入区域增速", "done_text": "入区域增速走完",
		"trigger": "activate", "system_entry": "配方登记：配方10/D14（演示=抽象轨迹动作，无具体技能）"},
	{"id": "guide_ball", "group": "抽象参考标签", "title": "20 OP_GUIDE 制导", "model": M_SPHERE + "(手动态)",
		"steps": "按4发占位球→W=球朝鼠标移动 A,D=偏转双源控制→再按4=收回", "done_text": "双源制导走完",
		"trigger": "activate", "system_entry": "配方登记：操1 §1 双源/波6#17（演示=抽象制导动作，无具体技能）"},
	{"id": "firework_use", "group": "抽象参考标签", "title": "21 OP_TRANSFORM 形态变换", "model": "形态占位(A/B)",
		"steps": "按4生成形态A(待用态方块)→Q=变形态B(圆球)→触碰敌生效→恢复形态A", "done_text": "形态变换走完",
		"trigger": "activate", "system_entry": "配方登记：35号2b（演示=抽象形态变换动作，无具体技能）"},
	{"id": "hold_aura", "group": "抽象参考标签", "title": "23 OP_HOLD 维持", "model": "维持占位(光环)",
		"steps": "按4生成维持占位→按住 H 维持(倒计时刷新)→松开倒计时衰减→归零消散", "done_text": "维持结束",
		"trigger": "activate", "system_entry": "38号§7·五 扩展口①（维持键刷新倒计时——交互刷新先例，无具体技能）"},
	{"id": "fp_whiteball", "group": "抽象参考标签", "title": "22 FP_SELECT 准星选择", "model": "FP准星+可选对象",
		"steps": "按4进FP→准星对准对象(高亮)→左键单选→准星对准敌(红)/队友(绿)→左键锁定→占位飞向目标 E=退出", "done_text": "FP 选择链走完",
		"trigger": "activate", "system_entry": "配方登记：35号S3（演示=第一视角选择变体，无具体技能）"},
]


class Runner:
	## 剧本运行器：主控持有一个，headless 套件可直接推演
	## env: {tester, buddy, parent, half_x, half_z, platform}

	var env: Dictionary = {}
	var script_id := ""
	var phase := "idle"
	var hint := ""
	var done := false
	var t := 0.0
	var counter := 0
	var mouse := Vector3.ZERO          # 主控每帧写入（鼠标地面点）
	var keep: Array[Node] = []         # 本剧本产物（切换清场用）
	var flags: Dictionary = {}
	var ph = null                      # 主占位
	var ph2 = null                     # 副占位

	func setup(p_env: Dictionary) -> void:
		env = p_env
		hint = "面板点选标签装载技能栏 → 按 4/5/6 触发演示"

	func find_script() -> Dictionary:
		for s in SCRIPTS:
			if str(s.get("id")) == script_id:
				return s
		return {}

	## 修1：剧本触发键（缺省=技能键 activate；combo=T/fp=E/拖长击与右键取消=仅进入就绪态）
	func trigger_of(id: String) -> String:
		for s in SCRIPTS:
			if str(s.get("id")) == id:
				return str(s.get("trigger", "activate"))
		return "activate"

	## 修3：占位触碰敌方命中（距陪衬<32=命中：扣血+占位消失+完成）
	func _flight_hit(ph) -> bool:
		if ph == null:
			return false
		var bd: Node3D = env.get("buddy")
		if bd == null:
			return false
		var d: Vector3 = ph.position - bd.global_position
		d.y = 0.0
		if d.length() < 32.0:
			bd.call("take_hit", 10)
			ph.call("vanish")
			_finish("命中敌方！体力-10（状态栏可见）")
			return true
		return false

	## 面板点选/测试切换：清场进入
	func switch_to(id: String) -> void:
		clear_script()
		script_id = id
		phase = "idle"
		done = false
		counter = 0
		t = 0.0
		flags = {}
		var def := find_script()
		hint = str(def.get("steps", "")) if not def.is_empty() else "未知剧本"
		if id == "cancel_demo":
			# 15号横切：自动进入瞄准前半（生成占位+瞄准线），等右键
			phase = "aim_pre"
			ph = _spawn(K_SPHERE, {"color": Color(0.55, 0.7, 1.0)})
			ph.position = _tester_pos() + Vector3(0, 0, -50)
			ph2 = _spawn(K_LINE, {"color": Color(0.55, 0.7, 1.0)})
			hint = "瞄准进行中…按右键→取消回退（3.4）"

	## 全清（右键横切取消/切换剧本）
	func clear_script() -> void:
		for n in keep:
			if is_instance_valid(n):
				n.call("vanish", false)
		keep.clear()
		ph = null
		ph2 = null
		flags = {}

	## 横切取消：任意激活剧本右键→清场回空闲（15号横切对全部剧本生效）
	func cancel() -> void:
		if phase == "idle":
			return
		var was := script_id
		clear_script()
		phase = "idle"
		if was != "cancel_demo":
			hint = "已右键取消——占位回退/选择清空，演示回空闲（要重试请再按技能键）"
		else:
			hint = "✓ 完成：" + str(find_script().get("done_text", ""))
			done = true

	func is_busy() -> bool:
		return phase != "idle"

	## ===== 事件入口 =====
	func advance(kind: String, pos: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO) -> Dictionary:
		if pos.length_squared() > 0.01:
			mouse = pos
		if script_id == "":
			return result()
		# 15号横切：非 cancel_demo 剧本激活中右键=统一取消；cancel_demo 自己吃右键
		if kind == K_CANCEL and script_id != "cancel_demo":
			if phase != "idle":
				cancel()
			return result()
		var def := find_script()
		if def.is_empty():
			return result()
		var fn := "_adv_" + script_id
		# C9 双变体（38号批4 消费：ctl_input_view_mode）：OP_SELECT 模板 fp_cross=FP 准星变体（同 id 参数共享）
		if script_id == "whiteball_select" and str(tpl("ctl_input_view_mode", "camera")) == "fp_cross":
			fn = "_adv_fp_whiteball"
		if has_method(fn):
			call(fn, kind, pos, dir)
		return result()

	func tick(delta: float) -> Dictionary:
		if script_id != "" and phase != "idle":
			var fn := "_tick_" + script_id
			# C9 双变体转发（同上：view_mode=fp_cross）
			if script_id == "whiteball_select" and str(tpl("ctl_input_view_mode", "camera")) == "fp_cross":
				fn = "_tick_fp_whiteball"
			if has_method(fn):
				call(fn, delta)
		return result()

	func result() -> Dictionary:
		return {"done": done, "phase": phase, "hint": hint, "script": script_id}

	## 38号出口：读当前操控模板参数（env.template=工作台编辑副本引用——调参即时生效）
	func tpl(key: String, def: Variant = null) -> Variant:
		var t: Dictionary = env.get("template", {})
		if t.has(key):
			return t.get(key)
		return def

	## 批2 参数化助手：模板占位色（color+alpha 合成）/占位缩放
	func tcol(def: String) -> Color:
		var c := Color.html(str(tpl("ctl_visual_color", def)))
		c.a = float(tpl("ctl_visual_alpha", 1.0))
		return c

	func tsc() -> float:
		return float(tpl("ctl_visual_scale", 1.0))

	## ===== 工具 =====
	func _spawn(p_kind: int, p_params: Dictionary = {}, with_model: bool = false):
		var node = DemoPlaceholder.new()
		env.parent.add_child(node)
		node.setup(p_kind, p_params)
		# 38号批4 消费：ctl_visual_model_path/scale/rot/offset（25号闸门：模型到位自动替换占位）
		if with_model:
			var mp := str(tpl("ctl_visual_model_path", ""))
			if mp != "" and bool(tpl("_model_ok", false)):
				var off: Dictionary = tpl("ctl_visual_offset", {"x": 0.0, "y": 0.0})
				node.call("apply_model", mp, float(tpl("ctl_visual_scale", 1.0)), float(tpl("ctl_visual_rot", 0.0)), Vector3(float(off.get("x", 0.0)), 0.0, float(off.get("y", 0.0))))
		# 38号批4 消费：ctl_time_enter_fx 出现方式
		node.call("set_enter_fx", str(tpl("ctl_time_enter_fx", "instant")))
		keep.append(node)
		return node

	func _tester_pos() -> Vector3:
		var tster: Node3D = env.get("tester")
		return tster.global_position if tster != null else Vector3.ZERO

	func _buddy_pos() -> Vector3:
		var bd: Node3D = env.get("buddy")
		return bd.global_position if bd != null else Vector3(160, 0, 0)

	func _out_of_bounds(p: Vector3) -> bool:
		return absf(p.x) > float(env.half_x) + 40.0 or absf(p.z) > float(env.half_z) + 40.0

	func _finish(msg: String) -> void:
		done = true
		hint = "✓ 完成：" + msg
		phase = "idle"

	## ===== 1 auto =====
	func _adv_auto(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph = _spawn(K_SPHERE, {"color": tcol("#66CCFF")})
			ph.position = _tester_pos() + Vector3(0, 0, -45)
			var show: float = float(tpl("ctl_time_preview_show", 1.0))
			ph.call("pulse", show)
			phase = "flashing"
			t = show
			hint = "占位闪烁中…"

	func _tick_auto(delta: float) -> void:
		if phase == "flashing":
			t -= delta
			if t <= 0.0 and ph != null:
				ph.call("vanish")
				_finish(str(find_script().get("done_text", "")))

	## ===== 2 aim =====
	func _adv_aim(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph2 = _spawn(K_LINE, {"color": tcol("#66CCFF")})
			phase = "aiming"
			hint = "瞄准态：移动鼠标选方向（瞄准线），左键定方向"
		elif kind == K_CONFIRM and phase == "aiming":
			var d: Vector3 = mouse - _tester_pos()
			d.y = 0.0
			if d.length_squared() < 4.0:
				d = Vector3(0, 0, -1)
			d = d.normalized()
			if ph2 != null:
				ph2.call("vanish")
				ph2 = null
			ph = _spawn(K_SPHERE, {"color": Color(0.4, 0.8, 1.0)})
			ph.position = _tester_pos() + d * 30.0
			flags["fly_dir"] = d
			flags["speed"] = 420.0
			phase = "flying"
			hint = "占位沿方向飞出…"

	func _tick_aim(delta: float) -> void:
		if phase == "aiming" and ph2 != null:
			ph2.call("set_line", _tester_pos() + Vector3(0, 26, 0), mouse + Vector3(0, 2, 0))
		elif phase == "flying" and ph != null:
			ph.position += (flags.get("fly_dir", Vector3(0, 0, -1)) as Vector3) * float(flags.get("speed", 420.0)) * delta
			if _flight_hit(ph):
				return
			if _out_of_bounds(ph.position):
				ph.call("vanish")
				_finish(str(find_script().get("done_text", "")))

	## ===== 3 point =====
	func _adv_point(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph = _spawn(K_PAD, {"shape": "circle", "radius": 46.0, "translucent": true})
			phase = "selecting"
			hint = "SELECTING：左键选场地点（圆圈跟随鼠标）"
		elif kind == K_CONFIRM and phase == "selecting":
			ph.call("vanish")
			ph = null
			ph2 = _spawn(K_PAD, {"shape": "circle", "radius": 46.0, "color": tcol("#4DFF99")})
			ph2.position = Vector3(mouse.x, 0, mouse.z)
			phase = "placed"
			t = 1.5
			hint = "落点指示已放置…"

	func _tick_point(delta: float) -> void:
		if phase == "selecting" and ph != null:
			ph.position = Vector3(mouse.x, 0, mouse.z)
		elif phase == "placed":
			t -= delta
			if t <= 0.0:
				if ph2 != null:
					ph2.call("vanish")
				_finish(str(find_script().get("done_text", "")))

	## ===== 4 mark =====
	func _adv_mark(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			phase = "marking"
			hint = "MARKING：左键选目标球员（陪衬）"
		elif kind == K_CONFIRM and phase == "marking":
			# 3.1 选中对象（球员）：鼠标点谁贴谁（取地面点最近球员）
			var bd: Node3D = env.get("buddy")
			var ts: Node3D = env.get("tester")
			var tgt: Node3D = bd
			if ts != null and bd != null:
				var gp: Vector3 = Vector3(mouse.x, 0, mouse.z)
				tgt = ts if gp.distance_to(ts.global_position) < gp.distance_to(bd.global_position) else bd
			var sym := str(tpl("ctl_visual_mark_symbol", "star"))
			if sym == "star":
				ph = _spawn(K_STAR, {"color": Color(1.0, 0.85, 0.2)})
			else:
				# F3（主人批"可以"）：真符号牌模型=item_visual_3d 三件套（锅/药/烟花，25号真模型 fail-closed 自带符号标签）
				ph = _spawn(K_SPHERE, {"color": Color(1.0, 0.85, 0.2), "radius": 14.0})
				var sym_id: String = {"pan": "fenny_pan", "potion": "fenny_potion", "firework": "fenny_firework"}.get(sym, "fenny_pan")
				var sym_vis = load("res://scripts/battle3d/visual/item_visual_3d.gd").new()
				sym_vis.setup(sym_id)
				ph.add_child(sym_vis)
			ph.call("attach_to", tgt, Vector3(0, 75, 0))
			tgt.call("take_hit", 10)
			phase = "attached"
			t = 2.0
			hint = "五角星已贴附%s！命中：体力-10（状态栏可见）" % ("测试者" if tgt == ts else "陪衬")

	func _tick_mark(delta: float) -> void:
		if phase == "attached":
			t -= delta
			if t <= 0.0 and ph != null:
				ph.call("vanish")
				_finish(str(find_script().get("done_text", "")))

	## ===== 5 steer =====
	func _adv_steer(kind: String, _pos: Vector3, dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph = _spawn(K_SPHERE, {"color": tcol("#9999FF")})
			ph.position = _tester_pos() + Vector3(0, 0, -40)
			var d: Vector3 = mouse - _tester_pos()
			d.y = 0.0
			flags["yaw"] = atan2(-d.x, -d.z) if d.length_squared() > 4.0 else 0.0
			flags["speed"] = 300.0
			t = 8.0
			phase = "flying"
			hint = "受控飞行：鼠标引导 + A/D 偏转；碰墙/超时/右键结束"
		elif kind == K_AD and phase == "flying":
			flags["yaw"] = float(flags.get("yaw", 0.0)) + dir.x * 2.2 * 0.016
			hint = "偏转中（A/D）…"

	func _tick_steer(delta: float) -> void:
		if phase != "flying" or ph == null:
			return
		var yaw := float(flags.get("yaw", 0.0))
		if mouse.length_squared() > 1.0:
			var d: Vector3 = mouse - ph.position
			d.y = 0.0
			if d.length_squared() > 25.0:
				var target_yaw := atan2(-d.x, -d.z)
				yaw = lerp_angle(yaw, target_yaw, minf(2.5 * delta, 1.0))
				flags["yaw"] = yaw
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		ph.position += fwd * float(flags.get("speed", 300.0)) * delta
		t -= delta
		if _flight_hit(ph):
			return
		if _out_of_bounds(ph.position):
			ph.call("vanish")
			_finish("✓ 碰墙结束（受控飞行）")
		elif t <= 0.0:
			ph.call("vanish")
			_finish(str(find_script().get("done_text", "")))

	## ===== 6 midfly =====
	func _adv_midfly(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			var d: Vector3 = mouse - _tester_pos()
			d.y = 0.0
			if d.length_squared() < 4.0:
				d = Vector3(0, 0, -1)
			flags["vel"] = d.normalized() * 380.0
			ph = _spawn(K_SPHERE, {"color": tcol("#80FFD9")})
			ph.position = _tester_pos() + d.normalized() * 30.0
			counter = 3
			t = 9.0
			phase = "flying"
			hint = "占位飞出。再按4=拉回/推进（剩 3 次）"
		elif kind == K_ACTIVATE and phase == "flying":
			if counter > 0:
				counter -= 1
				var back := (counter % 2 == 0)
				var to_self: Vector3 = (_tester_pos() - ph.position)
				to_self.y = 0.0
				var d2: Vector3 = to_self.normalized() if to_self.length_squared() > 1.0 else Vector3(0, 0, 1)
				flags["vel"] = (d2 if back else -d2) * (240.0 if back else 560.0)
				hint = "干预（%s）！剩 %d 次" % ["拉回" if back else "推进", counter]
			else:
				hint = "干预次数已尽，飞行至结束"

	func _tick_midfly(delta: float) -> void:
		if phase != "flying" or ph == null:
			return
		ph.position += (flags.get("vel", Vector3.ZERO) as Vector3) * delta
		t -= delta
		if _flight_hit(ph):
			return
		if _out_of_bounds(ph.position) or t <= 0.0:
			ph.call("vanish")
			_finish(str(find_script().get("done_text", "")))

	## ===== 7 toggle =====
	func _adv_toggle(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph = _spawn(K_CUBE, {"size": 34.0, "color": tcol("#66FF80")})
			ph.position = _tester_pos() + Vector3(0, 0, -60)
			phase = "on"
			hint = "方块持续存在。再按4=关闭"
		elif kind == K_ACTIVATE and phase == "on":
			ph.call("vanish")
			_finish(str(find_script().get("done_text", "")))

	func _tick_toggle(_delta: float) -> void:
		pass

	## ===== 8 key_jump =====
	func _adv_key_jump(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph = _spawn(K_SPHERE, {"color": tcol("#CC8CFF")})
			ph.position = _tester_pos() + Vector3(45, 0, 0)
			phase = "active"
			hint = "操控窗激活：按空格→占位跳起（迁移语义）"
		elif kind == K_SPACE and phase == "active":
			var tw: Tween = ph.create_tween()
			tw.tween_property(ph, "position:y", 100.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(ph, "position:y", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			phase = "jumping"
			t = 0.6
			hint = "占位跳起中（球员未动=迁移语义可见）…"

	func _tick_key_jump(delta: float) -> void:
		if phase == "jumping":
			t -= delta
			if t <= 0.0:
				_finish(str(find_script().get("done_text", "")) + "（球员未动）")

	## ===== 9 place =====
	func _adv_place(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph = _spawn(K_PAD, {"shape": "rect", "w": 140.0, "h": 90.0, "translucent": true})
			phase = "preview"
			hint = "预览跟随鼠标。Q=切矩形/圆形，左键=放置"
		elif kind == K_SHAPE and phase == "preview":
			var circle := not bool(flags.get("circle", false))
			flags["circle"] = circle
			ph.call("vanish")
			ph = _spawn(K_PAD, {"shape": "circle" if circle else "rect", "radius": 70.0, "w": 140.0, "h": 90.0, "translucent": true})
			hint = "预览形状=%s。左键=放置" % ("圆形" if circle else "矩形")
		elif kind == K_CONFIRM and phase == "preview":
			ph.call("vanish")
			ph = null
			ph2 = _spawn(K_CUBE, {"size": 36.0, "color": tcol("#FF9940")})
			ph2.position = Vector3(mouse.x, 0, mouse.z)
			_finish(str(find_script().get("done_text", "")) + "（实体方块持续存在，切剧本才清场）")

	func _tick_place(delta: float) -> void:
		if phase == "preview" and ph != null:
			ph.position = Vector3(mouse.x, 0, mouse.z)

	## ===== 10 summon =====
	func _adv_summon(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph = _spawn(K_SPHERE, {"color": tcol("#4DF2E6"), "radius": 16.0 * tsc()})
			ph.position = _tester_pos() + Vector3(-45, 0, 0)
			phase = "spawned"
			hint = "召唤实体已出现。左键点地=下令移动"
		elif kind == K_CONFIRM and phase == "spawned":
			flags["dest"] = Vector3(mouse.x, 0, mouse.z)
			phase = "moving"
			hint = "受令移动中…"

	func _tick_summon(delta: float) -> void:
		if phase == "moving" and ph != null:
			var dest := flags.get("dest", Vector3.ZERO) as Vector3
			var d: Vector3 = dest - ph.position
			d.y = 0.0
			if d.length() < 10.0:
				phase = "alive"
				t = 5.0
				hint = "已到达。寿命倒计时 5s…"
			else:
				ph.position += d.normalized() * minf(200.0 * delta, d.length())
		elif phase == "alive":
			t -= delta
			if t <= 0.0 and ph != null:
				ph.call("vanish")
				_finish(str(find_script().get("done_text", "")))

	## ===== 11 fp =====
	func _adv_fp(kind: String, _pos: Vector3, dir: Vector3) -> void:
		if kind == K_E and phase == "idle":
			env.platform.call("enter_fp", true)
			phase = "fp"
			hint = "FP 第一人称：准星瞄准，左键释放（E 退出）"
		elif kind == K_CONFIRM and phase == "fp":
			env.platform.call("enter_fp", false)
			var d: Vector3 = dir if dir.length_squared() > 0.01 else Vector3(0, 0, -1)
			ph = _spawn(K_SPHERE, {"color": tcol("#FF80CC")})
			ph.position = _tester_pos() + Vector3(0, 46, 0) + d.normalized() * 30.0
			flags["vel"] = d.normalized() * 520.0
			phase = "flying"
			hint = "占位沿准星方向飞出…"
		elif kind == K_E and phase == "fp":
			env.platform.call("enter_fp", false)
			phase = "idle"
			hint = "已退出 FP（未释放）"

	func _tick_fp(delta: float) -> void:
		if phase == "flying" and ph != null:
			ph.position += (flags.get("vel", Vector3.ZERO) as Vector3) * delta
			if _flight_hit(ph):
				return
			if _out_of_bounds(ph.position):
				ph.call("vanish")
				_finish(str(find_script().get("done_text", "")))

	## ===== 12 combo =====
	func _adv_combo(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_T and phase == "idle":
			ph = _spawn(K_SPHERE, {"color": tcol("#FFD94D"), "radius": 13.0 * tsc()})
			ph.position = _tester_pos() + Vector3(0, 26, 0)
			ph2 = _spawn(K_SPHERE, {"color": Color(1.0, 0.85, 0.3), "radius": 13.0})
			ph2.position = _buddy_pos() + Vector3(0, 26, 0)
			var mid := (_tester_pos() + _buddy_pos()) * 0.5
			ph.call("move_to", mid + Vector3(0, 26, 0), 0.8)
			ph2.call("move_to", mid + Vector3(0, 26, 0), 0.8)
			phase = "merging"
			t = 0.85
			hint = "双占位合体中…"
		elif kind == K_T and phase == "merged":
			ph.call("vanish")
			var a = _spawn(K_SPHERE, {"color": Color(1.0, 0.85, 0.3), "radius": 11.0})
			var b = _spawn(K_SPHERE, {"color": Color(1.0, 0.85, 0.3), "radius": 11.0})
			a.call("attach_to", env.get("tester"), Vector3(0, 40, 0))
			b.call("attach_to", env.get("buddy"), Vector3(0, 40, 0))
			ph = a
			ph2 = b
			phase = "split_fade"
			t = 1.0
			hint = "拆分回位…"

	func _tick_combo(delta: float) -> void:
		if phase == "merging":
			t -= delta
			if t <= 0.0:
				if ph != null:
					ph.call("vanish", false)
				if ph2 != null:
					ph2.call("vanish", false)
				ph = _spawn(K_COMBO, {"color": Color(1.0, 0.8, 0.15), "radius": 22.0})
				ph.position = (_tester_pos() + _buddy_pos()) * 0.5
				phase = "merged"
				hint = "增强占位已合体！再按 T=拆分"
		elif phase == "split_fade":
			t -= delta
			if t <= 0.0:
				if ph != null:
					ph.call("vanish")
				if ph2 != null:
					ph2.call("vanish")
				_finish(str(find_script().get("done_text", "")))

	## ===== 13 multi_hit 再击 =====
	func _adv_multi_hit(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind != K_ACTIVATE:
			return
		match phase:
			"idle":
				counter = 1
				ph = _spawn(K_SPHERE, {"color": Color(0.9, 0.6, 1.0), "radius": 10.0})
				ph.position = _tester_pos() + Vector3(0, 0, -50)
				phase = "stage2_ready"
				hint = "第1段（小圆球）。再按4→第2段"
			"stage2_ready":
				ph.call("vanish", false)
				ph = _spawn(K_CUBE, {"size": 30.0, "color": Color(0.7, 0.6, 1.0)})
				ph.position = _tester_pos() + Vector3(0, 0, -70)
				phase = "stage3_ready"
				counter = 2
				hint = "第2段（方块）。再按4→第3段"
			"stage3_ready":
				ph.call("vanish", false)
				ph = _spawn(K_STAR, {"color": Color(1.0, 0.75, 0.3)})
				ph.position = _tester_pos() + Vector3(0, 0, -90)
				ph.call("pulse", 0.6)
				phase = "final"
				t = 0.8
				counter = 3
				hint = "第3段（五角星爆发）…"

	func _tick_multi_hit(delta: float) -> void:
		if phase == "final":
			t -= delta
			if t <= 0.0 and ph != null:
				ph.call("vanish")
				_finish(str(find_script().get("done_text", "")) + "（圆球→方块→五角星）")

	## ===== 14 drag 拖长击 =====
	func _adv_drag(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_PRESS and phase == "idle":
			ph = _spawn(K_LINE, {"color": Color(1.0, 0.45, 0.45)})
			phase = "dragging"
			flags["snap"] = false
			hint = "拖动中：线端吸附目标球员（近了会亮）→松开"
		elif kind == K_CONFIRM and phase == "dragging":
			var bd: Node3D = env.get("buddy")
			var snap_now: bool = bd != null and Vector3(mouse.x, 0, mouse.z).distance_to(bd.global_position) < 60.0
			if not snap_now:
				ph.call("vanish")
				phase = "idle"
				hint = "未吸附目标，已取消（3.3 需拖到 b 身上/附近）"
				return
			ph2 = _spawn(K_STAR, {"color": Color(1.0, 0.85, 0.2)})
			ph2.call("attach_to", bd, Vector3(0, 75, 0))
			ph2.call("pulse", 1.0)
			bd.call("take_hit", 10)
			hint = "a对b 作用中！命中：体力-10（状态栏可见）"
			phase = "acting"
			t = 1.2
			hint = "a对b 作用中（连线+五角星）…"

	func _tick_drag(delta: float) -> void:
		if phase == "dragging" and ph != null:
			var a := _tester_pos() + Vector3(0, 30, 0)
			var b := Vector3(mouse.x, 0, mouse.z)
			var bd: Node3D = env.get("buddy")
			var snap: bool = bd != null and Vector3(b.x, 0, b.z).distance_to(bd.global_position) < 60.0
			flags["snap"] = snap
			ph.call("set_line", a, bd.global_position + Vector3(0, 30, 0) if snap else b + Vector3(0, 2, 0))
			ph.call("set_highlight", snap)
		elif phase == "acting":
			t -= delta
			if t <= 0.0:
				if ph != null:
					ph.call("vanish")
				if ph2 != null:
					ph2.call("vanish")
				_finish(str(find_script().get("done_text", "")))

	## ===== 15 cancel_demo =====
	func _adv_cancel_demo(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		# advance 已把非本剧本的 cancel 横切走；这里只接本剧本自己的右键/确认
		# 3.4 键位表口径：右键=取消选中（占位回退），子态保留可重选
		if kind == K_CANCEL and phase == "aim_pre":
			# 取消可见化：占位回退消散（0.25s 动画）→0.6s 空档→再出重选占位
			clear_script()
			phase = "rewind"
			t = 0.6
			hint = "已取消选中！占位回退消散…（3.4 子态保留，稍候可重选）"
		elif kind == K_CONFIRM and phase == "aim_pre":
			var d: Vector3 = mouse - _tester_pos()
			d.y = 0.0
			if d.length_squared() < 4.0:
				d = Vector3(0, 0, -1)
			d = d.normalized()
			if ph2 != null:
				ph2.call("vanish")
				ph2 = null
			if ph != null:
				ph.call("vanish", false)
			ph = _spawn(K_SPHERE, {"color": Color(0.55, 0.7, 1.0)})
			ph.position = _tester_pos() + d * 30.0
			flags["fly_dir"] = d
			phase = "flying"
			hint = "重选确认→占位沿方向飞出…"

	func _tick_cancel_demo(delta: float) -> void:
		if phase == "rewind":
			t -= delta
			if t <= 0.0:
				phase = "aim_pre"
				ph = _spawn(K_SPHERE, {"color": Color(0.55, 0.7, 1.0)})
				ph.position = _tester_pos() + Vector3(0, 0, -50)
				ph2 = _spawn(K_LINE, {"color": Color(0.55, 0.7, 1.0)})
				hint = "选择已清空（子态保留）：左键重新确认目标 / 右键再取消"
		elif phase == "aim_pre" and ph2 != null:
			ph2.call("set_line", _tester_pos() + Vector3(0, 26, 0), mouse + Vector3(0, 2, 0))
		elif phase == "flying" and ph != null:
			ph.position += (flags.get("fly_dir", Vector3(0, 0, -1)) as Vector3) * 420.0 * delta
			if _out_of_bounds(ph.position):
				ph.call("vanish")
				_finish(str(find_script().get("done_text", "")) + "（取消→重选→确认全链通）")

	## ===== 16 migrate 按键迁移 =====
	func _adv_migrate(kind: String, _pos: Vector3, dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph = _spawn(K_SPHERE, {"color": Color(0.95, 0.95, 0.95)})
			ph.position = _tester_pos() + Vector3(0, 0, -50)
			phase = "active"
			hint = "操控窗开：空格=占位跳，A/D=占位偏转，按4=收窗"
		elif kind == K_SPACE and phase == "active":
			var tw: Tween = ph.create_tween()
			tw.tween_property(ph, "position:y", 100.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(ph, "position:y", 0.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			flags["jumped"] = true
			hint = "迁移跳（占位跳、球员不动）"
		elif kind == "move" and phase == "active":
			# 02表§1：移动方向键迁移到技能——占位随方向键移动（球员不动）
			var md: Vector3 = dir if dir.length_squared() > 0.01 else Vector3(0, 0, -1)
			ph.position += md.normalized() * 5.0
			flags["moved"] = true
			hint = "迁移移动中（方向键控占位，球员未动）…"
		elif kind == K_ACTIVATE and phase == "active":
			ph.call("vanish")
			var detail := "空格跳+方向键移动可见" if bool(flags.get("moved", false)) else "空格跳可见"
			_finish(str(find_script().get("done_text", "")) + "（" + detail + "）")

	func _tick_migrate(_delta: float) -> void:
		pass

	## ===== 17 OP_SELECT 选择（抽象：可选对象+类型环） =====
	func _adv_whiteball_select(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			var delay: float = float(tpl("ctl_time_spawn_delay", 0.0))
			if delay > 0.02:
				flags["delay"] = delay
				phase = "delay_spawn"
				t = delay
				hint = "占位出现延时中（ctl_time_spawn_delay=%.2fs）…" % delay
				return
			_spawn_select_set()
			phase = "selecting"
			hint = "选择模式：光标隐藏（投影环替身）→悬停对象高亮（两种占位均可选）→左键单选"
		elif kind == K_CONFIRM and phase == "selecting":
			var b: Dictionary = _hover_ball()
			if b.is_empty():
				hint = "未悬停到对象（移动鼠标到可选对象上）"
				return
			flags["picked"] = b
			(b.get("node")).call("set_highlight", true)
			phase = "choosing_target"
			hint = "已单选（高亮锁定）→悬停敌（红框）/队友（绿框）→左键锁定"
		elif kind == K_CONFIRM and phase == "choosing_target":
			var tgt: Node3D = _hover_actor()
			if tgt == null:
				hint = "悬停到敌（红框）/队友（绿框）再锁定"
				return
			flags["target"] = tgt
			if flags.has("tgt_ring"):
				flags["tgt_ring"].call("vanish")
				flags.erase("tgt_ring")
			var picked0: Dictionary = flags.get("picked", {})
			var n0: Node3D = picked0.get("node")
			var d: Vector3 = tgt.global_position - n0.position
			d.y = 0.0
			flags["fly_dir"] = d.normalized()
			phase = "flying"
			hint = "占位飞向目标…"

	func _spawn_whiteball(pos: Vector3, ring_kind: String):
		var hover_y: float = float(tpl("ctl_visual_hover_y", 75.0))
		var alpha: float = float(tpl("ctl_visual_alpha", 0.45))
		var wb = _spawn(K_SPHERE, {"color": Color(0.95, 0.95, 0.95), "radius": 12.0}, true)
		wb.position = Vector3(pos.x, maxf(hover_y - 26.0, 0.0), pos.z)   # 球心=模板悬浮高
		var ring = _spawn(K_PAD, {"shape": "circle", "radius": 20.0, "translucent": true,
			"color": Color(0.3, 0.6, 1.0) if ring_kind == "att" else Color(0.3, 1.0, 0.5)})
		ring.position = pos
		if ring.mat != null:
			ring.mat.albedo_color.a = alpha
		return wb

	func _hover_ball() -> Dictionary:
		var snap: float = float(tpl("ctl_input_hover_snap", 120.0))
		var best: Dictionary = {}
		var best_d: float = snap
		for b in flags.get("balls", []):
			var n: Node3D = b.get("node")
			if n != null:
				var gp: Vector3 = Vector3(mouse.x, 0, mouse.z)
				var dd: float = gp.distance_to(n.position)
				if dd < best_d:
					best_d = dd
					best = b
		return best

	func _hover_actor() -> Node3D:
		var lock: float = float(tpl("ctl_input_lock_snap", 150.0))
		var gp: Vector3 = Vector3(mouse.x, 0, mouse.z)
		var bd: Node3D = env.get("buddy")
		var ts: Node3D = env.get("tester")
		var best: Node3D = null
		var best_d: float = lock
		if bd != null and gp.distance_to(bd.global_position) < best_d:
			best = bd
			best_d = gp.distance_to(bd.global_position)
		if ts != null and gp.distance_to(ts.global_position) < best_d:
			best = ts
		return best

	func _spawn_select_set() -> void:
		var ring_col := Color.html(str(tpl("ctl_visual_color", "#50D4FFE0")))
		var alpha: float = float(tpl("ctl_visual_alpha", 0.45))
		ring_col.a = alpha
		flags["balls"] = [
			{"node": _spawn_whiteball(Vector3(-100, 0, -120), "att"), "kind": "att"},
			{"node": _spawn_whiteball(Vector3(60, 0, -120), "def"), "kind": "def"},
		]
		ph2 = _spawn(K_PAD, {"shape": "circle", "radius": 26.0, "color": ring_col, "translucent": true})

	func _tick_whiteball_select(delta: float) -> void:
		if phase == "delay_spawn":
			t -= delta
			if t <= 0.0:
				_spawn_select_set()
				phase = "selecting"
				hint = "选择模式：光标隐藏（投影环替身）→悬停对象高亮（两种占位均可选）→左键单选"
		elif phase == "selecting":
			if ph2 != null:
				ph2.position = Vector3(mouse.x, 0, mouse.z)
			# 悬停高亮：两种占位均可选（生效由锁定目标决定）
			var hb: Dictionary = _hover_ball()
			for b in flags.get("balls", []):
				(b.get("node")).call("set_highlight", b == hb)
			if not hb.is_empty():
				hint = "悬停高亮中→左键单选"
		elif phase == "choosing_target":
			var tgt: Node3D = _hover_actor()
			if tgt != null:
				if not flags.has("tgt_ring"):
					flags["tgt_ring"] = _spawn(K_PAD, {"shape": "circle", "radius": 30.0, "translucent": true, "color": Color(1, 0, 0)})
				var ring: Node3D = flags.get("tgt_ring")
				ring.position = tgt.global_position
				ring.mat.albedo_color = Color(1, 0.25, 0.2, 0.45) if tgt == env.get("buddy") else Color(0.25, 1, 0.4, 0.45)
				hint = "悬停中：%s（%s框）→左键锁定" % [("敌·陪衬" if tgt == env.get("buddy") else "队友·测试者"), ("红" if tgt == env.get("buddy") else "绿")]
			elif flags.has("tgt_ring"):
				flags["tgt_ring"].call("vanish")
				flags.erase("tgt_ring")
		elif phase == "flying":
			var picked: Dictionary = flags.get("picked", {})
			var n: Node3D = picked.get("node")
			var tgt: Node3D = flags.get("target")
			if n == null or tgt == null:
				return
			var remain: Vector3 = Vector3(tgt.global_position.x, 0, tgt.global_position.z) - Vector3(n.position.x, 0, n.position.z)
			n.position += (flags.get("fly_dir", Vector3.ZERO) as Vector3) * minf(320.0 * delta, remain.length())
			if Vector3(n.position.x, 0, n.position.z).distance_to(Vector3(tgt.global_position.x, 0, tgt.global_position.z)) < 30.0:
				if tgt == env.get("tester"):
					# 交付可见：占位贴附队友 0.8s（绿框脉冲）再消散
					phase = "delivering"
					t = 0.8
					hint = "交付中（绿框脉冲）…"
				else:
					n.call("vanish")
					tgt.call("take_hit", 10)
					_finish("选择链走完：作用版命中（敌体力-10，状态栏可见）")
		elif phase == "delivering":
			t -= delta
			if flags.has("tgt_ring") and is_instance_valid(flags.get("tgt_ring")):
				var rg: Node3D = flags.get("tgt_ring")
				rg.scale = Vector3.ONE * (1.0 + 0.25 * absf(sin(t * TAU * 2.0)))
			if t <= 0.0:
				var picked2: Dictionary = flags.get("picked", {})
				if picked2.get("node") != null:
					picked2.get("node").call("vanish")
				if flags.has("tgt_ring"):
					flags["tgt_ring"].call("vanish")
					flags.erase("tgt_ring")
				_finish("选择链走完：交付完成（占位贴附队友后消散）")

	## ===== 18 OP_ORIENT 定向+翻转（抽象：定向占位） =====
	func _adv_shark_swim(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph = _spawn(K_SPHERE, {"color": tcol("#7399BF"), "radius": 20.0 * tsc(), "translucent": float(tpl("ctl_visual_alpha", 1.0)) < 0.99})
			ph.position = _tester_pos() + Vector3(0, 0, -50)
			phase = "swimming"
			hint = "定向占位已生成：鼠标定向自游（无 WASD）→空格=下沉/浮起翻转"
		elif kind == K_SPACE and phase == "swimming":
			var sub: bool = not bool(flags.get("sub", false))
			flags["sub"] = sub
			ph.position.y = -14.0 if sub else 0.0
			if ph.mat != null:
				ph.mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if sub else BaseMaterial3D.TRANSPARENCY_DISABLED
				ph.mat.albedo_color.a = 0.5 if sub else 1.0
			hint = "下沉中（半透明）…" if sub else "浮起翻转！"

	func _tick_shark_swim(delta: float) -> void:
		if phase != "swimming" or ph == null:
			return
		var d: Vector3 = mouse - ph.position
		d.y = 0.0
		if d.length_squared() > 100.0:
			ph.position += d.normalized() * (80.0 if bool(flags.get("sub", false)) else 150.0) * delta
		var bd: Node3D = env.get("buddy")
		if bd != null and not bool(flags.get("sub", false)):
			var dd: Vector3 = ph.position - bd.global_position
			dd.y = 0.0
			if dd.length() < 35.0:
				bd.call("take_hit", 10)
				ph.call("vanish")
				_finish("触碰敌伤害！体力-10（状态栏可见）")
				return
		if _out_of_bounds(ph.position):
			ph.call("vanish")
			_finish("游出边界（演示结束）")

	## ===== 19 OP_TRAIL 轨迹（以球员为锚的区域释放；四形状 Tab 切换——主人 10-20 规格） =====
	## 锚点语义：矩形=球员站宽边中点向面向延伸；扇形=球员在圆心顶点；环形/圆形=球员在圆心
	func _trail_shapes() -> Array:
		return [
			{"shape": "rect", "title": "矩形(球员站宽边)", "params": {"shape": "rect", "w": 600.0, "h": 80.0, "anchor_edge": true}},
			{"shape": "sector", "title": "扇形", "params": {"shape": "sector", "radius": 300.0, "angle_deg": 90.0}},
			{"shape": "ring", "title": "环形", "params": {"shape": "ring", "inner_r": 80.0, "outer_r": 300.0}},
			{"shape": "circle", "title": "圆形", "params": {"shape": "circle", "radius": 200.0}},
		]

	func _spawn_trail(idx: int):
		var cfg: Dictionary = _trail_shapes()[idx]
		var base: Dictionary = (cfg.get("params") as Dictionary).duplicate()
		for dim in ["w", "h", "radius", "inner_r", "outer_r"]:
			if base.has(dim):
				base[dim] = float(base[dim]) * tsc()   # 区域尺寸随模板缩放
		var node = _spawn(K_PAD, base.merged({"translucent": float(tpl("ctl_visual_alpha", 0.45)) < 0.99, "color": tcol("#66E6FF")}))
		return node

	func _adv_fastlane_d14(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			flags["shape_idx"] = 0
			ph = _spawn_trail(0)
			phase = "preview"
			hint = "预览以球员为锚（矩形=球员站宽边）→Tab=切形状 左键=铺开"
		elif kind == K_TAB and phase == "preview":
			var idx: int = (int(flags.get("shape_idx", 0)) + 1) % 4
			flags["shape_idx"] = idx
			ph.call("vanish", false)
			ph = _spawn_trail(idx)
			hint = "形状=%s（Tab 继续切）→左键铺开" % str(_trail_shapes()[idx].get("title"))
		elif kind == K_CONFIRM and phase == "preview":
			# 铺开定格（以球员为锚+当前朝向），占位从球员前方向区域延申方向前进
			var d: Vector3 = mouse - _tester_pos()
			d.y = 0.0
			if d.length_squared() < 4.0:
				d = Vector3(0, 0, -1)
			d = d.normalized()
			flags["dir"] = d
			ph2 = _spawn(K_SPHERE, {"color": tcol("#7399BF"), "radius": 16.0 * tsc()})
			ph2.position = _tester_pos() + d * 20.0
			phase = "dashing"
			hint = "已铺开→占位入区域增速演示…"

	func _in_trail(p: Vector3) -> bool:
		var cfg: Dictionary = _trail_shapes()[int(flags.get("shape_idx", 0))]
		var local: Vector3 = ph.to_local(p)
		var pcfg: Dictionary = cfg.get("params")
		match str(cfg.get("shape")):
			"rect":
				return local.z <= -2.0 and -local.z <= float(pcfg.get("w", 600.0)) and absf(local.x) <= float(pcfg.get("h", 80.0)) * 0.5
			"sector":
				if Vector2(local.x, local.z).length() > float(pcfg.get("radius", 300.0)):
					return false
				return absf(atan2(local.x, -local.z)) <= deg_to_rad(float(pcfg.get("angle_deg", 90.0))) * 0.5
			"ring":
				var rr: float = Vector2(local.x, local.z).length()
				return rr >= float(pcfg.get("inner_r", 80.0)) and rr <= float(pcfg.get("outer_r", 300.0))
			"circle":
				return Vector2(local.x, local.z).length() <= float(pcfg.get("radius", 200.0))
		return false

	func _tick_fastlane_d14(delta: float) -> void:
		if phase == "preview" and ph != null:
			ph.position = _tester_pos()   # 球员为锚（矩形=站宽边；扇/环/圆=圆心）
			var d: Vector3 = mouse - _tester_pos()
			d.y = 0.0
			if d.length_squared() > 4.0:
				ph.rotation.y = atan2(-d.x, -d.z)   # 区域朝鼠标方向延伸
		elif phase == "dashing" and ph2 != null and ph != null:
			var in_area: bool = _in_trail(ph2.position)
			ph2.position += (flags.get("dir", Vector3(0, 0, -1)) as Vector3) * (300.0 if in_area else 150.0) * delta
			if in_area and not bool(flags.get("boosted", false)):
				flags["boosted"] = true
				hint = "入区域！增速 x2（150→300）…"
			elif not in_area and bool(flags.get("boosted", false)):
				flags["boosted"] = false
				hint = "已出区域（回速 150）…"
			if _out_of_bounds(ph2.position):
				ph2.call("vanish")
				_finish(str(find_script().get("done_text", "")))

	## ===== 20 guide_ball 球手动制导 WASD 双源 =====
	func _adv_guide_ball(kind: String, _pos: Vector3, dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			var d: Vector3 = mouse - _tester_pos()
			d.y = 0.0
			if d.length_squared() < 4.0:
				d = Vector3(0, 0, -1)
			ph = _spawn(K_SPHERE, {"color": tcol("#B3CCFF"), "radius": 14.0 * tsc()})
			ph.position = _tester_pos() + d.normalized() * 30.0
			flags["dir"] = d.normalized()
			phase = "guiding"
			hint = "球手动态：W=球朝鼠标 A,D=偏转（双源）→再按4=收回"
		elif kind == "move" and phase == "guiding":
			var to_m: Vector3 = mouse - ph.position
			to_m.y = 0.0
			if to_m.length_squared() > 100.0:
				ph.position += to_m.normalized() * 5.0
		elif kind == K_AD and phase == "guiding":
			flags["dir"] = ((flags.get("dir", Vector3(0, 0, -1)) as Vector3).rotated(Vector3.UP, dir.x * 0.12))
			hint = "偏转中（A/D）…W 朝鼠标 / 再按4=收回"
		elif kind == K_ACTIVATE and phase == "guiding":
			ph.call("move_to", _tester_pos() + Vector3(0, 0, -30), 0.4)
			phase = "recall"
			t = 0.45
			hint = "收回中…"

	func _tick_guide_ball(delta: float) -> void:
		if phase == "guiding" and ph != null:
			ph.position += (flags.get("dir", Vector3(0, 0, -1)) as Vector3) * 300.0 * delta
			if _out_of_bounds(ph.position):
				ph.call("vanish")
				_finish("球飞出边界（未收回）")
		elif phase == "recall":
			t -= delta
			if t <= 0.0 and ph != null:
				ph.call("vanish")
				_finish(str(find_script().get("done_text", "")) + "（W 朝鼠标+A/D 偏转→收回）")

	## ===== 21 OP_TRANSFORM 形态变换（抽象：A→B→作用→恢复） =====
	func _adv_firework_use(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			ph = _spawn(K_CUBE, {"size": 30.0 * tsc(), "color": Color(1.0, 0.6, 0.25)})
			ph.position = _tester_pos() + Vector3(0, 0, -55)
			phase = "form_a"
			hint = "形态A（待用态·方块）→按 Q 变身"
		elif kind == K_SHAPE and phase == "form_a":
			ph.call("vanish", false)
			ph = _spawn(K_SPHERE, {"color": tcol("#FFCC26"), "radius": 20.0 * tsc()})
			ph.position = _tester_pos() + Vector3(0, 0, -70)
			ph.call("pulse", 0.4)
			phase = "form_b"
			hint = "已变身为形态B！移动到敌身上生效（Q=变回）"
		elif kind == K_SHAPE and phase == "form_b":
			ph.call("vanish", false)
			ph = _spawn(K_CUBE, {"size": 30.0, "color": Color(1.0, 0.6, 0.25)})
			ph.position = _tester_pos() + Vector3(0, 0, -55)
			phase = "form_a"
			hint = "已恢复形态A→按 Q 变身"

	func _tick_firework_use(delta: float) -> void:
		if phase == "form_b" and ph != null:
			var mv: Vector3 = mouse - ph.position
			mv.y = 0.0
			if mv.length_squared() > 100.0:
				ph.position += mv.normalized() * 140.0 * delta   # 形态B 朝鼠标推进（变身生效路径）
			var bd: Node3D = env.get("buddy")
			if bd != null:
				var dd: Vector3 = ph.position - bd.global_position
				dd.y = 0.0
				if dd.length() < 38.0:
					bd.call("take_hit", 10)
					ph.call("vanish")
					ph = _spawn(K_CUBE, {"size": 30.0 * tsc(), "color": Color(1.0, 0.6, 0.25)})
					ph.position = _tester_pos() + Vector3(0, 0, -55)
					phase = "restored"
					t = 0.8
					hint = "生效！已恢复形态A（待用态）…"
		elif phase == "restored":
			t -= delta
			if t <= 0.0:
				_finish(str(find_script().get("done_text", "")) + "（A→B→作用→恢复A）")

	## ===== 22 FP_SELECT 准星选择（抽象：17 的第一视角变体） =====
	func _adv_fp_whiteball(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			env.platform.call("enter_fp", true)
			flags["balls"] = [
				{"node": _spawn_whiteball(Vector3(-120, 0, -160), "att"), "kind": "att"},
				{"node": _spawn_whiteball(Vector3(40, 0, -180), "def"), "kind": "def"},
			]
			flags["mode"] = "att"
			phase = "fp_scan"
			hint = "FP 准星选择：准星对准对象（高亮）→左键单选（E=退出）"
		elif kind == K_CONFIRM and phase == "fp_scan":
			var b: Dictionary = _fp_hover_ball()
			if b.is_empty():
				hint = "准星未对准对象（移动视角）"
				return
			flags["picked"] = b
			(b.get("node")).call("set_highlight", true)
			phase = "fp_target"
			hint = "已单选→准星对准敌（红框）/队友（绿框）→左键锁定"
		elif kind == K_CONFIRM and phase == "fp_target":
			var tgt: Node3D = _fp_hover_actor()
			if tgt == null:
				hint = "准星对准敌（红框）/队友（绿框）再锁定"
				return
			flags["target"] = tgt
			var picked0: Dictionary = flags.get("picked", {})
			var n0: Node3D = picked0.get("node")
			var d: Vector3 = tgt.global_position - n0.position
			d.y = 0.0
			flags["fly_dir"] = d.normalized()
			env.platform.call("enter_fp", false)
			phase = "fp_fly"
			hint = "占位飞向目标…"
		elif kind == K_E and (phase == "fp_scan" or phase == "fp_target"):
			env.platform.call("enter_fp", false)
			_finish("已退出（未完成选择）")

	func _fp_forward() -> Vector3:
		return env.platform.call("get_fp_forward")

	func _fp_hover_ball() -> Dictionary:
		var fwd: Vector3 = _fp_forward()
		for b in flags.get("balls", []):
			var n: Node3D = b.get("node")
			if n != null:
				var to: Vector3 = (n.position + Vector3(0, 26, 0)) - env.platform.call("get_fp_eye")
				if to.normalized().dot(fwd.normalized()) > 0.978:   # ≈12° 锥角
					return b
		return {}

	func _fp_hover_actor() -> Node3D:
		var fwd: Vector3 = _fp_forward()
		var bd: Node3D = env.get("buddy")
		var ts: Node3D = env.get("tester")
		if bd != null:
			var db: Vector3 = (bd.global_position + Vector3(0, 30, 0)) - env.platform.call("get_fp_eye")
			if db.normalized().dot(fwd.normalized()) > 0.978:
				return bd
		if ts != null:
			var dt2: Vector3 = (ts.global_position + Vector3(0, 30, 0)) - env.platform.call("get_fp_eye")
			if dt2.normalized().dot(fwd.normalized()) > 0.978:
				return ts
		return null

	func _tick_fp_whiteball(delta: float) -> void:
		if phase == "fp_scan":
			var hb: Dictionary = _fp_hover_ball()
			for b in flags.get("balls", []):
				(b.get("node")).call("set_highlight", b == hb)
			if not hb.is_empty():
				hint = "准星悬停高亮→左键单选"
		elif phase == "fp_target":
			var tgt: Node3D = _fp_hover_actor()
			if tgt != null:
				if not flags.has("tgt_ring"):
					flags["tgt_ring"] = _spawn(K_PAD, {"shape": "circle", "radius": 30.0, "translucent": true, "color": Color(1, 0, 0)})
				var ring: Node3D = flags.get("tgt_ring")
				ring.position = tgt.global_position
				ring.mat.albedo_color = Color(1, 0.25, 0.2, 0.45) if tgt == env.get("buddy") else Color(0.25, 1, 0.4, 0.45)
				hint = "准星悬停：%s（%s框）→左键锁定" % [("敌·陪衬" if tgt == env.get("buddy") else "队友·测试者"), ("红" if tgt == env.get("buddy") else "绿")]
			elif flags.has("tgt_ring"):
				flags["tgt_ring"].call("vanish")
				flags.erase("tgt_ring")
		elif phase == "fp_fly":
			var picked: Dictionary = flags.get("picked", {})
			var n: Node3D = picked.get("node")
			var tgt: Node3D = flags.get("target")
			if n == null or tgt == null:
				return
			var remain2: Vector3 = Vector3(tgt.global_position.x, 0, tgt.global_position.z) - Vector3(n.position.x, 0, n.position.z)
			n.position += (flags.get("fly_dir", Vector3.ZERO) as Vector3) * minf(320.0 * delta, remain2.length())
			if Vector3(n.position.x, 0, n.position.z).distance_to(Vector3(tgt.global_position.x, 0, tgt.global_position.z)) < 30.0:
				n.call("vanish")
				if tgt == env.get("tester"):
					_finish("FP 选择链走完：交付完成（占位到队友）")
				else:
					tgt.call("take_hit", 10)
					_finish("FP 选择链走完：命中（敌体力-10，状态栏可见）")
	## ===== 23 hold_aura OP_HOLD 维持（扩展口①演示：维持键刷新倒计时） =====
	func _adv_hold_aura(kind: String, _pos: Vector3, _dir: Vector3) -> void:
		if kind == K_ACTIVATE and phase == "idle":
			var alpha: float = float(tpl("ctl_visual_alpha", 0.5))
			ph = _spawn(K_SPHERE, {"color": tcol("#B08CFF"), "radius": 18.0 * tsc(), "translucent": alpha < 0.99})
			ph.position = _tester_pos() + Vector3(0, 0, -50)
			flags["timer"] = float(tpl("ctl_time_hold_timer", 5.0))
			flags["hold_left"] = float(flags.get("timer"))
			phase = "holding"
			hint = "维持占位已生成：按住 %s 维持（倒计时刷新）…" % str(tpl("ctl_input_hold_key", "H"))
		elif kind == K_HOLD and phase == "holding":
			flags["hold_left"] = float(flags.get("timer"))   # 扩展口①：维持键刷新倒计时
			flags["refreshes"] = int(flags.get("refreshes", 0)) + 1
			hint = "维持中（倒计时已刷新 %d 次）…" % int(flags.get("refreshes"))

	func _tick_hold_aura(delta: float) -> void:
		if phase != "holding" or ph == null:
			return
		flags["hold_left"] = float(flags.get("hold_left", 0.0)) - delta
		var left: float = float(flags.get("hold_left"))
		var timer: float = maxf(float(flags.get("timer", 5.0)), 0.1)
		if ph.mat != null:
			ph.mat.emission_energy_multiplier = 0.4 + 2.2 * clampf(left / timer, 0.0, 1.0)   # 余量越少越暗=倒计时可见
		if left <= 0.0:
			ph.call("vanish")
			_finish(str(find_script().get("done_text", "")) + "（按住刷新过 %d 次）" % int(flags.get("refreshes", 0)))
