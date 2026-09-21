class_name Difficulty
extends RefCounted
# パーティごとの難易度モード(Easy/Normal/Hard)。design.md 4.9節。
#
# 難易度は「敵の戦闘力」「スキルゲートの必要Lv」「収入・攻略報酬」を変える。パーティ単位の設定で
# (Parties.parties[id]["difficulty"])、いつでも切り替えられる。autoloadを参照しない定数と計算だけの
# スクリプトなので、どこからでも(--scriptの検証コードからも)そのまま使える。
# 数値はどれも初期チューニング値(要調整)。

enum Mode { EASY, NORMAL, HARD }

const DEFAULT := Mode.NORMAL

## 表示名・頭文字(マップのパーティアイコンのバッジ)。添字はMode。
const NAMES := ["Easy", "Normal", "Hard"]
const INITIALS := ["E", "N", "H"]

## 戦闘ゲートの敵の戦闘力にかける倍率(勝てるかの判定・予測・退避の判定まで、Combat経由で一貫して効く)。
const ENEMY_POWER_MULTIPLIER := [0.8, 1.0, 1.25]
## スキルゲートの必要Lvへの加減(下限は0)。
const SKILL_LEVEL_DELTA := [-1, 0, 1]
## 月次収入・周回収入・攻略報酬にかける倍率。危険を冒すほど稼げるようにして、全パーティがEasyに寄らないようにする。
const REWARD_MULTIPLIER := [0.75, 1.0, 1.5]

static func normalize(mode: int) -> int:
	return mode if mode >= 0 and mode < NAMES.size() else DEFAULT

## パーティのデータ(Dictionary)から難易度を取り出す。キーが無い(旧データ)・範囲外ならNormal。
static func of_party(party: Dictionary) -> int:
	return normalize(int(party.get("difficulty", DEFAULT)))

static func mode_name(mode: int) -> String:
	return NAMES[normalize(mode)]

static func initial(mode: int) -> String:
	return INITIALS[normalize(mode)]

## 敵の戦闘力(基礎値)に難易度をかけた値。0以下の敵(戦闘力が無い)は変えない。それ以外は最低1。
static func enemy_power(base: int, mode: int) -> int:
	if base <= 0:
		return base
	return maxi(1, roundi(base * ENEMY_POWER_MULTIPLIER[normalize(mode)]))

## スキルゲートの必要Lv(基礎値)に難易度を加減した値。最低0。
static func skill_min_level(base: int, mode: int) -> int:
	return maxi(0, base + SKILL_LEVEL_DELTA[normalize(mode)])

## 収入・報酬(基礎値)に難易度をかけた値。
static func reward(base: int, mode: int) -> int:
	return roundi(base * REWARD_MULTIPLIER[normalize(mode)])

## 画面に出す、その難易度の効果の1行説明。例: 「敵の戦闘力×0.8 / スキルゲートの必要Lv-1 / 収入・報酬×0.75」
static func describe(mode: int) -> String:
	var m := normalize(mode)
	var delta: int = SKILL_LEVEL_DELTA[m]
	var level_text := "±0" if delta == 0 else ("%+d" % delta)
	return "敵の戦闘力×%s / スキルゲートの必要Lv%s / 収入・報酬×%s" % [
		_trim_number(ENEMY_POWER_MULTIPLIER[m]), level_text, _trim_number(REWARD_MULTIPLIER[m])]

## 1.0→"1"、0.8→"0.8"、1.25→"1.25"(末尾の0を落とす)。
static func _trim_number(value: float) -> String:
	return ("%.2f" % value).rstrip("0").rstrip(".")
