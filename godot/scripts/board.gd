extends Node
# 常設の内部掲示板ログ。いつでも閲覧可能、集計タイムには要約表示する。
#
# 全体フィード(entries)には節目となる出来事(セクション/エリア初到達・イベント等)のみを載せる。
# フロア単位の細かい発見は、各セクションのスレッド(threads)にのみ記録し、
# 全体フィードが探索ノイズで埋もれないようにする。

enum Importance { MINOR, MAJOR }
## 自パーティ(雇用パーティ)の行動か、世界全体(野良の旅人・月次収入・シナリオイベントなど、
## 特定の雇用パーティに紐付かないもの)かの区別。ログウィンドウの掲示板枠と、左メニュー下の
## プレビュー(main.gdの_refresh_board)が、行の文字色とアイコンを変えるのに使う(2026-09-23、
## 「自パーティのものか世界全体のものか色分けした方が良い」との指摘への対応)。
enum Scope { PARTY, WORLD }
const SCOPE_ICON := {Scope.PARTY: "🧑", Scope.WORLD: "🌍"}
const SCOPE_COLOR := {Scope.PARTY: Color(0.55, 0.88, 0.6), Scope.WORLD: Color(0.55, 0.78, 0.98)}

var entries: Array = [] # {day, text, importance, source, scope}
var threads: Dictionary = {} # thread_id -> {id, title, entries: Array}

func post(day: int, text: String, importance: int, source: String = "", scope: int = Scope.PARTY) -> void:
	entries.append({
		"day": day,
		"text": text,
		"importance": importance,
		"source": source,
		"scope": scope,
	})

func post_to_thread(thread_id: String, thread_title: String, day: int, text: String, importance: int, source: String = "", scope: int = Scope.PARTY) -> void:
	if not threads.has(thread_id):
		threads[thread_id] = {"id": thread_id, "title": thread_title, "entries": []}
	threads[thread_id]["entries"].append({
		"day": day,
		"text": text,
		"importance": importance,
		"source": source,
		"scope": scope,
	})

func recent(count: int) -> Array:
	return entries.slice(max(0, entries.size() - count), entries.size())

func thread_recent(thread_id: String, count: int) -> Array:
	if not threads.has(thread_id):
		return []
	var thread_entries: Array = threads[thread_id]["entries"]
	return thread_entries.slice(max(0, thread_entries.size() - count), thread_entries.size())

func entries_between(start_day: int, end_day: int) -> Array:
	return entries.filter(func(e): return e["day"] >= start_day and e["day"] < end_day)

func immediate_entries_between(start_day: int, end_day: int) -> Array:
	return entries_between(start_day, end_day).filter(func(e): return e["importance"] == Importance.MAJOR)

func save_state() -> Dictionary:
	return {"entries": entries, "threads": threads}

func load_state(data: Dictionary) -> void:
	entries = data.get("entries", [])
	for entry in entries:
		entry["day"] = int(entry["day"])
		entry["importance"] = int(entry["importance"])
		entry["scope"] = int(entry.get("scope", Scope.PARTY)) # scope導入(2026-09-23)前のセーブは自パーティ扱いにする
	threads = data.get("threads", {})
	for thread_id in threads.keys():
		for entry in threads[thread_id]["entries"]:
			entry["day"] = int(entry["day"])
			entry["importance"] = int(entry["importance"])
			entry["scope"] = int(entry.get("scope", Scope.PARTY))

## 新規プレイ開始(複数セーブスロット、save_system.gd)用のリセット。
func reset() -> void:
	entries = []
	threads = {}
