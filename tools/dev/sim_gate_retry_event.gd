# 使い捨ての確認用スクリプト(2026-09-24)。報告「撤退後2回目のバトルイベントが再生されない」の再発防止。
# 会話付きの戦闘ゲートで、初回(発見時)に勝てずに撤退した後、日次の再挑戦(Exploration._retry_gates)で実際に戦う時にも、
# 発見時と同じく「前置きの会話 → 戦闘画面 → 結末の会話」が再生されるか。勝てば突破の会話、負ければ失敗の会話。
# 勝ち目が無く戦わない日(その場で待機して鍛えている間など)は、毎日会話を出さない(無音のまま)。
# 会話・戦闘画面が開いている間は、HP・突破を動かさない(閉じた後に反映)。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree

var _frames := 0
var _completed := false
var _fails := 0
var _lines: Array = []
var _battles := 0

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		return false
	if _frames == 3:
		_run()
		if not _completed:
			print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
		else:
			print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
		return true
	return false

## 会話を読み切り、戦闘画面が開いたら閉じる(前置き→戦闘画面→結末、の順に全部進める)。
func _play_through() -> void:
	var dialogue = root.get_node("EventDialogue"); var battle = root.get_node("BattleScreen")
	for _round in 10:
		var guard := 0
		while dialogue.is_active and guard < 50:
			guard += 1
			dialogue.advance()
		if battle.is_active:
			battle.close()
		elif not dialogue.is_active:
			return

func _texts(events, floor_id: String, passed: bool) -> Array:
	return Array(events.gate_event(floor_id, passed).get("script", [])).map(func(line): return String(line.get("text", "")))

func _run() -> void:
	var world_map = root.get_node("WorldMap"); var parties = root.get_node("Parties"); var save = root.get_node("SaveSystem")
	var dialogue = root.get_node("EventDialogue"); var events = root.get_node("ScenarioEvents"); var settings = root.get_node("Settings")
	var exploration = root.get_node("Exploration"); var combat = root.get_node("Combat"); var npcs = root.get_node("Npcs")
	var battle = root.get_node("BattleScreen")
	dialogue.line_shown.connect(func(line: Dictionary): _lines.append(String(line.get("text", ""))))
	_play_through()
	settings.set_show_battle_screen(true)
	save.start_fresh_session()
	_play_through()
	var party: Dictionary = parties.get_parties()[0]
	var pid: int = party["id"]

	# 会話付きの戦闘ゲート(前置きと結末がある)を選ぶ
	var floor_id := ""
	for id in world_map.nodes.keys():
		var gate: Dictionary = world_map.nodes[id]["gate"]
		if gate.get("type", "") == "combat" and events.has_gate_event(id) and not _texts(events, id, true).is_empty() and not _texts(events, id, false).is_empty():
			floor_id = id
			break
	_check("前提: 会話付きの戦闘ゲートがある", floor_id != "", floor_id)
	var enemy_power: int = world_map.nodes[floor_id]["gate"]["enemy_power"]
	var section_id: String = world_map.nodes[floor_id]["section"]
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	for id in world_map.nodes_in_section(section_id):
		if id != floor_id:
			world_map.mark_passed(id, true)
	parties.assign_section(pid, section_id)
	party["post_clear_behavior"] = 0
	for id in party["member_ids"]:
		var npc = npcs.get_npc(id)
		npc["unique_skill"] = {}
		npc["max_hp"] = 100.0
		npc["hp"] = 100.0

	# 満タンなら勝てるLvを探し、HPを1にして「挑むが負ける」状態で初回を迎える
	var win_level := -1
	for level in range(1, 60):
		for id in party["member_ids"]:
			npcs.get_npc(id)["skills"][SkillTypes.Skill.COMBAT]["level"] = level
		if combat.predict_party_result(pid, enemy_power, true) == "victory":
			win_level = level
			break
	_check("前提: 満タンなら勝てるLvがある", win_level != -1, "Lv%d" % win_level)
	for id in party["member_ids"]:
		npcs.get_npc(id)["hp"] = 1.0
	_check("前提: HP1では負ける", combat.predict_party_result(pid, enemy_power) != "victory")

	print("=== 初回(発見時): 負ける ===")
	_lines.clear()
	exploration._on_node_found("斥候", party["member_ids"][0], party, floor_id, 1)
	_check("初回: 会話が開く", dialogue.is_active or battle.is_active)
	_play_through()
	_check("初回: 失敗の会話の結末が出た", _lines.has(_texts(events, floor_id, false).back()), str(_lines))
	_check("初回: 突破していない", not world_map.is_passed(floor_id))

	print("=== 回復を待って、日次の再挑戦: 勝つ ===")
	var passed_day := -1
	var event_day := -1
	var saw_pass_ending := false
	for day in range(2, 40):
		_lines.clear()
		exploration._on_day_advanced(day)
		var opened: bool = dialogue.is_active or battle.is_active
		if opened and event_day == -1:
			event_day = day
			_check("再挑戦: 会話(または戦闘画面)が開いている間は、まだ突破していない", not world_map.is_passed(floor_id))
		_play_through()
		if _lines.has(_texts(events, floor_id, true).back()):
			saw_pass_ending = true
		if world_map.is_passed(floor_id):
			passed_day = day
			break
	_check("再挑戦で突破した", passed_day != -1, "Day%d" % passed_day)
	_check("再挑戦の日に、バトルイベントが再生された", event_day == passed_day, "イベント=Day%d 突破=Day%d" % [event_day, passed_day])
	_check("突破の会話の結末が出た", saw_pass_ending)

	print("=== 勝ち目が無い間は、毎日会話を出さない ===")
	save.start_fresh_session()
	_play_through()
	party = parties.get_parties()[0]
	pid = party["id"]
	var hopeless_floor := ""
	for id in world_map.nodes.keys():
		var gate: Dictionary = world_map.nodes[id]["gate"]
		if gate.get("type", "") == "combat" and events.has_gate_event(id) and int(gate["enemy_power"]) > 500:
			hopeless_floor = id
			break
	section_id = world_map.nodes[hopeless_floor]["section"]
	for id in world_map.nodes.keys():
		world_map.nodes[id]["found"] = false
		world_map.nodes[id]["passed"] = false
	for id in world_map.nodes_in_section(section_id):
		if id != hopeless_floor:
			world_map.mark_passed(id, true)
	world_map.mark_found(hopeless_floor, true) # 既に発見済み(初回の会話は済んだ)として、日次の再挑戦だけを見る
	parties.assign_section(pid, section_id)
	var opened_days := 0
	for day in range(1, 11):
		exploration._on_day_advanced(day)
		if dialogue.is_active or battle.is_active:
			opened_days += 1
		_play_through()
	_check("勝ち目の無い相手には、日次の再挑戦で会話を出さない", opened_days == 0, "%d日" % opened_days)
	_completed = true
