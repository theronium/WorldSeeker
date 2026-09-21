# 使い捨ての確認用スクリプト(2026-09-22)。マップの表示が、見せたい場所へ切り替わること(main.gdの_focus_map)の確認。
# 報告: 「マップクリアで次のエリアに移動しても、マップが切り替わらない」。エリアの表示(_active_area_id)はタブを押した時にしか
# 変わらず、次のエリアへ移ったパーティや、そこで起きるイベントが、表示中の別のエリアの裏で起きて見えなかった。
# 要望: 「イベントの起きたエリアに切り替えるのが良い(状況を見たい)。初めてのエリアも、イベントと同じく移動する」。
#   a: パーティが自動で、まだ誰も来ていないエリアへ配置転換された → そのエリアへ切り替わる(見ているエリアによらず)
#   b: 既に雇用パーティが来たエリアへの移動・手動の割り当て・未割当・同じエリア内の移動では、切り替えない
#   c: イベントの会話が始まったら、起きた場所のエリアへ切り替わり、フロアが会話ウィンドウに隠れずに見える位置へスクロールする
#      (フロアのゲート結果のイベント・フロア発見/セクション到達の条件のイベント。日数・フラグだけの条件と案内会話は切り替えない)
#   d: 雇用パーティが誰も来ていないエリアで初めてフロアを発見したら切り替わる(野良の旅人の発見では切り替えない)
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
#       (タッチUIは、末尾に `-- --touch-ui` を付ける。--script モードの作法は tools/dev/README.md 参照。
#        実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree

var _frames := 0
var _main: Node
var _completed := false
var _fails := 0
var _day := 1
var _scroll_floor := "" # 段階2(レイアウトが済んだ後)で、見える位置にあるかを確かめるフロア

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		root.size = Vector2i(1280, 720) # ヘッドレスの既定の画面は極小で、マップの表示範囲(スクロールの計算)が実際と大きく違うため
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	if _frames == 5:
		_run()
		return false
	if _frames == 14: # スクロールの確定は遅延呼び出しなので、数フレーム後に確かめる
		_run_stage2()
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

func _icon_count() -> int:
	var count := 0
	for id in _main.node_icon_rows.keys():
		count += _main.node_icon_rows[id].get_child_count()
	return count

func _tick() -> void:
	_day += 1
	root.get_node("TimeSystem").day_advanced.emit(_day) # 探索(Exploration)→画面(main.gd)の順に、実際の日次と同じ流れで処理される
	_finish(root.get_node("EventDialogue"))

## Aのセクションを全て攻略済み(雇用パーティが発見したことになる)にして、最後のセクションに「先へ進む」のパーティを置く。
## 次の日次で、次のエリア(まだ誰も来ていない)へ移る。表示はAにしておく。
func _setup_cleared_first_area() -> Dictionary:
	var world_map = root.get_node("WorldMap"); var parties = root.get_node("Parties"); var save = root.get_node("SaveSystem")
	_finish(root.get_node("EventDialogue"))
	save.start_fresh_session()
	var area_a: String = world_map.areas.keys()[0]
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
		world_map.nodes[id]["found_by_employed"] = false
	var last_section := ""
	for section_id in world_map.sections_in_area(area_a):
		for id in world_map.nodes_in_section(section_id):
			world_map.mark_passed(id, true)
		last_section = section_id
	var party: Dictionary = parties.get_parties()[0]
	parties.assign_section(party["id"], last_section)
	party["post_clear_behavior"] = 1 # MOVE_ON
	_main._on_area_tab_pressed(area_a)
	_main._refresh_all()
	return {"party": party, "area_a": area_a, "last_section": last_section}

