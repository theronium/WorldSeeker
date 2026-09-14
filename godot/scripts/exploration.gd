extends Node
# 担当セクションに割り当てられたパーティの自動探索を日次で処理する。design.md 4.7/5.4節。
#
# 1日ごとに各パーティは:
#   1. 発見済みだが未突破のゲートを、パーティ内の該当メンバーの現在のスキル値/戦力で
#      無音に再判定する(戦闘ゲートは実際にcombat.gdで解決され、敗北/撤退時はパーティ全体が
#      一時的に離脱する)
#   2. 担当セクションの未発見の隣接ノード全てに、パーティ内最高知覚メンバーの知覚スキルに
#      応じた確率で発見を試みる(発見に成功した瞬間だけ、そのノードにイベント台本があれば
#      会話を再生する)
#
# ゲート種別ごとに「どのメンバーが判定を担うか」は以下の方針(design.md 4.7節):
#   スキルゲート: パーティ内で該当スキルが最も高い(固有スキルの実効Lv込み)メンバー。
#     経験値もそのメンバーへ入る
#   血筋/所持品ゲート: パーティ内の誰か1人が満たせば通過(WorldMap.first_passing_member)
#   戦闘ゲート: combat.gdが並び順で解決し、止めを刺したメンバーを返す
#
# 掲示板には、フロア単位の発見は所属セクションのスレッドにのみ記録し、
# セクション/エリアへの初到達やイベントだけを全体フィードに載せる(wild_npcs.gdも本モジュールを利用する)。

const DISCOVERY_BASE_CHANCE := 0.2
const DISCOVERY_PER_PERCEPTION := 0.1
const DISCOVERY_MAX_CHANCE := 0.9

# 月次収入・攻略報酬(design.md 6章「経済」で構想されていたが未実装だった資金獲得経路。
# 2026-09-13に実装、2026-09-14にパーティ単位へ変更): ワーカー配置型。担当パーティがいる
# セクションだけ、そのセクションの累計突破フロア数×セクション倍率(WorldMap.section_multiplier、
# エリアの登場順で自動算出)を毎月の収入として得る。配置転換すると元のセクションからの収入は失われる。
const MONTHLY_INCOME_PER_POINT := 5
# セクションを完全攻略(全フロア突破)した瞬間に入る一時金。1フロアあたりの基礎額×セクション倍率×
# フロア数。同一プレイで本当に最初に完全攻略したセクションだけ、さらに固定ボーナスが乗る。
const SECTION_CLEAR_REWARD_PER_FLOOR := 20
const FIRST_SECTION_CLEAR_BONUS := 200

func _ready() -> void:
	TimeSystem.day_advanced.connect(_on_day_advanced)
	TimeSystem.month_ended.connect(_on_month_ended)

## 月末の集計タイムで、担当パーティがいる全セクション分の収入をまとめて資金化する。
func _on_month_ended(current_month: int) -> void:
	var current_day := TimeSystem.current_day
	var total_income := 0
	for party in Parties.get_parties():
		var section_id: String = party["assigned_section"]
		if section_id == "" or not WorldMap.sections.has(section_id):
			continue
		var income: int = MONTHLY_INCOME_PER_POINT * WorldMap.section_multiplier(section_id) * WorldMap.passed_count_in_section(section_id)
		total_income += income
	if total_income > 0:
		Economy.earn(total_income)
		var text := "月次収入として%d資金を得た(第%d月)" % [total_income, current_month]
		Board.post(current_day, text, Board.Importance.MAJOR, "economy")
		ActionLog.record(current_day, "monthly_income", text)

func _on_day_advanced(current_day: int) -> void:
	for party in Parties.get_parties():
		if party["status"] != Parties.Status.EXPLORING:
			continue
		if not Parties.is_available(party["id"], current_day):
			continue
		_claim_wild_progress(party)
		_retry_gates(party, current_day)
		if Parties.is_available(party["id"], current_day):
			_attempt_discovery(party, current_day)

## 野良NPC(wild_npcs.gd)がゲート無しのフロアを先に発見・突破してしまうと、found=trueに
## なった時点でfrontier_for_section/_retry_gatesのどちらの対象からも永久に外れてしまい、
## そのフロアを実際に担当しているパーティが常駐していても「誰か(灰色)」表示のまま二度と
## 「自身(青)」に塗り替わらなかった(ささやきの森「森の小道」で報告された不具合)。
## 担当パーティが稼働している間は、既に突破済みだが自分の踏破扱いになっていないフロアを
## 日次でここに合流させる。
func _claim_wild_progress(party: Dictionary) -> void:
	for node_id in WorldMap.nodes_in_section(party["assigned_section"]):
		var node: Dictionary = WorldMap.nodes[node_id]
		if node["passed"] and not node["found_by_employed"]:
			WorldMap.mark_passed(node_id, true)

