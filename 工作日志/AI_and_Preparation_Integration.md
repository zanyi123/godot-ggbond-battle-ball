# AI和备战界面集成总结

## 已创建的文件

### 1. 备战界面
**文件**: `scripts/ui/preparation_ui.gd`

**功能**:
- 球员状态面板（3个框）：显示体力、速度、攻击力，支持替补
- 元灵选择面板（3个框）：显示当前元灵，支持切换
- 战术策略面板：个人策略（突破、防守、传球）+ 团队策略（进攻、防守、平衡）

**信号**:
- `strategy_changed(player_strategy, team_strategy)` - 策略变更
- `player_substituted(index, new_char_id)` - 球员替补
- `spirit_changed(index, spirit_id)` - 元灵切换

### 2. AI管理器
**文件**: `scripts/battle/ai_manager.gd`

**功能**:
- AI状态机：闲置、追球、防守、支持、回位、传球、攻击
- 三种团队策略：全力进攻、全力防守、攻守平衡
- 三种个人策略：突破进攻、防守反击、传球配合
- 自动传球功能
- 发球功能
- 战术适配：根据备战界面的策略调整AI行为

**主要方法**:
- `register_player(player, team_name, index)` - 注册AI球员
- `unregister_player(player)` - 注销AI球员
- `set_player_strategy(player_index, strategy)` - 设置个人策略
- `set_team_strategy(team_name, strategy)` - 设置团队策略
- `kickoff_ai(player, player_data)` - 发球AI

### 3. 角色选择界面
**文件**: `scripts/ui/character_selection.gd`

**功能**:
- 显示可用角色列表
- 支持选择角色用于替补

## 已修改的文件

### battle_manager.gd
**添加**:
- `preparation_ui: Control` - 备战界面引用
- `_setup_ai_manager()` - 初始化AI管理器
- `_setup_preparation_ui()` - 初始化备战界面
- `_on_strategy_changed(player_strategy, team_strategy)` - 策略变更处理
- `_on_player_substituted(index, new_char_id)` - 球员替补处理
- `_on_spirit_changed(index, spirit_id)` - 元灵切换处理

## 使用方法

### 1. 启动游戏时
- 备战界面自动显示
- 比赛自动暂停
- 玩家可以设置策略和调整阵容

### 2. 点击"开始比赛"后
- 备战界面隐藏
- 比赛恢复
- AI开始控制队友和对手

### 3. 中场休息时
- 备战界面自动显示
- 玩家可以调整策略和替补

### 4. 比赛结束时
- 备战界面隐藏
- 显示最终比分

## AI行为说明

### 进攻型AI（全力进攻）
- 持球时直接进攻
- 球在附近时积极追球
- 快速响应球的位置

### 防守型AI（全力防守）
- 持球时优先传球
- 球接近己方场地时追球
- 平时回到防守位置

### 平衡型AI（攻守平衡）
- 持球时根据个人策略决定行为
- 球在附近时追球
- 平时回到自己的位置

## 战术策略影响

### 个人策略
- **突破进攻**：持球时直接向对方场地移动
- **防守反击**：持球时回到防守位置
- **传球配合**：持球时寻找传球机会

### 团队策略
- **全力进攻**：所有AI球员积极进攻
- **全力防守**：所有AI球员以防守为主
- **攻守平衡**：根据个人策略行动

## 待完善功能

### 球员替补（TODO）
- 实现替补选择界面集成
- 处理球员替换逻辑
- 更新AI管理器

### 元灵切换（TODO）
- 实现元灵系统
- 应用元灵属性到球员
- 更新备战界面显示

### AI优化（TODO）
- 添加路径规划
- 优化传球目标选择
- 添加团队协作逻辑
- 改善防守定位

## 测试建议

1. 启动游戏，检查备战界面是否正常显示
2. 测试策略按钮是否正常工作
3. 点击"开始比赛"，检查AI是否正常控制队友和对手
4. 测试中场休息时备战界面是否正常显示
5. 检查不同策略下AI行为是否符合预期