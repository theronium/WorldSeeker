# 使い捨ての確認用スクリプト(2026-09-21)。マップ編集(docs/scenario_editor.md、tools/scenario-editor/)の確認:
# エディタのロジック(worldlogic.js)で編集したシナリオを、ゲーム本体が読めて、遊べるか。
#   エリア・セクション・フロアの追加、IDの変更(接続・アイテム・イベントへの波及)、並べ替え、別セクションへの移動、削除、
#   4種類のゲート(戦闘/技能/アイテム/生まれ)、アイテム定義 → 読み込んだ並び・接続・ゲートが期待どおりか、
#   追加したフロアが実際に発見されるか、セーブ/ロードの往復。
# 前処理(隔離したAPPDATAの、カスタムシナリオの置き場へ、編集済みシナリオを書き出す):
#   APPDATA=<隔離した空のディレクトリ> node tools/scenario-editor/test/make_edited_scenario.js <APPDATA>/Godot/app_userdata/WorldSeeker/scenarios
# 実行: APPDATA=<同じディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
extends SceneTree

var _ran := false
var _completed := false # _run()が最後まで走ったか(途中でスクリプトエラーが出ても、失敗0件で「成功」と出ないようにする)
var _fails := 0

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	if not _completed:
		print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
	else:
		print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
	return true

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

