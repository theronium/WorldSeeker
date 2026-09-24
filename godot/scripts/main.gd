extends Control

var candidates_grid: GridContainer # 候補者の肖像カード(2026-09-14、ItemListのテキスト行から変更)
var _selected_candidate_index: int = -1
var hire_status_label: Label
var roster_grid: GridContainer # 探索者ごとの正方形ポートレートカード(画像/名前/状態)を並べる
var npc_roster_view: Control # 探索者管理パネル: 一覧ビュー(既定で表示)
var npc_detail_view: Control # 探索者管理パネル: 選択中探索者の詳細ビュー(ステータス+スキル訓練)
var npc_detail_label: Label
var npc_job_label: Label
var npc_detail_portrait: PanelContainer
var skill_level_labels: Dictionary = {} # skill:int -> Label(Lv/コスト表示)
var skill_train_buttons: Dictionary = {} # skill:int -> Button(資金が足りない間は押せなくする。_refresh_train_buttons)
var reclass_option: OptionButton # 転職先ジョブの選択(design.md 4.8節)
var reclass_button: Button
var _selected_npc_id: int = -1
var facility_button: Button

# 探索者一覧の並べ替え・絞り込み(2026-09-21。RosterQuery)。パネルを閉じても、次に開くまで選択を覚えている。
var roster_sort_option: OptionButton
var roster_sort_dir_button: Button
var roster_bloodline_option: OptionButton
var roster_job_option: OptionButton
var roster_count_label: Label
var _roster_sort_key: String = RosterQuery.SORT_JOIN
var _roster_sort_descending: bool = false
var _roster_bloodline: String = RosterQuery.ALL_BLOODLINES
var _roster_job: int = RosterQuery.ALL_JOBS

# パーティ編成パネル(design.md 4.7節)。担当セクション割り当て・予測・完全踏破後の設定は
# 探索者単位ではなくパーティ単位の操作になった(旧npc_panelの[担当]タブから移設)。
var party_panel: PanelContainer
var party_roster_view: Control
var party_detail_view: Control
var party_grid: GridContainer
var party_form_picker: MemberPicker # 未所属探索者から最大4人を選ぶ(チェックボックス式。ItemListの複数選択は、タッチでは1人しか選べなかった)
var party_form_button: Button
# パーティ詳細(メンバー画面)の、メンバーの追加と外す(2026-09-21)
var party_add_picker: MemberPicker
var party_add_label: Label
var party_add_button: Button
var party_add_status_label: Label
var party_remove_button: Button
var party_form_status_label: Label
var party_detail_label: Label
var difficulty_buttons: Array[Button] = [] # 難易度の切り替え(添字はDifficulty.Mode)。開いている側が、その難易度の色になる
var difficulty_desc_label: Label # 選んでいる難易度の効果の1行説明
# パーティ詳細は2つのタブ(メンバー・並び順/担当セクション)に分けてある(2026-09-19)。
var party_member_row: HBoxContainer # 選択中パーティのメンバーを肖像付きのカードで左(先頭)から並べる
var party_member_move_buttons: Array[Button] = [] # 前へ/後ろへ。メンバーのカードを選んでいる間だけ押せる
var _selected_member_index: int = -1 # 並び順の中で選んでいるメンバー(-1は未選択)
var party_tab_buttons: Array[Button] = [] # [メンバー, 担当セクション]
var party_tab_pages: Array[Control] = []
var section_action_buttons: Array[Button] = [] # 割り当て/ログ/予測。セクションを選んでいる間だけ押せる
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
var _pending_assignment_followup: bool = false # 導入・後編(場面名"intro_part2")の予約フラグ

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
var node_icon_rows: Dictionary = {} # node_id -> HBoxContainer(担当探索者アイコンを現在フロアに表示)
var section_bounds_cache: Dictionary = {} # section_id -> Rect2(エリア選択ボタンのスクロール先計算用)
var section_lock_icons: Dictionary = {} # section_id -> Control(未到達セクションの鍵アイコン)
var section_title_buttons: Dictionary = {} # section_id -> Button(セクション名ボタン。到達状況でdisabledを更新)
var facility_info_label: Label
var funds_label: Label
var date_label: Label
var time_label: Label
# タイムバー(2026-09-21): 日付・月末までの文字の下に、今日(太め)と今月(細め)の進みを出す。
var day_bar: TimeBar
var month_bar: TimeBar
var day_caption: Label
var month_caption: Label
var speed_buttons: Dictionary = {} # multiplier:float -> Button
var log_toggle_button: Button # マップ右上のフロートボタン。ログウィンドウ(log_window)を出し入れする
var area_nav_panel: PanelContainer # マップ上部にフロートするエリア選択バー
var left_scroll: ScrollContainer
var left_menu: VBoxContainer
var _fit_left_menu_pending: bool = false
var node_detail_panel: PanelContainer
var node_detail_title: Label
var node_detail_body: RichTextLabel

