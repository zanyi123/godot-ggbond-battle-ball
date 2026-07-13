# 元灵技能 AI 设计原则

> **文档定位**：元灵技能 AI 的设计原则与决策框架。AI 智能使用元灵技能，而不是冷却好了就乱放。

---

## 一、核心设计目标

让 AI 球员像真实玩家一样**有策略地使用元灵技能**：
- **会选时机**：不是冷却好了就用，而是在关键节点释放
- **会选目标**：根据技能类型选择最优目标（自己/队友/敌人/场地位置）
- **会省资源**：动态评估"现在用的价值"vs"留到未来的价值"，不是固定阈值
- **有角色视角差异**：同一技能，不同角色看到的价值不同——主攻手评估"能不能帮我得分"，防御手评估"能不能阻止丢分"，辅助手评估"能不能补团队短板"。角色不是只会一类技能的偏执狂，而是基于自身定位有不同评估重心
- **有失误节奏**：不是每次都用在最优点，偶尔早用/晚用/用错目标
- **会处理复合技能**：一个技能可同时含多个标签（球+球员+场），按多标签权重综合评分，不当成单一标签评估

---

## 二、六大设计原则

### 原则1：效用驱动（Utility-Driven）

**设计**：所有技能释放决策基于"评分制"，计算每个可用技能的预期收益，选最高分的释放。

**为什么**：避免"冷却好了就用"的机械行为，让 AI 能权衡"现在用值不值"。

**核心修正——引入技能意图（skill_intent）**：

技能不只有类型标签（BALL/FIELD/PLAYER），还有**意图标签**（进攻/防御/支援）。同一技能在不同角色眼中，意图权重不同：

| 意图 | 含义 | 举例 |
|------|------|------|
| **进攻意图** | 增加我方得分概率 | 球强化、加速冲刺、给敌人加减速debuff |
| **防御意图** | 降低对方得分概率 | 放障碍拦截、给自己/队友加防、区域减速 |
| **支援意图** | 维持/提升团队状态 | 给队友回血、给队友加buff、给队友加速 |

> **关键洞察**：同一个PLAYER类"加攻buff"，主攻手看到的是"进攻意图"（我要更强地打），防御手看到的是"防御意图"（保护球权不被抢），辅助手看到的是"支援意图"（帮队友进攻）。意图由角色视角决定，不由技能类型决定。

**实现方式**：
- 每个技能计算 `total_score = base_value × situation_factor × intent_match × resource_factor`
- `intent_match`：角色对该技能意图的匹配度（取代原来简单的"类型偏好"）
- 只有当 `total_score >= skill_use_threshold` 时才释放
- 多个技能都达标时选最高分的

---

### 原则2：角色视角差异化（Role Perspective）

**设计**：不同角色对同一技能的评估重心不同。角色差异体现在"评估视角"而非"技能类型偏好"。

**旧版错误**：把主攻手写成"不爱给自己buff"——一个聪明的主攻手当然会给自己加攻击buff，因为那是进攻准备。问题出在用"BALL/FIELD/PLAYER偏好"来描述角色，把角色变成了只会一招的偏执狂。

#### 角色评估视角

| 角色 | 评估核心问题 | 典型思维方式 | 不是什么 |
|------|------------|------------|---------|
| **主攻手** | "这能不能帮我得分或创造进攻机会？" | 给自己加攻buff=进攻准备（高价值）；放障碍挡住防守者=创造空间（有价值）；给自己加防=保护进攻持续性（有价值） | 不是"不爱给自己buff的傻攻" |
| **防御手** | "这能不能阻止对方得分或保护我方？" | 放障碍拦截=核心手段（最高价值）；给自己加防=保护球权（高价值）；反击时用球强化=转守为攻（有价值） | 不是"攒着能量不用的缩头乌龟" |
| **辅助手** | "这能不能补团队短板或创造团队优势？" | 给残血队友回血=最高优先；给进攻队友加buff=配合得分（高价值）；控场=战术配合（有价值） | 不是"只会加buff的工具人" |

#### 角色意图匹配度 intent_match

同一技能，不同角色看到不同意图，匹配度不同：

| 技能示例 | 技能类型 | 主攻手视角 | 防御手视角 | 辅助手视角 |
|---------|---------|-----------|-----------|-----------|
| 球+30%伤害 | BALL | 进攻意图 1.6（核心进攻手段） | 反击意图 0.9（转守为攻时用） | 支援意图 1.0（帮队友进攻） |
| 给自己+攻击buff | PLAYER | 进攻意图 1.4（进攻准备！） | 防御意图 0.9（保护球权） | 支援意图 1.0（帮队友进攻） |
| 放障碍挡路 | FIELD | 进攻意图 1.1（挡住防守者创造空间） | 防御意图 1.6（核心拦截手段） | 支援意图 1.0（战术配合） |
| 给队友回血 | PLAYER | 进攻意图 0.7（保住进攻队友） | 防御意图 1.1（保住防守队友） | 支援意图 1.7（核心职责） |
| 给自己加防 | PLAYER | 进攻意图 1.0（保护进攻持续性） | 防御意图 1.5（核心生存手段） | 支援意图 1.1（保住自己才能帮队友） |
| 区域减速 | FIELD | 进攻意图 0.9（让对方追不上我） | 防御意图 1.4（延缓对方推进） | 支援意图 1.1（配合队友） |

**为什么这样改**：
- 主攻手给自己加攻buff不是"不爱PLAYER技能"，而是"评估为进攻准备，高价值"
- 防御手也会用球强化技能，但只在"反击时"——因为转守为攻是防御的一部分
- 辅助手什么技能都能用，但评估重心是"团队最需要什么"

**能量使用风格**（不是激进/保守这种极端标签）：

| 角色 | 能量使用风格 | 说明 |
|------|------------|------|
| 主攻手 | **机会型**——善于识别进攻窗口，窗口出现时精准投入能量 | 不是"有能量就乱放"，是"等好机会才放" |
| 防御手 | **预判型**——提前布局，在对方进攻到来前已准备好 | 不是"攒着不用"，是"预判对方行动，提前布防" |
| 辅助手 | **响应型**——根据队友状态动态调整，缺口出现时立即补上 | 不是"队友要就给"，是"判断哪里最需要支援" |

---

### 原则3：局势敏感（Situation-Aware）

**设计**：技能释放决策强依赖当前场上局势，而不是固定冷却循环。

**局势因子**（影响评分）：

| 因子 | 说明 | 影响 |
|------|------|------|
| **球权归属** | 我方持球 vs 对方持球 vs 争球 | 不再简单二值化：我方持球时防守技也有价值（防止被抢断后立即丢分），对方持球时进攻技也有价值（准备反击） |
| **分差** | 领先 vs 落后 | 落后→冒险技能加分；领先→保守技能加分 |
| **体力比** | 我方/对方体力状态 | 我方体力低→恢复技加分；对方体力低→终结技加分 |
| **时间节点** | 开场/中场/末段 | 末段→全力进攻加分；开场→保留能量 |
| **人数差** | 我方/对方被罚下人数 | 少打多→防御/控制技加分；多打少→进攻技加分 |
| **球飞行状态** | 球在飞 vs 球在手里 | BALL类技能必须在持球/投球前用 |
| **进攻窗口** | 是否有明确的得分机会 | 窗口出现时，任何能抓住窗口的技能大幅加分 |

**为什么**：真实球员不会无脑放技能，会根据场上情况判断"现在是不是好时机"。而且真实球员也不会我方持球时完全不考虑防守——持球时被抢断的风险始终存在，聪明的玩家会同时评估攻防。

---

### 原则4：动态资源管理（Dynamic Resource Management）

**设计**：AI 管理元灵能量不是靠固定百分比阈值，而是动态评估"现在用的价值"vs"留到未来的预期价值"。

**旧版错误**：0-30%保留期/30-60%谨慎期/60-100%充裕期——这种固定三档把AI变成了死板的能量守财奴。真实玩家不是按百分比管理的：关键球时刻10%能量也会用，垃圾时间90%能量也可能不用。

#### 动态能量价值评估

**核心公式**：

```
energy_value_now = current_skill_score    # 现在用这个技能的评分
energy_value_future = expected_future_score × time_remaining_ratio × uncertainty_discount

should_use_energy = energy_value_now > energy_value_future × reserve_weight
```

