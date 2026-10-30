## 工单03 下一批 · 版本检查器（02 档 W1）
## 纯逻辑层（headless 可测）：语义版本比对 + 决策矩阵（same/patch/minor/major）。
## 数据源：本地 res://version.json（当前版本真相）；URL 可选（空=离线静默）。
## 主菜单启动时静默调用：有新版本才提示，无感（UI 零判定红线：本类只算不弹）。
class_name VersionChecker
extends RefCounted

## 语义版本比较：返回 -1/0/1（a<b / 相等 / a>b）；非数字段按 0 处理
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in range(maxi(pa.size(), pb.size())):
		var va := _seg(pa, i)
		var vb := _seg(pb, i)
		if va < vb:
			return -1
		if va > vb:
			return 1
	return 0

static func _seg(parts: Array, i: int) -> int:
	if i >= parts.size():
		return 0
	return int(str(parts[i]).to_int())

## 更新决策：remote 比 local 新→需要更新（含版本信息）；否则静默
## local_json/remote_json 形如 {"version": "1.2.0", "url": "下载页（可选）", "notes": "更新说明（可选）"}
static func decide(local_json: Dictionary, remote_json: Dictionary) -> Dictionary:
	var lv := str(local_json.get("version", "0.0.0"))
	var rv := str(remote_json.get("version", "0.0.0"))
	if compare_versions(rv, lv) == 1:
		return {
			"update_needed": true,
			"from": lv, "to": rv,
			"url": str(remote_json.get("url", "")),
			"notes": str(remote_json.get("notes", "")),
		}
	return {"update_needed": false, "from": lv, "to": rv, "url": "", "notes": ""}

## 读本地版本真相（res://version.json）；缺失=0.0.0 兜底
static func load_local_version() -> Dictionary:
	var f := FileAccess.open("res://version.json", FileAccess.READ)
	if f == null:
		return {"version": "0.0.0"}
	var v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return v if v is Dictionary else {"version": "0.0.0"}
