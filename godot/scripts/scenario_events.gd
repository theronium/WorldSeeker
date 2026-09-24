extends Node
# シナリオのイベント(会話)の定義と、その進行状態(フラグ・発生済み)を扱う(docs/scenario_editor.md)。
#
# 定義(events/cast/info)はワールドのスナップショットの一部で、world_schema_db.gdのimport_into_worldmap()が
# load_definitions()で流し込む。進行状態(flags/fired)はセーブスロットごとに保存する(save_system.gd)。
#
# イベントの発生のしかたは3種類(trigger.type):
#   "gate"       フロアのゲート結果。exploration.gdが発見時にgate_event()で引いてplay()する
#   "conditions" conditionsが全て成り立った日に、check_daily()が再生する(1日に最優先の1本だけ)
#   "system"     ゲームの決まった場面(案内会話)。呼び出し側がsystem_event()で引いてplay()する
# 会話が終わると、発生済みに記録し、その結果コード(outcome)に合う効果(effects)を適用する。

## 会話を開いた直後に出る。画面(main.gd)が、イベントの起きた場所へマップの表示を移すために聞く(event_locationで場所を引く)。
## 効果「探索者が加入する」で探索者が加わった(main.gdが、探索者・パーティの一覧を更新する)
signal joined(npc_id: int)
signal event_started(event: Dictionary)

var info: Dictionary = {} # シナリオの基本情報(id, source, name, ...)
var events: Array = [] # 優先度の高い順
var cast: Dictionary = {} # 話者名 -> {"image", "side"}

var flags: Dictionary = {} # フラグ名 -> true(立っているものだけ持つ)
var fired: Dictionary = {} # イベントid -> {"count", "day"}

var _gate_events: Dictionary = {} # "floor|result" -> イベント
var _system_events: Dictionary = {} # 場面名 -> イベント
var _conditional_events: Array = []

## ワールドのスナップショット(world_schema_db.gd)から、イベント・登場人物表・シナリオ情報を読み込む。
## 進行状態(flags/fired)は触らない(セーブ側が決める)。
func load_definitions(new_events: Array, new_cast: Array, new_info: Dictionary) -> void:
	info = new_info
	events = new_events
	cast = {}
	for entry in new_cast:
		cast[String(entry["name"])] = {"image": String(entry["image"]), "side": String(entry["side"])}
	_gate_events = {}
	_system_events = {}
	_conditional_events = []
	for event in events:
		var trigger: Dictionary = event["trigger"]
		match trigger.get("type", ""):
			"gate":
				_gate_events["%s|%s" % [trigger.get("floor", ""), trigger.get("result", "")]] = event
			"system":
				_system_events[String(trigger.get("name", ""))] = event
			"conditions":
				_conditional_events.append(event)

## 新規プレイ用。フラグと発生済みを空に戻す。
func reset_progress() -> void:
	flags = {}
	fired = {}

func save_state() -> Dictionary:
	return {"flags": flags.keys(), "fired": fired}

func load_state(data: Dictionary) -> void:
	flags = {}
	for flag in data.get("flags", []):
		flags[String(flag)] = true
	fired = {}
	for event_id in data.get("fired", {}).keys():
		var record: Dictionary = data["fired"][event_id]
		fired[String(event_id)] = {"count": int(record["count"]), "day": int(record["day"])}

# --- 引く ---

func gate_event(floor_id: String, passed: bool) -> Dictionary:
	return _gate_events.get("%s|%s" % [floor_id, "pass" if passed else "fail"], {})

func has_gate_event(floor_id: String) -> bool:
	return _gate_events.has(floor_id + "|pass") or _gate_events.has(floor_id + "|fail")

func system_event(scene_name: String) -> Dictionary:
	return _system_events.get(scene_name, {})

## 話者名に割り当てた画像id(登場人物表)。表に無ければ空文字。
func cast_image(speaker_name: String) -> String:
	return cast.get(speaker_name, {}).get("image", "")

## イベントの種別("boss"/"combat"/"skill"/"item"/"bloodline"/"guide"/"")。event["kind"]が"auto"なら、
## ゲート結果のイベントはゲートの種類(WorldMap.event_kind_for_node)から決める(play()と、戦闘画面(main.gd)が
## 敵の画像を選ぶのに使う。両方が同じ決め方をするよう、ここへ1つにまとめてある)。
func resolved_kind(event: Dictionary) -> String:
	var kind: String = event.get("kind", "")
	if kind != "auto":
		return kind
	var trigger: Dictionary = event.get("trigger", {})
	return WorldMap.event_kind_for_node(String(trigger.get("floor", ""))) if trigger.get("type", "") == "gate" else ""

