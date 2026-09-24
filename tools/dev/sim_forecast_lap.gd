# 使い捨ての確認用スクリプト(2026-09-24)。指摘「予測がループ回数分を掛けていない」への対応の確認。
# 完全攻略済み(周回する)セクションの「予測」(Exploration.forecast_section、main.gdの_forecast_text)が、1周の単価×月内の
# 周回数になっていて、実際に30日動かした周回収入とほぼ一致するか。未攻略のセクションは従来どおり月次収入の式で、周回の注記が出ないこと。
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

func _drain() -> void:
	var dialogue = root.get_node("EventDialogue"); var battle = root.get_node("BattleScreen")
	for _i in 5:
		var guard := 0
		while dialogue.is_active and guard < 50:
			guard += 1
			dialogue.advance()
		if battle.is_active:
			battle.close()

func _run() -> void:
	var save = root.get_node("SaveSystem"); var world_map = root.get_node("WorldMap"); var parties = root.get_node("Parties")
	var exploration = root.get_node("Exploration"); var board = root.get_node("Board"); var time_system = root.get_node("TimeSystem")
	_drain()
	save.start_fresh_session()
	_drain()
	var party: Dictionary = parties.get_parties()[0]
	var pid: int = party["id"]
	var section: String = world_map.first_section()
	for id in world_map.nodes_in_section(section):
		world_map.mark_passed(id, true)
	world_map.mark_section_reward_claimed(section) # 攻略報酬は数えない(周回収入だけを見る)
	parties.assign_section(pid, section)
	party["post_clear_behavior"] = 0 # ループ(先へ進まない)
	_check("前提: 完全攻略済み", world_map.is_section_cleared(section))

	var result: Dictionary = exploration.forecast_section(pid, section)
	var floors: int = world_map.nodes_in_section(section).size()
	print("  予測: ", result)
	print("  文面: ", _main._forecast_text(pid, section))
	_check("1周の日数 = フロア数", int(result["lap_days"]) == floors, "%d / %d" % [result["lap_days"], floors])
	_check("周回数 = 30 ÷ 1周の日数", is_equal_approx(float(result["laps"]), 30.0 / floors), str(result["laps"]))
	_check("予測 = 単価 × 周回数", int(result["base_income"]) == int(round(int(result["lap_income"]) * float(result["laps"]))))
	_check("周回数が1より多いなら、予測は単価より大きい(以前は単価1回分だった)", float(result["laps"]) <= 1.0 or int(result["predicted_income"]) > int(result["lap_income"]))
	var text: String = _main._forecast_text(pid, section)
	_check("文面に「1周N日でX資金 × 約Y周」が入る", text.contains("1周%d日で%d資金" % [floors, result["lap_income"]]) and text.contains("周)"), text)

	# 実際に30日動かして、周回収入の合計と比べる
	board.reset()
	for day in range(1, 31):
		time_system.current_day = day
		exploration._on_day_advanced(day)
		_drain()
	var earned := 0
	var laps := 0
	for thread in board.threads.values():
		for entry in thread["entries"]:
			if entry["source"] == "lap_income":
				laps += 1
	earned = laps * int(result["lap_income"])
	print("  実際: %d周 %d資金" % [laps, earned])
	_check("実際の周回数は、予測の周回数と1周以内の差", absf(laps - float(result["laps"])) <= 1.0, "%d周 / 予測%.1f周" % [laps, result["laps"]])

	# 未攻略のセクションは、従来どおり(周回の注記なし)
	var other: String = world_map.sections_in_area(world_map.areas.keys()[0])[1]
	var other_result: Dictionary = exploration.forecast_section(pid, other)
	_check("未攻略のセクションは周回しない扱い(lap_days=0)", not world_map.is_section_cleared(other) and int(other_result["lap_days"]) == 0)
	_check("未攻略のセクションの文面に、周回の注記は出ない", not _main._forecast_text(pid, other).contains("周回"), _main._forecast_text(pid, other))
	_completed = true
