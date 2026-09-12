extends Control

var candidates_list: ItemList
var roster_list: ItemList
var section_option: OptionButton
var skill_option: OptionButton
var train_cost_label: Label
var facility_button: Button
var node_labels: Dictionary = {} # node_id -> Label(状態表示)
var node_centers: Dictionary = {} # node_id -> Vector2(map_canvas内での中心座標。接続線描画用)
var funds_label: Label
var time_label: Label
var speed_button: Button
var board_log: RichTextLabel
var board_title_label: Label
var viewing_thread_id: String = "" # 空なら全体フィード
var next_month_button: Button
var map_scroll: ScrollContainer
var map_canvas: Control
var _map_panning: bool = false

var dialogue_panel: PanelContainer
var left_slot: VBoxContainer
var right_slot: VBoxContainer
var speaker_name_label: Label
var dialogue_text_label: Label
var choices_box: VBoxContainer
var advance_hint: Button

var action_log_panel: PanelContainer
var action_log_npc_option: OptionButton
var action_log_text: RichTextLabel

var slot_panel: PanelContainer
var slot_list: ItemList
var new_game_confirm: ConfirmationDialog
var delete_slot_confirm: ConfirmationDialog
var _pending_delete_slot_id: int = -1

var hire_panel: PanelContainer
var npc_panel: PanelContainer
var modal_blocker: ColorRect

func _ready() -> void:
	_build_ui()
	_build_dialogue_ui()
	_build_action_log_ui()
	_build_slot_ui()
	_build_hire_ui()
	_build_npc_ui()
	# アクティブなセーブスロットが、今のworld_data.gdより古いワールドスキーマで生成された
	# ものであれば、そのバージョンでWorldMapを作り直してからUIを組み立てる(スキーマの
	# 複数バージョン管理。design.md 8.2/11章)。ノードグラフのUI(_seed_demo_world)は
	# 実際にWorldMapに読み込まれた内容を基準にする必要があるため、この判定は
	# _seed_demo_world()より前に行う。
	var pinned_version := SaveSystem.get_slot_schema_version(SaveSystem.current_slot_id)
	if pinned_version != "" and pinned_version != WorldSchemaDb.active_version_id:
		WorldSchemaDb.import_into_worldmap(pinned_version)
	_seed_demo_world()
	SaveSystem.load_game()
	TimeSystem.day_advanced.connect(_on_day_advanced)
	TimeSystem.month_ended.connect(_on_month_ended)
	TimeSystem.speed_changed.connect(_on_speed_changed)
	EventDialogue.line_shown.connect(_on_dialogue_line_shown)
	EventDialogue.finished.connect(_on_dialogue_finished)
	_refresh_all()

func _process(_delta: float) -> void:
	_refresh_time_label()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveSystem.save_game()
		get_tree().quit()

