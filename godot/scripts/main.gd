extends Control

var candidates_list: ItemList
var hire_status_label: Label
var roster_list: VBoxContainer # NPCごとのカード行(アイコン/HPバー/状態バッジ)を並べる
var section_tree: Tree
var npc_detail_label: Label
var skill_level_labels: Dictionary = {} # skill:int -> Label(Lv/コスト表示)
var post_clear_behavior_buttons: Dictionary = {} # Npcs.PostClearBehavior:int -> Button
var _selected_npc_id: int = -1
var facility_button: Button
var node_labels: Dictionary = {} # node_id -> Label(状態表示)
var node_name_labels: Dictionary = {} # node_id -> Label(名前表示。未発見なら????)
var node_boxes: Dictionary = {} # node_id -> PanelContainer(自身/誰か/未踏破の色分け対象)
var node_centers: Dictionary = {} # node_id -> Vector2(map_canvas内での中心座標。接続線描画用)
var section_icon_rows: Dictionary = {} # section_id -> HBoxContainer(担当NPCアイコン表示用)
var section_bounds_cache: Dictionary = {} # section_id -> Rect2(エリア選択ボタンのスクロール先計算用)
var funds_label: Label
var date_label: Label
var time_label: Label
var speed_buttons: Dictionary = {} # multiplier:float -> Button
var board_log: RichTextLabel
var board_title_label: Label
var board_preview_log: RichTextLabel
var board_panel: PanelContainer
var node_detail_panel: PanelContainer
var node_detail_title: Label
var node_detail_body: RichTextLabel
var viewing_thread_id: String = "" # 空なら全体フィード
var next_month_button: Button
var map_scroll: ScrollContainer
var map_canvas: Control
var _map_panning: bool = false
var _map_zoom: float = 1.0
var _node_style_self: StyleBoxFlat
var _node_style_someone: StyleBoxFlat
var _node_style_unexplored: StyleBoxFlat

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
	_build_theme()
	_build_node_styles()
	_build_ui()
	_build_dialogue_ui()
	_build_action_log_ui()
	_build_slot_ui()
	_build_hire_ui()
	_build_npc_ui()
	_build_board_ui()
	_build_node_detail_ui()
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

## アプリ全体に1枚だけ適用する共通テーマ。「押せる/選べるもの」と「ただの文字」が
## 見た目でほとんど区別できない(押せるのに素の文字にしか見えない、選択してもわずかにしか
## 色が変わらない)という指摘への対応。ボタン・Tree・ItemListの各状態(通常/ホバー/押下・
## 選択中)に、彩度・明度の差がはっきり付くStyleBoxFlatを設定し、rootに1回設定するだけで
## 全パネルの全ボタン/一覧に伝播させる(個々のadd_child箇所を1つずつ直す必要がない)。
func _build_theme() -> void:
	var ui_theme := Theme.new()

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.2, 0.22, 0.28, 1.0)
	btn_normal.border_color = Color(0.5, 0.56, 0.68, 0.9)
	btn_normal.set_border_width_all(2)
	btn_normal.set_corner_radius_all(4)
	btn_normal.content_margin_left = 10
	btn_normal.content_margin_right = 10
	btn_normal.content_margin_top = 6
	btn_normal.content_margin_bottom = 6

	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = Color(0.28, 0.31, 0.4, 1.0)
	btn_hover.border_color = Color(0.65, 0.72, 0.85, 1.0)

	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = Color(0.14, 0.46, 0.86, 1.0) # 押下中/選択中は彩度の高い青にはっきり変える
	btn_pressed.border_color = Color(0.6, 0.85, 1.0, 1.0)
	btn_pressed.set_border_width_all(2)
	btn_pressed.set_corner_radius_all(4)
	btn_pressed.content_margin_left = 10
	btn_pressed.content_margin_right = 10
	btn_pressed.content_margin_top = 6
	btn_pressed.content_margin_bottom = 6

	var btn_hover_pressed := btn_pressed.duplicate()
	btn_hover_pressed.bg_color = Color(0.2, 0.54, 0.92, 1.0)

	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.bg_color = Color(0.13, 0.13, 0.15, 0.6)
	btn_disabled.set_corner_radius_all(4)

	var btn_focus := StyleBoxFlat.new()
	btn_focus.draw_center = false
	btn_focus.border_color = Color(1, 1, 1, 0.6)
	btn_focus.set_border_width_all(1)
	btn_focus.set_corner_radius_all(4)

	for type_name in ["Button", "OptionButton"]:
		ui_theme.set_stylebox("normal", type_name, btn_normal)
		ui_theme.set_stylebox("hover", type_name, btn_hover)
		ui_theme.set_stylebox("pressed", type_name, btn_pressed)
		ui_theme.set_stylebox("hover_pressed", type_name, btn_hover_pressed)
		ui_theme.set_stylebox("disabled", type_name, btn_disabled)
		ui_theme.set_stylebox("focus", type_name, btn_focus)
		ui_theme.set_color("font_color", type_name, Color(0.93, 0.95, 0.98))
		ui_theme.set_color("font_hover_color", type_name, Color(1, 1, 1))
		ui_theme.set_color("font_pressed_color", type_name, Color(1, 1, 1))
		ui_theme.set_color("font_disabled_color", type_name, Color(0.55, 0.55, 0.58))

	# Tree(担当セクション選択)・ItemList(候補/セーブスロット一覧)も、選択中の行がボタンの
	# 押下状態と同じ彩度の青にはっきり変わるようにする(そうしないと「選べる」ことが
	# 見た目でほとんど分からず、地の文字と見分けが付かない)。
	var selected_row := StyleBoxFlat.new()
	selected_row.bg_color = Color(0.14, 0.46, 0.86, 0.9)
	selected_row.set_corner_radius_all(3)
	for type_name in ["Tree", "ItemList"]:
		ui_theme.set_stylebox("selected", type_name, selected_row)
		ui_theme.set_stylebox("selected_focus", type_name, selected_row)

	theme = ui_theme # rootのControl(このシーン自身)に設定するだけで、以降add_childする全子孫に伝播する

