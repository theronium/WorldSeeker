# 使い捨ての確認用スクリプト(2026-09-21)。シナリオ・イベントの仕組み(docs/scenario_editor.md)を通しで確認する:
#   カスタムシナリオの作成→新規開始(暦の起点)→条件イベント(日数・フラグ)→効果(資金・フラグ・フロア開放)→
#   ゲート結果のイベント(発見時)→セーブ/ロードの往復→別シナリオへの切替→シナリオを後から編集しても古いスロットは
#   遊び始めた時点のままか→旧形式のスキーマ(events表なし)の読み込み。
# 必ずAPPDATAを隔離して実行する(セーブ用のスロットとカスタムシナリオを作る)。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
extends SceneTree

var _ran := false
var _completed := false # _run()が最後まで走ったか(途中でスクリプトエラーが出ても、失敗0件で「成功」と出ないようにする)
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

func _cfg_value(path: String, section: String, key: String) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg.get_value(section, key, false)

func _finish_dialogue(choice_index: int = 0) -> void:
	var dialogue = root.get_node("EventDialogue")
	var guard := 0
	while dialogue.is_active and guard < 30:
		guard += 1
		var line: Dictionary = dialogue._script[dialogue._index]
		if not line.get("choices", []).is_empty():
			dialogue.choose(choice_index)
		else:
			dialogue.advance()

func _write_custom_scenario(scenario_name: String) -> void:
	var dir := "user://scenarios/test_custom"
	ScenarioStore.write_json(dir + "/scenario.json", {"format": 1, "id": "test_custom", "name": scenario_name, "description": "確認用", "author": "", "start_year": 3, "start_month": 4})
	ScenarioStore.write_json(dir + "/world.json", {
		"items": [{"id": "key_a", "name": "鍵A"}],
		"areas": [{"id": "a1", "name": "試験エリア"}],
		"sections": [{"id": "s1", "name": "試験セクション", "area": "a1"}],
		"nodes": [
			{"id": "start", "name": "出発点", "section": "s1", "connections": ["gate_a"], "gate": {}, "item_reward": "", "initially_passed": true},
			{"id": "gate_a", "name": "試験の間", "section": "s1", "connections": ["start", "sealed"], "gate": {}, "item_reward": "", "initially_passed": false},
			{"id": "sealed", "name": "封印の間", "section": "s1", "connections": ["gate_a"], "gate": {"type": "combat", "enemy_power": 99999}, "item_reward": "", "initially_passed": false},
		],
	})
	ScenarioStore.write_json(dir + "/cast.json", [{"name": "試験官", "image": "@tester.png", "side": "left"}])
	var events := {
		"intro_day2": {
			"id": "intro_day2", "title": "二日目の来訪者", "trigger": {"type": "conditions"},
			"conditions": [{"type": "day_min", "day": 2}], "repeat": false, "priority": 0, "kind": "",
			"script": [{"side": "left", "name": "試験官", "text": "こんにちは", "next": 1}, {"side": "none", "name": "", "text": "贈り物を受け取った", "outcome": "ok"}],
			"effects": [{"on": "*", "type": "funds", "amount": 100}, {"on": "*", "type": "set_flag", "flag": "met_tester", "value": true}],
		},
		"follow_up": {
			"id": "follow_up", "title": "試験官の頼み", "trigger": {"type": "conditions"},
			"conditions": [{"type": "flag", "flag": "met_tester", "value": true}, {"type": "floor_passed", "floor": "start"}], "repeat": false, "priority": 0, "kind": "guide",
			"script": [{"side": "left", "name": "試験官", "text": "封印を解こうか?", "choices": [{"label": "頼む", "outcome": "help"}, {"label": "断る", "outcome": "refuse"}]}],
			"effects": [{"on": "help", "type": "open_floor", "floor": "sealed"}, {"on": "refuse", "type": "set_flag", "flag": "refused", "value": true}],
		},
		"guide_intro_part1": {
			"id": "guide_intro_part1", "title": "自作の導入", "trigger": {"type": "system", "name": "intro_part1"},
			"conditions": [], "repeat": false, "priority": 0, "kind": "guide",
			"script": [{"side": "left", "name": "試験官", "text": "ようこそ、試験の世界へ", "outcome": "ok"}],
			"effects": [{"on": "ok", "type": "set_flag", "flag": "intro_done", "value": true}],
		},
		"gate_a_pass": {
			"id": "gate_a_pass", "title": "試験の間(突破)", "trigger": {"type": "gate", "floor": "gate_a", "result": "pass"},
			"conditions": [], "repeat": false, "priority": 0, "kind": "auto",
			"script": [{"side": "none", "name": "試験の間", "text": "扉が開いた", "outcome": "pass"}],
			"effects": [{"on": "pass", "type": "set_flag", "flag": "gate_a_done", "value": true}],
		},
	}
	for id in events.keys():
		ScenarioStore.write_json("%s/events/%s.json" % [dir, id], events[id])