func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# 雇用/NPC管理/行動ログ/セーブは全て画面中央に開くポップアップなので、
	# 同時に開けると重なってしまう。開いている間は背後に敷いて他の操作を受け付けない
	# 半透明の遮断レイヤー(常に1枚だけ存在し、_open_modal/_close_modalで使い回す)。
	modal_blocker = ColorRect.new()
	modal_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_blocker.color = Color(0, 0, 0, 0.45)
	modal_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_blocker.visible = false
	add_child(modal_blocker)

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(240, 0)
	root.add_child(left_scroll)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left)

	funds_label = Label.new()
	left.add_child(funds_label)

	var time_row := HBoxContainer.new()
	left.add_child(time_row)

	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 12)
	time_label.modulate = Color(1, 1, 1, 0.7)
	time_row.add_child(time_label)

	speed_button = Button.new()
	speed_button.text = "1x"
	speed_button.pressed.connect(_on_speed_pressed)
	time_row.add_child(speed_button)

	next_month_button = Button.new()
	next_month_button.text = "次の月へ"
	next_month_button.pressed.connect(_on_next_month_pressed)
	next_month_button.visible = false
	left.add_child(next_month_button)

	# 資金/時間以外の各機能は、ボタンが増えて240px幅のサイドバーに収まりきらなくなったため、
	# ボタン1つで開くポップアップパネルにまとめてある(行動ログ・セーブスロットと同じパターン)。
	var hire_button := Button.new()
	hire_button.text = "雇用"
	hire_button.pressed.connect(_on_open_hire_pressed)
	left.add_child(hire_button)

	var npc_button := Button.new()
	npc_button.text = "NPC管理"
	npc_button.pressed.connect(_on_open_npc_panel_pressed)
	left.add_child(npc_button)

	var action_log_button := Button.new()
	action_log_button.text = "行動ログ"
	action_log_button.pressed.connect(_on_open_action_log_pressed)
	left.add_child(action_log_button)

	var slot_button := Button.new()
	slot_button.text = "セーブ"
	slot_button.pressed.connect(_on_open_slots_pressed)
	left.add_child(slot_button)

	map_scroll = ScrollContainer.new()
	map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(map_scroll)

	map_canvas = Control.new()
	map_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	map_canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
	map_canvas.draw.connect(_on_map_canvas_draw)
	map_canvas.gui_input.connect(_on_map_canvas_gui_input)
	map_scroll.add_child(map_canvas)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(260, 0)
	root.add_child(right)

	var board_header := HBoxContainer.new()
	right.add_child(board_header)

	board_title_label = Label.new()
	board_title_label.text = "掲示板(全体)"
	board_header.add_child(board_title_label)

	var back_to_global_button := Button.new()
	back_to_global_button.text = "全体に戻す"
	back_to_global_button.pressed.connect(_on_back_to_global_pressed)
	board_header.add_child(back_to_global_button)

	board_log = RichTextLabel.new()
	board_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(board_log)

## 雇用/NPC管理/行動ログ/セーブのポップアップパネルを、他を必ず閉じた上で1つだけ開く。
## 遮断レイヤーも一緒に前面へ持ってきて、開いている間はマップや他のパネルを操作できなくする。
func _open_modal(panel: PanelContainer) -> void:
	for p in [hire_panel, npc_panel, action_log_panel, slot_panel]:
		p.visible = (p == panel)
	modal_blocker.visible = true
	move_child(modal_blocker, get_child_count() - 1)
	move_child(panel, get_child_count() - 1)

func _close_modal(panel: PanelContainer) -> void:
	panel.visible = false
	modal_blocker.visible = false

func _build_dialogue_ui() -> void:
	dialogue_panel = PanelContainer.new()
	dialogue_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue_panel.offset_top = -200 # BOTTOM_WIDEはtop/bottomアンカーが同値になり高さ0になるため、明示的に高さを確保する
	dialogue_panel.visible = false
	add_child(dialogue_panel) # rootの後に追加することで手前に重ねて表示する

	var row := HBoxContainer.new()
	dialogue_panel.add_child(row)

	left_slot = _make_portrait_slot(Color(0.3, 0.45, 0.6))
	row.add_child(left_slot)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(0, 200)
	row.add_child(center)

	speaker_name_label = Label.new()
	speaker_name_label.add_theme_font_size_override("font_size", 20)
	center.add_child(speaker_name_label)

	dialogue_text_label = Label.new()
	dialogue_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	dialogue_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(dialogue_text_label)

	choices_box = VBoxContainer.new()
	center.add_child(choices_box)

	advance_hint = Button.new()
	advance_hint.text = "▼ 次へ"
	advance_hint.pressed.connect(func(): EventDialogue.advance())
	center.add_child(advance_hint)

	right_slot = _make_portrait_slot(Color(0.6, 0.35, 0.3))
	row.add_child(right_slot)

