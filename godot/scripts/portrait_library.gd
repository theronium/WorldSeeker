class_name PortraitLibrary
# NPCの肖像画像。design.md 4.2節の血筋(NameGenerator.NAMES_BY_BLOODLINE)と同じ抽選パターンで、
# 血筋ごとに雰囲気の合う画像プールから抽選する。画像本体は`res://assets/portraits/`に置き、
# ここでは血筋ごとのid一覧(ファイル名から拡張子を除いたもの)だけを持つ。
#
# 由来: 2026-09-14、ユーザーが`sandbox/charactors/`に生成済みのNPC用画像(char_01〜char_40、
# 40枚)を用意。人型でない3枚(char_21=骸骨/リッチ、char_32=ゴーレム、char_34=狼(動物単体))は
# 通常のNPC肖像として使うには不自然なため、抽選プールからは除外した(画像ファイル自体は
# assets/portraits/に残してあるので、将来ボス/モンスター表示に使う場合はそのまま利用できる)。
# 残り37枚を、絵柄の雰囲気(エルフ耳/王冠・貴族衣装/一般的な冒険者や亜人など)で
# 既存4血筋に振り分けた。オーク・ドワーフ・獣人・悪魔・竜人・人魚といった非人間種の絵柄は
# どの血筋にも明確な一致が無いため平民プールに含めている(design.md上、平民は「特別な血筋を
# 持たない」という消極的な定義のため、多様な種族を受け止める役割として矛盾しない)。

const PORTRAITS_BY_BLOODLINE := {
	"平民": [
		"char_01", "char_02", "char_04", "char_06", "char_07", "char_08", "char_09",
		"char_11", "char_12", "char_14", "char_16", "char_17", "char_18", "char_20",
		"char_22", "char_23", "char_26", "char_28", "char_29", "char_31", "char_33",
		"char_35", "char_37", "char_38", "char_39",
	],
	"旧家の血筋": ["char_05", "char_13", "char_30", "char_36"],
	"森人の血": ["char_03", "char_15", "char_19", "char_24", "char_25"],
	"王家の落胤": ["char_10", "char_27", "char_40"],
}

const PORTRAIT_DIR := "res://assets/portraits/"

static func generate(bloodline: String) -> String:
	var pool: Array = PORTRAITS_BY_BLOODLINE.get(bloodline, PORTRAITS_BY_BLOODLINE["平民"])
	return pool[randi() % pool.size()] if not pool.is_empty() else ""

static func texture_path(portrait_id: String) -> String:
	return "%s%s.png" % [PORTRAIT_DIR, portrait_id]
