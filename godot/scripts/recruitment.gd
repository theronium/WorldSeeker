extends Node
# 募集(候補提示)から雇用までのフロー。

const BLOODLINES := ["平民", "旧家の血筋", "森人の血", "王家の落胤"]
## 雇用候補の血筋の出やすさ(合計100)。旧家の血筋と王家の落胤は、ごく稀にしか出ない(2026-09-24。以前は4種が等確率で、
## 候補の4人に1人が王家の落胤だった)。主な入手手段は、シナリオのイベントでの加入(効果「探索者が加入する」)。
const BLOODLINE_WEIGHTS := {"平民": 71, "森人の血": 25, "旧家の血筋": 3, "王家の落胤": 1}

var current_candidates: Array = []

func post_recruitment() -> bool:
	if not Economy.spend(Economy.recruitment_post_cost()):
		return false
	current_candidates = _generate_candidates(3)
	return true

func _generate_candidates(count: int) -> Array:
	var candidates := []
	var jobs := Jobs.all_jobs()
	for i in range(count):
		var quality := randf()
		var skills := {}
		for skill in SkillTypes.all_skills():
			skills[skill] = randi_range(0, 2) + int(quality * 3)
		var bloodline := _roll_bloodline()
		var job: int = jobs[randi() % jobs.size()]
		candidates.append({
			"name": NameGenerator.generate(bloodline),
			"quality": quality,
			"innate_traits": {"bloodline": bloodline},
			"job": job,
			"portrait": PortraitLibrary.generate(bloodline), # 雇用パネルのプレビューに使う(2026-09-14)
			"skills": skills,
			"cost": Economy.hire_cost(quality),
		})
	return candidates

## BLOODLINE_WEIGHTSの重みで、血筋を1つ選ぶ。
static func _roll_bloodline() -> String:
	var total := 0
	for weight in BLOODLINE_WEIGHTS.values():
		total += int(weight)
	var roll := randi() % total
	for bloodline in BLOODLINES:
		roll -= int(BLOODLINE_WEIGHTS.get(bloodline, 0))
		if roll < 0:
			return bloodline
	return BLOODLINES[0]

func hire_candidate(index: int) -> int:
	if index < 0 or index >= current_candidates.size():
		return -1
	if Npcs.get_roster().size() >= Economy.employ_cap:
		return -1
	var candidate: Dictionary = current_candidates[index]
	if not Economy.spend(candidate["cost"]):
		return -1
	var id := Npcs.hire(candidate["name"], candidate["innate_traits"], candidate["skills"], candidate["job"], candidate["portrait"])
	current_candidates.remove_at(index)
	return id

## 新規プレイ開始(複数セーブスロット、save_system.gd)用のリセット。
func reset() -> void:
	current_candidates = []
