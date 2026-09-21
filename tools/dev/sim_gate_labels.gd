# 使い捨ての確認用スクリプト(2026-09-22)。マップの「突破待ち(発見済みだが進めない)」のフロアの箱に、解除に必要な条件を
# アイコン付きで出す(main.gdの_gate_icon/_gate_short_text/_refresh_map)ことの確認。
#   鍵開け🔒 / 知覚🔍 / 知恵🧩 / 破壊💥 / 戦闘⚔️ / 血筋👑 / 所持品🎒。突破済み・未発見の表示は従来どおり。
#   長い条件(アイテム名など)で箱が横に広がらないこと。フロア詳細のゲート説明にも同じアイコンが付くこと。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree

var _frames := 0
var _main: Node
var _completed := false
var _fails := 0
var _ids: Array = []
var _cases: Array = []

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	if _frames == 5:
		_setup_and_check_texts()
		return false
	if _frames == 12: # 文字を入れ替えた後のレイアウトが済んでから、箱の大きさを測る
		_check_layout_and_details()
		if not _completed:
			print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
		else:
			print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
		return true
	return false

func _finish(dialogue) -> void:
	var guard := 0
	while dialogue.is_active and guard < 50:
		guard += 1
		dialogue.advance()

func _setup_and_check_texts() -> void:
	var world_map = root.get_node("WorldMap"); var save = root.get_node("SaveSystem"); var dialogue = root.get_node("EventDialogue")
	var items = root.get_node("Items")
	_finish(dialogue)
	save.start_fresh_session()
	_main._refresh_all()

	_ids = _main.node_labels.keys()
	_check("前提: 表示中のエリアにフロアが9つ以上ある", _ids.size() >= 9, str(_ids.size()))
	var long_item := "phylactery_shard" # 「砕けたフィラクテリーの欠片」(最長級の名前)
	_check("前提: 長い名前のアイテムがある", items.name_of(long_item).length() >= 10, items.name_of(long_item))

	var W: int = SkillTypes.Skill.WISDOM; var L: int = SkillTypes.Skill.LOCKPICKING
	var D: int = SkillTypes.Skill.DESTRUCTION; var P: int = SkillTypes.Skill.PERCEPTION
	_cases = [
		[{"type": "skill", "skill": L, "min_level": 3}, "🔒 鍵開け Lv3"],
		[{"type": "skill", "skill": P, "min_level": 2}, "🔍 知覚/発見 Lv2"],
		[{"type": "skill", "skill": W, "min_level": 4}, "🧩 知恵 Lv4"],
		[{"type": "skill", "skill": D, "min_level": 3}, "💥 破壊 Lv3"],
		[{"type": "combat", "enemy_power": 320}, "⚔️ 敵の戦闘力 320"],
		[{"type": "innate_trait", "trait": "bloodline", "value": "旧家の血筋"}, "👑 血筋: 旧家の血筋"],
		[{"type": "item", "item": long_item}, "🎒 " + items.name_of(long_item)],
	]
	for i in range(_cases.size()):
		var id: String = _ids[i]
		world_map.nodes[id]["gate"] = _cases[i][0]
		world_map.nodes[id]["found"] = true
		world_map.nodes[id]["passed"] = false
	# 8つ目は突破済み、9つ目は未発見(従来どおりの表示)
	world_map.nodes[_ids[7]]["found"] = true
	world_map.nodes[_ids[7]]["passed"] = true
	world_map.nodes[_ids[8]]["found"] = false
	world_map.nodes[_ids[8]]["passed"] = false
	_main._refresh_map()
	for i in range(_cases.size()):
		var text: String = _main.node_labels[_ids[i]].text
		_check("突破待ち: %s" % _cases[i][1], text == _cases[i][1], text)
	_check("突破済みは、従来どおり「突破済み」", _main.node_labels[_ids[7]].text == "突破済み")
	_check("未発見は、従来どおり「未発見」", _main.node_labels[_ids[8]].text == "未発見")
	# ゲートの無い突破待ち(通常は起きない)は、従来の文言に戻す
	world_map.nodes[_ids[8]]["found"] = true
	world_map.nodes[_ids[8]]["gate"] = {}
	_main._refresh_map()
	_check("ゲートが無い突破待ちは、従来の「発見済み(進行不可)」", _main.node_labels[_ids[8]].text == "発見済み(進行不可)")
	world_map.nodes[_ids[8]]["found"] = false

func _check_layout_and_details() -> void:
	var node_size: Vector2 = _main._map_node_size()
	var widest := 0.0
	for i in range(_cases.size()):
		widest = maxf(widest, _main.node_boxes[_ids[i]].size.x)
	_check("長い条件でも、箱が横に広がらない(規定の幅以内)", widest <= node_size.x + 0.5, "最大=%.1f 規定=%.1f" % [widest, node_size.x])
	var long_label: Label = _main.node_labels[_ids[6]]
	_check("長い条件は「…」で省略する設定", long_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS)
	# フロア詳細・ゲート説明にも、同じアイコンが付く
	var expectations := [
		[0, "🔒 鍵開け Lv3以上が必要"], [1, "🔍 知覚/発見 Lv2以上が必要"], [2, "🧩 知恵 Lv4以上が必要"], [3, "💥 破壊 Lv3以上が必要"],
		[4, "⚔️ 戦闘(敵の戦闘力320)"], [5, "👑 特定の血筋(旧家の血筋)が必要"],
	]
	for e in expectations:
		var gate: Dictionary = _cases[e[0]][0]
		_check("ゲート説明: %s" % e[1], _main._gate_description(gate) == e[1], _main._gate_description(gate))
	_check("ゲート説明(アイテム)にアイコンとアイテム名", _main._gate_description(_cases[6][0]).begins_with("🎒 アイテム「") and _main._gate_description(_cases[6][0]).contains("砕けたフィラクテリーの欠片"))
	_check("ゲートが無ければ、アイコンなしの従来の文言", _main._gate_description({}) == "なし(自由に通行可能)" and _main._gate_short_text({}) == "" and _main._gate_icon({}) == "")
	_check("未知のゲートは❓", _main._gate_icon({"type": "mystery"}) == "❓")
	_completed = true
