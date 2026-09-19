extends Control

var candidates_grid: GridContainer # 候補者の肖像カード(2026-09-14、ItemListのテキスト行から変更)
var _selected_candidate_index: int = -1
var hire_status_label: Label
var roster_grid: GridContainer # NPCごとの正方形ポートレートカード(画像/名前/状態)を並べる
var npc_roster_view: Control # NPC管理パネル: 一覧ビュー(既定で表示)
var npc_detail_view: Control # NPC管理パネル: 選択中NPCの詳細ビュー(ステータス+スキル訓練)
var npc_detail_label: Label
var npc_job_label: Label
var npc_detail_portrait: PanelContainer
var skill_level_labels: Dictionary = {} # skill:int -> Label(Lv/コスト表示)
var reclass_option: OptionButton # 転職先ジョブの選択(design.md 4.8節)
var reclass_button: Button
var _selected_npc_id: int = -1
var facility_button: Button

# パーティ編成パネル(design.md 4.7節)。担当セクション割り当て・予測・完全踏破後の設定は
# NPC単位ではなくパーティ単位の操作になった(旧npc_panelの[担当]タブから移設)。
var party_panel: PanelContainer
var party_roster_view: Control
var party_detail_view: Control
var party_grid: GridContainer
var party_form_list: ItemList # 未所属NPCから最大4人を選ぶ簡易選択(多重選択)
var party_form_status_label: Label
var party_detail_label: Label
var party_member_list: ItemList # 選択中パーティの並び順(上下移動ボタンで編成)
var section_tree: Tree
var section_forecast_label: Label
var post_clear_behavior_buttons: Dictionary = {} # Parties.PostClearBehavior:int -> Button
var _selected_party_id: int = -1
var disband_confirm: ConfirmationDialog
var _pending_disband_party_id: int = -1
var party_button: Button # サイドバー。未割当パーティがある間は赤字で警告表示する(_refresh_party_roster参照)

# セクションへパーティを割り当てる小さなモーダル(マップのセクション名ボタンから開く)。
# パーティ管理パネルの「パーティを選ぶ→担当セクションを選ぶ」の逆順(「セクションを選ぶ→
# パーティを選ぶ」)を提供する。
var section_assign_panel: PanelContainer
var section_assign_title: Label
var section_assign_list: VBoxContainer
var section_assign_status_label: Label
var _section_assign_target_id: String = ""
var _pending_assignment_followup: bool = false # INTRO_TUTORIAL_PART2_SCRIPT予約フラグ

# 武器防具屋パネル(design.md 6.2節)。
var shop_panel: PanelContainer
var shop_npc_option: OptionButton
var shop_weapon_row: HBoxContainer
var shop_armor_row: HBoxContainer
var shop_status_label: Label
var _shop_selected_npc_id: int = -1
var node_labels: Dictionary = {} # node_id -> Label(状態表示)
var node_name_labels: Dictionary = {} # node_id -> Label(名前表示。未発見なら????)
var node_boxes: Dictionary = {} # node_id -> PanelContainer(自身/誰か/未踏破の色分け対象)
var node_centers: Dictionary = {} # node_id -> Vector2(map_canvas内での中心座標。接続線描画用)
var node_icon_rows: Dictionary = {} # node_id -> HBoxContainer(担当NPCアイコンを現在フロアに表示)
var section_bounds_cache: Dictionary = {} # section_id -> Rect2(エリア選択ボタンのスクロール先計算用)
var section_lock_icons: Dictionary = {} # section_id -> Control(未到達セクションの鍵アイコン)
var section_title_buttons: Dictionary = {} # section_id -> Button(セクション名ボタン。到達状況でdisabledを更新)
var facility_info_label: Label
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

# 2本指のピンチでマップを拡大縮小するための状態(2026-09-19)。Android等のタッチ画面向け。
# 専用のピンチイベントが届くかは環境次第なので、生のタッチ(ScreenTouch/ScreenDrag)の位置を自分で
# 追跡し、2本の指の距離の比から倍率を求める。
var _touch_points: Dictionary = {} # 指のindex -> 画面上の位置(押されている指だけ)
var _pinch_active: bool = false
var _pinch_prev_distance: float = 1.0
var _pinch_prev_center: Vector2 = Vector2.ZERO
var _pinch_target_zoom: float = 1.0 # 指の動きに追従して連続的に変わる目標倍率(実際のレイアウトへの反映は間引く)
var _pinch_last_rebuild_msec: int = 0
var _pinch_rebuild_cost_msec: int = 0 # 直近の再構築にかかった時間(遅い端末では反映の間隔を空けるのに使う)
const PINCH_REBUILD_INTERVAL_MSEC := 90 # ピンチ中にマップを作り直す最短の間隔
const PINCH_MIN_ZOOM_CHANGE := 0.02 # 倍率の変化(割合)がこれ未満なら、作り直しを省く
var _active_area_id: String = "" # マップのエリアタブ(design.md 5.1節)で今表示中のエリア
var area_tab_buttons: Dictionary = {} # area_id -> Button(選択状態・🔒表示の更新に使う)
var area_option: OptionButton # タッチUI時のエリア選択プルダウン(area_tab_buttonsの代わりに使う)
var area_prev_button: Button
var area_next_button: Button

## タッチ操作向けのUI(指で押せる高さのボタン、エリア切替のプルダウン等)を使うか。
## Android/iOSでは常にtrue。デスクトップでは通常falseだが、`-- --touch-ui`(ユーザー引数)で
## 確認用に有効にできる。デスクトップ版の見た目・挙動は変えない(_touch_uiがfalseなら従来どおり)。
var _touch_ui: bool = false

const TOUCH_BUTTON_MARGIN_V := 16 # タッチUI時のボタン上下の内側余白(通常は6)。ボタン高さが約50pxになる
const TOUCH_LIST_ROW_MARGIN := 10 # タッチUI時のTree行の上下余白
const TOUCH_DIALOGUE_HEIGHT := 270 # タッチUI時の会話ウィンドウの高さ(通常は200)
# 実機(Android等)で、UI全体を画面の四辺から最低これだけ内側に寄せる(表示上のpx)。切り欠きは
# DisplayServer.get_display_safe_area()で避けられるが、角丸の画面の角はOSが半径を教えてくれない
# 端末(moto g05は0と報告する)があるため、その分の余白を固定で確保する(_apply_safe_area参照)。
const MOBILE_MIN_EDGE_MARGIN := 24.0

const BACK_EXIT_WINDOW_MSEC := 2000 # 戻るキーを続けて押して終了するまでの猶予(何も開いていない時)
var _last_back_press_msec: int = -100000
var back_hint_panel: PanelContainer # 「もう一度戻るキーを押すと終了します」の一時表示
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

var license_panel: PanelContainer # 左メニュー一番下の「ライセンス」ボタンで開く(内容はLicenseInfoが読み込む)
var license_text: RichTextLabel

var action_log_panel: PanelContainer
var action_log_npc_option: OptionButton
var action_log_text: RichTextLabel

var slot_panel: PanelContainer
var slot_list: ItemList
var slot_name_input: LineEdit
var manual_save_status_label: Label
var autosave_checkbox: CheckBox
var new_game_confirm: ConfirmationDialog
var delete_slot_confirm: ConfirmationDialog
var _pending_delete_slot_id: int = -1

var hire_panel: PanelContainer
var npc_panel: PanelContainer
var modal_blocker: ColorRect

## 初回起動時だけ再生する導入会話・前編(design.md参照、2026-09-14に前後編へ分割)。
## 「チュートリアルのマップ割り当てまでが分かりにくい」という指摘への対応として、
## 情報を詰め込みすぎず、まずマップでの割り当て操作そのものへ誘導することだけに絞った。
## SaveSystem.tutorial_intro_seenで一度きりに制御する(_ready()参照)。後編は
## INTRO_TUTORIAL_PART2_SCRIPT(初めて実際に割り当てを行った直後に再生。
## _maybe_show_assignment_followup_tutorial()参照)。
const INTRO_TUTORIAL_PART1_SCRIPT: Array = [
	{"side": "none", "name": "案内人", "text": "ようこそ。ここは、雇ったNPCたちに代わりに世界を探索させ、その稼ぎで暮らしを立てていく土地だ。"},
	{"side": "none", "name": "案内人", "text": "既に「初期パーティ」が1つ、無償で用意されている。まずはこれをどこかのセクション(区画)に割り当てて、探索を始めよう。"},
	{"side": "none", "name": "案内人", "text": "マップに並ぶ、枠で囲まれたセクション名(📍のついたボタンになっている)を押してみるといい。そこにパーティを割り当てられる。", "outcome": "ok"},
]

## 導入会話・後編。初めて実際にパーティ割り当てを行った直後に再生する(マップのセクション名
## ボタン経由/パーティパネルの「割り当て」ボタン経由、どちらでも良い)。前編で触れなかった
## 収入の仕組み/行ける場所の増やし方/進行速度について説明する。
## SaveSystem.tutorial_assignment_followup_seenで一度きりに制御する。
const INTRO_TUTORIAL_PART2_SCRIPT: Array = [
	{"side": "none", "name": "案内人", "text": "よし、これで探索が始まった。割り当てたパーティが、毎日自動で発見・突破に挑んでくれる。"},
	{"side": "none", "name": "案内人", "text": "資金は、担当セクションで突破したフロアの数に応じて毎月自動的に入る。フロアを突破するほど、そしてセクションを完全に突破しきるほど、実入りは大きくなる。"},
	{"side": "none", "name": "案内人", "text": "セクションを突破しきれば、その先の新しいセクションやエリアへの道も開ける。行ける場所を増やしたいなら、目の前を突破し続けるのが一番の近道だ。"},
	{"side": "none", "name": "案内人", "text": "進行速度は画面左上の「1x/10x/100x/1000x」でいつでも変えられる。月末には自動で一時停止するので、収支を確かめてから次の月へ進めるといい。"},
	{"side": "none", "name": "案内人", "text": "困ったら、NPC管理やパーティのパネルを開いて様子を見るといい。……それでは、健闘を祈る。", "outcome": "ok"},
]

## 初めてNPCを雇用した直後だけ再生する説明会話。雇っただけではまだ働けず、パーティ編成
## (1人でも組める)が必要なことを教える。SaveSystem.tutorial_party_seenで一度きりに制御する
## (_on_hire_pressed()参照)。
const PARTY_TUTORIAL_SCRIPT: Array = [
	{"side": "none", "name": "案内人", "text": "新しい仲間が加わった。……とはいえ、雇っただけではまだ働けない。"},
	{"side": "none", "name": "案内人", "text": "「パーティ」パネルを開いて、雇ったNPCを選び、パーティを編成しよう。1人だけでもパーティは組める――まずは1人で始めて、あとから仲間を増やしても構わない。"},
	{"side": "none", "name": "案内人", "text": "パーティが組めたら、担当セクションを割り当てるといい。あとは毎日自動で探索に挑んでくれる。", "outcome": "ok"},
]

func _ready() -> void:
	_touch_ui = OS.has_feature("mobile") or "--touch-ui" in OS.get_cmdline_user_args()
	_build_theme()
	_build_node_styles()
	_build_ui()
	_build_dialogue_ui()
	_build_action_log_ui()
	_build_slot_ui()
	_build_hire_ui()
	_build_npc_ui()
	_build_party_ui()
	_build_shop_ui()
	_build_board_ui()
	_build_node_detail_ui()
	_build_section_assign_ui()
	_build_license_ui()
	_build_back_hint_ui()
	_apply_safe_area()
	get_window().size_changed.connect(_apply_safe_area) # 画面の向きが変わった時など
	# 2026-09-14: 起動時に前回のアクティブスロットを自動ロードする仕様をやめ、常に
	# まっさらな新規プレイから始まるようにした(design.md 8.2節)。既存の進行を続けたい
	# 場合は、セーブパネルから明示的に「このスロットをロードする」を選ぶ(一般的な
	# ゲームの「ロードは明示的操作」という体験に合わせた。過去に診断作業が実セーブを
	# 誤って上書きした事故の根本原因でもあったため、安全面でも狙い通り)。
	# WorldMapはworld_data.gdの起動時ブートストラップで既に最新スキーマで構築済みのため、
	# ここではスキーマの再構築は不要。
	_seed_demo_world()
	SaveSystem.start_fresh_session()
	TimeSystem.day_advanced.connect(_on_day_advanced)
	TimeSystem.month_ended.connect(_on_month_ended)
	TimeSystem.speed_changed.connect(_on_speed_changed)
	EventDialogue.line_shown.connect(_on_dialogue_line_shown)
	EventDialogue.finished.connect(_on_dialogue_finished)
	_refresh_all()
	# 初回起動時だけ、遊び方(NPCの配置/稼ぎ方/行ける場所の増やし方/進行速度)を説明する
	# 導入会話を挟む。スロットに紐付かず(SaveSystem.tutorial_intro_seen)、新規プレイを
	# 何度始めても一度見せたら二度と出さない。この時点ではまだ他の会話は動いていないので、
	# そのまま直接EventDialogue.play()してよい(節末の「イベント会話まわりの実装メモ」参照)。
	# 「見た」フラグは再生開始時ではなく、実際にプレイヤーが最後まで進めてEventDialogue.finished
	# が発火した時点でONE_SHOT接続で永続化する。開始時点で即座に書き込むと、`--headless --quit`
	# のようなコンパイル確認だけの起動(誰も会話を進めない)でも実ファイル(worldseeker_meta.cfg)
	# に「見た」と書き込まれてしまい、次回以降の本当のプレイでチュートリアルが二度と出なくなる
	# 事故につながる(実際に一度発生させて修正した)。
	if not SaveSystem.tutorial_intro_seen:
		EventDialogue.finished.connect(func(_o): SaveSystem.mark_tutorial_intro_seen(), CONNECT_ONE_SHOT)
		EventDialogue.play(INTRO_TUTORIAL_PART1_SCRIPT)
	TimeSystem.mark_boot_complete()

func _process(_delta: float) -> void:
	_refresh_time_label()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_and_quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_go_back_requested()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# 裏に回った間に指を離されると、離した通知を受け取れず、押されたままの指が残ってしまう
		if _pinch_active:
			_end_pinch()
		_touch_points.clear()

func _save_and_quit() -> void:
	SaveSystem.autosave()
	get_tree().quit()

## Androidの戻るキー/戻るジェスチャー。project.godotで`quit_on_go_back=false`にしてあり、
## Godot既定の「即アプリ終了」は行われない(以前はポップアップを閉じるつもりで押すとゲームが
## 終了してしまった)。内側から順に、閉じられるものを1つだけ閉じる。何も開いていなければ
## 「もう一度押すと終了」を出し、猶予内にもう一度押されたときだけ終了する(誤操作対策)。
func _on_go_back_requested() -> void:
	for dialog in [new_game_confirm, delete_slot_confirm]:
		if dialog.visible:
			dialog.hide()
			return
	if npc_panel.visible and npc_detail_view.visible:
		_on_npc_detail_back_pressed() # 詳細画面からは、パネルごと閉じずに一覧へ戻る
		return
	if party_panel.visible and party_detail_view.visible:
		_on_party_detail_back_pressed()
		return
	if modal_blocker.visible:
		_close_any_modal()
		return
	if dialogue_panel.visible:
		return # 会話中は誤って終了しないよう何もしない(「次へ」で進める)
	var now: int = Time.get_ticks_msec()
	if now - _last_back_press_msec <= BACK_EXIT_WINDOW_MSEC:
		_save_and_quit()
		return
	_last_back_press_msec = now
	back_hint_panel.visible = true
	get_tree().create_timer(BACK_EXIT_WINDOW_MSEC / 1000.0).timeout.connect(func(): back_hint_panel.visible = false)

