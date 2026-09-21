extends Node
# ワールドの進行状態をSQLite(addons/godot-sqlite)で保存・復元する(docs/design.md 8.2/10章)。
#
# 保存対象は「プレイ進行状態」のみ(資金・探索者名簿・ワールド探索の発見/突破状態・掲示板ログ)。
# ワールドスキーマそのもの(エリア/セクション/フロア/ゲート/イベント台本の定義)は
# シナリオ(scenario_store.gd、docs/scenario_editor.md)が正本で、world_schema_db.gdが版管理して
# スナップショットにする(このファイルとは別のSQLite)。ここが持つのは、そのバージョンID(meta)と進行状態だけ。
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
	"scenario_flags", "scenario_events_fired",
]

## current_slot_idがこの値の間は「起動直後のまっさらな新規プレイ」を表し、どのスロット
## ファイルにも紐付いていない(design.md 8.2節、実セーブ誤上書き事故の再発防止)。
## この状態でsave_game()が呼ばれた場合のみ、その場で新しいスロットを割り当てる。
const NO_ACTIVE_SLOT := -1

var current_slot_id: int = NO_ACTIVE_SLOT
var current_slot_name: String = "" # 空文字なら一覧表示側が「スロットN」を代わりに使う
## オートセーブ(日次/終了時)を止めたい、という要望への対応(2026-09-13追加)。手動セーブ/
## 進行の複製機能があるので、オフにしても明示的な保存手段は残る。プレイヤー設定として
## worldseeker_meta.cfgに永続化する(スロットごとの値ではない)。
var autosave_enabled: bool = true


func _ready() -> void:
	# 2026-09-14: 起動時に前回のアクティブスロットを自動ロードする仕様をやめた(design.md
	# 10章)。診断・検証作業や単なる再起動のたびに実セーブへ意図せず触れてしまうリスクの
	# 根本原因だったため、「起動後は常に新規プレイから始まり、既存の進行を続けたい場合は
	# セーブパネルから明示的にロードする」という一般的なゲームの体験に合わせた。そのため
	# current_slot_idはworldseeker_meta.cfgから復元しない(autosave_enabledのみ復元する)。
	var cfg := ConfigFile.new()
	if cfg.load(META_PATH) == OK:
		autosave_enabled = bool(cfg.get_value("state", "autosave_enabled", true))

## 案内会話(場面名: intro_part1 導入・前編 / intro_part2 導入・後編 / party_formed 初雇用後 / retreat 初撤退)を、
## 既に見せたかどうか。プレイヤー個人の既知情報でありセーブスロットの進行状態ではないため、autosave_enabledと同じく
## worldseeker_meta.cfgへスロット非依存で永続化する(新しいスロットを作るたびに毎回見せ直さないため)。
## 2026-09-21: **シナリオごと**に持つ(シナリオが自前の導入会話を持てるため。自作のシナリオを初めて始める時に、その導入が流れる)。
## デフォルトシナリオは、従来のキー("state"の`tutorial_intro_seen`など)をそのまま使うので、見た記録は引き継がれる。
const TUTORIAL_LEGACY_KEYS := {
	"intro_part1": "tutorial_intro_seen", "intro_part2": "tutorial_assignment_followup_seen",
	"party_formed": "tutorial_party_seen", "retreat": "tutorial_retreat_seen",
}

## 今遊んでいるシナリオ(ScenarioEvents.info)の、案内会話の記録先: [セクション, キー]
func _tutorial_key(scene: String) -> Array:
	var source := String(ScenarioEvents.info.get("source", "default"))
	var scenario_id := String(ScenarioEvents.info.get("id", "default"))
	if source == "default" and scenario_id == "default":
		return ["state", TUTORIAL_LEGACY_KEYS.get(scene, "tutorial_%s_seen" % scene)]
	return ["tutorial_seen.%s.%s" % [source, scenario_id], scene]

