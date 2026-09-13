extends Node
# 雇用NPCの名簿管理。

enum Status { IDLE, EXPLORING, RECOVERING }
enum CombatAction { USE_ITEM, RETREAT }
## 担当セクションを完全踏破した後の挙動(exploration.gdが月次/攻略時に参照する)。
## STAY: そのセクションに留まり続け、収入源として維持する。
## MOVE_ON: 次の未踏破セクションへ自動的に再配置される(無ければ何もしない)。
enum PostClearBehavior { STAY, MOVE_ON }

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
		"post_clear_behavior": PostClearBehavior.MOVE_ON,
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

func set_post_clear_behavior(id: int, behavior: int) -> void:
	if roster.has(id):
		roster[id]["post_clear_behavior"] = behavior

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

func save_state() -> Dictionary:
	return {"next_id": _next_id, "roster": roster}

## JSON往復後はDictionaryキーが全て文字列に、数値が全てfloatになるため、
## id/スキル種別(int)をキーに使うroster/skillsは明示的に復元し直す必要がある。
func load_state(data: Dictionary) -> void:
	roster = {}
	var max_id := 0
	for key in data.get("roster", {}).keys():
		var id := int(key)
		var npc: Dictionary = data["roster"][key]
		npc["id"] = id
		npc["status"] = int(npc["status"])
		npc["recovering_until_day"] = int(npc["recovering_until_day"])
		npc["combat_policy"]["action"] = int(npc["combat_policy"]["action"])
		npc["post_clear_behavior"] = int(npc.get("post_clear_behavior", PostClearBehavior.MOVE_ON))
		var skills := {}
		for skill_key in npc["skills"].keys():
			var entry: Dictionary = npc["skills"][skill_key]
			skills[int(skill_key)] = {"level": int(entry["level"]), "exp": int(entry["exp"])}
		npc["skills"] = skills
		roster[id] = npc
		max_id = max(max_id, id)
	_next_id = max(int(data.get("next_id", 1)), max_id + 1)

## 新規プレイ開始(複数セーブスロット、save_system.gd)用のリセット。
func reset() -> void:
	roster = {}
	_next_id = 1
