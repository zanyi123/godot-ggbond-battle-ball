# AccuRIG 自动绑骨教程

> **用途**：当 Mixamo 绑骨失败（Q版大头小身模型比例不匹配）时，用 AccuRIG 替代绑骨。
> **前提**：已安装 AccuRIG（从 https://www.reallusion.com/character-creator/download-accuRIG.html 下载）
> **输入**：`建模素材库/3D模型素材/player2.fbx`（Blender 转出的 FBX）

---

## 一、打开 AccuRIG

1. 双击桌面 AccuRIG 图标启动
2. 登录 Reallusion 账号
3. 进入主界面，看到一个空白的 3D 视图

---

## 二、导入模型

**方法A：菜单导入**
1. 点左上角 **File → Import**
2. 找到 `E:\项目储存\决竞球battle-ball\建模素材库\3D模型素材\player2.fbx`
3. 点 Open

**方法B：直接拖拽**
- 把 `player2.fbx` 从文件夹直接拖进 AccuRIG 窗口

导入后模型出现在中间视图。

---

## 三、导入设置（重要！）

导入时弹出设置窗口，按以下选择：

| 选项 | 选什么 | 原因 |
|------|--------|------|
| Facing Direction | **+Z Forward** | 正面朝Z正方向，游戏引擎标准 |
| Up Axis | **Y Up** | 游戏引擎标准 |
| Scale | 1.0（不改） | 保持原大小 |
| Unit | Meter 或默认 | 不影响绑骨 |

点 **OK / Confirm** 确认。

---

## 四、检查模型

导入后在视图中检查：

- ✅ 模型完整（无残缺）
- ✅ 是 T-pose（双臂水平张开）
- ✅ 贴图显示正常（有颜色，不是全灰）

**视角操作：**
| 操作 | 功能 |
|------|------|
| 鼠标中键拖动 | 旋转视角 |
| 滚轮 | 缩放 |
| Shift + 中键拖动 | 平移 |

---

## 五、自动绑骨（核心步骤）

### 5.1 启动 Auto Rig

1. 看顶部工具栏，找到 **"Auto Rig"** 按钮（或菜单 Edit → Auto Rig）
2. 点它

### 5.2 AccuRIG 自动检测关节

AccuRIG 会自动分析模型，在身体上放置关节标记点。

**和 Mixamo 的区别：**
- ✅ AccuRIG 自动放点，通常不需要手动调
- ✅ 点不会"拖到模型外就消失"
- ✅ 对 Q 版大头小身模型支持更好

### 5.3 检查关节点位置

自动检测完后，画面显示骨架。检查以下关键点是否正确：

| 部位 | 正确位置 | 容易出错的地方 |
|------|----------|---------------|
| 头部 | 脖子根、头顶 | 头太大的模型可能偏 |
| 肩膀 | 脖子根和肩膀连接处 | Q版肩膀窄，可能偏内 |
| 手肘 | 手臂中段弯曲处 | — |
| 手腕 | 手掌根部 | — |
| 脊椎 | 背部中线 | — |
| 盆骨 | 腰部中点 | — |
| 膝盖 | 大腿小腿连接处 | — |
| 脚踝 | 小腿和脚连接处 | — |

### 5.4 手动微调（如果需要）

如果点位置不对：

1. **左键点住** 关节标记点
2. **拖动** 到正确位置
3. 松开左键

> ⚠️ AccuRIG 的点不会像 Mixamo 那样拖到模型外就消失，放心拖。

---

## 六、生成骨骼

1. 关节点确认无误后
2. 点右下角 **"Create Rig"**（创建骨骼）蓝色按钮
3. 等待 3-10 秒
4. 骨骼生成完成，模型身上出现完整骨架

---

## 七、预览测试

绑骨完成后，AccuRIG 自动播放预览动作。

**检查：**
- ✅ 手肘朝后弯（不是朝前）
- ✅ 膝盖朝前弯（不是朝后）
- ✅ 没有穿模（手脚穿透身体）
- ✅ 动作流畅无扭曲

**如果扭曲严重：**
- 点 **"Undo Rig"** 回到上一步
- 调整关节点位置
- 重新 Create Rig

---

## 八、导出带骨骼的 FBX

### 8.1 导出

1. 点 **File → Export**（或 Export As）
2. 设置：

| 选项 | 选什么 | 原因 |
|------|--------|------|
| 格式 | **FBX** | Godot/Mixamo 通用 |
| Include Animation | **不勾** | 只要模型+骨骼，动画另外下 |
| Include Textures | **勾** | 贴图嵌入 |
| Scale | 1.0 | 不改 |

3. 文件名：`player2_rigged.fbx`
4. 保存到：`建模素材库/3D模型素材/player2_rigged.fbx`
5. 点 **Export**

### 8.2 验证

导出后，文件大小应该比原 FBX 大一点（因为加了骨骼数据）。

---

## 九、下一步：下载动画

绑骨完成后，还需要下载 4 个动画。有两条路：

### 路线A：回 Mixamo 下动画（推荐）

> ⚠️ **注意**：Mixamo 的动画必须套在 Mixamo 自己绑骨的模型上。
> 如果 Mixamo 绑骨还是失败，用路线B。

1. 打开 https://www.mixamo.com
2. 上传 `player2.fbx`（原始的，不是 AccuRIG 导出的）
3. 如果 Mixamo 这次绑骨成功了 → 下载 4 个动画
4. 如果还是失败 → 用路线B

### 路线B：用 AccuRIG 的动画库

AccuRIG 自带基础动画库：

1. 绑骨完成后，点 **"Motion"** 或 **"Animation"** 标签
2. 搜索动画：
   - Idle / Breathing
   - Jog / Run
   - Throw
   - Stumble / Fall
3. 选中动画 → 点 **"Apply"** 套用到模型
4. 点 **File → Export**，这次勾上 **Include Animation**
5. 每个动画分别导出

**导出命名：**
| 动画 | 文件名 |
|------|--------|
| 待机 | player2_idle.fbx |
| 跑步 | player2_run.fbx |
| 投球 | player2_throw.fbx |
| 受击 | player2_hurt.fbx |

保存到：`建模素材库/3D模型素材/player2动作/`

---

## 十、完成后的文件结构

```
建模素材库/
  3D模型素材/
    player2.fbx                  ← 原始模型（Blender转的）
    player2_rigged.fbx           ← AccuRIG绑骨后的模型（备用）
    player2动作/
      player2_idle.fbx           ← 待机动画
      player2_run.fbx            ← 跑步动画
      player2_throw.fbx          ← 投球动画
      player2_hurt.fbx           ← 受击动画
```

---

## 常见问题

| 问题 | 解决 |
|------|------|
| 导入FBX贴图丢失 | 检查 Blender 导出时是否勾了 Embed Textures |
| Auto Rig 检测不到关节 | 模型可能不是 T-pose，回 Blender 检查 |
| 绑骨后动作扭曲 | 手动调整关节点，重新 Create Rig |
| 导出文件太大 | AccuRIG 导出时减面（Decimate） |
| 找不到动画库 | AccuRIG 免费版动画少，可去 Mixamo 下 |

---

## 时间预算

| 步骤 | 耗时 |
|------|------|
| 导入模型 | 1分钟 |
| Auto Rig 自动检测 | 1分钟 |
| 检查微调关节点 | 3-5分钟 |
| Create Rig 生成骨骼 | 1分钟 |
| 预览测试 | 2分钟 |
| 导出 FBX | 1分钟 |
| **合计** | **约10分钟** |

---

*文档版本：v1.0（2026-07-14）*
