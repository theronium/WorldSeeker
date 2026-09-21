'use strict';
// node --test test/  で実行する。マップ(world.json)の編集ロジックを、実際のデフォルトシナリオで確かめる。
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const W = require('../public/worldlogic.js');

const DEFAULT_DIR = path.resolve(__dirname, '..', '..', '..', 'godot', 'scenarios', 'default');
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const world = readJson(path.join(DEFAULT_DIR, 'world.json'));
const events = fs.readdirSync(path.join(DEFAULT_DIR, 'events')).filter((f) => f.endsWith('.json')).sort()
  .map((f) => readJson(path.join(DEFAULT_DIR, 'events', f)));
const draftOf = () => W.startDraft(world);

test('デフォルトのマップ: 保存し直しても、ファイルの中身が1バイトも変わらない(Gitの差分が出ない)', () => {
  const raw = fs.readFileSync(path.join(DEFAULT_DIR, 'world.json'), 'utf8').split(String.fromCharCode(13, 10)).join('\n');
  assert.strictEqual(JSON.stringify(W.canonicalWorld(W.startDraft(JSON.parse(raw))), null, 2) + '\n', raw);
});

test('デフォルトのマップ: 検証でエラーも警告も出ない', () => {
  assert.deepStrictEqual(W.validateWorld(draftOf(), { events }).map((i) => `${i.level}: ${i.msg}`), []);
});

test('フロアの追加: 双方向につながり、同じセクションの並びの末尾に入る', () => {
  const d = draftOf();
  const before = W.floorsIn(d, 'old_cave_dungeon').map((n) => n.id);
  const r = W.addFloor(d, 'old_cave_dungeon', { id: 'new_room', name: '新しい部屋', connectTo: before[0] });
  assert.ok(r.entity);
  assert.deepStrictEqual(W.floorsIn(d, 'old_cave_dungeon').map((n) => n.id), [...before, 'new_room']);
  assert.ok(W.find(d, 'floor', before[0]).connections.includes('new_room'));
  assert.deepStrictEqual(W.find(d, 'floor', 'new_room').connections, [before[0]]);
  assert.strictEqual(r.entity._orig, null);
  assert.ok(W.addFloor(d, 'old_cave_dungeon', { id: 'new_room', name: 'x' }).error, '同じIDは追加できない');
  assert.ok(W.addFloor(d, 'old_cave_dungeon', { id: 'Bad-Id', name: 'x' }).error, '不正なIDは追加できない');
});

test('接続: 双方向に張り、外し、自分自身へは張れない', () => {
  const d = draftOf();
  assert.ok(W.connect(d, 'village', 'old_shrine'));
  assert.ok(W.find(d, 'floor', 'old_shrine').connections.includes('village'));
  W.disconnect(d, 'village', 'old_shrine');
  assert.ok(!W.find(d, 'floor', 'village').connections.includes('old_shrine'));
  assert.ok(!W.find(d, 'floor', 'old_shrine').connections.includes('village'));
  assert.strictEqual(W.connect(d, 'village', 'village'), false);
});

test('並べ替え: 同じ親の中だけで入れ替わり、端では動かない', () => {
  const d = draftOf();
  const ids = W.floorsIn(d, 'old_cave_dungeon').map((n) => n.id);
  assert.strictEqual(W.moveFloor(d, ids[0], -1), false);
  assert.ok(W.moveFloor(d, ids[0], +1));
  assert.deepStrictEqual(W.floorsIn(d, 'old_cave_dungeon').map((n) => n.id).slice(0, 2), [ids[1], ids[0]]);
  const areas = d.areas.map((a) => a.id);
  assert.ok(W.moveArea(d, areas[0], +1));
  assert.deepStrictEqual(d.areas.map((a) => a.id).slice(0, 2), [areas[1], areas[0]]);
  const inFirst = W.sectionsIn(d, areas[1]).map((s) => s.id);
  if (inFirst.length > 1) {
    assert.ok(W.moveSection(d, inFirst[0], +1));
    assert.deepStrictEqual(W.sectionsIn(d, areas[1]).map((s) => s.id).slice(0, 2), [inFirst[1], inFirst[0]]);
  }
});

