extends Node
# シナリオ(ScenarioStore、godot/scenarios/ や user://scenarios/)の内容を、SQLiteへスナップショットとして
# 書き出し(design.md 8.1「DBに格納」/8.2「スキーマ再プレイ」)、そこからWorldMap等を再構築する。
#
# 2026-09-21: 世界の正本を、GDScript直書き(world_data.gd)からシナリオのJSONへ移した(docs/scenario_editor.md)。
# シナリオはフォルダ(JSON+画像)で、このDBは「シナリオの内容を、ある時点で凍結したスナップショット」という位置づけ。
# スナップショットにはマップに加えて、イベント(会話)・登場人物表・シナリオ情報も入れる。よってセーブスロットは、
# 後でシナリオが編集・削除されても、遊び始めた時点の内容で再開できる(画像ファイルだけは外部参照)。
# 保存進行状態(save_system.gd)とはライフサイクルが異なる(世界の中身は不変のスナップショット、進行状態はプレイ間で
# 引き継ぐ)ため、あえて別のSQLiteファイルに分けている。
#
# 複数バージョン管理: スナップショットの正規化JSONのSHA-256をバージョンID(schema_version)とし、
# `user://schemas/schema_<version_id>.sqlite`にバージョンごとに別ファイルとして保存する(design.md 8.2「スキーマ再
# プレイ」/11章)。内容が実際に変わった時だけ新しいバージョンファイルが増える(同じ内容なら同じハッシュ=同じファイル)。
# エディタでシナリオを編集して保存すると、内容が変わるので新バージョンになり、既存のスロットは古いバージョンのまま。
#
# `current_version_id`は「今選んでいるシナリオの、今の内容が生成するバージョン」(use_scenario()で切り替わる)、
# `active_version_id`は「今WorldMapに実際に読み込まれているバージョン」で、常に一致するとは限らない(古いセーブ
# スロットを開くと、そのスロットが生成された時点のバージョンをimport_into_worldmap()で読み込み直すため)。
# save_system.gdはセーブのたびにactive_version_idをそのスロットのmetaテーブルへ記録し、次回そのスロットを開く時に
# 同じバージョンを再現する。
#
# ゲート条件(gate)とイベントは種類によって形が変わる可変構造なので、無理に正規化せずJSON列として保存する。
# それ以外のエリア/セクション/ノード/接続は素直に正規化したテーブルに分けている。並びに意味がある(エリアの順など)ため、
# 読み出しはrowid順(=書き込んだ順)で行う。
#
# 注意: gate_json/イベントの復元では、GodotのJSON.parse_stringが数値を全てfloatで返すため、整数の項目は
# 明示的にintへ直している(save_system.gdで踏んだのと同じ罠。詳細はそちらのコメント参照)。
#
# initially_passed列: 最初から突破済み扱いのノード(village/forest_edgeなど、スタート地点)をスキーマの一部として
# 記録する。このファイルの`_ready()`はSaveSystem.load_game()より前に実行される(project.godotのautoload順)ため、
# 実プレイの進行状況(発見/突破)が混ざらず、常に「まっさらな初期状態」だけを捉えられる。
#
# 旧形式(2026-09-21より前に保存された、events表・cast表・scenario_info表を持たないスキーマ)も読める:
# ノードごとの突破用/失敗用の台本(event_scripts表)から`gate`イベントを起こし、登場人物表とシナリオ情報は
# デフォルトシナリオのものを使う。

const SCHEMA_DIR := "user://schemas"
const STARTUP_SCENARIO_ID := "default"

var current_version_id: String = "" # 今選んでいるシナリオの、今の内容が生成するバージョン
var active_version_id: String = "" # 今WorldMapに実際に読み込まれているバージョン

func _ready() -> void:
	if use_scenario(STARTUP_SCENARIO_ID, "default"):
		import_into_worldmap(current_version_id)
		# 端末(特にAndroid: res://のフォルダ一覧が使えるか)で、シナリオを読めたかを確かめるためのログ(logcat -s godot)
		print("[scenario] 起動: %s フロア%d 会話%d 選べるシナリオ%d" % [
			ScenarioEvents.info.get("id", ""), WorldMap.nodes.size(), ScenarioEvents.events.size(), ScenarioStore.list_scenarios().size()])
	else:
		push_error("デフォルトシナリオを読み込めません: " + ScenarioStore.scenario_dir(STARTUP_SCENARIO_ID, "default"))

