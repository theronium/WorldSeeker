# 使い捨ての確認用スクリプト(2026-09-21)。タイムバー(左メニューの「今日」「今月」。time_bar.gd、main.gdの_refresh_time_bars)の確認。
#   T: TimeSystem.day_progress / month_progress(進みの計算、実時間での進み、月末の待ち)
#   B: TimeBar(割合のクランプ、縞の時だけ_processが動く)
#   U: 画面(通常・倍速ごと・月末の集計待ち・会話中の表示)
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える)
extends SceneTree

var _frames := 0
var _main: Node
var _completed := false
var _fails := 0

func _check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		_fails += 1
	print("%s %s%s" % ["OK  " if condition else "NG  ", label, "" if detail == "" else "  (" + detail + ")"])

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	if _frames == 5:
		_run()
		if not _completed:
			print("=== 途中でスクリプトエラーが出て、最後まで走りませんでした ===")
		else:
			print("=== 失敗 %d件 ===" % _fails if _fails > 0 else "=== 全て成功 ===")
		return true
	return false

func _finish(dialogue) -> void:
	var guard := 0
	while dialogue.is_active and guard < 50:
		guard += 1
		dialogue.advance()

func _run() -> void:
	var time_system = root.get_node("TimeSystem"); var save = root.get_node("SaveSystem"); var dialogue = root.get_node("EventDialogue")
	_finish(dialogue)
	save.start_fresh_session()
	var spd: float = time_system.SECONDS_PER_DAY

	# ---------- T: TimeSystem ----------
	print("--- T: TimeSystem ---")
	time_system.reset()
	_check("T: 1日=50秒(1か月25分÷30日)", is_equal_approx(spd, 50.0), str(spd))
	_check("T: 日の始まりは0", is_equal_approx(time_system.day_progress(), 0.0) and is_equal_approx(time_system.month_progress(), 0.0))
	time_system._accumulated = spd * 0.4
	_check("T: 今日の進み(0.4)", is_equal_approx(time_system.day_progress(), 0.4), str(time_system.day_progress()))
	time_system._accumulated = spd * 3.0
	_check("T: 遅れて溜まった分(1日超)は、1にとどめる", is_equal_approx(time_system.day_progress(), 1.0))
	time_system._accumulated = spd * 0.5
	time_system.current_day = 20
	_check("T: 今月の進み: (20日目終了+今日半分)/30", is_equal_approx(time_system.month_progress(), 20.5 / 30.0), str(time_system.month_progress()))
	time_system.current_day = 59
	_check("T: 月の29日目(現在59日)の終わり際は、ほぼ1", time_system.month_progress() > 0.97 and time_system.month_progress() < 1.0, str(time_system.month_progress()))
	time_system.current_day = 60
	time_system.is_paused = true
	_check("T: 月末の待ち(is_paused)の間は、今月は1", is_equal_approx(time_system.month_progress(), 1.0))
	time_system.is_paused = false
	_check("T: 待ちが解けて新しい月が始まると、今月は0近く", time_system.month_progress() < 0.05, str(time_system.month_progress()))
	# 実時間での進み: 5秒経ったことにして1倍速で処理する → 5/50=0.1
	time_system.reset()
	time_system._last_check_ms = Time.get_ticks_msec() - 5000
	time_system._process(0.0)
	_check("T: 1倍速で実時間5秒 → 今日の進み約0.1", time_system.day_progress() > 0.099 and time_system.day_progress() < 0.11, str(time_system.day_progress()))
	time_system.set_speed(10.0)
	time_system._last_check_ms = Time.get_ticks_msec() - 2000
	time_system._process(0.0)
	_check("T: 10倍速で実時間2秒 → さらに約0.4(20秒分)進む", time_system.day_progress() > 0.49 and time_system.day_progress() < 0.51, str(time_system.day_progress()))
	# 日をまたぐと、割合は戻る
	time_system.reset()
	time_system._accumulated = spd - 0.001
	time_system._last_check_ms = Time.get_ticks_msec() - 100
	time_system._process(0.0)
	_check("T: 日が進むと、今日の割合は0近くへ戻る", time_system.current_day == 1 and time_system.day_progress() < 0.01, "day=%d p=%s" % [time_system.current_day, str(time_system.day_progress())])

	# ---------- B: TimeBar ----------
	print("--- B: TimeBar ---")
	var bar: Control = load("res://scripts/time_bar.gd").new()
	bar.fraction = 1.7
	_check("B: 割合は1にとどまる", is_equal_approx(bar.fraction, 1.0))
	bar.fraction = -0.3
	_check("B: 割合は0にとどまる", is_equal_approx(bar.fraction, 0.0))
	_check("B: 縞でない間は、毎フレームの処理をしない", not bar.is_processing())
	bar.striped = true
	_check("B: 縞の間だけ、毎フレーム動く", bar.is_processing())
	bar.striped = false
	_check("B: 縞をやめると止まる", not bar.is_processing())
	_check("B: クリックを邪魔しない(mouse_filter=IGNORE)、はみ出しを切る(clip_contents)", bar.mouse_filter == Control.MOUSE_FILTER_IGNORE and bar.clip_contents)
	bar.free()

	# ---------- U: 画面 ----------
	print("--- U: 画面 ---")
	time_system.reset()
	time_system.current_day = 19 # 月の20日目
	time_system._accumulated = spd * 0.25
	_main._refresh_time_bars()
	_check("U: 今日のバー: 進みの割合(0.25)、縞でない", is_equal_approx(_main.day_bar.fraction, 0.25) and not _main.day_bar.striped)
	_check("U: 今月のバー: (19+0.25)/30", is_equal_approx(_main.month_bar.fraction, 19.25 / 30.0), str(_main.month_bar.fraction))
	_check("U: 見出し: 「今日」「今月 20/30」", _main.day_caption.text == "今日" and _main.month_caption.text == "今月 20/30", "%s / %s" % [_main.day_caption.text, _main.month_caption.text])
	_check("U: 色: 今日=青、今月=琥珀", _main.day_bar.fill_color == _main.TIME_BAR_DAY_COLOR and _main.month_bar.fill_color == _main.TIME_BAR_MONTH_COLOR)
	for speed in [1.0, 10.0]:
		time_system.set_speed(speed)
		_main._refresh_time_bars()
		_check("U: %dx: 今日のバーは縞にしない(進みを読める)" % int(speed), not _main.day_bar.striped)
	for speed in [100.0, 1000.0]:
		time_system.set_speed(speed)
		_main._refresh_time_bars()
		_check("U: %dx: 今日のバーは流れる縞(進みは今月のバーで読む)" % int(speed), _main.day_bar.striped and is_equal_approx(_main.month_bar.fraction, (19.0 + time_system.day_progress()) / 30.0))
	time_system.set_speed(1.0)
	# 月末の集計待ち
	time_system.current_day = 30
	time_system.is_paused = true
	time_system.set_speed(1000.0)
	_main._refresh_time_bars()
	_check("U: 月末の集計待ち: 両方満タンの橙、縞は止める(高速でも)", is_equal_approx(_main.day_bar.fraction, 1.0) and is_equal_approx(_main.month_bar.fraction, 1.0) and _main.day_bar.fill_color == _main.TIME_BAR_PAUSED_COLOR and _main.month_bar.fill_color == _main.TIME_BAR_PAUSED_COLOR and not _main.day_bar.striped)
	_check("U: 月末の集計待ち: 見出しは「今月 30/30」", _main.month_caption.text == "今月 30/30", _main.month_caption.text)
	time_system.is_paused = false
	time_system.set_speed(1.0)
	# 会話中
	time_system.reset()
	time_system._accumulated = spd * 0.6
	time_system.dialogue_hold = true
	_main._refresh_time_bars()
	_check("U: 会話中: 灰色で止まり、見出しは「会話中」", _main.day_bar.fill_color == _main.TIME_BAR_HELD_COLOR and _main.month_bar.fill_color == _main.TIME_BAR_HELD_COLOR and _main.day_caption.text == "会話中" and is_equal_approx(_main.day_bar.fraction, 0.6), "%s" % _main.day_caption.text)
	time_system.set_speed(100.0)
	_main._refresh_time_bars()
	_check("U: 会話中は、高速でも縞にしない(止まっているので)", not _main.day_bar.striped)
	time_system.dialogue_hold = false
	time_system.set_speed(1.0)
	_main._refresh_time_bars()
	_check("U: 会話が終わると、青に戻り、見出しも「今日」", _main.day_bar.fill_color == _main.TIME_BAR_DAY_COLOR and _main.day_caption.text == "今日")
	_completed = true
