extends Node
# world_data.gdが構築したWorldMap/Itemsの内容を、起動のたびにSQLiteへスナップショットとして
# 書き出す(design.md 8.1「DBに格納」/8.2「スキーマ再プレイ」)。
#
# world_data.gdが引き続き正本(コンテンツはGDScriptの add_area/add_section/add_node/
# set_event_scripts で書き続ける)で、このDBは「起動のたびに再生成される、生成済みの
# スナップショット」という位置づけ。保存進行状態(save_system.gd)とはライフサイクルが
# 異なる(世界の中身は毎回world_data.gdから作り直すが、進行状態はプレイ間で引き継ぐ)ため、
# あえて別のSQLiteファイルに分けている。
#
# ゲート条件(gate)とイベント台本(event_script_*)は種類によって形が変わる可変構造なので、
# 無理に正規化せずJSON列として保存する(design.md 11章のスキーマ検討に合わせた判断)。
# それ以外のエリア/セクション/ノード/接続は素直に正規化したテーブルに分けている。
#
# 注意: gate_json/script_jsonの復元(import_into_worldmap)では、GodotのJSON.parse_stringが
# 数値を全てfloatで返すため、gate_jsonの"skill"/"min_level"/"enemy_power"はint()で
# 明示的に復元している(save_system.gdで踏んだのと同じ罠。詳細はそちらのコメント参照)。
#
# initially_passed列: 「発見済みだが進めない」等ではなく最初から突破済み扱いのノード
# (village/forest_edgeなど、world_data.gdが起動直後にmark_passed()するスタート地点)を
# スキーマの一部として記録する。export_snapshot()は必ずWorldData._ready()の直後・
# SaveSystem.load_game()より前に実行される(project.godotのautoload順)ため、実プレイの
# 進行状況(発見/突破)が混ざらず、常に「まっさらな初期状態」だけを捉えられる。
# import_into_worldmap()は新規プレイ開始(複数セーブスロット)でこの列を使い、
# スタート地点だけを突破済みとして復元する。

const DB_PATH := "user://worldseeker_world_schema.sqlite"

func _ready() -> void:
	export_snapshot()

## export_snapshot()は起動のたびに全データを作り直す(過去の内容を引き継がない)ので、
## テーブル定義自体もDROP→CREATEで毎回作り直す。こうしておけば、開発中にこのファイルの
## カラム構成を変更しても、古いuser://ファイルを手動で消さずに済む(自己修復する)。
func _ensure_schema(db: SQLite) -> void:
	db.query("DROP TABLE IF EXISTS items")
	db.query("CREATE TABLE items (item_id TEXT PRIMARY KEY, name TEXT)")
	db.query("DROP TABLE IF EXISTS areas")
	db.query("CREATE TABLE areas (area_id TEXT PRIMARY KEY, name TEXT)")
	db.query("DROP TABLE IF EXISTS sections")
	db.query("CREATE TABLE sections (section_id TEXT PRIMARY KEY, name TEXT, area_id TEXT)")
	db.query("DROP TABLE IF EXISTS nodes")
	db.query("""CREATE TABLE nodes (
		node_id TEXT PRIMARY KEY, name TEXT, section_id TEXT, gate_json TEXT, item_reward TEXT, initially_passed INTEGER
	)""")
	db.query("DROP TABLE IF EXISTS connections")
	db.query("CREATE TABLE connections (node_id TEXT, neighbor_id TEXT, PRIMARY KEY (node_id, neighbor_id))")
	db.query("DROP TABLE IF EXISTS event_scripts")
	db.query("CREATE TABLE event_scripts (node_id TEXT, outcome TEXT, script_json TEXT, PRIMARY KEY (node_id, outcome))")

