## battle3d 常量表 —— 唯一资产映射与定死规格处
## ⚠ 3D 场景单位制铁律（2026-09-10 确立，详见 battle-ball skill）：
##   3D 世界单位 = GD 2D 像素，1:1 零换算，坐标只做 (x,y)→(x,0,y)
##   禁止引入 ×0.01/×0.02 米制换算因子；读 Unity 数值时 ×50（角度不变）
class_name Battle3DConst
extends Object

## ==================== 球员规格（定死，禁止改动） ====================
const PROXY_SCALE: float = 70.0          ## ModelSlot 唯一缩放控制点
const PROXY_FBX_SCALE: float = 1.0       ## FBX 强制 1.0（缩放铁律）
const PROXY_MODEL_HEIGHT: float = 49.86  ## 球员模型实际高度（实测）

## ==================== 球规格（player_3d_test 一体化平台口径） ====================
const BALL_SCALE: float = 30.0
const BALL_CARRIED_Y: float = 55.0       ## 持球高度（手部）
const BALL_FLIGHT_Y: float = 30.0        ## 飞行高度（腰部）
const BALL_SPIN_SPEED: float = 12.0      ## 飞行自旋 rad/s

## ==================== 相机规格（player_3d_test 大相机口径） ====================
const CAM_TOP_Y: float = 1000.0
const CAM_TOP_ORTHO_SIZE: float = 870.0
const CAM_ANGLED_DIST: float = 1200.0
const CAM_FOV: float = 62.0
## UNITY 观感模式：Unity TestBattle 相机 (0,16,-10) 俯角58° ×50
const CAM_UNITY_POS := Vector3(0.0, 800.0, 500.0)  ## +Z 侧看 -Z：屏幕方向与 2D 操作一致（-Z 侧会上下镜像，2026-09-10 修）
const CAM_UNITY_PITCH_DEG: float = 58.0

## ==================== 球场规格 ====================
const FIELD_GLB_PATH := "res://scenes/blender/battle_field_3d_yup.glb"
## 根偏移（battle_field_3d_test.tscn 根节点实测值，白线对齐用）
const FIELD_ROOT_OFFSET := Vector3(-1.8370361, 1.042633, 0.35451508)
## 白线判定权威值（= scripts/battle/field_zone.gd，仅作 3D 侧画框/双轨参考）
const FIELD_INNER := Rect2(-380.0, -260.0, 760.0, 520.0)
const FIELD_WALKABLE := Rect2(-510.0, -325.0, 1020.0, 650.0)
const FIELD_CENTER_CIRCLE_R: float = 60.0

## ==================== 球员资产映射（唯一映射处） ====================
## 每球员：mesh = 专属 idle 姿势 FBX（带骨骼）；动画 = 共享 Mixamo 动作库
## player6~8 无专属动作 FBX → mesh 兜底用共享 avatars/Idle.fbx（已知限制）
const ASSET_BASE := "res://建模素材库/3D模型素材/"
const SHARED_AVATARS := "res://assets/characters/avatars/"

const MODEL_MAP: Dictionary = {
	"char_001": {
		"mesh_fbx": ASSET_BASE + "player1动作/Idle.fbx",
		"pbr_prefix": ASSET_BASE + "player1_base_texture_pbr_20250901",
	},
	"char_002": {
		"mesh_fbx": ASSET_BASE + "player2动作/Standing Idle.fbx",
		"pbr_prefix": ASSET_BASE + "player2_base_texture_pbr_20250901",
	},
	"char_003": {
		"mesh_fbx": ASSET_BASE + "player3动作/Standing Block Idle.fbx",
		"pbr_prefix": ASSET_BASE + "player3_base_texture_pbr_20250901",
	},
	"char_004": {
		"mesh_fbx": ASSET_BASE + "player4动作/Standing Block Idle.fbx",
		"pbr_prefix": ASSET_BASE + "player4_base_texture_pbr_20250901",
	},
	"char_005": {
		"mesh_fbx": SHARED_AVATARS + "player5_idle.fbx",
		"pbr_prefix": ASSET_BASE + "player5_base_texture_pbr_20250901",
	},
	"char_006": {
		"mesh_fbx": SHARED_AVATARS + "Idle.fbx",
		"pbr_prefix": ASSET_BASE + "player6_base_texture_pbr_20250901",
	},
	"char_007": {
		"mesh_fbx": SHARED_AVATARS + "Idle.fbx",
		"pbr_prefix": ASSET_BASE + "player7_base_texture_pbr_20250901",
	},
	"char_008": {
		"mesh_fbx": SHARED_AVATARS + "Idle.fbx",
		"pbr_prefix": ASSET_BASE + "player8_base_texture_pbr_20250901",
	},
}

## 共享动画（Mixamo 同骨架，跨球员合并到各自 AnimationPlayer）
const SHARED_ANIMS: Dictionary = {
	"run": SHARED_AVATARS + "Jog_Forward.fbx",
	"throw": SHARED_AVATARS + "Goalie_Throw.fbx",
	"catch": SHARED_AVATARS + "Goalkeeper_Catch.fbx",
}

## 球模型
const BALL_GLB_PATH := "res://建模素材库/3D模型素材/battleball.glb"

## ==================== 坐标映射（唯一入口） ====================
## 2D 游戏坐标 → 3D 世界坐标，1:1 零换算（铁律）
static func game2d_to_3d(pos2d: Vector2) -> Vector3:
	return Vector3(pos2d.x, 0.0, pos2d.y)

## 2D 朝向 → 3D 绕 Y 旋转角（弧度）
## 2026-09-11 实测校准（-X 侧贴脸截图见正脸铁证）：模型本征面向 +Z，
## 公式 = atan2(facing.x, facing.y)，**不加 PI**（2026-09-10 的 +PI 是误诊——
## 当时看到的"反向"全是 UNITY 相机 -Z 机位镜像造成的视觉假象，相机已移 +Z 侧修复）
static func facing_to_rotation_y(facing: Vector2) -> float:
	if facing.length_squared() < 0.0001:
		return 0.0
	return atan2(facing.x, facing.y)
