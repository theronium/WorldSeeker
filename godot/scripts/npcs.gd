extends Node
# 雇用NPCの名簿管理。
#
# 2026-09-14のパーティ制導入により、担当セクション/探索状態/回復待ち/踏破後の挙動は
# パーティ単位(parties.gd)に移った。ここではNPC個人の資質(血筋/ジョブ/スキル/装備/
# 固有スキル/所持品/HP/戦闘方針)だけを扱う。

enum CombatAction { USE_ITEM, RETREAT }

var _next_id: int = 1
var roster: Dictionary = {} # id -> npc data

## portrait_idを省略(空文字)すると血筋から新規抽選する。Recruitment側で候補提示の時点
## (雇用ボタンを押す前)から肖像を確定・表示しておきたいため、明示的に渡せるようにしてある
## (雇用パネルのプレビューと実際に雇用されるNPCの肖像を一致させるため)。
func hire(display_name: String, innate_traits: Dictionary, base_skills: Dictionary = {}, job: int = Jobs.Job.WARRIOR, portrait_id: String = "") -> int:
	var id := _next_id
	_next_id += 1
	var skills := {}
	for skill in SkillTypes.all_skills():
		skills[skill] = {"level": base_skills.get(skill, 0), "exp": 0}
	var unique_skill := UniqueSkills.generate(job)
	# "max_hp_flat"固有スキルは最大HPそのものを底上げする(常時有効なので雇用時に一度だけ適用)。
	var max_hp: float = 100.0 + (float(unique_skill["value"]) if unique_skill.get("effect_type", "") == "max_hp_flat" else 0.0)
	roster[id] = {
		"id": id,
		"name": display_name,
		"innate_traits": innate_traits,
		"job": job,
		"unique_skill": unique_skill,
		"portrait": portrait_id if portrait_id != "" else PortraitLibrary.generate(innate_traits.get("bloodline", "")),
		"skills": skills,
		"hp": max_hp,
		"max_hp": max_hp,
		"combat_policy": {"hp_threshold": 0.3, "action": CombatAction.USE_ITEM},
		"inventory": [],
		"equipped_weapon": {}, # {"tier": Equipment.Tier} または空(未装備)
		"equipped_armor": {},
		"party_id": -1, # 所属パーティ(未所属なら-1)
	}
	return id

func get_npc(id: int) -> Dictionary:
	return roster.get(id, {})

func get_roster() -> Array:
	return roster.values()

func set_party(id: int, party_id: int) -> void:
	if roster.has(id):
		roster[id]["party_id"] = party_id

func set_combat_policy(id: int, hp_threshold: float, action: int) -> void:
	if roster.has(id):
		roster[id]["combat_policy"] = {"hp_threshold": hp_threshold, "action": action}

const EXP_PER_LEVEL := 10

## 経験値獲得。ジョブの得意スキル(job_types.gd)なら1.5倍になる(design.md 4.8節)。
func grant_skill_exp(id: int, skill: int, amount: int) -> void:
	if not roster.has(id):
		return
	var npc: Dictionary = roster[id]
	var entry: Dictionary = npc["skills"][skill]
	entry["exp"] += int(round(amount * Jobs.exp_multiplier_for(npc["job"], skill)))
	var needed: int = EXP_PER_LEVEL * (entry["level"] + 1)
	while entry["exp"] >= needed:
		entry["exp"] -= needed
		entry["level"] += 1
		needed = EXP_PER_LEVEL * (entry["level"] + 1)

func train_skill(id: int, skill: int, cost_paid: int) -> void:
	if not roster.has(id):
		return
	roster[id]["skills"][skill]["level"] += 1

func skill_level(id: int, skill: int) -> int:
	if not roster.has(id):
		return 0
	return roster[id]["skills"][skill]["level"]

## 戦力スコア(design.md 6.2節): スキル(戦闘力)由来のcombat_power + 装備の戦闘力補正。
func power(id: int) -> int:
	if not roster.has(id):
		return 0
	var npc: Dictionary = roster[id]
	var total: int = skill_level(id, SkillTypes.Skill.COMBAT) * 10 + 10
	if npc["equipped_weapon"].has("tier"):
		total += Equipment.power_bonus(npc["equipped_weapon"]["tier"])
	if npc["equipped_armor"].has("tier"):
		total += Equipment.power_bonus(npc["equipped_armor"]["tier"])
	var unique: Dictionary = npc.get("unique_skill", {})
	if unique.get("effect_type", "") == "combat_power_flat":
		total += int(unique["value"])
	return total