func _make_portrait_slot(base_color: Color) -> VBoxContainer:
	var slot := VBoxContainer.new()
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(140, 160)
	rect.color = base_color
	slot.add_child(rect)
	var name_plate := Label.new()
	name_plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.add_child(name_plate)
	_dim_portrait_slot(slot)
	return slot

func _dim_portrait_slot(slot: VBoxContainer) -> void:
	slot.modulate = Color(1, 1, 1, 0.35)
	slot.get_child(1).text = ""

func _highlight_portrait_slot(slot: VBoxContainer, character_name: String) -> void:
	slot.modulate = Color(1, 1, 1, 1)
	slot.get_child(1).text = character_name

func _on_dialogue_line_shown(line: Dictionary) -> void:
	dialogue_panel.visible = true
	speaker_name_label.text = line.get("name", "")
	dialogue_text_label.text = line.get("text", "")

	var side: String = line.get("side", "none")
	if side == "left":
		_highlight_portrait_slot(left_slot, line.get("name", ""))
	else:
		_dim_portrait_slot(left_slot)
	if side == "right":
		_highlight_portrait_slot(right_slot, line.get("name", ""))
	else:
		_dim_portrait_slot(right_slot)

	for child in choices_box.get_children():
		child.queue_free()

	var choices: Array = line.get("choices", [])
	choices_box.visible = not choices.is_empty()
	advance_hint.visible = choices.is_empty()
	for i in range(choices.size()):
		var choice_button := Button.new()
		choice_button.text = choices[i]["label"]
		choice_button.pressed.connect(func(): EventDialogue.choose(i))
		choices_box.add_child(choice_button)

func _on_dialogue_finished(_outcome: String) -> void:
	# ゲーム状態への反映(ゲート突破の適用など)はExploration側が個別に処理する。
	# ここではUIを閉じて最新状態を反映するだけ。
	dialogue_panel.visible = false
	_refresh_board()
	_refresh_map()

## 行動ログビューアー(design.md 8.2「記録再生」)。掲示板と違い、DBの`action_log`テーブルを
## その場でクエリして表示する(常時メモリに保持しない)。NPCで絞り込める。
func _build_action_log_ui() -> void:
	action_log_panel = PanelContainer.new()
	action_log_panel.set_anchors_preset(Control.PRESET_CENTER)
	action_log_panel.offset_left = -280
	action_log_panel.offset_top = -220
	action_log_panel.offset_right = 280
	action_log_panel.offset_bottom = 220
	action_log_panel.visible = false
	add_child(action_log_panel)

	var col := VBoxContainer.new()
	action_log_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "行動ログ"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(action_log_panel))
	header.add_child(close_button)

	action_log_npc_option = OptionButton.new()
	action_log_npc_option.item_selected.connect(func(_i): _refresh_action_log())
	col.add_child(action_log_npc_option)

	action_log_text = RichTextLabel.new()
	action_log_text.custom_minimum_size = Vector2(0, 320)
	action_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(action_log_text)

func _on_open_action_log_pressed() -> void:
	action_log_npc_option.clear()
	action_log_npc_option.add_item("全員", -1)
	action_log_npc_option.set_item_metadata(0, -1)
	for npc in Npcs.get_roster():
		var idx := action_log_npc_option.item_count
		action_log_npc_option.add_item(npc["name"], idx)
		action_log_npc_option.set_item_metadata(idx, npc["id"])
	_open_modal(action_log_panel)
	_refresh_action_log()

func _refresh_action_log() -> void:
	var npc_id := -1
	if action_log_npc_option.selected >= 0:
		npc_id = action_log_npc_option.get_item_metadata(action_log_npc_option.selected)
	action_log_text.clear()
	for entry in SaveSystem.query_action_log(npc_id):
		action_log_text.append_text("[Day %d] %s\n" % [entry["day"], entry["text"]])

