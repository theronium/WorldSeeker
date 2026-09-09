extends Node
# 暫定のJSON保存。ワールドスキーマ/リプレイログの本実装ではGDSQLiteへの移行を想定(docs/design.md 10章)。

const SAVE_PATH := "user://worldseeker_save.json"

func save_game() -> void:
	var data := {
		"funds": Economy.funds,
		"employ_cap": Economy.employ_cap,
		"facility_level": Economy.facility_level,
		"current_day": TimeSystem.current_day,
		"current_month": TimeSystem.current_month,
		"roster": Npcs.roster,
		"board": Board.entries,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	if data == null:
		return false
	Economy.funds = data["funds"]
	Economy.employ_cap = data["employ_cap"]
	Economy.facility_level = data["facility_level"]
	TimeSystem.current_day = data["current_day"]
	TimeSystem.current_month = data["current_month"]
	Npcs.roster = data["roster"]
	Board.entries = data["board"]
	return true
