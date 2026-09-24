'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const { createServer, config } = require('../server.js');
const { createZip, readZip } = require('../zip.js');

const REAL_DEFAULT = path.resolve(__dirname, '..', '..', '..', 'godot', 'scenarios');
// 最小のPNG(1x1)
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');

let server;
let base;
let tmp;

test.before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ws-editor-'));
  fs.cpSync(REAL_DEFAULT, path.join(tmp, 'default_root'), { recursive: true });
  config.defaultRoot = path.join(tmp, 'default_root');
  config.customRoot = path.join(tmp, 'custom_root');
  server = createServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
test.after(() => { server.close(); fs.rmSync(tmp, { recursive: true, force: true }); });

async function api(method, url, body, headers = {}) {
  const init = { method, headers: { 'X-WS-Editor': '1', ...headers } };
  if (body !== undefined) {
    if (Buffer.isBuffer(body)) init.body = body;
    else { init.body = JSON.stringify(body); init.headers['Content-Type'] = 'application/json'; }
  }
  const res = await fetch(base + url, init);
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = text; }
  return { status: res.status, data };
}

test('一覧: デフォルトが出る', async () => {
  const { status, data } = await api('GET', '/api/scenarios');
  assert.strictEqual(status, 200);
  const d = data.find((s) => s.id === 'default');
  assert.ok(d && d.source === 'default' && d.eventCount === 172, JSON.stringify(d));
});

test('カスタムをデフォルトからコピーして作り、イベントを保存・削除できる', async () => {
  let r = await api('POST', '/api/scenarios', { source: 'custom', id: 'my_story', name: '私の物語', copyFrom: { source: 'default', id: 'default' } });
  assert.strictEqual(r.status, 201);
  r = await api('GET', '/api/scenarios/custom/my_story');
  assert.strictEqual(r.data.meta.name, '私の物語');
  assert.strictEqual(r.data.meta.id, 'my_story');
  assert.strictEqual(r.data.events.length, 172);
  assert.strictEqual(r.data.world.nodes.length, 196);
  assert.deepStrictEqual(r.data.errors, []);

  const ev = { id: 'my_event', title: 'テスト', trigger: { type: 'conditions' }, conditions: [], repeat: false, priority: 0, kind: '', script: [{ side: 'none', name: '', text: 'やあ', outcome: 'ok' }], effects: [] };
  r = await api('PUT', '/api/scenarios/custom/my_story/events/my_event', ev);
  assert.strictEqual(r.status, 200);
  const onDisk = fs.readFileSync(path.join(config.customRoot, 'my_story', 'events', 'my_event.json'), 'utf8');
  assert.strictEqual(onDisk, JSON.stringify(ev, null, 2) + '\n');
  r = await api('GET', '/api/scenarios/custom/my_story');
  assert.strictEqual(r.data.events.length, 173);

  r = await api('DELETE', '/api/scenarios/custom/my_story/events/my_event');
  assert.strictEqual(r.status, 200);
  r = await api('DELETE', '/api/scenarios/custom/my_story/events/my_event');
  assert.strictEqual(r.status, 404);

  // デフォルトのシナリオには影響しない
  assert.strictEqual((await api('GET', '/api/scenarios/default/default')).data.events.length, 172);
});

test('登場人物表とメタ情報の保存', async () => {
  let r = await api('PUT', '/api/scenarios/custom/my_story/cast', [{ name: 'テスト人', image: 'npc_03', side: 'left' }]);
  assert.strictEqual(r.status, 200);
  r = await api('PUT', '/api/scenarios/custom/my_story/meta', { format: 1, id: 'ignored', name: '改名', description: 'd', author: 'a', start_year: 7, start_month: 3 });
  assert.strictEqual(r.status, 200);
  r = await api('GET', '/api/scenarios/custom/my_story');
  assert.deepStrictEqual(r.data.cast, [{ name: 'テスト人', image: 'npc_03', side: 'left' }]);
  assert.strictEqual(r.data.meta.name, '改名');
  assert.strictEqual(r.data.meta.id, 'my_story'); // idはURLが正
  assert.strictEqual(r.data.meta.start_year, 7);
});