func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# 雇用/NPC管理/行動ログ/セーブは全て画面中央に開くポップアップなので、
	# 同時に開けると重なってしまう。開いている間は背後に敷いて他の操作を受け付けない
	# 半透明の遮断レイヤー(常に1枚だけ存在し、_open_modal/_close_modalで使い回す)。
	modal_blocker = ColorRect.new()
	modal_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_blocker.color = Color(0.03, 0.03, 0.05, 0.92) # 背景(マップ等)を透かしすぎないよう、ほぼ不透明に
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

	date_label = Label.new()
	date_label.add_theme_font_size_override("font_size", 12)
	left.add_child(date_label)

	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 12)
	time_label.modulate = Color(1, 1, 1, 0.7)
	left.add_child(time_label)

	# 順送りクリックで切り替えるのではなく、全段階を横に並べて1クリックで直接選べるようにする。
	# ButtonGroupで排他選択(ラジオボタン相当)にし、現在の倍速が一目で分かるようにする。
	var speed_row := HBoxContainer.new()
	left.add_child(speed_row)

	var speed_group := ButtonGroup.new()
	speed_buttons.clear()
	for speed in TimeSystem.SPEED_STEPS:
		var btn := Button.new()
		btn.text = "%dx" % int(speed)
		btn.toggle_mode = true
		btn.button_group = speed_group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_speed_button_pressed.bind(speed))
		speed_row.add_child(btn)
		speed_buttons[speed] = btn

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

	var board_button := Button.new()
	board_button.text = "掲示板"
	board_button.pressed.connect(_on_open_board_pressed)
	left.add_child(board_button)

	# ボタン直下に直近10件(全体フィード固定)だけ流す小さなプレビュー。全文・スレッド切替は
	# board_buttonから開くウィンドウ(board_panel)側で行う。背景を透かさず不透明気味にして、
	# 他の要素の上に浮いて見えないようにする。
	var board_preview_panel := PanelContainer.new()
	var board_preview_style := StyleBoxFlat.new()
	board_preview_style.bg_color = Color(0.05, 0.05, 0.07, 0.95)
	board_preview_style.set_border_width_all(1)
	board_preview_style.border_color = Color(1, 1, 1, 0.15)
	board_preview_style.content_margin_left = 4
	board_preview_style.content_margin_right = 4
	board_preview_style.content_margin_top = 4
	board_preview_style.content_margin_bottom = 4
	board_preview_panel.add_theme_stylebox_override("panel", board_preview_style)
	left.add_child(board_preview_panel)

	board_preview_log = RichTextLabel.new()
	board_preview_log.custom_minimum_size = Vector2(0, 150)
	board_preview_log.scroll_active = true
	board_preview_log.add_theme_font_size_override("normal_font_size", 11)
	board_preview_panel.add_child(board_preview_log)

	# マップが縦に長くエリア間の移動が大変なため、マップ領域(map_area)を作って
	# map_scrollを全面に敷き、その上にエリア選択ボタンをフロートで重ねる。
	var map_area := Control.new()
	map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(map_area)

	map_scroll = ScrollContainer.new()
	map_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_area.add_child(map_scroll)

	map_canvas = Control.new()
	map_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	map_canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
	map_canvas.draw.connect(_on_map_canvas_draw)
	map_canvas.gui_input.connect(_on_map_canvas_gui_input)
	map_scroll.add_child(map_canvas)

	# エリア選択ボタン(map_scrollの後に追加することで手前に重ねて表示する)。WorldMap.areasは
	# オートロードのWorldDataが既に流し込み済みなので、ここで一度作ればズームでの再描画時も
	# 作り直す必要はない(area_bar自体はズームやマップ内容に依存しないため)。
	var area_nav_panel := PanelContainer.new()
	area_nav_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var area_nav_style := StyleBoxFlat.new()
	area_nav_style.bg_color = Color(0.05, 0.05, 0.07, 0.9)
	area_nav_style.content_margin_left = 6
	area_nav_style.content_margin_right = 6
	area_nav_style.content_margin_top = 4
	area_nav_style.content_margin_bottom = 4
	area_nav_panel.add_theme_stylebox_override("panel", area_nav_style)
	map_area.add_child(area_nav_panel)

	var area_nav_scroll := ScrollContainer.new()
	area_nav_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	area_nav_panel.add_child(area_nav_scroll)

	var area_nav_row := HBoxContainer.new()
	area_nav_scroll.add_child(area_nav_row)
	for area_id in WorldMap.areas.keys():
		var area_button := Button.new()
		area_button.text = WorldMap.areas[area_id]["name"]
		area_button.pressed.connect(_on_area_nav_pressed.bind(area_id))
		area_nav_row.add_child(area_button)

## 雇用/NPC管理/行動ログ/セーブ/掲示板のポップアップパネルを、他を必ず閉じた上で1つだけ開く。
## 遮断レイヤーも一緒に前面へ持ってきて、開いている間はマップや他のパネルを操作できなくする。
func _open_modal(panel: PanelContainer) -> void:
	for p in [hire_panel, npc_panel, action_log_panel, slot_panel, board_panel, node_detail_panel]:
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

## 掲示板パネル(全体フィード/セクション別スレッド)。以前は右カラムに常設表示していたが、
## 他の機能と同じくサイドバーの「掲示板」ボタンから開くウィンドウに統合した。
## ボタン直下の直近10件プレビュー(board_preview_log)は_build_ui()側で作っている。
func _build_board_ui() -> void:
	board_panel = PanelContainer.new()
	board_panel.set_anchors_preset(Control.PRESET_CENTER)
	board_panel.offset_left = -300
	board_panel.offset_top = -240
	board_panel.offset_right = 300
	board_panel.offset_bottom = 240
	board_panel.visible = false
	add_child(board_panel)

	var col := VBoxContainer.new()
	board_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)

	board_title_label = Label.new()
	board_title_label.text = "掲示板(全体)"
	board_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(board_title_label)

	var back_to_global_button := Button.new()
	back_to_global_button.text = "全体に戻す"
	back_to_global_button.pressed.connect(_on_back_to_global_pressed)
	header.add_child(back_to_global_button)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(board_panel))
	header.add_child(close_button)

	board_log = RichTextLabel.new()
	board_log.custom_minimum_size = Vector2(0, 360)
	board_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(board_log)

func _on_open_board_pressed() -> void:
	_open_modal(board_panel)
	_refresh_board()

## フロア詳細パネル。マップ上でフロアの箱をダブルクリックすると開く(_on_map_double_click)。
func _build_node_detail_ui() -> void:
	node_detail_panel = PanelContainer.new()
	node_detail_panel.set_anchors_preset(Control.PRESET_CENTER)
	node_detail_panel.offset_left = -260
	node_detail_panel.offset_top = -220
	node_detail_panel.offset_right = 260
	node_detail_panel.offset_bottom = 220
	node_detail_panel.visible = false
	add_child(node_detail_panel)

	var col := VBoxContainer.new()
	node_detail_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)

	node_detail_title = Label.new()
	node_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_detail_title.add_theme_font_size_override("font_size", 18)
	header.add_child(node_detail_title)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(node_detail_panel))
	header.add_child(close_button)

	node_detail_body = RichTextLabel.new()
	node_detail_body.custom_minimum_size = Vector2(0, 320)
	node_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(node_detail_body)

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

	hire_status_label = Label.new()
	hire_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	hire_status_label.modulate = Color(1, 1, 1, 0.8)
	col.add_child(hire_status_label)

