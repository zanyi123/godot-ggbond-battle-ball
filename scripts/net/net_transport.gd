## 工单01 S1 传输层 · ENet 连接封装 + UDP 房间信标（host 广播/大厅发现）
## 本 4.6.2 构建的 ENetPacketPeer 无 peer_id 属性（流式 peer），
## peer 标识统一用 ENetPacketPeer.get_instance_id() 做不透明 id（会话层当 peer_id 用，host 侧分配一致）。
## 事件经信号上抛，由 NetSession 消费；本类不包含任何游戏语义。
class_name NetTransport
extends RefCounted

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal packet_received(peer_id: int, msg_type: int, payload: Dictionary, channel: int)

## ENet 协议包标志位（RELIABLE=1；本构建无常量名，用协议字面量）
const FLAG_RELIABLE := 1

var is_host: bool = false
var port: int = 0

var _conn: ENetConnection = null
var _peers: Dictionary = {}            # instance_id(int) -> ENetPacketPeer
var _local_id: int = 1                 # host=1；guest 收 WELCOME 后设为 host 分配的 id
var _host_peer_id: int = -1            # guest 视角：host peer 键

# 信标（S1：host 每 1s 广播；发现端聚合）——独立于 ENet 连接
var _beacon_sock: PacketPeerUDP = null
var _beacon_text: String = ""
var _beacon_timer: float = 0.0

## host 端：绑定端口开服（3 频道：可靠/状态/语音，对齐 NetSchema.CHANNEL_COUNT）
func start_server(bind_port: int) -> bool:
	is_host = true
	port = bind_port
	_local_id = 1
	_host_peer_id = -1
	_conn = ENetConnection.new()
	var err: int = _conn.create_host_bound("*", bind_port, NetSchema.CHANNEL_COUNT, 8)
	return err == OK

## guest 端：连接 host
func start_client(host_ip: String, host_port: int) -> bool:
	is_host = false
	port = host_port
	_conn = ENetConnection.new()
	var err: int = _conn.create_host(NetSchema.CHANNEL_COUNT, 1)
	if err != OK:
		return false
	var peer: ENetPacketPeer = _conn.connect_to_host(host_ip, host_port, NetSchema.CHANNEL_COUNT)
	_host_peer_id = int(peer.get_instance_id())
	_peers[_host_peer_id] = peer
	_local_id = _host_peer_id   # 临时值；入房后由 set_local_id 更新为 host 分配 id
	return true

## guest 收 WELCOME 后设置 host 分配的本端 id
func set_local_id(id: int) -> void:
	_local_id = id

func close() -> void:
	if _beacon_sock != null:
		_beacon_sock.close()
		_beacon_sock = null
	if _conn != null:
		_conn.flush()
		_conn = null
	_peers.clear()

func is_open() -> bool:
	return _conn != null

func local_id() -> int:
	return _local_id

func host_peer_id() -> int:
	return _host_peer_id

func peer_ids() -> Array:
	return _peers.keys()

# ── 信标广播（host 侧）───────────────────────────────
## 开始每 interval 秒向 broadcast_ip:beacon_port 发房间信标（测试可单播 127.0.0.1）
func start_beacon(text: String, beacon_port: int, broadcast_ip: String = "255.255.255.255") -> bool:
	_beacon_text = text
	_beacon_sock = PacketPeerUDP.new()
	_beacon_sock.set_broadcast_enabled(true)
	_beacon_sock.set_dest_address(broadcast_ip, beacon_port)
	return true

func stop_beacon() -> void:
	if _beacon_sock != null:
		_beacon_sock.close()
		_beacon_sock = null

## 房间人数变化时刷新信标内容（不发重启）
func update_beacon_text(text: String) -> void:
	_beacon_text = text

# ── 帧驱动（真实时钟 delta 秒；测试可小步调用）────────
func poll(delta: float = 0.0) -> void:
	# 信标节拍（独立于 ENet 连接，纯信标模式也要发）
	if _beacon_sock != null and not _beacon_text.is_empty():
		_beacon_timer += delta
		if _beacon_timer >= NetSchema.BEACON_INTERVAL_S:
			_beacon_timer = 0.0
			_beacon_sock.put_packet(_beacon_text.to_utf8_buffer())
	if _conn == null:
		return
	var ev: Array = _conn.service(0)
	var kind: int = ev[0] if ev.size() > 0 else 0
	while kind != ENetConnection.EVENT_NONE:
		match kind:
			ENetConnection.EVENT_CONNECT:
				var cp: Object = ev[1] if ev.size() > 1 else null
				if cp is ENetPacketPeer:
					var cp2: ENetPacketPeer = cp
					var cid := int(cp2.get_instance_id())
					_peers[cid] = cp2
					peer_connected.emit(cid)
			ENetConnection.EVENT_DISCONNECT:
				var dp: Object = ev[1] if ev.size() > 1 else null
				if dp is ENetPacketPeer:
					var dp2: ENetPacketPeer = dp
					var did := int(dp2.get_instance_id())
					_peers.erase(did)
					peer_disconnected.emit(did)
			ENetConnection.EVENT_RECEIVE:
				var rp: Object = ev[1] if ev.size() > 1 else null
				var ch: int = ev[2] if ev.size() > 2 else 0
				if rp is ENetPacketPeer:
					var rp2: ENetPacketPeer = rp
					# 本构建为流式 peer：事件只通知，包体从 peer.get_packet() 读（可能有积压多包）
					while rp2.is_active() and rp2.get_available_packet_count() > 0:
						var pkt: PackedByteArray = rp2.get_packet()
						if pkt.size() == 0:
							break
						var m: Dictionary = NetSchema.decode_msg(pkt)
						if m["t"] != 0:
							packet_received.emit(int(rp2.get_instance_id()), int(m["t"]), m["d"], ch)
		ev = _conn.service(0)
		kind = ev[0] if ev.size() > 0 else 0

