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
# 注意: 将来ここからWorldMapを再構築するインポーターを書く場合、GodotのJSON.parse_stringは
# 数値を全てfloatで返すため、gate_jsonの"skill"/"min_level"/"enemy_power"はint()で
# 明示的に復元すること(save_system.gdで踏んだのと同じ罠。詳細はそちらのコメント参照)。

const DB_PATH := "user://worldseeker_world_schema.sqlite"

func _ready() -> void:
	export_snapshot()

func _ensure_schema(db: SQLite) -> void:
	db.query("CREATE TABLE IF NOT EXISTS items (item_id TEXT PRIMARY KEY, name TEXT)")
	db.query("CREATE TABLE IF NOT EXISTS areas (area_id TEXT PRIMARY KEY, name TEXT)")
	db.query("CREATE TABLE IF NOT EXISTS sections (section_id TEXT PRIMARY KEY, name TEXT, area_id TEXT)")
	db.query("""CREATE TABLE IF NOT EXISTS nodes (
		node_id TEXT PRIMARY KEY, name TEXT, section_id TEXT, gate_json TEXT, item_reward TEXT
	)""")
	db.query("CREATE TABLE IF NOT EXISTS connections (node_id TEXT, neighbor_id TEXT, PRIMARY KEY (node_id, neighbor_id))")
	db.query("CREATE TABLE IF NOT EXISTS event_scripts (node_id TEXT, outcome TEXT, script_json TEXT, PRIMARY KEY (node_id, outcome))")

func export_snapshot() -> void:
	var db := SQLite.new()
	db.path = DB_PATH
	if not db.open_db():
		return
	_ensure_schema(db)
	db.query("BEGIN TRANSACTION")
	for table in ["items", "areas", "sections", "nodes", "connections", "event_scripts"]:
		db.query("DELETE FROM %s" % table)

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
			"INSERT INTO nodes (node_id, name, section_id, gate_json, item_reward) VALUES (?, ?, ?, ?, ?)",
			[node_id, node["name"], node["section"], JSON.stringify(gate) if not gate.is_empty() else "", node["item_reward"]])
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
