# 使い捨ての確認用スクリプト(2026-09-21)。ログウィンドウ(毎日の動き・行動ログ・掲示板をタブで切り替え、
# マップの右端に重ねる。2026-09-24に2枠のモーダルから変更)と、毎日の動き(DailyLog)の確認。
#   D: DailyLog(状態の判定・未割当は出さない・同じ日の記録し直し・90日の保持・まとめ表示の区間・リセット)
#   W: ログウィンドウ(メイン画面を組み立てて操作する。マップ右上のボタン・タブ・絞り込み・まとめて表示・掲示板のスレッド)
#   I: 探索との連携(日次の記録。会話が閉じて退避が反映された後に、その日の動きが記録し直される)
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
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

func _finish(dialogue) -> void:
	var guard := 0
	while dialogue.is_active and guard < 50:
		guard += 1
		dialogue.advance()

func _log_text() -> String:
	return _main.log_window._text.get_parsed_text()

func _select_source(key: String) -> void:
	_main.log_window._tab_buttons[key].button_pressed = true
	_main.log_window._tab_buttons[key].pressed.emit()

func _select_filter(value: Variant) -> void:
	var filter: OptionButton = _main.log_window._filter
	for i in filter.item_count:
		if filter.get_item_metadata(i) == value:
			filter.select(i)
			_main.log_window._on_filter_selected(i)

