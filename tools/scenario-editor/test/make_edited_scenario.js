'use strict';
// デフォルトシナリオを、エディタのロジック(public/worldlogic.js)で編集した結果を、シナリオのフォルダとして書き出す。
// ゲーム本体が、エディタの書いたworld.jsonを読めて、遊べるかを確かめる(tools/dev/sim_map_edit.gd)ための前処理。
//   node test/make_edited_scenario.js <シナリオの置き場(カスタムのルート)>
// <置き場>/edited/ にシナリオを、<置き場>/edited_expected.json に「読み込んだ結果はこうなるはず」を書く。
const fs = require('fs');
const path = require('path');
const W = require('../public/worldlogic.js');
const L = require('../public/logic.js');

const root = process.argv[2];
if (!root) { console.error('使い方: node make_edited_scenario.js <シナリオの置き場>'); process.exit(1); }
const DEFAULT_DIR = path.resolve(__dirname, '..', '..', '..', 'godot', 'scenarios', 'default');
const out = path.join(root, 'edited');
fs.rmSync(out, { recursive: true, force: true });
fs.cpSync(DEFAULT_DIR, out, { recursive: true });

const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const writeJson = (p, data) => fs.writeFileSync(p, JSON.stringify(data, null, 2) + '\n');
const saved = readJson(path.join(out, 'world.json'));
const events = fs.readdirSync(path.join(out, 'events')).filter((f) => f.endsWith('.json')).map((f) => readJson(path.join(out, 'events', f)));
const d = W.startDraft(saved);

// --- 編集(エディタの操作と同じ関数) ---
const ok = (r) => { if (r && r.error) throw new Error(r.error); return r; };
ok(W.addArea(d, { id: 'smoke_area', name: '試験エリア' }));
ok(W.addSection(d, 'smoke_area', { id: 'smoke_section', name: '試験セクション' }));
ok(W.addFloor(d, 'smoke_section', { id: 'smoke_a', name: '試験の入口', connectTo: 'village' }));
ok(W.addFloor(d, 'smoke_section', { id: 'smoke_b', name: '技能の間', connectTo: 'smoke_a' }));
ok(W.addFloor(d, 'smoke_section', { id: 'smoke_c', name: '鍵の間', connectTo: 'smoke_b' }));
ok(W.addFloor(d, 'smoke_section', { id: 'smoke_d', name: '血筋の間', connectTo: 'smoke_c' }));
ok(W.addItem(d, { id: 'smoke_key', name: '試験の鍵' }));
W.find(d, 'floor', 'smoke_a').gate = W.defaultGate('combat'); // 敵の戦闘力30
W.find(d, 'floor', 'smoke_b').gate = { type: 'skill', skill: 'LOCKPICKING', min_level: 2 };
W.find(d, 'floor', 'smoke_b').item_reward = 'smoke_key';
W.find(d, 'floor', 'smoke_c').gate = { type: 'item', item: 'smoke_key' };
W.find(d, 'floor', 'smoke_d').gate = { type: 'innate_trait', trait: 'bloodline', value: '王家の落胤' };
W.find(d, 'floor', 'smoke_d').item_reward = 'reclass_elixir';
// IDの変更(接続・アイテム・イベントへ波及する)
assert(W.renameId(d, 'floor', 'old_shrine', 'renamed_shrine') === null);
assert(W.renameId(d, 'item', 'goblin_amulet', 'amulet_x') === null);
// 並べ替え
const firstArea = d.areas[0].id;
W.moveArea(d, d.areas[1].id, -1); // 2番目のエリアを先頭へ
const kingdomSections = W.sectionsIn(d, 'kingdom').map((s) => s.id);
W.moveSection(d, kingdomSections[0], +1);
const caveFloors = W.floorsIn(d, 'old_cave_dungeon').map((n) => n.id);
W.moveFloor(d, caveFloors[0], +1);
// 別のセクションへの移動と、削除
W.moveFloorToSection(d, 'renamed_shrine', 'village_area');
const deletedSection = W.sectionsIn(d, 'kingdom').find((s) => s.id === 'noble_quarter') ? 'noble_quarter' : kingdomSections[kingdomSections.length - 1];
W.deleteEntity(d, 'section', deletedSection);

function assert(cond) { if (!cond) throw new Error('編集に失敗'); }

// --- 保存(サーバーと同じ書式で書く) ---
const changed = W.remapEvents(events, W.diffIds(saved, d)).map(L.canonicalEvent);
for (const ev of changed) writeJson(path.join(out, 'events', `${ev.id}.json`), ev);
const world = W.canonicalWorld(d);
writeJson(path.join(out, 'world.json'), world);
const meta = readJson(path.join(out, 'scenario.json'));
writeJson(path.join(out, 'scenario.json'), { ...meta, id: 'edited', name: '編集済みシナリオ' });

// --- 「ゲームが読んだ結果はこうなるはず」 ---
const expected = {
  areas: world.areas.map((a) => a.id),
  sections_by_area: Object.fromEntries(world.areas.map((a) => [a.id, world.sections.filter((s) => s.area === a.id).map((s) => s.id)])),
  floors_by_section: Object.fromEntries(world.sections.map((s) => [s.id, world.nodes.filter((n) => n.section === s.id).map((n) => n.id)])),
  connections: Object.fromEntries(world.nodes.map((n) => [n.id, n.connections])),
  node_count: world.nodes.length,
  items: world.items.map((i) => i.id),
  deleted_section: deletedSection,
  deleted_floors: saved.nodes.filter((n) => n.section === deletedSection).map((n) => n.id),
  changed_events: changed.map((e) => e.id),
  gate_event_floor: 'renamed_shrine',
  first_area_before: firstArea,
};
writeJson(path.join(root, 'edited_expected.json'), expected);
console.log(`書き出しました: ${out}(フロア${world.nodes.length}、書き換えたイベント${changed.length}本、削除したセクション ${deletedSection})`);
