extends Node
# ボス・危険な生物との戦闘解決。事前設定された方針に従い自動進行する。

func resolve_encounter(npc_id: int, enemy_power: int, current_day: int) -> Dictionary:
	var npc := Npcs.get_npc(npc_id)
	if npc.is_empty():
		return {"result": "error"}

	var combat_power: int = Npcs.skill_level(npc_id, SkillTypes.Skill.COMBAT) * 10 + 10
	var hp: float = npc["hp"]
	var policy: Dictionary = npc["combat_policy"]
	var rounds := 0

	while hp > 0 and enemy_power > 0:
		rounds += 1
		hp -= max(1, enemy_power - combat_power)
		enemy_power -= max(1, combat_power - enemy_power / 2)

		if hp / npc["max_hp"] <= policy["hp_threshold"]:
			if policy["action"] == Npcs.CombatAction.RETREAT:
				npc["hp"] = max(hp, 1.0)
				Npcs.grant_skill_exp(npc_id, SkillTypes.Skill.COMBAT, rounds)
				Npcs.retreat_and_recover(npc_id, current_day, 3)
				return {"result": "retreat"}
			else:
				hp += npc["max_hp"] * 0.3 # アイテム使用による回復

	# 実際に戦った分(ラウンド数)だけ戦闘力の経験値が入る。結果が勝利でも敗北でも変わらない。
	Npcs.grant_skill_exp(npc_id, SkillTypes.Skill.COMBAT, rounds)

	if hp <= 0:
		npc["hp"] = 1.0
		Npcs.retreat_and_recover(npc_id, current_day, 5)
		return {"result": "defeat"}

	npc["hp"] = hp
	return {"result": "victory"}
