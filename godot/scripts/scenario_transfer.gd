class_name ScenarioTransfer
# シナリオのzipの取り込み(PCのエディタで作ったシナリオを、スマホへ持ち込む)と、カスタムシナリオの一覧・削除。
# docs/scenario_editor.md「スマホへの持ち込み」。
#
# zipの形と検査の規則は、エディタ(tools/scenario-editor/server.js の parseScenarioZip)と同じ:
#   manifest.json(形式の印)、scenario.json、world.json、cast.json、events/<id>.json、images/<名前>.png
# 外から来るファイルなので、ファイル名は信用せず(決まった形の名前だけを拾い、一時フォルダには自分で決めた名前で書く)、
# 展開後の大きさ・ファイル数に上限を設け、中身は、ゲームが「あるはず」と前提にして読むキーまで確かめてから取り込む。
#
# 状態は持たない。取り込みは2段階: read_import_file()で検査して一時フォルダへ展開(まだ何も取り込まない)→
# 呼び出し側が確認を取る → install_import()で置く(やめる時はcancel_import())。
# autoloadは参照しない(--scriptの確認から、名前で直接呼べるようにするため)。

const FORMAT := "worldseeker-scenario"
const FORMAT_VERSION := 1
const TMP_DIR := "user://import_scenario_tmp"
const STAGED_DIR := "user://import_scenario_tmp/scenario"
const REPLACED_DIR := "user://scenario_replaced_tmp"
const MAX_ZIP_BYTES := 48 * 1024 * 1024
const MAX_ENTRIES := 1500
const MAX_ENTRY_BYTES := 4 * 1024 * 1024 # zipの中の1ファイル(画像1枚など)の、展開後の大きさ
const MAX_TOTAL_BYTES := 64 * 1024 * 1024
const MAX_JSON_BYTES := 2 * 1024 * 1024
const SCENARIO_ID_PATTERN := "^[a-z][a-z0-9_]{1,40}$"
const WORLD_ID_PATTERN := "^[a-z0-9][a-z0-9_]{0,60}$"
const EVENT_FILE_PATTERN := "^events/([a-z0-9][a-z0-9_]{0,80})\\.json$"
const IMAGE_FILE_PATTERN := "^images/([A-Za-z0-9_-]{1,60}\\.png)$"
const JSON_FILES := ["manifest.json", "scenario.json", "world.json", "cast.json"]
const PNG_SIGNATURE := [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

# 条件・効果の種類ごとの、必須のキーと型(ScenarioEventsが存在を前提に読むもの)
const CONDITION_KEYS := {
	"day_min": [["day", "number"]], "flag": [["flag", "string"]],
	"floor_found": [["floor", "string"]], "floor_passed": [["floor", "string"]],
	"section_entered": [["section", "string"]], "area_entered": [["area", "string"]],
}
const EFFECT_KEYS := {
	"set_flag": [["flag", "string"]], "funds": [["amount", "number"]],
	"grant_item": [["item", "string"]], "open_floor": [["floor", "string"]],
	"join": [["name", "string"], ["bloodline", "string"], ["job", "string"]],
}

# --- 取り込み ---

## 取り込み元のzip(path)を読んで検査し、一時フォルダへ展開する。この時点では何も取り込まない。
## 戻り値: {"ok": bool, "error": String, "id", "name", "description", "author", "floors", "events", "images",
##          "ignored"(拾わなかったファイルの数), "exists"(同じIDのカスタムシナリオが既にあるか)}
static func read_import_file(path: String) -> Dictionary:
	cancel_import()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return _error("ファイルを読み込めませんでした")
	if bytes.size() > MAX_ZIP_BYTES:
		return _error("ファイルが大きすぎます(シナリオのファイルではありません)")
	var directory := _central_directory(bytes)
	if directory.has("error"):
		return _error(directory["error"])
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var tmp_zip := TMP_DIR + "/in.zip"
	var tmp_file := FileAccess.open(tmp_zip, FileAccess.WRITE)
	if tmp_file == null:
		return _error("ファイルを一時保存できませんでした")
	tmp_file.store_buffer(bytes)
	tmp_file.close()
	var zip := ZIPReader.new()
	if zip.open(tmp_zip) != OK:
		cancel_import()
		return _error("シナリオのファイル(zip)ではありません")
	var result := _read_zip(zip)
	zip.close()
	DirAccess.remove_absolute(tmp_zip)
	if not result["ok"]:
		cancel_import()
	return result

## read_import_file()で検査したシナリオを、カスタムシナリオとして置く。同じIDのものが既にあれば置き換える
## (確認は呼び出し側で済ませておくこと)。置き換えに失敗したら、元のシナリオに戻す。
## 戻り値: {"ok": bool, "error": String, "id": String, "name": String, "replaced": bool}
static func install_import() -> Dictionary:
	var meta = ScenarioStore.read_json(STAGED_DIR + "/scenario.json")
	if not (meta is Dictionary) or not is_valid_scenario_id(String(meta.get("id", ""))):
		return {"ok": false, "error": "取り込む内容が見つかりません(もう一度ファイルを選んでください)", "id": "", "replaced": false}
	var id := String(meta["id"])
	var target := "%s/%s" % [ScenarioStore.CUSTOM_ROOT, id]
	DirAccess.make_dir_recursive_absolute(ScenarioStore.CUSTOM_ROOT)
	var replaced := DirAccess.dir_exists_absolute(target)
	if replaced:
		remove_dir_recursive(REPLACED_DIR)
		if DirAccess.rename_absolute(target, REPLACED_DIR) != OK:
			return {"ok": false, "error": "今のシナリオを置き換えられませんでした", "id": id, "replaced": false}
	if DirAccess.rename_absolute(STAGED_DIR, target) != OK:
		if replaced:
			DirAccess.rename_absolute(REPLACED_DIR, target) # 元に戻す
		return {"ok": false, "error": "シナリオを保存できませんでした", "id": id, "replaced": false}
	remove_dir_recursive(REPLACED_DIR)
	cancel_import()
	return {"ok": true, "error": "", "id": id, "name": String(meta.get("name", id)), "replaced": replaced}

## 展開した一時ファイルを消す(取り込みをやめる時、取り込みが終わった時)。
static func cancel_import() -> void:
	remove_dir_recursive(TMP_DIR)

# --- カスタムシナリオの一覧・削除 ---

## 端末に入っているカスタムシナリオ: [{id, name, description, floors, events, images}]
static func list_custom() -> Array:
	var out := []
	for entry in ScenarioStore.list_scenarios():
		if entry["source"] != "custom":
			continue
		var dir := "%s/%s" % [ScenarioStore.CUSTOM_ROOT, entry["id"]]
		var world = ScenarioStore.read_json(dir + "/world.json")
		var floors: int = world["nodes"].size() if world is Dictionary and world.get("nodes") is Array else 0
		out.append({
			"id": entry["id"], "name": entry["name"], "description": entry["description"],
			"floors": floors, "events": _count_files(dir + "/events", ".json"), "images": _count_files(dir + "/images", ".png"),
		})
	return out

## カスタムシナリオを、フォルダごと削除する。遊び始めているセーブは、その時点の内容(スナップショット)で続けられる
## (会話の画像だけは、このフォルダの外部参照なので、自動選択の画像に戻る)。
static func delete_custom(id: String) -> bool:
	if not is_valid_scenario_id(id):
		return false
	var dir := "%s/%s" % [ScenarioStore.CUSTOM_ROOT, id]
	if not DirAccess.dir_exists_absolute(dir):
		return false
	remove_dir_recursive(dir)
	return not DirAccess.dir_exists_absolute(dir)

static func is_valid_scenario_id(id: String) -> bool:
	return RegEx.create_from_string(SCENARIO_ID_PATTERN).search(id) != null

static func remove_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		remove_dir_recursive("%s/%s" % [path, sub])
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute("%s/%s" % [path, file_name])
	DirAccess.remove_absolute(path)

static func _count_files(dir: String, extension: String) -> int:
	var count := 0
	if not DirAccess.dir_exists_absolute(dir):
		return 0 # 画像の無いシナリオには、imagesフォルダが無い
	for file_name in DirAccess.get_files_at(dir):
		if String(file_name).ends_with(extension):
			count += 1
	return count

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

# --- zipの読み取り ---

## zipの中央ディレクトリを読み、展開後の大きさなどの申告を検査する。ZIPReaderは、申告された大きさで先にメモリを
## 確保してから展開するので、嘘の大きさ(展開爆弾)を、読む前に弾く。戻り値: {} か {"error": メッセージ}
static func _central_directory(bytes: PackedByteArray) -> Dictionary:
	var size := bytes.size()
	if size < 22:
		return {"error": "シナリオのファイル(zip)ではありません"}
	var eocd := -1
	var pos := size - 22
	var stop := maxi(0, size - 22 - 65535)
	while pos >= stop:
		if bytes.decode_u32(pos) == 0x06054b50:
			eocd = pos
			break
		pos -= 1
	if eocd < 0:
		return {"error": "シナリオのファイル(zip)ではありません"}
	var total := bytes.decode_u16(eocd + 10)
	var directory_size := bytes.decode_u32(eocd + 12)
	var directory_offset := bytes.decode_u32(eocd + 16)
	if total == 0xffff or directory_size == 0xffffffff or directory_offset == 0xffffffff:
		return {"error": "zip64には対応していません"}
	if total > MAX_ENTRIES:
		return {"error": "zipの中のファイルが多すぎます(%d個)" % total}
	if directory_offset + directory_size > size:
		return {"error": "zipファイルが壊れています"}
	pos = directory_offset
	var total_bytes := 0
	for _i in total:
		if pos + 46 > size or bytes.decode_u32(pos) != 0x02014b50:
			return {"error": "zipファイルが壊れています"}
		var flags := bytes.decode_u16(pos + 8)
		var compressed := bytes.decode_u32(pos + 20)
		var uncompressed := bytes.decode_u32(pos + 24)
		var name_length := bytes.decode_u16(pos + 28)
		var extra_length := bytes.decode_u16(pos + 30)
		var comment_length := bytes.decode_u16(pos + 32)
		if pos + 46 + name_length > size:
			return {"error": "zipファイルが壊れています"}
		var entry_name := bytes.slice(pos + 46, pos + 46 + name_length).get_string_from_utf8()
		pos += 46 + name_length + extra_length + comment_length
		if entry_name.ends_with("/"):
			continue
		if flags & 1 != 0:
			return {"error": "暗号化されたzipには対応していません"}
		if compressed == 0xffffffff or uncompressed == 0xffffffff:
			return {"error": "zip64には対応していません"}
		if uncompressed > MAX_ENTRY_BYTES:
			return {"error": "zipの中のファイルが大きすぎます"}
		total_bytes += uncompressed
		if total_bytes > MAX_TOTAL_BYTES:
			return {"error": "zipを展開した大きさが大きすぎます"}
	return {}

## 開いたzipから、決まった名前のファイルだけを拾い、全て検査して、一時フォルダへ書く。
static func _read_zip(zip: ZIPReader) -> Dictionary:
	var event_re := RegEx.create_from_string(EVENT_FILE_PATTERN)
	var image_re := RegEx.create_from_string(IMAGE_FILE_PATTERN)
	var accepted := {} # zip内の名前 -> PackedByteArray
	var event_ids := {} # zip内の名前 -> イベントID
	var ignored := 0
	for raw_name in zip.get_files():
		var entry_name := String(raw_name)
		if entry_name.ends_with("/"):
			continue
		var event_match := event_re.search(entry_name)
		if JSON_FILES.has(entry_name) or event_match != null or image_re.search(entry_name) != null:
			accepted[entry_name] = zip.read_file(entry_name)
			if event_match != null:
				event_ids[entry_name] = event_match.get_string(1)
		else:
			ignored += 1

	if not accepted.has("manifest.json"):
		return _error("WorldSeekerのシナリオのファイルではありません")
	var manifest = _parse_json(accepted["manifest.json"])
	if not (manifest is Dictionary) or manifest.get("format", "") != FORMAT:
		if manifest is Dictionary and manifest.get("format", "") == "worldseeker-saves":
			return _error("これはセーブのファイルです(シナリオのファイルではありません)")
		return _error("WorldSeekerのシナリオのファイルではありません")
	if int(manifest.get("version", 0)) > FORMAT_VERSION:
		return _error("新しい版のエディタで書き出したファイルです。ゲームを更新してください")
	if not accepted.has("scenario.json") or not accepted.has("world.json"):
		return _error("シナリオの必須ファイル(scenario.json / world.json)がありません")

	var meta = _parse_json(accepted["scenario.json"])
	if not (meta is Dictionary) or typeof(meta.get("id")) != TYPE_STRING or not is_valid_scenario_id(meta["id"]):
		return _error("scenario.jsonのIDが正しくありません")
	if int(meta.get("format", ScenarioStore.FORMAT)) > ScenarioStore.FORMAT:
		return _error("scenario.jsonが新しい形式です。ゲームを更新してください")
	if typeof(meta.get("name")) != TYPE_STRING:
		return _error("scenario.jsonに名前がありません")
	var world = _parse_json(accepted["world.json"])
	var world_error := validate_world(world)
	if world_error != "":
		return _error(world_error)
	if accepted.has("cast.json"):
		var cast = _parse_json(accepted["cast.json"])
		if not (cast is Array):
			return _error("cast.jsonの形式が正しくありません")
		for entry in cast:
			if not (entry is Dictionary) or typeof(entry.get("name")) != TYPE_STRING:
				return _error("cast.jsonの形式が正しくありません")
	var image_count := 0
	var event_count := 0
	for entry_name in accepted.keys():
		if event_ids.has(entry_name):
			var event_error := validate_event(_parse_json(accepted[entry_name]), event_ids[entry_name])
			if event_error != "":
				return _error(event_error)
			event_count += 1
		elif String(entry_name).begins_with("images/"):
			if not _is_png(accepted[entry_name]):
				return _error("画像がPNGではありません: %s" % entry_name)
			image_count += 1

	# 検査を全て通ったものだけを、決まった名前で一時フォルダへ書く(zipの中の名前は使わない: 上の正規表現で確かめた形だけ)
	for entry_name in accepted.keys():
		if entry_name == "manifest.json":
			continue # 形式の印は、置かない
		var target := "%s/%s" % [STAGED_DIR, entry_name]
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			return _error("ファイルを一時保存できませんでした")
		file.store_buffer(accepted[entry_name])
		file.close()
	return {
		"ok": true, "error": "", "id": String(meta["id"]), "name": String(meta["name"]),
		"description": String(meta.get("description", "")), "author": String(meta.get("author", "")),
		"floors": world["nodes"].size(), "events": event_count, "images": image_count, "ignored": ignored,
		"exists": DirAccess.dir_exists_absolute("%s/%s" % [ScenarioStore.CUSTOM_ROOT, meta["id"]]),
	}

static func _parse_json(bytes: PackedByteArray) -> Variant:
	if bytes.size() > MAX_JSON_BYTES:
		return null
	return JSON.parse_string(bytes.get_string_from_utf8())

static func _is_png(bytes: PackedByteArray) -> bool:
	if bytes.size() < 24:
		return false
	for i in PNG_SIGNATURE.size():
		if bytes[i] != PNG_SIGNATURE[i]:
			return false
	return true

static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

# --- 検査(エディタのserver.jsのvalidateWorldShape / validateGateShape / validateEventDeepと同じ規則) ---

## world.jsonの検査。ゲームが「あるはず」と前提にして読むキー(id・name・所属・ゲートの種類ごとのキー)と、
## 不正な技能名(読み込みの時点でエラーになる)を確かめる。問題が無ければ""、あれば理由。
static func validate_world(world: Variant) -> String:
	if not (world is Dictionary):
		return "world.jsonの形式が正しくありません"
	var id_re := RegEx.create_from_string(WORLD_ID_PATTERN)
	var ids := {}
	for key in ["items", "areas", "sections", "nodes"]:
		var list = world.get(key)
		if not (list is Array):
			return "world.jsonの%sが配列ではありません" % key
		var seen := {}
		for entry in list:
			if not (entry is Dictionary) or typeof(entry.get("id")) != TYPE_STRING or id_re.search(entry["id"]) == null:
				return "world.jsonの%sに、IDが正しくない項目があります" % key
			if typeof(entry.get("name")) != TYPE_STRING:
				return "world.jsonの%s(%s)に名前がありません" % [key, entry["id"]]
			if seen.has(entry["id"]):
				return "world.jsonの%sにIDの重複があります: %s" % [key, entry["id"]]
			seen[entry["id"]] = true
		ids[key] = seen
	for section in world["sections"]:
		if typeof(section.get("area")) != TYPE_STRING or not ids["areas"].has(section["area"]):
			return "セクション(%s)のエリアが正しくありません" % section["id"]
	for node in world["nodes"]:
		if typeof(node.get("section")) != TYPE_STRING or not ids["sections"].has(node["section"]):
			return "フロア(%s)のセクションが正しくありません" % node["id"]
		if node.has("connections"):
			if not (node["connections"] is Array):
				return "フロア(%s)の接続が正しくありません" % node["id"]
			for neighbor in node["connections"]:
				if typeof(neighbor) != TYPE_STRING:
					return "フロア(%s)の接続が正しくありません" % node["id"]
		var gate_error := _gate_error(node.get("gate", {}), String(node["id"]))
		if gate_error != "":
			return gate_error
	return ""

static func _gate_error(gate: Variant, floor_id: String) -> String:
	if not (gate is Dictionary):
		return "フロア(%s)のゲートが正しくありません" % floor_id
	if gate.is_empty():
		return ""
	match gate.get("type"):
		"combat":
			if gate.has("enemy_power") and not _is_number(gate["enemy_power"]):
				return "フロア(%s)のゲートの敵の戦闘力が正しくありません" % floor_id
		"skill":
			if typeof(gate.get("skill")) != TYPE_STRING or not SkillTypes.Skill.has(gate["skill"]):
				return "フロア(%s)のゲートの技能が正しくありません" % floor_id
			if not _is_number(gate.get("min_level")):
				return "フロア(%s)のゲートの必要レベルが正しくありません" % floor_id
		"item":
			if typeof(gate.get("item")) != TYPE_STRING:
				return "フロア(%s)のゲートのアイテムが正しくありません" % floor_id
		"innate_trait":
			if typeof(gate.get("trait")) != TYPE_STRING or typeof(gate.get("value")) != TYPE_STRING:
				return "フロア(%s)のゲートの特性が正しくありません" % floor_id
		_:
			return "フロア(%s)のゲートの種類が正しくありません" % floor_id
	return ""

## イベント1本の検査(ScenarioEventsが存在を前提に読むキーまで)。問題が無ければ""、あれば理由。
static func validate_event(event: Variant, file_id: String) -> String:
	var where := "イベント(%s)" % file_id
	if not (event is Dictionary):
		return "%sの形式が正しくありません" % where
	if event.get("id") != file_id:
		return "%sのIDがファイル名と一致しません" % where
	var trigger = event.get("trigger")
	if not (trigger is Dictionary) or not ["gate", "conditions", "system"].has(trigger.get("type")):
		return "%sの発生のしかたが正しくありません" % where
	var script = event.get("script")
	if not (script is Array):
		return "%sの会話がありません" % where
	for line in script:
		if not (line is Dictionary):
			return "%sの会話に、形式が正しくない行があります" % where
		if line.has("choices"):
			if not (line["choices"] is Array):
				return "%sの選択肢の形式が正しくありません" % where
			for choice in line["choices"]:
				if not (choice is Dictionary):
					return "%sの選択肢の形式が正しくありません" % where
	for pair in [["conditions", CONDITION_KEYS, "条件"], ["effects", EFFECT_KEYS, "効果"]]:
		var list = event.get(pair[0], [])
		if not (list is Array):
			return "%sの%sの形式が正しくありません" % [where, pair[2]]
		for item in list:
			if not (item is Dictionary) or not pair[1].has(item.get("type")):
				return "%sの%sに、対応していない種類があります" % [where, pair[2]]
			for required in pair[1][item["type"]]:
				var value = item.get(required[0])
				var type_ok: bool = _is_number(value) if required[1] == "number" else typeof(value) == TYPE_STRING
				if not type_ok:
					return "%sの%s(%s)の%sが正しくありません" % [where, pair[2], item["type"], required[0]]
	return ""
