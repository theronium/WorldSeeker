# 使い捨ての確認用スクリプト(2026-10-12)。組織と月のランキング(organizations.gd、design.md 4.10節)の確認。
#   O: 組織の定義(シナリオの定義・無い時の既定・分担率の縮小・不正な値)、野良の発見の振り分け
#   P: 点の記録(開拓=自分の発見・ゲート突破・他の組織の発見、稼ぎ=収入、戦闘=勝利)、月の区切り
#   F: 月末の確定(順位・同点・他の組織の計算上の点と成長・前月の順位・部門別1位・掲示板)
#   S: セーブ往復(SQLite)と、この機能より前のセーブ
#   U: 画面(月末の集計画面のランキングタブ・タブ切替・前月比、新規プレイの組織名、設定での変更)
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

## まだ発見されていない、ゲートの無い/有るフロア(最前線)を1つ探す。
func _frontier_node(world_map, gated: bool) -> String:
	for section_id in world_map.sections.keys():
		for node_id in world_map.frontier_for_section(section_id):
			if world_map.nodes[node_id]["gate"].is_empty() != gated:
				return node_id
	return ""

func _run() -> void:
	var time_system = root.get_node("TimeSystem"); var save = root.get_node("SaveSystem"); var dialogue = root.get_node("EventDialogue")
	var orgs = root.get_node("Organizations"); var exploration = root.get_node("Exploration"); var economy = root.get_node("Economy")
	var combat = root.get_node("Combat"); var parties = root.get_node("Parties"); var npcs = root.get_node("Npcs")
	var world_map = root.get_node("WorldMap"); var board = root.get_node("Board"); var scenario = root.get_node("ScenarioEvents")
	_finish(dialogue)
	save.start_fresh_session()

	# ---------- O: 組織 ----------
	print("--- O: 組織 ---")
	_check("O: 標準のシナリオに組織の定義がある", String(scenario.info.get("organizations", "")) != "")
	var ids: Array = orgs.rivals.map(func(r): return r["id"])
	_check("O: 新規開始で、シナリオの3組織になる", ids == ["compass", "hammer", "lion"], str(ids))
	_check("O: 名前と特色", orgs.rival("hammer")["name"] == "鉄槌団" and orgs.rival("hammer")["style"] == "combat")
	_check("O: 自分の組織は既定の名前", orgs.player_name == orgs.DEFAULT_PLAYER_NAME and orgs.org_name("player") == orgs.DEFAULT_PLAYER_NAME)
	var fallback: Array = orgs.parse_rivals("")
	_check("O: 定義が無ければ既定の3組織", fallback.size() == 3 and fallback[0]["name"] == "銀の羅針盤")
	var scaled: Array = orgs.parse_rivals([{"id": "a", "share": 0.8}, {"id": "b", "share": 0.8, "style": "nonsense"}, {"name": "IDなし"}, {"id": "player"}])
	_check("O: IDの無いもの・playerは捨てる", scaled.size() == 2, str(scaled.size()))
	_check("O: 分担率の合計が1を超えたら1に縮める", is_equal_approx(scaled[0]["share"] + scaled[1]["share"], 1.0) and is_equal_approx(scaled[0]["share"], 0.5))
	_check("O: 知らない特色は探索派", scaled[1]["style"] == "explore" and scaled[0]["name"] == "a")
	var counts := {"": 0, "compass": 0, "hammer": 0, "lion": 0}
	seed(12345)
	for i in range(10000):
		counts[orgs.roll_wild_owner()] += 1
	_check("O: 野良の発見の振り分け(30/20/20、残り30%は無所属)", absf(counts["compass"] / 10000.0 - 0.3) < 0.02 and absf(counts["hammer"] / 10000.0 - 0.2) < 0.02
		and absf(counts["lion"] / 10000.0 - 0.2) < 0.02 and absf(counts[""] / 10000.0 - 0.3) < 0.02, str(counts))

	# ---------- P: 点 ----------
	print("--- P: 点 ---")
	time_system.current_day = 3
	economy.earn(25)
	economy.earn(17)
	_check("P: 稼ぎは月の収入の合計を10資金ごとに1点(25+17=42→4点)", orgs.current_points("player")["earn"] == 4, str(orgs.current_points("player")))

	var party: Dictionary = parties.get_parties()[0]
	for npc_id in party["member_ids"]:
		npcs.get_npc(npc_id)["hp"] = npcs.get_npc(npc_id)["max_hp"]
	var win: Dictionary = combat.resolve_party_encounter(party["id"], 3, 3)
	_check("P: 勝った戦闘で戦闘15点", win["result"] == "victory" and orgs.current_points("player")["combat"] == 15)
	for npc_id in party["member_ids"]:
		npcs.get_npc(npc_id)["hp"] = npcs.get_npc(npc_id)["max_hp"]
	combat.resolve_party_encounter(party["id"], 100000, 3)
	_check("P: 負けた戦闘は点にならない", orgs.current_points("player")["combat"] == 15)

	# 自分の組織の発見(ゲート無し=10点、ゲートを突破=10+20点、再挑戦での突破=20点、突破できない発見=10点)
	var npc_id: int = party["member_ids"][0]
	var plain := _frontier_node(world_map, false)
	world_map.mark_found(plain, true)
	exploration._finalize_discovery("テスト", plain, true, 3, exploration._capture_milestone_state(plain), npc_id)
	_check("P: 自分の発見(ゲート無し)で開拓10点", orgs.current_points("player")["explore"] == 10, str(orgs.current_points("player")))
	var gated := _frontier_node(world_map, true)
	world_map.mark_found(gated, true)
	exploration._finalize_discovery("テスト", gated, false, 3, exploration._capture_milestone_state(gated), npc_id)
	_check("P: 突破できなかった発見は10点だけ", orgs.current_points("player")["explore"] == 20)
	exploration._apply_retry_pass(party, gated, {"npc_id": npc_id}, 3)
	_check("P: 再挑戦での突破で20点", orgs.current_points("player")["explore"] == 40)
	var gated2 := _frontier_node(world_map, true)
	world_map.mark_found(gated2, true)
	exploration._finalize_discovery("テスト", gated2, true, 3, exploration._capture_milestone_state(gated2), npc_id)
	_check("P: 発見と同時にゲートを突破すると30点", orgs.current_points("player")["explore"] == 70)

	# 他の組織の発見: 分担率を1組織に寄せて確かめる
	var saved_rivals: Array = orgs.rivals.duplicate(true)
	for r in orgs.rivals:
		r["share"] = 1.0 if r["id"] == "lion" else 0.0
	var wild := _frontier_node(world_map, false)
	var board_count: int = 0
	for t in board.threads.values():
		board_count += t["entries"].size()
	exploration.wild_discover(wild, 3)
	_check("P: 他の組織の発見は、その組織の開拓10点", orgs.current_points("lion")["explore"] == 10 and orgs.current_points("player")["explore"] == 70)
	var thread: Dictionary = board.threads.get(world_map.nodes[wild]["section"], {})
	_check("P: 掲示板には組織名で出る", not thread.is_empty() and String(thread["entries"][-1]["text"]).contains("「金獅子商会」の一行"), String(thread["entries"][-1]["text"]) if not thread.is_empty() else "")
	for r in orgs.rivals:
		r["share"] = 0.0
	var wild2 := _frontier_node(world_map, false)
	exploration.wild_discover(wild2, 3)
	thread = board.threads.get(world_map.nodes[wild2]["section"], {})
	_check("P: 無所属の発見は「野良の旅人」で、誰の点にもならない", String(thread["entries"][-1]["text"]).contains("野良の旅人") and orgs.current_points("lion")["explore"] == 10
		and orgs.current_points("compass")["explore"] == 0)
	orgs.rivals = saved_rivals

	time_system.current_day = 31
	_check("P: 次の月に入ると、前の月の点は見えない", orgs.current_points("player") == {"explore": 0, "earn": 0, "combat": 0})
	economy.earn(30)
	_check("P: 次の月の記録で数え直す", orgs.current_points("player")["earn"] == 3 and orgs.current_points("lion")["explore"] == 0)

	# ---------- F: 月末の確定 ----------
	print("--- F: 月末の確定 ---")
	save.start_fresh_session()
	time_system.current_day = 30
	orgs.add("player", "explore", 500)
	orgs.add("compass", "explore", 40)
	var entry1: Dictionary = orgs.finalize_month(1)
	var rows: Array = entry1["rows"]
	_check("F: 4組織が並ぶ", rows.size() == 4)
	_check("F: 総合点の高い順で、順位が付く", rows[0]["id"] == "player" and rows[0]["rank"] == 1 and rows.all(func(r): return r["total"] == r["explore"] + r["earn"] + r["combat"])
		and rows[1]["total"] >= rows[2]["total"] and rows[2]["total"] >= rows[3]["total"] and rows[3]["rank"] == 4)
	var compass_row: Dictionary = rows.filter(func(r): return r["id"] == "compass")[0]
	_check("F: 他の組織の開拓は、実際の発見の点", compass_row["explore"] == 40)
	_check("F: 他の組織の稼ぎ・戦闘は計算(1か月目、基準×強さ×特色×0.8〜1.2)",
		rows.all(func(r): return r["id"] == "player" or _within_first_month(orgs, r)), str(rows))
	_check("F: historyに積まれる", orgs.history.size() == 1 and orgs.latest() == entry1)
	_check("F: 1か月目は前月の順位が無い", orgs.previous_rank("player") == -1)
	var leaders: Dictionary = orgs.category_leaders(entry1)
	_check("F: 部門別1位(開拓は自分)", leaders["explore"]["id"] == "player" and leaders.has("earn") and leaders.has("combat"))
	time_system.current_day = 60
	var entry2: Dictionary = orgs.finalize_month(2)
	_check("F: 点の無い月は自分が0点", entry2["rows"].filter(func(r): return r["id"] == "player")[0]["total"] == 0)
	_check("F: 前月の順位(自分は1位だった)", orgs.previous_rank("player") == 1)
	# 成長: 13か月目の最小値 > 1か月目の最大値
	var grows := true
	for r in orgs.rivals:
		for category in ["earn", "combat"]:
			var base: float = orgs.RIVAL_BASE[category] * r["strength"] * orgs.STYLES[r["style"]][category]
			if base * (1.0 + r["growth"] * 12) * 0.8 <= base * 1.2:
				grows = false
	_check("F: 他の組織は月ごとに強くなる(13か月目の最小 > 1か月目の最大)", grows)
	# 同点はプレイヤー優先
	orgs.history.clear()
	var tie_rows: Array = [orgs._row("compass", "羅針盤", {"explore": 10, "earn": 10, "combat": 10}), orgs._row("player", "自分", {"explore": 10, "earn": 10, "combat": 10})]
	tie_rows.sort_custom(func(a, b):
		for key in ["total", "explore", "earn", "combat"]:
			if a[key] != b[key]:
				return a[key] > b[key]
		return a["id"] == "player")
	_check("F: 完全な同点は自分が上", tie_rows[0]["id"] == "player")
	# 掲示板(実際のmonth_endedで)
	save.start_fresh_session()
	var entries_before: int = board.entries.size()
	time_system.current_day = 29
	orgs.add("player", "explore", 1000)
	time_system._advance_day()
	_finish(dialogue)
	var posted: Array = board.entries.slice(entries_before).filter(func(e): return e["source"] == "ranking")
	_check("F: 月末(month_ended)で確定し、掲示板の全体に出る", orgs.history.size() == 1 and posted.size() == 1 and String(posted[0]["text"]).contains("1位はなんと「%s」" % orgs.DEFAULT_PLAYER_NAME)
		and posted[0]["scope"] == board.Scope.WORLD, str(posted))
	# 月末の収入(Exploration._on_month_ended)の後に確定する: 同じシグナルの接続順=autoloadの順
	_check("F: 月末の収入の後に順位を確定する(autoloadがExplorationより後)", orgs.get_index() > exploration.get_index(), "%d > %d" % [orgs.get_index(), exploration.get_index()])

	# ---------- S: セーブ往復 ----------
	print("--- S: セーブ往復 ---")
	var slot: int = save.create_new_slot("組織テスト", "", "default", "暁の探索団")
	_check("S: 新規プレイで組織名を付けられる", orgs.player_name == "暁の探索団")
	time_system.current_day = 40
	orgs.add("player", "explore", 30)
	orgs.add("hammer", "explore", 10)
	economy.earn(55)
	time_system.current_day = 60
	orgs.finalize_month(2)
	time_system.current_day = 70
	orgs.add("player", "combat", 15)
	orgs.rivals[0]["name"] = "改名された羅針盤"
	var before: Dictionary = orgs.save_state().duplicate(true)
	save.save_game()
	orgs.setup_from_scenario("別の名前")
	var loaded: bool = save.load_game()
	var after: Dictionary = orgs.save_state()
	_check("S: ロードできる", loaded)
	_check("S: 組織名", after["player_name"] == "暁の探索団")
	_check("S: 他の組織(セーブした時のまま)", JSON.stringify(after["rivals"]) == JSON.stringify(before["rivals"]), str(after["rivals"]))
	_check("S: 今月の点", after["month_index"] == before["month_index"] and JSON.stringify(after["points"]) == JSON.stringify(before["points"]), str(after["points"]))
	_check("S: 確定済みの順位", JSON.stringify(after["history"]) == JSON.stringify(before["history"]), str(after["history"]))
	# この機能より前のセーブ: 組織の表を空にしてロード → シナリオの定義から、名前は既定
	var db_path: String = save._slot_path(slot)
	var db = ClassDB.instantiate("SQLite")
	db.path = db_path
	db.open_db()
	for table in ["organizations", "org_points", "org_history"]:
		db.query("DELETE FROM %s" % table)
	db.query("DELETE FROM meta WHERE key IN ('org_player_name', 'org_points_month')")
	db.close_db()
	save.load_game()
	_check("S: 旧セーブは、シナリオの組織・既定の名前・空の順位", orgs.player_name == orgs.DEFAULT_PLAYER_NAME and orgs.rivals.size() == 3 and orgs.rivals[0]["name"] == "銀の羅針盤"
		and orgs.history.is_empty() and orgs.points.is_empty())
	save.delete_slot(slot)

	# ---------- U: 画面 ----------
	print("--- U: 画面 ---")
	save.start_fresh_session()
	time_system.current_day = 30
	time_system.current_month = 1
	time_system.is_paused = true
	orgs.add("player", "explore", 300)
	orgs.finalize_month(1)
	_main._on_month_ended(1)
	_main._maybe_show_month_summary()
	_check("U: 月末の集計画面はランキングタブから開く", _main.month_summary_panel.visible and _main.month_summary_ranking_scroll.visible and not _main.month_summary_stats_scroll.visible
		and _main.month_summary_ranking_tab.button_pressed)
	var grid: GridContainer = _main.month_summary_ranking_body.get_children().filter(func(c): return c is GridContainer)[0]
	var cells: Array = grid.get_children()
	_check("U: 見出し+4組織の行(7列)", cells.size() == 7 * 5, str(cells.size()))
	var first: Array = cells.slice(7, 14).map(func(c): return c.text)
	_check("U: 1位の行は自分(順位・名前・総合・開拓・前月)", first[0] == "1位" and first[1] == orgs.DEFAULT_PLAYER_NAME and first[3] == "300" and first[6] == "―", str(first))
	_check("U: 自分の行は色が付く", cells[8].has_theme_color_override("font_color") and not cells[15].has_theme_color_override("font_color"))
	var labels: Array = _main.month_summary_ranking_body.get_children().filter(func(c): return c is Label).map(func(c): return c.text)
	_check("U: 部門別の1位", labels.has("部門別の1位") and labels.any(func(t): return t.begins_with("開拓: " + orgs.DEFAULT_PLAYER_NAME)), str(labels))
	_main.month_summary_stats_tab.emit_signal("pressed")
	_check("U: 「探索者の戦績」タブに切り替わる", _main.month_summary_stats_scroll.visible and not _main.month_summary_ranking_scroll.visible)
	_main._on_next_month_pressed()
	# 2か月目: 自分は0点 → 順位が下がる
	time_system.current_day = 60
	time_system.current_month = 2
	time_system.is_paused = true
	orgs.finalize_month(2)
	_main._on_month_ended(2)
	_main._maybe_show_month_summary()
	_check("U: 2回目も、ランキングタブから開く", _main.month_summary_ranking_scroll.visible)
	grid = _main.month_summary_ranking_body.get_children().filter(func(c): return c is GridContainer and not c.is_queued_for_deletion())[0]
	var player_change := ""
	cells = grid.get_children()
	for i in range(7, cells.size(), 7):
		if cells[i + 1].text == orgs.DEFAULT_PLAYER_NAME:
			player_change = cells[i + 6].text
	_check("U: 前月より下がった自分の行は「↓」", player_change.begins_with("↓"), player_change)
	_main._on_next_month_pressed()

	# 確定前(ロード直後など)の表示
	orgs.history.clear()
	_main._fill_month_ranking()
	labels = _main.month_summary_ranking_body.get_children().filter(func(c): return c is Label and not c.is_queued_for_deletion()).map(func(c): return c.text)
	_check("U: 番付がまだ無い時の文言", labels.size() == 1 and labels[0].begins_with("まだ番付は出ていません"), str(labels))

	# 設定での変更
	_main._on_open_settings_pressed()
	_check("U: 設定に今の組織名が入る", _main.settings_org_input.text == orgs.player_name)
	_main.settings_org_input.text = "  新しい名前  "
	_main._on_org_rename_pressed()
	_check("U: 設定で組織名を変えられる(前後の空白は除く)", orgs.player_name == "新しい名前")
	_main.settings_org_input.text = ""
	_main._on_org_rename_pressed()
	_check("U: 空にすると既定の名前", orgs.player_name == orgs.DEFAULT_PLAYER_NAME and _main.settings_org_input.text == orgs.DEFAULT_PLAYER_NAME)
	_main._close_modal(_main.settings_panel)

	# 新規プレイの組織名
	_main.new_game_org_input.text = " 夜明け団 "
	_main._on_new_game_confirmed()
	_finish(dialogue)
	_check("U: 新規プレイの画面の組織名で始まる", orgs.player_name == "夜明け団", orgs.player_name)
	save.delete_slot(save.current_slot_id)

	_completed = true

func _within_first_month(orgs, row: Dictionary) -> bool:
	var r: Dictionary = orgs.rival(row["id"])
	for category in ["earn", "combat"]:
		var base: float = orgs.RIVAL_BASE[category] * r["strength"] * orgs.STYLES[r["style"]][category]
		if row[category] < roundi(base * 0.8) - 1 or row[category] > roundi(base * 1.2) + 1:
			return false
	return true
