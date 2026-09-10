extends Node
# ワールドの進行状態をSQLite(addons/godot-sqlite)で保存・復元する(docs/design.md 8.2/10章)。
#
# 保存対象は「プレイ進行状態」のみ(資金・NPC名簿・ワールド探索の発見/突破状態・掲示板ログ)。
# ワールドスキーマそのもの(エリア/セクション/フロア/ゲート/イベント台本の定義)は
# 引き続き`world_data.gd`が開発時コンテンツとして担当する(design.md 8.1の想定通り、
# 将来そちらをDB化する場合はこのファイルとは別のテーブル/読み込み経路になる)。
#
# 保存のたびに全テーブルをDELETEしてから現在の状態を丸ごと再INSERTする(差分更新はしない)。
# npc_id/skillなどint型のキーはSQLiteのINTEGERカラムに素のint/floatとしてバインドしており、
# JSON保存で問題になった「数値が全てfloat化・キーが全て文字列化される」事象は発生しない。
#
# 例外は`action_log`テーブル(action_log.gd、design.md 8.2の「記録再生」用): こちらは
# 「現在の状態」ではなく「これまで起きた出来事の履歴」なので、他テーブルと違いDELETEの
# 対象にせず、ActionLog側にバッファされた分だけをINSERTで追記する。
#
# 複数セーブスロット対応: セーブファイルは`user://saves/slot_<id>.sqlite`としてスロットごとに
# 分ける(テーブル定義はスロット間で共通、パスだけが変わる)。どのスロットがアクティブかは
# `user://worldseeker_meta.cfg`に1行だけ持たせている。ワールドスキーマ(world_schema_db.gd)は
# 全スロット共通の単一ファイルのまま(スロットは「進行状態」の違いであり、マップ自体は
# 共有する設計。design.md 8.2参照)。

const SLOT_DIR := "user://saves"
const META_PATH := "user://worldseeker_meta.cfg"

const TABLES := [
	"meta", "npcs", "npc_traits", "npc_skills", "npc_inventory",
	"world_progress", "board_entries", "board_threads", "board_thread_entries",
]

var current_slot_id: int = 1

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(META_PATH) == OK:
		current_slot_id = int(cfg.get_value("state", "active_slot", 1))

func _slot_path(slot_id: int) -> String:
	return "%s/slot_%d.sqlite" % [SLOT_DIR, slot_id]

func _set_active_slot(slot_id: int) -> void:
	current_slot_id = slot_id
	var cfg := ConfigFile.new()
	cfg.load(META_PATH) # 失敗しても新規作成として続行してよい
	cfg.set_value("state", "active_slot", slot_id)
	cfg.save(META_PATH)

## 既存スロット一覧(スロットID順)。各スロットのDBを開いて概要(資金/日付/NPC数)だけ読む。
func list_slots() -> Array:
	var result := []
	DirAccess.make_dir_recursive_absolute(SLOT_DIR)
	var dir := DirAccess.open(SLOT_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("slot_") and file_name.ends_with(".sqlite"):
			var slot_id := int(file_name.trim_prefix("slot_").trim_suffix(".sqlite"))
			var info := _peek_slot(slot_id)
			if not info.is_empty():
				result.append(info)
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a, b): return a["slot_id"] < b["slot_id"])
	return result

func _peek_slot(slot_id: int) -> Dictionary:
	var db := SQLite.new()
	db.path = _slot_path(slot_id)
	if not db.open_db():
		return {}
	_ensure_schema(db)
	db.query("SELECT key, value FROM meta")
	var meta := {}
	for row in db.query_result:
		meta[String(row["key"])] = row["value"]
	db.query("SELECT COUNT(*) AS c FROM npcs")
	var npc_count: int = int(db.query_result[0]["c"]) if not db.query_result.is_empty() else 0
	db.close_db()
	if meta.is_empty():
		return {}
	return {
		"slot_id": slot_id,
		"funds": int(meta.get("funds", 0)),
		"day": int(meta.get("current_day", 0)),
		"month": int(meta.get("current_month", 0)),
		"npc_count": npc_count,
	}