func _run() -> void:
	var world_map = root.get_node("WorldMap"); var parties = root.get_node("Parties")
	var events = root.get_node("ScenarioEvents"); var exploration = root.get_node("Exploration")
	var s := _setup_cleared_first_area()
	var party: Dictionary = s["party"]
	var area_a: String = s["area_a"]
	var area_ids: Array = world_map.areas.keys()
	var next_section: String = world_map.next_section_to_explore(s["last_section"])
	var area_b: String = world_map.sections[next_section]["area"] if next_section != "" else ""
	var area_c: String = ""
	for id in area_ids:
		if id != area_a and id != area_b:
			area_c = id
			break
	_check("前提: 最後のセクションを攻略済みにすると、次に探索するセクションが別のエリア(まだ誰も来ていない)にある", next_section != "" and area_b != "" and area_b != area_a, "次=%s エリア=%s" % [next_section, area_b])
	_check("前提: 表示中のエリアがAで、パーティのアイコンが見えている", _main._active_area_id == area_a and _icon_count() >= 1, "アイコン数=%d" % _icon_count())

	print("\n=== a: まだ誰も来ていないエリアへ、パーティが自動で配置転換された ===")
	_tick()
	_check("パーティが次のエリアのセクションへ配置転換された", world_map.sections[party["assigned_section"]]["area"] == area_b, party["assigned_section"])
	_check("マップの表示が、次のエリアに切り替わる", _main._active_area_id == area_b, "表示中=%s 期待=%s" % [_main._active_area_id, area_b])
	if _main.area_tab_buttons.has(area_b): # デスクトップ(タブ列)。タッチUIにはタブ列が無く、プルダウンだけ
		_check("(デスクトップ)エリアのタブが、次のエリアを選んだ状態になる", _main.area_tab_buttons[area_b].button_pressed and not _main.area_tab_buttons[area_a].button_pressed)
	if _main.area_option != null:
		_check("(タッチUI)エリアのプルダウンも、次のエリアを選んだ状態になる", _main.area_option.get_item_metadata(_main.area_option.selected) == area_b)
	_check("移った先のエリアの地図に、パーティのアイコンが見える", _icon_count() >= 1, "アイコン数=%d" % _icon_count())
	var s2 := _setup_cleared_first_area()
	party = s2["party"]
	_main._on_area_tab_pressed(area_c) # 関係の無い第3のエリアを見ている
	_tick()
	_check("別のエリアを見ていても、まだ誰も来ていないエリアへ移ったパーティを追いかける", _main._active_area_id == area_b, "表示中=%s" % _main._active_area_id)

	print("\n=== b: 切り替えない場合 ===")
	var s3 := _setup_cleared_first_area()
	party = s3["party"]
	world_map.mark_found(world_map.nodes_in_section(next_section)[0], true) # Bには、既に雇用パーティが来ている
	_main._refresh_map() # 「既に来たエリア」の記録を更新する
	_tick()
	_check("パーティは次のエリアへ移った", world_map.sections[party["assigned_section"]]["area"] == area_b)
	_check("既に雇用パーティが来たエリアへの移動(退避・復帰・ループなど)では、切り替えない", _main._active_area_id == area_a, "表示中=%s" % _main._active_area_id)
	var s4 := _setup_cleared_first_area()
	party = s4["party"]
	party["post_clear_behavior"] = 0 # STAY(自動では動かさない)
	var manual_section: String = world_map.sections_in_area(area_b)[0]
	_main._assign_party_to_section(party["id"], manual_section) # パーティ画面や、マップのセクション名からの割り当てと同じ処理
	# 探索(Exploration)は通さない: 通すと、移った先で初めてフロアを発見して「初エリア」の規則(d)で切り替わることがある(乱数)
	_day += 1
	_main._on_day_advanced(_day)
	_check("手動の割り当ては、翌日の更新でも追いかけない(表示はAのまま)", _main._active_area_id == area_a, "表示中=%s" % _main._active_area_id)
	var s5 := _setup_cleared_first_area()
	party = s5["party"]
	party["post_clear_behavior"] = 0
	parties.assign_section(party["id"], world_map.sections_in_area(area_a)[0])
	_main._refresh_map()
	parties.assign_section(party["id"], world_map.sections_in_area(area_a)[1]) # 同じエリア内の別のセクションへ
	_tick()
	_check("同じエリア内の移動では、切り替えない", _main._active_area_id == area_a)
	party["assigned_section"] = ""
	party["status"] = 0 # IDLE
	_tick()
	_check("未割当のパーティでは、切り替えない", _main._active_area_id == area_a)

	print("\n=== c: イベントの起きた場所へ ===")
	_setup_cleared_first_area()
	# 場所の引き方(ScenarioEvents.event_location)
	var gate_floor: String = ""
	var gate_event: Dictionary = {}
	for event in events.events:
		var trigger: Dictionary = event["trigger"]
		if trigger.get("type", "") == "gate" and world_map.nodes.has(String(trigger["floor"])) and world_map.sections[world_map.nodes[String(trigger["floor"])]["section"]]["area"] == area_c:
			gate_floor = String(trigger["floor"])
			gate_event = event
			break
	_check("前提: 第3のエリアにゲートのイベントがある", gate_floor != "", "エリア=%s" % area_c)
	var location: Dictionary = events.event_location(gate_event)
	_check("ゲートのイベントの場所 = そのフロア・セクション・エリア", location.get("floor") == gate_floor and location.get("section") == world_map.nodes[gate_floor]["section"] and location.get("area") == area_c, str(location))
	var found_event := {"trigger": {"type": "conditions"}, "conditions": [{"type": "day_min", "day": 1}, {"type": "floor_found", "floor": gate_floor}], "script": [{"side": "none", "name": "", "text": "t", "outcome": "done"}], "id": "t1", "title": "t", "kind": "", "effects": [], "repeat": false}
	_check("条件のイベントの場所 = 最初の場所の条件(日数の条件は飛ばす)のフロア", events.event_location(found_event).get("floor") == gate_floor)
	var section_event := {"trigger": {"type": "conditions"}, "conditions": [{"type": "section_entered", "section": world_map.nodes[gate_floor]["section"]}]}
	var section_location: Dictionary = events.event_location(section_event)
	_check("セクション到達の条件のイベントの場所 = そのセクションとエリア(フロアは無し)", section_location.get("section") == world_map.nodes[gate_floor]["section"] and section_location.get("area") == area_c and section_location.get("floor") == "", str(section_location))
	_check("日数・フラグだけの条件のイベントには場所が無い", events.event_location({"trigger": {"type": "conditions"}, "conditions": [{"type": "day_min", "day": 5}, {"type": "flag", "flag": "x"}]}).is_empty())
	_check("案内会話(system)には場所が無い", events.event_location(events.system_event("intro_part1")).is_empty())
	_check("存在しないフロアのイベントには場所が無い", events.event_location({"trigger": {"type": "gate", "floor": "no_such_floor"}}).is_empty())

	# 表示の切り替え: 第3のエリア以外を見ている時に、イベントが始まる
	_main._on_area_tab_pressed(area_a)
	events.play(gate_event)
	_check("ゲートのイベントが始まると、そのフロアのエリアへ切り替わる", _main._active_area_id == area_c, "表示中=%s" % _main._active_area_id)
	_check("会話が開いている", root.get_node("EventDialogue").is_active)
	_finish(root.get_node("EventDialogue"))
	_main._on_area_tab_pressed(area_a)
	events.play(found_event)
	_check("条件(フロア発見)のイベントも、そのフロアのエリアへ切り替わる", _main._active_area_id == area_c)
	_finish(root.get_node("EventDialogue"))
	_main._on_area_tab_pressed(area_a)
	events.play({"trigger": {"type": "conditions"}, "conditions": [{"type": "day_min", "day": 1}], "script": [{"side": "none", "name": "", "text": "t", "outcome": "done"}], "id": "t2", "title": "t", "kind": "", "effects": [], "repeat": false})
	_check("日数だけの条件のイベントでは、切り替えない", _main._active_area_id == area_a)
	_finish(root.get_node("EventDialogue"))
	events.play_system("intro_part1")
	_check("案内会話では、切り替えない", _main._active_area_id == area_a)
	_finish(root.get_node("EventDialogue"))

	print("\n=== d: 誰も来ていないエリアで、初めてフロアを発見した ===")
	var entry_floor: String = world_map.nodes_in_section(world_map.sections_in_area(area_c)[0])[0]
	var wild_floor: String = world_map.nodes_in_section(world_map.sections_in_area(area_ids[area_ids.size() - 1])[0])[0]
	_check("前提: どちらのエリアにも、誰も来ていない", not world_map.is_area_entered(area_c) and not world_map.is_area_entered(area_ids[area_ids.size() - 1]))
	_main._on_area_tab_pressed(area_a)
	exploration.wild_discover(wild_floor, _day) # 野良の旅人の発見
	_check("野良の旅人が初めて入っても、切り替えない", _main._active_area_id == area_a, "表示中=%s" % _main._active_area_id)
	var milestone: Dictionary = exploration._capture_milestone_state(entry_floor)
	world_map.mark_found(entry_floor, true)
	exploration._finalize_discovery("テスト隊", entry_floor, true, _day, milestone, party["member_ids"][0]) # 雇用パーティの発見
	_check("雇用パーティが初めて入ったら、そのエリアへ切り替わる", _main._active_area_id == area_c, "表示中=%s" % _main._active_area_id)
	_finish(root.get_node("EventDialogue"))

	print("\n=== c(続き): 見えない位置のフロアで起きたイベントは、見える位置へスクロールする ===")
	# Aの中で、最初の画面に入らない下の方のフロアのゲートのイベントを選ぶ
	_main._on_area_tab_pressed(area_a)
	var deepest_event: Dictionary = {}
	var deepest_y := -1.0
	for event in events.events:
		var trigger: Dictionary = event["trigger"]
		if trigger.get("type", "") != "gate" or not _main.node_boxes.has(String(trigger["floor"])):
			continue
		var y: float = _main.node_boxes[String(trigger["floor"])].position.y
		if y > deepest_y:
			deepest_y = y
			deepest_event = event
	_scroll_floor = String(deepest_event["trigger"]["floor"])
	_check("前提: 最初の画面(スクロール0)に入らない下のフロアがある", deepest_y > _main.map_scroll.size.y, "y=%.0f 画面の高さ=%.0f" % [deepest_y, _main.map_scroll.size.y])
	_main._on_area_tab_pressed(area_c) # 別のエリアを見ている状態から
	events.play(deepest_event)
	_check("下のフロアのイベントでも、そのエリアへ切り替わる", _main._active_area_id == area_a)
	_completed = true

## レイアウトと遅延したスクロールの確定が済んだ後: フロアが、会話ウィンドウに隠れない範囲に見えている。
func _run_stage2() -> void:
	_check("(段階2)会話は開いたまま", root.get_node("EventDialogue").is_active)
	var box: Control = _main.node_boxes[_scroll_floor]
	var scroll := Vector2(_main.map_scroll.scroll_horizontal, _main.map_scroll.scroll_vertical)
	var view := Vector2(_main.map_scroll.size.x, maxf(120.0, _main.map_scroll.size.y - _main._dialogue_reserved_height()))
	var rect := Rect2(box.position, _main._map_node_size())
	_check("スクロールされている", scroll.y > 0, "scroll=%s" % scroll)
	_check("フロアが、会話ウィンドウに隠れない範囲に、全体が見えている", Rect2(scroll, view).encloses(rect), "フロア=%s 見える範囲=%s" % [rect, Rect2(scroll, view)])
	_finish(root.get_node("EventDialogue"))
