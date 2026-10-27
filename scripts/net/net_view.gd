## 工单01 S8 · 视图镜像（己方永远在左）——纯数学层（headless 可测）
## 2D 逻辑层不动（A 左 B 右语义不变）；guest（B 队位）渲染层镜像：
## 相机绕场心 yaw 180°（CAMERA_YAW_OFFSET），屏幕方向↔世界方向互逆换算。
## 真机挂接（camera_3d_controller 镜像机位/HUD 侧序）=下批 3D 层改造，本类先定数学契约。
class_name NetView
extends RefCounted

## guest 镜像机位偏移：绕场心 yaw 180°
const CAMERA_YAW_OFFSET := PI

## guest 是右侧队（需镜像）判定：本端槽位在 B 队即镜像（host/A 队=原样）
static func needs_mirror(local_slot: Dictionary) -> bool:
	return str(local_slot.get("team", "A")) == "B"

## 输入换算：guest 屏幕方向 → 世界方向（与镜像互逆，保证「按左=往屏幕左走」）
static func mirror_move(v: Vector2, mirrored: bool) -> Vector2:
	return -v if mirrored else v

## 世界坐标 → 屏幕语义坐标（host 恒等；guest 绕场心 180° 翻转）
static func world_to_screen(p: Vector2, field_center: Vector2, mirrored: bool) -> Vector2:
	if not mirrored:
		return p
	return Vector2(2.0 * field_center.x - p.x, 2.0 * field_center.y - p.y)

## 屏幕语义 → 世界（world_to_screen 的逆；瞄准/放置点上行换算用，S0.3/D17）
static func screen_to_world(p: Vector2, field_center: Vector2, mirrored: bool) -> Vector2:
	return world_to_screen(p, field_center, mirrored)

## 瞄准向量换算（guest 本地瞄准 → 世界系，D17 aim 事件上行前调用）
static func mirror_aim(v: Vector2, mirrored: bool) -> Vector2:
	return mirror_move(v, mirrored)

## HUD 侧序：guest 计分板/技能体力条己方在左（返回 true=需侧序镜像）
static func hud_flip(mirrored: bool) -> bool:
	return mirrored