## 雇用パネル(募集・候補一覧・雇用)。サイドバーの「雇用」ボタンから開く。
func _build_hire_ui() -> void:
	hire_panel = PanelContainer.new()
	hire_panel.set_anchors_preset(Control.PRESET_CENTER)
	hire_panel.offset_left = -240
	hire_panel.offset_top = -180
	hire_panel.offset_right = 240
	hire_panel.offset_bottom = 180
	hire_panel.visible = false
	add_child(hire_panel)

	var col := VBoxContainer.new()
	hire_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "雇用"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(hire_panel))
	header.add_child(close_button)

	var recruit_button := Button.new()
	recruit_button.text = "募集を掛ける(コスト: %d)" % Economy.recruitment_post_cost()
	recruit_button.pressed.connect(_on_recruit_pressed)
	col.add_child(recruit_button)

	candidates_list = ItemList.new()
	candidates_list.custom_minimum_size = Vector2(0, 160)
	candidates_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(candidates_list)

	var hire_button := Button.new()
	hire_button.text = "選択した候補を雇う"
	hire_button.pressed.connect(_on_hire_pressed)
	col.add_child(hire_button)

func _on_open_hire_pressed() -> void:
	_refresh_candidates()
	_open_modal(hire_panel)

## NPC管理パネル(名簿・担当セクション割り当て・スキル訓練・施設拡張)。
## サイドバーの「NPC管理」ボタンから開く。
func _build_npc_ui() -> void:
	npc_panel = PanelContainer.new()
	npc_panel.set_anchors_preset(Control.PRESET_CENTER)
	npc_panel.offset_left = -280
	npc_panel.offset_top = -260
	npc_panel.offset_right = 280
	npc_panel.offset_bottom = 260
	npc_panel.visible = false
	add_child(npc_panel)

	var col := VBoxContainer.new()
	npc_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "NPC管理"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(npc_panel))
	header.add_child(close_button)

	var roster_label := Label.new()
	roster_label.text = "雇用NPC"
	col.add_child(roster_label)

	roster_list = ItemList.new()
	roster_list.custom_minimum_size = Vector2(0, 150)
	roster_list.item_selected.connect(func(_i): _refresh_train_cost_label())
	col.add_child(roster_list)

	section_option = OptionButton.new()
	col.add_child(section_option)

	var assign_button := Button.new()
	assign_button.text = "選択NPCを担当セクションに割り当てる"
	assign_button.pressed.connect(_on_assign_section_pressed)
	col.add_child(assign_button)

	var view_thread_button := Button.new()
	view_thread_button.text = "選択セクションの詳細ログを見る"
	view_thread_button.pressed.connect(_on_view_thread_pressed)
	col.add_child(view_thread_button)

	skill_option = OptionButton.new()
	for skill in SkillTypes.all_skills():
		skill_option.add_item(SkillTypes.SKILL_NAMES[skill], skill)
	skill_option.item_selected.connect(func(_i): _refresh_train_cost_label())
	col.add_child(skill_option)

	var train_row := HBoxContainer.new()
	col.add_child(train_row)

	var train_button := Button.new()
	train_button.text = "選択NPCのスキルを訓練する"
	train_button.pressed.connect(_on_train_pressed)
	train_row.add_child(train_button)

	train_cost_label = Label.new()
	train_row.add_child(train_cost_label)

	facility_button = Button.new()
	facility_button.pressed.connect(_on_upgrade_facility_pressed)
	col.add_child(facility_button)

func _on_open_npc_panel_pressed() -> void:
	_refresh_roster()
	_refresh_train_cost_label()
	_refresh_facility_button()
	_open_modal(npc_panel)