## 戦闘画面(main.gd)用: そのイベントの会話に登場する敵の名前。台本の最初の"right"側(敵側)の行の話者名。
## 見つからなければ空文字(戦闘の会話は必ず敵の登場行から始まる作りだが、念のため)。
func combat_opponent_name(event: Dictionary) -> String:
	for line in event.get("script", []):
		if line.get("side", "") == "right":
			return String(line.get("name", ""))
	return ""

# --- 再生 ---

## イベントの会話を再生する(会話が終わったら、発生済みの記録と効果の適用を行い、最後にon_doneを呼ぶ)。
## 再生できなければfalse(on_doneは呼ばれない)。呼び出し側が、既に別の会話が開いていないことを確かめてから呼ぶこと
## (EventDialogue.play()は上書きする)。
func play(event: Dictionary, on_done: Callable = Callable()) -> bool:
	if event.is_empty() or event["script"].is_empty():
		return false
	var trigger: Dictionary = event["trigger"]
	var is_gate: bool = trigger.get("type", "") == "gate"
	var kind: String = resolved_kind(event)
	var result: String = String(trigger.get("result", "")) if is_gate else ""
	EventDialogue.finished.connect(func(outcome: String):
		_on_event_finished(event, outcome)
		if on_done.is_valid():
			on_done.call(), CONNECT_ONE_SHOT)
	EventDialogue.play(event["script"], kind, result)
	event_started.emit(event) # 会話が開いた後に出す(画面は、会話ウィンドウに隠れない位置へマップを動かす)
	return true

## そのイベントが起きる場所(マップで見せたい場所)。{"area", "section", "floor"}を返す(分からないものは空文字)。
## フロアのゲート結果のイベントはそのフロア、条件のイベントは、条件に書かれた最初の場所(フロアの発見/突破・セクション/エリアへの
## 到達)。日数・フラグだけの条件や、案内会話には場所が無いので、空の辞書を返す。
func event_location(event: Dictionary) -> Dictionary:
	var trigger: Dictionary = event.get("trigger", {})
	var floor_id := ""
	var section_id := ""
	var area_id := ""
	match trigger.get("type", ""):
		"gate":
			floor_id = String(trigger.get("floor", ""))
		"conditions":
			for condition in event.get("conditions", []):
				match condition.get("type", ""):
					"floor_found", "floor_passed":
						floor_id = String(condition["floor"])
					"section_entered":
						section_id = String(condition["section"])
					"area_entered":
						area_id = String(condition["area"])
				if floor_id != "" or section_id != "" or area_id != "":
					break
	if floor_id != "":
		if not WorldMap.nodes.has(floor_id):
			return {}
		section_id = String(WorldMap.nodes[floor_id]["section"])
	if section_id != "":
		if not WorldMap.sections.has(section_id):
			return {}
		area_id = String(WorldMap.sections[section_id]["area"])
	if area_id == "" or not WorldMap.areas.has(area_id):
		return {}
	return {"area": area_id, "section": section_id, "floor": floor_id}

## 案内会話など、場面名で引いて再生する。そのシナリオに無ければ何もしない(falseを返す)。
func play_system(scene_name: String, on_done: Callable = Callable()) -> bool:
	return play(system_event(scene_name), on_done)

## 案内会話を再生し、最後まで進められたら「このシナリオでは見た」と記録する(SaveSystem.mark_tutorial_seen)。
## 見た/見ないの判定は、呼び出し側がSaveSystem.is_tutorial_seen()で先に行う(リセットボタンは、見たあとでも再生する)。
func play_guide(scene_name: String) -> bool:
	return play_system(scene_name, func(): SaveSystem.mark_tutorial_seen(scene_name))

func _on_event_finished(event: Dictionary, outcome: String) -> void:
	var record: Dictionary = fired.get(event["id"], {"count": 0, "day": 0})
	record["count"] += 1
	record["day"] = TimeSystem.current_day
	fired[event["id"]] = record
	apply_effects(event, outcome)

## 毎日の探索の最後に呼ぶ。条件が成り立った未発生のイベントのうち最優先の1本を再生する。
func check_daily(_day: int) -> void:
	if EventDialogue.is_active:
		return # 会話中は見送り、翌日また判定する
	for event in _conditional_events:
		if fired.has(event["id"]) and not event["repeat"]:
			continue
		if conditions_met(event["conditions"]):
			play(event)
			return

func conditions_met(conditions: Array) -> bool:
	for condition in conditions:
		match condition.get("type", ""):
			"day_min":
				if TimeSystem.current_day < int(condition["day"]):
					return false
			"flag":
				if flags.has(String(condition["flag"])) != bool(condition.get("value", true)):
					return false
			"floor_found":
				if not WorldMap.is_found(String(condition["floor"])):
					return false
			"floor_passed":
				if not WorldMap.is_passed(String(condition["floor"])):
					return false
			"section_entered":
				if not WorldMap.is_section_entered(String(condition["section"])):
					return false
			"area_entered":
				if not WorldMap.is_area_entered(String(condition["area"])):
					return false
			_:
				return false # 知らない条件は、満たされないものとして扱う
	return true