| 变量 | 含义 |
|------|------|
| `expected_future_score` | 未来可能出现更高价值技能使用的预期评分 |
| `time_remaining_ratio` | 剩余时间比例（越接近结束，未来价值越低→越该现在用） |
| `uncertainty_discount` | 不确定性折扣（未来机会不确定，打折） |
| `reserve_weight` | 保留权重（受角色风格和局势影响） |

#### 角色风格的保留权重

| 角色 | reserve_weight | 行为表现 |
|------|---------------|---------|
| 主攻手（机会型） | 0.7 | 更倾向现在用——因为进攻窗口稍纵即逝 |
| 防御手（预判型） | 1.1 | 更倾向保留——因为要等对方进攻时再精准反制 |
| 辅助手（响应型） | 0.9 | 接近中性——根据队友缺口程度动态调整 |

#### 局势对保留权重的影响

| 局势 | reserve_weight 变化 | 原因 |
|------|-------------------|------|
| 末段（最后20%时间） | × 0.5 | 未来不多了，不用就浪费 |
| 落后 | × 0.7 | 需要现在追分 |
| 领先 | × 1.3 | 保留能量应对对方反扑 |
| 进攻窗口出现 | × 0.3 | 窗口难得，立刻投入 |
| 对方全员健康 | × 1.2 | 对方威胁大，留能量防守 |

**为什么这样改**：
- 固定阈值无法区分"现在该用但能量低"和"不该用但能量高"的情况
- 动态评估让AI像真实玩家一样：看到好机会果断用，没好机会耐心等
- 关键球时刻AI不会因为"能量在保留线以下"就不救命

---

### 原则5：技能意图适配（Intent-Appropriate Targeting）

**设计**：技能的使用时机和目标选择由其**意图**决定，而非仅由类型标签决定。同一类型标签的技能在不同意图下有完全不同的使用逻辑。

**旧版错误**：FIELD类技能只写"对方持球推进时放障碍"——但进攻时放障碍挡住对方防守路线也是合理策略，同一技能可以有攻防两种用法。

#### BALL 类技能（球强化/球属性修改）
- **进攻意图**：持球时，即将投球前，强化球属性以增加得分概率
- **防御意图**：持球被逼抢时，给球加减速/变向属性以安全转移球权
- **使用时机**：持球时 / 即将投球前 / 被逼抢需要保球时
- **目标选择**：球本身（不需要选目标）
- **评分重点**：得分概率提升 / 球权安全提升

#### FIELD 类技能（场地/障碍/区域效果）
- **防御意图**：对方持球推进时放障碍拦截，延缓对方进攻
- **进攻意图**：我方持球时在对方防守路径上放障碍，创造进攻空间
- **支援意图**：在关键区域放置增益/减益区域，改变局部战局
- **使用时机**：不再是"只有对方持球时才用"
- **目标选择**：根据意图选择位置——拦截对方路径 / 遮挡对方防守 / 控制关键区域
- **评分重点**：拦截成功率 / 进攻空间创造价值 / 区域控制价值

#### PLAYER 类技能（buff/debuff/恢复/状态）
- **进攻意图**：给自己加攻击buff（进攻准备），给敌人加减速debuff（削弱防守）
- **防御意图**：给自己/队友加防（保护球权/站位），给敌人减攻（降低威胁）
- **支援意图**：给队友回血/加buff（补短板），给敌人群体debuff（团队收益）
- **使用时机**：不再是"体力低才用"——进攻前给自己加攻buff也是好时机
- **目标选择**：根据意图选目标——要进攻的队友 / 需要保护的队友 / 最具威胁的敌人
- **评分重点**：意图匹配度 + 目标当前状态 + 技能收益

---

### 原则6：数值外置 + 可调试（Data-Driven & Tunable）

**设计**：所有技能 AI 参数全部在 AIProfile 中，调平衡不改代码。

**参数清单**（全部 profile 化）：

| 参数 | 作用 | 默认值 |
|------|------|--------|
| `skill_use_threshold` | 技能释放评分阈值（达到才用） | 40.0 |
| `skill_energy_min` | 使用技能的最低能量要求 | 20.0 |
| `reserve_weight` | 能量保留权重（越高越倾向保留能量） | 0.9 |
| `attack_intent_weight` | 进攻意图匹配权重 | 1.0 |
| `defense_intent_weight` | 防御意图匹配权重 | 1.0 |
| `support_intent_weight` | 支援意图匹配权重 | 1.0 |
| `skill_think_interval` | 技能决策间隔（秒） | 0.5 |
| `skill_late_game_bonus` | 末段技能释放加成 | 1.5 |
| `skill_losing_bonus` | 落后时技能释放加成 | 1.3 |
| `skill_leading_penalty` | 领先时技能释放惩罚 | 0.7 |
| `uncertainty_discount` | 未来机会不确定性折扣 | 0.6 |
| `expected_future_score` | 未来技能使用预期评分（基准） | 50.0 |
| `synergy_bonus_critical` | 关键协同技能加成 | 1.5 |
| `synergy_bonus_high` | 高协同技能加成 | 1.3 |
| `element_counter_bonus` | 元素克制加成 | 1.3 |
| `element_counter_penalty` | 元素被克制惩罚 | 0.7 |
| `combo_bonus` | 连招组合额外加成 | 0.5 |
| `threat_assessment_weight` | 威胁评估权重（影响目标选择） | 0.3 |
| `distance_factor_weight` | 距离因素权重（影响目标选择） | 0.1 |

**为什么**：平衡调优时只改参数，不动引擎代码。

---

### 原则7：复合技能处理（Multi-Tag Skills）

**设计**：一个技能可以同时含有多个标签（球+球员+场），AI 不应强行归类到某一个标签，而要按多标签加权综合评估。

**数据格式**：
- 单标签（兼容）：`"tag": "on_ball"`
- 多标签（新格式）：`"tag": ["on_ball", "on_player"]`

**多标签权重规则**：

| 标签数 | 权重 | 解释 |
|--------|------|------|
| 1个 | 100% | 纯单标签技能 |
| 2个 | 各70% | 双标签复合（如球+球员），各取70%求和 |
| 3个 | 各50% | 三标签复合（如球+球员+场），各取50%求和 |

**为什么这样设计**：
- 复合技能应该比单一标签强（多个效果），但又不应过强（避免复合技能成为唯一选择）
- 70%/50% 是经验值，能让复合技能略强于纯标签但不会过强
- 不用"加和再除"是因为那样复合技能反而比单标签弱（违背复合技能本意）

**应用范围**：

| 评估项 | 单标签处理 | 多标签处理 |
|--------|----------|----------|
| **基础价值 base_value** | 直接按该标签计算 | 各标签价值×权重后求和 |
| **意图匹配 intent_match** | 单一意图分布 | 各标签意图×权重后叠加 |
| **使用时机** | 按主标签决定 | 各标签独立判断，全满足才用 |
| **目标选择** | 按主标签选目标 | 主标签选目标，副标签作为额外评估 |
| **协同度计算** | 与球员属性匹配度 | 各标签分别计算后取最高 |

**示例：假想复合技能 "火球·爆焰"**（`on_ball` + `on_player`）
- 效果：球伤害+20 + 击退+20% + 击退时给目标玩家附带灼烧debuff
- 标签数=2，权重各70%
- 基础价值 = (球价值: 30×0.7) + (球员价值: 15×0.7) = 31.5（比纯球强化技能15分高，但不会过强）
- 意图分布 = (球意图: 攻击0.7) + (球员意图: 攻击0.3) = 攻击型复合技能

**示例：实际技能 "冰冻之球"**（`on_ball` 单标签 + 减速25%）
- 标签数=1，权重100%
- 基础价值按球类算（含减速效果）
- 意图 = 攻击0.7 + 控制0.3（减速效果提升控制权重）

**为什么原则5 也要改**：
- 原则5原写"FIELD类技能只在对方持球推进时放"——错，进攻时放障碍挡防守者也是合理用法
- 多意图分析必须支持（"对方进攻时" = 防御意图，"我方进攻时" = 进攻意图）
- 复合技能的意图是多意图混合，要用加权融合

---

## 三、决策流程

