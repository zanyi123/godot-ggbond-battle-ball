---
name: "test_first"
description: "全能自动测试框架。每次修改代码后自动执行：Python验证→Godot编译检查→功能测试→问题修复循环，直到全部通过才交付。集成所有测试类型（资源/逻辑/UI/系统）。"
---

# 全能自动测试框架

## 核心原则

**光说没有用，每次都要执行才行。测试-修复-验证，全自动化循环。**

## 自动测试流程

### 每次修改代码后，必须自动执行以下步骤：

```
┌─────────────────────────────────────────────────────────────┐
│                    自动测试循环                              │
├─────────────────────────────────────────────────────────────┤
│  1. Python验证（文件/资源/数据）                             │
│     ↓ 通过                                                  │
│  2. Godot编译检查（语法/API）                                │
│     ↓ 通过                                                  │
│  3. 功能测试（最小测试脚本）                                  │
│     ↓ 通过                                                  │
│  4. 系统集成测试（run_sim.sh）                               │
│     ↓ 通过                                                  │
│  5. 交付                                                    │
│                                                             │
│  任一步骤失败 → 自动修复 → 重新测试 → 循环直到通过            │
└─────────────────────────────────────────────────────────────┘
```

## 测试类型库

### 1. 资源文件测试
```python
# 执行方式：python -c "..."
import os
from PIL import Image

def test_image_files(dir_path):
    """验证图片文件是否存在且有效"""
    for f in os.listdir(dir_path):
        if f.endswith('.png'):
            path = os.path.join(dir_path, f)
            img = Image.open(path)
            print(f"✓ {f}: {img.size}")
```

### 2. 数据文件测试
```python
import json

def test_json_files(dir_path):
    """验证JSON文件格式正确"""
    for f in os.listdir(dir_path):
        if f.endswith('.json'):
            path = os.path.join(dir_path, f)
            with open(path, 'r', encoding='utf-8') as file:
                data = json.load(file)
                print(f"✓ {f}: {len(data)} items")
```

### 3. Godot编译测试
```bash
# 执行方式：godot --check-only --no-window
# 或检查特定脚本：godot --headless --script scripts/test_xxx.gd
```

### 4. 功能单元测试
```gdscript
# 文件：scripts/test_<功能名>.gd
extends Node

func _ready() -> void:
    print("=" * 50)
    print("[测试] <功能名> 开始")
    
    # 测试项
    test_条件1()
    test_条件2()
    test_显示验证()
    
    print("=" * 50)
    print("[测试] <功能名> 完成")
    
    # 自动退出（CI模式）
    if "--auto-close" in OS.get_cmdline_args():
        get_tree().quit()
```

### 5. 系统集成测试
```bash
# 执行方式：bash run_sim.sh
# 验证游戏整体运行状态
```

## 自动修复机制

### 当测试失败时，自动执行：

1. **分析错误输出** → 定位问题类型
2. **分类修复策略**：
   - 资源缺失 → 创建占位资源
   - 语法错误 → 修正代码
   - API变更 → 更新调用方式
   - 逻辑错误 → 修复算法
3. **重新运行测试** → 确认修复成功
4. **循环直到通过** → 最多3轮

## 执行命令速查表

| 测试类型 | 命令 | 用途 |
|---------|------|------|
| 图片验证 | `python -c "from PIL import Image; ..."` | 验证PNG有效 |
| JSON验证 | `python -c "import json; ..."` | 验证数据格式 |
| Godot编译 | `godot --check-only --no-window` | 检查语法错误 |
| 脚本测试 | `godot --headless --script scripts/test_xxx.gd` | 运行测试脚本 |
| 系统测试 | `bash run_sim.sh` | 完整游戏验证 |

## 使用示例

### 场景1：修改UI组件
```
修改 base_system.gd 的 _create_item_card 函数
↓
自动执行：
1. python验证图标文件存在
2. godot --check-only 验证语法
3. godot --headless --script scripts/test_icon_display.gd
4. 全部通过后才算完成
```

### 场景2：修改数据加载
```
修改 inventory_manager.gd 的加载逻辑
↓
自动执行：
1. python验证items.json格式
2. godot --check-only 验证语法
3. 创建test_inventory_load.gd验证加载
4. bash run_sim.sh验证整体
```

### 场景3：修复Bug
```
用户反馈：食物列表为空
↓
自动执行：
1. 创建test_nutrition_data.gd验证数据源
2. 发现foods.json路径错误
3. 自动修复路径
4. 重新测试通过
5. bash run_sim.sh验证
```

## 与其他Skill的联动

- **配合 bug-fix**：测试验证bug存在→修复→测试验证bug消失
- **配合 verify-before-deliver**：测试通过是交付的前置条件
- **配合 new-project**：新模块开发必须先写测试再写实现

## 禁止的行为

- ❌ 只说"应该测试"但不实际执行
- ❌ 修改代码后让用户手动测试
- ❌ 测试失败后不修复直接继续
- ❌ 跳过任何测试步骤