## セーブスロット管理UI(design.md 8.2「スキーマ再プレイ」)。既存スロットの一覧・切替と、
## スキーマDBから新規プレイを開始する導線をここにまとめる。
func _build_slot_ui() -> void:
	slot_panel = PanelContainer.new()
	slot_panel.set_anchors_preset(Control.PRESET_CENTER)
	slot_panel.offset_left = -280
	slot_panel.offset_top = -220
	slot_panel.offset_right = 280
	slot_panel.offset_bottom = 220
	slot_panel.visible = false
	add_child(slot_panel)

	var col := VBoxContainer.new()
	slot_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "セーブスロット"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(slot_panel))
	header.add_child(close_button)

	slot_list = ItemList.new()
	slot_list.custom_minimum_size = Vector2(0, 260)
	slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(slot_list)

	var open_button := Button.new()
	open_button.text = "このスロットを開く"
	open_button.pressed.connect(_on_open_slot_pressed)
	col.add_child(open_button)

	var delete_button := Button.new()
	delete_button.text = "選択したスロットを削除する"
	delete_button.pressed.connect(_on_delete_slot_pressed)
	col.add_child(delete_button)

	var new_game_button := Button.new()
	new_game_button.text = "新規プレイを開始する"
	new_game_button.pressed.connect(func(): new_game_confirm.popup_centered())
	col.add_child(new_game_button)

	new_game_confirm = ConfirmationDialog.new()
	new_game_confirm.dialog_text = "現在の進行とは別に、新しいセーブスロットでゼロから始めます。よろしいですか？"
	new_game_confirm.confirmed.connect(_on_new_game_confirmed)
	add_child(new_game_confirm)

	delete_slot_confirm = ConfirmationDialog.new()
	delete_slot_confirm.confirmed.connect(_on_delete_slot_confirmed)
	add_child(delete_slot_confirm)

func _on_open_slots_pressed() -> void:
	_refresh_slot_list()
	_open_modal(slot_panel)

func _refresh_slot_list() -> void:
	slot_list.clear()
	for slot in SaveSystem.list_slots():
		var active_mark := " (現在)" if slot["slot_id"] == SaveSystem.current_slot_id else ""
		var idx := slot_list.item_count
		slot_list.add_item("スロット%d%s — 資金%d / Day%d / NPC%d人" % [
			slot["slot_id"], active_mark, slot["funds"], slot["day"], slot["npc_count"]])
		slot_list.set_item_metadata(idx, slot["slot_id"])

func _on_open_slot_pressed() -> void:
	var selected := slot_list.get_selected_items()
	if selected.is_empty():
		return
	var slot_id: int = slot_list.get_item_metadata(selected[0])
	if slot_id == SaveSystem.current_slot_id:
		_close_modal(slot_panel)
		return
	SaveSystem.switch_to_slot(slot_id)
	_refresh_all()
	_close_modal(slot_panel)

func _on_new_game_confirmed() -> void:
	SaveSystem.create_new_slot()
	_refresh_all()
	_close_modal(slot_panel)

func _on_delete_slot_pressed() -> void:
	var selected := slot_list.get_selected_items()
	if selected.is_empty():
		return
	var slot_id: int = slot_list.get_item_metadata(selected[0])
	if slot_id == SaveSystem.current_slot_id:
		return # 開いている(アクティブな)スロットは削除できない
	_pending_delete_slot_id = slot_id
	delete_slot_confirm.dialog_text = "スロット%dを完全に削除します。元に戻せません。よろしいですか？" % slot_id
	delete_slot_confirm.popup_centered()

func _on_delete_slot_confirmed() -> void:
	SaveSystem.delete_slot(_pending_delete_slot_id)
	_pending_delete_slot_id = -1
	_refresh_slot_list()

const MAP_COLUMNS := 5
const MAP_CELL_SIZE := Vector2(220, 100)
const MAP_NODE_SIZE := Vector2(200, 74)
const MAP_SECTION_GAP := 60.0
const MAP_SECTION_HEADER := 26.0
const MAP_SECTION_PADDING := 12.0
const MAP_OUTER_MARGIN := Vector2(20, 20)

