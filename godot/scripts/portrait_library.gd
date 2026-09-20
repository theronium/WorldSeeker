class_name PortraitLibrary
# NPCの肖像画像。design.md 4.2節の血筋(NameGenerator.NAMES_BY_BLOODLINE)と同じ抽選パターンで、
# 血筋ごとに雰囲気の合う画像プールから抽選する。画像本体は`res://assets/portraits/`に置き、
# ここでは血筋ごとのid一覧(ファイル名から拡張子を除いたもの)だけを持つ。
#
# 由来: 2026-09-19、ユーザーが正方形に作り直した生成済み画像48枚(char_01〜char_48)に差し替えた
# (2026-09-14の初版は縦長の40枚だった)。元画像は番号付きの一覧シートの切り出しで、縁の白枠と
# 左上の番号が焼き込まれていたため、tools/prepare_portraits.pyで縁と番号を取り除き、256x256の
# 正方形にしてassets/portraits/へ出力している(画像を差し替える時は、このスクリプトを通すこと)。
# 同じファイル名(char_01〜)で中身が変わったため、以前のセーブで保存済みのportrait_idは、
# 名前や血筋はそのままで別の顔に変わって表示される(壊れはしない、見た目の不一致のみ)。
#
# 人型でない/顔の見えない3枚(char_16=ゴーレム、char_24=骸骨のリッチ、char_32=顔の見えない
# 黒い騎士)は、通常のNPC肖像として使うには不自然なため、抽選プールからは除外した(画像ファイル
# 自体はassets/portraits/に残してあるので、将来ボス/モンスター表示に使う場合はそのまま利用できる)。
# 残り45枚を、絵柄の雰囲気で既存4血筋に振り分けた: 森人の血=エルフ耳の自然系(弓使い・妖精・
# 花冠・薬草・ドライアド)、王家の落胤=王冠・ティアラ・紋章の盾、旧家の血筋=聖職者や魔導士の
# 家柄らしい絵柄(司教・老魔導士・本や羽根ペンを持つ学者・貴族的な魔女帽)。オーク・ドワーフ・
# 獣人・悪魔・竜人・人魚・精霊といった非人間種や、その他の一般的な冒険者の絵柄はどの血筋にも
# 明確な一致が無いため平民プールに含めている(design.md上、平民は「特別な血筋を持たない」という
# 消極的な定義のため、多様な種族を受け止める役割として矛盾しない)。
#
# 2026-09-20: char_49〜char_64の16枚を追加した(同じ番号付きシートの続きで、同じ加工を通した。
# 既存のファイルは変えていないので、保存済みのportrait_idの見た目は変わらない)。全16枚が
# 抽選対象で、同じ基準で振り分けた: 旧家の血筋=聖職者風の青いフード(49)と本を持つ星の魔女帽(62)、
# 森人の血=弓と矢筒(50)・花冠のドライアド(53)・羽根つき帽のリュート弾き(54)・花冠の
# 翼のある聖女(59)、王家の落胤=王冠をのせた悪魔(60)と金の冠飾りの竜人風(64)、平民=
# 海賊(51)・獣人(52,56,58)・トカゲ人(55)・歯車帽の技師(57)・炎の精霊(61)・道化師(63)。

const PORTRAITS_BY_BLOODLINE := {
	"平民": [
		"char_01", "char_02", "char_04", "char_06", "char_07", "char_08", "char_09",
		"char_12", "char_13", "char_14", "char_15", "char_18", "char_19", "char_20",
		"char_22", "char_23", "char_25", "char_27", "char_28", "char_29", "char_30",
		"char_31", "char_38", "char_41", "char_42", "char_43", "char_44", "char_45",
		"char_46", "char_48", "char_51", "char_52", "char_55", "char_56", "char_57",
		"char_58", "char_61", "char_63",
	],
	"旧家の血筋": ["char_05", "char_17", "char_36", "char_37", "char_40", "char_49", "char_62"],
	"森人の血": ["char_03", "char_10", "char_11", "char_21", "char_39", "char_47", "char_50", "char_53", "char_54", "char_59"],
	"王家の落胤": ["char_26", "char_33", "char_34", "char_35", "char_60", "char_64"],
}

const PORTRAIT_DIR := "res://assets/portraits/"

static func generate(bloodline: String) -> String:
	var pool: Array = PORTRAITS_BY_BLOODLINE.get(bloodline, PORTRAITS_BY_BLOODLINE["平民"])
	return pool[randi() % pool.size()] if not pool.is_empty() else ""

static func texture_path(portrait_id: String) -> String:
	return "%s%s.png" % [PORTRAIT_DIR, portrait_id]
