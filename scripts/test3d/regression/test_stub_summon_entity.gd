extends Node2D
class_name TestStubSummonEntity
## 测试专用 stub 召唤实体（对齐 23b 召唤物系统契约的最小字段面；仅供桥接/显示套件消费）
## 真实实体=summon_entity.gd 基类（F1 域），本 stub 零行为零判定，只有显示层消费的声明字段

var summon_type: String = ""
var state: String = "active"        # active / burrowed / consumed（23b 状态机子集）
var _tdef: Dictionary = {}          # 类型表下发（23b §三；kind=shark/magic_ball）
