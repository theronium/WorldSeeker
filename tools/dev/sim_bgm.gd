# 使い捨ての確認用スクリプト(2026-09-22)。BGM(main.gdの_build_bgm)の確認: 起動すると自動で再生が始まり、
# ループが有効で、音量が設定(Settings.bgm_volume)どおりであること。設定を変えると即座に反映されること
# (音量スライダー・ミュート)、設定画面のUIがSettingsと一致すること。
# 実行: APPDATA=<隔離した空のディレクトリ> godot --headless --path godot --script <このファイルの絶対パス>
# (--script モードの作法は tools/dev/README.md 参照。実セーブに触れないよう、必ずAPPDATAを差し替える。
#  --headless(ダミー音声ドライバ)だと、終了時に「ERROR: 1 resources still in use at exit」が出ることがあるが、
#  これはヘッドレス特有の後片付けの表示だけで、exit codeは0のまま・実ウィンドウ起動では出ない。無視してよい)
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

func _run() -> void:
	var Settings = root.get_node("Settings")
	_check("bgm_playerが作られている", _main.bgm_player != null)
	_check("ストリームが読み込まれている", _main.bgm_player.stream != null, str(_main.bgm_player.stream))
	if _main.bgm_player.stream is AudioStreamMP3:
		_check("MP3のループが有効", _main.bgm_player.stream.loop)
	_check("起動時に自動で再生が始まっている", _main.bgm_player.playing)
	_check("初期音量はSettings.bgm_volume(既定0.6)から計算した値", is_equal_approx(_main.bgm_player.volume_db, linear_to_db(Settings.bgm_volume)), "%.1fdB" % _main.bgm_player.volume_db)
	_check("音量は0dB(原音のまま)より下げてある(既定値なので)", _main.bgm_player.volume_db < 0.0)

	print("\n=== 設定を変えると即座に反映される ===")
	Settings.set_bgm_volume(1.0)
	_check("音量を最大にすると0dB(原音のまま)", is_equal_approx(_main.bgm_player.volume_db, 0.0), "%.1fdB" % _main.bgm_player.volume_db)
	Settings.set_bgm_volume(0.0)
	_check("音量を0にすると、聞こえないほど下がる(停止はしない)", _main.bgm_player.volume_db <= _main.BGM_SILENT_DB and _main.bgm_player.playing)
	Settings.set_bgm_volume(0.6)
	Settings.set_bgm_muted(true)
	_check("ミュートすると、音量が0でなくても聞こえないほど下がる", _main.bgm_player.volume_db <= _main.BGM_SILENT_DB)
	Settings.set_bgm_muted(false)
	_check("ミュートを解くと、音量が戻る", is_equal_approx(_main.bgm_player.volume_db, linear_to_db(0.6)), "%.1fdB" % _main.bgm_player.volume_db)

	print("\n=== 設定画面 ===")
	Settings.set_bgm_volume(0.35)
	Settings.set_bgm_muted(true)
	Settings.set_show_battle_screen(false)
	_main._on_open_settings_pressed()
	_check("開いた時、スライダー・チェックが今の設定と一致する", is_equal_approx(_main.settings_bgm_slider.value, 0.35) and _main.settings_bgm_mute_check.button_pressed and not _main.settings_battle_screen_check.button_pressed)
	_main.settings_battle_screen_check.toggled.emit(true)
	_check("戦闘画面のチェックを操作するとSettingsに反映される", Settings.show_battle_screen)
	_main.settings_bgm_mute_check.toggled.emit(false)
	_check("ミュートのチェックを操作するとSettingsに反映される", not Settings.bgm_muted)

	print("\n=== settings.cfgへの保存・読み込み ===")
	var before := {"volume": Settings.bgm_volume, "muted": Settings.bgm_muted, "battle": Settings.show_battle_screen}
	Settings.set_bgm_volume(0.8)
	Settings.set_bgm_muted(true)
	Settings.set_show_battle_screen(false)
	Settings.bgm_volume = 0.0 # メモリ上だけ変えて(保存はしない)、load_settings()がファイルから正しく戻すか確かめる
	Settings.load_settings()
	_check("load_settingsで、直前にsave_settingsした値が戻る", is_equal_approx(Settings.bgm_volume, 0.8) and Settings.bgm_muted and not Settings.show_battle_screen, str(Settings.bgm_volume))
	print("  (前回値=%s、確認用に上書きしたので元へは戻さない。実セーブとは無関係な設定ファイル)" % before)
	_completed = true