```
每 skill_think_interval 秒决策一次
  ↓
1. 检查能量 < skill_energy_min → 跳过
2. 获取所有可用技能（冷却已结束 + 能量足够）
3. 读取每个技能的 tag 字段
   - 单 tag：直接使用
   - 多 tag：按权重规则拆分计算（70%/50%）
4. 对每个技能：
   a. 按所有标签分别计算价值 → 加权求和得 base_value
   b. 按所有标签分别计算意图 → 加权叠加得意图分布
   c. 主标签 = 价值最高标签 → 决定使用时机和目标选择
   d. 乘以局势因子（球权/分差/体力/时间/人数/进攻窗口）
   e. 乘以意图匹配度 intent_match（角色视角 × 意图权重）
   f. 乘以协同度（与球员属性的匹配度，复合技能取最高标签协同度）
   g. 动态能量评估：现在用的价值 vs 保留到未来的价值
5. 选最高分技能
6. 最高分 >= skill_use_threshold 且 能量动态评估通过 → 释放
   否则 → 等待下次决策
```

---

## 四、与六大AI原则的对应关系

| AI总原则 | 在技能AI中的体现 |
|---------|-----------------|
| **分层职责** | 参数在 AIProfile，决策在 ai_manager，零硬编码 |
| **有限信息** | 技能决策基于 AI 感知到的信息（不是全局全知），感知不到的敌人/队友不参与评分 |
| **个性失误节奏** | 不同角色评估视角不同（不是类型偏好）；释放时机有随机偏差；偶尔"误判"（早用/晚用） |
| **队形优先** | FIELD类技能释放考虑阵型位置，不破坏自己队形 |
| **对手有弱点** | 对手AI的技能使用有设计性缺陷（如评估视角片面/能量管理差） |
| **数值外置** | 所有参数在 AIProfile，可通过备战面板调整 |

---

## 五、实现优先级

### Phase 1：基础可用
- [ ] 技能评分框架（通用评分函数）
- [ ] BALL 类技能 AI（持球时释放球强化）
- [ ] 能量检查 + 冷却检查
- [ ] 角色偏好参数 + 阈值

### Phase 2：PLAYER 类
- [ ] PLAYER 类技能 AI（给自己/队友加buff/恢复）
- [ ] 目标选择（最需要的队友/最危险的敌人）
- [ ] 局势因子（体力比/人数差）

### Phase 3：FIELD 类
- [ ] FIELD 类技能 AI（放障碍/区域效果）
- [ ] 目标位置预测（对方移动路径）
- [ ] 区域控制价值评估

### Phase 4：高级
- [ ] 团队配合（队友技能联动）
- [ ] 对手弱点系统扩展（技能使用相关弱点）
- [ ] 元灵元素克制系统

---

## 六、段位难度系统

> **设计目标**：通过统一的难度缩放公式，让同一套AI逻辑在不同段位表现出不同强度。段位系统后续开发，当前先用难度等级（1-10级）对接。

### 6.1 段位与难度等级映射

| 段位 | 难度等级 | 定位 | 说明 |
|------|---------|------|------|
| 青铜 | 1-2 | 入门 | 技能很少用，能量管理差，经常错过时机 |
| 白银 | 3-4 | 普通 | 偶尔用技能，偏好单一类型，失误较多 |
| 黄金 | 5-6 | 中等 | 正常使用技能，有基本的局势判断，偶有失误 |
| 铂金 | 7-8 | 进阶 | 技能使用合理，能量管理好，较少失误 |
| 钻石 | 9 | 高手 | 技能时机精准，连招意识强，几乎不失误 |
| 王者 | 10 | 顶尖 | 最优决策，完美能量管理，零失误（接近理论最优） |

### 6.2 难度影响参数一览

难度通过**缩放系数**影响以下参数，公式见 6.3 节。

| 参数 | 难度影响方向 | 说明 |
|------|------------|------|
| `skill_use_threshold` | 难度↑ → 阈值↓ | 低难度AI犹豫不用，高难度AI敢用 |
| `skill_energy_min` | 难度↑ → 下限↓ | 低难度AI能量多了才敢用，高难度AI精打细算 |
| `reserve_weight` | 难度↑ → 保留权重动态化 | 低难度AI倾向攒能量不用，高难度AI根据局势动态调整 |
| `skill_accuracy` | 难度↑ → 精准度↑ | 影响目标选择和时机判断的误差 |
| `skill_mistake_chance` | 难度↑ → 失误率↓ | 偶尔用错技能/选错目标的概率 |
| `skill_late_game_bonus` | 难度↑ → 末段加成↑ | 高难度AI更懂末段爆发 |
| `situation_reading_depth` | 难度↑ → 局势阅读深度↑ | 低难度只看1-2个因子，高难度综合判断 |
| `uncertainty_discount` | 难度↑ → 折扣降低 | 低难度对未来不确定更保守，高难度更相信预判 |

### 6.3 难度缩放公式

#### 核心公式：线性插值 + 边界裁剪

```
difficulty_level ∈ [1, 10]
normalized_difficulty = (difficulty_level - 1) / 9    # 归一化到 [0, 1]

参数实际值 = base_value * (1 + (normalized_difficulty - 0.5) * 2 * scale_range)
最终值 = clamp(参数实际值, min_value, max_value)
```

**说明**：
- `base_value`：难度5时的基准值（中等难度）
- `scale_range`：该参数随难度变化的幅度（如 0.5 表示 ±50% 波动）
- 难度1 = 基准值 × (1 - scale_range)
- 难度10 = 基准值 × (1 + scale_range)
- 难度5 = 基准值 × 1.0

#### 各参数难度缩放表

| 参数 | base_value（难度5） | scale_range | min_value | max_value |
|------|---------------------|-------------|-----------|-----------|
| `skill_use_threshold` | 40.0 | 0.4 | 24.0 | 56.0 |
| `skill_energy_min` | 20.0 | 0.5 | 10.0 | 30.0 |
| `reserve_weight` | 0.9 | 0.3 | 0.63 | 1.17 |
| `skill_accuracy` | 0.7 | 0.3 | 0.4 | 1.0 |
| `skill_mistake_chance` | 0.15 | 0.6 | 0.0 | 0.3 |
| `skill_late_game_bonus` | 1.5 | 0.3 | 1.05 | 1.95 |
| `situation_reading_depth` | 3 | — | 1 | 6 |
| `uncertainty_discount` | 0.6 | 0.3 | 0.42 | 0.78 |

#### 难度应用示例

```
例：难度1（青铜）的 skill_use_threshold
normalized_difficulty = (1 - 1) / 9 = 0
实际值 = 40.0 × (1 + (0 - 0.5) × 2 × 0.4)
      = 40.0 × (1 - 0.4)
      = 40.0 × 0.6
      = 24.0

例：难度10（王者）的 skill_use_threshold
normalized_difficulty = (10 - 1) / 9 = 1.0
实际值 = 40.0 × (1 + (1.0 - 0.5) × 2 × 0.4)
      = 40.0 × (1 + 0.4)
      = 40.0 × 1.4
      = 56.0
```

---

## 七、数学公式详解

> **业内参考**：基于 Utility AI（效用AI）理论，参考 Dave Mark 的《Behavioral Mathematics for Game AI》和 F.E.A.R. 的 GOAP 系统中的响应曲线设计思想。核心思路：**用连续的效用函数替代离散的条件判断，让决策更平滑自然**。

### 7.1 总评分公式

```
total_score = base_value × situation_factor × intent_match × difficulty_modifier
```

| 变量 | 含义 | 取值范围 |
|------|------|---------|
| `base_value` | 技能基础价值（由技能效果强度决定） | [10, 100] |
| `situation_factor` | 局势综合因子 | [0, ~3.0] |
| `intent_match` | 角色-意图匹配度（取代原来的role_preference） | [0.5, 2.0] |
| `difficulty_modifier` | 难度修正（影响"敢不敢用"） | [0.5, 1.5] |

> **修正说明**：旧版用 `role_preference`（角色对BALL/FIELD/PLAYER的偏好），新版用 `intent_match`（角色对技能意图的匹配度）。本质区别：主攻手不是"不爱PLAYER技能"，而是"评估一切技能的进攻价值"。

### 7.2 技能基础价值 base_value

**公式**：按技能效果类型加权求和

```
base_value = Σ(effect_i × weight_i)
```