func _run() -> void:
	var save = root.get_node("SaveSystem"); var world_map = root.get_node("WorldMap"); var scenario = root.get_node("ScenarioEvents")
	var items = root.get_node("Items"); var parties = root.get_node("Parties"); var exploration = root.get_node("Exploration")
	var schema = root.get_node("WorldSchemaDb")

	var expected_text := FileAccess.get_file_as_string("user://scenarios/edited_expected.json")
	if expected_text == "":
		print("NG  期待値(edited_expected.json)が無い。先にmake_edited_scenario.jsを実行すること")
		_fails += 1
		return
	var expected: Dictionary = JSON.parse_string(expected_text)

	_check("一覧に編集済みシナリオが出る", ScenarioStore.list_scenarios().any(func(s): return s["id"] == "edited" and s["source"] == "custom"))
	var slot: int = save.create_new_slot("編集確認", "edited", "custom")
	_check("新規開始: 編集済みの世界が読み込まれた", scenario.info.get("id", "") == "edited" and world_map.nodes.size() == int(expected["node_count"]), "%d / %d" % [world_map.nodes.size(), int(expected["node_count"])])

	# --- 並び(エリア・セクション・フロア) ---
	_check("エリアの並び(先頭へ動かした結果を含む)", Array(world_map.areas.keys()) == expected["areas"], str(world_map.areas.keys()))
	_check("エリアの並び: 追加した試験エリアは最後", world_map.areas.keys().back() == "smoke_area")
	var sections_ok := true
	for area_id in expected["areas"]:
		if Array(world_map.sections_in_area(area_id)) != expected["sections_by_area"][area_id]:
			sections_ok = false
			print("   セクションの並びが違う: ", area_id, " ", world_map.sections_in_area(area_id), " != ", expected["sections_by_area"][area_id])
	_check("セクションの並び(エリアごと。並べ替え・移動・削除を含む)", sections_ok)
	var floors_ok := true
	for section_id in expected["floors_by_section"].keys():
		if Array(world_map.nodes_in_section(section_id)) != expected["floors_by_section"][section_id]:
			floors_ok = false
			print("   フロアの並びが違う: ", section_id, " ", world_map.nodes_in_section(section_id), " != ", expected["floors_by_section"][section_id])
	_check("フロアの並び(セクションごと。=マップ画面の配置。並べ替え・移動を含む)", floors_ok)
	_check("試験セクションの並び", Array(world_map.nodes_in_section("smoke_section")) == ["smoke_a", "smoke_b", "smoke_c", "smoke_d"], str(world_map.nodes_in_section("smoke_section")))

	# --- 削除 ---
	var gone := true
	for floor_id in expected["deleted_floors"]:
		if world_map.nodes.has(floor_id):
			gone = false
	_check("削除: セクション(%s)と、その中のフロアが無い" % expected["deleted_section"], gone and not world_map.sections.has(expected["deleted_section"]))
	var dangling := 0
	for id in world_map.nodes.keys():
		for neighbor in world_map.nodes[id]["connections"]:
			if not world_map.nodes.has(neighbor):
				dangling += 1
	_check("削除: 消えたフロアへの接続が残っていない", dangling == 0, str(dangling))

	# --- 接続(双方向) ---
	var connections_ok := true
	for id in expected["connections"].keys():
		if Array(world_map.nodes[id]["connections"]) != expected["connections"][id]:
			connections_ok = false
			print("   接続が違う: ", id, " ", world_map.nodes[id]["connections"], " != ", expected["connections"][id])
	_check("接続: 全フロアが期待どおり(追加・ID変更・削除を含む)", connections_ok)
	_check("接続: 追加したフロアが、既存のフロア(village)と双方向につながる", "smoke_a" in world_map.nodes["village"]["connections"] and "village" in world_map.nodes["smoke_a"]["connections"])

	# --- ゲート・報酬・アイテム ---
	var gate_b: Dictionary = world_map.nodes["smoke_b"]["gate"]
	_check("ゲート(技能): 技能名が内部の整数になり、レベルは整数", gate_b["skill"] == SkillTypes.Skill.LOCKPICKING and gate_b["min_level"] == 2 and typeof(gate_b["min_level"]) == TYPE_INT, str(gate_b))
	_check("ゲート(戦闘): 敵の戦闘力", world_map.nodes["smoke_a"]["gate"] == {"type": "combat", "enemy_power": 30}, str(world_map.nodes["smoke_a"]["gate"]))
	_check("ゲート(アイテム)", world_map.nodes["smoke_c"]["gate"] == {"type": "item", "item": "smoke_key"})
	_check("ゲート(生まれ)", world_map.nodes["smoke_d"]["gate"] == {"type": "innate_trait", "trait": "bloodline", "value": "王家の落胤"})
	_check("突破報酬", world_map.nodes["smoke_b"]["item_reward"] == "smoke_key" and world_map.nodes["smoke_d"]["item_reward"] == "reclass_elixir")
	_check("アイテム定義(追加・ID変更)", items.name_of("smoke_key") == "試験の鍵" and items.name_of("amulet_x") == "ゴブリンキングの護符", "%s / %s" % [items.name_of("smoke_key"), items.name_of("amulet_x")])
	_check("アイテム定義: 変更前のIDは無い", items.name_of("goblin_amulet") != "ゴブリンキングの護符")
	var amulet_gate := false
	for id in world_map.nodes.keys():
		var gate: Dictionary = world_map.nodes[id]["gate"]
		if gate.get("type", "") == "item" and gate.get("item", "") == "amulet_x":
			amulet_gate = true
	_check("ID変更: アイテムのゲートも付け替わっている", amulet_gate)
	_check("エリアの倍率: 最後のエリア(試験エリア)は×%d" % expected["areas"].size(), world_map.section_multiplier("smoke_section") == int(expected["areas"].size()))
	_check("最初のセクション: 先頭のエリアの先頭", world_map.first_section() == expected["sections_by_area"][expected["areas"][0]][0], world_map.first_section())

	# --- イベントの追随(IDの変更) ---
	_check("イベント: ID変更したフロアの会話が、新しいIDで引ける", not scenario.gate_event(expected["gate_event_floor"], true).is_empty())
	_check("イベント: 古いIDでは引けない", scenario.gate_event("old_shrine", true).is_empty())
	_check("イベント: 書き換わったイベントがある(%d本)" % expected["changed_events"].size(), expected["changed_events"].size() > 0)

	# --- 遊べるか: 追加した試験セクションを担当させて、日を進める ---
	var party: Dictionary = parties.get_parties()[0]
	parties.assign_section(party["id"], "smoke_section")
	_check("発見の前提: 試験の入口が、発見できるフロア(frontier)に出る", "smoke_a" in world_map.frontier_for_section("smoke_section"), str(world_map.frontier_for_section("smoke_section")))
	_check("試験セクションは、担当に選べる(到達可能)", world_map.is_section_reachable("smoke_section"))
	var found_day := -1
	for day in range(1, 201):
		exploration._on_day_advanced(day)
		if found_day < 0 and world_map.is_found("smoke_a"):
			found_day = day
		if world_map.is_passed("smoke_a") and found_day > 0 and day > found_day + 5:
			break
	_check("探索: 追加したフロア(試験の入口)を発見できた", found_day > 0, "発見=%d日目" % found_day)
	print("   (突破済み: ", world_map.nodes_in_section("smoke_section").filter(func(id): return world_map.is_passed(id)), ")")

	# --- セーブ/ロードの往復 ---
	var passed_before: Array = world_map.nodes.keys().filter(func(id): return world_map.is_found(id))
	save.save_game()
	world_map.reset()
	schema.import_into_worldmap(schema.active_version_id)
	save.load_game()
	var passed_after: Array = world_map.nodes.keys().filter(func(id): return world_map.is_found(id))
	_check("往復: 発見済みのフロアが戻り、編集済みの世界のまま", passed_after == passed_before and world_map.nodes.size() == int(expected["node_count"]), "%d -> %d" % [passed_before.size(), passed_after.size()])
	_completed = true