func _on_open_hire_pressed() -> void:
	_refresh_candidates()
	hire_status_label.text = ""
	_open_modal(hire_panel)

## NPC管理パネル(名簿・担当セクション割り当て・スキル訓練・施設拡張)。
## サイドバーの「NPC管理」ボタンから開く。
##
## 「場所を選んでからNPCを選ぶ」ではなく「NPCを選ぶと、その子の移動先や
## スキル訓練などの操作が右側に出る」という順番にしてある方が分かりやすいため、
## 左に名簿、右にその場で選択中のNPC向けの操作をまとめている。
func _build_npc_ui() -> void:
	npc_panel = PanelContainer.new()
	npc_panel.set_anchors_preset(Control.PRESET_CENTER)
	npc_panel.offset_left = -380
	npc_panel.offset_top = -300
	npc_panel.offset_right = 380
	npc_panel.offset_bottom = 300
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

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(220, 0)
	body.add_child(left_col)

	var roster_label := Label.new()
	roster_label.text = "雇用NPC(選択すると右に操作が出ます)"
	roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	left_col.add_child(roster_label)

	# 血筋・担当・状態を1行の文字列に詰め込むと折り返し/はみ出しで読めなくなるため、
	# NPCごとにアイコン・HPバー・状態バッジを別々の部品として並べたカード行に作り直した
	# (ItemListの文字列一覧から、素のControlで組んだカードのリストへ)。
	var roster_scroll := ScrollContainer.new()
	roster_scroll.custom_minimum_size = Vector2(0, 300)
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(roster_scroll)

	roster_list = VBoxContainer.new()
	roster_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(roster_list)

	facility_button = Button.new()
	facility_button.pressed.connect(_on_upgrade_facility_pressed)
	left_col.add_child(facility_button)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right_scroll)

	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right_col)

	npc_detail_label = Label.new()
	npc_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	right_col.add_child(npc_detail_label)

	right_col.add_child(HSeparator.new())

	var section_label := Label.new()
	section_label.text = "担当セクションの割り当て(エリアごとに折り畳めます)"
	section_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	right_col.add_child(section_label)

	section_tree = Tree.new()
	section_tree.custom_minimum_size = Vector2(0, 180)
	section_tree.hide_root = true
	right_col.add_child(section_tree)

	var section_actions := HBoxContainer.new()
	right_col.add_child(section_actions)

	var assign_button := Button.new()
	assign_button.text = "選択セクションに割り当てる"
	assign_button.pressed.connect(_on_assign_to_section_pressed)
	section_actions.add_child(assign_button)

	var view_thread_button := Button.new()
	view_thread_button.text = "このセクションのログを見る"
	view_thread_button.pressed.connect(_on_view_thread_pressed)
	section_actions.add_child(view_thread_button)

	# 完全踏破後の挙動(留まって収入源として維持するか、次の未踏破セクションへ自動で移るか)。
	# NPCごとに設定できる(exploration.gdのpost_clear_behavior参照)。
	var post_clear_row := HBoxContainer.new()
	right_col.add_child(post_clear_row)

	var post_clear_label := Label.new()
	post_clear_label.text = "完全踏破後:"
	post_clear_row.add_child(post_clear_label)

	var post_clear_group := ButtonGroup.new()
	var stay_button := Button.new()
	stay_button.text = "留まる(収入維持)"
	stay_button.toggle_mode = true
	stay_button.button_group = post_clear_group
	stay_button.pressed.connect(_on_post_clear_behavior_pressed.bind(Npcs.PostClearBehavior.STAY))
	post_clear_row.add_child(stay_button)
	post_clear_behavior_buttons[Npcs.PostClearBehavior.STAY] = stay_button

	var move_on_button := Button.new()
	move_on_button.text = "次のセクションへ自動移動"
	move_on_button.toggle_mode = true
	move_on_button.button_group = post_clear_group
	move_on_button.pressed.connect(_on_post_clear_behavior_pressed.bind(Npcs.PostClearBehavior.MOVE_ON))
	post_clear_row.add_child(move_on_button)
	post_clear_behavior_buttons[Npcs.PostClearBehavior.MOVE_ON] = move_on_button

	right_col.add_child(HSeparator.new())

	var skill_label := Label.new()
	skill_label.text = "スキル訓練"
	right_col.add_child(skill_label)

	skill_level_labels.clear()
	for skill in SkillTypes.all_skills():
		var row := HBoxContainer.new()
		right_col.add_child(row)

		var name_col := VBoxContainer.new()
		name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_col)

		var name_label := Label.new()
		name_label.text = SkillTypes.SKILL_NAMES[skill]
		name_col.add_child(name_label)

		var desc_label := Label.new()
		desc_label.text = SkillTypes.SKILL_DESCRIPTIONS[skill]
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.modulate = Color(1, 1, 1, 0.6)
		name_col.add_child(desc_label)

		var level_label := Label.new()
		level_label.custom_minimum_size = Vector2(140, 0)
		row.add_child(level_label)
		skill_level_labels[skill] = level_label

		var train_button := Button.new()
		train_button.text = "訓練する"
		train_button.pressed.connect(_on_train_skill_pressed.bind(skill))
		row.add_child(train_button)

func _on_open_npc_panel_pressed() -> void:
	_populate_section_tree()
	_refresh_roster()
	_refresh_npc_detail()
	_refresh_facility_button()
	_open_modal(npc_panel)

## セクション選択肢をエリア→セクションの2階層に組んで、エリア単位で折り畳めるようにする。
## 割り当て先として選べるのは、既に誰かが到達しているか、隣接する突破済みノードから
## 発見を試みられるセクションだけにする(WorldMap.is_section_reachable)。世界のどこからも
## 繋がっていない未到達地帯は、選んでも実際には何も進まず紛らわしいだけなので表示しない。
func _populate_section_tree() -> void:
	section_tree.clear()
	var root := section_tree.create_item()
	for area_id in WorldMap.areas.keys():
		var reachable_sections := WorldMap.sections_in_area(area_id).filter(WorldMap.is_section_reachable)
		if reachable_sections.is_empty():
			continue
		var area_item := section_tree.create_item(root)
		area_item.set_text(0, WorldMap.areas[area_id]["name"])
		area_item.set_selectable(0, false)
		for section_id in reachable_sections:
			var section_item := section_tree.create_item(area_item)
			section_item.set_text(0, WorldMap.sections[section_id]["name"])
			section_item.set_metadata(0, section_id)