## 装備。slotは"weapon"か"armor"。種類(Jobs.WeaponType/ArmorCategory)はそのNPCのジョブから
## 一意に決まるため引数に取らず、材質等級(tier)だけを指定する(design.md 6.2節)。
func equip(id: int, slot: String, tier: int) -> bool:
	if not roster.has(id):
		return false
	match slot:
		"weapon":
			roster[id]["equipped_weapon"] = {"tier": tier}
		"armor":
			roster[id]["equipped_armor"] = {"tier": tier}
		_:
			return false
	return true

## 転職(design.md 4.8節、半固定)。スキルLv・経験値・固有スキルは変化しない(そのNPC個人の
## 資質として維持される)。装備している武器・防具は新ジョブでは種類が合わなくなるため、
## 転職時に自動で外す(プレイヤーは武器防具屋で新ジョブに合った装備を買い直す)。
func change_job(id: int, new_job: int) -> void:
	if not roster.has(id):
		return
	roster[id]["job"] = new_job
	roster[id]["equipped_weapon"] = {}
	roster[id]["equipped_armor"] = {}

func save_state() -> Dictionary:
	return {"next_id": _next_id, "roster": roster}

## JSON往復後はDictionaryキーが全て文字列に、数値が全てfloatになるため、
## id/スキル種別(int)をキーに使うroster/skillsは明示的に復元し直す必要がある。
func load_state(data: Dictionary) -> void:
	roster = {}
	var max_id := 0
	for key in data.get("roster", {}).keys():
		var id := int(key)
		var npc: Dictionary = data["roster"][key]
		npc["id"] = id
		npc["job"] = int(npc.get("job", Jobs.Job.WARRIOR))
		npc["party_id"] = int(npc.get("party_id", -1))
		npc["combat_policy"]["action"] = int(npc["combat_policy"]["action"])
		var skills := {}
		for skill_key in npc["skills"].keys():
			var entry: Dictionary = npc["skills"][skill_key]
			skills[int(skill_key)] = {"level": int(entry["level"]), "exp": int(entry["exp"])}
		# 旧セーブ(スキル追加前に保存されたもの)には、後から追加されたスキル(例: 2026-09-15の
		# HEALING)の行がnpc_skillsテーブルに一切無い。ここで補わないと、skill_level()等の
		# roster[id]["skills"][skill]アクセスがキー不在でエラーになる(Lv0からのスタートとして
		# 補完すれば、新スキルも既存NPCが後から普通に鍛えられる)。
		for skill in SkillTypes.all_skills():
			if not skills.has(skill):
				skills[skill] = {"level": 0, "exp": 0}
		npc["skills"] = skills
		roster[id] = npc
		max_id = max(max_id, id)
	_next_id = max(int(data.get("next_id", 1)), max_id + 1)

## 新規プレイ開始(複数セーブスロット、save_system.gd)用のリセット。
func reset() -> void:
	roster = {}
	_next_id = 1

## 初期パーティ(design.md 4.7節、購入不要で最低限揃っている状態)用に、得意スキルが
## 被らない4人(戦士/重戦士/盗賊/賢者)を平民血筋・木等級装備で雇用する。斥候(知覚)は
## 含めない、という設計時の決定(4.7節参照。常にどれか1職の恩恵を諦める編成になる)。
func create_starter_roster() -> Array:
	var starter_jobs := [Jobs.Job.WARRIOR, Jobs.Job.HEAVY_WARRIOR, Jobs.Job.THIEF, Jobs.Job.SAGE]
	var ids := []
	for job in starter_jobs:
		var id := hire(NameGenerator.generate("平民"), {"bloodline": "平民"}, {}, job)
		equip(id, "weapon", Equipment.Tier.WOOD)
		equip(id, "armor", Equipment.Tier.WOOD)
		ids.append(id)
	return ids
