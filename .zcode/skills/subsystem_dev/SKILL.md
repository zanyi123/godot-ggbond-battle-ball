---
name: "subsystem_dev"
description: "副系统（离散系统）开发规范。UI 界面外不可见、但参与主游戏逻辑判定的玩法系统集成时必读：三判据、目录/挂接点/结果协议/生命周期规范、已实现清单、headless 测试铁律。开发副系统/离散系统/隐藏玩法系统/球权韧性耐久等判定逻辑时触发。"
---

# 副系统（离散系统）开发规范

> 副系统 = 玩法逻辑的离散集成点：界面上看不见，但每一次主游戏判定都有它参与。
> 本规范 2026-09-11 由韧性/球权/耐久等判定的实际修复经验沉淀而来。

## 一、定义与判据（三条全满足才算副系统）

1. **无独立战斗 UI**：对局画面中不可见（最多极简反馈，如状态灯颜色）
2. **参与主游戏逻辑判断**：其输出会改变比赛判定/数值/流转（球权、伤害、属性、结算）
3. **可独立描述**：一句话说清"输入什么 → 判定什么 → 影响什么"

反例：元灵系统（有完整 UI+特效）、battle3d 视觉层（纯表现不参与判定）——都不是副系统。

## 二、系统范围登记表（⚠ 待主人定义，禁止 AI 自行划分）

> 哪些系统属于副系统、未来规划哪些，**由主人逐个定义登记**。
> AI 开发/重构时只处理登记在册的系统；未登记的系统不预设归属、不擅自按本规范改造。

**登记格式**（主人每定义一个，填一行）：
```
| 系统名 | 形态(autoload/class_name/内嵌) | 挂接点 | 结果协议 | 状态(已实现/规划中) |
|---|---|---|---|---|
| 事件触发-响应系统(EventBus) | battle 子节点/autoload | 各判定点 emit | 事件枚举+payload | 规划中（方案 docs/副系统-事件触发响应系统方案.md） |
| 天赋树 | class_name 响应器 + data JSON | refresh_bonuses + 事件总线 | bonus 字典/事件改写 | 规划中（同上方案 点2） |
| 元素克制(对局接线) | 分散（take_damage 参数） | 命中判定 | 伤害乘数 | 规划中（同上方案 点4） |
| 被动技能修复 | 分散（spirit_skill_trigger 内） | 事件自动触发 | 触发bool+能量扣减 | 规划中（同上方案 点3） |
```

## 三、开发规范（六条）

1. **位置**：`scripts/systems/<name>/`；单文件纯逻辑优先 `class_name`（如 buff_manager），需常驻跨场景用 autoload（project.godot 注册）
2. **单向依赖**：副系统可**读**主逻辑状态；**禁止**直接改主节点/回写位置——结果通过返回值或信号交还主逻辑处置（皮影原则：副系统出主意，主逻辑动手）
3. **结果协议**：判定类接口统一返回 Dictionary：`{result: bool/String, effect: String, data: Dictionary}`（推荐参照既有代码模式，如 take_damage 返回 `{damage, effect}`——仅作模式参考，不预设其归属）；新增字段向后兼容（读方用 `.get(key, 默认值)`）
4. **生命周期**：开赛初始化（battle_manager `_ready` 或开赛回调）→ 事件/每帧驱动 → 结算清理；中途创建的实体必须在结算/回菜单路径清理
5. **数据**：数值配置放 `data/systems/<name>/*.json`，经 DataManager 加载，保持热改可调；代码里不写死平衡数值
6. **可开关**：每个副系统提供 enable 开关（const 或配置项），关闭时主逻辑走**默认路径**（行为=无此系统），开关不得改变接口签名

## 三.5 事件-响应流程化操作手册（2026-09-11 实测验证）

事件-响应系统（EventBus+被动+天赋）已验证：**加功能=写 JSON，零代码**。

**加一个新被动技能**（skills.json，作用于装备者本人）：
```json
{"id":"skill_X_passive","name":"名","type":"passive","element":"元素",
 "trigger":{"event":"Hit.HIT_TAKEN","condition":{}},
 "cooldown":8,"energy_cost":5,
 "tags":["player_def_up_flat"],
 "tag_params":{"player_def_up_flat":{"duration":5,"value":6}}}
```
**加一个新天赋节点**（tree.json，event 型=全队生效；也可 stat/manual 型）：
```json
{"id":"buf_9","direction":"增益","name":"名","requires":["buf_1"],"cost":2,
 "type":"event","event":"Hit.HIT_COUNTER","condition":{},
 "tags":["player_atk_up_flat"],"tag_params":{"player_atk_up_flat":{"duration":5,"value":8}},
 "cooldown":10,"energy_cost":0}
```
**三条铁律（实测踩坑）**：
1. **tag id 必须精确**（是 `player_atk_up_flat` 不是 attack_up_flat）——写错静默无效；TalentSystem 执行失败会 push_warning，被动路径暂无此防线
2. **作用范围语义**：被动=个人（装备者）；天赋 event 型=全队（TalentSystem 循环）；全队效果别用被动实现
3. **condition 留空 {}=无条件**；payload 字段可比较，但对象字段（defender 等节点引用）不能做数值比较

可用 tag 清单查 `data/spirits/tags_registry.json`（id 列）+ handler case 分支（实现状态以 E6 审计为准）。
事件名格式 `"大类.事件名"`（如 Hit.HIT_TAKEN / Defend.BOUNCED / Resource.STAMINA_THRESHOLD）。

## 四、测试铁律

- **headless 可测**：每个副系统必须有自动化测试（集成测试进 `scripts/test3d/regression/` 风格：加载真实 battle_arena → 驱动 → 断言；纯逻辑可独立场景）
- **改副系统必跑 `run_sim.sh`**（关联 verify_before_deliver），对比基线说明差异
- **分支样例法**：判定有多分支时，测试必须让每个分支至少出现一次（参考接球三分：接住/击退/弹飞统计断言）
- 警惕假阳性：统计断言要排除无关路径（如半场分配导致的"得到球"≠"接住球"）

## 五、与 3D 层（battle3d）的关系

副系统属于 **2D 逻辑权威层**。battle3d 视觉代理只读副系统的**结果表现**（状态灯颜色、球权归属），**不直接调用**副系统接口——保证关掉 3D（USE_3D_SCENE=false）时副系统逻辑完全不变。

## 六、修改公约

- 新增副系统 = 新目录 + 新测试 + 本清单登记，三件套齐才算完成
- 修改既有副系统判定 = 必须同步更新其测试断言 + run_sim 对比
- 副系统间的调用允许，但形成环时必须经主逻辑中转（A→主逻辑→B）
