---
name: verify_before_deliver
description: 决竞球项目交付前验证纪律。修改 AI 相关文件(ai_manager/ai_profile/battle_manager/game_manager)后，必须运行 run_sim.sh 自动模拟验证，对比基线健康指标，无危险项才能交付。防止"改完直接让人测"的旧模式，落实"无证据不算完成"。
location: .pi/skills/verify_before_deliver/SKILL.md
---

# 决竞球 交付前验证 Skill

## 触发条件
当本轮对话**修改了以下任一文件**时，本技能强制激活：
- `scripts/battle/ai_manager.gd`（AI决策/移动/感知）
- `scripts/battle/ai_profile.gd`（AI参数/角色预设）
- `scripts/battle/battle_manager.gd`（比赛流程/球权）
- `scripts/core/game_manager.gd`（比赛计时/阶段）
- `scripts/battle/match_stats.gd`（指标采集）
- `scripts/battle/ball.gd`（球的物理/信号，影响AI接球投球）

## 核心规则

### 规则1：改完必跑模拟
修改上述文件后，**必须**运行：
```bash
./run_sim.sh 3 6 1 80
```
（3场、6倍速、种子1-3、每半场80秒，约90秒完成）

### 规则2：读健康结论
模拟结束的"整体健康检查"必须满足：
- ✗ 危险总数 = 0（硬规则全过）
- 才能认为"本次改动验证通过"

### 规则3：危险项必须排查
若出现 ✗ 危险（如比分0-0僵死、卡死>0、传球率<80%、零击中）：
- **禁止直接交付**让主人测
- 必须定位根因并修复，重跑模拟直至危险清零
- 参考 `sim_results/baseline.json` 的 `known_observations` 区分"已知现象"和"真bug"

### 规则4：警告项需说明
⚠ 警告（如状态切换过多/过少、外场接球0）不阻塞交付，但必须向主人**说明**：
- 是已知现象（参考 baseline.json）→ 可忽略
- 是本次改动引入 → 需主人确认是否接受

### 规则5：快速改动豁免
仅以下改动可豁免跑模拟（但仍需语法检查）：
- 纯注释/格式调整
- 只改 `print` 日志
- 只改数值且该数值不影响AI行为（如UI颜色）

## 交付话术模板
向主人交付时，必须包含验证状态：
```
✅ 自检：
- 语法检查：通过
- 自动模拟：3场全部健康（或：X场健康，详情如下）
  - 比分：1-2 / 2-1 / 0-2（无僵死）
  - 卡死：0次（P0修复持续有效）
  - 传球率：100%
- ⚠ 警告：外场接球0（已知现象）

需要主人验证：开游戏确认手感（数据无法体现的部分）
```

## 原则来源
本 skill 落实 GitHub vibecoding 调研提炼的 **"无证据不算完成"**（agentic-os）原则。
- AI 最爱说"改完了"，但"done"必须有可验证证据
- 没有 run_sim 的证据，"改完了"不算数

## 基线维护
当 AI 行为有重大优化且验证稳定后，更新 `sim_results/baseline.json`：
- 更新 `baseline_run_*` 快照
- 调整 `hard_rules` / `normal_range`（收紧标准，不轻易放宽）
- 在 `known_observations` 记录新发现的"正常但可疑"现象

## 反模式（禁止）
- ❌ "语法过了应该没问题" → 必须跑模拟
- ❌ "改得很小不用测" → 除非符合规则5豁免条件
- ❌ "让主人跑游戏看看" → 这是把测试推给主人，本 skill 就是为消除此模式
- ❌ 跑了模拟但只报"OK" → 必须报具体指标和结论
