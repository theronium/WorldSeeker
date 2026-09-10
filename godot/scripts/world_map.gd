extends Node
# ワールドの階層構造(エリア > セクション > フロア)とノードグラフを保持する。
#
# - エリア(area)   : 国や地方などの最上位区分
# - セクション(section): ダンジョンやフィールドなど、NPCの担当エリア割り当ての単位
# - フロア(node)   : 個々の場所(ノードグラフの1ノード)
#
# ノードは3状態を取る:
#   未発見          found=false, passed=false
#   発見済みだが進めない  found=true,  passed=false (ゲート未突破)
#   突破済み         found=true,  passed=true

var areas: Dictionary = {} # area_id -> {id, name}
var sections: Dictionary = {} # section_id -> {id, name, area}
var nodes: Dictionary = {} # id -> {name, connections, found, passed, gate, section, event_script_pass, event_script_fail}

func add_area(id: String, display_name: String) -> void:
	areas[id] = {"id": id, "name": display_name}

func add_section(id: String, display_name: String, area_id: String = "") -> void:
	sections[id] = {"id": id, "name": display_name, "area": area_id}

func add_node(id: String, display_name: String, connections: Array, gate: Dictionary = {}, section: String = "", item_reward: String = "") -> void:
	nodes[id] = {
		"id": id,
		"name": display_name,
		"connections": connections,
		"found": false,
		"passed": false,
		"gate": gate, # 例: {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3} / {"type": "item", "item": "goblin_amulet"}
		"section": section, # 所属するセクション(ダンジョン/エリア)のsection_id（未所属なら空文字）
		"item_reward": item_reward, # 突破時に発見者へ渡すアイテムid（なければ空文字）
		"event_script_pass": [],
		"event_script_fail": [],
	}

func set_event_scripts(id: String, script_pass: Array, script_fail: Array) -> void:
	if nodes.has(id):
		nodes[id]["event_script_pass"] = script_pass
		nodes[id]["event_script_fail"] = script_fail

func has_event(id: String) -> bool:
	return nodes.has(id) and (not nodes[id]["event_script_pass"].is_empty() or not nodes[id]["event_script_fail"].is_empty())

func nodes_in_section(section_id: String) -> Array:
	return nodes.keys().filter(func(id): return nodes[id]["section"] == section_id)

func sections_in_area(area_id: String) -> Array:
	return sections.keys().filter(func(id): return sections[id]["area"] == area_id)

func mark_found(id: String) -> void:
	if nodes.has(id):
		nodes[id]["found"] = true

func mark_passed(id: String) -> void:
	if nodes.has(id):
		nodes[id]["found"] = true
		nodes[id]["passed"] = true

func is_found(id: String) -> bool:
	return nodes.has(id) and nodes[id]["found"]

func is_passed(id: String) -> bool:
	return nodes.has(id) and nodes[id]["passed"]

func is_section_entered(section_id: String) -> bool:
	for id in nodes_in_section(section_id):
		if nodes[id]["found"]:
			return true
	return false

func is_area_entered(area_id: String) -> bool:
	for section_id in sections_in_area(area_id):
		if is_section_entered(section_id):
			return true
	return false

func neighbors(id: String) -> Array:
	if not nodes.has(id):
		return []
	return nodes[id]["connections"]

func can_pass_gate(id: String, npc_id: int) -> bool:
	if not nodes.has(id):
		return false
	var gate: Dictionary = nodes[id].get("gate", {})
	if gate.is_empty():
		return true
	match gate.get("type", ""):
		"skill":
			return Npcs.skill_level(npc_id, gate["skill"]) >= gate["min_level"]
		"innate_trait":
			var npc := Npcs.get_npc(npc_id)
			return npc.get("innate_traits", {}).get(gate["trait"], null) == gate["value"]
		"item":
			return Items.has_item(npc_id, gate["item"])
		_:
			return true

func save_progress() -> Dictionary:
	var result := {}
	for id in nodes.keys():
		if nodes[id]["found"]:
			result[id] = {"found": true, "passed": nodes[id]["passed"]}
	return result

func load_progress(states: Dictionary) -> void:
	for id in states.keys():
		if nodes.has(id):
			nodes[id]["found"] = bool(states[id]["found"])
			nodes[id]["passed"] = bool(states[id]["passed"])

func frontier_for_section(section_id: String) -> Array:
	# そのセクション内で、通過済みノードに隣接するがまだ未発見のノード一覧。
	# 隣接元は他セクションの通過済みノードでもよい(ダンジョンの入口が村側からつながる場合など)。
	var result := []
	for id in nodes_in_section(section_id):
		if nodes[id]["found"]:
			continue
		for neighbor_id in nodes[id]["connections"]:
			if nodes.has(neighbor_id) and nodes[neighbor_id]["passed"]:
				result.append(id)
				break
	return result