| 效果类型 | 权重 weight | 说明 |
|---------|------------|------|
| 伤害提升 | 1.0 / 每10%伤害 | 伤害越高基础价值越高 |
| 速度提升 | 0.8 / 每10%速度 | 速度提升价值略低于伤害 |
| 防御提升 | 0.7 / 每10%防御 | 防御提升价值中等 |
| 恢复量 | 0.6 / 每10%体力恢复 | 恢复类技能基础价值偏低 |
| 控制时长 | 1.2 / 每秒控制 | 控制类技能基础价值高 |
| 范围半径 | 0.5 / 每10px范围 | 范围效果有额外价值 |

**示例**：
- 一个 +30% 伤害 + 20% 速度的 BALL 技能：
  `base_value = 30%/10% × 1.0 + 20%/10% × 0.8 = 3.0 + 1.6 = 4.6 → 归一化到 46 分`

### 7.3 局势综合因子 situation_factor

**公式**：各局势因子相乘（或加权几何平均）

```
situation_factor = (possession_factor × score_diff_factor × stamina_factor × time_factor × numbers_factor) ^ (1 / situation_reading_depth)
```

> **设计说明**：参考 Utility AI 的乘法合成模型。难度越高，`situation_reading_depth` 越大，对局势的判断越全面；低难度 AI 只看少数几个因子，判断片面。

---

#### 7.3.1 球权因子 possession_factor

**类型**：连续梯度函数（取代旧版阶跃二值函数）

**旧版问题**：我方持球时攻击技1.5/防守技0.5——但真实比赛中，持球时也需要考虑防守（防止被抢断），对方持球时进攻技也有价值（准备反击）。

**公式**：

```
ball_possession = 我方控球概率    # [0, 1]，基于球权归属和球距

# 不再是简单的二值判断，而是连续梯度
# 我方持球：ball_possession ≈ 0.8~1.0
# 争球/球在飞：ball_possession ≈ 0.5
# 对方持球：ball_possession ≈ 0.0~0.2

possession_factor = lerp(defense_value, attack_value, ball_possession)

# attack_value 和 defense_value 由技能意图决定：

if 技能意图 == 进攻意图：
    attack_value = 1.6    # 我方持球时进攻技高价值
    defense_value = 0.7   # 对方持球时进攻技仍有反击价值（不是0.5）

if 技能意图 == 防御意图：
    attack_value = 0.8    # 我方持球时防御技有保护球权价值（不是0.5）
    defense_value = 1.7   # 对方持球时防御技最高价值

if 技能意图 == 支援意图：
    attack_value = 1.1    # 我方持球时支援进攻
    defense_value = 1.2   # 对方持球时支援防守
```

**对比旧版**：

| 场景 | 旧版（主攻手+PLAYER技能） | 新版（主攻手+进攻意图PLAYER技能） |
|------|-------------------------|-------------------------------|
| 我方持球+给自己加攻buff | 0.7×1.0=0.7（"不爱给自己buff"） | 1.6×1.4=2.24（进攻准备，高价值！） |
| 对方持球+给自己加防 | 0.7×1.0=0.7 | 0.7×1.0=0.7（保护自己等反击机会） |
| 我方持球+放障碍 | 0.9×1.0=0.9 | 1.6×1.1=1.76（挡住防守者=进攻空间） |

**业内参考**：连续梯度评估（Continuous Gradient Evaluation），取代离散状态切换，更接近人类决策的模糊性。

---

#### 7.3.2 分差因子 score_diff_factor

**类型**：Sigmoid / Logistic 响应曲线

**公式**：

```
score_diff = 我方得分 - 对方得分
max_expected_diff = 10    # 预期最大分差（用于归一化）
normalized_diff = score_diff / max_expected_diff    # [-1, 1]

# 落后时冒险加分，领先时保守减分
# 参考 Logistic 函数：f(x) = L / (1 + e^(-k(x - x0)))
if 技能类型 == 攻击型：
    # 落后越多，攻击技能价值越高（S型曲线）
    score_diff_factor = 1.0 + 0.8 / (1 + exp(3 × normalized_diff))
    # 落后很多(normalized_diff=-1) → 1.0 + 0.8/(1+e^-3) ≈ 1.76
    # 领先很多(normalized_diff=1) → 1.0 + 0.8/(1+e^3) ≈ 1.04

if 技能类型 == 防守型：
    # 领先越多，防守技能价值越高
    score_diff_factor = 1.0 + 0.8 / (1 + exp(-3 × normalized_diff))
    # 领先很多 → ≈1.76，落后很多 → ≈1.04

if 技能类型 == 辅助型：
    # 辅助技能受分差影响较小
    score_diff_factor = 1.0 + 0.3 × sin(π × normalized_diff / 2)
    # 范围：[0.7, 1.3]
```

**响应曲线图**：

```
攻击型技能
1.8 ┤        ╭───────
    │      ╭╯
1.4 ┤    ╭╯
    │  ╭╯
1.0 ┤─╯
    ╰─────────────────
    -1    0     1    分差(归一化)

防守型技能
1.8 ┼───────╮
    │        ╰╮
1.4 ┤          ╰╮
    │            ╰╮
1.0 ┼──────────────╯─
    -1    0     1
```

**业内参考**：Dave Mark 提出的 Sigmoid 响应曲线，用于处理"越多越好但有上限"的关系，避免线性函数的极端值问题。

---

#### 7.3.3 体力比因子 stamina_factor

**类型**：指数响应曲线

**公式**：

```
target_stamina_ratio = 目标当前体力 / 目标最大体力    # [0, 1]

# 恢复类技能：目标体力越低，价值越高（指数增长）
if 技能类型 == 恢复型：
    stamina_factor = exp(2 × (1 - target_stamina_ratio)) - 1
    # 体力满(1.0) → e^0 - 1 = 0
    # 体力半(0.5) → e^1 - 1 ≈ 1.72
    # 体力空(0.0) → e^2 - 1 ≈ 6.39

# 伤害类技能：对方体力越低，终结价值越高（指数增长）
if 技能类型 == 攻击型 and 目标是敌人：
    stamina_factor = 0.5 + exp(-2 × target_stamina_ratio)
    # 敌方体力满 → 0.5 + e^-2 ≈ 0.64
    # 敌方体力半 → 0.5 + e^-1 ≈ 0.87
    # 敌方体力空 → 0.5 + e^0 = 1.5

# 防御类技能：我方体力越低，防御越重要
if 技能类型 == 防守型 and 目标是友方：
    stamina_factor = 1.0 + 0.8 × (1 - target_stamina_ratio)^2
    # 体力满 → 1.0
    # 体力半 → 1.0 + 0.8 × 0.25 = 1.2
    # 体力空 → 1.8
```

**业内参考**：指数响应曲线（Exponential Response Curve），用于"低的时候价值飙升"的场景，如残血时的治疗和终结技能。

---

#### 7.3.4 时间节点因子 time_factor

**类型**：分段线性函数 + 末段指数加速

**公式**：

```
time_progress = 已过时间 / 总比赛时间    # [0, 1]

if time_progress < 0.7:
    # 前70%时间：线性增长，谨慎使用
    time_factor = 0.7 + 0.3 × time_progress / 0.7
    # 开场(0) → 0.7，70%时间 → 1.0
elif time_progress < 0.9:
    # 70%-90%：线性增长到末段加成
    time_factor = 1.0 + (skill_late_game_bonus - 1.0) × (time_progress - 0.7) / 0.2
else:
    # 最后10%：指数级爆发
    t = (time_progress - 0.9) / 0.1    # [0, 1]
    time_factor = skill_late_game_bonus × (1 + 0.3 × exp(2 × t - 2))
    # 90%时间 → skill_late_game_bonus × (1 + 0.3×e^-2) ≈ bonus × 1.04
    # 结束时 → skill_late_game_bonus × (1 + 0.3×e^0) = bonus × 1.3
```

**曲线图**：

```
1.6 ┤                    ╭╮
    │                  ╭╯ │
1.3 ┤                ╭╯   │  末段指数加速
    │              ╭─╯    │
1.0 ┼─────────────╯       │
    │    线性增长          │
0.7 ┼────                 │
    0    0.7   0.9   1.0
         时间进度
```

**业内参考**：分段函数（Piecewise Function）+ 末段指数爆发，模拟真实比赛"最后时刻孤注一掷"的心理。