test('画像: PNGだけ受け付け、一覧と配信ができる', async () => {
  let r = await api('POST', '/api/scenarios/custom/my_story/images?name=hero.png', PNG);
  assert.strictEqual(r.status, 200);
  assert.deepStrictEqual(r.data.map((i) => [i.name, i.width, i.height]), [['hero.png', 1, 1]]);
  r = await api('POST', '/api/scenarios/custom/my_story/images?name=fake.png', Buffer.from('not a png at all, really not a png'));
  assert.strictEqual(r.status, 400);
  r = await api('POST', '/api/scenarios/custom/my_story/images?name=../evil.png', PNG);
  assert.strictEqual(r.status, 400);
  const img = await fetch(`${base}/scenario-images/custom/my_story/hero.png`);
  assert.strictEqual(img.status, 200);
  assert.strictEqual(img.headers.get('content-type'), 'image/png');
  r = await api('DELETE', '/api/scenarios/custom/my_story/images/hero.png');
  assert.deepStrictEqual(r.data, []);
});

test('マップの保存: 世界とイベントの書き換えを一緒に保存でき、不正な形は拒否する', async () => {
  let r = await api('GET', '/api/scenarios/custom/my_story');
  const world = r.data.world;
  const before = fs.readFileSync(path.join(config.customRoot, 'my_story', 'world.json'), 'utf8');
  // 何も変えずに保存し直しても、ファイルが変わらない
  r = await api('PUT', '/api/scenarios/custom/my_story/world', { world, events: [] });
  assert.strictEqual(r.status, 200);
  assert.strictEqual(fs.readFileSync(path.join(config.customRoot, 'my_story', 'world.json'), 'utf8'), before);

  // フロア名の変更 + 既存イベントの書き換え
  const changed = JSON.parse(JSON.stringify(world));
  changed.nodes[0].name = '改名した場所';
  const event = (await api('GET', '/api/scenarios/custom/my_story')).data.events.find((e) => e.trigger.type === 'gate');
  event.title = '書き換えたタイトル';
  r = await api('PUT', '/api/scenarios/custom/my_story/world', { world: changed, events: [event] });
  assert.deepStrictEqual(r.data, { ok: true, eventsUpdated: 1 });
  r = await api('GET', '/api/scenarios/custom/my_story');
  assert.strictEqual(r.data.world.nodes[0].name, '改名した場所');
  assert.strictEqual(r.data.events.find((e) => e.id === event.id).title, '書き換えたタイトル');
  // デフォルトのシナリオには影響しない
  assert.notStrictEqual((await api('GET', '/api/scenarios/default/default')).data.world.nodes[0].name, '改名した場所');

  const bad = async (mutate, expected) => {
    const w = JSON.parse(JSON.stringify(world));
    mutate(w);
    const res = await api('PUT', '/api/scenarios/custom/my_story/world', { world: w, events: [] });
    assert.strictEqual(res.status, expected, JSON.stringify(res.data));
  };
  await bad((w) => { w.nodes.push({ ...w.nodes[0] }); }, 400); // ID重複
  await bad((w) => { w.nodes[0].id = 'Bad Id'; }, 400);
  await bad((w) => { delete w.sections; }, 400);
  await bad((w) => { w.nodes[0].connections = 'x'; }, 400);
  await bad((w) => { w.nodes[0].gate = []; }, 400);
  r = await api('PUT', '/api/scenarios/custom/my_story/world', { world, events: [{ ...event, id: 'no_such_event' }] });
  assert.strictEqual(r.status, 404); // 新しいイベントは、このAPIでは作れない
  r = await api('PUT', '/api/scenarios/custom/my_story/world', { world, events: [{ id: 'x', trigger: { type: 'conditions' } }] });
  assert.strictEqual(r.status, 400);
});

async function rawApi(method, url, body) {
  const res = await fetch(base + url, { method, headers: { 'X-WS-Editor': '1' }, body });
  const buffer = Buffer.from(await res.arrayBuffer());
  let data;
  try { data = JSON.parse(buffer.toString('utf8')); } catch { data = null; }
  return { status: res.status, headers: res.headers, buffer, data };
}

