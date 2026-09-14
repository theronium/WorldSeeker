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
	"meta", "npcs", "npc_traits", "npc_skills", "npc_inventory", "parties", "party_members",
	"world_progress", "section_rewards", "board_entries", "board_threads", "board_thread_entries",
]

var current_slot_id: int = 1
## オートセーブ(日次/終了時)を止めたい、という要望への対応(2026-09-13追加)。手動セーブ/
## 進行の複製機能があるので、オフにしても明示的な保存手段は残る。プレイヤー設定として
## worldseeker_meta.cfgに永続化する(スロットごとの値ではない)。
var autosave_enabled: bool = true

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(META_PATH) == OK:
		current_slot_id = int(cfg.get_value("state", "active_slot", 1))
		autosave_enabled = bool(cfg.get_value("state", "autosave_enabled", true))

func _slot_path(slot_id: int) -> String:
	return "%s/slot_%d.sqlite" % [SLOT_DIR, slot_id]

func _set_active_slot(slot_id: int) -> void:
	current_slot_id = slot_id
	var cfg := ConfigFile.new()
	cfg.load(META_PATH) # 失敗しても新規作成として続行してよい
	cfg.set_value("state", "active_slot", slot_id)
	cfg.save(META_PATH)

func set_autosave_enabled(enabled: bool) -> void:
	autosave_enabled = enabled
	var cfg := ConfigFile.new()
	cfg.load(META_PATH)
	cfg.set_value("state", "autosave_enabled", enabled)
	cfg.save(META_PATH)

## オートセーブ経路(main.gdの日次/終了時保存)専用の入り口。autosave_enabledがfalseの間は
## 何もしない。手動セーブ・分岐複製・スロット切替/削除・新規プレイなど、プレイヤーが明示的に
## 操作した結果としてのsave_game()呼び出しはこのフラグの影響を受けない(そちらは直接
## save_game()を呼ぶ)。
func autosave() -> void:
	if autosave_enabled:
		save_game()

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
## 新規プレイは常に最新のワールドスキーマ(WorldSchemaDb.current_version_id)を使う。
func create_new_slot() -> int:
	var next_id := _next_free_slot_id()
	save_game() # 離れる前のスロットを保存
	Economy.reset()
	TimeSystem.reset()
	Npcs.reset()
	Parties.reset()
	Recruitment.reset()
	Board.reset()
	ActionLog.reset()
	WorldSchemaDb.import_into_worldmap(WorldSchemaDb.current_version_id)
	# design.md 4.7節: 購入・募集不要の初期パーティ(4人)を無償で用意する。
	var starter_ids := Npcs.create_starter_roster()
	Parties.form_party(starter_ids, "初期パーティ")
	_set_active_slot(next_id)
	save_game()
	return next_id

## 今のスロットの進行状態を、それとは別の新しいスロットへそのまま複製する(design.md 8.2
## 「分岐」用)。create_new_slot()と違いワールド進行をゼロから作り直さず、今の状態をそのまま
## 複製するため、同じ分岐点から別方向へ進められる2本目のスロットができる。アクティブスロットは
## 複製後も元のままで、呼び出し側は引き続き同じスロットで続行する(ファイルコピーのみなので
## WorldMap/Npcs等の再構築も不要)。
func duplicate_current_slot() -> int:
	save_game() # 複製前に最新の状態をディスクへ反映しておく
	var next_id := _next_free_slot_id()
	DirAccess.make_dir_recursive_absolute(SLOT_DIR)
	var err := DirAccess.copy_absolute(_slot_path(current_slot_id), _slot_path(next_id))
	return next_id if err == OK else -1

func _next_free_slot_id() -> int:
	var max_id := 0
	for slot in list_slots():
		max_id = max(max_id, int(slot["slot_id"]))
	return max_id + 1

## 指定スロットが最後に保存した時点のワールドスキーマバージョンIDを返す(未保存/未記録なら空文字)。
func get_slot_schema_version(slot_id: int) -> String:
	var path := _slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return ""
	var db := SQLite.new()
	db.path = path
	if not db.open_db():
		return ""
	_ensure_schema(db)
	db.query_with_bindings("SELECT value FROM meta WHERE key = ?", ["schema_version"])
	var result := ""
	if not db.query_result.is_empty():
		result = String(db.query_result[0]["value"])
	db.close_db()
	return result

