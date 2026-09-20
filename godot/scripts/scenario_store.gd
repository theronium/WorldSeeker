class_name ScenarioStore
# シナリオ(フォルダ)の一覧・読み込み・書き出しと、JSONとゲーム内部の形の相互変換(docs/scenario_editor.md)。
# 状態は持たない(読み込んだ結果を世界へ流し込むのは world_schema_db.gd と scenario_events.gd)。
#
# 読み込みの結果(スナップショット)は、world_schema_db.gdがSQLiteへ書くのと同じ形のDictionary:
#   {"scenario": {id, source, name, description, author, start_year, start_month},
#    "items": [{id, name}], "areas": [{id, name}], "sections": [{id, name, area_id}],
#    "nodes": [{id, name, section_id, gate, item_reward, connections, initially_passed}],
#    "events": [イベント...], "cast": [{name, image, side}]}
# 並びが意味を持つもの(エリア・セクションの順など)を守るため、全て配列。ゲートのskillはゲート内部の形(SkillTypesの整数)。
# JSONのskillは名前("LOCKPICKING")で、encode_gate/decode_gateで相互に変換する。

const DEFAULT_ROOT := "res://scenarios"
const CUSTOM_ROOT := "user://scenarios"
const FORMAT := 1

static func root_for(source: String) -> String:
	return DEFAULT_ROOT if source == "default" else CUSTOM_ROOT

static func scenario_dir(id: String, source: String) -> String:
	return "%s/%s" % [root_for(source), id]

## 選べるシナリオの一覧: [{id, source("default"/"custom"), name, description}]。デフォルト→カスタムの順、各々id順。
static func list_scenarios() -> Array:
	var result := []
	for source in ["default", "custom"]:
		var root := root_for(source)
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		var ids := Array(dir.get_directories())
		ids.sort()
		for id in ids:
			var meta = read_json("%s/%s/scenario.json" % [root, id])
			if not (meta is Dictionary):
				continue
			result.append({
				"id": String(id), "source": source,
				"name": String(meta.get("name", id)), "description": String(meta.get("description", "")),
			})
	return result

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## 整形(インデント2、キー順は入れた順)して書く。Gitの差分が読めるようにするため。
static func write_json(path: String, data: Variant) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "  ", false) + "\n")
	file.close()
	return true

# --- ゲート(JSONのskill名 ⇔ 内部の整数) ---

static func encode_gate(gate: Dictionary) -> Dictionary:
	var out := gate.duplicate(true)
	if out.has("skill"):
		out["skill"] = String(SkillTypes.Skill.keys()[int(out["skill"])])
	return out

static func decode_gate(gate: Dictionary) -> Dictionary:
	var out := gate.duplicate(true)
	if out.has("skill"):
		out["skill"] = int(SkillTypes.Skill[String(out["skill"])])
	for key in ["min_level", "enemy_power"]:
		if out.has(key):
			out[key] = int(out[key])
	return out

# --- 読み込み ---

## シナリオのフォルダを読み、スナップショットを返す。読めなければ空のDictionary。
static func load_scenario(id: String, source: String) -> Dictionary:
	var dir := scenario_dir(id, source)
	var meta = read_json(dir + "/scenario.json")
	var world = read_json(dir + "/world.json")
	if not (meta is Dictionary) or not (world is Dictionary):
		return {}

	var snapshot := {
		"scenario": {
			"id": id, "source": source,
			"name": String(meta.get("name", id)), "description": String(meta.get("description", "")),
			"author": String(meta.get("author", "")),
			"start_year": int(meta.get("start_year", 0)), "start_month": int(meta.get("start_month", 1)),
		},
		"items": [], "areas": [], "sections": [], "nodes": [], "events": [], "cast": [],
	}
	for item in world.get("items", []):
		snapshot["items"].append({"id": String(item["id"]), "name": String(item["name"])})
	for area in world.get("areas", []):
		snapshot["areas"].append({"id": String(area["id"]), "name": String(area["name"])})
	for section in world.get("sections", []):
		snapshot["sections"].append({"id": String(section["id"]), "name": String(section["name"]), "area_id": String(section["area"])})
	for node in world.get("nodes", []):
		var connections := []
		for neighbor in node.get("connections", []):
			connections.append(String(neighbor))
		snapshot["nodes"].append({
			"id": String(node["id"]), "name": String(node["name"]), "section_id": String(node.get("section", "")),
			"gate": decode_gate(node.get("gate", {})), "item_reward": String(node.get("item_reward", "")),
			"connections": connections, "initially_passed": bool(node.get("initially_passed", false)),
		})

	var events := []
	var events_dir := DirAccess.open(dir + "/events")
	if events_dir != null:
		var files := Array(events_dir.get_files())
		files.sort()
		for file_name in files:
			if not String(file_name).ends_with(".json"):
				continue
			var raw = read_json("%s/events/%s" % [dir, file_name])
			if raw is Dictionary and raw.has("id"):
				events.append(normalize_event(raw))
	snapshot["events"] = sort_events(events)

	var cast = read_json(dir + "/cast.json")
	if cast is Array:
		for entry in cast:
			snapshot["cast"].append({
				"name": String(entry["name"]), "image": String(entry.get("image", "")), "side": String(entry.get("side", "left")),
			})
	return snapshot

## 優先度の高い順、同じなら id 順(条件イベントは1日に最優先の1本だけ再生するため、順序に意味がある)。
static func sort_events(events: Array) -> Array:
	var sorted := events.duplicate()
	sorted.sort_custom(func(a, b):
		if a["priority"] != b["priority"]:
			return a["priority"] > b["priority"]
		return String(a["id"]) < String(b["id"]))
	return sorted

## JSONの数値は全てfloatで返ってくる(GodotのJSONの仕様)ため、整数の項目をintへ直し、既定値を補う。
static func normalize_event(raw: Dictionary) -> Dictionary:
	var trigger: Dictionary = raw.get("trigger", {}).duplicate(true)
	var conditions := []
	for condition in raw.get("conditions", []):
		var c: Dictionary = condition.duplicate(true)
		if c.has("day"):
			c["day"] = int(c["day"])
		if c.has("value"):
			c["value"] = bool(c["value"])
		conditions.append(c)
	var effects := []
	for effect in raw.get("effects", []):
		var e: Dictionary = effect.duplicate(true)
		if e.has("amount"):
			e["amount"] = int(e["amount"])
		if e.has("value"):
			e["value"] = bool(e["value"])
		e["on"] = String(e.get("on", "*"))
		effects.append(e)
	return {
		"id": String(raw["id"]),
		"title": String(raw.get("title", raw["id"])),
		"trigger": trigger,
		"conditions": conditions,
		"repeat": bool(raw.get("repeat", false)),
		"priority": int(raw.get("priority", 0)),
		"kind": String(raw.get("kind", "auto")),
		"script": normalize_script(raw.get("script", [])),
		"effects": effects,
	}

static func normalize_script(script: Array) -> Array:
	var lines := []
	for raw_line in script:
		var line: Dictionary = raw_line.duplicate(true)
		if line.has("next"):
			line["next"] = int(line["next"])
		if line.has("choices"):
			for choice in line["choices"]:
				if choice.has("next"):
					choice["next"] = int(choice["next"])
		lines.append(line)
	return lines