test('シナリオのzip: 書き出し→削除→取り込みで元どおりになり、同じIDは確認(409)、overwriteで上書き', async () => {
  const exported = await rawApi('GET', '/api/scenarios/custom/my_story/export');
  assert.strictEqual(exported.status, 200);
  assert.strictEqual(exported.headers.get('content-type'), 'application/zip');
  assert.ok(exported.headers.get('content-disposition').includes('worldseeker_scenario_my_story.zip'));
  const files = readZip(exported.buffer);
  const names = files.map((f) => f.name);
  assert.ok(['manifest.json', 'scenario.json', 'world.json', 'cast.json'].every((n) => names.includes(n)), names.slice(0, 6).join(','));
  assert.strictEqual(names.filter((n) => n.startsWith('events/')).length, 172);
  const manifest = JSON.parse(files.find((f) => f.name === 'manifest.json').data.toString('utf8'));
  assert.strictEqual(manifest.format, 'worldseeker-scenario');
  assert.strictEqual(manifest.id, 'my_story');

  const before = await api('GET', '/api/scenarios/custom/my_story');
  assert.strictEqual((await api('DELETE', '/api/scenarios/custom/my_story')).status, 200);
  let r = await rawApi('POST', '/api/scenarios/import?source=custom', exported.buffer);
  assert.strictEqual(r.status, 200, JSON.stringify(r.data));
  assert.strictEqual(r.data.id, 'my_story');
  assert.strictEqual(r.data.overwritten, false);
  assert.strictEqual(r.data.eventCount, 172);
  const after = await api('GET', '/api/scenarios/custom/my_story');
  assert.deepStrictEqual(after.data.world, before.data.world);
  assert.deepStrictEqual(after.data.events, before.data.events);
  assert.deepStrictEqual(after.data.meta, before.data.meta);
  assert.deepStrictEqual(after.data.cast, before.data.cast);

  r = await rawApi('POST', '/api/scenarios/import?source=custom', exported.buffer);
  assert.strictEqual(r.status, 409);
  assert.strictEqual(r.data.exists, true);
  assert.strictEqual(r.data.id, 'my_story');
  await api('PUT', '/api/scenarios/custom/my_story/cast', []); // 取り込みで元に戻ることを見るため、先に変える
  r = await rawApi('POST', '/api/scenarios/import?source=custom&overwrite=1', exported.buffer);
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.data.overwritten, true);
  assert.deepStrictEqual((await api('GET', '/api/scenarios/custom/my_story')).data.cast, before.data.cast);
  assert.deepStrictEqual(fs.readdirSync(config.customRoot).filter((n) => n.startsWith('.')), [], '一時フォルダが残っていない');
});

test('シナリオのzip: 画像も往復し、標準のシナリオ(default)は上書きできない', async () => {
  assert.strictEqual((await api('POST', '/api/scenarios/custom/my_story/images?name=hero.png', PNG)).status, 200);
  const exported = await rawApi('GET', '/api/scenarios/custom/my_story/export');
  assert.ok(readZip(exported.buffer).some((f) => f.name === 'images/hero.png' && f.data.equals(PNG)));
  await api('DELETE', '/api/scenarios/custom/my_story');
  assert.strictEqual((await rawApi('POST', '/api/scenarios/import?source=custom', exported.buffer)).status, 200);
  assert.strictEqual((await fetch(`${base}/scenario-images/custom/my_story/hero.png`)).status, 200);
  await api('DELETE', '/api/scenarios/custom/my_story/images/hero.png');

  // 標準のシナリオ(default/default)を、zipで上書きすることはできない(カスタムに同じIDで入れるのは可)
  const std = await rawApi('GET', '/api/scenarios/default/default/export');
  assert.strictEqual((await rawApi('POST', '/api/scenarios/import?source=default&overwrite=1', std.buffer)).status, 400);
  assert.strictEqual((await rawApi('POST', '/api/scenarios/import?source=custom', std.buffer)).status, 200);
  assert.strictEqual((await api('DELETE', '/api/scenarios/custom/default')).status, 200);
});

