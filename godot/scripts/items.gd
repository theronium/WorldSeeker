extends Node
# アイテムの定義とNPCの所持品を管理する最小限のシステム。
# 「特定アイテムの所持」ゲート(5.3節)を満たすためだけの、シンプルな所持判定。

var definitions: Dictionary = {} # item_id -> {id, name}

func define(id: String, display_name: String) -> void:
	definitions[id] = {"id": id, "name": display_name}

func name_of(id: String) -> String:
	return definitions[id]["name"] if definitions.has(id) else id

func grant(npc_id: int, item_id: String) -> void:
	var npc := Npcs.get_npc(npc_id)
	if npc.is_empty() or npc["inventory"].has(item_id):
		return
	npc["inventory"].append(item_id)

func has_item(npc_id: int, item_id: String) -> bool:
	return Npcs.get_npc(npc_id).get("inventory", []).has(item_id)

## ワールドスキーマの再構築前に呼ぶ(world_schema_db.gdのimport_into_worldmap())。
## define()は上書きのみで削除はしないため、これを呼ばずに別バージョンを読み込むと、
## 前のバージョンにしかないアイテム定義が残ってしまう。
func reset() -> void:
	definitions = {}
