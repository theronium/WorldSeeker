extends Node
# 探索者の組織(プレイヤーの組織と、他の組織)と、毎月のランキング(design.md 4.10節、2026-10-12)。
#
# 他の組織は、野良探索者(wild_npcs.gd)の発見を分担する: 発見のたびに分担率(share)で、どの組織の発見かを決める
# (分担率の残りは無所属=従来どおりの「野良の旅人」)。他の組織もゲートは突破できないので、開拓の点は実際の発見だけ。
# 稼ぎ・戦闘の点は、世界に何も起こさない計算(組織ごとの特色と成長率。_rival_points)で出す。プレイヤーの成績には
# 合わせない: 育てれば追い抜け、放っておけば抜かれる。
#
# 今月の点は、記録する時に日数から何か月目かを見て、前の月の分が残っていれば捨ててから足す(MonthlyStatsと同じ作り。
# 月末の日=30日目の出来事は、その月に数える)。月末(TimeSystem.month_ended)に順位を確定し、historyへ積んで掲示板に出す。
# 月末の収入(Exploration._on_month_ended)も今月の稼ぎに数えるため、このautoloadはExplorationより後に読み込む
# (同じシグナルの接続順=autoloadの順で、収入の後に確定する)。

const PLAYER_ID := "player"
const DEFAULT_PLAYER_NAME := "名もなき探索団"

## 部門と点。開拓: 発見1件・ゲート突破1件。稼ぎ: 収入10資金ごと。戦闘: 勝った戦闘1回
const CATEGORIES := ["explore", "earn", "combat"]
const CATEGORY_NAMES := {"explore": "開拓", "earn": "稼ぎ", "combat": "戦闘"}
const POINTS_DISCOVER := 10
const POINTS_GATE := 20
const FUNDS_PER_EARN_POINT := 10
const POINTS_VICTORY := 15

## 他の組織の計算上の点(稼ぎ・戦闘)の基準。1か月目の、特色の倍率1・強さ1の組織の値。成長は毎月 growth ずつ
## (1 + growth × 経過月数)。初期パーティだけで動かした時、探索が進んでいる月のプレイヤーの点(開拓50〜70・稼ぎ15〜30・
## 戦闘15〜45)を見て決めた(2026-10-12)。1か月目は初期パーティでも上位に入れ、1年目の終わりには他の組織が今の2倍ほどに
## なるので、雇用・育成で規模を広げないと抜かれる。
const RIVAL_BASE := {"earn": 25, "combat": 20}
const RIVAL_RANDOM_RANGE := 0.2 # ±20%

## 特色: 稼ぎ・戦闘の倍率と、分担率を書かなかった時の既定値。
const STYLES := {
	"explore": {"name": "探索派", "earn": 0.8, "combat": 0.8, "share": 0.3},
	"combat": {"name": "武闘派", "earn": 0.9, "combat": 1.5, "share": 0.2},
	"trade": {"name": "商売派", "earn": 1.5, "combat": 0.6, "share": 0.2},
}

## シナリオに定義が無い時の他の組織。
const FALLBACK_RIVALS := [
	{"id": "compass", "name": "銀の羅針盤", "style": "explore", "strength": 1.0, "growth": 0.08},
	{"id": "hammer", "name": "鉄槌団", "style": "combat", "strength": 1.2, "growth": 0.05},
	{"id": "lion", "name": "金獅子商会", "style": "trade", "strength": 0.9, "growth": 0.12},
]

var player_name: String = DEFAULT_PLAYER_NAME
## 他の組織: [{"id", "name", "style", "share", "strength", "growth"}]
var rivals: Array = []
## 今月の記録: org_id -> {"explore": 点, "earn_funds": 収入(資金。点にするのは読む時), "combat": 点}。
## 他の組織は開拓(実際の発見)だけを記録し、稼ぎ・戦闘は月末に計算する
var points: Dictionary = {}
var month_index: int = -1
## 確定した月ごとの順位: [{"month": int(TimeSystem.current_month。1か月目=1), "rows": [{"id", "name", "explore", "earn", "combat", "total", "rank"}]}]
var history: Array = []