func _on_roster_row_pressed(npc_id: int) -> void:
	_selected_npc_id = npc_id
	_refresh_npc_detail()

func _refresh_npc_detail() -> void:
	if _selected_npc_id < 0 or Npcs.get_npc(_selected_npc_id).is_empty():
		npc_detail_label.text = "左の一覧からNPCを選択してください"
		for skill in skill_level_labels.keys():
			skill_level_labels[skill].text = ""
		for behavior in post_clear_behavior_buttons.keys():
			post_clear_behavior_buttons[behavior].button_pressed = false
		return
	var npc := Npcs.get_npc(_selected_npc_id)
	var section_id: String = npc["assigned_section"]
	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else "未割当"
	npc_detail_label.text = "%s (血筋: %s)\n担当: %s / HP: %d/%d / 状態: %s" % [
		npc["name"], npc["innate_traits"].get("bloodline", "-"), section_name, int(npc["hp"]), int(npc["max_hp"]),
		_npc_status_text(npc)]
	for skill in skill_level_labels.keys():
		var level := Npcs.skill_level(_selected_npc_id, skill)
		skill_level_labels[skill].text = "Lv%d → コスト%d" % [level, Economy.training_cost(level)]
	var behavior: int = npc["post_clear_behavior"]
	if post_clear_behavior_buttons.has(behavior):
		post_clear_behavior_buttons[behavior].button_pressed = true
	_select_current_section_in_tree(section_id)

## NPCを切り替えるたびに、担当セクションのTreeもそのNPCの現在の割り当て先を選択済みに
## しておく(以前は前に選んでいたNPCの選択状態がそのまま残っていて紛らわしかった)。
func _select_current_section_in_tree(section_id: String) -> void:
	var root := section_tree.get_root()
	if root == null:
		return
	var area_item := root.get_first_child()
	while area_item:
		var item := area_item.get_first_child()
		while item:
			if item.get_metadata(0) == section_id:
				item.select(0)
				return
			item = item.get_next()
		area_item = area_item.get_next()

## 探索中/回復中(あと何日か)/未割当を文字にする。回復中はcombat.gdでの敗北/撤退時のみ発生し、
## 従来UIのどこにも表示していなかったため、放置していても「なぜ動いていないのか」が
## 分かりづらかった。
func _npc_status_text(npc: Dictionary) -> String:
	match int(npc["status"]):
		Npcs.Status.RECOVERING:
			return "回復中(あと%d日)" % max(0, npc["recovering_until_day"] - TimeSystem.current_day)
		Npcs.Status.EXPLORING:
			return "探索中"
		_:
			return "待機中(未割当)"

func _on_post_clear_behavior_pressed(behavior: int) -> void:
	if _selected_npc_id < 0:
		return
	Npcs.set_post_clear_behavior(_selected_npc_id, behavior)

func _on_assign_to_section_pressed() -> void:
	if _selected_npc_id < 0:
		return
	var selected_item := section_tree.get_selected()
	if selected_item == null:
		return
	var section_id = selected_item.get_metadata(0)
	if section_id == null:
		return
	Npcs.assign_section(_selected_npc_id, section_id)
	_refresh_roster()
	_refresh_npc_detail()

func _on_train_skill_pressed(skill: int) -> void:
	if _selected_npc_id < 0:
		return
	var cost := Economy.training_cost(Npcs.skill_level(_selected_npc_id, skill))
	if not Economy.spend(cost):
		return
	Npcs.train_skill(_selected_npc_id, skill, cost)
	_refresh_funds()
	_refresh_roster()
	_refresh_npc_detail()

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
const BASE_MAP_CELL_SIZE := Vector2(220, 100)
const BASE_MAP_NODE_SIZE := Vector2(200, 74)
const BASE_MAP_SECTION_GAP := 60.0
const BASE_MAP_SECTION_HEADER := 40.0 # タイトル行+担当NPCアイコン行の2段分の高さ
const BASE_MAP_SECTION_PADDING := 12.0
const BASE_MAP_OUTER_MARGIN := Vector2(20, 20)
const BASE_AREA_PADDING := 18.0
const BASE_AREA_HEADER := 34.0 # エリア名を表示する分の余白
# マップ上部にフロートで重ねているエリア選択バー(_build_ui参照)のおおよその高さ。
# ズームでは拡大縮小されない固定オーバーレイなので、_map_zoomを掛けない生の値で扱う。
const MAP_NAV_BAR_CLEARANCE := 50.0
const MAP_ZOOM_MIN := 0.4
const MAP_ZOOM_MAX := 2.2
const MAP_ZOOM_STEP := 0.15

func _map_cell_size() -> Vector2:
	return BASE_MAP_CELL_SIZE * _map_zoom

func _map_node_size() -> Vector2:
	return BASE_MAP_NODE_SIZE * _map_zoom

## マップセルの状態別スタイル(自身=明るく+ボーダー、誰か=普通、未踏破=暗い)。使い回すだけなので
## 3つだけ作って全ノードで共有する(StyleBoxFlatはResourceなので複数Controlに使い回して問題ない)。
func _build_node_styles() -> void:
	_node_style_self = StyleBoxFlat.new()
	_node_style_self.bg_color = Color(0.22, 0.5, 0.85, 0.9)
	_node_style_self.border_color = Color(0.75, 0.92, 1.0, 1.0)
	_node_style_self.set_border_width_all(2)
	_node_style_self.set_corner_radius_all(3)

	_node_style_someone = StyleBoxFlat.new()
	_node_style_someone.bg_color = Color(0.28, 0.28, 0.32, 0.85)
	_node_style_someone.set_corner_radius_all(3)

	_node_style_unexplored = StyleBoxFlat.new()
	_node_style_unexplored.bg_color = Color(0.08, 0.08, 0.09, 0.85)
	_node_style_unexplored.set_corner_radius_all(3)

