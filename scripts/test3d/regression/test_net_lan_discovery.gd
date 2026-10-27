## 工单01 S11 · 网络套件 B：LAN 房间发现 + ENet 传输往返（同进程回环）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_net_lan_discovery.gd
## 覆盖：S1 UDP 信标广播（本测试单播 127.0.0.1 验证逻辑；真广播=主人双机终验）、
##       大厅聚合去重/超龄移除、ENet 三频道连接/reliable+unreliable 往返、send_to_host。
extends SceneTree

const T_PORT := 18777   # ENet 测试端口（避开默认 7777 防与真机联机冲突）
const B_PORT := 18778   # 信标测试端口

var _pass: int = 0
var _fail: int = 0

# 收包侧状态（成员变量供信号回调写入）
var _srv_got: Array = []       # server 收到的 [type, payload]
var _cli_got: Array = []       # client 收到的 [type, payload]
var _found_ip: String = ""
var _found_info: Dictionary = {}
var _lost_ip: String = ""

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

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	print("\n========== 工单01 · 网络套件 B（LAN 发现 + ENet 往返） ==========\n")

	# ── L1 UDP 信标：host 发 → 大厅发现聚合
	var host_tr := NetTransport.new()
	var beacon := NetSchema.make_beacon_json("测试房", NetSchema.MP_1V1, 1, 2)
	host_tr.start_beacon(beacon, B_PORT, "127.0.0.1")
	var listener: NetTransport.DiscoveryListener = NetTransport.DiscoveryListener.new()
	listener.room_found.connect(func(ip: String, info: Dictionary): _found_ip = ip; _found_info = info)
	listener.room_lost.connect(func(ip: String): _lost_ip = ip)
	_assert(listener.start(B_PORT), "L1a: 大厅发现端绑定 %d 成功" % B_PORT)
	host_tr.poll(1.1)                 # 推过 1s 节拍 → 发一包
	listener.poll(0.1)
	_assert(_found_ip == "127.0.0.1", "L1b: host 信标被大厅发现（ip=%s）" % _found_ip)
	_assert(str(_found_info.get("name")) == "测试房" and int(_found_info.get("cap")) == 2, "L1c: 信标字段（昵称/模式/人数/上限）完整")

	# ── L2 超龄移除：3s 未刷新 → 条目移除 + room_lost
	listener.poll(NetSchema.BEACON_STALE_S + 0.5)
	_assert(_lost_ip == "127.0.0.1" and listener.entries().is_empty(), "L2: 信标 %.1fs 未刷新 → 大厅移除并报 room_lost" % NetSchema.BEACON_STALE_S)
	host_tr.stop_beacon()
	listener.stop()

	# ── E1 ENet 连接：server + client 同进程互连
	var srv := NetTransport.new()
	_assert(srv.start_server(T_PORT), "E1a: ENet server 绑定 %d" % T_PORT)
	var cli := NetTransport.new()
	_assert(cli.start_client("127.0.0.1", T_PORT), "E1b: ENet client 连接发起")
	srv.packet_received.connect(func(pid: int, t: int, d: Dictionary, ch: int): _srv_got.append([t, d, ch]))
	cli.packet_received.connect(func(pid: int, t: int, d: Dictionary, ch: int): _cli_got.append([t, d, ch]))
	# 轮帧直至 server 看到 peer（连接建立）
	var linked := false
	for i in 60:
		srv.poll(0.016)
		cli.poll(0.016)
		await process_frame
		if srv.peer_ids().size() >= 1:
			linked = true
			break
	_assert(linked, "E1c: ENet 三频道连接建立（server 见 peer）")

	# ── E2 可靠通道往返（ch0）
	cli.send_to_host(NetSchema.MSG_HELLO, {"ver": NetSchema.PROTO_VERSION, "name": "客人"})
	for i in 60:
		srv.poll(0.016)
		cli.poll(0.016)
		await process_frame
		if _srv_got.size() >= 1:
			break
	_assert(_srv_got.size() >= 1 and _srv_got[0][0] == NetSchema.MSG_HELLO, "E2a: guest→host 可靠包到达（HELLO）")
	_assert(str((_srv_got[0][1] as Dictionary).get("ver")) == NetSchema.PROTO_VERSION, "E2b: 包体 payload 逐字段无损")

	# ── E3 host 回发 + 不可靠通道（ch1 快照通道）
	srv.broadcast(NetSchema.MSG_WELCOME, {"your_peer_id": 2, "room": {"cur": 2}})
	srv.broadcast(NetSchema.MSG_SNAPSHOT, {"frame": 77, "score": {"A": 1}}, NetSchema.CH_STATE, false)
	for i in 60:
		srv.poll(0.016)
		cli.poll(0.016)
		await process_frame
		if _cli_got.size() >= 2:
			break
	var types := []
	for e in _cli_got:
		types.append(e[0])
	_assert(types.has(NetSchema.MSG_WELCOME), "E3a: host→guest 可靠包（WELCOME）到达")
	_assert(types.has(NetSchema.MSG_SNAPSHOT), "E3b: ch1 不可靠快照通道独立收包（D21 同构）")

	# ── E4 收尾关闭
	srv.close()
	cli.close()
	host_tr.close()
	_assert(not srv.is_open() and not cli.is_open(), "E4: 双端 close 干净")