---

#### 7.3.5 人数差因子 numbers_factor

**类型**：线性加权函数

**公式**：

```
numbers_diff = 我方在场人数 - 对方在场人数    # [-2, 2]（假设3v3）

if 技能类型 == 攻击型：
    numbers_factor = 1.0 + 0.2 × numbers_diff
    # 多打少(+2) → 1.4
    # 少打多(-2) → 0.6

if 技能类型 == 防守型：
    numbers_factor = 1.0 - 0.25 × numbers_diff
    # 多打少(+2) → 0.5（不需要那么多防守）
    # 少打多(-2) → 1.5（防守更重要）

if 技能类型 == 辅助型：
    numbers_factor = 1.0 + 0.15 × abs(numbers_diff)
    # 人数差越大，辅助技能越有价值（拉平差距）
    # 差2人 → 1.3
```

**业内参考**：线性响应曲线（Linear Response Curve），适用于"越多越..."且关系简单直接的场景。

### 7.4 意图匹配度 intent_match（取代旧版 role_preference）

**核心思想**：角色对技能的匹配度取决于"这个技能在角色评估视角下属于什么意图"，而非"这个技能属于BALL/FIELD/PLAYER哪种类型"。

**公式**：

```
# 1. 确定角色视角下该技能的意图
skill_intent = determine_intent(role, skill)    # 进攻/防御/支援

# 2. 取角色对应意图的权重
intent_weight = get_intent_weight(role, skill_intent)
#   主攻手: attack=1.4, defense=0.9, support=1.0
#   防御手: attack=0.9, defense=1.4, support=1.0
#   辅助手: attack=1.0, defense=1.0, support=1.4

# 3. 计算意图匹配度
intent_match = intent_weight × situation_intent_bonus
```

#### 角色意图权重表

| 角色 | 进攻意图权重 | 防御意图权重 | 支援意图权重 |
|------|------------|------------|------------|
| 主攻手 | 1.4 | 0.9 | 1.0 |
| 防御手 | 0.9 | 1.4 | 1.0 |
| 辅助手 | 1.0 | 1.0 | 1.4 |

> **注意**：所有权重最低都是0.9，不是0.3/0.6这种极端值。角色不是"完全不会某类技能"，只是"评估重心不同"。

#### 意图判定逻辑 determine_intent

同一技能在不同角色/局势下可能判定为不同意图：

```
func determine_intent(role: String, skill: SkillData, situation: Dictionary) -> String:
    # 1. 技能自身有默认意图标签
    var default_intent = skill.default_intent    # "attack"/"defense"/"support"
    
    # 2. 角色视角可能改变意图判定
    match role:
        "attacker":
            # 主攻手视角：几乎所有给自己加的buff都视为进攻意图
            if skill.target == self and skill.effect_type == "buff":
                return "attack"    # 给自己加攻=进攻准备
            if skill.target == enemy and skill.effect_type == "debuff":
                return "attack"    # 给敌人加debuff=削弱对方防守
        
        "defender":
            # 防御手视角：反击时球强化视为防御意图（转守为攻）
            if skill.type == "BALL" and situation.ball_possession < 0.3:
                return "defense"    # 反击中保球=防御延续
            # 给自己加防=核心防御
            if skill.target == self and skill.effect_type == "buff":
                return "defense"
        
        "support":
            # 辅助手视角：给任何队友加buff都视为支援意图
            if skill.target == teammate:
                return "support"
    
    return default_intent
```

#### situation_intent_bonus（局势加成）

局势对意图匹配度的加成——特定局势下，某种意图的技能额外加分：

```
situation_intent_bonus = 1.0    # 基础值

# 进攻窗口出现时
if has_attack_window() and skill_intent == "attack":
    situation_intent_bonus = 1.4

# 被逼抢时
if under_pressure() and skill_intent == "defense":
    situation_intent_bonus = 1.3

# 队友残血时
if any_teammate_low_health() and skill_intent == "support":
    situation_intent_bonus = 1.3
```

#### 对比旧版

| 技能 | 角色 | 旧版 role_preference | 新版 intent_match | 差异 |
|------|------|---------------------|-------------------|------|
| 给自己加攻buff | 主攻手 | 0.7（"PLAYER偏好低"） | 1.4×1.0=1.4（进攻意图高匹配） | **翻倍** |
| 给自己加防 | 主攻手 | 0.7（"PLAYER偏好低"） | 0.9×1.0=0.9（防御意图低匹配但不是极端低） | 合理 |
| 放障碍 | 主攻手 | 0.9（"FIELD偏好中"） | 1.4×1.0=1.4（进攻意图：创造空间） | 合理 |
| 球强化 | 防御手 | 0.6（"BALL偏好低"） | 0.9×1.0=0.9（反击时有价值） | 不再极端低 |

### 7.5 动态能量评估（取代旧版固定阈值 resource_factor）

**旧版问题**：0-30%保留期/30-60%谨慎期/60-100%充裕期的固定三档，无法区分"关键球+低能量"和"垃圾时间+高能量"。

**新版核心**：动态比较"现在用的价值"与"留到未来的预期价值"。

#### 公式

```
# 当前技能评分（已算完 base_value × situation_factor × intent_match × difficulty_modifier）
energy_value_now = total_score

# 未来预期价值
time_remaining = 1.0 - time_progress    # 剩余时间比例 [0, 1]
energy_value_future = expected_future_score × time_remaining × uncertainty_discount

# 动态保留决策
effective_reserve_weight = reserve_weight × situation_reserve_modifier
should_use = energy_value_now > energy_value_future × effective_reserve_weight

# 如果决定不用，资源修正因子为0（不释放）
# 如果决定用，计算能量充裕度修正因子
if should_use:
    energy_ratio = current_energy / max_energy    # [0, 1]
    # 能量越充裕，评分微增（更从容的决策）
    # 能量越紧张，评分微降（紧迫感，但不是不能用）
    energy_modifier = 0.85 + 0.3 × energy_ratio
    # 能量满 → 1.15（从容）
    # 能量半 → 1.0（中性）
    # 能量空 → 0.85（紧迫但仍可用）
else:
    energy_modifier = 0    # 不释放
```

#### 局势保留修正 situation_reserve_modifier

```
situation_reserve_modifier = 1.0    # 基础值

# 末段：未来不多了，降低保留意愿
if time_progress > 0.8:
    situation_reserve_modifier *= 0.5

# 落后：需要现在追分
if score_diff < 0:
    situation_reserve_modifier *= 0.7

# 领先：保留能量防守
if score_diff > 0:
    situation_reserve_modifier *= 1.3

# 进攻窗口出现：立即投入
if has_attack_window():
    situation_reserve_modifier *= 0.3

# 队友残血：保人优先
if any_teammate_critical():
    situation_reserve_modifier *= 0.6
```

#### 角色风格对 reserve_weight 的影响

| 角色 | reserve_weight | 行为特征 |
|------|---------------|---------|
| 主攻手 | 0.7 | 更倾向现在用——进攻窗口稍纵即逝 |
| 防御手 | 1.1 | 更倾向保留——等对方进攻时精准反制 |
| 辅助手 | 0.9 | 接近中性——根据队友缺口调整 |

#### 对比旧版

| 场景 | 旧版（固定阈值） | 新版（动态评估） |
|------|----------------|----------------|
| 关键球+能量25% | 0.007（保留线以下，几乎不用） | energy_value_now >> future → 用！（关键球不管能量多少） |
| 垃圾时间+能量80% | 1.24（充裕期正常用） | energy_value_now < future → 不用（没好机会，不如留着） |
| 末段+落后+能量40% | 谨慎期+末段加成≈1.0 | 0.7×0.5×0.7=0.245 → 大幅倾向现在用 |

**业内参考**：机会成本评估（Opportunity Cost Evaluation），源自经济学决策理论。AI不再按固定百分比管理资源，而是按"现在用的机会成本 vs 未来预期收益"动态决策。

### 7.6 难度修正与失误机制

#### 7.6.1 难度修正 difficulty_modifier

```
difficulty_modifier = 1.0 + (normalized_difficulty - 0.5) × 0.6
# 难度1 → 1.0 - 0.3 = 0.7（AI评分偏低，不容易触发）
# 难度5 → 1.0
# 难度10 → 1.0 + 0.3 = 1.3（AI评分偏高，更敢用）
```