# 戦闘画面(design.md 5.4節、2026-09-22): イベント戦闘(会話の付いた戦闘ゲート)の実際の攻防を、
# ラウンドごとに再現して見せる。BattleScreen(battle_screen.gd)のopened/closedシグナルで開閉する。
var battle_panel: PanelContainer
var battle_title_label: Label
var battle_kind_badge: Label
var battle_party_slots: Array = [] # [{"portrait":Control, "name":Label, "hp_bar":ProgressBar, "hp_label":Label, "frame":Panel}]
var battle_enemy_portrait: Control
var battle_enemy_name_label: Label
var battle_enemy_hp_bar: ProgressBar
var battle_enemy_hp_label: Label
var battle_log: RichTextLabel
var battle_skip_button: Button
var battle_close_button: Button
var battle_click_catcher: Control # パネル全体のクリックで1ラウンド早送り
var _battle_trace: Array = []
var _battle_round_index: int = 0
var _battle_enemy_hp: int = 0
var _battle_result_kind: String = "" # "victory"/"defeat"/"retreat"/"retreat_before_fight"(BattleScreen.showのdata["result"])。_finish_battle_roundsの結果表示に使う
var _battle_slot_index_by_npc: Dictionary = {} # npc_id -> battle_party_slotsの添字
var _battle_timer: Timer
const BATTLE_ROUND_DELAY_SEC := 0.45
var next_month_button: Button # 月末の集計待ちの間だけ、今日・今月のバー(time_bars_box)の位置に重ねて出す
var time_bars_box: VBoxContainer
var map_scroll: ScrollContainer
var map_canvas: Control
var _map_panning: bool = false
var _map_press_pos := Vector2.ZERO # マップを押した位置(画面上)。離した時にほぼ動いていなければタップとみなす
var _map_press_is_tap := false # 押してから、まだタップとみなせる範囲しか動いていない
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
var _party_area_seen: Dictionary = {} # party_id -> 前回マップを描いた時の、担当セクションのエリア(_follow_parties_to_new_area)
var _employed_areas_seen: Dictionary = {} # 前回マップを描いた時に、雇用パーティが発見したフロアがあったエリア(area_id -> true)
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
# デスクトップの会話ウィンドウを、ウィンドウの下端から浮かせる高さ。下端に貼り付くと、最下段の「次へ」が窓の縁に
# 近すぎて押しにくい(2026-09-21、Windowsで報告)。タッチUIは従来どおり(下端まで使う)。
const DESKTOP_DIALOGUE_LIFT := 32
# デスクトップで会話を進めるキー(_handle_dialogue_key)
const DIALOGUE_ADVANCE_KEYS := [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
# 実機(Android等)で、UI全体を画面の四辺から最低これだけ内側に寄せる(表示上のpx)。切り欠きは
# DisplayServer.get_display_safe_area()で避けられるが、角丸の画面の角はOSが半径を教えてくれない
# 端末(moto g05は0と報告する)があるため、その分の余白を固定で確保する(_apply_safe_area参照)。
const MOBILE_MIN_EDGE_MARGIN := 24.0
# タッチUIの左メニューのボタンの内側余白(上下)。画面が低くても縦に収まるよう、これを下限にして小さく作り、
# 余った高さがあれば_fit_left_menu()が各ボタンをTOUCH_BUTTON_MARGIN_V相当まで広げる。
const LEFT_MENU_BUTTON_MARGIN_V := 4
const LEFT_MENU_BOTTOM_MARGIN := 12.0 # 左メニューの最下のボタンの下に空ける余白
const LEFT_MENU_RIGHT_MARGIN := 12 # 左メニューのボタンの右に空ける余白(マップとの間)
const LOG_WINDOW_WIDTH_TOUCH := 400.0 # ログウィンドウ(マップ右端に重ねる)の幅(表示上のpx)
const LOG_WINDOW_WIDTH_DESKTOP := 460.0

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
var dialogue_kind_badge: PanelContainer # 会話の種別(ボス戦/戦闘/技能…)と結果(突破/失敗)を示すバッジ
var dialogue_kind_label: Label
var _dialogue_accent: Color = Color.TRANSPARENT # 今の会話の色(選択肢ボタンにも同じ色を付けるために覚えておく)
var dialogue_text_label: Label
var choices_box: VBoxContainer
var advance_hint: Button

var license_panel: PanelContainer # 左メニュー一番下の「ライセンス」ボタンで開く(内容はLicenseInfoが読み込む)
var license_text: RichTextLabel

# 設定画面(2026-09-22): 端末ごとの設定(Settings)。BGM音量・ミュート、イベント戦闘の戦闘画面ON-OFF。
var settings_panel: PanelContainer
var settings_bgm_slider: HSlider
var settings_bgm_mute_check: CheckBox
var settings_battle_screen_check: CheckBox

var log_window: LogWindow # ログウィンドウ: マップ右端に重ねる。毎日の動き・行動ログ・掲示板をタブで切り替える

var slot_panel: PanelContainer
var slot_list: ItemList
var slot_name_input: LineEdit
var manual_save_status_label: Label
var autosave_checkbox: CheckBox
var new_game_confirm: ConfirmationDialog
var new_game_scenario_option: OptionButton # 新規プレイで遊ぶシナリオ(ScenarioStore.list_scenarios())
var _built_world_version: String = "" # エリア選択バーとマップを作った時の世界のバージョン(WorldSchemaDb.active_version_id)
var delete_slot_confirm: ConfirmationDialog
var _pending_delete_slot_id: int = -1
# セーブのエクスポート/インポート(SaveSystem.export_all_slots/read_import_file/import_slots)。
var export_file_dialog: FileDialog
var import_file_dialog: FileDialog
var import_confirm: ConfirmationDialog
var import_slot_list: ItemList
var _import_slots: Array = [] # read_import_file()が返した取り込み候補(import_slot_listの行と同じ順)
# シナリオの取り込み・カスタムシナリオの管理(ScenarioTransfer。docs/scenario_editor.md「スマホへの持ち込み」)。
var scenario_import_file_dialog: FileDialog
var scenario_import_confirm: ConfirmationDialog
var scenario_manage_dialog: ConfirmationDialog
var scenario_manage_list: ItemList
var scenario_manage_hint: Label
var scenario_import_label: Label
var scenario_delete_confirm: ConfirmationDialog
var _scenario_manage_entries: Array = [] # scenario_manage_listの行と同じ順のカスタムシナリオ
var _pending_delete_scenario: Dictionary = {}

var hire_panel: PanelContainer
var npc_panel: PanelContainer
var modal_blocker: ColorRect

## 案内会話(導入の前編・後編、初雇用後のパーティ編成の説明)は、2026-09-21にシナリオのイベント
## (scenarios/<id>/events/guide_*.json、trigger.type="system")へ移した。ここからは、場面名で
## ScenarioEvents.play_system()を呼んで再生する:
##   "intro_part1"  導入・前編(起動直後の一度きり。SaveSystem.is_tutorial_seen("intro_part1")で制御。_ready()と、新規プレイ開始時の_play_intro_if_unseen()参照)。
##                  情報を詰め込みすぎず、マップでの割り当て操作そのものへ誘導することだけに絞ってある
##   "intro_part2"  導入・後編(初めて実際に割り当てを行った直後。SaveSystem.is_tutorial_seen("intro_part2")、
##                  _maybe_show_assignment_followup_tutorial()参照)。収入の仕組み/行ける場所の増やし方/進行速度の説明
##   "party_formed" 初めて探索者を雇用した直後(SaveSystem.is_tutorial_seen("party_formed")、_on_hire_pressed()参照)。
##                  雇っただけではまだ働けず、パーティ編成(1人でも組める)が必要なことを教える

func _ready() -> void:
	_touch_ui = OS.has_feature("mobile") or "--touch-ui" in OS.get_cmdline_user_args()
	_build_theme()
	_build_node_styles()
	_build_ui()
	_build_dialogue_ui()
	_build_slot_ui()
	_build_hire_ui()
	_build_npc_ui()
	_build_party_ui()
	_build_shop_ui()
	_build_node_detail_ui()
	_build_battle_screen_ui()
	_build_section_assign_ui()
	_build_license_ui()
	_build_settings_ui()
	_build_back_hint_ui()
	_apply_safe_area()
	get_window().size_changed.connect(_apply_safe_area) # 画面の向きが変わった時など
	# 2026-09-14: 起動時に前回のアクティブスロットを自動ロードする仕様をやめ、常に
	# まっさらな新規プレイから始まるようにした(design.md 8.2節)。既存の進行を続けたい
	# 場合は、セーブパネルから明示的に「このスロットをロードする」を選ぶ(一般的な
	# ゲームの「ロードは明示的操作」という体験に合わせた。過去に診断作業が実セーブを
	# 誤って上書きした事故の根本原因でもあったため、安全面でも狙い通り)。
	# WorldMapはオートロードのWorldSchemaDbが起動時にデフォルトシナリオで既に構築済みのため、
	# ここではスキーマの再構築は不要。
	_seed_demo_world()
	SaveSystem.start_fresh_session()
	TimeSystem.day_advanced.connect(_on_day_advanced)
	ScenarioEvents.event_started.connect(_on_scenario_event_started) # イベントの起きた場所へマップを移す(_focus_map)
	ScenarioEvents.joined.connect(func(_npc_id: int): # イベントで探索者が加わった(効果「探索者が加入する」)
		_refresh_roster()
		_refresh_party_roster()
		_refresh_funds())
	Exploration.area_first_entered.connect(_on_area_first_entered)
	Exploration.party_location_changed.connect(_on_party_location_changed)
	TimeSystem.month_ended.connect(_on_month_ended)
	TimeSystem.speed_changed.connect(_on_speed_changed)
	EventDialogue.line_shown.connect(_on_dialogue_line_shown)
	EventDialogue.finished.connect(_on_dialogue_finished)
	_refresh_all()
	# 初回起動時だけ、遊び方(探索者の配置/稼ぎ方/行ける場所の増やし方/進行速度)を説明する
	# 導入会話を挟む。スロットに紐付かず(SaveSystem.is_tutorial_seen)、シナリオごとに、新規プレイを
	# 何度始めても一度見せたら二度と出さない(起動直後はデフォルトシナリオ。別のシナリオは、その新規プレイ開始時に
	# _on_new_game_confirmed()が_play_intro_if_unseen()で流す)。この時点ではまだ他の会話は動いていないので、
	# そのまま直接EventDialogue.play()してよい(節末の「イベント会話まわりの実装メモ」参照)。
	# 「見た」フラグは再生開始時ではなく、実際にプレイヤーが最後まで進めてEventDialogue.finished
	# が発火した時点でONE_SHOT接続で永続化する。開始時点で即座に書き込むと、`--headless --quit`
	# のようなコンパイル確認だけの起動(誰も会話を進めない)でも実ファイル(worldseeker_meta.cfg)
	# に「見た」と書き込まれてしまい、次回以降の本当のプレイでチュートリアルが二度と出なくなる
	# 事故につながる(実際に一度発生させて修正した)。
	_play_intro_if_unseen()
	TimeSystem.mark_boot_complete()

## 導入・前編を、今のシナリオでまだ見ていなければ再生する(起動直後と、新規プレイの開始直後)。
## 「見た」記録は、会話を最後まで進めた時にScenarioEvents.play_guide()が付ける(会話を進めない`--headless --quit`の
## 起動で、実ファイルへ「見た」と書き込んでしまわないため)。
func _play_intro_if_unseen() -> void:
	if EventDialogue.is_active or SaveSystem.is_tutorial_seen("intro_part1"):
		return
	ScenarioEvents.play_guide("intro_part1")

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
	for dialog in [new_game_confirm, delete_slot_confirm, scenario_import_confirm, scenario_manage_dialog, scenario_delete_confirm]:
		if dialog.visible:
			if dialog == scenario_import_confirm:
				ScenarioTransfer.cancel_import() # 取り込みをやめる(展開した一時ファイルを消す)
			dialog.hide()
			return
	if npc_panel.visible and npc_detail_view.visible:
		_on_npc_detail_back_pressed() # 詳細画面からは、パネルごと閉じずに一覧へ戻る
		return
	if party_panel.visible and party_detail_view.visible:
		_on_party_detail_back_pressed()
		return
	if battle_panel.visible:
		return # 戦闘画面中は何もしない(タップ早送り・「閉じる」で進める)。他のモーダルと同じくmodal_blockerも
		# 立っているため、次のif(modal_blocker.visible)より前で弾く必要がある(そちらは_close_any_modal()で閉じてしまう)。
	if modal_blocker.visible:
		_close_any_modal()
		return
	if log_window.visible:
		_set_log_window_visible(false)
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

	# 戦闘画面のHPバー(design.md 5.4節)。ProgressBarはここでしか使っておらず、無指定のままだと
	# Godot標準テーマの薄い塗りが暗い背景に埋もれてほぼ見えない(満タンでも空に見える不具合。
	# 2026-09-23、実機で報告)。地(空の部分)を暗く縁取り、満タン側は視認性の高い色ではっきり塗る。
	# 敵側だけ赤系にして、パーティ(緑系)と一目で見分けられるようにする(EnemyHPBarのtheme_type_variation)。
	var hp_bar_bg := StyleBoxFlat.new()
	hp_bar_bg.bg_color = Color(0.1, 0.1, 0.13, 1.0)
	hp_bar_bg.border_color = Color(0.4, 0.44, 0.52, 0.8)
	hp_bar_bg.set_border_width_all(1)
	hp_bar_bg.set_corner_radius_all(3)
	var hp_bar_fill_ally := StyleBoxFlat.new()
	hp_bar_fill_ally.bg_color = Color(0.35, 0.82, 0.45, 1.0)
	hp_bar_fill_ally.set_corner_radius_all(3)
	var hp_bar_fill_enemy := StyleBoxFlat.new()
	hp_bar_fill_enemy.bg_color = Color(0.88, 0.32, 0.32, 1.0)
	hp_bar_fill_enemy.set_corner_radius_all(3)
	ui_theme.set_stylebox("background", "ProgressBar", hp_bar_bg)
	ui_theme.set_stylebox("fill", "ProgressBar", hp_bar_fill_ally)
	ui_theme.set_type_variation("EnemyHPBar", "ProgressBar")
	ui_theme.set_stylebox("background", "EnemyHPBar", hp_bar_bg)
	ui_theme.set_stylebox("fill", "EnemyHPBar", hp_bar_fill_enemy)

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
	_apply_accent_button_style(button, Color(0.16, 0.5, 0.22), Color(0.45, 0.85, 0.5))

## 取り消せない危険な操作(スロットの削除など)のボタン: 赤(2026-09-24、「削除はボタンを赤に」)。
func _apply_danger_button_style(button: Button) -> void:
	_apply_accent_button_style(button, Color(0.62, 0.14, 0.12), Color(1.0, 0.42, 0.36))

## 大きな切り替えを伴う操作(新規プレイなど)のボタン: オレンジ(2026-09-24、「新規プレイもオレンジくらいに」)。
func _apply_caution_button_style(button: Button) -> void:
	_apply_accent_button_style(button, Color(0.72, 0.4, 0.08), Color(1.0, 0.7, 0.3))

## 色付きのボタン(緑=主要・赤=危険・オレンジ=注意)の共通処理。bgは通常時の背景、borderは枠の色。
## 押せない(disabled)時は、共有Themeの灰色のままにする(色が付いていると押せそうに見えるため)。
func _apply_accent_button_style(button: Button, bg: Color, border: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = border
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = bg.lightened(0.2)
	var pressed := normal.duplicate()
	pressed.bg_color = bg.darkened(0.2)
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

const BACKGROUND_TEXTURE_PATH := "res://assets/background/bg_main.png"
# 背景の絵が明るい青空なので、上に暗いフィルターを重ねて、素のラベル(資金・日付など)や
# 半透明のマップのノードが読みやすいようにする(色みは絵の青に寄せた暗色)。濃さはここで調整する。
const BACKGROUND_DIM_COLOR := Color(0.02, 0.03, 0.07, 0.76)

## 画面全体の最背面に、背景画像と暗いフィルターを敷く。安全領域(_apply_safe_area)でこのControlを
## 内側に寄せても、切り欠きの裏まで背景が届くよう、寄せの影響を受けないCanvasLayerに置く
## (layer=-1で通常のUI=レイヤー0より奥)。入力は一切受けない。
## 画像は画面を隙間なく覆う大きさにして、下端に揃えて左右は中央に置く。縦が余る(画面が画像より横長な、
## 普通の場合)ときは、上側だけが見切れる(絵の下寄りにいるキャラクターを残すため)。TextureRectの
## STRETCH_KEEP_ASPECT_COVEREDは上下を均等に切るので使えず、大きさと位置は_layout_backgroundで決める。
func _build_background() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var frame := Control.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	var picture := TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture = load(BACKGROUND_TEXTURE_PATH)
	frame.add_child(picture)
	frame.resized.connect(_layout_background.bind(frame, picture)) # 画面の大きさ・向きが変わるたびに置き直す
	layer.add_child(frame)
	_layout_background(frame, picture)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = BACKGROUND_DIM_COLOR
	layer.add_child(dim)

func _layout_background(frame: Control, picture: TextureRect) -> void:
	var texture_size := picture.texture.get_size()
	if frame.size.x <= 0.0 or frame.size.y <= 0.0 or texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var fit := maxf(frame.size.x / texture_size.x, frame.size.y / texture_size.y)
	var fitted := texture_size * fit
	picture.size = fitted
	picture.position = Vector2((frame.size.x - fitted.x) * 0.5, frame.size.y - fitted.y)

## BGMを1曲、ループ再生する(2026-09-22)。ライセンス条件はgodot/licenses/LICENSE-AUDIO.md参照
## (音楽・効果音・フォントを追加する時の手順は、license_info.gd冒頭のコメントに同じ)。
## 音量調整UIは今回は作らない(設定メニューを別途用意する時にまとめて追加する予定、要望どおり)。
## そのため控えめな音量(BGM_VOLUME_DB)に固定してある。
const BGM_PATH := "res://assets/music/bgm_forest_journey.mp3"
const BGM_SILENT_DB := -80.0 # ミュート・音量0の代わり(stream_pausedは使わず、再生位置を保ったまま無音にする)

var bgm_player: AudioStreamPlayer

func _build_bgm() -> void:
	bgm_player = AudioStreamPlayer.new()
	add_child(bgm_player) # 音源が無くても作っておく(設定画面の音量変更などが参照するため)
	# 音源ファイルはライセンス上リポジトリに入れていない(.gitignore)。新しいクローンやCIのビルドには
	# 無いので、その場合はBGM無しで起動する(2026-09-23)
	if not ResourceLoader.exists(BGM_PATH):
		push_warning("BGMの音源が見つからないため、BGM無しで起動します: " + BGM_PATH)
		return
	var stream: AudioStream = load(BGM_PATH)
	if stream is AudioStreamMP3:
		stream.loop = true # ファイル自体にループ再生を持たせる(AudioStreamPlayerのfinishedを拾って再生し直す必要が無い)
	bgm_player.stream = stream
	bgm_player.volume_db = _bgm_volume_db()
	bgm_player.play()
	Settings.changed.connect(func(): bgm_player.volume_db = _bgm_volume_db()) # 設定画面のスライダー/ミュートに即反映する

## Settings.bgm_volume(0.0〜1.0の線形値)を、AudioStreamPlayer.volume_dbへ変換する(2026-09-22)。
## ミュート中、または音量0の時は、再生を止めず(seek位置を保つ)、聞こえないほど下げるだけにする。
func _bgm_volume_db() -> float:
	if Settings.bgm_muted or Settings.bgm_volume <= 0.0:
		return BGM_SILENT_DB
	return linear_to_db(Settings.bgm_volume)

func _build_ui() -> void:
	_build_background()
	_build_bgm()
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# 雇用/探索者管理/行動ログ/セーブは全て画面中央に開くポップアップなので、
	# 同時に開けると重なってしまう。開いている間は背後に敷いて他の操作を受け付けない
	# 半透明の遮断レイヤー(常に1枚だけ存在し、_open_modal/_close_modalで使い回す)。
	modal_blocker = ColorRect.new()
	modal_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_blocker.color = Color(0.03, 0.03, 0.05, 0.92) # 背景(マップ等)を透かしすぎないよう、ほぼ不透明に
	modal_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_blocker.visible = false
	add_child(modal_blocker)

	left_scroll = ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(240, 0)
	root.add_child(left_scroll)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _touch_ui:
		# スクロールバーは出さない(全部のボタンが収まる高さに_fit_left_menuが合わせるため。万一収まらない
		# 小さい画面では、ボタン以外をドラッグすれば動かせる)。横には動かさない。ボタンがスクロールバーや
		# マップの縁に張り付かないよう、ボタン列の右に余白を置く(ボタン自体の幅は変えない)。
		left_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var left_margin := MarginContainer.new()
		left_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_margin.add_theme_constant_override("margin_right", LEFT_MENU_RIGHT_MARGIN)
		left_scroll.add_child(left_margin)
		left_margin.add_child(left)
	else:
		left_scroll.add_child(left)
	left_menu = left
	if _touch_ui:
		# スクロールしなくても全部のボタンが画面に収まるよう、左メニューのボタンだけ余白を小さく作る。
		# 高さの調整は_fit_left_menu()。
		left.theme = _compact_button_theme()
		# 画面サイズの変化と、行やラベルの増減・高さの変化(次の月へボタンの出入り、文字の設定など)のたびに取り直す
		left_scroll.resized.connect(_queue_fit_left_menu)
		left.minimum_size_changed.connect(_queue_fit_left_menu)

	funds_label = Label.new()
	left.add_child(funds_label)

	date_label = Label.new()
	date_label.add_theme_font_size_override("font_size", 12)
	left.add_child(date_label)

	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 12)
	time_label.modulate = Color(1, 1, 1, 0.7)
	left.add_child(time_label)

	# 今日・今月のバーと「次の月へ」ボタンは、同じ場所に重ねて置き、月末の集計待ちの間だけボタンを見せる
	# (2026-09-24。以前はボタンをバーの下に1行足していて、月末のたびにメニューが伸び縮みしていた)。
	# MarginContainerは子を重ねて並べるので、高さは両者の大きい方で固定になる。
	var time_stack := MarginContainer.new()
	left.add_child(time_stack)
	time_bars_box = VBoxContainer.new()
	time_bars_box.alignment = BoxContainer.ALIGNMENT_CENTER
	time_stack.add_child(time_bars_box)
	day_bar = TimeBar.new()
	day_caption = _add_time_bar_row(time_bars_box, day_bar, 10.0)
	month_bar = TimeBar.new()
	month_caption = _add_time_bar_row(time_bars_box, month_bar, 6.0)
	next_month_button = Button.new()
	next_month_button.text = "次の月へ ▶"
	next_month_button.pressed.connect(_on_next_month_pressed)
	_apply_primary_button_style(next_month_button)
	time_stack.add_child(next_month_button)
	_set_next_month_shown(false)

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

	# 資金/時間以外の各機能は、ボタンが増えて240px幅のサイドバーに収まりきらなくなったため、
	# ボタン1つで開くポップアップパネルにまとめてある(行動ログ・セーブスロットと同じパターン)。
	var hire_button := Button.new()
	hire_button.text = "🧑 雇用"
	hire_button.pressed.connect(_on_open_hire_pressed)
	left.add_child(hire_button)

	var npc_button := Button.new()
	npc_button.text = "📋 探索者管理"
	npc_button.pressed.connect(_on_open_npc_panel_pressed)
	left.add_child(npc_button)

	party_button = Button.new()
	party_button.text = "🧩 パーティ"
	party_button.pressed.connect(_on_open_party_panel_pressed)
	left.add_child(party_button)

	var shop_button := Button.new()
	shop_button.text = "🏪 武器防具屋"
	shop_button.pressed.connect(_on_open_shop_pressed)
	left.add_child(shop_button)

	var slot_button := Button.new()
	slot_button.text = "💾 セーブ/ロード"
	slot_button.pressed.connect(_on_open_slots_pressed)
	left.add_child(slot_button)

	# 設定(BGM音量/ミュート、イベント戦闘の戦闘画面ON-OFF。2026-09-22)。ライセンスと同じく日常的には
	# 使わないので、その直上に置く。
	var settings_button := Button.new()
	settings_button.text = "⚙️ 設定"
	settings_button.pressed.connect(_on_open_settings_pressed)
	left.add_child(settings_button)

	# ライセンス表示(画像・Godot・godot-sqlite・音楽)。日常的には使わないので、メニューの
	# ボタンとしては一番下に置く。
	var license_button := Button.new()
	license_button.text = "📄 ライセンス"
	license_button.pressed.connect(_on_open_license_pressed)
	left.add_child(license_button)

	if _touch_ui:
		# 最下のボタンが画面の下端に張り付かないよう、下に余白を置く(_fit_left_menuの高さの計算にも含まれる)
		var bottom_spacer := Control.new()
		bottom_spacer.custom_minimum_size = Vector2(0, LEFT_MENU_BOTTOM_MARGIN)
		bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left.add_child(bottom_spacer)

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
	# 手前に重ねて表示する。WorldMap.areasはオートロードのWorldSchemaDbが(シナリオから)既に流し込み済みなので、
	# ボタン自体はここで一度作ればよい(選択状態・🔒表示は_refresh_area_tabsで更新する)。
	area_nav_panel = PanelContainer.new()
	area_nav_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var area_nav_style := StyleBoxFlat.new()
	area_nav_style.bg_color = Color(0.05, 0.05, 0.07, 0.9)
	area_nav_style.content_margin_left = 6
	area_nav_style.content_margin_right = 6
	area_nav_style.content_margin_top = 4
	area_nav_style.content_margin_bottom = 4
	area_nav_panel.add_theme_stylebox_override("panel", area_nav_style)
	map_area.add_child(area_nav_panel)

	_rebuild_area_nav()
	_build_log_window(map_area) # エリアバーの後に追加して、その手前に重ねる

## エリア選択バーを、今のWorldMap.areasから(作り直して)組み立てる。別のシナリオ(別の世界)へ切り替えると
## エリアの顔ぶれが変わるため、_refresh_all()が_built_world_versionとの違いを見つけて呼び直す。
func _rebuild_area_nav() -> void:
	for child in area_nav_panel.get_children():
		area_nav_panel.remove_child(child)
		child.queue_free()
	area_tab_buttons.clear()
	area_option = null
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
	_built_world_version = WorldSchemaDb.active_version_id
	if not WorldMap.areas.has(_active_area_id):
		_active_area_id = WorldMap.areas.keys()[0] if not WorldMap.areas.is_empty() else "" # 既定は最初のエリア

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

## 雇用/探索者管理/行動ログ/セーブ/掲示板のポップアップパネルを、他を必ず閉じた上で1つだけ開く。
## 遮断レイヤーも一緒に前面へ持ってきて、開いている間はマップや他のパネルを操作できなくする。
func _open_modal(panel: PanelContainer) -> void:
	for p in [hire_panel, npc_panel, party_panel, shop_panel, slot_panel, node_detail_panel, section_assign_panel, license_panel, battle_panel, settings_panel]:
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
	else:
		# デスクトップ: 下端から浮かせ(DESKTOP_DIALOGUE_LIFT)、内容が高さを超えても上へ伸びるようにする。
		# パネルのどこをクリックしても次へ進む(_on_dialogue_panel_gui_input)。
		dialogue_panel.offset_top = -(dialogue_height + DESKTOP_DIALOGUE_LIFT)
		dialogue_panel.offset_bottom = -DESKTOP_DIALOGUE_LIFT
		dialogue_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		dialogue_panel.gui_input.connect(_on_dialogue_panel_gui_input)
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

	# 発言者名の行: 左に名前、右に会話の種別バッジ(_apply_dialogue_style)
	var name_row := HBoxContainer.new()
	center.add_child(name_row)

	speaker_name_label = Label.new()
	speaker_name_label.add_theme_font_size_override("font_size", 20)
	speaker_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(speaker_name_label)

	dialogue_kind_badge = PanelContainer.new()
	dialogue_kind_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE # クリックを、会話パネル(どこをクリックしても進む)へ通す
	dialogue_kind_badge.visible = false
	dialogue_kind_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(dialogue_kind_badge)

	dialogue_kind_label = Label.new()
	dialogue_kind_label.add_theme_font_size_override("font_size", 14)
	dialogue_kind_badge.add_child(dialogue_kind_label)

	dialogue_text_label = Label.new()
	dialogue_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # クリックを、会話パネル(どこをクリックしても進む)へ通す
	slot.add_child(rect)
	# 話者の画像(EventPortraits)。画像が無い間は隠しておき、色付きの四角(base_color)がそのまま見える。
	var image_rect := TextureRect.new()
	image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	image_rect.visible = false
	rect.add_child(image_rect)
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

## 枠に話者の画像を出す(portrait_idが空、または画像が無ければ隠す)。画像は、その枠が次に別の話者で
## 埋まるか会話が終わるまで残り、話していない間は_dim_portrait_slotで暗くなるだけで消えない。
func _set_portrait_slot_image(slot: VBoxContainer, portrait_id: String) -> void:
	var image_rect: TextureRect = slot.get_child(0).get_child(0)
	var texture: Texture2D = EventPortraits.load_texture(portrait_id)
	image_rect.texture = texture
	image_rect.visible = texture != null

## イベント会話の種別ごとの表示スタイル(2026-09-20)。パネルの縁と背景、発言者名、種別バッジ、次へ/選択肢の
## ボタンが、この色(accent)で揃う。種別はEventDialogue.play()の引数で決まる(フロアのイベントは、ゲートの種類から
## WorldMap.event_kind_for_nodeが自動で決める)。色の意味: ボス戦=赤、戦闘=朱、技能=青(通常の進行)、
## アイテム=金、血筋=紫、案内=灰。結果(突破/失敗)は色を変えず、バッジの文字と、失敗時の彩度の低下で示す。
const EVENT_STYLES := {
	"boss": {"label": "ボス戦", "accent": Color(0.92, 0.26, 0.24)},
	"combat": {"label": "戦闘", "accent": Color(0.95, 0.55, 0.2)},
	"skill": {"label": "技能", "accent": Color(0.32, 0.58, 0.96)},
	"item": {"label": "アイテム", "accent": Color(0.95, 0.78, 0.25)},
	"bloodline": {"label": "血筋", "accent": Color(0.68, 0.45, 0.92)},
	"guide": {"label": "案内", "accent": Color(0.62, 0.68, 0.74)},
}
const EVENT_RESULT_LABELS := {"pass": "突破", "fail": "失敗"}

func _apply_dialogue_style(kind: String, result: String) -> void:
	if not EVENT_STYLES.has(kind):
		# 種別なし: 従来の見た目に戻す
		_dialogue_accent = Color.TRANSPARENT
		dialogue_panel.remove_theme_stylebox_override("panel")
		speaker_name_label.remove_theme_color_override("font_color")
		dialogue_kind_badge.visible = false
		_apply_dialogue_button_style(advance_hint)
		return

	var accent: Color = EVENT_STYLES[kind]["accent"]
	if result == "fail":
		accent = accent.lerp(Color(0.5, 0.5, 0.5), 0.45) # 失敗は、同じ色味のまま彩度を落とす
	_dialogue_accent = accent

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(accent.darkened(0.8), 0.96)
	panel_style.border_color = accent
	panel_style.set_border_width_all(3)
	panel_style.border_width_top = 6
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(8)
	dialogue_panel.add_theme_stylebox_override("panel", panel_style)
	speaker_name_label.add_theme_color_override("font_color", accent.lightened(0.55))

	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = accent.darkened(0.1)
	badge_style.set_corner_radius_all(8)
	badge_style.content_margin_left = 10
	badge_style.content_margin_right = 10
	badge_style.content_margin_top = 2
	badge_style.content_margin_bottom = 2
	dialogue_kind_badge.add_theme_stylebox_override("panel", badge_style)
	var badge_text: String = EVENT_STYLES[kind]["label"]
	if EVENT_RESULT_LABELS.has(result):
		badge_text += " ― " + EVENT_RESULT_LABELS[result]
	dialogue_kind_label.text = badge_text
	dialogue_kind_badge.visible = true
	_apply_dialogue_button_style(advance_hint)

## 会話の「次へ」や選択肢のボタンに、今の会話の色(_dialogue_accent)を付ける。種別なしなら共通テーマに戻す。
func _apply_dialogue_button_style(button: Button) -> void:
	if _dialogue_accent == Color.TRANSPARENT:
		for state in ["normal", "hover", "pressed", "focus"]:
			button.remove_theme_stylebox_override(state)
		return
	var margin_v: int = TOUCH_BUTTON_MARGIN_V if _touch_ui else 6
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = _dialogue_accent.darkened({"normal": 0.55, "hover": 0.4, "pressed": 0.2}[state])
		style.border_color = _dialogue_accent
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = margin_v
		style.content_margin_bottom = margin_v
		button.add_theme_stylebox_override(state, style)

func _on_dialogue_line_shown(line: Dictionary) -> void:
	dialogue_panel.visible = true
	speaker_name_label.text = line.get("name", "")
	dialogue_text_label.text = line.get("text", "")
	var kind: String = line.get("kind", EventDialogue.current_kind)
	_apply_dialogue_style(kind, line.get("result", EventDialogue.current_result))

	var side: String = line.get("side", "none")
	var speaker: String = line.get("name", "")
	# 画像は、行の"image"(その行だけの指定)、無ければ登場人物表(cast)の割り当て、無ければ名前からの自動選択の順
	var line_image: String = line.get("image", "")
	if side == "left":
		if speaker != "":
			_set_portrait_slot_image(left_slot, line_image if line_image != "" else EventPortraits.portrait_id(speaker, kind))
		_highlight_portrait_slot(left_slot, speaker)
	else:
		_dim_portrait_slot(left_slot)
	if side == "right":
		if speaker != "":
			_set_portrait_slot_image(right_slot, line_image if line_image != "" else EventPortraits.portrait_id(speaker, kind))
		_highlight_portrait_slot(right_slot, speaker)
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
		_apply_dialogue_button_style(choice_button)
		choices_box.add_child(choice_button)

func _on_dialogue_finished(_outcome: String) -> void:
	# ゲーム状態への反映(ゲート突破の適用など)はExploration側が個別に処理する。
	# ここではUIを閉じて最新状態を反映するだけ。
	dialogue_panel.visible = false
	_set_portrait_slot_image(left_slot, "") # 次の会話に前の話者の顔が残らないようにする
	_set_portrait_slot_image(right_slot, "")
	_refresh_map()
	# 導入会話・後編("intro_part2")の予約消化。他の会話(フロア発見時のVN等)
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
	if SaveSystem.is_tutorial_seen("intro_part2") or _pending_assignment_followup:
		return
	_pending_assignment_followup = true
	call_deferred("_try_show_assignment_followup_tutorial")

func _try_show_assignment_followup_tutorial() -> void:
	if not _pending_assignment_followup or EventDialogue.is_active:
		return
	_pending_assignment_followup = false
	# dialogue_panelはhire_panel等のモーダルより手前に重ねていない(_open_modalの管理対象外)ため、
	# パーティパネル/割り当てモーダルを開いたまま再生すると会話が背後に隠れて見えなくなる
	# ("party_formed"の再生箇所と同じ理由)。先に閉じてから再生する。
	_close_any_modal()
	ScenarioEvents.play_guide("intro_part2")

## 開いているモーダルパネルを問わず全て閉じる(_open_modal/_close_modalは特定の1枚を
## 対象にする作りのため、「今何が開いているか分からないが、とにかく閉じたい」場面用に用意)。
func _close_any_modal() -> void:
	# 戦闘画面が開いたままここへ来ることは通常無い(入力を塞ぐモーダルなので、閉じる操作自体ができない)が、
	# 万一に備え、開いていればBattleScreen側にも閉じたことを伝える(でないとexploration.gdがclosedを待ち続け、
	# 時間が止まったままになる)。
	if battle_panel.visible:
		BattleScreen.close()
	for p in [hire_panel, npc_panel, party_panel, shop_panel, slot_panel, node_detail_panel, section_assign_panel, license_panel, battle_panel, settings_panel]:
		p.visible = false
	modal_blocker.visible = false

## ログウィンドウ(LogWindow): 毎日の動き・行動ログ・掲示板をタブで切り替える。マップの右端に半透明で重ね、
## マップ右上のフロートボタン(log_toggle_button)で出し入れする(2026-09-24)。モーダルではないので、
## 開いたままマップを操作できる。以前は、画面中央のモーダルの「ログ」(2種を左右に並べる)と、タッチUIの
## 右端の「掲示板」ウィンドウ(直近10件)が別々にあり、同じ掲示板を見る入口が重複していた。
func _build_log_window(map_area: Control) -> void:
	log_toggle_button = Button.new()
	log_toggle_button.text = "📜 ログ"
	log_toggle_button.toggle_mode = true
	log_toggle_button.tooltip_text = "毎日の動き・行動ログ・掲示板"
	log_toggle_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_toggle_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	log_toggle_button.toggled.connect(_set_log_window_visible)
	map_area.add_child(log_toggle_button)

	log_window = LogWindow.new()
	log_window.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	log_window.offset_left = -(LOG_WINDOW_WIDTH_TOUCH if _touch_ui else LOG_WINDOW_WIDTH_DESKTOP)
	log_window.offset_right = -4
	log_window.offset_bottom = -8
	if _touch_ui:
		log_window.theme = _compact_button_theme() # 見出しの小さなボタン用
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	style.border_color = Color(1, 1, 1, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	log_window.add_theme_stylebox_override("panel", style)
	log_window.close_requested.connect(_set_log_window_visible.bind(false))
	map_area.add_child(log_window)

	# エリア選択バーの高さ(文字の設定・画面幅で変わる)に合わせて、ボタンとウィンドウをその下に置く
	area_nav_panel.resized.connect(_place_log_window)
	log_toggle_button.minimum_size_changed.connect(_place_log_window)
	_place_log_window.call_deferred()

func _place_log_window() -> void:
	var top := area_nav_panel.size.y + 4
	var button_size := log_toggle_button.get_combined_minimum_size()
	log_toggle_button.offset_top = top
	log_toggle_button.offset_bottom = top + button_size.y
	log_toggle_button.offset_right = -4
	log_toggle_button.offset_left = -4 - button_size.x
	log_window.offset_top = log_toggle_button.offset_bottom + 4

func _set_log_window_visible(shown: bool) -> void:
	log_window.visible = shown
	log_toggle_button.set_pressed_no_signal(shown) # ✕や戻るで閉じた時も、ボタンの押された状態を戻す
	if shown:
		log_window.refresh()

## 掲示板のスレッド(""なら全体フィード)を、ログウィンドウの掲示板タブで開く。ポップアップ(セクションの
## 割り当て画面など)から開いた場合は、ポップアップを閉じる(ログウィンドウはマップの上に出るため)。
func _open_board_log(thread_id: String) -> void:
	if modal_blocker.visible and not battle_panel.visible:
		_close_any_modal()
	log_window.show_board_thread(thread_id)
	_set_log_window_visible(true)

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

## 設定画面(2026-09-22)。端末ごとの設定(Settings、セーブスロットとは無関係)を直接操作する。
## BGM音量・ミュートと、イベント戦闘の戦闘画面ON-OFFの2項目(配色など他の項目は優先度低のため今回は含めない)。
func _build_settings_ui() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	settings_panel.offset_left = -220
	settings_panel.offset_top = -100
	settings_panel.offset_right = 220
	settings_panel.offset_bottom = 100
	settings_panel.visible = false
	add_child(settings_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	settings_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "設定"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(settings_panel))
	header.add_child(close_button)

	var bgm_label := Label.new()
	bgm_label.text = "BGM音量"
	col.add_child(bgm_label)
	var bgm_row := HBoxContainer.new()
	col.add_child(bgm_row)
	settings_bgm_slider = HSlider.new()
	settings_bgm_slider.min_value = 0.0
	settings_bgm_slider.max_value = 1.0
	settings_bgm_slider.step = 0.05
	settings_bgm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_bgm_slider.custom_minimum_size = Vector2(0, TOUCH_BUTTON_MARGIN_V if _touch_ui else 0) # タッチUIで掴みやすい高さに
	settings_bgm_slider.value_changed.connect(func(v: float): Settings.set_bgm_volume(v))
	bgm_row.add_child(settings_bgm_slider)
	settings_bgm_mute_check = CheckBox.new()
	settings_bgm_mute_check.text = "ミュート"
	settings_bgm_mute_check.toggled.connect(func(pressed: bool): Settings.set_bgm_muted(pressed))
	bgm_row.add_child(settings_bgm_mute_check)

	settings_battle_screen_check = CheckBox.new()
	settings_battle_screen_check.text = "イベント戦闘で戦闘画面を表示する"
	settings_battle_screen_check.toggled.connect(func(pressed: bool): Settings.set_show_battle_screen(pressed))
	col.add_child(settings_battle_screen_check)

func _on_open_settings_pressed() -> void:
	settings_bgm_slider.set_value_no_signal(Settings.bgm_volume)
	settings_bgm_mute_check.set_pressed_no_signal(Settings.bgm_muted)
	settings_battle_screen_check.set_pressed_no_signal(Settings.show_battle_screen)
	_open_modal(settings_panel)

## ボタンの内側余白(上下)を小さくしたテーマ。共通テーマのボタンのスタイルを複製して、余白だけ変える。
## 左メニューや掲示板ウィンドウなど、縦の余裕が無い場所のControlに設定して使う。
func _compact_button_theme() -> Theme:
	var compact := Theme.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style: StyleBoxFlat = theme.get_stylebox(state, "Button").duplicate()
		style.content_margin_top = LEFT_MENU_BUTTON_MARGIN_V
		style.content_margin_bottom = LEFT_MENU_BUTTON_MARGIN_V
		compact.set_stylebox(state, "Button", style)
	return compact

## タッチUIの左メニューを、スクロール無しで画面に収める(可能な範囲で)。ボタンの内側余白は小さく作って
## あるので、まずその「自然な高さ」で並べた時の合計を求め、画面の高さに余りがあれば、行数で割った分だけ
## 各ボタンの行を縦に広げる。広げる幅には上限があり、以前の見た目(TOUCH_BUTTON_MARGIN_V)より大きくは
## しない。小さい画面で自然な高さでも収まらない場合は、そのまま(従来どおりスクロールになる)。
##
## 合計は、メニュー全体の最小サイズ(広げた分を含み、文字の設定などのタイミングで古い値が残る)を
## 使わず、各行の自然な高さ(get_minimum_size)と、ラベルの高さ、行の間隔から直接足して求める。
## 広げた結果でメニューの最小サイズが変わっても同じ値を求め直すだけなので、繰り返しは収束する。
func _fit_left_menu() -> void:
	_fit_left_menu_pending = false
	if left_scroll == null or left_menu == null:
		return
	var rows: Array[Control] = []
	var natural_total := 0.0
	var visible_count := 0
	for child in left_menu.get_children():
		if not child.visible:
			continue
		visible_count += 1
		# ボタンと、倍速ボタンの行(HBoxContainer)が対象。文字ラベルは、そのままの高さで数える
		if child is Button or child is HBoxContainer:
			rows.append(child)
			natural_total += child.get_minimum_size().y
		else:
			natural_total += child.get_combined_minimum_size().y
	if rows.is_empty():
		return
	natural_total += left_menu.get_theme_constant("separation") * (visible_count - 1)
	var max_extra := float(TOUCH_BUTTON_MARGIN_V - LEFT_MENU_BUTTON_MARGIN_V) * 2.0
	var extra := clampf((left_scroll.size.y - natural_total) / rows.size(), 0.0, max_extra)
	for row in rows:
		row.custom_minimum_size.y = row.get_minimum_size().y + extra

## 左メニューの高さの調整を、このフレームの終わりに1回だけ行う(短い間に何度も呼ばれても1回にまとめる)。
func _queue_fit_left_menu() -> void:
	if _fit_left_menu_pending:
		return
	_fit_left_menu_pending = true
	_fit_left_menu.call_deferred()

## フロア詳細パネル。マップ上でフロアの箱をタップ(クリック)すると開く(_on_map_tap)。
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

## 戦闘画面(design.md 5.4節、2026-09-22)。イベント戦闘(会話の付いた戦闘ゲート)の実際の攻防を、
## パーティ4人を上段、敵を中央、ラウンドの様子を下段の文字に出して再現する。BattleScreenのopened/closedを
## 聞いて開閉する(exploration.gdは、このシグナルの往復だけでやり取りし、main.gdへの参照を持たない)。
func _build_battle_screen_ui() -> void:
	battle_panel = PanelContainer.new()
	battle_panel.set_anchors_preset(Control.PRESET_CENTER)
	battle_panel.offset_left = -300
	battle_panel.offset_top = -260
	battle_panel.offset_right = 300
	battle_panel.offset_bottom = 260
	battle_panel.visible = false
	add_child(battle_panel)

	battle_click_catcher = Control.new()
	battle_click_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	battle_click_catcher.mouse_filter = Control.MOUSE_FILTER_PASS # 下の中身(ボタン等)へクリックを通しつつ、自分でも拾う
	battle_click_catcher.gui_input.connect(_on_battle_panel_gui_input)
	battle_panel.add_child(battle_click_catcher)

	var col := VBoxContainer.new()
	battle_panel.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	battle_title_label = Label.new()
	battle_title_label.add_theme_font_size_override("font_size", 18)
	battle_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(battle_title_label)
	battle_kind_badge = Label.new()
	battle_kind_badge.add_theme_font_size_override("font_size", 13)
	header.add_child(battle_kind_badge)

	# 敵を上、パーティを下に置く(2026-09-23。「実際に見ると敵が上・パーティが下の方が良い」との
	# 指摘への対応。対峙する相手を先に見せてから自分たちの並びを見る方が読みやすい)。
	var enemy_row := HBoxContainer.new()
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(enemy_row)
	var enemy_slot := _create_battle_party_slot(enemy_row, "", true)
	battle_enemy_portrait = enemy_slot["portrait"]
	battle_enemy_name_label = enemy_slot["name"]
	battle_enemy_hp_bar = enemy_slot["hp_bar"]
	battle_enemy_hp_label = enemy_slot["hp_label"]
	enemy_slot["order_label"].visible = false

	var vs_label := Label.new()
	vs_label.text = "VS"
	vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_label.add_theme_font_size_override("font_size", 16)
	vs_label.modulate = Color(1, 1, 1, 0.7)
	col.add_child(vs_label)

	var party_row := HBoxContainer.new()
	party_row.alignment = BoxContainer.ALIGNMENT_CENTER
	party_row.add_theme_constant_override("separation", 10)
	col.add_child(party_row)
	battle_party_slots.clear()
	for i in range(Parties.MAX_PARTY_SIZE):
		battle_party_slots.append(_create_battle_party_slot(party_row, "先頭" if i == 0 else "%d番手" % (i + 1)))

	battle_log = RichTextLabel.new()
	battle_log.custom_minimum_size = Vector2(0, 110)
	battle_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_log.scroll_following = true # 行が増えるたびに末尾へ自動でスクロール
	battle_log.bbcode_enabled = true
	battle_log.mouse_filter = Control.MOUSE_FILTER_IGNORE # クリックはbattle_click_catcherに任せる(早送り)
	col.add_child(battle_log)

	var footer := HBoxContainer.new()
	col.add_child(footer)
	var footer_hint := Label.new()
	footer_hint.text = "画面をタップで早送り"
	footer_hint.modulate = Color(1, 1, 1, 0.6)
	footer_hint.add_theme_font_size_override("font_size", 12)
	footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_hint)
	battle_skip_button = Button.new()
	battle_skip_button.text = "▶▶ 早送り"
	battle_skip_button.pressed.connect(_on_battle_skip_pressed)
	footer.add_child(battle_skip_button)
	battle_close_button = Button.new()
	battle_close_button.text = "閉じる"
	battle_close_button.visible = false
	battle_close_button.pressed.connect(_on_battle_close_pressed)
	_apply_primary_button_style(battle_close_button)
	footer.add_child(battle_close_button)

	_battle_timer = Timer.new()
	_battle_timer.one_shot = true
	_battle_timer.wait_time = BATTLE_ROUND_DELAY_SEC
	_battle_timer.timeout.connect(_advance_battle_round)
	add_child(_battle_timer)

	BattleScreen.opened.connect(_on_battle_screen_opened)

## 戦闘画面のパーティ/敵1枠(肖像・名前・HPバー・HP文字)。party_rowにもenemy_rowにも同じ形で使う。
## is_enemyなら、HPバーを共有Theme(_build_theme())の"EnemyHPBar"バリエーション(赤系)にする。
func _create_battle_party_slot(parent: Control, order_text: String, is_enemy: bool = false) -> Dictionary:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(110, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(box)

	var order_label := Label.new()
	order_label.text = order_text
	order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_label.add_theme_font_size_override("font_size", 11)
	order_label.modulate = Color(1, 1, 1, 0.7)
	box.add_child(order_label)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(64, 64)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.clip_contents = true
	box.add_child(frame)
	var portrait := Control.new()
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(portrait)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)

	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 12)
	hp_bar.show_percentage = false
	if is_enemy:
		hp_bar.theme_type_variation = "EnemyHPBar"
	box.add_child(hp_bar)

	var hp_label := Label.new()
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 11)
	hp_label.modulate = Color(1, 1, 1, 0.8)
	box.add_child(hp_label)

	return {"frame": frame, "portrait": portrait, "name": name_label, "hp_bar": hp_bar, "hp_label": hp_label, "order_label": order_label}

