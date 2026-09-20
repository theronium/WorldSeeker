extends Node
# ワールドの階層構造(エリア > セクション > フロア)とノードグラフを保持する。
#
# - エリア(area)   : 国や地方などの最上位区分
# - セクション(section): ダンジョンやフィールドなど、探索者の担当エリア割り当ての単位
# - フロア(node)   : 個々の場所(ノードグラフの1ノード)
#
# ノードは3状態を取る:
#   未発見          found=false, passed=false
#   発見済みだが進めない  found=true,  passed=false (ゲート未突破)
#   突破済み         found=true,  passed=true
#
# さらに found=true のノードは、雇用探索者自身が到達したか(found_by_employed)を区別する。
# 野良探索者だけが見つけた場所はfound=true/found_by_employed=falseのままになる
# (マップ表示で「自身/誰か/未踏破」の3色に塗り分けるための情報。design.md参照)。

var areas: Dictionary = {} # area_id -> {id, name}
var sections: Dictionary = {} # section_id -> {id, name, area}
var nodes: Dictionary = {} # id -> {name, connections, found, passed, found_by_employed, gate, section, event_script_pass, event_script_fail}
var section_reward_claimed: Dictionary = {} # section_id -> true(攻略報酬を既に支給済みのセクション)

## nodes_in_section()は日次探索処理(exploration.gd)から担当パーティ数×複数回呼ばれるが、
## 毎回全ノードをフィルタし直すと世界全体のノード数に比例して重くなる。add_node()/reset()の
## 時にだけ無効化するキャッシュを持たせ、ゲーム進行中の呼び出しはO(1)気味に保つ。
var _section_nodes_cache: Dictionary = {} # section_id -> Array[String]

func add_area(id: String, display_name: String) -> void:
	areas[id] = {"id": id, "name": display_name}

func add_section(id: String, display_name: String, area_id: String = "") -> void:
	sections[id] = {"id": id, "name": display_name, "area": area_id}

func add_node(id: String, display_name: String, connections: Array, gate: Dictionary = {}, section: String = "", item_reward: String = "") -> void:
	nodes[id] = {
		"id": id,
		"name": display_name,
		"connections": connections,
		"found": false,
		"passed": false,
		"found_by_employed": false,
		"gate": gate, # 例: {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3} / {"type": "item", "item": "goblin_amulet"}
		"section": section, # 所属するセクション(ダンジョン/エリア)のsection_id（未所属なら空文字）
		"item_reward": item_reward, # 突破時に発見者へ渡すアイテムid（なければ空文字）
		"event_script_pass": [],
		"event_script_fail": [],
	}
	_section_nodes_cache.clear()

func set_event_scripts(id: String, script_pass: Array, script_fail: Array) -> void:
	if nodes.has(id):
		nodes[id]["event_script_pass"] = script_pass
		nodes[id]["event_script_fail"] = script_fail

func has_event(id: String) -> bool:
	return nodes.has(id) and (not nodes[id]["event_script_pass"].is_empty() or not nodes[id]["event_script_fail"].is_empty())

func nodes_in_section(section_id: String) -> Array:
	if not _section_nodes_cache.has(section_id):
		_section_nodes_cache[section_id] = nodes.keys().filter(func(id): return nodes[id]["section"] == section_id)
	return _section_nodes_cache[section_id]

func sections_in_area(area_id: String) -> Array:
	return sections.keys().filter(func(id): return sections[id]["area"] == area_id)

func mark_found(id: String, by_employed: bool = false) -> void:
	if nodes.has(id):
		nodes[id]["found"] = true
		if by_employed:
			nodes[id]["found_by_employed"] = true

func mark_passed(id: String, by_employed: bool = false) -> void:
	if nodes.has(id):
		nodes[id]["found"] = true
		nodes[id]["passed"] = true
		if by_employed:
			nodes[id]["found_by_employed"] = true

func is_found(id: String) -> bool:
	return nodes.has(id) and nodes[id]["found"]

func is_passed(id: String) -> bool:
	return nodes.has(id) and nodes[id]["passed"]

func is_found_by_employed(id: String) -> bool:
	return nodes.has(id) and nodes[id]["found_by_employed"]

func is_section_entered(section_id: String) -> bool:
	for id in nodes_in_section(section_id):
		if nodes[id]["found"]:
			return true
	return false