## シナリオを読み込み、そのスナップショットを書き出して「今選んでいるバージョン」にする。WorldMapは変えない
## (呼び出し側が続けてimport_into_worldmap(current_version_id)する)。既存のバージョンファイルも、毎回書き直す
## (DROP→CREATEで自己修復もする、後述)。読み込めなければfalse(状態は変えない)。
func use_scenario(scenario_id: String, source: String) -> bool:
	var snapshot := ScenarioStore.load_scenario(scenario_id, source)
	if snapshot.is_empty():
		return false
	var version_id := _compute_version_id(snapshot)
	_write_snapshot(version_id, snapshot)
	current_version_id = version_id
	active_version_id = version_id
	return true

func _version_path(version_id: String) -> String:
	return "%s/schema_%s.sqlite" % [SCHEMA_DIR, version_id]

## 指定バージョンのスキーマファイルのパス。セーブのエクスポート/インポート(save_system.gd)が、
## スロットが使っているバージョンをzipに同梱したり、この端末に無いバージョンを取り込んだりするために公開している。
func version_file_path(version_id: String) -> String:
	return _version_path(version_id)

## この関数の出力をJSON化してハッシュ化したものがバージョンIDになるため、スナップショットに含めた情報の変化だけが
## 「新バージョン」として検出される。
func _compute_version_id(snapshot: Dictionary) -> String:
	return JSON.stringify(snapshot).sha256_text()

## DROP→CREATEで毎回作り直す。こうしておけば、開発中にテーブルの列構成を変更しても、「今の」バージョンファイルは
## 古いuser://ファイルを手動で消さずに済む(自己修復する)。ただし過去バージョンのファイルは元データがもう無く
## 書き直せないため、対象外。event_scriptsは旧形式の表で、もう書かない(読む側だけが知っている)。
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
	db.query("DROP TABLE IF EXISTS events")
	db.query("CREATE TABLE events (event_id TEXT PRIMARY KEY, event_json TEXT)")
	db.query("DROP TABLE IF EXISTS cast")
	db.query("CREATE TABLE cast (speaker_name TEXT PRIMARY KEY, image TEXT, side TEXT)")
	db.query("DROP TABLE IF EXISTS scenario_info")
	db.query("CREATE TABLE scenario_info (key TEXT PRIMARY KEY, value TEXT)")