func _run() -> void:
	var save = root.get_node("SaveSystem"); var world_map = root.get_node("WorldMap"); var parties = root.get_node("Parties")
	var npcs = root.get_node("Npcs"); var dialogue = root.get_node("EventDialogue"); var exploration = root.get_node("Exploration")
	var daily = root.get_node("DailyLog"); var board = root.get_node("Board"); var action_log = root.get_node("ActionLog")
	_finish(dialogue)
	save.start_fresh_session()
	daily.reset()

	# ---------- D: DailyLog ----------
	print("--- D: DailyLog ---")
	var p1: Dictionary = parties.get_parties()[0]
	var first: String = world_map.first_section()
	var second: String = world_map.sections_in_area(world_map.areas.keys()[0])[1]
	_check("D: 前提: 初期パーティは未割当", int(p1["status"]) == parties.Status.IDLE)
	daily.record_day(1)
	_check("D: 未割当のパーティしかいない日は、記録しない", daily.day_count() == 0)

	parties.assign_section(p1["id"], first)
	daily.record_day(2)
	var day2: Array = daily.days_newest_first()
	_check("D: 担当を割り当てると、探索中として記録される", day2.size() == 1 and day2[0]["parties"][0]["kind"] == "explore", str(day2))
	_check("D: 文言: 「〜」を探索中", daily.describe(day2[0]["parties"][0], 2) == "「%s」を探索中" % world_map.sections[first]["name"], daily.describe(day2[0]["parties"][0], 2))

	# 未割当のパーティは混ざらない
	var extra_ids: Array = []
	for n in 2:
		extra_ids.append(npcs.hire("控え%d" % n, {"bloodline": "平民"}))
	var p2_id: int = parties.form_party(extra_ids, "控えパーティ")
	daily.record_day(2)
	_check("D: 同じ日を記録し直すと、その日の分を置き換える(日は増えない)", daily.day_count() == 1)
	_check("D: 未割当の控えパーティは出ない", daily.days_newest_first()[0]["parties"].size() == 1)

	# 回復中
	parties.retreat_and_recover(p1["id"], 3, 3) # 3日目から3日 → 6日目まで
	daily.record_day(3)
	var recover_entry: Dictionary = daily.days_newest_first()[0]["parties"][0]
	_check("D: 回復中: あと3日", recover_entry["kind"] == "recover" and daily.describe(recover_entry, 3) == "回復中(あと3日)", daily.describe(recover_entry, 3))
	_check("D: 回復中: 期限の日は「まもなく復帰」", daily.describe(recover_entry, 6) == "回復中(まもなく復帰)", daily.describe(recover_entry, 6))
	_check("D: まとめ表示用の文言(日数なし)", daily.describe(recover_entry) == "回復中")

	# 力を付けている(退避中): 別のセクションへ退避 / その場で待機
	parties.assign_section(p1["id"], first)
	parties.retreat_for_training(p1["id"], first, second, "cave")
	daily.record_day(4)
	var train_entry: Dictionary = daily.days_newest_first()[0]["parties"][0]
	_check("D: 力を付けている(退避中)", train_entry["kind"] == "train" and daily.describe(train_entry, 4).contains("力を付けている") and daily.describe(train_entry, 4).contains("目標"), daily.describe(train_entry, 4))
	parties.assign_section(p1["id"], second)
	parties.set_return(p1["id"], second, "cave")
	daily.record_day(5)
	var stay_entry: Dictionary = daily.days_newest_first()[0]["parties"][0]
	_check("D: その場で力を付けている", stay_entry["kind"] == "train" and daily.describe(stay_entry, 5).contains("その場で力を付けている"), daily.describe(stay_entry, 5))

	# 周回中
	parties.assign_section(p1["id"], first)
	for id in world_map.nodes_in_section(first):
		world_map.mark_passed(id, true)
	daily.record_day(6)
	var lap_entry: Dictionary = daily.days_newest_first()[0]["parties"][0]
	_check("D: 完全攻略済みのセクションは、周回中", lap_entry["kind"] == "lap" and daily.describe(lap_entry, 6).contains("周回中"), daily.describe(lap_entry, 6))

	# まとめ表示と絞り込み(控えパーティは未割当のまま)
	daily.reset()
	_check("D: リセットで空になる", daily.day_count() == 0 and daily.days_newest_first().is_empty())
	parties.assign_section(p1["id"], second)
	world_map.nodes[world_map.nodes_in_section(second)[0]]["passed"] = false # 第2セクションは未攻略に戻す
	for id in world_map.nodes_in_section(first):
		world_map.nodes[id]["passed"] = false
	var p1_states := ["explore", "explore", "explore", "recover", "recover", "explore", "explore"] # 日1〜7
	for i in p1_states.size():
		var day: int = i + 1
		if p1_states[i] == "recover":
			parties.retreat_and_recover(p1["id"], day, 2)
		else:
			parties.assign_section(p1["id"], second)
		daily.record_day(day)
	var spans: Array = daily.spans_newest_first(p1["id"])
	_check("D: まとめ: 探索(1〜3)・回復(4〜5)・探索(6〜7)の3区間、新しい順", spans.size() == 3 and spans[0]["from_day"] == 6 and spans[0]["to_day"] == 7 and spans[1]["from_day"] == 4 and spans[2]["from_day"] == 1 and spans[2]["to_day"] == 3, str(spans.map(func(s): return "%d-%d" % [s["from_day"], s["to_day"]])))
	_check("D: まとめの文言: 日数を添える", daily.describe_span(spans[2]).ends_with("を探索中(3日間)") and daily.describe_span(spans[1]) == "回復中(2日間)", "%s / %s" % [daily.describe_span(spans[2]), daily.describe_span(spans[1])])
	_check("D: パーティ絞り込み: 控えパーティは記録されていない(未割当)", daily.spans_newest_first(p2_id).is_empty() and daily.days_newest_first(p2_id).is_empty())
	_check("D: 日ごと: 7日分、新しい順", daily.days_newest_first().size() == 7 and daily.days_newest_first()[0]["day"] == 7 and daily.days_newest_first()[6]["day"] == 1)
	# 日が飛ぶと、同じ状態でも区間が分かれる
	daily.reset()
	parties.assign_section(p1["id"], second)
	for day in [1, 2, 4, 5]:
		daily.record_day(day)
	var gap_spans: Array = daily.spans_newest_first(p1["id"])
	_check("D: 日が連続しなければ、別の区間(1〜2と4〜5)", gap_spans.size() == 2 and gap_spans[0]["from_day"] == 4 and gap_spans[1]["to_day"] == 2)
	# 保持: 90日
	daily.reset()
	for day in range(1, 121):
		daily.record_day(day)
	var retained: Array = daily.days_newest_first()
	_check("D: 直近90日分だけ保持する(31〜120日)", retained.size() == 90 and retained[0]["day"] == 120 and retained[89]["day"] == 31, "%d件 %d〜%d" % [retained.size(), retained.back()["day"], retained[0]["day"]])

	# ---------- W: ログウィンドウ ----------
	print("--- W: ログウィンドウ ---")
	var button_texts: Array = []
	for child in _main.left_menu.get_children():
		if child is Button:
			button_texts.append(child.text)
	_check("W: 左メニューに「ログ」「掲示板」のボタンは無い(マップ右上へ移した)", not button_texts.any(func(t): return String(t).contains("ログ") or String(t).contains("掲示板")), str(button_texts))
	var window = _main.log_window
	var toggle: Button = _main.log_toggle_button
	_check("W: マップ右上に「ログ」ボタン", toggle != null and toggle.get_parent() == window.get_parent() and toggle.text.contains("ログ"))
	_check("W: タブは3つ(毎日の動き・行動ログ・掲示板)", window._tab_buttons.size() == 3 and window._tab_buttons["events"].text == "行動ログ")
	_check("W: ログウィンドウはモーダルではない(マップの領域の子)", window.get_parent() == toggle.get_parent() and not _main.modal_blocker.visible)
	# 毎日の動き
	daily.reset()
	parties.assign_section(p1["id"], second)
	for day in range(1, 5):
		daily.record_day(day)
	toggle.button_pressed = true
	_check("W: ボタンで窓が開き、ボタンは押された状態", window.visible and toggle.button_pressed)
	_select_source("daily")
	var text0: String = _log_text()
	_check("W: 毎日の動き: 日ごと(新しい日が上)", text0.find("Day 4") >= 0 and text0.find("Day 4") < text0.find("Day 3") and text0.contains("初期パーティ: 「"), text0.substr(0, 80))
	window._merge.button_pressed = true
	_check("W: まとめて表示: 「Day 1〜4」1行(4日間)", _log_text().contains("Day 1〜4") and _log_text().contains("(4日間)"), _log_text())
	window._merge.button_pressed = false
	# 絞り込み(パーティ)
	_check("W: 絞り込みの選択肢: 全パーティ+パーティ数", window._filter.item_count == 1 + parties.get_parties().size(), str(window._filter.item_count))
	_select_filter(p2_id)
	_check("W: 未割当のパーティで絞ると、記録なし", _log_text().contains("まだ動きの記録がありません"))
	_select_filter(-1)
	# 掲示板・行動ログ
	board.reset()
	board.post(7, "掲示板の全体の書き込み", board.Importance.MAJOR, "test")
	board.post_to_thread("village_area", "始まりの村周辺", 8, "スレッドの書き込み", board.Importance.MINOR, "test")
	board.post(9, "新しい書き込み", board.Importance.MAJOR, "test")
	action_log.record(6, "test_event", "イベントの記録A", npcs.roster.keys()[0])
	action_log.record(7, "test_event", "イベントの記録B", npcs.roster.keys()[1])
	save.save_game() # 行動ログはDBから読むので、保存して反映する(隔離APPDATA)
	_select_source("events")
	var events_text := _log_text()
	_check("W: 行動ログ: 新しい順(B→A)", events_text.contains("イベントの記録B") and events_text.find("イベントの記録B") < events_text.find("イベントの記録A"), events_text.substr(0, 90))
	_select_filter(npcs.roster.keys()[0])
	_check("W: 行動ログ: 探索者で絞る", _log_text().contains("イベントの記録A") and not _log_text().contains("イベントの記録B"))
	_select_source("board")
	var board_text := _log_text()
	_check("W: 掲示板: 全体フィードを新しい順(9→7)", board_text.contains("新しい書き込み") and board_text.find("新しい書き込み") < board_text.find("掲示板の全体の書き込み") and not board_text.contains("スレッドの書き込み"), board_text)
	_select_filter("village_area")
	_check("W: 掲示板: スレッドで絞る", _log_text().contains("スレッドの書き込み") and not _log_text().contains("新しい書き込み"), _log_text())
	# タブを切り替えると、前に選んだ絞り込みを覚えている
	_select_source("events")
	_check("W: 行動ログへ戻ると、探索者の絞り込みが残っている", _log_text().contains("イベントの記録A") and not _log_text().contains("イベントの記録B"))
	_select_filter(-1)
	_select_source("board")
	_check("W: 掲示板へ戻ると、スレッドの選択が残っている", window._filters["board"] == "village_area" and _log_text().contains("スレッドの書き込み"))
	# ✕で閉じると、ボタンの押された状態も戻る
	window.close_requested.emit()
	_check("W: ✕で閉じると窓が隠れ、ボタンも戻る", not window.visible and not toggle.button_pressed)
	# セクションのスレッドを開く(割り当て画面の「ログ」・マップのダブルクリックの共通処理)
	_select_source("events")
	_main._open_section_thread("village_area")
	_check("W: セクションのスレッドを開くと、掲示板タブがそのスレッドになる", window.visible and toggle.button_pressed and window._source == "board" and window._tab_buttons["board"].button_pressed and _log_text().contains("スレッドの書き込み"), _log_text())
	window.close_requested.emit()
	# ポップアップ(割り当て画面など)から開くと、ポップアップは閉じる
	_main._open_modal(_main.section_assign_panel)
	_main._open_section_thread("village_area")
	_check("W: ポップアップから開くと、ポップアップは閉じる", window.visible and not _main.section_assign_panel.visible and not _main.modal_blocker.visible)
	# 戻るキー(Android)で閉じる
	_main._on_go_back_requested()
	_check("W: 戻るキーで閉じる", not window.visible and not toggle.button_pressed)
	# 自動更新(日が進むと、開いている間だけ更新される)
	toggle.button_pressed = true
	_select_source("daily")
	daily.record_day(5)
	window._dirty = true
	window._on_refresh_timer()
	_check("W: 日が進んだ印があると、自動更新される", _log_text().contains("Day 5"))
	toggle.button_pressed = false
	daily.record_day(6)
	window._dirty = true
	window._on_refresh_timer()
	_check("W: 閉じている間は更新しない(印は立ったまま)", not _log_text().contains("Day 6") and window._dirty)

	# ---------- I: 探索との連携 ----------
	print("--- I: 探索との連携 ---")
	save.start_fresh_session()
	daily.reset()
	var party: Dictionary = parties.get_parties()[0]
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	for id in world_map.nodes_in_section(world_map.first_section()):
		world_map.mark_passed(id, true)
	world_map.mark_passed("cave", true)
	world_map.mark_passed("locked_vault", true)
	parties.assign_section(party["id"], "old_cave_dungeon")
	var opened_day := -1
	for day in range(1, 601):
		exploration._on_day_advanced(day)
		if dialogue.is_active:
			opened_day = day
			break
	_check("I: 日次の処理で、毎日の動きが記録される", opened_day > 0 and daily.day_count() == opened_day, "%d日目で会話、%d日分" % [opened_day, daily.day_count()])
	_check("I: 会話が開いている間は、その日の動きは「探索中」", daily.days_newest_first()[0]["parties"][0]["kind"] == "explore", str(daily.days_newest_first()[0]["parties"][0]["kind"]))
	_finish(dialogue)
	# 戦闘ゲートの会話は、前置き→戦闘画面→結末の会話の順(2026-09-23)。戦闘画面(設定ON)を閉じ、結末の会話も読み切る
	var battle_screen = root.get_node("BattleScreen")
	for _i in 5:
		if battle_screen.is_active:
			battle_screen.close()
		_finish(dialogue)
	var after: Dictionary = daily.days_newest_first()[0]
	_check("I: 会話が閉じて退避が反映された後は、その日の動きが「力を付けている」に記録し直される(日は増えない)", after["day"] == opened_day and after["parties"][0]["kind"] == "train" and daily.day_count() == opened_day, "%s %d日分" % [after["parties"][0]["kind"], daily.day_count()])

	# ---------- S: セーブ/ロード(毎日の動きはセーブしない) ----------
	print("--- S: セーブ/ロード ---")
	var before: int = daily.day_count()
	save.save_game()
	save.load_game()
	_check("S: ロード直後は、毎日の動きが空から(セーブに含まれない)", before > 0 and daily.day_count() == 0, "%d日分 → %d日分" % [before, daily.day_count()])
	save.start_fresh_session()
	daily.record_day(1)
	parties.assign_section(parties.get_parties()[0]["id"], world_map.first_section())
	daily.record_day(2)
	save.start_fresh_session()
	_check("S: 新規プレイ(start_fresh_session)でも空から", daily.day_count() == 0)
	_completed = true
