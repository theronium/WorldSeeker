// シナリオ・イベントエディタの、画面に依存しない部分(ブラウザとNode.jsの両方で読める)。
// 会話の行の編集(分岐先の付け替え)、イベントの検証、話者の画像の自動選択(ゲームと同じ結果)、書き出す形の正規化など。
// フォーマットの仕様は docs/scenario_editor.md。
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Logic = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // ---- 定数(選択肢・ラベル) ----

  // 会話の種別。色はゲーム(main.gdのEVENT_STYLES)と同じ
  const KIND_STYLES = {
    boss: { label: 'ボス戦', accent: 'rgb(235,66,61)' },
    combat: { label: '戦闘', accent: 'rgb(242,140,51)' },
    skill: { label: '技能', accent: 'rgb(82,148,245)' },
    item: { label: 'アイテム', accent: 'rgb(242,199,64)' },
    bloodline: { label: '血筋', accent: 'rgb(173,115,235)' },
    guide: { label: '案内', accent: 'rgb(158,173,189)' },
  };
  const KIND_OPTIONS = [
    { value: 'auto', label: '自動(フロアのゲートの種類から)' },
    { value: '', label: 'なし(従来の見た目)' },
    ...Object.entries(KIND_STYLES).map(([value, s]) => ({ value, label: s.label })),
  ];
  const SKILL_NAMES = { WISDOM: '知恵', LOCKPICKING: '鍵開け', DESTRUCTION: '破壊', PERCEPTION: '知覚/発見', COMBAT: '戦闘力', HEALING: '回復' };
  const SIDES = [{ value: 'left', label: '左(人物)' }, { value: 'right', label: '右(敵)' }, { value: 'none', label: 'なし(語り)' }];
  const SYSTEM_SCENES = [
    { value: 'intro_part1', label: '導入・前編(ゲーム起動直後の一度きり)' },
    { value: 'intro_part2', label: '導入・後編(初めてパーティを割り当てた直後)' },
    { value: 'party_formed', label: '初めて探索者を雇用した直後' },
    { value: 'retreat', label: '初めて戦闘で撤退した直後' },
  ];
  const CONDITION_TYPES = [
    { type: 'day_min', label: '経過日数がN日以上', fields: [{ key: 'day', kind: 'int', default: 30 }] },
    { type: 'flag', label: 'フラグの状態', fields: [{ key: 'flag', kind: 'flag' }, { key: 'value', kind: 'bool', default: true }] },
    { type: 'floor_found', label: 'フロアを発見済み', fields: [{ key: 'floor', kind: 'floor' }] },
    { type: 'floor_passed', label: 'フロアを突破済み', fields: [{ key: 'floor', kind: 'floor' }] },
    { type: 'section_entered', label: 'セクションに到達済み', fields: [{ key: 'section', kind: 'section' }] },
    { type: 'area_entered', label: 'エリアに到達済み', fields: [{ key: 'area', kind: 'area' }] },
  ];
  const EFFECT_TYPES = [
    { type: 'set_flag', label: 'フラグを設定/解除', fields: [{ key: 'flag', kind: 'flag' }, { key: 'value', kind: 'bool', default: true }] },
    { type: 'funds', label: '資金を増減', fields: [{ key: 'amount', kind: 'int', default: 100 }] },
    { type: 'grant_item', label: 'アイテムを渡す', fields: [{ key: 'item', kind: 'item' }] },
    { type: 'open_floor', label: 'フロアを開放(突破済みにする)', fields: [{ key: 'floor', kind: 'floor' }] },
  ];
  const EVENT_ID = /^[a-z0-9][a-z0-9_]{0,80}$/;
  const POOL_SIZE = 32;

  // ---- 画像の自動選択(ゲームのEventPortraits.portrait_idと同じ) ----

  // GodotのString.hash()(djb2、32ビット)。表に無い話者名の画像を、ゲームと同じ結果で予告するために使う
  function godotHash(text) {
    let h = 5381;
    for (const ch of text) h = (Math.imul(h, 33) + ch.codePointAt(0)) >>> 0;
    return h;
  }

  function fallbackImage(name, kind) {
    const prefix = kind === 'boss' || kind === 'combat' ? 'enemy' : 'npc';
    return `${prefix}_${String((godotHash(name) % POOL_SIZE) + 1).padStart(2, '0')}`;
  }

  // 行の画像: 行のimage → 登場人物表 → 自動選択。話者名が空なら画像なし
  function resolveImage(line, cast, kind) {
    if (line.image) return line.image;
    if (!line.name) return '';
    const entry = (cast || []).find((c) => c.name === line.name);
    if (entry && entry.image) return entry.image;
    return fallbackImage(line.name, kind);
  }

  // ---- ワールド(参照用) ----

  function worldIndex(world) {
    const idx = { floors: new Map(), sections: new Map(), areas: new Map(), items: new Map(), floorsBySection: new Map() };
    for (const a of world.areas || []) idx.areas.set(a.id, a);
    for (const s of world.sections || []) idx.sections.set(s.id, s);
    for (const i of world.items || []) idx.items.set(i.id, i);
    for (const n of world.nodes || []) {
      idx.floors.set(n.id, n);
      if (!idx.floorsBySection.has(n.section)) idx.floorsBySection.set(n.section, []);
      idx.floorsBySection.get(n.section).push(n);
    }
    return idx;
  }

  // ゲームのWorldMap.event_kind_for_nodeと同じ: 戦闘は、そのセクションで敵戦闘力が最も高ければボス戦
  function autoKind(idx, floorId) {
    const node = idx.floors.get(floorId);
    if (!node) return '';
    const gate = node.gate || {};
    switch (gate.type) {
      case 'combat': {
        const power = gate.enemy_power || 0;
        const strongerExists = (idx.floorsBySection.get(node.section) || []).some((o) => o.gate && o.gate.type === 'combat' && (o.gate.enemy_power || 0) > power);
        return strongerExists ? 'combat' : 'boss';
      }
      case 'skill': return 'skill';
      case 'item': return 'item';
      case 'innate_trait': return 'bloodline';
      default: return '';
    }
  }

  function gateSummary(gate, idx) {
    if (!gate || !gate.type) return 'ゲートなし';
    switch (gate.type) {
      case 'combat': return `戦闘(敵戦闘力 ${gate.enemy_power})`;
      case 'skill': return `技能(${SKILL_NAMES[gate.skill] || gate.skill} Lv${gate.min_level}以上)`;
      case 'item': return `アイテム(${idx && idx.items.get(gate.item) ? idx.items.get(gate.item).name : gate.item})`;
      case 'innate_trait': return `生まれ(${gate.trait}: ${gate.value})`;
      default: return gate.type;
    }
  }

  // 会話の種別(実際に使われるもの): kindが"auto"ならゲートから、それ以外はそのまま
  function effectiveKind(event, idx) {
    if (event.kind !== 'auto') return event.kind || '';
    return event.trigger && event.trigger.type === 'gate' ? autoKind(idx, event.trigger.floor) : '';
  }

  // ---- 会話の台本の編集(行の番号が変わると、分岐先の番号も付け替える) ----

  function clone(x) { return JSON.parse(JSON.stringify(x)); }

  function mapRefs(script, fn) {
    for (const line of script) {
      if (typeof line.next === 'number') line.next = fn(line.next);
      for (const choice of line.choices || []) if (typeof choice.next === 'number') choice.next = fn(choice.next);
    }
  }

  // 「次の行(i+1)へ」の明示(next: i+1)を省略に直す。省略した行は、並びが変わっても、次の行へ流れる。
  // 行の挿入・削除・移動の前に行い、「一覧の並び=会話の流れ」を保つ(飛び先の付け替えは、それ以外の分岐だけになる)
  function normalizeSequential(script) {
    script.forEach((line, i) => {
      if (line.next === i + 1) delete line.next;
      for (const choice of line.choices || []) if (choice.next === i + 1) delete choice.next;
    });
    return script;
  }

  function insertLine(script, at, line) {
    const out = normalizeSequential(clone(script));
    mapRefs(out, (n) => (n >= at ? n + 1 : n));
    out.splice(at, 0, line);
    return out;
  }

  // 消した行を指していた分岐は、その次の行(消した後にその番号へ繰り上がる行)を指す
  function deleteLine(script, at) {
    const out = normalizeSequential(clone(script));
    mapRefs(out, (n) => (n > at ? n - 1 : n));
    out.splice(at, 1);
    return out;
  }

  function moveLine(script, from, to) {
    const n = script.length;
    const order = script.map((_, i) => i);
    order.splice(from, 1);
    order.splice(to, 0, from);
    const newIndex = [];
    order.forEach((old, pos) => { newIndex[old] = pos; });
    const out = order.map((old) => clone(normalizeSequential(clone(script))[old]));
    mapRefs(out, (r) => (r >= 0 && r < n ? newIndex[r] : r));
    return out;
  }

  function defaultLine(previous) {
    return { side: previous ? previous.side : 'left', name: previous ? previous.name : '', text: '' };
  }

  // 1つの行(または選択肢)から進む先。{to: 行番号} か {end: true, outcome}
  function stepTarget(step, i, length) {
    if (step.outcome !== undefined && step.outcome !== null) return { end: true, outcome: String(step.outcome) };
    const to = typeof step.next === 'number' ? step.next : i + 1;
    if (to < 0 || to >= length) return { end: true, outcome: '' };
    return { to };
  }

  // 行から出る矢印: [{label, to | end+outcome}]。選択肢があればそれぞれ、無ければ1本
  function edgesOf(script, i) {
    const line = script[i];
    if (line.choices && line.choices.length) {
      return line.choices.map((c) => ({ label: c.label || '', ...stepTarget(c, i, script.length) }));
    }
    return [{ label: '', ...stepTarget(line, i, script.length) }];
  }

  function reachable(script) {
    const seen = new Set();
    if (!script.length) return seen;
    const queue = [0];
    while (queue.length) {
      const i = queue.pop();
      if (seen.has(i)) continue;
      seen.add(i);
      for (const e of edgesOf(script, i)) if (e.to !== undefined) queue.push(e.to);
    }
    return seen;
  }

  // 到達できる終わりの結果コード(''は、結果コード無しで終わる)
  function endOutcomes(script) {
    const out = new Set();
    for (const i of reachable(script)) for (const e of edgesOf(script, i)) if (e.end) out.add(e.outcome);
    return out;
  }

  function usedSpeakers(events) {
    const counts = new Map();
    for (const ev of events) for (const line of ev.script || []) if (line.name) counts.set(line.name, (counts.get(line.name) || 0) + 1);
    return counts;
  }

  // ---- 書き出す形の正規化(ゲームが書く形・キー順と同じにして、Gitの差分を小さくする) ----

  function ordered(obj, keys) {
    const out = {};
    for (const k of keys) if (obj[k] !== undefined) out[k] = obj[k];
    for (const k of Object.keys(obj)) if (!(k in out) && obj[k] !== undefined) out[k] = obj[k];
    return out;
  }

  function canonicalLine(line) {
    const out = ordered(line, ['side', 'name', 'text', 'image', 'kind', 'result', 'next', 'choices', 'outcome']);
    if (out.choices) out.choices = out.choices.map((c) => ordered(c, ['label', 'next', 'outcome']));
    return out;
  }

  function canonicalEvent(ev) {
    const trigger = ev.trigger || {};
    const triggerKeys = trigger.type === 'gate' ? ['type', 'floor', 'result'] : trigger.type === 'system' ? ['type', 'name'] : ['type'];
    const withFields = (specs) => (item) => ordered(item, ['on', 'type', ...(specs.find((s) => s.type === item.type) || { fields: [] }).fields.map((f) => f.key)]);
    return {
      id: ev.id,
      title: ev.title,
      trigger: ordered(trigger, triggerKeys),
      conditions: (ev.conditions || []).map((c) => ordered(c, ['type', ...((CONDITION_TYPES.find((s) => s.type === c.type) || { fields: [] }).fields.map((f) => f.key))])),
      repeat: !!ev.repeat,
      priority: ev.priority || 0,
      kind: ev.kind === undefined ? 'auto' : ev.kind,
      script: (ev.script || []).map(canonicalLine),
      effects: (ev.effects || []).map(withFields(EFFECT_TYPES)),
    };
  }

  // ---- 新しいイベントの雛形 ----

  function uniqueId(base, taken) {
    let id = base;
    for (let n = 2; taken.has(id); n++) id = `${base}_${n}`;
    return id;
  }

  function newGateEvent(idx, floorId, result, taken) {
    const floor = idx.floors.get(floorId);
    const name = floor ? floor.name : floorId;
    const text = result === 'pass' ? '(ゲートを突破した場面のセリフ)' : '(突破できなかった場面のセリフ)';
    return {
      id: uniqueId(`floor_${floorId}_${result}`, taken),
      title: `${name}(${result === 'pass' ? '突破' : '失敗'})`,
      trigger: { type: 'gate', floor: floorId, result },
      conditions: [], repeat: false, priority: 0, kind: 'auto',
      script: [{ side: 'none', name: name, text, next: 1 }, { side: 'none', name: '', text: result === 'pass' ? '道が開いた。' : '先へは進めなかった。', outcome: result }],
      effects: [],
    };
  }

  function newConditionEvent(title, taken) {
    return {
      id: uniqueId('event', taken),
      title: title || '新しいイベント',
      trigger: { type: 'conditions' },
      conditions: [{ type: 'day_min', day: 10 }], repeat: false, priority: 0, kind: '',
      script: [{ side: 'none', name: '', text: '(場面の描写やセリフ)', next: 1 }, { side: 'none', name: '', text: '(結末)', outcome: 'ok' }],
      effects: [],
    };
  }

  function newSystemEvent(scene, taken) {
    const label = (SYSTEM_SCENES.find((s) => s.value === scene) || { label: scene }).label;
    return {
      id: uniqueId(`guide_${scene}`, taken),
      title: label.replace(/(.*)\(.*\)$/, '$1'),
      trigger: { type: 'system', name: scene },
      conditions: [], repeat: false, priority: 0, kind: 'guide',
      script: [{ side: 'left', name: '案内人', text: '(案内のセリフ)', outcome: 'ok' }],
      effects: [],
    };
  }

  // ---- 説明文 ----

  function describeCondition(c, idx) {
    const floorName = (id) => (idx.floors.get(id) ? idx.floors.get(id).name : `${id}(存在しない)`);
    switch (c.type) {
      case 'day_min': return `${c.day}日目以降`;
      case 'flag': return c.value === false ? `フラグ「${c.flag}」が立っていない` : `フラグ「${c.flag}」が立っている`;
      case 'floor_found': return `「${floorName(c.floor)}」を発見済み`;
      case 'floor_passed': return `「${floorName(c.floor)}」を突破済み`;
      case 'section_entered': return `セクション「${idx.sections.get(c.section) ? idx.sections.get(c.section).name : c.section}」に到達済み`;
      case 'area_entered': return `エリア「${idx.areas.get(c.area) ? idx.areas.get(c.area).name : c.area}」に到達済み`;
      default: return `(不明な条件: ${c.type})`;
    }
  }

  function describeEffect(e, idx) {
    switch (e.type) {
      case 'set_flag': return e.value === false ? `フラグ「${e.flag}」を降ろす` : `フラグ「${e.flag}」を立てる`;
      case 'funds': return e.amount >= 0 ? `資金 +${e.amount}` : `資金 ${e.amount}`;
      case 'grant_item': return `アイテム「${idx.items.get(e.item) ? idx.items.get(e.item).name : e.item}」を渡す`;
      case 'open_floor': return `「${idx.floors.get(e.floor) ? idx.floors.get(e.floor).name : e.floor}」を開放する`;
      default: return `(不明な効果: ${e.type})`;
    }
  }

  // ---- 検証 ----
  // ctx: {idx(worldIndex), events(全イベント), library(Set of id), scenarioImages(Set of ファイル名)}
  // 戻り値: [{level:'error'|'warn', msg, line?}]

  function validateEvent(ev, ctx) {
    const out = [];
    const err = (msg, line) => out.push({ level: 'error', msg, line });
    const warn = (msg, line) => out.push({ level: 'warn', msg, line });
    const { idx } = ctx;
    const others = ctx.events.filter((e) => e !== ev && e.id !== ev.id);

    if (!EVENT_ID.test(ev.id || '')) err('IDは、小文字英数字と _ だけにしてください');
    if (!ev.title) warn('タイトルが空です(一覧で見分けにくくなります)');
    if (ctx.events.some((e) => e !== ev && e.id === ev.id)) err(`同じIDのイベントが他にあります: ${ev.id}`);

    const trigger = ev.trigger || {};
    if (trigger.type === 'gate') {
      if (!idx.floors.has(trigger.floor)) err(`フロアが存在しません: ${trigger.floor}`);
      if (trigger.result !== 'pass' && trigger.result !== 'fail') err('結果は pass か fail にしてください');
      if (others.some((e) => e.trigger && e.trigger.type === 'gate' && e.trigger.floor === trigger.floor && e.trigger.result === trigger.result)) {
        err('同じフロア・同じ結果のイベントが他にあります(片方しか再生されません)');
      }
    } else if (trigger.type === 'system') {
      if (!SYSTEM_SCENES.some((s) => s.value === trigger.name)) err(`不明な場面です: ${trigger.name}`);
      if (others.some((e) => e.trigger && e.trigger.type === 'system' && e.trigger.name === trigger.name)) err('同じ場面の案内会話が他にあります');
    } else if (trigger.type === 'conditions') {
      if (!(ev.conditions || []).length) warn('条件が1つも無いので、ゲーム開始の翌日に発生します');
    } else {
      err(`不明な発生のしかたです: ${trigger.type}`);
    }

    for (const c of ev.conditions || []) {
      const spec = CONDITION_TYPES.find((s) => s.type === c.type);
      if (!spec) { err(`不明な条件です: ${c.type}`); continue; }
      if (c.type === 'day_min' && !Number.isInteger(c.day)) err('日数は整数にしてください');
      if ((c.type === 'floor_found' || c.type === 'floor_passed') && !idx.floors.has(c.floor)) err(`条件のフロアが存在しません: ${c.floor}`);
      if (c.type === 'section_entered' && !idx.sections.has(c.section)) err(`条件のセクションが存在しません: ${c.section}`);
      if (c.type === 'area_entered' && !idx.areas.has(c.area)) err(`条件のエリアが存在しません: ${c.area}`);
      if (c.type === 'flag') {
        if (!c.flag) err('条件のフラグ名が空です');
        else if (c.value !== false && !ctx.events.some((e) => (e.effects || []).some((f) => f.type === 'set_flag' && f.flag === c.flag && f.value !== false))) {
          warn(`フラグ「${c.flag}」を立てるイベントが、このシナリオに無いので、この条件は成り立ちません`);
        }
      }
    }

    const script = ev.script || [];
    if (!script.length) err('会話の行が1つもありません');
    const seen = reachable(script);
    const ends = endOutcomes(script);
    script.forEach((line, i) => {
      const at = i;
      if (!['left', 'right', 'none'].includes(line.side)) err(`行${i + 1}: 左右の指定が正しくありません`, at);
      if (!String(line.text || '').trim()) warn(`行${i + 1}: セリフが空です`, at);
      if ((line.side === 'left' || line.side === 'right') && !line.name) warn(`行${i + 1}: 画像を出す側なのに、話者名が空です`, at);
      const checkRef = (n, what) => { if (typeof n === 'number' && (n < 0 || n >= script.length)) err(`行${i + 1}: ${what}の行き先(${n + 1}行目)がありません`, at); };
      checkRef(line.next, '次');
      if (line.choices) {
        if (!line.choices.length) warn(`行${i + 1}: 選択肢が空です`, at);
        line.choices.forEach((c, k) => {
          if (!String(c.label || '').trim()) err(`行${i + 1}: 選択肢${k + 1}のラベルが空です`, at);
          checkRef(c.next, `選択肢${k + 1}`);
        });
      }
      if (!seen.has(i)) warn(`行${i + 1}: どこからも到達できません`, at);
    });
    if (script.length && !ends.size) err('会話が終わりに到達できません(行き先がぐるぐる回っています)');
    if (trigger.type === 'gate') {
      for (const outcome of ends) {
        if (outcome !== 'pass' && outcome !== 'fail') err(`フロアの会話は、結果コードが pass か fail で終わる必要があります(今は「${outcome || '(なし)'}」で終わる道があります)`);
      }
    }

    for (const eff of ev.effects || []) {
      const spec = EFFECT_TYPES.find((s) => s.type === eff.type);
      if (!spec) { err(`不明な効果です: ${eff.type}`); continue; }
      if (eff.on && eff.on !== '*' && !ends.has(eff.on)) warn(`効果の「${eff.on}」で終わる道が、会話にありません(この効果は働きません)`);
      if (eff.type === 'set_flag' && !eff.flag) err('効果のフラグ名が空です');
      if (eff.type === 'funds' && (!Number.isInteger(eff.amount) || eff.amount === 0)) warn('資金の増減は、0以外の整数にしてください');
      if (eff.type === 'grant_item' && !idx.items.has(eff.item)) warn(`アイテムが定義されていません: ${eff.item}`);
      if (eff.type === 'open_floor' && !idx.floors.has(eff.floor)) err(`開放するフロアが存在しません: ${eff.floor}`);
    }

    // 画像の指定
    for (const [i, line] of script.entries()) {
      if (line.image && !imageExists(line.image, ctx)) warn(`行${i + 1}: 画像が見つかりません: ${line.image}`, i);
    }
    return out;
  }

  function imageExists(id, ctx) {
    if (id.startsWith('@')) return ctx.scenarioImages.has(id.slice(1));
    return ctx.library.has(id);
  }

  function validateCast(cast, ctx) {
    const out = [];
    const names = new Set();
    for (const entry of cast) {
      if (!entry.name) out.push({ level: 'error', msg: '話者名が空の登場人物がいます' });
      if (names.has(entry.name)) out.push({ level: 'error', msg: `話者名が重複しています: ${entry.name}` });
      names.add(entry.name);
      if (entry.image && !imageExists(entry.image, ctx)) out.push({ level: 'warn', msg: `「${entry.name}」の画像が見つかりません: ${entry.image}` });
    }
    return out;
  }

  // シナリオ全体: [{eventId | null, level, msg, line?}]
  function validateScenario(bundle, ctx) {
    const out = [];
    for (const ev of ctx.events) {
      for (const issue of validateEvent(ev, ctx)) out.push({ eventId: ev.id, ...issue });
    }
    for (const issue of validateCast(bundle.cast, ctx)) out.push({ eventId: null, ...issue });
    for (const e of bundle.errors || []) out.push({ eventId: null, level: 'error', msg: e });
    return out;
  }

  return {
    KIND_STYLES, KIND_OPTIONS, SKILL_NAMES, SIDES, SYSTEM_SCENES, CONDITION_TYPES, EFFECT_TYPES, EVENT_ID,
    godotHash, fallbackImage, resolveImage, worldIndex, autoKind, gateSummary, effectiveKind,
    clone, normalizeSequential, insertLine, deleteLine, moveLine, defaultLine, stepTarget, edgesOf, reachable, endOutcomes, usedSpeakers,
    canonicalLine, canonicalEvent, uniqueId, newGateEvent, newConditionEvent, newSystemEvent,
    describeCondition, describeEffect, validateEvent, validateCast, validateScenario, imageExists,
  };
});
