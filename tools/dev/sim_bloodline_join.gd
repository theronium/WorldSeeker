# 使い捨ての確認用スクリプト(2026-09-24)。血筋キャラの加入イベント(王都「旧家の屋敷」で旧家の血筋のイザベラ、
# 貴族街「離宮の隠れ家」で王家の落胤のリュシアン → 貴族街の門・国境の関所を通れるようになる)と、効果「探索者が加入する」、
# 雇用候補の血筋の出やすさ(旧家3%・王家1%)の確認。
#   R: 雇用候補の血筋の割合(Recruitment._roll_bloodline)
#   J: 効果「探索者が加入する」(ScenarioEvents._join): 名前・血筋・職業・肖像・初期スキル、雇用上限を超えても加わる、掲示板/行動ログ、
#      肖像が探索者の画像でなければ血筋から自動、取り込み時の検査(ScenarioTransfer.validate_event)
#   C: デフォルトシナリオの連鎖: 旧家の屋敷の発見 → イザベラ加入 → パーティに入れると貴族街の門を通れる →
#      離宮の隠れ家の発見 → リュシアン加入 → 国境の関所を通れる。セーブ往復で残る
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree

var _frames := 0
var _completed := false
var _fails := 0

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		return false
	if _frames == 3:
		_run()
		if not _completed:
			print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
		else:
			print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
		return true
	return false

func _drain() -> void:
	var dialogue = root.get_node("EventDialogue"); var battle = root.get_node("BattleScreen")
	for _i in 5:
		var guard := 0
		while dialogue.is_active and guard < 50:
			guard += 1
			dialogue.advance()
		if battle.is_active:
			battle.close()

func _find_by_name(npcs, npc_name: String) -> Dictionary:
	for npc in npcs.get_roster():
		if npc["name"] == npc_name:
			return npc
	return {}

## そのフロアを「隣は突破済み、本人は未発見」にして、パーティをそのセクションへ置く
func _setup_floor(world_map, parties, pid: int, floor_id: String) -> void:
	var section_id: String = world_map.nodes[floor_id]["section"]
	for id in world_map.nodes_in_section(section_id):
		if id != floor_id:
			world_map.mark_passed(id, true)
	world_map.nodes[floor_id]["found"] = false
	world_map.nodes[floor_id]["passed"] = false
	parties.assign_section(pid, section_id)