# --- 効果 ---

func apply_effects(event: Dictionary, outcome: String) -> void:
	var day: int = TimeSystem.current_day
	for effect in event["effects"]:
		var on: String = effect.get("on", "*")
		if on != "*" and on != outcome:
			continue
		match effect.get("type", ""):
			"set_flag":
				if bool(effect.get("value", true)):
					flags[String(effect["flag"])] = true
				else:
					flags.erase(String(effect["flag"]))
			"funds":
				var amount: int = int(effect["amount"])
				if amount >= 0:
					Economy.earn(amount)
					_post(day, "「%s」: %d資金を得た" % [event["title"], amount], "「%s」の一件で、%d資金が転がり込んだそうだ" % [event["title"], amount])
				else:
					var paid: int = min(-amount, Economy.funds) # 資金は0未満にならない
					Economy.spend(paid)
					_post(day, "「%s」: %d資金を失った" % [event["title"], paid], "「%s」の一件で、%d資金も失くしたんだとさ。災難だねえ" % [event["title"], paid])
			"grant_item":
				_grant_item(event, String(effect["item"]), day)
			"join":
				_join(event, effect, day)
			"open_floor":
				var floor_id := String(effect["floor"])
				if WorldMap.nodes.has(floor_id) and not WorldMap.is_passed(floor_id):
					WorldMap.mark_passed(floor_id, true)
					_post(day, "「%s」: 「%s」への道が開いた" % [event["title"], WorldMap.nodes[floor_id]["name"]],
						"「%s」への道が開けたらしいよ。「%s」の一件のおかげだってさ" % [WorldMap.nodes[floor_id]["name"], event["title"]])

## そのアイテムをまだ持たない雇用探索者のうち、名簿の先頭の1人へ渡す。
func _grant_item(event: Dictionary, item_id: String, day: int) -> void:
	var ids: Array = Npcs.roster.keys()
	ids.sort()
	for npc_id in ids:
		if not Items.has_item(npc_id, item_id):
			Items.grant(npc_id, item_id)
			_post(day, "「%s」: %sが「%s」を手に入れた" % [event["title"], Npcs.get_npc(npc_id)["name"], Items.name_of(item_id)],
				"%sが「%s」を手に入れたって噂だ。「%s」の一件でね" % [Npcs.get_npc(npc_id)["name"], Items.name_of(item_id), event["title"]])
			return

## textは行動ログ(報告調)、board_textは掲示板(噂話の口語調)の文。
## 効果「探索者が加入する」(2026-09-24)。シナリオに書いた名前・血筋・職業・肖像・初期スキルの探索者を、雇用上限を
## 超えても加入させる(物語上の加入なので、枠が空くのを待たない。上限を超えている間は、次の雇用ができないだけ)。
## 雇用と同じく、どのパーティにも入っていない状態で加わる。職業・スキルの名前はenumのキー(SAGE・WISDOMなど)。
## 知らない職業は戦士、知らないスキルは無視する(取り込み時の検査で弾くのは、必須のキーの有無と型まで)。
func _join(event: Dictionary, effect: Dictionary, day: int) -> void:
	var job_key := String(effect["job"])
	var job: int = int(Jobs.Job[job_key]) if Jobs.Job.has(job_key) else Jobs.Job.WARRIOR
	var skills := {}
	var skill_levels = effect.get("skills", {})
	if skill_levels is Dictionary:
		for key in skill_levels.keys():
			if SkillTypes.Skill.has(String(key)):
				skills[int(SkillTypes.Skill[String(key)])] = int(skill_levels[key])
	var bloodline := String(effect["bloodline"])
	var npc_name := String(effect["name"])
	# 探索者の肖像は、探索者用の画像(char_XX)だけ(res://assets/portraits/にあるもの)。それ以外・空なら、血筋から選ぶ
	var portrait := String(effect.get("portrait", ""))
	if not portrait.begins_with("char_") or not ResourceLoader.exists(PortraitLibrary.texture_path(portrait)):
		portrait = ""
	var npc_id: int = Npcs.hire(npc_name, {"bloodline": bloodline}, skills, job, portrait)
	_post(day, "「%s」: %s(%s・%s)が仲間に加わった" % [event["title"], npc_name, bloodline, Jobs.JOB_NAMES.get(job, "")],
		"%sって人が、探索者の一団に加わったらしいよ。%sだって噂だ" % [npc_name, bloodline])
	joined.emit(npc_id)

func _post(day: int, text: String, board_text: String) -> void:
	Board.post(day, board_text, Board.Importance.MAJOR, "scenario_event", Board.Scope.WORLD)
	ActionLog.record(day, "scenario_event", text)
