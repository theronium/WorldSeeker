'use strict';
// node --test test/  で実行する。実際のデフォルトシナリオ(godot/scenarios/default)を使って、ロジックを確かめる。
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const L = require('../public/logic.js');

const DEFAULT_DIR = path.resolve(__dirname, '..', '..', '..', 'godot', 'scenarios', 'default');
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const world = readJson(path.join(DEFAULT_DIR, 'world.json'));
const cast = readJson(path.join(DEFAULT_DIR, 'cast.json'));
const eventFiles = fs.readdirSync(path.join(DEFAULT_DIR, 'events')).filter((f) => f.endsWith('.json')).sort();
const events = eventFiles.map((f) => readJson(path.join(DEFAULT_DIR, 'events', f)));
const idx = L.worldIndex(world);

test('godotHash: Godotの String.hash() と同じ値(Godotで実測した値)', () => {
  assert.strictEqual(L.godotHash('謎の旅人'), 3380140256);
  assert.strictEqual(L.godotHash('村長'), 6770989);
  assert.strictEqual(L.godotHash('🐉ドラゴン'), 2081734695);
  assert.strictEqual(L.fallbackImage('村長', ''), 'npc_14');
  assert.strictEqual(L.fallbackImage('村長', 'boss'), 'enemy_14');
});

