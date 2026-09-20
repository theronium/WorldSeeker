extends Node
# 雇用していない野良探索者の群れ。雇用探索者と同じ実際のマップを探索するが、
# 個々の探索者データ(スキル等)は持たない集計的な存在として扱う。
# ゲートのないノードまでしか自力で突破できない(ゲート付きノードは「発見済みだが進めない」
# 状態で見つけるだけに留まり、実際の突破は雇用探索者に委ねる)。
#
# 発見はExploration.wild_discover()を通じて雇用探索者と全く同じ状態(found/passed)・
# 掲示板(セクション別スレッド + 節目の全体投稿)に反映される。

const DISCOVERY_CHANCE_PER_SECTION := 0.05 # セクション1つあたり、1日に発見が起こる確率

func _ready() -> void:
	TimeSystem.day_advanced.connect(_on_day_advanced)

func _on_day_advanced(current_day: int) -> void:
	for section_id in WorldMap.sections.keys():
		var frontier := WorldMap.frontier_for_section(section_id)
		for node_id in frontier:
			if randf() < DISCOVERY_CHANCE_PER_SECTION:
				Exploration.wild_discover(node_id, current_day)
