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

## 「回復」スキル(SkillTypes.Skill.HEALING、2026-09-15追加)による日次のパーティ内HP回復。
## 「復帰後HP回復手段がないため1のまま挑んでしまう」というバグ報告への対応。それまではHPが
## 回復するのはParties.retreat_and_recover()経由の療養明け(Parties.is_available参照)だけで、
## 勝利はしたが個別に撤退したメンバー(combat.gdのRETREAT方針)はそのままHP1付近で放置され、
## 翌日以降も平然と次の戦闘に挑んでしまっていた(combat.gd側は別途any_setbackで修正済み)。
## スキルLv0でも最低限の回復(HEALING_BASE)は起きるようにし(無課金プレイでも詰まりきらない、
## design.md 4.3節の方針)、Lvが上がるほど回復量が伸びる。
const HEALING_BASE := 5
const HEALING_PER_LEVEL := 3

## 完全踏破済みセクションでの周回(ループ)収入(2026-09-15、「ループでループしない」という
## バグ報告への対応。design.md上「ループ=そのまま留まって収入源として維持する」だったのを
## 実際に周回する仕組みへ変更した)。完全踏破後のセクションは、月次収入の対象から外れる代わりに、
## 1周(セクションのフロア数に応じた日数で最初のフロアから最後のフロアまで再度進む)ごとに
## 月次収入と同じ単価で収入を得る。月内に何周もできれば、その分だけ収入も増える
## (_process_lap参照)。マップ上のパーティアイコンも、周回の進み具合に応じて最初のフロアから
## 動かし、1周し終えるたびに最初のフロアへ戻す(main.gdの_current_node_for_party参照)。
const LAP_INCOME_PER_POINT := MONTHLY_INCOME_PER_POINT

# 戦力不足で退避(待機)している間に、パーティ全員が毎日得る戦闘力の経験値(_update_retreat_state)。
# 戦闘力のレベルアップに必要な経験値は10×(レベル+1)なので、Lv0→1が約10日。初期チューニング値(要調整)。
const RETREAT_TRAINING_EXP_PER_DAY := 1

## 初めて戦闘で撤退した直後だけ、案内会話(シナリオの場面名"retreat")を再生する。「ループ」「先へ進む」
## (design.md 4.7節のpost_clear_behavior)は今まさに阻まれている状況には関係なく、セクションを完全に突破し
## 終えたあとの挙動を決める設定だと誤解されやすいため、その区別を説明する内容(デフォルトシナリオ)。
## 会話の中身は、2026-09-21にシナリオ(scenarios/<id>/events/guide_retreat.json)へ移した。
## SaveSystem.is_tutorial_seen("retreat")で(シナリオごとに)一度きりに制御する(_post_retreat_help()/_maybe_show_retreat_tutorial()参照)。

## 撤退説明会話の予約フラグ: _post_retreat_help()が立て、EventDialogue.finished(または
## その場)から_maybe_show_retreat_tutorial()が消化する。true→実際に再生完了までの間、
## trueのままになりうる(既に別の会話が開いている間は待つ)。
var _retreat_tutorial_pending: bool = false

func _ready() -> void:
	TimeSystem.day_advanced.connect(_on_day_advanced)
	TimeSystem.month_ended.connect(_on_month_ended)
	# 撤退説明会話(下記_post_retreat_help参照)を、既に開いている別の会話(フロア発見時の
	# VN等)を横取りせずに安全なタイミングで出すための待ち受け。
	EventDialogue.finished.connect(_on_any_dialogue_finished)

## 撤退の瞬間、_post_retreat_help()はまだ「発見イベントの本編VN」を再生する前(_on_node_found
## 参照)のことがあり、その場でEventDialogue.play()すると直後に本編VNのplay()で即座に
## 上書きされてしまう(EventDialogue.play()はis_active判定なしに強制的に現在の会話を
## 差し替えるため)。call_deferred()で1フレーム後に回すことで、同一フレーム内で起きる
## その後続のplay()呼び出しが全て終わってから安全に判定できるようにする。
func _on_any_dialogue_finished(_outcome: String) -> void:
	if _retreat_tutorial_pending:
		call_deferred("_maybe_show_retreat_tutorial")

func _maybe_show_retreat_tutorial() -> void:
	if not _retreat_tutorial_pending or EventDialogue.is_active:
		return
	_retreat_tutorial_pending = false
	# 「見た」フラグは再生開始時ではなく、実際に最後まで進めてfinishedが発火した時点で
	# 永続化する(main.gdのINTRO_TUTORIAL_SCRIPT再生箇所のコメント参照。同じ理由で、
	# 日数を進めるだけの診断がたまたま撤退を発生させても、会話を進めない限り実ファイルは
	# 汚れない)。
	ScenarioEvents.play_guide("retreat")