test('デフォルトシナリオ: 保存し直しても、ファイルの中身が1バイトも変わらない(Gitの差分が出ない)', () => {
  for (const f of eventFiles) {
    // Gitの改行自動変換(autocrlf)でCRLFになっていても、中身の一致を見る
    const raw = fs.readFileSync(path.join(DEFAULT_DIR, 'events', f), 'utf8').replace(/
/g, '
');
    const rewritten = JSON.stringify(L.canonicalEvent(JSON.parse(raw)), null, 2) + '\n';
    assert.strictEqual(rewritten, raw, f);
  }
});

test('デフォルトシナリオ: 全イベントが検証を通る(エラー無し)', () => {
  const ctx = { idx, events, library: new Set(), scenarioImages: new Set() };
  const errors = [];
  for (const ev of events) for (const issue of L.validateEvent(ev, ctx)) if (issue.level === 'error') errors.push(`${ev.id}: ${issue.msg}`);
  assert.deepStrictEqual(errors, []);
});

test('種別の自動判定が、ゲームの集計(HANDOFF: 戦闘36フロアのうちボス戦29)と一致する', () => {
  let boss = 0;
  let combat = 0;
  for (const n of world.nodes) {
    if (n.gate && n.gate.type === 'combat') { if (L.autoKind(idx, n.id) === 'boss') boss++; else combat++; }
  }
  assert.strictEqual(boss, 29);
  assert.strictEqual(boss + combat, 36);
  assert.strictEqual(L.autoKind(idx, 'old_shrine'), 'skill');
  assert.strictEqual(L.autoKind(idx, 'goblin_treasury'), 'item');
  assert.strictEqual(L.autoKind(idx, 'border_checkpoint'), 'bloodline');
  assert.strictEqual(L.autoKind(idx, 'village'), '');
});

test('登場人物表: 案内人=npc_01、未登録の話者は名前から自動選択', () => {
  assert.strictEqual(L.resolveImage({ name: '案内人' }, cast, 'guide'), 'npc_01');
  assert.strictEqual(L.resolveImage({ name: '案内人', image: '@x.png' }, cast, 'guide'), '@x.png');
  assert.strictEqual(L.resolveImage({ name: '' }, cast, ''), '');
  assert.strictEqual(L.resolveImage({ name: '知らない人' }, cast, 'boss'), L.fallbackImage('知らない人', 'boss'));
});

// 分岐のある台本: 0 → 選択肢(1へ / 3へ) ; 1 → 2 ; 2 → 終了(a) ; 3 → 終了(b)
const branching = () => [
  { side: 'left', name: 'A', text: '0', choices: [{ label: 'x', next: 1 }, { label: 'y', next: 3 }] },
  { side: 'left', name: 'A', text: '1' },
  { side: 'left', name: 'A', text: '2', outcome: 'a' },
  { side: 'left', name: 'A', text: '3', outcome: 'b' },
];

test('行の挿入: 「次の行へ」の選択肢は新しい行へ流れ、飛び先は付け替わる', () => {
  const out = L.insertLine(branching(), 1, { side: 'none', name: '', text: 'new' });
  assert.strictEqual(out.length, 5);
  assert.deepStrictEqual(out[0].choices.map((c) => c.next), [undefined, 4]); // 1つ目=次の行(=新しい行)、2つ目=元の3行目(今は4番目)
  assert.strictEqual(out[2].text, '1');
});

test('行の削除: 消した行を指していた分岐は、次の行へ', () => {
  const out = L.deleteLine(branching(), 1);
  assert.strictEqual(out.length, 3);
  assert.deepStrictEqual(out[0].choices.map((c) => c.next), [undefined, 2]);
  assert.strictEqual(out[1].text, '2');
  const outEnd = L.deleteLine(branching(), 3);
  assert.deepStrictEqual(outEnd[0].choices.map((c) => c.next), [undefined, 3]); // 消した最後の行を指す分岐は範囲外=終了に落ちる
});

test('行の移動: 明示の分岐先を持つ台本は、どこへ動かしても流れ(どの文言からどの文言へ)が変わらない', () => {
  const flow = (script) => script.flatMap((l, i) => L.edgesOf(script, i).map((e) => `${l.text}->${e.end ? '終:' + e.outcome : script[e.to].text}`)).sort();
  const explicit = [
    { side: 'left', name: 'A', text: 'p', next: 2 },
    { side: 'left', name: 'A', text: 'q', outcome: 'end' },
    { side: 'left', name: 'A', text: 'r', next: 1 },
  ];
  for (let from = 0; from < 3; from++) {
    for (let to = 0; to < 3; to++) {
      assert.deepStrictEqual(flow(L.moveLine(explicit, from, to)), flow(explicit), `${from}->${to}`);
    }
  }
});

test('到達判定と終わりの結果コード', () => {
  const s = branching();
  assert.deepStrictEqual([...L.reachable(s)].sort(), [0, 1, 2, 3]);
  assert.deepStrictEqual([...L.endOutcomes(s)].sort(), ['a', 'b']);
  s[0].choices[1].next = 1; // 3が孤立する
  assert.ok(!L.reachable(s).has(3));
  const loop = [{ side: 'none', name: '', text: 'x', next: 0 }];
  assert.strictEqual(L.endOutcomes(loop).size, 0);
});

test('検証: 問題のあるイベントを見つける', () => {
  const ctx = (evs) => ({ idx, events: evs, library: new Set(['npc_01']), scenarioImages: new Set() });
  const bad = L.newGateEvent(idx, 'no_such_floor', 'pass', new Set());
  const messages = (ev) => L.validateEvent(ev, ctx([ev])).map((i) => `${i.level}:${i.msg}`);
  assert.ok(messages(bad).some((m) => m.startsWith('error:フロアが存在しません')));

  const gate = L.newGateEvent(idx, 'old_shrine', 'pass', new Set());
  gate.script[1].outcome = 'ok'; // フロアの会話がpass/failで終わらない
  assert.ok(messages(gate).some((m) => m.includes('pass か fail で終わる')));

  const dup = L.newGateEvent(idx, 'old_shrine', 'pass', new Set(['floor_old_shrine_pass']));
  const original = L.newGateEvent(idx, 'old_shrine', 'pass', new Set());
  assert.ok(L.validateEvent(dup, ctx([dup, original])).some((i) => i.msg.includes('同じフロア・同じ結果')));

  const cond = L.newConditionEvent('x', new Set());
  cond.conditions.push({ type: 'flag', flag: 'never_set', value: true });
  cond.effects.push({ on: 'nope', type: 'funds', amount: 10 });
  cond.script[0].choices = [{ label: '', next: 9 }];
  const m = messages(cond);
  assert.ok(m.some((x) => x.includes('never_set')));
  assert.ok(m.some((x) => x.includes('「nope」で終わる道')));
  assert.ok(m.some((x) => x.includes('ラベルが空')));
  assert.ok(m.some((x) => x.includes('行き先(10行目)がありません')));

  const sys = L.newSystemEvent('intro_part1', new Set());
  assert.deepStrictEqual(L.validateEvent(sys, ctx([sys])).filter((i) => i.level === 'error'), []);
});

test('雛形: 新しいイベントは検証を通る(エラー無し)', () => {
  const mk = [L.newGateEvent(idx, 'cave', 'pass', new Set()), L.newGateEvent(idx, 'cave', 'fail', new Set()), L.newConditionEvent('t', new Set()), L.newSystemEvent('retreat', new Set())];
  const c = { idx, events: mk, library: new Set(), scenarioImages: new Set() };
  for (const ev of mk) {
    assert.deepStrictEqual(L.validateEvent(ev, c).filter((i) => i.level === 'error'), [], ev.id);
  }
});

test('ゲームのデータ(全ての行にnext: i+1を明示)でも、挿入・削除・移動の後に「一覧の並び=会話の流れ」が保たれる', () => {
  const explicit = () => [
    { side: 'left', name: 'A', text: 'a', next: 1 },
    { side: 'left', name: 'A', text: 'b', next: 2 },
    { side: 'none', name: '', text: 'c', outcome: 'pass' },
  ];
  const order = (script) => { const seen = []; let i = 0; while (i < script.length && !seen.includes(i)) { seen.push(i); const e = L.edgesOf(script, i)[0]; if (e.end) break; i = e.to; } return seen.map((k) => script[k].text).join(''); };
  assert.strictEqual(order(explicit()), 'abc');
  assert.strictEqual(order(L.insertLine(explicit(), 1, { side: 'left', name: 'A', text: 'X' })), 'aXbc');
  assert.strictEqual(order(L.insertLine(explicit(), 3, { side: 'left', name: 'A', text: 'X' })), 'abc'); // 終わりの後ろに足した行は、流れに入らない(終わりの行が先に終える)
  assert.strictEqual(order(L.deleteLine(explicit(), 1)), 'ac');
  assert.strictEqual(order(L.moveLine(explicit(), 2, 0)), 'cab'.slice(0, 1)); // 終わりの行を先頭へ動かすと、そこで終わる
  assert.strictEqual(order(L.moveLine(explicit(), 0, 1)), 'bac'); // 1行目と2行目を入れ替えると、並びの順に流れる
});