func _run() -> void:
	var save = root.get_node("SaveSystem"); var world_map = root.get_node("WorldMap"); var parties = root.get_node("Parties")
	var npcs = root.get_node("Npcs"); var events = root.get_node("ScenarioEvents"); var exploration = root.get_node("Exploration")
	var economy = root.get_node("Economy"); var board = root.get_node("Board"); var dialogue = root.get_node("EventDialogue")
	var recruitment = root.get_node("Recruitment")
	_drain()
	save.start_fresh_session()
	_drain()

	# ---------- R ----------
	print("--- R: 雇用候補の血筋の割合 ---")
	seed(12345)
	var counts := {}
	var rolls := 20000
	for i in rolls:
		var b: String = recruitment._roll_bloodline()
		counts[b] = counts.get(b, 0) + 1
	print("  ", counts)
	var pct := func(b: String) -> float: return 100.0 * counts.get(b, 0) / rolls
	_check("王家の落胤は約1%", pct.call("王家の落胤") > 0.6 and pct.call("王家の落胤") < 1.5, "%.2f%%" % pct.call("王家の落胤"))
	_check("旧家の血筋は約3%", pct.call("旧家の血筋") > 2.4 and pct.call("旧家の血筋") < 3.6, "%.2f%%" % pct.call("旧家の血筋"))
	_check("森人の血は約25%", pct.call("森人の血") > 23.5 and pct.call("森人の血") < 26.5, "%.2f%%" % pct.call("森人の血"))
	_check("平民は約71%", pct.call("平民") > 69.0 and pct.call("平民") < 73.0, "%.2f%%" % pct.call("平民"))
	randomize()

	# ---------- J ----------
	print("--- J: 効果「探索者が加入する」 ---")
	# 雇用上限いっぱいにしてから加入させる(物語上の加入なので、上限を超えても加わる)
	while npcs.get_roster().size() < economy.employ_cap:
		npcs.hire("埋め草%d" % npcs.get_roster().size(), {"bloodline": "平民"})
	var before: int = npcs.get_roster().size()
	var test_event := {"id": "t_join", "title": "試験の加入", "effects": [
		{"on": "*", "type": "join", "name": "試験の人", "bloodline": "王家の落胤", "job": "SCOUT", "portrait": "char_33", "skills": {"PERCEPTION": 5, "NO_SUCH": 3}},
		{"on": "*", "type": "join", "name": "肖像の違う人", "bloodline": "旧家の血筋", "job": "NO_SUCH_JOB", "portrait": "npc_01"},
	]}
	var joined_ids: Array = []
	events.joined.connect(func(id: int): joined_ids.append(id))
	events.apply_effects(test_event, "pass")
	_check("雇用上限いっぱいでも、2人とも加わる(上限を超える)", npcs.get_roster().size() == before + 2 and npcs.get_roster().size() > economy.employ_cap, "%d人 / 上限%d" % [npcs.get_roster().size(), economy.employ_cap])
	_check("joinedシグナルが2回", joined_ids.size() == 2)
	var tester: Dictionary = _find_by_name(npcs, "試験の人")
	_check("血筋・職業・肖像", tester.get("innate_traits", {}).get("bloodline") == "王家の落胤" and tester.get("job") == Jobs.Job.SCOUT and tester.get("portrait") == "char_33", str([tester.get("innate_traits"), tester.get("job"), tester.get("portrait")]))
	_check("初期スキル(知らない技能は無視)", npcs.skill_level(tester["id"], SkillTypes.Skill.PERCEPTION) == 5 and npcs.skill_level(tester["id"], SkillTypes.Skill.COMBAT) == 0)
	_check("パーティには入っていない(雇用と同じ)", int(tester.get("party_id", 0)) == -1)
	var other: Dictionary = _find_by_name(npcs, "肖像の違う人")
	_check("知らない職業は戦士、探索者の画像でない肖像は血筋から自動", other.get("job") == Jobs.Job.WARRIOR and String(other.get("portrait", "")).begins_with("char_") and PortraitLibrary.PORTRAITS_BY_BLOODLINE["旧家の血筋"].has(other.get("portrait")), str([other.get("job"), other.get("portrait")]))
	_check("掲示板に噂が載る", board.entries.any(func(e): return "試験の人" in String(e["text"]) and "噂" in String(e["text"])))
	_check("取り込み時の検査: 正しい加入は通る", ScenarioTransfer.validate_event({"id": "a", "trigger": {"type": "conditions"}, "script": [], "effects": [{"type": "join", "name": "x", "bloodline": "平民", "job": "SAGE"}]}, "a") == "")
	_check("取り込み時の検査: 名前が無い加入は弾く", ScenarioTransfer.validate_event({"id": "a", "trigger": {"type": "conditions"}, "script": [], "effects": [{"type": "join", "bloodline": "平民", "job": "SAGE"}]}, "a") != "")

	# ---------- C ----------
	print("--- C: デフォルトシナリオの連鎖 ---")
	save.start_fresh_session()
	_drain()
	var party: Dictionary = parties.get_parties()[0]
	var pid: int = party["id"]
	var members: Array = party["member_ids"].duplicate()
	_check("前提: 初期パーティには旧家の血筋・王家の落胤がいない", members.all(func(id): return not ["旧家の血筋", "王家の落胤"].has(npcs.get_npc(id)["innate_traits"]["bloodline"])))
	_check("前提: 貴族街の門は、今のパーティでは通れない", world_map.first_passing_member("noble_gate", members) == -1)
	_check("前提: 旧家の屋敷は王都、離宮の隠れ家は貴族街", world_map.nodes["old_family_manor"]["section"] == "capital_district" and world_map.nodes["hidden_villa"]["section"] == "noble_quarter")

	_setup_floor(world_map, parties, pid, "old_family_manor")
	exploration._on_node_found("斥候", members[0], party, "old_family_manor", 1)
	_check("旧家の屋敷: 会話が開く", dialogue.is_active)
	_check("旧家の屋敷: 会話の間は、まだ加わっていない", _find_by_name(npcs, "イザベラ・ヴァルモン").is_empty())
	_drain()
	var isabella: Dictionary = _find_by_name(npcs, "イザベラ・ヴァルモン")
	_check("イザベラが加わる(旧家の血筋・賢者・char_40・知恵4)", not isabella.is_empty() and isabella["innate_traits"]["bloodline"] == "旧家の血筋" and isabella["job"] == Jobs.Job.SAGE and isabella["portrait"] == "char_40" and npcs.skill_level(isabella["id"], SkillTypes.Skill.WISDOM) == 4)
	_check("フラグisabella_joined", events.flags.has("isabella_joined"))
	_check("旧家の屋敷は突破済み", world_map.is_passed("old_family_manor"))
	# 初期パーティは4人で満員なので、1人外してイザベラを入れる
	parties.remove_member(pid, members[3])
	_check("イザベラをパーティに入れられる", parties.add_members(pid, [isabella["id"]]))
	_check("貴族街の門を、イザベラが通せる", world_map.first_passing_member("noble_gate", parties.get_party(pid)["member_ids"]) == isabella["id"])

	_setup_floor(world_map, parties, pid, "hidden_villa")
	party = parties.get_party(pid)
	exploration._on_node_found("斥候", party["member_ids"][0], party, "hidden_villa", 2)
	_check("離宮の隠れ家: 会話が開く", dialogue.is_active)
	_drain()
	var lucien: Dictionary = _find_by_name(npcs, "リュシアン")
	_check("リュシアンが加わる(王家の落胤・重戦士・char_26・戦闘力4)", not lucien.is_empty() and lucien["innate_traits"]["bloodline"] == "王家の落胤" and lucien["job"] == Jobs.Job.HEAVY_WARRIOR and lucien["portrait"] == "char_26" and npcs.skill_level(lucien["id"], SkillTypes.Skill.COMBAT) == 4)
	parties.remove_member(pid, party["member_ids"][2])
	parties.add_members(pid, [lucien["id"]])
	_check("国境の関所を、リュシアンが通せる", world_map.first_passing_member("border_checkpoint", parties.get_party(pid)["member_ids"]) == lucien["id"])

	var roster_size: int = npcs.get_roster().size()
	save.save_game()
	save.load_game()
	_check("セーブ往復: 2人とも残る", npcs.get_roster().size() == roster_size and not _find_by_name(npcs, "イザベラ・ヴァルモン").is_empty() and not _find_by_name(npcs, "リュシアン").is_empty())
	_check("セーブ往復: 肖像と血筋", _find_by_name(npcs, "リュシアン").get("portrait") == "char_26" and _find_by_name(npcs, "リュシアン")["innate_traits"]["bloodline"] == "王家の落胤")
	_completed = true
