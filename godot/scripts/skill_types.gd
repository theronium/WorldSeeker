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

## 各スキルが何に使われるかの短い説明。訓練UIで名前の下に添えて表示する。
const SKILL_DESCRIPTIONS := {
	Skill.WISDOM: "リドルや封印など、知的な謎解きゲートを突破する",
	Skill.LOCKPICKING: "施錠された扉のゲートを開ける",
	Skill.DESTRUCTION: "障害物を破壊するゲートを突破する",
	Skill.PERCEPTION: "隠し通路の発見確率と、知覚ゲートの突破に使う",
	Skill.COMBAT: "戦闘の強さ(戦闘力 = Lv×10+10)",
}

static func all_skills() -> Array:
	return Skill.values()