func _build_back_hint_ui() -> void:
	back_hint_panel = PanelContainer.new()
	back_hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	back_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	back_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	back_hint_panel.offset_left = -150
	back_hint_panel.offset_right = 150
	back_hint_panel.offset_top = -100
	back_hint_panel.offset_bottom = -40
	back_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE # 表示中もその下の操作を邪魔しない
	back_hint_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.95)
	style.border_color = Color(1, 1, 1, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	back_hint_panel.add_theme_stylebox_override("panel", style)
	var hint := Label.new()
	hint.text = "もう一度戻るキーを押すと終了します"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_hint_panel.add_child(hint)
	add_child(back_hint_panel) # 最後に追加して、他のパネル・会話の手前に表示する

## 実機(Android等)で、切り欠き(ノッチ/パンチホール)や角丸の画面の角にUIが隠れないよう、UI全体
## (このControl自身)を画面の四辺から内側に寄せる。FlutterのSafeAreaに当たる処理。
## DisplayServer.get_display_safe_area()は切り欠きなどを避けた領域を、画面のピクセル座標で返す。
## ストレッチ(canvas_items)で表示上のpxとは倍率が違うので、変換してから使う。角丸は取得できない
## 端末があるため、どの辺にもMOBILE_MIN_EDGE_MARGINの余白を最低限確保する。
## modal_blockerだけは、寄せたぶん外へ広げて、画面全体を覆ったままにする。デスクトップでは何もしない。
func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var window_size := Vector2(get_window().size)
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return
	var to_viewport := get_viewport().get_visible_rect().size / window_size
	var top_left := Vector2.ZERO
	var bottom_right := Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.has_area():
		top_left = Vector2(safe.position) * to_viewport
		bottom_right = (window_size - Vector2(safe.end)) * to_viewport
	var left := maxf(top_left.x, MOBILE_MIN_EDGE_MARGIN)
	var top := maxf(top_left.y, MOBILE_MIN_EDGE_MARGIN)
	var right := maxf(bottom_right.x, MOBILE_MIN_EDGE_MARGIN)
	var bottom := maxf(bottom_right.y, MOBILE_MIN_EDGE_MARGIN)
	offset_left = left
	offset_top = top
	offset_right = -right
	offset_bottom = -bottom
	modal_blocker.offset_left = -left
	modal_blocker.offset_top = -top
	modal_blocker.offset_right = right
	modal_blocker.offset_bottom = bottom

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
	var margin_v: int = TOUCH_BUTTON_MARGIN_V if _touch_ui else 6
	btn_normal.content_margin_top = margin_v
	btn_normal.content_margin_bottom = margin_v

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
	btn_pressed.content_margin_top = margin_v
	btn_pressed.content_margin_bottom = margin_v

	var btn_hover_pressed := btn_pressed.duplicate()
	btn_hover_pressed.bg_color = Color(0.2, 0.54, 0.92, 1.0)

	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.bg_color = Color(0.13, 0.13, 0.15, 0.6)
	btn_disabled.set_corner_radius_all(4)
	if _touch_ui:
		# disabledスタイルには元々内側余白が無く、押せない状態のボタンだけ他より低くなってしまうため、
		# タッチUIでは通常ボタンと同じ余白を持たせて高さを揃える(デスクトップは従来どおり)。
		btn_disabled.content_margin_left = 10
		btn_disabled.content_margin_right = 10
		btn_disabled.content_margin_top = margin_v
		btn_disabled.content_margin_bottom = margin_v

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

	if _touch_ui:
		# プルダウン(OptionButtonのポップアップ)・Tree・ItemListの1行を指で押せる高さにする。
		ui_theme.set_constant("v_separation", "PopupMenu", 22)
		ui_theme.set_font_size("font_size", "PopupMenu", 18)
		ui_theme.set_constant("inner_item_margin_top", "Tree", TOUCH_LIST_ROW_MARGIN)
		ui_theme.set_constant("inner_item_margin_bottom", "Tree", TOUCH_LIST_ROW_MARGIN)
		ui_theme.set_constant("v_separation", "ItemList", 14)

	var fallback_fonts := _load_system_fallback_fonts()
	if not fallback_fonts.is_empty():
		var default_font := FontVariation.new()
		default_font.base_font = ThemeDB.fallback_font
		default_font.fallbacks = fallback_fonts
		ui_theme.default_font = default_font

	theme = ui_theme # rootのControl(このシーン自身)に設定するだけで、以降add_childする全子孫に伝播する

## Android用: 端末に入っているフォントを、既定フォントのフォールバックとして返す(日本語のCJKと絵文字)。
##
## (1) CJK(2026-09-19): 「[Day 1] 「古い洞窟」…」のように、英数字の直後に来る「「」などの記号が
## 豆腐(□)になる問題への対策。Godotは英字の並びの直後にあるCJK記号を「英字」として扱い、CJKに
## 対応しないフォントをシステムのフォールバックに選んでしまう(Labelのlanguage指定やSystemFontの
## 名前指定を試したが直らなかった)。フォントを同梱せず、端末のNoto Sans CJKを直接読み込んで
## 登録することで、アプリサイズを増やさずに直す(この端末で読み込み約34ms・メモリ約32MB)。ttcの
## 先頭の顔(face 0)が日本語版なのはAndroid標準の並び(fonts.xmlでlang="ja"がindex=0)。
##
## (2) 絵文字(2026-09-19): マップの再構築が実機で約0.5秒かかっていた主因が、「📍」「🔒」を含む文字の
## 描画(セクション名ボタンと鍵アイコン)で、絵文字のたびに端末のシステムフォントを探し直すため
## だった(計測で、セクション1つあたり約60ms=文字設定とツリーへの追加が各約12ms)。絵文字フォントを
## ここで読み込んでおけば、探し直しが要らなくなる(NotoColorEmoji.ttfは約2.7MB)。
##
## 見つからないファイルは飛ばし、無い端末では従来どおりシステムのフォールバックに任せる。
## デスクトップは対象外。
func _load_system_fallback_fonts() -> Array[Font]:
	var fonts: Array[Font] = []
	if not OS.has_feature("android"):
		return fonts
	for path in ["/system/fonts/NotoSansCJK-Regular.ttc", "/system/fonts/NotoColorEmoji.ttf"]:
		if not FileAccess.file_exists(path):
			continue
		var font := FontFile.new()
		if font.load_dynamic_font(path) == OK:
			fonts.append(font)
	return fonts

## マップのセクション名ボタン専用のスタイル(2026-09-14、「セクション名が押せると直感的に
## 分からない」という指摘への対応)。共有Theme([[godot_install_path]]の通常ボタン(青系)とは
## 明確に別系統の暖色(アンバー)にし、「ここが目印/行き先」という意味合いを持たせる。
## disabled状態は個別に上書きしない(共有Themeの薄暗いdisabledスタイルへ自然にフォールバック
## させ、到達不可能なセクションは「押せない」ことも見た目で伝わるようにする)。
func _apply_section_title_button_style(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.55, 0.38, 0.08, 0.9)
	normal.border_color = Color(1.0, 0.78, 0.3, 1.0)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	normal.content_margin_top = 3
	normal.content_margin_bottom = 3
	var hover := normal.duplicate()
	hover.bg_color = Color(0.7, 0.48, 0.1, 0.95)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.4, 0.28, 0.05, 0.95)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))

## 「ここに割り当てる」系の主要アクションボタンを、同じ並びの他ボタン(ログ/予測等)より
## 視覚的に強調する(2026-09-14、「割り当てボタンを目立たせる」という要望への対応)。
## 彩度の高い緑を専用に割り当て、共有Theme(_build_theme())の通常ボタン(青系)と
## 明確に見分けが付くようにする。
func _apply_primary_button_style(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.5, 0.22, 1.0)
	normal.border_color = Color(0.45, 0.85, 0.5, 1.0)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = Color(0.2, 0.62, 0.28, 1.0)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.12, 0.4, 0.18, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color(1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))

## パーティカード(_create_party_card)/セクション割り当てモーダルの行、どちらでも使う
## 「未割当」の赤い強調スタイル(2026-09-14、「未割当のパーティが赤く光る」という要望への
## 対応)。選択中(toggle_mode押下時)は共有Themeの青いpressedスタイルに任せたいため、
## "pressed"は上書きしない。
func _apply_unassigned_warning_style(control: Control) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.5, 0.13, 0.1, 0.85)
	normal.border_color = Color(1.0, 0.35, 0.3, 1.0)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate()
	hover.bg_color = Color(0.6, 0.18, 0.14, 0.95)
	if control is Button:
		control.add_theme_stylebox_override("normal", normal)
		control.add_theme_stylebox_override("hover", hover)
	else:
		control.add_theme_stylebox_override("panel", normal)

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

	party_button = Button.new()
	party_button.text = "パーティ"
	party_button.pressed.connect(_on_open_party_panel_pressed)
	left.add_child(party_button)

	var shop_button := Button.new()
	shop_button.text = "武器防具屋"
	shop_button.pressed.connect(_on_open_shop_pressed)
	left.add_child(shop_button)

	var action_log_button := Button.new()
	action_log_button.text = "行動ログ"
	action_log_button.pressed.connect(_on_open_action_log_pressed)
	left.add_child(action_log_button)

	var slot_button := Button.new()
	slot_button.text = "セーブ/ロード"
	slot_button.pressed.connect(_on_open_slots_pressed)
	left.add_child(slot_button)

	var board_button := Button.new()
	board_button.text = "掲示板"
	board_button.pressed.connect(_on_open_board_pressed)
	left.add_child(board_button)

	# ライセンス表示(画像・Godot・godot-sqlite、将来は音楽なども)。日常的には使わないので、メニューの
	# ボタンとしては一番下に置く。掲示板プレビュー(ボタンではなくログ表示)より上にしてあるのは、
	# タッチUIではこのメニューが画面より縦に長くなり、ボタンの上からのドラッグではスクロールできない
	# (Godotのボタンがドラッグを受け止める)ため、プレビューの下だと指が届かなくなるから。
	var license_button := Button.new()
	license_button.text = "ライセンス"
	license_button.pressed.connect(_on_open_license_pressed)
	left.add_child(license_button)

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

	# エリアタブ(design.md 5.1節、2026-09-14: スクロール式のエリア選択バーから置き換え)。
	# マップが9エリア分を1列に縦積みし続けて際限なく長大化していた問題への対応として、
	# 選んだエリアのセクションだけを表示する方式にした。map_scrollの後に追加することで
	# 手前に重ねて表示する。WorldMap.areasはオートロードのWorldDataが既に流し込み済みなので、
	# ボタン自体はここで一度作ればよい(選択状態・🔒表示は_refresh_area_tabsで更新する)。
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

	area_tab_buttons.clear()
	if _touch_ui:
		_build_area_nav_touch(area_nav_panel)
	else:
		var area_nav_scroll := ScrollContainer.new()
		area_nav_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		area_nav_panel.add_child(area_nav_scroll)

		var area_nav_row := HBoxContainer.new()
		area_nav_scroll.add_child(area_nav_row)
		var area_tab_group := ButtonGroup.new()
		for area_id in WorldMap.areas.keys():
			var area_button := Button.new()
			area_button.toggle_mode = true
			area_button.button_group = area_tab_group
			area_button.pressed.connect(_on_area_tab_pressed.bind(area_id))
			area_nav_row.add_child(area_button)
			area_tab_buttons[area_id] = area_button
	if _active_area_id == "" and not WorldMap.areas.is_empty():
		_active_area_id = WorldMap.areas.keys()[0] # 既定は最初のエリア(王国)

## タッチUI用のエリア選択(2026-09-19)。横スクロールのタブ列は、指でなぞるとバー自体が動いてしまい
## 押し辛かったため、「◀ [現在のエリア ▼] ▶」に置き換えた。中央のプルダウンで任意のエリアへ一発で
## 移動でき、両脇の矢印で隣のエリアへ1タップで移れる。デスクトップ版は従来のタブ列のまま。
func _build_area_nav_touch(panel: PanelContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	area_prev_button = Button.new()
	area_prev_button.text = "◀"
	area_prev_button.custom_minimum_size = Vector2(72, 0)
	area_prev_button.pressed.connect(_on_area_step_pressed.bind(-1))
	row.add_child(area_prev_button)

	area_option = OptionButton.new()
	area_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for area_id in WorldMap.areas.keys():
		area_option.add_item(WorldMap.areas[area_id]["name"])
		area_option.set_item_metadata(area_option.item_count - 1, area_id)
	area_option.item_selected.connect(_on_area_option_selected)
	row.add_child(area_option)

	area_next_button = Button.new()
	area_next_button.text = "▶"
	area_next_button.custom_minimum_size = Vector2(72, 0)
	area_next_button.pressed.connect(_on_area_step_pressed.bind(1))
	row.add_child(area_next_button)

func _on_area_option_selected(index: int) -> void:
	_on_area_tab_pressed(area_option.get_item_metadata(index))

## 矢印ボタン: 現在のエリアから見て前(-1)/次(1)のエリアへ移る(端では押せない状態にしてある)。
func _on_area_step_pressed(direction: int) -> void:
	var area_ids: Array = WorldMap.areas.keys()
	var current: int = area_ids.find(_active_area_id)
	var target: int = clampi(current + direction, 0, area_ids.size() - 1)
	_on_area_tab_pressed(area_ids[target])

## 雇用/NPC管理/行動ログ/セーブ/掲示板のポップアップパネルを、他を必ず閉じた上で1つだけ開く。
## 遮断レイヤーも一緒に前面へ持ってきて、開いている間はマップや他のパネルを操作できなくする。
func _open_modal(panel: PanelContainer) -> void:
	for p in [hire_panel, npc_panel, party_panel, shop_panel, action_log_panel, slot_panel, board_panel, node_detail_panel, section_assign_panel, license_panel]:
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
	var dialogue_height := TOUCH_DIALOGUE_HEIGHT if _touch_ui else 200
	dialogue_panel.offset_top = -dialogue_height # BOTTOM_WIDEはtop/bottomアンカーが同値になり高さ0になるため、明示的に高さを確保する
	if _touch_ui:
		# 選択肢が増えて内容が高さを超えても、画面の外(下)ではなく上へ伸びるようにする。
		dialogue_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialogue_panel.visible = false
	add_child(dialogue_panel) # rootの後に追加することで手前に重ねて表示する

	var row := HBoxContainer.new()
	dialogue_panel.add_child(row)

	left_slot = _make_portrait_slot(Color(0.3, 0.45, 0.6))
	row.add_child(left_slot)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(0, dialogue_height)
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
	if _touch_ui:
		advance_hint.custom_minimum_size = Vector2(0, 72) # 会話は何度も連打するボタンなので、特に大きくする
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
	# 導入会話・後編(INTRO_TUTORIAL_PART2_SCRIPT)の予約消化。他の会話(フロア発見時のVN等)
	# が終わるたびにここでも確認する(下のコメント参照)。
	if _pending_assignment_followup:
		call_deferred("_try_show_assignment_followup_tutorial")

## パーティ割り当て(_assign_party_to_section)の直後に呼ぶ。導入会話・後編を、
## 初めて割り当てを行った時だけ再生する。割り当てはプレイヤーの明示的なクリック操作なので
## 基本的に他の会話と衝突しないはずだが、フロア発見時のVN(exploration.gdの_on_node_found)は
## dialogue_panelがモーダル扱いではないため、理論上は同時に開いていた状態のまま
## 別パネルを操作してこの割り当てクリックに至ることもありえる。exploration.gdの
## RETREAT_TUTORIAL_SCRIPT(撤退説明会話)と同じ「安全になるまでcall_deferredで
## 先送りし続ける」方式で対応する。
func _maybe_show_assignment_followup_tutorial() -> void:
	if SaveSystem.tutorial_assignment_followup_seen or _pending_assignment_followup:
		return
	_pending_assignment_followup = true
	call_deferred("_try_show_assignment_followup_tutorial")

func _try_show_assignment_followup_tutorial() -> void:
	if not _pending_assignment_followup or EventDialogue.is_active:
		return
	_pending_assignment_followup = false
	# dialogue_panelはhire_panel等のモーダルより手前に重ねていない(_open_modalの管理対象外)ため、
	# パーティパネル/割り当てモーダルを開いたまま再生すると会話が背後に隠れて見えなくなる
	# (PARTY_TUTORIAL_SCRIPT再生箇所と同じ理由)。先に閉じてから再生する。
	_close_any_modal()
	EventDialogue.finished.connect(func(_o): SaveSystem.mark_tutorial_assignment_followup_seen(), CONNECT_ONE_SHOT)
	EventDialogue.play(INTRO_TUTORIAL_PART2_SCRIPT)

## 開いているモーダルパネルを問わず全て閉じる(_open_modal/_close_modalは特定の1枚を
## 対象にする作りのため、「今何が開いているか分からないが、とにかく閉じたい」場面用に用意)。
func _close_any_modal() -> void:
	for p in [hire_panel, npc_panel, party_panel, shop_panel, action_log_panel, slot_panel, board_panel, node_detail_panel, section_assign_panel, license_panel]:
		p.visible = false
	modal_blocker.visible = false

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
## ライセンス画面。文書の一覧と読み込みはLicenseInfo(license_info.gd)にあり、ここは表示だけを担当する。
## 音楽などの素材を追加する時も、この関数は変更不要(LicenseInfo.ENTRIESに足す)。
func _build_license_ui() -> void:
	license_panel = PanelContainer.new()
	license_panel.set_anchors_preset(Control.PRESET_CENTER)
	license_panel.offset_left = -320
	license_panel.offset_top = -240
	license_panel.offset_right = 320
	license_panel.offset_bottom = 240
	license_panel.visible = false
	add_child(license_panel)

	var col := VBoxContainer.new()
	license_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "ライセンス"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(license_panel))
	header.add_child(close_button)

	license_text = RichTextLabel.new()
	license_text.bbcode_enabled = true
	license_text.scroll_active = true
	license_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	license_text.custom_minimum_size = Vector2(0, 320)
	col.add_child(license_text)

