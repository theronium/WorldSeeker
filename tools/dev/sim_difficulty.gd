# 使い捨ての確認用スクリプト(2026-09-22)。パーティごとの難易度モード(Easy/Normal/Hard。godot/scripts/difficulty.gd、design.md 4.9節)の確認。
#   ロジック: 計算式・パーティの初期値と切替とセーブ往復(メモリ上と実際のSQLite)・戦闘の勝てる上限が Easy>Normal>Hard・
#             スキルゲートの必要Lvの加減・月次収入/周回収入/攻略報酬/予測の倍率(攻略報酬の初回ボーナスは固定)
#   画面:     メイン画面を組み立てて、マップのパーティアイコンの頭文字バッジ(E/N/H と色)・ツールチップ・パーティ一覧のカード・
#             パーティ詳細の切替ボタン(押すと切り替わり、バッジと説明が変わる)
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

func _reset_hp(party: Dictionary) -> void:
	var npcs = root.get_node("Npcs")
	for id in party["member_ids"]:
		var npc = npcs.get_npc(id)
		npc["hp"] = npc["max_hp"]
	party["status"] = 1 # Parties.Status.EXPLORING
	party["recovering_until_day"] = -1

func _run() -> void:
	var npcs = root.get_node("Npcs"); var parties = root.get_node("Parties"); var world_map = root.get_node("WorldMap")
	var combat = root.get_node("Combat"); var exploration = root.get_node("Exploration"); var economy = root.get_node("Economy")
	var save = root.get_node("SaveSystem"); var dialogue = root.get_node("EventDialogue")
	var EASY: int = Difficulty.Mode.EASY; var NORMAL: int = Difficulty.Mode.NORMAL; var HARD: int = Difficulty.Mode.HARD
	_finish(dialogue)
	save.start_fresh_session()

	print("\n=== 計算式(difficulty.gd) ===")
	_check("敵の戦闘力 660 → 528 / 660 / 825", [Difficulty.enemy_power(660, EASY), Difficulty.enemy_power(660, NORMAL), Difficulty.enemy_power(660, HARD)] == [528, 660, 825])
	_check("敵の戦闘力 0 は変えない・1 でも最低1", Difficulty.enemy_power(0, HARD) == 0 and Difficulty.enemy_power(1, EASY) == 1)
	_check("必要Lv 3 → 2 / 3 / 4、必要Lv 0 のEasyは0のまま(下限0)", [Difficulty.skill_min_level(3, EASY), Difficulty.skill_min_level(3, NORMAL), Difficulty.skill_min_level(3, HARD)] == [2, 3, 4] and Difficulty.skill_min_level(0, EASY) == 0)
	_check("報酬 100 → 75 / 100 / 150", [Difficulty.reward(100, EASY), Difficulty.reward(100, NORMAL), Difficulty.reward(100, HARD)] == [75, 100, 150])
	_check("範囲外・キー無しはNormal", Difficulty.normalize(-1) == NORMAL and Difficulty.normalize(3) == NORMAL and Difficulty.of_party({}) == NORMAL and Difficulty.of_party({"difficulty": 99}) == NORMAL)
	_check("表示名・頭文字", Difficulty.mode_name(EASY) == "Easy" and Difficulty.mode_name(HARD) == "Hard" and Difficulty.initial(EASY) == "E" and Difficulty.initial(NORMAL) == "N" and Difficulty.initial(HARD) == "H")
	print("  説明: ", Difficulty.describe(EASY), " | ", Difficulty.describe(NORMAL), " | ", Difficulty.describe(HARD))
	_check("説明の文言(Easy)", Difficulty.describe(EASY) == "敵の戦闘力×0.8 / スキルゲートの必要Lv-1 / 収入・報酬×0.75", Difficulty.describe(EASY))
	_check("説明の文言(Normal)", Difficulty.describe(NORMAL) == "敵の戦闘力×1 / スキルゲートの必要Lv±0 / 収入・報酬×1", Difficulty.describe(NORMAL))
	_check("説明の文言(Hard)", Difficulty.describe(HARD) == "敵の戦闘力×1.25 / スキルゲートの必要Lv+1 / 収入・報酬×1.5", Difficulty.describe(HARD))

	print("\n=== パーティの難易度(初期値・切替・セーブ) ===")
	var party: Dictionary = parties.get_parties()[0]
	var pid: int = party["id"]
	_check("初期パーティの難易度はNormal", parties.difficulty(pid) == NORMAL and party["difficulty"] == NORMAL)
	_check("範囲外への切替は断る・存在しないパーティはNormal", not parties.set_difficulty(pid, 5) and not parties.set_difficulty(999, HARD) and parties.difficulty(pid) == NORMAL and parties.difficulty(999) == NORMAL)
	_check("Hardへ切替", parties.set_difficulty(pid, HARD) and parties.difficulty(pid) == HARD)
	var snapshot: Dictionary = parties.save_state().duplicate(true)
	parties.load_state(snapshot)
	_check("save_state→load_stateで保たれる", parties.difficulty(pid) == HARD)
	var old_form: Dictionary = snapshot.duplicate(true)
	old_form["parties"][pid].erase("difficulty")
	parties.load_state(old_form)
	_check("旧セーブ(キーが無い)はNormalで読む", parties.difficulty(pid) == NORMAL)

	# 実際のSQLiteのセーブで往復(隔離したAPPDATAでのみ実行する)
	parties.set_difficulty(pid, EASY)
	var slot: int = save.create_new_slot("難易度テスト")
	parties.set_difficulty(parties.get_parties()[0]["id"], HARD)
	save.save_game()
	parties.reset()
	var loaded: bool = save.load_game()
	var restored: Dictionary = parties.get_parties()[0]
	_check("SQLiteのセーブ→ロードで難易度が戻る", loaded and Difficulty.of_party(restored) == HARD, "loaded=%s difficulty=%s" % [loaded, restored.get("difficulty")])
	save.delete_slot(slot)
	save.start_fresh_session()
	party = parties.get_parties()[0]
	pid = party["id"]
	_finish(dialogue)

	print("\n=== 戦闘: 勝てる敵の上限が Easy > Normal > Hard ===")
	var top_power := 0
	for id in party["member_ids"]:
		top_power = maxi(top_power, npcs.power(id))
	print("  パーティ内の最強メンバーの戦力=%d" % top_power)
	var limits := {}
	for mode in [EASY, NORMAL, HARD]:
		parties.set_difficulty(pid, mode)
		var best := 0
		for enemy in range(10, 1200, 5):
			if combat.predict_party_result(pid, enemy, true) == "victory":
				best = enemy
		limits[mode] = best
	print("  満タンで勝てる敵の戦闘力(基礎値)の上限: Easy=%d Normal=%d Hard=%d" % [limits[EASY], limits[NORMAL], limits[HARD]])
	_check("上限が Easy > Normal > Hard", limits[EASY] > limits[NORMAL] and limits[NORMAL] > limits[HARD])
	_check("上限の比が、倍率(0.8/1.25)におおよそ合う(±10%)", absf(float(limits[NORMAL]) / limits[EASY] - 0.8) < 0.1 and absf(float(limits[HARD]) / limits[NORMAL] - 0.8) < 0.1, "N/E=%.2f H/N=%.2f" % [float(limits[NORMAL]) / limits[EASY], float(limits[HARD]) / limits[NORMAL]])
	# Hard: Normalでは勝てる敵(=Hardの上限のすぐ上)には勝てない。実際の戦闘(resolve)は戦闘力の経験値が入って
	# 戦力が変わるので、上限を測った直後の、戦う前に確かめる
	var above_hard: int = limits[HARD] + 5
	parties.set_difficulty(pid, HARD)
	_check("Hardでは、上限のすぐ上の敵に勝てない(予測)。Normalなら勝てる", limits[HARD] < limits[NORMAL] and combat.predict_party_result(pid, above_hard, true) != "victory")
	parties.set_difficulty(pid, NORMAL)
	_check("同じ敵に、Normalなら勝てる(予測)", combat.predict_party_result(pid, above_hard, true) == "victory")
	_check("effective_enemy_power(Hard, 400) = 500", (func(): parties.set_difficulty(pid, HARD); return combat.effective_enemy_power(pid, 400) == 500).call())
	# Normalでは勝てず、Easyなら勝てる敵で、実際の戦闘(resolve)も結果が変わる
	var between: int = limits[NORMAL] + 5
	parties.set_difficulty(pid, NORMAL)
	_check("前提: 上限のすぐ上の敵は、Normalでは勝てない(予測)", combat.predict_party_result(pid, between, true) != "victory")
	parties.set_difficulty(pid, EASY)
	_check("Easyなら、同じ敵に勝てる(予測)", combat.predict_party_result(pid, between, true) == "victory")
	# 実際の戦闘は、戦った分の戦闘力の経験値が入ってレベルが上がることがある。次の戦闘が同じ条件になるよう、スキルを戻す
	var saved_skills := {}
	for id in party["member_ids"]:
		saved_skills[id] = npcs.get_npc(id)["skills"].duplicate(true)
	_reset_hp(party)
	var easy_result: Dictionary = combat.resolve_party_encounter(pid, between, 1)
	_check("Easyで実際に戦うと勝つ", easy_result["result"] == "victory", str(easy_result))
	for id in party["member_ids"]:
		npcs.get_npc(id)["skills"] = saved_skills[id].duplicate(true)
	parties.set_difficulty(pid, NORMAL)
	_reset_hp(party)
	var normal_result: Dictionary = combat.resolve_party_encounter(pid, between, 1)
	_check("Normalで実際に戦うと勝てない", normal_result["result"] != "victory", str(normal_result))
	_reset_hp(party)
	_finish(dialogue)

	print("\n=== スキルゲートの必要Lv ===")
	var skill_node := ""
	for node_id in world_map.nodes.keys():
		var gate: Dictionary = world_map.nodes[node_id]["gate"]
		if gate.get("type", "") == "skill" and int(gate["min_level"]) == 3:
			skill_node = node_id
			break
	_check("前提: 必要Lv3のスキルゲートがある", skill_node != "", skill_node)
	var gate_data: Dictionary = world_map.nodes[skill_node]["gate"]
	var gate_skill: int = gate_data["skill"]
	for id in party["member_ids"]:
		npcs.get_npc(id)["unique_skill"] = {} # 固有スキルの実効Lv加算を切り離す
	var results := {}
	for level in [2, 3]:
		for id in party["member_ids"]:
			npcs.get_npc(id)["skills"][gate_skill]["level"] = level
			npcs.get_npc(id)["skills"][gate_skill]["exp"] = 0
		for mode in [EASY, NORMAL, HARD]:
			parties.set_difficulty(pid, mode)
			results["%d/%d" % [level, mode]] = exploration._attempt_gate(party, skill_node, 1)["passed"]
	print("  必要Lv3のゲートの結果(スキルLv/難易度→突破): ", results)
	_check("スキルLv2: Easyだけ突破(必要Lv2)", results["2/%d" % EASY] and not results["2/%d" % NORMAL] and not results["2/%d" % HARD])
	_check("スキルLv3: EasyとNormalが突破、Hardは不可(必要Lv4)", results["3/%d" % EASY] and results["3/%d" % NORMAL] and not results["3/%d" % HARD])

	print("\n=== 収入・報酬の倍率 ===")
	parties.set_difficulty(pid, NORMAL)
	# 一部だけ突破しても完全攻略にならないよう、フロアが4つ以上あるセクションを選ぶ(最初のセクションは3フロアしかない)
	var section := ""
	for section_id in world_map.sections.keys():
		if world_map.nodes_in_section(section_id).size() >= 4:
			section = section_id
			break
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	var floors: Array = world_map.nodes_in_section(section)
	for i in range(2):
		world_map.mark_passed(floors[i], true)
	parties.assign_section(pid, section)
	party["post_clear_behavior"] = 0 # STAY(完全攻略しても、配置転換で動かさない)
	var base_monthly: int = exploration.MONTHLY_INCOME_PER_POINT * world_map.section_multiplier(section) * world_map.passed_count_in_section(section)
	print("  月次収入の基礎値=%d" % base_monthly)
	var monthly := {}
	for mode in [EASY, NORMAL, HARD]:
		parties.set_difficulty(pid, mode)
		var before: int = economy.funds
		exploration._on_month_ended(1)
		monthly[mode] = economy.funds - before
		_check("月次収入(%s)= 基礎値×倍率" % Difficulty.mode_name(mode), monthly[mode] == Difficulty.reward(base_monthly, mode), "得た=%d 期待=%d" % [monthly[mode], Difficulty.reward(base_monthly, mode)])
		_check("予測(forecast)の基礎収入(%s)も同じ" % Difficulty.mode_name(mode), exploration.forecast_section(pid, section)["base_income"] == Difficulty.reward(base_monthly, mode))
	_check("月次収入は Hard > Normal > Easy", monthly[HARD] > monthly[NORMAL] and monthly[NORMAL] > monthly[EASY])

	# 攻略報酬(初回=固定ボーナスあり): 難易度の倍率はフロア数の分だけにかかり、初回ボーナスは固定
	for id in floors:
		world_map.mark_passed(id, true)
	var per_floor: int = exploration.SECTION_CLEAR_REWARD_PER_FLOOR * world_map.section_multiplier(section) * floors.size()
	var clear_expect := {}
	for mode in [EASY, NORMAL, HARD]:
		world_map.section_reward_claimed = {} # 初回の完全攻略に戻す
		parties.set_difficulty(pid, mode)
		var before: int = economy.funds
		exploration._check_section_cleared(section, 1, pid)
		var got: int = economy.funds - before
		clear_expect[mode] = Difficulty.reward(per_floor, mode) + exploration.FIRST_SECTION_CLEAR_BONUS
		_check("攻略報酬・初回(%s)= フロア分×倍率 + 固定ボーナス" % Difficulty.mode_name(mode), got == clear_expect[mode], "得た=%d 期待=%d(フロア分の基礎値=%d)" % [got, clear_expect[mode], per_floor])
	# 2回目以降(初回ボーナスなし)
	world_map.section_reward_claimed = {"other_section": true}
	parties.set_difficulty(pid, HARD)
	var before_second: int = economy.funds
	exploration._check_section_cleared(section, 1, pid)
	_check("攻略報酬・2つ目以降(Hard)= フロア分×1.5(ボーナス無し)", economy.funds - before_second == Difficulty.reward(per_floor, HARD), "得た=%d" % (economy.funds - before_second))
	world_map.section_reward_claimed = {"other_section": true}
	before_second = economy.funds
	exploration._check_section_cleared(section, 1, -1)
	_check("突破したパーティが分からない(野良など)ならNormal扱い", economy.funds - before_second == per_floor, "得た=%d 期待=%d" % [economy.funds - before_second, per_floor])

	# 周回収入(完全攻略済みのセクションで1周したとき)
	var lap := {}
	var lap_base: int = exploration.LAP_INCOME_PER_POINT * world_map.section_multiplier(section) * world_map.passed_count_in_section(section)
	var lap_days: int = maxi(1, world_map.nodes_in_section(section).size())
	for mode in [EASY, NORMAL, HARD]:
		parties.set_difficulty(pid, mode)
		parties.assign_section(pid, section)
		exploration._process_lap(party, 100) # 周回の開始
		var before: int = economy.funds
		exploration._process_lap(party, 100 + lap_days) # 1周
		lap[mode] = economy.funds - before
		_check("周回収入(%s)= 基礎値×倍率" % Difficulty.mode_name(mode), lap[mode] == Difficulty.reward(lap_base, mode), "得た=%d 期待=%d" % [lap[mode], Difficulty.reward(lap_base, mode)])

	print("\n=== 画面: マップのアイコン・一覧・詳細 ===")
	_finish(dialogue)
	parties.set_difficulty(pid, NORMAL)
	var badge_info := {}
	for mode in [EASY, NORMAL, HARD]:
		parties.set_difficulty(pid, mode)
		var icon: Button = _main._create_party_icon(party)
		var found_text := ""
		var found_color := Color(0, 0, 0, 0)
		var found_top_left := false
		for child in icon.get_children():
			if child is PanelContainer and child.get_child_count() > 0 and child.get_child(0) is Label:
				var t: String = child.get_child(0).text
				if t in ["E", "N", "H"]:
					found_text = t
					found_color = child.get_theme_stylebox("panel").bg_color
					found_top_left = child.anchor_left == 0.0 and child.anchor_right == 0.0 and child.anchor_top == 0.0 and child.anchor_bottom == 0.0
		badge_info[mode] = [found_text, found_color]
		_check("アイコンの左上の頭文字バッジ(%s)= %s・色が難易度の色" % [Difficulty.mode_name(mode), Difficulty.initial(mode)], found_text == Difficulty.initial(mode) and found_top_left and found_color.is_equal_approx(Color(_main.DIFFICULTY_COLORS[mode].r, _main.DIFFICULTY_COLORS[mode].g, _main.DIFFICULTY_COLORS[mode].b, 0.95)), "text=%s color=%s 左上=%s" % [found_text, found_color, found_top_left])
		_check("ツールチップに難易度名(%s)" % Difficulty.mode_name(mode), icon.tooltip_text.contains(Difficulty.mode_name(mode)), icon.tooltip_text)
		icon.free()
	_check("3つのバッジの背景色は、それぞれ違う", badge_info[EASY][1] != badge_info[NORMAL][1] and badge_info[NORMAL][1] != badge_info[HARD][1] and badge_info[EASY][1] != badge_info[HARD][1])
	# 休養中(右下に日数のバッジ)でも、左上の頭文字が残る
	party["status"] = 2 # RECOVERING
	party["recovering_until_day"] = 999
	var recovering_icon: Button = _main._create_party_icon(party)
	var letters := 0
	for child in recovering_icon.get_children():
		if child is PanelContainer and child.get_child_count() > 0 and child.get_child(0) is Label and child.get_child(0).text in ["E", "N", "H"]:
			letters += 1
	_check("休養中のアイコンにも、頭文字のバッジが1つある", letters == 1, str(letters))
	recovering_icon.free()
	_reset_hp(party)

	parties.set_difficulty(pid, HARD)
	var group := ButtonGroup.new()
	var card: Button = _main._create_party_card(party, group)
	_check("パーティ一覧のカードに難易度名", card.text.contains("[Hard]"), card.text.replace("\n", " / "))
	card.free()

	_main._selected_party_id = -1
	_main._refresh_party_detail()
	_check("パーティ未選択: 難易度のボタンは押せず、説明も空", _main.difficulty_buttons.all(func(b): return b.disabled) and _main.difficulty_desc_label.text == "")
	_main._selected_party_id = pid
	_main._refresh_party_detail()
	_check("パーティ選択: ボタンが押せる。今の難易度(Hard)だけが押されている", _main.difficulty_buttons.all(func(b): return not b.disabled) and _main.difficulty_buttons[HARD].button_pressed and not _main.difficulty_buttons[EASY].button_pressed and not _main.difficulty_buttons[NORMAL].button_pressed)
	_check("説明の1行が今の難易度のもの", _main.difficulty_desc_label.text == Difficulty.describe(HARD), _main.difficulty_desc_label.text)
	_main._on_difficulty_pressed(EASY)
	_check("Easyのボタンを押すとパーティの難易度が変わる", parties.difficulty(pid) == EASY)
	_check("ボタン・説明も切り替わる", _main.difficulty_buttons[EASY].button_pressed and not _main.difficulty_buttons[HARD].button_pressed and _main.difficulty_desc_label.text == Difficulty.describe(EASY))
	_main.difficulty_buttons[NORMAL].pressed.emit()
	_check("ボタンの pressed シグナルでも切り替わる(Normal)", parties.difficulty(pid) == NORMAL and _main.difficulty_buttons[NORMAL].button_pressed)
	_check("切替ボタンの押下スタイルが、難易度の色", _main.difficulty_buttons[HARD].get_theme_stylebox("pressed").bg_color.is_equal_approx(_main.DIFFICULTY_COLORS[HARD]))
	_completed = true
