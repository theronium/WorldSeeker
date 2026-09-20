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
		"lap_start_day": -1, # 完全踏破済みセクションでの周回(ループ)開始日。exploration.gd参照
		# 戦力不足で退避中の記録(exploration.gdの_check_blocked/_update_retreat_state参照)。return_sectionが空でなければ
		# 退避(待機)中で、return_nodeの敵に勝てる見込みが立ったらreturn_sectionへ戻る。
		"return_section": "",
		"return_node": "",
	}
	for npc_id in member_ids:
		Npcs.set_party(npc_id, id)
	return id

## パーティ解散(main.gdのパーティ詳細パネル「パーティを解散する」ボタンから呼ばれる)。
## 全メンバーが未所属に戻る。スキル/ジョブ/装備/固有スキルはNPC個体側が持つため失われない。
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
	parties[party_id]["lap_start_day"] = -1 # 配置転換したら周回の進み具合もリセット(exploration.gdが再開始する)
	# 割り当て直したら、退避中の記録は消える(プレイヤーの手動の割り当てでも、自動の配置転換でも)
	parties[party_id]["return_section"] = ""
	parties[party_id]["return_node"] = ""
	return true

## 戦力不足のフロアの前で詰まったパーティを、safe_sectionへ退避させ、勝てる見込みが立ったら
## back_sectionのblocked_nodeへ戻れるように記録する。safe_sectionがback_sectionと同じ(退避先が無い)なら、
## 移動はせずにその場で待機する扱いになる。
func retreat_for_training(party_id: int, safe_section: String, back_section: String, blocked_node: String) -> bool:
	if not assign_section(party_id, safe_section):
		return false
	parties[party_id]["return_section"] = back_section
	parties[party_id]["return_node"] = blocked_node
	return true

## 移動せずに、その場で待機する扱いにする(退避先が今のセクション自身の時)。
func set_return(party_id: int, back_section: String, blocked_node: String) -> void:
	if parties.has(party_id):
		parties[party_id]["return_section"] = back_section
		parties[party_id]["return_node"] = blocked_node

func clear_return(party_id: int) -> void:
	if parties.has(party_id):
		parties[party_id]["return_section"] = ""
		parties[party_id]["return_node"] = ""

func is_retreating(party: Dictionary) -> bool:
	return String(party.get("return_section", "")) != ""

func set_post_clear_behavior(party_id: int, behavior: int) -> void:
	if parties.has(party_id):
		parties[party_id]["post_clear_behavior"] = behavior

## 完全踏破済みセクションでの周回(ループ)管理(design.md「ループ」設定参照)。
## start_lap()は1周の起点となる日を記録し、reset_lap()は周回対象外(未踏破区間がまだ残っている
## 等)になった時に、次に対象になった時点から改めて1周目を始められるようにクリアする。
func start_lap(party_id: int, current_day: int) -> void:
	if parties.has(party_id):
		parties[party_id]["lap_start_day"] = current_day

func reset_lap(party_id: int) -> void:
	if parties.has(party_id) and parties[party_id]["lap_start_day"] != -1:
		parties[party_id]["lap_start_day"] = -1

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
		party["lap_start_day"] = int(party.get("lap_start_day", -1))
		party["return_section"] = String(party.get("return_section", ""))
		party["return_node"] = String(party.get("return_node", ""))
		parties[id] = party
		max_id = max(max_id, id)
	_next_id = max(int(data.get("next_id", 1)), max_id + 1)

## 新規プレイ開始(複数セーブスロット、save_system.gd)用のリセット。
func reset() -> void:
	parties = {}
	_next_id = 1
