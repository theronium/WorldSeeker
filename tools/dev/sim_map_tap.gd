# 使い捨ての確認用スクリプト(2026-09-24)。報告「フロアをダブルタップでないと開けないのは気付けない」への対応の確認。
# マップ(main.gdの_on_map_canvas_gui_input)で、フロアの箱を1回タップ(押して、ほぼ動かさずに離す)すると
# フロア詳細が開くこと、ドラッグ(パン)では開かないこと、鍵アイコンも1回で開くこと、ダブルタップでセクション枠の
# 何も無い所を叩くと、そのセクションの掲示板スレッドが開くこと。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス> [-- --touch-ui]
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

func _button(pos: Vector2, pressed: bool, double := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = double
	event.position = pos
	event.global_position = pos # テストでは、画面上の位置もキャンバス上の位置と同じにする(差だけを見るため)
	_main._on_map_canvas_gui_input(event)

func _motion(pos: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	event.relative = relative
	_main._on_map_canvas_gui_input(event)

func _run() -> void:
	var dialogue = root.get_node("EventDialogue"); var save = root.get_node("SaveSystem")
	while dialogue.is_active:
		dialogue.advance()
	save.start_fresh_session()
	while dialogue.is_active:
		dialogue.advance()
	_main._refresh_all()
	var slop: float = _main._map_tap_slop()
	print("タッチUI: %s / タップとみなす移動量: %.0fpx" % [str(_main._touch_ui), slop])

	var node_id: String = _main.node_boxes.keys()[0]
	var center: Vector2 = _main.node_boxes[node_id].get_rect().get_center()

	_button(center, true)
	_button(center, false)
	_check("フロアの箱を1回タップすると、フロア詳細が開く", _main.node_detail_panel.visible, node_id)
	_main._close_any_modal()

	_button(center, true)
	_motion(center + Vector2(slop * 0.5, 0), Vector2(slop * 0.5, 0))
	_button(center + Vector2(slop * 0.5, 0), false)
	_check("少し(許容範囲内)ずれて離しても、タップとして開く", _main.node_detail_panel.visible)
	_main._close_any_modal()

	_button(center, true)
	_motion(center + Vector2(slop * 3, 0), Vector2(slop * 3, 0))
	_motion(center, Vector2(-slop * 3, 0))
	_button(center, false)
	_check("ドラッグ(パン)した後は、元の位置で離しても開かない", not _main.node_detail_panel.visible)

	# 鍵アイコン(未到達セクション)
	var lock_section := ""
	for section_id in _main.section_lock_icons.keys():
		if _main.section_lock_icons[section_id].visible:
			lock_section = section_id
			break
	if lock_section == "":
		print("(表示中のエリアに未到達のセクションが無いので、鍵アイコンの確認は省略)")
	else:
		var lock: Control = _main.section_lock_icons[lock_section]
		_check("鍵アイコンの文言は「%s」" % ("タップで詳細" if _main._touch_ui else "クリックで詳細"), lock.text.contains("タップで詳細" if _main._touch_ui else "クリックで詳細"), lock.text)
		var lock_center: Vector2 = lock.get_rect().get_center()
		_button(lock_center, true)
		_button(lock_center, false)
		_check("鍵アイコンを1回タップすると、説明(フロア詳細と同じパネル)が開く", _main.node_detail_panel.visible and _main.node_detail_title.text.contains("未到達"), _main.node_detail_title.text)
		_main._close_any_modal()

	# セクション枠の、フロアの箱の無い所: 1回では何も開かず、ダブルタップで掲示板スレッド
	var section_id: String = _main.node_boxes.keys().map(func(id): return root.get_node("WorldMap").nodes[id]["section"])[0]
	var bounds: Rect2 = _main.section_bounds_cache[section_id]
	var empty_pos := Vector2(bounds.position.x + 4, bounds.position.y + 4)
	var on_box := false
	for id in _main.node_boxes.keys():
		if _main.node_boxes[id].get_rect().has_point(empty_pos):
			on_box = true
	_check("前提: セクション枠の左上の隅は、フロアの箱の外", not on_box and bounds.has_point(empty_pos))
	_button(empty_pos, true)
	_button(empty_pos, false)
	_check("セクション枠の何も無い所を1回タップしても、何も開かない", not _main.modal_blocker.visible and not _main.log_window.visible)
	_button(empty_pos, true, true)
	_button(empty_pos, false)
	_check("ダブルタップで、そのセクションの掲示板スレッドが開く", _main.log_window.visible and _main.log_window._source == "board" and _main.log_window._filters["board"] == section_id)
	_check("ダブルタップの2回目の離しでは、タップとして扱わない(何も開かない)", not _main.modal_blocker.visible)
	_main._set_log_window_visible(false)

	# フロアの箱をダブルタップ: 1回目で詳細が開き、2回目は何もしない(二重に開いたり、スレッドを開いたりしない)
	_button(center, true)
	_button(center, false)
	_button(center, true, true)
	_button(center, false)
	_check("フロアの箱のダブルタップ: 詳細が開いたまま、ログは開かない", _main.node_detail_panel.visible and not _main.log_window.visible)
	_main._close_any_modal()
	_completed = true