## 戦闘画面を開く(BattleScreen.opened)。dataは_maybe_show_battle_screen(exploration.gd)が渡す
## {"trace", "passed", "result", "enemy_start_power", "enemy_name", "kind", "member_ids"}。
func _on_battle_screen_opened(data: Dictionary) -> void:
	_battle_trace = data.get("trace", [])
	_battle_round_index = 0
	_battle_enemy_hp = int(data.get("enemy_start_power", 0))
	_battle_result_kind = String(data.get("result", ""))
	var kind: String = data.get("kind", "")

	battle_title_label.text = "戦闘"
	if EVENT_STYLES.has(kind):
		battle_kind_badge.text = EVENT_STYLES[kind]["label"]
		battle_kind_badge.modulate = EVENT_STYLES[kind]["accent"]
	else:
		battle_kind_badge.text = ""

	# パーティは、選択中のパーティではなく「戦ったパーティ」を出す必要がある。traceの先頭のnpc_idから
	# 所属パーティを逆引きする(未割当や退避などでも、戦った時点のメンバー構成をそのまま表示できる)。
	var member_ids: Array = data.get("member_ids", [])
	_battle_slot_index_by_npc.clear()
	for i in range(battle_party_slots.size()):
		var slot: Dictionary = battle_party_slots[i]
		if i < member_ids.size():
			var npc_id: int = member_ids[i]
			_battle_slot_index_by_npc[npc_id] = i
			_fill_battle_slot(slot, npc_id)
			slot["frame"].visible = true
			slot["hp_bar"].visible = true
		else:
			slot["frame"].visible = false
			slot["name"].text = ""
			slot["hp_bar"].visible = false
			slot["hp_label"].text = ""
		_set_battle_slot_active(slot, false)

	var enemy_name: String = data.get("enemy_name", "")
	battle_enemy_name_label.text = enemy_name if enemy_name != "" else "敵"
	_set_battle_portrait_texture(battle_enemy_portrait, EventPortraits.load_texture(EventPortraits.portrait_id(enemy_name, kind if kind != "" else "combat")))
	battle_enemy_hp_bar.max_value = max(1, _battle_enemy_hp)
	battle_enemy_hp_bar.value = _battle_enemy_hp
	battle_enemy_hp_label.text = str(_battle_enemy_hp)

	battle_log.clear()
	battle_log.append_text("[color=#9ecbff]%s が現れた![/color]\n" % battle_enemy_name_label.text)

	_open_modal(battle_panel)
	if _battle_result_kind == "retreat_before_fight":
		# 満タンHPでも勝てないと分かっている(_is_hopeless_gate)ので、そもそも打ち合わない。traceが
		# 空でラウンドを再生しようがないため、ここで直接「結果」まで進める(2026-09-23)。
		battle_skip_button.visible = false
		battle_close_button.visible = false
		_finish_battle_rounds()
	else:
		battle_skip_button.visible = true
		battle_close_button.visible = false
		_battle_timer.start()

func _fill_battle_slot(slot: Dictionary, npc_id: int) -> void:
	var npc := Npcs.get_npc(npc_id)
	slot["name"].text = npc.get("name", "?")
	_set_battle_portrait_control(slot["portrait"], _create_portrait_content(npc))
	var max_hp: float = float(npc.get("max_hp", 100.0))
	# トレースにこのメンバーの最初のラウンドがあれば、そのhp_before(=このメンバーが戦い始めた時点のHP)から
	# 再生する(現在のNpcs側のhpは、既に戦闘が確定した後の最終値になっているため)。トレースが無い(=一度も
	# 出番が無かった)メンバーは、現在のhpをそのまま満タン表示として使う。
	var start_hp: float = float(npc.get("hp", max_hp))
	for entry in _battle_trace:
		if int(entry["npc_id"]) == npc_id:
			start_hp = float(entry["hp_before"])
			break
	slot["hp_bar"].max_value = max(1.0, max_hp)
	slot["hp_bar"].value = maxf(0.0, start_hp)
	slot["hp_label"].text = "%d/%d" % [maxi(0, roundi(start_hp)), roundi(max_hp)]

## パーティ側: _create_portrait_content()(肖像があればTextureRect、無ければ頭文字のLabel)をそのまま差し込む。
func _set_battle_portrait_control(portrait: Control, content: Control) -> void:
	for child in portrait.get_children():
		portrait.remove_child(child)
		child.queue_free()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.add_child(content)

## 敵側: EventPortraits.load_texture()の結果(見つからなければnull)を差し込む。
func _set_battle_portrait_texture(portrait: Control, texture: Texture2D) -> void:
	for child in portrait.get_children():
		portrait.remove_child(child)
		child.queue_free()
	if texture == null:
		return
	var texture_rect := TextureRect.new()
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture = texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.add_child(texture_rect)

## 今まさに動いているメンバーの枠を、他より目立たせる(黄色い縁)。
func _set_battle_slot_active(slot: Dictionary, active: bool) -> void:
	if not active:
		slot["frame"].remove_theme_stylebox_override("panel")
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 1.0)
	style.border_color = Color(1.0, 0.85, 0.3, 1.0)
	style.set_border_width_all(3)
	slot["frame"].add_theme_stylebox_override("panel", style)

func _on_battle_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_battle_round()
	elif event is InputEventScreenTouch and event.pressed:
		_advance_battle_round()

func _on_battle_skip_pressed() -> void:
	# 残りラウンドを、一瞬で(間を置かずに)最後まで適用する。ログは最後の数行だけ載せれば十分。
	while _battle_round_index < _battle_trace.size():
		_apply_battle_round(_battle_trace[_battle_round_index], false)
		_battle_round_index += 1
	_finish_battle_rounds()

## 1ラウンド分を進める(タイマー満了・タップ・「早送り」で共通)。既に最後まで進んでいれば何もしない
## (自動タイマーが結果表示の後に発火しても無害にするため)。
func _advance_battle_round() -> void:
	if _battle_round_index >= _battle_trace.size():
		return
	_apply_battle_round(_battle_trace[_battle_round_index], true)
	_battle_round_index += 1
	if _battle_round_index >= _battle_trace.size():
		_finish_battle_rounds()
	else:
		_battle_timer.start()

## traceの1エントリをHPバー・ハイライト・ログへ反映する。log_lineがtrueならログにも1行足す(早送り中はfalseで省く)。
func _apply_battle_round(entry: Dictionary, log_line: bool) -> void:
	var npc_id: int = entry["npc_id"]
	if not _battle_slot_index_by_npc.has(npc_id):
		return
	var slot: Dictionary = battle_party_slots[_battle_slot_index_by_npc[npc_id]]
	for other in battle_party_slots:
		_set_battle_slot_active(other, other == slot)

	var hp_after: float = maxf(0.0, float(entry["hp_after"]))
	slot["hp_bar"].value = hp_after
	slot["hp_label"].text = "%d/%d" % [roundi(hp_after), roundi(float(entry["max_hp"]))]

	_battle_enemy_hp = maxi(0, int(entry["enemy_after"]))
	battle_enemy_hp_bar.value = _battle_enemy_hp
	battle_enemy_hp_label.text = str(_battle_enemy_hp)

	if not log_line:
		return
	var name: String = slot["name"].text
	var event_tag: String = String(entry["event"])
	var damage_dealt: int = maxi(0, int(entry["enemy_before"]) - int(entry["enemy_after"]))
	var damage_taken: int = maxi(0, roundi(float(entry["hp_before"]) - float(entry["hp_after"])))
	if event_tag.contains("item_used"):
		battle_log.append_text("%sの攻撃！ %sに%dのダメージ。%sは体勢を立て直した(HP回復)\n" % [name, battle_enemy_name_label.text, damage_dealt, name])
	elif damage_taken > 0:
		battle_log.append_text("%sの攻撃！ %sに%dのダメージ。反撃で%dのダメージを受けた\n" % [name, battle_enemy_name_label.text, damage_dealt, damage_taken]) if damage_dealt > 0 \
			else battle_log.append_text("%sは%dのダメージを受けた\n" % [name, damage_taken])
	else:
		battle_log.append_text("%sの攻撃！ %sに%dのダメージ\n" % [name, battle_enemy_name_label.text, damage_dealt])
	if event_tag.contains("retreated"):
		battle_log.append_text("[color=#e5a04c]%sは戦線を離脱した[/color]\n" % name)
	if event_tag.contains("defeated"):
		battle_log.append_text("[color=#e0574c]%sは力尽きた[/color]\n" % name)
	if event_tag.contains("victory"):
		battle_log.append_text("[color=#7ed08a]%sが%sを倒した！[/color]\n" % [name, battle_enemy_name_label.text])

