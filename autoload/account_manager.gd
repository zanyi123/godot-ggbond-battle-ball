## 工单03 · 玩家账号管理器（autoload）
## 身份三级：guest（游客·本地）→ registered → logged（持 token 会话）。
## PocketBase REST 适配：base_url 为空=离线游客模式（v1 默认，零门槛）。
## 持久化：user://account_local.json 每次变更即存（A3）；密码不落盘（A6）。
extends Node

signal account_changed

const SAVE_PATH := "user://account_local.json"
const PB_BASE_URL := ""   # PocketBase 接入步骤（工单03 §五）：填 "http://IP:8090" 即启用在线身份；空=离线游客

var state: String = "guest"          # guest | logged
var device_id: String = ""
var nickname: String = ""
var token: String = ""
var remembered_email: String = ""
var _http: HTTPRequest = null
var _pending: Dictionary = {}        # in-flight 请求回调上下文

func _ready() -> void:
	_load_local()
	if nickname == "":
		_ensure_guest()
	_http = HTTPRequest.new()
	add_child(_http)

# ── 本地持久化（A3）──
func _load_local() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if v is Dictionary:
		var d: Dictionary = v
		device_id = str(d.get("device_id", ""))
		nickname = str(d.get("nickname", ""))
		token = str(d.get("token", ""))
		remembered_email = str(d.get("email", ""))
		state = "logged" if token != "" else "guest"

func _save_local() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"device_id": device_id, "nickname": nickname, "token": token, "email": remembered_email,
	}))
	f.close()

# ── 游客身份 ──
func _ensure_guest() -> void:
	if device_id == "":
		device_id = "%016x" % (randi() * 65536 + randi())   # 64bit 设备码
	if nickname == "" or nickname.begins_with("游客-"):
		nickname = "游客-%s" % device_id.substr(device_id.length() - 4)
	state = "guest"
	token = ""
	_save_local()

## 游客模式下改昵称（联机大厅用；改了即存）
func set_guest_nickname(name: String) -> void:
	if state != "guest" or name.strip_edges() == "":
		return
	nickname = name.strip_edges().substr(0, 20)
	_save_local()
	account_changed.emit()

func get_nickname() -> String:
	return nickname

func is_guest() -> bool:
	return state != "logged"

# ── PocketBase REST（在线身份）──
## 注册 {email, password, nickname}：成功=自动登录（PB auth-with-password 二段）
func register(email: String, password: String, name: String, on_done: Callable) -> void:
	_pb_request("POST", "/api/collections/users/records", {
		"email": email, "password": password, "passwordConfirm": password, "nickname": name,
	}, func(ok: bool, data: Dictionary):
		if ok:
			login(email, password, on_done)
		else:
			on_done.call(false, _err_msg(data, "注册失败")))

## 登录：成功=logged+token 持久化；失败=保持游客+错误文案
func login(email: String, password: String, on_done: Callable) -> void:
	_pb_request("POST", "/api/collections/users/auth-with-password", {
		"identity": email, "password": password,
	}, func(ok: bool, data: Variant):
		if not (data is Dictionary):
			data = {}
		if ok and str(data.get("token", "")) != "":
			token = str(data.get("token"))
			remembered_email = email
			var rec: Dictionary = data.get("record", {})
			nickname = str(rec.get("nickname", "")) if str(rec.get("nickname", "")) != "" else email.split("@")[0]
			state = "logged"
			_save_local()
			account_changed.emit()
			on_done.call(true, "登录成功")
		else:
			on_done.call(false, _err_msg(data, "登录失败：邮箱或密码不对")))

func logout() -> void:
	_ensure_guest()
	account_changed.emit()

## PocketBase 侧配置了 base_url 才发真请求；否则直接回失败（离线游客兜底）
func _pb_request(method: String, path: String, body: Dictionary, on_done: Callable) -> void:
	if PB_BASE_URL == "":
		on_done.call(false, "未配置账号服务器（当前为游客模式）")
		return
	_http.cancel_request()
	_pending = {"cb": on_done}
	_http.request_completed.connect(_on_http_done, CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: " + token)
	_http.request(PB_BASE_URL + path, headers, HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET, JSON.stringify(body))

func _on_http_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	var data: Dictionary = {}
	var v: Variant = JSON.parse_string(body.get_string_from_utf8())
	if v is Dictionary:
		data = v
	if _pending.has("cb"):
		var cb: Callable = _pending["cb"]
		_pending = {}
		cb.call(ok, data)

func _err_msg(data: Dictionary, fallback: String) -> String:
	return str(data.get("message", fallback))
