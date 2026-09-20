# 使い捨ての確認用スクリプト(2026-09-20)。完全踏破後の再配置(ループ/先へ進む)の確認。ループのまま踏破→動かない、先へ進むに切替→その場で移る、日次でも移る、未攻略では動かさない、未到達セクションは選ばない。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree

var WorldMap
var Parties
var Exploration

func _name_of(section_id) -> String:
	return WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else "(なし:%s)" % section_id

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true

func _run() -> void:
	WorldMap = root.get_node("WorldMap")
	Parties = root.get_node("Parties")
	Exploration = root.get_node("Exploration")
	root.get_node("SaveSystem").start_fresh_session()
	var STAY := 0
	var MOVE_ON := 1
	var party = Parties.get_parties()[0]
	var area_id = WorldMap.areas.keys()[0]
	var sections: Array = WorldMap.sections_in_area(area_id)
	var sec_a = sections[0]
	print("area=", area_id, " sec_a=", _name_of(sec_a))
	for s in sections:
		print("  ", _name_of(s), " cleared=", WorldMap.is_section_cleared(s), " reachable=", WorldMap.is_section_reachable(s))

	# sec_aを全て突破済みにし、ループ(STAY)で担当させ、初回踏破の判定を通す
	for id in WorldMap.nodes_in_section(sec_a):
		WorldMap.mark_passed(id, true)
	Parties.assign_section(party["id"], sec_a)
	Parties.set_post_clear_behavior(party["id"], STAY)
	Exploration._check_section_cleared(sec_a, 5)
	print("[1] STAYで初回踏破 -> 担当=", _name_of(party["assigned_section"]), " (期待: sec_aのまま)")
	Exploration._on_day_advanced(6)
	print("[2] STAYで翌日 -> 担当=", _name_of(party["assigned_section"]), " (期待: sec_aのまま)")

	# 「先へ進む」に切り替えた瞬間(main.gdのボタン処理と同じ呼び出し)
	Parties.set_post_clear_behavior(party["id"], MOVE_ON)
	var moved = Exploration.apply_post_clear_behavior(party, 6)
	print("[3] STAY->MOVE_ONに切替 -> moved=", moved, " 担当=", _name_of(party["assigned_section"]), " (期待: true、次のセクション)")
	var first_next = party["assigned_section"]

	# 日次処理でも移ること(切替の即時適用を通らなかった場合の保険)
	Parties.assign_section(party["id"], sec_a)
	Parties.set_post_clear_behavior(party["id"], MOVE_ON)
	Exploration._on_day_advanced(7)
	print("[4] MOVE_ONで攻略済みセクションに居る状態で翌日 -> 担当=", _name_of(party["assigned_section"]), " (期待: ", _name_of(first_next), ")")

	# 未攻略のセクションにいる間は動かさない
	var before = party["assigned_section"]
	var moved2 = Exploration.apply_post_clear_behavior(party, 8)
	print("[5] 未攻略のセクションでは動かさない -> moved=", moved2, " 担当=", _name_of(party["assigned_section"]), " (期待: false、", _name_of(before), "のまま)")

	# 繋がっていないセクションは選ばれない
	var unreachable_pick := false
	for s in sections:
		if not WorldMap.is_section_reachable(s) and WorldMap.next_section_to_explore(sec_a) == s:
			unreachable_pick = true
	print("[6] next_section_to_exploreが未到達セクションを返す=", unreachable_pick, " (期待: false)")