#### 7.6.2 失误机制 mistake_chance

**类型**：随机扰动 + 难度控制

```
if randf() < skill_mistake_chance:
    # 发生失误：随机选择以下一种
    mistake_type = random_choice(["timing", "target", "wrong_skill"])
    
    if mistake_type == "timing":
        # 时机失误：评分×随机系数，导致早用/晚用
        total_score *= randf_range(0.5, 1.5)
    
    elif mistake_type == "target":
        # 目标失误：从可用目标中随机选一个（而非最优）
        selected_target = random_choice(all_targets)
    
    elif mistake_type == "wrong_skill":
        # 技能失误：用低分技能替代高分技能
        selected_skill = random_choice(available_skills)
```

**业内参考**：参考《AI Game Programming Wisdom》系列中的"Imperfect AI"设计理念——让AI有不完美的决策，更像真人。

### 7.7 最终决策：Softmax 选择（可选，高难度用）

> 低难度直接选最高分，高难度用 Softmax 引入概率分布，更自然。

**公式**：

```
对于 N 个可用技能，每个技能分数为 s_i

softmax_prob_i = exp(s_i / temperature) / Σ(exp(s_j / temperature))

然后按概率分布随机选择，而不是一定选最高分。
```

- `temperature`（温度）：控制选择的确定性
  - 温度高（如 2.0）→ 概率分布更平均，更随机
  - 温度低（如 0.5）→ 概率分布更集中，更倾向最高分
  - 温度→0 → 等同于选最高分（argmax）

**难度与温度的关系**：
```
temperature = 2.0 - normalized_difficulty × 1.5
# 难度1 → 2.0（很随机）
# 难度5 → 1.25（中等随机）
# 难度10 → 0.5（几乎选最优）
```

**业内参考**：强化学习中的 Softmax 探索策略（Boltzmann Exploration），平衡"探索（尝试新策略）"与"利用（选当前最优）"。

---

## 八、业内设计参考总结

| 设计点 | 参考来源/理论 | 对应章节 |
|--------|-------------|---------|
| 效用驱动决策（Utility AI） | Dave Mark, *Behavioral Mathematics for Game AI* | 7.1 总评分公式 |
| 技能意图系统 | Personality-based AI + 角色视角评估理论 | 原则2 角色视角差异化 / 7.4 意图匹配度 |
| 乘法合成模型 | 经典 Utility AI 合成方法 | 7.3 局势综合因子 |
| 连续梯度评估 | Continuous Gradient Evaluation | 7.3.1 球权因子（取代旧版二值阶跃） |
| Sigmoid / Logistic 响应曲线 | Dave Mark 响应曲线理论 | 7.3.2 分差因子 |
| 指数响应曲线 | Exponential Response Curve | 7.3.3 体力比因子 |
| 分段线性函数 | Piecewise Function | 7.3.4 时间节点因子 |
| 动态能量评估（机会成本） | 经济学 Opportunity Cost 理论 | 7.5 动态能量评估（取代旧版固定阈值） |
| Softmax 概率选择 | 强化学习 Boltzmann Exploration | 7.7 Softmax 选择 |
| 不完美决策/失误机制 | *AI Game Programming Wisdom* Imperfect AI | 7.6.2 失误机制 |
| 难度缩放系统 | Dynamic Difficulty Adjustment (DDA) | 第六章 段位难度系统 |
| 意图判定逻辑 | Goal-Oriented Action Planning (GOAP) 的目标驱动思想 | 7.4 determine_intent 函数 |

---

## 九、赛前技能组合分析（个性化决策模板生成）

> **核心设计**：技能AI不是固定的"职位模板"，而是根据具体球员+元灵组合生成个性化决策模板。比赛开始前完成分析，比赛中按模板决策。

### 9.1 分析时机

| 时机 | 触发条件 | 分析内容 |
|------|---------|---------|
| **赛前准备阶段** | 玩家进入备战界面，选择球员+元灵 | 生成完整个性化模板 |
| **中场休息** | 半场结束，玩家可能更换元灵 | 重新分析变更部分 |
| **比赛进行中** | 元灵等级提升/技能解锁 | 增量更新模板 |

### 9.2 分析输入数据

#### 9.2.1 球员属性（从 characters.json 读取）

| 属性 | 字段 | 作用 |
|------|------|------|
| 攻击力 | `attack` | 评估攻击技能的基础伤害加成 |
| 防御力 | `defense` | 评估防御技能的必要性——防御低的球员更需要防御buff |
| 速度 | `speed` | 评估追击/逃跑能力——速度快的球员更适合进攻走位 |
| 体力 | `stamina` | 评估生存能力——体力低的球员更需要恢复技能 |
| 韧性 | `resilience` | 评估击退抵抗能力——韧性低的球员更需要减控技能 |
| 球速 | `ball_speed` | 评估投球威胁——球速快的球员配合球强化技能效果更好 |
| 天赋 | `talent_name` / `talent_desc` | 特殊能力——如"体力低于30%攻击力+15%"会改变技能使用时机 |

#### 9.2.2 元灵技能数据（从 skills.json + tags_registry.json 读取）

| 字段 | 作用 |
|------|------|
| `id` | 技能唯一标识 |
| `name` | 技能名称 |
| `element` | 元素属性（用于元素克制） |
| `energy_cost` | 能量消耗——影响技能使用频率 |
| `cooldown` | 冷却时间——影响技能使用节奏 |
| `tags` | 标签列表——决定技能效果类型 |
| `tag_params` | 标签参数——决定技能效果强度 |

### 9.3 个性化决策模板结构

```json
{
  "player_id": "char_003",
  "player_name": "菲菲",
  "spirit_id": "spirit_caomu",
  "spirit_name": "藤灵",
  
  // 球员属性分析
  "player_profiling": {
    "weaknesses": ["defense_low", "stamina_low"],      // 弱点
    "strengths": ["speed_high", "ball_speed_high"],    // 强项
    "risk_level": "high",                              // 生存风险等级
    "optimal_role": "supporter"                        // 基于属性的最优角色定位
  },
  
  // 技能组合分析
  "skills_analysis": [
    {
      "skill_id": "skill_草木_1",
      "skill_name": "生机护体",
      "energy_cost": 20,
      "cooldown": 12.0,
      
      // 标签深度分析
      "tags_analysis": [
        {
          "tag_id": "player_hp_regen",
          "effect_type": "heal",
          "value": 8.0,
          "duration": 5.0,
          "target": "self",
          "synergy_with_player": "high"   // 与球员属性的协同度
        },
        {
          "tag_id": "player_def_up_pct",
          "effect_type": "buff",
          "value": 25.0,
          "duration": 5.0,
          "synergy_with_player": "critical"  // 弥补弱点的关键技能
        }
      ],
      
      // 意图判定（基于球员视角）
      "intents": {
        "attack": 0.9,   // 进攻意图权重（给自己加防后能更安全地进攻）
        "defense": 1.4,  // 防御意图权重（核心防御手段）
        "support": 1.0   // 支援意图权重（保护自己才能支援队友）
      },
      
      // 局势响应规则
      "situation_rules": [
        { "condition": "stamina < 40%", "priority_modifier": 1.5 },
        { "condition": "under_pressure", "priority_modifier": 1.3 },
        { "condition": "enemy_nearby", "priority_modifier": 1.2 }
      ],
      
      // 能量阈值（个性化）
      "energy_threshold": 15    // 因为菲菲防御低，能量阈值降低，更愿意用
    }
  ],
  
  // 能量管理策略（个性化）
  "energy_strategy": {
    "base_reserve_weight": 0.8,           // 基础保留权重（低于默认0.9）
    "emergency_energy": 10,               // 紧急情况最低能量（低于默认20）
    "max_consecutive_uses": 2,            // 连续使用上限
    "regeneration_priority": "high"       // 能量恢复优先级
  },
  
  // 组合策略
  "combo_strategy": [
    {
      "sequence": ["skill_草木_1", "ball_attack"],
      "condition": "stamina_full && enemy_low",
      "expected_value": 1.8
    }
  ]
}
```

### 9.4 球员弱点/强项判定

#### 9.4.1 属性阈值判定

