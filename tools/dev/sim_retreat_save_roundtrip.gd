# 使い捨ての確認用スクリプト(2026-09-20)。退避状態を実際のSQLiteのセーブ(create_new_slot→save_game→load_game)で往復させる確認。必ずAPPDATAを隔離して実行する(セーブ用のスロットを作る)。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree
var _ran := false
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true

func _run() -> void:
	var Parties = root.get_node("Parties"); var Save = root.get_node("SaveSystem"); var WorldMap = root.get_node("WorldMap")
	var slot: int = Save.create_new_slot("退避テスト")
	var party = Parties.get_parties()[0]
	Parties.assign_section(party["id"], "old_cave_dungeon")
	Parties.retreat_for_training(party["id"], WorldMap.first_section(), "old_cave_dungeon", "boss_lair")
	Save.save_game()
	print("保存: slot=", slot, " 戻り先=", party["return_section"], " node=", party["return_node"])
	Parties.reset()
	print("リセット後のパーティ数=", Parties.get_parties().size())
	var ok: bool = Save.load_game()
	var restored = Parties.get_parties()[0]
	print("load_game=", ok, " 担当=", restored["assigned_section"], " return_section=", restored["return_section"], " return_node=", restored["return_node"], " retreating=", Parties.is_retreating(restored))
	Save.delete_slot(slot)
