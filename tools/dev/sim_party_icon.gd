# 使い捨ての確認用スクリプト(2026-09-21)。マップのパーティアイコンを、どのフロアに出すか(main.gdの_current_node_for_party)の確認。
# 報告: 「最終フロアをクリアした後で、次のセクションの一番最後に一瞬移動してしまう」。次のセクションへ配置転換された直後は、
# そのセクションのフロアが1つも発見・突破されていないので、どの優先順にも当たらず、「セクションの最後のフロア」に落ちていた。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree

var _frames := 0
var _main: Node
var _completed := false
var _fails := 0

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
		_run()
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

func _run() -> void:
	var save = root.get_node("SaveSystem"); var world_map = root.get_node("WorldMap"); var parties = root.get_node("Parties")
	var dialogue = root.get_node("EventDialogue"); var time_system = root.get_node("TimeSystem")
	_finish(dialogue)
	save.start_fresh_session()
	var party: Dictionary = parties.get_parties()[0]
	var first: String = world_map.first_section()
	var next: String = world_map.next_section_to_explore(first)
	var first_floors: Array = world_map.nodes_in_section(first)
	var next_floors: Array = world_map.nodes_in_section(next)
	print("最初=%s(%d) 次=%s(%d)" % [first, first_floors.size(), next, next_floors.size()])

	# 最初のセクションを完全攻略した状態にして、次のセクションへ配置転換された直後
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	for id in first_floors:
		world_map.mark_passed(id, true)
	parties.assign_section(party["id"], next)
	var frontier: Array = world_map.frontier_for_section(next)
	_check("前提: 次のセクションは、まだ何も発見・突破されておらず、入口(最前線)がある", frontier.size() > 0 and next_floors.all(func(id): return not world_map.is_found(id) and not world_map.is_passed(id)), str(frontier))
	var shown: String = _main._current_node_for_party(party)
	_check("配置転換の直後: セクションの最後のフロアではなく、入口(探している最前線のフロア)に出す", shown != next_floors.back() and shown == frontier[0], "表示=%s 最後=%s 入口=%s" % [shown, next_floors.back(), frontier[0]])

	# 入口が発見されて、まだ突破していない: そのフロアに出す(従来どおり。優先1)
	world_map.mark_found(frontier[0], true)
	_check("入口が発見済みで未突破なら、そのフロア(優先1。従来どおり)", _main._current_node_for_party(party) == frontier[0])
	# 入口を突破して、奥が未発見: 最前線の突破済みフロア(優先2。従来どおり)
	world_map.mark_passed(frontier[0], true)
	var after_entry: String = _main._current_node_for_party(party)
	var unfound_next_to_it: bool = world_map.neighbors(frontier[0]).any(func(n): return world_map.nodes.has(n) and not world_map.nodes[n]["found"])
	_check("入口を突破して奥が未発見なら、入口のフロア(優先2。従来どおり)", after_entry == frontier[0] or not unfound_next_to_it, after_entry)

	# セクション内の別の入口: 最前線が複数なら、セクションの並びで先のもの
	if frontier.size() > 1:
		_check("最前線が複数なら、並びで先のもの", shown == frontier[0])

	# 未到達で、最前線も無いセクション(どこからもつながっていない): 最後ではなく、先頭のフロア
	var far: String = ""
	for section_id in world_map.sections.keys():
		if section_id != first and section_id != next and world_map.frontier_for_section(section_id).is_empty() and not world_map.is_section_cleared(section_id):
			far = section_id
	if far != "":
		parties.assign_section(party["id"], far)
		var far_floors: Array = world_map.nodes_in_section(far)
		_check("どこからもつながっていないセクションでも、最後ではなく先頭のフロアに出す", _main._current_node_for_party(party) == far_floors[0], _main._current_node_for_party(party))

	# 周回中(完全攻略済み、lap_start_dayあり)は、経過日数に応じて動く(従来どおり)
	parties.assign_section(party["id"], first)
	party["lap_start_day"] = time_system.current_day
	_check("周回中は、最初のフロアから(従来どおり)", _main._current_node_for_party(party) == first_floors[0])
	_completed = true