test('シナリオのzip: 不正なファイルを拒否する(zipでない・形式違い・不正なゲート/イベント/ID・展開爆弾)', async () => {
  const good = readZip((await rawApi('GET', '/api/scenarios/default/default/export')).buffer);
  const get = (name) => good.find((f) => f.name === name).data;
  const json = (name) => JSON.parse(get(name).toString('utf8'));
  const build = (mutate) => {
    const entries = good.map((f) => ({ ...f }));
    mutate(entries);
    return createZip(entries.map((e) => ({ name: e.name, data: Buffer.isBuffer(e.data) ? e.data : Buffer.from(JSON.stringify(e.data)) })));
  };
  const setJson = (entries, name, value) => { entries.find((e) => e.name === name).data = Buffer.from(JSON.stringify(value)); };
  const expectRejected = async (label, buffer, pattern) => {
    const r = await rawApi('POST', '/api/scenarios/import?source=custom&overwrite=1', buffer);
    assert.strictEqual(r.status, 400, `${label}: ${r.status} ${JSON.stringify(r.data)}`);
    if (pattern) assert.match(r.data.error, pattern, label);
  };
  assert.ok(good.length > 100);

  await expectRejected('zipでない', Buffer.from('not a zip file at all, just some plain text here'), /zip/);
  await expectRejected('マニフェスト無し', build((e) => e.splice(e.findIndex((x) => x.name === 'manifest.json'), 1)), /シナリオのファイルではありません/);
  await expectRejected('セーブのファイル', build((e) => setJson(e, 'manifest.json', { format: 'worldseeker-saves', version: 1 })), /セーブのファイル/);
  await expectRejected('新しい版', build((e) => setJson(e, 'manifest.json', { format: 'worldseeker-scenario', version: 99 })), /新しい版/);
  await expectRejected('IDが不正', build((e) => setJson(e, 'scenario.json', { ...json('scenario.json'), id: '../evil' })), /ID/);
  await expectRejected('必須ファイル無し', build((e) => e.splice(e.findIndex((x) => x.name === 'world.json'), 1)), /必須ファイル/);
  const badWorld = (mutate) => build((e) => { const w = json('world.json'); mutate(w); setJson(e, 'world.json', w); });
  await expectRejected('不正な技能名', badWorld((w) => { w.nodes.find((n) => n.gate.type === 'skill').gate.skill = 'NOPE'; }), /技能/);
  await expectRejected('技能ゲートにレベル無し', badWorld((w) => { delete w.nodes.find((n) => n.gate.type === 'skill').gate.min_level; }), /必要レベル/);
  await expectRejected('不明なゲート種別', badWorld((w) => { w.nodes[3].gate = { type: 'magic' }; }), /種類/);
  await expectRejected('IDの重複', badWorld((w) => { w.nodes.push({ ...w.nodes[0] }); }), /重複/);
  const baseEvent = () => ({ id: 'zip_test_event', title: 'テスト', trigger: { type: 'conditions' }, conditions: [{ type: 'day_min', day: 3 }], repeat: false, priority: 0, kind: '', script: [{ side: 'none', name: '', text: 'x', outcome: 'ok' }], effects: [{ on: '*', type: 'funds', amount: 100 }] });
  const withEvent = (mutate) => build((e) => { const ev = baseEvent(); mutate(ev); e.push({ name: 'events/zip_test_event.json', data: Buffer.from(JSON.stringify(ev)) }); });
  // 正常な例は通る(下の失敗が、変更した点のせいだと分かるように)
  const okResult = await rawApi('POST', '/api/scenarios/import?source=custom&overwrite=1', withEvent(() => {}));
  assert.strictEqual(okResult.status, 200, JSON.stringify(okResult.data));
  await expectRejected('効果のキー欠け', withEvent((ev) => { delete ev.effects[0].amount; }), /効果/);
  await expectRejected('効果の値の型', withEvent((ev) => { ev.effects[0].amount = 'many'; }), /効果/);
  await expectRejected('不明な効果', withEvent((ev) => { ev.effects[0].type = 'explode'; }), /効果/);
  await expectRejected('条件のキー欠け', withEvent((ev) => { delete ev.conditions[0].day; }), /条件/);
  await expectRejected('不明な発生のしかた', withEvent((ev) => { ev.trigger.type = 'magic'; }), /発生のしかた/);
  await expectRejected('選択肢が配列でない', withEvent((ev) => { ev.script[0].choices = 'x'; }), /選択肢/);
  await expectRejected('行がオブジェクトでない', withEvent((ev) => { ev.script.push('text'); }), /行/);
  await expectRejected('イベントIDとファイル名の不一致', withEvent((ev) => { ev.id = 'other_name'; }), /イベント/);
  await expectRejected('画像がPNGでない', build((e) => e.push({ name: 'images/fake.png', data: Buffer.from('not really a png, sorry') })), /PNG/);

  // 展開爆弾(申告された大きさが嘘)
  const bomb = createZip([{ name: 'manifest.json', data: Buffer.alloc(300000, 0x20) }]);
  bomb.writeUInt32LE(20, bomb.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02])) + 24);
  await expectRejected('展開爆弾', bomb, /zip/);
});

