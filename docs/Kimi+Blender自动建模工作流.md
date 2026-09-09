# Kimi Code + Blender 自动建模工作流

> 基于真实工程案例验证的 AI 自动建模方案

---

## 一、方案概述

### 1.1 核心思路

```
用户需求 → Kimi Code(解析+生成) → Blender(执行建模) → Kimi(验证+迭代) → 导出GLB
```

### 1.2 效率提升

| 指标 | 传统方案 | Kimi + Blender | 提升 |
|---|---|---|---|
| 建模时间 | 数天 | 30分钟-1小时 | **10-50倍** |
| 修改响应 | 小时级 | 分钟级 | **60倍** |
| 变更单减少 | - | 60%-80% | - |

### 1.3 真实案例验证

**酒店工程案例**：
- 3个工程师，6周 → 1个工程师，9天
- 190个房间的管道、电线、风管自动建模
- 施工变更单减少60%-80%

---

## 二、AI 角色分工

### 2.1 角色矩阵

| AI 角色 | 功能 | 工具 | 可行性 |
|---|---|---|---|
| **需求解析官** | 理解中文描述，提取参数 | Kimi Code | ⭐⭐⭐⭐⭐ |
| **代码生成官** | 生成 Blender Python 脚本 | Kimi Code | ⭐⭐⭐⭐ |
| **执行指挥官** | 调度 Blender 执行代码 | Blender CLI/MCP | ⭐⭐⭐⭐ |
| **质量验证官** | 视觉分析，对比需求 | Kimi Code (Vision) | ⭐⭐⭐⭐⭐ |
| **格式转换官** | 导出 GLB，验证兼容 | Blender 导出器 | ⭐⭐⭐⭐⭐ |

### 2.2 关键能力

| 能力 | 说明 | Kimi 支持 |
|---|---|---|
| 长任务编码 | 支持百万级 Token 上下文 | ✅ |
| 原生视觉理解 | 查看 Blender 截图并分析 | ✅ |
| 工具调用 | 连接 MCP 操作 Blender | ✅ |
| 迭代修改 | 边看边改，持续优化 | ✅ |
| 中文优化 | 理解中文需求，生成中文注释 | ✅ |

---

## 三、操作流程详解

### 3.1 Step 1：需求输入（5分钟）

**操作**：
1. 打开 Kimi Code
2. 提供场地参数（复制 `field_zone.gd` 内容）
3. 用自然语言描述需求

**Prompt 模板**：
```
我需要创建一个决竞球游戏的3D场地模型，请用Blender Python代码实现：

【场地参数】（与项目代码field_zone.gd完全一致）
- 场地总尺寸：1300(X宽) × 780(Z深)，单位cm
- 坐标原点：场地中心
- 坐标系：X右，Y上，Z前（Godot标准）

【场地结构】
1. 基础草地：1300×780，深绿色RGB(0.12, 0.18, 0.12)
2. 蓝色禁区：与草地同尺寸，深蓝色RGB(0.15, 0.25, 0.55)
3. 内场（灰色）：760宽×520深，左下角(-380, -260)，灰色RGB(0.65, 0.65, 0.65)
4. 左外场（凹字形）：
   - 主体：130×650，位置(-510, -325)
   - 上臂：130×65，位置(-380, -325)
   - 下臂：130×65，位置(-380, 260)
   - 颜色：橙黄色RGB(0.9, 0.6, 0.2)
5. 右外场（凹字形）：镜像左外场
6. 白色边界线：宽度4cm，高度2cm
7. 中圈：半径60cm的白色圆环
8. 中线：X=0处，沿Z轴延伸
9. 6块悬浮能量墙：
   - 尺寸：8厚×50高×8宽
   - 位置：内场四角+内场两侧
   - 颜色：青色RGB(0.3, 0.7, 0.9)，透明度40%
   - 悬浮高度：Y=50~100
10. 中央计分板：
   - 支架：5×5×50，灰色
   - 主板：80×30×5，白色
   - 屏幕：70×22×0.5，黑色
   - 位置：场地中心上方

【技术要求】
- 使用bpy API创建网格
- 材质使用Principled BSDF
- 导出格式：GLB（Godot兼容）
- 导出参数：export_yup=True
- 代码要有中文注释
- 变量命名用中文（与项目代码风格一致）
```

**产出**：Kimi 生成完整的 Blender Python 脚本

---

### 3.2 Step 2：代码检查（2分钟）

**操作**：快速检查 Kimi 生成的代码

**检查清单**：
- [ ] 变量命名正确（与项目代码一致）
- [ ] 导出参数正确（export_yup=True）
- [ ] 材质创建逻辑正确
- [ ] 无明显语法错误
- [ ] 坐标系正确（Y轴朝上）

**产出**：确认/微调后的代码

---

### 3.3 Step 3：执行建模（1分钟）

