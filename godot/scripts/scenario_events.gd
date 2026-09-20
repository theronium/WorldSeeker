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

# --- 再生 ---

## イベントの会話を再生する(会話が終わったら、発生済みの記録と効果の適用を行い、最後にon_doneを呼ぶ)。
## 再生できなければfalse(on_doneは呼ばれない)。呼び出し側が、既に別の会話が開いていないことを確かめてから呼ぶこと
## (EventDialogue.play()は上書きする)。
func play(event: Dictionary, on_done: Callable = Callable()) -> bool:
	if event.is_empty() or event["script"].is_empty():
		return false
	var trigger: Dictionary = event["trigger"]
	var is_gate: bool = trigger.get("type", "") == "gate"
	var kind: String = event["kind"]
	if kind == "auto":
		kind = WorldMap.event_kind_for_node(String(trigger.get("floor", ""))) if is_gate else ""
	var result: String = String(trigger.get("result", "")) if is_gate else ""
	EventDialogue.finished.connect(func(outcome: String):
		_on_event_finished(event, outcome)
		if on_done.is_valid():
			on_done.call(), CONNECT_ONE_SHOT)
	EventDialogue.play(event["script"], kind, result)
	return true

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
					_post(day, "「%s」: %d資金を得た" % [event["title"], amount])
				else:
					var paid: int = min(-amount, Economy.funds) # 資金は0未満にならない
					Economy.spend(paid)
					_post(day, "「%s」: %d資金を失った" % [event["title"], paid])
			"grant_item":
				_grant_item(event, String(effect["item"]), day)
			"open_floor":
				var floor_id := String(effect["floor"])
				if WorldMap.nodes.has(floor_id) and not WorldMap.is_passed(floor_id):
					WorldMap.mark_passed(floor_id, true)
					_post(day, "「%s」: 「%s」への道が開いた" % [event["title"], WorldMap.nodes[floor_id]["name"]])

## そのアイテムをまだ持たない雇用探索者のうち、名簿の先頭の1人へ渡す。
func _grant_item(event: Dictionary, item_id: String, day: int) -> void:
	var ids: Array = Npcs.roster.keys()
	ids.sort()
	for npc_id in ids:
		if not Items.has_item(npc_id, item_id):
			Items.grant(npc_id, item_id)
			_post(day, "「%s」: %sが「%s」を手に入れた" % [event["title"], Npcs.get_npc(npc_id)["name"], Items.name_of(item_id)])
			return

func _post(day: int, text: String) -> void:
	Board.post(day, text, Board.Importance.MAJOR, "scenario_event")
	ActionLog.record(day, "scenario_event", text)