signal ranking_finalized(entry: Dictionary)

func _ready() -> void:
	TimeSystem.month_ended.connect(_on_month_ended)

# --- 組織 ---

## 新規プレイ(SaveSystem.start_fresh_session)で、今のシナリオの定義から組織を作り直す。
func setup_from_scenario(new_player_name: String = "") -> void:
	player_name = new_player_name if new_player_name != "" else DEFAULT_PLAYER_NAME
	rivals = parse_rivals(ScenarioEvents.info.get("organizations", ""))
	points.clear()
	month_index = -1
	history.clear()

## scenario.jsonの"organizations"(スナップショットにはJSONの文字列で入る)を読む。読めない・空なら FALLBACK_RIVALS。
## 分担率の合計が1を超えていれば、合計が1になるよう縮める。
static func parse_rivals(source) -> Array:
	var raw = source
	if raw is String:
		raw = JSON.parse_string(raw) if raw != "" else null
	var result: Array = []
	if raw is Array:
		for entry in raw:
			if not (entry is Dictionary) or String(entry.get("id", "")) == "" or String(entry.get("id", "")) == PLAYER_ID:
				continue
			result.append(_normalize_rival(entry))
	if result.is_empty():
		for entry in FALLBACK_RIVALS:
			result.append(_normalize_rival(entry))
	var share_total := 0.0
	for rival in result:
		share_total += rival["share"]
	if share_total > 1.0:
		for rival in result:
			rival["share"] = rival["share"] / share_total
	return result

static func _normalize_rival(entry: Dictionary) -> Dictionary:
	var style := String(entry.get("style", "explore"))
	if not STYLES.has(style):
		style = "explore"
	return {
		"id": String(entry["id"]),
		"name": String(entry.get("name", entry["id"])),
		"style": style,
		"share": clampf(float(entry.get("share", STYLES[style]["share"])), 0.0, 1.0),
		"strength": maxf(0.0, float(entry.get("strength", 1.0))),
		"growth": maxf(0.0, float(entry.get("growth", 0.08))),
	}

func rival(org_id: String) -> Dictionary:
	for entry in rivals:
		if entry["id"] == org_id:
			return entry
	return {}

func org_name(org_id: String) -> String:
	if org_id == PLAYER_ID:
		return player_name
	return String(rival(org_id).get("name", org_id))

## 野良探索者の発見を、分担率で組織に割り当てる。無所属なら""。
func roll_wild_owner() -> String:
	var roll := randf()
	for entry in rivals:
		if roll < entry["share"]:
			return entry["id"]
		roll -= entry["share"]
	return ""

# --- 点 ---

func add(org_id: String, category: String, amount: int) -> void:
	if amount <= 0:
		return
	var month := MonthlyStats.month_of_day(TimeSystem.current_day)
	if month != month_index:
		points.clear()
		month_index = month
	if not points.has(org_id):
		points[org_id] = {"explore": 0, "earn_funds": 0, "combat": 0}
	points[org_id][category] += amount

## プレイヤーの収入(Economy.earn)。点(10資金ごとに1点)にするのは、月の合計で(端数を毎回切り捨てない)
func add_player_income(funds: int) -> void:
	add(PLAYER_ID, "earn_funds", funds)

## 今月の点(開拓・稼ぎ・戦闘)。
func current_points(org_id: String) -> Dictionary:
	if month_index != MonthlyStats.month_of_day(TimeSystem.current_day) or not points.has(org_id):
		return {"explore": 0, "earn": 0, "combat": 0}
	var record: Dictionary = points[org_id]
	return {"explore": int(record["explore"]), "earn": int(record["earn_funds"]) / FUNDS_PER_EARN_POINT, "combat": int(record["combat"])}

