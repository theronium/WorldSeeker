class_name Jobs
# 探索者のジョブ(職業)定義。design.md 4.8節。SkillTypesと同じ静的定義パターン(オートロードではない)。
# 既存5スキル(SkillTypes.Skill)に1対1対応する5職を用意する。

enum Job { WARRIOR, HEAVY_WARRIOR, THIEF, SAGE, SCOUT }
enum WeaponType { SWORD, GREAT_HAMMER, DAGGER, STAFF, BOW }
enum ArmorCategory { HEAVY, LIGHT, ROBE }

const JOB_NAMES := {
	Job.WARRIOR: "戦士",
	Job.HEAVY_WARRIOR: "重戦士",
	Job.THIEF: "盗賊",
	Job.SAGE: "賢者",
	Job.SCOUT: "斥候",
}

## 各ジョブの得意スキル(経験値獲得ボーナスの対象、4.8節)。
const JOB_SKILL_AFFINITY := {
	Job.WARRIOR: SkillTypes.Skill.COMBAT,
	Job.HEAVY_WARRIOR: SkillTypes.Skill.DESTRUCTION,
	Job.THIEF: SkillTypes.Skill.LOCKPICKING,
	Job.SAGE: SkillTypes.Skill.WISDOM,
	Job.SCOUT: SkillTypes.Skill.PERCEPTION,
}

const JOB_WEAPON_TYPE := {
	Job.WARRIOR: WeaponType.SWORD,
	Job.HEAVY_WARRIOR: WeaponType.GREAT_HAMMER,
	Job.THIEF: WeaponType.DAGGER,
	Job.SAGE: WeaponType.STAFF,
	Job.SCOUT: WeaponType.BOW,
}

const JOB_ARMOR_CATEGORY := {
	Job.WARRIOR: ArmorCategory.HEAVY,
	Job.HEAVY_WARRIOR: ArmorCategory.HEAVY,
	Job.THIEF: ArmorCategory.LIGHT,
	Job.SAGE: ArmorCategory.ROBE,
	Job.SCOUT: ArmorCategory.LIGHT,
}

const SKILL_EXP_MULTIPLIER := 1.5

static func all_jobs() -> Array:
	return Job.values()

## 得意スキルの経験値獲得倍率(4.8節)。得意スキルなら1.5倍、それ以外は等倍。
static func exp_multiplier_for(job: int, skill: int) -> float:
	return SKILL_EXP_MULTIPLIER if JOB_SKILL_AFFINITY.get(job, -1) == skill else 1.0
