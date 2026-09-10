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

const SAVE_PATH := "user://worldseeker_save.sqlite"

const TABLES := [
	"meta", "npcs", "npc_traits", "npc_skills", "npc_inventory",
	"world_progress", "board_entries", "board_threads", "board_thread_entries",
]

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

func save_game() -> void:
	var db := SQLite.new()
	db.path = SAVE_PATH
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

	db.query("COMMIT")
	db.close_db()

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var db := SQLite.new()
	db.path = SAVE_PATH
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
