class_name LogWindow
extends PanelContainer
# ログウィンドウ(2026-09-24)。毎日の動き・行動ログ・掲示板の3種を、上のタブで切り替えて1つずつ見る。
# マップの右端に重ねて出し(main.gdの_build_log_window)、マップ右上のフロートボタンで出し入れする。
# 以前は画面中央のモーダルで2種を左右に並べる方式で、タッチUIには別に右端の「掲示板」ウィンドウ
# (全体フィードの直近10件)があり、同じ掲示板を見る入口が2つ重複していたため、1つに統合した。
#   毎日の動き: その日、担当中のパーティが何をしていたか(DailyLog。メモリだけ。日ごと/まとめて表示の切替、パーティで絞る)
#   行動ログ  : 節目の出来事(ActionLog、DB。探索者で絞る)。報告書調の文体。戦闘ゲートに関する行には
#               ⚔️を付け、イベント戦闘との関連が見て分かるようにする(_is_combat_action_entry参照)。
#               (2026-09-23に「イベント」から「行動記録」へ改名し、2026-09-24に「行動ログ」へ戻した)
#   掲示板    : 人々の噂話(Board。口語調の文体)。全体フィード/セクション別スレッド。自パーティ/世界全体で
#               色・アイコンを分ける(Board.Scope、_add_board_line参照)
# 3種とも、新しい順に並べる。開いている間、日が進むと中身が更新される(読み返している最中は、先頭へ戻さない)。

signal close_requested

const SOURCE_DAILY := "daily"
const SOURCE_EVENTS := "events"
const SOURCE_BOARD := "board"
const SOURCES := [
	{"key": SOURCE_DAILY, "label": "毎日の動き"},
	{"key": SOURCE_EVENTS, "label": "行動ログ"},
	{"key": SOURCE_BOARD, "label": "掲示板"},
]

const REFRESH_INTERVAL := 0.5 # 開いている間の、自動更新の間隔(秒)。日が進んでいる時だけ更新する
const EVENT_LIMIT := 300
const BOARD_LIMIT := 200
const AT_TOP_TOLERANCE := 4.0 # スクロールが先頭とみなす範囲(自動更新は、先頭にいる時だけ)

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

var _source := SOURCE_BOARD
var _tab_buttons := {} # 種類 -> Button(ButtonGroupで排他)
var _filter: OptionButton
var _merge: CheckBox
var _hint: Label
var _text: RichTextLabel
var _filters := {SOURCE_DAILY: -1, SOURCE_EVENTS: -1, SOURCE_BOARD: ""} # 種類 -> 絞り込みの値(その種類で最後に選んだもの)
var _filter_key := "" # 絞り込みの選択肢を作った種類
var _dirty := false

func _ready() -> void:
	visible = false

	var col := VBoxContainer.new()
	add_child(col)

	var tabs := HBoxContainer.new()
	col.add_child(tabs)
	var group := ButtonGroup.new()
	for entry in SOURCES:
		var tab := Button.new()
		tab.text = entry["label"]
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_select_source.bind(String(entry["key"])))
		tabs.add_child(tab)
		_tab_buttons[entry["key"]] = tab
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.tooltip_text = "閉じる"
	close_button.pressed.connect(func(): close_requested.emit())
	tabs.add_child(close_button)
	_tab_buttons[_source].set_pressed_no_signal(true)

	var head := HBoxContainer.new()
	col.add_child(head)
	_filter = OptionButton.new()
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.clip_text = true
	_filter.item_selected.connect(_on_filter_selected)
	head.add_child(_filter)
	_merge = CheckBox.new()
	_merge.text = "まとめて表示"
	_merge.toggled.connect(func(_pressed): refresh())
	head.add_child(_merge)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.modulate = Color(1, 1, 1, 0.6)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hint)

	_text = RichTextLabel.new()
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.scroll_active = true
	_text.add_theme_font_size_override("normal_font_size", 13)
	col.add_child(_text)

	# 開いている間の自動更新。日が進んだ/会話が終わって結果が反映された時に「更新が要る」印を立て、一定間隔でまとめて更新する
	# (倍速で1秒に何十日も進んでも、描画し直しは毎秒2回まで)。
	TimeSystem.day_advanced.connect(func(_day): _dirty = true)
	EventDialogue.finished.connect(func(_outcome): _dirty = true)
	var timer := Timer.new()
	timer.wait_time = REFRESH_INTERVAL
	timer.timeout.connect(_on_refresh_timer)
	add_child(timer)
	timer.start()

