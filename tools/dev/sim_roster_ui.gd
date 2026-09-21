# 使い捨ての確認用スクリプト(2026-09-21)。探索者一覧の並べ替え・絞り込み・総合戦力の表示(RosterQuery、main.gd)と、
# 会話パネルの「次へ」を押しやすくする変更(下端から浮かす・どこをクリックしても進む・Enter/Spaceで進む)の確認。
#   L: ロジック(RosterQuery、Npcs.power_breakdown)  U: 画面(メイン画面を組み立てて操作する)  D: 会話パネル
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
# RosterQueryはオートロード(Npcs/Recruitment)を参照するので、名前では呼べない: load()して呼ぶ。
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

func _names(list: Array) -> Array:
	return list.map(func(npc): return npc["name"])

func _card_names() -> Array:
	var names: Array = []
	for child in _main.roster_grid.get_children():
		if child is Button:
			names.append(child.tooltip_text)
	return names

func _run() -> void:
	var npcs = root.get_node("Npcs"); var save = root.get_node("SaveSystem"); var dialogue = root.get_node("EventDialogue")
	var RQ = load("res://scripts/roster_query.gd")
	while dialogue.is_active:
		dialogue.advance() # 起動時の導入会話は進めておく
	save.start_fresh_session()
	for id in npcs.roster.keys().duplicate():
		npcs.roster.erase(id) # 初期パーティの4人を除き、顔ぶれを自分で決める
	var a: int = npcs.hire("アアア", {"bloodline": "平民"}, {SkillTypes.Skill.COMBAT: 3, SkillTypes.Skill.WISDOM: 1}, Jobs.Job.WARRIOR)
	var b: int = npcs.hire("イイイ", {"bloodline": "王家の落胤"}, {SkillTypes.Skill.COMBAT: 1, SkillTypes.Skill.WISDOM: 5}, Jobs.Job.SAGE)
	var c: int = npcs.hire("ウウウ", {"bloodline": "平民"}, {SkillTypes.Skill.COMBAT: 3, SkillTypes.Skill.WISDOM: 2}, Jobs.Job.SAGE)
	var d: int = npcs.hire("エエエ", {"bloodline": "森人の血"}, {SkillTypes.Skill.COMBAT: 6, SkillTypes.Skill.WISDOM: 0}, Jobs.Job.WARRIOR)
	# 固有スキルは乱数なので、戦力の比較が揺れないように外す
	for id in [a, b, c, d]:
		npcs.roster[id]["unique_skill"] = {}
	npcs.equip(c, "weapon", Equipment.Tier.IRON) # ウウウは武器+30: 戦闘Lv3(40)+30=70 > アアア(40)
	var all: Array = npcs.get_roster()

	# ---------- L: ロジック ----------
	print("--- L: ロジック ---")
	var bd: Dictionary = npcs.power_breakdown(c)
	_check("L: 内訳: 戦闘Lv3→40 / 武器+30 / 防具0 / 固有0 で合計70", bd["skill_level"] == 3 and bd["skill"] == 40 and bd["weapon"] == 30 and bd["armor"] == 0 and bd["unique"] == 0 and bd["total"] == 70, str(bd))
	_check("L: power()は内訳の合計と一致する", npcs.power(c) == 70 and npcs.power(a) == 40 and npcs.power(d) == 70, "%d/%d/%d" % [npcs.power(a), npcs.power(c), npcs.power(d)])
	npcs.equip(a, "armor", Equipment.Tier.BRONZE)
	_check("L: 防具の補正も合計に入る(アアア 40+15)", npcs.power(a) == 55 and npcs.power_breakdown(a)["armor"] == 15)
	npcs.roster[a]["equipped_armor"] = {} # 元に戻す
	npcs.roster[d]["unique_skill"] = {"effect_type": "combat_power_flat", "value": 25}
	_check("L: 固有スキル(固定加算)も合計に入る(エエエ 70+25)", npcs.power(d) == 95 and npcs.power_breakdown(d)["unique"] == 25, str(npcs.power(d)))
	npcs.roster[d]["unique_skill"] = {}
	_check("L: 存在しないIDは0", npcs.power(9999) == 0 and npcs.power_breakdown(9999)["total"] == 0)

	_check("L: 加入順(昇順)", _names(RQ.query(all, "join", false)) == ["アアア", "イイイ", "ウウウ", "エエエ"], str(_names(RQ.query(all, "join", false))))
	_check("L: 加入順(降順)", _names(RQ.query(all, "join", true)) == ["エエエ", "ウウウ", "イイイ", "アアア"])
	_check("L: 名前(昇順)", _names(RQ.query(all, "name", false)) == ["アアア", "イイイ", "ウウウ", "エエエ"])
	_check("L: 名前(降順)", _names(RQ.query(all, "name", true)) == ["エエエ", "ウウウ", "イイイ", "アアア"])
	# 総合戦力: ウウウ70=エエエ70 > アアア40 > イイイ20 。同値(ウウウ・エエエ)は、向きに関わらずID順(ウウウが先)
	_check("L: 総合戦力(降順): 同値はID順", _names(RQ.query(all, "power", true)) == ["ウウウ", "エエエ", "アアア", "イイイ"], str(_names(RQ.query(all, "power", true))))
	_check("L: 総合戦力(昇順): 同値はID順のまま", _names(RQ.query(all, "power", false)) == ["イイイ", "アアア", "ウウウ", "エエエ"], str(_names(RQ.query(all, "power", false))))
	var wisdom_key := "skill:%d" % SkillTypes.Skill.WISDOM
	_check("L: 知恵Lv(降順): イイイ5 > ウウウ2 > アアア1 > エエエ0", _names(RQ.query(all, wisdom_key, true)) == ["イイイ", "ウウウ", "アアア", "エエエ"], str(_names(RQ.query(all, wisdom_key, true))))
	_check("L: 戦闘力Lv(降順): エエエ6 > アアア3=ウウウ3(ID順) > イイイ1", _names(RQ.query(all, "skill:%d" % SkillTypes.Skill.COMBAT, true)) == ["エエエ", "アアア", "ウウウ", "イイイ"])
	_check("L: 元の配列は変わらない", _names(all) == ["アアア", "イイイ", "ウウウ", "エエエ"])

	_check("L: 血筋で絞る(平民)", _names(RQ.query(all, "join", false, "平民")) == ["アアア", "ウウウ"])
	_check("L: 血筋で絞る(王家の落胤)", _names(RQ.query(all, "join", false, "王家の落胤")) == ["イイイ"])
	_check("L: ジョブで絞る(賢者)", _names(RQ.query(all, "join", false, "", Jobs.Job.SAGE)) == ["イイイ", "ウウウ"])
	_check("L: 血筋とジョブはAND(平民の賢者)", _names(RQ.query(all, "join", false, "平民", Jobs.Job.SAGE)) == ["ウウウ"])
	_check("L: 該当なしは空", RQ.query(all, "join", false, "王家の落胤", Jobs.Job.WARRIOR).is_empty())
	_check("L: 絞り込み+並べ替え(平民を戦力の降順)", _names(RQ.query(all, "power", true, "平民")) == ["ウウウ", "アアア"])
	_check("L: 血筋の選択肢: 名簿にいる血筋だけ、Recruitmentの並び順", RQ.bloodlines_in(all) == ["平民", "森人の血", "王家の落胤"], str(RQ.bloodlines_in(all)))
	_check("L: カードの1行: 戦力だけ", RQ.card_stat_text(npcs.get_npc(c), "join") == "戦力 70", RQ.card_stat_text(npcs.get_npc(c), "join"))
	_check("L: カードの1行: スキルで並べる時はそのLvも", RQ.card_stat_text(npcs.get_npc(b), wisdom_key) == "戦力 20 ・ 知恵 Lv5", RQ.card_stat_text(npcs.get_npc(b), wisdom_key))
	_check("L: 詳細の内訳の文字", RQ.power_breakdown_text(c) == "総合戦力 70(戦闘スキルLv3 → 40 / 武器 +30)", RQ.power_breakdown_text(c))

	# ---------- U: 画面 ----------
	print("--- U: 画面 ---")
	_main._open_npc_panel(false)
	_check("U: 一覧に4枚のカード(既定は加入順)", _card_names() == ["アアア", "イイイ", "ウウウ", "エエエ"], str(_card_names()))
	_check("U: 件数の表示(絞り込み無し)", _main.roster_count_label.text == "全4人", _main.roster_count_label.text)
	_check("U: 並べ替えの選択肢: 加入順・名前・総合戦力+スキル%d種" % SkillTypes.all_skills().size(), _main.roster_sort_option.item_count == 3 + SkillTypes.all_skills().size(), str(_main.roster_sort_option.item_count))
	_check("U: 血筋の選択肢: すべて+3種", _main.roster_bloodline_option.item_count == 4, str(_main.roster_bloodline_option.item_count))
	_check("U: ジョブの選択肢: すべて+%d種" % Jobs.JOB_NAMES.size(), _main.roster_job_option.item_count == 1 + Jobs.JOB_NAMES.size())
	# 総合戦力の並べ替え
	var power_index := -1
	for i in _main.roster_sort_option.item_count:
		if _main.roster_sort_option.get_item_metadata(i)["key"] == "power":
			power_index = i
	_main.roster_sort_option.select(power_index)
	_main._on_roster_sort_selected(power_index)
	_check("U: 総合戦力を選ぶと、大きい順(降順)になる", _card_names() == ["ウウウ", "エエエ", "アアア", "イイイ"] and _main.roster_sort_dir_button.text == "降順 ▼", "%s %s" % [str(_card_names()), _main.roster_sort_dir_button.text])
	_main._on_roster_sort_dir_pressed()
	_check("U: 向きのボタンで昇順に反転する", _card_names() == ["イイイ", "アアア", "ウウウ", "エエエ"] and _main.roster_sort_dir_button.text == "昇順 ▲", str(_card_names()))
	# カードの1行(スキルで並べた時)
	var wisdom_index := -1
	for i in _main.roster_sort_option.item_count:
		if _main.roster_sort_option.get_item_metadata(i)["key"] == wisdom_key:
			wisdom_index = i
	_main.roster_sort_option.select(wisdom_index)
	_main._on_roster_sort_selected(wisdom_index)
	_check("U: 知恵Lvで並べる(降順)", _card_names() == ["イイイ", "ウウウ", "アアア", "エエエ"], str(_card_names()))
	var stat_texts: Array = []
	for card in _main.roster_grid.get_children():
		for label in card.find_children("*", "Label", true, false):
			if String(label.text).begins_with("戦力"):
				stat_texts.append(label.text)
	_check("U: カードに総合戦力と、並べたスキルのLvが出る", stat_texts == ["戦力 20 ・ 知恵 Lv5", "戦力 70 ・ 知恵 Lv2", "戦力 40 ・ 知恵 Lv1", "戦力 70 ・ 知恵 Lv0"], str(stat_texts))
	# 絞り込み
	var bloodline_index := -1
	for i in _main.roster_bloodline_option.item_count:
		if _main.roster_bloodline_option.get_item_metadata(i) == "平民":
			bloodline_index = i
	_main.roster_bloodline_option.select(bloodline_index)
	_main._on_roster_bloodline_selected(bloodline_index)
	_check("U: 血筋(平民)で絞る", _card_names() == ["ウウウ", "アアア"] and _main.roster_count_label.text == "4人中 2人を表示", "%s %s" % [str(_card_names()), _main.roster_count_label.text])
	var sage_index := -1
	for i in _main.roster_job_option.item_count:
		if _main.roster_job_option.get_item_metadata(i) == Jobs.Job.SAGE:
			sage_index = i
	_main.roster_job_option.select(sage_index)
	_main._on_roster_job_selected(sage_index)
	_check("U: ジョブ(賢者)も加えて絞る(AND)", _card_names() == ["ウウウ"], str(_card_names()))
	# 該当なし(王家の落胤は賢者だけ。ジョブを戦士にすれば、誰もいない)
	var warrior_index := -1
	for i in _main.roster_job_option.item_count:
		if _main.roster_job_option.get_item_metadata(i) == Jobs.Job.WARRIOR:
			warrior_index = i
	_main.roster_job_option.select(warrior_index)
	_main._on_roster_job_selected(warrior_index)
	var royal_index := -1
	for i in _main.roster_bloodline_option.item_count:
		if _main.roster_bloodline_option.get_item_metadata(i) == "王家の落胤":
			royal_index = i
	_main.roster_bloodline_option.select(royal_index)
	_main._on_roster_bloodline_selected(royal_index)
	var empty_shown := false
	for child in _main.roster_grid.get_children():
		if child is Label and child.text == "条件に合う探索者がいません":
			empty_shown = true
	_check("U: 該当なしの時は、その旨を出す", empty_shown and _card_names().is_empty())
	_main._on_roster_filter_reset_pressed()
	_check("U: 「絞り込みを解除」で全員に戻る(並べ替えは残る)", _card_names() == ["イイイ", "ウウウ", "アアア", "エエエ"] and _main.roster_count_label.text == "全4人", str(_card_names()))
	# 顔ぶれが変わって、選んでいた血筋がいなくなった場合
	_main._roster_bloodline = "王家の落胤"
	npcs.roster.erase(b)
	_main._refresh_roster()
	_check("U: 選んでいた血筋が名簿からいなくなったら「すべて」に戻る", _main._roster_bloodline == "" and _card_names().size() == 3, "%s %d" % [_main._roster_bloodline, _card_names().size()])
	# 詳細
	_main._on_roster_card_pressed(c)
	var detail_text: String = _main.npc_job_label.text
	_check("U: 詳細に、内訳つきの総合戦力が出る", detail_text.contains("総合戦力 70(戦闘スキルLv3 → 40 / 武器 +30)"), detail_text)
	_main._close_modal(_main.npc_panel)

	# ---------- D: 会話パネル ----------
	print("--- D: 会話パネル ---")
	var panel: PanelContainer = _main.dialogue_panel
	_check("D: 下端から浮いている(offset_bottom=-%d)" % _main.DESKTOP_DIALOGUE_LIFT, panel.offset_bottom == -_main.DESKTOP_DIALOGUE_LIFT and panel.offset_top == -(200 + _main.DESKTOP_DIALOGUE_LIFT), "%s/%s" % [panel.offset_top, panel.offset_bottom])
	var script := [
		{"side": "left", "name": "甲", "text": "1行目"},
		{"side": "left", "name": "甲", "text": "2行目"},
		{"side": "left", "name": "甲", "text": "3行目"},
		{"side": "left", "name": "甲", "text": "選ぶ", "choices": [{"label": "はい", "outcome": "yes"}, {"label": "いいえ", "outcome": "no"}]},
	]
	dialogue.play(script, "", "")
	_check("D: 会話が開く", dialogue.is_active and panel.visible and _main.advance_hint.visible)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_main._on_dialogue_panel_gui_input(click)
	_check("D: パネルをクリックすると次の行へ進む", dialogue._index == 1, "index=%d" % dialogue._index)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	_main._on_dialogue_panel_gui_input(right_click)
	_check("D: 右クリックでは進まない", dialogue._index == 1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	_main._on_dialogue_panel_gui_input(release)
	_check("D: ボタンを離しただけでは進まない(1回のクリックで2行進まない)", dialogue._index == 1)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	_check("D: Enterで次の行へ進み、処理済みになる", _main._handle_dialogue_key(enter) and dialogue._index == 2, "index=%d" % dialogue._index)
	var space_echo := InputEventKey.new()
	space_echo.keycode = KEY_SPACE
	space_echo.pressed = true
	space_echo.echo = true
	_check("D: 押しっぱなしの繰り返し(echo)では進まない", not _main._handle_dialogue_key(space_echo) and dialogue._index == 2)
	var other_key := InputEventKey.new()
	other_key.keycode = KEY_A
	other_key.pressed = true
	_check("D: 他のキーでは進まない", not _main._handle_dialogue_key(other_key) and dialogue._index == 2)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	_check("D: Spaceでも進む(選択肢の行へ)", _main._handle_dialogue_key(space) and dialogue._index == 3, "index=%d" % dialogue._index)
	_check("D: 選択肢の行では、「次へ」は隠れている", not _main.advance_hint.visible)
	_check("D: 選択肢の行では、Enterは何もしない(選択肢ボタンに任せる)", not _main._handle_dialogue_key(enter) and dialogue._index == 3)
	_main._on_dialogue_panel_gui_input(click)
	_check("D: 選択肢の行では、パネルをクリックしても進まない", dialogue.is_active and dialogue._index == 3)
	dialogue.choose(0)
	_check("D: 選択肢を選ぶと会話が終わる", not dialogue.is_active and not panel.visible)
	_check("D: 会話が無い時のEnterは何もしない(処理済みにしない)", not _main._handle_dialogue_key(enter))
	_completed = true
