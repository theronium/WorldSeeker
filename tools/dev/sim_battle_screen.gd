# 使い捨ての確認用スクリプト(2026-09-22)。戦闘画面(battle_screen.gd、main.gdの_build_battle_screen_ui、
# design.md 5.4節)の確認。依頼「戦闘イベントがすぐに終わってしまうため、戦っている画面を見せたい」。
#   Combat.resolve_party_encounterのtrace: 数値計算そのものは変えず、ラウンドごとの記録を追加しただけであること
#     (traceを外してもresult/npc_id/HP/経験値は従来と完全に同じ)
#   exploration.gd: 会話が付いた戦闘ゲートの突破/失敗で、設定ONなら開き、OFFなら開かない。勝ち目が無く
#     戦わなかった場合は開かない。開いている間はTimeSystem.dialogue_holdが立ち、閉じると日付が進む。
#     退避の説明会話は、戦闘画面が開いている間は待ち、閉じた後に出る(横取りしない)。
#   main.gd: パネルの中身(4人分+敵のHPバー・肖像・名前)、タップ/早送りでラウンドが進み、最後に結果が出て
#     「閉じる」でBattleScreenへ伝わる。back-keyでは閉じない。
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
		return false
	if _frames == 8: # call_deferred()(退避の説明会話の予約)が、その間のフレームで済んでから確かめる
		_run_part2()
		if not _completed:
			print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
		else:
			print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
		return true
	return false

func _finish_dialogue() -> void:
	var dialogue = root.get_node("EventDialogue")
	var guard := 0
	while dialogue.is_active and guard < 50:
		guard += 1
		dialogue.advance()

## 会話が閉じるまで進める(選択肢の無い行だけの前提。ボス戦・戦闘の会話は選択肢が無い)。
func _click_through_dialogue() -> void:
	_finish_dialogue()

