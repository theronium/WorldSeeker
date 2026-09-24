# 使い捨ての確認用スクリプト(2026-09-21)。シナリオの取り込み・カスタムシナリオの管理の、メイン画面の操作の通し:
# メイン画面を実際に組み立て、取り込みのボタンの先(ファイルを選んだ後の確認画面・上書きの確認・取り込み・一覧・削除・
# 戻るキーでのやめる)を、画面の関数を直接呼んで確かめる(OSのファイル選択だけは、選んだ後の関数を直接呼ぶ)。
# zipの用意は、sim_scenario_transfer.gdと同じ(その前処理を先に実行しておく)。必ずAPPDATAを隔離する。
# 実行: APPDATA=<隔離したディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
extends SceneTree

const DIR := "user://transfer_test"

var _frames := 0
var _main: Node
var _fails := 0
var _completed := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	if _frames == 5:
		_phase1()
		return false
	if _frames == 9: # 削除の後に、一覧が開き直される(call_deferred)のを待つ
		_phase2()
		if not _completed:
			print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
		else:
			print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
		return true
	return false

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

func _option_ids() -> Array:
	var ids := []
	for i in _main.new_game_scenario_option.item_count:
		ids.append(_main.new_game_scenario_option.get_item_metadata(i)["id"])
	return ids

func _phase1() -> void:
	var dialogue = root.get_node("EventDialogue")
	while dialogue.is_active:
		dialogue.advance() # 起動直後の導入会話を進める
	_main._on_open_slots_pressed()
	var status: Label = _main.manual_save_status_label
	_check("前提: ボタンとダイアログが組み立てられている", _main.scenario_import_confirm != null and _main.scenario_manage_dialog != null and _main.scenario_delete_confirm != null and _main.scenario_import_file_dialog != null)
	_check("前提: 選べるシナリオは標準だけ", _option_ids() == ["default"], str(_option_ids()))

	# 不正なファイル: 状態欄に理由が出て、確認画面は出ない
	_main._on_scenario_import_file_selected(DIR + "/bad_skill.zip")
	_check("不正なzip: 理由が状態欄に出る", status.text.begins_with("取り込めません") and status.text.contains("技能"), status.text)
	_check("不正なzip: 確認画面は出ない", not _main.scenario_import_confirm.visible)

	# 正常: 確認画面(内容の要約)→ 取り込む
	_main._on_scenario_import_file_selected(DIR + "/transfer_one.zip")
	var text: String = _main.scenario_import_label.text
	_check("確認画面: 出る", _main.scenario_import_confirm.visible)
	_check("確認画面: 名前・ID・数・作者・説明が出る", text.contains("持ち込み試験") and text.contains("transfer_one") and text.contains("フロア196") and text.contains("画像1枚") and text.contains("試験者") and text.contains("取り込みの確認用"), text)
	_check("確認画面: 新しいIDなので、ボタンは「取り込む」", _main.scenario_import_confirm.ok_button_text == "取り込む")
	_main.scenario_import_confirm.hide()
	_main._on_scenario_import_confirmed()
	_check("取り込み: 完了の表示", status.text.contains("持ち込み試験") and status.text.contains("取り込みました") and not status.text.contains("上書き"), status.text)
	_check("取り込み: 「シナリオ:」の一覧に出て、選択される", _option_ids() == ["default", "transfer_one"] and _main._selected_scenario().get("id", "") == "transfer_one", str(_option_ids()))

	# 同じIDを再び: 上書きの確認
	_main._on_scenario_import_file_selected(DIR + "/transfer_two.zip")
	_check("上書き: 確認画面に「既にあります」と、ボタンは「上書きして取り込む」", _main.scenario_import_label.text.contains("既にあります") and _main.scenario_import_confirm.ok_button_text == "上書きして取り込む", _main.scenario_import_label.text)
	_main.scenario_import_confirm.hide()
	_main._on_scenario_import_confirmed()
	_check("上書き: 完了の表示", status.text.contains("上書きして取り込みました"), status.text)
	_check("上書き: 新しい内容(名前)になった", ScenarioTransfer.list_custom()[0]["name"] == "持ち込み試験(改訂版)", str(ScenarioTransfer.list_custom()))

	# やめる: 戻るキーで、確認画面を閉じ、展開した一時ファイルも消える
	_main._on_scenario_import_file_selected(DIR + "/transfer_one.zip")
	_check("やめる: 検査後は一時フォルダがある", DirAccess.dir_exists_absolute(ScenarioTransfer.TMP_DIR))
	_main._on_go_back_requested()
	_check("やめる: 戻るキーで確認画面が閉じ、一時ファイルが消える", not _main.scenario_import_confirm.visible and not DirAccess.dir_exists_absolute(ScenarioTransfer.TMP_DIR))
	_check("やめる: 取り込まれていない(名前は改訂版のまま)", ScenarioTransfer.list_custom()[0]["name"] == "持ち込み試験(改訂版)")

	# 管理: 一覧 → 選ぶまで削除は押せない → 確認 → 削除
	_main._on_scenario_manage_pressed()
	_check("管理: 一覧が出る(1件)", _main.scenario_manage_dialog.visible and _main.scenario_manage_list.item_count == 1 and _main.scenario_manage_list.get_item_text(0).contains("transfer_one"), _main.scenario_manage_list.get_item_text(0) if _main.scenario_manage_list.item_count > 0 else "")
	_check("管理: 選ぶまで「削除」は押せない", _main.scenario_manage_dialog.get_ok_button().disabled)
	_main.scenario_manage_list.select(0)
	_main.scenario_manage_list.item_selected.emit(0)
	_check("管理: 選ぶと押せる", not _main.scenario_manage_dialog.get_ok_button().disabled)
	_main.scenario_manage_dialog.hide()
	_main._on_scenario_manage_confirmed()
	_check("管理: 削除の確認に、名前と「元に戻せません」が出る", _main.scenario_delete_confirm.visible and _main.scenario_delete_confirm.dialog_text.contains("持ち込み試験(改訂版)") and _main.scenario_delete_confirm.dialog_text.contains("元に戻せません"), _main.scenario_delete_confirm.dialog_text)
	_main.scenario_delete_confirm.hide()
	_main._on_scenario_delete_confirmed()
	_check("削除: 消え、一覧(シナリオ:)からも消える", ScenarioTransfer.list_custom().is_empty() and _option_ids() == ["default"] and status.text.contains("削除しました"), "%s / %s" % [str(_option_ids()), status.text])
	# 続きの確認は、_phase2(数フレーム後: 一覧が開き直される)

func _phase2() -> void:
	_check("削除の後: 一覧が開き直される(0件、空の案内)", _main.scenario_manage_dialog.visible and _main.scenario_manage_list.item_count == 0 and _main.scenario_manage_hint.text.contains("入っていません"), _main.scenario_manage_hint.text)
	_main._on_go_back_requested()
	_check("戻るキーで、管理の一覧が閉じる", not _main.scenario_manage_dialog.visible)
	_completed = true