## 既存スロットに切り替える。WorldMapを「そのスロットが生成された時点のワールドスキーマ
## バージョン」からまっさらに再構築してから、そのスロットの進行状態を上書きする
## (別スロットの発見/突破状態が混ざらないようにするため。スロットに記録がなければ
## 現行バージョンにフォールバックする)。
func switch_to_slot(slot_id: int) -> bool:
	if current_slot_id != slot_id:
		save_game()
	var pinned_version := get_slot_schema_version(slot_id)
	if pinned_version == "":
		pinned_version = WorldSchemaDb.current_version_id
	_set_active_slot(slot_id)
	WorldSchemaDb.import_into_worldmap(pinned_version)
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

## マップのフロアをダブルクリックした際の詳細表示用: そのフロア単体に絞った行動ログ。
## query_action_log()と同じテーブルをnode_idで絞り込むだけの姉妹版。
func query_action_log_for_node(node_id: String, limit: int = 50) -> Array:
	var result := []
	var db := SQLite.new()
	db.path = _slot_path(current_slot_id)
	if not db.open_db():
		return result
	_ensure_schema(db)
	db.query_with_bindings("SELECT * FROM action_log WHERE node_id = ? ORDER BY id DESC LIMIT ?", [node_id, limit])
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
	# found_by_employed/post_clear_behaviorは後から追加した列。既存スロット(旧スキーマ)には
	# まだ無いことがあるため、CREATE TABLE IF NOT EXISTSでは反映されない分をここで補う。
	_ensure_column(db, "world_progress", "found_by_employed", "INTEGER DEFAULT 0")
	# 2026-09-14のパーティ制導入: status/assigned_section/recovering_until_day/post_clear_behaviorは
	# パーティ側(parties table)に移ったため、npcsテーブルには以後書き込まない(列自体は旧セーブ
	# 互換のため残置)。代わりにジョブ・固有スキル・装備の列を追加する。job=-1は「旧セーブ由来で
	# 未設定」を表し、load_game()側で移行処理(job割り当て+固有スキル生成)の対象になる。
	_ensure_column(db, "npcs", "job", "INTEGER DEFAULT -1")
	_ensure_column(db, "npcs", "unique_skill_id", "TEXT DEFAULT ''")
	_ensure_column(db, "npcs", "equipped_weapon_tier", "INTEGER DEFAULT -1")
	_ensure_column(db, "npcs", "equipped_armor_tier", "INTEGER DEFAULT -1")
	# 2026-09-14追加。空文字は「旧セーブ由来で未割り当て」を表し、load_game()側の移行処理で
	# 血筋に応じたportraitを新規抽選する(job=-1の移行と同じ考え方)。
	_ensure_column(db, "npcs", "portrait_id", "TEXT DEFAULT ''")
	db.query("""CREATE TABLE IF NOT EXISTS parties (
		id INTEGER PRIMARY KEY, name TEXT, assigned_section TEXT, status INTEGER,
		recovering_until_day INTEGER, post_clear_behavior INTEGER
	)""")
	db.query("CREATE TABLE IF NOT EXISTS party_members (party_id INTEGER, npc_id INTEGER, order_index INTEGER, PRIMARY KEY (party_id, npc_id))")
	db.query("CREATE TABLE IF NOT EXISTS section_rewards (section_id TEXT PRIMARY KEY)")
	db.query("CREATE TABLE IF NOT EXISTS board_entries (seq INTEGER PRIMARY KEY AUTOINCREMENT, day INTEGER, text TEXT, importance INTEGER, source TEXT)")
	db.query("CREATE TABLE IF NOT EXISTS board_threads (thread_id TEXT PRIMARY KEY, title TEXT)")
	db.query("CREATE TABLE IF NOT EXISTS board_thread_entries (seq INTEGER PRIMARY KEY AUTOINCREMENT, thread_id TEXT, day INTEGER, text TEXT, importance INTEGER, source TEXT)")
	db.query("""CREATE TABLE IF NOT EXISTS action_log (
		id INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT, day INTEGER, event_type TEXT,
		npc_id INTEGER, node_id TEXT, section_id TEXT, text TEXT
	)""")