func _retry_gates(party: Dictionary, current_day: int) -> void:
	for node_id in WorldMap.nodes_in_section(party["assigned_section"]):
		if not Parties.is_available(party["id"], current_day):
			return # 戦闘で撤退し離脱した場合、この日はもう動けない
		var node: Dictionary = WorldMap.nodes[node_id]
		if node["found"] and not node["passed"]:
			var result := _attempt_gate(party, node_id, current_day)
			if result["passed"]:
				WorldMap.mark_passed(node_id, true)
				_grant_item_reward(result["npc_id"], node)
				var actor_name: String = Npcs.get_npc(result["npc_id"]).get("name", party["name"])
				_post_floor(actor_name, node_id, current_day, "%sが「%s」を突破した" % [actor_name, node["name"]], "gate_pass", result["npc_id"])
				_check_section_cleared(party["assigned_section"], current_day)

## パーティ内で該当スキルが最も高い(固有スキルの実効Lv込み)メンバーを返す。
func _effective_skill_level(npc_id: int, skill: int) -> int:
	var level := Npcs.skill_level(npc_id, skill)
	var unique: Dictionary = Npcs.get_npc(npc_id).get("unique_skill", {})
	if unique.get("effect_type", "") == "gate_level_bonus" and unique.get("skill", -1) == skill:
		level += int(unique["value"])
	return level

## 同レベルの場合、そのスキルを得意とするジョブ(job_types.gd)のメンバーを優先する。
## そうしないと、全員Lv0の序盤は並び順が先頭のメンバーが常に「最高」判定を独占してしまい、
## 他メンバーが自分の得意スキルで経験値を積む機会を得られず、design.md 4.7節が意図した
## 「パーティ内で自然に役割分担が育っていく」という効果が起きない。
func _best_member_for_skill(party: Dictionary, skill: int) -> int:
	var best_id := -1
	var best_level := -1
	var best_is_specialist := false
	for npc_id in party["member_ids"]:
		var level := _effective_skill_level(npc_id, skill)
		var is_specialist: bool = Jobs.JOB_SKILL_AFFINITY.get(Npcs.get_npc(npc_id)["job"], -1) == skill
		if level > best_level or (level == best_level and is_specialist and not best_is_specialist):
			best_level = level
			best_id = npc_id
			best_is_specialist = is_specialist
	return best_id

## 知覚スキルによる発見確率。パーティ内最高知覚メンバー基準(固有スキルの発見確率ボーナス込み)。
func discovery_chance_for_member(npc_id: int) -> float:
	var perception := Npcs.skill_level(npc_id, SkillTypes.Skill.PERCEPTION)
	var chance := DISCOVERY_BASE_CHANCE + perception * DISCOVERY_PER_PERCEPTION
	var unique: Dictionary = Npcs.get_npc(npc_id).get("unique_skill", {})
	if unique.get("effect_type", "") == "discovery_pct":
		chance += float(unique["value"])
	return min(DISCOVERY_MAX_CHANCE, chance)

func _attempt_discovery(party: Dictionary, current_day: int) -> void:
	# 担当セクションの未発見の隣接ノード全てに、並列で1回ずつ発見を試みる
	var frontier := WorldMap.frontier_for_section(party["assigned_section"])
	var scout_id := _best_member_for_skill(party, SkillTypes.Skill.PERCEPTION)
	if scout_id == -1:
		return
	var chance := discovery_chance_for_member(scout_id)
	var scout_name: String = Npcs.get_npc(scout_id)["name"]

	for node_id in frontier:
		if not Parties.is_available(party["id"], current_day):
			return
		Npcs.grant_skill_exp(scout_id, SkillTypes.Skill.PERCEPTION, 1)
		if randf() < chance:
			_on_node_found(scout_name, scout_id, party, node_id, current_day)