func _on_open_license_pressed() -> void:
	license_text.text = LicenseInfo.to_bbcode() # 開く時に読み込む(起動を遅くしない)
	license_text.scroll_to_line(0)
	_open_modal(license_panel)

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

## セクションへパーティを割り当てる小さなモーダル(2026-09-14、「選んだセクションから
## パーティ割り当てを可能にする」という要望への対応)。マップのセクション名ボタン
## (_create_section_panel/_on_section_name_pressed)から開く。パーティパネルの
## 「パーティを選ぶ→セクションを選ぶ」の逆順(「セクションを選ぶ→パーティを選ぶ」)を提供する。
func _build_section_assign_ui() -> void:
	section_assign_panel = PanelContainer.new()
	section_assign_panel.set_anchors_preset(Control.PRESET_CENTER)
	section_assign_panel.offset_left = -300
	section_assign_panel.offset_top = -240
	section_assign_panel.offset_right = 300
	section_assign_panel.offset_bottom = 240
	section_assign_panel.visible = false
	add_child(section_assign_panel)

	var col := VBoxContainer.new()
	section_assign_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)

	section_assign_title = Label.new()
	section_assign_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_assign_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	section_assign_title.add_theme_font_size_override("font_size", 16)
	header.add_child(section_assign_title)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(section_assign_panel))
	header.add_child(close_button)

	var hint_label := Label.new()
	hint_label.text = "どのパーティをここへ割り当てますか?(未割当のパーティは赤く強調表示しています)"
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(hint_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	section_assign_list = VBoxContainer.new()
	section_assign_list.add_theme_constant_override("separation", 8)
	section_assign_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(section_assign_list)

	section_assign_status_label = Label.new()
	section_assign_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(section_assign_status_label)

	var form_party_shortcut := Button.new()
	form_party_shortcut.text = "パーティが無い場合はこちらで編成する"
	form_party_shortcut.pressed.connect(func():
		_close_modal(section_assign_panel)
		_open_party_panel())
	col.add_child(form_party_shortcut)

## マップのセクション名ボタン(_create_section_panel)を押した時に開く。
func _on_section_name_pressed(section_id: String) -> void:
	_section_assign_target_id = section_id
	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else section_id
	section_assign_title.text = "「%s」へパーティを割り当て" % section_name
	_refresh_section_assign_list()
	_open_modal(section_assign_panel)

func _refresh_section_assign_list() -> void:
	for child in section_assign_list.get_children():
		section_assign_list.remove_child(child)
		child.queue_free()
	var parties := Parties.get_parties()
	if parties.is_empty():
		section_assign_status_label.text = "まだパーティがありません。NPCを雇用してパーティを編成してください。"
		return
	section_assign_status_label.text = ""
	# 未割当のパーティを先頭に並べ、対応が必要なものを見つけやすくする。
	parties.sort_custom(func(a, b): return a["assigned_section"] == "" and b["assigned_section"] != "")
	for party in parties:
		section_assign_list.add_child(_create_section_assign_row(party))

func _create_section_assign_row(party: Dictionary) -> Control:
	var row := PanelContainer.new()
	var is_unassigned: bool = party["assigned_section"] == ""
	var is_current: bool = party["assigned_section"] == _section_assign_target_id
	if is_unassigned:
		_apply_unassigned_warning_style(row)
	else:
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.16, 0.18, 0.22, 0.9)
		normal.border_color = Color(0.4, 0.44, 0.5, 0.6)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(4)
		normal.content_margin_left = 10
		normal.content_margin_right = 10
		normal.content_margin_top = 6
		normal.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", normal)

	var hbox := HBoxContainer.new()
	row.add_child(hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var section_name := "未割当"
	if not is_unassigned and WorldMap.sections.has(party["assigned_section"]):
		section_name = WorldMap.sections[party["assigned_section"]]["name"]

	var name_label := Label.new()
	name_label.text = "%s%s" % [party["name"], "  ⚠ 未割当" if is_unassigned else ""]
	info.add_child(name_label)

	var sub_label := Label.new()
	sub_label.modulate = Color(1, 1, 1, 0.75)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub_label.text = "現在: %s / 状態: %s / 戦力: %d" % [section_name, _party_status_text(party), Parties.power(party["id"])]
	info.add_child(sub_label)

	var assign_button := Button.new()
	assign_button.text = "現在地です" if is_current else "ここに割り当てる"
	assign_button.disabled = is_current
	if not is_current:
		_apply_primary_button_style(assign_button)
	assign_button.pressed.connect(_on_section_assign_row_pressed.bind(party["id"]))
	hbox.add_child(assign_button)

	return row

func _on_section_assign_row_pressed(party_id: int) -> void:
	_assign_party_to_section(party_id, _section_assign_target_id)
	_close_modal(section_assign_panel)

## 雇用パネル(募集・候補一覧・雇用)。サイドバーの「雇用」ボタンから開く。
func _build_hire_ui() -> void:
	hire_panel = PanelContainer.new()
	hire_panel.set_anchors_preset(Control.PRESET_CENTER)
	hire_panel.offset_left = -260
	hire_panel.offset_top = -220
	hire_panel.offset_right = 260
	hire_panel.offset_bottom = 220
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

	var candidates_scroll := ScrollContainer.new()
	candidates_scroll.custom_minimum_size = Vector2(0, 190)
	candidates_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(candidates_scroll)

	candidates_grid = GridContainer.new()
	candidates_grid.columns = 3
	candidates_grid.add_theme_constant_override("h_separation", 8)
	candidates_grid.add_theme_constant_override("v_separation", 8)
	candidates_scroll.add_child(candidates_grid)

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
## 一覧ビュー(NPCの正方形ポートレートカードを並べただけの画面)を既定で表示し、
## カードをクリックすると詳細ビューに切り替わる(担当及びスキルは一覧には出さない)。
## 詳細ビューは[ステータス(スキル訓練込み)][担当]の2タブに分け、常時2カラムで
## 詰め込んでいた旧UIより縦横それぞれを広く使えるようにした。
func _build_npc_ui() -> void:
	npc_panel = PanelContainer.new()
	npc_panel.set_anchors_preset(Control.PRESET_CENTER)
	npc_panel.offset_left = -500
	npc_panel.offset_top = -300
	npc_panel.offset_right = 500
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

	_build_npc_roster_view(col)
	_build_npc_detail_view(col)

## 一覧ビュー: 正方形ポートレートカードのグリッドのみを中心に表示する(ジョブ/装備/戦力は
## カードをクリックして詳細ビューに移るまで出さない)。
func _build_npc_roster_view(col: VBoxContainer) -> void:
	npc_roster_view = VBoxContainer.new()
	npc_roster_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(npc_roster_view)

	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	npc_roster_view.add_child(roster_scroll)

	roster_grid = GridContainer.new()
	roster_grid.columns = 5
	roster_grid.add_theme_constant_override("h_separation", 10)
	roster_grid.add_theme_constant_override("v_separation", 10)
	roster_scroll.add_child(roster_grid)

	facility_button = Button.new()
	facility_button.text = "施設を拡張する"
	facility_button.pressed.connect(_on_upgrade_facility_pressed)
	npc_roster_view.add_child(facility_button)

	# コスト表示をボタン本体の文字列に埋め込むと、桁が増えるたびにボタンの最小幅が伸びて
	# 押し広げてしまっていたため、ボタンの文言は固定にして数値は別行のLabelへ分離した。
	facility_info_label = Label.new()
	facility_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	facility_info_label.add_theme_font_size_override("font_size", 12)
	facility_info_label.modulate = Color(1, 1, 1, 0.75)
	npc_roster_view.add_child(facility_info_label)

## 詳細ビュー: 一覧でNPCを選ぶとここに切り替わる。上部に「一覧へ戻る」と身元表示
## (ジョブ・固有スキル・装備・戦力込み、npc_detail_label/npc_job_labelに集約)、
## 下にスキル訓練を並べる。担当セクション割り当て・予測・完全踏破後の設定は
## パーティ単位の操作になったため、パーティパネル(_build_party_ui)に移設した。
func _build_npc_detail_view(col: VBoxContainer) -> void:
	npc_detail_view = VBoxContainer.new()
	npc_detail_view.visible = false
	npc_detail_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(npc_detail_view)

	var back_button := Button.new()
	back_button.text = "← 一覧へ戻る"
	back_button.pressed.connect(_on_npc_detail_back_pressed)
	npc_detail_view.add_child(back_button)

	# タッチUIはボタンが高く、身元+スキル訓練6行+転職欄が画面の高さ(論理648px)に収まらず、転職欄が
	# 画面外に切れていた(2026-09-19、実機で発見)。「戻る」は常に押せるよう固定し、それ以外を
	# スクロールできる領域に入れる。デスクトップでは収まるのでスクロールバーは出ない。
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	npc_detail_view.add_child(detail_scroll)

	var detail_body := VBoxContainer.new()
	detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail_body)

	var identity_row := HBoxContainer.new()
	detail_body.add_child(identity_row)

	npc_detail_portrait = PanelContainer.new()
	npc_detail_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	npc_detail_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN # 隣の文章の高さに合わせて縦に伸びず、正方形のままにする
	npc_detail_portrait.clip_contents = true
	identity_row.add_child(npc_detail_portrait)

	var identity_col := VBoxContainer.new()
	identity_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_row.add_child(identity_col)

	npc_detail_label = Label.new()
	npc_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	identity_col.add_child(npc_detail_label)

	npc_job_label = Label.new()
	npc_job_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	npc_job_label.modulate = Color(1, 1, 1, 0.85)
	identity_col.add_child(npc_job_label)

	var skill_label := Label.new()
	skill_label.text = "スキル訓練"
	detail_body.add_child(skill_label)

	skill_level_labels.clear()
	for skill in SkillTypes.all_skills():
		var row := HBoxContainer.new()
		detail_body.add_child(row)

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

	# 転職(design.md 4.8節)。「転職の秘薬」を所持している場合のみ押せる(_refresh_npc_detailで
	# 有効/無効を切り替える)。転職すると装備は自動で外れる(Npcs.change_job参照)ため、
	# 武器防具屋で新ジョブに合った装備を買い直す前提。
	var reclass_row := HBoxContainer.new()
	detail_body.add_child(reclass_row)

	reclass_option = OptionButton.new()
	for job in Jobs.all_jobs():
		reclass_option.add_item(Jobs.JOB_NAMES[job])
		reclass_option.set_item_metadata(reclass_option.item_count - 1, job)
	reclass_option.select(0) # ドロップダウンを一度も開かずに押された場合でもselectedが-1にならないようにする
	reclass_row.add_child(reclass_option)

	reclass_button = Button.new()
	reclass_button.text = "転職する(要: 転職の秘薬)"
	reclass_button.pressed.connect(_on_reclass_pressed)
	reclass_row.add_child(reclass_button)

## 一覧ビューを表示する(NPC管理パネルを開いた時の既定表示)。
func _show_npc_roster_view() -> void:
	npc_roster_view.visible = true
	npc_detail_view.visible = false

## 詳細ビューを表示する(一覧でNPCを選んだ時、またはマップのNPCアイコンから直接開いた時)。
func _show_npc_detail_view() -> void:
	npc_roster_view.visible = false
	npc_detail_view.visible = true

func _on_npc_detail_back_pressed() -> void:
	_refresh_roster() # 詳細側での訓練/割り当て変更をカードに反映してから一覧へ戻る
	_show_npc_roster_view()

## NPC管理パネルを開く共通処理。show_detailがtrueなら選択中NPCの詳細から始める
## (マップのNPCアイコンをクリックした場合)。falseなら一覧ビューから始める
## (サイドバーの「NPC管理」ボタンから開いた場合。一覧を中心に見せるため、以前選択して
## いたNPCがあっても毎回一覧からにする)。
func _open_npc_panel(show_detail: bool) -> void:
	_refresh_roster()
	_refresh_facility_button()
	if show_detail:
		_refresh_npc_detail()
		_show_npc_detail_view()
	else:
		_show_npc_roster_view()
	_open_modal(npc_panel)

func _on_open_npc_panel_pressed() -> void:
	_open_npc_panel(false)

