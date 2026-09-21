# 使い捨ての確認用スクリプト(2026-09-21)。シナリオのzipの取り込み(スマホへの持ち込み)の確認:
# エディタ(Node)が書き出したzipを、ゲームが検査して取り込み、そのシナリオで新規プレイでき、上書き・削除ができるか。
# 不正なzip(セーブのファイル・不正なID/技能/効果/画像・展開爆弾・zipでないもの)を、何も取り込まずに断るか。
# 前処理(隔離したAPPDATAの、zipの置き場へ書き出す):
#   APPDATA=<隔離した空のディレクトリ> node tools/scenario-editor/test/make_transfer_zips.js <APPDATA>/Godot/app_userdata/WorldSeeker/transfer_test
# 実行: APPDATA=<同じディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
extends SceneTree

const DIR := "user://transfer_test"

var _ran := false
var _completed := false # _run()が最後まで走ったか(途中でスクリプトエラーが出ても、失敗0件で「成功」と出ないようにする)
var _fails := 0

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	if not _completed:
		print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
	else:
		print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
	return true

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

func _custom_ids() -> Array:
	return ScenarioTransfer.list_custom().map(func(e): return e["id"])

func _expect_rejected(file_name: String, fragment: String) -> void:
	var result := ScenarioTransfer.read_import_file("%s/%s" % [DIR, file_name])
	_check("不正: %s は断られる(%s)" % [file_name, fragment], not result["ok"] and String(result["error"]).contains(fragment), String(result.get("error", "")))
	_check("不正: %s は一時ファイルを残さず、何も取り込まない" % file_name, not DirAccess.dir_exists_absolute(ScenarioTransfer.TMP_DIR) and _custom_ids().is_empty(), str(_custom_ids()))

