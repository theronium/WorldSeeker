# 使い捨ての確認用スクリプト(2026-09-21)。雇用上限の4人単位と、パーティのメンバー操作(編成・追加・外す)の確認。
# 報告: 「雇用が4人ごとでなく、拡張と合っていない」「Androidで、雇用した探索者でパーティを組もうとしても1人しか選べず、
# パーティへの追加も出来ない」。選べなかった原因は、ItemListの複数選択(SELECT_MULTI)がCtrl/Shift前提で、タッチの1タップが
# 選択を置き換えていたこと。チェックボックス式(MemberPicker)に替え、パーティへの追加・外すを足した。
#   E: 雇用上限(Economy)  P: Parties(add_members / remove_member / free_slots)  K: MemberPicker  U: 画面の操作
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree

var _frames := 0
var _main: Node
var _completed := false
var _fails := 0

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	if _frames == 5:
		_run()
		if not _completed:
			print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
		else:
			print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
		return true
	return false

func _finish(dialogue) -> void:
	var guard := 0
	while dialogue.is_active and guard < 50:
		guard += 1
		dialogue.advance()

func _hire(npcs, count: int) -> Array:
	var ids: Array = []
	for i in count:
		ids.append(npcs.hire("控え%d" % (npcs.roster.size() + 1), {"bloodline": "平民"}))
	return ids

func _check_box(picker, npc_id: int, pressed: bool) -> void:
	for box in picker._boxes:
		if int(box.get_meta("npc_id")) == npc_id:
			box.button_pressed = pressed # toggledが出る(タップと同じ)