## 結果の文言は_battle_result_kind(exploration.gdのCombat.resolve_party_encounter/_attempt_gateが
## 返す"victory"/"defeat"/"retreat"/"retreat_before_fight")で出し分ける(2026-09-23)。以前はHPが
## 0かどうかだけで「勝利」/「撤退した」の2択にしていたため、実際は誰かが力尽きた「敗北」も
## 一律「撤退した」と表示されており、区別が付かなかった。
func _finish_battle_rounds() -> void:
	for slot in battle_party_slots:
		_set_battle_slot_active(slot, false)
	battle_log.append_text("\n[color=#ffd54a]--- 結果 ---[/color]\n")
	match _battle_result_kind:
		"victory":
			battle_log.append_text("[color=#7ed08a]勝利！[/color]\n")
		"defeat":
			battle_log.append_text("[color=#e0574c]敗北した[/color]\n")
		"retreat_before_fight":
			battle_log.append_text("[color=#e5a04c]勝ち目が無いと判断し、戦わずに撤退した[/color]\n")
		_: # "retreat"、または将来resultが渡らない呼び出しが出てきた場合の保険
			battle_log.append_text("[color=#e5a04c]撤退した[/color]\n")
	battle_skip_button.visible = false
	battle_close_button.visible = true

func _on_battle_close_pressed() -> void:
	_close_modal(battle_panel)
	BattleScreen.close()

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
	section_assign_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section_assign_title.add_theme_font_size_override("font_size", 16)
	header.add_child(section_assign_title)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(section_assign_panel))
	header.add_child(close_button)

	var hint_label := Label.new()
	hint_label.text = "どのパーティをここへ割り当てますか?(未割当のパーティは赤く強調表示しています)"
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	section_assign_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		section_assign_status_label.text = "まだパーティがありません。探索者を雇用してパーティを編成してください。"
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
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.text = "現在: %s / 状態: %s / 戦力: %d" % [section_name, _party_status_text(party), Parties.power(party["id"])]
	info.add_child(sub_label)

	# 予測(2026-09-24、「セクションクリック時も予測ボタンを出して欲しい」)。パーティパネルの「予測」と同じ計算・文面で、
	# このパーティをこのセクションに置いた場合の今月の見込みを、行の下に出す。
	var forecast_label := Label.new()
	forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forecast_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	forecast_label.visible = false
	info.add_child(forecast_label)

	var forecast_button := Button.new()
	forecast_button.text = "予測"
	forecast_button.tooltip_text = "このパーティをここに割り当てた場合の、今月の予測報酬と撤退リスク"
	forecast_button.pressed.connect(func():
		forecast_label.text = _forecast_text(party["id"], _section_assign_target_id)
		forecast_label.visible = true)
	hbox.add_child(forecast_button)

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
	hire_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hire_status_label.modulate = Color(1, 1, 1, 0.8)
	col.add_child(hire_status_label)

func _on_open_hire_pressed() -> void:
	_refresh_candidates()
	hire_status_label.text = ""
	_open_modal(hire_panel)

## 探索者管理パネル(名簿・担当セクション割り当て・スキル訓練・施設拡張)。
## サイドバーの「探索者管理」ボタンから開く。
##
## 一覧ビュー(探索者の正方形ポートレートカードを並べただけの画面)を既定で表示し、
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
	title.text = "探索者管理"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(func(): _close_modal(npc_panel))
	header.add_child(close_button)

	_build_npc_roster_view(col)
	_build_npc_detail_view(col)

## 一覧ビュー: 上に並べ替え・絞り込みの行、その下に正方形ポートレートカードのグリッド(名前・状態・総合戦力)。
## ジョブ/装備の中身は、カードをクリックして詳細ビューに移るまで出さない。
func _build_npc_roster_view(col: VBoxContainer) -> void:
	npc_roster_view = VBoxContainer.new()
	npc_roster_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(npc_roster_view)

	_build_roster_filter_row(npc_roster_view)

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
	facility_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facility_info_label.add_theme_font_size_override("font_size", 12)
	facility_info_label.modulate = Color(1, 1, 1, 0.75)
	npc_roster_view.add_child(facility_info_label)

## 一覧の上の行: 並べ替え(項目+昇順/降順)と、絞り込み(血筋・ジョブ)。
func _build_roster_filter_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	row.add_child(_make_filter_caption("並べ替え"))
	roster_sort_option = OptionButton.new()
	for option in RosterQuery.sort_options():
		roster_sort_option.add_item(option["label"])
		roster_sort_option.set_item_metadata(roster_sort_option.item_count - 1, option)
	roster_sort_option.item_selected.connect(_on_roster_sort_selected)
	row.add_child(roster_sort_option)

	roster_sort_dir_button = Button.new()
	roster_sort_dir_button.pressed.connect(_on_roster_sort_dir_pressed)
	row.add_child(roster_sort_dir_button)

	row.add_child(VSeparator.new())
	row.add_child(_make_filter_caption("血筋"))
	roster_bloodline_option = OptionButton.new()
	roster_bloodline_option.item_selected.connect(_on_roster_bloodline_selected)
	row.add_child(roster_bloodline_option)

	row.add_child(_make_filter_caption("ジョブ"))
	roster_job_option = OptionButton.new()
	roster_job_option.add_item("すべて")
	roster_job_option.set_item_metadata(0, RosterQuery.ALL_JOBS)
	for job in Jobs.JOB_NAMES.keys():
		roster_job_option.add_item(Jobs.JOB_NAMES[job])
		roster_job_option.set_item_metadata(roster_job_option.item_count - 1, job)
	roster_job_option.item_selected.connect(_on_roster_job_selected)
	row.add_child(roster_job_option)

	var reset_button := Button.new()
	reset_button.text = "絞り込みを解除"
	reset_button.pressed.connect(_on_roster_filter_reset_pressed)
	row.add_child(reset_button)

	roster_count_label = Label.new()
	roster_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	roster_count_label.add_theme_font_size_override("font_size", 12)
	row.add_child(roster_count_label)

func _make_filter_caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(1, 1, 1, 0.75)
	return label

func _on_roster_sort_selected(index: int) -> void:
	var option: Dictionary = roster_sort_option.get_item_metadata(index)
	_roster_sort_key = option["key"]
	_roster_sort_descending = option["descending"] # 項目を選び直した直後の向きは、項目ごとの既定(戦力・スキルは大きい順)
	_refresh_roster()

func _on_roster_sort_dir_pressed() -> void:
	_roster_sort_descending = not _roster_sort_descending
	_refresh_roster()

func _on_roster_bloodline_selected(index: int) -> void:
	_roster_bloodline = String(roster_bloodline_option.get_item_metadata(index))
	_refresh_roster()

func _on_roster_job_selected(index: int) -> void:
	_roster_job = int(roster_job_option.get_item_metadata(index))
	_refresh_roster()

func _on_roster_filter_reset_pressed() -> void:
	_roster_bloodline = RosterQuery.ALL_BLOODLINES
	_roster_job = RosterQuery.ALL_JOBS
	_refresh_roster()

## 並べ替え・絞り込みの部品を、覚えている選択に合わせる。血筋の選択肢は、いま名簿にいる血筋から作る
## (顔ぶれが変わった時だけ作り直す。選んだ直後の呼び出しの最中に、選択肢を消さないため)。
func _sync_roster_filter_controls() -> void:
	var wanted: Array = [RosterQuery.ALL_BLOODLINES]
	wanted.append_array(RosterQuery.bloodlines_in(Npcs.get_roster()))
	var current: Array = []
	for i in roster_bloodline_option.item_count:
		current.append(roster_bloodline_option.get_item_metadata(i))
	if current != wanted:
		roster_bloodline_option.clear()
		for bloodline in wanted:
			roster_bloodline_option.add_item("すべて" if bloodline == RosterQuery.ALL_BLOODLINES else bloodline)
			roster_bloodline_option.set_item_metadata(roster_bloodline_option.item_count - 1, bloodline)
	if not (_roster_bloodline in wanted):
		_roster_bloodline = RosterQuery.ALL_BLOODLINES # 選んでいた血筋が、名簿にいなくなった(新規開始など)
	roster_bloodline_option.select(wanted.find(_roster_bloodline))
	for i in roster_job_option.item_count:
		if int(roster_job_option.get_item_metadata(i)) == _roster_job:
			roster_job_option.select(i)
	for i in roster_sort_option.item_count:
		if roster_sort_option.get_item_metadata(i)["key"] == _roster_sort_key:
			roster_sort_option.select(i)
	roster_sort_dir_button.text = "降順 ▼" if _roster_sort_descending else "昇順 ▲"

## 詳細ビュー: 一覧で探索者を選ぶとここに切り替わる。上部に「一覧へ戻る」と身元表示
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
	npc_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity_col.add_child(npc_detail_label)

	npc_job_label = Label.new()
	npc_job_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_job_label.modulate = Color(1, 1, 1, 0.85)
	identity_col.add_child(npc_job_label)

	var skill_label := Label.new()
	skill_label.text = "スキル訓練"
	detail_body.add_child(skill_label)

	skill_level_labels.clear()
	skill_train_buttons.clear()
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
		skill_train_buttons[skill] = train_button

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

## 一覧ビューを表示する(探索者管理パネルを開いた時の既定表示)。
func _show_npc_roster_view() -> void:
	npc_roster_view.visible = true
	npc_detail_view.visible = false

## 詳細ビューを表示する(一覧で探索者を選んだ時、またはマップの探索者アイコンから直接開いた時)。
func _show_npc_detail_view() -> void:
	npc_roster_view.visible = false
	npc_detail_view.visible = true

func _on_npc_detail_back_pressed() -> void:
	_refresh_roster() # 詳細側での訓練/割り当て変更をカードに反映してから一覧へ戻る
	_show_npc_roster_view()

## 探索者管理パネルを開く共通処理。show_detailがtrueなら選択中探索者の詳細から始める
## (マップの探索者アイコンをクリックした場合)。falseなら一覧ビューから始める
## (サイドバーの「探索者管理」ボタンから開いた場合。一覧を中心に見せるため、以前選択して
## いた探索者があっても毎回一覧からにする)。
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
		npc_detail_label.text = "左の一覧から探索者を選択してください"
		npc_job_label.text = ""
		for skill in skill_level_labels.keys():
			skill_level_labels[skill].text = ""
		_refresh_train_buttons()
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
	npc_job_label.text = "ジョブ: %s / 固有スキル: %s(%s)\n装備: %s / %s\n%s" % [
		Jobs.JOB_NAMES[npc["job"]], unique.get("name", "-"), unique.get("description", ""),
		weapon_text, armor_text, RosterQuery.power_breakdown_text(_selected_npc_id)]

	for skill in skill_level_labels.keys():
		var level := Npcs.skill_level(_selected_npc_id, skill)
		skill_level_labels[skill].text = "Lv%d → コスト%d" % [level, Economy.training_cost(level)]
	_refresh_train_buttons()

	reclass_button.disabled = not Items.has_item(_selected_npc_id, "reclass_elixir")

## 探索中/回復中(あと何日か)/未所属を文字にする。パーティ単位の状態(parties.gd)を
## その探索者の所属パーティから読む。
func _npc_status_text(npc: Dictionary) -> String:
	var party_id: int = npc["party_id"]
	if party_id == -1:
		return "未所属"
	var party := Parties.get_party(party_id)
	if party.is_empty() or int(party.get("status", Parties.Status.IDLE)) == Parties.Status.IDLE:
		return "待機中(未割当)"
	return _party_status_text(party) # RECOVERING/EXPLORINGの文言は_party_status_text()と共通化

## 訓練ボタンを、資金が足りる間だけ押せるようにする(2026-09-20、「資金がなくても訓練ボタンが押せてしまう」との指摘。
## 以前は常に押せて、資金が足りなければ押しても何も起きず、押せない理由も分からなかった)。足りない間は、コスト表示を
## 赤みがかった色にして理由を示す。資金は月末の収入や別の操作でも変わるので、_refresh_funds()からも呼ぶ。
func _refresh_train_buttons() -> void:
	var has_selection := _selected_npc_id >= 0 and not Npcs.get_npc(_selected_npc_id).is_empty()
	for skill in skill_train_buttons.keys():
		var button: Button = skill_train_buttons[skill]
		var label: Label = skill_level_labels[skill]
		if not has_selection:
			button.disabled = true
			button.tooltip_text = ""
			label.modulate = Color.WHITE
			continue
		var cost := Economy.training_cost(Npcs.skill_level(_selected_npc_id, skill))
		var affordable := Economy.can_afford(cost)
		button.disabled = not affordable
		button.tooltip_text = "" if affordable else "資金が足りません(必要: %d)" % cost
		label.modulate = Color.WHITE if affordable else Color(1.0, 0.6, 0.55)

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

## パーティ編成パネル(design.md 4.7節)。探索者管理パネルと同じ一覧/詳細の2画面構成。
## 一覧ビュー: 既存パーティのカード一覧+「新しいパーティを編成」の簡易選択。
## 詳細ビュー: 並び順(戦闘での対戦順)・担当セクション割り当て・予測・完全踏破後の設定
## (旧探索者管理パネルの[担当]タブから移設。担当割り当ての単位が探索者からパーティに変わったため)。
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
	form_label.text = "新しいパーティを編成する(未所属探索者から最大%d人を選択)" % Parties.MAX_PARTY_SIZE
	form_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	party_roster_view.add_child(form_label)

	party_form_picker = MemberPicker.new()
	party_form_picker.limit = Parties.MAX_PARTY_SIZE
	party_form_picker.row_height = MEMBER_PICKER_TOUCH_ROW_HEIGHT if _touch_ui else MemberPicker.DEFAULT_ROW_HEIGHT
	party_form_picker.selection_changed.connect(_update_party_form_button)
	party_roster_view.add_child(party_form_picker)

	party_form_button = Button.new()
	party_form_button.text = "選択した探索者でパーティを編成する"
	party_form_button.pressed.connect(_on_form_party_pressed)
	party_roster_view.add_child(party_form_button)

	party_form_status_label = Label.new()
	party_form_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	party_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	party_detail_view.add_child(party_detail_label)

	# 難易度(Easy/Normal/Hard)。パーティごとに、いつでも切り替えられる(difficulty.gd)。タブの外に置いて、
	# どちらのタブを開いていても見えて押せるようにする。開いている側は、マップのアイコンのバッジと同じ色になる。
	var difficulty_row := HBoxContainer.new()
	party_detail_view.add_child(difficulty_row)
	var difficulty_title := Label.new()
	difficulty_title.text = "難易度:"
	difficulty_row.add_child(difficulty_title)
	var difficulty_group := ButtonGroup.new()
	difficulty_buttons.clear()
	for mode in range(Difficulty.NAMES.size()):
		var mode_button := Button.new()
		mode_button.text = Difficulty.mode_name(mode)
		mode_button.tooltip_text = Difficulty.describe(mode)
		mode_button.toggle_mode = true
		mode_button.button_group = difficulty_group
		mode_button.custom_minimum_size.x = 96
		_apply_difficulty_button_style(mode_button, mode)
		mode_button.pressed.connect(_on_difficulty_pressed.bind(mode))
		difficulty_row.add_child(mode_button)
		difficulty_buttons.append(mode_button)
	difficulty_desc_label = Label.new()
	difficulty_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	difficulty_desc_label.modulate = Color(1, 1, 1, 0.85)
	# ボタンと同じ行の残りに置く(幅が足りれば1行、足りなければ折り返す。縦を節約して、担当セクションの一覧を狭めない)
	difficulty_desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_desc_label.custom_minimum_size.x = 260
	difficulty_row.add_child(difficulty_desc_label)

	# 詳細は2つのタブに分ける(2026-09-19、実機で「メンバーが文字だけ・担当セクションの一覧が狭く潰れる・
	# 割り当てボタンだけが目立つ」との指摘): 「メンバー・並び順」と「担当セクション」。タブは、
	# 倍速ボタンと同じくButtonGroupのトグルにして、開いている側が青く押された状態になる。
	var tab_row := HBoxContainer.new()
	party_detail_view.add_child(tab_row)
	var tab_group := ButtonGroup.new()
	party_tab_buttons.clear()
	for tab_index in range(2):
		var tab_button := Button.new()
		tab_button.text = ["メンバー・並び順", "担当セクション"][tab_index]
		tab_button.toggle_mode = true
		tab_button.button_group = tab_group
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.pressed.connect(_show_party_tab.bind(tab_index))
		tab_row.add_child(tab_button)
		party_tab_buttons.append(tab_button)

	party_tab_pages.clear()
	_build_party_members_page()
	_build_party_sections_page()
	_show_party_tab(0)

