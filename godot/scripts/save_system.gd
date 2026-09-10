extends Node
# ワールドの進行状態を保存・復元する。GDSQLite移行までの暫定としてJSONファイル保存
# を使う(docs/design.md 10章)。GodotのJSON.parse_stringは数値を必ずfloatで返し、
# Dictionaryキーも全て文字列になるため、int型で使っている値/キーは明示的に復元する。

const SAVE_PATH := "user://worldseeker_save.json"

func save_game() -> void:
	var data := {
		"funds": Economy.funds,
		"employ_cap": Economy.employ_cap,
		"facility_level": Economy.facility_level,
		"current_day": TimeSystem.current_day,
		"current_month": TimeSystem.current_month,
		"is_paused": TimeSystem.is_paused,
		"speed_multiplier": TimeSystem.speed_multiplier,
		"npcs": Npcs.save_state(),
		"board": Board.save_state(),
		"world_progress": WorldMap.save_progress(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var data = JSON.parse_string(file.get_as_text())
	if data == null:
		return false

	Economy.funds = int(data["funds"])
	Economy.employ_cap = int(data["employ_cap"])
	Economy.facility_level = int(data["facility_level"])
	TimeSystem.current_day = int(data["current_day"])
	TimeSystem.current_month = int(data["current_month"])
	TimeSystem.is_paused = data.get("is_paused", false)
	TimeSystem.speed_multiplier = data.get("speed_multiplier", 1.0)
	Npcs.load_state(data.get("npcs", {}))
	Board.load_state(data.get("board", {}))
	WorldMap.load_progress(data.get("world_progress", {}))
	return true