func is_tutorial_seen(scene: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(META_PATH) != OK:
		return false
	var key := _tutorial_key(scene)
	return bool(cfg.get_value(key[0], key[1], false))

func mark_tutorial_seen(scene: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(META_PATH)
	var key := _tutorial_key(scene)
	cfg.set_value(key[0], key[1], true)
	cfg.save(META_PATH)

## 「イベント確認が出来ない」という要望への対応(2026-09-14)。一度見ると二度と出ない説明用イベント会話4種を、
## 今遊んでいるシナリオについて、すべて未視聴の状態に戻す(セーブスロットパネルの「イベント会話を
## リセットする」ボタンから呼ぶ、main.gd参照)。進行中のセーブデータ自体には触れない。
func reset_tutorial_flags() -> void:
	var cfg := ConfigFile.new()
	cfg.load(META_PATH)
	for scene in TUTORIAL_LEGACY_KEYS.keys():
		var key := _tutorial_key(scene)
		cfg.set_value(key[0], key[1], false)
	cfg.save(META_PATH)

## カスタムシナリオを削除した時に、そのシナリオの案内会話の「見た」記録も消す(同じIDで取り込み直したら、
## 導入会話がまた流れるように)。セーブスロットには触れない。
func forget_scenario_records(source: String, scenario_id: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(META_PATH) != OK:
		return
	var section := "tutorial_seen.%s.%s" % [source, scenario_id]
	if cfg.has_section(section):
		cfg.erase_section(section)
		cfg.save(META_PATH)

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

## 既存スロット一覧(スロットID順)。各スロットのDBを開いて概要(資金/日付/探索者数)だけ読む。
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
	var path := _slot_path(slot_id)
	var mtime := int(FileAccess.get_modified_time(path)) # 下の読み取りがファイルを書き換える前に取る
	var info := _peek_db(path, slot_id)
	# 最終更新の時刻を持たない古いセーブには、ファイルの更新日時を一度だけ書き足す(以後は、書き出しても取り込んでも
	# 日時が残る)。次にそのスロットで保存すれば、正確な時刻に置き換わる。
	if not info.is_empty() and int(info["saved_at"]) == 0 and mtime > 0:
		_backfill_saved_at(path, mtime)
		info["saved_at"] = mtime
	return info

func _backfill_saved_at(path: String, unix_time: int) -> void:
	var db := SQLite.new()
	db.path = path
	if not db.open_db():
		return
	db.query_with_bindings("DELETE FROM meta WHERE key = ?", ["saved_at"])
	db.query_with_bindings("INSERT INTO meta (key, value) VALUES (?, ?)", ["saved_at", unix_time])
	db.close_db()

## UNIX時刻(UTC)を、この端末の現地時刻の「2026/09/20 23:59」にする。記録が無い(0以下)なら「日時不明」。
func format_saved_at(unix_time: int) -> String:
	if unix_time <= 0:
		return "日時不明"
	var bias_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var t := Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%04d/%02d/%02d %02d:%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"]]

## セーブファイル(path)を開いて、一覧表示用の概要だけを読む。slot_idは返す辞書にそのまま入れる
## (取り込み前の一時ファイルでは、zip内の番号を入れる)。セーブとして読めなければ空の辞書。
func _peek_db(path: String, slot_id: int) -> Dictionary:
	var db := SQLite.new()
	db.path = path
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
		"name": String(meta.get("slot_name", "")),
		"funds": int(meta.get("funds", 0)),
		"day": int(meta.get("current_day", 0)),
		"month": int(meta.get("current_month", 0)),
		"npc_count": npc_count,
		"schema_version": String(meta.get("schema_version", "")),
		"saved_at": int(meta.get("saved_at", 0)),
		"scenario_name": String(meta.get("scenario_name", "")), # 遊んでいるシナリオの名前(旧セーブは空)
	}

## Economy/TimeSystem/Npcs/Parties等をまっさらな状態に戻し、design.md 4.7節の初期パーティ
## (購入・募集不要の4人)を無償で組む。起動時ブートストラップ(main.gdの_ready())と
## create_new_slot()の両方が使う共通処理。ディスクには一切触れない(スロットの作成/切替/
## 保存は呼び出し側の責務)。WorldMapの再構築も呼び出し側の責務とする: 起動直後は
## WorldSchemaDbが起動時にデフォルトシナリオで既に構築済みのため不要だが、既存スロットから
## 新規プレイへ切り替える場合はWorldSchemaDb.import_into_worldmap()で作り直す必要がある。
func start_fresh_session() -> void:
	Economy.reset()
	TimeSystem.reset()
	# 暦の起点はシナリオが決める(TimeSystem.start_year/start_monthのコメント参照)。呼び出し側は、先にワールドの
	# スナップショットを読み込んでおくこと(ScenarioEvents.infoがそのシナリオの情報になる)
	TimeSystem.start_year = int(ScenarioEvents.info.get("start_year", 0))
	TimeSystem.start_month = int(ScenarioEvents.info.get("start_month", 1))
	ScenarioEvents.reset_progress()
	Npcs.reset()
	Parties.reset()
	Recruitment.reset()
	Board.reset()
	ActionLog.reset()
	DailyLog.reset() # 毎日の動きはメモリだけ(セーブしない)。別のセーブの動きが混ざらないようにする
	var starter_ids := Npcs.create_starter_roster()
	Parties.form_party(starter_ids, "初期パーティ")

## 新規スロットを作成してアクティブにする(design.md 8.2「スキーマ再プレイ」)。
## ワールドスキーマDB(world_schema_db.gd)経由でWorldMapを再構築するため、
## GDScript直書き経路と同じ形の「まっさらな世界」から始まることをこの一手が保証する。
## 新規プレイは常に最新のワールドスキーマ(WorldSchemaDb.current_version_id)を使う。scenario_idを渡すと、
## そのシナリオ(scenario_source="default"/"custom")を今の内容で読み直して使う(読めなければ、今選んでいる
## シナリオのまま)。省略すると、今選んでいるシナリオの、今の内容(=エディタで直した最新)を使う。
func create_new_slot(display_name: String = "", scenario_id: String = "", scenario_source: String = "default") -> int:
	var next_id := _next_free_slot_id()
	if current_slot_id != NO_ACTIVE_SLOT:
		save_game() # 離れる前のスロットを保存(起動直後でまだどのスロットにも属していなければ何もしない)
	if scenario_id != "":
		WorldSchemaDb.use_scenario(scenario_id, scenario_source)
	elif not ScenarioEvents.info.is_empty():
		WorldSchemaDb.use_scenario(String(ScenarioEvents.info.get("id", "")), String(ScenarioEvents.info.get("source", "default")))
	WorldSchemaDb.import_into_worldmap(WorldSchemaDb.current_version_id)
	start_fresh_session() # ワールドの読み込みの後(暦の起点などをシナリオの情報から決めるため)
	_set_active_slot(next_id)
	current_slot_name = display_name
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
	# NO_ACTIVE_SLOT(起動直後のまっさらな新規プレイ)からロードする場合、保存すべき
	# 既存の進行が無いため、ここでsave_game()を呼んではいけない(呼ぶと、この後すぐ
	# 切り替える先とは無関係な「空のスロット」がその場で新規作成されてしまう)。
	if current_slot_id != NO_ACTIVE_SLOT and current_slot_id != slot_id:
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

## スロット名を変更する。アクティブなスロットでなくても(一覧から選んだだけの状態でも)
## 変更できるよう、対象がアクティブでなければそのスロットのDBを直接開いてmetaだけ書き換える
## (他のテーブルには触れない。アクティブな他スロットの進行を巻き込まないため)。
func rename_slot(slot_id: int, new_name: String) -> bool:
	if slot_id == current_slot_id:
		current_slot_name = new_name
		save_game()
		return true
	var path := _slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return false
	var db := SQLite.new()
	db.path = path
	if not db.open_db():
		return false
	_ensure_schema(db)
	db.query_with_bindings("DELETE FROM meta WHERE key = ?", ["slot_name"])
	db.query_with_bindings("INSERT INTO meta (key, value) VALUES (?, ?)", ["slot_name", new_name])
	db.close_db()
	return true

# --- エクスポート/インポート(2026-09-20、Androidで「セーブを別の端末/場所へ移したい」との要望) ---
#
# 全スロットを1つのzipにまとめて、プレイヤーが選んだ場所へ書き出す。取り込みは、そのzipを読み、含まれる
# スロットのうち選んだものを新しいスロットとして追加する(既存のスロットは上書きしない)。
# 保存先/取り込み元の選択は、OSのファイル選択(main.gdのFileDialog)に任せる。Androidでは
# ストレージアクセスフレームワークの画面が開き、Googleドライブ・ダウンロード・USBなどを選べる
# (その場合のパスは`content://`のURIで、FileAccessでそのまま読み書きできる)。
#
# zipの中身:
#   manifest.json                        形式の名前と版。別のzipを取り込もうとして壊さないための確認用
#   slots/slot_<番号>.sqlite             スロットのセーブファイルそのもの(番号は取り込み時に振り直す)
#   schemas/schema_<64桁の16進>.sqlite   スロットが使っているワールドスキーマ(world_schema_db.gd)。
#                                        別のビルドで作ったセーブでも、同じ世界で取り込めるように同梱する
#                                        (この端末に同じバージョンがあれば使わない)。
const EXPORT_FORMAT := "worldseeker-saves"
const EXPORT_FORMAT_VERSION := 1
const EXPORT_TMP_ZIP := "user://export_tmp.zip"
const IMPORT_TMP_DIR := "user://import_tmp"
const IMPORT_MAX_BYTES := 64 * 1024 * 1024 # セーブは1つ数百KB。これを超えるファイルは、別物として取り込まない
const SQLITE_MAGIC := "SQLite format 3"

## 書き出しファイルの既定の名前(保存先の選択画面に最初から入れておく)。
func default_export_file_name() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "worldseeker_saves_%04d%02d%02d_%02d%02d.zip" % [t["year"], t["month"], t["day"], t["hour"], t["minute"]]

## 全スロットを1つのzipにまとめ、pathへ書く。今のスロットは、先に保存して最新の状態にする。
## 戻り値は書き出したスロットの数。失敗(スロットが無い/書けない)は-1。
func export_all_slots(path: String) -> int:
	if current_slot_id != NO_ACTIVE_SLOT:
		save_game()
	var slots := list_slots()
	if slots.is_empty():
		return -1
	var zip := ZIPPacker.new()
	if zip.open(EXPORT_TMP_ZIP) != OK:
		return -1
	var versions := {}
	var count := 0
	for slot in slots:
		var slot_id: int = slot["slot_id"]
		var bytes := FileAccess.get_file_as_bytes(_slot_path(slot_id))
		if bytes.is_empty():
			continue
		_zip_add(zip, "slots/slot_%d.sqlite" % slot_id, bytes)
		count += 1
		var version := String(slot.get("schema_version", ""))
		if version != "":
			versions[version] = true
	for version in versions:
		var schema_path := WorldSchemaDb.version_file_path(version)
		if FileAccess.file_exists(schema_path):
			_zip_add(zip, "schemas/schema_%s.sqlite" % version, FileAccess.get_file_as_bytes(schema_path))
	var manifest := {
		"format": EXPORT_FORMAT,
		"version": EXPORT_FORMAT_VERSION,
		"exported_at": Time.get_datetime_string_from_system(),
		"slot_count": count,
	}
	_zip_add(zip, "manifest.json", JSON.stringify(manifest).to_utf8_buffer())
	zip.close()
	if count == 0:
		DirAccess.remove_absolute(EXPORT_TMP_ZIP)
		return -1
	# 保存先は、まず手元(user://)にzipを完成させてから書き写す。保存先がAndroidの`content://`だと、
	# ZIPPackerが直接は書けないため。
	var out := FileAccess.open(path, FileAccess.WRITE)
	var written := false
	if out != null:
		out.store_buffer(FileAccess.get_file_as_bytes(EXPORT_TMP_ZIP))
		written = out.get_error() == OK
		out.close()
	DirAccess.remove_absolute(EXPORT_TMP_ZIP)
	return count if written else -1

func _zip_add(zip: ZIPPacker, name_in_zip: String, bytes: PackedByteArray) -> void:
	zip.start_file(name_in_zip)
	zip.write_file(bytes)
	zip.close_file()

## 取り込み元のzip(path)を読み、含まれるスロットの一覧を返す。この時点では何も取り込まない
## (一時フォルダ(user://import_tmp)に展開するだけ)。実際の取り込みはimport_slots()、やめる時はcancel_import()。
## 戻り値: {"ok": bool, "error": String, "slots": [{"key": int(zip内の番号), "name", "funds", "day", "month", "npc_count", ...}]}
func read_import_file(path: String) -> Dictionary:
	cancel_import()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return _import_error("ファイルを読み込めませんでした")
	if bytes.size() > IMPORT_MAX_BYTES:
		return _import_error("ファイルが大きすぎます(セーブのファイルではありません)")
	DirAccess.make_dir_recursive_absolute(IMPORT_TMP_DIR)
	var tmp_zip := IMPORT_TMP_DIR + "/in.zip"
	var tmp_file := FileAccess.open(tmp_zip, FileAccess.WRITE)
	if tmp_file == null:
		return _import_error("ファイルを一時保存できませんでした")
	tmp_file.store_buffer(bytes)
	tmp_file.close()
	var zip := ZIPReader.new()
	if zip.open(tmp_zip) != OK:
		cancel_import()
		return _import_error("セーブのファイル(zip)ではありません")
	var files := zip.get_files()
	var manifest = null
	if "manifest.json" in files:
		manifest = JSON.parse_string(zip.read_file("manifest.json").get_string_from_utf8())
	if not (manifest is Dictionary) or manifest.get("format", "") != EXPORT_FORMAT:
		zip.close()
		cancel_import()
		return _import_error("WorldSeekerのセーブのファイルではありません")
	if int(manifest.get("version", 0)) > EXPORT_FORMAT_VERSION:
		zip.close()
		cancel_import()
		return _import_error("新しい版のゲームで書き出したファイルです。ゲームを更新してください")
	# zip内の名前は信用せず、決まった形の名前だけを拾い、一時フォルダには自分で決めた名前で書く
	# (`../`などで意図しない場所へ書かれるのを防ぐ)。
	var slot_re := RegEx.create_from_string("^slots/slot_(\\d+)\\.sqlite$")
	var schema_re := RegEx.create_from_string("^schemas/schema_([0-9a-f]{64})\\.sqlite$")
	var keys: Array = []
	for file_name in files:
		var slot_match := slot_re.search(file_name)
		var schema_match := schema_re.search(file_name)
		if slot_match == null and schema_match == null:
			continue
		var content := zip.read_file(file_name)
		if content.size() > IMPORT_MAX_BYTES or not _looks_like_sqlite(content):
			continue
		var target := ""
		if slot_match != null:
			var key := int(slot_match.get_string(1))
			keys.append(key)
			target = "%s/slot_%d.sqlite" % [IMPORT_TMP_DIR, key]
		else:
			target = "%s/schema_%s.sqlite" % [IMPORT_TMP_DIR, schema_match.get_string(1)]
		var target_file := FileAccess.open(target, FileAccess.WRITE)
		if target_file != null:
			target_file.store_buffer(content)
			target_file.close()
	zip.close()
	DirAccess.remove_absolute(tmp_zip)
	keys.sort()
	var slots: Array = []
	for key in keys:
		var info := _peek_db("%s/slot_%d.sqlite" % [IMPORT_TMP_DIR, key], key)
		if not info.is_empty():
			info["key"] = key
			slots.append(info)
	if slots.is_empty():
		cancel_import()
		return _import_error("取り込めるセーブが入っていませんでした")
	return {"ok": true, "error": "", "slots": slots}

func _import_error(message: String) -> Dictionary:
	return {"ok": false, "error": message, "slots": []}

func _looks_like_sqlite(content: PackedByteArray) -> bool:
	return content.size() > 100 and content.slice(0, SQLITE_MAGIC.length()).get_string_from_ascii() == SQLITE_MAGIC

## read_import_file()で読んだスロットのうち、keys(zip内の番号)で選んだものを、新しいスロットとして追加する。
## 既存のスロットは上書きせず、アクティブなスロットも変えない。追加したスロットの番号の配列を返す。
## 同梱されていたワールドスキーマのうち、この端末に無いバージョンも一緒に取り込む。
func import_slots(keys: Array) -> Array:
	var new_ids: Array = []
	DirAccess.make_dir_recursive_absolute(WorldSchemaDb.SCHEMA_DIR)
	DirAccess.make_dir_recursive_absolute(SLOT_DIR)
	for file_name in DirAccess.get_files_at(IMPORT_TMP_DIR):
		if file_name.begins_with("schema_"):
			var dest := "%s/%s" % [WorldSchemaDb.SCHEMA_DIR, file_name]
			if not FileAccess.file_exists(dest): # 内容が版の名前(ハッシュ)になっているので、同名なら同じ中身
				DirAccess.copy_absolute("%s/%s" % [IMPORT_TMP_DIR, file_name], dest)
	for key in keys:
		var src := "%s/slot_%d.sqlite" % [IMPORT_TMP_DIR, int(key)]
		if not FileAccess.file_exists(src):
			continue
		var new_id := _next_free_slot_id()
		if DirAccess.copy_absolute(src, _slot_path(new_id)) != OK:
			continue
		_repin_missing_schema_version(new_id)
		new_ids.append(new_id)
	cancel_import()
	return new_ids

## 取り込んだスロットが記録しているワールドスキーマのバージョンが、この端末に無ければ(zipに同梱されて
## いなかった場合)、この端末の最新のバージョンに付け替える。付け替えないと、ロードした時にWorldMapが
## 更新されず、直前に開いていたスロットの世界のまま進行を上書きしてしまう(switch_to_slotの説明参照)。
func _repin_missing_schema_version(slot_id: int) -> void:
	var version := get_slot_schema_version(slot_id)
	if version == "" or FileAccess.file_exists(WorldSchemaDb.version_file_path(version)):
		return
	var db := SQLite.new()
	db.path = _slot_path(slot_id)
	if not db.open_db():
		return
	db.query_with_bindings("DELETE FROM meta WHERE key = ?", ["schema_version"])
	db.query_with_bindings("INSERT INTO meta (key, value) VALUES (?, ?)", ["schema_version", WorldSchemaDb.current_version_id])
	db.close_db()

## read_import_file()が一時フォルダに展開したものを消す(取り込みをやめる時、取り込みが終わった時)。
func cancel_import() -> void:
	if not DirAccess.dir_exists_absolute(IMPORT_TMP_DIR):
		return
	for file_name in DirAccess.get_files_at(IMPORT_TMP_DIR):
		DirAccess.remove_absolute("%s/%s" % [IMPORT_TMP_DIR, file_name])
	DirAccess.remove_absolute(IMPORT_TMP_DIR)

## 行動ログビューアー用: 現在のスロットのaction_logを取得する(npc_id<0で全探索者分)。
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
	# 2026-09-15追加。完全踏破済みセクションでの周回(ループ)機能の開始日(exploration.gd参照)。
	_ensure_column(db, "parties", "lap_start_day", "INTEGER DEFAULT -1")
	# 2026-09-20追加。戦力不足で退避中のパーティの、戻り先のセクションと、勝てなかったフロア(exploration.gd参照)。
	_ensure_column(db, "parties", "return_section", "TEXT DEFAULT ''")
	_ensure_column(db, "parties", "return_node", "TEXT DEFAULT ''")
	db.query("CREATE TABLE IF NOT EXISTS party_members (party_id INTEGER, npc_id INTEGER, order_index INTEGER, PRIMARY KEY (party_id, npc_id))")
	db.query("CREATE TABLE IF NOT EXISTS section_rewards (section_id TEXT PRIMARY KEY)")
	db.query("CREATE TABLE IF NOT EXISTS board_entries (seq INTEGER PRIMARY KEY AUTOINCREMENT, day INTEGER, text TEXT, importance INTEGER, source TEXT)")
	db.query("CREATE TABLE IF NOT EXISTS board_threads (thread_id TEXT PRIMARY KEY, title TEXT)")
	db.query("CREATE TABLE IF NOT EXISTS board_thread_entries (seq INTEGER PRIMARY KEY AUTOINCREMENT, thread_id TEXT, day INTEGER, text TEXT, importance INTEGER, source TEXT)")
	# 2026-09-21追加。シナリオのイベントの進行状態(scenario_events.gd): 立っているフラグと、発生済みのイベント。
	db.query("CREATE TABLE IF NOT EXISTS scenario_flags (flag TEXT PRIMARY KEY)")
	db.query("CREATE TABLE IF NOT EXISTS scenario_events_fired (event_id TEXT PRIMARY KEY, count INTEGER, day INTEGER)")
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
	if current_slot_id == NO_ACTIVE_SLOT:
		# 起動直後のまっさらな新規プレイで、スロットを明示的に選ぶ前に保存(手動セーブ/
		# オートセーブ/終了時保存のいずれか)が呼ばれた。この時点で初めて新しいスロットを
		# 割り当てる(「新規プレイの保存先は必ず新しいスロット」という方針を、
		# 「新規プレイを開始する」ボタンを経由しない場合にも一貫させるための入り口)。
		_set_active_slot(_next_free_slot_id())
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
		"slot_name": current_slot_name,
		"funds": Economy.funds,
		"employ_cap": Economy.employ_cap,
		"facility_level": Economy.facility_level,
		"current_day": TimeSystem.current_day,
		"current_month": TimeSystem.current_month,
		"is_paused": 1 if TimeSystem.is_paused else 0,
		"speed_multiplier": TimeSystem.speed_multiplier,
		"start_year": TimeSystem.start_year,
		"start_month": TimeSystem.start_month,
		# 最終更新の時刻(UNIX時刻、UTC)。スロット一覧に出す(2026-09-20)。ファイルの更新日時ではなくmetaに持つのは、
		# 名前の変更や取り込み(ファイルのコピー)でファイルの日時が変わっても、「進行を最後に保存した時刻」を保つため。
		"saved_at": int(Time.get_unix_time_from_system()),
	}
	var npc_data: Dictionary = Npcs.save_state()
	meta["npc_next_id"] = npc_data["next_id"]
	ActionLog.ensure_run_id()
	meta["run_id"] = ActionLog.run_id
	# WorldMapが今実際に読み込んでいるスキーマバージョンを記録しておく(古いバージョンでも良い。
	# world_schema_db.gdのコメント参照)。次回このスロットを開く時にswitch_to_slot()が使う。
	meta["schema_version"] = WorldSchemaDb.active_version_id
	meta["scenario_name"] = String(ScenarioEvents.info.get("name", ""))
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
			"INSERT INTO parties (id, name, assigned_section, status, recovering_until_day, post_clear_behavior, lap_start_day, return_section, return_node) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
			[party_id, party["name"], party["assigned_section"], party["status"], party["recovering_until_day"], party["post_clear_behavior"], party.get("lap_start_day", -1), party.get("return_section", ""), party.get("return_node", "")])
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

	var scenario_state: Dictionary = ScenarioEvents.save_state()
	for flag in scenario_state["flags"]:
		db.query_with_bindings("INSERT INTO scenario_flags (flag) VALUES (?)", [flag])
	for event_id in scenario_state["fired"].keys():
		var record: Dictionary = scenario_state["fired"][event_id]
		db.query_with_bindings("INSERT INTO scenario_events_fired (event_id, count, day) VALUES (?, ?, ?)",
			[event_id, record["count"], record["day"]])

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

	current_slot_name = String(meta.get("slot_name", ""))
	Economy.funds = int(meta.get("funds", Economy.funds))
	Economy.employ_cap = int(meta.get("employ_cap", Economy.employ_cap))
	Economy.facility_level = int(meta.get("facility_level", Economy.facility_level))
	TimeSystem.current_day = int(meta.get("current_day", TimeSystem.current_day))
	TimeSystem.current_month = int(meta.get("current_month", TimeSystem.current_month))
	# 保存されるのは「月末の待ち」だけ(月末の日=日数が30の倍数で、開始直後ではない)。それ以外の一時停止は、
	# 過去のバージョンが会話中の停止を保存してしまったもので、復元すると月の途中で『次の月へ』が出て時間が止まる
	# (2026-09-21、ロードすると3月22日なのに止まっていた)ため、ロード時に取り除く。
	var saved_paused := bool(int(meta.get("is_paused", 0)))
	var at_month_end: bool = TimeSystem.current_day > 0 and TimeSystem.current_day % TimeSystem.DAYS_PER_MONTH == 0
	TimeSystem.is_paused = saved_paused and at_month_end
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
			# Npcs.hire()と同様、"max_hp_flat"固有スキルなら最大HPを底上げする(既存のhpは
			# そのまま、最大値だけ引き上げる。負傷中の探索者を不当に全回復させないため)。
			if npc["unique_skill"].get("effect_type", "") == "max_hp_flat":
				npc["max_hp"] = float(npc["max_hp"]) + float(npc["unique_skill"]["value"])
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
			"lap_start_day": int(row.get("lap_start_day", -1)),
			"return_section": String(row.get("return_section", "")),
			"return_node": String(row.get("return_node", "")),
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

	# 旧セーブ(パーティ制導入前)は誰もパーティに所属していない。探索者をid順に4人ずつ
	# グループ化して新規パーティを組む。旧モデルでは1探索者=1セクションの個別割り当てだった
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
	DailyLog.reset() # 毎日の動きはセーブしない: ロード直後は空から

	var scenario_flags := []
	db.query("SELECT flag FROM scenario_flags")
	for row in db.query_result:
		scenario_flags.append(String(row["flag"]))
	var scenario_fired := {}
	db.query("SELECT event_id, count, day FROM scenario_events_fired")
	for row in db.query_result:
		scenario_fired[String(row["event_id"])] = {"count": int(row["count"]), "day": int(row["day"])}
	ScenarioEvents.load_state({"flags": scenario_flags, "fired": scenario_fired})

	db.close_db()
	return true
