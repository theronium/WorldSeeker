extends Node
# ワールドの初期コンテンツ定義(エリア/セクション/フロア/ゲート/イベント台本)を集約する。
#
# UI(main.gd)からは完全に独立しており、WorldMapへ流し込むだけの役割を持つ。
# 8.1節の想定通り、将来的にはここが開発時オフライン生成データ(Claude Code生成 → DB格納)に
# 置き換わる。オートロードとして他のシステムより先にワールドを構築しておく。

func _ready() -> void:
	_define_items()
	_build_kingdom()
	_build_reinvale()

func _define_items() -> void:
	Items.define("goblin_amulet", "ゴブリンキングの護符")

func _build_kingdom() -> void:
	WorldMap.add_area("kingdom", "小さな王国")
	WorldMap.add_section("village_area", "始まりの村周辺", "kingdom")
	WorldMap.add_section("old_cave_dungeon", "古い洞窟", "kingdom")
	WorldMap.add_section("whispering_forest", "ささやきの森", "kingdom")
	WorldMap.add_section("border_road", "国境の道", "kingdom")

	# --- 始まりの村周辺 ---
	WorldMap.add_node("village", "始まりの村", ["forest_edge"], {}, "village_area")
	WorldMap.add_node("forest_edge", "森の入口", ["village", "old_shrine", "cave", "forest_path", "border_path"], {}, "village_area")
	WorldMap.add_node("old_shrine", "古い祠", ["forest_edge"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 2}, "village_area")
	WorldMap.mark_passed("village")
	WorldMap.mark_passed("forest_edge")

	# --- 古い洞窟 ---
	WorldMap.add_node("cave", "洞窟", ["forest_edge", "locked_vault"], {}, "old_cave_dungeon")
	WorldMap.add_node("locked_vault", "封印の小部屋", ["cave", "boss_lair"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 2}, "old_cave_dungeon")
	WorldMap.add_node("boss_lair", "ゴブリンキングの間", ["locked_vault", "goblin_treasury"], {"type": "combat", "enemy_power": 40}, "old_cave_dungeon", "goblin_amulet")
	WorldMap.add_node("goblin_treasury", "秘密の宝物庫", ["boss_lair"], {"type": "item", "item": "goblin_amulet"}, "old_cave_dungeon")

	# --- ささやきの森 ---
	WorldMap.add_node("forest_path", "森の小道", ["forest_edge", "mossy_clearing"], {}, "whispering_forest")
	WorldMap.add_node("mossy_clearing", "苔むした広場", ["forest_path", "fallen_log", "old_well"], {}, "whispering_forest")
	WorldMap.add_node("old_well", "古井戸", ["mossy_clearing"], {}, "whispering_forest")
	WorldMap.add_node("fallen_log", "倒木の道", ["mossy_clearing", "deep_thicket"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 2}, "whispering_forest")
	WorldMap.add_node("deep_thicket", "深い茂み", ["fallen_log", "wolf_den"], {}, "whispering_forest")
	WorldMap.add_node("wolf_den", "狼の巣穴", ["deep_thicket"], {"type": "combat", "enemy_power": 25}, "whispering_forest")

	# --- 国境の道 ---
	WorldMap.add_node("border_path", "国境へ続く道", ["forest_edge", "border_checkpoint"], {}, "border_road")
	WorldMap.add_node("border_checkpoint", "国境の関所", ["border_path", "reinvale_gate"], {"type": "innate_trait", "trait": "bloodline", "value": "王家の落胤"}, "border_road")

	WorldMap.set_event_scripts("old_shrine",
		[
			{"side": "none", "name": "古い祠", "text": "祠の奥から声が響く。「三つの問いに答えよ」", "next": 1},
			{"side": "none", "name": "古い祠", "text": "同行したNPCは静かに考え込み、やがて答えを口にした。", "next": 2},
			{"side": "none", "name": "古い祠", "text": "……正解だ。道を開けよう。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "古い祠", "text": "祠の奥から声が響く。「三つの問いに答えよ」", "next": 1},
			{"side": "none", "name": "古い祠", "text": "NPCは首をひねるばかりで、答えが出てこない。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("boss_lair",
		[
			{"side": "right", "name": "ゴブリンキング", "text": "……よくぞここまで来たか、小僧……", "next": 1},
			{"side": "none", "name": "", "text": "激しい戦闘の末、ゴブリンキングは膝をついた。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "ゴブリンキング", "text": "……よくぞここまで来たか、小僧……", "next": 1},
			{"side": "none", "name": "", "text": "歯が立たず、深手を負って撤退した。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("goblin_treasury",
		[
			{"side": "none", "name": "宝物庫の扉", "text": "護符をはめ込む窪みのある、頑丈な扉だ。", "next": 1},
			{"side": "none", "name": "", "text": "ゴブリンキングの護符が窪みに吸い込まれ、扉が開いた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "宝物庫の扉", "text": "護符をはめ込む窪みのある、頑丈な扉だ。", "next": 1},
			{"side": "none", "name": "", "text": "護符を持っていないため、扉はびくともしない。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("wolf_den",
		[
			{"side": "right", "name": "狼の群れ", "text": "茂みの奥から、複数の唸り声が聞こえる。", "next": 1},
			{"side": "none", "name": "", "text": "群れのボスを退け、巣穴を制圧した。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "狼の群れ", "text": "茂みの奥から、複数の唸り声が聞こえる。", "next": 1},
			{"side": "none", "name": "", "text": "数に押され、やむなく退いた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("border_checkpoint",
		[
			{"side": "left", "name": "国境の衛兵", "text": "止まれ。この先は隣国レインヴェールだ。血筋を示せ。", "next": 1},
			{"side": "none", "name": "", "text": "紋章を確かめた衛兵は道を譲った。「……失礼した、お通りください」", "outcome": "pass"},
		],
		[
			{"side": "left", "name": "国境の衛兵", "text": "止まれ。この先は隣国レインヴェールだ。血筋を示せ。", "next": 1},
			{"side": "none", "name": "", "text": "「証がなければ通せぬ」衛兵は道を譲らなかった。", "outcome": "fail"},
		])

func _build_reinvale() -> void:
	WorldMap.add_area("reinvale", "隣国レインヴェール")
	WorldMap.add_section("reinvale_outskirts", "レインヴェール郊外", "reinvale")
	WorldMap.add_section("sunken_ruins", "沈んだ遺跡", "reinvale")

	# --- レインヴェール郊外 ---
	# 王国の国境検問所(border_checkpoint)を突破すると、ここが隣接フロアとして開ける。
	WorldMap.add_node("reinvale_gate", "国境門", ["border_checkpoint", "market_road"], {}, "reinvale_outskirts")
	WorldMap.add_node("market_road", "市場通り", ["reinvale_gate", "old_watchtower", "riverside"], {}, "reinvale_outskirts")
	WorldMap.add_node("old_watchtower", "古い物見塔", ["market_road"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3}, "reinvale_outskirts")
	WorldMap.add_node("riverside", "川辺の道", ["market_road", "sunken_path"], {}, "reinvale_outskirts")

	# --- 沈んだ遺跡 ---
	WorldMap.add_node("sunken_path", "水没した小道", ["riverside", "ruin_entrance"], {}, "sunken_ruins")
	WorldMap.add_node("ruin_entrance", "遺跡の入口", ["sunken_path", "ruin_hall"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 3}, "sunken_ruins")
	WorldMap.add_node("ruin_hall", "遺跡の大広間", ["ruin_entrance", "throne_room"], {}, "sunken_ruins")
	WorldMap.add_node("throne_room", "沈める王の間", ["ruin_hall"], {"type": "combat", "enemy_power": 70}, "sunken_ruins")

	WorldMap.set_event_scripts("old_watchtower",
		[
			{"side": "none", "name": "物見塔の扉", "text": "扉に古代文字の刻まれた仕掛け錠がある。", "next": 1},
			{"side": "none", "name": "", "text": "刻まれた詩の意味を読み解き、錠が外れた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "物見塔の扉", "text": "扉に古代文字の刻まれた仕掛け錠がある。", "next": 1},
			{"side": "none", "name": "", "text": "文字の意味がわからず、扉は開かなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("throne_room",
		[
			{"side": "right", "name": "沈める王", "text": "……何用だ、我が眠りを妨げる者よ。", "next": 1},
			{"side": "none", "name": "", "text": "長き戦いの果て、沈める王はついに崩れ去った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "沈める王", "text": "……何用だ、我が眠りを妨げる者よ。", "next": 1},
			{"side": "none", "name": "", "text": "王の力は圧倒的で、生きて広間を後にするのが精一杯だった。", "outcome": "fail"},
		])
