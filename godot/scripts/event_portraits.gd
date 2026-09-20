class_name EventPortraits
# イベント会話の左右の枠に出す画像(design.md 7.3節)。会話の行(`side`が"left"/"right")の話者名から、
# 出す画像のidを決める。画像本体は探索者の肖像と同じ`res://assets/portraits/`にある
# (PortraitLibrary.texture_path()で読める): 町人・イベントキャラ=`npc_01`〜`npc_32`(32枚)、
# 敵=`enemy_01`〜`enemy_32`(32枚)。元画像は tools/prepare_portraits.py の`--no-number`で加工した。
#
# 画像のidは2種類:
#   ライブラリのid("npc_05"、"enemy_21"など)  res://assets/portraits/ の画像
#   シナリオ固有の画像("@hero.png")           そのシナリオのimages/フォルダの画像(エディタでアップロードする)
#
# 選び方(優先順): (1)会話の行の"image"(main.gdが先に見る、その行だけの指定) (2)シナリオの登場人物表(cast.json、
# 話者名→画像id。ScenarioEvents.cast_image) (3)表に無い名前は、戦闘系の会話(kind=boss/combat)なら敵の画像から、
# それ以外なら町人の画像から、名前のハッシュで1枚を選ぶ(同じ名前は同じ画像。新しい敵・人物の会話を足しても、
# 表へ足し忘れて画像が出ない、ということは起きない)。
#
# 2026-09-21: 名前ごとの固定の対応表(敵35種・人物5名)を、このファイルの定数から、デフォルトシナリオの登場人物表
# (scenarios/default/cast.json)へ移した。敵は35種の名前に対して画像が32枚なので、絵柄が近い敵(ゴーレム・幽霊・竜など)は
# 離れたエリア同士で画像を使い回している。

const POOL_SIZE := 32
const SCENARIO_IMAGE_PREFIX := "@"

## 話者名と会話の種別から、画像のidを返す。kindは"boss"/"combat"なら戦闘系(敵の画像)、それ以外は町人の画像。
static func portrait_id(speaker_name: String, kind: String) -> String:
	var assigned: String = ScenarioEvents.cast_image(speaker_name)
	if assigned != "":
		return assigned
	var prefix := "enemy" if kind == "boss" or kind == "combat" else "npc"
	return "%s_%02d" % [prefix, speaker_name.hash() % POOL_SIZE + 1]

## 画像のidからテクスチャを読む。空・見つからなければnull(枠は隠れる)。
static func load_texture(image_id: String) -> Texture2D:
	if image_id == "":
		return null
	if image_id.begins_with(SCENARIO_IMAGE_PREFIX):
		return _load_scenario_image(image_id.substr(SCENARIO_IMAGE_PREFIX.length()))
	var path := PortraitLibrary.texture_path(image_id)
	return load(path) if ResourceLoader.exists(path) else null

## シナリオ固有の画像を読む。デフォルトシナリオ(res://)はエクスポートで取り込まれた画像、カスタム(user://)は
## 実行時にPNGを読む。エディタで足した直後でまだ取り込まれていないres://の画像も、開発中は直接読める。
static func _load_scenario_image(file_name: String) -> Texture2D:
	var info: Dictionary = ScenarioEvents.info
	if String(info.get("id", "")) == "" or file_name.contains("/") or file_name.contains(".."):
		return null
	var path := "%s/images/%s" % [ScenarioStore.scenario_dir(String(info["id"]), String(info.get("source", "custom"))), file_name]
	if ResourceLoader.exists(path):
		return load(path)
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null:
			return ImageTexture.create_from_image(image)
	return null