# ── 发送 ─────────────────────────────────────────────
## 单发：reliable=false 走不可靠（快照/语音用，D21 独立频道互不挤占）
func send_to(peer_id: int, msg_type: int, payload: Dictionary, channel: int = NetSchema.CH_RELIABLE, reliable: bool = true) -> void:
	if not _peers.has(peer_id):
		return
	var peer: ENetPacketPeer = _peers[peer_id]
	var flags: int = FLAG_RELIABLE if reliable else 0
	var err: int = peer.send(channel, NetSchema.encode_msg(msg_type, payload), flags)
	if err != OK:
		push_warning("[NetTransport] send ch%d err=%d peer=%d" % [channel, err, peer_id])

## 广播（host 用；逐 peer 单发，人数 ≤6 无所谓）
func broadcast(msg_type: int, payload: Dictionary, channel: int = NetSchema.CH_RELIABLE, reliable: bool = true) -> void:
	for pid in _peers.keys():
		send_to(int(pid), msg_type, payload, channel, reliable)

## guest 发给 host：底层无稳定 host id，client 端只有唯一 peer（connect_to_host 返回者）
func send_to_host(msg_type: int, payload: Dictionary, channel: int = NetSchema.CH_RELIABLE, reliable: bool = true) -> void:
	if is_host:
		broadcast(msg_type, payload, channel, reliable)
		return
	send_to(_host_peer_id, msg_type, payload, channel, reliable)

## S10 UPnP 自动端口映射（真机路由器环境生效；headless/无网关返回 false 不阻塞——真映射入主人终验）
func try_upnp(port: int) -> bool:
	var upnp := UPNP.new()
	var discover_err: int = upnp.discover()
	if discover_err != UPNP.UPNP_RESULT_SUCCESS or upnp.get_gateway() == null:
		return false
	var err: int = upnp.add_port_mapping(port)
	return err == UPNP.UPNP_RESULT_SUCCESS

## 强断某 peer（host 踢人/测试模拟掉线用）；不直接发信号——由后续 poll 的
## DISCONNECT 事件统一触发 peer_disconnected，避免双发。
func drop_peer(peer_id: int) -> void:
	if _peers.has(peer_id):
		var peer: ENetPacketPeer = _peers[peer_id]
		peer.peer_disconnect_now(0)
		_peers.erase(peer_id)


# ── 大厅发现端（S1：聚合去重 + 失效移除）──────────────
## 独立小类：绑定 UDP 端口收信标，entries 按地址聚合
class DiscoveryListener:
	extends RefCounted
	signal room_found(ip: String, info: Dictionary)
	signal room_lost(ip: String)

	var _sock: PacketPeerUDP = null
	var _entries: Dictionary = {}     # ip -> {info: Dictionary, age: float}
	var _stale_s: float = NetSchema.BEACON_STALE_S

	func start(listen_port: int) -> bool:
		_sock = PacketPeerUDP.new()
		return _sock.bind(listen_port, "0.0.0.0") == OK

	func stop() -> void:
		if _sock != null:
			_sock.close()
			_sock = null

	func entries() -> Array:
		var out: Array = []
		for ip in _entries.keys():
			var e: Dictionary = _entries[ip]
			var info: Dictionary = e.get("info", {}).duplicate()
			info["ip"] = ip
			out.append(info)
		return out

	## delta 秒推进：收包聚合 + 超龄移除（测试可注入大 delta 快进）
	func poll(delta: float) -> void:
		if _sock == null:
			return
		for ip in _entries.keys():
			_entries[ip]["age"] = float(_entries[ip]["age"]) + delta
		var stale: Array = []
		for ip in _entries.keys():
			if float(_entries[ip]["age"]) > _stale_s:
				stale.append(ip)
		for ip in stale:
			_entries.erase(ip)
			room_lost.emit(str(ip))
		while _sock.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _sock.get_packet()
			var from_ip: String = _sock.get_packet_ip()
			var info: Dictionary = NetSchema.parse_beacon_json(pkt.get_string_from_utf8())
			if info.is_empty():
				continue
			var is_new: bool = not _entries.has(from_ip)
			_entries[from_ip] = {"info": info, "age": 0.0}
			if is_new:
				room_found.emit(from_ip, info)
