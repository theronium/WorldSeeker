extends Node
# イベント会話の進行管理。ボス戦・障害突破・発見イベントなど、
# 「特定条件を満たすと会話ウィンドウが開く」場面全般で共用する。
#
# スクリプト形式(Array[Dictionary]):
#   {
#     "side": "left" | "right" | "none",   # left/rightは、その枠に話者の画像(EventPortraits)を出して明るくする。
#                                          # 戦闘の敵はright、人物(衛兵・案内人など)はleft。noneは物の語りやナレーションで画像なし
#     "name": "表示名",                    # 画像は、この名前(と会話の種別)から決まる(EventPortraits.portrait_id)
#     "text": "セリフ",
#     "next": int,                 # 省略時は現在の行+1。分岐なしの通常行はこれで進む
#     "outcome": String,           # このキーがあれば、この行の表示後に即終了してoutcomeを通知
#     "choices": [                 # あれば選択肢を表示し、next/outcomeの代わりに使う
#       {"label": String, "next": int, "outcome": String},
#       ...
#     ],
#   }

signal line_shown(line: Dictionary)
signal finished(outcome: String)

var is_active: bool = false

# 会話全体の表示スタイルの種別と結果(main.gdのEVENT_STYLESが色と名前を決める)。
#   kind: "boss"(ボス戦) | "combat"(戦闘) | "skill"(技能) | "item"(アイテム) | "bloodline"(血筋) |
#         "guide"(案内・チュートリアル) | ""(指定なし=従来の見た目)
#   result: "pass"(突破) | "fail"(失敗) | ""(結果を出さない)
# 行に"kind"キーがあれば、その行だけ種別を上書きできる。フロアのイベントの種別は、ゲートの種類から
# WorldMap.event_kind_for_nodeが決めるので、イベントの会話データ自体には書かなくてよい。
var current_kind: String = ""
var current_result: String = ""

var _script: Array = []
var _index: int = 0
var _time_was_paused: bool = false

func play(script: Array, kind: String = "", result: String = "") -> void:
	if script.is_empty():
		return
	_script = script
	_index = 0
	current_kind = kind
	current_result = result
	_time_was_paused = TimeSystem.is_paused
	TimeSystem.is_paused = true
	is_active = true
	_show_current()

func choose(choice_index: int) -> void:
	if not is_active:
		return
	var line: Dictionary = _script[_index]
	var choices: Array = line.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	_advance_from(choices[choice_index])

func advance() -> void:
	if not is_active:
		return
	var line: Dictionary = _script[_index]
	if not line.get("choices", []).is_empty():
		return # 選択肢がある行はchoose()経由でのみ進む
	_advance_from(line)

func _advance_from(step: Dictionary) -> void:
	if step.has("outcome"):
		_finish(step["outcome"])
		return
	var next_index: int = step.get("next", _index + 1)
	if next_index < 0 or next_index >= _script.size():
		_finish("")
		return
	_index = next_index
	_show_current()

func _show_current() -> void:
	line_shown.emit(_script[_index])

func _finish(outcome: String) -> void:
	is_active = false
	TimeSystem.is_paused = _time_was_paused
	finished.emit(outcome)