test('フロア・セクションの移動: 移った先の並びの末尾に入る', () => {
  const d = draftOf();
  const target = 'village_area';
  assert.ok(W.moveFloorToSection(d, 'old_shrine', target));
  assert.strictEqual(W.find(d, 'floor', 'old_shrine').section, target);
  assert.strictEqual(W.floorsIn(d, target).at(-1).id, 'old_shrine');
  const otherArea = d.areas[1].id;
  const moving = d.sections[0].id;
  assert.ok(W.moveSectionToArea(d, moving, otherArea));
  assert.strictEqual(W.sectionsIn(d, otherArea).at(-1).id, moving);
});

test('IDの変更: 世界の中の参照(接続・所属・アイテム)が付け替わる', () => {
  const d = draftOf();
  assert.strictEqual(W.renameId(d, 'floor', 'old_shrine', 'renamed_shrine'), null);
  assert.ok(!W.find(d, 'floor', 'old_shrine'));
  assert.ok(d.nodes.every((n) => !n.connections.includes('old_shrine')));
  assert.ok(d.nodes.some((n) => n.connections.includes('renamed_shrine')));
  assert.strictEqual(W.find(d, 'floor', 'renamed_shrine')._orig, 'old_shrine');

  assert.strictEqual(W.renameId(d, 'section', 'old_cave_dungeon', 'cave_x'), null);
  assert.ok(W.floorsIn(d, 'cave_x').length > 0);
  assert.strictEqual(W.renameId(d, 'area', 'kingdom', 'kingdom_x'), null);
  assert.ok(W.sectionsIn(d, 'kingdom_x').length > 0);
  assert.strictEqual(W.renameId(d, 'item', 'goblin_amulet', 'amulet_x'), null);
  assert.ok(d.nodes.some((n) => n.gate.item === 'amulet_x'));
  assert.ok(d.nodes.some((n) => n.item_reward === 'amulet_x'));
  assert.ok(d.nodes.every((n) => n.gate.item !== 'goblin_amulet' && n.item_reward !== 'goblin_amulet'));

  assert.ok(W.renameId(d, 'floor', 'village', 'renamed_shrine'), '既にあるIDへは変えられない');
  assert.ok(W.renameId(d, 'floor', 'village', 'Bad Id'), '不正なIDへは変えられない');
});

test('IDの変更の波及: 保存済みのイベントが付け替わる(参照していないイベントは含まれない)', () => {
  const d = draftOf();
  W.renameId(d, 'floor', 'old_shrine', 'renamed_shrine');
  W.renameId(d, 'item', 'goblin_amulet', 'amulet_x');
  const diff = W.diffIds(world, d);
  assert.strictEqual(diff.floor.renames.get('old_shrine'), 'renamed_shrine');
  const changed = W.remapEvents(events, diff);
  const gateEvents = events.filter((e) => e.trigger.type === 'gate' && e.trigger.floor === 'old_shrine');
  assert.ok(gateEvents.length >= 1);
  for (const ev of gateEvents) assert.strictEqual(changed.find((c) => c.id === ev.id).trigger.floor, 'renamed_shrine');
  assert.ok(changed.length < events.length);
  assert.ok(changed.every((c) => W.eventReferences(c).some((r) => r.id === 'renamed_shrine' || r.id === 'amulet_x')));
  // 元のイベントは書き換わらない
  assert.strictEqual(events.find((e) => e.id === gateEvents[0].id).trigger.floor, 'old_shrine');
});

test('入れ替わりのID変更(AとBを交換)も、同時に付け替わる', () => {
  const d = draftOf();
  const a = W.find(d, 'floor', 'old_shrine');
  const b = W.find(d, 'floor', 'village');
  a.id = 'tmp_swap_x';
  b.id = 'old_shrine';
  a.id = 'village';
  const diff = W.diffIds(world, d);
  assert.strictEqual(diff.floor.renames.get('old_shrine'), 'village');
  assert.strictEqual(diff.floor.renames.get('village'), 'old_shrine');
});