func is_area_entered(area_id: String) -> bool:
	for section_id in sections_in_area(area_id):
		if is_section_entered(section_id):
			return true
	return false

## マップのエリアタブ表示用(design.md 5.1節): そのエリアの中に到達可能なセクションが
## 1つでもあれば選べる。is_section_reachable()のエリア単位版。
func is_area_reachable(area_id: String) -> bool:
	for section_id in sections_in_area(area_id):
		if is_section_reachable(section_id):
			return true
	return false

## 探索者の担当割り当て先として選べるセクションかどうか。既に誰か(雇用/野良問わず)が
## 足を踏み入れているか、まだ誰も入っていなくても隣接する突破済みノードから
## 発見を試みられる状態(frontier_for_sectionが空でない)なら選べる。どちらでもない
## (世界のどこからも繋がっていない未到達地帯)セクションは選択肢から隠す対象になる。
func is_section_reachable(section_id: String) -> bool:
	return is_section_entered(section_id) or not frontier_for_section(section_id).is_empty()

## イベント会話の表示スタイルの種別(event_dialogue.gdのcurrent_kind参照)。ゲートの種類から自動で決める:
## 戦闘は、そのセクションで最も敵戦闘力が高ければ"boss"(セクションの最奥にいる主)、そうでなければ
## "combat"。技能は"skill"、アイテムは"item"、生まれ・血筋の条件は"bloodline"。ゲートが無い/未知なら""
## (従来の見た目)。
func event_kind_for_node(id: String) -> String:
	if not nodes.has(id):
		return ""
	var gate: Dictionary = nodes[id].get("gate", {})
	match gate.get("type", ""):
		"combat":
			return "boss" if _is_strongest_combat_in_section(id) else "combat"
		"skill":
			return "skill"
		"item":
			return "item"
		"innate_trait":
			return "bloodline"
	return ""

func _is_strongest_combat_in_section(id: String) -> bool:
	var power: int = nodes[id]["gate"].get("enemy_power", 0)
	for other_id in nodes_in_section(nodes[id]["section"]):
		var other_gate: Dictionary = nodes[other_id].get("gate", {})
		if other_gate.get("type", "") == "combat" and other_gate.get("enemy_power", 0) > power:
			return false
	return true

func neighbors(id: String) -> Array:
	if not nodes.has(id):
		return []
	return nodes[id]["connections"]

func can_pass_gate(id: String, npc_id: int) -> bool:
	if not nodes.has(id):
		return false
	var gate: Dictionary = nodes[id].get("gate", {})
	if gate.is_empty():
		return true
	match gate.get("type", ""):
		"skill":
			return Npcs.skill_level(npc_id, gate["skill"]) >= gate["min_level"]
		"innate_trait":
			var npc := Npcs.get_npc(npc_id)
			return npc.get("innate_traits", {}).get(gate["trait"], null) == gate["value"]
		"item":
			return Items.has_item(npc_id, gate["item"])
		_:
			return true

## パーティ版のゲート判定(design.md 4.7節): skill/innate_trait/itemゲートいずれも、
## パーティ内の誰か1人が満たしていれば通過できる(パーティ内OR判定)。既存のcan_pass_gate()を
## メンバーごとに呼ぶだけで、ゲート種別ごとの判定ロジック自体は変更しない。並び順で最初に
## 満たしたメンバーのidを返す(突破報酬アイテムの受け取り手を決めるのに使う)。誰も満たさなければ-1。
func first_passing_member(id: String, member_ids: Array) -> int:
	for npc_id in member_ids:
		if can_pass_gate(id, npc_id):
			return npc_id
	return -1

func save_progress() -> Dictionary:
	var result := {}
	for id in nodes.keys():
		if nodes[id]["found"]:
			result[id] = {"found": true, "passed": nodes[id]["passed"], "found_by_employed": nodes[id]["found_by_employed"]}
	return result

func load_progress(states: Dictionary) -> void:
	for id in states.keys():
		if nodes.has(id):
			nodes[id]["found"] = bool(states[id]["found"])
			nodes[id]["passed"] = bool(states[id]["passed"])
			# found_by_employedが無い旧セーブ(この列を追加する前のもの)はfalseがデフォルト値として
			# 補完される。village/forest_edgeなどはworld_data.gdの起動時ブートストラップで
			# 既にtrueが立っているため、ここは上書きではなくOR統合にして、旧セーブ読み込みで
			# ブートストラップ済みの値を後から潰してしまわないようにする。
			nodes[id]["found_by_employed"] = nodes[id]["found_by_employed"] or bool(states[id].get("found_by_employed", false))

