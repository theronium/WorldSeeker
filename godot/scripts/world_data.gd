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
	_build_ashen_peaks()
	_build_forgotten_catacombs()
	_build_spirit_plane()
	_build_moonlit_lake()
	_build_fae_hollow()
	_build_crystalline_depths()
	_build_inferno_crater()

func _define_items() -> void:
	Items.define("goblin_amulet", "ゴブリンキングの護符")
	Items.define("old_expedition_map", "古い探検隊の地図")
	Items.define("thief_signet", "盗賊の印章")
	Items.define("crown_of_the_deep", "深淵の王冠")
	Items.define("dwarven_forge_hammer", "ドワーフの鍛冶槌")
	Items.define("warden_key", "坑道主の鍵")
	Items.define("ashen_dragon_scale", "灰塵の竜鱗")
	Items.define("silver_reliquary", "銀の聖遺物匣")
	Items.define("phylactery_shard", "砕けたフィラクテリーの欠片")
	Items.define("starlight_fragment", "星の欠片")
	Items.define("astral_core", "星幽の核")
	Items.define("moonpearl", "月の真珠")
	Items.define("moonsoul_crown", "月魄の冠")
	Items.define("fae_dust", "妖精の粉塵")
	Items.define("queens_favor", "女王の寵愛の証")
	Items.define("resonant_shard", "共鳴する欠片")
	Items.define("heart_of_crystal", "結晶の心臓")
	Items.define("obsidian_shard", "黒曜石の欠片")
	Items.define("emberforged_ingot", "業火で鍛えた鋼塊")
	Items.define("heart_of_inferno", "業火の心臓")
	# design.md 4.8節「転職」用の消費アイテム。後半〜終盤の各エリア(4〜9番目)の
	# 手強い戦闘ゲート6箇所(いずれも既存の報酬チェーンに含まれない箇所)にそれぞれ設置し、
	# 同じアイテムIDなので複数箇所から繰り返し入手できる(1体のNPCが同時に複数個は持てない、
	# Items.grant()の仕様どおり)。消費すると任意のジョブへ転職できる(NPC管理パネル)。
	Items.define("reclass_elixir", "転職の秘薬")

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
	WorldMap.mark_passed("village", true)
	WorldMap.mark_passed("forest_edge", true)

	# --- 古い洞窟 ---
	WorldMap.add_node("cave", "洞窟", ["forest_edge", "locked_vault"], {}, "old_cave_dungeon")
	WorldMap.add_node("locked_vault", "封印の小部屋", ["cave", "boss_lair"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 2}, "old_cave_dungeon")
	WorldMap.add_node("boss_lair", "ゴブリンキングの間", ["locked_vault", "goblin_treasury"], {"type": "combat", "enemy_power": 180}, "old_cave_dungeon", "goblin_amulet")
	WorldMap.add_node("goblin_treasury", "秘密の宝物庫", ["boss_lair"], {"type": "item", "item": "goblin_amulet"}, "old_cave_dungeon")

	# --- ささやきの森 ---
	WorldMap.add_node("forest_path", "森の小道", ["forest_edge", "mossy_clearing"], {}, "whispering_forest")
	WorldMap.add_node("mossy_clearing", "苔むした広場", ["forest_path", "fallen_log", "old_well"], {}, "whispering_forest")
	WorldMap.add_node("old_well", "古井戸", ["mossy_clearing", "well_shaft"], {}, "whispering_forest")
	WorldMap.add_node("fallen_log", "倒木の道", ["mossy_clearing", "deep_thicket"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 2}, "whispering_forest")
	WorldMap.add_node("deep_thicket", "深い茂み", ["fallen_log", "wolf_den"], {}, "whispering_forest")
	WorldMap.add_node("wolf_den", "狼の巣穴", ["deep_thicket"], {"type": "combat", "enemy_power": 140}, "whispering_forest")

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
	WorldMap.add_node("thieves_den", "盗賊団のアジト", ["back_alley"], {"type": "combat", "enemy_power": 160}, "capital_district", "thief_signet")

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
	WorldMap.add_node("bell_tower", "大聖堂の鐘楼", ["cathedral_square", "crypt_stairs"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 3}, "noble_quarter")

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
	WorldMap.add_node("old_watchtower", "古い物見塔", ["market_road", "mountain_pass"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3}, "reinvale_outskirts")
	WorldMap.add_node("riverside", "川辺の道", ["market_road", "sunken_path"], {}, "reinvale_outskirts")

	# --- 沈んだ遺跡 ---
	WorldMap.add_node("sunken_path", "水没した小道", ["riverside", "ruin_entrance"], {}, "sunken_ruins")
	WorldMap.add_node("ruin_entrance", "遺跡の入口", ["sunken_path", "ruin_hall"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 3}, "sunken_ruins")
	WorldMap.add_node("ruin_hall", "遺跡の大広間", ["ruin_entrance", "throne_room"], {}, "sunken_ruins")
	WorldMap.add_node("throne_room", "沈める王の間", ["ruin_hall", "depths_stair"], {"type": "combat", "enemy_power": 200}, "sunken_ruins")

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
	WorldMap.add_node("spirit_shrine", "精霊の祠", ["elder_grove", "threshold_rift"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 4}, "elven_woods")
	WorldMap.add_node("moonwell_guardian", "月の泉の守護者", ["elder_grove", "lake_path"], {"type": "combat", "enemy_power": 180}, "elven_woods")

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
	WorldMap.add_node("drowned_throne", "溺れし玉座の間", ["flooded_crypt", "treasure_hall"], {"type": "combat", "enemy_power": 240}, "sunken_depths", "crown_of_the_deep")
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

