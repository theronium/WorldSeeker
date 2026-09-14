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

func resolve_party_encounter(party_id: int, enemy_power: int, current_day: int) -> Dictionary:
	var party := Parties.get_party(party_id)
	if party.is_empty():
		return {"result": "error"}

	var any_defeated := false
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
			hp -= max(1, enemy_power - combat_power)
			enemy_power -= max(1, combat_power - enemy_power / 2)

			if hp / npc["max_hp"] <= policy["hp_threshold"]:
				if policy["action"] == Npcs.CombatAction.RETREAT:
					npc["hp"] = max(hp, 1.0)
					retreated = true
					break
				else:
					hp += npc["max_hp"] * 0.3 # アイテム使用による回復

		# 実際に戦った分(ラウンド数)だけ戦闘力の経験値が入る。結果が勝利でも敗北でも変わらない。
		Npcs.grant_skill_exp(npc_id, SkillTypes.Skill.COMBAT, rounds)

		if retreated:
			continue # 次のメンバーが、この時点のenemy_powerを引き継いで戦う

		# hp<=0を先に判定する(同ラウンドでenemy_powerも<=0になる相殺の場合、このメンバー自身は
		# 戦闘不能として扱う。次のメンバーがいれば、既に力尽きた敵を引き継ぐだけで勝利できる)。
		if hp <= 0:
			npc["hp"] = 1.0
			any_defeated = true
			continue

		npc["hp"] = hp
		victor_id = npc_id # 突破報酬アイテムの受け取り手(止めを刺したメンバー)
		break

	if victor_id != -1:
		if any_defeated:
			# 勝利はしたが、途中で戦闘不能になったメンバーがいる。パーティ全体を短い療養に入れ、
			# 次に動けるようになった時点でHPを全回復させる(回復の唯一の経路、Parties.is_available参照)。
			Parties.retreat_and_recover(party_id, current_day, 3)
		return {"result": "victory", "npc_id": victor_id}

	var recovery_days := 5 if any_defeated else 3
	Parties.retreat_and_recover(party_id, current_day, recovery_days)
	return {"result": "defeat" if any_defeated else "retreat"}

## exploration.gdのforecast_section(「予測」ボタン)用の非破壊シミュレーション。
## resolve_party_encounter()と同じ計算式を使うが、NPCの実際のHP/経験値/回復状態には
## 一切書き込まない(dry run)。
func predict_party_result(party_id: int, enemy_power: int) -> String:
	var party := Parties.get_party(party_id)
	if party.is_empty():
		return "error"

	var any_defeated := false
	for npc_id in party["member_ids"]:
		var npc := Npcs.get_npc(npc_id)
		if npc.is_empty():
			continue
		var combat_power := _combat_power_for(npc_id, npc, party)
		var hp: float = npc["hp"]
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
