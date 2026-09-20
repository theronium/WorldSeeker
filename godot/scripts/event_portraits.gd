class_name EventPortraits
# イベント会話の左右の枠に出す画像(design.md 7.3節)。会話の行(`side`が"left"/"right")の話者名から、
# 出す画像のidを決める。画像本体は探索者の肖像と同じ`res://assets/portraits/`にある
# (PortraitLibrary.texture_path()で読める): 町人・イベントキャラ=`npc_01`〜`npc_32`(32枚)、
# 敵=`enemy_01`〜`enemy_32`(32枚)。元画像は tools/prepare_portraits.py の`--no-number`で加工した。
#
# 選び方: 名前ごとに固定の対応表(下の2つ)で決める。同じ名前なら、いつ見ても同じ顔になる。
# 表に無い名前(新しく足した敵や人物)は、戦闘系の会話(kind=boss/combat)なら敵の画像から、それ以外なら
# 町人の画像から、名前のハッシュで1枚を選ぶ(同じ名前は同じ画像。新しいコンテンツを足しても、
# ここへ足し忘れて画像が出ない、ということは起きない)。表に書き足せば、後から選び直せる。
#
# 敵の対応は絵柄の近さで選んだ。敵は35種の名前に対して画像が32枚なので、絵柄が近い同士(骸骨・ゴーレム・
# 幽霊など)は、離れたエリアの敵に限って同じ画像を使い回している。

const ENEMY_BY_NAME := {
	# 古い洞窟・ささやきの森・王都・沈んだ遺跡
	"ゴブリンキング": "enemy_21", # 角付きの兜を被った重装のオーク風=ゴブリンの王
	"ゴブリンの見張り": "enemy_18", # 弓のゴブリン
	"狼の群れ": "enemy_23",
	"盗賊団の頭目": "enemy_22", # 短剣とスカーフの獣人盗賊
	"沈める王": "enemy_31", # ミイラ=古代の王
	"溺れし王の亡霊": "enemy_27",
	"月の泉の守護者": "enemy_13", # ケルベロス=守護獣
	# 灰色の山嶺
	"坑道の主": "enemy_10", # ミノタウロス=巨躯の主
	"灰の幼竜": "enemy_09", # 竜人風のリザードマン(竜は次の「灰塵の竜」に取っておく)
	"灰塵の竜": "enemy_12",
	# 忘れられた地下墓地
	"彷徨う骨片": "enemy_28",
	"骸骨兵の群れ": "enemy_29",
	"彷徨う守護者": "enemy_32", # 朽ちた鎧の騎士=首なしの黒騎士
	"リッチ": "enemy_02", # 魔導書と紫の炎のフード姿
	# 精霊界
	"空竜蛇": "enemy_12",
	"島影の番人": "enemy_14", # 樹の番人
	"影の分身": "enemy_15", # 鏡像のような吸血鬼
	"星幽の守護者": "enemy_01", # 星飾りの帽子の魔女
	# 月魄の湖
	"漂う亡霊": "enemy_27",
	"里を守る影": "enemy_30", # ゾンビ=沈んだ里の亡者
	"鬼火の群れ": "enemy_27", # 青い炎をまとった幽霊
	"月姫": "enemy_11", # 翼のあるハーピー
	# 妖精の隠れ里
	"苔の輪の番人": "enemy_06", # 小さな緑の何か=マンドラゴラ
	"群生地の番人": "enemy_08", # 大蜘蛛
	"妖精女王": "enemy_01",
	# 結晶の深淵
	"結晶の欠片獣": "enemy_24",
	"結晶蜘蛛": "enemy_08",
	"砕ける谺": "enemy_02",
	"結晶の王": "enemy_04", # 結晶を核にしたゴーレム
	# 業火の火口
	"灰の小鬼": "enemy_03", # 炎の小悪魔
	"黒曜石のゴーレム": "enemy_04",
	"燠火の精": "enemy_03",
	"火蜥蜴の群れ": "enemy_09",
	"溶岩の大蛇": "enemy_12",
	"業火の王": "enemy_16", # 角と黒い鎧の魔王風
}

const NPC_BY_NAME := {
	"案内人": "npc_01", # チュートリアルの案内役=杖の老賢者
	"国境の衛兵": "npc_27", # 槍と兜の兵士
	"門番": "npc_29", # 赤いマントの騎士
	"森の精霊": "npc_08", # 緑のフードと薬草の紫髪
	"謎かけの妖精": "npc_20", # 水晶玉の占い師
}

const POOL_SIZE := 32

## 話者名と会話の種別から、画像のidを返す。kindは"boss"/"combat"なら戦闘系(敵の画像)、それ以外は町人の画像。
static func portrait_id(speaker_name: String, kind: String) -> String:
	if ENEMY_BY_NAME.has(speaker_name):
		return ENEMY_BY_NAME[speaker_name]
	if NPC_BY_NAME.has(speaker_name):
		return NPC_BY_NAME[speaker_name]
	var prefix := "enemy" if kind == "boss" or kind == "combat" else "npc"
	return "%s_%02d" % [prefix, speaker_name.hash() % POOL_SIZE + 1]