func _on_roster_card_pressed(npc_id: int) -> void:
	_selected_npc_id = npc_id
	_refresh_npc_detail()
	_show_npc_detail_view()

## ジョブ・固有スキル・装備・戦力(design.md 4.8/6.2節)込みの身元表示。担当セクション割り当てや
## 完全踏破後の設定はパーティ単位の操作になったため、ここには所属パーティ名のみ表示する
## (詳しくは「パーティ」パネルへ)。
func _refresh_npc_detail() -> void:
	if _selected_npc_id < 0 or Npcs.get_npc(_selected_npc_id).is_empty():
		npc_detail_label.text = "左の一覧からNPCを選択してください"
		npc_job_label.text = ""
		for skill in skill_level_labels.keys():
			skill_level_labels[skill].text = ""
		reclass_button.disabled = true
		return
	var npc := Npcs.get_npc(_selected_npc_id)
	var party_id: int = npc["party_id"]
	var party_name: String = Parties.get_party(party_id).get("name", "なし") if party_id != -1 else "なし"
	npc_detail_label.text = "%s (血筋: %s)\n所属パーティ: %s / HP: %d/%d / 状態: %s" % [
		npc["name"], npc["innate_traits"].get("bloodline", "-"), party_name, int(npc["hp"]), int(npc["max_hp"]),
		_npc_status_text(npc)]

	for child in npc_detail_portrait.get_children():
		npc_detail_portrait.remove_child(child)
		child.queue_free()
	var portrait_bg := StyleBoxFlat.new()
	portrait_bg.bg_color = _bloodline_color(npc["innate_traits"].get("bloodline", ""))
	portrait_bg.set_corner_radius_all(6)
	npc_detail_portrait.add_theme_stylebox_override("panel", portrait_bg)
	npc_detail_portrait.add_child(_create_portrait_content(npc))

	var unique: Dictionary = npc.get("unique_skill", {})
	var weapon_text := "未装備"
	if npc["equipped_weapon"].has("tier"):
		weapon_text = Equipment.item_name(npc["equipped_weapon"]["tier"], Equipment.WEAPON_TYPE_NAMES[Jobs.JOB_WEAPON_TYPE[npc["job"]]])
	var armor_text := "未装備"
	if npc["equipped_armor"].has("tier"):
		armor_text = Equipment.item_name(npc["equipped_armor"]["tier"], Equipment.ARMOR_CATEGORY_NAMES[Jobs.JOB_ARMOR_CATEGORY[npc["job"]]])
	npc_job_label.text = "ジョブ: %s / 固有スキル: %s(%s)\n装備: %s / %s / 戦力: %d" % [
		Jobs.JOB_NAMES[npc["job"]], unique.get("name", "-"), unique.get("description", ""),
		weapon_text, armor_text, Npcs.power(_selected_npc_id)]

	for skill in skill_level_labels.keys():
		var level := Npcs.skill_level(_selected_npc_id, skill)
		skill_level_labels[skill].text = "Lv%d → コスト%d" % [level, Economy.training_cost(level)]

	reclass_button.disabled = not Items.has_item(_selected_npc_id, "reclass_elixir")

## 探索中/回復中(あと何日か)/未所属を文字にする。パーティ単位の状態(parties.gd)を
## そのNPCの所属パーティから読む。
func _npc_status_text(npc: Dictionary) -> String:
	var party_id: int = npc["party_id"]
	if party_id == -1:
		return "未所属"
	var party := Parties.get_party(party_id)
	if party.is_empty() or int(party.get("status", Parties.Status.IDLE)) == Parties.Status.IDLE:
		return "待機中(未割当)"
	return _party_status_text(party) # RECOVERING/EXPLORINGの文言は_party_status_text()と共通化

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

## 転職(design.md 4.8節)。「転職の秘薬」を消費し、選択したジョブへ切り替える
## (装備は自動で外れる。Npcs.change_job参照)。
func _on_reclass_pressed() -> void:
	if _selected_npc_id < 0:
		return
	if reclass_option.selected < 0:
		return
	var new_job: int = reclass_option.get_item_metadata(reclass_option.selected)
	# 選択内容を検証できてから初めてアイテムを消費する(検証失敗後にアイテムだけ失う事故を防ぐ)。
	if not Items.consume(_selected_npc_id, "reclass_elixir"):
		return
	Npcs.change_job(_selected_npc_id, new_job)
	_refresh_roster()
	_refresh_npc_detail()

## パーティ編成パネル(design.md 4.7節)。NPC管理パネルと同じ一覧/詳細の2画面構成。
## 一覧ビュー: 既存パーティのカード一覧+「新しいパーティを編成」の簡易選択。
## 詳細ビュー: 並び順(戦闘での対戦順)・担当セクション割り当て・予測・完全踏破後の設定
## (旧NPC管理パネルの[担当]タブから移設。担当割り当ての単位がNPCからパーティに変わったため)。
func _build_party_ui() -> void:
	party_panel = PanelContainer.new()
	party_panel.set_anchors_preset(Control.PRESET_CENTER)
	party_panel.offset_left = -500
	party_panel.offset_top = -300
	party_panel.offset_right = 500
	party_panel.offset_bottom = 300
	party_panel.visible = false
	add_child(party_panel)

	var col := VBoxContainer.new()
	party_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "パーティ編成"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(party_panel))
	header.add_child(close_button)

	_build_party_roster_view(col)
	_build_party_detail_view(col)

func _build_party_roster_view(col: VBoxContainer) -> void:
	party_roster_view = VBoxContainer.new()
	party_roster_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(party_roster_view)

	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_roster_view.add_child(roster_scroll)

	party_grid = GridContainer.new()
	party_grid.columns = 3
	party_grid.add_theme_constant_override("h_separation", 10)
	party_grid.add_theme_constant_override("v_separation", 10)
	roster_scroll.add_child(party_grid)

	var form_label := Label.new()
	form_label.text = "新しいパーティを編成する(未所属NPCから最大%d人を選択)" % Parties.MAX_PARTY_SIZE
	form_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	party_roster_view.add_child(form_label)

	party_form_list = ItemList.new()
	party_form_list.custom_minimum_size = Vector2(0, 100)
	party_form_list.select_mode = ItemList.SELECT_MULTI
	party_roster_view.add_child(party_form_list)

	var form_button := Button.new()
	form_button.text = "選択したNPCでパーティを編成する"
	form_button.pressed.connect(_on_form_party_pressed)
	party_roster_view.add_child(form_button)

	party_form_status_label = Label.new()
	party_form_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	party_form_status_label.modulate = Color(1, 1, 1, 0.8)
	party_roster_view.add_child(party_form_status_label)

func _build_party_detail_view(col: VBoxContainer) -> void:
	party_detail_view = VBoxContainer.new()
	party_detail_view.visible = false
	party_detail_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(party_detail_view)

	var detail_header := HBoxContainer.new()
	party_detail_view.add_child(detail_header)
	var back_button := Button.new()
	back_button.text = "← 一覧へ戻る"
	back_button.pressed.connect(_on_party_detail_back_pressed)
	detail_header.add_child(back_button)
	var detail_spacer := Control.new()
	detail_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_header.add_child(detail_spacer)
	var disband_button := Button.new()
	disband_button.text = "パーティを解散する"
	disband_button.pressed.connect(_on_disband_party_pressed)
	detail_header.add_child(disband_button)

	disband_confirm = ConfirmationDialog.new()
	disband_confirm.confirmed.connect(_on_disband_party_confirmed)
	add_child(disband_confirm)

	party_detail_label = Label.new()
	party_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	party_detail_view.add_child(party_detail_label)

	var order_label := Label.new()
	order_label.text = "並び順(戦闘での対戦順。上が先頭。先頭に立つ間だけ効果を発揮する固有スキルもある)"
	order_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	party_detail_view.add_child(order_label)

	party_member_list = ItemList.new()
	party_member_list.custom_minimum_size = Vector2(0, 90)
	party_detail_view.add_child(party_member_list)

	var order_actions := HBoxContainer.new()
	party_detail_view.add_child(order_actions)
	var move_up_button := Button.new()
	move_up_button.text = "↑ 上へ"
	move_up_button.pressed.connect(_on_move_member_pressed.bind(-1))
	order_actions.add_child(move_up_button)
	var move_down_button := Button.new()
	move_down_button.text = "↓ 下へ"
	move_down_button.pressed.connect(_on_move_member_pressed.bind(1))
	order_actions.add_child(move_down_button)

	var section_label := Label.new()
	section_label.text = "担当セクションの割り当て(エリアごとに折り畳めます)"
	section_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	party_detail_view.add_child(section_label)

	section_tree = Tree.new()
	section_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section_tree.hide_root = true
	party_detail_view.add_child(section_tree)

	var section_actions := HBoxContainer.new()
	party_detail_view.add_child(section_actions)

	var assign_button := Button.new()
	assign_button.text = "割り当て"
	assign_button.pressed.connect(_on_assign_to_section_pressed)
	_apply_primary_button_style(assign_button) # 2026-09-14: 「割り当てボタンを目立たせる」という要望への対応
	section_actions.add_child(assign_button)

	var view_thread_button := Button.new()
	view_thread_button.text = "ログ"
	view_thread_button.pressed.connect(_on_view_thread_pressed)
	section_actions.add_child(view_thread_button)

	var forecast_button := Button.new()
	forecast_button.text = "予測"
	forecast_button.pressed.connect(_on_forecast_pressed)
	section_actions.add_child(forecast_button)

	section_forecast_label = Label.new()
	section_forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	section_forecast_label.modulate = Color(1, 1, 1, 0.85)
	party_detail_view.add_child(section_forecast_label)

	# 完全踏破後の挙動(留まって収入源として維持するか、次の未踏破セクションへ自動で移るか)。
	# パーティごとに設定できる(exploration.gdのpost_clear_behavior参照)。
	var post_clear_row := HBoxContainer.new()
	party_detail_view.add_child(post_clear_row)

	var post_clear_label := Label.new()
	post_clear_label.text = "完全踏破後:"
	post_clear_row.add_child(post_clear_label)

	var post_clear_group := ButtonGroup.new()
	var stay_button := Button.new()
	stay_button.text = "ループ"
	stay_button.tooltip_text = "留まる(収入維持)"
	stay_button.toggle_mode = true
	stay_button.button_group = post_clear_group
	stay_button.pressed.connect(_on_post_clear_behavior_pressed.bind(Parties.PostClearBehavior.STAY))
	post_clear_row.add_child(stay_button)
	post_clear_behavior_buttons[Parties.PostClearBehavior.STAY] = stay_button

	var move_on_button := Button.new()
	move_on_button.text = "先へ進む"
	move_on_button.tooltip_text = "次のセクションへ自動移動"
	move_on_button.toggle_mode = true
	move_on_button.button_group = post_clear_group
	move_on_button.pressed.connect(_on_post_clear_behavior_pressed.bind(Parties.PostClearBehavior.MOVE_ON))
	post_clear_row.add_child(move_on_button)
	post_clear_behavior_buttons[Parties.PostClearBehavior.MOVE_ON] = move_on_button

func _show_party_roster_view() -> void:
	party_roster_view.visible = true
	party_detail_view.visible = false

func _show_party_detail_view() -> void:
	party_roster_view.visible = false
	party_detail_view.visible = true

func _on_party_detail_back_pressed() -> void:
	_refresh_party_roster()
	_show_party_roster_view()

## パーティ解散(design.md 4.7節): 装備・スキル経験値・固有スキルはNPC個体側に残るため、
## 解散してもメンバーの育成は失われない。メンバーは全員未所属(party_id=-1)に戻り、
## 別のパーティへ再編成できる。取り消せない操作なので確認ダイアログを挟む
## (新規プレイ/スロット削除と同じConfirmationDialogのパターン)。
func _on_disband_party_pressed() -> void:
	if _selected_party_id < 0:
		return
	var party := Parties.get_party(_selected_party_id)
	if party.is_empty():
		return
	_pending_disband_party_id = _selected_party_id
	disband_confirm.dialog_text = "「%s」を解散します。メンバーは全員未所属に戻ります(スキルや装備は失われません)。よろしいですか？" % party["name"]
	disband_confirm.popup_centered()

func _on_disband_party_confirmed() -> void:
	Parties.disband(_pending_disband_party_id)
	_pending_disband_party_id = -1
	_selected_party_id = -1
	_refresh_party_roster()
	_show_party_roster_view()
	_refresh_map()

## パーティパネルを開く共通処理。party_idを指定すればそのパーティの詳細から始める
## (マップのパーティアイコンをクリックした場合)。省略時は一覧ビューから始める。
func _open_party_panel(party_id: int = -1) -> void:
	_populate_section_tree()
	_refresh_party_roster()
	if party_id != -1:
		_selected_party_id = party_id
		_refresh_party_detail()
		_show_party_detail_view()
	else:
		_show_party_roster_view()
	_open_modal(party_panel)

func _on_open_party_panel_pressed() -> void:
	_open_party_panel()

## セクション選択肢をエリア→セクションの2階層に組む(旧NPC管理パネルの同名関数を移設。
## WorldMapのみに依存する汎用ロジックなので内容は変更なし)。割り当て先として選べるのは、
## 既に誰かが到達しているか、隣接する突破済みノードから発見を試みられるセクションだけにする
## (WorldMap.is_section_reachable)。
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

## パーティを切り替えるたびに、担当セクションのTreeもそのパーティの現在の割り当て先を
## 選択済みにしておく。
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

func _refresh_party_roster() -> void:
	for child in party_grid.get_children():
		party_grid.remove_child(child)
		child.queue_free()
	var group := ButtonGroup.new()
	var has_unassigned := false
	for party in Parties.get_parties():
		party_grid.add_child(_create_party_card(party, group))
		if party["assigned_section"] == "":
			has_unassigned = true

	party_form_list.clear()
	for npc in Npcs.get_roster():
		if npc["party_id"] == -1:
			party_form_list.add_item("%s(%s)" % [npc["name"], Jobs.JOB_NAMES[npc["job"]]])
			party_form_list.set_item_metadata(party_form_list.item_count - 1, npc["id"])
	party_form_status_label.text = ""

	# サイドバーの「パーティ」ボタン自体も、未割当のパーティが1つでもあれば赤字で警告する
	# (2026-09-14、「未割当のパーティが赤く光る」という要望への対応。パネルを開かなくても
	# 対応が必要なことに気付けるようにする)。
	if has_unassigned:
		party_button.text = "パーティ ⚠未割当あり"
		party_button.add_theme_color_override("font_color", Color(1.0, 0.42, 0.36))
		party_button.add_theme_color_override("font_hover_color", Color(1.0, 0.55, 0.5))
	else:
		party_button.text = "パーティ"
		party_button.remove_theme_color_override("font_color")
		party_button.remove_theme_color_override("font_hover_color")

func _create_party_card(party: Dictionary, group: ButtonGroup) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = group
	card.custom_minimum_size = Vector2(220, 90)
	card.autowrap_mode = TextServer.AUTOWRAP_WORD
	var member_names := []
	for npc_id in party["member_ids"]:
		member_names.append(String(Npcs.get_npc(npc_id).get("name", "?")))
	var is_unassigned: bool = party["assigned_section"] == ""
	var section_name := "未割当"
	if not is_unassigned and WorldMap.sections.has(party["assigned_section"]):
		section_name = WorldMap.sections[party["assigned_section"]]["name"]
	card.text = "%s\n%s\n担当: %s%s" % [party["name"], "・".join(member_names), section_name, "  ⚠" if is_unassigned else ""]
	if is_unassigned:
		_apply_unassigned_warning_style(card)
	card.pressed.connect(_on_party_card_pressed.bind(party["id"]))
	return card