## GraphEdit(Godot標準のノードエディタ用UI)は当初マップ表示に流用していたが、
## ノード/フレームがドラッグで動かせてしまう(GraphElement.draggableを切ってもグラフ編集用の
## 挙動が随所に残る)ため、プレイ中に意図せずレイアウトが崩れる問題があった。ノードグラフ編集の
## ためのウィジェットであり、読み取り専用のマップ表示には使うべきでないと判断し、
## 素のControlノードで組み直した(接続線は自前でdraw_lineする)。
##
## ズーム変更時もこの関数を呼び直してレイアウトを丸ごと再計算する(Control.scaleは
## ScrollContainerがスクロール範囲を正しく再計算してくれないため使わない方針)。
func _seed_demo_world() -> void:
	# ワールドの中身(エリア/セクション/フロア/イベント)はworld_data.gdが
	# オートロードとして既に流し込み済み。ここではWorldMapの内容を
	# UI(ノードグラフ)として描画するだけ。担当セクションの選択肢(section_tree)は
	# NPC管理パネルを開くたびに_populate_section_treeで組み直す。
	for child in map_canvas.get_children():
		child.queue_free()

	var positions := _compute_node_positions()
	node_labels.clear()
	node_name_labels.clear()
	node_boxes.clear()
	node_centers.clear()
	section_icon_rows.clear()
	section_bounds_cache.clear()

	var cell_size := _map_cell_size()
	var content_size := Vector2.ZERO
	var area_bounds: Dictionary = {} # area_id -> Rect2(所属セクションのbounds同士の外接矩形)
	for section_id in WorldMap.sections.keys():
		var member_ids := WorldMap.nodes_in_section(section_id)
		if member_ids.is_empty():
			continue
		var bounds := _section_bounds(member_ids, positions)
		section_bounds_cache[section_id] = bounds
		var area_id: String = WorldMap.sections[section_id]["area"]
		area_bounds[area_id] = bounds if not area_bounds.has(area_id) else area_bounds[area_id].merge(bounds)

	# 「小さな王国」のようなエリア名がマップ上のどこにも表示されず、どこからどこまでが
	# そのエリアなのか分からないという指摘への対応。所属セクションを束ねる大きな背景枠を
	# 先に(=描画上は手前のセクション枠より後ろに)追加する。
	for area_id in area_bounds.keys():
		var expanded := _create_area_panel(area_id, area_bounds[area_id])
		content_size.x = max(content_size.x, expanded.position.x + expanded.size.x)
		content_size.y = max(content_size.y, expanded.position.y + expanded.size.y)

	for section_id in section_bounds_cache.keys():
		_create_section_panel(section_id, section_bounds_cache[section_id])
		var bounds: Rect2 = section_bounds_cache[section_id]
		content_size.x = max(content_size.x, bounds.position.x + bounds.size.x)
		content_size.y = max(content_size.y, bounds.position.y + bounds.size.y)

	for id in WorldMap.nodes.keys():
		var cell_pos: Vector2 = positions.get(id, Vector2.ZERO)
		_create_node_box(id, cell_pos)
		content_size.x = max(content_size.x, cell_pos.x + cell_size.x)
		content_size.y = max(content_size.y, cell_pos.y + cell_size.y)

	map_canvas.custom_minimum_size = content_size + Vector2(40, 40) * _map_zoom
	map_canvas.queue_redraw()
	_refresh_map()

## セクションごとにグリッド状の自動レイアウトを組む。手動で位置を指定しなくても、
## ノード数がどれだけ増えても(数百規模でも)セクション同士が重ならないようにする。
func _compute_node_positions() -> Dictionary:
	# ScrollContainerは子の負座標部分をスクロールでは見せてくれない(スクロール範囲は
	# コンテンツが(0,0)起点である前提で計算される)ため、セクション枠のパディング/ヘッダー分だけ
	# 全体を右下にずらして、どのセクション枠も座標が負にならないようにする。
	var positions := {}
	var cell_size := _map_cell_size()
	var outer_margin := BASE_MAP_OUTER_MARGIN * _map_zoom
	var section_header := BASE_MAP_SECTION_HEADER * _map_zoom
	var section_gap := BASE_MAP_SECTION_GAP * _map_zoom
	# エリアの背景枠(_create_area_panel)とその見出し用に、エリアの先頭と切り替わり目に
	# 余白を確保しておく。そうしないとエリア名がすぐ上のエリアの中身と重なってしまう。
	var area_reserve := (BASE_AREA_PADDING + BASE_AREA_HEADER) * _map_zoom
	# 起動直後(スクロール位置0)でも1つ目のエリア名がフロートのエリア選択バーの
	# 真裏に隠れないよう、その分もあらかじめ余白として確保しておく。
	var y_offset := outer_margin.y + area_reserve + MAP_NAV_BAR_CLEARANCE
	var previous_area := ""
	for section_id in WorldMap.sections.keys():
		var member_ids := WorldMap.nodes_in_section(section_id)
		if member_ids.is_empty():
			continue
		var area_id: String = WorldMap.sections[section_id]["area"]
		if previous_area != "" and area_id != previous_area:
			y_offset += area_reserve
		previous_area = area_id
		var section_top := y_offset + section_header
		for i in range(member_ids.size()):
			var col := i % MAP_COLUMNS
			var row := i / MAP_COLUMNS
			positions[member_ids[i]] = Vector2(outer_margin.x + col * cell_size.x, section_top + row * cell_size.y)
		var rows := ceili(float(member_ids.size()) / MAP_COLUMNS)
		y_offset = section_top + rows * cell_size.y + section_gap

	for id in WorldMap.nodes.keys():
		if not positions.has(id):
			positions[id] = outer_margin # 未所属フロアの保険

	return positions

func _section_bounds(member_ids: Array, positions: Dictionary) -> Rect2:
	var cell_size := _map_cell_size()
	var padding := BASE_MAP_SECTION_PADDING * _map_zoom
	var header := BASE_MAP_SECTION_HEADER * _map_zoom
	var min_pos: Vector2 = positions[member_ids[0]]
	var max_pos: Vector2 = positions[member_ids[0]] + cell_size
	for id in member_ids:
		var p: Vector2 = positions[id]
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		max_pos.x = max(max_pos.x, p.x + cell_size.x)
		max_pos.y = max(max_pos.y, p.y + cell_size.y)
	var top_left := min_pos - Vector2(padding, header)
	var size := (max_pos - min_pos) + Vector2(padding * 2.0, header + padding)
	return Rect2(top_left, size)