## 月末の集計タイムで、担当パーティがいる全セクション分の収入をまとめて資金化する。
## 完全踏破済みのセクションは対象外(_process_lapによる周回収入に置き換わっている。
## 両方から支給すると二重取りになるため)。
func _on_month_ended(current_month: int) -> void:
	var current_day := TimeSystem.current_day
	var total_income := 0
	for party in Parties.get_parties():
		var section_id: String = party["assigned_section"]
		if section_id == "" or not WorldMap.sections.has(section_id):
			continue
		if WorldMap.is_section_cleared(section_id):
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
		# is_available()を先に呼ぶ: RECOVERING状態で回復期限を過ぎたパーティをEXPLORINGへ戻し
		# HPを全回復させる処理はこの呼び出しの中にしかないため、statusチェックを先にすると
		# RECOVERING中のパーティが永久にここへ到達できず、回復期限が来ても自動復帰しなくなる。
		if not Parties.is_available(party["id"], current_day):
			continue
		# 未割当(IDLE、担当セクションから外れている/まだ一度も割り当てていない)のパーティは
		# 「ホームに留まっている」ものとして扱い、毎日その場でHPを全回復させる(2026-09-15、
		# 「ホーム帰還時もフルに回復を」という要望への対応)。以前はEXPLORING以外を丸ごと
		# skipしていたため、IDLEのパーティは(RECOVERING明けの全回復はおろか、EXPLORING中の
		# 「回復」スキルによる緩やかな回復すら)一切回復手段が無いまま放置されていた。
		if party["status"] == Parties.Status.IDLE:
			_heal_idle_party(party)
			continue
		if party["status"] != Parties.Status.EXPLORING:
			continue
		if _update_retreat_state(party, current_day): # 戦力不足で退避中なら、経験値を得る/勝てる見込みが立てば戻る
			continue # 戻った日は、戻っただけで終える(理由は_update_retreat_stateの説明)
		apply_post_clear_behavior(party, current_day) # 完全攻略済みの担当のままなら、「先へ進む」の設定に従って次へ移る
		_apply_daily_healing(party)
		_claim_wild_progress(party)
		_retry_gates(party, current_day)
		if Parties.is_available(party["id"], current_day):
			_attempt_discovery(party, current_day)
			if not EventDialogue.is_active: # 会話が開いた日は、会話が閉じた後に判定する(_on_node_found)
				_check_blocked(party, current_day) # 勝てない敵しか残っていなければ、退避する
		_process_lap(party, current_day)
	ScenarioEvents.check_daily(current_day) # 条件が成り立ったシナリオのイベント(日数・フラグ・到達など)

## 完全踏破済みセクションでの周回(ループ)処理。対象外(まだ未踏破区間が残っている)なら
## 周回状態をリセットしておき、対象になった時点から1周目を始められるようにする。
## 対象で、まだ周回を始めていなければ今日を起点として開始する。1周分の日数が経過したら
## 月次収入と同じ単価で収入を得て、今日を起点に次の周を開始する(=月内に何周もできれば、
## その分だけ収入も増える)。
func _process_lap(party: Dictionary, current_day: int) -> void:
	var section_id: String = party["assigned_section"]
	if section_id == "" or not WorldMap.sections.has(section_id) or not WorldMap.is_section_cleared(section_id):
		Parties.reset_lap(party["id"])
		return
	if party["lap_start_day"] < 0:
		Parties.start_lap(party["id"], current_day)
		return
	var lap_days: int = max(1, WorldMap.nodes_in_section(section_id).size())
	if current_day - party["lap_start_day"] < lap_days:
		return
	var income: int = LAP_INCOME_PER_POINT * WorldMap.section_multiplier(section_id) * WorldMap.passed_count_in_section(section_id)
	Economy.earn(income)
	var section_name: String = WorldMap.sections[section_id]["name"]
	var text := "%sが「%s」を1周し、%d資金を得た" % [party["name"], section_name, income]
	Board.post_to_thread(section_id, section_name, current_day, text, Board.Importance.MINOR, "lap_income")
	ActionLog.record(current_day, "lap_income", text, -1, "", section_id)
	Parties.start_lap(party["id"], current_day)

