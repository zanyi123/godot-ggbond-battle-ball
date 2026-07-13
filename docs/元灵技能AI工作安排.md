# 元灵技能AI 工作安排

---

## Phase 0：基础框架（先跑通链路）

| 任务 | 做什么 | 改哪些文件 | 验收标准 |
|------|--------|-----------|---------|
| T0.1 | 新建 `spirit_ai_manager.gd` 空框架，含初始化/注册/主循环 | `scripts/battle/spirit_ai_manager.gd`（新） | 文件创建，能被 Godot 加载不报错 |
| T0.2 | `ai_profile.gd` 加技能AI基础参数（阈值/能量/间隔/意图权重） | `scripts/battle/ai_profile.gd` | 3个角色预设都有技能AI参数 |
| T0.3 | `ai_manager.gd` 集成技能AI（初始化+注册+每帧调用） | `scripts/battle/ai_manager.gd` | 比赛开始后技能AI正常运行不报错 |
| T0.4 | 技能AI能读取技能列表 + 随机调用 `spirit_system.use_skill()` | `scripts/battle/spirit_ai_manager.gd` | AI球员偶尔会放技能（先不管时机对不对） |

---

## Phase 1：BALL类技能 + 基础评分（含复合技能处理）

| 任务 | 做什么 | 改哪些文件 | 验收标准 |
|------|--------|-----------|---------|
| T1.0 | **复合技能处理**：`tag`字段归一化（字符串/数组），多标签权重规则（1个100%/2个各70%/3个各50%），复合技能基础价值计算 | `spirit_ai_manager.gd` | 冰冻之球（球+控场）、铁壁守护（球员+防御）评分合理且优于纯单标签技能 |
| T1.1 | 技能基础价值计算（按标签效果算 base_value） | `spirit_ai_manager.gd` | 每个技能能算出一个分数 |
| T1.2 | 球权因子 + 分差因子（简化版） | `spirit_ai_manager.gd` | 我方持球时攻击技能分更高，落后时更敢用 |
| T1.3 | 意图匹配度（角色视角 → 技能意图 → intent_match），**支持复合技能多意图合并** | `spirit_ai_manager.gd` | 主攻手看进攻意图，防御手看防御意图，复合技能按权重合并意图 |
| T1.4 | BALL类技能释放时机（持球时 + 投球前触发） | `spirit_ai_manager.gd` | AI持球投球前会用球强化技能 |

---

## Phase 2：PLAYER类技能 + 目标选择（含复合技能）

| 任务 | 做什么 | 改哪些文件 | 验收标准 |
|------|--------|-----------|---------|
| T2.1 | 赛前球员属性分析（弱点/强项/生存风险等级） | `spirit_ai_manager.gd` | 菲菲=高风险，超人强=低风险 |
| T2.2 | 技能协同度计算（critical/high/medium/low），**复合技能按多标签分别计算后取最高** | `spirit_ai_manager.gd` | 菲菲+草木防御buff=critical，超人强+岩石墙=high |
| T2.3 | PLAYER类技能目标选择（自己/队友/敌人），**复合技能中PLAYER标签的部分进入目标选择** | `spirit_ai_manager.gd` | 辅助手给残血队友回血，主攻手给自己加攻 |
| T2.4 | 体力因子 + 局势响应规则 | `spirit_ai_manager.gd` | 血量低时恢复技能分飙升 |

---

## Phase 3：FIELD类技能 + 位置选择（含复合技能）

| 任务 | 做什么 | 改哪些文件 | 验收标准 |
|------|--------|-----------|---------|
| T3.1 | FIELD类技能意图判定（进攻用/防守用），**复合技能中FIELD标签的部分进入意图判定** | `spirit_ai_manager.gd` | 敌方推进=防守意图，我方进攻=进攻意图 |
| T3.2 | 障碍放置位置计算（拦截对方路径/挡住防守者） | `spirit_ai_manager.gd` | 障碍放在对方进攻路线上 |
| T3.3 | 区域效果位置选择（控制关键区域） | `spirit_ai_manager.gd` | 减速区放在己方防守要地 |
| T3.4 | 人数差因子 | `spirit_ai_manager.gd` | 少打多时防御技能分更高 |