func _run() -> void:
	var economy = root.get_node("Economy"); var parties = root.get_node("Parties"); var npcs = root.get_node("Npcs")
	var save = root.get_node("SaveSystem"); var dialogue = root.get_node("EventDialogue")
	_finish(dialogue)
	save.start_fresh_session()

	# ---------- E: 雇用上限 ----------
	print("--- E: 雇用上限 ---")
	_check("E: 初期は8(無償の初期パーティ4人+雇用枠4人)", economy.employ_cap == 8 and economy.EMPLOY_CAP_INITIAL == 8, str(economy.employ_cap))
	economy.funds = 100000
	var before: int = economy.employ_cap
	_check("E: 拡張を1回すると+4(パーティ1つ分)", economy.upgrade_facility() and economy.employ_cap == before + 4, str(economy.employ_cap))
	economy.upgrade_facility()
	_check("E: 8→12→16", economy.employ_cap == 16, str(economy.employ_cap))
	_check("E: 拡張の費用は今の式のまま(300×1.6^レベル)", economy.facility_upgrade_cost() == int(300 * pow(1.6, 2)), str(economy.facility_upgrade_cost()))
	var aligned := {0: 0, 4: 4, 5: 8, 7: 8, 8: 8, 9: 12, 11: 12, 12: 12, 13: 16}
	var aligned_ok := true
	for cap in aligned.keys():
		if economy.aligned_cap(cap) != aligned[cap]:
			aligned_ok = false
			print("   aligned_cap(%d) = %d (期待 %d)" % [cap, economy.aligned_cap(cap), aligned[cap]])
	_check("E: 旧セーブの上限は、4の倍数へ切り上げる(5→8、7→8、9→12。下がらない)", aligned_ok)
	economy.employ_cap = 5 # 旧セーブ相当
	save.save_game()
	save.load_game()
	_check("E: 上限5のセーブを読むと、8になる", economy.employ_cap == 8, str(economy.employ_cap))
	economy.employ_cap = 9
	save.save_game()
	save.load_game()
	_check("E: 上限9のセーブを読むと、12になる", economy.employ_cap == 12, str(economy.employ_cap))
	economy.reset()
	_check("E: リセットで初期の8に戻る", economy.employ_cap == 8 and economy.facility_level == 0)
	save.start_fresh_session()

	# ---------- P: Parties ----------
	print("--- P: Parties ---")
	var starter: Dictionary = parties.get_parties()[0]
	_check("P: 前提: 初期パーティは4人(満員)", starter["member_ids"].size() == 4 and parties.free_slots(starter["id"]) == 0)
	var extra: Array = _hire(npcs, 6) # 未所属6人
	var team_id: int = parties.form_party([extra[0]], "少人数")
	_check("P: 1人でもパーティは組める。空きは3", team_id != -1 and parties.free_slots(team_id) == 3)
	_check("P: 追加: 2人を末尾に加える", parties.add_members(team_id, [extra[1], extra[2]]) and parties.get_party(team_id)["member_ids"] == [extra[0], extra[1], extra[2]], str(parties.get_party(team_id)["member_ids"]))
	_check("P: 追加した探索者は、そのパーティに所属する", npcs.get_npc(extra[1])["party_id"] == team_id and npcs.get_npc(extra[2])["party_id"] == team_id)
	_check("P: 空きは1", parties.free_slots(team_id) == 1)
	var members_before: Array = parties.get_party(team_id)["member_ids"].duplicate()
	_check("P: 空きを超える追加は、何も変えずに失敗", not parties.add_members(team_id, [extra[3], extra[4]]) and parties.get_party(team_id)["member_ids"] == members_before and npcs.get_npc(extra[3])["party_id"] == -1)
	_check("P: 既にパーティにいる探索者は追加できない", not parties.add_members(team_id, [starter["member_ids"][0]]) and parties.get_party(team_id)["member_ids"] == members_before)
	_check("P: 重複は追加できない", not parties.add_members(team_id, [extra[3], extra[3]]) and parties.get_party(team_id)["member_ids"] == members_before)
	_check("P: 存在しない探索者は追加できない", not parties.add_members(team_id, [9999]) and parties.get_party(team_id)["member_ids"] == members_before)
	_check("P: 空の追加・存在しないパーティは失敗", not parties.add_members(team_id, []) and not parties.add_members(9999, [extra[3]]))
	_check("P: 4人目を追加すると満員(空き0)", parties.add_members(team_id, [extra[3]]) and parties.free_slots(team_id) == 0 and parties.get_party(team_id)["member_ids"].size() == 4)
	_check("P: 満員には追加できない", not parties.add_members(team_id, [extra[4]]))
	# 外す
	_check("P: 外す: 未所属に戻り、並びが詰まる", parties.remove_member(team_id, extra[1]) and npcs.get_npc(extra[1])["party_id"] == -1 and parties.get_party(team_id)["member_ids"] == [extra[0], extra[2], extra[3]], str(parties.get_party(team_id)["member_ids"]))
	_check("P: 外した探索者の能力は失われない(名前・ジョブ)", npcs.get_npc(extra[1])["name"] != "" and npcs.get_npc(extra[1])["job"] >= 0)
	_check("P: メンバーでない探索者は外せない", not parties.remove_member(team_id, extra[5]) and not parties.remove_member(team_id, extra[1]))
	parties.remove_member(team_id, extra[2]) # [e0, e3]
	_check("P: 2人から1人外せる", parties.remove_member(team_id, extra[3]) and parties.get_party(team_id)["member_ids"] == [extra[0]], str(parties.get_party(team_id)["member_ids"]))
	_check("P: 最後の1人は外せない(1人は残す)", not parties.remove_member(team_id, extra[0]) and parties.get_party(team_id)["member_ids"] == [extra[0]] and npcs.get_npc(extra[0])["party_id"] == team_id)
	# セーブ往復
	parties.add_members(team_id, [extra[1], extra[2]])
	save.save_game()
	save.load_game()
	_check("P: セーブ/ロードの往復でも、追加したメンバーが残る", parties.get_party(team_id)["member_ids"] == [extra[0], extra[1], extra[2]] and npcs.get_npc(extra[2])["party_id"] == team_id, str(parties.get_party(team_id)["member_ids"]))

	# ---------- K: MemberPicker(チェックボックス式の複数選択) ----------
	print("--- K: MemberPicker ---")
	save.start_fresh_session()
	extra = _hire(npcs, 6)
	var unaffiliated: Array = npcs.get_roster().filter(func(n): return n["party_id"] == -1)
	var picker: Control = load("res://scripts/member_picker.gd").new()
	root.add_child(picker)
	picker.limit = 4
	picker.set_choices(unaffiliated)
	_check("K: 未所属6人の行ができる", picker._boxes.size() == 6, str(picker._boxes.size()))
	_check("K: 最初は誰も選んでおらず、案内は「選択 0/4人」", picker.selected_ids().is_empty() and picker._count_label.text == "選択 0/4人", picker._count_label.text)
	# 核心: 1タップずつで、複数選べる(ItemListの複数選択では、タッチで1人しか選べなかった)
	_check_box(picker, extra[0], true)
	_check_box(picker, extra[1], true)
	_check_box(picker, extra[2], true)
	_check("K: 3人を、1人ずつのタップで選べる", picker.selected_ids() == [extra[0], extra[1], extra[2]], str(picker.selected_ids()))
	_check("K: 「選択 3/4人」", picker._count_label.text == "選択 3/4人")
	_check_box(picker, extra[3], true)
	_check("K: 上限の4人に達すると、選んでいない行は押せなくなる", picker.selected_ids().size() == 4 and picker._boxes.filter(func(b): return b.disabled).size() == 2, "無効=%d" % picker._boxes.filter(func(b): return b.disabled).size())
	_check("K: 選んだ行は押せたまま(外せる)", picker._boxes.filter(func(b): return b.button_pressed and b.disabled).is_empty())
	_check_box(picker, extra[0], false)
	_check("K: 1人外すと、他の行がまた押せる", picker.selected_ids().size() == 3 and picker._boxes.all(func(b): return not b.disabled))
	# 作り直さない(日次の更新で、押している最中に行が消えないように)
	var boxes_before: Array = picker._boxes.duplicate()
	picker.set_choices(unaffiliated)
	_check("K: 中身が同じなら、行を作り直さない(同じノードのまま、選択も残る)", picker._boxes == boxes_before and picker.selected_ids().size() == 3)
	# 中身が変わったら、作り直すが、選択は引き継ぐ
	picker.set_choices(unaffiliated.filter(func(n): return n["id"] != extra[5]))
	_check("K: 顔ぶれが変わると作り直すが、残っている人の選択は引き継ぐ", picker._boxes.size() == 5 and picker.selected_ids() == [extra[1], extra[2], extra[3]], str(picker.selected_ids()))
	picker.limit = 0
	_check("K: 上限0(満員)なら、全ての行が押せない。案内は「空きがありません」", picker._count_label.text == "空きがありません" and picker._boxes.filter(func(b): return not b.button_pressed and b.disabled).size() == picker._boxes.size() - picker.selected_ids().size())
	picker.limit = 4
	picker.clear_selection()
	_check("K: 選択を全て外せる", picker.selected_ids().is_empty())
	picker.set_choices([], "誰もいません")
	_check("K: 選べる人がいなければ、その旨を出す", picker._boxes.is_empty() and picker._rows.get_child_count() == 1)
	picker.queue_free()

	# ---------- U: 画面の操作 ----------
	print("--- U: 画面 ---")
	save.start_fresh_session()
	extra = _hire(npcs, 5) # 未所属5人
	_main._refresh_party_roster()
	var form: Control = _main.party_form_picker
	_check("U: 編成の欄に、未所属5人のチェックボックス。ボタンは、選ぶまで押せない", form._boxes.size() == 5 and _main.party_form_button.disabled)
	_check_box(form, extra[0], true)
	_check_box(form, extra[1], true)
	_check_box(form, extra[2], true)
	_check("U: 3人を選ぶと、編成ボタンが押せる", form.selected_ids().size() == 3 and not _main.party_form_button.disabled)
	var parties_before: int = parties.get_parties().size()
	_main._on_form_party_pressed()
	_check("U: 選んだ3人でパーティができる", parties.get_parties().size() == parties_before + 1 and parties.get_parties().back()["member_ids"] == [extra[0], extra[1], extra[2]], str(parties.get_parties().back()["member_ids"]))
	_check("U: 編成した3人は、未所属の一覧から消え、残りは2人", _main.party_form_picker._boxes.size() == 2)
	_check("U: 編成後、選択は空に戻り、編成ボタンは押せない", _main.party_form_picker.selected_ids().is_empty() and _main.party_form_button.disabled)

	# 追加(詳細画面)
	var team: Dictionary = parties.get_parties().back()
	_main._on_party_card_pressed(team["id"])
	var add_picker: Control = _main.party_add_picker
	_check("U: 詳細のメンバー画面に、追加の欄。空き1人・未所属2人", add_picker.limit == 1 and add_picker._boxes.size() == 2 and _main.party_add_label.text.contains("あと1人"), _main.party_add_label.text)
	_check("U: 追加ボタンは、選ぶまで押せない", _main.party_add_button.disabled)
	_check("U: 詳細の追加リストは、内側でスクロールしない(外側のページに任せる)。編成の一覧は内側でスクロールする", add_picker._scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and _main.party_form_picker._scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO)
	_check_box(add_picker, extra[3], true)
	_check("U: 空きが1人なので、1人選ぶと、もう1人の行は押せなくなる", add_picker.selected_ids() == [extra[3]] and add_picker._boxes.filter(func(b): return b.disabled).size() == 1 and not _main.party_add_button.disabled)
	_main._on_party_add_pressed()
	_check("U: 追加でメンバーが4人になる", parties.get_party(team["id"])["member_ids"] == [extra[0], extra[1], extra[2], extra[3]], str(parties.get_party(team["id"])["member_ids"]))
	_check("U: 満員になると、その旨を出し、追加の行は押せない", _main.party_add_label.text.contains("満員") and add_picker.limit == 0 and _main.party_add_status_label.text.contains("追加しました"), _main.party_add_label.text)
	_check("U: メンバーのカードが4枚になる", _main.party_member_row.get_child_count() == 4)
	# 外す
	_check("U: メンバーを選ぶまで、外すボタンは押せない", _main.party_remove_button.disabled)
	_main._on_party_member_card_pressed(1)
	_check("U: メンバーを選ぶと、外すボタンが押せる(4人いるので)", not _main.party_remove_button.disabled)
	_main._on_remove_member_pressed()
	_check("U: 外すと、そのメンバーが未所属に戻り、3人になる", parties.get_party(team["id"])["member_ids"] == [extra[0], extra[2], extra[3]] and npcs.get_npc(extra[1])["party_id"] == -1, str(parties.get_party(team["id"])["member_ids"]))
	_check("U: 外した人は、追加の一覧に出る(空き1・未所属2)", add_picker.limit == 1 and add_picker._boxes.size() == 2 and _main.party_add_status_label.text.contains("外しました"), "%d行" % add_picker._boxes.size())
	# 1人になるまで外して、最後の1人は外せない
	_main._on_party_member_card_pressed(0)
	_main._on_remove_member_pressed()
	_main._on_party_member_card_pressed(0)
	_main._on_remove_member_pressed()
	_check("U: 1人まで外せる", parties.get_party(team["id"])["member_ids"] == [extra[3]], str(parties.get_party(team["id"])["member_ids"]))
	_main._on_party_member_card_pressed(0)
	_check("U: 最後の1人は、外すボタンが押せない", _main.party_remove_button.disabled)
	_main._on_remove_member_pressed()
	_check("U: (押せたとしても)最後の1人は外せない", parties.get_party(team["id"])["member_ids"] == [extra[3]] and _main.party_add_status_label.text.contains("1人は残す"), _main.party_add_status_label.text)
	# 日次の更新で、行を作り直さない
	var rows_before: Array = add_picker._boxes.duplicate()
	_main._refresh_party_roster()
	_main._refresh_party_detail()
	_check("U: 画面の更新(日次)で、チェックボックスの行を作り直さない", add_picker._boxes == rows_before)
	_main._refresh_funds()
	_check("U: 施設拡張の説明は「雇用上限 +4」", _main.facility_info_label.text.begins_with("雇用上限 +4"), _main.facility_info_label.text)
	_completed = true
