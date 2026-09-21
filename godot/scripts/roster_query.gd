class_name RosterQuery
# 探索者管理パネルの一覧の、並べ替えと絞り込み(画面に依存しない部分。2026-09-21)。
# 並べ替えの項目: 加入順(雇った順=ID順)/ 名前 / 総合戦力(Npcs.power)/ 各スキルのLv。
# 絞り込み: 血筋 / ジョブ(どちらも「すべて」なら絞らない。両方指定すればAND)。
# 並べ替えは、同じ値なら常にID順(向きに関わらず)にそろえる。Godotのsort_customは安定ソートではないため。

const SORT_JOIN := "join"
const SORT_NAME := "name"
const SORT_POWER := "power"
const SORT_SKILL_PREFIX := "skill:" # "skill:<SkillTypes.Skill>"

const ALL_BLOODLINES := ""
const ALL_JOBS := -1

## 並べ替えの選択肢: [{"key", "label", "descending"}]。descendingは、その項目を選んだ直後の向き
## (戦力・スキルは大きい順、加入順・名前は昇順)。
static func sort_options() -> Array:
	var options: Array = [
		{"key": SORT_JOIN, "label": "加入順", "descending": false},
		{"key": SORT_NAME, "label": "名前", "descending": false},
		{"key": SORT_POWER, "label": "総合戦力", "descending": true},
	]
	for skill in SkillTypes.all_skills():
		options.append({"key": SORT_SKILL_PREFIX + str(skill), "label": "%sLv" % SkillTypes.SKILL_NAMES[skill], "descending": true})
	return options

## 並べ替えのキーがスキルのものなら、そのスキル(SkillTypes.Skill)を返す。違えば-1。
static func skill_of_key(key: String) -> int:
	if key.begins_with(SORT_SKILL_PREFIX):
		return int(key.substr(SORT_SKILL_PREFIX.length()))
	return -1

static func sort_value(npc: Dictionary, key: String) -> Variant:
	var id: int = int(npc["id"])
	if key == SORT_NAME:
		return String(npc["name"])
	if key == SORT_POWER:
		return Npcs.power(id)
	var skill := skill_of_key(key)
	if skill >= 0:
		return Npcs.skill_level(id, skill)
	return id # SORT_JOIN、または知らないキー

static func matches(npc: Dictionary, bloodline: String, job: int) -> bool:
	if bloodline != ALL_BLOODLINES and String(npc["innate_traits"].get("bloodline", "")) != bloodline:
		return false
	if job != ALL_JOBS and int(npc["job"]) != job:
		return false
	return true

## 絞り込んで、並べ替えた探索者の配列を返す(元の配列は変えない)。
static func query(roster: Array, sort_key: String, descending: bool, bloodline: String = ALL_BLOODLINES, job: int = ALL_JOBS) -> Array:
	var result: Array = roster.filter(func(npc): return matches(npc, bloodline, job))
	result.sort_custom(func(a, b): return _before(a, b, sort_key, descending))
	return result

static func _before(a: Dictionary, b: Dictionary, key: String, descending: bool) -> bool:
	var value_a: Variant = sort_value(a, key)
	var value_b: Variant = sort_value(b, key)
	if value_a != value_b:
		return (value_a > value_b) if descending else (value_a < value_b)
	return int(a["id"]) < int(b["id"])

## 一覧のカードに出す1行。総合戦力は常に出し、スキルのLvで並べている時は、そのスキルのLvも添える
## (並べた結果の根拠が、カードを見れば分かるように)。
static func card_stat_text(npc: Dictionary, sort_key: String) -> String:
	var id: int = int(npc["id"])
	var text := "戦力 %d" % Npcs.power(id)
	var skill := skill_of_key(sort_key)
	if skill >= 0:
		text += " ・ %s Lv%d" % [SkillTypes.SKILL_NAMES[skill], Npcs.skill_level(id, skill)]
	return text

## 絞り込みの選択肢に出す血筋: いま名簿にいる血筋を、Recruitment.BLOODLINESの並び順で(それ以外は出てきた順で)。
static func bloodlines_in(roster: Array) -> Array:
	var present := {}
	for npc in roster:
		present[String(npc["innate_traits"].get("bloodline", ""))] = true
	var result: Array = []
	for bloodline in Recruitment.BLOODLINES:
		if present.has(bloodline):
			result.append(bloodline)
			present.erase(bloodline)
	for bloodline in present.keys():
		if bloodline != "":
			result.append(bloodline)
	return result

## 総合戦力の内訳を、詳細に出す1行の文字にする(合計が先頭。0の項目は省く)。
static func power_breakdown_text(id: int) -> String:
	var b: Dictionary = Npcs.power_breakdown(id)
	var parts: Array = ["戦闘スキルLv%d → %d" % [b["skill_level"], b["skill"]]]
	if int(b["weapon"]) != 0:
		parts.append("武器 +%d" % b["weapon"])
	if int(b["armor"]) != 0:
		parts.append("防具 +%d" % b["armor"])
	if int(b["unique"]) != 0:
		parts.append("固有スキル +%d" % b["unique"])
	return "総合戦力 %d(%s)" % [b["total"], " / ".join(parts)]
