extends Node
# 雇用NPCの名簿管理。

enum Status { IDLE, EXPLORING, RECOVERING }
enum CombatAction { USE_ITEM, RETREAT }

var _next_id: int = 1
var roster: Dictionary = {} # id -> npc data

func hire(display_name: String, innate_traits: Dictionary, base_skills: Dictionary = {}) -> int:
	var id := _next_id
	_next_id += 1
	var skills := {}
	for skill in SkillTypes.all_skills():
		skills[skill] = {"level": base_skills.get(skill, 0), "exp": 0}
	roster[id] = {
		"id": id,
		"name": display_name,
		"innate_traits": innate_traits,
		"skills": skills,
		"hp": 100,
		"max_hp": 100,
		"status": Status.IDLE,
		"assigned_section": "",
		"combat_policy": {"hp_threshold": 0.3, "action": CombatAction.USE_ITEM},
		"recovering_until_day": -1,
		"inventory": [],
	}
	return id

func get_npc(id: int) -> Dictionary:
	return roster.get(id, {})

func get_roster() -> Array:
	return roster.values()

func assign_section(id: int, section_id: String) -> bool:
	if not roster.has(id) or not WorldMap.sections.has(section_id):
		return false
	roster[id]["assigned_section"] = section_id
	roster[id]["status"] = Status.EXPLORING
	return true

func set_combat_policy(id: int, hp_threshold: float, action: int) -> void:
	if roster.has(id):
		roster[id]["combat_policy"] = {"hp_threshold": hp_threshold, "action": action}

const EXP_PER_LEVEL := 10

func grant_skill_exp(id: int, skill: int, amount: int) -> void:
	if not roster.has(id):
		return
	var entry: Dictionary = roster[id]["skills"][skill]
	entry["exp"] += amount
	var needed: int = EXP_PER_LEVEL * (entry["level"] + 1)
	while entry["exp"] >= needed:
		entry["exp"] -= needed
		entry["level"] += 1
		needed = EXP_PER_LEVEL * (entry["level"] + 1)

func train_skill(id: int, skill: int, cost_paid: int) -> void:
	if not roster.has(id):
		return
	roster[id]["skills"][skill]["level"] += 1

func skill_level(id: int, skill: int) -> int:
	if not roster.has(id):
		return 0
	return roster[id]["skills"][skill]["level"]

func retreat_and_recover(id: int, current_day: int, recovery_days: int) -> void:
	if not roster.has(id):
		return
	roster[id]["status"] = Status.RECOVERING
	roster[id]["recovering_until_day"] = current_day + recovery_days

func is_available(id: int, current_day: int) -> bool:
	if not roster.has(id):
		return false
	var npc: Dictionary = roster[id]
	if npc["status"] != Status.RECOVERING:
		return true
	if current_day < npc["recovering_until_day"]:
		return false
	npc["status"] = Status.EXPLORING
	npc["hp"] = npc["max_hp"]
	return true