## 「回復」スキル(HEALING_BASE/HEALING_PER_LEVEL参照)によるパーティ内の日次HP回復。
## パーティ内で最も「回復」スキルが高いメンバー(_best_member_for_skill、同値ならその職の
## 適性者優先)が、その日の担当者としてHP満タンでないメンバー全員を回復させる。実際に誰かを
## 回復させた日だけ、その担当者へ経験値を1入れる(5.2節「試行を重ねることで育つ」の考え方を
## 踏襲。回復対象がいない日に経験値だけ積み上がる不自然さを避ける)。
func _apply_daily_healing(party: Dictionary) -> void:
	var healer_id := _best_member_for_skill(party, SkillTypes.Skill.HEALING)
	if healer_id == -1:
		return
	var heal_amount := float(HEALING_BASE + HEALING_PER_LEVEL * _effective_skill_level(healer_id, SkillTypes.Skill.HEALING))
	var healed_anyone := false
	for npc_id in party["member_ids"]:
		var npc := Npcs.get_npc(npc_id)
		if npc.is_empty() or npc["hp"] >= npc["max_hp"]:
			continue
		npc["hp"] = min(float(npc["max_hp"]), float(npc["hp"]) + heal_amount)
		healed_anyone = true
	if healed_anyone:
		Npcs.grant_skill_exp(healer_id, SkillTypes.Skill.HEALING, 1)

## 未割当(IDLE)のパーティを毎日全回復させる(_on_day_advanced参照)。「回復」スキルによる
## 緩やかな回復(_apply_daily_healing、探索中のみ)とは別に、担当から明示的に外して
## 休ませれば早く全快する、という分かりやすい手段をプレイヤーに提供する。
func _heal_idle_party(party: Dictionary) -> void:
	for npc_id in party["member_ids"]:
		var npc := Npcs.get_npc(npc_id)
		if not npc.is_empty():
			npc["hp"] = npc["max_hp"]

## 野良探索者(wild_npcs.gd)がゲート無しのフロアを先に発見・突破してしまうと、found=trueに
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
		if EventDialogue.is_active:
			return # 会話が開いた(開いている)間は、続きの発見は翌日(会話→判定の適用→撤退の順を崩さないため)
		Npcs.grant_skill_exp(scout_id, SkillTypes.Skill.PERCEPTION, 1)
		if randf() < chance:
			_on_node_found(scout_name, scout_id, party, node_id, current_day)

func _on_node_found(discoverer_name: String, scout_id: int, party: Dictionary, node_id: String, current_day: int) -> void:
	var node: Dictionary = WorldMap.nodes[node_id]

	if ScenarioEvents.has_gate_event(node_id):
		if EventDialogue.is_active:
			return # 今日は既に別の会話中なので見送り、翌日また発見を試みる
		var milestone := _capture_milestone_state(node_id)
		WorldMap.mark_found(node_id, true)
		# フロアに着いてからの進み方は、会話 → 判定の適用 → イベントの効果 → 撤退(2026-09-21)。会話が開いている間は、
		# HP・休養・突破・報酬・退避・配置転換を動かさない(以前は、会話の前に全て適用されていて、失敗の会話を読んでいる
		# 時点で、パーティは既に退避先へ戻っていた)。会話は結果ごとに別なので、結果は先に決める必要がある。戦闘は、
		# 乱数が無く同じ結果になる非破壊の先読み(_preview_gate)で決め、実際の戦闘は会話が閉じた後に行う。戦闘以外
		# (技能・アイテム・生まれ)は、経験値が入るだけで見た目に出ないので、従来どおり先に判定する。
		var is_combat: bool = String(node["gate"].get("type", "")) == "combat"
		var gate_result := _preview_gate(party, node_id) if is_combat else _attempt_gate(party, node_id, current_day)
		var event := ScenarioEvents.gate_event(node_id, gate_result["passed"])
		if event.is_empty() or event["script"].is_empty():
			# 突破/失敗の片方にだけ会話がある(もう片方は無い)場合は、会話なしで結果だけ反映する
			if is_combat:
				gate_result = _attempt_gate(party, node_id, current_day)
			var reward_npc_id: int = gate_result["npc_id"] if gate_result["passed"] else scout_id
			_finalize_discovery(discoverer_name, node_id, gate_result["passed"], current_day, milestone, reward_npc_id)
			return
		# 突破の確定は、会話の結果コード(outcome)で行う。ScenarioEvents.play()は、同じ会話の終了時に後から
		# 発生済みの記録と効果(フロアの開放など)を適用するので、効果は突破が反映された後に働く。
		# 最後に、on_doneで撤退(退避)の判定をする: 効果まで済んだ後に、先へ進めるかを見る。
		EventDialogue.finished.connect(
			func(outcome: String):
				var applied: Dictionary = _attempt_gate(party, node_id, current_day) if is_combat else gate_result
				var reward_npc_id: int = applied["npc_id"] if applied["passed"] else scout_id
				_finalize_discovery(discoverer_name, node_id, outcome == "pass", current_day, milestone, reward_npc_id),
			CONNECT_ONE_SHOT)
		ScenarioEvents.play(event, func():
			if Parties.is_available(party["id"], current_day):
				_check_blocked(party, current_day))
		return

	var milestone := _capture_milestone_state(node_id)
	WorldMap.mark_found(node_id, true)
	var gate_result := _attempt_gate(party, node_id, current_day)
	var reward_npc_id: int = gate_result["npc_id"] if gate_result["passed"] else scout_id
	_finalize_discovery(discoverer_name, node_id, gate_result["passed"], current_day, milestone, reward_npc_id)