## 今の内容で描き直す(開いた時と、設定を変えた時)。
func refresh() -> void:
	_refresh(true)

## 掲示板の、指定のスレッド(セクション。""なら全体フィード)を出す。
func show_board_thread(thread_id: String) -> void:
	_filters[SOURCE_BOARD] = thread_id
	_tab_buttons[SOURCE_BOARD].set_pressed_no_signal(true)
	_source = SOURCE_BOARD
	refresh()

func _select_source(key: String) -> void:
	_source = key
	refresh()

func _on_refresh_timer() -> void:
	if not visible or not _dirty:
		return
	_dirty = false
	_refresh(false)

func _on_filter_selected(item: int) -> void:
	_filters[_source] = _filter.get_item_metadata(item)
	refresh()

## 描き直す。forceでなければ、読み返している最中(スクロールが先頭でない)なら、そのままにする。
func _refresh(force: bool) -> void:
	if not force and _text.get_v_scroll_bar().value > AT_TOP_TOLERANCE:
		return
	_sync_filter(_source)
	_merge.visible = _source == SOURCE_DAILY
	_hint.text = HINTS[_source]
	_hint.visible = HINTS[_source] != ""
	_text.clear()
	var any := false
	match _source:
		SOURCE_DAILY:
			any = _fill_daily(_text)
		SOURCE_EVENTS:
			any = _fill_events(_text)
		SOURCE_BOARD:
			any = _fill_board(_text)
	if not any:
		_text.add_text(EMPTY_TEXTS[_source])

## 絞り込みの選択肢: 毎日の動き=パーティ、行動ログ=探索者、掲示板=スレッド(全体/セクション)。[{"value", "label"}]
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
			# まだ書き込みの無いセクションのスレッドを開いた(マップのダブルタップなど)場合も、そのセクションを選べるようにする
			# (選択肢に無いと「全体」に戻ってしまい、開いたセクションと違うものが出る)
			var wanted: String = String(_filters[SOURCE_BOARD])
			if wanted != "" and not Board.threads.has(wanted) and WorldMap.sections.has(wanted):
				choices.append({"value": wanted, "label": String(WorldMap.sections[wanted]["name"])})
	return choices

## 絞り込みの部品を、種類に合わせる。選択肢は、顔ぶれが変わった時だけ作り直す(選んだ直後の呼び出しの最中に消さないため)。
func _sync_filter(key: String) -> void:
	var choices := _filter_choices(key)
	var wanted: Array = choices.map(func(choice): return choice["value"])
	var current: Array = []
	for i in _filter.item_count:
		current.append(_filter.get_item_metadata(i))
	if _filter_key != key or current != wanted:
		_filter.clear()
		for choice in choices:
			_filter.add_item(choice["label"])
			_filter.set_item_metadata(_filter.item_count - 1, choice["value"])
		_filter_key = key
	var selected := wanted.find(_filters[key])
	if selected < 0:
		selected = 0 # 選んでいたパーティ・探索者・スレッドが無くなった(新規開始など)
		_filters[key] = wanted[0]
	_filter.select(selected)

## 毎日の動き。日ごと(日の見出しの下に、パーティごとに1行)か、まとめて(同じ状態が続く間を1行)。新しい順。
func _fill_daily(text: RichTextLabel) -> bool:
	var party_id: int = int(_filters[SOURCE_DAILY])
	var any := false
	if _merge.button_pressed:
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

## 行動ログ。DBの行動ログを、新しい順に。戦闘ゲートに関する行には⚔️を付ける。
func _fill_events(text: RichTextLabel) -> bool:
	var entries: Array = SaveSystem.query_action_log(int(_filters[SOURCE_EVENTS]), EVENT_LIMIT)
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
func _fill_board(text: RichTextLabel) -> bool:
	var thread_id: String = String(_filters[SOURCE_BOARD])
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
