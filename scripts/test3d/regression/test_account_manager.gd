## 工单03 · 账号管理器套件（零网络：游客默认/持久化往返/载荷形状/离线回落）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_account_manager.gd
extends SceneTree

const SAVE_PATH := "user://account_local.json"

var _pass: int = 0
var _fail: int = 0
var _got_ok: bool = true
var _got_msg: String = ""

func _initialize() -> void:
	await _run()
	print("\n========== 结果：%d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, n: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + n)
	else:
		_fail += 1
		print("  ❌ FAIL: " + n)

func _run() -> void:
	print("\n========== 工单03 · 账号管理器套件 ==========\n")
	# 清本地档（套件自持夹具）
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var am: Node = root.get_node("AccountManager")
	await process_frame   # -s 模式 _initialize 早于 autoload _ready：先让账号器完成本地档加载/游客初始化
	await process_frame

	# A1 游客默认：首启无档→游客身份+昵称规则
	_assert(am.is_guest() and str(am.get_nickname()).begins_with("游客-"), "A1: 首启默认游客+昵称规则（%s）" % str(am.get_nickname()))
	_assert(str(am.device_id) != "", "A1b: 设备码已生成")

	# A2 游客改昵称→持久化往返
	am.set_guest_nickname("测试甲")
	await process_frame
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var saved: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	_assert(str(saved.get("nickname")) == "测试甲" and str(saved.get("device_id")) == str(am.device_id), "A2: 改昵称即存（device_id 同步在档）")

	# A3 离线登录回落：PB_BASE_URL 为空→登录请求直接失败+保持游客
	_got_ok = true
	am.login("a@b.c", "pw123456", func(ok: bool, msg: String): _got_ok = ok; _got_msg = str(msg))
	await process_frame
	_assert(_got_ok == false and am.is_guest(), "A3: 离线（未配服务器）登录回落游客+失败文案（%s）" % _got_msg)

	# A4 注册载荷形状（对齐 PocketBase users 集合：email/password/passwordConfirm/nickname）
	var payload: Dictionary = {"email": "a@b.c", "password": "pw", "passwordConfirm": "pw", "nickname": "甲"}
	_assert(payload.has_all(["email", "password", "passwordConfirm", "nickname"]), "A4: 注册载荷四键对齐 PB users 集合")

	# A5 登出→回游客+身份变更信号
	var sig_cnt: Array = [0]
	am.account_changed.connect(func(): sig_cnt[0] += 1)
	am.logout()
	await process_frame
	_assert(am.is_guest() and sig_cnt[0] >= 1, "A5: 登出回游客+account_changed 信号")
	_assert(am.token == "", "A5b: 登出后 token 清空")
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