## 戦闘ゲートの結果を、HP・経験値・休養状態に触れずに先読みして、{"passed": bool, "npc_id": -1}を返す
## (_attempt_gateと同じ結果。戦闘に乱数は無く、Combat.predict_party_resultは実際の戦闘と同じ計算式)。
## 会話を先に見せるため(_on_node_found)。突破報酬の受け取り手は、実際に戦うまで決まらないので-1。
func _preview_gate(party: Dictionary, node_id: String) -> Dictionary:
	var node: Dictionary = WorldMap.nodes[node_id]
	if _is_hopeless_gate(party, node):
		return {"passed": false, "npc_id": -1}
	return {"passed": Combat.predict_party_result(party["id"], node["gate"]["enemy_power"]) == "victory", "npc_id": -1}

## 野良探索者(wild_npcs.gd)からも使う、ステータス不問の簡易発見処理。
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
		if party["assigned_section"] == section_id:
			apply_post_clear_behavior(party, current_day)

## 担当セクションが完全攻略済みで、パーティの完全踏破後の設定が「先へ進む」(MOVE_ON)なら、次の未踏破
## セクションへ配置転換する。配置転換したかどうかを返す。
##
## 以前は、セクションを初めて完全攻略した瞬間(_check_section_cleared)にしか判定されなかった。そのため
## 「ループ」のまま攻略を終えて、後から「先へ進む」に切り替えても、次のセクションへ移らなかった
## (2026-09-19、実機で報告)。今は、毎日の探索(_on_day_advanced)と、設定を切り替えた時(main.gd)にも
## 呼ぶので、完全攻略済みのセクションに「先へ進む」で居続けることは無い。ずっと居たいなら「ループ」にする。
func apply_post_clear_behavior(party: Dictionary, current_day: int) -> bool:
	if party["post_clear_behavior"] != Parties.PostClearBehavior.MOVE_ON:
		return false
	if Parties.is_retreating(party):
		return false # 戦力不足で退避中は、勝てる見込みが立つまで、先へ進ませない(進むと同じ敵に戻ってしまう)
	var section_id: String = party["assigned_section"]
	if section_id == "" or not WorldMap.sections.has(section_id) or not WorldMap.is_section_cleared(section_id):
		return false
	var next_section := WorldMap.next_section_to_explore(section_id)
	if next_section == "":
		return false
	var section_name: String = WorldMap.sections[section_id]["name"]
	var next_section_name: String = WorldMap.sections[next_section]["name"]
	Parties.assign_section(party["id"], next_section)
	Board.post(current_day, "%sは「%s」から「%s」へ配置転換された" % [party["name"], section_name, next_section_name], Board.Importance.MINOR, "reassignment")
	# npc_idには代表としてパーティ先頭メンバーを記録する(行動ログの探索者別フィルタで、
	# そのメンバーで絞り込んだ時にも配置転換イベントが見えるようにするため)。
	ActionLog.record(current_day, "reassignment", "%sが「%s」へ配置転換された" % [party["name"], next_section_name], party["member_ids"][0], "", next_section)
	return true

## 満タンのHPでもパーティが勝てない戦闘ゲートかどうか(勝ち目が無い)。
func _is_hopeless_gate(party: Dictionary, node: Dictionary) -> bool:
	var gate: Dictionary = node.get("gate", {})
	if gate.get("type", "") != "combat":
		return false
	return Combat.predict_party_result(party["id"], gate["enemy_power"], true) != "victory"

