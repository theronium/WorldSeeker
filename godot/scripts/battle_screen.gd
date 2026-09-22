extends Node
# イベント戦闘(ゲート結果の会話が付いた戦闘ゲート)の、実際の攻防を見せる戦闘画面の状態管理。design.md 5.4節。
#
# EventDialogueと同じ役割分担: このautoloadはデータと開閉の合図だけを持ち、実際の描画はmain.gdが
# opened/closedシグナルを聞いて行う(main.gdへの参照は持たない)。exploration.gdは、会話が閉じて
# 実際の戦闘(Combat.resolve_party_encounter)を解決した直後、trace(ラウンドごとの記録)が
# あればshow()を呼び、closedを待ってから突破の確定処理(_finalize_discovery)を続ける。
#
# show()を呼んでいる間、exploration.gdが日次の進行を止めている(TimeSystem.dialogue_holdを立てたまま)
# ので、画面を閉じるまで次の日は進まない。

signal opened(data: Dictionary)
signal closed

var is_active: bool = false

## dataの中身: {"trace": Array(Combat.resolve_party_encounterの"trace"), "result": String,
## "enemy_name": String, "enemy_image": String(EventPortraits.portrait_id()の結果), "kind": String("boss"/"combat")}
func show(data: Dictionary) -> void:
	is_active = true
	opened.emit(data)

## main.gdが、プレイヤーの操作(閉じる/スキップ後の閉じるボタン)で呼ぶ。
func close() -> void:
	is_active = false
	closed.emit()