---

## Phase 4：动态能量 + 难度系统

| 任务 | 做什么 | 改哪些文件 | 验收标准 |
|------|--------|-----------|---------|
| T4.1 | 动态能量评估（现在用的价值 vs 留到未来的价值） | `spirit_ai_manager.gd` | 关键球低能量也用，垃圾时间高能量也不用 |
| T4.2 | 时间因子（末段爆发/开场保留） | `spirit_ai_manager.gd` | 最后10秒AI更敢用技能 |
| T4.3 | 难度系统对接（青铜1级→王者10级，统一缩放公式） | `ai_profile.gd` + `spirit_ai_manager.gd` | 低难度很少用且常失误，高难度时机精准 |
| T4.4 | 失误机制（时机/目标/技能三类失误） | `spirit_ai_manager.gd` | 低难度AI偶尔选错目标或用错技能 |

---

## Phase 5：AI间信号交流

| 任务 | 做什么 | 改哪些文件 | 验收标准 |
|------|--------|-----------|---------|
| T5.1 | 扩展通信系统：新增 SKILL_READY / BUFF_ON_YOU / NEED_BUFF 3种消息 | `scripts/battle/ai_communication.gd` | 3种消息能正常发送和接收 |
| T5.2 | 技能AI发送消息（有大招了喊队友，给队友加buff了通知） | `spirit_ai_manager.gd` | AI释放技能后会发对应消息 |
| T5.3 | 技能AI响应队友消息（收到NEED_BUFF就给队友加buff） | `spirit_ai_manager.gd` | 主攻手喊要buff，辅助手就给加 |
| T5.4 | 球员AI响应技能消息（收到BUFF_ON_YOU就更敢进攻） | `ai_manager.gd` | 有buff的AI更激进进攻 |

---

## Phase 6：高级功能

| 任务 | 做什么 | 改哪些文件 | 验收标准 |
|------|--------|-----------|---------|
| T6.1 | 技能组合策略（连招/互补/协同） | `spirit_ai_manager.gd` | AI会减速→眩晕→高伤害连招 |
| T6.2 | 元素克制系统（克制+30%，被克制-30%） | `spirit_ai_manager.gd` | 用克制元素的技能时效果更强 |
| T6.3 | 团队短板分析（全局策略调整） | `spirit_ai_manager.gd` | 全队防御弱时防御技能全局加分 |
| T6.4 | Softmax概率选择（高难度更确定，低难度更随机） | `spirit_ai_manager.gd` | 低难度AI偶尔选次优技能 |

---

## 依赖关系

```
Phase 0 → Phase 1 → Phase 1.5（复合技能） → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6
  │          │              │                  │          │          │          │
  └─ 框架    └─ 基础+复合    └─ 复合技能验证     └─ PLAYER  └─ FIELD   └─ 难度    └─ 高级
```

## 改动文件清单

| 文件 | 改动类型 | 涉及Phase |
|------|---------|-----------|
| `scripts/battle/spirit_ai_manager.gd` | 新建 | 全部 |
| `scripts/battle/ai_profile.gd` | 修改 | 0, 4 |
| `scripts/battle/ai_manager.gd` | 修改 | 0, 5 |
| `scripts/battle/ai_communication.gd` | 修改 | 5 |

## 复合技能处理统一规则（贯穿所有Phase）

| 标签数 | 权重 | 应用到评分 | 应用到意图 | 应用到目标选择 |
|--------|------|----------|----------|--------------|
| 1个 | 100% | 全部按单标签算 | 单一意图 | 单一目标 |
| 2个 | 各70% | 各标签价值×0.7求和 | 各标签意图×0.7叠加 | 按主标签选目标 |
| 3个 | 各50% | 各标签价值×0.5求和 | 各标签意图×0.5叠加 | 按主标签选目标 |
