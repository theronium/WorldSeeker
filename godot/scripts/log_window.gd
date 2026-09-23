class_name LogWindow
extends PanelContainer
# ログウィンドウ(2026-09-21)。掲示板・行動記録・毎日の動きの3種から、2つを選んで左右に並べる。
# 以前の「掲示板」と「行動ログ」の2つのウィンドウを統合したもの(発生源がほぼ同じで、似ていた)。
#   毎日の動き: その日、担当中のパーティが何をしていたか(DailyLog。メモリだけ。日ごと/まとめて表示の切替、パーティで絞る)
#   行動記録  : 節目の出来事(旧・行動ログ。ActionLog、DB。探索者で絞る)。タブ名は元「イベント」だったが、
#               フロアのゲート結果として再生される「イベント戦闘」(シナリオのVN+戦闘画面)と紛らわしい
#               (中身が別物なのに名前だけ似ている)ため改名した(2026-09-23)。戦闘ゲートに関する行には
#               ⚔️を付け、イベント戦闘との関連が見て分かるようにする(_is_combat_action_entry参照)。
#   掲示板    : 掲示板の全体フィード/セクション別スレッド(Board)。自パーティ/世界全体で色・アイコンを分ける
#               (Board.Scope、_scope_prefix参照。2026-09-23)
# 3種とも、新しい順に並べる。開いている間、日が進むと中身が更新される(読み返している最中は、先頭へ戻さない)。

signal close_requested

const SOURCE_DAILY := "daily"
const SOURCE_EVENTS := "events"
const SOURCE_BOARD := "board"
const SOURCES := [
	{"key": SOURCE_DAILY, "label": "毎日の動き"},
	{"key": SOURCE_EVENTS, "label": "行動記録"},
	{"key": SOURCE_BOARD, "label": "掲示板"},
]
const DEFAULT_SOURCES := [SOURCE_DAILY, SOURCE_EVENTS] # 左・右の枠の初期の中身

const REFRESH_INTERVAL := 0.5 # 開いている間の、自動更新の間隔(秒)。日が進んでいる時だけ更新する
const EVENT_LIMIT := 300
const BOARD_LIMIT := 200
const AT_TOP_TOLERANCE := 4.0 # スクロールが先頭とみなす範囲(自動更新は、先頭にいる枠だけ)

const HINTS := {
	SOURCE_DAILY: "直近90日分。ゲームを閉じると消えます(セーブには入りません)",
	SOURCE_EVENTS: "",
	SOURCE_BOARD: "",
}
const EMPTY_TEXTS := {
	SOURCE_DAILY: "(まだ動きの記録がありません。パーティに担当セクションを割り当てて日が進むと、ここに出ます)",
	SOURCE_EVENTS: "(まだ記録がありません)",
	SOURCE_BOARD: "(まだ書き込みがありません)",
}
const DAY_COLOR := Color(0.95, 0.82, 0.45)

# 2枠。各枠: {"source": OptionButton, "filter": OptionButton, "merge": CheckBox, "hint": Label, "text": RichTextLabel,
#            "filters": {種類 -> 絞り込みの値(その種類で最後に選んだもの)}, "filter_key": 絞り込みの選択肢を作った種類}
var _panes: Array = []
var _dirty := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -500
	offset_top = -300
	offset_right = 500
	offset_bottom = 300
	visible = false

	var col := VBoxContainer.new()
	add_child(col)
	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "ログ"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): close_requested.emit())
	header.add_child(close_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	col.add_child(body)
	for index in DEFAULT_SOURCES.size():
		if index > 0:
			body.add_child(VSeparator.new())
		body.add_child(_build_pane(index))

	# 開いている間の自動更新。日が進んだ/会話が終わって結果が反映された時に「更新が要る」印を立て、一定間隔でまとめて更新する
	# (倍速で1秒に何十日も進んでも、描画し直しは毎秒2回まで)。
	TimeSystem.day_advanced.connect(func(_day): _dirty = true)
	EventDialogue.finished.connect(func(_outcome): _dirty = true)
	var timer := Timer.new()
	timer.wait_time = REFRESH_INTERVAL
	timer.timeout.connect(_on_refresh_timer)
	add_child(timer)
	timer.start()

func _build_pane(index: int) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	box.add_child(head)

	var source := OptionButton.new()
	for entry in SOURCES:
		source.add_item(entry["label"])
		source.set_item_metadata(source.item_count - 1, entry["key"])
	source.select(_source_index(DEFAULT_SOURCES[index]))
	source.item_selected.connect(func(_i): _refresh_pane(index, true))
	head.add_child(source)

	var filter := OptionButton.new()
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter.item_selected.connect(func(item): _on_filter_selected(index, item))
	head.add_child(filter)

	var merge := CheckBox.new()
	merge.text = "まとめて表示"
	merge.toggled.connect(func(_pressed): _refresh_pane(index, true))
	head.add_child(merge)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)

	var text := RichTextLabel.new()
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(0, 300)
	text.scroll_active = true
	box.add_child(text)

	_panes.append({
		"source": source, "filter": filter, "merge": merge, "hint": hint, "text": text,
		"filters": {SOURCE_DAILY: -1, SOURCE_EVENTS: -1, SOURCE_BOARD: ""}, "filter_key": "",
	})
	return box

