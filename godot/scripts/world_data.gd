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
	Items.define("old_expedition_map", "古い探検隊の地図")
	Items.define("thief_signet", "盗賊の印章")
	Items.define("crown_of_the_deep", "深淵の王冠")

func _build_kingdom() -> void:
	WorldMap.add_area("kingdom", "小さな王国")
	WorldMap.add_section("village_area", "始まりの村周辺", "kingdom")
	WorldMap.add_section("old_cave_dungeon", "古い洞窟", "kingdom")
	WorldMap.add_section("whispering_forest", "ささやきの森", "kingdom")
	WorldMap.add_section("border_road", "国境の道", "kingdom")
	WorldMap.add_section("capital_district", "王都", "kingdom")
	WorldMap.add_section("noble_quarter", "貴族街", "kingdom")

	# --- 始まりの村周辺 ---
	WorldMap.add_node("village", "始まりの村", ["forest_edge", "capital_road"], {}, "village_area")
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

	# --- 王都 ---
	WorldMap.add_node("capital_road", "王都へ続く街道", ["village", "capital_gate"], {}, "capital_district")
	WorldMap.add_node("capital_gate", "王都の門", ["capital_road", "capital_plaza"], {}, "capital_district")
	WorldMap.add_node("capital_plaza", "王都広場", ["capital_gate", "guild_hall", "market_district", "noble_gate"], {}, "capital_district")
	WorldMap.add_node("guild_hall", "冒険者ギルド", ["capital_plaza", "archive_room"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 1}, "capital_district")
	WorldMap.add_node("archive_room", "古文書庫", ["guild_hall", "royal_library"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3}, "capital_district", "old_expedition_map")
	WorldMap.add_node("royal_library", "王立図書館の禁書区画", ["archive_room"], {"type": "item", "item": "old_expedition_map"}, "capital_district")
	WorldMap.add_node("market_district", "商業区", ["capital_plaza", "back_alley"], {}, "capital_district")
	WorldMap.add_node("back_alley", "裏路地", ["market_district", "thieves_den"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 2}, "capital_district")
	WorldMap.add_node("thieves_den", "盗賊団のアジト", ["back_alley"], {"type": "combat", "enemy_power": 35}, "capital_district", "thief_signet")

	WorldMap.set_event_scripts("archive_room",
		[
			{"side": "none", "name": "古文書庫", "text": "崩れかけた棚に、色褪せた探検記録の束が眠っている。", "next": 1},
			{"side": "none", "name": "", "text": "記録の中から、当時の探検隊が遺した地図を見つけ出した。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "古文書庫", "text": "崩れかけた棚に、色褪せた探検記録の束が眠っている。", "next": 1},
			{"side": "none", "name": "", "text": "文字はほとんど判読できず、手がかりは得られなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("thieves_den",
		[
			{"side": "right", "name": "盗賊団の頭目", "text": "裏路地に迷い込むとはな……高くつくぜ？", "next": 1},
			{"side": "none", "name": "", "text": "頭目を打ち倒し、印章を回収した。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "盗賊団の頭目", "text": "裏路地に迷い込むとはな……高くつくぜ？", "next": 1},
			{"side": "none", "name": "", "text": "一味に囲まれ、命からがら逃げ出した。", "outcome": "fail"},
		])

	# --- 貴族街 ---
	# 王都広場(capital_plaza)から血筋を示すことで入れる区画。
	WorldMap.add_node("noble_gate", "貴族街の門", ["capital_plaza", "manor_garden"], {"type": "innate_trait", "trait": "bloodline", "value": "旧家の血筋"}, "noble_quarter")
	WorldMap.add_node("manor_garden", "屋敷の庭園", ["noble_gate", "hidden_vault", "cathedral_square"], {}, "noble_quarter")
	WorldMap.add_node("hidden_vault", "隠し金庫室", ["manor_garden"], {"type": "item", "item": "thief_signet"}, "noble_quarter")
	WorldMap.add_node("cathedral_square", "大聖堂前広場", ["manor_garden", "bell_tower"], {}, "noble_quarter")
	WorldMap.add_node("bell_tower", "大聖堂の鐘楼", ["cathedral_square"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 3}, "noble_quarter")

	WorldMap.set_event_scripts("noble_gate",
		[
			{"side": "left", "name": "門番", "text": "ここから先は由緒ある家柄の者のみが立ち入れる。家名を名乗れ。", "next": 1},
			{"side": "none", "name": "", "text": "血筋を確かめた門番は、静かに門を開いた。", "outcome": "pass"},
		],
		[
			{"side": "left", "name": "門番", "text": "ここから先は由緒ある家柄の者のみが立ち入れる。家名を名乗れ。", "next": 1},
			{"side": "none", "name": "", "text": "「聞いたことのない家名だ」門番は取り合わなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("hidden_vault",
		[
			{"side": "none", "name": "隠し金庫室", "text": "扉には見覚えのある紋章の凹みがある。", "next": 1},
			{"side": "none", "name": "", "text": "盗賊団の印章を差し込むと、重い扉が開いた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "隠し金庫室", "text": "扉には見覚えのある紋章の凹みがある。", "next": 1},
			{"side": "none", "name": "", "text": "凹みに合う印章を持っていない。扉は開かなかった。", "outcome": "fail"},
		])

func _build_reinvale() -> void:
	WorldMap.add_area("reinvale", "隣国レインヴェール")
	WorldMap.add_section("reinvale_outskirts", "レインヴェール郊外", "reinvale")
	WorldMap.add_section("sunken_ruins", "沈んだ遺跡", "reinvale")
	WorldMap.add_section("elven_woods", "隠れ森の郷", "reinvale")
	WorldMap.add_section("sunken_depths", "遺跡の深層", "reinvale")

	# --- レインヴェール郊外 ---
	# 王国の国境検問所(border_checkpoint)を突破すると、ここが隣接フロアとして開ける。
	WorldMap.add_node("reinvale_gate", "国境門", ["border_checkpoint", "market_road"], {}, "reinvale_outskirts")
	WorldMap.add_node("market_road", "市場通り", ["reinvale_gate", "old_watchtower", "riverside", "elf_ward"], {}, "reinvale_outskirts")
	WorldMap.add_node("old_watchtower", "古い物見塔", ["market_road"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3}, "reinvale_outskirts")
	WorldMap.add_node("riverside", "川辺の道", ["market_road", "sunken_path"], {}, "reinvale_outskirts")

	# --- 沈んだ遺跡 ---
	WorldMap.add_node("sunken_path", "水没した小道", ["riverside", "ruin_entrance"], {}, "sunken_ruins")
	WorldMap.add_node("ruin_entrance", "遺跡の入口", ["sunken_path", "ruin_hall"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 3}, "sunken_ruins")
	WorldMap.add_node("ruin_hall", "遺跡の大広間", ["ruin_entrance", "throne_room"], {}, "sunken_ruins")
	WorldMap.add_node("throne_room", "沈める王の間", ["ruin_hall", "depths_stair"], {"type": "combat", "enemy_power": 70}, "sunken_ruins")

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

	# --- 隠れ森の郷 ---
	# 市場通り(market_road)から森人の血を示すことで入れる隠れ里。
	WorldMap.add_node("elf_ward", "森の結界", ["market_road", "elder_grove"], {"type": "innate_trait", "trait": "bloodline", "value": "森人の血"}, "elven_woods")
	WorldMap.add_node("elder_grove", "長老の木立", ["elf_ward", "spirit_shrine", "moonwell_guardian"], {}, "elven_woods")
	WorldMap.add_node("spirit_shrine", "精霊の祠", ["elder_grove"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 4}, "elven_woods")
	WorldMap.add_node("moonwell_guardian", "月の泉の守護者", ["elder_grove"], {"type": "combat", "enemy_power": 55}, "elven_woods")

	WorldMap.set_event_scripts("elf_ward",
		[
			{"side": "left", "name": "森の精霊", "text": "結界の向こうから声がする。「森人の血を持たぬ者は通さぬ」", "next": 1},
			{"side": "none", "name": "", "text": "血の証を認めた結界が、静かに揺らいで道を開いた。", "outcome": "pass"},
		],
		[
			{"side": "left", "name": "森の精霊", "text": "結界の向こうから声がする。「森人の血を持たぬ者は通さぬ」", "next": 1},
			{"side": "none", "name": "", "text": "結界はびくともせず、弾き返されてしまった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("moonwell_guardian",
		[
			{"side": "right", "name": "月の泉の守護者", "text": "泉の水面が波立ち、古の獣が姿を現す。", "next": 1},
			{"side": "none", "name": "", "text": "守護者を退け、泉には再び静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "月の泉の守護者", "text": "泉の水面が波立ち、古の獣が姿を現す。", "next": 1},
			{"side": "none", "name": "", "text": "獣の力に押され、木立の外まで追い返された。", "outcome": "fail"},
		])

	# --- 遺跡の深層 ---
	# 沈める王の間(throne_room)を突破すると、さらに奥へ続く階段が見つかる。
	WorldMap.add_node("depths_stair", "深層へ続く階段", ["throne_room", "flooded_crypt"], {}, "sunken_depths")
	WorldMap.add_node("flooded_crypt", "水没した墓所", ["depths_stair", "drowned_throne"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 4}, "sunken_depths")
	WorldMap.add_node("drowned_throne", "溺れし玉座の間", ["flooded_crypt", "treasure_hall"], {"type": "combat", "enemy_power": 90}, "sunken_depths", "crown_of_the_deep")
	WorldMap.add_node("treasure_hall", "王冠の間", ["drowned_throne"], {"type": "item", "item": "crown_of_the_deep"}, "sunken_depths")

	WorldMap.set_event_scripts("drowned_throne",
		[
			{"side": "right", "name": "溺れし王の亡霊", "text": "……我が王冠を求め、ここまで来たか。", "next": 1},
			{"side": "none", "name": "", "text": "亡霊はついに力尽き、水底へと崩れ落ちていった。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "溺れし王の亡霊", "text": "……我が王冠を求め、ここまで来たか。", "next": 1},
			{"side": "none", "name": "", "text": "圧倒的な力の前に、なすすべなく押し戻された。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("treasure_hall",
		[
			{"side": "none", "name": "王冠の間", "text": "水底に沈んだ台座に、王冠を収める窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "深淵の王冠を捧げると、間全体が静かな光に包まれた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "王冠の間", "text": "水底に沈んだ台座に、王冠を収める窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "王冠を持たぬ今は、台座はただ沈黙している。", "outcome": "fail"},
		])
