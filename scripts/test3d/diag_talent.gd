extends Node3D
func _ready() -> void:
	var talent = get_node("/root/TalentSystem")
	talent.unlocked.clear()
	PlayerSaveManager.save_team_talent_tree([])
	print("[DT] 清空后 get=", PlayerSaveManager.get_team_talent_tree())
	var r1: bool = talent.try_unlock("atk_1")
	print("[DT] try_unlock=", r1, " unlocked=", talent.unlocked, " bonuses=", talent.get_team_bonuses())
	print("[DT] save 后 get=", PlayerSaveManager.get_team_talent_tree())
	var p0: float = 0
	var arena = null
	# 直接检查 reload 场景
	get_tree().quit()
