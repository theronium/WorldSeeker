# 使い捨ての確認用スクリプト(2026-09-21)。フロアに着いた時の進み方が「会話 → 判定の適用 → イベントの効果 → 撤退」の順か。
# 会話(ゲート結果のイベント)が開いている間は、HP・休養・突破・退避・配置転換が動かず、会話が閉じた後に反映されること。
# (以前は、会話を読んでいる時点で既に退避先へ戻っていた。2026-09-21、東方のテスト用シナリオで報告)
#   H: 勝てない相手(ゴブリンキング)   会話が失敗 → 開いている間は退避していない → 閉じた後に退避
#   D: 実際に戦って負ける            会話が失敗 → 開いている間は休養に入っていない → 閉じた後に休養
#   P: 勝てる                       会話が突破 → 開いている間は未突破 → 閉じた後に突破
#   T: 日次の流れ(_on_day_advanced)  勝てない相手を自然に発見した日も、会話が開いている間は退避していない
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree

var _ran := false
var _completed := false
var _fails := 0

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	if not _completed:
		print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
	else:
		print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
	return true

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

# 開いている会話を最後まで進める(ゲームでは、プレイヤーが「次へ」を押す)
func _finish(dialogue) -> void:
	var guard := 0
	while dialogue.is_active and guard < 50:
		guard += 1
		var line: Dictionary = dialogue._script[dialogue._index]
		if not line.get("choices", []).is_empty():
			dialogue.choose(0)
		else:
			dialogue.advance()

# 新規開始。最初のセクションを攻略済みにして、古い洞窟の入口(cave・locked_vault)まで通した状態。boss_lairは未発見。
func _setup(save, world_map, parties, dialogue) -> Dictionary:
	_finish(dialogue) # 前の検証の会話が残っていると、次の発見が見送られる
	save.start_fresh_session()
	var party: Dictionary = parties.get_parties()[0]
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	for id in world_map.nodes_in_section(world_map.first_section()):
		world_map.mark_passed(id, true)
	world_map.mark_passed("cave", true)
	world_map.mark_passed("locked_vault", true)
	parties.assign_section(party["id"], "old_cave_dungeon")
	return party

func _set_combat_level(npcs, party: Dictionary, level: int) -> void:
	for id in party["member_ids"]:
		npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]["level"] = level

func _run() -> void:
	var save = root.get_node("SaveSystem"); var world_map = root.get_node("WorldMap"); var parties = root.get_node("Parties")
	var exploration = root.get_node("Exploration"); var npcs = root.get_node("Npcs"); var dialogue = root.get_node("EventDialogue")

	# --- H: 勝てない相手 ---
	print("--- H: 勝てない相手(ゴブリンキング) ---")
	var party: Dictionary = _setup(save, world_map, parties, dialogue)
	exploration._on_node_found("探索者", party["member_ids"][0], party, "boss_lair", 5)
	_check("H: 失敗の会話が開く", dialogue.is_active and dialogue.current_result == "fail", "%s/%s" % [dialogue.is_active, dialogue.current_result])
	_check("H: 会話の間は、まだ退避していない(担当は古い洞窟のまま)", not parties.is_retreating(party) and party["assigned_section"] == "old_cave_dungeon", "担当=%s 退避=%s" % [party["assigned_section"], parties.is_retreating(party)])
	_check("H: 会話の間、フロアは発見済み・未突破", world_map.nodes["boss_lair"]["found"] and not world_map.nodes["boss_lair"]["passed"])
	_finish(dialogue)
	_check("H: 会話が閉じた後に退避する", parties.is_retreating(party) and party["assigned_section"] != "old_cave_dungeon" and party["return_section"] == "old_cave_dungeon", "担当=%s 戻り先=%s" % [party["assigned_section"], party["return_section"]])

	# --- D: 実際に戦って負ける(満タンなら勝てるが、今のHPでは負ける) ---
	print("--- D: 実戦闘で敗北 ---")
	party = _setup(save, world_map, parties, dialogue)
	var chosen := -1
	var hp_low := 10.0
	for level in range(0, 60):
		_set_combat_level(npcs, party, level)
		for id in party["member_ids"]:
			npcs.get_npc(id)["hp"] = 100.0
			npcs.get_npc(id)["max_hp"] = 100.0
		var winnable_at_full: bool = not exploration._is_hopeless_gate(party, world_map.nodes["boss_lair"])
		for id in party["member_ids"]:
			npcs.get_npc(id)["hp"] = hp_low
		var wins_now: bool = exploration._preview_gate(party, "boss_lair")["passed"]
		if winnable_at_full and not wins_now:
			chosen = level
			break
	_check("D: 前提: 満タンなら勝てて、HPが低いと負ける戦闘力が見つかった", chosen >= 0, "戦闘Lv=%d" % chosen)
	if chosen >= 0:
		exploration._on_node_found("探索者", party["member_ids"][0], party, "boss_lair", 5)
		_check("D: 失敗の会話が開く", dialogue.is_active and dialogue.current_result == "fail", "%s/%s" % [dialogue.is_active, dialogue.current_result])
		_check("D: 会話の間は、まだ休養に入っていない(戦闘は会話の後)", party["status"] == parties.Status.EXPLORING, "status=%d" % party["status"])
		var hp_open: Array = party["member_ids"].map(func(id): return npcs.get_npc(id)["hp"])
		_check("D: 会話の間は、HPも変わっていない", hp_open.all(func(hp): return is_equal_approx(hp, hp_low)), str(hp_open))
		_finish(dialogue)
		_check("D: 会話が閉じた後に戦闘が適用され、休養に入る", party["status"] == parties.Status.RECOVERING, "status=%d" % party["status"])

	# --- P: 勝てる ---
	print("--- P: 勝てる ---")
	party = _setup(save, world_map, parties, dialogue)
	_set_combat_level(npcs, party, 40)
	exploration._on_node_found("探索者", party["member_ids"][0], party, "boss_lair", 5)
	_check("P: 突破の会話が開く", dialogue.is_active and dialogue.current_result == "pass", "%s/%s" % [dialogue.is_active, dialogue.current_result])
	_check("P: 会話の間は、まだ未突破", not world_map.nodes["boss_lair"]["passed"])
	_finish(dialogue)
	_check("P: 会話が閉じた後に突破する", world_map.nodes["boss_lair"]["passed"])

	# --- T: 日次の流れ(勝てない相手を、自然な探索で発見する) ---
	print("--- T: 日次の流れ ---")
	party = _setup(save, world_map, parties, dialogue)
	var opened_day := -1
	for day in range(1, 601):
		exploration._on_day_advanced(day)
		if dialogue.is_active:
			opened_day = day
			break
	_check("T: 探索の途中で、会話が開いた", opened_day > 0, "%d日目" % opened_day)
	if opened_day > 0:
		_check("T: 会話が開いた日も、会話の間は退避していない", not parties.is_retreating(party) and party["assigned_section"] == "old_cave_dungeon", "担当=%s 退避=%s" % [party["assigned_section"], parties.is_retreating(party)])
		_finish(dialogue)
		_check("T: 会話が閉じた後に退避する", parties.is_retreating(party))
	_completed = true