func _run() -> void:
	var save = root.get_node("SaveSystem"); var scenario = root.get_node("ScenarioEvents"); var world_map = root.get_node("WorldMap")
	var time_system = root.get_node("TimeSystem"); var economy = root.get_node("Economy"); var dialogue = root.get_node("EventDialogue")
	var exploration = root.get_node("Exploration"); var schema = root.get_node("WorldSchemaDb"); var parties = root.get_node("Parties")
	# EventPortraitsはオートロードを参照するので、--scriptのコンパイル時には直接書けない(実行時にloadする)
	var portraits = load("res://scripts/event_portraits.gd")

	# --- 起動時のデフォルトシナリオ ---
	_check("起動時: デフォルトシナリオを読み込んだ", scenario.info.get("id", "") == "default" and world_map.nodes.size() == 196, str(world_map.nodes.size()))
	_check("起動時: 会話172本(案内4含む)", scenario.events.size() == 172, str(scenario.events.size()))
	_check("起動時: 案内会話(intro_part1)が引ける", not scenario.system_event("intro_part1").is_empty())
	_check("起動時: 登場人物表(案内人=npc_01)", scenario.cast_image("案内人") == "npc_01")
	_check("起動時: 1つ目のフロアは初期突破済み", world_map.is_passed("village"))

	# --- カスタムシナリオを作って新規開始 ---
	_write_custom_scenario("試験シナリオ")
	_check("一覧にカスタムが出る", ScenarioStore.list_scenarios().any(func(s): return s["id"] == "test_custom" and s["source"] == "custom"))
	var slot: int = save.create_new_slot("試験", "test_custom", "custom")
	_check("新規開始: 世界が入れ替わった", world_map.nodes.size() == 3 and world_map.areas.size() == 1, str(world_map.nodes.size()))
	_check("新規開始: シナリオ情報", scenario.info.get("name", "") == "試験シナリオ" and scenario.info.get("source", "") == "custom")
	_check("新規開始: 暦の起点(3年4月)", time_system.format_date() == "3年4月1日", time_system.format_date())
	_check("新規開始: フラグは空", scenario.flags.is_empty() and scenario.fired.is_empty())

	# --- 案内会話(導入)の「見た」記録は、シナリオごと ---
	_check("導入: 自作シナリオではまだ見ていない", not save.is_tutorial_seen("intro_part1"))
	_check("導入: 自作の導入会話を再生できる", scenario.play_guide("intro_part1") and dialogue.is_active and dialogue.current_kind == "guide")
	_check("導入: 会話が終わるまでは、見た記録が付かない", not save.is_tutorial_seen("intro_part1"))
	_finish_dialogue()
	_check("導入: 最後まで進めると見た記録が付き、効果(フラグ)も働く", save.is_tutorial_seen("intro_part1") and scenario.flags.has("intro_done"))
	scenario.reset_progress()

	# --- 画像(ライブラリの画像と、シナリオ固有のPNG) ---
	var png := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	png.fill(Color(1, 0, 0))
	DirAccess.make_dir_recursive_absolute("user://scenarios/test_custom/images")
	png.save_png("user://scenarios/test_custom/images/tester.png")
	_check("画像: ライブラリのid(npc_01)を読める", portraits.load_texture("npc_01") != null)
	_check("画像: シナリオ固有の画像(@tester.png)を読める", portraits.load_texture("@tester.png") != null)
	_check("画像: 無い画像・不正な名前はnull", portraits.load_texture("@missing.png") == null and portraits.load_texture("@../x.png") == null and portraits.load_texture("") == null)
	_check("画像: 登場人物表(試験官=@tester.png)が優先される", portraits.portrait_id("試験官", "") == "@tester.png" and portraits.portrait_id("知らない人", "boss").begins_with("enemy_"))

	# --- 条件イベント ---
	var funds_before: int = economy.funds
	time_system._advance_day() # 1日目
	_check("1日目: まだ会話は出ない", not dialogue.is_active)
	time_system._advance_day() # 2日目
	_check("2日目: 日数条件のイベントが始まる", dialogue.is_active and dialogue.current_kind == "", str(dialogue.is_active))
	_finish_dialogue()
	_check("効果: 資金+100", economy.funds == funds_before + 100, "%d -> %d" % [funds_before, economy.funds])
	_check("効果: フラグmet_testerが立つ", scenario.flags.has("met_tester"))
	_check("発生済みに記録", scenario.fired.has("intro_day2") and scenario.fired["intro_day2"]["count"] == 1)
	time_system._advance_day() # 3日目: フラグ条件のイベント
	_check("3日目: フラグ条件のイベントが始まる(kind=guide)", dialogue.is_active and dialogue.current_kind == "guide")
	_finish_dialogue(0) # 「頼む」
	_check("選択肢の効果: 封印の間が開く", world_map.is_passed("sealed"))
	_check("選択肢の効果: 断る側のフラグは立たない", not scenario.flags.has("refused"))
	time_system._advance_day()
	_check("4日目: 済んだイベントは繰り返さない", not dialogue.is_active)
	_check("掲示板に効果が載る", root.get_node("Board").entries.any(func(e): return "二日目の来訪者" in e["text"]))

	# --- ゲート結果のイベント(発見時) ---
	var party: Dictionary = parties.get_parties()[0]
	# それまでの日次の処理で、野良の旅人が先にgate_a(ゲート無し)を発見・突破していることがある(乱数。約4回に1回)。
	# ここでは「まだ誰も来ていないフロアを、雇用パーティが見つけた」場面を確かめたいので、未発見に戻してから呼ぶ。
	world_map.nodes["gate_a"]["found"] = false
	world_map.nodes["gate_a"]["passed"] = false
	exploration._on_node_found("誰か", party["member_ids"][0], party, "gate_a", time_system.current_day)
	_check("発見: ゲート結果(突破)のイベントが始まる", dialogue.is_active and dialogue.current_result == "pass" and dialogue.current_kind == "", "%s/%s" % [dialogue.current_kind, dialogue.current_result])
	_check("発見: 会話が終わる前は未突破", not world_map.is_passed("gate_a"))
	_finish_dialogue()
	_check("発見: 会話の結果(pass)で突破が確定", world_map.is_passed("gate_a"))
	_check("発見: ゲートイベントの効果(フラグ)", scenario.flags.has("gate_a_done"))

	# --- セーブ/ロードの往復 ---
	save.save_game()
	scenario.reset_progress()
	world_map.reset()
	schema.import_into_worldmap(schema.active_version_id)
	save.load_game()
	_check("往復: フラグが戻る", scenario.flags.has("met_tester") and scenario.flags.has("gate_a_done") and not scenario.flags.has("refused"))
	_check("往復: 発生済みが戻る", scenario.fired.has("follow_up") and scenario.fired["intro_day2"]["count"] == 1)
	_check("往復: 暦の起点が戻る", time_system.format_date().begins_with("3年4月"), time_system.format_date())
	var slot_info = save.list_slots().filter(func(s): return s["slot_id"] == slot)[0]
	_check("スロット一覧: シナリオ名", slot_info["scenario_name"] == "試験シナリオ", slot_info["scenario_name"])

	# --- 別のシナリオへ切替 → 元のスロットへ戻る ---
	var other_slot: int = save.create_new_slot("標準", "default", "default")
	_check("導入: デフォルトシナリオの記録は、自作のものと別(自作を見ても、デフォルトは見ていない扱い)", not save.is_tutorial_seen("intro_part1"))
	save.mark_tutorial_seen("intro_part1")
	_check("導入: デフォルトの記録は従来のキー(state/tutorial_intro_seen)に付く", ConfigFile.new().load(save.META_PATH) == OK and bool(_cfg_value(save.META_PATH, "state", "tutorial_intro_seen")))
	save.reset_tutorial_flags()
	_check("導入: リセットは今のシナリオだけ(デフォルトは未視聴に戻り、自作の記録は残る)", not save.is_tutorial_seen("intro_part1") and bool(_cfg_value(save.META_PATH, "tutorial_seen.custom.test_custom", "intro_part1")))
	_check("別シナリオ: デフォルトの世界(196)、フラグは空、暦は0年1月", world_map.nodes.size() == 196 and scenario.flags.is_empty() and time_system.format_date() == "0年1月1日", "%d %s" % [world_map.nodes.size(), time_system.format_date()])
	# シナリオを後から編集する(名前と、条件イベントの本数)
	_write_custom_scenario("試験シナリオ(編集後)")
	ScenarioStore.write_json("user://scenarios/test_custom/events/extra.json", {"id": "extra", "trigger": {"type": "conditions"}, "conditions": [], "script": [{"side": "none", "name": "", "text": "追加", "outcome": "ok"}]})
	save.switch_to_slot(slot)
	_check("スロット切替: 遊び始めた時点の世界のまま(編集は反映されない)", scenario.info.get("name", "") == "試験シナリオ" and world_map.nodes.size() == 3 and not scenario.events.any(func(e): return e["id"] == "extra"), scenario.info.get("name", ""))
	_check("スロット切替: フラグも戻る", scenario.flags.has("met_tester"))
	# 新規開始すると、編集後の最新の内容になる
	save.create_new_slot("編集後", "test_custom", "custom")
	_check("新規開始: 編集後の最新の内容", scenario.info.get("name", "") == "試験シナリオ(編集後)" and scenario.events.any(func(e): return e["id"] == "extra"))

	# --- 旧形式のスキーマ(events表なし)の読み込み ---
	save.create_new_slot("標準に戻す", "default", "default")
	var legacy_id := "legacy_test_version"
	var db := SQLite.new()
	DirAccess.copy_absolute(schema.version_file_path(schema.current_version_id), schema.version_file_path(legacy_id))
	db.path = schema.version_file_path(legacy_id)
	db.open_db()
	db.query("DROP TABLE events"); db.query("DROP TABLE cast"); db.query("DROP TABLE scenario_info")
	db.query("CREATE TABLE event_scripts (node_id TEXT, outcome TEXT, script_json TEXT, PRIMARY KEY (node_id, outcome))")
	db.query_with_bindings("INSERT INTO event_scripts (node_id, outcome, script_json) VALUES (?, ?, ?)", ["old_shrine", "pass", JSON.stringify([{"side": "none", "name": "古い祠", "text": "旧形式", "outcome": "pass"}])])
	db.close_db()
	schema.import_into_worldmap(legacy_id)
	var legacy_event: Dictionary = scenario.gate_event("old_shrine", true)
	_check("旧形式: 突破用の台本からgateイベントが起こる", legacy_event.get("id", "") == "floor_old_shrine_pass" and legacy_event["script"][0]["text"] == "旧形式", str(legacy_event.get("id", "")))
	_check("旧形式: 台本の無い側は空", scenario.gate_event("old_shrine", false).is_empty())
	_check("旧形式: 登場人物表はデフォルトのものを使う", scenario.cast_image("案内人") == "npc_01" and scenario.info.get("id", "") == "default")
	_check("旧形式: 世界は同じ", world_map.nodes.size() == 196 and world_map.areas.keys()[0] == "kingdom")

	_measure_load_time()
	_completed = true

	# 後片付け(隔離したAPPDATAの中だが、念のため)
	for id in ["test_custom"]:
		DirAccess.remove_absolute("user://scenarios/%s" % id)

## 読み込みの所要時間(起動のたびに、デフォルトシナリオのJSON170本+世界を読んで、スナップショットを書く)。Androidは数倍遅い想定。
func _measure_load_time() -> void:
	var t0 := Time.get_ticks_msec()
	var snapshot := ScenarioStore.load_scenario("default", "default")
	var t1 := Time.get_ticks_msec()
	var version_id: String = JSON.stringify(snapshot).sha256_text()
	var t2 := Time.get_ticks_msec()
	print("所要時間: JSON読み込み=%dms ハッシュ=%dms(イベント%d本)" % [t1 - t0, t2 - t1, snapshot["events"].size()])
