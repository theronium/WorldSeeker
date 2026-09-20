extends SceneTree
# 一度きりの移行ツール(2026-09-21): world_data.gd(GDScript直書きのワールド)+案内会話4本+話者の画像対応表を、
# デフォルトシナリオ(godot/scenarios/default/)のJSONへ書き出す。書き出した後、読み直した内容が元のWorldMapと
# 一致するか(順序・ゲート・接続・会話の台本)を照合して、結果を表示する。
# world_data.gdをシナリオ読み込みへ置き換えた後は、元になるものが無いので実行できない(git履歴に残っている)。
#
# 実行: APPDATA=<空の隔離ディレクトリ> "$GODOT_EXE" --headless --path godot --script <このファイルの絶対パス>

const OUT_DIR := "res://scenarios/default"

func _process(_delta: float) -> bool:
	var world_map = root.get_node("WorldMap")
	var items = root.get_node("Items")

	var world := {"items": [], "areas": [], "sections": [], "nodes": []}
	for item_id in items.definitions.keys():
		world["items"].append({"id": item_id, "name": items.definitions[item_id]["name"]})
	for area_id in world_map.areas.keys():
		world["areas"].append({"id": area_id, "name": world_map.areas[area_id]["name"]})
	for section_id in world_map.sections.keys():
		var s: Dictionary = world_map.sections[section_id]
		world["sections"].append({"id": section_id, "name": s["name"], "area": s["area"]})
	var events := []
	for node_id in world_map.nodes.keys():
		var n: Dictionary = world_map.nodes[node_id]
		world["nodes"].append({
			"id": node_id, "name": n["name"], "section": n["section"], "connections": n["connections"].duplicate(),
			"gate": ScenarioStore.encode_gate(n["gate"]), "item_reward": n["item_reward"], "initially_passed": n["passed"],
		})
		for result in ["pass", "fail"]:
			var script: Array = n["event_script_" + result]
			if script.is_empty():
				continue
			events.append({
				"id": "floor_%s_%s" % [node_id, result],
				"title": "%s(%s)" % [n["name"], "突破" if result == "pass" else "失敗"],
				"trigger": {"type": "gate", "floor": node_id, "result": result},
				"conditions": [], "repeat": false, "priority": 0, "kind": "auto",
				"script": script, "effects": [],
			})

	# 案内会話(チュートリアル)。定数はmain.gd/exploration.gdにあった。
	var main_consts: Dictionary = load("res://scripts/main.gd").get_script_constant_map()
	var exploration_consts: Dictionary = load("res://scripts/exploration.gd").get_script_constant_map()
	var guides := [
		["intro_part1", "導入(前編)", main_consts["INTRO_TUTORIAL_PART1_SCRIPT"]],
		["intro_part2", "導入(後編)", main_consts["INTRO_TUTORIAL_PART2_SCRIPT"]],
		["party_formed", "初めての雇用(パーティ編成の案内)", main_consts["PARTY_TUTORIAL_SCRIPT"]],
		["retreat", "初めての撤退", exploration_consts["RETREAT_TUTORIAL_SCRIPT"]],
	]
	for guide in guides:
		events.append({
			"id": "guide_" + guide[0], "title": guide[1],
			"trigger": {"type": "system", "name": guide[0]},
			"conditions": [], "repeat": false, "priority": 0, "kind": "guide",
			"script": guide[2], "effects": [],
		})

	var cast := []
	for speaker in EventPortraits.ENEMY_BY_NAME.keys():
		cast.append({"name": speaker, "image": EventPortraits.ENEMY_BY_NAME[speaker], "side": "right"})
	for speaker in EventPortraits.NPC_BY_NAME.keys():
		cast.append({"name": speaker, "image": EventPortraits.NPC_BY_NAME[speaker], "side": "left"})

	ScenarioStore.write_json(OUT_DIR + "/scenario.json", {
		"format": ScenarioStore.FORMAT, "id": "default", "name": "小さな王国から始まる探索",
		"description": "標準のシナリオ。9エリア・39セクション・194フロアのデモ規模のワールド。",
		"author": "Theronium", "start_year": 0, "start_month": 1,
	})
	ScenarioStore.write_json(OUT_DIR + "/world.json", world)
	ScenarioStore.write_json(OUT_DIR + "/cast.json", cast)
	for event in events:
		ScenarioStore.write_json("%s/events/%s.json" % [OUT_DIR, event["id"]], event)
	print("書き出し: フロア%d 会話%d(うち案内%d) 話者%d" % [world["nodes"].size(), events.size(), guides.size(), cast.size()])

	_verify(world_map, items, events, cast)
	return true

## 読み直したスナップショットが、元のWorldMap・Itemsと一致するかを確認する。
func _verify(world_map, items, events: Array, cast: Array) -> void:
	var snap := ScenarioStore.load_scenario("default", "default")
	var problems: Array = []
	if snap.is_empty():
		print("照合失敗: 読み込めない")
		return
	if snap["items"].map(func(i): return [i["id"], i["name"]]) != items.definitions.keys().map(func(k): return [k, items.definitions[k]["name"]]):
		problems.append("items")
	if snap["areas"].map(func(a): return [a["id"], a["name"]]) != world_map.areas.keys().map(func(k): return [k, world_map.areas[k]["name"]]):
		problems.append("areas(順序含む)")
	if snap["sections"].map(func(s): return [s["id"], s["name"], s["area_id"]]) != world_map.sections.keys().map(func(k): return [k, world_map.sections[k]["name"], world_map.sections[k]["area"]]):
		problems.append("sections(順序含む)")
	if snap["nodes"].size() != world_map.nodes.size():
		problems.append("nodes数")
	var i := 0
	for node_id in world_map.nodes.keys():
		var n: Dictionary = world_map.nodes[node_id]
		var s: Dictionary = snap["nodes"][i]
		i += 1
		if s["id"] != node_id or s["name"] != n["name"] or s["section_id"] != n["section"] or s["item_reward"] != n["item_reward"]:
			problems.append("node基本 " + node_id)
		if s["connections"] != n["connections"]:
			problems.append("node接続(順序含む) " + node_id)
		if s["gate"] != n["gate"]:
			problems.append("nodeゲート " + node_id + " " + str(s["gate"]) + " vs " + str(n["gate"]))
		if s["initially_passed"] != n["passed"]:
			problems.append("初期突破 " + node_id)
	var by_id := {}
	for event in snap["events"]:
		by_id[event["id"]] = event
	for event in events:
		if not by_id.has(event["id"]):
			problems.append("会話なし " + event["id"])
		elif by_id[event["id"]]["script"] != ScenarioStore.normalize_script(event["script"]):
			problems.append("台本 " + event["id"])
	if snap["events"].size() != events.size():
		problems.append("会話の本数 %d vs %d" % [snap["events"].size(), events.size()])
	if snap["cast"].size() != cast.size():
		problems.append("話者数")
	print("照合: ", "OK(差異なし)" if problems.is_empty() else "差異あり " + str(problems))
