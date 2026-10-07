# vibecoding 提示词库（主人出任务手册）

> 用途：主人不懂底层技术，也能把任务说清楚，让 ZCode 高效理解并默认执行技能链。
> 配套路由技能：`.zcode/skills/vibe_task/SKILL.md`；跨工具说明书：根目录 `AGENTS.md`。
> 建立：2026-10-04。出处均为 GitHub 成熟开源库——取其结构思想，内容已按本项目翻译。

## 一、成熟提示词库出处（调研于 2026-10）

| 库 | 地址 | 是什么 | 编入去向（2026-10-04 已落地） |
|---|---|---|---|
| GitHub Spec Kit | [github.com/github/spec-kit](https://github.com/github/spec-kit) | 规范驱动开发（SDD）工具包：constitution → specify → plan → tasks → implement → converge | 思想编入 `vibe_task`（复述=specify、铁律=constitution）。重型五阶段流程**不搬**——本项目工单+决策清单体系已同款覆盖 |
| wshobson/commands | [github.com/wshobson/commands](https://github.com/wshobson/commands) | Claude Code 生产级命令库（15 工作流 + 42 工具） | 填空模板结构编入 `vibe_task` 三句话模板 + 任务路由表 |
| awesome-claude-code | [github.com/hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) | Claude Code 生态资源总目录 | **留作索引**，以后找现成命令/技能时翻 |
| awesome-cursorrules | [github.com/PatrickJS/awesome-cursorrules](https://github.com/PatrickJS/awesome-cursorrules) | 各语言/框架规则文件合集（含 Godot/GDScript） | 定位思想编入 `project-context` 窄读铁律（grep→行号→窄读，配套 `docs/code_map.md`+`tools/gen_code_map.py`）；GDScript 规则卡在本文第五节 |
| BMAD-METHOD | [github.com/bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) | 角色化敏捷 AI 开发框架（多智能体分工） | **不搬**——本项目多窗口并发（集成/布场/操球/平台/规划）已是同款实践；工单文件契约思想与现行工单纪律一致 |
| AGENTS.md 开放标准 | [agents.md](https://agents.md) | 跨工具 AI 说明书开放标准 | 根目录 `AGENTS.md`（指针式说明书）+ `write_log` 接手速览段 |
| system-prompts 合集 | [github.com/x1xhlol/system-prompts-and-models-of-ai-tools](https://github.com/x1xhlol/system-prompts-and-models-of-ai-tools) | Cursor/Devin/v0 等真实系统提示词合集 | **留作索引**，学"给代理定角色边界"时查 |

## 二、方法论浓缩（为什么这么设计）

1. **规范驱动优于纯 vibe**（Spec Kit）：主人一句话 → 窗口先产出「规格复述」给主人确认 → 再动手。本项目已有同款：复述+纲要铁律。
2. **宪法只定一次**（Spec Kit constitution）：项目级规矩写成铁律文件（本项目 = battle-ball / project-context 技能），任务级文档只引用不重复，避免双头维护失同步。
3. **说明书要短、要指向**（AGENTS.md 原则）：根目录说明书只写指针 + 铁律摘要，细节进技能文件。
4. **工作流与工具分开**（wshobson）：多步任务走工作流链（本项目的技能链），单点操作用工具命令。
5. **任务四要素**（综合提炼）：**目标 / 完成标准 / 禁区 / 参考**。主人写不全没关系，窗口补全后进复述确认。

## 三、主人出任务模板（填空即用）

> 用法：复制对应模板 → 填空 → 粘给 ZCode。填不了的部分留空，窗口会补全并在复述里让主人确认。

### ① 新功能

```
【目标】给<谁/哪个系统>加一个<什么能力>，玩家<怎么用/怎么感知>
【完成标准】<在什么场景看到什么效果>；不破坏现有<XX>
【禁区】<不许改的文件/机制，不清楚就留空>
【参考】原作里<哪段表现/哪个队伍>是这样
```

示例：给防守球员加"贴身盯人"倾向。完成标准=自动模拟里对方主攻接球率下降但无卡死，危险=0。参考=原作防守 utoki 队的贴身防守桥段。

### ② 修 Bug

```
【现象】我做了<什么操作>，期望<什么>，实际<什么>
【报错】有报错整段贴上来，没有就写"无"
【复现】必现/偶现；在哪个场景
```

### ③ 调平衡 / 数值

```
【对象】<哪队/哪个技能/哪类参数>
【现状 vs 期望】现在<太强/太弱/太慢>，希望<目标手感>
【验收口径】模拟指标<哪个>落在<什么范围>；危险=0
```

### ④ 调研 / 规划

```
【问题】我想搞清楚<什么>
【用途】结论要用在<哪>
【产出】<对比表/方案文档/工单>，放到<哪个文件夹>
```

### ⑤ 验收 / 复盘

```
【验收对象】<工单号/功能名>
【怎么验】<跑什么/看什么指标/手测什么操作>
【产出】验收记录写进<工单/进度看板/工作日志>
```

## 四、窗口侧约定

主人发出模板（哪怕只写了一句话）后，窗口自动执行——细节见 `vibe_task` 技能：

1. 白话翻译成技术动作，5 行以内复述纲要给主人确认
2. 按任务类型默认串联技能链（修 Bug → bug_fix；新功能 → new_project/subsystem_dev；…收尾必跑 test_first / verify_before_deliver / write_log）
3. 技能默认执行不请示；只有花积分操作（MCP/建模/批量跑批）先报预算
4. 收尾四件套：完成总结 + 改动文件清单 + 待办 + 工作日志

## 五、Godot/GDScript 通用规则卡（跨项目可复用）

通用层（源自 awesome-cursorrules 的 Godot 规则思路）：

- **Godot 4.x 写法**：`@export` / `@onready`；Tween 用 `create_tween()`；信号连接优先用信号名而非字符串
- **风格**：函数/变量 snake_case；缩进用 **Tab**；推荐 typed GDScript（参数与返回值标类型）
- **节点**：`$Node/Path` 必须与场景树一致；组合优于继承；信号驱动解耦

本项目专属踩坑（**以 `.zcode/skills/project-context/SKILL.md` §11 为唯一权威**，此处仅提示存在）：

- `look_at()` up 向量、`ImageTexture` API 差异、SubViewport 三件套、`.tscn` [node] 块禁 `#` 注释、Key 常量跨版本不一致等

## 六、更新约定

- 发现新的成熟库 → 追加进第一节表格并注明调研日期
- 第三、五节模板结构改动由主人定，窗口不得擅自重构
