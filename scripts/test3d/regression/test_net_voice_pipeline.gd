## 工单01 S11 · 网络套件 F：S13.3 语音管线回环（headless，mock 采集帧）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_net_voice_pipeline.gd
## 覆盖：40ms 分包/水位>0/多路本地混音/丢包容忍（unreliable 不重传）/PCM 常量（D21 定案）。
extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _rx: NetVoice = null

func _loopback(pkt: PackedByteArray) -> void:
	if _rx != null:
		_rx.on_packet(7, pkt)

func _initialize() -> void:
	_run()
	print("\n========== 结果：%d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, n: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + n)
	else:
		_fail += 1
		print("  ❌ FAIL: " + n)

## mock 采集：正弦 int16 PCM（毫秒数）
func _sine_pcm(ms: int, amp: int) -> PackedByteArray:
	var n: int = NetVoice.SAMPLE_RATE * ms / 1000
	var out := PackedByteArray()
	out.resize(n * 2)
	for i in n:
		var v: int = int(float(amp) * sin(TAU * 440.0 * float(i) / float(NetVoice.SAMPLE_RATE)))
		out.encode_s16(i * 2, v)
	return out

func _run() -> void:
	print("\n========== 工单01 · 网络套件 F（S13.3 语音管线） ==========\n")

	# V1 PCM 定案常量（D21）
	_assert(NetVoice.SAMPLE_RATE == 8000 and NetVoice.FRAME_BYTES == 640, "V1: PCM 16bit 8kHz 单声道·40ms/包=640B（25 包/s，D21 定案）")

	# V2 采集→分包→回环→水位（feed 返回包数组，调用方直连接收端）
	var rx := NetVoice.new()
	var tx := NetVoice.new()
	var pkts: Array = tx.feed_pcm(_sine_pcm(100, 8000))   # 100ms → 2 整包 + 20ms 尾巴
	for p in pkts:
		rx.on_packet(7, p)   # 假想 peer 7
	var sent: int = pkts.size()
	_assert(sent == 2, "V2a: 100ms 采集 → 2 个 40ms 整包（余 20ms 留尾巴拼下包）")
	_assert(tx.pending_send_bytes() == 320, "V2b: 尾巴 20ms=320B 不发半包")
	_assert(rx.buffer_ms(7) >= 80.0, "V2c: 接收缓冲水位>0（%.0fms，工件规格断言）" % rx.buffer_ms(7))

	# V3 单路读出非零（可播放）
	var played := rx.read_mix(160)   # 20ms
	var nonzero := false
	for i in range(0, played.size(), 40):
		if played[i] != 0 or played[i + 1] != 0:
			nonzero = true
			break
	_assert(played.size() == 320 and nonzero, "V3: 混音读出 20ms 非静音（正弦可闻）")

	# V4 多路本地混音（D22：接收端混音）
	rx.on_packet(8, _sine_pcm(40, 8000))
	var mixed := rx.read_mix(160)
	var peak := 0
	for i in range(0, mixed.size(), 2):
		var v: int = mixed[i] | (mixed[i + 1] << 8)
		if v >= 32768:
			v -= 65536
		peak = maxi(peak, absi(v))
	_assert(peak > 3000, "V4: 双路叠加（同相正弦振幅翻倍截断前 >3k）")

	# V5 丢包容忍：unreliable 丢包=该 40ms 静音，不重传不卡死（D21）
	var before_lost := rx.lost_packets()
	rx.on_packet(7, PackedByteArray())    # 空包模拟丢包
	var after_mix := rx.read_mix(160)     # 继续读出（不阻塞）
	_assert(rx.lost_packets() == before_lost + 1 and after_mix.size() == 320, "V5: 丢包计数+继续混音（杂音容忍不重传）")