## 既存テーブルに列が無ければALTER TABLEで足す(CREATE TABLE IF NOT EXISTSは既存テーブルの
## 列を追加してくれないため)。新しい永続化フィールドを足すたびにこのヘルパー経由で追加する。
func _ensure_column(db: SQLite, table: String, column: String, column_def: String) -> void:
	db.query("PRAGMA table_info(%s)" % table)
	for row in db.query_result:
		if String(row["name"]) == column:
			return
	db.query("ALTER TABLE %s ADD COLUMN %s %s" % [table, column, column_def])

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
		"start_year": TimeSystem.start_year,
		"start_month": TimeSystem.start_month,
	}
	var npc_data: Dictionary = Npcs.save_state()
	meta["npc_next_id"] = npc_data["next_id"]
	ActionLog.ensure_run_id()
	meta["run_id"] = ActionLog.run_id
	# WorldMapが今実際に読み込んでいるスキーマバージョンを記録しておく(古いバージョンでも良い。
	# world_schema_db.gdのコメント参照)。次回このスロットを開く時にswitch_to_slot()が使う。
	meta["schema_version"] = WorldSchemaDb.active_version_id
	for key in meta.keys():
		db.query_with_bindings("INSERT INTO meta (key, value) VALUES (?, ?)", [key, meta[key]])

	var roster: Dictionary = npc_data["roster"]
	for npc_id in roster.keys():
		var npc: Dictionary = roster[npc_id]
		var weapon_tier: int = npc["equipped_weapon"]["tier"] if npc["equipped_weapon"].has("tier") else -1
		var armor_tier: int = npc["equipped_armor"]["tier"] if npc["equipped_armor"].has("tier") else -1
		db.query_with_bindings(
			"""INSERT INTO npcs (id, name, hp, max_hp, combat_hp_threshold, combat_action, job, unique_skill_id, equipped_weapon_tier, equipped_armor_tier, portrait_id)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
			[npc_id, npc["name"], npc["hp"], npc["max_hp"],
				npc["combat_policy"]["hp_threshold"], npc["combat_policy"]["action"],
				npc["job"], npc["unique_skill"].get("id", ""), weapon_tier, armor_tier, npc.get("portrait", "")])
		for trait_key in npc["innate_traits"].keys():
			db.query_with_bindings("INSERT INTO npc_traits (npc_id, trait_key, trait_value) VALUES (?, ?, ?)",
				[npc_id, trait_key, npc["innate_traits"][trait_key]])
		for skill in npc["skills"].keys():
			var entry: Dictionary = npc["skills"][skill]
			db.query_with_bindings("INSERT INTO npc_skills (npc_id, skill, level, exp) VALUES (?, ?, ?, ?)",
				[npc_id, skill, entry["level"], entry["exp"]])
		for item_id in npc["inventory"]:
			db.query_with_bindings("INSERT INTO npc_inventory (npc_id, item_id) VALUES (?, ?)", [npc_id, item_id])

	var party_data: Dictionary = Parties.save_state()
	# metaのINSERTループは既に上で実行済みのため、ここは単独のINSERTで追記する。
	db.query_with_bindings("INSERT INTO meta (key, value) VALUES (?, ?)", ["party_next_id", party_data["next_id"]])
	for party_id in party_data["parties"].keys():
		var party: Dictionary = party_data["parties"][party_id]
		db.query_with_bindings(
			"INSERT INTO parties (id, name, assigned_section, status, recovering_until_day, post_clear_behavior) VALUES (?, ?, ?, ?, ?, ?)",
			[party_id, party["name"], party["assigned_section"], party["status"], party["recovering_until_day"], party["post_clear_behavior"]])
		for i in range(party["member_ids"].size()):
			db.query_with_bindings("INSERT INTO party_members (party_id, npc_id, order_index) VALUES (?, ?, ?)",
				[party_id, party["member_ids"][i], i])

	var progress: Dictionary = WorldMap.save_progress()
	for node_id in progress.keys():
		var state: Dictionary = progress[node_id]
		db.query_with_bindings("INSERT INTO world_progress (node_id, found, passed, found_by_employed) VALUES (?, ?, ?, ?)",
			[node_id, 1 if state["found"] else 0, 1 if state["passed"] else 0, 1 if state["found_by_employed"] else 0])

	for section_id in WorldMap.section_reward_claimed.keys():
		db.query_with_bindings("INSERT INTO section_rewards (section_id) VALUES (?)", [section_id])

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
	TimeSystem.start_year = int(meta.get("start_year", TimeSystem.start_year))
	TimeSystem.start_month = int(meta.get("start_month", TimeSystem.start_month))
	if meta.has("run_id"):
		ActionLog.run_id = String(meta["run_id"])

	var roster := {}
	db.query("SELECT * FROM npcs")
	for row in db.query_result:
		var npc_id: int = int(row["id"])
		var weapon_tier: int = int(row.get("equipped_weapon_tier", -1))
		var armor_tier: int = int(row.get("equipped_armor_tier", -1))
		roster[npc_id] = {
			"name": String(row["name"]),
			"hp": row["hp"],
			"max_hp": row["max_hp"],
			"job": int(row.get("job", -1)),
			"unique_skill": UniqueSkills.by_id(String(row.get("unique_skill_id", ""))),
			"portrait": String(row.get("portrait_id", "")),
			"equipped_weapon": {"tier": weapon_tier} if weapon_tier >= 0 else {},
			"equipped_armor": {"tier": armor_tier} if armor_tier >= 0 else {},
			"party_id": -1, # party_membersテーブルから後で復元する
			"combat_policy": {"hp_threshold": row["combat_hp_threshold"], "action": int(row["combat_action"])},
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

	# 2026-09-14パーティ制導入前のセーブ移行: job==-1は旧セーブ由来でジョブ未設定という印。
	# 5スキルのうち最も高いものに対応するジョブを割り当て、固有スキルを新規生成する
	# (design.md 11章に記載した移行方針)。
	for npc_id in Npcs.roster.keys():
		var npc: Dictionary = Npcs.roster[npc_id]
		if npc["job"] == -1:
			var best_job: int = Jobs.Job.WARRIOR
			var best_level := -1
			for job in Jobs.all_jobs():
				var level := Npcs.skill_level(npc_id, Jobs.JOB_SKILL_AFFINITY[job])
				if level > best_level:
					best_level = level
					best_job = job
			npc["job"] = best_job
			npc["unique_skill"] = UniqueSkills.generate(best_job)
		# 2026-09-14追加: portrait==""は旧セーブ由来(または移行直後でまだ未割り当て)の印。
		# 血筋に応じた肖像を新規抽選する。
		if npc["portrait"] == "":
			npc["portrait"] = PortraitLibrary.generate(npc["innate_traits"].get("bloodline", ""))

	var parties_data := {}
	db.query("SELECT * FROM parties")
	for row in db.query_result:
		var party_id: int = int(row["id"])
		parties_data[party_id] = {
			"id": party_id,
			"name": String(row["name"]),
			"assigned_section": String(row["assigned_section"]),
			"status": int(row["status"]),
			"recovering_until_day": int(row["recovering_until_day"]),
			"post_clear_behavior": int(row["post_clear_behavior"]),
			"member_ids": [],
		}
	var had_saved_parties := not parties_data.is_empty()
	db.query("SELECT * FROM party_members ORDER BY party_id, order_index")
	for row in db.query_result:
		var party_id: int = int(row["party_id"])
		if parties_data.has(party_id):
			parties_data[party_id]["member_ids"].append(int(row["npc_id"]))
	Parties.load_state({"next_id": int(meta.get("party_next_id", 1)), "parties": parties_data})
	for party_id in Parties.parties.keys():
		for npc_id in Parties.parties[party_id]["member_ids"]:
			Npcs.set_party(npc_id, party_id)

	# 旧セーブ(パーティ制導入前)は誰もパーティに所属していない。NPCをid順に4人ずつ
	# グループ化して新規パーティを組む。旧モデルでは1NPC=1セクションの個別割り当てだった
	# ため、4人纏めた際にどのセクションを継承すべきか一意に決まらない。安全側に倒し、
	# 各パーティのassigned_sectionは空のまま(プレイヤーに手動で再割り当てしてもらう)にする。
	if not had_saved_parties and not Npcs.roster.is_empty():
		var ids: Array = Npcs.roster.keys()
		ids.sort()
		var chunk := []
		for npc_id in ids:
			chunk.append(npc_id)
			if chunk.size() == Parties.MAX_PARTY_SIZE:
				Parties.form_party(chunk)
				chunk = []
		if not chunk.is_empty():
			Parties.form_party(chunk)

	var progress := {}
	db.query("SELECT * FROM world_progress")
	for row in db.query_result:
		progress[String(row["node_id"])] = {
			"found": bool(row["found"]),
			"passed": bool(row["passed"]),
			"found_by_employed": bool(row.get("found_by_employed", 0)),
		}
	WorldMap.load_progress(progress)

	db.query("SELECT section_id FROM section_rewards")
	for row in db.query_result:
		WorldMap.mark_section_reward_claimed(String(row["section_id"]))

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