## 他の組織の、その月(1か月目=1)の稼ぎ・戦闘の点。
func _rival_points(entry: Dictionary, month: int) -> Dictionary:
	var growth := 1.0 + float(entry["growth"]) * maxi(0, month - 1)
	var result := {}
	for category in ["earn", "combat"]:
		var jitter := randf_range(1.0 - RIVAL_RANDOM_RANGE, 1.0 + RIVAL_RANDOM_RANGE)
		result[category] = roundi(RIVAL_BASE[category] * float(entry["strength"]) * float(STYLES[entry["style"]][category]) * growth * jitter)
	return result

# --- 月末の確定 ---

func _on_month_ended(month: int) -> void:
	var entry := finalize_month(month)
	_post_ranking(entry)
	ranking_finalized.emit(entry)

## その月の順位を確定してhistoryへ積み、確定した1件を返す。順位は総合点の高い順(同点は開拓→稼ぎ→戦闘→プレイヤー優先)。
func finalize_month(month: int) -> Dictionary:
	var rows: Array = []
	var player := current_points(PLAYER_ID)
	rows.append(_row(PLAYER_ID, player_name, player))
	for entry in rivals:
		var found := current_points(entry["id"])
		var computed := _rival_points(entry, month)
		rows.append(_row(entry["id"], entry["name"], {"explore": found["explore"], "earn": computed["earn"], "combat": computed["combat"]}))
	rows.sort_custom(func(a, b):
		for key in ["total", "explore", "earn", "combat"]:
			if a[key] != b[key]:
				return a[key] > b[key]
		return a["id"] == PLAYER_ID)
	for i in range(rows.size()):
		rows[i]["rank"] = i + 1
	var result := {"month": month, "rows": rows}
	history.append(result)
	return result

func _row(org_id: String, name: String, values: Dictionary) -> Dictionary:
	var row := {"id": org_id, "name": name}
	var total := 0
	for category in CATEGORIES:
		row[category] = int(values.get(category, 0))
		total += row[category]
	row["total"] = total
	return row

## 最新の確定済みの順位(無ければ空)。
func latest() -> Dictionary:
	return history[-1] if not history.is_empty() else {}

## その組織の、ひとつ前に確定した月の順位(無ければ-1)。前月からの上下の表示に使う。
func previous_rank(org_id: String) -> int:
	if history.size() < 2:
		return -1
	for row in history[-2]["rows"]:
		if row["id"] == org_id:
			return int(row["rank"])
	return -1

## 部門ごとの1位(点が0なら無し): category -> row
static func category_leaders(entry: Dictionary) -> Dictionary:
	var leaders := {}
	for category in CATEGORIES:
		var best: Dictionary = {}
		for row in entry.get("rows", []):
			if int(row[category]) > 0 and (best.is_empty() or int(row[category]) > int(best[category])):
				best = row
		if not best.is_empty():
			leaders[category] = best
	return leaders

func _post_ranking(entry: Dictionary) -> void:
	var rows: Array = entry["rows"]
	if rows.is_empty():
		return
	var player_rank := -1
	for row in rows:
		if row["id"] == PLAYER_ID:
			player_rank = int(row["rank"])
	var top: Dictionary = rows[0]
	var text: String
	if top["id"] == PLAYER_ID:
		text = "今月の探索者番付が出たよ。1位はなんと「%s」(%d点)だ！ 大したもんだね" % [top["name"], top["total"]]
	else:
		text = "今月の探索者番付が出たよ。1位は「%s」(%d点)、「%s」は%d位だってさ" % [top["name"], top["total"], player_name, player_rank]
	Board.post(TimeSystem.current_day, text, Board.Importance.MAJOR, "ranking", Board.Scope.WORLD)

# --- セーブ ---

func save_state() -> Dictionary:
	return {"player_name": player_name, "rivals": rivals, "points": points, "month_index": month_index, "history": history}

func load_state(data: Dictionary) -> void:
	player_name = String(data.get("player_name", DEFAULT_PLAYER_NAME))
	if player_name == "":
		player_name = DEFAULT_PLAYER_NAME
	rivals = data.get("rivals", [])
	if rivals.is_empty():
		rivals = parse_rivals(ScenarioEvents.info.get("organizations", ""))
	points = data.get("points", {})
	month_index = int(data.get("month_index", -1))
	history = data.get("history", [])