## 新規スロットを作成してアクティブにする(design.md 8.2「スキーマ再プレイ」)。
## ワールドスキーマDB(world_schema_db.gd)経由でWorldMapを再構築するため、
## GDScript直書き経路と同じ形の「まっさらな世界」から始まることをこの一手が保証する。
func create_new_slot() -> int:
	var next_id := _next_free_slot_id()
	save_game() # 離れる前のスロットを保存
	Economy.reset()
	TimeSystem.reset()
	Npcs.reset()
	Recruitment.reset()
	Board.reset()
	ActionLog.reset()
	WorldSchemaDb.import_into_worldmap()
	_set_active_slot(next_id)
	save_game()
	return next_id

func _next_free_slot_id() -> int:
	var max_id := 0
	for slot in list_slots():
		max_id = max(max_id, int(slot["slot_id"]))
	return max_id + 1

## 既存スロットに切り替える。WorldMapをスキーマDBからまっさらに再構築してから
## そのスロットの進行状態を上書きする(別スロットの発見/突破状態が混ざらないようにするため)。
func switch_to_slot(slot_id: int) -> bool:
	if current_slot_id != slot_id:
		save_game()
	_set_active_slot(slot_id)
	WorldSchemaDb.import_into_worldmap()
	return load_game()

## スロットを削除する。アクティブなスロットは(切り替え先が定まらないため)削除できない。
func delete_slot(slot_id: int) -> bool:
	if slot_id == current_slot_id:
		return false
	var path := _slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK

## 行動ログビューアー用: 現在のスロットのaction_logを取得する(npc_id<0で全NPC分)。
func query_action_log(npc_id: int = -1, limit: int = 200) -> Array:
	var result := []
	var db := SQLite.new()
	db.path = _slot_path(current_slot_id)
	if not db.open_db():
		return result
	_ensure_schema(db)
	if npc_id < 0:
		db.query_with_bindings("SELECT * FROM action_log ORDER BY id DESC LIMIT ?", [limit])
	else:
		db.query_with_bindings("SELECT * FROM action_log WHERE npc_id = ? ORDER BY id DESC LIMIT ?", [npc_id, limit])
	for row in db.query_result:
		result.append({
			"day": int(row["day"]),
			"event_type": String(row["event_type"]),
			"npc_id": int(row["npc_id"]),
			"node_id": String(row["node_id"]),
			"section_id": String(row["section_id"]),
			"text": String(row["text"]),
		})
	db.close_db()
	return result

func _ensure_schema(db: SQLite) -> void:
	db.query("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value)")
	db.query("""CREATE TABLE IF NOT EXISTS npcs (
		id INTEGER PRIMARY KEY, name TEXT, hp REAL, max_hp REAL, status INTEGER,
		assigned_section TEXT, combat_hp_threshold REAL, combat_action INTEGER, recovering_until_day INTEGER
	)""")
	db.query("CREATE TABLE IF NOT EXISTS npc_traits (npc_id INTEGER, trait_key TEXT, trait_value TEXT, PRIMARY KEY (npc_id, trait_key))")
	db.query("CREATE TABLE IF NOT EXISTS npc_skills (npc_id INTEGER, skill INTEGER, level INTEGER, exp INTEGER, PRIMARY KEY (npc_id, skill))")
	db.query("CREATE TABLE IF NOT EXISTS npc_inventory (npc_id INTEGER, item_id TEXT, PRIMARY KEY (npc_id, item_id))")
	db.query("CREATE TABLE IF NOT EXISTS world_progress (node_id TEXT PRIMARY KEY, found INTEGER, passed INTEGER)")
	db.query("CREATE TABLE IF NOT EXISTS board_entries (seq INTEGER PRIMARY KEY AUTOINCREMENT, day INTEGER, text TEXT, importance INTEGER, source TEXT)")
	db.query("CREATE TABLE IF NOT EXISTS board_threads (thread_id TEXT PRIMARY KEY, title TEXT)")
	db.query("CREATE TABLE IF NOT EXISTS board_thread_entries (seq INTEGER PRIMARY KEY AUTOINCREMENT, thread_id TEXT, day INTEGER, text TEXT, importance INTEGER, source TEXT)")
	db.query("""CREATE TABLE IF NOT EXISTS action_log (
		id INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT, day INTEGER, event_type TEXT,
		npc_id INTEGER, node_id TEXT, section_id TEXT, text TEXT
	)""")

