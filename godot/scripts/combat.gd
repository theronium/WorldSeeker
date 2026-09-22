extends Node
# パーティの戦闘解決。事前設定された方針に従い自動進行する。design.md 5.4節(パーティ制)。
#
# パーティ内の並び順(Parties.parties[party_id]["member_ids"])で1人ずつ、同じ敵と戦う。
# 先頭のメンバーが方針(撤退)に従って戦線を離脱するか、戦闘不能(hp<=0)になると、
# その時点の敵の残り戦闘力を次のメンバーが引き継いで続けて戦う。全員を使い切っても
# なお敵を倒せなければ、パーティ全体が退却し、まとめて一定期間の回復待ちに入る
# (hp<=0になったメンバーが1人でもいれば5日、全員が自主的な撤退のみなら3日)。

## 戦闘に使うcombat_power。装備込みの戦力(Npcs.power)を基準に、固有スキルが
## "front_combat_power_pct"(例: 戦士の「先陣」)かつ、そのメンバーが並び順の先頭(index 0)
## にいる場合だけ補正を掛ける(design.md 4.8節「パーティの先頭に立つ間」)。
func _combat_power_for(npc_id: int, npc: Dictionary, party: Dictionary) -> int:
	var base := Npcs.power(npc_id)
	var skill: Dictionary = npc.get("unique_skill", {})
	if skill.get("effect_type", "") == "front_combat_power_pct" and not party["member_ids"].is_empty() and party["member_ids"][0] == npc_id:
		base = int(round(base * (1.0 + float(skill["value"]))))
	return base

## traceの最後のラウンド(そのメンバーの直近の1エントリ)に、追加の印を付ける。既に何か印(item_usedなど)が
## 付いていれば、両方が分かるよう"+"でつなげる(例: 回復を使ったが、それでも力尽きた場合は"item_used+defeated")。
func _tag_last_round(trace: Array, tag: String) -> void:
	if trace.is_empty():
		return
	var current: String = trace[-1]["event"]
	trace[-1]["event"] = "%s+%s" % [current, tag] if current != "" else tag

## ゲートの敵の戦闘力(基礎値)に、そのパーティの難易度(difficulty.gd)をかけた値。戦闘の解決・予測・
## 「勝ち目が無い」の判定は、すべてこの値で行う(だから難易度を切り替えると、退避や予測も一貫して変わる)。
func effective_enemy_power(party_id: int, base_enemy_power: int) -> int:
	return Difficulty.enemy_power(base_enemy_power, Parties.difficulty(party_id))

