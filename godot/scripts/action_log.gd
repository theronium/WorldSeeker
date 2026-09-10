extends Node
# 「意味のある出来事」だけを記録する、リプレイ/観戦用の行動ログ(design.md 8.2 記録再生)。
#
# 掲示板(board.gd)と同じ発生源・同じ粒度(発見/ゲート突破/マイルストーン。日次の
# ゲート再挑戦の失敗などルーチンな判定は記録しない)で記録するが、掲示板が表示用の
# 整形済みテキストを持つだけなのに対し、こちらはnpc_id/node_id/section_idを構造化した
# 列で持ち、後から特定NPCや特定ノードで絞り込めるようにする。
#
# 記録はメモリ上にバッファし、SaveSystem.save_game()のタイミングでDBへ追記(INSERT)される。
# 掲示板/NPC名簿など「現在状態」を持つテーブルと違い、こちらは保存のたびに削除されない
# 追記専用ログなので、SaveSystemの一括DELETE対象には含めない。
#
# run_idはプレイ回(セーブファイル)ごとに1つ発行し、meta経由でセーブ/ロードされる。
# 現状は単一セーブ運用だが、将来「スキーマ再プレイ」で複数プレイ回を区別する下地として持つ。

var run_id: String = ""
var _pending: Array = []

func ensure_run_id() -> void:
	if run_id == "":
		run_id = "run_%d_%d" % [Time.get_unix_time_from_system(), randi()]

func record(day: int, event_type: String, text: String, npc_id: int = -1, node_id: String = "", section_id: String = "") -> void:
	ensure_run_id()
	_pending.append({
		"run_id": run_id,
		"day": day,
		"event_type": event_type,
		"npc_id": npc_id,
		"node_id": node_id,
		"section_id": section_id,
		"text": text,
	})

func flush(db: SQLite) -> void:
	for entry in _pending:
		db.query_with_bindings(
			"INSERT INTO action_log (run_id, day, event_type, npc_id, node_id, section_id, text) VALUES (?, ?, ?, ?, ?, ?, ?)",
			[entry["run_id"], entry["day"], entry["event_type"], entry["npc_id"], entry["node_id"], entry["section_id"], entry["text"]])
	_pending.clear()