func _run() -> void:
	var world_map = root.get_node("WorldMap"); var parties = root.get_node("Parties"); var npcs = root.get_node("Npcs")
	var combat = root.get_node("Combat"); var save = root.get_node("SaveSystem"); var dialogue = root.get_node("EventDialogue")
	var events = root.get_node("ScenarioEvents"); var settings = root.get_node("Settings"); var exploration = root.get_node("Exploration")
	var battle = root.get_node("BattleScreen"); var time_system = root.get_node("TimeSystem")
	_finish_dialogue()

	print("=== Combat: traceは数値計算に影響しない(副作用が無い追加) ===")
	save.start_fresh_session()
	var party: Dictionary = parties.get_parties()[0]
	var pid: int = party["id"]
	for id in party["member_ids"]:
		npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]["level"] = 3
	var snapshot_hp := {}
	var exp_before := {}
	for id in party["member_ids"]:
		snapshot_hp[id] = npcs.get_npc(id)["hp"]
		exp_before[id] = npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]["exp"]
	var result: Dictionary = combat.resolve_party_encounter(pid, 250, 1)
	_check("traceキーがある", result.has("trace") and result.has("enemy_start_power"))
	_check("traceは空でない(実際に戦った)", not result["trace"].is_empty(), str(result["trace"].size()))
	var trace_rounds_by_npc := {}
	for entry in result["trace"]:
		trace_rounds_by_npc[entry["npc_id"]] = trace_rounds_by_npc.get(entry["npc_id"], 0) + 1
	# grant_skill_exp()はジョブ適性の1.5倍補正とレベルアップ時のexp繰り越しがあるため、「ラウンド数=exp増分」の
	# 厳密な一致は成り立たない(ジョブ適性者だとexp増分の方が大きく、レベルアップを跨ぐと差し引かれて小さくも見える)。
	# ここでは「戦ったメンバーはexpが増え、戦わなかったメンバーは増えない」という緩い対応だけ確かめる。
	for id in party["member_ids"]:
		var exp_gain: int = npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]["exp"] - exp_before[id]
		var fought: bool = trace_rounds_by_npc.has(id)
		if fought:
			_check("npc%dはtraceに記録があり、expも増えている" % id, exp_gain > 0, "trace=%dラウンド exp増分=%d" % [trace_rounds_by_npc[id], exp_gain])
		else:
			_check("npc%dはtraceに記録が無く(出番無し)、expも増えていない" % id, exp_gain == 0)
	_check("traceの最後のエントリはvictory/defeat/retreatのいずれかを含む", ["victory", "defeated", "retreated"].any(func(t): return String(result["trace"][-1]["event"]).contains(t)), result["trace"][-1]["event"])
	# 同じ状況をpredict_party_resultと突き合わせる(手前で状態をリセット)
	for id in party["member_ids"]:
		npcs.get_npc(id)["hp"] = snapshot_hp[id]
	party["status"] = 1
	var predicted: String = combat.predict_party_result(pid, 250)
	for id in party["member_ids"]:
		npcs.get_npc(id)["hp"] = snapshot_hp[id]
	var result2: Dictionary = combat.resolve_party_encounter(pid, 250, 1)
	_check("同じ状況なら、resolveの結果はpredictと一致する", result2["result"] == predicted, "%s vs %s" % [result2["result"], predicted])
	_check("同じ状況なら、traceも(乱数が無いので)全く同じ", result["trace"] == result2["trace"])

	print("\n=== exploration.gd: 会話付きの戦闘ゲートで、設定ONなら戦闘画面が開く ===")
	save.start_fresh_session()
	settings.set_show_battle_screen(true)
	party = parties.get_parties()[0]
	pid = party["id"]
	# 突破できる戦闘ゲート(archive等)を探す。低いLvでも勝てるよう戦闘力を上げる
	for id in party["member_ids"]:
		npcs.get_npc(id)["unique_skill"] = {} # 戦力の乱数要因を外す(前述と同じ理由)
		npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]["level"] = 20
	var combat_floor := ""
	for id in world_map.nodes.keys():
		var gate: Dictionary = world_map.nodes[id]["gate"]
		if gate.get("type", "") == "combat" and events.has_gate_event(id):
			combat_floor = id
			break
	_check("前提: 会話付きの戦闘ゲートがある", combat_floor != "", combat_floor)
	var section_id: String = world_map.nodes[combat_floor]["section"]
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	for id in world_map.nodes_in_section(section_id):
		if id != combat_floor:
			world_map.mark_passed(id, true)
	parties.assign_section(pid, section_id)
	exploration._attempt_discovery(party, 1) # 隣接する未発見ノードを試す(combat_floorが対象に含まれる状態)
	# 発見の乱数に依存するので、直接呼んで発見させる
	exploration._on_node_found("斥候", party["member_ids"][0], party, combat_floor, 1)
	_check("会話が開く", dialogue.is_active)
	_click_through_dialogue()
	_check("会話が閉じた直後、戦闘画面が開いている", battle.is_active)
	_check("戦闘画面が開いている間、時間が止まる(dialogue_hold)", time_system.dialogue_hold)
	_check("戦闘画面が開いている間、フロアは既に突破済み(再現表示なので先に確定する)", world_map.is_passed(combat_floor))
	_check("パネルが表示され、モーダルが効いている", _main.battle_panel.visible and _main.modal_blocker.visible)
	_check("敵の名前が入っている", _main.battle_enemy_name_label.text != "")
	# ProgressBarのmax_valueは既定で100なので、「>0」だけでは中身が入っていないケースを見逃す
	# (2026-09-22、member_idsを渡し忘れていた不具合がこれで一度見逃されていた)。実際のnpcの名前・HPと突き合わせる。
	for i in range(4):
		var npc: Dictionary = npcs.get_npc(party["member_ids"][i])
		var slot: Dictionary = _main.battle_party_slots[i]
		_check("%d番目のスロットの名前が、そのメンバー(%s)と一致する" % [i, npc["name"]], slot["name"].text == npc["name"], slot["name"].text)
		_check("%d番目のスロットのHPバーの最大値が、そのメンバーの最大HPと一致する" % i, is_equal_approx(slot["hp_bar"].max_value, npc["max_hp"]), "%.0f vs %.0f" % [slot["hp_bar"].max_value, npc["max_hp"]])

	# タップで1ラウンドずつ進む
	var before_round: int = _main._battle_round_index
	_main._on_battle_panel_gui_input(InputEventMouseButton.new())
	_check("タップでは進まない(左クリック+pressedのイベントでないと)", _main._battle_round_index == before_round)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	_main._on_battle_panel_gui_input(click)
	_check("正しいクリックイベントなら1ラウンド進む", _main._battle_round_index == before_round + 1)

	# 早送りで最後まで
	_main._on_battle_skip_pressed()
	_check("早送りで最後まで進む", _main._battle_round_index == _main._battle_trace.size())
	_check("結果表示になり、閉じるボタンが出る", _main.battle_close_button.visible and not _main.battle_skip_button.visible)
	_check("back-keyでは閉じない(閉じるボタンのみ)", _main.battle_panel.visible)
	_main._on_go_back_requested()
	_check("実際にback-keyを送っても、開いたまま", _main.battle_panel.visible)

	_main._on_battle_close_pressed()
	_check("閉じるボタンでパネルが閉じる", not _main.battle_panel.visible)
	_check("BattleScreen.is_activeもfalseに戻る", not battle.is_active)
	_check("戦闘画面が閉じると、時間の一時停止も解ける", not time_system.dialogue_hold)

	print("\n=== 設定OFFなら開かない ===")
	save.start_fresh_session()
	settings.set_show_battle_screen(false)
	party = parties.get_parties()[0]
	pid = party["id"]
	for id in party["member_ids"]:
		npcs.get_npc(id)["unique_skill"] = {} # 戦力の乱数要因を外す(前述と同じ理由)
		npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]["level"] = 20
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	section_id = world_map.nodes[combat_floor]["section"]
	for id in world_map.nodes_in_section(section_id):
		if id != combat_floor:
			world_map.mark_passed(id, true)
	parties.assign_section(pid, section_id)
	exploration._on_node_found("斥候", party["member_ids"][0], party, combat_floor, 1)
	_click_through_dialogue()
	_check("設定OFFなら、会話が閉じても戦闘画面は開かない", not battle.is_active and not _main.battle_panel.visible)
	_check("それでも、フロアは通常どおり突破済みになる", world_map.is_passed(combat_floor))
	settings.set_show_battle_screen(true)

	print("\n=== 勝ち目が無い(挑まなかった)ゲートでは開かない ===")
	save.start_fresh_session()
	party = parties.get_parties()[0]
	pid = party["id"]
	# 戦闘力を上げず(弱いまま)、勝てない敵の会話付きゲートを探す
	var hopeless_floor := ""
	for id in world_map.nodes.keys():
		var gate: Dictionary = world_map.nodes[id]["gate"]
		if gate.get("type", "") == "combat" and events.has_gate_event(id) and int(gate["enemy_power"]) > 500:
			hopeless_floor = id
			break
	_check("前提: 満タンでも勝てない、会話付きの戦闘ゲートがある", hopeless_floor != "", hopeless_floor)
	section_id = world_map.nodes[hopeless_floor]["section"]
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	for id in world_map.nodes_in_section(section_id):
		if id != hopeless_floor:
			world_map.mark_passed(id, true)
	parties.assign_section(pid, section_id)
	exploration._on_node_found("斥候", party["member_ids"][0], party, hopeless_floor, 1)
	_check("会話(失敗側)は開く", dialogue.is_active)
	_click_through_dialogue()
	_check("勝ち目が無く戦わなかった場合、戦闘画面は開かない(見せる戦闘が無いため)", not battle.is_active)

	print("\n=== 戦闘画面が塞いでいる間、退避の説明会話は横取りしない ===")
	save.start_fresh_session()
	party = parties.get_parties()[0]
	pid = party["id"]
	# 確実に「負ける(挑む)」状況を作る: 満タンでは勝てるが、今はHPが低く、predict(通常HP)がdefeat/retreatになるケースを使う
	var target_floor := ""
	var target_gate := {}
	for id in world_map.nodes.keys():
		var gate: Dictionary = world_map.nodes[id]["gate"]
		if gate.get("type", "") == "combat" and events.has_gate_event(id):
			target_floor = id
			target_gate = gate
			break
	for id in party["member_ids"]:
		var npc = npcs.get_npc(id)
		npc["unique_skill"] = {} # 固有スキル(雇用時に乱数で決まり、戦闘力に影響しうる)を外し、Lvだけで戦力を決まらせる
		npc["max_hp"] = 100.0 # 雇用時にmax_hp_flat固有スキルで底上げ済みの場合があり、後からunique_skillを外しても
		npc["hp"] = 100.0 # 戻らない(hire()で一度だけ適用され、値に焼き込まれるため)。ここで揃えて乱数要因を消す
	# 「満タンでは勝てるが、今のHP(=1)では勝てない」Lvを探す。enemy_powerが減っていく非線形な計算式のため、
	# 単純な数式では求めにくく、実際にpredict_party_result(ゲーム本体と同じ関数)で1レベルずつ試すのが確実。
	var chosen_level := -1
	for level in range(1, 60):
		for id in party["member_ids"]:
			npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]["level"] = level
		if combat.predict_party_result(pid, target_gate["enemy_power"], true) != "victory":
			continue
		for id in party["member_ids"]:
			npcs.get_npc(id)["hp"] = 1.0
		if combat.predict_party_result(pid, target_gate["enemy_power"], false) != "victory":
			chosen_level = level
			break
		for id in party["member_ids"]: # このLvでは満タンでもHP=1でも勝ててしまった。HPを戻して次のLvを試す
			npcs.get_npc(id)["hp"] = npcs.get_npc(id)["max_hp"]
	_check("前提: 満タンでは勝てるが、今のHPでは勝てないLvが見つかる", chosen_level != -1, "Lv=%d 敵の戦闘力=%d" % [chosen_level, target_gate["enemy_power"]])
	section_id = world_map.nodes[target_floor]["section"]
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	for id in world_map.nodes_in_section(section_id):
		if id != target_floor:
			world_map.mark_passed(id, true)
	parties.assign_section(pid, section_id)
	exploration._on_node_found("斥候", party["member_ids"][0], party, target_floor, 1)
	_click_through_dialogue()
	_check("戦闘画面が開く(実際に戦って負けたので、traceがある)", battle.is_active)
	_check("退避の説明会話は、戦闘画面の陰でまだ開いていない", not dialogue.is_active)
	_main._on_battle_skip_pressed()
	_main._on_battle_close_pressed()
	_check("戦闘画面を閉じた直後は、まだ開いていない(call_deferredで次のフレームに回る)", not dialogue.is_active)
	# ここで_run()を終える(次のフレームでcall_deferredが実行されてから_run_part2()で確かめる)。

## 戦闘画面が閉じてから数フレーム後: 予約されていた退避の説明会話が、横取りされずに正しく開くこと。
func _run_part2() -> void:
	var save = root.get_node("SaveSystem"); var dialogue = root.get_node("EventDialogue")
	_check("戦闘画面を閉じた後、退避の説明会話が(未視聴なら)開く", dialogue.is_active or save.is_tutorial_seen("retreat"))
	if dialogue.is_active:
		_check("退避の説明会話の種別はguide", dialogue.current_kind == "guide")
	_finish_dialogue()
	_completed = true