func _source_index(key: String) -> int:
	for i in SOURCES.size():
		if SOURCES[i]["key"] == key:
			return i
	return 0

func _source_key(pane: Dictionary) -> String:
	var source: OptionButton = pane["source"]
	return String(source.get_item_metadata(source.selected))

## 全ての枠を、今の内容で描き直す(開いた時と、設定を変えた時)。
func refresh() -> void:
	for index in _panes.size():
		_refresh_pane(index, true)

## 掲示板の、指定のスレッド(セクション)を出す。掲示板の枠が既にあればそれを、無ければ右の枠を掲示板にする。
func show_board_thread(thread_id: String) -> void:
	var target := 1
	for index in _panes.size():
		if _source_key(_panes[index]) == SOURCE_BOARD:
			target = index
			break
	var pane: Dictionary = _panes[target]
	var source: OptionButton = pane["source"]
	source.select(_source_index(SOURCE_BOARD))
	pane["filters"][SOURCE_BOARD] = thread_id
	refresh()

func _on_refresh_timer() -> void:
	if not visible or not _dirty:
		return
	_dirty = false
	for index in _panes.size():
		_refresh_pane(index, false)

func _on_filter_selected(index: int, item: int) -> void:
	var pane: Dictionary = _panes[index]
	var filter: OptionButton = pane["filter"]
	pane["filters"][_source_key(pane)] = filter.get_item_metadata(item)
	_refresh_pane(index, true)

## 1つの枠を描き直す。forceでなければ、読み返している最中(スクロールが先頭でない)の枠は、そのままにする。
func _refresh_pane(index: int, force: bool) -> void:
	var pane: Dictionary = _panes[index]
	var text: RichTextLabel = pane["text"]
	if not force and text.get_v_scroll_bar().value > AT_TOP_TOLERANCE:
		return
	var key := _source_key(pane)
	_sync_filter(pane, key)
	pane["merge"].visible = key == SOURCE_DAILY
	pane["hint"].text = HINTS[key]
	pane["hint"].visible = HINTS[key] != ""
	text.clear()
	var any := false
	match key:
		SOURCE_DAILY:
			any = _fill_daily(pane, text)
		SOURCE_EVENTS:
			any = _fill_events(pane, text)
		SOURCE_BOARD:
			any = _fill_board(pane, text)
	if not any:
		text.add_text(EMPTY_TEXTS[key])

## 絞り込みの選択肢: 毎日の動き=パーティ、行動記録=探索者、掲示板=スレッド(全体/セクション)。[{"value", "label"}]
func _filter_choices(key: String) -> Array:
	var choices: Array = []
	match key:
		SOURCE_DAILY:
			choices.append({"value": -1, "label": "全パーティ"})
			for party in Parties.get_parties():
				choices.append({"value": int(party["id"]), "label": String(party["name"])})
		SOURCE_EVENTS:
			choices.append({"value": -1, "label": "全員"})
			for npc in Npcs.get_roster():
				choices.append({"value": int(npc["id"]), "label": String(npc["name"])})
		SOURCE_BOARD:
			choices.append({"value": "", "label": "全体"})
			for thread in Board.threads.values():
				choices.append({"value": String(thread["id"]), "label": String(thread["title"])})
	return choices