test('シナリオのzip: 決まった名前以外(../や余計なファイル)は無視され、外へは書かれない', async () => {
  const good = readZip((await rawApi('GET', '/api/scenarios/custom/my_story/export')).buffer);
  const entries = [...good, { name: '../evil.txt', data: Buffer.from('x') }, { name: 'events/../escape.json', data: Buffer.from('{}') }, { name: 'notes.txt', data: Buffer.from('memo') }, { name: 'images/..\\x.png', data: PNG }];
  const r = await rawApi('POST', '/api/scenarios/import?source=custom&overwrite=1', createZip(entries));
  assert.strictEqual(r.status, 200, JSON.stringify(r.data));
  assert.strictEqual(r.data.ignored, 4);
  assert.ok(!fs.existsSync(path.join(config.customRoot, '..', 'evil.txt')));
  assert.ok(!fs.existsSync(path.join(config.customRoot, 'my_story', 'notes.txt')));
  assert.ok(!fs.existsSync(path.join(config.customRoot, 'my_story', 'escape.json')));
  // ヘッダ無しの取り込みは拒否
  const res = await fetch(`${base}/api/scenarios/import?source=custom`, { method: 'POST', body: createZip(entries) });
  assert.strictEqual(res.status, 403);
});

test('ライブラリ画像の一覧と配信', async () => {
  const r = await api('GET', '/api/library');
  assert.ok(r.data.length >= 128, String(r.data.length));
  assert.ok(r.data.some((i) => i.id === 'npc_01' && i.group === 'npc'));
  const res = await fetch(`${base}/library/npc_01.png`);
  assert.strictEqual(res.status, 200);
});

test('安全: 変更にはヘッダが必要・不正なID/パス/Hostは拒否', async () => {
  let res = await fetch(`${base}/api/scenarios/custom/my_story/cast`, { method: 'PUT', body: '[]' });
  assert.strictEqual(res.status, 403);
  assert.strictEqual((await api('GET', '/api/scenarios/custom/Bad-ID')).status, 400);
  assert.strictEqual((await api('PUT', '/api/scenarios/custom/my_story/events/..%2Fescape', { id: '../escape', trigger: { type: 'conditions' }, script: [] })).status, 400);
  assert.strictEqual((await api('PUT', '/api/scenarios/custom/my_story/events/other', { id: 'mismatch', trigger: { type: 'conditions' }, script: [] })).status, 400);
  res = await fetch(`${base}/..%2F..%2Fserver.js`);
  assert.ok(res.status === 400 || res.status === 404);
  // Hostヘッダ(DNSリバインディング)
  const status = await new Promise((resolve) => {
    const req = http.request({ host: '127.0.0.1', port: server.address().port, path: '/', headers: { Host: 'evil.example.com' } }, (r) => { r.resume(); resolve(r.statusCode); });
    req.end();
  });
  assert.strictEqual(status, 403);
});

test('デフォルトは消せない・重複IDは拒否・空のシナリオを作れる', async () => {
  assert.strictEqual((await api('DELETE', '/api/scenarios/default/default')).status, 400);
  assert.strictEqual((await api('POST', '/api/scenarios', { source: 'custom', id: 'my_story', name: 'x' })).status, 409);
  let r = await api('POST', '/api/scenarios', { source: 'custom', id: 'blank_one', name: '空' });
  assert.strictEqual(r.status, 201);
  r = await api('GET', '/api/scenarios/custom/blank_one');
  assert.strictEqual(r.data.world.nodes.length, 2);
  assert.strictEqual(r.data.events.length, 0);
  assert.strictEqual((await api('DELETE', '/api/scenarios/custom/blank_one')).status, 200);
  assert.strictEqual((await api('GET', '/api/scenarios/custom/blank_one')).status, 404);
});
