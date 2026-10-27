## 工单01 S13.3 · 语音管线 v1（D21 定死：PCM 16bit 8kHz 单声道 ≈128kbps/人；ADPCM=M5 公网优化项）
## 采集→40ms 分包（640B）→ch2 unreliable 独立通道（D21，与快照互不挤占）→
## 接收端 jitter 缓冲→本地多路混音（D22：host 只转发不混音）。
## 真机接线（AudioEffectCapture 采集/AudioStreamGenerator 播放/PTT 键位）=下批+操控域键位；
## 本类=纯管线逻辑，headless 可测（mock 帧→分包→回环→缓冲→混音）。
class_name NetVoice
extends RefCounted

const SAMPLE_RATE := 8000
const FRAME_MS := 40
const FRAME_BYTES := SAMPLE_RATE * 2 * FRAME_MS / 1000   # 640 字节/包（25 包/s）

var _send_buf: PackedByteArray = []
var _recv: Dictionary = {}     # peer_id -> PackedByteArray（各路 jitter 尾巴）
var _lost_packets: int = 0     # 统计（unreliable 丢包=杂音不重传，D21）

## 采集侧喂入（真机=AudioEffectCapture 取帧；测试=mock 正弦）。
## 返回打好的整包数组（40ms/640B）——调用方自行接 transport 广播（ch2 unreliable）或回环。
## 不用 Callable 钩子：本构建跨对象 Callable 成员调用不可靠（is_valid=true 但不执行，已探针实证）。
func feed_pcm(samples: PackedByteArray) -> Array:
	_send_buf.append_array(samples)
	var packets: Array = []
	while _send_buf.size() >= FRAME_BYTES:
		var pkt := _send_buf.slice(0, FRAME_BYTES)
		_send_buf = _send_buf.slice(FRAME_BYTES)
		packets.append(pkt)
	return packets

## 接收入包（真机=transport packet_received ch2；测试=直接回环）
## ⚠ Packed 类型值语义：从 Dictionary 取出即拷贝，必须改完放回
func on_packet(peer_id: int, pkt: PackedByteArray) -> void:
	if pkt.size() == 0:
		_lost_packets += 1
		return
	var buf: PackedByteArray = _recv.get(peer_id, PackedByteArray())
	buf.append_array(pkt)
	_recv[peer_id] = buf

## 某路缓冲水位（毫秒）
func buffer_ms(peer_id: int) -> float:
	var buf: PackedByteArray = _recv.get(peer_id, PackedByteArray())
	return float(buf.size()) / float(SAMPLE_RATE * 2) * 1000.0

## 多路混音读出 samples 个样本（int16 相加 clamp；掉线路自然耗尽静音）
func read_mix(samples: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples * 2)
	var acc := PackedInt32Array()
	acc.resize(samples)
	for pid in _recv.keys():
		var buf: PackedByteArray = _recv[pid]
		var take: int = mini(buf.size(), samples * 2)
		var i := 0
		while i < take:
			var v: int = buf[i] | (buf[i + 1] << 8)
			if v >= 32768:
				v -= 65536
			acc[i / 2] += v
			i += 2
		_recv[pid] = buf.slice(take)
	for j in samples:
		out.encode_s16(j * 2, clampi(acc[j], -32768, 32767))
	return out

func pending_send_bytes() -> int:
	return _send_buf.size()

func lost_packets() -> int:
	return _lost_packets