## GraphEdit(Godot標準のノードエディタ用UI)は当初マップ表示に流用していたが、
## ノード/フレームがドラッグで動かせてしまう(GraphElement.draggableを切ってもグラフ編集用の
## 挙動が随所に残る)ため、プレイ中に意図せずレイアウトが崩れる問題があった。ノードグラフ編集の
## ためのウィジェットであり、読み取り専用のマップ表示には使うべきでないと判断し、
## 素のControlノードで組み直した(接続線は自前でdraw_lineする)。
func _seed_demo_world() -> void:
	# ワールドの中身(エリア/セクション/フロア/イベント)はworld_data.gdが
	# オートロードとして既に流し込み済み。ここではWorldMapの内容を
	# UI(セクション選択・ノードグラフ)として描画するだけ。
	for section_id in WorldMap.sections.keys():
		section_option.add_item(WorldMap.sections[section_id]["name"], section_option.item_count)
		section_option.set_item_metadata(section_option.item_count - 1, section_id)

	var positions := _compute_node_positions()
	node_labels.clear()
	node_centers.clear()

	var content_size := Vector2.ZERO
	for section_id in WorldMap.sections.keys():
		var member_ids := WorldMap.nodes_in_section(section_id)
		if member_ids.is_empty():
			continue
		var bounds := _section_bounds(member_ids, positions)
		_create_section_panel(section_id, bounds)
		content_size.x = max(content_size.x, bounds.position.x + bounds.size.x)
		content_size.y = max(content_size.y, bounds.position.y + bounds.size.y)

	for id in WorldMap.nodes.keys():
		var cell_pos: Vector2 = positions.get(id, Vector2.ZERO)
		_create_node_box(id, cell_pos)
		content_size.x = max(content_size.x, cell_pos.x + MAP_CELL_SIZE.x)
		content_size.y = max(content_size.y, cell_pos.y + MAP_CELL_SIZE.y)

	map_canvas.custom_minimum_size = content_size + Vector2(40, 40)
	map_canvas.queue_redraw()
	_refresh_map()

## セクションごとにグリッド状の自動レイアウトを組む。手動で位置を指定しなくても、
## ノード数がどれだけ増えても(数百規模でも)セクション同士が重ならないようにする。
func _compute_node_positions() -> Dictionary:
	# ScrollContainerは子の負座標部分をスクロールでは見せてくれない(スクロール範囲は
	# コンテンツが(0,0)起点である前提で計算される)ため、セクション枠のパディング/ヘッダー分だけ
	# 全体を右下にずらして、どのセクション枠も座標が負にならないようにする。
	var positions := {}
	var y_offset := MAP_OUTER_MARGIN.y
	for section_id in WorldMap.sections.keys():
		var member_ids := WorldMap.nodes_in_section(section_id)
		if member_ids.is_empty():
			continue
		var section_top := y_offset + MAP_SECTION_HEADER
		for i in range(member_ids.size()):
			var col := i % MAP_COLUMNS
			var row := i / MAP_COLUMNS
			positions[member_ids[i]] = Vector2(MAP_OUTER_MARGIN.x + col * MAP_CELL_SIZE.x, section_top + row * MAP_CELL_SIZE.y)
		var rows := ceili(float(member_ids.size()) / MAP_COLUMNS)
		y_offset = section_top + rows * MAP_CELL_SIZE.y + MAP_SECTION_GAP

	for id in WorldMap.nodes.keys():
		if not positions.has(id):
			positions[id] = MAP_OUTER_MARGIN # 未所属フロアの保険

	return positions

func _section_bounds(member_ids: Array, positions: Dictionary) -> Rect2:
	var min_pos: Vector2 = positions[member_ids[0]]
	var max_pos: Vector2 = positions[member_ids[0]] + MAP_CELL_SIZE
	for id in member_ids:
		var p: Vector2 = positions[id]
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		max_pos.x = max(max_pos.x, p.x + MAP_CELL_SIZE.x)
		max_pos.y = max(max_pos.y, p.y + MAP_CELL_SIZE.y)
	var top_left := min_pos - Vector2(MAP_SECTION_PADDING, MAP_SECTION_HEADER)
	var size := (max_pos - min_pos) + Vector2(MAP_SECTION_PADDING * 2.0, MAP_SECTION_HEADER + MAP_SECTION_PADDING)
	return Rect2(top_left, size)

