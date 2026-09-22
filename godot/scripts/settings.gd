extends Node
# 端末ごとのゲーム設定(セーブスロットに依らない。design.md 10章)。
#
# どのスロットで遊んでいても共通の設定として、`user://settings.cfg`に読み書きする(ConfigFile)。
# セーブスロットの内容(資金・探索者・進行)とは別物なので、SaveSystemの各スロットのSQLiteには入れない。
# 起動時に一度だけ読み込み、値を変えるたびに書き直す(setter経由。値が少ないので都度保存で十分)。

signal changed # 何か変わった(main.gdが画面を更新する)

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "settings"

const BGM_VOLUME_DEFAULT := 0.6 # 0.0(無音)〜1.0(原音)。main.gdがdBに変換する
const SHOW_BATTLE_SCREEN_DEFAULT := true

var bgm_volume: float = BGM_VOLUME_DEFAULT
var bgm_muted: bool = false
var show_battle_screen: bool = SHOW_BATTLE_SCREEN_DEFAULT

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return # 初回起動などファイルが無ければ、既定値のまま
	bgm_volume = clampf(float(config.get_value(SECTION, "bgm_volume", BGM_VOLUME_DEFAULT)), 0.0, 1.0)
	bgm_muted = bool(config.get_value(SECTION, "bgm_muted", false))
	show_battle_screen = bool(config.get_value(SECTION, "show_battle_screen", SHOW_BATTLE_SCREEN_DEFAULT))

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "bgm_volume", bgm_volume)
	config.set_value(SECTION, "bgm_muted", bgm_muted)
	config.set_value(SECTION, "show_battle_screen", show_battle_screen)
	config.save(SETTINGS_PATH)

func set_bgm_volume(value: float) -> void:
	bgm_volume = clampf(value, 0.0, 1.0)
	save_settings()
	changed.emit()

func set_bgm_muted(muted: bool) -> void:
	bgm_muted = muted
	save_settings()
	changed.emit()

func set_show_battle_screen(enabled: bool) -> void:
	show_battle_screen = enabled
	save_settings()
	changed.emit()