**方式 A：命令行（推荐，稳定）**
```powershell
# Windows
blender --background --python create_battle_field.py

# 指定 Blender 完整路径
"C:\Program Files\Blender Foundation\Blender 4.2\blender.exe" --background --python create_battle_field.py
```

**方式 B：MCP 连接（如果稳定）**
- 让 Kimi 通过 MCP 直接操作 Blender
- 实时查看结果

**产出**：Blender 生成 `.blend` 文件

---

### 3.4 Step 4：质量验证（10分钟）

**操作**：
1. 在 Blender 中打开生成的场景
2. 截图（多视角：俯视、侧视、透视）
3. 把截图发给 Kimi
4. 问："这是你生成的模型，对比需求，有哪些问题？"

**Kimi 验证能力**：
- ✅ 视觉分析（尺寸、颜色、结构）
- ✅ 对比需求（检查是否符合要求）
- ✅ 提出修改建议

**产出**：修改建议/修正代码

---

### 3.5 Step 5：迭代优化（5-15分钟）

**操作**：
1. 根据 Kimi 的建议，修改代码
2. 重新执行 Step 3-4
3. 通常 1-3 轮即可得到满意结果

**产出**：最终 `.blend` 文件

---

### 3.6 Step 6：导出 GLB（1分钟）

**操作**（在 Blender 中）：
1. 文件 → 导出 → glTF (.glb/.gltf)
2. 格式：GLB（二进制）
3. 设置：
   - ✅ 导出 Y 轴朝上
   - ❌ 不导出相机
   - ❌ 不导出灯光
   - ✅ 导出材质

**产出**：`.glb` 文件

---

### 3.7 Step 7：Godot 验证（5分钟）

**操作**：
1. 把 `.glb` 放入 Godot 项目目录
2. Godot 自动生成 `.import` 文件
3. 在测试场景中加载验证

**验证清单**：
- [ ] 尺寸是否正确（1300×780）
- [ ] 材质是否正常显示
- [ ] 能否添加碰撞体
- [ ] 能否设置区域触发区

**产出**：可在 Godot 中使用的 3D 场地

---

## 四、避坑指南

### 4.1 常见问题与解决

| 问题 | 解决方案 | 来源案例 |
|---|---|---|
| AI 删除重要对象 | 保存增量版本，明确告知哪些不能改 | 酒店案例经验 |
| 审美判断不可靠 | 人类负责方向，AI 负责执行 | Kimi 官方建议 |
| MCP 连接不稳定 | 改用命令行执行 | 实际测试经验 |
| 模型尺寸偏差 | 给 Kimi 提供精确的数值参数 | 酒店案例经验 |
| 材质显示白膜 | 检查 PBR 参数（metallic/roughness） | 实测经验 |
| 坐标系不对 | 确保 export_yup=True | Godot 兼容性 |

### 4.2 安全操作规范

1. **保存增量版本**：每次重要修改前保存 .blend 文件
2. **限制自动审批**：Kimi 执行高风险操作前需人工确认
3. **明确范围**：告诉 Kimi 哪些文件/对象不能修改
4. **代码审查**：Kimi 生成的代码需快速检查一遍
5. **备份原始文件**：保留原始 .blend 文件作为回退

---

## 五、MCP 搭建指南（Kimi + Blender）

### 5.1 环境准备

#### 必备软件

| 软件 | 版本要求 | 下载地址 |
|---|---|---|
| **Blender** | 4.0+ | blender.org |
| **Python** | 3.10+（Blender 内置） | - |
| **Kimi Code CLI** | 最新版 | code.moonshot.cn |

#### 安装 Kimi Code CLI

```powershell
# 安装命令
npm install -g kimi-code

# 验证安装
kimi-code --version
```

### 5.2 Blender MCP 配置

#### 安装 Blender MCP 插件

```powershell
# 方式1：从 GitHub 克隆
cd C:\Users\Lenovo\AppData\Blender Foundation\Blender\4.2\scripts\addons
git clone https://github.com/chen-xuan/blender-mcp.git

# 方式2：下载 release
# 从 GitHub 下载最新 release，解压到 addons 目录
```

#### 在 Blender 中启用插件

1. 打开 Blender
2. 编辑 → 偏好设置 → 插件
3. 搜索 "Blender MCP"
4. 勾选启用
5. 配置端口（默认 8080）

#### 启动 MCP 服务

1. 在 Blender 中点击 3D 视图右上角的 MCP 按钮
2. 等待状态变为 "Connected"
3. 记录 Blender 的 IP 和端口

### 5.3 Kimi Code 连接配置

#### 创建配置文件

在用户目录创建 `kimi-config.toml`：

```toml
# MCP 服务器配置
[mcp]
# Blender MCP 服务器地址
servers = [
    {
        name = "blender"
        url = "http://localhost:8080"
        timeout = 30
    }
]

# AI 模型配置
[model]
provider = "kimi"
model = "kimi-k2-0904"
max_tokens = 1000000  # 支持长上下文
```