## enemy_powerには、ゲートの基礎値(難易度をかける前)を渡す。
##
## 返り値には、戦闘画面(battle_screen.gd)がラウンドごとに再現表示するための"trace"(2026-09-22追加)も
## 入っている: {"npc_id", "round"(そのメンバーの何ラウンド目か), "hp_before"/"hp_after", "max_hp",
## "enemy_before"/"enemy_after", "event"(""/"item_used"/"retreated"/"defeated"/"victory")}の配列。
## 数値計算の行(hp/enemy_powerを増減する式)は一切変えず、その前後でtraceへ積み増すだけにしてある
## (戦闘の勝敗・経験値・HPなど実際の結果に影響しない、副作用の無い追加)。
func resolve_party_encounter(party_id: int, enemy_power: int, current_day: int) -> Dictionary:
	var party := Parties.get_party(party_id)
	if party.is_empty():
		return {"result": "error"}
	enemy_power = effective_enemy_power(party_id, enemy_power)
	var enemy_start_power := enemy_power
	var trace: Array = []

	var any_defeated := false
	# any_setback: any_defeated(hp<=0)に加え、個別にRETREAT方針で戦線離脱した(hpが1付近まで
	# 減っている)メンバーも含む。以前はany_defeatedだけを見て回復要否を判定していたため、
	# 「勝利はしたが誰かが個別に撤退してHP1付近まで減った」ケースでパーティ全体の療養が
	# 一切トリガーされず、そのメンバーがHP1のまま翌日以降の戦闘に平然と挑んでしまう不具合が
	# あった(2026-09-15、「復帰後HP回復手段がないため1のまま挑んでしまう」というバグ報告)。
	var any_setback := false
	var victor_id := -1

	for npc_id in party["member_ids"]:
		var npc := Npcs.get_npc(npc_id)
		if npc.is_empty():
			continue
		var combat_power := _combat_power_for(npc_id, npc, party)
		var hp: float = npc["hp"]
		var policy: Dictionary = npc["combat_policy"]
		var rounds := 0
		var retreated := false

		while hp > 0 and enemy_power > 0:
			rounds += 1
			var hp_before := hp
			var enemy_before := enemy_power
			hp -= max(1, enemy_power - combat_power)
			enemy_power -= max(1, combat_power - enemy_power / 2)
			var event_tag := ""

			if hp / npc["max_hp"] <= policy["hp_threshold"]:
				if policy["action"] == Npcs.CombatAction.RETREAT:
					npc["hp"] = max(hp, 1.0)
					retreated = true
					any_setback = true
					event_tag = "retreated"
					trace.append({"npc_id": npc_id, "round": rounds, "hp_before": hp_before, "hp_after": npc["hp"],
						"max_hp": npc["max_hp"], "enemy_before": enemy_before, "enemy_after": enemy_power, "event": event_tag})
					break
				else:
					hp += npc["max_hp"] * 0.3 # アイテム使用による回復
					event_tag = "item_used"

			trace.append({"npc_id": npc_id, "round": rounds, "hp_before": hp_before, "hp_after": hp,
				"max_hp": npc["max_hp"], "enemy_before": enemy_before, "enemy_after": enemy_power, "event": event_tag})

		# 実際に戦った分(ラウンド数)だけ戦闘力の経験値が入る。結果が勝利でも敗北でも変わらない。
		Npcs.grant_skill_exp(npc_id, SkillTypes.Skill.COMBAT, rounds)

		if retreated:
			continue # 次のメンバーが、この時点のenemy_powerを引き継いで戦う

		# hp<=0を先に判定する(同ラウンドでenemy_powerも<=0になる相殺の場合、このメンバー自身は
		# 戦闘不能として扱う。次のメンバーがいれば、既に力尽きた敵を引き継ぐだけで勝利できる)。
		if hp <= 0:
			npc["hp"] = 1.0
			any_defeated = true
			any_setback = true
			_tag_last_round(trace, "defeated") # このメンバーの最後のラウンドに印を付ける(戦闘画面の演出用)
			continue

		npc["hp"] = hp
		victor_id = npc_id # 突破報酬アイテムの受け取り手(止めを刺したメンバー)
		_tag_last_round(trace, "victory") # 止めを刺したラウンドに印を付ける
		break

	if victor_id != -1:
		if any_setback:
			# 勝利はしたが、途中で戦闘不能または個別撤退になったメンバーがいる。パーティ全体を
			# 短い療養に入れ、次に動けるようになった時点でHPを全回復させる
			# (ホーム帰還時のフル回復、Parties.is_available参照)。
			Parties.retreat_and_recover(party_id, current_day, 3)
		return {"result": "victory", "npc_id": victor_id, "trace": trace, "enemy_start_power": enemy_start_power}

	var recovery_days := 5 if any_defeated else 3
	Parties.retreat_and_recover(party_id, current_day, recovery_days)
	return {"result": "defeat" if any_defeated else "retreat", "trace": trace, "enemy_start_power": enemy_start_power}

## exploration.gdのforecast_section(「予測」ボタン)用の非破壊シミュレーション。
## resolve_party_encounter()と同じ計算式を使うが、探索者の実際のHP/経験値/回復状態には
## 一切書き込まない(dry run)。
## assume_full_hpをtrueにすると、今のHPではなく全員が満タンだった場合の結果を返す(「満タンでも勝てない=勝ち目が
## 無い」の判定用。exploration.gdの_is_hopeless_gate)。
## enemy_powerには、ゲートの基礎値(難易度をかける前)を渡す。
func predict_party_result(party_id: int, enemy_power: int, assume_full_hp: bool = false) -> String:
	var party := Parties.get_party(party_id)
	if party.is_empty():
		return "error"
	enemy_power = effective_enemy_power(party_id, enemy_power)

	var any_defeated := false
	for npc_id in party["member_ids"]:
		var npc := Npcs.get_npc(npc_id)
		if npc.is_empty():
			continue
		var combat_power := _combat_power_for(npc_id, npc, party)
		var hp: float = npc["max_hp"] if assume_full_hp else npc["hp"]
		var policy: Dictionary = npc["combat_policy"]
		var retreated := false

		while hp > 0 and enemy_power > 0:
			hp -= max(1, enemy_power - combat_power)
			enemy_power -= max(1, combat_power - enemy_power / 2)
			if hp / npc["max_hp"] <= policy["hp_threshold"]:
				if policy["action"] == Npcs.CombatAction.RETREAT:
					retreated = true
					break
				else:
					hp += npc["max_hp"] * 0.3

		if retreated:
			continue
		# resolve_party_encounter()と同じ優先順位(hp<=0を先に判定)にしておく。
		if hp <= 0:
			any_defeated = true
			continue
		return "victory"

	return "defeat" if any_defeated else "retreat"