func _build_ashen_peaks() -> void:
	WorldMap.add_area("ashen_peaks", "灰色の山嶺")
	WorldMap.add_section("mountain_pass_road", "峠道", "ashen_peaks")
	WorldMap.add_section("dwarven_hold", "ドワーフの砦", "ashen_peaks")
	WorldMap.add_section("abandoned_mine", "廃坑", "ashen_peaks")
	WorldMap.add_section("dragon_spire", "竜の尖塔", "ashen_peaks")

	# --- 峠道 ---
	# レインヴェール郊外の古い物見塔(old_watchtower)を突破すると隣接フロアとして開ける。
	WorldMap.add_node("mountain_pass", "山越えの道", ["old_watchtower", "ridge_camp"], {}, "mountain_pass_road")
	WorldMap.add_node("ridge_camp", "尾根の野営地", ["mountain_pass", "hold_gate", "cliff_shrine"], {}, "mountain_pass_road")
	WorldMap.add_node("cliff_shrine", "断崖の祠", ["ridge_camp", "spire_trail"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 3}, "mountain_pass_road")

	WorldMap.set_event_scripts("cliff_shrine",
		[
			{"side": "none", "name": "断崖の祠", "text": "崖に張り付くように佇む小さな祠。目を凝らすと、壁面にかすかな足がかりが見える。", "next": 1},
			{"side": "none", "name": "", "text": "見つけた足がかりを頼りに、誰も知らない獣道へと踏み出した。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "断崖の祠", "text": "崖に張り付くように佇む小さな祠。目を凝らすと、壁面にかすかな足がかりが見える。", "next": 1},
			{"side": "none", "name": "", "text": "壁は滑らかで、それらしい痕跡は見当たらなかった。", "outcome": "fail"},
		])

	# --- ドワーフの砦 ---
	WorldMap.add_node("hold_gate", "砦の門", ["ridge_camp", "hold_square"], {}, "dwarven_hold")
	WorldMap.add_node("hold_square", "砦の広場", ["hold_gate", "forge_district", "tavern", "mine_entrance_road"], {}, "dwarven_hold")
	WorldMap.add_node("forge_district", "鍛冶区画", ["hold_square", "master_forge", "sealed_stockroom"], {}, "dwarven_hold")
	WorldMap.add_node("master_forge", "大鍛冶場", ["forge_district"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 3}, "dwarven_hold", "dwarven_forge_hammer")
	WorldMap.add_node("sealed_stockroom", "封印の資材庫", ["forge_district"], {"type": "item", "item": "dwarven_forge_hammer"}, "dwarven_hold")
	WorldMap.add_node("tavern", "酒場", ["hold_square", "rumor_room"], {}, "dwarven_hold")
	WorldMap.add_node("rumor_room", "酒場の奥部屋", ["tavern"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 2}, "dwarven_hold")

	WorldMap.set_event_scripts("master_forge",
		[
			{"side": "none", "name": "大鍛冶場", "text": "使われなくなった炉の奥に、頑丈な鉄扉で閉ざされた道具棚がある。", "next": 1},
			{"side": "none", "name": "", "text": "扉を打ち破ると、ドワーフ製の鍛冶槌が眠っていた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "大鍛冶場", "text": "使われなくなった炉の奥に、頑丈な鉄扉で閉ざされた道具棚がある。", "next": 1},
			{"side": "none", "name": "", "text": "扉はびくともせず、力尽きて諦めた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("sealed_stockroom",
		[
			{"side": "none", "name": "封印の資材庫", "text": "分厚い鉄板が打ち付けられた戸口。並の道具では歯が立たなそうだ。", "next": 1},
			{"side": "none", "name": "", "text": "鍛冶槌を振るうと、鉄板は呆気なく砕け散った。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "封印の資材庫", "text": "分厚い鉄板が打ち付けられた戸口。並の道具では歯が立たなそうだ。", "next": 1},
			{"side": "none", "name": "", "text": "鉄板はびくともせず、手ぶらでは開けようがなかった。", "outcome": "fail"},
		])

	# --- 廃坑 ---
	WorldMap.add_node("mine_entrance_road", "廃坑への道", ["hold_square", "mine_entrance"], {}, "abandoned_mine")
	WorldMap.add_node("mine_entrance", "廃坑入口", ["mine_entrance_road", "collapsed_tunnel"], {}, "abandoned_mine")
	WorldMap.add_node("collapsed_tunnel", "崩れた坑道", ["mine_entrance", "deep_shaft"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 2}, "abandoned_mine")
	WorldMap.add_node("deep_shaft", "深部立坑", ["collapsed_tunnel", "crystal_cavern", "goblin_outpost"], {}, "abandoned_mine")
	WorldMap.add_node("crystal_cavern", "結晶洞", ["deep_shaft", "descent_path"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 4}, "abandoned_mine")
	WorldMap.add_node("goblin_outpost", "ゴブリンの前哨基地", ["deep_shaft", "mine_boss_chamber"], {"type": "combat", "enemy_power": 220}, "abandoned_mine")
	WorldMap.add_node("mine_boss_chamber", "坑道主の間", ["goblin_outpost", "mine_vault"], {"type": "combat", "enemy_power": 260}, "abandoned_mine", "warden_key")
	WorldMap.add_node("mine_vault", "坑道の宝物庫", ["mine_boss_chamber"], {"type": "item", "item": "warden_key"}, "abandoned_mine")

	WorldMap.set_event_scripts("crystal_cavern",
		[
			{"side": "none", "name": "結晶洞", "text": "暗闇の中、壁一面に無数の結晶が埋まっているのが、目を凝らすとようやく見えてくる。", "next": 1},
			{"side": "none", "name": "", "text": "淡く光る結晶の一つ一つに、思わず息を呑んだ。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "結晶洞", "text": "暗闇の中、壁一面に無数の結晶が埋まっているのが、目を凝らすとようやく見えてくる。", "next": 1},
			{"side": "none", "name": "", "text": "ただの暗い岩壁にしか見えず、何も見つけられなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("goblin_outpost",
		[
			{"side": "right", "name": "ゴブリンの見張り", "text": "坑道の奥から、複数の気配が押し寄せてくる。", "next": 1},
			{"side": "none", "name": "", "text": "見張りたちを蹴散らし、前哨基地を制圧した。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "ゴブリンの見張り", "text": "坑道の奥から、複数の気配が押し寄せてくる。", "next": 1},
			{"side": "none", "name": "", "text": "数の多さに押し切られ、坑道を後にした。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("mine_boss_chamber",
		[
			{"side": "right", "name": "坑道の主", "text": "巨躯の影が、坑道を守るように立ちはだかる。", "next": 1},
			{"side": "none", "name": "", "text": "坑道の主を打ち倒し、腰から下がっていた鍵を回収した。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "坑道の主", "text": "巨躯の影が、坑道を守るように立ちはだかる。", "next": 1},
			{"side": "none", "name": "", "text": "圧倒的な力の前に、なすすべなく退いた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("mine_vault",
		[
			{"side": "none", "name": "坑道の宝物庫", "text": "頑丈な鉄格子の奥に、積み上げられた財宝が見える。", "next": 1},
			{"side": "none", "name": "", "text": "坑道の主の鍵が、鉄格子の錠に吸い込まれるようにはまった。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "坑道の宝物庫", "text": "頑丈な鉄格子の奥に、積み上げられた財宝が見える。", "next": 1},
			{"side": "none", "name": "", "text": "鍵を持たぬ今は、鉄格子を開ける術がない。", "outcome": "fail"},
		])

	# --- 竜の尖塔 ---
	# 断崖の祠(cliff_shrine)を突破すると隣接フロアとして開ける。
	WorldMap.add_node("spire_trail", "尖塔への隠し道", ["cliff_shrine", "spire_base"], {}, "dragon_spire")
	WorldMap.add_node("spire_base", "尖塔の麓", ["spire_trail", "ash_chamber", "spire_ascent"], {}, "dragon_spire")
	WorldMap.add_node("ash_chamber", "灰塵の間", ["spire_base", "rim_path"], {"type": "combat", "enemy_power": 240}, "dragon_spire")
	WorldMap.add_node("spire_ascent", "尖塔の階段", ["spire_base", "sealed_gate"], {}, "dragon_spire")
	WorldMap.add_node("sealed_gate", "封印の大扉", ["spire_ascent", "dragon_throne"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 5}, "dragon_spire")
	WorldMap.add_node("dragon_throne", "竜の玉座", ["sealed_gate", "dragon_hoard"], {"type": "combat", "enemy_power": 300}, "dragon_spire", "ashen_dragon_scale")
	WorldMap.add_node("dragon_hoard", "竜の財宝", ["dragon_throne"], {"type": "item", "item": "ashen_dragon_scale"}, "dragon_spire")

	WorldMap.set_event_scripts("ash_chamber",
		[
			{"side": "right", "name": "灰の幼竜", "text": "灰塵の間の奥で、小さな竜が威嚇するように鳴いた。", "next": 1},
			{"side": "none", "name": "", "text": "幼竜を退け、灰の中に静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "灰の幼竜", "text": "灰塵の間の奥で、小さな竜が威嚇するように鳴いた。", "next": 1},
			{"side": "none", "name": "", "text": "小さくとも竜は竜。歯が立たず退散した。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("sealed_gate",
		[
			{"side": "none", "name": "封印の大扉", "text": "扉一面に刻まれた古代の紋様が、微かな光を放っている。", "next": 1},
			{"side": "none", "name": "", "text": "紋様の意味を読み解くと、封印はひとりでに解けていった。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "封印の大扉", "text": "扉一面に刻まれた古代の紋様が、微かな光を放っている。", "next": 1},
			{"side": "none", "name": "", "text": "紋様の意味は掴めず、扉は沈黙したままだった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("dragon_throne",
		[
			{"side": "right", "name": "灰塵の竜", "text": "……久しいな、小さき者よ。我が眠りを妨げに来たか。", "next": 1},
			{"side": "none", "name": "", "text": "壮絶な死闘の末、灰塵の竜はついに力尽きた。その鱗の一枚が床に落ちた。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "灰塵の竜", "text": "……久しいな、小さき者よ。我が眠りを妨げに来たか。", "next": 1},
			{"side": "none", "name": "", "text": "竜の圧倒的な力の前に、命からがら尖塔を降りた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("dragon_hoard",
		[
			{"side": "none", "name": "竜の財宝", "text": "山と積まれた財宝の中央に、鱗をはめ込む台座がある。", "next": 1},
			{"side": "none", "name": "", "text": "竜の鱗を捧げると、財宝の間全体が静かに輝きを放った。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "竜の財宝", "text": "山と積まれた財宝の中央に、鱗をはめ込む台座がある。", "next": 1},
			{"side": "none", "name": "", "text": "鱗を持たぬ今は、台座はただ沈黙している。", "outcome": "fail"},
		])

func _build_forgotten_catacombs() -> void:
	WorldMap.add_area("forgotten_catacombs", "忘れられた地下墓地")
	WorldMap.add_section("crypt_entrance", "納骨堂入口", "forgotten_catacombs")
	WorldMap.add_section("bone_ossuary", "白骨の回廊", "forgotten_catacombs")
	WorldMap.add_section("sunken_chapel", "沈黙の礼拝堂", "forgotten_catacombs")
	WorldMap.add_section("lich_sanctum", "リッチの聖域", "forgotten_catacombs")

	# --- 納骨堂入口 ---
	# 王国・貴族街の大聖堂の鐘楼(bell_tower)を突破すると隣接フロアとして開ける。
	WorldMap.add_node("crypt_stairs", "地下への階段", ["bell_tower", "crypt_hall"], {}, "crypt_entrance")
	WorldMap.add_node("crypt_hall", "納骨堂の間", ["crypt_stairs", "rusted_door", "forgotten_shrine", "bone_corridor"], {}, "crypt_entrance")
	WorldMap.add_node("rusted_door", "錆びついた格子扉", ["crypt_hall"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 3}, "crypt_entrance")
	WorldMap.add_node("forgotten_shrine", "忘れられた祭壇", ["crypt_hall"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 2}, "crypt_entrance")

	# --- 白骨の回廊 ---
	WorldMap.add_node("bone_corridor", "白骨の回廊", ["crypt_hall", "whispering_alcove", "cracked_sarcophagus", "rattling_alcove", "ossuary_depths"], {}, "bone_ossuary")
	WorldMap.add_node("whispering_alcove", "囁きの窪み", ["bone_corridor"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 3}, "bone_ossuary")
	WorldMap.add_node("cracked_sarcophagus", "罅割れた石棺", ["bone_corridor"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 2}, "bone_ossuary", "silver_reliquary")
	WorldMap.add_node("rattling_alcove", "骨の鳴る窪み", ["bone_corridor"], {"type": "combat", "enemy_power": 280}, "bone_ossuary")
	WorldMap.add_node("ossuary_depths", "骸骨兵の間", ["bone_corridor", "chapel_stairs", "sealed_crypt_gate"], {"type": "combat", "enemy_power": 300}, "bone_ossuary")
	WorldMap.add_node("sealed_crypt_gate", "封じられた墓所の門", ["ossuary_depths", "lich_antechamber"], {"type": "item", "item": "silver_reliquary"}, "bone_ossuary")

	WorldMap.set_event_scripts("whispering_alcove",
		[
			{"side": "none", "name": "囁きの窪み", "text": "耳を澄ますと、壁の奥からかすかな囁き声が聞こえてくる気がする。", "next": 1},
			{"side": "none", "name": "", "text": "声の主は分からないが、誰かの祈りの言葉だけが静かに残った。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "囁きの窪み", "text": "耳を澄ますと、壁の奥からかすかな囁き声が聞こえてくる気がする。", "next": 1},
			{"side": "none", "name": "", "text": "耳を澄ませても、ただの静寂が広がるばかりだった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("cracked_sarcophagus",
		[
			{"side": "none", "name": "罅割れた石棺", "text": "蓋に大きな亀裂が走った石棺が、静かに横たわっている。", "next": 1},
			{"side": "none", "name": "", "text": "石棺を打ち砕くと、燻んだ銀の聖遺物匣が現れた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "罅割れた石棺", "text": "蓋に大きな亀裂が走った石棺が、静かに横たわっている。", "next": 1},
			{"side": "none", "name": "", "text": "石棺はびくともせず、力尽きて諦めた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("rattling_alcove",
		[
			{"side": "right", "name": "彷徨う骨片", "text": "窪みの奥で、砕けた骨がかたかたと音を立てて動き出す。", "next": 1},
			{"side": "none", "name": "", "text": "取るに足らない残骸を退け、静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "彷徨う骨片", "text": "窪みの奥で、砕けた骨がかたかたと音を立てて動き出す。", "next": 1},
			{"side": "none", "name": "", "text": "思いのほか手こずり、やむなく引き返した。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("ossuary_depths",
		[
			{"side": "right", "name": "骸骨兵の群れ", "text": "暗がりの奥で、骨のこすれ合う音が一斉に響いた。", "next": 1},
			{"side": "none", "name": "", "text": "骸骨兵たちを打ち払い、奥への道を切り開いた。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "骸骨兵の群れ", "text": "暗がりの奥で、骨のこすれ合う音が一斉に響いた。", "next": 1},
			{"side": "none", "name": "", "text": "数に押され、回廊の入口まで押し戻された。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("sealed_crypt_gate",
		[
			{"side": "none", "name": "封じられた墓所の門", "text": "門には聖印を嵌める窪みがあり、生半可な力では開かなそうだ。", "next": 1},
			{"side": "none", "name": "", "text": "銀の聖遺物匣を窪みに納めると、門は音もなく開いた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "封じられた墓所の門", "text": "門には聖印を嵌める窪みがあり、生半可な力では開かなそうだ。", "next": 1},
			{"side": "none", "name": "", "text": "聖遺物を持たぬ今は、門はぴくりとも動かなかった。", "outcome": "fail"},
		])

	# --- 沈黙の礼拝堂 ---
	# 骸骨兵の間(ossuary_depths)から分岐する、進行に必須ではない支線。
	WorldMap.add_node("chapel_stairs", "礼拝堂への階段", ["ossuary_depths", "chapel_nave"], {}, "sunken_chapel")
	WorldMap.add_node("chapel_nave", "礼拝堂の身廊", ["chapel_stairs", "altar_room", "bell_loft", "confessional_nook"], {}, "sunken_chapel")
	WorldMap.add_node("altar_room", "祭壇の間", ["chapel_nave"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3}, "sunken_chapel")
	WorldMap.add_node("bell_loft", "聖鐘楼", ["chapel_nave"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 4}, "sunken_chapel")
	WorldMap.add_node("confessional_nook", "懺悔室", ["chapel_nave"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 2}, "sunken_chapel")

	# --- リッチの聖域 ---
	WorldMap.add_node("lich_antechamber", "リッチの前室", ["sealed_crypt_gate", "restless_guardian", "warding_circle"], {}, "lich_sanctum")
	WorldMap.add_node("restless_guardian", "彷徨う守護者", ["lich_antechamber"], {"type": "combat", "enemy_power": 320}, "lich_sanctum", "reclass_elixir")
	WorldMap.add_node("warding_circle", "結界の間", ["lich_antechamber", "lich_throne"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 4}, "lich_sanctum")
	WorldMap.add_node("lich_throne", "リッチの玉座", ["warding_circle", "lich_vault"], {"type": "combat", "enemy_power": 360}, "lich_sanctum", "phylactery_shard")
	WorldMap.add_node("lich_vault", "秘宝の間", ["lich_throne"], {"type": "item", "item": "phylactery_shard"}, "lich_sanctum")

	WorldMap.set_event_scripts("restless_guardian",
		[
			{"side": "right", "name": "彷徨う守護者", "text": "前室の隅で、朽ちた鎧の騎士がゆっくりと立ち上がる。", "next": 1},
			{"side": "none", "name": "", "text": "守護者を打ち倒し、前室に再び沈黙が満ちた。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "彷徨う守護者", "text": "前室の隅で、朽ちた鎧の騎士がゆっくりと立ち上がる。", "next": 1},
			{"side": "none", "name": "", "text": "朽ちてなお衰えぬ剣技の前に、退かざるを得なかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("warding_circle",
		[
			{"side": "none", "name": "結界の間", "text": "床一面に描かれた魔法陣が、近づく者を拒むように淡く輝いている。", "next": 1},
			{"side": "none", "name": "", "text": "陣に刻まれた術式を読み解き、結界を静かに解いた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "結界の間", "text": "床一面に描かれた魔法陣が、近づく者を拒むように淡く輝いている。", "next": 1},
			{"side": "none", "name": "", "text": "術式の意味は掴めず、結界は輝きを増すばかりだった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("lich_throne",
		[
			{"side": "right", "name": "リッチ", "text": "……何者だ、我が眠りを騒がす者は。", "next": 1},
			{"side": "none", "name": "", "text": "死闘の末、リッチの体は崩れ去り、砕けたフィラクテリーの欠片だけが残った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "リッチ", "text": "……何者だ、我が眠りを騒がす者は。", "next": 1},
			{"side": "none", "name": "", "text": "死してなお纏う強大な力の前に、なすすべなく退いた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("lich_vault",
		[
			{"side": "none", "name": "秘宝の間", "text": "奥の台座に、欠片を嵌め込む窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "フィラクテリーの欠片を捧げると、間に眠っていた秘宝が姿を現した。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "秘宝の間", "text": "奥の台座に、欠片を嵌め込む窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "欠片を持たぬ今は、台座はただ沈黙している。", "outcome": "fail"},
		])

func _build_spirit_plane() -> void:
	WorldMap.add_area("spirit_plane", "精霊界")
	WorldMap.add_section("plane_threshold", "狭間の境界", "spirit_plane")
	WorldMap.add_section("drifting_isles", "漂う島々", "spirit_plane")
	WorldMap.add_section("mirror_hollow", "鏡影の窪地", "spirit_plane")
	WorldMap.add_section("astral_sanctum", "星幽の聖域", "spirit_plane")

	# --- 狭間の境界 ---
	# 隠れ森の郷の精霊の祠(spirit_shrine)を突破すると隣接フロアとして開ける。
	WorldMap.add_node("threshold_rift", "狭間の裂け目", ["spirit_shrine", "drifting_path"], {}, "plane_threshold")
	WorldMap.add_node("drifting_path", "漂う小道", ["threshold_rift", "isle_gate", "hollow_mist", "drifting_shrine"], {}, "plane_threshold")
	WorldMap.add_node("drifting_shrine", "漂う祠", ["drifting_path"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 2}, "plane_threshold")

	# --- 漂う島々 ---
	WorldMap.add_node("isle_gate", "浮島の門", ["drifting_path", "floating_garden"], {}, "drifting_isles")
	WorldMap.add_node("floating_garden", "浮遊庭園", ["isle_gate", "wind_shrine", "star_pool", "sky_serpent_nest", "isle_depths"], {}, "drifting_isles")
	WorldMap.add_node("wind_shrine", "風の祠", ["floating_garden"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 4}, "drifting_isles")
	WorldMap.add_node("star_pool", "星映す泉", ["floating_garden", "sealed_garden_vault"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 4}, "drifting_isles", "starlight_fragment")
	WorldMap.add_node("sealed_garden_vault", "封じられた庭園の蔵", ["star_pool"], {"type": "item", "item": "starlight_fragment"}, "drifting_isles")
	WorldMap.add_node("sky_serpent_nest", "空竜蛇の巣", ["floating_garden"], {"type": "combat", "enemy_power": 340}, "drifting_isles")
	WorldMap.add_node("isle_depths", "島影の奥", ["floating_garden", "sanctum_bridge"], {"type": "combat", "enemy_power": 380}, "drifting_isles", "reclass_elixir")

	WorldMap.set_event_scripts("star_pool",
		[
			{"side": "none", "name": "星映す泉", "text": "泉の水面に、見たこともない星々が揺らめいて映り込んでいる。", "next": 1},
			{"side": "none", "name": "", "text": "水面にそっと手を差し入れると、砕けた星の欠片がそっと掌に収まった。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "星映す泉", "text": "泉の水面に、見たこともない星々が揺らめいて映り込んでいる。", "next": 1},
			{"side": "none", "name": "", "text": "水面は揺らぐばかりで、何も掴むことはできなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("sealed_garden_vault",
		[
			{"side": "none", "name": "封じられた庭園の蔵", "text": "蔦に覆われた小さな蔵。鍵穴の代わりに、星形の窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "星の欠片を窪みにはめ込むと、蔦がひとりでにほどけていった。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "封じられた庭園の蔵", "text": "蔦に覆われた小さな蔵。鍵穴の代わりに、星形の窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "窪みに合う物を持たぬ今は、蔦をほどく術がない。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("sky_serpent_nest",
		[
			{"side": "right", "name": "空竜蛇", "text": "庭園の上空で、細長い影がとぐろを巻くように舞い降りてくる。", "next": 1},
			{"side": "none", "name": "", "text": "空竜蛇を退け、巣は再び静けさを取り戻した。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "空竜蛇", "text": "庭園の上空で、細長い影がとぐろを巻くように舞い降りてくる。", "next": 1},
			{"side": "none", "name": "", "text": "素早い動きに翻弄され、退かざるを得なかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("isle_depths",
		[
			{"side": "right", "name": "島影の番人", "text": "島の裏側、影の濃い場所から気配が立ち上る。", "next": 1},
			{"side": "none", "name": "", "text": "番人を退け、その奥に架かる橋を見つけた。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "島影の番人", "text": "島の裏側、影の濃い場所から気配が立ち上る。", "next": 1},
			{"side": "none", "name": "", "text": "影に飲まれかけ、慌てて島の表側へ逃げ戻った。", "outcome": "fail"},
		])

	# --- 鏡影の窪地 ---
	# 漂う小道(drifting_path)から分岐する、進行に必須ではない支線。
	WorldMap.add_node("hollow_mist", "霧のくぼ地", ["drifting_path", "mirror_maze"], {}, "mirror_hollow")
	WorldMap.add_node("mirror_maze", "鏡の迷路", ["hollow_mist", "echo_chamber", "false_reflection", "silent_pool"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3}, "mirror_hollow")
	WorldMap.add_node("echo_chamber", "谺の間", ["mirror_maze"], {"type": "combat", "enemy_power": 360}, "mirror_hollow")
	WorldMap.add_node("false_reflection", "偽りの鏡像", ["mirror_maze"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 3}, "mirror_hollow")
	WorldMap.add_node("silent_pool", "静寂の水底", ["mirror_maze"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 3}, "mirror_hollow")

	WorldMap.set_event_scripts("mirror_maze",
		[
			{"side": "none", "name": "鏡の迷路", "text": "四方を鏡に囲まれ、どちらが本物の道か分からなくなる。", "next": 1},
			{"side": "none", "name": "", "text": "わずかな違和感を頼りに、本物の道筋を見抜いた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "鏡の迷路", "text": "四方を鏡に囲まれ、どちらが本物の道か分からなくなる。", "next": 1},
			{"side": "none", "name": "", "text": "鏡像に惑わされ、同じ場所を巡るばかりだった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("echo_chamber",
		[
			{"side": "right", "name": "影の分身", "text": "谺の間の奥で、もう一人の自分のような影が立ち上がる。", "next": 1},
			{"side": "none", "name": "", "text": "影の分身を打ち破ると、谺だけが静かに残った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "影の分身", "text": "谺の間の奥で、もう一人の自分のような影が立ち上がる。", "next": 1},
			{"side": "none", "name": "", "text": "同じ動きを見切られ、なすすべなく押し返された。", "outcome": "fail"},
		])

	# --- 星幽の聖域 ---
	WorldMap.add_node("sanctum_bridge", "星幽への橋", ["isle_depths", "sanctum_gate"], {}, "astral_sanctum")
	WorldMap.add_node("sanctum_gate", "聖域の門", ["sanctum_bridge", "sanctum_inner"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 5}, "astral_sanctum")
	WorldMap.add_node("sanctum_inner", "聖域の内殿", ["sanctum_gate", "astral_guardian"], {}, "astral_sanctum")
	WorldMap.add_node("astral_guardian", "星幽の守護者", ["sanctum_inner", "astral_heart"], {"type": "combat", "enemy_power": 420}, "astral_sanctum", "astral_core")
	WorldMap.add_node("astral_heart", "星幽の中心", ["astral_guardian"], {"type": "item", "item": "astral_core"}, "astral_sanctum")

	WorldMap.set_event_scripts("sanctum_gate",
		[
			{"side": "none", "name": "聖域の門", "text": "門の表面に、星の巡りを描いたような紋様が浮かんでいる。", "next": 1},
			{"side": "none", "name": "", "text": "星の巡りを読み解くと、門は音もなく開いた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "聖域の門", "text": "門の表面に、星の巡りを描いたような紋様が浮かんでいる。", "next": 1},
			{"side": "none", "name": "", "text": "紋様の意味は掴めず、門は閉ざされたままだった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("astral_guardian",
		[
			{"side": "right", "name": "星幽の守護者", "text": "……何用だ、この地の深奥に至る者よ。", "next": 1},
			{"side": "none", "name": "", "text": "長き戦いの果て、守護者の姿は星屑となって消えた。後には小さな核だけが残った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "星幽の守護者", "text": "……何用だ、この地の深奥に至る者よ。", "next": 1},
			{"side": "none", "name": "", "text": "星屑のような力に押され、内殿の外まで弾き飛ばされた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("astral_heart",
		[
			{"side": "none", "name": "星幽の中心", "text": "中心には、核を収める小さな窪みが静かに浮かんでいる。", "next": 1},
			{"side": "none", "name": "", "text": "星幽の核を捧げると、中心全体が穏やかな光に満たされた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "星幽の中心", "text": "中心には、核を収める小さな窪みが静かに浮かんでいる。", "next": 1},
			{"side": "none", "name": "", "text": "核を持たぬ今は、窪みはただ静かに浮かんでいるだけだった。", "outcome": "fail"},
		])

func _build_moonlit_lake() -> void:
	WorldMap.add_area("moonlit_lake", "月魄の湖")
	WorldMap.add_section("lake_shore", "湖畔", "moonlit_lake")
	WorldMap.add_section("sunken_village", "沈んだ里", "moonlit_lake")
	WorldMap.add_section("reed_maze", "葦の迷路", "moonlit_lake")
	WorldMap.add_section("moon_palace", "月宮", "moonlit_lake")

	# --- 湖畔 ---
	# 隠れ森の郷の月の泉の守護者(moonwell_guardian)を突破すると隣接フロアとして開ける。
	WorldMap.add_node("lake_path", "湖への小道", ["moonwell_guardian", "lake_dock"], {}, "lake_shore")
	WorldMap.add_node("lake_dock", "湖畔の桟橋", ["lake_path", "village_gate", "reed_entrance", "sunken_bell", "drift_wraith"], {}, "lake_shore")
	WorldMap.add_node("sunken_bell", "沈んだ鐘", ["lake_dock"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 3}, "lake_shore")
	WorldMap.add_node("drift_wraith", "漂う亡霊", ["lake_dock"], {"type": "combat", "enemy_power": 400}, "lake_shore")

	WorldMap.set_event_scripts("sunken_bell",
		[
			{"side": "none", "name": "沈んだ鐘", "text": "湖の底から、かすかに鐘の音が響いてくる気がする。", "next": 1},
			{"side": "none", "name": "", "text": "耳を澄ませ続けると、確かに規則正しい鐘の音が聞こえてきた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "沈んだ鐘", "text": "湖の底から、かすかに鐘の音が響いてくる気がする。", "next": 1},
			{"side": "none", "name": "", "text": "聞こえるのはただの水音ばかりで、何も掴めなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("drift_wraith",
		[
			{"side": "right", "name": "漂う亡霊", "text": "桟橋の下から、青白い影がゆらりと浮かび上がる。", "next": 1},
			{"side": "none", "name": "", "text": "漂う亡霊を鎮め、桟橋に静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "漂う亡霊", "text": "桟橋の下から、青白い影がゆらりと浮かび上がる。", "next": 1},
			{"side": "none", "name": "", "text": "冷たい気配に飲まれかけ、慌てて桟橋を後にした。", "outcome": "fail"},
		])

	# --- 沈んだ里 ---
	WorldMap.add_node("village_gate", "沈んだ里の門", ["lake_dock", "drowned_square"], {}, "sunken_village")
	WorldMap.add_node("drowned_square", "沈んだ広場", ["village_gate", "flooded_house", "moonlit_altar", "hidden_cellar", "village_depths"], {}, "sunken_village")
	WorldMap.add_node("flooded_house", "水没した家", ["drowned_square"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 3}, "sunken_village", "moonpearl")
	WorldMap.add_node("moonlit_altar", "月光の祭壇", ["drowned_square"], {"type": "item", "item": "moonpearl"}, "sunken_village")
	WorldMap.add_node("hidden_cellar", "隠された地下室", ["drowned_square"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 3}, "sunken_village")
	WorldMap.add_node("village_depths", "里の奥", ["drowned_square", "palace_stairs"], {"type": "combat", "enemy_power": 440}, "sunken_village", "reclass_elixir")

	WorldMap.set_event_scripts("flooded_house",
		[
			{"side": "none", "name": "水没した家", "text": "傾いた家の奥に、固く閉ざされた木箱が沈んでいる。", "next": 1},
			{"side": "none", "name": "", "text": "箱をこじ開けると、月光を宿したような真珠がひとつ入っていた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "水没した家", "text": "傾いた家の奥に、固く閉ざされた木箱が沈んでいる。", "next": 1},
			{"side": "none", "name": "", "text": "錠は固く、こじ開けることはできなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("moonlit_altar",
		[
			{"side": "none", "name": "月光の祭壇", "text": "広場の中央、水面から突き出た祭壇に真珠を置く窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "月の真珠を捧げると、祭壇が淡い光を放ち始めた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "月光の祭壇", "text": "広場の中央、水面から突き出た祭壇に真珠を置く窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "真珠を持たぬ今は、窪みはただ乾いたままだった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("village_depths",
		[
			{"side": "right", "name": "里を守る影", "text": "沈んだ里の奥から、無数の影がゆっくりと集まってくる。", "next": 1},
			{"side": "none", "name": "", "text": "影たちを鎮め、里の奥への道が開けた。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "里を守る影", "text": "沈んだ里の奥から、無数の影がゆっくりと集まってくる。", "next": 1},
			{"side": "none", "name": "", "text": "影の群れに押し返され、広場まで逃げ戻った。", "outcome": "fail"},
		])

	# --- 葦の迷路 ---
	# 湖畔の桟橋(lake_dock)から分岐する、進行に必須ではない支線。
	WorldMap.add_node("reed_entrance", "葦原の入口", ["lake_dock", "reed_paths"], {}, "reed_maze")
	WorldMap.add_node("reed_paths", "葦の小道", ["reed_entrance", "will_o_wisp", "hidden_skiff", "reed_depths"], {}, "reed_maze")
	WorldMap.add_node("will_o_wisp", "鬼火の群れ", ["reed_paths"], {"type": "combat", "enemy_power": 420}, "reed_maze")
	WorldMap.add_node("hidden_skiff", "隠された小舟", ["reed_paths"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 3}, "reed_maze")
	WorldMap.add_node("reed_depths", "葦の最奥", ["reed_paths"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3}, "reed_maze")

	WorldMap.set_event_scripts("will_o_wisp",
		[
			{"side": "right", "name": "鬼火の群れ", "text": "葦の合間を、青白い火の玉がいくつも漂っている。", "next": 1},
			{"side": "none", "name": "", "text": "鬼火を打ち払うと、葦原に静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "鬼火の群れ", "text": "葦の合間を、青白い火の玉がいくつも漂っている。", "next": 1},
			{"side": "none", "name": "", "text": "惑わされて道を見失い、入口まで引き返した。", "outcome": "fail"},
		])

	# --- 月宮 ---
	WorldMap.add_node("palace_stairs", "月宮への階段", ["village_depths", "palace_hall"], {}, "moon_palace")
	WorldMap.add_node("palace_hall", "月宮の広間", ["palace_stairs", "moon_throne"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 5}, "moon_palace")
	WorldMap.add_node("moon_throne", "月姫の玉座", ["palace_hall", "palace_vault"], {"type": "combat", "enemy_power": 480}, "moon_palace", "moonsoul_crown")
	WorldMap.add_node("palace_vault", "秘宝の間", ["moon_throne"], {"type": "item", "item": "moonsoul_crown"}, "moon_palace")

	WorldMap.set_event_scripts("palace_hall",
		[
			{"side": "none", "name": "月宮の広間", "text": "広間の壁一面に、満ち欠けを描いた月の紋様が刻まれている。", "next": 1},
			{"side": "none", "name": "", "text": "月の満ち欠けの順序を読み解くと、奥の扉が静かに開いた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "月宮の広間", "text": "広間の壁一面に、満ち欠けを描いた月の紋様が刻まれている。", "next": 1},
			{"side": "none", "name": "", "text": "紋様の並びの意味は掴めず、扉は閉ざされたままだった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("moon_throne",
		[
			{"side": "right", "name": "月姫", "text": "……久方ぶりだ。この宮を訪れる者があろうとは。", "next": 1},
			{"side": "none", "name": "", "text": "壮絶な戦いの末、月姫の姿は水面に溶けるように消え、冠だけが残された。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "月姫", "text": "……久方ぶりだ。この宮を訪れる者があろうとは。", "next": 1},
			{"side": "none", "name": "", "text": "月姫の力は底知れず、命からがら広間まで退いた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("palace_vault",
		[
			{"side": "none", "name": "秘宝の間", "text": "奥の台座に、冠を戴く窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "月魄の冠を捧げると、間全体が満月の光に包まれた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "秘宝の間", "text": "奥の台座に、冠を戴く窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "冠を持たぬ今は、台座はただ静まり返っている。", "outcome": "fail"},
		])

func _build_fae_hollow() -> void:
	WorldMap.add_area("fae_hollow", "妖精の隠れ里")
	WorldMap.add_section("hollow_entrance", "隠れ里の入口", "fae_hollow")
	WorldMap.add_section("mushroom_glade", "茸の群生地", "fae_hollow")
	WorldMap.add_section("trickster_maze", "悪戯妖精の迷路", "fae_hollow")
	WorldMap.add_section("fae_court", "妖精の宮廷", "fae_hollow")

	# --- 隠れ里の入口 ---
	# ささやきの森の古井戸(old_well、ゲートなしの行き止まり)を通ると隣接フロアとして開ける。
	WorldMap.add_node("well_shaft", "井戸の縦坑", ["old_well", "hollow_floor"], {}, "hollow_entrance")
	WorldMap.add_node("hollow_floor", "隠れ里の床", ["well_shaft", "glade_path", "maze_path", "sleeping_pixie", "moss_ring"], {}, "hollow_entrance")
	WorldMap.add_node("sleeping_pixie", "眠るピクシー", ["hollow_floor"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 2}, "hollow_entrance")
	WorldMap.add_node("moss_ring", "苔の輪", ["hollow_floor"], {"type": "combat", "enemy_power": 460}, "hollow_entrance")

	WorldMap.set_event_scripts("sleeping_pixie",
		[
			{"side": "none", "name": "眠るピクシー", "text": "床の隅、苔の上で小さな羽の生えた何かがすやすやと眠っている。", "next": 1},
			{"side": "none", "name": "", "text": "起こさないようそっと見守り、静かにその場を離れた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "眠るピクシー", "text": "床の隅、苔の上で小さな羽の生えた何かがすやすやと眠っている。", "next": 1},
			{"side": "none", "name": "", "text": "薄暗がりの中では、それが苔の塊にしか見えなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("moss_ring",
		[
			{"side": "right", "name": "苔の輪の番人", "text": "円状に生えた苔の輪から、小さな緑色の何かが飛び出してくる。", "next": 1},
			{"side": "none", "name": "", "text": "取るに足らない相手を追い払い、苔の輪は静かになった。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "苔の輪の番人", "text": "円状に生えた苔の輪から、小さな緑色の何かが飛び出してくる。", "next": 1},
			{"side": "none", "name": "", "text": "意外なすばしっこさに翻弄され、退かざるを得なかった。", "outcome": "fail"},
		])

	# --- 茸の群生地 ---
	WorldMap.add_node("glade_path", "茸への小道", ["hollow_floor", "glade_clearing"], {}, "mushroom_glade")
	WorldMap.add_node("glade_clearing", "茸の群生地", ["glade_path", "giant_toadstool", "toadstool_ring", "glade_depths"], {}, "mushroom_glade")
	WorldMap.add_node("giant_toadstool", "巨大な茸", ["glade_clearing"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 2}, "mushroom_glade", "fae_dust")
	WorldMap.add_node("toadstool_ring", "茸の輪", ["glade_clearing"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 2}, "mushroom_glade")
	WorldMap.add_node("glade_depths", "群生地の奥", ["glade_clearing", "court_gate"], {"type": "combat", "enemy_power": 500}, "mushroom_glade", "reclass_elixir")

	WorldMap.set_event_scripts("giant_toadstool",
		[
			{"side": "none", "name": "巨大な茸", "text": "見上げるほどの茸が一本、傘を大きく広げて立っている。", "next": 1},
			{"side": "none", "name": "", "text": "傘を叩き割ると、きらきらと輝く粉塵が舞い散った。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "巨大な茸", "text": "見上げるほどの茸が一本、傘を大きく広げて立っている。", "next": 1},
			{"side": "none", "name": "", "text": "茸は思いのほか頑丈で、びくともしなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("glade_depths",
		[
			{"side": "right", "name": "群生地の番人", "text": "群生地の奥から、大きな蜘蛛のような影が這い出してくる。", "next": 1},
			{"side": "none", "name": "", "text": "番人を退け、宮廷へ続く道が開けた。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "群生地の番人", "text": "群生地の奥から、大きな蜘蛛のような影が這い出してくる。", "next": 1},
			{"side": "none", "name": "", "text": "糸に絡め取られかけ、慌てて群生地の入口まで戻った。", "outcome": "fail"},
		])

	# --- 悪戯妖精の迷路 ---
	# 隠れ里の床(hollow_floor)から分岐する、進行に必須ではない支線。
	WorldMap.add_node("maze_path", "悪戯妖精への道", ["hollow_floor", "maze_heart"], {}, "trickster_maze")
	WorldMap.add_node("maze_heart", "迷路の中心", ["maze_path", "riddling_sprite", "illusive_door", "maze_depths"], {}, "trickster_maze")
	WorldMap.add_node("riddling_sprite", "謎かけの妖精", ["maze_heart"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3}, "trickster_maze")
	WorldMap.add_node("illusive_door", "幻影の扉", ["maze_heart"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 3}, "trickster_maze")
	WorldMap.add_node("maze_depths", "迷路の最奥", ["maze_heart"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 2}, "trickster_maze")

	WorldMap.set_event_scripts("riddling_sprite",
		[
			{"side": "left", "name": "謎かけの妖精", "text": "「三つの謎を解けたら、面白いものを見せてやろう」小さな妖精がにやりと笑う。", "next": 1},
			{"side": "none", "name": "", "text": "すべての謎を解き明かすと、妖精は満足げに小さな道を示した。", "outcome": "pass"},
		],
		[
			{"side": "left", "name": "謎かけの妖精", "text": "「三つの謎を解けたら、面白いものを見せてやろう」小さな妖精がにやりと笑う。", "next": 1},
			{"side": "none", "name": "", "text": "「つまらん」妖精はそう言うと、姿を消してしまった。", "outcome": "fail"},
		])

	# --- 妖精の宮廷 ---
	WorldMap.add_node("court_gate", "宮廷の門", ["glade_depths", "court_hall"], {}, "fae_court")
	WorldMap.add_node("court_hall", "妖精の宮廷", ["court_gate", "fae_queen"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 4}, "fae_court")
	WorldMap.add_node("fae_queen", "妖精女王", ["court_hall", "court_treasury"], {"type": "combat", "enemy_power": 540}, "fae_court", "queens_favor")
	WorldMap.add_node("court_treasury", "宮廷の宝物庫", ["fae_queen"], {"type": "item", "item": "queens_favor"}, "fae_court")

	WorldMap.set_event_scripts("court_hall",
		[
			{"side": "none", "name": "妖精の宮廷", "text": "宮廷の門番たちが、来訪者に気の利いた受け答えを求めているようだ。", "next": 1},
			{"side": "none", "name": "", "text": "見事な受け答えに、門番たちは道を譲った。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "妖精の宮廷", "text": "宮廷の門番たちが、来訪者に気の利いた受け答えを求めているようだ。", "next": 1},
			{"side": "none", "name": "", "text": "気の利いた言葉が出ず、門番たちに追い返された。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("fae_queen",
		[
			{"side": "right", "name": "妖精女王", "text": "……ほう、ここまで辿り着くとはな。相応の資格があるか、見せてもらおう。", "next": 1},
			{"side": "none", "name": "", "text": "女王との激しい鍔迫り合いの末、その笑みとともに寵愛の証を授けられた。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "妖精女王", "text": "……ほう、ここまで辿り着くとはな。相応の資格があるか、見せてもらおう。", "next": 1},
			{"side": "none", "name": "", "text": "女王の圧倒的な力の前に、なすすべなく退いた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("court_treasury",
		[
			{"side": "none", "name": "宮廷の宝物庫", "text": "宝物庫の扉には、女王の紋章を象った窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "寵愛の証を窪みにかざすと、扉は静かに開いた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "宮廷の宝物庫", "text": "宝物庫の扉には、女王の紋章を象った窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "証を持たぬ今は、扉はぴくりとも動かなかった。", "outcome": "fail"},
		])

func _build_crystalline_depths() -> void:
	WorldMap.add_area("crystalline_depths", "結晶の深淵")
	WorldMap.add_section("crystal_descent", "結晶への降下路", "crystalline_depths")
	WorldMap.add_section("geode_hollows", "晶洞の窪み", "crystalline_depths")
	WorldMap.add_section("resonance_halls", "共鳴の回廊", "crystalline_depths")
	WorldMap.add_section("crystal_throne", "結晶の玉座", "crystalline_depths")

	# --- 結晶への降下路 ---
	# 灰色の山嶺・廃坑の結晶洞(crystal_cavern)を突破すると隣接フロアとして開ける。
	WorldMap.add_node("descent_path", "降下路", ["crystal_cavern", "crystal_floor"], {}, "crystal_descent")
	WorldMap.add_node("crystal_floor", "結晶の床", ["descent_path", "geode_path", "resonance_path", "glowing_vein", "faint_tremor"], {}, "crystal_descent")
	WorldMap.add_node("glowing_vein", "光る鉱脈", ["crystal_floor"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 3}, "crystal_descent")
	WorldMap.add_node("faint_tremor", "微かな震え", ["crystal_floor"], {"type": "combat", "enemy_power": 520}, "crystal_descent")

	WorldMap.set_event_scripts("glowing_vein",
		[
			{"side": "none", "name": "光る鉱脈", "text": "壁の奥に、淡く脈打つように光る鉱脈が走っているのが見える。", "next": 1},
			{"side": "none", "name": "", "text": "鉱脈の輝きを目で追ううちに、床の奥へと続く隙間を見つけた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "光る鉱脈", "text": "壁の奥に、淡く脈打つように光る鉱脈が走っているのが見える。", "next": 1},
			{"side": "none", "name": "", "text": "ただの岩壁にしか見えず、何も見つけられなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("faint_tremor",
		[
			{"side": "right", "name": "結晶の欠片獣", "text": "床の結晶片が、意思を持つようにかたかたと震え出す。", "next": 1},
			{"side": "none", "name": "", "text": "欠片獣を鎮め、床は再び静けさを取り戻した。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "結晶の欠片獣", "text": "床の結晶片が、意思を持つようにかたかたと震え出す。", "next": 1},
			{"side": "none", "name": "", "text": "鋭い欠片に手を焼き、やむなく引き返した。", "outcome": "fail"},
		])

	# --- 晶洞の窪み ---
	WorldMap.add_node("geode_path", "晶洞への道", ["crystal_floor", "geode_chamber"], {}, "geode_hollows")
	WorldMap.add_node("geode_chamber", "晶洞の間", ["geode_path", "cracked_geode", "crystal_spiders", "prismatic_pool", "geode_depths"], {}, "geode_hollows")
	WorldMap.add_node("cracked_geode", "割れた晶洞", ["geode_chamber"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 3}, "geode_hollows", "resonant_shard")
	WorldMap.add_node("crystal_spiders", "結晶蜘蛛の巣", ["geode_chamber"], {"type": "combat", "enemy_power": 560}, "geode_hollows", "reclass_elixir")
	WorldMap.add_node("prismatic_pool", "虹色の水溜まり", ["geode_chamber"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 3}, "geode_hollows")
	WorldMap.add_node("geode_depths", "晶洞の奥", ["geode_chamber", "throne_path"], {"type": "item", "item": "resonant_shard"}, "geode_hollows")

	WorldMap.set_event_scripts("cracked_geode",
		[
			{"side": "none", "name": "割れた晶洞", "text": "大きな晶洞が一つ、うっすらとひびの入った状態で転がっている。", "next": 1},
			{"side": "none", "name": "", "text": "晶洞を打ち割ると、中から共鳴する欠片が転がり出た。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "割れた晶洞", "text": "大きな晶洞が一つ、うっすらとひびの入った状態で転がっている。", "next": 1},
			{"side": "none", "name": "", "text": "晶洞は硬く、ひびを広げることすらできなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("crystal_spiders",
		[
			{"side": "right", "name": "結晶蜘蛛", "text": "透き通った脚を持つ蜘蛛の群れが、巣の奥から這い出してくる。", "next": 1},
			{"side": "none", "name": "", "text": "結晶蜘蛛を退け、晶洞の間に静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "結晶蜘蛛", "text": "透き通った脚を持つ蜘蛛の群れが、巣の奥から這い出してくる。", "next": 1},
			{"side": "none", "name": "", "text": "鋭い脚に阻まれ、なすすべなく退いた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("geode_depths",
		[
			{"side": "none", "name": "晶洞の奥", "text": "奥の壁面に、欠片を嵌め込むような窪みが並んでいる。", "next": 1},
			{"side": "none", "name": "", "text": "共鳴する欠片を窪みにはめ込むと、壁面全体が震えるように鳴り響き、道が開けた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "晶洞の奥", "text": "奥の壁面に、欠片を嵌め込むような窪みが並んでいる。", "next": 1},
			{"side": "none", "name": "", "text": "窪みに合う物を持たぬ今は、壁は沈黙したままだった。", "outcome": "fail"},
		])

	# --- 共鳴の回廊 ---
	# 結晶の床(crystal_floor)から分岐する、進行に必須ではない支線。
	WorldMap.add_node("resonance_path", "共鳴への道", ["crystal_floor", "resonance_hall"], {}, "resonance_halls")
	WorldMap.add_node("resonance_hall", "共鳴の回廊", ["resonance_path", "humming_crystal", "shattering_echo", "resonance_depths"], {}, "resonance_halls")
	WorldMap.add_node("humming_crystal", "唸る結晶", ["resonance_hall"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3}, "resonance_halls")
	WorldMap.add_node("shattering_echo", "砕ける谺", ["resonance_hall"], {"type": "combat", "enemy_power": 540}, "resonance_halls")
	WorldMap.add_node("resonance_depths", "共鳴の最奥", ["resonance_hall"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 3}, "resonance_halls")

	WorldMap.set_event_scripts("shattering_echo",
		[
			{"side": "right", "name": "砕ける谺", "text": "回廊の奥で、音そのものが形を成したような何かが唸る。", "next": 1},
			{"side": "none", "name": "", "text": "谺を打ち払うと、回廊に本来の静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "砕ける谺", "text": "回廊の奥で、音そのものが形を成したような何かが唸る。", "next": 1},
			{"side": "none", "name": "", "text": "耳を劈く音の奔流に押され、退かざるを得なかった。", "outcome": "fail"},
		])

	# --- 結晶の玉座 ---
	WorldMap.add_node("throne_path", "玉座への道", ["geode_depths", "throne_hall"], {}, "crystal_throne")
	WorldMap.add_node("throne_hall", "結晶の広間", ["throne_path", "crystal_monarch"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 4}, "crystal_throne")
	WorldMap.add_node("crystal_monarch", "結晶の王", ["throne_hall", "throne_vault"], {"type": "combat", "enemy_power": 600}, "crystal_throne", "heart_of_crystal")
	WorldMap.add_node("throne_vault", "王の秘宝庫", ["crystal_monarch"], {"type": "item", "item": "heart_of_crystal"}, "crystal_throne")

	WorldMap.set_event_scripts("throne_hall",
		[
			{"side": "none", "name": "結晶の広間", "text": "広間の床一面に、幾何学的な結晶の紋様が広がっている。", "next": 1},
			{"side": "none", "name": "", "text": "紋様の規則性を読み解くと、奥の間へ続く道が静かに現れた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "結晶の広間", "text": "広間の床一面に、幾何学的な結晶の紋様が広がっている。", "next": 1},
			{"side": "none", "name": "", "text": "紋様の規則は掴めず、道は現れなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("crystal_monarch",
		[
			{"side": "right", "name": "結晶の王", "text": "……何者だ、この深奥まで辿り着くとは。", "next": 1},
			{"side": "none", "name": "", "text": "死闘の末、結晶の王の体は砕け散り、脈打つ結晶の心臓だけが残った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "結晶の王", "text": "……何者だ、この深奥まで辿り着くとは。", "next": 1},
			{"side": "none", "name": "", "text": "結晶の王の力は底知れず、なすすべなく広間まで退いた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("throne_vault",
		[
			{"side": "none", "name": "王の秘宝庫", "text": "奥の台座に、心臓を収める窪みが静かに脈打っている。", "next": 1},
			{"side": "none", "name": "", "text": "結晶の心臓を捧げると、秘宝庫全体が眩い光に満たされた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "王の秘宝庫", "text": "奥の台座に、心臓を収める窪みが静かに脈打っている。", "next": 1},
			{"side": "none", "name": "", "text": "心臓を持たぬ今は、窪みはただ静かに沈黙している。", "outcome": "fail"},
		])

func _build_inferno_crater() -> void:
	WorldMap.add_area("inferno_crater", "業火の火口")
	WorldMap.add_section("caldera_rim", "火口の縁", "inferno_crater")
	WorldMap.add_section("obsidian_flats", "黒曜石の平原", "inferno_crater")
	WorldMap.add_section("ember_tunnels", "燠火の坑道", "inferno_crater")
	WorldMap.add_section("molten_forge", "溶鉱の鍛冶場", "inferno_crater")
	WorldMap.add_section("inferno_heart", "業火の中心", "inferno_crater")

	# --- 火口の縁 ---
	# 灰色の山嶺・竜の尖塔の灰塵の間(ash_chamber)を突破すると隣接フロアとして開ける。
	WorldMap.add_node("rim_path", "火口縁への道", ["ash_chamber", "rim_overlook"], {}, "caldera_rim")
	WorldMap.add_node("rim_overlook", "火口を見渡す岸", ["rim_path", "obsidian_path", "ember_path", "heat_shimmer", "ash_drift", "cracked_ridge"], {}, "caldera_rim")
	WorldMap.add_node("heat_shimmer", "陽炎の揺らぎ", ["rim_overlook"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 4}, "caldera_rim")
	WorldMap.add_node("ash_drift", "灰の吹き溜まり", ["rim_overlook"], {"type": "combat", "enemy_power": 540}, "caldera_rim")
	WorldMap.add_node("cracked_ridge", "罅割れた尾根", ["rim_overlook"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 3}, "caldera_rim")

	WorldMap.set_event_scripts("heat_shimmer",
		[
			{"side": "none", "name": "陽炎の揺らぎ", "text": "熱気で景色が揺らめく先に、何か人工的な輪郭が見え隠れしている気がする。", "next": 1},
			{"side": "none", "name": "", "text": "揺らぎの奥に、確かに削られた道の跡を見つけた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "陽炎の揺らぎ", "text": "熱気で景色が揺らめく先に、何か人工的な輪郭が見え隠れしている気がする。", "next": 1},
			{"side": "none", "name": "", "text": "熱気に阻まれ、揺らめく景色以外は何も見えなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("ash_drift",
		[
			{"side": "right", "name": "灰の小鬼", "text": "灰の吹き溜まりから、小さな炎をまとった影がいくつも飛び出してくる。", "next": 1},
			{"side": "none", "name": "", "text": "灰の小鬼たちを退け、吹き溜まりは静かになった。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "灰の小鬼", "text": "灰の吹き溜まりから、小さな炎をまとった影がいくつも飛び出してくる。", "next": 1},
			{"side": "none", "name": "", "text": "熱い灰に阻まれ、やむなく退いた。", "outcome": "fail"},
		])

	# --- 黒曜石の平原 ---
	WorldMap.add_node("obsidian_path", "黒曜石への道", ["rim_overlook", "obsidian_field"], {}, "obsidian_flats")
	WorldMap.add_node("obsidian_field", "黒曜石の平原", ["obsidian_path", "shattered_pillar", "glass_maze", "field_depths", "forge_path"], {}, "obsidian_flats")
	WorldMap.add_node("shattered_pillar", "砕けた石柱", ["obsidian_field", "sealed_kiln"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 3}, "obsidian_flats", "obsidian_shard")
	WorldMap.add_node("sealed_kiln", "封じられた窯", ["shattered_pillar"], {"type": "item", "item": "obsidian_shard"}, "obsidian_flats")
	WorldMap.add_node("glass_maze", "硝子の迷路", ["obsidian_field"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 3}, "obsidian_flats")
	WorldMap.add_node("field_depths", "平原の奥", ["obsidian_field"], {"type": "combat", "enemy_power": 600}, "obsidian_flats")
	WorldMap.add_node("forge_path", "溶鉱への道", ["obsidian_field", "forge_floor"], {}, "obsidian_flats")

	WorldMap.set_event_scripts("shattered_pillar",
		[
			{"side": "none", "name": "砕けた石柱", "text": "黒曜石でできた石柱が一本、ひび割れながらも立っている。", "next": 1},
			{"side": "none", "name": "", "text": "石柱を打ち崩すと、鋭く輝く黒曜石の欠片が転がり出た。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "砕けた石柱", "text": "黒曜石でできた石柱が一本、ひび割れながらも立っている。", "next": 1},
			{"side": "none", "name": "", "text": "石柱は硬く、ひびを広げることすらできなかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("sealed_kiln",
		[
			{"side": "none", "name": "封じられた窯", "text": "窯の扉に、欠片を嵌め込む窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "黒曜石の欠片をはめ込むと、窯の扉が静かに開いた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "封じられた窯", "text": "窯の扉に、欠片を嵌め込む窪みがある。", "next": 1},
			{"side": "none", "name": "", "text": "窪みに合う物を持たぬ今は、窯は閉ざされたままだった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("field_depths",
		[
			{"side": "right", "name": "黒曜石のゴーレム", "text": "平原の奥、黒曜石でできた巨躯がゆっくりと起き上がる。", "next": 1},
			{"side": "none", "name": "", "text": "ゴーレムを打ち崩し、平原の奥に静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "黒曜石のゴーレム", "text": "平原の奥、黒曜石でできた巨躯がゆっくりと起き上がる。", "next": 1},
			{"side": "none", "name": "", "text": "鋭い破片を撒き散らされ、なすすべなく退いた。", "outcome": "fail"},
		])

	# --- 燠火の坑道 ---
	# 火口を見渡す岸(rim_overlook)から分岐する、進行に必須ではない支線。
	WorldMap.add_node("ember_path", "燠火への道", ["rim_overlook", "ember_hollow"], {}, "ember_tunnels")
	WorldMap.add_node("ember_hollow", "燠火の窪み", ["ember_path", "cinder_wisps", "buried_cache", "ember_depths"], {}, "ember_tunnels")
	WorldMap.add_node("cinder_wisps", "燠火の精", ["ember_hollow"], {"type": "combat", "enemy_power": 560}, "ember_tunnels")
	WorldMap.add_node("buried_cache", "埋もれた蓄え", ["ember_hollow"], {"type": "skill", "skill": SkillTypes.Skill.LOCKPICKING, "min_level": 3}, "ember_tunnels")
	WorldMap.add_node("ember_depths", "燠火の最奥", ["ember_hollow"], {"type": "skill", "skill": SkillTypes.Skill.PERCEPTION, "min_level": 3}, "ember_tunnels")

	WorldMap.set_event_scripts("cinder_wisps",
		[
			{"side": "right", "name": "燠火の精", "text": "窪みの奥で、赤く燃える小さな精霊たちが群れている。", "next": 1},
			{"side": "none", "name": "", "text": "燠火の精を鎮め、窪みに静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "燠火の精", "text": "窪みの奥で、赤く燃える小さな精霊たちが群れている。", "next": 1},
			{"side": "none", "name": "", "text": "飛び散る火の粉に阻まれ、退かざるを得なかった。", "outcome": "fail"},
		])

	# --- 溶鉱の鍛冶場 ---
	WorldMap.add_node("forge_floor", "溶鉱の鍛冶場", ["forge_path", "molten_anvil", "salamander_den", "slag_heap", "forge_depths"], {}, "molten_forge")
	WorldMap.add_node("molten_anvil", "溶鉱の鉄床", ["forge_floor"], {"type": "skill", "skill": SkillTypes.Skill.DESTRUCTION, "min_level": 3}, "molten_forge", "emberforged_ingot")
	WorldMap.add_node("salamander_den", "火蜥蜴の巣", ["forge_floor"], {"type": "combat", "enemy_power": 580}, "molten_forge")
	WorldMap.add_node("slag_heap", "鉱滓の山", ["forge_floor"], {"type": "combat", "enemy_power": 520}, "molten_forge")
	WorldMap.add_node("forge_depths", "鍛冶場の奥", ["forge_floor", "caldera_gate"], {"type": "item", "item": "emberforged_ingot"}, "molten_forge")

	WorldMap.set_event_scripts("molten_anvil",
		[
			{"side": "none", "name": "溶鉱の鉄床", "text": "今なお赤く熱を帯びた鉄床に、鋼の塊が乗せられたままになっている。", "next": 1},
			{"side": "none", "name": "", "text": "鉄床を打つと、鋼塊は形を変えて業火で鍛えられた一塊となった。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "溶鉱の鉄床", "text": "今なお赤く熱を帯びた鉄床に、鋼の塊が乗せられたままになっている。", "next": 1},
			{"side": "none", "name": "", "text": "鉄床はびくともせず、力尽きて諦めた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("salamander_den",
		[
			{"side": "right", "name": "火蜥蜴の群れ", "text": "鍛冶場の隅、真っ赤な鱗をした蜥蜴たちがこちらを睨んでいる。", "next": 1},
			{"side": "none", "name": "", "text": "火蜥蜴たちを退け、鍛冶場に静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "火蜥蜴の群れ", "text": "鍛冶場の隅、真っ赤な鱗をした蜥蜴たちがこちらを睨んでいる。", "next": 1},
			{"side": "none", "name": "", "text": "噴き出す炎に阻まれ、退かざるを得なかった。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("forge_depths",
		[
			{"side": "none", "name": "鍛冶場の奥", "text": "奥の扉には、鋼塊を差し込むような溝が刻まれている。", "next": 1},
			{"side": "none", "name": "", "text": "業火で鍛えた鋼塊を差し込むと、扉は静かに開いた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "鍛冶場の奥", "text": "奥の扉には、鋼塊を差し込むような溝が刻まれている。", "next": 1},
			{"side": "none", "name": "", "text": "溝に合う物を持たぬ今は、扉はぴくりとも動かなかった。", "outcome": "fail"},
		])

	# --- 業火の中心 ---
	WorldMap.add_node("caldera_gate", "火口への門", ["forge_depths", "caldera_floor"], {}, "inferno_heart")
	WorldMap.add_node("caldera_floor", "火口の底", ["caldera_gate", "molten_serpent", "caldera_hall"], {}, "inferno_heart")
	WorldMap.add_node("molten_serpent", "溶岩の大蛇", ["caldera_floor"], {"type": "combat", "enemy_power": 620}, "inferno_heart", "reclass_elixir")
	WorldMap.add_node("caldera_hall", "火口の内殿", ["caldera_floor", "inferno_lord"], {"type": "skill", "skill": SkillTypes.Skill.WISDOM, "min_level": 5}, "inferno_heart")
	WorldMap.add_node("inferno_lord", "業火の王", ["caldera_hall", "inferno_vault"], {"type": "combat", "enemy_power": 660}, "inferno_heart", "heart_of_inferno")
	WorldMap.add_node("inferno_vault", "業火の秘宝庫", ["inferno_lord"], {"type": "item", "item": "heart_of_inferno"}, "inferno_heart")

	WorldMap.set_event_scripts("molten_serpent",
		[
			{"side": "right", "name": "溶岩の大蛇", "text": "火口の底、溶岩そのものが形を成したような大蛇がとぐろを巻く。", "next": 1},
			{"side": "none", "name": "", "text": "大蛇を退け、火口の底に静けさが戻った。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "溶岩の大蛇", "text": "火口の底、溶岩そのものが形を成したような大蛇がとぐろを巻く。", "next": 1},
			{"side": "none", "name": "", "text": "灼熱の体当たりに阻まれ、なすすべなく退いた。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("caldera_hall",
		[
			{"side": "none", "name": "火口の内殿", "text": "内殿の熱は尋常でなく、正しい呼吸の作法を知らねば足を踏み入れられないという。", "next": 1},
			{"side": "none", "name": "", "text": "古の作法を思い出し、灼熱の中を静かに進むことができた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "火口の内殿", "text": "内殿の熱は尋常でなく、正しい呼吸の作法を知らねば足を踏み入れられないという。", "next": 1},
			{"side": "none", "name": "", "text": "作法が分からず、灼熱に耐えきれず引き返した。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("inferno_lord",
		[
			{"side": "right", "name": "業火の王", "text": "……小さき者よ、この炎の中で生き延びられると思うてか。", "next": 1},
			{"side": "none", "name": "", "text": "壮絶な死闘の末、業火の王はついに崩れ、脈打つ炎の心臓だけが残された。", "outcome": "pass"},
		],
		[
			{"side": "right", "name": "業火の王", "text": "……小さき者よ、この炎の中で生き延びられると思うてか。", "next": 1},
			{"side": "none", "name": "", "text": "業火の王の力は底知れず、なすすべなく内殿の外まで押し戻された。", "outcome": "fail"},
		])

	WorldMap.set_event_scripts("inferno_vault",
		[
			{"side": "none", "name": "業火の秘宝庫", "text": "奥の台座に、心臓を収める窪みが静かに脈打つ熱を放っている。", "next": 1},
			{"side": "none", "name": "", "text": "業火の心臓を捧げると、秘宝庫全体が眩い炎の光に満たされた。", "outcome": "pass"},
		],
		[
			{"side": "none", "name": "業火の秘宝庫", "text": "奥の台座に、心臓を収める窪みが静かに脈打つ熱を放っている。", "next": 1},
			{"side": "none", "name": "", "text": "心臓を持たぬ今は、窪みはただ静かに熱を放つのみだった。", "outcome": "fail"},
		])
