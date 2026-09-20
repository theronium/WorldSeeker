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
# 複数バージョン管理: world_data.gdの内容から作った正規化JSONのSHA-256をバージョンID
# (schema_version)とし、`user://schemas/schema_<version_id>.sqlite`にバージョンごとに
# 別ファイルとして保存する(design.md 8.2「スキーマ再プレイ」/11章)。内容が実際に変わった
# 時だけ新しいバージョンファイルが増え、変わっていなければ起動のたびに書き直すことはしない
# (同じ内容なら同じハッシュ=同じファイルなので、存在チェックだけで済む)。
#
# `current_version_id`は「今起動しているworld_data.gdの内容が生成するバージョン」、
# `active_version_id`は「今WorldMapに実際に読み込まれているバージョン」で、常に一致すると
# は限らない(古いセーブスロットを開くと、そのスロットが生成された時点のバージョンを
# import_into_worldmap()で読み込み直すため)。save_system.gdはセーブのたびにactive_version_id
# をそのスロットのmetaテーブルへ記録し、次回そのスロットを開く時に同じバージョンを再現する。
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
# スキーマの一部として記録する。このファイルの`_ready()`は必ずWorldData._ready()の直後・
# SaveSystem.load_game()より前に実行される(project.godotのautoload順)ため、実プレイの
# 進行状況(発見/突破)が混ざらず、常に「まっさらな初期状態」だけを捉えられる。

const SCHEMA_DIR := "user://schemas"

var current_version_id: String = "" # 今のworld_data.gdの内容が生成するバージョン
var active_version_id: String = "" # 今WorldMapに実際に読み込まれているバージョン

func _ready() -> void:
	var snapshot := _build_snapshot_dict()
	current_version_id = _compute_version_id(snapshot)
	active_version_id = current_version_id
	# 「今のworld_data.gdが生成する内容」に対応するファイルは、既に存在するかに関わらず
	# 毎回書き直す(DROP→CREATEで自己修復もする、後述)。過去バージョン(別ハッシュ=別ファイル)
	# は元になったworld_data.gdの内容がもう手元にないため、書き直しようがなく触らない。
	_write_snapshot(current_version_id, snapshot)

func _version_path(version_id: String) -> String:
	return "%s/schema_%s.sqlite" % [SCHEMA_DIR, version_id]

## 指定バージョンのスキーマファイルのパス。セーブのエクスポート/インポート(save_system.gd)が、
## スロットが使っているバージョンをzipに同梱したり、この端末に無いバージョンを取り込んだりするために公開している。
func version_file_path(version_id: String) -> String:
	return _version_path(version_id)

## WorldMap/Itemsの現在の内容を、DB書き込み用のプレーンなDictionaryに変換する。
## この関数の出力をJSON化してハッシュ化したものがバージョンIDになるため、
## ここに含めた情報の変化だけが「新バージョン」として検出される。
func _build_snapshot_dict() -> Dictionary:
	var items := {}
	for item_id in Items.definitions.keys():
		items[item_id] = Items.definitions[item_id]["name"]

	var areas := {}
	for area_id in WorldMap.areas.keys():
		areas[area_id] = WorldMap.areas[area_id]["name"]

	var sections := {}
	for section_id in WorldMap.sections.keys():
		var s: Dictionary = WorldMap.sections[section_id]
		sections[section_id] = {"name": s["name"], "area_id": s["area"]}

	var nodes := {}
	for node_id in WorldMap.nodes.keys():
		var n: Dictionary = WorldMap.nodes[node_id]
		nodes[node_id] = {
			"name": n["name"],
			"section_id": n["section"],
			"gate": n["gate"],
			"item_reward": n["item_reward"],
			"connections": n["connections"],
			"event_script_pass": n["event_script_pass"],
			"event_script_fail": n["event_script_fail"],
			"initially_passed": n["passed"],
		}

	return {"items": items, "areas": areas, "sections": sections, "nodes": nodes}

func _compute_version_id(snapshot: Dictionary) -> String:
	return JSON.stringify(snapshot).sha256_text()

## DROP→CREATEで毎回作り直す。こうしておけば、開発中にテーブルの列構成を変更しても、
## 「今の」バージョンファイルは古いuser://ファイルを手動で消さずに済む(自己修復する)。
## ただし過去バージョンのファイルは元データがもう無く書き直せないため、対象外(上のコメント参照)。
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

func _write_snapshot(version_id: String, snapshot: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(SCHEMA_DIR)
	var db := SQLite.new()
	db.path = _version_path(version_id)
	if not db.open_db():
		return
	_ensure_schema(db) # DROP→CREATEなので、この時点で全テーブルは既に空
	db.query("BEGIN TRANSACTION")

	for item_id in snapshot["items"].keys():
		db.query_with_bindings("INSERT INTO items (item_id, name) VALUES (?, ?)", [item_id, snapshot["items"][item_id]])

	for area_id in snapshot["areas"].keys():
		db.query_with_bindings("INSERT INTO areas (area_id, name) VALUES (?, ?)", [area_id, snapshot["areas"][area_id]])

	for section_id in snapshot["sections"].keys():
		var section: Dictionary = snapshot["sections"][section_id]
		db.query_with_bindings("INSERT INTO sections (section_id, name, area_id) VALUES (?, ?, ?)",
			[section_id, section["name"], section["area_id"]])

	for node_id in snapshot["nodes"].keys():
		var node: Dictionary = snapshot["nodes"][node_id]
		var gate: Dictionary = node["gate"]
		db.query_with_bindings(
			"INSERT INTO nodes (node_id, name, section_id, gate_json, item_reward, initially_passed) VALUES (?, ?, ?, ?, ?, ?)",
			[node_id, node["name"], node["section_id"], JSON.stringify(gate) if not gate.is_empty() else "", node["item_reward"],
				1 if node["initially_passed"] else 0])
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

## 指定したバージョンのスキーマDBからWorldMap/Itemsを(再)構築する。
## world_data.gdが呼ぶのと同じWorldMapの公開メソッド(add_area等)経由で組み立てるため、
## GDScript直書きの経路とDB経由の経路が常に同じ形のWorldMapに収束する。
## ファイルが存在しない(例: 手動で消された)場合は何もせず、WorldMapは変更しない。
func import_into_worldmap(version_id: String) -> void:
	var path := _version_path(version_id)
	if not FileAccess.file_exists(path):
		return
	var db := SQLite.new()
	db.path = path
	if not db.open_db():
		return
	active_version_id = version_id
	# add_area/add_section/add_node/defineは上書きのみで削除しないため、先に完全にクリアする。
	# しないと、別バージョンに切り替えた際に前のバージョンにしかない要素が残ってしまう
	# (実際にマルチバージョン切替のシミュレーションでこの不具合を検出して追加した)。
	WorldMap.reset()
	Items.reset()

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
		WorldMap.mark_passed(node_id, true)

	db.close_db()

func _decode_gate(gate_json: String) -> Dictionary:
	var gate: Dictionary = JSON.parse_string(gate_json)
	for key in ["skill", "min_level", "enemy_power"]:
		if gate.has(key):
			gate[key] = int(gate[key])
	return gate
