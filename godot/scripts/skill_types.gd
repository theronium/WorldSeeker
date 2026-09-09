class_name SkillTypes

enum Skill {
	WISDOM,       # リドル等の謎解き
	LOCKPICKING,  # 施錠された扉
	DESTRUCTION,  # 障害物の破壊
	PERCEPTION,   # 隠し通路への気づき
	COMBAT,       # 戦闘力
}

const SKILL_NAMES := {
	Skill.WISDOM: "知恵",
	Skill.LOCKPICKING: "鍵開け",
	Skill.DESTRUCTION: "破壊",
	Skill.PERCEPTION: "知覚/発見",
	Skill.COMBAT: "戦闘力",
}

static func all_skills() -> Array:
	return Skill.values()