## 担当セクションで、発見済みだが未突破のフロアが「勝てない戦闘ゲートだけ」になり、これ以上発見できる
## フロアも残っていない(=このセクションでは先に進めない)時に、パーティを退避させる。退避先は、世界の並び順で
## 1つ前の攻略済みセクション。無ければ世界の最初のセクション。退避先が今のセクション自身なら、移動せずに
## その場で待機する。退避中は_update_retreat_stateが毎日経験値を与え、勝てる見込みが立てば元のセクションへ戻す。
## 他に挑めるフロア(技能/アイテムのゲートなど)が残っている間は、退避しない。
func _check_blocked(party: Dictionary, current_day: int) -> void:
	if Parties.is_retreating(party):
		return
	var section_id: String = party["assigned_section"]
	if section_id == "" or not WorldMap.sections.has(section_id):
		return
	var blocker := ""
	for node_id in WorldMap.nodes_in_section(section_id):
		var node: Dictionary = WorldMap.nodes[node_id]
		if not node["found"] or node["passed"]:
			continue
		if not _is_hopeless_gate(party, node):
			return # 他に挑めるフロアが残っている
		if blocker == "":
			blocker = node_id
	if blocker == "":
		return
	if not WorldMap.frontier_for_section(section_id).is_empty():
		return # まだ発見できるフロアがある

	var safe_section := WorldMap.previous_cleared_section(section_id)
	if safe_section == "":
		safe_section = WorldMap.first_section()
	if safe_section == "":
		safe_section = section_id
	var section_name: String = WorldMap.sections[section_id]["name"]
	var blocker_name: String = WorldMap.nodes[blocker]["name"]
	var text: String
	if safe_section == section_id:
		Parties.set_return(party["id"], section_id, blocker)
		text = "%sは「%s」の「%s」に勝つ見込みが無いため、戦力が整うまでその場で待機する" % [party["name"], section_name, blocker_name]
	else:
		var safe_name: String = WorldMap.sections[safe_section]["name"]
		Parties.retreat_for_training(party["id"], safe_section, section_id, blocker)
		text = "%sは「%s」の「%s」に勝つ見込みが無いため、「%s」へ戻って力を付けることにした" % [party["name"], section_name, blocker_name, safe_name]
	Board.post(current_day, text, Board.Importance.MINOR, "reassignment")
	# npc_idには代表としてパーティ先頭メンバーを記録する(配置転換と同じ。行動ログの探索者別フィルタ用)
	ActionLog.record(current_day, "reassignment", text, party["member_ids"][0], blocker, section_id)

