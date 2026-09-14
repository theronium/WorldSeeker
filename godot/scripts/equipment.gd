class_name Equipment
# 装備(武器・防具)の材質等級・種類の静的定義。design.md 6.2節。SkillTypesと同じ静的定義パターン。
#
# 価格・戦闘力補正は材質等級のみで決まり、種類(Jobs.WeaponType/ArmorCategory)は
# ジョブの装備適性を分けるためだけの軸(design.md 6.2「種類(ジョブ適性)の軸」参照)。

enum Tier { WOOD, BRONZE, IRON, STEEL, MITHRIL, ORICHALCUM }

const TIER_NAMES := {
	Tier.WOOD: "木",
	Tier.BRONZE: "青銅",
	Tier.IRON: "鉄",
	Tier.STEEL: "鋼",
	Tier.MITHRIL: "ミスリル",
	Tier.ORICHALCUM: "オリハルコン",
}

const TIER_POWER := {
	Tier.WOOD: 5,
	Tier.BRONZE: 15,
	Tier.IRON: 30,
	Tier.STEEL: 50,
	Tier.MITHRIL: 80,
	Tier.ORICHALCUM: 130,
}

const TIER_PRICE := {
	Tier.WOOD: 80,
	Tier.BRONZE: 180,
	Tier.IRON: 390,
	Tier.STEEL: 850,
	Tier.MITHRIL: 1900,
	Tier.ORICHALCUM: 4100,
}

const WEAPON_TYPE_NAMES := {
	Jobs.WeaponType.SWORD: "剣",
	Jobs.WeaponType.GREAT_HAMMER: "大槌",
	Jobs.WeaponType.DAGGER: "短剣",
	Jobs.WeaponType.STAFF: "杖",
	Jobs.WeaponType.BOW: "弓",
}

const ARMOR_CATEGORY_NAMES := {
	Jobs.ArmorCategory.HEAVY: "重装備",
	Jobs.ArmorCategory.LIGHT: "軽装備",
	Jobs.ArmorCategory.ROBE: "法衣",
}

static func all_tiers() -> Array:
	return Tier.values()

static func power_bonus(tier: int) -> int:
	return TIER_POWER.get(tier, 0)

static func price(tier: int) -> int:
	return TIER_PRICE.get(tier, 0)

## 表示用アイテム名。例: item_name(Tier.BRONZE, "剣") -> "青銅の剣"
static func item_name(tier: int, kind_display_name: String) -> String:
	return "%sの%s" % [TIER_NAMES.get(tier, "?"), kind_display_name]