func _on_party_card_pressed(party_id: int) -> void:
	_selected_party_id = party_id
	_refresh_party_detail()
	_show_party_detail_view()

func _on_form_party_pressed() -> void:
	var selected := party_form_list.get_selected_items()
	if selected.is_empty():
		party_form_status_label.text = "NPCを選択してください"
		return
	if selected.size() > Parties.MAX_PARTY_SIZE:
		party_form_status_label.text = "パーティは最大%d人までです" % Parties.MAX_PARTY_SIZE
		return
	var member_ids := []
	for index in selected:
		member_ids.append(party_form_list.get_item_metadata(index))
	var party_id := Parties.form_party(member_ids)
	if party_id == -1:
		party_form_status_label.text = "パーティを編成できませんでした"
		return
	_refresh_party_roster()
	party_form_status_label.text = "パーティを編成しました"

func _refresh_party_detail() -> void:
	if _selected_party_id < 0 or Parties.get_party(_selected_party_id).is_empty():
		party_detail_label.text = "左の一覧からパーティを選択してください"
		section_forecast_label.text = ""
		party_member_list.clear()
		for behavior in post_clear_behavior_buttons.keys():
			post_clear_behavior_buttons[behavior].button_pressed = false
		return
	section_forecast_label.text = ""
	var party := Parties.get_party(_selected_party_id)
	var section_id: String = party["assigned_section"]
	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else "未割当"
	party_detail_label.text = "%s / 担当: %s / 状態: %s / 戦力: %d" % [
		party["name"], section_name, _party_status_text(party), Parties.power(_selected_party_id)]

	party_member_list.clear()
	for npc_id in party["member_ids"]:
		var npc := Npcs.get_npc(npc_id)
		if npc.is_empty():
			continue
		party_member_list.add_item("%s(%s) HP:%d/%d" % [npc["name"], Jobs.JOB_NAMES[npc["job"]], int(npc["hp"]), int(npc["max_hp"])])

	var behavior: int = party["post_clear_behavior"]
	if post_clear_behavior_buttons.has(behavior):
		post_clear_behavior_buttons[behavior].button_pressed = true
	_select_current_section_in_tree(section_id)

## 探索中/回復中(あと何日か)/未割当を文字にする(design.md 5.4節、パーティ全体で足並みを揃える)。
func _party_status_text(party: Dictionary) -> String:
	match int(party["status"]):
		Parties.Status.RECOVERING:
			return "回復中(あと%d日)" % max(0, party["recovering_until_day"] - TimeSystem.current_day)
		Parties.Status.EXPLORING:
			return "探索中"
		_:
			return "未割当"

## 並び順の入れ替え(direction: -1で上、+1で下)。design.md 5.4節「先頭のメンバーが戦線を
## 離脱すると次の並び順のメンバーが引き継ぐ」ため、並び順が戦術に直結する。
func _on_move_member_pressed(direction: int) -> void:
	if _selected_party_id < 0:
		return
	var party := Parties.get_party(_selected_party_id)
	if party.is_empty():
		return
	var selected := party_member_list.get_selected_items()
	if selected.is_empty():
		return
	var index: int = selected[0]
	var order: Array = party["member_ids"].duplicate()
	var target := index + direction
	if target < 0 or target >= order.size():
		return
	var tmp = order[index]
	order[index] = order[target]
	order[target] = tmp
	Parties.reorder(_selected_party_id, order)
	_refresh_party_detail()
	party_member_list.select(target)

func _on_post_clear_behavior_pressed(behavior: int) -> void:
	if _selected_party_id < 0:
		return
	Parties.set_post_clear_behavior(_selected_party_id, behavior)

func _on_assign_to_section_pressed() -> void:
	if _selected_party_id < 0:
		return
	var selected_item := section_tree.get_selected()
	if selected_item == null:
		return
	var section_id = selected_item.get_metadata(0)
	if section_id == null:
		return
	_assign_party_to_section(_selected_party_id, section_id)

## パーティ割り当ての共通処理。パーティパネルの「割り当て」ボタン(_on_assign_to_section_pressed)、
## マップのセクション名ボタンから開く割り当てモーダル(_on_section_assign_row_pressed)の
## 両方から使う(2026-09-14、「選んだセクションからパーティ割り当てを可能にする」という
## 要望への対応で後者を新設した際、処理を一本化した)。
func _assign_party_to_section(party_id: int, section_id: String) -> void:
	Parties.assign_section(party_id, section_id)
	_refresh_party_roster()
	_refresh_party_detail()
	_refresh_map()
	_maybe_show_assignment_followup_tutorial()

## 「予測」ボタン: 選択中のパーティをTreeで選んだセクションに置いた場合の、実際の配置転換を
## 行わずに今月の見込みだけを計算して表示する(Exploration.forecast_section参照)。
func _on_forecast_pressed() -> void:
	if _selected_party_id < 0:
		return
	var selected_item := section_tree.get_selected()
	if selected_item == null:
		return
	var section_id = selected_item.get_metadata(0)
	if section_id == null:
		return
	var result := Exploration.forecast_section(_selected_party_id, section_id)
	if result["risk_node_name"] == "":
		section_forecast_label.text = "予測報酬(1ヶ月): 約%d資金 / 撤退リスク: なし" % result["predicted_income"]
	else:
		section_forecast_label.text = "予測報酬(1ヶ月): 約%d資金(通常時は約%d資金) / 撤退リスク: 約%d%%(「%s」で撤退の恐れ)" % [
			result["predicted_income"], result["base_income"], roundi(result["retreat_probability"] * 100), result["risk_node_name"]]

## 武器防具屋パネル(design.md 6.2節)。選んだNPCのジョブに応じた武器種別・防具カテゴリの
## 材質等級ボタンを並べ、購入するとその場で装備が切り替わる(既に装備中の等級はボタンを無効化)。
func _build_shop_ui() -> void:
	shop_panel = PanelContainer.new()
	shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	shop_panel.offset_left = -320
	shop_panel.offset_top = -260
	shop_panel.offset_right = 320
	shop_panel.offset_bottom = 260
	shop_panel.visible = false
	add_child(shop_panel)

	var col := VBoxContainer.new()
	shop_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "武器防具屋"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(shop_panel))
	header.add_child(close_button)

	shop_npc_option = OptionButton.new()
	shop_npc_option.item_selected.connect(_on_shop_npc_selected)
	col.add_child(shop_npc_option)

	var weapon_label := Label.new()
	weapon_label.text = "武器"
	col.add_child(weapon_label)
	shop_weapon_row = HBoxContainer.new()
	col.add_child(shop_weapon_row)

	var armor_label := Label.new()
	armor_label.text = "防具"
	col.add_child(armor_label)
	shop_armor_row = HBoxContainer.new()
	col.add_child(shop_armor_row)

	shop_status_label = Label.new()
	shop_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(shop_status_label)

func _on_open_shop_pressed() -> void:
	_refresh_shop_npc_list()
	_open_modal(shop_panel)

func _refresh_shop_npc_list() -> void:
	shop_npc_option.clear()
	var roster := Npcs.get_roster()
	for npc in roster:
		shop_npc_option.add_item("%s(%s)" % [npc["name"], Jobs.JOB_NAMES[npc["job"]]])
		shop_npc_option.set_item_metadata(shop_npc_option.item_count - 1, npc["id"])
	_shop_selected_npc_id = shop_npc_option.get_item_metadata(0) if not roster.is_empty() else -1
	_refresh_shop_offers()

func _on_shop_npc_selected(index: int) -> void:
	_shop_selected_npc_id = shop_npc_option.get_item_metadata(index)
	_refresh_shop_offers()

func _refresh_shop_offers() -> void:
	for child in shop_weapon_row.get_children():
		shop_weapon_row.remove_child(child)
		child.queue_free()
	for child in shop_armor_row.get_children():
		shop_armor_row.remove_child(child)
		child.queue_free()
	shop_status_label.text = ""

	if _shop_selected_npc_id == -1:
		return
	var npc := Npcs.get_npc(_shop_selected_npc_id)
	var weapon_kind_name: String = Equipment.WEAPON_TYPE_NAMES[Jobs.JOB_WEAPON_TYPE[npc["job"]]]
	var armor_kind_name: String = Equipment.ARMOR_CATEGORY_NAMES[Jobs.JOB_ARMOR_CATEGORY[npc["job"]]]
	var current_weapon_tier: int = npc["equipped_weapon"].get("tier", -1)
	var current_armor_tier: int = npc["equipped_armor"].get("tier", -1)

	for tier in Equipment.all_tiers():
		shop_weapon_row.add_child(_create_shop_tier_button(tier, weapon_kind_name, "weapon", current_weapon_tier))
	for tier in Equipment.all_tiers():
		shop_armor_row.add_child(_create_shop_tier_button(tier, armor_kind_name, "armor", current_armor_tier))

## current_tierは今そのNPCが装備している等級(未装備なら-1)。Tierは等級が上がるほど戦力・価格が
## 単調に増える設計(equipment.gd参照)なので、現在の装備より下位の等級は「買っても損しかない」
## 選択肢であり、押せないようにする(2026-09-15、「武器防具にメリットがないのにランク下の
## ものを買えてしまう」というバグ報告への対応)。current_tier==-1(転職直後で未装備等)の場合は
## どの等級も下位に当たらないため、この制限は効かない。
func _create_shop_tier_button(tier: int, kind_name: String, slot: String, current_tier: int) -> Button:
	var button := Button.new()
	var price := Equipment.price(tier)
	var is_equipped := tier == current_tier
	var is_downgrade := tier < current_tier
	button.text = "%s\n+%d 戦力\n%d資金" % [Equipment.item_name(tier, kind_name), Equipment.power_bonus(tier), price]
	button.custom_minimum_size = Vector2(90, 60)
	button.disabled = is_equipped or is_downgrade or not Economy.can_afford(price)
	if is_equipped:
		button.tooltip_text = "装備中"
	elif is_downgrade:
		button.tooltip_text = "現在の装備より下位のため、購入するメリットがありません"
	button.pressed.connect(_on_buy_equipment_pressed.bind(slot, tier))
	return button

func _on_buy_equipment_pressed(slot: String, tier: int) -> void:
	if _shop_selected_npc_id == -1:
		return
	var price := Equipment.price(tier)
	if not Economy.spend(price):
		shop_status_label.text = "資金が足りません(価格: %d)" % price
		return
	Npcs.equip(_shop_selected_npc_id, slot, tier)
	_refresh_funds()
	_refresh_shop_offers()
	shop_status_label.text = "装備しました"

## セーブスロット管理UI(design.md 8.2「スキーマ再プレイ」)。既存スロットの一覧・切替と、
## スキーマDBから新規プレイを開始する導線をここにまとめる。
func _build_slot_ui() -> void:
	slot_panel = PanelContainer.new()
	slot_panel.set_anchors_preset(Control.PRESET_CENTER)
	slot_panel.offset_left = -320
	slot_panel.offset_top = -260
	slot_panel.offset_right = 320
	slot_panel.offset_bottom = 260
	slot_panel.visible = false
	add_child(slot_panel)

	var col := VBoxContainer.new()
	slot_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "セーブ/ロード"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(slot_panel))
	header.add_child(close_button)

	slot_list = ItemList.new()
	# タッチUIはボタンが高い分、パネル全体が画面の高さ(約650px)を超えてしまうため、一覧の最小高を詰める
	# (一覧自体はスクロールできるので、スロットが多くても操作はできる)。
	slot_list.custom_minimum_size = Vector2(0, 110 if _touch_ui else 220)
	slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(slot_list)

	# スロットに名前を付けられるように(2026-09-14)。1つの入力欄を、選択中スロットの
	# 「名前を変更する」と、次に「新規プレイを開始する」際の名前付けの両方で使い回す
	# (どちらのボタンを押した時点のテキストを使うかは各ハンドラ側で決まる)。
	var name_row := HBoxContainer.new()
	col.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "名前:"
	name_row.add_child(name_label)
	slot_name_input = LineEdit.new()
	slot_name_input.placeholder_text = "スロット名(選択中の変更 / 次の新規プレイ用、省略可)"
	slot_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(slot_name_input)
	var rename_button := Button.new()
	rename_button.text = "選択中の名前を変更"
	rename_button.tooltip_text = "一覧で選択中のスロットの名前を、上の入力欄の内容に変更する"
	rename_button.pressed.connect(_on_rename_slot_pressed)
	name_row.add_child(rename_button)

	# ボタンを全部縦に並べると数が増えるたびにパネルの下端からはみ出してしまっていたため、
	# 2列に分けて縦の高さを抑える。左列は「今どのスロットに対しても行う」保存系の操作、
	# 右列はリストで選択したスロットに対する操作+新規プレイ、という分担。
	var actions_row := HBoxContainer.new()
	col.add_child(actions_row)

	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_row.add_child(left_col)

	# オートセーブ(日次/終了時)とは別に、プレイヤーが好きなタイミングで明示的に保存できる
	# 手段が無く、「新規プレイを開始する」の内部処理(離れる前のスロットを保存)頼みになって
	# いた。分岐前のチェックポイントとして能動的に保存したい、という要望への対応。
	var manual_save_button := Button.new()
	manual_save_button.text = "今すぐセーブする"
	manual_save_button.pressed.connect(_on_manual_save_pressed)
	left_col.add_child(manual_save_button)

	# 「新規プレイ」は進行をゼロから作り直してしまうため、今の進行を保ったまま別スロットへ
	# 分岐させたい(色々試す前のチェックポイントを残したい)場合の手段が無かった。ファイルを
	# そのまま複製するだけなので確認ダイアログは挟まず即実行し、結果はステータス表示で伝える。
	var duplicate_button := Button.new()
	duplicate_button.text = "進行を複製する(分岐用)"
	duplicate_button.tooltip_text = "現在の進行を複製する(分岐用の新規スロットを作る)"
	duplicate_button.pressed.connect(_on_duplicate_slot_pressed)
	left_col.add_child(duplicate_button)

	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_row.add_child(right_col)

	var open_button := Button.new()
	open_button.text = "このスロットをロードする"
	open_button.pressed.connect(_on_open_slot_pressed)
	right_col.add_child(open_button)

	var delete_button := Button.new()
	delete_button.text = "選択したスロットを削除する"
	delete_button.pressed.connect(_on_delete_slot_pressed)
	right_col.add_child(delete_button)

	var new_game_button := Button.new()
	new_game_button.text = "新規プレイを開始する"
	new_game_button.pressed.connect(func(): new_game_confirm.popup_centered())
	right_col.add_child(new_game_button)

	# オートセーブを切りたい(手動セーブだけで管理したい)という要望への対応。
	# チェック状態はworldseeker_meta.cfgに永続化し、次回起動後も引き継ぐ(SaveSystem.autosave_enabled)。
	autosave_checkbox = CheckBox.new()
	autosave_checkbox.text = "オートセーブを有効にする(日次/終了時)"
	autosave_checkbox.button_pressed = SaveSystem.autosave_enabled
	autosave_checkbox.toggled.connect(SaveSystem.set_autosave_enabled)
	col.add_child(autosave_checkbox)

	# 「イベント確認が出来ない」という要望への対応(2026-09-14)。一度見ると二度と出ない
	# 導入/初雇用/初撤退/初割り当ての説明会話4種を、確認のためだけに何度でも見返せるように、
	# 「見た」フラグを丸ごとリセットするボタンを設定(セーブスロットパネル)に置く。
	# セーブデータ自体(資金/NPC等)には触れない。
	var reset_tutorial_button := Button.new()
	reset_tutorial_button.text = "イベント会話をリセットする(確認用)"
	reset_tutorial_button.tooltip_text = "導入/初雇用/初撤退/初割り当ての説明会話を、もう一度見られるようにします"
	reset_tutorial_button.pressed.connect(_on_reset_tutorials_pressed)
	col.add_child(reset_tutorial_button)

	manual_save_status_label = Label.new()
	manual_save_status_label.modulate = Color(1, 1, 1, 0.75)
	col.add_child(manual_save_status_label)

	new_game_confirm = ConfirmationDialog.new()
	new_game_confirm.dialog_text = "現在の進行とは別に、新しいセーブスロットでゼロから始めます。よろしいですか？"
	new_game_confirm.confirmed.connect(_on_new_game_confirmed)
	add_child(new_game_confirm)

	delete_slot_confirm = ConfirmationDialog.new()
	delete_slot_confirm.confirmed.connect(_on_delete_slot_confirmed)
	add_child(delete_slot_confirm)

