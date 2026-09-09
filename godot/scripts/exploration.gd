extends Node
# 担当セクションに割り当てられた雇用NPCの自動探索を日次で処理する。
#
# 1日ごとに各NPCは:
#   1. 発見済みだが未突破のゲートを、現在のスキル値/戦闘力で無音に再判定する
#      (戦闘ゲートは実際にcombat.gdで解決され、敗北/撤退時はNPCが一時的に離脱する)
#   2. 担当セクションの未発見の隣接ノード全てに、知覚スキルに応じた確率で発見を試みる
#      (発見に成功した瞬間だけ、そのノードにイベント台本があれば会話を再生する)
#
# 掲示板には、フロア単位の発見は所属セクションのスレッドにのみ記録し、
# セクション/エリアへの初到達やイベントだけを全体フィードに載せる(wild_npcs.gdも本モジュールを利用する)。

const DISCOVERY_BASE_CHANCE := 0.2
const DISCOVERY_PER_PERCEPTION := 0.1
const DISCOVERY_MAX_CHANCE := 0.9

func _ready() -> void:
	TimeSystem.day_advanced.connect(_on_day_advanced)

func _on_day_advanced(current_day: int) -> void:
	for npc in Npcs.get_roster():
		if npc["status"] != Npcs.Status.EXPLORING:
			continue
		if not Npcs.is_available(npc["id"], current_day):
			continue
		_retry_gates(npc, current_day)
		if Npcs.is_available(npc["id"], current_day):
			_attempt_discovery(npc, current_day)

func _retry_gates(npc: Dictionary, current_day: int) -> void:
	for node_id in WorldMap.nodes_in_section(npc["assigned_section"]):
		if not Npcs.is_available(npc["id"], current_day):
			return # 戦闘で撤退し離脱した場合、この日はもう動けない
		var node: Dictionary = WorldMap.nodes[node_id]
		if node["found"] and not node["passed"]:
			if _attempt_gate(npc["id"], node_id, current_day):
				WorldMap.mark_passed(node_id)
				_grant_item_reward(npc["id"], node)
				_post_floor(npc["name"], node_id, current_day, "%sが「%s」を突破した" % [npc["name"], node["name"]])

func _attempt_discovery(npc: Dictionary, current_day: int) -> void:
	# 担当セクションの未発見の隣接ノード全てに、並列で1回ずつ発見を試みる
	var frontier := WorldMap.frontier_for_section(npc["assigned_section"])
	var perception := Npcs.skill_level(npc["id"], SkillTypes.Skill.PERCEPTION)
	var chance: float = min(DISCOVERY_MAX_CHANCE, DISCOVERY_BASE_CHANCE + perception * DISCOVERY_PER_PERCEPTION)

	for node_id in frontier:
		if not Npcs.is_available(npc["id"], current_day):
			return
		Npcs.grant_skill_exp(npc["id"], SkillTypes.Skill.PERCEPTION, 1)
		if randf() < chance:
			_on_node_found(npc["name"], npc["id"], node_id, current_day)

func _on_node_found(discoverer_name: String, npc_id: int, node_id: String, current_day: int) -> void:
	var node: Dictionary = WorldMap.nodes[node_id]

	if WorldMap.has_event(node_id):
		if EventDialogue.is_active:
			return # 今日は既に別の会話中なので見送り、翌日また発見を試みる
		var milestone := _capture_milestone_state(node_id)
		WorldMap.mark_found(node_id)
		var passed := _attempt_gate(npc_id, node_id, current_day)
		var script: Array = node["event_script_pass"] if passed else node["event_script_fail"]
		EventDialogue.finished.connect(
			func(outcome: String): _finalize_discovery(discoverer_name, node_id, outcome == "pass", current_day, milestone, npc_id),
			CONNECT_ONE_SHOT)
		EventDialogue.play(script)
		return

	var milestone := _capture_milestone_state(node_id)
	WorldMap.mark_found(node_id)
	_finalize_discovery(discoverer_name, node_id, _attempt_gate(npc_id, node_id, current_day), current_day, milestone, npc_id)

## 野良NPC(wild_npcs.gd)からも使う、ステータス不問の簡易発見処理。
## ゲートがあるノードは「発見済みだが進めない」までしか進められない(実際の突破は雇用NPCの役目)。
func wild_discover(node_id: String, current_day: int) -> void:
	var node: Dictionary = WorldMap.nodes[node_id]
	if node["found"]:
		return
	var milestone := _capture_milestone_state(node_id)
	WorldMap.mark_found(node_id)
	var passed: bool = node["gate"].is_empty()
	_finalize_discovery("野良の旅人", node_id, passed, current_day, milestone)

func _capture_milestone_state(node_id: String) -> Dictionary:
	var section_id: String = WorldMap.nodes[node_id]["section"]
	var area_id: String = WorldMap.sections[section_id]["area"] if WorldMap.sections.has(section_id) else ""
	return {
		"section_id": section_id,
		"area_id": area_id,
		"was_section_entered": WorldMap.is_section_entered(section_id),
		"was_area_entered": area_id != "" and WorldMap.is_area_entered(area_id),
	}

func _finalize_discovery(discoverer_name: String, node_id: String, passed: bool, current_day: int, milestone: Dictionary, npc_id: int = -1) -> void:
	var node: Dictionary = WorldMap.nodes[node_id]
	if passed:
		WorldMap.mark_passed(node_id)
		if npc_id != -1:
			_grant_item_reward(npc_id, node)
		_post_floor(discoverer_name, node_id, current_day, "%sが「%s」を発見した" % [discoverer_name, node["name"]])
	else:
		_post_floor(discoverer_name, node_id, current_day, "%sが「%s」を発見したが、まだ先へ進めない" % [discoverer_name, node["name"]])

	if not milestone["was_section_entered"]:
		var section_name: String = WorldMap.sections[milestone["section_id"]]["name"] if WorldMap.sections.has(milestone["section_id"]) else milestone["section_id"]
		Board.post(current_day, "「%s」に初めて到達した" % section_name, Board.Importance.MAJOR, "exploration")
	if milestone["area_id"] != "" and not milestone["was_area_entered"]:
		var area_name: String = WorldMap.areas[milestone["area_id"]]["name"] if WorldMap.areas.has(milestone["area_id"]) else milestone["area_id"]
		Board.post(current_day, "「%s」に初めて足を踏み入れた" % area_name, Board.Importance.MAJOR, "exploration")

func _grant_item_reward(npc_id: int, node: Dictionary) -> void:
	var item_id: String = node.get("item_reward", "")
	if item_id == "":
		return
	Items.grant(npc_id, item_id)

func _post_floor(discoverer_name: String, node_id: String, current_day: int, text: String) -> void:
	var section_id: String = WorldMap.nodes[node_id]["section"]
	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else section_id
	Board.post_to_thread(section_id, section_name, current_day, text, Board.Importance.MINOR, "exploration")

func _attempt_gate(npc_id: int, node_id: String, current_day: int) -> bool:
	var gate: Dictionary = WorldMap.nodes[node_id]["gate"]
	match gate.get("type", ""):
		"combat":
			var result: Dictionary = Combat.resolve_encounter(npc_id, gate["enemy_power"], current_day)
			return result["result"] == "victory"
		"skill":
			# 挑戦するたびに、たとえ突破できなくても該当スキルの経験値が入る
			# (5.2節: 試行を重ねることでいつか開ける、という思想を全スキルに適用)
			Npcs.grant_skill_exp(npc_id, gate["skill"], 1)
			return WorldMap.can_pass_gate(node_id, npc_id)
		_:
			return WorldMap.can_pass_gate(node_id, npc_id)