func save_game() -> void:
	DirAccess.make_dir_recursive_absolute(SLOT_DIR)
	var db := SQLite.new()
	db.path = _slot_path(current_slot_id)
	if not db.open_db():
		return
	_ensure_schema(db)
	db.query("BEGIN TRANSACTION")
	for table in TABLES:
		db.query("DELETE FROM %s" % table)

	var meta := {
		"funds": Economy.funds,
		"employ_cap": Economy.employ_cap,
		"facility_level": Economy.facility_level,
		"current_day": TimeSystem.current_day,
		"current_month": TimeSystem.current_month,
		"is_paused": 1 if TimeSystem.is_paused else 0,
		"speed_multiplier": TimeSystem.speed_multiplier,
	}
	var npc_data: Dictionary = Npcs.save_state()
	meta["npc_next_id"] = npc_data["next_id"]
	ActionLog.ensure_run_id()
	meta["run_id"] = ActionLog.run_id
	for key in meta.keys():
		db.query_with_bindings("INSERT INTO meta (key, value) VALUES (?, ?)", [key, meta[key]])

	var roster: Dictionary = npc_data["roster"]
	for npc_id in roster.keys():
		var npc: Dictionary = roster[npc_id]
		db.query_with_bindings(
			"""INSERT INTO npcs (id, name, hp, max_hp, status, assigned_section, combat_hp_threshold, combat_action, recovering_until_day)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
			[npc_id, npc["name"], npc["hp"], npc["max_hp"], npc["status"], npc["assigned_section"],
				npc["combat_policy"]["hp_threshold"], npc["combat_policy"]["action"], npc["recovering_until_day"]])
		for trait_key in npc["innate_traits"].keys():
			db.query_with_bindings("INSERT INTO npc_traits (npc_id, trait_key, trait_value) VALUES (?, ?, ?)",
				[npc_id, trait_key, npc["innate_traits"][trait_key]])
		for skill in npc["skills"].keys():
			var entry: Dictionary = npc["skills"][skill]
			db.query_with_bindings("INSERT INTO npc_skills (npc_id, skill, level, exp) VALUES (?, ?, ?, ?)",
				[npc_id, skill, entry["level"], entry["exp"]])
		for item_id in npc["inventory"]:
			db.query_with_bindings("INSERT INTO npc_inventory (npc_id, item_id) VALUES (?, ?)", [npc_id, item_id])

	var progress: Dictionary = WorldMap.save_progress()
	for node_id in progress.keys():
		var state: Dictionary = progress[node_id]
		db.query_with_bindings("INSERT INTO world_progress (node_id, found, passed) VALUES (?, ?, ?)",
			[node_id, 1 if state["found"] else 0, 1 if state["passed"] else 0])

	var board_data: Dictionary = Board.save_state()
	for entry in board_data["entries"]:
		db.query_with_bindings("INSERT INTO board_entries (day, text, importance, source) VALUES (?, ?, ?, ?)",
			[entry["day"], entry["text"], entry["importance"], entry["source"]])
	var threads: Dictionary = board_data["threads"]
	for thread_id in threads.keys():
		var thread: Dictionary = threads[thread_id]
		db.query_with_bindings("INSERT INTO board_threads (thread_id, title) VALUES (?, ?)", [thread_id, thread["title"]])
		for entry in thread["entries"]:
			db.query_with_bindings(
				"INSERT INTO board_thread_entries (thread_id, day, text, importance, source) VALUES (?, ?, ?, ?, ?)",
				[thread_id, entry["day"], entry["text"], entry["importance"], entry["source"]])

	ActionLog.flush(db)

	db.query("COMMIT")
	db.close_db()

func load_game() -> bool:
	if not FileAccess.file_exists(_slot_path(current_slot_id)):
		return false
	var db := SQLite.new()
	db.path = _slot_path(current_slot_id)
	if not db.open_db():
		return false
	_ensure_schema(db)

	db.query("SELECT key, value FROM meta")
	var meta := {}
	for row in db.query_result:
		meta[String(row["key"])] = row["value"]
	if meta.is_empty():
		db.close_db()
		return false

	Economy.funds = int(meta.get("funds", Economy.funds))
	Economy.employ_cap = int(meta.get("employ_cap", Economy.employ_cap))
	Economy.facility_level = int(meta.get("facility_level", Economy.facility_level))
	TimeSystem.current_day = int(meta.get("current_day", TimeSystem.current_day))
	TimeSystem.current_month = int(meta.get("current_month", TimeSystem.current_month))
	TimeSystem.is_paused = bool(int(meta.get("is_paused", 0)))
	TimeSystem.speed_multiplier = float(meta.get("speed_multiplier", 1.0))
	if meta.has("run_id"):
		ActionLog.run_id = String(meta["run_id"])

	var roster := {}
	db.query("SELECT * FROM npcs")
	for row in db.query_result:
		var npc_id: int = int(row["id"])
		roster[npc_id] = {
			"name": String(row["name"]),
			"hp": row["hp"],
			"max_hp": row["max_hp"],
			"status": int(row["status"]),
			"assigned_section": String(row["assigned_section"]),
			"combat_policy": {"hp_threshold": row["combat_hp_threshold"], "action": int(row["combat_action"])},
			"recovering_until_day": int(row["recovering_until_day"]),
			"innate_traits": {},
			"skills": {},
			"inventory": [],
		}
	db.query("SELECT * FROM npc_traits")
	for row in db.query_result:
		var npc_id: int = int(row["npc_id"])
		if roster.has(npc_id):
			roster[npc_id]["innate_traits"][String(row["trait_key"])] = String(row["trait_value"])
	db.query("SELECT * FROM npc_skills")
	for row in db.query_result:
		var npc_id: int = int(row["npc_id"])
		if roster.has(npc_id):
			roster[npc_id]["skills"][int(row["skill"])] = {"level": int(row["level"]), "exp": int(row["exp"])}
	db.query("SELECT * FROM npc_inventory")
	for row in db.query_result:
		var npc_id: int = int(row["npc_id"])
		if roster.has(npc_id):
			roster[npc_id]["inventory"].append(String(row["item_id"]))
	Npcs.load_state({"next_id": int(meta.get("npc_next_id", 1)), "roster": roster})

	var progress := {}
	db.query("SELECT * FROM world_progress")
	for row in db.query_result:
		progress[String(row["node_id"])] = {"found": bool(row["found"]), "passed": bool(row["passed"])}
	WorldMap.load_progress(progress)

	var entries := []
	db.query("SELECT day, text, importance, source FROM board_entries ORDER BY seq")
	for row in db.query_result:
		entries.append({"day": row["day"], "text": String(row["text"]), "importance": row["importance"], "source": String(row["source"])})
	var threads := {}
	db.query("SELECT thread_id, title FROM board_threads")
	for row in db.query_result:
		var thread_id: String = String(row["thread_id"])
		threads[thread_id] = {"id": thread_id, "title": String(row["title"]), "entries": []}
	db.query("SELECT thread_id, day, text, importance, source FROM board_thread_entries ORDER BY seq")
	for row in db.query_result:
		var thread_id: String = String(row["thread_id"])
		if threads.has(thread_id):
			threads[thread_id]["entries"].append({"day": row["day"], "text": String(row["text"]), "importance": row["importance"], "source": String(row["source"])})
	Board.load_state({"entries": entries, "threads": threads})

	db.close_db()
	return true