func export_snapshot() -> void:
	var db := SQLite.new()
	db.path = DB_PATH
	if not db.open_db():
		return
	_ensure_schema(db) # DROP→CREATEなので、この時点で全テーブルは既に空
	db.query("BEGIN TRANSACTION")

	for item_id in Items.definitions.keys():
		db.query_with_bindings("INSERT INTO items (item_id, name) VALUES (?, ?)", [item_id, Items.definitions[item_id]["name"]])

	for area_id in WorldMap.areas.keys():
		db.query_with_bindings("INSERT INTO areas (area_id, name) VALUES (?, ?)", [area_id, WorldMap.areas[area_id]["name"]])

	for section_id in WorldMap.sections.keys():
		var section: Dictionary = WorldMap.sections[section_id]
		db.query_with_bindings("INSERT INTO sections (section_id, name, area_id) VALUES (?, ?, ?)",
			[section_id, section["name"], section["area"]])

	for node_id in WorldMap.nodes.keys():
		var node: Dictionary = WorldMap.nodes[node_id]
		var gate: Dictionary = node["gate"]
		db.query_with_bindings(
			"INSERT INTO nodes (node_id, name, section_id, gate_json, item_reward, initially_passed) VALUES (?, ?, ?, ?, ?, ?)",
			[node_id, node["name"], node["section"], JSON.stringify(gate) if not gate.is_empty() else "", node["item_reward"],
				1 if node["passed"] else 0])
		for neighbor_id in node["connections"]:
			db.query_with_bindings("INSERT INTO connections (node_id, neighbor_id) VALUES (?, ?)", [node_id, neighbor_id])
		if not node["event_script_pass"].is_empty():
			db.query_with_bindings("INSERT INTO event_scripts (node_id, outcome, script_json) VALUES (?, 'pass', ?)",
				[node_id, JSON.stringify(node["event_script_pass"])])
		if not node["event_script_fail"].is_empty():
			db.query_with_bindings("INSERT INTO event_scripts (node_id, outcome, script_json) VALUES (?, 'fail', ?)",
				[node_id, JSON.stringify(node["event_script_fail"])])

	db.query("COMMIT")
	db.close_db()

## スキーマDBの内容からWorldMap/Itemsを(再)構築する。新規プレイ開始(save_system.gd)で使う。
## world_data.gdが呼ぶのと同じWorldMapの公開メソッド(add_area等)経由で組み立てるため、
## GDScript直書きの経路とDB経由の経路が常に同じ形のWorldMapに収束する。
func import_into_worldmap() -> void:
	var db := SQLite.new()
	db.path = DB_PATH
	if not db.open_db():
		return

	db.query("SELECT * FROM items")
	for row in db.query_result:
		Items.define(String(row["item_id"]), String(row["name"]))

	db.query("SELECT * FROM areas")
	for row in db.query_result:
		WorldMap.add_area(String(row["area_id"]), String(row["name"]))

	db.query("SELECT * FROM sections")
	for row in db.query_result:
		WorldMap.add_section(String(row["section_id"]), String(row["name"]), String(row["area_id"]))

	var connections_by_node := {}
	db.query("SELECT * FROM connections")
	for row in db.query_result:
		var node_id: String = String(row["node_id"])
		if not connections_by_node.has(node_id):
			connections_by_node[node_id] = []
		connections_by_node[node_id].append(String(row["neighbor_id"]))

	var passed_nodes := []
	db.query("SELECT * FROM nodes")
	for row in db.query_result:
		var node_id: String = String(row["node_id"])
		var gate_json: String = String(row["gate_json"])
		var gate: Dictionary = _decode_gate(gate_json) if gate_json != "" else {}
		WorldMap.add_node(node_id, String(row["name"]), connections_by_node.get(node_id, []), gate,
			String(row["section_id"]), String(row["item_reward"]))
		if bool(row["initially_passed"]):
			passed_nodes.append(node_id)

	var scripts_by_node := {}
	db.query("SELECT * FROM event_scripts")
	for row in db.query_result:
		var node_id: String = String(row["node_id"])
		if not scripts_by_node.has(node_id):
			scripts_by_node[node_id] = {"pass": [], "fail": []}
		scripts_by_node[node_id][String(row["outcome"])] = JSON.parse_string(String(row["script_json"]))
	for node_id in scripts_by_node.keys():
		WorldMap.set_event_scripts(node_id, scripts_by_node[node_id]["pass"], scripts_by_node[node_id]["fail"])

	for node_id in passed_nodes:
		WorldMap.mark_passed(node_id)

	db.close_db()

func _decode_gate(gate_json: String) -> Dictionary:
	var gate: Dictionary = JSON.parse_string(gate_json)
	for key in ["skill", "min_level", "enemy_power"]:
		if gate.has(key):
			gate[key] = int(gate[key])
	return gate