```
normalized_defense = player.defense / max_possible_defense    # 归一化到 [0, 1]

if normalized_defense < 0.5:
    weaknesses.append("defense_low")
    if normalized_defense < 0.3:
        weaknesses.append("defense_critical")    # 严重弱点

if normalized_speed > 0.7:
    strengths.append("speed_high")

if normalized_stamina < 0.5:
    weaknesses.append("stamina_low")

if normalized_attack > 0.7:
    strengths.append("attack_high")
```

#### 9.4.2 生存风险等级计算

```
risk_score = (1 - normalized_defense) × 0.3 + 
             (1 - normalized_stamina) × 0.3 + 
             (1 - normalized_resilience) × 0.2 + 
             (1 - normalized_speed) × 0.2

if risk_score > 0.6:
    risk_level = "high"       # 需要频繁使用防御/恢复技能
elif risk_score > 0.3:
    risk_level = "medium"     # 正常使用技能
else:
    risk_level = "low"        # 可以激进使用进攻技能
```

### 9.5 技能与球员协同度计算

```
synergy_score = 0.0

# 1. 技能效果弥补球员弱点
for weakness in player_profiling.weaknesses:
    if skill_has_effect_against(weakness):
        synergy_score += 0.4    # 弥补弱点 +0.4
        if weakness == "critical":
            synergy_score += 0.2    # 严重弱点额外 +0.2

# 2. 技能效果强化球员强项
for strength in player_profiling.strengths:
    if skill_has_effect_enhancing(strength):
        synergy_score += 0.3    # 强化强项 +0.3

# 3. 能量消耗适配球员能量回复能力
energy_cost_ratio = skill.energy_cost / player.max_spirit_energy
if energy_cost_ratio < 0.2:
    synergy_score += 0.1    # 消耗低 +0.1
elif energy_cost_ratio > 0.4:
    synergy_score -= 0.1    # 消耗高 -0.1

# 转换为标签
if synergy_score >= 0.8:
    synergy_level = "critical"    # 关键技能，必须优先用
elif synergy_score >= 0.5:
    synergy_level = "high"        # 高协同，优先用
elif synergy_score >= 0.2:
    synergy_level = "medium"      # 中等协同
else:
    synergy_level = "low"         # 低协同，尽量不用
```

### 9.6 实战示例

#### 示例1：菲菲（高敏低防）+ 草木（回血+防御buff）

```
球员分析：
  weaknesses = ["defense_low", "stamina_low"]
  strengths = ["speed_high", "ball_speed_high"]
  risk_level = "high"
  optimal_role = "supporter"

技能分析（生机护体）：
  tags_analysis = [
    {"player_hp_regen": {"synergy": "high"}},
    {"player_def_up_pct": {"synergy": "critical"}}
  ]
  
  intents = {attack: 0.9, defense: 1.4, support: 1.0}
  
  situation_rules = [
    {"stamina < 40%": 1.5},
    {"under_pressure": 1.3},
    {"enemy_nearby": 1.2}
  ]
  
  energy_threshold = 15    # 降低到15，更愿意用

能量策略：
  base_reserve_weight = 0.8    # 低于默认0.9
  emergency_energy = 10        # 紧急时10点能量就用
```

#### 示例2：菲菲（高敏低防）+ 梦幻（隐身+加速）

```
球员分析：
  weaknesses = ["defense_low", "stamina_low"]
  strengths = ["speed_high", "ball_speed_high"]
  risk_level = "high"

技能分析（虚幻迷踪）：
  tags_analysis = [
    {"player_stealth": {"synergy": "critical"}},    # 没有回血技能，隐身是唯一保命手段
    {"player_spd_up_pct": {"synergy": "high"}}      # 强化速度强项
  ]
  
  intents = {attack: 1.1, defense: 1.5, support: 0.9}
  
  situation_rules = [
    {"stamina < 30%": 2.0},    # 血量低时立即隐身保命
    {"chased_by_multiple": 1.8},
    {"need_reposition": 1.3}
  ]
  
  energy_threshold = 20

能量策略：
  base_reserve_weight = 0.7    # 更低，因为没有回血技能，需要更激进使用隐身
  emergency_energy = 15
```

#### 示例3：超人强（高防高血）+ 大地（岩石墙）

```
球员分析：
  weaknesses = []
  strengths = ["defense_high", "stamina_high", "resilience_high"]
  risk_level = "low"

技能分析（岩石墙）：
  tags_analysis = [
    {"field_obs_add": {"synergy": "high"}}    # 强化防御强项
  ]
  
  intents = {attack: 0.9, defense: 1.6, support: 1.0}
  
  situation_rules = [
    {"enemy_advancing": 1.5},
    {"ball_coming": 1.3},
    {"teammate_recovering": 1.2}
  ]
  
  energy_threshold = 20

能量策略：
  base_reserve_weight = 1.1    # 更高，因为生存能力强，可以攒能量
  emergency_energy = 25
```

---

## 十、技能标签深度分析与组合搭配

> **核心设计**：技能不只是"进攻/防御/支援"的简单分类，还需要分析标签的副作用、冷却时间、能量消耗、与其他技能的组合效果等。

### 10.1 技能标签深度分析

#### 10.1.1 标签效果类型分类

| 效果类型 | 说明 | 示例标签 |
|---------|------|---------|
| **直接伤害** | 对目标造成即时伤害 | `ball_dmg_up_pct`, `player_hp_damage_flat` |
| **持续伤害** | 持续一段时间的伤害 | `player_hp_dot` |
| **直接恢复** | 对目标造成即时恢复 | `player_hp_heal_flat` |
| **持续恢复** | 持续一段时间的恢复 | `player_hp_regen` |
| **属性增益** | 提升目标属性 | `player_atk_up_pct`, `player_def_up_pct` |
| **属性减益** | 降低目标属性 | `player_atk_down_pct`, `player_move_slow` |
| **控制效果** | 限制目标行动 | `player_stun`, `player_root` |
| **免疫效果** | 使目标免疫某种效果 | `player_cc_immune`, `player_invincible` |
| **位移效果** | 改变目标位置 | `player_teleport`, `player_swap_pos` |
| **状态效果** | 改变目标状态 | `player_stealth`, `player_silence` |
| **场地效果** | 改变场地环境 | `field_obs_add`, `field_speed_zone` |
| **能量效果** | 改变能量状态 | `player_energy_gain_flat`, `player_spirit_cost_down` |

#### 10.1.2 技能深度分析结构

```json
{
  "skill_id": "skill_冰雪_1",
  "skill_name": "寒冰减速",
  "energy_cost": 22,
  "cooldown": 9.0,
  "element": "冰雪",
  
  // 标签深度分析
  "tags_depth_analysis": [
    {
      "tag_id": "player_move_slow",
      "effect_type": "debuff",
      "target_type": "enemy",
      "value": 50.0,
      "duration": 3.0,
      
      // 深度分析
      "impact_radius": 0,           // 影响范围（0=单体）
      "stackable": true,            // 是否可叠加
      "max_stacks": 2,              // 最大叠加层数
      "duration_extendable": true,  // 持续时间是否可延长
      "counter_tags": ["player_move_boost"],  // 克制标签
      "synergy_tags": ["player_stun"],        // 协同标签
      "side_effect": null           // 副作用（如伤害降低）
    },
    {
      "tag_id": "ball_dmg_down_pct",
      "effect_type": "debuff",
      "target_type": "ball",
      "value": 20.0,
      "duration": null,
      
      // 深度分析
      "side_effect": "ball_damage_reduction",  // 副作用：球伤害降低20%
      "trade_off_ratio": 0.8,                  // 利弊比：减速50% vs 伤害降20%
      "when_to_use": "need_control_over_damage",
      "when_to_avoid": "need_high_damage"
    }
  ],
  
  // 技能综合评估
  "overall_evaluation": {
    "offensive_value": 0.7,    // 进攻价值（减速创造击杀窗口）
    "defensive_value": 0.8,    // 防御价值（减速延缓对方进攻）
    "support_value": 0.5,      // 支援价值
    "risk_level": "low",       // 使用风险（副作用较小）
    "efficiency": 0.85         // 能量效率（22能量换50%减速3秒）
  }
}
```

### 10.2 技能组合搭配分析

#### 10.2.1 组合类型