func _on_node_found(discoverer_name: String, scout_id: int, party: Dictionary, node_id: String, current_day: int) -> void:
	var node: Dictionary = WorldMap.nodes[node_id]

	if WorldMap.has_event(node_id):
		if EventDialogue.is_active:
			return # 今日は既に別の会話中なので見送り、翌日また発見を試みる
		var milestone := _capture_milestone_state(node_id)
		WorldMap.mark_found(node_id, true)
		var gate_result := _attempt_gate(party, node_id, current_day)
		var script: Array = node["event_script_pass"] if gate_result["passed"] else node["event_script_fail"]
		var reward_npc_id: int = gate_result["npc_id"] if gate_result["passed"] else scout_id
		EventDialogue.finished.connect(
			func(outcome: String): _finalize_discovery(discoverer_name, node_id, outcome == "pass", current_day, milestone, reward_npc_id),
			CONNECT_ONE_SHOT)
		EventDialogue.play(script)
		return

	var milestone := _capture_milestone_state(node_id)
	WorldMap.mark_found(node_id, true)
	var gate_result := _attempt_gate(party, node_id, current_day)
	var reward_npc_id: int = gate_result["npc_id"] if gate_result["passed"] else scout_id
	_finalize_discovery(discoverer_name, node_id, gate_result["passed"], current_day, milestone, reward_npc_id)

## 野良NPC(wild_npcs.gd)からも使う、ステータス不問の簡易発見処理。
## ゲートがあるノードは「発見済みだが進めない」までしか進められない(実際の突破は雇用パーティの役目)。
func wild_discover(node_id: String, current_day: int) -> void:
	var node: Dictionary = WorldMap.nodes[node_id]
	if node["found"]:
		return
	var milestone := _capture_milestone_state(node_id)
	WorldMap.mark_found(node_id)
	var passed: bool = node["gate"].is_empty()
	_finalize_discovery("野良の旅人", node_id, passed, current_day, milestone)

func _capture_milestone_state(node_id: String) -> Dictionary:
	var section_id: String = WorldMap.nodes[node_id]["section"]
	var area_id: String = WorldMap.sections[section_id]["area"] if WorldMap.sections.has(section_id) else ""
	return {
		"section_id": section_id,
		"area_id": area_id,
		"was_section_entered": WorldMap.is_section_entered(section_id),
		"was_area_entered": area_id != "" and WorldMap.is_area_entered(area_id),
	}

func _finalize_discovery(discoverer_name: String, node_id: String, passed: bool, current_day: int, milestone: Dictionary, npc_id: int = -1) -> void:
	var node: Dictionary = WorldMap.nodes[node_id]
	if passed:
		WorldMap.mark_passed(node_id, npc_id != -1)
		if npc_id != -1:
			_grant_item_reward(npc_id, node)
		_post_floor(discoverer_name, node_id, current_day, "%sが「%s」を発見した" % [discoverer_name, node["name"]], "discover_pass", npc_id)
		_check_section_cleared(node["section"], current_day)
	else:
		_post_floor(discoverer_name, node_id, current_day, "%sが「%s」を発見したが、まだ先へ進めない" % [discoverer_name, node["name"]], "discover_blocked", npc_id)

	if not milestone["was_section_entered"]:
		var section_name: String = WorldMap.sections[milestone["section_id"]]["name"] if WorldMap.sections.has(milestone["section_id"]) else milestone["section_id"]
		var text := "「%s」に初めて到達した" % section_name
		Board.post(current_day, text, Board.Importance.MAJOR, "exploration")
		ActionLog.record(current_day, "milestone_section", text, npc_id, node_id, milestone["section_id"])
	if milestone["area_id"] != "" and not milestone["was_area_entered"]:
		var area_name: String = WorldMap.areas[milestone["area_id"]]["name"] if WorldMap.areas.has(milestone["area_id"]) else milestone["area_id"]
		var text := "「%s」に初めて足を踏み入れた" % area_name
		Board.post(current_day, text, Board.Importance.MAJOR, "exploration")
		ActionLog.record(current_day, "milestone_area", text, npc_id, node_id, milestone["section_id"])

func _grant_item_reward(npc_id: int, node: Dictionary) -> void:
	var item_id: String = node.get("item_reward", "")
	if item_id == "" or npc_id == -1:
		return
	Items.grant(npc_id, item_id)

