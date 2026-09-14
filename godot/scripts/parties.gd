extends Node
# パーティの編成・担当セクション割り当てを管理する。design.md 4.7節。
#
# 2026-09-14のパーティ制導入前は、担当セクション/探索状態/回復待ち/踏破後の挙動は
# NPC個体ごと(npcs.gd)に持っていたが、これらは全てパーティ単位の概念に置き換わった。
# NPC個体はスキル/ジョブ/装備/固有スキルなど「個人の資質」だけを持ち続け、
# 「どこを探索するか」「今どういう状態か」はこちら(Parties)が持つ。

enum Status { IDLE, EXPLORING, RECOVERING }
## セクション完全踏破後の挙動(旧Npcs.PostClearBehaviorをパーティ単位に移した)。
## STAY: そのセクションに留まり続け、収入源として維持する。
## MOVE_ON: 次の未踏破セクションへ自動的に再配置される(無ければ何もしない)。
enum PostClearBehavior { STAY, MOVE_ON }

const MAX_PARTY_SIZE := 4

var _next_id: int = 1
var parties: Dictionary = {} # party_id -> party data

func form_party(member_ids: Array, display_name: String = "") -> int:
	if member_ids.is_empty() or member_ids.size() > MAX_PARTY_SIZE:
		return -1
	var seen: Dictionary = {}
	for npc_id in member_ids:
		if seen.has(npc_id):
			return -1 # 同じNPCを2重に含めることはできない
		seen[npc_id] = true
		var npc := Npcs.get_npc(npc_id)
		if npc.is_empty() or npc["party_id"] != -1:
			return -1 # 既にどこかのパーティに所属しているNPCは含められない

	var id := _next_id
	_next_id += 1
	parties[id] = {
		"id": id,
		"name": display_name if display_name != "" else "パーティ%d" % id,
		"member_ids": member_ids.duplicate(),
		"assigned_section": "",
		"status": Status.IDLE,
		"recovering_until_day": -1,
		"post_clear_behavior": PostClearBehavior.MOVE_ON,
	}
	for npc_id in member_ids:
		Npcs.set_party(npc_id, id)
	return id

## 今回UIからは呼ばないが、対称性のため用意(解散すると全メンバーが未所属に戻る)。
func disband(party_id: int) -> void:
	if not parties.has(party_id):
		return
	for npc_id in parties[party_id]["member_ids"]:
		Npcs.set_party(npc_id, -1)
	parties.erase(party_id)

func get_party(party_id: int) -> Dictionary:
	return parties.get(party_id, {})

func get_parties() -> Array:
	return parties.values()

func reorder(party_id: int, new_order: Array) -> bool:
	if not parties.has(party_id):
		return false
	var current: Array = parties[party_id]["member_ids"]
	var sorted_new: Array = new_order.duplicate()
	sorted_new.sort()
	var sorted_current: Array = current.duplicate()
	sorted_current.sort()
	if new_order.size() != current.size() or sorted_new != sorted_current:
		return false
	parties[party_id]["member_ids"] = new_order.duplicate()
	return true

func assign_section(party_id: int, section_id: String) -> bool:
	if not parties.has(party_id) or not WorldMap.sections.has(section_id):
		return false
	parties[party_id]["assigned_section"] = section_id
	parties[party_id]["status"] = Status.EXPLORING
	return true

func set_post_clear_behavior(party_id: int, behavior: int) -> void:
	if parties.has(party_id):
		parties[party_id]["post_clear_behavior"] = behavior

func retreat_and_recover(party_id: int, current_day: int, recovery_days: int) -> void:
	if not parties.has(party_id):
		return
	parties[party_id]["status"] = Status.RECOVERING
	parties[party_id]["recovering_until_day"] = current_day + recovery_days

func is_available(party_id: int, current_day: int) -> bool:
	if not parties.has(party_id):
		return false
	var party: Dictionary = parties[party_id]
	if party["status"] != Status.RECOVERING:
		return true
	if current_day < party["recovering_until_day"]:
		return false
	party["status"] = Status.EXPLORING
	for npc_id in party["member_ids"]:
		var npc := Npcs.get_npc(npc_id)
		if not npc.is_empty():
			npc["hp"] = npc["max_hp"]
	return true

## パーティ全体の戦力(design.md 6.2節): 4人分のNpcs.power()の単純合算。
func power(party_id: int) -> int:
	if not parties.has(party_id):
		return 0
	var total := 0
	for npc_id in parties[party_id]["member_ids"]:
		total += Npcs.power(npc_id)
	return total

func save_state() -> Dictionary:
	return {"next_id": _next_id, "parties": parties}

## JSON往復想定は無い(save_system.gdが専用テーブルへ書く)が、npcs.gdのload_state()と
## 同じ形の防御的な型復元をしておく。
func load_state(data: Dictionary) -> void:
	parties = {}
	var max_id := 0
	for key in data.get("parties", {}).keys():
		var id := int(key)
		var party: Dictionary = data["parties"][key]
		party["id"] = id
		party["status"] = int(party["status"])
		party["recovering_until_day"] = int(party["recovering_until_day"])
		party["post_clear_behavior"] = int(party.get("post_clear_behavior", PostClearBehavior.MOVE_ON))
		parties[id] = party
		max_id = max(max_id, id)
	_next_id = max(int(data.get("next_id", 1)), max_id + 1)

## 新規プレイ開始(複数セーブスロット、save_system.gd)用のリセット。
func reset() -> void:
	parties = {}
	_next_id = 1