## エリア名を表示する大きな背景枠。所属する全セクションのboundsを外接する矩形に、
## パディングと見出し分の余白を足して描く。0未満にならないようclampしているのは、
## ScrollContainerが負座標のコンテンツを正しくスクロールできないため(design.md参照)。
func _create_area_panel(area_id: String, bounds: Rect2) -> Rect2:
	var padding := BASE_AREA_PADDING * _map_zoom
	var header := BASE_AREA_HEADER * _map_zoom
	var top_left := Vector2(max(0.0, bounds.position.x - padding), max(0.0, bounds.position.y - padding - header))
	var bottom_right := bounds.position + bounds.size + Vector2(padding, padding)
	var expanded := Rect2(top_left, bottom_right - top_left)

	var panel := Panel.new()
	panel.position = expanded.position
	panel.size = expanded.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.16, 0.26, 0.14)
	style.border_color = Color(0.4, 0.55, 0.8, 0.55)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	map_canvas.add_child(panel)

	var title := Label.new()
	title.text = WorldMap.areas[area_id]["name"]
	title.position = expanded.position + Vector2(10, 6) * _map_zoom
	title.add_theme_font_size_override("font_size", max(13, roundi(22 * _map_zoom)))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_canvas.add_child(title)

	return expanded

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
	title.position = bounds.position + Vector2(6, 2) * _map_zoom
	title.add_theme_font_size_override("font_size", max(9, roundi(14 * _map_zoom)))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_canvas.add_child(title)

	# どの雇用NPCがこのセクションを担当しているか一目で分かるよう、タイトルの下に
	# 小さなアイコン(暫定として頭文字の丸ボタン。将来的には画像に差し替える)を並べる。
	# クリックでNPC管理パネルを開き、そのNPCを選択した状態にする。中身は_refresh_map()で
	# 担当替えのたびに作り直す(ここでは空の行を用意するだけ)。
	var icon_row := HBoxContainer.new()
	icon_row.position = bounds.position + Vector2(4, 20) * _map_zoom
	map_canvas.add_child(icon_row)
	section_icon_rows[section_id] = icon_row

func _create_node_box(id: String, cell_pos: Vector2) -> void:
	var cell_size := _map_cell_size()
	var node_size := _map_node_size()
	var margin := (cell_size - node_size) / 2.0
	var box := PanelContainer.new()
	box.position = cell_pos + margin
	box.custom_minimum_size = node_size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	box.add_child(vbox)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", max(9, roundi(13 * _map_zoom)))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(name_label)

	var status_label := Label.new()
	status_label.add_theme_font_size_override("font_size", max(8, roundi(11 * _map_zoom)))
	status_label.modulate = Color(1, 1, 1, 0.7)
	vbox.add_child(status_label)

	map_canvas.add_child(box)
	node_boxes[id] = box
	node_name_labels[id] = name_label
	node_labels[id] = status_label
	node_centers[id] = cell_pos + cell_size / 2.0

