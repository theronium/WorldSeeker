extends Node
# 常設の内部掲示板ログ。いつでも閲覧可能、集計タイムには要約表示する。
#
# 全体フィード(entries)には節目となる出来事(セクション/エリア初到達・イベント等)のみを載せる。
# フロア単位の細かい発見は、各セクションのスレッド(threads)にのみ記録し、
# 全体フィードが探索ノイズで埋もれないようにする。

enum Importance { MINOR, MAJOR }

var entries: Array = [] # {day, text, importance, source}
var threads: Dictionary = {} # thread_id -> {id, title, entries: Array}

func post(day: int, text: String, importance: int, source: String = "") -> void:
	entries.append({
		"day": day,
		"text": text,
		"importance": importance,
		"source": source,
	})

func post_to_thread(thread_id: String, thread_title: String, day: int, text: String, importance: int, source: String = "") -> void:
	if not threads.has(thread_id):
		threads[thread_id] = {"id": thread_id, "title": thread_title, "entries": []}
	threads[thread_id]["entries"].append({
		"day": day,
		"text": text,
		"importance": importance,
		"source": source,
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
