extends Node
# セッション型の時間進行。1ヶ月(30日)=25分(等速)をポモドーロ的な基準とし、
# 倍速設定でゲームらしいテンポにも調整できる。月末は集計のため自動停止する。

signal day_advanced(day: int)
signal month_ended(month: int)
signal speed_changed(multiplier: float)

const MONTH_REAL_SECONDS := 25.0 * 60.0 # ポモドーロ1本分
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const SECONDS_PER_DAY := MONTH_REAL_SECONDS / DAYS_PER_MONTH

const SPEED_STEPS := [1.0, 10.0, 100.0, 1000.0]

var current_day: int = 0
var current_month: int = 0
var is_paused: bool = false # 月末になると自動でtrueになり、確認操作を待つ
var speed_multiplier: float = 1.0
var _accumulated: float = 0.0

## 暦の起点(何年何月から始まったプレイか)。デフォルトは0年1月。
## 将来シナリオ選択機能ができた際は、reset()の後にこれを上書きして使う想定。
var start_year: int = 0
var start_month: int = 1 # 1〜12

func _process(delta: float) -> void:
	if is_paused:
		return
	_accumulated += delta * speed_multiplier
	# is_pausedもループ条件に含める: 1フレームのdeltaが大きい場合(重い_ready()直後の初回フレームなど)、
	# ここでis_pausedをチェックしないと、_advance_day()が月末でis_paused=trueを立てても
	# ループが止まらずそのまま次の月・その次の月まで一気に消化してしまい、月末の
	# 自動一時停止(月末集計待ち)を素通りしてしまう。
	while _accumulated >= SECONDS_PER_DAY and not is_paused:
		_accumulated -= SECONDS_PER_DAY
		_advance_day()

func _advance_day() -> void:
	current_day += 1
	# day_advanced経由の日次オートセーブ(main.gdの_on_day_advanced)がis_pausedを正しく
	# 保存できるよう、is_pausedはday_advanced.emit()より前に確定させておく(逆順だと、
	# 月末の日だけ「一時停止する直前」の状態が保存されてしまい、次回起動時にis_paused=falseから
	# 再開して月末停止がすり抜けてしまう不具合になる)。
	var month_ending := current_day % DAYS_PER_MONTH == 0
	if month_ending:
		current_month += 1
		is_paused = true
	day_advanced.emit(current_day)
	if month_ending:
		month_ended.emit(current_month)

func confirm_and_resume() -> void:
	is_paused = false

func set_speed(multiplier: float) -> void:
	if not SPEED_STEPS.has(multiplier):
		return
	speed_multiplier = multiplier
	speed_changed.emit(speed_multiplier)

func seconds_until_month_end() -> float:
	var day_in_month := current_day % DAYS_PER_MONTH
	var days_remaining := DAYS_PER_MONTH - day_in_month
	var real_seconds_remaining := (days_remaining * SECONDS_PER_DAY - _accumulated) / speed_multiplier
	return max(0.0, real_seconds_remaining)

## start_year/start_month(暦の起点)に経過月数を足した、表示用の暦。
func current_year() -> int:
	return start_year + ((start_month - 1) + current_month) / MONTHS_PER_YEAR

func current_month_of_year() -> int:
	return ((start_month - 1) + current_month) % MONTHS_PER_YEAR + 1

func current_day_of_month() -> int:
	return current_day % DAYS_PER_MONTH + 1

func format_date() -> String:
	return "%d年%d月%d日" % [current_year(), current_month_of_year(), current_day_of_month()]

## 新規プレイ開始(複数セーブスロット、save_system.gd)用のリセット。
func reset() -> void:
	current_day = 0
	current_month = 0
	is_paused = false
	speed_multiplier = 1.0
	_accumulated = 0.0
	start_year = 0
	start_month = 1