## ノード/セクション枠自体はドラッグできない(意図的にmouse_filter = IGNOREにしている)が、
## スクロールバーだけでは数百ノード規模のマップを動き回るのがつらいので、
## 何もない場所を左ドラッグすればキャンバスごと掴んで動かせるようにする。
## ホイール回転はズーム(カーソル直下の位置を保ったまま拡大縮小)に割り当てる。
func _on_map_canvas_gui_input(event: InputEvent) -> void:
	# ダブルクリック判定は先に単独でチェックする。そうしないと下のプレーンな左クリック分岐に
	# 先に引っかかってパン開始(_map_panning=true)扱いになり、ダブルクリックへ届かなくなる。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		_on_map_double_click(event.position)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_map_panning = event.pressed
	elif event is InputEventMouseMotion and _map_panning:
		map_scroll.scroll_horizontal -= event.relative.x
		map_scroll.scroll_vertical -= event.relative.y
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_map(true, event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_map(false, event.position)

## マウスホイールでのズーム。カーソル直下にあったコンテンツ座標がズーム後も同じ画面位置に
## 留まるよう、レイアウト再構築後にスクロール位置を計算し直す。
func _zoom_map(zoom_in: bool, cursor_pos: Vector2) -> void:
	var old_zoom := _map_zoom
	var new_zoom := clampf(old_zoom + (MAP_ZOOM_STEP if zoom_in else -MAP_ZOOM_STEP), MAP_ZOOM_MIN, MAP_ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var viewport_pos := cursor_pos - Vector2(map_scroll.scroll_horizontal, map_scroll.scroll_vertical)
	_map_zoom = new_zoom
	_seed_demo_world()
	var new_content_pos := cursor_pos * (new_zoom / old_zoom)
	map_scroll.scroll_horizontal = int(new_content_pos.x - viewport_pos.x)
	map_scroll.scroll_vertical = int(new_content_pos.y - viewport_pos.y)

## フロア(ノード)の枠内なら詳細ポップアップ、それ以外でセクション枠内ならそのセクションの
## 掲示板スレッドを開く。フロアの箱の方がセクション枠より内側にある(小さい)ので、先に
## フロアを判定してからセクションにフォールバックする。
func _on_map_double_click(pos: Vector2) -> void:
	for id in node_boxes.keys():
		var box: PanelContainer = node_boxes[id]
		if box.get_rect().has_point(pos):
			_show_node_detail(id)
			return
	for section_id in section_bounds_cache.keys():
		if section_bounds_cache[section_id].has_point(pos):
			_open_section_thread(section_id)
			return

## フロア単体の詳細(所属セクション・状態・ゲート条件・突破報酬・このフロアに絞った行動ログ)。
## 未発見のフロアはゲート条件やアイテム報酬を明かさない(名前も????のまま)。
func _show_node_detail(id: String) -> void:
	var node: Dictionary = WorldMap.nodes[id]
	var section_name: String = WorldMap.sections[node["section"]]["name"] if WorldMap.sections.has(node["section"]) else node["section"]
	node_detail_title.text = node["name"] if WorldMap.is_found(id) else "????"

	node_detail_body.clear()
	node_detail_body.append_text("所属セクション: %s\n" % section_name)
	if WorldMap.is_passed(id):
		node_detail_body.append_text("状態: 突破済み\n")
	elif WorldMap.is_found(id):
		node_detail_body.append_text("状態: 発見済み(進行不可)\n")
	else:
		node_detail_body.append_text("状態: 未発見\n")

	if WorldMap.is_found(id):
		node_detail_body.append_text("ゲート: %s\n" % _gate_description(node.get("gate", {})))
		var item_reward: String = node.get("item_reward", "")
		if item_reward != "":
			node_detail_body.append_text("突破報酬アイテム: %s\n" % Items.name_of(item_reward))

	node_detail_body.append_text("\n--- このフロアの行動ログ ---\n")
	var entries := SaveSystem.query_action_log_for_node(id)
	if entries.is_empty():
		node_detail_body.append_text("(まだ記録なし)\n")
	else:
		for entry in entries:
			node_detail_body.append_text("[Day %d] %s\n" % [entry["day"], entry["text"]])

	_open_modal(node_detail_panel)

func _gate_description(gate: Dictionary) -> String:
	if gate.is_empty():
		return "なし(自由に通行可能)"
	match gate.get("type", ""):
		"skill":
			return "%s Lv%d以上が必要" % [SkillTypes.SKILL_NAMES[gate["skill"]], gate["min_level"]]
		"combat":
			return "戦闘(敵の戦闘力%d)" % gate["enemy_power"]
		"innate_trait":
			return "特定の血筋(%s)が必要" % gate["value"]
		"item":
			return "アイテム「%s」の所持が必要" % Items.name_of(gate["item"])
		_:
			return "不明"

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

## 状態テキストに加えて、自身(雇用NPCが到達済み)/誰か(野良NPCのみが発見)/未踏破の3色に
## ノードを塗り分ける。未踏破の場所は名前も????にして隠す。踏破待ち(発見済みだが未突破)は
## 半透明にして「まだ先に進めない」ことを示す。
func _refresh_map() -> void:
	for id in node_labels.keys():
		var status_label: Label = node_labels[id]
		var name_label: Label = node_name_labels[id]
		var box: PanelContainer = node_boxes[id]

		if WorldMap.is_passed(id):
			status_label.text = "突破済み"
		elif WorldMap.is_found(id):
			status_label.text = "発見済み(進行不可)"
		else:
			status_label.text = "未発見"

		if not WorldMap.is_found(id):
			name_label.text = "????"
			box.add_theme_stylebox_override("panel", _node_style_unexplored)
		else:
			name_label.text = WorldMap.nodes[id]["name"]
			box.add_theme_stylebox_override("panel", _node_style_self if WorldMap.is_found_by_employed(id) else _node_style_someone)

		var alpha := 0.6 if (WorldMap.is_found(id) and not WorldMap.is_passed(id)) else 1.0
		box.modulate = Color(1, 1, 1, alpha)

	_refresh_section_npc_icons()

## セクションごとの担当NPCアイコンを、現在の割り当て(担当替え・配置転換の結果)に
## 合わせて作り直す。どのセクションにどのNPCがいるか一目で分かるようにするための表示で、
## クリックするとNPC管理パネルでそのNPCを選択した状態にする。
func _refresh_section_npc_icons() -> void:
	var npcs_by_section: Dictionary = {}
	for npc in Npcs.get_roster():
		var section_id: String = npc["assigned_section"]
		if section_id == "":
			continue
		if not npcs_by_section.has(section_id):
			npcs_by_section[section_id] = []
		npcs_by_section[section_id].append(npc)

	for section_id in section_icon_rows.keys():
		var row: HBoxContainer = section_icon_rows[section_id]
		# queue_free()だけだと実際に破棄されるのはアイドルタイム(このフレームの終わり)まで
		# 遅延するため、高倍速で1フレーム中に複数日分処理される(TimeSystem._process()の
		# whileループがフレームをまたがずに何日も_advance_day()を呼ぶ)と、同じフレーム内で
		# この関数が連続で呼ばれるたびにget_children()がまだ残っている古いアイコンを
		# 返してしまい、アイコンが重複表示され続ける不具合になっていた。remove_child()で
		# 即座にツリーから外してからqueue_free()することで、次の呼び出し時にget_children()が
		# 正しく空を返すようにする。
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
		for npc in npcs_by_section.get(section_id, []):
			row.add_child(_create_npc_icon(npc["id"], npc["name"]))

## 頭文字だけの暫定アイコン(将来的にはNPCごとの画像に差し替える想定)。
func _create_npc_icon(npc_id: int, npc_name: String) -> Button:
	var icon := Button.new()
	icon.text = npc_name.substr(0, 1)
	icon.custom_minimum_size = Vector2(20, 20) * _map_zoom
	icon.tooltip_text = npc_name
	icon.add_theme_font_size_override("font_size", max(8, roundi(12 * _map_zoom)))
	icon.pressed.connect(_on_npc_icon_pressed.bind(npc_id))
	return icon

func _on_npc_icon_pressed(npc_id: int) -> void:
	_selected_npc_id = npc_id
	_on_open_npc_panel_pressed()

## マップ上部のエリア選択ボタン用: そのエリアの中で最も上にあるセクションの位置までスクロールする。
func _on_area_nav_pressed(area_id: String) -> void:
	var target_y := -1.0
	for section_id in WorldMap.sections_in_area(area_id):
		if section_bounds_cache.has(section_id):
			var y: float = section_bounds_cache[section_id].position.y
			if target_y < 0 or y < target_y:
				target_y = y
	if target_y >= 0:
		# セクションの先頭ぴったりだと、その上にあるエリア名の見出しがフロートのエリア選択
		# バーの真裏に来て読めなくなるため、見出し分+バーの高さ分だけ余分に上から見せる。
		var area_reserve := (BASE_AREA_PADDING + BASE_AREA_HEADER) * _map_zoom
		map_scroll.scroll_vertical = int(max(0.0, target_y - area_reserve - MAP_NAV_BAR_CLEARANCE))
		map_scroll.scroll_horizontal = 0

func _on_recruit_pressed() -> void:
	if not Economy.can_afford(Economy.recruitment_post_cost()):
		hire_status_label.text = "資金が足りません(募集コスト: %d)" % Economy.recruitment_post_cost()
		return
	Recruitment.post_recruitment()
	hire_status_label.text = "候補を%d人表示しました" % Recruitment.current_candidates.size()
	_refresh_candidates()
	_refresh_funds()

func _on_hire_pressed() -> void:
	if Npcs.get_roster().size() >= Economy.employ_cap:
		hire_status_label.text = "雇用上限(%d)に達しています。NPC管理パネルから施設を拡張すると増やせます" % Economy.employ_cap
		return
	var selected := candidates_list.get_selected_items()
	if selected.is_empty():
		hire_status_label.text = "候補を一覧から選択してください"
		return
	var npc_id := Recruitment.hire_candidate(selected[0])
	if npc_id == -1:
		hire_status_label.text = "雇用できませんでした(資金不足の可能性があります)"
		return
	hire_status_label.text = "%sを雇用しました" % Npcs.get_npc(npc_id)["name"]
	_refresh_candidates()
	_refresh_roster()
	_refresh_funds()

func _on_view_thread_pressed() -> void:
	var selected_item := section_tree.get_selected()
	if selected_item == null:
		return
	var section_id = selected_item.get_metadata(0)
	if section_id == null:
		return
	_open_section_thread(section_id)

## セクションの掲示板スレッドを開く。NPC管理パネルの「このセクションのログを見る」ボタンと、
## マップ上でセクション枠をダブルクリックした場合の両方から使う共通処理。
func _open_section_thread(section_id: String) -> void:
	viewing_thread_id = section_id
	board_title_label.text = "掲示板(%s)" % WorldMap.sections[section_id]["name"]
	_open_modal(board_panel)
	_refresh_board()

func _on_back_to_global_pressed() -> void:
	viewing_thread_id = ""
	board_title_label.text = "掲示板(全体)"
	_refresh_board()

func _on_upgrade_facility_pressed() -> void:
	Economy.upgrade_facility()
	_refresh_funds()
	_refresh_facility_button()

func _on_next_month_pressed() -> void:
	TimeSystem.confirm_and_resume()
	next_month_button.visible = false

func _on_speed_button_pressed(speed: float) -> void:
	TimeSystem.set_speed(speed)

func _on_speed_changed(multiplier: float) -> void:
	if speed_buttons.has(multiplier):
		speed_buttons[multiplier].button_pressed = true

func _on_day_advanced(_day: int) -> void:
	_refresh_board()
	_refresh_map()
	_refresh_roster()
	_refresh_npc_detail()
	_refresh_funds() # セクション攻略の一時金は月末を待たずその日のうちに入るため、日次でも反映する
	SaveSystem.save_game()

func _on_month_ended(_month: int) -> void:
	next_month_button.visible = true
	_refresh_board()
	_refresh_funds() # 月次収入(exploration.gdのEconomy.earn())はここで確定するので反映する

func _refresh_all() -> void:
	_refresh_funds()
	_refresh_candidates()
	_refresh_roster()
	_refresh_board()
	_refresh_map()
	_refresh_npc_detail()
	_refresh_facility_button()
	_on_speed_changed(TimeSystem.speed_multiplier) # ロード直後、実際の倍速にボタンの押下表示を合わせる
	# next_month_buttonは元々month_endedシグナル(その場で月末になった瞬間)でのみ表示していたため、
	# 「一時停止した状態のままセーブ→再起動」すると、is_paused=trueなのにボタンだけ非表示で
	# 再開する手段が無くなってしまう不具合があった。ロード直後の実状態にも合わせて同期する。
	next_month_button.visible = TimeSystem.is_paused

func _refresh_facility_button() -> void:
	facility_button.text = "施設を拡張する(雇用上限+2, コスト: %d)" % Economy.facility_upgrade_cost()

func _refresh_funds() -> void:
	funds_label.text = "資金: %d / 雇用上限: %d" % [Economy.funds, Economy.employ_cap]

func _refresh_time_label() -> void:
	date_label.text = TimeSystem.format_date()
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
	for child in roster_list.get_children():
		roster_list.remove_child(child)
		child.queue_free()
	var roster_group := ButtonGroup.new() # 行を作り直すたびに新しいグループにして排他選択させる
	for npc in Npcs.get_roster():
		var row := _create_roster_row(npc, roster_group)
		roster_list.add_child(row)
		if npc["id"] == _selected_npc_id:
			row.button_pressed = true

const BLOODLINE_COLORS := {
	"平民": Color(0.45, 0.45, 0.48),
	"旧家の血筋": Color(0.5, 0.35, 0.65),
	"森人の血": Color(0.3, 0.6, 0.35),
	"王家の落胤": Color(0.75, 0.6, 0.15),
}

func _bloodline_color(bloodline: String) -> Color:
	return BLOODLINE_COLORS.get(bloodline, Color(0.4, 0.4, 0.4))

const STATUS_COLORS := {
	Npcs.Status.EXPLORING: Color(0.25, 0.55, 0.3),
	Npcs.Status.RECOVERING: Color(0.7, 0.45, 0.15),
	Npcs.Status.IDLE: Color(0.35, 0.35, 0.38),
}

## ロースターのカード行1件。血筋色のアイコン(頭文字)・名前・担当セクション・HPバー・
## 状態バッジを別々の部品として並べる(1つの文字列に詰め込んで折り返す旧UIの反省点)。
## 行全体をtoggle_mode付きButtonにして、どこをクリックしてもそのNPCを選択できるようにする
## (中の子要素はmouse_filter=IGNOREにしてクリックをButtonまで素通りさせる)。
func _create_roster_row(npc: Dictionary, group: ButtonGroup) -> Button:
	var row := Button.new()
	row.toggle_mode = true
	row.button_group = group
	row.custom_minimum_size = Vector2(0, 48)
	row.pressed.connect(_on_roster_row_pressed.bind(npc["id"]))

	# HBoxContainerを行いっぱいに敷くと、中身(アイコン/HPバー等)がボタン自体の背景色/枠線を
	# ほぼ覆い隠してしまい、「押せる/選択できるボタンである」ことがかえって分かりにくくなる。
	# 数pxの余白を残して、選択中の彩度の高い青がフチとして見えるようにする。
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	row.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 6)
	margin.add_child(hbox)

	var icon := PanelContainer.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(32, 32)
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = _bloodline_color(npc["innate_traits"].get("bloodline", ""))
	icon_style.set_corner_radius_all(4)
	icon.add_theme_stylebox_override("panel", icon_style)
	var icon_label := Label.new()
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_label.text = npc["name"].substr(0, 1)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_child(icon_label)
	hbox.add_child(icon)

	var info_col := VBoxContainer.new()
	info_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_col)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = npc["name"]
	info_col.add_child(name_label)

	var section_id: String = npc["assigned_section"]
	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else "未割当"
	var sub_label := Label.new()
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_label.text = section_name
	sub_label.add_theme_font_size_override("font_size", 11)
	sub_label.modulate = Color(1, 1, 1, 0.6)
	info_col.add_child(sub_label)

	var hp_bar := ProgressBar.new()
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.custom_minimum_size = Vector2(44, 0)
	hp_bar.show_percentage = false
	hp_bar.max_value = npc["max_hp"]
	hp_bar.value = npc["hp"]
	hbox.add_child(hp_bar)

	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = STATUS_COLORS.get(int(npc["status"]), Color(0.3, 0.3, 0.3))
	badge_style.set_corner_radius_all(8)
	badge_style.content_margin_left = 6
	badge_style.content_margin_right = 6
	badge_style.content_margin_top = 2
	badge_style.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", badge_style)
	var badge_label := Label.new()
	badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_label.text = _npc_status_short(npc)
	badge_label.add_theme_font_size_override("font_size", 11)
	badge.add_child(badge_label)
	hbox.add_child(badge)

	return row

## カード行のバッジ用に、状態を短い一言にする(詳細な残り日数は右側の詳細パネルに任せる)。
func _npc_status_short(npc: Dictionary) -> String:
	match int(npc["status"]):
		Npcs.Status.RECOVERING:
			return "回復中"
		Npcs.Status.EXPLORING:
			return "探索中"
		_:
			return "待機中"

func _refresh_board() -> void:
	board_log.clear()
	var source: Array = Board.thread_recent(viewing_thread_id, 30) if viewing_thread_id != "" else Board.recent(20)
	for entry in source:
		board_log.append_text("[Day %d] %s\n" % [entry["day"], entry["text"]])

	# ボタン直下のプレビューは常に全体フィードの直近10件固定(閲覧中のスレッドに関係なく)。
	board_preview_log.clear()
	for entry in Board.recent(10):
		board_preview_log.append_text("[Day %d] %s\n" % [entry["day"], entry["text"]])
