# 使い捨ての確認用スクリプト(2026-09-21)。メイン画面を実際に組み立てて、シナリオ選択→新規プレイ→別の世界の描画
# (エリア選択バー・マップの作り直し)がエラー無く通ることを確認する。必ずAPPDATAを隔離して実行する。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
extends SceneTree

var _frames := 0
var _main: Node

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	if _frames == 5:
		_run()
		return true
	return false

func _run() -> void:
	var world_map = root.get_node("WorldMap")
	print("起動: エリア%d フロア%d タブ%d" % [world_map.areas.size(), world_map.nodes.size(), _main.area_tab_buttons.size()])
	ScenarioStore.write_json("user://scenarios/ui_test/scenario.json", {"format": 1, "id": "ui_test", "name": "UI確認", "description": "d", "start_year": 5, "start_month": 2})
	ScenarioStore.write_json("user://scenarios/ui_test/world.json", {
		"items": [], "areas": [{"id": "x1", "name": "第一"}, {"id": "x2", "name": "第二"}],
		"sections": [{"id": "sx1", "name": "区画1", "area": "x1"}, {"id": "sx2", "name": "区画2", "area": "x2"}],
		"nodes": [
			{"id": "n1", "name": "入口", "section": "sx1", "connections": ["n2"], "gate": {}, "item_reward": "", "initially_passed": true},
			{"id": "n2", "name": "奥", "section": "sx1", "connections": ["n1", "n3"], "gate": {}, "item_reward": "", "initially_passed": false},
			{"id": "n3", "name": "別区画", "section": "sx2", "connections": ["n2"], "gate": {}, "item_reward": "", "initially_passed": false},
		],
	})
	_main._on_open_slots_pressed()
	var options: OptionButton = _main.new_game_scenario_option
	var labels := []
	for i in options.item_count:
		labels.append(options.get_item_text(i))
	print("選べるシナリオ: ", labels, " 選択中=", options.get_item_text(options.selected))
	var target := -1
	for i in options.item_count:
		if options.get_item_metadata(i)["id"] == "ui_test":
			target = i
	options.select(target)
	_main._on_new_game_pressed()
	print("確認文: ", _main.new_game_confirm.dialog_text)
	_main._on_new_game_confirmed()
	print("新規後: エリア%d フロア%d タブ%s 暦%s 選択中エリア=%s" % [world_map.areas.size(), world_map.nodes.size(), _main.area_tab_buttons.keys(), root.get_node("TimeSystem").format_date(), _main._active_area_id])
	print("マップのフロア箱: ", _main.node_boxes.keys())
	_main._on_area_tab_pressed("x2")
	print("第二エリアへ: フロア箱=", _main.node_boxes.keys())
	_main._on_open_slots_pressed()
	var slot_texts := []
	for i in _main.slot_list.item_count:
		slot_texts.append(_main.slot_list.get_item_text(i))
	print("スロット一覧: ", slot_texts)
	# 標準へ戻す
	for i in options.item_count:
		if options.get_item_metadata(i)["id"] == "default":
			options.select(i)
	_main._on_new_game_confirmed()
	print("標準へ: エリア%d フロア%d タブ%d 選択中エリア=%s フロア箱=%d" % [world_map.areas.size(), world_map.nodes.size(), _main.area_tab_buttons.size(), _main._active_area_id, _main.node_boxes.size()])
	DirAccess.remove_absolute("user://scenarios/ui_test")