## セクション内の全フロアが今まさに突破されたかを確認し、完全攻略済みなら一時金(初回のみ追加
## ボーナス込み)を支給する。さらに、そのセクションを担当しているパーティそれぞれについて、
## post_clear_behaviorの設定に従い「そのまま留まる」か「次の未踏破セクションへ自動再配置」かを
## 適用する(design.mdの「複数パーティが並列でセクションを分担」方針に合わせ、既に他のパーティが
## 担当中のセクションへは再配置しない)。
func _check_section_cleared(section_id: String, current_day: int) -> void:
	if section_id == "" or WorldMap.is_section_reward_claimed(section_id):
		return
	if not WorldMap.is_section_cleared(section_id):
		return

	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else section_id
	var multiplier := WorldMap.section_multiplier(section_id)
	var node_count := WorldMap.nodes_in_section(section_id).size()
	var is_first_clear := WorldMap.section_reward_claimed.is_empty()
	WorldMap.mark_section_reward_claimed(section_id)

	var reward := SECTION_CLEAR_REWARD_PER_FLOOR * multiplier * node_count
	if is_first_clear:
		reward += FIRST_SECTION_CLEAR_BONUS
	Economy.earn(reward)

	var text := "「%s」を完全攻略した(攻略報酬: %d資金)" % [section_name, reward]
	if is_first_clear:
		text += "。初めての完全攻略ボーナスも得た！"
	Board.post(current_day, text, Board.Importance.MAJOR, "section_clear")
	ActionLog.record(current_day, "section_clear", text, -1, "", section_id)

	for party in Parties.get_parties():
		if party["assigned_section"] != section_id:
			continue
		if party["post_clear_behavior"] != Parties.PostClearBehavior.MOVE_ON:
			continue
		var next_section := WorldMap.next_section_to_explore(section_id)
		if next_section == "":
			continue
		var next_section_name: String = WorldMap.sections[next_section]["name"]
		Parties.assign_section(party["id"], next_section)
		Board.post(current_day, "%sは「%s」から「%s」へ配置転換された" % [party["name"], section_name, next_section_name], Board.Importance.MINOR, "reassignment")
		ActionLog.record(current_day, "reassignment", "%sが「%s」へ配置転換された" % [party["name"], next_section_name], -1, "", next_section)

func _post_floor(discoverer_name: String, node_id: String, current_day: int, text: String, event_type: String, npc_id: int = -1) -> void:
	var section_id: String = WorldMap.nodes[node_id]["section"]
	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else section_id
	Board.post_to_thread(section_id, section_name, current_day, text, Board.Importance.MINOR, "exploration")
	ActionLog.record(current_day, event_type, text, npc_id, node_id, section_id)

## ゲートを判定し、{"passed": bool, "npc_id": int}を返す。npc_idは判定を担った(=突破報酬アイテムを
## 受け取る)メンバー。誰も満たさない/敗北した場合は-1。
func _attempt_gate(party: Dictionary, node_id: String, current_day: int) -> Dictionary:
	var gate: Dictionary = WorldMap.nodes[node_id]["gate"]
	match gate.get("type", ""):
		"combat":
			var result: Dictionary = Combat.resolve_party_encounter(party["id"], gate["enemy_power"], current_day)
			if result["result"] == "victory":
				return {"passed": true, "npc_id": result["npc_id"]}
			_post_retreat_help(party, node_id, current_day, result["result"], gate["enemy_power"])
			return {"passed": false, "npc_id": -1}
		"skill":
			# 挑戦するたびに、たとえ突破できなくても該当スキルの経験値が(判定を担ったメンバーに)入る
			# (5.2節: 試行を重ねることでいつか開ける、という思想を全スキルに適用)
			var member_id := _best_member_for_skill(party, gate["skill"])
			if member_id == -1:
				return {"passed": false, "npc_id": -1}
			Npcs.grant_skill_exp(member_id, gate["skill"], 1)
			var passed: bool = _effective_skill_level(member_id, gate["skill"]) >= gate["min_level"]
			return {"passed": passed, "npc_id": member_id if passed else -1}
		_:
			var member_id := WorldMap.first_passing_member(node_id, party["member_ids"])
			return {"passed": member_id != -1, "npc_id": member_id}

## 戦闘での撤退/敗北時、プレイヤーが次に何をすればよいか分かるよう掲示板(セクションスレッド)に
## ヒントを投稿する(design.md 6.2節の「即死の壁」構造を踏まえた対応策の案内)。敗北・撤退した
## パーティはParties.retreat_and_recover()により数日は再挑戦できないため、この投稿も実質
## 「回復サイクルごとに1回程度」の頻度に自然と収まる(毎日スパムにはならない)。
func _post_retreat_help(party: Dictionary, node_id: String, current_day: int, result: String, enemy_power: int) -> void:
	var node: Dictionary = WorldMap.nodes[node_id]
	var verb := "力及ばず敗れて撤退した" if result == "defeat" else "苦戦して撤退した"
	var text := "%sは「%s」で%s(相手の戦闘力: %d)。突破のヒント: ①武器防具屋で装備を強化する ②NPC管理パネルで「戦闘力」スキルを訓練する ③このまま何度も挑み続ければ、戦闘の経験値で自然に強くなる。いずれか(または組み合わせ)を試してみてください。" % [
		party["name"], node["name"], verb, enemy_power]
	var section_id: String = node["section"]
	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else section_id
	Board.post_to_thread(section_id, section_name, current_day, text, Board.Importance.MINOR, "combat_retreat")
	ActionLog.record(current_day, "combat_retreat", text, -1, node_id, section_id)

