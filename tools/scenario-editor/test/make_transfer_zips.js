'use strict';
// ゲームのシナリオ取り込み(godot/scripts/scenario_transfer.gd)の確認用に、エディタの書き出し(server.jsのbuildScenarioZip)で
// 作ったzipと、いろいろな不正なzipを、<出力先>へ書く。tools/dev/sim_scenario_transfer.gd が、これを読む。
//   node test/make_transfer_zips.js <出力先ディレクトリ>
const fs = require('fs');
const path = require('path');
const { buildScenarioZip } = require('../server.js');
const zip = require('../zip.js');

const out = process.argv[2];
if (!out) { console.error('使い方: node make_transfer_zips.js <出力先>'); process.exit(1); }
fs.mkdirSync(out, { recursive: true });
const DEFAULT_DIR = path.resolve(__dirname, '..', '..', '..', 'godot', 'scenarios', 'default');
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
const j = (value) => Buffer.from(JSON.stringify(value));
const write = (name, buffer) => fs.writeFileSync(path.join(out, name), buffer);

(async () => {
  const base = zip.readZip(await buildScenarioZip(DEFAULT_DIR, 'default'));
  const entryOf = (entries, name) => entries.find((e) => e.name === name);
  const rebuild = (entries) => zip.createZip(entries.map((e) => ({ name: e.name, data: e.data, store: e.name.endsWith('.png') })));
  const withScenario = (entries, patch) => entries.map((e) => (e.name === 'scenario.json' ? { name: e.name, data: j({ ...JSON.parse(e.data.toString('utf8')), ...patch }) } : e));
  const mutateWorld = (entries, mutate) => entries.map((e) => {
    if (e.name !== 'world.json') return e;
    const world = JSON.parse(e.data.toString('utf8'));
    mutate(world);
    return { name: e.name, data: j(world) };
  });

  // 正常: 画像付き。ID transfer_one、名前「持ち込み試験」
  const one = [...withScenario(base, { id: 'transfer_one', name: '持ち込み試験', author: '試験者', description: '取り込みの確認用' }), { name: 'images/hero.png', data: PNG }];
  write('transfer_one.zip', rebuild(one));
  // 正常: 同じIDで、名前とイベントの数が違う(上書きの確認用)
  const events = one.filter((e) => e.name.startsWith('events/')).slice(0, 5).map((e) => e.name);
  const two = withScenario(base, { id: 'transfer_one', name: '持ち込み試験(改訂版)' }).filter((e) => !e.name.startsWith('events/') || events.includes(e.name));
  write('transfer_two.zip', rebuild(two));
  write('expected.json', j({ one_events: one.filter((e) => e.name.startsWith('events/')).length, two_events: two.filter((e) => e.name.startsWith('events/')).length, floors: JSON.parse(entryOf(base, 'world.json').data.toString('utf8')).nodes.length }));

  // 正常: ../ や余計なファイルが混ざっている(無視されて、外へは書かれない)
  write('traversal.zip', rebuild([...withScenario(base, { id: 'transfer_trav', name: '相対パス試験' }),
    { name: '../evil.txt', data: Buffer.from('x') }, { name: 'events/../../escape.json', data: Buffer.from('{}') }, { name: 'notes.txt', data: Buffer.from('memo') }]));

  // 不正
  const saves = base.map((e) => (e.name === 'manifest.json' ? { name: e.name, data: j({ format: 'worldseeker-saves', version: 1 }) } : e));
  write('bad_saves_format.zip', rebuild(saves));
  write('bad_newer_version.zip', rebuild(base.map((e) => (e.name === 'manifest.json' ? { name: e.name, data: j({ format: 'worldseeker-scenario', version: 99 }) } : e))));
  write('bad_no_manifest.zip', rebuild(base.filter((e) => e.name !== 'manifest.json')));
  write('bad_id.zip', rebuild(withScenario(base, { id: 'Bad-ID' })));
  write('bad_skill.zip', rebuild(mutateWorld(withScenario(base, { id: 'transfer_bad' }), (w) => { w.nodes.find((n) => n.gate.type === 'skill').gate.skill = 'NOPE'; })));
  write('bad_gate_key.zip', rebuild(mutateWorld(withScenario(base, { id: 'transfer_bad' }), (w) => { delete w.nodes.find((n) => n.gate.type === 'skill').gate.min_level; })));
  write('bad_section.zip', rebuild(mutateWorld(withScenario(base, { id: 'transfer_bad' }), (w) => { w.nodes[3].section = 'no_such_section'; })));
  write('bad_duplicate.zip', rebuild(mutateWorld(withScenario(base, { id: 'transfer_bad' }), (w) => { w.nodes.push({ ...w.nodes[0] }); })));
  const eventEntry = { name: 'events/zip_test_event.json', data: j({ id: 'zip_test_event', title: 'テスト', trigger: { type: 'conditions' }, conditions: [{ type: 'day_min', day: 3 }], repeat: false, priority: 0, kind: '', script: [{ side: 'none', name: '', text: 'x', outcome: 'ok' }], effects: [{ on: '*', type: 'funds' }] }) };
  write('bad_effect.zip', rebuild([...withScenario(base, { id: 'transfer_bad' }), eventEntry])); // 効果にamount無し
  write('bad_image.zip', rebuild([...withScenario(base, { id: 'transfer_bad' }), { name: 'images/fake.png', data: Buffer.from('not a png at all, only text') }]));
  write('not_a_zip.zip', Buffer.from('これはzipではありません。ただの文字列です。これはzipではありません。'));
  // 展開爆弾: 申告された展開後の大きさが嘘(中央ディレクトリを書き換える)
  const bomb = zip.createZip([{ name: 'manifest.json', data: Buffer.alloc(300000, 0x20) }]);
  bomb.writeUInt32LE(20 * 1024 * 1024, bomb.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02])) + 24);
  write('bad_bomb.zip', bomb);
  console.log(`書き出しました: ${out}(${fs.readdirSync(out).length}ファイル)`);
})().catch((e) => { console.error(e); process.exit(1); });
