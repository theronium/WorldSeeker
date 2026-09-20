# 使い捨ての確認用スクリプト(2026-09-20)。ワールドデータの集計例: イベント会話のあるフロアを、ゲート種別ごとに数える(イベント種別の設計の根拠にした)。
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
	var WorldMap = root.get_node("WorldMap")
	var Scenario = root.get_node("ScenarioEvents") # 2026-09-21: フロアの会話は、WorldMapのノードではなくシナリオのイベントに移った
	var total := 0
	var with_event := 0
	var by_gate := {}
	var event_by_gate := {}
	var rows := []
	for id in WorldMap.nodes.keys():
		var n: Dictionary = WorldMap.nodes[id]
		total += 1
		var g: Dictionary = n["gate"]
		var gt: String = g.get("type", "(なし)")
		var key := gt
		if gt == "combat":
			var p: int = g.get("enemy_power", 0)
			key = "combat"
		by_gate[key] = by_gate.get(key, 0) + 1
		if Scenario.has_gate_event(id):
			with_event += 1
			event_by_gate[key] = event_by_gate.get(key, 0) + 1
			var pass_script: Array = Scenario.gate_event(id, true).get("script", [])
			var fail_script: Array = Scenario.gate_event(id, false).get("script", [])
			var maxlen := 0
			var speakers := {}
			for line in pass_script + fail_script:
				maxlen = max(maxlen, String(line.get("text", "")).length())
				speakers[line.get("name", "")] = true
			rows.append("%s | %s | gate=%s%s | pass=%d fail=%d行 最長%d字 話者=%s" % [
				id, n["name"], gt, (" 敵戦力%d" % g.get("enemy_power", 0)) if gt == "combat" else "",
				pass_script.size(), fail_script.size(), maxlen, ",".join(speakers.keys())])
	print("全ノード=", total, " イベント有=", with_event)
	print("ゲート種別(全体)=", by_gate)
	print("ゲート種別(イベント有のみ)=", event_by_gate)
	for r in rows:
		print(r)
