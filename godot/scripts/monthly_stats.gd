extends Node
# 月ごとの探索者別の戦績(与えたダメージ・受けたダメージ・回復させた量)。月末の集計画面(main.gdの
# _show_month_summary)が表示する(2026-10-08)。対象は雇用中の探索者(Npcs.roster)の戦闘と「回復」スキルだけ。
#
# 記録する時に、その日が何か月目か(month_of_day)を見て、前の月の記録が残っていれば捨ててから足す。
# 「次の月へ」を押した時にリセットする作りにしないのは、月末の日(30日目)の戦闘はまだその月に数えたいが、
# TimeSystem.current_monthは月末の日のday_advancedより前に繰り上がるため。日数から月を出せば、月末の待ちの間に
# 会話の後で起きた戦闘も、その月の分として数えられる。

## npc_id -> {"dealt": int, "taken": int, "healed": int}
var stats: Dictionary = {}
## statsが何か月目(0始まり。month_of_day参照)の記録か。-1は、まだ何も記録していない
var month_index: int = -1

## 日数(1日目〜)が何か月目か(0始まり)。1〜30日目が0、31〜60日目が1。
func month_of_day(day: int) -> int:
	return maxi(0, day - 1) / TimeSystem.DAYS_PER_MONTH

func add(npc_id: int, key: String, amount: int) -> void:
	if amount <= 0:
		return
	var month := month_of_day(TimeSystem.current_day)
	if month != month_index:
		stats.clear()
		month_index = month
	if not stats.has(npc_id):
		stats[npc_id] = {"dealt": 0, "taken": 0, "healed": 0}
	stats[npc_id][key] += amount

## 今の月(月末の待ちの間は、終わったばかりの月)の、その探索者の記録。記録が無ければすべて0。
func for_npc(npc_id: int) -> Dictionary:
	if month_index == month_of_day(TimeSystem.current_day) and stats.has(npc_id):
		return stats[npc_id]
	return {"dealt": 0, "taken": 0, "healed": 0}

func save_state() -> Dictionary:
	return {"month_index": month_index, "stats": stats}

func load_state(data: Dictionary) -> void:
	month_index = int(data.get("month_index", -1))
	stats = data.get("stats", {})

func reset() -> void:
	stats.clear()
	month_index = -1