## 戦力不足で退避(待機)中のパーティの日次処理。戻り先のフロアにまだ勝てないなら、パーティ全員が戦闘力の
## 経験値を毎日少し(RETREAT_TRAINING_EXP_PER_DAY)得る。勝てる見込みが立った(または、そのフロアが突破済みに
## なった)ら、戻り先のセクションへ戻す(その場で待機していただけなら、退避の記録を消して通常の探索に戻る)。
##
## 戻り先のセクションへ実際に移動した時だけtrueを返す。呼び出し側(_on_day_advanced)は、その日の残りの探索を
## 打ち切る。戻った日にそのままゲートへ挑ませると、勝って完全攻略し、「先へ進む」で次のセクションへ移るまでが
## 1日のうちに済み、画面上は、退避先から2つ先のセクションへ飛んだように見える(戻り先にいる姿が一度も描画されない。
## 2026-09-21、実機で報告)。戻った直後にまた勝てないと分かって退避し直す場合も、動かないまま退避中に見えていた。
func _update_retreat_state(party: Dictionary, current_day: int) -> bool:
	if not Parties.is_retreating(party):
		return false
	var back_section: String = party["return_section"]
	var blocker_id: String = party["return_node"]
	var still_blocked := false
	if WorldMap.nodes.has(blocker_id):
		var blocker: Dictionary = WorldMap.nodes[blocker_id]
		still_blocked = not blocker["passed"] and _is_hopeless_gate(party, blocker)
	if still_blocked:
		for npc_id in party["member_ids"]:
			Npcs.grant_skill_exp(npc_id, SkillTypes.Skill.COMBAT, RETREAT_TRAINING_EXP_PER_DAY)
		return false

	if party["assigned_section"] == back_section or not WorldMap.sections.has(back_section):
		Parties.clear_return(party["id"]) # その場で待機していた(または戻り先が無い)ので、通常の探索に戻る
		return false
	var from_name: String = WorldMap.sections[party["assigned_section"]]["name"] if WorldMap.sections.has(party["assigned_section"]) else ""
	var to_name: String = WorldMap.sections[back_section]["name"]
	Parties.assign_section(party["id"], back_section) # 退避の記録も消える
	var text := "%sは力を付け、「%s」へ戻った" % [party["name"], to_name]
	Board.post(current_day, text, Board.Importance.MINOR, "reassignment")
	ActionLog.record(current_day, "reassignment", text, party["member_ids"][0], "", back_section)
	return true

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
			# 満タンのHPでも勝てない相手には挑まない(戦闘に乱数は無く、同じ戦力なら結果は毎回同じなので、挑んでも
			# 全滅して休養に入るだけ。以前はそれを繰り返して、同じ敵に全滅し続けた)。詰まった後の動きは_check_blocked。
			if _is_hopeless_gate(party, WorldMap.nodes[node_id]):
				return {"passed": false, "npc_id": -1}
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
	var text := "%sは「%s」で%s(相手の戦闘力: %d)。突破のヒント: ①武器防具屋で装備を強化する ②探索者管理パネルで「戦闘力」スキルを訓練する ③このまま何度も挑み続ければ、戦闘の経験値で自然に強くなる。いずれか(または組み合わせ)を試してみてください。" % [
		party["name"], node["name"], verb, enemy_power]
	var section_id: String = node["section"]
	var section_name: String = WorldMap.sections[section_id]["name"] if WorldMap.sections.has(section_id) else section_id
	Board.post_to_thread(section_id, section_name, current_day, text, Board.Importance.MINOR, "combat_retreat")
	ActionLog.record(current_day, "combat_retreat", text, -1, node_id, section_id)

	if not SaveSystem.is_tutorial_seen("retreat") and not _retreat_tutorial_pending:
		_retreat_tutorial_pending = true
		call_deferred("_maybe_show_retreat_tutorial")

## 探索者管理パネルの「予測」ボタン用: 指定パーティを指定セクションに置いた場合の、実際には
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
	if party.is_empty():
		return {"base_income": 0, "predicted_income": 0, "retreat_probability": 0.0, "risk_node_name": ""}
	var base_income: int = MONTHLY_INCOME_PER_POINT * WorldMap.section_multiplier(section_id) * WorldMap.passed_count_in_section(section_id)
	var horizon := float(TimeSystem.DAYS_PER_MONTH)
	var scout_id := _best_member_for_skill(party, SkillTypes.Skill.PERCEPTION)
	var chance := discovery_chance_for_member(scout_id) if scout_id != -1 else DISCOVERY_BASE_CHANCE

	var eta_days: Dictionary = {} # node_id -> float(このノードの発見が見込まれる日数)
	var queue: Array = []

	# 既に発見済みだが未突破のゲート(野良探索者の先行発見や、前回このセクションを担当していた
	# 時に見つけたがまだ突破できていないもの)は、_retry_gates()により配置初日から毎日無条件で
	# 再挑戦される。以前はfrontier_for_section()が返す未発見ノードしか見ておらず(BFSも
	# neighbor["found"]を弾く作り)、こうした「既発見だが未突破」のノードが予測から漏れて
	# いた(=そこが最初のゲートでも撤退リスクが常に0扱いになっていた)。eta=0(即座に
	# リスクがある)として、他のどの未発見フロアよりも先にキューへ積む。
	# 下のBFSは「先に積んだノードほどetaが小さい」前提でeta昇順に処理される(通常のBFSは
	# 均一な辺コストの下でこの前提を保つ性質がある)ため、eta=0のノードを混ぜる際もこの順序
	# (小さいeta→大きいeta)を保つ必要がある。frontier(eta=1/chance)を先に積んでしまうと、
	# より遠いリスクを「最短の危険地点」と誤判定しかねない。
	for node_id in WorldMap.nodes_in_section(section_id):
		var existing_node: Dictionary = WorldMap.nodes[node_id]
		if existing_node["found"] and not existing_node["passed"]:
			eta_days[node_id] = 0.0
			queue.append(node_id)

	for node_id in WorldMap.frontier_for_section(section_id):
		if not eta_days.has(node_id):
			eta_days[node_id] = 1.0 / chance
			queue.append(node_id)

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
			_:
				# _attempt_gate()のdefault分岐と揃える(未知のゲート種別を「常に通過可能」と
				# 誤って見積もらないようにする)。
				if not gate.is_empty():
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
