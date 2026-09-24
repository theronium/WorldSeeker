# 使い捨ての確認用スクリプト(2026-09-24)。報告「戦わず撤退した時に、深手を負う演出が入ってしまう」の再発防止。
# 勝ち目が無く戦わなかった(retreat_before_fight)会話付きの戦闘ゲートで、結末の会話が、失敗の台本(「深手を負って
# 撤退した」など戦った前提の文)ではなく、戦わずに引き返した旨の1行(Exploration.RETREAT_BEFORE_FIGHT_TEXT)になるか。
# 実際に戦って負けた場合は、従来どおり失敗の台本の結末が出ることも確かめる。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree

var _frames := 0
var _completed := false
var _fails := 0
var _lines: Array = [] # 会話で表示された行の文(line_shownで集める)

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		return false
	if _frames == 3:
		_run()
		if not _completed:
			print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
		else:
			print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
		return true
	return false

## 会話を読み切り、戦闘画面が開いたら閉じる(前置き→戦闘画面→結末、の順に全部進める)。
func _play_through() -> void:
	var dialogue = root.get_node("EventDialogue"); var battle = root.get_node("BattleScreen")
	for _round in 10:
		var guard := 0
		while dialogue.is_active and guard < 50:
			guard += 1
			dialogue.advance()
		if battle.is_active:
			battle.close()
		elif not dialogue.is_active:
			return

## fail側の台本の、前置き(pass側と共通の先頭)より後の文。
func _fail_ending_texts(events, floor_id: String) -> Array:
	var pass_script: Array = events.gate_event(floor_id, true).get("script", [])
	var fail_script: Array = events.gate_event(floor_id, false).get("script", [])
	var intro_len := 0
	while intro_len < pass_script.size() and intro_len < fail_script.size() and pass_script[intro_len] == fail_script[intro_len]:
		intro_len += 1
	return fail_script.slice(intro_len).map(func(line): return String(line.get("text", "")))

func _setup_floor(world_map, parties, pid: int, floor_id: String) -> void:
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	var section_id: String = world_map.nodes[floor_id]["section"]
	for id in world_map.nodes_in_section(section_id):
		if id != floor_id:
			world_map.mark_passed(id, true)
	parties.assign_section(pid, section_id)

func _run() -> void:
	var world_map = root.get_node("WorldMap"); var parties = root.get_node("Parties"); var save = root.get_node("SaveSystem")
	var dialogue = root.get_node("EventDialogue"); var events = root.get_node("ScenarioEvents"); var settings = root.get_node("Settings")
	var exploration = root.get_node("Exploration"); var combat = root.get_node("Combat")
	dialogue.line_shown.connect(func(line: Dictionary): _lines.append(String(line.get("text", ""))))
	_play_through()
	settings.set_show_battle_screen(true)

	print("=== 勝ち目が無く、戦わずに撤退 ===")
	save.start_fresh_session()
	var party: Dictionary = parties.get_parties()[0]
	var pid: int = party["id"]
	var hopeless_floor := ""
	for id in world_map.nodes.keys():
		var gate: Dictionary = world_map.nodes[id]["gate"]
		if gate.get("type", "") == "combat" and events.has_gate_event(id) and int(gate["enemy_power"]) > 500 \
				and not _fail_ending_texts(events, id).is_empty():
			hopeless_floor = id
			break
	_check("前提: 満タンでも勝てない、会話付きの戦闘ゲートがある", hopeless_floor != "", hopeless_floor)
	_setup_floor(world_map, parties, pid, hopeless_floor)
	_check("前提: 挑まずに撤退する相手", exploration._is_hopeless_gate(party, world_map.nodes[hopeless_floor]))
	var fail_endings := _fail_ending_texts(events, hopeless_floor)
	_lines.clear()
	exploration._on_node_found("斥候", party["member_ids"][0], party, hopeless_floor, 1)
	_play_through()
	var expected: String = exploration.RETREAT_BEFORE_FIGHT_TEXT % party["name"]
	_check("結末は、戦わずに引き返した旨の1行", _lines.has(expected), str(_lines))
	_check("失敗の台本の結末(戦った前提の文)は出ない", not fail_endings.any(func(t): return _lines.has(t)), str(fail_endings))
	_check("フロアは突破されていない", not world_map.is_passed(hopeless_floor))
	_check("会話は全て閉じている", not dialogue.is_active)

	print("=== 実際に戦って負けた場合は、従来どおり失敗の台本 ===")
	save.start_fresh_session()
	party = parties.get_parties()[0]
	pid = party["id"]
	# 満タンなら勝ち目があり挑むが、今のHP(=1)では負ける状況を作る(sim_battle_screen.gdと同じく、固有スキルの乱数を
	# 消した上で、戦闘力のLvを1ずつ試して探す)。
	var npcs = root.get_node("Npcs")
	var lose_floor := ""
	for id in world_map.nodes.keys():
		var gate: Dictionary = world_map.nodes[id]["gate"]
		if gate.get("type", "") == "combat" and events.has_gate_event(id) and not _fail_ending_texts(events, id).is_empty():
			lose_floor = id
			break
	for id in party["member_ids"]:
		var npc = npcs.get_npc(id)
		npc["unique_skill"] = {}
		npc["max_hp"] = 100.0
		npc["hp"] = 100.0
	var found_level := false
	if lose_floor != "":
		var enemy_power: int = world_map.nodes[lose_floor]["gate"]["enemy_power"]
		for level in range(1, 60):
			for id in party["member_ids"]:
				npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]["level"] = level
				npcs.get_npc(id)["hp"] = 100.0
			if combat.predict_party_result(pid, enemy_power, true) != "victory":
				continue
			for id in party["member_ids"]:
				npcs.get_npc(id)["hp"] = 1.0
			if combat.predict_party_result(pid, enemy_power, false) != "victory":
				found_level = true
				break
	if not found_level:
		lose_floor = ""
	if lose_floor == "":
		print("(初期パーティで、挑むが負ける会話付きの戦闘ゲートが無いので、この確認は省略)")
	else:
		_setup_floor(world_map, parties, pid, lose_floor)
		var endings := _fail_ending_texts(events, lose_floor)
		_lines.clear()
		exploration._on_node_found("斥候", party["member_ids"][0], party, lose_floor, 1)
		_play_through()
		_check("失敗の台本の結末が出る", endings.all(func(t): return _lines.has(t)), "%s / %s" % [str(endings), str(_lines)])
		_check("戦わずに引き返した旨の1行は出ない", not _lines.has(exploration.RETREAT_BEFORE_FIGHT_TEXT % party["name"]))
	_completed = true
