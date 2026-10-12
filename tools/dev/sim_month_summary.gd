# 使い捨ての確認用スクリプト(2026-10-08)。月の集計(monthly_stats.gd、main.gdの_build_month_summary_ui)の確認。
#   L: 記録(戦闘の与ダメージ・被ダメージは実際に通った分だけ、「回復」スキルは担当者が実際に回復させた量、月の区切り、月末の日の戦闘)
#   S: セーブ往復(SQLite)
#   U: 画面(月末に開く、会話・戦闘画面の間は待つ、表の中身、最大値の色、「次の月へ」)
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

func _sum(stats, key: String) -> int:
	var total := 0
	for npc_id in stats.stats.keys():
		total += int(stats.stats[npc_id][key])
	return total

func _run() -> void:
	var time_system = root.get_node("TimeSystem"); var save = root.get_node("SaveSystem"); var dialogue = root.get_node("EventDialogue")
	var stats = root.get_node("MonthlyStats"); var combat = root.get_node("Combat"); var parties = root.get_node("Parties")
	var npcs = root.get_node("Npcs"); var exploration = root.get_node("Exploration"); var battle = root.get_node("BattleScreen")
	_finish(dialogue)
	save.start_fresh_session()
	var party: Dictionary = parties.get_parties()[0]
	var ids: Array = party["member_ids"]

	# ---------- L: 記録 ----------
	print("--- L: 記録 ---")
	_check("L: 新規開始では空", stats.stats.is_empty() and stats.month_index == -1)
	_check("L: 月の区切り(1〜30日目=0、31日目=1、0日目=0)",
		stats.month_of_day(1) == 0 and stats.month_of_day(30) == 0 and stats.month_of_day(31) == 1 and stats.month_of_day(0) == 0)

	time_system.current_day = 5
	for npc_id in ids:
		var npc: Dictionary = npcs.get_npc(npc_id)
		npc["hp"] = npc["max_hp"]
	var win: Dictionary = combat.resolve_party_encounter(party["id"], 3, 5)
	_check("L: 弱い敵に勝つ", win["result"] == "victory", win["result"])
	_check("L: 勝った戦闘の与ダメージ合計は、敵の戦闘力ちょうど(止めの超過分を含めない)",
		_sum(stats, "dealt") == int(win["enemy_start_power"]), "%d / %d" % [_sum(stats, "dealt"), win["enemy_start_power"]])
	var dealt_after_win := _sum(stats, "dealt")
	var taken_after_win := _sum(stats, "taken")

	# 負ける戦闘: 被ダメージはラウンドごとに、残りHPまでで切る
	for npc_id in ids:
		var npc: Dictionary = npcs.get_npc(npc_id)
		npc["hp"] = npc["max_hp"]
		npc["combat_policy"] = {"hp_threshold": -1.0e9, "action": npcs.CombatAction.USE_ITEM} # 閾値に届かない: アイテム回復も撤退もせず、力尽きるまで戦う
	var lose: Dictionary = combat.resolve_party_encounter(party["id"], 100000, 6)
	_check("L: 強い敵に負ける", lose["result"] == "defeat", lose["result"])
	var expected_taken := 0
	var expected_dealt := 0
	for entry in lose["trace"]:
		expected_taken += roundi(float(entry["hp_before"]) - maxf(float(entry["hp_after"]), 0.0))
		expected_dealt += int(entry["enemy_before"]) - maxi(int(entry["enemy_after"]), 0)
	_check("L: 負けた戦闘の被ダメージは、HP0で切った分", _sum(stats, "taken") - taken_after_win == expected_taken, "%d / %d" % [_sum(stats, "taken") - taken_after_win, expected_taken])
	_check("L: 力尽きた探索者の被ダメージは最大HPを超えない(アイテム回復なし)",
		ids.all(func(i): return int(stats.for_npc(i)["taken"]) <= roundi(float(npcs.get_npc(i)["max_hp"])) * 2), "勝った戦闘の分も含むので2倍まで")
	_check("L: 負けた戦闘の与ダメージ", _sum(stats, "dealt") - dealt_after_win == expected_dealt)

	# 「回復」スキル: 担当者に、実際に回復させた量が入る
	var healer_id: int = exploration._best_member_for_skill(party, SkillTypes.Skill.HEALING)
	var before_heal: int = int(stats.for_npc(healer_id)["healed"])
	var hp_sum_before := 0.0
	for npc_id in ids:
		var npc: Dictionary = npcs.get_npc(npc_id)
		npc["hp"] = maxf(1.0, float(npc["max_hp"]) - 3.0) # 1回の回復量より少ない不足 → 最大HPで切られる
		hp_sum_before += float(npc["hp"])
	exploration._apply_daily_healing(party)
	var hp_sum_after := 0.0
	for npc_id in ids:
		hp_sum_after += float(npcs.get_npc(npc_id)["hp"])
	var healed: int = int(stats.for_npc(healer_id)["healed"]) - before_heal
	_check("L: 担当者の回復量 = 実際に戻ったHPの合計(最大HPで切った分)", healed == roundi(hp_sum_after - hp_sum_before) and healed > 0, "%d / %s" % [healed, str(hp_sum_after - hp_sum_before)])
	_check("L: 担当者以外に回復量は付かない", ids.all(func(i): return i == healer_id or int(stats.for_npc(i)["healed"]) == 0))
	exploration._apply_daily_healing(party) # 全員満タン: 何も足さない
	_check("L: 満タンなら回復量は増えない", int(stats.for_npc(healer_id)["healed"]) - before_heal == healed)

	# 月末の日(30日目)の記録は、その月に入る。31日目に記録すると前の月の分は消える
	time_system.current_day = 30
	stats.add(ids[0], "dealt", 7)
	_check("L: 30日目の記録は、1か月目の分に足される", stats.month_index == 0 and int(stats.for_npc(ids[0])["dealt"]) > 7)
	time_system.current_day = 31
	_check("L: 次の月に入ると、前の月の記録は見えない(0)", int(stats.for_npc(ids[0])["dealt"]) == 0)
	stats.add(ids[1], "taken", 4)
	_check("L: 次の月に記録すると、前の月の分は捨てて数え直す", stats.month_index == 1 and stats.stats.size() == 1 and int(stats.for_npc(ids[1])["taken"]) == 4)
	stats.add(ids[1], "taken", 0)
	stats.add(ids[1], "taken", -3)
	_check("L: 0以下は足さない", int(stats.for_npc(ids[1])["taken"]) == 4)

	# ---------- S: セーブ往復 ----------
	print("--- S: セーブ往復 ---")
	var slot: int = save.create_new_slot("集計テスト")
	party = parties.get_parties()[0]
	ids = party["member_ids"]
	time_system.current_day = 45
	stats.add(ids[0], "dealt", 120)
	stats.add(ids[0], "taken", 33)
	stats.add(ids[2], "healed", 18)
	var saved: Dictionary = stats.stats.duplicate(true)
	save.save_game()
	stats.reset()
	var loaded: bool = save.load_game()
	_check("S: ロードできる", loaded)
	_check("S: 月と記録が戻る", stats.month_index == 1 and stats.stats == saved, "%d %s" % [stats.month_index, str(stats.stats)])
	save.start_fresh_session()
	_check("S: 新規プレイでは空", stats.stats.is_empty() and stats.month_index == -1)
	save.delete_slot(slot)

	# ---------- U: 画面 ----------
	print("--- U: 画面 ---")
	_finish(dialogue)
	save.start_fresh_session()
	party = parties.get_parties()[0]
	ids = party["member_ids"]
	time_system.current_day = 30
	time_system.current_month = 1
	time_system.is_paused = true
	stats.add(ids[0], "dealt", 250)
	stats.add(ids[1], "dealt", 90)
	stats.add(ids[1], "taken", 61)
	stats.add(ids[2], "healed", 40)
	var panel: PanelContainer = _main.month_summary_panel

	dialogue.is_active = true # 会話が開いている間は出さない
	_main._on_month_ended(1)
	_main._maybe_show_month_summary()
	_check("U: 会話の間は開かない", not panel.visible and _main._month_summary_pending)
	dialogue.is_active = false
	battle.is_active = true # 戦闘画面の間も出さない
	_main._maybe_show_month_summary()
	_check("U: 戦闘画面の間は開かない", not panel.visible)
	battle.is_active = false
	_main._maybe_show_month_summary()
	_check("U: 会話・戦闘画面が閉じたら開く", panel.visible and not _main._month_summary_pending)
	_check("U: 見出しは終わった月の暦", _main.month_summary_title.text == "0年1月の集計", _main.month_summary_title.text)

	var labels: Array = []
	for child in _main.month_summary_body.get_children():
		if child is Label:
			labels.append(child.text)
	_check("U: パーティ名の見出し", labels.has(party["name"]), str(labels))
	var grid: GridContainer = null
	for child in _main.month_summary_body.get_children():
		if child is GridContainer:
			grid = child
	var cells: Array = grid.get_children()
	_check("U: 表は 見出し行+メンバー数 の行", cells.size() == 4 * (1 + ids.size()), str(cells.size()))
	var row0: Array = cells.slice(4, 8).map(func(c): return c.text)
	var row1: Array = cells.slice(8, 12).map(func(c): return c.text)
	var row2: Array = cells.slice(12, 16).map(func(c): return c.text)
	_check("U: 1人目の行(与ダメージ250)", row0 == [npcs.get_npc(ids[0])["name"], "250", "0", "0"], str(row0))
	_check("U: 2人目の行(90/61/0)", row1 == [npcs.get_npc(ids[1])["name"], "90", "61", "0"], str(row1))
	_check("U: 3人目の行(回復40)", row2 == [npcs.get_npc(ids[2])["name"], "0", "0", "40"], str(row2))
	_check("U: 列ごとの最大値だけ色が付く", cells[5].has_theme_color_override("font_color") and not cells[9].has_theme_color_override("font_color")
		and cells[10].has_theme_color_override("font_color") and cells[15].has_theme_color_override("font_color")
		and not cells[6].has_theme_color_override("font_color"))

	# パーティを抜けた探索者の記録は「パーティ外」にまとめる
	var outsider: int = npcs.hire("外の人", {}, {})
	stats.add(outsider, "dealt", 5)
	_main._fill_month_summary()
	labels.clear()
	for child in _main.month_summary_body.get_children():
		if child is Label and not child.is_queued_for_deletion():
			labels.append(child.text)
	_check("U: パーティに居ない探索者の記録は「パーティ外」に出る", labels.has("パーティ外"), str(labels))

	_main._on_next_month_pressed()
	_check("U: 「次の月へ」で閉じて時間が動く", not panel.visible and not time_system.is_paused)

	_completed = true