test('削除: セクションはフロアごと消え、他のフロアの接続からも外れる。イベントの参照が分かる', () => {
  const d = draftOf();
  const sectionFloors = W.floorsIn(d, 'old_cave_dungeon').map((n) => n.id);
  const plan = W.collectDeletion(d, 'section', 'old_cave_dungeon');
  assert.deepStrictEqual(plan.floors, sectionFloors);
  assert.deepStrictEqual(plan.sections, ['old_cave_dungeon']);
  const affected = W.eventsReferencing(events, plan);
  assert.ok(affected.length >= 1);
  W.deleteEntity(d, 'section', 'old_cave_dungeon');
  assert.ok(!W.find(d, 'section', 'old_cave_dungeon'));
  assert.ok(sectionFloors.every((id) => !W.find(d, 'floor', id)));
  assert.ok(d.nodes.every((n) => n.connections.every((c) => !sectionFloors.includes(c))));
  assert.strictEqual(W.diffIds(world, d).floor.removed.size, sectionFloors.length);

  const d2 = draftOf();
  const area = d2.areas[1];
  const areaPlan = W.collectDeletion(d2, 'area', area.id);
  assert.ok(areaPlan.sections.length >= 1 && areaPlan.floors.length >= 1);
  W.deleteEntity(d2, 'area', area.id);
  assert.ok(d2.sections.every((s) => s.area !== area.id));
  assert.ok(d2.nodes.every((n) => W.find(d2, 'section', n.section)));
});

test('検証: 壊れた世界を見つける(致命的なものはfatal)', () => {
  const d = draftOf();
  d.nodes[3].section = 'no_such_section';
  d.nodes[4].connections.push('no_such_floor');
  d.nodes[5].connections.push(d.nodes[5].id);
  d.items.push({ id: d.items[0].id, name: 'dup' });
  W.find(d, 'floor', 'old_shrine').gate = { type: 'skill', skill: 'NOPE', min_level: 1 };
  const issues = W.validateWorld(d, { events });
  const has = (text, fatal) => issues.some((i) => i.msg.includes(text) && i.fatal === fatal);
  assert.ok(has('セクションが存在しません', true));
  assert.ok(has('接続先が存在しません', true));
  assert.ok(has('自分自身', true));
  assert.ok(has('IDが重複', true));
  assert.ok(has('ゲートの技能が正しくありません', true));
});

test('検証: 片方向の接続・到達できないフロア・開始地点なし・入手できないゲートのアイテム', () => {
  const d = draftOf();
  const one = W.find(d, 'floor', 'old_shrine');
  const other = one.connections[0];
  W.find(d, 'floor', other).connections = W.find(d, 'floor', other).connections.filter((c) => c !== 'old_shrine');
  let issues = W.validateWorld(d, { events });
  assert.ok(issues.some((i) => i.level === 'warn' && i.msg.includes('相手側にはありません') && i.target.id === 'old_shrine'));

  const d2 = draftOf();
  W.addFloor(d2, 'old_cave_dungeon', { id: 'lonely', name: 'ひとりぼっち' });
  issues = W.validateWorld(d2, { events });
  assert.ok(issues.some((i) => i.level === 'warn' && i.msg.includes('発見できません') && i.target.id === 'lonely'));
  // イベントの効果「フロアを開放」の対象は、出発点として数える
  const opener = { id: 'opens', trigger: { type: 'conditions' }, conditions: [], effects: [{ type: 'open_floor', floor: 'lonely' }], script: [] };
  assert.ok(!W.validateWorld(d2, { events: [...events, opener] }).some((i) => i.msg.includes('発見できません') && i.target.id === 'lonely'));

  const d3 = draftOf();
  for (const n of d3.nodes) n.initially_passed = false;
  assert.ok(W.validateWorld(d3, { events }).some((i) => i.level === 'error' && i.msg.includes('開始地点')));

  const d4 = draftOf();
  const gated = d4.nodes.find((n) => n.gate.type === 'item');
  for (const n of d4.nodes) if (n.item_reward === gated.gate.item) n.item_reward = '';
  assert.ok(W.validateWorld(d4, { events }).some((i) => i.level === 'warn' && i.msg.includes('入手する手段がありません') && i.target.id === gated.id));
});

test('世界の書き出し: 編集用の_origは含まれず、ゲートのキー順が保たれる', () => {
  const d = draftOf();
  const w = W.canonicalWorld(d);
  assert.ok(!JSON.stringify(w).includes('_orig'));
  const node = W.find(d, 'floor', 'old_shrine');
  node.gate = W.defaultGate('skill');
  assert.deepStrictEqual(Object.keys(W.canonicalWorld(d).nodes.find((n) => n.id === 'old_shrine').gate), ['type', 'skill', 'min_level']);
  node.gate = {};
  assert.deepStrictEqual(W.canonicalWorld(d).nodes.find((n) => n.id === 'old_shrine').gate, {});
});