#### 启动 Kimi Code

```powershell
# 带配置启动
kimi-code --config kimi-config.toml

# 直接使用
kimi-code
```

### 5.4 MCP 测试与验证

#### 测试连接

在 Kimi Code 中输入：
```
请列出 Blender 当前场景的所有对象
```

如果连接成功，Kimi 会返回 Blender 场景中的对象列表。

#### 测试操作

```
请创建一个 10×10×1 的立方体，位置在原点
```

如果操作成功，Blender 中会出现一个新的立方体。

### 5.5 常见 MCP 问题排查

| 问题 | 排查步骤 | 解决方案 |
|---|---|---|
| 连接超时 | 1. 检查 Blender MCP 是否启动<br>2. 检查端口是否正确<br>3. 检查防火墙 | 重启 MCP，开放端口 |
| 连接被拒绝 | 1. 检查 Blender 是否运行<br>2. 检查 MCP 插件是否启用 | 重启 Blender，重新启用插件 |
| 操作无响应 | 1. 检查 MCP 日志<br>2. 检查 Blender 控制台 | 重启 MCP，查看错误日志 |
| 对象创建失败 | 1. 检查 Blender 版本<br>2. 检查 API 兼容性 | 升级 Blender，使用兼容 API |

---

## 六、项目集成路径

### 6.1 与现有代码对接

#### 3D 场地加载流程

```
.blb 文件 → Godot 导入 → field_3d_loader.gd 加载 → 与 field_zone.gd 逻辑同步
```

#### 必要的 GDScript 代码

```gdscript
# field_3d_loader.gd 核心结构
const FIELD_3D_PATH := "res://建模素材库/3D模型素材/battle_field_v3.glb"

func _ready():
    # 1. 加载 3D 场地
    var field_scene = load(FIELD_3D_PATH)
    field_root = field_scene.instantiate()
    add_child(field_root)
    
    # 2. 设置碰撞体（与 field_zone.gd 同步）
    _setup_collision()
    
    # 3. 设置区域触发区
    _setup_zone_triggers()
```

### 6.2 参数同步表

| field_zone.gd | Blender | field_3d_loader.gd |
|---|---|---|
| `FIELD_WIDTH = 1300` | 草地宽度 1300 | `FIELD_WIDTH = 1300` |
| `FIELD_HEIGHT = 780` | 草地深度 780 | `FIELD_HEIGHT = 780` |
| `INNER.width = 760` | 内场宽度 760 | `INNER.width = 760` |
| `INNER.height = 520` | 内场深度 520 | `INNER.height = 520` |

---

## 七、资源链接

### 7.1 官方资源

| 资源 | 链接 |
|---|---|
| Kimi Code 官网 | code.moonshot.cn |
| Blender 官网 | blender.org |
| Blender MCP GitHub | github.com/chen-xuan/blender-mcp |
| Godot 引擎 | godotengine.org |

### 7.2 参考文档

| 文档 | 说明 |
|---|---|
| [Blender Python API 文档](https://docs.blender.org/api/current/) | bpy API 参考 |
| [Godot GLB 导入文档](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_scenes.html) | GLB 导入说明 |
| [Kimi Code MCP 文档](https://code.moonshot.cn/docs) | MCP 配置指南 |

### 7.3 相关案例

| 案例 | 说明 |
|---|---|
| 酒店工程案例 | 190 房间管道自动建模 |
| Kimi K3 + Blender 实测 | 赛博朋克街道场景搭建 |

---

## 八、总结

### 8.1 可行性判定

| 判定项 | 结果 | 说明 |
|---|---|---|
| 技术可行性 | ✅ | 已在多个真实案例中验证 |
| 经济可行性 | ✅ | 效率提升 10-50 倍 |
| 质量可行性 | ✅ | 可达到游戏原型要求 |
| 风险可控性 | ✅ | 有明确的规避方案 |

### 8.2 核心优势

1. **中文优化**：Kimi 对中文需求的理解是核心优势
2. **视觉验证**：Vision in the Loop 让 AI 能边看边改
3. **长上下文**：支持百万级 Token，能处理复杂场景
4. **迭代修改**：不是重新生成，而是在现有基础上修改
5. **代码可见**：全程生成可编辑的 Python 代码

### 8.3 立即行动清单

- [ ] 安装 Blender 4.0+
- [ ] 安装 Kimi Code CLI
- [ ] 配置 Blender MCP
- [ ] 测试 MCP 连接
- [ ] 用 Prompt 模板生成场地脚本
- [ ] 执行建模并验证
- [ ] 导出 GLB 并导入 Godot

---

**文档版本**：v1.0  
**最后更新**：2026-08-09  
**适用项目**：决竞球 Battle Ball