func _on_open_slots_pressed() -> void:
	_refresh_slot_list()
	manual_save_status_label.text = ""
	slot_name_input.text = ""
	autosave_checkbox.button_pressed = SaveSystem.autosave_enabled
	_open_modal(slot_panel)

func _refresh_slot_list() -> void:
	slot_list.clear()
	for slot in SaveSystem.list_slots():
		var active_mark := " (現在)" if slot["slot_id"] == SaveSystem.current_slot_id else ""
		var label: String = slot["name"] if slot["name"] != "" else "スロット%d" % slot["slot_id"]
		var idx := slot_list.item_count
		slot_list.add_item("%s%s — 資金%d / Day%d / NPC%d人" % [
			label, active_mark, slot["funds"], slot["day"], slot["npc_count"]])
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
	SaveSystem.create_new_slot(slot_name_input.text.strip_edges())
	_refresh_all()
	_close_modal(slot_panel)

func _on_rename_slot_pressed() -> void:
	var selected := slot_list.get_selected_items()
	if selected.is_empty():
		manual_save_status_label.text = "名前を変更するスロットを一覧から選択してください"
		return
	var slot_id: int = slot_list.get_item_metadata(selected[0])
	if SaveSystem.rename_slot(slot_id, slot_name_input.text.strip_edges()):
		manual_save_status_label.text = "スロット%dの名前を変更しました" % slot_id
		_refresh_slot_list()
	else:
		manual_save_status_label.text = "名前の変更に失敗しました"

func _on_manual_save_pressed() -> void:
	SaveSystem.save_game()
	_refresh_slot_list()
	manual_save_status_label.text = "保存しました(%s)" % TimeSystem.format_date()

func _on_duplicate_slot_pressed() -> void:
	var new_id := SaveSystem.duplicate_current_slot()
	if new_id == -1:
		manual_save_status_label.text = "複製に失敗しました"
		return
	_refresh_slot_list()
	manual_save_status_label.text = "スロット%dとして複製しました(現在のスロットのまま続けられます)" % new_id

## 一度見ると二度と出ない説明用イベント会話4種を、確認用に未視聴の状態へ戻す。導入会話
## (INTRO_TUTORIAL_PART1_SCRIPT)は起動時にしかトリガーできないため、リセット直後にこの場で
## 再生する(パネルを閉じてから再生しないとdialogue_panelが背後に隠れる。他の会話の再生箇所と
## 同じ理由)。残り3つ(初雇用/初撤退/初割り当て)は該当の操作を実際に行うと再度表示される。
func _on_reset_tutorials_pressed() -> void:
	SaveSystem.reset_tutorial_flags()
	_close_modal(slot_panel)
	EventDialogue.finished.connect(func(_o): SaveSystem.mark_tutorial_intro_seen(), CONNECT_ONE_SHOT)
	EventDialogue.play(INTRO_TUTORIAL_PART1_SCRIPT)

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
# 2026-09-14: パーティ代表アイコンの拡大(20px→40px)を枠内の専用エリアとして確保するため、
# 横幅を+48(アイコン領域分)広げた。文字表示エリア自体の幅は以前とほぼ変わらない。
const BASE_MAP_CELL_SIZE := Vector2(268, 100)
const BASE_MAP_NODE_SIZE := Vector2(248, 74)
const BASE_MAP_SECTION_GAP := 60.0
const BASE_MAP_SECTION_HEADER := 40.0 # タイトル行+担当NPCアイコン行の2段分の高さ
const BASE_MAP_SECTION_PADDING := 12.0
const BASE_MAP_OUTER_MARGIN := Vector2(20, 20)
# マップ上部にフロートで重ねているエリアタブバー(_build_ui参照)のおおよその高さ。
# ズームでは拡大縮小されない固定オーバーレイなので、_map_zoomを掛けない生の値で扱う。
const MAP_NAV_BAR_CLEARANCE := 50.0
const MAP_ZOOM_MIN := 0.4
const MAP_ZOOM_MAX := 2.2
const MAP_ZOOM_STEP := 0.15
const MAP_ICON_SIZE := 40.0 # パーティ代表アイコンの一辺(2026-09-14、20pxから2倍に拡大)

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
## design.md 5.1節(2026-09-14エリアタブ化): _active_area_idのセクションだけを描画する。
## 以前は9エリア全部を1枚のキャンバスに縦積みしていたため、マップが際限なく長大化し、
## 条件付きの支線エリアも進めないままずっと画面の奥に居座り続ける問題があった。
func _seed_demo_world() -> void:
	# ワールドの中身(エリア/セクション/フロア/イベント)はworld_data.gdが
	# オートロードとして既に流し込み済み。ここではWorldMapの内容を
	# UI(ノードグラフ)として描画するだけ。担当セクションの選択肢(section_tree)は
	# NPC管理パネルを開くたびに_populate_section_treeで組み直す。
	for child in map_canvas.get_children():
		child.queue_free()

	# _active_area_idの既定選択は_build_ui()(最初にタブボタンを作る場所)で行う。
	# _on_area_tab_pressed()もタブ切替時に呼ぶ前に自分で設定するため、この関数に来る時点では
	# 常に設定済み。
	var positions := _compute_node_positions()
	node_labels.clear()
	node_name_labels.clear()
	node_boxes.clear()
	node_centers.clear()
	node_icon_rows.clear()
	section_bounds_cache.clear()
	section_lock_icons.clear()
	section_title_buttons.clear()

	var cell_size := _map_cell_size()
	var content_size := Vector2.ZERO

	for section_id in WorldMap.sections_in_area(_active_area_id):
		var member_ids := WorldMap.nodes_in_section(section_id)
		if member_ids.is_empty():
			continue
		var bounds := _section_bounds(member_ids, positions)
		section_bounds_cache[section_id] = bounds
		_create_section_panel(section_id, bounds)
		content_size.x = max(content_size.x, bounds.position.x + bounds.size.x)
		content_size.y = max(content_size.y, bounds.position.y + bounds.size.y)

	for id in positions.keys():
		var cell_pos: Vector2 = positions[id]
		_create_node_box(id, cell_pos)
		content_size.x = max(content_size.x, cell_pos.x + cell_size.x)
		content_size.y = max(content_size.y, cell_pos.y + cell_size.y)

	# エリアをまたぐ接続(支線の分岐元など)は実際に線を引かず、分岐元ノードのそばに
	# 「→エリア名」というリンクを表示してタブ切替に誘導する(design.md 5.1節)。
	var link_counts: Dictionary = {} # node_id -> 何本目のリンクか(同じノードから複数出る場合に縦に積む)
	for id in positions.keys():
		for neighbor_id in WorldMap.neighbors(id):
			if positions.has(neighbor_id) or not WorldMap.nodes.has(neighbor_id):
				continue
			var neighbor_section: String = WorldMap.nodes[neighbor_id]["section"]
			if not WorldMap.sections.has(neighbor_section):
				continue
			var neighbor_area: String = WorldMap.sections[neighbor_section]["area"]
			if neighbor_area == "" or neighbor_area == _active_area_id:
				continue
			var link_index: int = link_counts.get(id, 0)
			link_counts[id] = link_index + 1
			var link_bottom: float = _create_area_link(id, neighbor_area, positions[id], link_index)
			content_size.y = max(content_size.y, link_bottom)

	map_canvas.custom_minimum_size = content_size + Vector2(40, 40) * _map_zoom
	map_canvas.queue_redraw()
	_refresh_map()
	_refresh_area_tabs()

## _active_area_id内のセクションだけを対象に、グリッド状の自動レイアウトを組む
## (design.md 5.1節、2026-09-14: エリアタブ化に伴い1エリア分だけのレイアウトに簡略化。
## 以前は9エリア分を縦に積み上げていたため際限なく長大化していた)。手動で位置を
## 指定しなくても、ノード数が増えてもセクション同士が重ならないようにする。
func _compute_node_positions() -> Dictionary:
	# ScrollContainerは子の負座標部分をスクロールでは見せてくれない(スクロール範囲は
	# コンテンツが(0,0)起点である前提で計算される)ため、セクション枠のパディング/ヘッダー分だけ
	# 全体を右下にずらして、どのセクション枠も座標が負にならないようにする。
	var positions := {}
	var cell_size := _map_cell_size()
	var outer_margin := BASE_MAP_OUTER_MARGIN * _map_zoom
	var section_header := BASE_MAP_SECTION_HEADER * _map_zoom
	var section_gap := BASE_MAP_SECTION_GAP * _map_zoom
	# 起動直後(スクロール位置0)でもエリア名見出しがフロートのエリアタブバーの
	# 真裏に隠れないよう、その分もあらかじめ余白として確保しておく。
	var y_offset := outer_margin.y + MAP_NAV_BAR_CLEARANCE
	for section_id in WorldMap.sections_in_area(_active_area_id):
		var member_ids := WorldMap.nodes_in_section(section_id)
		if member_ids.is_empty():
			continue
		var section_top := y_offset + section_header
		for i in range(member_ids.size()):
			var col := i % MAP_COLUMNS
			var row := i / MAP_COLUMNS
			positions[member_ids[i]] = Vector2(outer_margin.x + col * cell_size.x, section_top + row * cell_size.y)
		var rows := ceili(float(member_ids.size()) / MAP_COLUMNS)
		y_offset = section_top + rows * cell_size.y + section_gap

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

## エリアをまたぐ接続の分岐元ノードのそばに「→エリア名」の小さなリンクを表示する
## (design.md 5.1節)。クリックでそのエリアのタブに切り替わる(離れたエリアまで実際に
## 接続線を引くことはしない)。同じノードから複数本出る場合はlink_indexぶん縦に積む。
## 戻り値はこのリンクの下端Y座標(コンテンツサイズ計算用)。
func _create_area_link(node_id: String, target_area_id: String, cell_pos: Vector2, link_index: int) -> float:
	var node_size := _map_node_size()
	var link_height := 18.0 * _map_zoom
	var link := Button.new()
	link.text = "→ %s" % WorldMap.areas[target_area_id]["name"]
	link.flat = true
	link.add_theme_font_size_override("font_size", max(8, roundi(11 * _map_zoom)))
	link.modulate = Color(0.55, 0.75, 1.0, 1.0)
	link.position = cell_pos + Vector2(4, node_size.y + 2 + link_index * link_height)
	link.pressed.connect(_on_area_tab_pressed.bind(target_area_id))
	map_canvas.add_child(link)
	return link.position.y + link_height

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

	# セクション名を、ただの文字ではなく「押せるボタン」として見せる(2026-09-14、実プレイの
	# フィードバックへの対応: マップ上でセクション名が押せることが直感的に分からない、との指摘)。
	# クリックでそのセクションへのパーティ割り当てモーダル(_on_section_name_pressed)を開く。
	# 到達不可能なセクション(WorldMap.is_section_reachable=false)はdisabled=trueにする。
	# 個別に"disabled"stylebox上書きをしていないため、共有Theme(_build_theme())側の
	# 薄暗いdisabledスタイルへ自然にフォールバックし、「押せない」ことが見た目でも伝わる。
	var title_button := Button.new()
	# design.md 6.2節「推奨戦力」: セクション内で最も敵戦闘力が高い戦闘ゲートの値を、
	# パーティの戦力と比較するための大まかな目安として表示する(戦闘ゲートが無ければ表示しない)。
	# 表示しないセクションでも2行目に全角スペースを入れて、見出しボタンの高さを全セクションで揃える
	# (1行だけだと、推奨戦力ありのセクションより見出しの帯が細くなってしまう。末尾の改行だけでは
	# Buttonが空の行を数えないので、空白でも中身のある行にする)。
	var recommended := Exploration.recommended_power_for_section(section_id)
	var title_text: String = "📍 " + WorldMap.sections[section_id]["name"] + "\n"
	title_text += "推奨戦力: %d" % recommended if recommended > 0 else "　"
	title_button.position = bounds.position + Vector2(4, 2) * _map_zoom
	title_button.custom_minimum_size = Vector2(bounds.size.x - 8 * _map_zoom, 0)
	title_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_button.add_theme_font_size_override("font_size", max(9, roundi(14 * _map_zoom)))
	title_button.tooltip_text = "クリックしてこのセクションへパーティを割り当てる"
	title_button.disabled = not WorldMap.is_section_reachable(section_id)
	_apply_section_title_button_style(title_button)
	title_button.pressed.connect(_on_section_name_pressed.bind(section_id))
	map_canvas.add_child(title_button)
	# 文字は、スタイルや文字サイズの上書きを全て済ませ、ツリーに入れた後に、最後に1回だけ設定する。
	# 文字の形の計算(シェーピング)は、テーマの上書きが1つ入るたびにやり直され、1回が実機で数msかかる
	# ため、先に文字を入れておくと1つのボタンで何度も計算していた(2026-09-19、実測)。
	title_button.text = title_text
	section_title_buttons[section_id] = title_button

	# まだ誰も足を踏み入れておらず、隣接する突破済みノードも無いセクション(WorldMap.
	# is_section_reachable=false)には、枠の下に鍵アイコンを出す。表示/非表示の切り替えは
	# 到達状況が変わるたびに_refresh_mapで行うので、ここでは作るだけ(常時mapに常駐させ、
	# ダブルクリック判定は_on_map_double_clickでこの位置を直接ヒットテストする)。
	var lock_icon := Label.new()
	lock_icon.add_theme_font_size_override("font_size", max(9, roundi(12 * _map_zoom)))
	lock_icon.modulate = Color(1, 0.82, 0.35, 0.95)
	lock_icon.position = bounds.position + Vector2(6, bounds.size.y + 4 * _map_zoom)
	map_canvas.add_child(lock_icon)
	lock_icon.text = "🔒 未到達(%sで詳細)" % ("ダブルタップ" if _touch_ui else "ダブルクリック") # 文字は最後に(上と同じ理由)
	section_lock_icons[section_id] = lock_icon

