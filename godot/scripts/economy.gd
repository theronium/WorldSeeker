extends Node
# 単一の資金プールと、雇用/訓練/施設拡張のコスト計算。

var funds: int = 300
# 無償の初期パーティ(design.md 4.7節)が既に4人いるため、上限は最低でもそれを上回っている
# 必要がある。旧デフォルト(3)は、この4人パーティが導入される前の値が更新されないまま
# 残っていたもので、新規プレイ開始直後から「雇用上限に達しています」と表示され、施設拡張
# (初期資金300を丸ごと使い切る額)をしない限り1人も追加雇用できないという実質詰みの
# 状態になっていた(初雇用時のパーティ編成チュートリアルを検証中に発覚・修正)。
#
# 2026-09-21: 雇用上限を4人(パーティ1つ分。Parties.MAX_PARTY_SIZE)単位にそろえた。以前は初期5・拡張のたびに+2で、
# パーティの人数(4)と噛み合わず、端数の探索者が出ていた。今は、初期=無償の初期パーティ(4人)+雇用枠(4人)、拡張1回=パーティ1つ分。
const EMPLOY_CAP_INITIAL := 8
const EMPLOY_CAP_STEP := 4
var employ_cap: int = EMPLOY_CAP_INITIAL
var facility_level: int = 0

func can_afford(amount: int) -> bool:
	return funds >= amount

func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	funds -= amount
	return true

func earn(amount: int) -> void:
	funds += amount

func recruitment_post_cost() -> int:
	return 50

func hire_cost(candidate_quality: float) -> int:
	# quality は 0.0(平均)〜1.0(高能力・レア特性)想定。
	# 初回雇用の負担を抑えるため基準額は低めに設定(募集コスト50+雇用50で初回合計100)
	return int(50 + candidate_quality * 400)

func training_cost(current_skill_level: int) -> int:
	# レベルが上がるほど次の訓練が高額になる逓増カーブ
	return int(20 * pow(1.4, current_skill_level))

func facility_upgrade_cost() -> int:
	return int(300 * pow(1.6, facility_level))

func upgrade_facility() -> bool:
	var cost := facility_upgrade_cost()
	if not spend(cost):
		return false
	facility_level += 1
	employ_cap += EMPLOY_CAP_STEP
	return true

## 雇用上限を、4の倍数へ切り上げる。旧セーブ(初期5・+2ずつ: 5,7,9…)を読む時に使う。上限が下がることは無い(5→8、7→8、9→12)。
func aligned_cap(cap: int) -> int:
	return int(ceil(float(cap) / EMPLOY_CAP_STEP)) * EMPLOY_CAP_STEP

## 新規プレイ開始(複数セーブスロット、save_system.gd)用のリセット。
func reset() -> void:
	funds = 300
	employ_cap = EMPLOY_CAP_INITIAL
	facility_level = 0
