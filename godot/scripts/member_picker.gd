class_name MemberPicker
extends VBoxContainer
# 探索者の複数選択(チェックボックス式。2026-09-21)。パーティの編成と、既存パーティへの追加で使う。
# 以前の編成は、ItemListの複数選択(SELECT_MULTI)だった。ItemListの複数選択は、CtrlやShiftを押しながらのクリックが要るので、
# タッチ(Android)では、1タップが選択を置き換えてしまい、1人しか選べなかった。チェックボックスは、タップで付け外しできる。
# limit(選べる最大人数)に達すると、まだ選んでいない行は押せなくなる(選び過ぎを、押した後のエラーではなく、その場で防ぐ)。

signal selection_changed

const DEFAULT_ROW_HEIGHT := 30.0
const SCROLL_MIN_HEIGHT := 120.0 # fit_contentでない時の、一覧の最低の高さ

## 選べる最大人数。0なら、全ての行が押せない(パーティが満員の時など)。
var limit: int = 4:
	set(value):
		limit = maxi(0, value)
		_apply_limit()
## 1行の高さ。タッチUIでは指で押せる高さにする(main.gdが設定する)。
var row_height: float = DEFAULT_ROW_HEIGHT
## trueなら、一覧の高さを中身に合わせ、この部品の中ではスクロールしない。外側のスクロール(パーティ詳細のページ)に任せる
## (スクロールの中にスクロールがあると、タッチで、どちらが動くか分からなくなる)。
var fit_content: bool = false:
	set(value):
		fit_content = value
		if _scroll != null:
			_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if fit_content else ScrollContainer.SCROLL_MODE_AUTO
			_scroll.custom_minimum_size = Vector2(0, 0 if fit_content else SCROLL_MIN_HEIGHT)

var _count_label: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _boxes: Array = [] # CheckBox。メタデータに探索者のID
var _signature: Array = [] # 今の行の中身([ID, 文字]の並び)。変わっていなければ、作り直さない

func _init() -> void:
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.modulate = Color(1, 1, 1, 0.8)
	add_child(_count_label)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, SCROLL_MIN_HEIGHT)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)

## 選べる探索者の一覧を作り直す。前に選んでいた探索者が、まだ一覧にいれば、選択を引き継ぐ。
## 中身(探索者と、行の文字)が前と同じなら、何もしない。パーティ画面は日が進むたびに更新されるので、毎回行を作り直すと、
## 押している最中に行が消えて、タップが取りこぼされる(倍速では毎秒何十回も起きる)。
func set_choices(npcs: Array, empty_text: String = "選べる探索者がいません") -> void:
	var signature: Array = []
	for npc in npcs:
		signature.append([int(npc["id"]), _row_text(npc)])
	signature.append(empty_text if npcs.is_empty() else "")
	if signature == _signature:
		_apply_limit()
		return
	_signature = signature
	var kept: Array = selected_ids()
	for child in _rows.get_children():
		_rows.remove_child(child) # queue_free()だけだと、同じフレーム内の作り直しで古い行が残る
		child.queue_free()
	_boxes.clear()
	for npc in npcs:
		var id: int = int(npc["id"])
		var box := CheckBox.new()
		box.text = _row_text(npc)
		box.set_meta("npc_id", id)
		box.custom_minimum_size = Vector2(0, row_height)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.clip_text = true
		box.toggled.connect(func(_pressed): _on_toggled())
		box.set_pressed_no_signal(id in kept)
		_rows.add_child(box)
		_boxes.append(box)
	if npcs.is_empty():
		var empty := Label.new()
		empty.text = empty_text
		empty.modulate = Color(1, 1, 1, 0.6)
		_rows.add_child(empty)
	_apply_limit()

func _row_text(npc: Dictionary) -> String:
	return "%s(%s)  戦力 %d" % [npc["name"], Jobs.JOB_NAMES[npc["job"]], Npcs.power(int(npc["id"]))]

## 選んでいる探索者のID(一覧の並び順)。
func selected_ids() -> Array:
	var ids: Array = []
	for box in _boxes:
		if box.button_pressed:
			ids.append(int(box.get_meta("npc_id")))
	return ids

func clear_selection() -> void:
	for box in _boxes:
		box.set_pressed_no_signal(false)
	_apply_limit()
	selection_changed.emit()

func _on_toggled() -> void:
	_apply_limit()
	selection_changed.emit()

## 選んだ人数の表示と、上限に達した時に、まだ選んでいない行を押せなくする。
func _apply_limit() -> void:
	if _count_label == null:
		return # プロパティの初期化(limitのsetter)が、_init()より先に走る場合の保険
	var count := selected_ids().size()
	if limit <= 0:
		_count_label.text = "空きがありません"
	else:
		_count_label.text = "選択 %d/%d人" % [count, limit]
	for box in _boxes:
		box.disabled = not box.button_pressed and count >= limit