func _create_node_box(id: String, cell_pos: Vector2) -> void:
	var cell_size := _map_cell_size()
	var node_size := _map_node_size()
	var margin := (cell_size - node_size) / 2.0
	var box := PanelContainer.new()
	box.position = cell_pos + margin
	box.custom_minimum_size = node_size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	box.add_child(hbox)

	# 担当パーティがどのフロアで今動いているか一目で分かるよう、枠の左側に肖像アイコンを
	# 表示する(_current_node_for_partyが選んだ代表ノードに対して1つ、_refresh_party_map_iconsが
	# 担当替えのたびに作り直す)。2026-09-14: 以前は枠の右下に小さく重ねる方式(20px)だったが
	# 視認性向上のため2倍(40px)に拡大し、重なりを避けるため枠内の専用エリアへ配置し直した。
	# box自体はmouse_filter=IGNOREだが、子のButton(パーティアイコン)は個別にクリックを拾える。
	var icon_row := HBoxContainer.new()
	icon_row.custom_minimum_size = Vector2(MAP_ICON_SIZE + 8, 0) * _map_zoom
	icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(icon_row)
	node_icon_rows[id] = icon_row

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

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

## マウスホイールでのズーム(1段階ずつ)。
func _zoom_map(zoom_in: bool, cursor_pos: Vector2) -> void:
	_set_map_zoom(_map_zoom + (MAP_ZOOM_STEP if zoom_in else -MAP_ZOOM_STEP), cursor_pos)

