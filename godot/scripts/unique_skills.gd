class_name UniqueSkills
# NPC個体ごとの固有スキル。design.md 4.8節。
#
# プレイヤーからは「そのNPCだけの個性」に見えるが、実装上はジョブ別の事前定義プールから
# 抽選する(NameGenerator.generate(bloodline)の血筋別名前抽選と同じ仕組み)。
#
# 2026-09-14: ジョブごと8種(計40種)に拡充した(design.md 4.8で「ジョブごとに8〜12種を想定」
# としていた分の初回拡充。当初はパターン例示として各ジョブ1種のみだった)。
#
# effect_typeの意味(npcs.gd/combat.gd/exploration.gdが参照する):
#   "front_combat_power_pct": パーティの戦闘順番で自分の番の間、戦闘力に(1+value)を掛ける
#   "gate_level_bonus": 対象skillのゲート判定時、実効スキルLvに+valueして判定する
#     (design.mdの例示では「成功率+20%」と書いていたが、skillゲートの判定は確率ではなく
#     閾値判定のため、実装に合わせて「実効Lv+2」に読み替えている)
#   "discovery_pct": 発見確率にvalueを加算する
#   "combat_power_flat": 常時、戦闘力(Npcs.power())に+valueする(位置や対象を問わない)
#   "max_hp_flat": 最大HPに+valueする(雇用時に一度だけ適用。Npcs.hire()参照)