func _build_party_members_page() -> void:
	# 並び順のカードに、メンバーの追加が加わって縦に長くなったので、スクロールできるページにする(2026-09-21)
	var page_scroll := ScrollContainer.new()
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	party_detail_view.add_child(page_scroll)
	party_tab_pages.append(page_scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.add_child(page)

	var order_label := Label.new()
	order_label.text = "並び順(戦闘での対戦順。左が先頭。先頭に立つ間だけ効果を発揮する固有スキルもある)。カードを選んで、前へ/後ろへで入れ替える"
	order_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(order_label)

	party_member_row = HBoxContainer.new()
	party_member_row.alignment = BoxContainer.ALIGNMENT_CENTER
	party_member_row.add_theme_constant_override("separation", 12)
	page.add_child(party_member_row)

	var order_actions := HBoxContainer.new()
	order_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(order_actions)
	party_member_move_buttons.clear()
	var move_forward_button := Button.new()
	move_forward_button.text = "◀ 前へ"
	move_forward_button.pressed.connect(_on_move_member_pressed.bind(-1))
	order_actions.add_child(move_forward_button)
	party_member_move_buttons.append(move_forward_button)
	var move_back_button := Button.new()
	move_back_button.text = "後ろへ ▶"
	move_back_button.pressed.connect(_on_move_member_pressed.bind(1))
	order_actions.add_child(move_back_button)
	party_member_move_buttons.append(move_back_button)
	party_remove_button = Button.new()
	party_remove_button.text = "パーティから外す"
	party_remove_button.pressed.connect(_on_remove_member_pressed)
	order_actions.add_child(party_remove_button)

	page.add_child(HSeparator.new())
	party_add_label = Label.new()
	party_add_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(party_add_label)
	party_add_picker = MemberPicker.new()
	party_add_picker.row_height = MEMBER_PICKER_TOUCH_ROW_HEIGHT if _touch_ui else MemberPicker.DEFAULT_ROW_HEIGHT
	party_add_picker.fit_content = true # パーティ詳細のページ(スクロール)の中なので、この一覧の中ではスクロールしない
	party_add_picker.selection_changed.connect(_update_party_add_button)
	page.add_child(party_add_picker)
	party_add_button = Button.new()
	party_add_button.text = "選択した探索者をこのパーティに追加する"
	party_add_button.pressed.connect(_on_party_add_pressed)
	page.add_child(party_add_button)
	party_add_status_label = Label.new()
	party_add_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	party_add_status_label.modulate = Color(1, 1, 1, 0.8)
	page.add_child(party_add_status_label)

func _build_party_sections_page() -> void:
	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_detail_view.add_child(page)
	party_tab_pages.append(page)

	var section_label := Label.new()
	section_label.text = "担当セクションを選んで「割り当て」を押す(エリアごとに折り畳めます)。右の欄は、各セクションを今担当しているパーティ"
	section_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(section_label)

	# 選ぶ場所だと一目で分かるよう、一覧に枠と暗い背景を付ける(ただの文字と区別が付きにくかった)
	section_tree = Tree.new()
	section_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section_tree.hide_root = true
	# 左: セクション名、右: 今そこを担当しているパーティ(_update_section_party_labels)。どちらの欄を押しても
	# 行全体が選択されるようにする。
	section_tree.columns = 2
	section_tree.select_mode = Tree.SELECT_ROW
	section_tree.set_column_expand(0, true)
	section_tree.set_column_expand(1, false)
	section_tree.set_column_custom_minimum_width(1, SECTION_TREE_PARTY_COLUMN_WIDTH)
	var tree_style := StyleBoxFlat.new()
	tree_style.bg_color = Color(0.07, 0.08, 0.11, 1.0)
	tree_style.border_color = Color(0.45, 0.6, 0.85, 1.0)
	tree_style.set_border_width_all(2)
	tree_style.set_corner_radius_all(4)
	tree_style.set_content_margin_all(4)
	section_tree.add_theme_stylebox_override("panel", tree_style)
	section_tree.item_selected.connect(_update_section_action_buttons)
	section_tree.nothing_selected.connect(_update_section_action_buttons)
	page.add_child(section_tree)

	var section_actions := HBoxContainer.new()
	page.add_child(section_actions)
	section_action_buttons.clear()

	var assign_button := Button.new()
	assign_button.text = "割り当て"
	assign_button.pressed.connect(_on_assign_to_section_pressed)
	_apply_primary_button_style(assign_button) # 2026-09-14: 「割り当てボタンを目立たせる」という要望への対応
	section_actions.add_child(assign_button)
	section_action_buttons.append(assign_button)

	var view_thread_button := Button.new()
	view_thread_button.text = "ログ"
	view_thread_button.pressed.connect(_on_view_thread_pressed)
	section_actions.add_child(view_thread_button)
	section_action_buttons.append(view_thread_button)

	var forecast_button := Button.new()
	forecast_button.text = "予測"
	forecast_button.pressed.connect(_on_forecast_pressed)
	section_actions.add_child(forecast_button)
	section_action_buttons.append(forecast_button)

	var actions_spacer := Control.new()
	actions_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_actions.add_child(actions_spacer)

	# 完全踏破後の挙動(留まって収入源として維持するか、次の未踏破セクションへ自動で移るか)。
	# パーティごとに設定できる(exploration.gdのpost_clear_behavior参照)。割り当ての操作と同じ行の右端に置く。
	var post_clear_row := section_actions

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

	section_forecast_label = Label.new()
	section_forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section_forecast_label.modulate = Color(1, 1, 1, 0.85)
	page.add_child(section_forecast_label)

## 詳細のタブを切り替える(0=メンバー・並び順、1=担当セクション)。
func _show_party_tab(tab_index: int) -> void:
	for i in range(party_tab_pages.size()):
		party_tab_pages[i].visible = i == tab_index
		party_tab_buttons[i].set_pressed_no_signal(i == tab_index)

func _show_party_roster_view() -> void:
	party_roster_view.visible = true
	party_detail_view.visible = false

## パーティ詳細を開く。担当が未割当のパーティは、次にやることが割り当てなので「担当セクション」のタブから、
## そうでなければ「メンバー・並び順」のタブから始める。
func _show_party_detail_view() -> void:
	party_roster_view.visible = false
	party_detail_view.visible = true
	var party := Parties.get_party(_selected_party_id)
	_show_party_tab(1 if not party.is_empty() and party["assigned_section"] == "" else 0)

func _on_party_detail_back_pressed() -> void:
	_refresh_party_roster()
	_show_party_roster_view()

## パーティ解散(design.md 4.7節): 装備・スキル経験値・固有スキルは探索者個体側に残るため、
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
	_selected_member_index = -1
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
		_selected_member_index = -1
		_refresh_party_detail()
		_show_party_detail_view()
	else:
		_show_party_roster_view()
	_open_modal(party_panel)

func _on_open_party_panel_pressed() -> void:
	_open_party_panel()

## セクション選択肢をエリア→セクションの2階層に組む(旧探索者管理パネルの同名関数を移設。
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
		area_item.set_selectable(1, false)
		for section_id in reachable_sections:
			var section_item := section_tree.create_item(area_item)
			section_item.set_text(0, WorldMap.sections[section_id]["name"])
			section_item.set_metadata(0, section_id)
	_update_section_party_labels()
	_update_section_action_buttons() # clear()で選択が無くなるので、ボタンの押せる状態も合わせる

const SECTION_TREE_PARTY_COLUMN_WIDTH := 320

## 担当セクションの一覧の右の欄に、各セクションを今担当しているパーティを表示する(パーティ詳細を開いて
## いる間は、そのパーティを先頭に「▶」付きで金色にして、他のパーティと見分けられるようにする)。
## どのパーティも担当していないセクションは空欄。パーティの割り当てが変わるたびに呼び直す。
func _update_section_party_labels() -> void:
	var names_by_section := {} # section_id -> Array[String]
	var current_section := ""
	for party in Parties.get_parties():
		var section_id: String = party["assigned_section"]
		if section_id == "":
			continue
		var names: Array = names_by_section.get(section_id, [])
		if party["id"] == _selected_party_id:
			names.push_front("▶ " + String(party["name"]))
			current_section = section_id
		else:
			names.append(String(party["name"]))
		names_by_section[section_id] = names
	var root := section_tree.get_root()
	if root == null:
		return
	var area_item := root.get_first_child()
	while area_item:
		var item := area_item.get_first_child()
		while item:
			var section_id = item.get_metadata(0)
			var names: Array = names_by_section.get(section_id, [])
			item.set_text(1, "・".join(names))
			item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
			item.set_custom_color(1, Color(1.0, 0.85, 0.4) if section_id == current_section else Color(0.75, 0.8, 0.9))
			item = item.get_next()
		area_item = area_item.get_next()

## パーティを切り替えるたびに、担当セクションのTreeもそのパーティの現在の割り当て先を
## 選択済みにしておく。
func _select_current_section_in_tree(section_id: String) -> void:
	section_tree.deselect_all() # 別のパーティで選んでいた行が残って、誤って割り当てないように
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

	party_form_picker.set_choices(_unaffiliated_npcs(), "未所属の探索者がいません(雇用するか、パーティから外すと、ここに出ます)")
	_update_party_form_button()
	party_form_status_label.text = ""

	# サイドバーの「パーティ」ボタン自体も、未割当のパーティが1つでもあれば赤字で警告する
	# (2026-09-14、「未割当のパーティが赤く光る」という要望への対応。パネルを開かなくても
	# 対応が必要なことに気付けるようにする)。
	if has_unassigned:
		party_button.text = "🧩 パーティ ⚠未割当あり"
		party_button.add_theme_color_override("font_color", Color(1.0, 0.42, 0.36))
		party_button.add_theme_color_override("font_hover_color", Color(1.0, 0.55, 0.5))
	else:
		party_button.text = "🧩 パーティ"
		party_button.remove_theme_color_override("font_color")
		party_button.remove_theme_color_override("font_hover_color")

func _create_party_card(party: Dictionary, group: ButtonGroup) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = group
	card.custom_minimum_size = Vector2(220, 90)
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var member_names := []
	for npc_id in party["member_ids"]:
		member_names.append(String(Npcs.get_npc(npc_id).get("name", "?")))
	var is_unassigned: bool = party["assigned_section"] == ""
	var section_name := "未割当"
	if not is_unassigned and WorldMap.sections.has(party["assigned_section"]):
		section_name = WorldMap.sections[party["assigned_section"]]["name"]
	card.text = "%s  [%s]\n%s\n担当: %s%s" % [party["name"], Difficulty.mode_name(Difficulty.of_party(party)), "・".join(member_names), section_name, "  ⚠" if is_unassigned else ""]
	if is_unassigned:
		_apply_unassigned_warning_style(card)
	card.pressed.connect(_on_party_card_pressed.bind(party["id"]))
	return card

func _on_party_card_pressed(party_id: int) -> void:
	_selected_party_id = party_id
	_selected_member_index = -1
	party_add_status_label.text = ""
	_refresh_party_detail()
	_show_party_detail_view()

## パーティに入っていない(未所属の)探索者。
func _unaffiliated_npcs() -> Array:
	return Npcs.get_roster().filter(func(npc): return npc["party_id"] == -1)

func _update_party_form_button() -> void:
	party_form_button.disabled = party_form_picker.selected_ids().is_empty()

func _on_form_party_pressed() -> void:
	var member_ids: Array = party_form_picker.selected_ids()
	if member_ids.is_empty():
		party_form_status_label.text = "探索者を選択してください"
		return
	if member_ids.size() > Parties.MAX_PARTY_SIZE:
		party_form_status_label.text = "パーティは最大%d人までです" % Parties.MAX_PARTY_SIZE
		return
	var party_id := Parties.form_party(member_ids)
	if party_id == -1:
		party_form_status_label.text = "パーティを編成できませんでした"
		return
	_refresh_party_roster()
	party_form_status_label.text = "パーティを編成しました"

func _clear_party_member_row() -> void:
	for child in party_member_row.get_children():
		party_member_row.remove_child(child) # queue_free()だけだと、同じフレーム内の再構築で残ってしまう
		child.queue_free()

func _refresh_party_detail() -> void:
	if _selected_party_id < 0 or Parties.get_party(_selected_party_id).is_empty():
		party_detail_label.text = "左の一覧からパーティを選択してください"
		section_forecast_label.text = ""
		_clear_party_member_row()
		_update_member_move_buttons()
		party_add_picker.limit = 0
		party_add_picker.set_choices([])
		party_add_label.text = ""
		_update_party_add_button()
		for behavior in post_clear_behavior_buttons.keys():
			post_clear_behavior_buttons[behavior].button_pressed = false
		_refresh_difficulty_controls(-1)
		return
	section_forecast_label.text = ""
	var party := Parties.get_party(_selected_party_id)
	var section_id: String = party["assigned_section"]
	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else "未割当"
	party_detail_label.text = "%s / 担当: %s / 状態: %s / 戦力: %d" % [
		party["name"], section_name, _party_status_text(party), Parties.power(_selected_party_id)]

	_clear_party_member_row()
	var member_group := ButtonGroup.new()
	var member_ids: Array = party["member_ids"]
	for index in range(member_ids.size()):
		var npc := Npcs.get_npc(member_ids[index])
		if npc.is_empty():
			continue
		var card := _create_party_member_card(npc, index, member_group)
		party_member_row.add_child(card)
		if index == _selected_member_index:
			card.set_pressed_no_signal(true)
	if _selected_member_index >= member_ids.size():
		_selected_member_index = -1
	_update_member_move_buttons()
	_refresh_party_add_section()

	var behavior: int = party["post_clear_behavior"]
	if post_clear_behavior_buttons.has(behavior):
		post_clear_behavior_buttons[behavior].button_pressed = true
	_refresh_difficulty_controls(Difficulty.of_party(party))
	_select_current_section_in_tree(section_id)
	_update_section_party_labels()
	_update_section_action_buttons()

const MEMBER_PICKER_TOUCH_ROW_HEIGHT := 48.0 # タッチUIの、探索者のチェックボックスの1行の高さ(指で押せる高さ)
const PARTY_MEMBER_CARD_WIDTH := 170.0
const PARTY_MEMBER_PORTRAIT_SIZE := 110.0

## パーティ詳細の並び順の1人分: [先頭/2番手…][肖像][名前][ジョブ HP]。押すと選択(青い枠)になり、
## 前へ/後ろへで並び順を入れ替えられる。Buttonは子の大きさを最小サイズに反映しないので、大きさは決め打ち
## (_create_roster_cardと同じ作り。名前は長くてもはみ出さないよう省略表示にする)。
func _create_party_member_card(npc: Dictionary, index: int, group: ButtonGroup) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = group
	card.custom_minimum_size = Vector2(PARTY_MEMBER_CARD_WIDTH, PARTY_MEMBER_PORTRAIT_SIZE + 96)
	card.tooltip_text = npc["name"]
	card.pressed.connect(_on_party_member_card_pressed.bind(index))

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

	var order_label := Label.new()
	order_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_label.text = "先頭" if index == 0 else "%d番手" % (index + 1)
	order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_label.add_theme_font_size_override("font_size", 12)
	order_label.modulate = Color(1.0, 0.85, 0.4) if index == 0 else Color(1, 1, 1, 0.7)
	vbox.add_child(order_label)

	var portrait := PanelContainer.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.custom_minimum_size = Vector2(PARTY_MEMBER_PORTRAIT_SIZE, PARTY_MEMBER_PORTRAIT_SIZE)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.clip_contents = true
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = _bloodline_color(npc["innate_traits"].get("bloodline", ""))
	portrait_style.set_corner_radius_all(6)
	portrait.add_theme_stylebox_override("panel", portrait_style)
	portrait.add_child(_create_portrait_content(npc))
	vbox.add_child(portrait)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = npc["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(name_label)

	var stats_label := Label.new()
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_label.text = "%s HP:%d/%d" % [Jobs.JOB_NAMES[npc["job"]], int(npc["hp"]), int(npc["max_hp"])]
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.modulate = Color(1, 1, 1, 0.8)
	stats_label.clip_text = true
	stats_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(stats_label)
	return card

## メンバー画面の「追加」欄: 未所属の探索者を、空きの数まで選べる。満員なら、その旨を出して押せなくする。
func _refresh_party_add_section() -> void:
	var free := Parties.free_slots(_selected_party_id)
	party_add_picker.limit = free
	party_add_picker.set_choices(_unaffiliated_npcs(), "未所属の探索者がいません(雇用するか、他のパーティから外すと、ここに出ます)")
	if free > 0:
		party_add_label.text = "未所属の探索者をこのパーティに追加する(あと%d人まで。並び順の最後に入る)" % free
	else:
		party_add_label.text = "このパーティは満員です(最大%d人)。追加するには、メンバーを外してください" % Parties.MAX_PARTY_SIZE
	_update_party_add_button()

func _update_party_add_button() -> void:
	party_add_button.disabled = party_add_picker.selected_ids().is_empty()

func _on_party_add_pressed() -> void:
	if _selected_party_id < 0:
		return
	var ids: Array = party_add_picker.selected_ids()
	if ids.is_empty():
		party_add_status_label.text = "追加する探索者を選択してください"
		return
	if not Parties.add_members(_selected_party_id, ids):
		party_add_status_label.text = "追加できませんでした(パーティは最大%d人までです)" % Parties.MAX_PARTY_SIZE
		return
	var names: Array = ids.map(func(id): return String(Npcs.get_npc(id).get("name", "?")))
	party_add_picker.clear_selection()
	_refresh_party_roster()
	_refresh_party_detail()
	party_add_status_label.text = "%sをパーティに追加しました" % "・".join(names)

func _on_remove_member_pressed() -> void:
	var party := Parties.get_party(_selected_party_id)
	if party.is_empty() or _selected_member_index < 0 or _selected_member_index >= party["member_ids"].size():
		return
	var npc_id: int = party["member_ids"][_selected_member_index]
	var npc_name := String(Npcs.get_npc(npc_id).get("name", "?"))
	if not Parties.remove_member(_selected_party_id, npc_id):
		party_add_status_label.text = "外せませんでした(パーティには1人は残す必要があります。全員を外すなら、解散してください)"
		return
	_selected_member_index = -1
	_refresh_party_roster()
	_refresh_party_detail()
	party_add_status_label.text = "%sをパーティから外しました(未所属に戻りました)" % npc_name

func _on_party_member_card_pressed(index: int) -> void:
	_selected_member_index = index
	_update_member_move_buttons()

## 前へ/後ろへは、カードを選んでいて、その方向にまだ動かせる時だけ押せる(動かせない時は薄く表示される)。
func _update_member_move_buttons() -> void:
	var party := Parties.get_party(_selected_party_id)
	var count: int = party["member_ids"].size() if not party.is_empty() else 0
	var has_selection := _selected_member_index >= 0 and _selected_member_index < count
	party_member_move_buttons[0].disabled = not has_selection or _selected_member_index == 0
	party_member_move_buttons[1].disabled = not has_selection or _selected_member_index >= count - 1
	party_remove_button.disabled = not has_selection or count <= 1 # パーティには1人は残す(全員を外すなら、解散)

## 割り当て/ログ/予測は、担当セクションを選んでいる時だけ押せる(選ぶ前から緑の割り当てボタンだけが
## 目立って、選ぶ場所が目立たなかったため)。セクション名のグループ行(エリア)は選択できない。
func _update_section_action_buttons() -> void:
	var has_selection := section_tree.get_selected() != null
	for button in section_action_buttons:
		button.disabled = not has_selection

## 探索中/回復中(あと何日か)/未割当を文字にする(design.md 5.4節、パーティ全体で足並みを揃える)。
func _party_status_text(party: Dictionary) -> String:
	match int(party["status"]):
		Parties.Status.RECOVERING:
			return "回復中(あと%d日)" % max(0, party["recovering_until_day"] - TimeSystem.current_day)
		Parties.Status.EXPLORING:
			# 勝てない敵の前で詰まって、力を付けている間(exploration.gdの_check_blocked)
			return "戦力不足で待機中(力を付けている)" if Parties.is_retreating(party) else "探索中"
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
	var index := _selected_member_index
	if index < 0:
		return
	var order: Array = party["member_ids"].duplicate()
	var target := index + direction
	if index >= order.size() or target < 0 or target >= order.size():
		return
	var tmp = order[index]
	order[index] = order[target]
	order[target] = tmp
	Parties.reorder(_selected_party_id, order)
	_selected_member_index = target # 動かしたメンバーを選択したままにして、続けて動かせるようにする
	_refresh_party_detail()

## 難易度のボタンを、選択中のパーティの難易度(-1なら、どれも選ばない)に合わせる。
func _refresh_difficulty_controls(mode: int) -> void:
	for i in range(difficulty_buttons.size()):
		difficulty_buttons[i].set_pressed_no_signal(i == mode)
		difficulty_buttons[i].disabled = mode < 0
	difficulty_desc_label.text = Difficulty.describe(mode) if mode >= 0 else ""

## 難易度を切り替える。次の戦闘・判定・収入から効く。マップのアイコンのバッジ、パーティ一覧のカードの表示も更新する。
func _on_difficulty_pressed(mode: int) -> void:
	if _selected_party_id < 0 or not Parties.set_difficulty(_selected_party_id, mode):
		return
	_refresh_party_roster()
	_refresh_party_detail()
	_refresh_map()

## 難易度の切り替えボタンの見た目。選んでいる側は、その難易度の色(DIFFICULTY_COLORS)で塗る
## (マップのアイコンのバッジと同じ色。共有Themeの青い押下スタイルだと、どの難易度か色で分からない)。
func _apply_difficulty_button_style(button: Button, mode: int) -> void:
	var color: Color = DIFFICULTY_COLORS[mode]
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = color
	pressed.border_color = color.lightened(0.5)
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(4)
	pressed.content_margin_left = 12
	pressed.content_margin_right = 12
	pressed.content_margin_top = 8
	pressed.content_margin_bottom = 8
	var hover_pressed := pressed.duplicate()
	hover_pressed.bg_color = color.lightened(0.12)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", hover_pressed)
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	button.add_theme_color_override("font_hover_pressed_color", Color(1, 1, 1))

func _on_post_clear_behavior_pressed(behavior: int) -> void:
	if _selected_party_id < 0:
		return
	Parties.set_post_clear_behavior(_selected_party_id, behavior)
	# 「先へ進む」に切り替えた時点で、既に完全攻略済みのセクションにいるなら、翌日を待たずにその場で次へ移す
	if Exploration.apply_post_clear_behavior(Parties.get_party(_selected_party_id), TimeSystem.current_day):
		_refresh_party_roster()
		_refresh_party_detail()
		_refresh_map()

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
	section_forecast_label.text = _forecast_text(_selected_party_id, section_id)

## 予測の文面(パーティパネルの「予測」と、マップのセクション名から開く割り当て画面の「予測」で共通)。
## 完全攻略済み(周回する)セクションは、合計に加えて、1周の日数・単価・月内の周回数も出す。
func _forecast_text(party_id: int, section_id: String) -> String:
	var result := Exploration.forecast_section(party_id, section_id)
	var lap_note := ""
	if int(result["lap_days"]) > 0:
		lap_note = "(周回: 1周%d日で%d資金 × 約%.1f周)" % [result["lap_days"], result["lap_income"], result["laps"]]
	if result["risk_node_name"] == "":
		return "予測報酬(1ヶ月): 約%d資金%s / 撤退リスク: なし" % [result["predicted_income"], lap_note]
	return "予測報酬(1ヶ月): 約%d資金(通常時は約%d資金)%s / 撤退リスク: 約%d%%(「%s」で撤退の恐れ)" % [
		result["predicted_income"], result["base_income"], lap_note, roundi(result["retreat_probability"] * 100), result["risk_node_name"]]

## 武器防具屋パネル(design.md 6.2節)。選んだ探索者のジョブに応じた武器種別・防具カテゴリの
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
	shop_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

## current_tierは今その探索者が装備している等級(未装備なら-1)。Tierは等級が上がるほど戦力・価格が
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
	_refresh_roster()
	_refresh_npc_detail()
	_refresh_party_roster()
	_refresh_party_detail()
	shop_status_label.text = "装備しました"

## セーブスロット管理UI(design.md 8.2「スキーマ再プレイ」)。既存スロットの一覧・切替と、
## スキーマDBから新規プレイを開始する導線をここにまとめる。
func _build_slot_ui() -> void:
	slot_panel = PanelContainer.new()
	slot_panel.set_anchors_preset(Control.PRESET_CENTER)
	# タッチUIは、画面の高さ(横向きで約720px)ぎりぎりまで使う。実機は日本語の代替フォントの行が高く、ボタンが
	# 増えた分もあり、中身が画面をはみ出して、下端のステータス表示が見えなくなっていた(2026-09-20、実機で確認)。
	# 中身はスクロールできるようにして、どんな画面の高さでも下のボタンまで届くようにする。
	# 横3分割(一覧|ボタン1列|ボタン2列)にしたので、横長の画面を広く使う(2026-09-21)。
	slot_panel.offset_left = -540
	slot_panel.offset_right = 540
	if _touch_ui:
		slot_panel.anchor_left = 0.03
		slot_panel.anchor_right = 0.97
		slot_panel.offset_left = 0
		slot_panel.offset_right = 0
		# 実機のUIの領域は、切り欠き・角を避ける分、画面より小さい。ピクセルで高さを決めず、その領域の
		# 高さに対する割合で上下いっぱい(少しだけ余白)に広げる。
		slot_panel.anchor_top = 0.03
		slot_panel.anchor_bottom = 0.97
		slot_panel.offset_top = 0
		slot_panel.offset_bottom = 0
	else:
		slot_panel.offset_top = -295
		slot_panel.offset_bottom = 295
	# 横に広げたので、既定の半透明のままだと背面の文字(資金・左のメニュー)が透けて重なる。ほぼ不透明にする。
	var slot_panel_style := StyleBoxFlat.new()
	slot_panel_style.bg_color = Color(0.10, 0.11, 0.15, 0.98)
	slot_panel_style.border_color = Color(0.35, 0.40, 0.55)
	slot_panel_style.set_border_width_all(2)
	slot_panel_style.set_corner_radius_all(6)
	slot_panel_style.set_content_margin_all(10)
	slot_panel.add_theme_stylebox_override("panel", slot_panel_style)
	slot_panel.visible = false
	add_child(slot_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slot_panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

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

	# 操作の結果(保存しました/書き出しました等)。パネルが縦にスクロールしても見える、見出しの直下に置く。
	manual_save_status_label = Label.new()
	manual_save_status_label.modulate = Color(1, 1, 1, 0.75)
	manual_save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(manual_save_status_label)

	# 横3分割(2026-09-21、「ボタンが大半を占めるようになったので、リスト・ボタン1列・ボタン2列の3列にした方が
	# 良いかも」との提案): 左=スロットの一覧と名前、中=スロットへの操作(1列)、右=新規プレイとシナリオ・ファイル系(2列)。
	# 横長の画面を使って、縦に並べていた時の縦スクロールをなくす。
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)

	# --- 左: 一覧と名前 ---
	var list_col := VBoxContainer.new()
	list_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_col.size_flags_stretch_ratio = 2.3
	body.add_child(list_col)

	slot_list = ItemList.new()
	slot_list.custom_minimum_size = Vector2(0, 260)
	slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_col.add_child(slot_list)

	# スロットに名前を付けられるように(2026-09-14)。1つの入力欄を、選択中スロットの
	# 「名前を変更する」と、次に「新規プレイを開始する」際の名前付けの両方で使い回す
	# (どちらのボタンを押した時点のテキストを使うかは各ハンドラ側で決まる)。
	var name_row := HBoxContainer.new()
	list_col.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "名前:"
	name_row.add_child(name_label)
	slot_name_input = LineEdit.new()
	slot_name_input.placeholder_text = "スロット名(選択中の変更 / 次の新規プレイ用、省略可)"
	slot_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(slot_name_input)
	var rename_button := Button.new()
	rename_button.text = "✏️ 名前を変更"
	rename_button.tooltip_text = "一覧で選択中のスロットの名前を、左の入力欄の内容に変更する"
	rename_button.pressed.connect(_on_rename_slot_pressed)
	name_row.add_child(rename_button)

	# --- 中: スロットへの操作(1列) ---
	var op_col := VBoxContainer.new()
	op_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_col.size_flags_stretch_ratio = 1.0
	body.add_child(op_col)

	# オートセーブ(日次/終了時)とは別に、プレイヤーが好きなタイミングで明示的に保存できる
	# 手段が無く、「新規プレイを開始する」の内部処理(離れる前のスロットを保存)頼みになって
	# いた。分岐前のチェックポイントとして能動的に保存したい、という要望への対応。
	var manual_save_button := Button.new()
	manual_save_button.text = "💾 今すぐセーブする"
	manual_save_button.pressed.connect(_on_manual_save_pressed)
	op_col.add_child(manual_save_button)

	var open_button := Button.new()
	open_button.text = "📂 このスロットをロードする"
	open_button.pressed.connect(_on_open_slot_pressed)
	op_col.add_child(open_button)

	# 「新規プレイ」は進行をゼロから作り直してしまうため、今の進行を保ったまま別スロットへ
	# 分岐させたい(色々試す前のチェックポイントを残したい)場合の手段が無かった。ファイルを
	# そのまま複製するだけなので確認ダイアログは挟まず即実行し、結果はステータス表示で伝える。
	var duplicate_button := Button.new()
	duplicate_button.text = "🔀 進行を複製する(分岐用)"
	duplicate_button.tooltip_text = "現在の進行を複製する(分岐用の新規スロットを作る)"
	duplicate_button.pressed.connect(_on_duplicate_slot_pressed)
	op_col.add_child(duplicate_button)

	var delete_button := Button.new()
	delete_button.text = "🗑️ 選択したスロットを削除する"
	_apply_danger_button_style(delete_button)
	delete_button.pressed.connect(_on_delete_slot_pressed)
	op_col.add_child(delete_button)

	# オートセーブを切りたい(手動セーブだけで管理したい)という要望への対応。
	# チェック状態はworldseeker_meta.cfgに永続化し、次回起動後も引き継ぐ(SaveSystem.autosave_enabled)。
	autosave_checkbox = CheckBox.new()
	autosave_checkbox.text = "オートセーブを有効にする"
	autosave_checkbox.tooltip_text = "日次/終了時に、自動でセーブする"
	autosave_checkbox.button_pressed = SaveSystem.autosave_enabled
	autosave_checkbox.toggled.connect(SaveSystem.set_autosave_enabled)
	op_col.add_child(autosave_checkbox)

	# --- 右: 新規プレイとシナリオ・ファイル系(2列) ---
	var new_col := VBoxContainer.new()
	new_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_col.size_flags_stretch_ratio = 1.7
	body.add_child(new_col)

	# 新規プレイで遊ぶシナリオ(2026-09-21、docs/scenario_editor.md)。エディタで作った/直した内容は、
	# ここで選んで新規プレイを始めた時に読み込まれる(遊び始めたスロットは、その時点の内容のまま続く)。
	var scenario_row := HBoxContainer.new()
	new_col.add_child(scenario_row)
	var scenario_label := Label.new()
	scenario_label.text = "シナリオ:"
	scenario_row.add_child(scenario_label)
	new_game_scenario_option = OptionButton.new()
	new_game_scenario_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_game_scenario_option.clip_text = true
	scenario_row.add_child(new_game_scenario_option)
	_refresh_scenario_options()

	var new_game_button := Button.new()
	new_game_button.text = "🆕 新規プレイを開始する"
	_apply_caution_button_style(new_game_button)
	new_game_button.pressed.connect(_on_new_game_pressed)
	new_col.add_child(new_game_button)

	var transfer_grid := GridContainer.new()
	transfer_grid.columns = 2
	transfer_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_col.add_child(transfer_grid)

	# エディタ(PC)で作ったシナリオのzipを取り込む・スマホに入っているカスタムシナリオを整理する(2026-09-21)。
	# 取り込んだシナリオは、上の「シナリオ:」の一覧に出る(新規プレイで遊べる)。
	var scenario_import_button := Button.new()
	scenario_import_button.text = "📥 シナリオを取り込む"
	scenario_import_button.tooltip_text = "エディタで書き出したシナリオのファイル(zip)を選んで、カスタムシナリオとして追加する(同じIDが既にあれば、確認して上書き)"
	scenario_import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scenario_import_button.pressed.connect(_on_scenario_import_pressed)
	transfer_grid.add_child(scenario_import_button)

	var scenario_manage_button := Button.new()
	scenario_manage_button.text = "🗂️ シナリオの管理"
	scenario_manage_button.tooltip_text = "取り込んだカスタムシナリオの一覧を見て、いらないものを削除する"
	scenario_manage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scenario_manage_button.pressed.connect(_on_scenario_manage_pressed)
	transfer_grid.add_child(scenario_manage_button)

	# 別の端末/場所へ移すための書き出しと取り込み(2026-09-20)。保存先・取り込み元はOSのファイル選択で選ぶ
	# (Androidでは、Googleドライブやダウンロードなども選べる画面が開く)。
	var export_button := Button.new()
	export_button.text = "📤 全スロットを書き出す"
	export_button.tooltip_text = "全てのスロットを1つのファイル(zip)にまとめて、選んだ場所へ保存する(バックアップ・別の端末への移行用)"
	export_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_button.pressed.connect(_on_export_pressed)
	transfer_grid.add_child(export_button)

	var import_button := Button.new()
	import_button.text = "📥 セーブを取り込む"
	import_button.tooltip_text = "書き出したファイルからスロットを選んで、新しいスロットとして追加する(今のスロットは変わらない)"
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_button.pressed.connect(_on_import_pressed)
	transfer_grid.add_child(import_button)

	# 「イベント確認が出来ない」という要望への対応(2026-09-14)。一度見ると二度と出ない
	# 導入/初雇用/初撤退/初割り当ての説明会話4種を、確認のためだけに何度でも見返せるように、
	# 「見た」フラグを丸ごとリセットするボタンを設定(セーブスロットパネル)に置く。
	# セーブデータ自体(資金/探索者等)には触れない。
	var reset_tutorial_button := Button.new()
	reset_tutorial_button.text = "🔄 イベント会話をリセットする(確認用)"
	reset_tutorial_button.tooltip_text = "導入/初雇用/初撤退/初割り当ての説明会話を、もう一度見られるようにします"
	reset_tutorial_button.pressed.connect(_on_reset_tutorials_pressed)
	new_col.add_child(reset_tutorial_button)

	new_game_confirm = ConfirmationDialog.new()
	new_game_confirm.dialog_text = "現在の進行とは別に、新しいセーブスロットでゼロから始めます。よろしいですか？"
	new_game_confirm.confirmed.connect(_on_new_game_confirmed)
	new_game_confirm.title = "確認"
	new_game_confirm.cancel_button_text = "やめる"
	new_game_confirm.ok_button_text = "開始する"
	_apply_caution_button_style(new_game_confirm.get_ok_button())
	add_child(new_game_confirm)

	delete_slot_confirm = ConfirmationDialog.new()
	delete_slot_confirm.confirmed.connect(_on_delete_slot_confirmed)
	delete_slot_confirm.title = "確認"
	delete_slot_confirm.cancel_button_text = "やめる"
	delete_slot_confirm.ok_button_text = "削除する"
	_apply_danger_button_style(delete_slot_confirm.get_ok_button())
	add_child(delete_slot_confirm)

	# OSのファイル選択が使えない環境のための、Godot自身のファイル選択画面(_show_file_dialogが使い分ける)。
	# 通常はOSのファイル選択(DisplayServer.file_dialog_show)を直接呼ぶ。FileDialogのuse_native_dialogは使わない:
	# 保存先の選択後に、フィルタの拡張子(.zip)を勝手に付け足すため、Androidの`content://.../document/17`が
	# `.../document/17.zip`という別のURIになり、書き込みが「権限なし」で失敗した(2026-09-20、実機で確認)。
	export_file_dialog = FileDialog.new()
	export_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_file_dialog.title = "セーブの書き出し先"
	export_file_dialog.add_filter("*.zip", "セーブのファイル(zip)")
	export_file_dialog.file_selected.connect(_on_export_file_selected)
	add_child(export_file_dialog)

	import_file_dialog = FileDialog.new()
	import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_file_dialog.title = "取り込むセーブのファイル"
	import_file_dialog.add_filter("*.zip", "セーブのファイル(zip)")
	import_file_dialog.file_selected.connect(_on_import_file_selected)
	add_child(import_file_dialog)

	# 取り込むスロットを選ぶ画面(ファイルには複数のスロットが入っている)。最初は全て選択済み。
	import_confirm = ConfirmationDialog.new()
	import_confirm.title = "取り込むスロットを選ぶ"
	import_confirm.ok_button_text = "取り込む"
	import_confirm.cancel_button_text = "やめる"
	var import_col := VBoxContainer.new()
	import_confirm.add_child(import_col)
	var import_hint := Label.new()
	import_hint.text = "選んだスロットを、新しいスロットとして追加します(今のスロットは変わりません)。"
	import_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	import_hint.custom_minimum_size = Vector2(600, 0)
	import_col.add_child(import_hint)
	import_slot_list = ItemList.new()
	# タップで選択の入り切りができるモード。SELECT_MULTIはCtrl/Shiftを押しながら選ぶ前提で、タッチ操作だと
	# 押したスロットだけが選ばれ、複数を選べなかった(2026-09-20、実機で確認)。
	import_slot_list.select_mode = ItemList.SELECT_TOGGLE
	import_slot_list.custom_minimum_size = Vector2(600, 200)
	import_col.add_child(import_slot_list)
	import_confirm.confirmed.connect(_on_import_confirmed)
	import_confirm.canceled.connect(SaveSystem.cancel_import)
	add_child(import_confirm)

	# シナリオの取り込み(2026-09-21): ファイルの選択 → 検査 → 内容の確認(同じIDが既にあれば、上書きの確認を兼ねる)→ 取り込み。
	scenario_import_file_dialog = FileDialog.new()
	scenario_import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	scenario_import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	scenario_import_file_dialog.title = "取り込むシナリオのファイル"
	scenario_import_file_dialog.add_filter("*.zip", "シナリオのファイル(zip)")
	scenario_import_file_dialog.file_selected.connect(_on_scenario_import_file_selected)
	add_child(scenario_import_file_dialog)

	scenario_import_confirm = ConfirmationDialog.new()
	scenario_import_confirm.title = "シナリオを取り込む"
	scenario_import_confirm.ok_button_text = "取り込む"
	scenario_import_confirm.cancel_button_text = "やめる"
	scenario_import_label = Label.new()
	scenario_import_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # 日本語はAUTOWRAP_WORDだとAndroidで折り返されない
	scenario_import_label.custom_minimum_size = Vector2(600, 0)
	scenario_import_confirm.add_child(scenario_import_label)
	scenario_import_confirm.confirmed.connect(_on_scenario_import_confirmed)
	scenario_import_confirm.canceled.connect(ScenarioTransfer.cancel_import)
	add_child(scenario_import_confirm)

	# カスタムシナリオの管理(一覧と削除)。「選んだシナリオを削除」を押すと、確認を挟んで削除し、一覧を開き直す(続けて消せる)。
	scenario_manage_dialog = ConfirmationDialog.new()
	scenario_manage_dialog.title = "カスタムシナリオの管理"
	scenario_manage_dialog.ok_button_text = "選んだシナリオを削除"
	scenario_manage_dialog.cancel_button_text = "閉じる"
	_apply_danger_button_style(scenario_manage_dialog.get_ok_button())
	var manage_col := VBoxContainer.new()
	scenario_manage_dialog.add_child(manage_col)
	scenario_manage_hint = Label.new()
	scenario_manage_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scenario_manage_hint.custom_minimum_size = Vector2(600, 0)
	manage_col.add_child(scenario_manage_hint)
	scenario_manage_list = ItemList.new()
	scenario_manage_list.custom_minimum_size = Vector2(600, 220)
	scenario_manage_list.item_selected.connect(func(_index: int): scenario_manage_dialog.get_ok_button().disabled = false)
	manage_col.add_child(scenario_manage_list)
	scenario_manage_dialog.confirmed.connect(_on_scenario_manage_confirmed)
	add_child(scenario_manage_dialog)

	scenario_delete_confirm = ConfirmationDialog.new()
	scenario_delete_confirm.ok_button_text = "削除する"
	scenario_delete_confirm.cancel_button_text = "やめる"
	scenario_delete_confirm.title = "確認"
	_apply_danger_button_style(scenario_delete_confirm.get_ok_button())
	scenario_delete_confirm.confirmed.connect(_on_scenario_delete_confirmed)
	scenario_delete_confirm.canceled.connect(_on_scenario_manage_pressed.call_deferred) # やめたら、一覧へ戻る
	add_child(scenario_delete_confirm)

## 新規プレイで選べるシナリオの一覧を作り直す。開いていたシナリオ(今の世界)を初期の選択にする。
## パネルを開くたびに呼ぶので、エディタで足した/消したシナリオが、ゲームを再起動せずに一覧へ出る。
func _refresh_scenario_options(force_source: String = "", force_id: String = "") -> void:
	var previous: Dictionary = {}
	if new_game_scenario_option.selected >= 0:
		previous = new_game_scenario_option.get_item_metadata(new_game_scenario_option.selected)
	var preferred_id := String(previous.get("id", ScenarioEvents.info.get("id", "")))
	var preferred_source := String(previous.get("source", ScenarioEvents.info.get("source", "default")))
	if force_id != "": # 取り込んだシナリオを、新規プレイの選択にする
		preferred_id = force_id
		preferred_source = force_source
	new_game_scenario_option.clear()
	for entry in ScenarioStore.list_scenarios():
		var label: String = entry["name"] if entry["source"] == "default" else "%s (カスタム)" % entry["name"]
		new_game_scenario_option.add_item(label)
		var index := new_game_scenario_option.item_count - 1
		new_game_scenario_option.set_item_metadata(index, entry)
		new_game_scenario_option.set_item_tooltip(index, entry["description"])
		if entry["id"] == preferred_id and entry["source"] == preferred_source:
			new_game_scenario_option.select(index)

func _selected_scenario() -> Dictionary:
	if new_game_scenario_option.selected < 0:
		return {}
	return new_game_scenario_option.get_item_metadata(new_game_scenario_option.selected)

func _on_new_game_pressed() -> void:
	var entry := _selected_scenario()
	new_game_confirm.dialog_text = "シナリオ「%s」を、現在の進行とは別の新しいセーブスロットでゼロから始めます。よろしいですか？" % String(entry.get("name", "(不明)"))
	new_game_confirm.popup_centered()

func _on_open_slots_pressed() -> void:
	_refresh_scenario_options()
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
		var scenario_text: String = " / " + slot["scenario_name"] if slot["scenario_name"] != "" else ""
		slot_list.add_item("%s%s — %s / 資金%d / Day%d / 探索者%d人%s" % [
			label, active_mark, SaveSystem.format_saved_at(slot["saved_at"]), slot["funds"], slot["day"], slot["npc_count"], scenario_text])
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
	var entry := _selected_scenario()
	SaveSystem.create_new_slot(slot_name_input.text.strip_edges(), String(entry.get("id", "")), String(entry.get("source", "default")))
	_refresh_all()
	_close_modal(slot_panel)
	_play_intro_if_unseen() # 遊ぶシナリオの導入会話を、そのシナリオでまだ見ていなければ流す(パネルを閉じた後: 開いたままだと会話が隠れる)

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

## ファイルを選ぶ画面を開く。OSの画面が使えれば(WindowsとAndroid)それを、無ければGodotの代替画面を出す。
## 選んだパスは、on_selectedに渡す。書き出し先(save=true)にはMIME形式(application/zip)を付け、Androidが
## 保存するファイルの種類を取り違えないようにする。取り込み元にはMIME形式を付けない(ドライブなどが、zipを
## 別の種類として扱うことがあり、選べなくなるのを避ける。中身はSaveSystem.read_import_file()が確かめる)。
func _show_file_dialog(save: bool, title: String, file_name: String, on_selected: Callable, fallback: FileDialog, filter_label: String = "セーブのファイル(zip)") -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var filters := PackedStringArray(["*.zip;%s;application/zip" % filter_label if save else "*.zip;%s" % filter_label])
		var mode := DisplayServer.FILE_DIALOG_MODE_SAVE_FILE if save else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
		# 選ばれた後の呼び出しは、メインスレッドで行う(OSの画面は別スレッドから知らせてくることがある)。
		DisplayServer.file_dialog_show(title, "", file_name, false, mode, filters,
			func(status: bool, paths: PackedStringArray, _filter_index: int):
				if status and not paths.is_empty():
					on_selected.call_deferred(paths[0]))
	else:
		if save:
			fallback.current_file = file_name
		fallback.popup_centered(Vector2i(720, 460))

func _on_export_pressed() -> void:
	_show_file_dialog(true, "セーブの書き出し先", SaveSystem.default_export_file_name(), _on_export_file_selected, export_file_dialog)

func _on_export_file_selected(path: String) -> void:
	var count := SaveSystem.export_all_slots(path)
	if count < 0:
		manual_save_status_label.text = "書き出しに失敗しました"
		return
	_refresh_slot_list() # 今のスロットを保存したので、一覧の資金/日付も更新される
	manual_save_status_label.text = "%d個のスロットを書き出しました" % count

func _on_import_pressed() -> void:
	_show_file_dialog(false, "取り込むセーブのファイル", "", _on_import_file_selected, import_file_dialog)

## ファイルを選んだ後: 中身を読んで、含まれるスロットの一覧を出す(ここではまだ何も取り込まない)。
func _on_import_file_selected(path: String) -> void:
	var result := SaveSystem.read_import_file(path)
	if not result["ok"]:
		manual_save_status_label.text = "取り込めません: %s" % result["error"]
		return
	_import_slots = result["slots"]
	import_slot_list.clear()
	for slot in _import_slots:
		var label: String = slot["name"] if slot["name"] != "" else "スロット%d" % slot["key"]
		var idx := import_slot_list.add_item("%s — %s / 資金%d / Day%d / 探索者%d人" % [
			label, SaveSystem.format_saved_at(slot["saved_at"]), slot["funds"], slot["day"], slot["npc_count"]])
		import_slot_list.select(idx, false) # 最初は全て選択済み(false=既に選択済みの行を解除しない)
	import_confirm.popup_centered()

func _on_import_confirmed() -> void:
	var keys: Array = []
	for idx in import_slot_list.get_selected_items():
		keys.append(_import_slots[idx]["key"])
	_import_slots = []
	if keys.is_empty():
		SaveSystem.cancel_import()
		manual_save_status_label.text = "スロットが選ばれていないので、取り込みませんでした"
		return
	var new_ids := SaveSystem.import_slots(keys)
	_refresh_slot_list()
	if new_ids.is_empty():
		manual_save_status_label.text = "取り込みに失敗しました"
		return
	manual_save_status_label.text = "%d個のスロットを取り込みました(スロット%s)" % [
		new_ids.size(), "、".join(new_ids.map(func(id): return str(id)))]

## シナリオのzipを選んだ後: 中身を検査して、取り込む内容を見せる(ここではまだ何も取り込まない)。
func _on_scenario_import_pressed() -> void:
	_show_file_dialog(false, "取り込むシナリオのファイル", "", _on_scenario_import_file_selected, scenario_import_file_dialog, "シナリオのファイル(zip)")

func _on_scenario_import_file_selected(path: String) -> void:
	var result := ScenarioTransfer.read_import_file(path)
	if not result["ok"]:
		manual_save_status_label.text = "取り込めません: %s" % result["error"]
		return
	var lines := PackedStringArray()
	lines.append("シナリオ「%s」(ID: %s)を取り込みます。" % [result["name"], result["id"]])
	lines.append("フロア%d・イベント%d本・画像%d枚" % [result["floors"], result["events"], result["images"]])
	if result["author"] != "":
		lines.append("作者: %s" % result["author"])
	if result["description"] != "":
		lines.append(result["description"])
	if result["exists"]:
		lines.append("")
		lines.append("同じIDのカスタムシナリオが既にあります。上書きします(元の内容には戻せません)。遊び始めているセーブは、そのまま遊べます。")
	scenario_import_confirm.ok_button_text = "上書きして取り込む" if result["exists"] else "取り込む"
	scenario_import_label.text = "\n".join(lines)
	scenario_import_confirm.popup_centered()

func _on_scenario_import_confirmed() -> void:
	var result := ScenarioTransfer.install_import()
	if not result["ok"]:
		manual_save_status_label.text = "取り込めません: %s" % result["error"]
		return
	_refresh_scenario_options("custom", String(result["id"]))
	manual_save_status_label.text = "シナリオ「%s」を%s取り込みました(「新規プレイを開始する」で遊べます)" % [
		result["name"], "上書きして" if result["replaced"] else ""]

## 取り込んだカスタムシナリオの一覧を開く。
func _on_scenario_manage_pressed() -> void:
	_scenario_manage_entries = ScenarioTransfer.list_custom()
	scenario_manage_list.clear()
	for entry in _scenario_manage_entries:
		scenario_manage_list.add_item("%s (%s) — フロア%d・イベント%d本・画像%d枚" % [entry["name"], entry["id"], entry["floors"], entry["events"], entry["images"]])
	scenario_manage_hint.text = "取り込んだカスタムシナリオです。削除しても、遊び始めているセーブは、そのまま遊べます。" if not _scenario_manage_entries.is_empty() else "カスタムシナリオは入っていません(「シナリオを取り込む」で追加できます)。"
	scenario_manage_dialog.get_ok_button().disabled = true # 一覧で選ぶまで、削除は押せない
	scenario_manage_dialog.popup_centered()

func _on_scenario_manage_confirmed() -> void:
	var selected := scenario_manage_list.get_selected_items()
	if selected.is_empty():
		return
	_pending_delete_scenario = _scenario_manage_entries[selected[0]]
	scenario_delete_confirm.dialog_text = "カスタムシナリオ「%s」を削除します。元に戻せません。\n(遊び始めているセーブは、そのまま遊べます)" % _pending_delete_scenario["name"]
	scenario_delete_confirm.popup_centered()

func _on_scenario_delete_confirmed() -> void:
	var entry := _pending_delete_scenario
	_pending_delete_scenario = {}
	if not entry.is_empty() and ScenarioTransfer.delete_custom(String(entry["id"])):
		SaveSystem.forget_scenario_records("custom", String(entry["id"])) # 同じIDで取り込み直したら、導入会話がまた流れるように
		_refresh_scenario_options()
		manual_save_status_label.text = "カスタムシナリオ「%s」を削除しました" % entry["name"]
	else:
		manual_save_status_label.text = "削除に失敗しました"
	_on_scenario_manage_pressed.call_deferred() # 続けて他のシナリオも削除できるよう、一覧を開き直す

## 一度見ると二度と出ない説明用イベント会話4種を、確認用に未視聴の状態へ戻す。導入会話
## ("intro_part1")は起動時にしかトリガーできないため、リセット直後にこの場で
## 再生する(パネルを閉じてから再生しないとdialogue_panelが背後に隠れる。他の会話の再生箇所と
## 同じ理由)。残り3つ(初雇用/初撤退/初割り当て)は該当の操作を実際に行うと再度表示される。
func _on_reset_tutorials_pressed() -> void:
	SaveSystem.reset_tutorial_flags()
	_close_modal(slot_panel)
	ScenarioEvents.play_guide("intro_part1")

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
const BASE_MAP_SECTION_HEADER := 40.0 # タイトル行+担当探索者アイコン行の2段分の高さ
const BASE_MAP_SECTION_PADDING := 12.0
const BASE_MAP_OUTER_MARGIN := Vector2(20, 20)
# マップ上部にフロートで重ねているエリアタブバー(_build_ui参照)のおおよその高さ。
# ズームでは拡大縮小されない固定オーバーレイなので、_map_zoomを掛けない生の値で扱う。
const MAP_NAV_BAR_CLEARANCE := 50.0
const MAP_ZOOM_MIN := 0.4
const MAP_ZOOM_MAX := 2.2
const MAP_ZOOM_STEP := 0.15
const MAP_ICON_SIZE := 40.0 # パーティ代表アイコンの一辺(2026-09-14、20pxから2倍に拡大)
# 難易度モード(Difficulty.Mode)の色: Easy=緑 / Normal=青灰 / Hard=赤。マップのパーティアイコンの左上のバッジ(頭文字E/N/Hの
# 背景)と、パーティ詳細の切り替えボタン(選んでいる側)で使う。肖像がアイコンの背景を覆うので、色はバッジで見せる。
const DIFFICULTY_COLORS := [Color(0.16, 0.55, 0.26), Color(0.3, 0.42, 0.6), Color(0.78, 0.16, 0.14)]
# タッチUIでは、マップの文字を(ズーム1.0でも)左メニューのボタンの文字(16px)以上にする(2026-09-20、
# 実機で「マップの文字が小さすぎる」との指摘)。大きくするのは文字だけで、フロアの箱の大きさ(BASE_MAP_*)は
# 変えない(箱は文字数に対して十分広い)。セクションの見出しだけは、2行ぶんの文字が収まるよう高さも同じ倍率で
# 広げる。デスクトップは従来どおり(1.0)。パーティアイコンの中の文字(頭文字・バッジ)は、アイコン自体が
# 拡大されないので対象外。
const TOUCH_MAP_FONT_SCALE := 1.3

func _map_font_scale() -> float:
	return TOUCH_MAP_FONT_SCALE if _touch_ui else 1.0

## マップ上の文字のサイズ。baseはズーム1.0・デスクトップでの大きさ、min_sizeは縮小ズームでも読める下限。
func _map_font_size(base: int, min_size: int) -> int:
	return maxi(min_size, roundi(base * _map_zoom * _map_font_scale()))

func _map_section_header() -> float:
	return BASE_MAP_SECTION_HEADER * _map_font_scale() * _map_zoom

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
	# ワールドの中身(エリア/セクション/フロア/イベント)はWorldSchemaDbが
	# (シナリオから)既に流し込み済み。ここではWorldMapの内容を
	# UI(ノードグラフ)として描画するだけ。担当セクションの選択肢(section_tree)は
	# 探索者管理パネルを開くたびに_populate_section_treeで組み直す。
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

	# 下端には、会話ウィンドウ1枚分の余白を足す(ズームによらない固定の高さ)。マップの一番下に近いフロアでイベントが起きても、
	# スクロールの限界に阻まれず、フロアを会話ウィンドウの上へ持ち上げて見せられる(_focus_map)。
	map_canvas.custom_minimum_size = content_size + Vector2(40, 40) * _map_zoom + Vector2(0, _dialogue_panel_height())
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
	var section_header := _map_section_header()
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
	var header := _map_section_header()
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
	var link_height := 18.0 * _map_zoom * _map_font_scale()
	var link := Button.new()
	link.text = "→ %s" % WorldMap.areas[target_area_id]["name"]
	link.flat = true
	link.add_theme_font_size_override("font_size", _map_font_size(11, 8))
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
	title_button.add_theme_font_size_override("font_size", _map_font_size(14, 9))
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
	# タップ判定は_on_map_tapでこの位置を直接ヒットテストする)。
	var lock_icon := Label.new()
	lock_icon.add_theme_font_size_override("font_size", _map_font_size(12, 9))
	lock_icon.modulate = Color(1, 0.82, 0.35, 0.95)
	lock_icon.position = bounds.position + Vector2(6, bounds.size.y + 4 * _map_zoom)
	map_canvas.add_child(lock_icon)
	lock_icon.text = "🔒 未到達(%sで詳細)" % ("タップ" if _touch_ui else "クリック") # 文字は最後に(上と同じ理由)
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
	name_label.add_theme_font_size_override("font_size", _map_font_size(13, 9))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_label)

	var status_label := Label.new()
	status_label.add_theme_font_size_override("font_size", _map_font_size(12, 8)) # 条件のアイコンが小さくならないよう、11から12に
	status_label.modulate = Color(1, 1, 1, 0.7)
	# 突破に必要な条件(長いアイテム名など)で箱が横に広がらないよう、収まらなければ末尾を「…」にする(全文はフロア詳細)
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
##
## フロアの箱と鍵アイコンは、1回のタップ(クリック)で詳細を開く(2026-09-24。以前はダブルタップで、
## 気付けなかった)。押してから離すまでにほぼ動いていなければタップ、動いたらパン(ドラッグ)とみなす。
func _on_map_canvas_gui_input(event: InputEvent) -> void:
	# ダブルクリック判定は先に単独でチェックする。そうしないと下のプレーンな左クリック分岐に
	# 先に引っかかってパン開始(_map_panning=true)扱いになり、ダブルクリックへ届かなくなる。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		_map_press_is_tap = false
		_on_map_double_click(event.position)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_map_panning = event.pressed
		if event.pressed:
			_map_press_pos = event.global_position
			_map_press_is_tap = true
		elif _map_press_is_tap:
			_map_press_is_tap = false
			if not _pinch_active and event.global_position.distance_to(_map_press_pos) <= _map_tap_slop():
				_on_map_tap(event.position)
	elif event is InputEventMouseMotion and _map_panning:
		if event.global_position.distance_to(_map_press_pos) > _map_tap_slop():
			_map_press_is_tap = false
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

## 生のタッチを最初に見て、マップ上の2本指ピンチを検出する(ボタンなどのControlより先に呼ばれる)。
##
## ピンチ中は、指の動きに合わせて、本物のレイアウトを一定間隔で作り直す(_rebuild_for_pinch)。
## 以前は、ピンチ中は見た目だけを拡大縮小し、離した時に1回だけ作り直していたが、(1)縮小して
## マップが画面より小さくなると、見た目は中央に寄るのに、離した後のレイアウトは左上に寄る、(2)縦方向は
## 倍率に比例しない(文字の最小サイズなど)ため、離した後に位置が飛ぶ、という食い違いで、実機で酔う
## ほど不快だった。再構築を実機で約0.5秒→約60msに軽くできた(絵文字フォントの登録と、文字を最後に
## 1回だけ設定する変更)ので、常に本物のレイアウトだけを見せる方式にした。
func _input(event: InputEvent) -> void:
	if _handle_dialogue_key(event):
		return
	if event is InputEventScreenTouch:
		_on_touch_changed(event)
	elif event is InputEventScreenDrag:
		_on_touch_dragged(event)
	elif _pinch_active and event is InputEventMouse:
		# 1本目の指から作られる擬似マウス(パン・クリック)を止める。止めないと、ピンチしながらマップが
		# 1本指でパンされたり、指の下のボタンが押されたりする
		get_viewport().set_input_as_handled()

## デスクトップ: 会話パネルのどこをクリックしても、次へ進む(「次へ」ボタンに狙いを定めなくてよい)。選択肢が出ている行では
## 進まない(advance()が何もしない)。ボタン(次へ・選択肢)を押した時は、ボタン自身が処理するので、ここには来ない。
func _on_dialogue_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and EventDialogue.is_active:
		EventDialogue.advance()
		accept_event()

## デスクトップ: Enter/Spaceで会話を進める(押しっぱなしの繰り返しでは進まない)。選択肢が出ている行では、何もしない
## (フォーカス中の選択肢ボタンに任せる)。GUIより先に処理して握りつぶすので、フォーカスが残っている別のボタン
## (左メニューなど)が、会話中のEnter/Spaceで押される事故も無い。処理したらtrue。
func _handle_dialogue_key(event: InputEvent) -> bool:
	if _touch_ui or not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or not (key_event.keycode in DIALOGUE_ADVANCE_KEYS):
		return false
	if not EventDialogue.is_active or not dialogue_panel.visible or not advance_hint.visible:
		return false
	EventDialogue.advance()
	get_viewport().set_input_as_handled()
	return true

func _on_touch_changed(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position
		if not _pinch_active and _touch_points.size() == 2 and _can_start_pinch():
			_start_pinch()
		if _pinch_active:
			get_viewport().set_input_as_handled() # 追加の指の押下を、ScrollContainerなどに渡さない
	else:
		_touch_points.erase(event.index)
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
	_map_press_is_tap = false
	_pinch_prev_distance = maxf(a.distance_to(b), 1.0)
	_pinch_prev_center = (a + b) * 0.5
	_pinch_target_zoom = _map_zoom
	_pinch_last_rebuild_msec = Time.get_ticks_msec()

## 指を離した時: 間引きに関係なく、最後の目標倍率に合わせる。
func _end_pinch() -> void:
	_rebuild_for_pinch(true)
	_pinch_active = false

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

## フロア(ノード)の枠内なら詳細ポップアップ、それ以外でセクション枠内ならそのセクションの
## 掲示板スレッドを開く。フロアの箱の方がセクション枠より内側にある(小さい)ので、先に
## フロアを判定してからセクションにフォールバックする。
## タップとみなす、押してから離すまでの移動量の上限(画面上のpx)。指は、マウスより止めにくい。
func _map_tap_slop() -> float:
	return 24.0 if _touch_ui else 6.0

## マップを1回タップ(クリック)した: フロアの箱なら詳細、未到達セクションの鍵アイコンなら説明を開く。
## 何かを開いたらtrue。
func _on_map_tap(pos: Vector2) -> bool:
	for id in node_boxes.keys():
		var box: PanelContainer = node_boxes[id]
		if box.get_rect().has_point(pos):
			_show_node_detail(id)
			return true
	for section_id in section_lock_icons.keys():
		var lock_icon: Control = section_lock_icons[section_id]
		if lock_icon.visible and lock_icon.get_rect().has_point(pos):
			_show_section_lock_detail(section_id)
			return true
	return false

## ダブルタップ(ダブルクリック): セクション枠の何も無い所なら、そのセクションの掲示板スレッドを開く。
## フロアの箱や鍵アイコンの上なら、1回目のタップで既に開いているので(_on_map_tap)何もしない。
func _on_map_double_click(pos: Vector2) -> void:
	for id in node_boxes.keys():
		if node_boxes[id].get_rect().has_point(pos):
			return
	for section_id in section_lock_icons.keys():
		var lock_icon: Control = section_lock_icons[section_id]
		if lock_icon.visible and lock_icon.get_rect().has_point(pos):
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

## ゲート(障害物)の種類を表すアイコン。マップの突破待ちのフロアの箱と、フロア詳細のゲート説明に出す(2026-09-22)。
## どれも「何が行く手を阻んでいるか」を表す: 鍵=施錠された扉、虫眼鏡=隠された通路、パズル=謎解き、爆発=壊して進む障害、
## 剣=敵、王冠=血筋、リュック=持ち物。Androidでも表示できるよう、古い世代の絵文字を選んである。
const SKILL_GATE_ICONS := {
	SkillTypes.Skill.LOCKPICKING: "🔒",
	SkillTypes.Skill.PERCEPTION: "🔍",
	SkillTypes.Skill.WISDOM: "🧩",
	SkillTypes.Skill.DESTRUCTION: "💥",
}
const COMBAT_GATE_ICON := "⚔️"
const BLOODLINE_GATE_ICON := "👑"
const ITEM_GATE_ICON := "🎒"
const UNKNOWN_GATE_ICON := "❓"
const GATE_CONDITION_COLOR := Color(1.0, 0.9, 0.62) # 突破待ちのフロアの、条件の行の色(暖色)

## ゲートの種類のアイコン。ゲートが無ければ空文字。
func _gate_icon(gate: Dictionary) -> String:
	match gate.get("type", ""):
		"skill":
			return SKILL_GATE_ICONS.get(gate["skill"], UNKNOWN_GATE_ICON)
		"combat":
			return COMBAT_GATE_ICON
		"innate_trait":
			return BLOODLINE_GATE_ICON
		"item":
			return ITEM_GATE_ICON
	return "" if gate.is_empty() else UNKNOWN_GATE_ICON

## 突破に必要な条件の短い表示「アイコン 条件」。マップの突破待ちのフロアの箱に出す(例: 「🔒 鍵開け Lv3」「⚔️ 敵の戦闘力 320」)。
## 基礎値のまま(パーティの難易度による増減は反映しない。推奨戦力と同じ扱い)。ゲートが無ければ空文字。
func _gate_short_text(gate: Dictionary) -> String:
	if gate.is_empty():
		return ""
	var icon := _gate_icon(gate)
	match gate.get("type", ""):
		"skill":
			return "%s %s Lv%d" % [icon, SkillTypes.SKILL_NAMES[gate["skill"]], gate["min_level"]]
		"combat":
			return "%s 敵の戦闘力 %d" % [icon, gate["enemy_power"]]
		"innate_trait":
			return "%s 血筋: %s" % [icon, gate["value"]]
		"item":
			return "%s %s" % [icon, Items.name_of(gate["item"])]
	return "%s 不明" % icon

func _gate_description(gate: Dictionary) -> String:
	if gate.is_empty():
		return "なし(自由に通行可能)"
	var icon := _gate_icon(gate)
	match gate.get("type", ""):
		"skill":
			return "%s %s Lv%d以上が必要" % [icon, SkillTypes.SKILL_NAMES[gate["skill"]], gate["min_level"]]
		"combat":
			return "%s 戦闘(敵の戦闘力%d)" % [icon, gate["enemy_power"]]
		"innate_trait":
			return "%s 特定の血筋(%s)が必要" % [icon, gate["value"]]
		"item":
			return "%s アイテム「%s」の所持が必要" % [icon, Items.name_of(gate["item"])]
		_:
			return "%s 不明" % icon

## 未到達セクション(マップ上の鍵アイコン)をタップ(クリック)した時の詳細ウィンドウ。
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

## 状態テキストに加えて、自身(雇用探索者が到達済み)/誰か(野良探索者のみが発見)/未踏破の3色に
## ノードを塗り分ける。未踏破の場所は名前も????にして隠す。踏破待ち(発見済みだが未突破)は
## 半透明にして「まだ先に進めない」ことを示す。
func _refresh_map() -> void:
	for id in node_labels.keys():
		var status_label: Label = node_labels[id]
		var name_label: Label = node_name_labels[id]
		var box: PanelContainer = node_boxes[id]

		var status_color := Color(1, 1, 1, 0.7)
		if WorldMap.is_passed(id):
			status_label.text = "突破済み"
		elif WorldMap.is_found(id):
			# 突破待ちは、何が必要かを出す(アイコン+条件。2026-09-22)。ゲートが無い(通常は起きない)時だけ従来の文言。
			# 箱ごと半透明(下のalpha)なので、条件の行は暖色で不透明にして、薄い灰色の文字より読み取りやすくする
			var condition := _gate_short_text(WorldMap.nodes[id].get("gate", {}))
			status_label.text = condition if condition != "" else "発見済み(進行不可)"
			if condition != "":
				status_color = GATE_CONDITION_COLOR
		else:
			status_label.text = "未発見"
		status_label.modulate = status_color

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
	_record_party_areas()

## マップ上でパーティアイコンを表示するノード(現在フロア)を1つ選ぶ。担当パーティはセクション内の
## 未発見フロア全部に同時並行でアタックする実装(exploration.gd)なので厳密な「今いる場所」は
## 存在しないが、表示上は次の優先順で代表点を決める:
## 1) 発見済みだが未突破のゲートがあれば、そこで足止め中として表示
## 2) なければ、既知の最前線(未発見フロアに隣接する突破済みノード)
## 3) それも無ければ(セクション完全踏破後など)周回(ループ)の進み具合(exploration.gdの
##    _process_lap/Parties.lap_start_day)に応じて最初のフロアから動かす。1周し終えるたびに
##    最初のフロアへ戻る(2026-09-15、「ループでループしない、終わったらアイコンが
##    最初に戻るべきだが戻っていない」というバグ報告への対応)。
## 4) 攻略しきっていないのに、どれにも当たらない(配置転換された直後で、入口がまだ見つかっていない等)なら、
##    探している最前線のフロア(無ければ先頭)。完全攻略済みなら最後のフロア。
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

	# 4) まだ攻略しきっていないのに、発見済みのフロアも最前線の突破済みフロアも無いセクション(次のセクションへ配置転換された
	#    直後など)は、入口を探している最中。探している最前線のフロア(無ければ先頭)に出す。以前は、ここで「セクションの最後の
	#    フロア」を返していたため、配置転換された直後に、入口が発見されるまで、最後のフロアへ飛んだように見えた(2026-09-21報告)。
	if not WorldMap.is_section_cleared(section_id):
		var frontier: Array = WorldMap.frontier_for_section(section_id)
		return frontier[0] if not frontier.is_empty() else member_ids[0]

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
	var is_recovering: bool = int(party["status"]) == Parties.Status.RECOVERING
	var is_looping := _is_party_looping(party)
	var is_retreating := Parties.is_retreating(party)
	var difficulty_mode := Difficulty.of_party(party)
	icon.tooltip_text = "%s(%s / %s / %s)" % [party["name"], _party_status_text(party), "退避中" if is_retreating else ("ループ中" if is_looping else "進行中"), Difficulty.mode_name(difficulty_mode)]
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

	# 撤退して休養中のパーティは、フロアの上から動かないので、止まって見えてしまう(実機で指摘)。
	# 休養中だと分かるよう、肖像を暗くし、橙の枠を付け、下に「💤 残り日数」を出す。
	# 文字では40pxの小さなアイコンに収まらず、点滅などのエフェクトは、アイコンを毎日作り直すので途切れるため、
	# 静止して見える暗転+枠+バッジにした。
	if is_recovering:
		for child in icon.get_children():
			if child is TextureRect:
				child.modulate = Color(0.5, 0.5, 0.56)
		var frame := Panel.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		var frame_style := StyleBoxFlat.new()
		frame_style.draw_center = false
		frame_style.border_color = Color(0.98, 0.62, 0.2)
		frame_style.set_border_width_all(maxi(2, roundi(3 * _map_zoom)))
		frame_style.set_corner_radius_all(4)
		frame.add_theme_stylebox_override("panel", frame_style)
		icon.add_child(frame)
		var days_left: int = maxi(0, int(party["recovering_until_day"]) - TimeSystem.current_day)
		icon.add_child(_make_party_icon_badge("💤%d日" % days_left, BadgeCorner.BOTTOM_RIGHT, Color(0.55, 0.3, 0.05, 0.92)))

	# 進行中(⏩)かループ中(🔁)かを、右上に出す(担当セクションを完全踏破して周回している間がループ)。
	# 戦力不足で1つ前のセクションへ退避して力を付けている間は、戻っていることが分かる「⏪」を出す。
	var progress_badge := "⏪" if is_retreating else ("🔁" if is_looping else "⏩")
	icon.add_child(_make_party_icon_badge(progress_badge, BadgeCorner.TOP_RIGHT, Color(0, 0, 0, 0.6)))
	# 難易度の頭文字(E/N/H)を、難易度の色の背景で左上に出す。右下(休養の日数)は40pxのアイコンに収まる幅が
	# 足りず重なるので、右上の進行バッジの反対側の左上にした。
	var difficulty_color: Color = DIFFICULTY_COLORS[difficulty_mode]
	difficulty_color.a = 0.95
	icon.add_child(_make_party_icon_badge(Difficulty.initial(difficulty_mode), BadgeCorner.TOP_LEFT, difficulty_color))
	return icon

## 担当セクションを完全踏破していて、踏破後の設定が「ループ」(留まって周回する)ならtrue。
## そうでなければ(まだ攻略中、または「先へ進む」)進行中とみなす。
func _is_party_looping(party: Dictionary) -> bool:
	var section_id: String = party["assigned_section"]
	return party["post_clear_behavior"] == Parties.PostClearBehavior.STAY \
		and WorldMap.sections.has(section_id) and WorldMap.is_section_cleared(section_id)

enum BadgeCorner { TOP_LEFT, TOP_RIGHT, BOTTOM_RIGHT }

## パーティアイコンの隅に重ねる、絵文字や短い文字の小さなバッジ。
func _make_party_icon_badge(text: String, corner: BadgeCorner, bg_color: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match corner:
		BadgeCorner.TOP_LEFT:
			badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
		BadgeCorner.TOP_RIGHT:
			badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		BadgeCorner.BOTTOM_RIGHT:
			badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(6)
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_font_size_override("font_size", max(8, roundi(12 * _map_zoom)))
	badge.add_child(label)
	return badge

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

## パーティの担当セクションがあるエリアのid。未割当なら空文字。
func _area_of_party(party: Dictionary) -> String:
	var section_id: String = party["assigned_section"]
	return String(WorldMap.sections[section_id]["area"]) if WorldMap.sections.has(section_id) else ""

## マップの表示を、見せたい場所へ移す(2026-09-22)。エリアの表示はタブを押した時にしか変わらなかったため、イベントや、
## 次のエリアへ移ったパーティの様子が、表示中の別のエリアの裏で起きて見えなかった(「マップクリアで次のエリアに移動しても、
## マップが切り替わらない」との報告と、「イベントの状況を見たい」との要望)。切り替わる場面は3つ:
##   (1) イベントの会話が始まった(_on_scenario_event_started。起きた場所のエリア・フロアへ)
##   (2) 雇用パーティが、誰も来ていないエリアで初めてフロアを発見した(_on_area_first_entered)
##   (3) パーティが自動で、まだ誰も来ていないエリアへ配置転換された(_follow_parties_to_new_area)
## エリアが違えばそのエリアに切り替え、見せたいフロア(またはセクションの先頭)が画面に見えていなければ、見える位置へ
## スクロールする(会話ウィンドウに隠れない位置。既に見えているなら動かさない)。
func _focus_map(area_id: String, floor_id: String = "", section_id: String = "") -> void:
	if map_canvas == null or area_id == "" or not WorldMap.areas.has(area_id):
		return
	var switched := area_id != _active_area_id
	if switched:
		_on_area_tab_pressed(area_id) # マップを作り直し、スクロールは先頭へ戻る
	var scroll_pos := _map_scroll_target(floor_id, section_id)
	if not switched:
		map_scroll.scroll_horizontal = scroll_pos.x # 同じエリアの中なので、スクロールの範囲は最新
		map_scroll.scroll_vertical = scroll_pos.y
		return
	# エリアを切り替えた直後は、ScrollContainerのスクロール範囲がまだ前のエリアの大きさのまま(次のフレームで更新される)。
	# ここで位置を代入すると、古い範囲に丸められる。ピンチのズームと同じ「範囲(max_value)を手動で書き換えてから代入する」
	# 手順は、ここでは逆効果だった(範囲が古い値のまま固定され、位置も丸められたままになった。実測)ので、1フレーム待つ。
	_scroll_map_after_layout(scroll_pos)

## スクロールの範囲が新しいマップの大きさに更新されるのを(最大30フレーム)待ってから、位置を代入する。
## 更新が済んだかは、スクロールバーの範囲(max_value)がマップの大きさに届いたかで見る(1フレームでは済まないことがあった)。
func _scroll_map_after_layout(scroll_pos: Vector2i) -> void:
	for i in range(30):
		await get_tree().process_frame
		var updated: bool = map_scroll.get_v_scroll_bar().max_value >= map_canvas.custom_minimum_size.y - 1.0 \
			and map_scroll.get_h_scroll_bar().max_value >= map_canvas.custom_minimum_size.x - 1.0
		if updated:
			break
	map_scroll.scroll_horizontal = scroll_pos.x
	map_scroll.scroll_vertical = scroll_pos.y

## 見せたいフロア(無ければセクションの先頭)が、会話ウィンドウに隠れずに見える、マップのスクロール位置。既に見えていれば
## 今の位置のまま。見せたい場所が無ければ今の位置(エリアを切り替えた直後は先頭)。
func _map_scroll_target(floor_id: String, section_id: String) -> Vector2i:
	var current := Vector2i(map_scroll.scroll_horizontal, map_scroll.scroll_vertical)
	var rect := Rect2()
	if node_boxes.has(floor_id):
		rect = Rect2(node_boxes[floor_id].position, _map_node_size())
	elif section_bounds_cache.has(section_id):
		var bounds: Rect2 = section_bounds_cache[section_id]
		rect = Rect2(bounds.position, Vector2(bounds.size.x, minf(bounds.size.y, _map_section_header() + _map_cell_size().y))) # セクションの見出しと最初の1行
	else:
		return current
	var view := Vector2(map_scroll.size.x, maxf(120.0, map_scroll.size.y - _dialogue_reserved_height()))
	if Rect2(Vector2(current), view).encloses(rect):
		return current
	var target := rect.get_center() - view / 2.0
	return Vector2i(maxi(0, int(target.x)), maxi(0, int(target.y)))

## 会話ウィンドウが、マップの下側を覆う高さ。
func _dialogue_panel_height() -> float:
	return float(TOUCH_DIALOGUE_HEIGHT) if _touch_ui else float(200 + DESKTOP_DIALOGUE_LIFT)

## 会話が開いている間、マップの下側を覆う会話ウィンドウの高さ(開いていなければ0)。
func _dialogue_reserved_height() -> float:
	return _dialogue_panel_height() if EventDialogue.is_active else 0.0

## イベントの会話が始まった: 起きた場所(フロア・セクション・エリア)がマップにあれば、そこへ表示を移す。日数・フラグだけの
## 条件のイベントや案内会話には場所が無いので、何もしない。
func _on_scenario_event_started(event: Dictionary) -> void:
	var location: Dictionary = ScenarioEvents.event_location(event)
	if location.is_empty():
		return
	_focus_map(location["area"], location["floor"], location["section"])

## 雇用パーティが、誰も来ていなかったエリアで初めてフロアを発見した(掲示板の「初めて足を踏み入れた」)。
func _on_area_first_entered(area_id: String, node_id: String) -> void:
	if not WorldMap.nodes.has(node_id):
		return
	_focus_map(area_id, node_id, String(WorldMap.nodes[node_id]["section"]))

## フロア発見時の会話が挟まると、退避などによる担当セクションの変更(Exploration._check_blocked等)が
## _on_dialogue_finished()のマップ再描画より後に確定する(exploration.gdのparty_location_changed参照)。
## そのままだと、担当パネルの文字は新しい現在地を示すのに、マップ上のアイコンだけ前の場所に
## 取り残されてしまう(2026-09-22の報告)。ここで改めて描き直し、両者を揃える。
func _on_party_location_changed() -> void:
	_refresh_map()
	_refresh_party_roster()
	_refresh_party_detail()

## 毎日の更新で、パーティが自動で(完全踏破後の「先へ進む」の配置転換など)、まだ雇用パーティの誰も来ていない(発見したフロアが
## 無い)エリアへ移っていたら、そのエリアの担当セクションへ表示を移す。既に来たことのあるエリアへの移動(退避・復帰・
## ループ)では切り替えない(退避のたびに表示が行き来しないように)。手動の割り当て(パーティ画面・マップのセクション名)は
## 対象外: _refresh_mapが移動先を記録するので、翌日の更新で「自動で移った」とは数えない。
func _follow_parties_to_new_area() -> void:
	var target_area := ""
	var target_section := ""
	for party in Parties.get_parties():
		var area := _area_of_party(party)
		var previous: String = _party_area_seen.get(party["id"], area)
		if target_area == "" and area != "" and previous != area and not _employed_areas_seen.has(area):
			target_area = area
			target_section = String(party["assigned_section"])
		_party_area_seen[party["id"]] = area
	if target_area != "":
		_focus_map(target_area, "", target_section)

## 各パーティの担当エリアと、雇用パーティが既に来たエリア(発見したフロアがあるエリア)を記録する(_follow_parties_to_new_area用)。
## マップを描き直すたびに更新するので、手動の割り当て・ロード・新規開始による移動は、「自動で移った」とは数えられない。
func _record_party_areas() -> void:
	_party_area_seen.clear()
	for party in Parties.get_parties():
		_party_area_seen[party["id"]] = _area_of_party(party)
	_employed_areas_seen.clear()
	for id in WorldMap.nodes.keys():
		if WorldMap.is_found_by_employed(id):
			var section_id: String = WorldMap.nodes[id]["section"]
			if WorldMap.sections.has(section_id):
				_employed_areas_seen[WorldMap.sections[section_id]["area"]] = true

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
		hire_status_label.text = "雇用上限(%d)に達しています。探索者管理パネルから施設を拡張すると増やせます" % Economy.employ_cap
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
	# フラグは再生開始時ではなくEventDialogue.finished発火時に永続化する(理由は_ready()の導入会話の再生箇所
	# 再生箇所のコメント参照。診断コードが雇用だけシミュレートして会話を進めずに終わった場合
	# などに、実際には見せていないのに実ファイルへ「見た」と書き込んでしまう事故を防ぐ)。
	if not SaveSystem.is_tutorial_seen("party_formed"):
		_close_modal(hire_panel)
		ScenarioEvents.play_guide("party_formed")

func _on_view_thread_pressed() -> void:
	var selected_item := section_tree.get_selected()
	if selected_item == null:
		return
	var section_id = selected_item.get_metadata(0)
	if section_id == null:
		return
	_open_section_thread(section_id)

## セクションの掲示板スレッドを開く。探索者管理パネルの「このセクションのログを見る」ボタンと、
## マップ上でセクション枠をダブルクリックした場合の両方から使う共通処理。
func _open_section_thread(section_id: String) -> void:
	_open_board_log(section_id)

func _on_upgrade_facility_pressed() -> void:
	Economy.upgrade_facility()
	_refresh_funds()
	_refresh_facility_button()

func _on_next_month_pressed() -> void:
	TimeSystem.confirm_and_resume()
	_set_next_month_shown(false)

## 月末の集計待ちの間だけ、今日・今月のバーの位置に「次の月へ」ボタンを出す(バーは見えなくするだけで、
## 場所は取ったまま。メニューの高さを変えないため)。
func _set_next_month_shown(shown: bool) -> void:
	next_month_button.visible = shown
	time_bars_box.modulate.a = 0.0 if shown else 1.0

func _on_speed_button_pressed(speed: float) -> void:
	TimeSystem.set_speed(speed)

func _on_speed_changed(multiplier: float) -> void:
	if speed_buttons.has(multiplier):
		speed_buttons[multiplier].button_pressed = true

func _on_day_advanced(_day: int) -> void:
	_follow_parties_to_new_area() # 再描画の前に、表示するエリアを決める
	_refresh_map()
	_refresh_roster()
	_refresh_npc_detail()
	_refresh_party_roster()
	_refresh_party_detail() # 探索者パネルと同様、パーティパネルを開いたまま倍速で進めても情報が古くならないようにする
	_refresh_funds() # セクション攻略の一時金は月末を待たずその日のうちに入るため、日次でも反映する
	SaveSystem.autosave()

func _on_month_ended(_month: int) -> void:
	_set_next_month_shown(true)
	_refresh_funds() # 月次収入(exploration.gdのEconomy.earn())はここで確定するので反映する

func _refresh_all() -> void:
	if WorldSchemaDb.active_version_id != _built_world_version:
		_rebuild_area_nav() # 別のシナリオ(世界)へ切り替わった: エリア選択バーとマップを作り直す
		_seed_demo_world()
	_refresh_funds()
	_refresh_candidates()
	_refresh_roster()
	_refresh_map()
	_refresh_npc_detail()
	_refresh_party_roster()
	_refresh_party_detail()
	_refresh_facility_button()
	_on_speed_changed(TimeSystem.speed_multiplier) # ロード直後、実際の倍速にボタンの押下表示を合わせる
	# next_month_buttonは元々month_endedシグナル(その場で月末になった瞬間)でのみ表示していたため、
	# 「一時停止した状態のままセーブ→再起動」すると、is_paused=trueなのにボタンだけ非表示で
	# 再開する手段が無くなってしまう不具合があった。ロード直後の実状態にも合わせて同期する。
	_set_next_month_shown(TimeSystem.is_paused)

func _refresh_facility_button() -> void:
	var cost := Economy.facility_upgrade_cost()
	var affordable := Economy.can_afford(cost)
	facility_info_label.text = "雇用上限 +%d\nコスト: %d%s" % [Economy.EMPLOY_CAP_STEP, cost, "" if affordable else "(資金が足りません)"]
	# 訓練ボタンと同じ理由(資金が足りない間は押せなくする)。押しても何も起きない状態を残さない。
	facility_button.disabled = not affordable

func _refresh_funds() -> void:
	funds_label.text = "資金: %d / 雇用上限: %d" % [Economy.funds, Economy.employ_cap]
	# 資金に応じて押せる/押せないが変わるボタンも、ここで一緒に更新する(月末の収入・雇用・購入などで変わるため)
	if facility_button != null and facility_info_label != null:
		_refresh_facility_button()
	_refresh_train_buttons()

## タイムバーの1行: 左に見出しの文字、右にバー。見出しの文字を返す(_refresh_time_barsが書き換える)。
func _add_time_bar_row(parent: Control, bar: TimeBar, bar_height: float) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var caption := Label.new()
	caption.add_theme_font_size_override("font_size", 11)
	caption.modulate = Color(1, 1, 1, 0.75)
	caption.custom_minimum_size = Vector2(62, 0)
	row.add_child(caption)
	bar.custom_minimum_size = Vector2(0, bar_height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return caption

const TIME_BAR_STRIPE_SPEED := 100.0 # この倍速以上では、1日が0.5秒以下で読めないので、今日のバーを流れる縞にする
const TIME_BAR_DAY_COLOR := Color(0.35, 0.6, 0.95)
const TIME_BAR_MONTH_COLOR := Color(0.9, 0.7, 0.3)
const TIME_BAR_PAUSED_COLOR := Color(0.95, 0.55, 0.2) # 月末の集計待ち
const TIME_BAR_HELD_COLOR := Color(0.6, 0.6, 0.66) # イベント会話の表示中(時間が止まっている)

## 今日・今月のバー。通常は進みの割合、月末の集計待ちは橙の満タン、会話中は灰色で止め、高速(100x以上)の間、今日は縞が流れる。
func _refresh_time_bars() -> void:
	var paused: bool = TimeSystem.is_paused
	var held: bool = TimeSystem.dialogue_hold and not paused
	var fast: bool = TimeSystem.speed_multiplier >= TIME_BAR_STRIPE_SPEED
	day_bar.striped = fast and not paused and not held
	day_bar.fraction = 1.0 if paused else TimeSystem.day_progress()
	month_bar.fraction = TimeSystem.month_progress()
	day_bar.fill_color = TIME_BAR_PAUSED_COLOR if paused else (TIME_BAR_HELD_COLOR if held else TIME_BAR_DAY_COLOR)
	month_bar.fill_color = TIME_BAR_PAUSED_COLOR if paused else (TIME_BAR_HELD_COLOR if held else TIME_BAR_MONTH_COLOR)
	day_caption.text = "会話中" if held else "今日"
	var day_of_month: int = TimeSystem.DAYS_PER_MONTH if paused else TimeSystem.current_day_of_month()
	month_caption.text = "今月 %d/%d" % [day_of_month, TimeSystem.DAYS_PER_MONTH]

func _refresh_time_label() -> void:
	_refresh_time_bars()
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
	_sync_roster_filter_controls()
	var roster_group := ButtonGroup.new() # 作り直すたびに新しいグループにして排他選択させる
	var all_npcs: Array = Npcs.get_roster()
	var shown: Array = RosterQuery.query(all_npcs, _roster_sort_key, _roster_sort_descending, _roster_bloodline, _roster_job)
	for npc in shown:
		var card := _create_roster_card(npc, roster_group)
		roster_grid.add_child(card)
		if npc["id"] == _selected_npc_id:
			card.button_pressed = true
	if shown.is_empty() and not all_npcs.is_empty():
		var empty_label := Label.new()
		empty_label.text = "条件に合う探索者がいません"
		roster_grid.add_child(empty_label)
	roster_count_label.text = "全%d人" % all_npcs.size() if shown.size() == all_npcs.size() else "%d人中 %d人を表示" % [all_npcs.size(), shown.size()]

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

## 探索者個人には状態を持たせていない(所属パーティの状態、design.md 4.7節)。未所属ならIDLE扱い。
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
## 差し替え、探索者ごとの画像を表示する想定)。カード全体をtoggle_mode付きButtonにして、
## どこをクリックしてもその探索者の詳細ビューに切り替わるようにする(中の子要素は
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
	card.custom_minimum_size = Vector2(CARD_WIDTH, ROSTER_PORTRAIT_SIZE + 74) # 名前・状態の行(56)+総合戦力の行(18)
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

	# 総合戦力(装備・スキルなどを合わせたもの)。スキルのLvで並べている時は、そのLvも添える(RosterQuery.card_stat_text)。
	var stat_label := Label.new()
	stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_label.text = RosterQuery.card_stat_text(npc, _roster_sort_key)
	stat_label.add_theme_font_size_override("font_size", 11)
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_label.clip_text = true
	stat_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stat_label.modulate = Color(1, 1, 1, 0.85)
	vbox.add_child(stat_label)

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