## NPC管理パネルの「予測」ボタン用: 指定パーティを指定セクションに置いた場合の、実際には
## 配置転換しない今月(TimeSystem.DAYS_PER_MONTH日)の見込みだけを計算する。
##
## セクション内の未突破ノードを、現在到達済みの場所から辿れる順に「発見にかかる予想日数」
## (1/発見確率、を経路に沿って積み上げたもの)で並べ、月内に到達しうる範囲でパーティが
## 実際に戦えない(撤退/敗北になる)戦闘ゲートが無いかをCombat.predict_party_result(実際の
## HP/経験値には触れない非破壊シミュレーション)で調べる。見つかった場合、その戦闘に
## 月内に行き着く確率分だけ予測報酬を割り引く(=撤退が先に来れば、その分の報酬は無いもの
## として扱う期待値化)。スキル/所持品/血筋のゲートで現状塞がれている先は、今月中に
## 抜けられる保証が無いため、この見積もりには含めない。
func forecast_section(party_id: int, section_id: String) -> Dictionary:
	var party := Parties.get_party(party_id)
	var base_income: int = MONTHLY_INCOME_PER_POINT * WorldMap.section_multiplier(section_id) * WorldMap.passed_count_in_section(section_id)
	var horizon := float(TimeSystem.DAYS_PER_MONTH)
	var scout_id := _best_member_for_skill(party, SkillTypes.Skill.PERCEPTION)
	var chance := discovery_chance_for_member(scout_id) if scout_id != -1 else DISCOVERY_BASE_CHANCE

	var eta_days: Dictionary = {} # node_id -> float(このノードの発見が見込まれる日数)
	var queue: Array = WorldMap.frontier_for_section(section_id).duplicate()
	for node_id in queue:
		eta_days[node_id] = 1.0 / chance

	var visited: Dictionary = {}
	var risk_node_id := ""
	var risk_eta := INF

	while not queue.is_empty():
		var node_id: String = queue.pop_front()
		if visited.has(node_id):
			continue
		visited[node_id] = true
		var eta: float = eta_days[node_id]
		var node: Dictionary = WorldMap.nodes[node_id]
		var gate: Dictionary = node.get("gate", {})

		var passable := true
		match gate.get("type", ""):
			"combat":
				if eta <= horizon:
					var result := Combat.predict_party_result(party_id, gate["enemy_power"])
					if result != "victory":
						risk_node_id = node_id
						risk_eta = eta
						break # BFSはeta昇順に訪れるため、最初に見つかった撤退/敗北が最短の危険地点
			"skill":
				passable = _effective_skill_level(_best_member_for_skill(party, gate["skill"]), gate["skill"]) >= gate["min_level"]
			"innate_trait", "item":
				passable = WorldMap.first_passing_member(node_id, party["member_ids"]) != -1

		if not passable:
			continue # 今のスキル/所持品では今月中に抜けられる保証が無い

		for neighbor_id in node["connections"]:
			if not WorldMap.nodes.has(neighbor_id):
				continue
			var neighbor: Dictionary = WorldMap.nodes[neighbor_id]
			if neighbor["section"] != section_id or neighbor["found"] or visited.has(neighbor_id):
				continue
			var next_eta: float = eta + 1.0 / chance
			if not eta_days.has(neighbor_id) or next_eta < eta_days[neighbor_id]:
				eta_days[neighbor_id] = next_eta
			queue.append(neighbor_id)

	var retreat_probability := 0.0
	var risk_node_name := ""
	if risk_node_id != "":
		retreat_probability = 1.0 - exp(-horizon / max(risk_eta, 0.01))
		risk_node_name = WorldMap.nodes[risk_node_id]["name"]

	return {
		"base_income": base_income,
		"predicted_income": int(round(base_income * (1.0 - retreat_probability))),
		"retreat_probability": retreat_probability,
		"risk_node_name": risk_node_name,
	}

## design.md 6.2節「推奨戦力」: セクション内で最も敵戦闘力(enemy_power)が高い戦闘ゲートの値。
## 戦闘ゲートが無いセクションは0を返す。
func recommended_power_for_section(section_id: String) -> int:
	var highest := 0
	for node_id in WorldMap.nodes_in_section(section_id):
		var gate: Dictionary = WorldMap.nodes[node_id].get("gate", {})
		if gate.get("type", "") == "combat":
			highest = max(highest, int(gate["enemy_power"]))
	return highest