const POOL := {
	Jobs.Job.WARRIOR: [
		{"id": "warrior_vanguard", "name": "先陣", "description": "パーティの先頭に立つ間、戦闘力+30%",
			"effect_type": "front_combat_power_pct", "value": 0.3},
		{"id": "warrior_guardian_stance", "name": "鉄壁の構え", "description": "パーティの先頭に立つ間、戦闘力+40%",
			"effect_type": "front_combat_power_pct", "value": 0.4},
		{"id": "warrior_last_stand", "name": "死中に活", "description": "パーティの先頭に立つ間、戦闘力+50%",
			"effect_type": "front_combat_power_pct", "value": 0.5},
		{"id": "warrior_broadsword", "name": "剛剣", "description": "常時、戦闘力+15",
			"effect_type": "combat_power_flat", "value": 15},
		{"id": "warrior_relentless", "name": "連撃", "description": "常時、戦闘力+25",
			"effect_type": "combat_power_flat", "value": 25},
		{"id": "warrior_stalwart", "name": "不屈", "description": "最大HP+30",
			"effect_type": "max_hp_flat", "value": 30},
		{"id": "warrior_ironwall", "name": "守護の心", "description": "最大HP+50",
			"effect_type": "max_hp_flat", "value": 50},
		{"id": "warrior_veteran", "name": "歴戦の勘", "description": "常時、戦闘力+10",
			"effect_type": "combat_power_flat", "value": 10},
	],
	Jobs.Job.HEAVY_WARRIOR: [
		{"id": "heavy_warrior_might", "name": "怪力", "description": "破壊ゲートの判定で、実効スキルLv+2として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.DESTRUCTION, "value": 2},
		{"id": "heavy_warrior_titanic", "name": "大力無双", "description": "破壊ゲートの判定で、実効スキルLv+3として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.DESTRUCTION, "value": 3},
		{"id": "heavy_warrior_earthbreaker", "name": "粉砕王", "description": "破壊ゲートの判定で、実効スキルLv+4として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.DESTRUCTION, "value": 4},
		{"id": "heavy_warrior_crush", "name": "破砕", "description": "常時、戦闘力+20",
			"effect_type": "combat_power_flat", "value": 20},
		{"id": "heavy_warrior_rockskin", "name": "岩の肌", "description": "最大HP+40",
			"effect_type": "max_hp_flat", "value": 40},
		{"id": "heavy_warrior_ironbody", "name": "鋼の肉体", "description": "最大HP+60",
			"effect_type": "max_hp_flat", "value": 60},
		{"id": "heavy_warrior_charge", "name": "猪突猛進", "description": "パーティの先頭に立つ間、戦闘力+35%",
			"effect_type": "front_combat_power_pct", "value": 0.35},
		{"id": "heavy_warrior_quake", "name": "地響き", "description": "常時、戦闘力+18",
			"effect_type": "combat_power_flat", "value": 18},
	],
	Jobs.Job.THIEF: [
		{"id": "thief_quickhands", "name": "早業", "description": "鍵開けゲートの判定で、実効スキルLv+2として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.LOCKPICKING, "value": 2},
		{"id": "thief_shadowhand", "name": "影の手", "description": "鍵開けゲートの判定で、実効スキルLv+3として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.LOCKPICKING, "value": 3},
		{"id": "thief_thousandkeys", "name": "千の鍵", "description": "鍵開けゲートの判定で、実効スキルLv+4として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.LOCKPICKING, "value": 4},
		{"id": "thief_nightvision", "name": "夜目", "description": "発見確率+15%",
			"effect_type": "discovery_pct", "value": 0.15},
		{"id": "thief_nimble", "name": "身軽", "description": "常時、戦闘力+10",
			"effect_type": "combat_power_flat", "value": 10},
		{"id": "thief_stealth", "name": "隠密", "description": "最大HP+15",
			"effect_type": "max_hp_flat", "value": 15},
		{"id": "thief_luckyfingers", "name": "幸運の手癖", "description": "鍵開けゲートの判定で、実効スキルLv+2として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.LOCKPICKING, "value": 2},
		{"id": "thief_bigscore", "name": "一攫千金", "description": "常時、戦闘力+12",
			"effect_type": "combat_power_flat", "value": 12},
	],
	Jobs.Job.SAGE: [
		{"id": "sage_erudition", "name": "博識", "description": "知恵ゲートの判定で、実効スキルLv+2として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.WISDOM, "value": 2},
		{"id": "sage_farsight", "name": "賢人の目", "description": "知恵ゲートの判定で、実効スキルLv+3として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.WISDOM, "value": 3},
		{"id": "sage_ancientlore", "name": "古の知恵", "description": "知恵ゲートの判定で、実効スキルLv+4として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.WISDOM, "value": 4},
		{"id": "sage_intuition", "name": "直感", "description": "発見確率+15%",
			"effect_type": "discovery_pct", "value": 0.15},
		{"id": "sage_focus", "name": "精神統一", "description": "最大HP+20",
			"effect_type": "max_hp_flat", "value": 20},
		{"id": "sage_arcaneward", "name": "秘術の加護", "description": "常時、戦闘力+10",
			"effect_type": "combat_power_flat", "value": 10},
		{"id": "sage_cosmos", "name": "森羅万象", "description": "知恵ゲートの判定で、実効スキルLv+2として扱う",
			"effect_type": "gate_level_bonus", "skill": SkillTypes.Skill.WISDOM, "value": 2},
		{"id": "sage_farseeing", "name": "千里眼", "description": "発見確率+20%",
			"effect_type": "discovery_pct", "value": 0.2},
	],
	Jobs.Job.SCOUT: [
		{"id": "scout_keeneye", "name": "鋭い目", "description": "発見確率+20%",
			"effect_type": "discovery_pct", "value": 0.2},
		{"id": "scout_windstep", "name": "風のように", "description": "発見確率+15%",
			"effect_type": "discovery_pct", "value": 0.15},
		{"id": "scout_hunch", "name": "山勘", "description": "発見確率+25%",
			"effect_type": "discovery_pct", "value": 0.25},
		{"id": "scout_swift", "name": "俊足", "description": "常時、戦闘力+10",
			"effect_type": "combat_power_flat", "value": 10},
		{"id": "scout_wildinstinct", "name": "野生の勘", "description": "最大HP+25",
			"effect_type": "max_hp_flat", "value": 25},
		{"id": "scout_alertness", "name": "気配察知", "description": "発見確率+15%",
			"effect_type": "discovery_pct", "value": 0.15},
		{"id": "scout_falconeye", "name": "隼の目", "description": "発見確率+30%",
			"effect_type": "discovery_pct", "value": 0.3},
		{"id": "scout_forestborn", "name": "森の申し子", "description": "常時、戦闘力+15",
			"effect_type": "combat_power_flat", "value": 15},
	],
}

static func generate(job: int) -> Dictionary:
	var pool: Array = POOL.get(job, [])
	return pool[randi() % pool.size()] if not pool.is_empty() else {}

static func by_id(id: String) -> Dictionary:
	if id == "":
		return {}
	for job in POOL.keys():
		for entry in POOL[job]:
			if entry["id"] == id:
				return entry
	return {}
