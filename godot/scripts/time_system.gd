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
var is_paused: bool = false # 月末になると自動でtrueになり、確認操作を待つ。セーブされるのは、この「月末の待ち」だけ
## イベント会話が開いている間、時間を止める印(event_dialogue.gd)。月末の待ち(is_paused)とは別にして、セーブしない。
## 以前は会話も同じis_pausedを立てていたため、会話が開いている間に保存(その日のオートセーブ、手動セーブ、アプリを閉じる時)
## されると、月の途中なのに「一時停止」が保存され、ロードすると『次の月へ』が出て時間が止まったままになった(2026-09-21)。
var dialogue_hold: bool = false
var speed_multiplier: float = 1.0
var _accumulated: float = 0.0
var _last_check_ms: int = 0

## 暦の起点(何年何月から始まったプレイか)。デフォルトは0年1月。
## シナリオ(scenario.jsonのstart_year/start_month)が決める。SaveSystem.start_fresh_session()が、reset()の後に上書きする。
var start_year: int = 0
var start_month: int = 1 # 1〜12

func _ready() -> void:
	_last_check_ms = Time.get_ticks_msec()

## main.gdの_ready()の最後(UI構築・セーブロードなど起動時の重い処理が全て終わった直後)に
## 呼ぶ。これを呼ばずTimeSystem自身の_ready()時点を基準にすると、そこから起動完了までに
## かかった実時間がまるごと経過時間として計算されてしまう(この後まさにその不具合が起きた:
## _first_process_frameで初回_processフレームのdeltaだけを捨てる対策では、実際には
## `--headless --quit`が1フレームより多く処理してから終了するケースを防げず、起動チェックを
## 繰り返すだけで日付がドリフトし続けた)。基準リセットのタイミングを実際の重い処理の直後に
## 明示的に固定することで、その種の不確実性を排除する。
func mark_boot_complete() -> void:
	_last_check_ms = Time.get_ticks_msec()

## フレームのdelta(Godot内部の計測値)を信用せず、実時間タイムスタンプの差分から経過時間を
## 計算する。1回のチェックで進められる日数は最大1日までとし、それを超える分(遅延)は
## _accumulatedに残したまま次回以降のチェックで徐々に追い上げる(セッション型なので、本当に
## 長時間バックグラウンドで走っていた場合は数フレームのうちに自然に追いつく。一方、重い処理や
## テスト起動による見せかけの大きなdeltaが原因で日付が瞬時に何日も飛ぶことはもう起きない)。
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var elapsed_sec := (now - _last_check_ms) / 1000.0
	_last_check_ms = now
	if is_time_stopped():
		return
	_accumulated += elapsed_sec * speed_multiplier
	if _accumulated >= SECONDS_PER_DAY:
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

## 今、時間が止まっているか(月末の待ち、またはイベント会話の表示中)。
func is_time_stopped() -> bool:
	return is_paused or dialogue_hold

func confirm_and_resume() -> void:
	is_paused = false

func set_speed(multiplier: float) -> void:
	if not SPEED_STEPS.has(multiplier):
		return
	speed_multiplier = multiplier
	speed_changed.emit(speed_multiplier)

## 今日の進み(0〜1): 1日(SECONDS_PER_DAY)のうち、どこまで進んだか。倍速に依らない、ゲーム内の時間の割合
## (倍速が上がると、同じ割合を、実時間では速く進む)。タイムバー(time_bar.gd)用。
func day_progress() -> float:
	return clampf(_accumulated / SECONDS_PER_DAY, 0.0, 1.0)

## 今月の進み(0〜1): 30日のうち、何日目まで進んだか+今日の進み。月末の待ち(is_paused)の間は1。
func month_progress() -> float:
	if is_paused:
		return 1.0
	return (float(current_day % DAYS_PER_MONTH) + day_progress()) / DAYS_PER_MONTH

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
	_last_check_ms = Time.get_ticks_msec()
	start_year = 0
	start_month = 1
