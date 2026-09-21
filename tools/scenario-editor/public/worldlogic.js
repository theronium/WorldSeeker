// マップ(world.json)の編集のうち、画面に依存しない部分(ブラウザとNode.jsの両方で読める)。
// 世界のデータの操作(追加・削除・並べ替え・接続・IDの変更)、書き出す形の正規化、検証、イベントへのIDの変更の波及。
// 形式の仕様は docs/scenario_editor.md の world.json。
//
// 編集中の世界(下書き)は、保存済みの世界の複製で、各要素に `_orig`(保存済みのときのID。新しく作ったものはnull)を持つ。
// IDを変えたり消したりしたとき、それを参照する保存済みのイベントを、保存時に付け替えるために使う。書き出す時は取り除く。
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./logic.js'));
  else root.WorldLogic = factory(root.Logic);
})(typeof self !== 'undefined' ? self : this, function (L) {
  'use strict';

  const ID_RE = /^[a-z0-9][a-z0-9_]{0,60}$/;
  const ID_HINT = 'IDは、小文字英数字と _ だけ(先頭は英数字、61文字まで)にしてください';
  const MAP_COLUMNS = 5; // ゲームのマップ画面が、セクション内のフロアを並べる列数(main.gdのMAP_COLUMNS)

  const KINDS = {
    area: { list: 'areas', label: 'エリア' },
    section: { list: 'sections', label: 'セクション' },
    floor: { list: 'nodes', label: 'フロア' },
    item: { list: 'items', label: 'アイテム' },
  };
  const GATE_TYPES = [
    { value: '', label: 'なし(誰でも通れる)' },
    { value: 'combat', label: '戦闘(敵の戦闘力)' },
    { value: 'skill', label: '技能(技能とレベル)' },
    { value: 'item', label: 'アイテム(持っていれば通れる)' },
    { value: 'innate_trait', label: '生まれ(血筋などの特性)' },
  ];

  const listOf = (world, kind) => world[KINDS[kind].list];
  const clone = (x) => JSON.parse(JSON.stringify(x));

  function ordered(obj, keys) {
    const out = {};
    for (const k of keys) if (obj[k] !== undefined) out[k] = obj[k];
    for (const k of Object.keys(obj)) if (!(k in out) && obj[k] !== undefined) out[k] = obj[k];
    return out;
  }

  // ---- 書き出す形 ----

  const GATE_KEYS = {
    combat: ['type', 'enemy_power'],
    skill: ['type', 'skill', 'min_level'],
    item: ['type', 'item'],
    innate_trait: ['type', 'trait', 'value'],
  };

  function canonicalGate(gate) {
    if (!gate || !gate.type) return {};
    return ordered(gate, GATE_KEYS[gate.type] || ['type']);
  }

  // ゲームが書く形・キー順と同じにして、Gitの差分を小さくする(`_orig`は取り除く)
  function canonicalWorld(world) {
    return {
      items: world.items.map((e) => ({ id: e.id, name: e.name })),
      areas: world.areas.map((e) => ({ id: e.id, name: e.name })),
      sections: world.sections.map((e) => ({ id: e.id, name: e.name, area: e.area })),
      nodes: world.nodes.map((n) => ({
        id: n.id, name: n.name, section: n.section, connections: [...(n.connections || [])],
        gate: canonicalGate(n.gate), item_reward: n.item_reward || '', initially_passed: !!n.initially_passed,
      })),
    };
  }

  // 保存済みの世界から、編集用の下書きを作る
  function startDraft(world) {
    const draft = clone(world);
    for (const kind of Object.keys(KINDS)) for (const e of listOf(draft, kind)) e._orig = e.id;
    return draft;
  }

  // ---- 検索 ----

  function find(world, kind, id) { return listOf(world, kind).find((e) => e.id === id); }
  function floorsIn(world, sectionId) { return world.nodes.filter((n) => n.section === sectionId); }
  function sectionsIn(world, areaId) { return world.sections.filter((s) => s.area === areaId); }

  function uniqueId(world, kind, base) {
    const taken = new Set(listOf(world, kind).map((e) => e.id));
    let id = base;
    for (let n = 2; taken.has(id); n++) id = `${base}_${n}`;
    return id;
  }

  // ---- 並びの操作 ----
  // 世界の並びは意味を持つ: エリアの並び=収入・報酬の倍率、セクションの並び(エリア内)=撤退先の判定とマップの上下、
  // フロアの並び(セクション内)=ゲームのマップ画面での配置(左上から右へ、MAP_COLUMNS列で折り返す)。
  // ファイルが読みやすいよう、同じ親の要素は隣り合わせに置く(ゲームは親で絞り込むので、間に別の要素が挟まっても動く)。

  function insertGrouped(list, item, sameGroup) {
    let last = -1;
    list.forEach((e, i) => { if (sameGroup(e)) last = i; });
    if (last < 0) list.push(item); else list.splice(last + 1, 0, item);
  }

  // 同じ親を持つ兄弟の中で、delta(+1/-1)だけ動かす。動かせたらtrue
  function moveWithin(list, id, delta, sameGroup) {
    const index = list.findIndex((e) => e.id === id);
    if (index < 0) return false;
    const siblings = [];
    list.forEach((e, i) => { if (sameGroup(list[index], e)) siblings.push(i); });
    const pos = siblings.indexOf(index);
    const target = pos + delta;
    if (target < 0 || target >= siblings.length) return false;
    const other = siblings[target];
    [list[index], list[other]] = [list[other], list[index]];
    return true;
  }

  const moveArea = (world, id, delta) => moveWithin(world.areas, id, delta, () => true);
  const moveSection = (world, id, delta) => moveWithin(world.sections, id, delta, (a, b) => a.area === b.area);
  const moveFloor = (world, id, delta) => moveWithin(world.nodes, id, delta, (a, b) => a.section === b.section);
  const moveItem = (world, id, delta) => moveWithin(world.items, id, delta, () => true);

  function moveSectionToArea(world, sectionId, areaId) {
    const index = world.sections.findIndex((s) => s.id === sectionId);
    if (index < 0 || !find(world, 'area', areaId)) return false;
    const [section] = world.sections.splice(index, 1);
    section.area = areaId;
    insertGrouped(world.sections, section, (s) => s.area === areaId);
    return true;
  }

  function moveFloorToSection(world, floorId, sectionId) {
    const index = world.nodes.findIndex((n) => n.id === floorId);
    if (index < 0 || !find(world, 'section', sectionId)) return false;
    const [node] = world.nodes.splice(index, 1);
    node.section = sectionId;
    insertGrouped(world.nodes, node, (n) => n.section === sectionId);
    return true;
  }

  // ---- 追加 ----

  function checkNewId(world, kind, id) {
    if (!ID_RE.test(id)) return ID_HINT;
    if (find(world, kind, id)) return `同じIDが既にあります: ${id}`;
    return null;
  }

  function addArea(world, { id, name }) {
    const err = checkNewId(world, 'area', id);
    if (err) return { error: err };
    const area = { id, name, _orig: null };
    world.areas.push(area);
    return { entity: area };
  }

  function addSection(world, areaId, { id, name }) {
    const err = checkNewId(world, 'section', id);
    if (err) return { error: err };
    if (!find(world, 'area', areaId)) return { error: 'エリアが見つかりません' };
    const section = { id, name, area: areaId, _orig: null };
    insertGrouped(world.sections, section, (s) => s.area === areaId);
    return { entity: section };
  }

  function defaultGate(type, world) {
    switch (type) {
      case 'combat': return { type, enemy_power: 30 };
      case 'skill': return { type, skill: 'WISDOM', min_level: 1 };
      case 'item': return { type, item: ((world && world.items[0]) || {}).id || '' };
      case 'innate_trait': return { type, trait: 'bloodline', value: '' };
      default: return {};
    }
  }

  function addFloor(world, sectionId, { id, name, connectTo }) {
    const err = checkNewId(world, 'floor', id);
    if (err) return { error: err };
    if (!find(world, 'section', sectionId)) return { error: 'セクションが見つかりません' };
    const node = { id, name, section: sectionId, connections: [], gate: defaultGate('combat', world), item_reward: '', initially_passed: false, _orig: null };
    insertGrouped(world.nodes, node, (n) => n.section === sectionId);
    if (connectTo && find(world, 'floor', connectTo)) connect(world, id, connectTo);
    return { entity: node };
  }

  function addItem(world, { id, name }) {
    const err = checkNewId(world, 'item', id);
    if (err) return { error: err };
    const item = { id, name, _orig: null };
    world.items.push(item);
    return { entity: item };
  }

  // ---- 接続(双方向)----
  // ゲームは「発見されるフロア自身の接続」に、突破済みの隣があるかで発見できるかを決める(WorldMap.frontier_for_section)。
  // そのため、片方にしか書かれていない接続は一方通行になる。エディタは、常に双方に書く。

  function connect(world, a, b) {
    if (a === b) return false;
    const na = find(world, 'floor', a);
    const nb = find(world, 'floor', b);
    if (!na || !nb) return false;
    if (!na.connections.includes(b)) na.connections.push(b);
    if (!nb.connections.includes(a)) nb.connections.push(a);
    return true;
  }

  function disconnect(world, a, b) {
    for (const [x, y] of [[a, b], [b, a]]) {
      const node = find(world, 'floor', x);
      if (node) node.connections = node.connections.filter((c) => c !== y);
    }
  }

  // ---- 削除 ----

  // 削除で一緒に消えるものの一覧(保存済みのときのID`_orig`。新しく作ったものは含めない): {floors, sections, areas, items}
  function collectDeletion(world, kind, id) {
    const out = { floors: [], sections: [], areas: [], items: [] };
    const floorIds = new Set();
    const sectionIds = new Set();
    const areaIds = new Set();
    if (kind === 'area') { areaIds.add(id); for (const s of sectionsIn(world, id)) sectionIds.add(s.id); }
    if (kind === 'section') sectionIds.add(id);
    for (const sid of sectionIds) for (const n of floorsIn(world, sid)) floorIds.add(n.id);
    if (kind === 'floor') floorIds.add(id);
    const orig = (k, i) => { const e = find(world, k, i); return e && e._orig ? e._orig : null; };
    for (const i of floorIds) { const o = orig('floor', i); if (o) out.floors.push(o); }
    for (const i of sectionIds) { const o = orig('section', i); if (o) out.sections.push(o); }
    for (const i of areaIds) { const o = orig('area', i); if (o) out.areas.push(o); }
    if (kind === 'item') { const o = orig('item', id); if (o) out.items.push(o); }
    out.ids = { floors: floorIds, sections: sectionIds, areas: areaIds };
    return out;
  }

  function deleteEntity(world, kind, id) {
    const { ids } = collectDeletion(world, kind, id);
    if (kind === 'item') { world.items = world.items.filter((e) => e.id !== id); return; }
    world.nodes = world.nodes.filter((n) => !ids.floors.has(n.id));
    for (const n of world.nodes) n.connections = n.connections.filter((c) => !ids.floors.has(c));
    world.sections = world.sections.filter((s) => !ids.sections.has(s.id));
    world.areas = world.areas.filter((a) => !ids.areas.has(a.id));
  }

  // ---- IDの変更(世界の中の参照を付け替える。イベントは保存時にdiffIds/remapEventsで) ----

  function renameId(world, kind, oldId, newId) {
    if (oldId === newId) return null;
    if (!ID_RE.test(newId)) return ID_HINT;
    const entity = find(world, kind, oldId);
    if (!entity) return `${KINDS[kind].label}が見つかりません: ${oldId}`;
    if (find(world, kind, newId)) return `同じIDが既にあります: ${newId}`;
    entity.id = newId;
    if (kind === 'floor') for (const n of world.nodes) n.connections = n.connections.map((c) => (c === oldId ? newId : c));
    if (kind === 'section') for (const n of world.nodes) if (n.section === oldId) n.section = newId;
    if (kind === 'area') for (const s of world.sections) if (s.area === oldId) s.area = newId;
    if (kind === 'item') {
      for (const n of world.nodes) {
        if (n.gate && n.gate.type === 'item' && n.gate.item === oldId) n.gate.item = newId;
        if (n.item_reward === oldId) n.item_reward = newId;
      }
    }
    return null;
  }

  // ---- イベントへの波及 ----

  // 保存済みの世界と下書きを比べて、IDの変更(旧→新)と、削除されたIDを求める: {floor:{renames:Map, removed:Set}, ...}
  function diffIds(saved, draft) {
    const out = {};
    for (const kind of Object.keys(KINDS)) {
      const renames = new Map();
      const present = new Set();
      for (const e of listOf(draft, kind)) {
        if (!e._orig) continue;
        present.add(e._orig);
        if (e._orig !== e.id) renames.set(e._orig, e.id);
      }
      const removed = new Set(listOf(saved, kind).map((e) => e.id).filter((id) => !present.has(id)));
      out[kind] = { renames, removed };
    }
    return out;
  }

  // イベントが世界の何を参照しているか: [{kind, id, where}](whereは、突破の会話/条件/効果)
  function eventReferences(event) {
    const refs = [];
    const trigger = event.trigger || {};
    if (trigger.type === 'gate') refs.push({ kind: 'floor', id: trigger.floor, where: trigger.result === 'fail' ? '失敗の会話' : '突破の会話' });
    for (const c of event.conditions || []) {
      if (c.type === 'floor_found' || c.type === 'floor_passed') refs.push({ kind: 'floor', id: c.floor, where: '条件' });
      if (c.type === 'section_entered') refs.push({ kind: 'section', id: c.section, where: '条件' });
      if (c.type === 'area_entered') refs.push({ kind: 'area', id: c.area, where: '条件' });
    }
    for (const e of event.effects || []) {
      if (e.type === 'open_floor') refs.push({ kind: 'floor', id: e.floor, where: '効果' });
      if (e.type === 'grant_item') refs.push({ kind: 'item', id: e.item, where: '効果' });
    }
    return refs;
  }

  // 保存済みのイベントのうち、IDの変更で書き換える必要があるものを、書き換えて返す(変わらないものは含めない)
  function remapEvents(events, diff) {
    const changed = [];
    const map = (kind, id) => (diff[kind].renames.has(id) ? diff[kind].renames.get(id) : id);
    for (const original of events) {
      const ev = clone(original);
      if (ev.trigger && ev.trigger.type === 'gate') ev.trigger.floor = map('floor', ev.trigger.floor);
      for (const c of ev.conditions || []) {
        if (c.type === 'floor_found' || c.type === 'floor_passed') c.floor = map('floor', c.floor);
        if (c.type === 'section_entered') c.section = map('section', c.section);
        if (c.type === 'area_entered') c.area = map('area', c.area);
      }
      for (const e of ev.effects || []) {
        if (e.type === 'open_floor') e.floor = map('floor', e.floor);
        if (e.type === 'grant_item') e.item = map('item', e.item);
      }
      if (JSON.stringify(ev) !== JSON.stringify(original)) changed.push(ev);
    }
    return changed;
  }

  // 削除するもの(collectDeletionの結果)を参照している、保存済みのイベント: [{event, refs:[{kind,id,where}]}]
  function eventsReferencing(events, removed) {
    const sets = { floor: new Set(removed.floors), section: new Set(removed.sections), area: new Set(removed.areas), item: new Set(removed.items) };
    const out = [];
    for (const event of events) {
      const refs = eventReferences(event).filter((r) => sets[r.kind].has(r.id));
      if (refs.length) out.push({ event, refs });
    }
    return out;
  }

  // 1つの要素(保存済みのときのID)を参照しているイベント
  function eventsUsing(events, kind, origId) {
    const out = [];
    for (const event of events) {
      const refs = eventReferences(event).filter((r) => r.kind === kind && r.id === origId);
      if (refs.length) out.push({ event, refs });
    }
    return out;
  }

  // ---- 表示用 ----

  function gateShort(gate) {
    if (!gate || !gate.type) return '';
    switch (gate.type) {
      case 'combat': return `戦闘 ${gate.enemy_power}`;
      case 'skill': return `${L.SKILL_NAMES[gate.skill] || gate.skill} Lv${gate.min_level}`;
      case 'item': return 'アイテム';
      case 'innate_trait': return '生まれ';
      default: return gate.type;
    }
  }

  // ---- 検証 ----
  // 戻り値: [{level:'error'|'warn', fatal, msg, target:{kind,id}|null, scope:'map'}]
  // fatal=trueは、ゲームが世界を読めなくなる(または壊れた参照でエラーになる)ので、保存を止める。

  function validateWorld(world, ctx) {
    const events = (ctx && ctx.events) || [];
    const out = [];
    const add = (level, msg, kind, id, fatal) => out.push({ level, fatal: !!fatal, msg, target: kind ? { kind, id } : null, scope: 'map' });
    const areaIds = new Set(world.areas.map((e) => e.id));
    const sectionIds = new Set(world.sections.map((e) => e.id));
    const floorIds = new Set(world.nodes.map((e) => e.id));
    const itemIds = new Set(world.items.map((e) => e.id));
    const byId = new Map(world.nodes.map((n) => [n.id, n]));

    for (const kind of Object.keys(KINDS)) {
      const seen = new Set();
      for (const e of listOf(world, kind)) {
        const label = `${KINDS[kind].label}「${e.name || e.id || '(名前なし)'}」`;
        if (!ID_RE.test(e.id || '')) add('error', `${label}のIDが正しくありません: ${e.id || '(空)'}(${ID_HINT})`, kind, e.id, true);
        else if (seen.has(e.id)) add('error', `${KINDS[kind].label}のIDが重複しています: ${e.id}`, kind, e.id, true);
        seen.add(e.id);
        if (!String(e.name || '').trim()) add('warn', `${label}(${e.id})の名前が空です`, kind, e.id);
      }
    }

    for (const area of world.areas) {
      if (!sectionsIn(world, area.id).length) add('warn', `エリア「${area.name}」にセクションが1つもありません(ゲームでは表示されません)`, 'area', area.id);
    }
    for (const section of world.sections) {
      if (!areaIds.has(section.area)) add('error', `セクション「${section.name}」のエリアが存在しません: ${section.area}`, 'section', section.id, true);
      if (!floorsIn(world, section.id).length) add('warn', `セクション「${section.name}」にフロアが1つもありません(ゲームでは表示されません)`, 'section', section.id);
    }

    const obtainable = new Set(world.nodes.map((n) => n.item_reward).filter(Boolean));
    for (const ev of events) for (const e of ev.effects || []) if (e.type === 'grant_item') obtainable.add(e.item);

    for (const n of world.nodes) {
      const label = `フロア「${n.name || n.id}」`;
      if (!sectionIds.has(n.section)) add('error', `${label}のセクションが存在しません: ${n.section}`, 'floor', n.id, true);
      const seen = new Set();
      for (const c of n.connections || []) {
        if (c === n.id) { add('error', `${label}が、自分自身につながっています`, 'floor', n.id, true); continue; }
        if (!floorIds.has(c)) { add('error', `${label}の接続先が存在しません: ${c}`, 'floor', n.id, true); continue; }
        if (seen.has(c)) add('warn', `${label}の接続に、同じフロアが重複しています: ${c}`, 'floor', n.id);
        seen.add(c);
        if (!byId.get(c).connections.includes(n.id)) {
          add('warn', `${label}は「${byId.get(c).name}」につながっていますが、相手側にはありません(相手を突破しても、このフロアは発見されません)`, 'floor', n.id);
        }
      }
      const gate = n.gate || {};
      if (Object.keys(gate).length && !gate.type) add('error', `${label}のゲートに種類がありません`, 'floor', n.id, true);
      else if (gate.type === 'combat') {
        if (!Number.isInteger(gate.enemy_power) || gate.enemy_power < 1) add('error', `${label}の敵の戦闘力は、1以上の整数にしてください`, 'floor', n.id);
      } else if (gate.type === 'skill') {
        if (!Object.prototype.hasOwnProperty.call(L.SKILL_NAMES, gate.skill)) add('error', `${label}のゲートの技能が正しくありません: ${gate.skill}`, 'floor', n.id, true);
        if (!Number.isInteger(gate.min_level) || gate.min_level < 1) add('error', `${label}の必要レベルは、1以上の整数にしてください`, 'floor', n.id);
      } else if (gate.type === 'item') {
        if (!itemIds.has(gate.item)) add('error', `${label}のゲートのアイテムが定義されていません: ${gate.item || '(未選択)'}`, 'floor', n.id);
        else if (!obtainable.has(gate.item)) add('warn', `${label}を通るためのアイテム「${find(world, 'item', gate.item).name}」を入手する手段がありません(どのフロアの報酬にも、イベントの効果にもありません)`, 'floor', n.id);
      } else if (gate.type === 'innate_trait') {
        if (!String(gate.trait || '').trim() || !String(gate.value || '').trim()) add('error', `${label}のゲートの、項目名と値を入力してください`, 'floor', n.id);
      } else if (gate.type) {
        add('error', `${label}の不明なゲート種別です: ${gate.type}`, 'floor', n.id, true);
      }
      if (n.item_reward && !itemIds.has(n.item_reward)) add('error', `${label}の突破報酬のアイテムが定義されていません: ${n.item_reward}`, 'floor', n.id);
    }

    // 発見できるか: ゲームと同じく、「自分の接続に、到達済みのフロアがある」フロアが順に発見される(ゲートは無視)。
    // 出発点は、最初から突破済みのフロアと、イベントの効果「フロアを開放」の対象
    const roots = new Set(world.nodes.filter((n) => n.initially_passed).map((n) => n.id));
    if (!roots.size) add('error', '最初から突破済みのフロア(開始地点)が1つもありません。探索者が最初のフロアを発見できません', null, null);
    for (const ev of events) for (const e of ev.effects || []) if (e.type === 'open_floor' && floorIds.has(e.floor)) roots.add(e.floor);
    const reached = new Set(roots);
    for (let changed = true; changed;) {
      changed = false;
      for (const n of world.nodes) {
        if (!reached.has(n.id) && (n.connections || []).some((c) => reached.has(c))) { reached.add(n.id); changed = true; }
      }
    }
    if (roots.size) {
      for (const n of world.nodes) {
        if (!reached.has(n.id)) add('warn', `フロア「${n.name}」は、開始地点から接続をたどっても発見できません`, 'floor', n.id);
      }
    }
    return out;
  }

  return {
    ID_RE, ID_HINT, MAP_COLUMNS, KINDS, GATE_TYPES,
    canonicalWorld, canonicalGate, startDraft, find, floorsIn, sectionsIn, uniqueId,
    moveArea, moveSection, moveFloor, moveItem, moveSectionToArea, moveFloorToSection,
    addArea, addSection, addFloor, addItem, defaultGate, connect, disconnect,
    collectDeletion, deleteEntity, renameId, diffIds, remapEvents, eventReferences, eventsReferencing, eventsUsing,
    gateShort, validateWorld,
  };
});