## ワールドスキーマの再構築前に呼ぶ(world_schema_db.gdのimport_into_worldmap())。
## add_area/add_section/add_nodeは上書きのみで削除はしないため、これを呼ばずに
## 別バージョンを読み込むと、前のバージョンにしかない要素が残ってしまう。
func reset() -> void:
	areas = {}
	sections = {}
	nodes = {}
	section_reward_claimed = {}
	_section_nodes_cache = {}

## セクションが所属するエリアの登場順(0始まり)+1を、収入・報酬計算用の倍率として使う。
## 後発エリアほど高倍率になり(design.md 8.1「後発エリアほど規模と難度を緩やかに引き上げる」方針と
## 整合)、セクションごとに新規データを追加しなくても、エリアを追加するだけで自動的に反映される。
func section_multiplier(section_id: String) -> int:
	if not sections.has(section_id):
		return 1
	var area_idx := areas.keys().find(sections[section_id]["area"])
	return (area_idx if area_idx >= 0 else 0) + 1

func passed_count_in_section(section_id: String) -> int:
	var count := 0
	for id in nodes_in_section(section_id):
		if nodes[id]["passed"]:
			count += 1
	return count

## セクション内の全フロアが突破済みになっている(=完全攻略済み)かどうか。
func is_section_cleared(section_id: String) -> bool:
	var member_ids := nodes_in_section(section_id)
	if member_ids.is_empty():
		return false
	for id in member_ids:
		if not nodes[id]["passed"]:
			return false
	return true

func is_section_reward_claimed(section_id: String) -> bool:
	return section_reward_claimed.get(section_id, false)

func mark_section_reward_claimed(section_id: String) -> void:
	section_reward_claimed[section_id] = true

## 踏破後の自動再配置(探索者のpost_clear_behavior=MOVE_ON)用: 同じエリア内でまだ完全攻略されていない
## セクションを優先し、無ければ次のエリア以降から順に探す。全て埋まっていれば空文字を返す。
## まだ世界のどこからも繋がっていない(is_section_reachable=false)セクションは選ばない: 配置転換しても
## 何も発見できず、パーティがそこで動けなくなるため。繋がった時に、改めて選ばれる(exploration.gdが毎日判定する)。
func next_section_to_explore(current_section_id: String) -> String:
	if not sections.has(current_section_id):
		return ""
	var current_area: String = sections[current_section_id]["area"]
	for section_id in sections_in_area(current_area):
		if section_id != current_section_id and not is_section_cleared(section_id) and is_section_reachable(section_id):
			return section_id
	var area_ids := areas.keys()
	var start_idx := area_ids.find(current_area)
	for i in range(start_idx + 1, area_ids.size()):
		for section_id in sections_in_area(area_ids[i]):
			if not is_section_cleared(section_id) and is_section_reachable(section_id):
				return section_id
	return ""

## 世界の最初のセクション(最初のエリアの最初のセクション)。戦力不足で退避する先が他に無い時の戻り先。
func first_section() -> String:
	for area_id in areas.keys():
		var section_ids := sections_in_area(area_id)
		if not section_ids.is_empty():
			return section_ids[0]
	return ""

## 世界の並び順(エリアの順、その中のセクションの順)で、current_section_idより前にある、最も近い
## 完全攻略済みのセクション。無ければ空文字。
func previous_cleared_section(current_section_id: String) -> String:
	var ordered: Array = []
	for area_id in areas.keys():
		ordered.append_array(sections_in_area(area_id))
	var index := ordered.find(current_section_id)
	for i in range(index - 1, -1, -1):
		if is_section_cleared(ordered[i]):
			return ordered[i]
	return ""

func frontier_for_section(section_id: String) -> Array:
	# そのセクション内で、通過済みノードに隣接するがまだ未発見のノード一覧。
	# 隣接元は他セクションの通過済みノードでもよい(ダンジョンの入口が村側からつながる場合など)。
	var result := []
	for id in nodes_in_section(section_id):
		if nodes[id]["found"]:
			continue
		for neighbor_id in nodes[id]["connections"]:
			if nodes.has(neighbor_id) and nodes[neighbor_id]["passed"]:
				result.append(id)
				break
	return result
