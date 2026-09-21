extends Node
# 毎日の動き(2026-09-21): その日、担当中のパーティが何をしていたか(探索中/回復中/力を付けている/周回中)。
# 未割当(待機中)のパーティは出さない。ログウィンドウ(log_window.gd)の「毎日の動き」で見返す。
#
# 掲示板(board.gd)・行動ログ(action_log.gd)と違い、節目の出来事ではなく「静かに続く状態」を持つ。記録はメモリだけで、
# セーブ・掲示板・行動ログには入れない(ゲームを閉じる/ロードすると空から)。直近RETENTION_DAYS日分(最低1か月は
# 見返せる)を保持し、古い日から捨てる。
# 記録のタイミングは、毎日の探索の最後(exploration.gdの_on_day_advanced)と、フロアの会話が閉じて結果が反映された後
# (同じ日を記録し直すと、その日の分を置き換える)。

const RETENTION_DAYS := 90

const KIND_EXPLORE := "explore" # 担当セクションを探索中
const KIND_RECOVER := "recover" # 戦闘の後の回復中
const KIND_TRAIN := "train" # 勝てない敵の前で詰まって、力を付けている(退避中。exploration.gdの_check_blocked)
const KIND_LAP := "lap" # 完全攻略済みのセクションを周回中

var _days: Array = [] # 古い順: [{"day": int, "parties": [エントリ]}]。エントリは_snapshot参照

## その日の、担当中の各パーティの動きを記録する。担当中のパーティが1つも無ければ、その日は記録しない。
## 同じ日を記録し直した場合は、その日の分を置き換える。
func record_day(day: int) -> void:
	var lines: Array = []
	for party in Parties.get_parties():
		var entry := _snapshot(party)
		if not entry.is_empty():
			lines.append(entry)
	if not _days.is_empty() and int(_days.back()["day"]) == day:
		if lines.is_empty():
			_days.pop_back()
		else:
			_days.back()["parties"] = lines
	elif not lines.is_empty():
		_days.append({"day": day, "parties": lines})
	while not _days.is_empty() and int(_days[0]["day"]) <= day - RETENTION_DAYS:
		_days.pop_front()

## パーティ1つの、今の動き。未割当なら空。
func _snapshot(party: Dictionary) -> Dictionary:
	var status := int(party["status"])
	if status == Parties.Status.IDLE:
		return {}
	var entry := {
		"party_id": int(party["id"]), "party_name": String(party["name"]), "section_id": String(party["assigned_section"]),
		"kind": KIND_EXPLORE, "target_id": "", "blocker": "", "until": -1,
	}
	if status == Parties.Status.RECOVERING:
		entry["kind"] = KIND_RECOVER
		entry["until"] = int(party["recovering_until_day"])
	elif Parties.is_retreating(party):
		entry["kind"] = KIND_TRAIN
		entry["target_id"] = String(party["return_section"])
		entry["blocker"] = String(party["return_node"])
	elif WorldMap.sections.has(entry["section_id"]) and WorldMap.is_section_cleared(entry["section_id"]):
		entry["kind"] = KIND_LAP
	return entry

## 記録した日を、新しい順に返す: [{"day": int, "parties": [エントリ]}]。party_idを指定すれば、そのパーティの分だけ。
func days_newest_first(party_id: int = -1) -> Array:
	var result: Array = []
	for i in range(_days.size() - 1, -1, -1):
		var parties: Array = _days[i]["parties"]
		if party_id != -1:
			parties = parties.filter(func(entry): return int(entry["party_id"]) == party_id)
		if not parties.is_empty():
			result.append({"day": int(_days[i]["day"]), "parties": parties})
	return result

## 同じ状態が続いた連続する日を1つにまとめた区間を、新しい順に返す。
## [{"party_id", "party_name", "entry", "from_day", "to_day"}]。同じパーティで、種別・場所・目標が同じで、日が連続する間を1つにする。
func spans_newest_first(party_id: int = -1) -> Array:
	var spans: Array = []
	var open := {} # party_id -> 進行中の区間
	for day_entry in _days:
		var day: int = int(day_entry["day"])
		for entry in day_entry["parties"]:
			var pid: int = int(entry["party_id"])
			if party_id != -1 and pid != party_id:
				continue
			var span: Variant = open.get(pid)
			if span != null and span["key"] == _merge_key(entry) and int(span["to_day"]) == day - 1:
				span["to_day"] = day
				span["entry"] = entry
			else:
				var fresh := {"party_id": pid, "party_name": entry["party_name"], "key": _merge_key(entry), "entry": entry, "from_day": day, "to_day": day}
				spans.append(fresh)
				open[pid] = fresh
	spans.sort_custom(func(a, b):
		if a["to_day"] != b["to_day"]:
			return a["to_day"] > b["to_day"]
		if a["from_day"] != b["from_day"]:
			return a["from_day"] > b["from_day"]
		return a["party_id"] < b["party_id"])
	return spans

func _merge_key(entry: Dictionary) -> String:
	return "%s|%s|%s|%s" % [entry["kind"], entry["section_id"], entry["target_id"], entry["blocker"]]

## 動きを1行の文にする。dayを渡すと、回復中は「あと何日」を添える(まとめ表示では-1: 日数は区間の長さで示す)。
func describe(entry: Dictionary, day: int = -1) -> String:
	var place := _section_name(String(entry["section_id"]))
	match String(entry["kind"]):
		KIND_RECOVER:
			if day >= 0:
				var left: int = int(entry["until"]) - day
				return "回復中(あと%d日)" % left if left > 0 else "回復中(まもなく復帰)"
			return "回復中"
		KIND_TRAIN:
			var target := _section_name(String(entry["target_id"]))
			var blocker := _node_name(String(entry["blocker"]))
			if entry["section_id"] == entry["target_id"]:
				return "「%s」の「%s」に勝つ見込みが無く、その場で力を付けている" % [place, blocker]
			return "「%s」で力を付けている(目標: 「%s」の「%s」)" % [place, target, blocker]
		KIND_LAP:
			return "「%s」を周回中" % place
		_:
			return "「%s」を探索中" % place

## まとめ表示の1行: 区間の日数を添える(例: 「2面 霧の湖」を探索中(9日間))。
func describe_span(span: Dictionary) -> String:
	var days: int = int(span["to_day"]) - int(span["from_day"]) + 1
	return "%s(%d日間)" % [describe(span["entry"]), days]

func _section_name(section_id: String) -> String:
	return String(WorldMap.sections[section_id]["name"]) if WorldMap.sections.has(section_id) else section_id

func _node_name(node_id: String) -> String:
	return String(WorldMap.nodes[node_id]["name"]) if WorldMap.nodes.has(node_id) else node_id

func day_count() -> int:
	return _days.size()

## 新規プレイ開始・ロード(save_system.gd)用のリセット。別のセーブの動きが混ざらないようにする。
func reset() -> void:
	_days = []