## 絞り込みの部品を、種類に合わせる。選択肢は、顔ぶれが変わった時だけ作り直す(選んだ直後の呼び出しの最中に消さないため)。
func _sync_filter(pane: Dictionary, key: String) -> void:
	var filter: OptionButton = pane["filter"]
	var choices := _filter_choices(key)
	var wanted: Array = choices.map(func(choice): return choice["value"])
	var current: Array = []
	for i in filter.item_count:
		current.append(filter.get_item_metadata(i))
	if pane["filter_key"] != key or current != wanted:
		filter.clear()
		for choice in choices:
			filter.add_item(choice["label"])
			filter.set_item_metadata(filter.item_count - 1, choice["value"])
		pane["filter_key"] = key
	var selected := wanted.find(pane["filters"][key])
	if selected < 0:
		selected = 0 # 選んでいたパーティ・探索者・スレッドが無くなった(新規開始など)
		pane["filters"][key] = wanted[0]
	filter.select(selected)

## 毎日の動き。日ごと(日の見出しの下に、パーティごとに1行)か、まとめて(同じ状態が続く間を1行)。新しい順。
func _fill_daily(pane: Dictionary, text: RichTextLabel) -> bool:
	var party_id: int = int(pane["filters"][SOURCE_DAILY])
	var any := false
	if pane["merge"].button_pressed:
		for span in DailyLog.spans_newest_first(party_id):
			any = true
			var from_day: int = int(span["from_day"])
			var to_day: int = int(span["to_day"])
			_add_day_heading(text, "Day %d" % from_day if from_day == to_day else "Day %d〜%d" % [from_day, to_day])
			text.add_text("  %s: %s\n" % [span["party_name"], DailyLog.describe_span(span)])
	else:
		for day_entry in DailyLog.days_newest_first(party_id):
			any = true
			_add_day_heading(text, "Day %d" % day_entry["day"])
			text.add_text("\n")
			for entry in day_entry["parties"]:
				text.add_text("  %s: %s\n" % [entry["party_name"], DailyLog.describe(entry, int(day_entry["day"]))])
	return any

const COMBAT_ACTION_EVENT_TYPES := ["discover_pass", "discover_blocked", "gate_pass"]

## 行動記録(旧・行動ログ)。DBの行動ログを、新しい順に。戦闘ゲートに関する行には⚔️を付ける。
func _fill_events(pane: Dictionary, text: RichTextLabel) -> bool:
	var entries: Array = SaveSystem.query_action_log(int(pane["filters"][SOURCE_EVENTS]), EVENT_LIMIT)
	for entry in entries:
		_add_day_heading(text, "[Day %d]" % entry["day"])
		var prefix: String = "⚔️ " if _is_combat_action_entry(entry) else ""
		text.add_text(" %s%s\n" % [prefix, entry["text"]])
	return not entries.is_empty()

## その行動記録の行が、戦闘ゲート(イベント戦闘)に関するものか。combat_retreatは常にそう、
## 発見/突破系はそのフロアの実際のゲート種別で判定する(2026-09-23、タブ名の改名(「イベント」→
## 「行動記録」)とあわせて、イベント戦闘との関連が見て分かるようにする対応)。
func _is_combat_action_entry(entry: Dictionary) -> bool:
	var event_type: String = String(entry.get("event_type", ""))
	if event_type == "combat_retreat":
		return true
	if not COMBAT_ACTION_EVENT_TYPES.has(event_type):
		return false
	var node_id: String = String(entry.get("node_id", ""))
	return WorldMap.nodes.has(node_id) and String(WorldMap.nodes[node_id].get("gate", {}).get("type", "")) == "combat"

## 掲示板。全体フィードか、選んだセクションのスレッドを、新しい順に。自パーティ/世界全体を、
## 行頭のアイコンと文字色で見分けられるようにする(Board.Scope、2026-09-23)。
func _fill_board(pane: Dictionary, text: RichTextLabel) -> bool:
	var thread_id: String = String(pane["filters"][SOURCE_BOARD])
	var entries: Array = Board.thread_recent(thread_id, BOARD_LIMIT) if thread_id != "" else Board.recent(BOARD_LIMIT)
	for i in range(entries.size() - 1, -1, -1):
		_add_day_heading(text, "[Day %d]" % entries[i]["day"])
		_add_board_line(text, entries[i])
	return not entries.is_empty()

func _add_board_line(text: RichTextLabel, entry: Dictionary) -> void:
	var scope: int = int(entry.get("scope", Board.Scope.PARTY))
	text.add_text(" %s " % String(Board.SCOPE_ICON.get(scope, "")))
	text.push_color(Board.SCOPE_COLOR.get(scope, Color.WHITE))
	text.add_text(entry["text"])
	text.pop()
	text.add_text("\n")

func _add_day_heading(text: RichTextLabel, heading: String) -> void:
	text.push_color(DAY_COLOR)
	text.add_text(heading)
	text.pop()
