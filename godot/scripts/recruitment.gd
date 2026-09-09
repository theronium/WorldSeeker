extends Node
# 募集(候補提示)から雇用までのフロー。

const BLOODLINES := ["平民", "旧家の血筋", "森人の血", "王家の落胤"]

var current_candidates: Array = []

func post_recruitment() -> bool:
	if not Economy.spend(Economy.recruitment_post_cost()):
		return false
	current_candidates = _generate_candidates(3)
	return true

func _generate_candidates(count: int) -> Array:
	var candidates := []
	for i in range(count):
		var quality := randf()
		var skills := {}
		for skill in SkillTypes.all_skills():
			skills[skill] = randi_range(0, 2) + int(quality * 3)
		candidates.append({
			"name": "候補%d" % (i + 1),
			"quality": quality,
			"innate_traits": {"bloodline": BLOODLINES[randi() % BLOODLINES.size()]},
			"skills": skills,
			"cost": Economy.hire_cost(quality),
		})
	return candidates

func hire_candidate(index: int) -> int:
	if index < 0 or index >= current_candidates.size():
		return -1
	if Npcs.get_roster().size() >= Economy.employ_cap:
		return -1
	var candidate: Dictionary = current_candidates[index]
	if not Economy.spend(candidate["cost"]):
		return -1
	var id := Npcs.hire(candidate["name"], candidate["innate_traits"], candidate["skills"])
	current_candidates.remove_at(index)
	return id