func _create_section_panel(section_id: String, bounds: Rect2) -> void:
	var panel := Panel.new()
	panel.position = bounds.position
	panel.size = bounds.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.3, 0.1, 0.18)
	style.border_color = Color(0.5, 0.3, 0.1, 0.6)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	map_canvas.add_child(panel)

	var title := Label.new()
	title.text = WorldMap.sections[section_id]["name"]
	title.position = bounds.position + Vector2(6, 2)
	title.add_theme_font_size_override("font_size", 14)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_canvas.add_child(title)

func _create_node_box(id: String, cell_pos: Vector2) -> void:
	var margin := (MAP_CELL_SIZE - MAP_NODE_SIZE) / 2.0
	var box := PanelContainer.new()
	box.position = cell_pos + margin
	box.custom_minimum_size = MAP_NODE_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	box.add_child(vbox)

	var name_label := Label.new()
	name_label.text = WorldMap.nodes[id]["name"]
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(name_label)

	var status_label := Label.new()
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.modulate = Color(1, 1, 1, 0.7)
	vbox.add_child(status_label)

	map_canvas.add_child(box)
	node_labels[id] = status_label
	node_centers[id] = cell_pos + MAP_CELL_SIZE / 2.0

## ノード/セクション枠自体はドラッグできない(意図的にmouse_filter = IGNOREにしている)が、
## スクロールバーだけでは数百ノード規模のマップを動き回るのがつらいので、
## 何もない場所を左ドラッグすればキャンバスごと掴んで動かせるようにする。
func _on_map_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_map_panning = event.pressed
	elif event is InputEventMouseMotion and _map_panning:
		map_scroll.scroll_horizontal -= event.relative.x
		map_scroll.scroll_vertical -= event.relative.y

func _on_map_canvas_draw() -> void:
	var drawn := {}
	for id in WorldMap.nodes.keys():
		if not node_centers.has(id):
			continue
		for neighbor in WorldMap.neighbors(id):
			if not node_centers.has(neighbor):
				continue
			var pair := "%s|%s" % [id, neighbor] if id < neighbor else "%s|%s" % [neighbor, id]
			if drawn.has(pair):
				continue
			drawn[pair] = true
			map_canvas.draw_line(node_centers[id], node_centers[neighbor], Color(1, 1, 1, 0.3), 2.0)

func _refresh_map() -> void:
	for id in node_labels.keys():
		var label: Label = node_labels[id]
		if WorldMap.is_passed(id):
			label.text = "突破済み"
		elif WorldMap.is_found(id):
			label.text = "発見済み(進行不可)"
		else:
			label.text = "未発見"

func _on_recruit_pressed() -> void:
	Recruitment.post_recruitment()
	_refresh_candidates()
	_refresh_funds()

func _on_hire_pressed() -> void:
	var selected := candidates_list.get_selected_items()
	if selected.is_empty():
		return
	Recruitment.hire_candidate(selected[0])
	_refresh_candidates()
	_refresh_roster()
	_refresh_funds()

func _on_assign_section_pressed() -> void:
	var selected_npc := roster_list.get_selected_items()
	if selected_npc.is_empty() or section_option.selected < 0:
		return
	var npc: Dictionary = Npcs.get_roster()[selected_npc[0]]
	var section_id: String = section_option.get_item_metadata(section_option.selected)
	Npcs.assign_section(npc["id"], section_id)
	_refresh_roster()

