# 使い捨ての確認用スクリプト(2026-09-20)。勝てないボスの前での退避の確認。挑まずに退避(1つ前の攻略済みセクション/最初のセクション)、退避中の経験値、強化後の復帰と勝利、手動の割り当てで退避解除、save_state/load_stateの往復。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree
var _ran := false
var Npcs
var Parties
var WorldMap
var Exploration
var Board

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true

func _hp(party) -> String:
	var parts := []
	for id in party["member_ids"]:
		var n = Npcs.get_npc(id)
		parts.append("%d/%d" % [int(n["hp"]), int(n["max_hp"])])
	return " ".join(parts)

func _sname(id) -> String:
	return WorldMap.sections[id]["name"] if WorldMap.sections.has(id) else "(なし)"

func _combat_lv(party) -> String:
	var parts := []
	for id in party["member_ids"]:
		var e = Npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]
		parts.append("Lv%d(%d)" % [e["level"], e["exp"]])
	return " ".join(parts)

func _setup(prior_cleared: bool):
	# 前の場面で開いたままの会話は閉じる。開いたままだと、会話が開いている間は撤退の判定を見送る仕様
	# (exploration.gdの_on_day_advanced)に掛かる。ゲームでは、会話が開いている間は時間が止まるので起きない
	var dialogue = root.get_node("EventDialogue")
	var guard := 0
	while dialogue.is_active and guard < 50:
		guard += 1
		dialogue.advance()
	root.get_node("SaveSystem").start_fresh_session()
	var party = Parties.get_parties()[0]
	var sec = "old_cave_dungeon"
	for id in WorldMap.nodes.keys():
		WorldMap.nodes[id]["found"] = false
		WorldMap.nodes[id]["passed"] = false
	var first = WorldMap.first_section()
	if prior_cleared:
		for id in WorldMap.nodes_in_section(first):
			WorldMap.mark_passed(id, true)
	else:
		# 最初のセクションの入口だけ通しておく(全部は突破していない)
		WorldMap.mark_passed(WorldMap.nodes_in_section(first)[0], true)
	WorldMap.mark_passed("cave", true)
	WorldMap.mark_passed("locked_vault", true)
	WorldMap.mark_found("boss_lair", true) # 宝物庫は、ボスを突破するまで見つからない
	Parties.assign_section(party["id"], sec)
	return party

func _run() -> void:
	Npcs = root.get_node("Npcs"); Parties = root.get_node("Parties"); WorldMap = root.get_node("WorldMap")
	Exploration = root.get_node("Exploration"); Board = root.get_node("Board")
	print("最初のセクション=", _sname(WorldMap.first_section()))

	for scenario in [true, false]:
		print("\n=== シナリオ: 1つ前の攻略済みセクション%s ===" % ("あり" if scenario else "なし(最初のセクションへ戻る)"))
		var party = _setup(scenario)
		var sec = "old_cave_dungeon"
		var statuses := {}
		var fights := 0
		for day in range(1, 31):
			var before_status = party["status"]
			Exploration._on_day_advanced(day)
			statuses[party["status"]] = statuses.get(party["status"], 0) + 1
			if day <= 3 or day % 10 == 0:
				print("day%2d 担当=%s 退避=%s status=%d HP=%s 戦闘Lv=%s" % [day, _sname(party["assigned_section"]), Parties.is_retreating(party), party["status"], _hp(party), _combat_lv(party)])
		print("30日のstatus内訳(1=探索中,2=休養中)=", statuses, " (期待: 休養中(2)が0)")

		# 強くなった(戦闘Lvを上げた)ら元のセクションへ戻り、勝つこと
		for id in party["member_ids"]:
			Npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]["level"] = 40
		Exploration._on_day_advanced(31)
		print("[戻り] 強化後1日目: 担当=%s 退避=%s status=%d" % [_sname(party["assigned_section"]), Parties.is_retreating(party), party["status"]])
		# 戻った日は戻っただけで終える(同じ日に突破・完全攻略・次のセクションへの配置転換まで進むと、画面上は
		# 退避先から2つ先へ飛んで見える。2026-09-21、実機で報告)。突破は翌日。
		print("[戻り] 戻った日はまだ突破していない=%s (期待: true)" % (not WorldMap.nodes["boss_lair"]["passed"]))
		Exploration._on_day_advanced(32)
		print("[戻り] 2日目: boss_lair突破=%s 担当=%s status=%d" % [WorldMap.nodes["boss_lair"]["passed"], _sname(party["assigned_section"]), party["status"]])

	# 手動の割り当てで退避が解除される
	print("\n=== 手動割り当て ===")
	var party2 = _setup(true)
	for day in range(1, 4):
		Exploration._on_day_advanced(day)
	print("退避中=", Parties.is_retreating(party2), " 担当=", _sname(party2["assigned_section"]))
	Parties.assign_section(party2["id"], "old_cave_dungeon")
	print("手動で割り当て直した後の退避=", Parties.is_retreating(party2), "(期待: false)")

	# セーブ状態の往復(メモリ上)
	print("\n=== save_state/load_state ===")
	var party3 = _setup(true)
	for day in range(1, 4):
		Exploration._on_day_advanced(day)
	var snapshot = Parties.save_state().duplicate(true)
	var rs_before = party3["return_section"]
	Parties.load_state(snapshot)
	var restored = Parties.get_parties()[0]
	print("戻り先が復元される=", restored["return_section"] == rs_before and rs_before != "", " return_node=", restored["return_node"])