## マップを指定の倍率にする(範囲内に丸める)。cursor_posの直下にあったコンテンツ座標がズーム後も
## 同じ画面位置に留まるよう、レイアウト再構築後にスクロール位置を計算し直す。cursor_posは
## map_canvas内の座標(マウスのイベント位置、または画面上の位置からcanvasの位置を引いたもの)。
func _set_map_zoom(target_zoom: float, cursor_pos: Vector2) -> void:
	var old_zoom := _map_zoom
	var new_zoom := clampf(target_zoom, MAP_ZOOM_MIN, MAP_ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var viewport_pos := cursor_pos - Vector2(map_scroll.scroll_horizontal, map_scroll.scroll_vertical)
	_map_zoom = new_zoom
	_seed_demo_world()
	# 拡大で内容が大きくなった分のスクロール範囲は、放っておくと次のレイアウト更新まで反映されない。すぐ下で
	# 大きいスクロール位置を代入すると、古い(小さい)範囲に丸められて、拡大の中心がずれてしまう(ピンチで
	# 一気に大きく拡大した時に実機で起きた。ホイールは少しずつなので目立たなかった)。かといって次の
	# フレームまで待つと、丸められた位置の画面が1フレーム表示されて、位置がずれて見える。そこで、
	# スクロールバーの範囲(max_value)を、新しい内容の大きさに、その場で更新しておく。次のレイアウト更新で
	# ScrollContainerが同じ値に設定し直すので、矛盾しない(実機で確認済み)。Container.NOTIFICATION_
	# SORT_CHILDRENを送っても、この範囲は更新されなかった(実測)。
	map_scroll.get_h_scroll_bar().max_value = map_canvas.custom_minimum_size.x
	map_scroll.get_v_scroll_bar().max_value = map_canvas.custom_minimum_size.y
	var new_content_pos := cursor_pos * (new_zoom / old_zoom)
	var new_scroll := Vector2i(int(new_content_pos.x - viewport_pos.x), int(new_content_pos.y - viewport_pos.y))
	map_scroll.scroll_horizontal = new_scroll.x
	map_scroll.scroll_vertical = new_scroll.y
	# それでも、このフレームのレイアウト更新の途中で、横のスクロール位置が再構築前の範囲に丸め直されて
	# しまう(実機でフレームごとに追って確認: 直後719 → 次のフレーム221)。遅延呼び出しは、このフレームの
	# レイアウト更新(コンテナの更新は、その中で更に遅延呼び出しされる)よりも後に実行されるよう、
	# 2段にして、描画の前に位置を確定させる。
	_apply_map_scroll_deferred.call_deferred(new_scroll, 1)

func _apply_map_scroll_deferred(scroll_pos: Vector2i, remaining_hops: int) -> void:
	if remaining_hops > 0:
		_apply_map_scroll_deferred.call_deferred(scroll_pos, remaining_hops - 1)
		return
	map_scroll.scroll_horizontal = scroll_pos.x
	map_scroll.scroll_vertical = scroll_pos.y

const PINCH_DEBUG := true # TODO: 実機確認が済んだら、この定数とprintごと外す

## 生のタッチを最初に見て、マップ上の2本指ピンチを検出する(ボタンなどのControlより先に呼ばれる)。
##
## ピンチ中は、指の動きに合わせて、本物のレイアウトを一定間隔で作り直す(_rebuild_for_pinch)。
## 以前は、ピンチ中は見た目だけを拡大縮小し、離した時に1回だけ作り直していたが、(1)縮小して
## マップが画面より小さくなると、見た目は中央に寄るのに、離した後のレイアウトは左上に寄る、(2)縦方向は
## 倍率に比例しない(文字の最小サイズなど)ため、離した後に位置が飛ぶ、という食い違いで、実機で酔う
## ほど不快だった。再構築を実機で約0.5秒→約60msに軽くできた(絵文字フォントの登録と、文字を最後に
## 1回だけ設定する変更)ので、常に本物のレイアウトだけを見せる方式にした。
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch_changed(event)
	elif event is InputEventScreenDrag:
		_on_touch_dragged(event)
	elif _pinch_active and event is InputEventMouse:
		# 1本目の指から作られる擬似マウス(パン・クリック)を止める。止めないと、ピンチしながらマップが
		# 1本指でパンされたり、指の下のボタンが押されたりする
		get_viewport().set_input_as_handled()

func _on_touch_changed(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position
		if PINCH_DEBUG:
			print("[pinch] touch down idx=%d pos=%s fingers=%d" % [event.index, str(event.position), _touch_points.size()])
		if not _pinch_active and _touch_points.size() == 2 and _can_start_pinch():
			_start_pinch()
		if _pinch_active:
			get_viewport().set_input_as_handled() # 追加の指の押下を、ScrollContainerなどに渡さない
	else:
		_touch_points.erase(event.index)
		if PINCH_DEBUG:
			print("[pinch] touch up idx=%d fingers=%d" % [event.index, _touch_points.size()])
		if _pinch_active and _touch_points.size() < 2:
			_end_pinch()

func _on_touch_dragged(event: InputEventScreenDrag) -> void:
	if _touch_points.has(event.index):
		_touch_points[event.index] = event.position
	if not _pinch_active:
		return
	get_viewport().set_input_as_handled() # ピンチ中の指の動きは、ScrollContainerの1本指スクロールに渡さない
	if _touch_points.size() < 2:
		return
	var points := _touch_points.values()
	var a: Vector2 = points[0]
	var b: Vector2 = points[1]
	var distance := maxf(a.distance_to(b), 1.0)
	var center := (a + b) * 0.5
	# 2本指の中心の動きで、マップをパンする(拡大縮小と同時に、指の間の場所を追う)
	var moved := center - _pinch_prev_center
	map_scroll.scroll_horizontal -= int(moved.x)
	map_scroll.scroll_vertical -= int(moved.y)
	_pinch_target_zoom = clampf(_pinch_target_zoom * distance / _pinch_prev_distance, MAP_ZOOM_MIN, MAP_ZOOM_MAX)
	_pinch_prev_distance = distance
	_pinch_prev_center = center
	_rebuild_for_pinch(false)

## 2本の指が両方ともマップの上にあり、ポップアップや会話が開いていない時だけ、ピンチを始める。
func _can_start_pinch() -> bool:
	if modal_blocker.visible or dialogue_panel.visible:
		return false
	var map_rect := map_scroll.get_global_rect()
	for point in _touch_points.values():
		if not map_rect.has_point(point):
			return false
	return true

func _start_pinch() -> void:
	var points := _touch_points.values()
	var a: Vector2 = points[0]
	var b: Vector2 = points[1]
	_pinch_active = true
	_map_panning = false
	_pinch_prev_distance = maxf(a.distance_to(b), 1.0)
	_pinch_prev_center = (a + b) * 0.5
	_pinch_target_zoom = _map_zoom
	_pinch_last_rebuild_msec = Time.get_ticks_msec()
	if PINCH_DEBUG:
		print("[pinch] START zoom=%.2f distance=%.0f center=%s" % [_map_zoom, _pinch_prev_distance, str(_pinch_prev_center)])

## 指を離した時: 間引きに関係なく、最後の目標倍率に合わせる。
func _end_pinch() -> void:
	_rebuild_for_pinch(true)
	_pinch_active = false
	if PINCH_DEBUG:
		print("[pinch] END zoom=%.2f" % _map_zoom)

## 目標倍率で、本物のレイアウトを作り直す。再構築は重いので、通常は前回から一定時間あけ(遅い端末では
## 直近の再構築にかかった時間に合わせて広げ)、倍率の変化が小さい間は省く。forceは、指を離した時用。
## 指の中心にあるマップの場所は、作り直しの前後で同じ画面位置に留まる(_set_map_zoom)。
func _rebuild_for_pinch(force: bool) -> void:
	var now := Time.get_ticks_msec()
	var interval := maxi(PINCH_REBUILD_INTERVAL_MSEC, int(_pinch_rebuild_cost_msec * 1.5))
	if not force and now - _pinch_last_rebuild_msec < interval:
		return
	if absf(_pinch_target_zoom - _map_zoom) / _map_zoom < (0.0 if force else PINCH_MIN_ZOOM_CHANGE):
		return
	# 指の中心の、map_canvas内の座標(=画面上の位置 - マップ領域の左上 + 今のスクロール量)
	var scroll := Vector2(map_scroll.scroll_horizontal, map_scroll.scroll_vertical)
	var cursor_in_canvas := _pinch_prev_center - map_scroll.get_global_rect().position + scroll
	_set_map_zoom(_pinch_target_zoom, cursor_in_canvas)
	_pinch_last_rebuild_msec = Time.get_ticks_msec()
	_pinch_rebuild_cost_msec = _pinch_last_rebuild_msec - now
	if PINCH_DEBUG:
		print("[pinch] rebuild -> zoom %.2f (%d ms)" % [_map_zoom, _pinch_rebuild_cost_msec])

## フロア(ノード)の枠内なら詳細ポップアップ、それ以外でセクション枠内ならそのセクションの
## 掲示板スレッドを開く。フロアの箱の方がセクション枠より内側にある(小さい)ので、先に
## フロアを判定してからセクションにフォールバックする。
func _on_map_double_click(pos: Vector2) -> void:
	for id in node_boxes.keys():
		var box: PanelContainer = node_boxes[id]
		if box.get_rect().has_point(pos):
			_show_node_detail(id)
			return
	for section_id in section_lock_icons.keys():
		var lock_icon: Control = section_lock_icons[section_id]
		if lock_icon.visible and lock_icon.get_rect().has_point(pos):
			_show_section_lock_detail(section_id)
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

## 未到達セクション(マップ上の鍵アイコン)をダブルクリックした時の詳細ウィンドウ。
## 通常のフロア詳細(_show_node_detail)と同じnode_detail_panelを使い回す。
func _show_section_lock_detail(section_id: String) -> void:
	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else section_id
	node_detail_title.text = "%s(未到達)" % section_name

	node_detail_body.clear()
	node_detail_body.append_text("まだ誰もこのセクションに足を踏み入れていません。\n\n開通に必要な条件:\n")
	var reasons := _locked_section_reasons(section_id)
	if reasons.is_empty():
		node_detail_body.append_text("(不明)\n")
	else:
		for reason in reasons:
			node_detail_body.append_text("・%s\n" % reason)

	_open_modal(node_detail_panel)

## 未到達セクションの詳細ウィンドウ用: 他セクションから繋がる入り口ノードのうち、
## まだ通れないもの(=WorldMap.is_section_reachableがfalseになっている理由)を列挙する。
## 未発見の入り口ノードは、フロア詳細と同様に名前を????のまま伏せる。
func _locked_section_reasons(section_id: String) -> Array:
	var member_ids := WorldMap.nodes_in_section(section_id)
	var member_set := {}
	for id in member_ids:
		member_set[id] = true

	var reasons := []
	for id in member_ids:
		for neighbor_id in WorldMap.neighbors(id):
			if member_set.has(neighbor_id) or not WorldMap.nodes.has(neighbor_id):
				continue
			if WorldMap.is_passed(neighbor_id):
				continue
			var neighbor: Dictionary = WorldMap.nodes[neighbor_id]
			var neighbor_section_name: String = WorldMap.sections[neighbor["section"]]["name"] if WorldMap.sections.has(neighbor["section"]) else neighbor["section"]
			var neighbor_name: String = neighbor["name"] if WorldMap.is_found(neighbor_id) else "????"
			var state: String = ("発見済みだが%s" % _gate_description(neighbor.get("gate", {}))) if WorldMap.is_found(neighbor_id) else "未発見"
			reasons.append("「%s」(%s)が%s" % [neighbor_name, neighbor_section_name, state])
	return reasons

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

	for section_id in section_lock_icons.keys():
		section_lock_icons[section_id].visible = not WorldMap.is_section_reachable(section_id)
	# セクション名ボタンのdisabledも、探索が進んで新たに到達可能になったセクションがあれば
	# ここで追従させる(作成時点のdisabled値のままだと、エリアタブを切り替えるかズームし直す
	# まで押せないままになってしまう)。
	for section_id in section_title_buttons.keys():
		section_title_buttons[section_id].disabled = not WorldMap.is_section_reachable(section_id)

	_refresh_party_map_icons()
	_refresh_area_tabs() # 探索の進行でエリアの到達状況(🔒表示)が変わりうるため、日次でも更新する

## マップ上でパーティアイコンを表示するノード(現在フロア)を1つ選ぶ。担当パーティはセクション内の
## 未発見フロア全部に同時並行でアタックする実装(exploration.gd)なので厳密な「今いる場所」は
## 存在しないが、表示上は次の優先順で代表点を決める:
## 1) 発見済みだが未突破のゲートがあれば、そこで足止め中として表示
## 2) なければ、既知の最前線(未発見フロアに隣接する突破済みノード)
## 3) それも無ければ(セクション完全踏破後など)周回(ループ)の進み具合(exploration.gdの
##    _process_lap/Parties.lap_start_day)に応じて最初のフロアから動かす。1周し終えるたびに
##    最初のフロアへ戻る(2026-09-15、「ループでループしない、終わったらアイコンが
##    最初に戻るべきだが戻っていない」というバグ報告への対応)。
func _current_node_for_party(party: Dictionary) -> String:
	var section_id: String = party["assigned_section"]
	if section_id == "" or not WorldMap.sections.has(section_id):
		return ""
	var member_ids := WorldMap.nodes_in_section(section_id)
	if member_ids.is_empty():
		return ""

	for id in member_ids:
		if WorldMap.is_found(id) and not WorldMap.is_passed(id):
			return id

	for id in member_ids:
		if not WorldMap.is_passed(id):
			continue
		for neighbor_id in WorldMap.neighbors(id):
			if WorldMap.nodes.has(neighbor_id) and not WorldMap.nodes[neighbor_id]["found"]:
				return id

	var lap_start_day: int = party.get("lap_start_day", -1)
	if lap_start_day >= 0:
		var elapsed: int = TimeSystem.current_day - lap_start_day
		var index: int = clampi(elapsed, 0, member_ids.size() - 1)
		return member_ids[index]

	return member_ids[member_ids.size() - 1]

## 担当パーティアイコンを、現在の割り当てと各パーティの現在フロア(_current_node_for_party)に
## 合わせて作り直す。クリックするとパーティパネルでそのパーティの詳細を選択した状態にする。
func _refresh_party_map_icons() -> void:
	var parties_by_node: Dictionary = {}
	for party in Parties.get_parties():
		var node_id := _current_node_for_party(party)
		if node_id == "":
			continue
		if not parties_by_node.has(node_id):
			parties_by_node[node_id] = []
		parties_by_node[node_id].append(party)

	for node_id in node_icon_rows.keys():
		var row: HBoxContainer = node_icon_rows[node_id]
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
		for party in parties_by_node.get(node_id, []):
			row.add_child(_create_party_icon(party))

## パーティの先頭(代表)メンバー1人の肖像を縮小表示するアイコン(2026-09-14)。先頭メンバーに
## 肖像が無い(旧データ等)場合はパーティ名の頭文字にフォールバックする。
func _create_party_icon(party: Dictionary) -> Button:
	var icon := Button.new()
	icon.custom_minimum_size = Vector2(MAP_ICON_SIZE, MAP_ICON_SIZE) * _map_zoom
	icon.clip_contents = true
	icon.tooltip_text = party["name"]
	icon.pressed.connect(_on_party_icon_pressed.bind(party["id"]))

	var member_ids: Array = party["member_ids"]
	var front_npc: Dictionary = Npcs.get_npc(member_ids[0]) if not member_ids.is_empty() else {}
	var portrait_id: String = front_npc.get("portrait", "")
	var portrait_path := PortraitLibrary.texture_path(portrait_id) if portrait_id != "" else ""
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		var texture_rect := TextureRect.new()
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_rect.texture = load(portrait_path)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.add_child(texture_rect)
	else:
		icon.text = party["name"].substr(0, 1)
		icon.add_theme_font_size_override("font_size", max(8, roundi(18 * _map_zoom)))
	return icon

func _on_party_icon_pressed(party_id: int) -> void:
	_open_party_panel(party_id)

## マップ上部のエリア選択ボタン用: そのエリアの中で最も上にあるセクションの位置までスクロールする。
## エリアタブ切替(design.md 5.1節)。選んだエリアのセクションだけを表示し直す。
func _on_area_tab_pressed(area_id: String) -> void:
	_active_area_id = area_id
	map_scroll.scroll_vertical = 0
	map_scroll.scroll_horizontal = 0
	_seed_demo_world()
	_refresh_area_tabs()

## エリアタブの表示名(🔒未到達なら鍵アイコン付き)と選択状態を、到達状況の変化(発見・攻略)に
## 合わせて更新する。_seed_demo_world()やゲーム進行の節目(_refresh_all)から呼ぶ。
func _refresh_area_tabs() -> void:
	for area_id in area_tab_buttons.keys():
		var button: Button = area_tab_buttons[area_id]
		var name: String = WorldMap.areas[area_id]["name"]
		button.text = name if WorldMap.is_area_reachable(area_id) else "🔒 %s" % name
		button.button_pressed = (area_id == _active_area_id)
	if area_option != null:
		var area_ids: Array = WorldMap.areas.keys()
		for i in area_ids.size():
			var area_name: String = WorldMap.areas[area_ids[i]]["name"]
			area_option.set_item_text(i, area_name if WorldMap.is_area_reachable(area_ids[i]) else "🔒 %s" % area_name)
		var current: int = area_ids.find(_active_area_id)
		if current >= 0:
			area_option.select(current)
		area_prev_button.disabled = current <= 0
		area_next_button.disabled = current >= area_ids.size() - 1

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
	if _selected_candidate_index < 0 or _selected_candidate_index >= Recruitment.current_candidates.size():
		hire_status_label.text = "候補を一覧から選択してください"
		return
	var npc_id := Recruitment.hire_candidate(_selected_candidate_index)
	if npc_id == -1:
		hire_status_label.text = "雇用できませんでした(資金不足の可能性があります)"
		return
	hire_status_label.text = "%sを雇用しました" % Npcs.get_npc(npc_id)["name"]
	_refresh_candidates()
	_refresh_roster()
	_refresh_funds()
	# 初めての雇用の直後だけ、パーティ編成の説明会話を挟む。雇用パネル(モーダル)が開いた
	# ままだと会話ウィンドウがその下に隠れてしまうため、先に閉じてから再生する。「見た」
	# フラグは再生開始時ではなくEventDialogue.finished発火時に永続化する(理由はINTRO_TUTORIAL_SCRIPT
	# 再生箇所のコメント参照。診断コードが雇用だけシミュレートして会話を進めずに終わった場合
	# などに、実際には見せていないのに実ファイルへ「見た」と書き込んでしまう事故を防ぐ)。
	if not SaveSystem.tutorial_party_seen:
		_close_modal(hire_panel)
		EventDialogue.finished.connect(func(_o): SaveSystem.mark_tutorial_party_seen(), CONNECT_ONE_SHOT)
		EventDialogue.play(PARTY_TUTORIAL_SCRIPT)

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
	_refresh_party_roster()
	_refresh_party_detail() # NPCパネルと同様、パーティパネルを開いたまま倍速で進めても情報が古くならないようにする
	_refresh_funds() # セクション攻略の一時金は月末を待たずその日のうちに入るため、日次でも反映する
	SaveSystem.autosave()

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
	_refresh_party_roster()
	_refresh_party_detail()
	_refresh_facility_button()
	_on_speed_changed(TimeSystem.speed_multiplier) # ロード直後、実際の倍速にボタンの押下表示を合わせる
	# next_month_buttonは元々month_endedシグナル(その場で月末になった瞬間)でのみ表示していたため、
	# 「一時停止した状態のままセーブ→再起動」すると、is_paused=trueなのにボタンだけ非表示で
	# 再開する手段が無くなってしまう不具合があった。ロード直後の実状態にも合わせて同期する。
	next_month_button.visible = TimeSystem.is_paused

func _refresh_facility_button() -> void:
	facility_info_label.text = "雇用上限 +2\nコスト: %d" % Economy.facility_upgrade_cost()

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
	for child in candidates_grid.get_children():
		candidates_grid.remove_child(child)
		child.queue_free()
	_selected_candidate_index = -1
	var group := ButtonGroup.new() # 作り直すたびに新しいグループにして排他選択させる
	for i in range(Recruitment.current_candidates.size()):
		candidates_grid.add_child(_create_candidate_card(Recruitment.current_candidates[i], i, group))

## 候補者1人分の肖像カード(2026-09-14、ロースターカードと同じ構造を流用)。
## クリックで選択状態にするだけで、実際の雇用は「選択した候補を雇う」ボタンから行う。
func _create_candidate_card(candidate: Dictionary, index: int, group: ButtonGroup) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = group
	card.custom_minimum_size = Vector2(CANDIDATE_CARD_WIDTH, CANDIDATE_PORTRAIT_SIZE + 60)
	card.tooltip_text = candidate["name"]
	card.pressed.connect(_on_candidate_card_pressed.bind(index))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var portrait := PanelContainer.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.custom_minimum_size = Vector2(CANDIDATE_PORTRAIT_SIZE, CANDIDATE_PORTRAIT_SIZE)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER # 正方形のまま中央に置く(カード幅に伸ばさない)
	portrait.clip_contents = true
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = _bloodline_color(candidate["innate_traits"].get("bloodline", ""))
	portrait_style.set_corner_radius_all(6)
	portrait.add_theme_stylebox_override("panel", portrait_style)
	portrait.add_child(_create_portrait_content(candidate))
	vbox.add_child(portrait)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = candidate["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(name_label)

	var info_label := Label.new()
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label.text = "%s / 質%.1f\nコスト%d" % [Jobs.JOB_NAMES[candidate["job"]], candidate["quality"], candidate["cost"]]
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.modulate = Color(1, 1, 1, 0.75)
	vbox.add_child(info_label)

	# 素のButtonは子の必要サイズを最小サイズに含めないため、上の「ポートレート+60」は文字の高さの
	# 見積もりでしかなく、CJKフォールバックフォント(行が少し高い)を入れたら「コスト」の行が
	# カード下端で切れた(2026-09-19、実機で発見)。ツリーに入ってテーマ(=実際に使うフォント)が
	# 反映されてから、中身の実測値に合わせて高さを広げる(見積もりより小さくはしない)。
	card.ready.connect(func():
		var needed: float = vbox.get_combined_minimum_size().y + 8.0 # 上下のmargin(4+4)
		card.custom_minimum_size.y = maxf(card.custom_minimum_size.y, needed))

	return card

func _on_candidate_card_pressed(index: int) -> void:
	_selected_candidate_index = index

func _refresh_roster() -> void:
	for child in roster_grid.get_children():
		roster_grid.remove_child(child)
		child.queue_free()
	var roster_group := ButtonGroup.new() # 作り直すたびに新しいグループにして排他選択させる
	for npc in Npcs.get_roster():
		var card := _create_roster_card(npc, roster_group)
		roster_grid.add_child(card)
		if npc["id"] == _selected_npc_id:
			card.button_pressed = true

const BLOODLINE_COLORS := {
	"平民": Color(0.45, 0.45, 0.48),
	"旧家の血筋": Color(0.5, 0.35, 0.65),
	"森人の血": Color(0.3, 0.6, 0.35),
	"王家の落胤": Color(0.75, 0.6, 0.15),
}

func _bloodline_color(bloodline: String) -> Color:
	return BLOODLINE_COLORS.get(bloodline, Color(0.4, 0.4, 0.4))

const STATUS_COLORS := {
	Parties.Status.EXPLORING: Color(0.25, 0.55, 0.3),
	Parties.Status.RECOVERING: Color(0.7, 0.45, 0.15),
	Parties.Status.IDLE: Color(0.35, 0.35, 0.38),
}

## NPC個人には状態を持たせていない(所属パーティの状態、design.md 4.7節)。未所属ならIDLE扱い。
func _npc_status_via_party(npc: Dictionary) -> int:
	var party_id: int = npc["party_id"]
	if party_id == -1:
		return Parties.Status.IDLE
	return int(Parties.get_party(party_id).get("status", Parties.Status.IDLE))

const PORTRAIT_SIZE := 96.0
# ロースターカードの肖像の一辺。肖像画像が正方形になった(2026-09-19)ので、画像枠も正方形のまま
# カード中央に置いて全体を見せる(以前は枠がカード幅いっぱいの横長に伸びており、縦長の画像なら
# 中央の顔だけ見えていたが、正方形だと上下が大きく切れて帽子や耳の先が見えなかった)。
const ROSTER_PORTRAIT_SIZE := 132.0
# カードの横幅は「名前ラベル+状態バッジを横並びで収める」ために必要な幅から逆算する
# べきところを、ポートレート(96px)基準の当て推量(+24px)で決め打ちしていたため、
# 「アーチボルド」のような長めの名前だとinfo_row(名前+バッジ)がこの幅に収まらず、
# カードの右端からはみ出して表示される不具合になっていた。Buttonは(VBoxContainer等の
# Containerと違い)子要素の必要サイズを自分の最小サイズに反映しないため、customに
# 決め打ちした値が子要素の実際の必要幅より小さくても警告なく素通りしてしまう点に注意
# (このクラスの見落としは[[godot_install_path]]にも対策として記録した)。ここでは
# 実際に収まる余裕を持った固定幅に広げ、かつ名前ラベル側にも省略表示の安全弁を入れる
# ことで、想定より長い名前が来ても二重に安全なようにしている。
const CARD_WIDTH := 190.0

# 雇用パネルの候補カード用(2026-09-14)。ロースターカードより一回り小さい縮小表示にする
# (雇用パネル自体がポップアップとして小さめのため)。
const CANDIDATE_PORTRAIT_SIZE := 96.0 # 正方形の肖像を上下を切らずに見せるため、64から拡大(2026-09-19)
const CANDIDATE_CARD_WIDTH := 130.0

## ロースターの正方形ポートレートカード1枚: [画像(正方形)]の下に[名前][状態]を並べる。
## 画像は未実装のため、血筋色の正方形+頭文字で代用している(将来ここをTextureRectへ
## 差し替え、NPCごとの画像を表示する想定)。カード全体をtoggle_mode付きButtonにして、
## どこをクリックしてもそのNPCの詳細ビューに切り替わるようにする(中の子要素は
## mouse_filter=IGNOREにしてクリックをButtonまで素通りさせる)。
## 肖像画像(portrait_library.gd、2026-09-14追加)があればそれを表示し、無ければ血筋色+頭文字の
## 従来プレースホルダにフォールバックする(旧セーブ由来で未割り当ての場合の保険)。
## 呼び出し元がPanelContainer(血筋色の背景+角丸)に1つだけ子として追加する想定。
func _create_portrait_content(npc: Dictionary) -> Control:
	var portrait_id: String = npc.get("portrait", "")
	var portrait_path := PortraitLibrary.texture_path(portrait_id) if portrait_id != "" else ""
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		var texture_rect := TextureRect.new()
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_rect.texture = load(portrait_path)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		return texture_rect

	var portrait_label := Label.new()
	portrait_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_label.text = npc["name"].substr(0, 1)
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_label.add_theme_font_size_override("font_size", 36)
	return portrait_label

func _create_roster_card(npc: Dictionary, group: ButtonGroup) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = group
	card.custom_minimum_size = Vector2(CARD_WIDTH, ROSTER_PORTRAIT_SIZE + 56)
	card.tooltip_text = npc["name"] # 名前が省略表示された場合でもホバーでフルネームを確認できる
	card.pressed.connect(_on_roster_card_pressed.bind(npc["id"]))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var portrait := PanelContainer.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.custom_minimum_size = Vector2(ROSTER_PORTRAIT_SIZE, ROSTER_PORTRAIT_SIZE)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER # カード幅いっぱいに伸ばさず、正方形のまま中央に置く
	portrait.clip_contents = true
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = _bloodline_color(npc["innate_traits"].get("bloodline", ""))
	portrait_style.set_corner_radius_all(6)
	portrait.add_theme_stylebox_override("panel", portrait_style)
	portrait.add_child(_create_portrait_content(npc))
	vbox.add_child(portrait)

	var info_row := HBoxContainer.new()
	info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_row.add_theme_constant_override("separation", 4)
	vbox.add_child(info_row)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = npc["name"]
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# CARD_WIDTHを広げても、それを上回る名前が来た時に無条件にはみ出さないよう、
	# 省略表示を安全弁として入れておく(はみ出た全文はcardのtooltip_textで確認できる)。
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_row.add_child(name_label)

	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = STATUS_COLORS.get(_npc_status_via_party(npc), Color(0.3, 0.3, 0.3))
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
	info_row.add_child(badge)

	return card

## カード行のバッジ用に、状態を短い一言にする(詳細な残り日数は右側の詳細パネルに任せる)。
func _npc_status_short(npc: Dictionary) -> String:
	match _npc_status_via_party(npc):
		Parties.Status.RECOVERING:
			return "回復中"
		Parties.Status.EXPLORING:
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