func _on_view_thread_pressed() -> void:
	if section_option.selected < 0:
		return
	viewing_thread_id = section_option.get_item_metadata(section_option.selected)
	board_title_label.text = "掲示板(%s)" % WorldMap.sections[viewing_thread_id]["name"]
	_refresh_board()

func _on_back_to_global_pressed() -> void:
	viewing_thread_id = ""
	board_title_label.text = "掲示板(全体)"
	_refresh_board()

func _on_train_pressed() -> void:
	var selected_npc := roster_list.get_selected_items()
	if selected_npc.is_empty() or skill_option.selected < 0:
		return
	var npc: Dictionary = Npcs.get_roster()[selected_npc[0]]
	var skill: int = skill_option.get_item_id(skill_option.selected)
	var cost := Economy.training_cost(Npcs.skill_level(npc["id"], skill))
	if not Economy.spend(cost):
		return
	Npcs.train_skill(npc["id"], skill, cost)
	_refresh_funds()
	_refresh_roster()
	_refresh_train_cost_label()

func _on_upgrade_facility_pressed() -> void:
	Economy.upgrade_facility()
	_refresh_funds()
	_refresh_facility_button()

func _on_next_month_pressed() -> void:
	TimeSystem.confirm_and_resume()
	next_month_button.visible = false

func _on_speed_pressed() -> void:
	TimeSystem.cycle_speed()

func _on_speed_changed(multiplier: float) -> void:
	speed_button.text = "%gx" % multiplier

func _on_day_advanced(_day: int) -> void:
	_refresh_board()
	_refresh_map()
	_refresh_roster()
	_refresh_train_cost_label()
	SaveSystem.save_game()

func _on_month_ended(_month: int) -> void:
	next_month_button.visible = true
	_refresh_board()

func _refresh_all() -> void:
	_refresh_funds()
	_refresh_candidates()
	_refresh_roster()
	_refresh_board()
	_refresh_map()
	_refresh_train_cost_label()
	_refresh_facility_button()

func _refresh_train_cost_label() -> void:
	var selected_npc := roster_list.get_selected_items()
	if selected_npc.is_empty() or skill_option.selected < 0:
		train_cost_label.text = ""
		return
	var npc: Dictionary = Npcs.get_roster()[selected_npc[0]]
	var skill: int = skill_option.get_item_id(skill_option.selected)
	var level := Npcs.skill_level(npc["id"], skill)
	train_cost_label.text = "現在Lv%d → コスト%d" % [level, Economy.training_cost(level)]

func _refresh_facility_button() -> void:
	facility_button.text = "施設を拡張する(雇用上限+2, コスト: %d)" % Economy.facility_upgrade_cost()

func _refresh_funds() -> void:
	funds_label.text = "資金: %d / 雇用上限: %d" % [Economy.funds, Economy.employ_cap]

func _refresh_time_label() -> void:
	if TimeSystem.is_paused:
		time_label.text = "月末集計待ち"
		return
	var remaining := int(TimeSystem.seconds_until_month_end())
	time_label.text = "月末まで %d:%02d" % [remaining / 60, remaining % 60]

func _refresh_candidates() -> void:
	candidates_list.clear()
	for c in Recruitment.current_candidates:
		candidates_list.add_item("%s (質%.1f, コスト%d)" % [c["name"], c["quality"], c["cost"]])

func _refresh_roster() -> void:
	roster_list.clear()
	for npc in Npcs.get_roster():
		var section_id: String = npc["assigned_section"]
		var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else "未割当"
		roster_list.add_item("%s (血筋: %s, 担当: %s)" % [npc["name"], npc["innate_traits"].get("bloodline", "-"), section_name])

func _refresh_board() -> void:
	board_log.clear()
	var source: Array = Board.thread_recent(viewing_thread_id, 30) if viewing_thread_id != "" else Board.recent(20)
	for entry in source:
		board_log.append_text("[Day %d] %s\n" % [entry["day"], entry["text"]])