| 组合类型 | 说明 | 示例 |
|---------|------|------|
| **连招组合** | 连续使用技能产生叠加效果 | 减速 → 眩晕 → 高伤害球 |
| **互补组合** | 技能之间互相弥补短板 | 回血+防御buff（草木技能本身就是这种组合） |
| **协同组合** | 技能效果互相增强 | 加速 + 隐身（梦幻技能） |
| **克制组合** | 针对特定敌人配置 | 沉默技能针对高技能使用率的敌人 |
| **应急组合** | 紧急情况下的技能组合 | 无敌 + 传送（保命组合） |

#### 10.2.2 组合效果计算

```
combo_effect = Σ(individual_effect_i × synergy_factor_i) + combo_bonus

# 连招组合示例：减速 → 眩晕 → 高伤害球
# 减速让敌人无法躲避，眩晕让敌人无法行动，高伤害球击杀

combo_effect = (0.5减速 × 1.0) + (1.0眩晕 × 1.2) + (1.3伤害 × 1.5) + 0.5连招加成
             = 0.5 + 1.2 + 1.95 + 0.5
             = 4.15

# 单技能效果总和 = 0.5 + 1.0 + 1.3 = 2.8
# 组合增益 = 4.15 / 2.8 ≈ 1.48 → 提升48%
```

#### 10.2.3 组合策略模板

```json
{
  "combo_id": "combo_control_kill",
  "combo_name": "控杀连招",
  "sequence": [
    {"skill_id": "skill_冰雪_1", "delay": 0},
    {"skill_id": "skill_金刚_1", "delay": 2.0}    // 减速生效后2秒再投球
  ],
  "conditions": [
    "enemy_stamina < 60%",
    "ball_possession > 0.8",
    "energy >= 42"    // 22 + 20
  ],
  "expected_value": 1.8,
  "risk_level": "medium",
  "energy_efficiency": 0.75
}
```

### 10.3 元素克制与技能选择

#### 10.3.1 元素克制关系

| 元素 | 克制 | 被克制 |
|------|------|--------|
| 金刚 | 草木 | 雷火 |
| 大地 | 梦幻 | 冰雪 |
| 雷火 | 金刚 | 大地 |
| 冰雪 | 雷火 | 梦幻 |
| 草木 | 冰雪 | 金刚 |
| 梦幻 | 草木 | 大地 |

#### 10.3.2 元素克制对技能评分的影响

```
element_factor = 1.0    # 基础值

# 我方技能元素克制敌方元素
if my_element == get_counter(enemy_element):
    element_factor = 1.3    # 克制时技能效果提升30%

# 敌方元素克制我方技能元素
if enemy_element == get_counter(my_element):
    element_factor = 0.7    # 被克制时技能效果降低30%

# 元素克制只影响技能效果价值，不影响意图匹配度
total_score = base_value × element_factor × situation_factor × intent_match × ...
```

---

## 十一、球员属性感知与策略调整

> **核心设计**：AI不仅要知道自己的属性，还要感知队友和敌人的属性，据此调整技能使用策略。

### 11.1 队友属性感知

#### 11.1.1 队友状态评估

```json
{
  "teammate_id": "char_005",
  "teammate_name": "波比",
  "role": "attacker",
  
  "current_state": {
    "stamina_ratio": 0.35,      // 体力比例
    "energy_ratio": 0.6,        // 能量比例
    "has_ball": false,          // 是否持球
    "is_defeated": false,       // 是否被击败
    "has_active_buff": ["player_atk_up_pct"]  // 当前buff
  },
  
  "needs_assistance": {
    "heal": 0.85,        // 需要治疗的程度（0-1）
    "defense": 0.6,      // 需要防御的程度
    "energy": 0.3        // 需要能量的程度
  },
  
  "is_dangerous": false,     // 是否对敌人构成威胁
  "threat_level": "high"     // 威胁等级
}
```

#### 11.1.2 支援技能目标选择

```
# 选择最需要支援的队友
target_score = 0.0

# 1. 体力需求
target_score += teammate.needs_assistance.heal × 0.4

# 2. 防御需求（身板脆+被攻击）
target_score += teammate.needs_assistance.defense × 0.3

# 3. 进攻价值（威胁高的队友值得支援）
target_score += teammate.threat_level.value × 0.2

# 4. 距离因素（距离近的优先）
target_score += (1 - distance_ratio) × 0.1

# 选最高分的队友作为支援目标
```

### 11.2 敌人属性感知

#### 11.2.1 敌人威胁评估

```json
{
  "enemy_id": "char_002",
  "enemy_name": "超人强",
  
  "stats": {
    "attack": 30.0,
    "defense": 80.0,
    "speed": 65.0,
    "stamina": 90.0
  },
  
  "current_state": {
    "stamina_ratio": 0.8,
    "energy_ratio": 0.5,
    "has_ball": true,
    "has_active_debuff": []
  },
  
  "threat_assessment": {
    "offensive_threat": "high",   // 进攻威胁
    "defensive_threat": "low",    // 防御威胁（对我方进攻的阻碍）
    "skill_threat": "medium"      // 技能威胁
  },
  
  "weaknesses": [],               // 敌人弱点（基于属性）
  "resistance": ["defense_high"]  // 敌人抗性
}
```

#### 11.2.2 攻击技能目标选择

```
# 选择最优攻击目标
target_score = 0.0

# 1. 威胁程度（威胁高的优先处理）
target_score += enemy.threat_assessment.offensive_threat.value × 0.3

# 2. 血量比例（血量低的优先击杀）
target_score += (1 - enemy.current_state.stamina_ratio) × 0.3

# 3. 抗性匹配（敌人抗性低的优先）
for resistance in enemy.resistance:
    if skill_can_counter(resistance):
        target_score += 0.2

# 4. 能量状态（能量低的敌人无法反击）
target_score += (1 - enemy.current_state.energy_ratio) × 0.1

# 5. 距离因素
target_score += (1 - distance_ratio) × 0.1

# 选最高分的敌人作为攻击目标
```

### 11.3 团队整体评估

#### 11.3.1 团队短板分析

```
team_weaknesses = []
team_strengths = []

# 统计团队平均属性
avg_defense = average(all_teammates.defense)
avg_stamina = average(all_teammates.stamina)
avg_speed = average(all_teammates.speed)
avg_attack = average(all_teammates.attack)

# 判定短板
if avg_defense < threshold_defense:
    team_weaknesses.append("team_defense_low")

if avg_stamina < threshold_stamina:
    team_weaknesses.append("team_stamina_low")

# 判定强项
if avg_speed > threshold_speed:
    team_strengths.append("team_speed_high")

# 调整技能策略
if "team_defense_low" in team_weaknesses:
    # 团队防御弱，防御/控制技能优先级提升
    all_defense_skills_priority += 0.2
    
if "team_stamina_low" in team_weaknesses:
    # 团队体力弱，恢复技能优先级提升
    all_heal_skills_priority += 0.2
```

---

## 十二、完整决策流程（含赛前分析）

```
=== 赛前阶段 ===
  ↓
1. 读取球员数据（characters.json）
2. 读取元灵技能数据（skills.json + tags_registry.json）
3. 生成个性化决策模板（每个球员一份）
   a. 球员弱点/强项分析
   b. 技能标签深度分析
   c. 技能与球员协同度计算
   d. 能量管理策略制定
   e. 组合策略制定
4. 团队整体评估（短板/强项）
5. 调整全局策略权重

=== 比赛阶段 ===
  ↓
每 skill_think_interval 秒决策一次
  ↓
1. 检查能量 < skill_energy_min → 跳过
2. 获取所有可用技能（冷却已结束 + 能量足够）
3. 感知队友/敌人状态（更新队友需求/敌人威胁）
4. 对每个技能：
   a. 判断技能类型（BALL/FIELD/PLAYER）
   b. 确定角色视角下的技能意图（进攻/防御/支援）
   c. 计算基础评分（技能效果价值 × 元素克制 × 协同度）
   d. 乘以局势因子（球权/分差/体力/时间/人数/进攻窗口）
   e. 乘以意图匹配度 intent_match（角色视角 × 意图权重 × 协同度）
   f. 动态能量评估：现在用的价值 vs 保留到未来的价值
5. 考虑组合策略（连招/互补/协同）
6. 选最高分技能（或最优组合）
7. 最高分 >= skill_use_threshold 且 能量动态评估通过 → 释放
   否则 → 等待下次决策
```