func _run() -> void:
	var save = root.get_node("SaveSystem"); var world_map = root.get_node("WorldMap"); var scenario = root.get_node("ScenarioEvents")
	var portraits = load("res://scripts/event_portraits.gd") # EventPortraitsはautoloadを参照するので、実行時に読む

	var expected_text := FileAccess.get_file_as_string(DIR + "/expected.json")
	if expected_text == "":
		print("NG  期待値(expected.json)が無い。先にmake_transfer_zips.jsを実行すること")
		_fails += 1
		return
	var expected: Dictionary = JSON.parse_string(expected_text)
	_check("前提: カスタムシナリオはまだ無い", _custom_ids().is_empty())

	# --- 不正なファイルを、何も取り込まずに断る ---
	_expect_rejected("not_a_zip.zip", "zip")
	_expect_rejected("bad_saves_format.zip", "セーブのファイル")
	_expect_rejected("bad_newer_version.zip", "新しい版")
	_expect_rejected("bad_no_manifest.zip", "シナリオのファイルではありません")
	_expect_rejected("bad_id.zip", "ID")
	_expect_rejected("bad_skill.zip", "技能")
	_expect_rejected("bad_gate_key.zip", "必要レベル")
	_expect_rejected("bad_section.zip", "セクション")
	_expect_rejected("bad_duplicate.zip", "重複")
	_expect_rejected("bad_effect.zip", "効果")
	_expect_rejected("bad_image.zip", "PNG")
	_expect_rejected("bad_bomb.zip", "大きすぎ")
	var missing := ScenarioTransfer.read_import_file(DIR + "/no_such_file.zip")
	_check("不正: 存在しないファイルは断られる", not missing["ok"])

	# --- 正常: エディタが書き出したzipを取り込む ---
	var read := ScenarioTransfer.read_import_file(DIR + "/transfer_one.zip")
	_check("検査: 正常なzipを読める", read["ok"], String(read.get("error", "")))
	_check("検査: ID・名前・作者・数(フロア%d・イベント%d本・画像1枚)" % [int(expected["floors"]), int(expected["one_events"])],
		read["id"] == "transfer_one" and read["name"] == "持ち込み試験" and read["author"] == "試験者" and read["floors"] == int(expected["floors"]) and read["events"] == int(expected["one_events"]) and read["images"] == 1, str(read))
	_check("検査: 同じIDはまだ無い(exists=false)", read["exists"] == false)
	_check("検査の段階では、まだ何も取り込まれていない", _custom_ids().is_empty())
	var installed := ScenarioTransfer.install_import()
	_check("取り込み: 成功し、置き換えではない", installed["ok"] and installed["id"] == "transfer_one" and installed["replaced"] == false and installed["name"] == "持ち込み試験", str(installed))
	_check("取り込み: 一時ファイルが片付いている", not DirAccess.dir_exists_absolute(ScenarioTransfer.TMP_DIR))
	_check("取り込み: フォルダの中身(scenario/world/cast/events/images)", FileAccess.file_exists("user://scenarios/transfer_one/world.json") and FileAccess.file_exists("user://scenarios/transfer_one/cast.json") and FileAccess.file_exists("user://scenarios/transfer_one/images/hero.png") and DirAccess.get_files_at("user://scenarios/transfer_one/events").size() == int(expected["one_events"]) and not FileAccess.file_exists("user://scenarios/transfer_one/manifest.json"))
	var listed := ScenarioTransfer.list_custom()
	_check("一覧: カスタムシナリオに出る(数も合う)", listed.size() == 1 and listed[0]["id"] == "transfer_one" and listed[0]["floors"] == int(expected["floors"]) and listed[0]["events"] == int(expected["one_events"]) and listed[0]["images"] == 1, str(listed))
	_check("一覧: 新規プレイの選択肢(ScenarioStore)にも出る", ScenarioStore.list_scenarios().any(func(s): return s["id"] == "transfer_one" and s["source"] == "custom"))

	# --- そのシナリオで新規プレイできる(エディタの書き出し→ゲームの取り込み→遊べる、の通し) ---
	var slot: int = save.create_new_slot("持ち込み", "transfer_one", "custom")
	_check("新規プレイ: 取り込んだ世界が読み込まれた(フロア%d)" % int(expected["floors"]), scenario.info.get("id", "") == "transfer_one" and world_map.nodes.size() == int(expected["floors"]), "%s %d" % [scenario.info.get("id", ""), world_map.nodes.size()])
	_check("新規プレイ: ID変更していないフロアの会話が引ける", not scenario.gate_event("old_shrine", true).is_empty())
	_check("新規プレイ: 同梱した画像(@hero.png)を読める", portraits.load_texture("@hero.png") != null)

	# --- 同じIDを取り込み直す(上書き) ---
	var read_two := ScenarioTransfer.read_import_file(DIR + "/transfer_two.zip")
	_check("上書き: 同じIDが既にあると分かる(exists=true)", read_two["ok"] and read_two["exists"] == true, str(read_two))
	var installed_two := ScenarioTransfer.install_import()
	_check("上書き: 置き換えとして成功", installed_two["ok"] and installed_two["replaced"] == true)
	var reloaded := ScenarioStore.load_scenario("transfer_one", "custom")
	_check("上書き: 新しい内容になった(名前・イベントの数。古い画像は消える)", reloaded["scenario"]["name"] == "持ち込み試験(改訂版)" and reloaded["events"].size() == int(expected["two_events"]) and not FileAccess.file_exists("user://scenarios/transfer_one/images/hero.png"), "%s %d" % [reloaded["scenario"]["name"], reloaded["events"].size()])
	_check("上書き: 置き換え用の一時フォルダが残っていない", not DirAccess.dir_exists_absolute(ScenarioTransfer.REPLACED_DIR) and not DirAccess.dir_exists_absolute(ScenarioTransfer.TMP_DIR))
	_check("上書き: 一覧は1件のまま", _custom_ids() == ["transfer_one"])

	# --- 遊び始めているセーブは、上書き・削除の後も、遊び始めた時点の内容で続く ---
	save.create_new_slot("標準", "default", "default")
	save.switch_to_slot(slot)
	_check("既存セーブ: 上書き後も、遊び始めた時点の内容(旧版の名前・イベント)のまま", scenario.info.get("name", "") == "持ち込み試験" and scenario.events.size() == int(expected["one_events"]), "%s %d" % [scenario.info.get("name", ""), scenario.events.size()])

	# --- 相対パス・余計なファイルは無視され、外へは書かれない ---
	var trav := ScenarioTransfer.read_import_file(DIR + "/traversal.zip")
	_check("相対パス: 決まった名前だけを拾う(無視したファイル3つ)", trav["ok"] and trav["ignored"] == 3, str(trav.get("ignored", "?")))
	ScenarioTransfer.install_import()
	_check("相対パス: 外へ書かれていない", not FileAccess.file_exists("user://evil.txt") and not FileAccess.file_exists("user://scenarios/evil.txt") and not FileAccess.file_exists("user://scenarios/escape.json") and not FileAccess.file_exists("user://scenarios/transfer_trav/notes.txt"))

	# --- 削除 ---
	_check("削除: 不正なID(../)は拒否される", not ScenarioTransfer.delete_custom("../scenarios") and not ScenarioTransfer.delete_custom("") and not ScenarioTransfer.delete_custom("Default"))
	_check("削除: 存在しないIDはfalse", not ScenarioTransfer.delete_custom("no_such_one"))
	_check("削除: 取り込んだシナリオを削除できる", ScenarioTransfer.delete_custom("transfer_one") and not DirAccess.dir_exists_absolute("user://scenarios/transfer_one"))
	_check("削除: 一覧から消え、もう1つは残る", _custom_ids() == ["transfer_trav"], str(_custom_ids()))
	_check("削除: 標準のシナリオは無事", ScenarioStore.list_scenarios().any(func(s): return s["id"] == "default" and s["source"] == "default"))
	save.switch_to_slot(slot)
	_check("削除後: 遊び始めているセーブは、そのまま遊べる(スナップショット)", scenario.info.get("id", "") == "transfer_one" and world_map.nodes.size() == int(expected["floors"]), "%s %d" % [scenario.info.get("id", ""), world_map.nodes.size()])
	# 案内会話の「見た」記録の掃除
	save.mark_tutorial_seen("intro_part1")
	_check("記録: 削除するシナリオの「見た」記録は付いている", save.is_tutorial_seen("intro_part1"))
	save.forget_scenario_records("custom", "transfer_one")
	_check("記録: 削除の時に消すと、見ていない状態に戻る", not save.is_tutorial_seen("intro_part1"))
	ScenarioTransfer.delete_custom("transfer_trav")
	_check("片付け: カスタムシナリオが全て無くなった", _custom_ids().is_empty())
	_completed = true