func _write_snapshot(version_id: String, snapshot: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(SCHEMA_DIR)
	var db := SQLite.new()
	db.path = _version_path(version_id)
	if not db.open_db():
		return
	_ensure_schema(db) # DROP→CREATEなので、この時点で全テーブルは既に空
	db.query("BEGIN TRANSACTION")

	for item in snapshot["items"]:
		db.query_with_bindings("INSERT INTO items (item_id, name) VALUES (?, ?)", [item["id"], item["name"]])
	for area in snapshot["areas"]:
		db.query_with_bindings("INSERT INTO areas (area_id, name) VALUES (?, ?)", [area["id"], area["name"]])
	for section in snapshot["sections"]:
		db.query_with_bindings("INSERT INTO sections (section_id, name, area_id) VALUES (?, ?, ?)",
			[section["id"], section["name"], section["area_id"]])
	for node in snapshot["nodes"]:
		var gate: Dictionary = node["gate"]
		db.query_with_bindings(
			"INSERT INTO nodes (node_id, name, section_id, gate_json, item_reward, initially_passed) VALUES (?, ?, ?, ?, ?, ?)",
			[node["id"], node["name"], node["section_id"], JSON.stringify(gate) if not gate.is_empty() else "", node["item_reward"],
				1 if node["initially_passed"] else 0])
		for neighbor_id in node["connections"]:
			db.query_with_bindings("INSERT INTO connections (node_id, neighbor_id) VALUES (?, ?)", [node["id"], neighbor_id])
	for event in snapshot["events"]:
		db.query_with_bindings("INSERT INTO events (event_id, event_json) VALUES (?, ?)", [event["id"], JSON.stringify(event)])
	for entry in snapshot["cast"]:
		db.query_with_bindings("INSERT INTO cast (speaker_name, image, side) VALUES (?, ?, ?)", [entry["name"], entry["image"], entry["side"]])
	var info: Dictionary = snapshot["scenario"]
	for key in info.keys():
		db.query_with_bindings("INSERT INTO scenario_info (key, value) VALUES (?, ?)", [key, str(info[key])])

	db.query("COMMIT")
	db.close_db()

## 指定したバージョンのスナップショットからWorldMap/Items/ScenarioEventsの定義を(再)構築する。
## 進行状態(発見/突破・フラグ)は触らない。ファイルが存在しない(例: 手動で消された)場合は何もしない。
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

	db.query("SELECT * FROM items ORDER BY rowid")
	for row in db.query_result:
		Items.define(String(row["item_id"]), String(row["name"]))

	db.query("SELECT * FROM areas ORDER BY rowid")
	for row in db.query_result:
		WorldMap.add_area(String(row["area_id"]), String(row["name"]))

	db.query("SELECT * FROM sections ORDER BY rowid")
	for row in db.query_result:
		WorldMap.add_section(String(row["section_id"]), String(row["name"]), String(row["area_id"]))

	var connections_by_node := {}
	db.query("SELECT * FROM connections ORDER BY rowid")
	for row in db.query_result:
		var node_id: String = String(row["node_id"])
		if not connections_by_node.has(node_id):
			connections_by_node[node_id] = []
		connections_by_node[node_id].append(String(row["neighbor_id"]))

	var passed_nodes := []
	var node_names := {}
	db.query("SELECT * FROM nodes ORDER BY rowid")
	for row in db.query_result:
		var node_id: String = String(row["node_id"])
		var gate_json: String = String(row["gate_json"])
		var gate: Dictionary = _decode_gate(gate_json) if gate_json != "" else {}
		WorldMap.add_node(node_id, String(row["name"]), connections_by_node.get(node_id, []), gate,
			String(row["section_id"]), String(row["item_reward"]))
		node_names[node_id] = String(row["name"])
		if bool(row["initially_passed"]):
			passed_nodes.append(node_id)
	for node_id in passed_nodes:
		WorldMap.mark_passed(node_id, true)

	_import_scenario_content(db, node_names)
	db.close_db()

## イベント・登場人物表・シナリオ情報をScenarioEventsへ流し込む。旧形式のスキーマ(events表なし)なら、
## 突破用/失敗用の台本からgateイベントを起こし、登場人物表とシナリオ情報はデフォルトシナリオのものを使う。
func _import_scenario_content(db: SQLite, node_names: Dictionary) -> void:
	if _has_table(db, "events"):
		var events := []
		db.query("SELECT event_json FROM events ORDER BY rowid")
		for row in db.query_result:
			events.append(ScenarioStore.normalize_event(JSON.parse_string(String(row["event_json"]))))
		var cast := []
		db.query("SELECT * FROM cast ORDER BY rowid")
		for row in db.query_result:
			cast.append({"name": String(row["speaker_name"]), "image": String(row["image"]), "side": String(row["side"])})
		var info := {}
		db.query("SELECT * FROM scenario_info")
		for row in db.query_result:
			info[String(row["key"])] = String(row["value"])
		for key in ["start_year", "start_month"]:
			info[key] = int(info.get(key, 0 if key == "start_year" else 1))
		ScenarioEvents.load_definitions(events, cast, info)
		return

	var legacy_events := []
	db.query("SELECT * FROM event_scripts ORDER BY rowid")
	for row in db.query_result:
		var node_id := String(row["node_id"])
		var result := String(row["outcome"])
		legacy_events.append(ScenarioStore.normalize_event({
			"id": "floor_%s_%s" % [node_id, result],
			"title": "%s(%s)" % [node_names.get(node_id, node_id), "突破" if result == "pass" else "失敗"],
			"trigger": {"type": "gate", "floor": node_id, "result": result},
			"script": JSON.parse_string(String(row["script_json"])),
		}))
	var fallback := ScenarioStore.load_scenario(STARTUP_SCENARIO_ID, "default")
	ScenarioEvents.load_definitions(ScenarioStore.sort_events(legacy_events), fallback.get("cast", []), fallback.get("scenario", {}))

func _has_table(db: SQLite, table: String) -> bool:
	db.query_with_bindings("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", [table])
	return not db.query_result.is_empty()

func _decode_gate(gate_json: String) -> Dictionary:
	var gate: Dictionary = JSON.parse_string(gate_json)
	for key in ["skill", "min_level", "enemy_power"]:
		if gate.has(key):
			gate[key] = int(gate[key])
	return gate
