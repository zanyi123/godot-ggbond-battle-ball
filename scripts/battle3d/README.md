# battle3d 模块（Phase 0 骨架 · 2026-09-10）

3D 场景视觉层：2D 逻辑权威 + 3D 只读代理。方案见 `docs/3D场景回归Godot融合方案.md`。

## 单位制铁律（禁止违反，详见 battle-ball skill）

- 3D 世界单位 = GD 2D 像素，**1:1 零换算**，坐标只做 `(x,y)→(x,0,y)`
- **禁止**引入 ×0.01/×0.02 米制换算因子（Unity 历史包袱，不进 Godot）
- 球员：ModelSlot scale=70 唯一缩放点，FBX 强制 1.0，模型高 ≈49.86
- 球：BALL_SCALE=30，持球高 55 / 飞行高 30，自旋 12 rad/s
- 球场 GLB：battle_field_3d_yup.glb **scale=1**（原生即像素级）+ 根偏移微调
- 场地判定常量唯一权威 = `scripts/battle/field_zone.gd` 像素值

## 目录约定

```
scripts/battle3d/
├── README.md              本文件（模块公约）
├── battle3d_const.gd      常量表 + MODEL_MAP（唯一资产映射处）
├── rules/                 规则双轨验证用（Phase 3）
└── visual/                3D 视觉代理
    ├── player_proxy_3d.gd     球员代理（GLB贴图+FBX骨骼+动画合并）
    ├── ball_proxy_3d_v2.gd    球代理（米制→已改像素制，对齐 player_3d_test 口径）
    ├── camera_3d_controller.gd 相机四模式 UNITY/TOP/ANGLED/FOLLOW
    ├── skill_fx_3d_adapter.gd  特效适配（Phase 4）
    └── skill_outline_3d.gd     环/条带 3D 绘制（Phase 4）
scripts/test3d/            独立验证场（不接主流程）
```

## 修改公约

- 本模块新文件**只读 2D 层数据，不回写**
- 修改 `scripts/battle/` 既有文件仅限：battle_manager 加开关+信号；player/ball/field_zone 加 `set_visual_visible`
- `scripts/test/` 既有 3D 测试设施（player_3d_test 等）原样保留作参考，**不修改不 import**

## 资产策略（Phase 0 确认）

- **大资源异步预加载**：生产接入（Phase 2 bridge）用 `ResourceLoader.load_threaded_request`
  + 首帧 loading 提示；Phase 1 验证场用同步 load + 分步计时打印（可接受窗口冻结）。
- 动画资产分两级：
  - 每球员专属 mesh（idle 姿势 FBX，带骨骼）：`建模素材库/3D模型素材/playerN动作/*.fbx`
  - 共享动作库（Mixamo 同骨架）：`assets/characters/avatars/{Idle,Jog_Forward,Goalie_Throw,Goalkeeper_Catch}.fbx`
  - player6~8 无专属动作 FBX → mesh 兜底用共享 `avatars/Idle.fbx`（Phase 1 已知限制，后续补资产）
- PBR 贴图：`playerN_base_texture_pbr_20250901{,_normal,_metallic-texture_pbr_20250901_roughness}.png`
  手动加载应用到 FBX mesh（player_3d_test 验证过的模式）
