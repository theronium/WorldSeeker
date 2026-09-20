'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const { createServer, config } = require('../server.js');

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
  assert.ok(d && d.source === 'default' && d.eventCount === 170, JSON.stringify(d));
});

test('カスタムをデフォルトからコピーして作り、イベントを保存・削除できる', async () => {
  let r = await api('POST', '/api/scenarios', { source: 'custom', id: 'my_story', name: '私の物語', copyFrom: { source: 'default', id: 'default' } });
  assert.strictEqual(r.status, 201);
  r = await api('GET', '/api/scenarios/custom/my_story');
  assert.strictEqual(r.data.meta.name, '私の物語');
  assert.strictEqual(r.data.meta.id, 'my_story');
  assert.strictEqual(r.data.events.length, 170);
  assert.strictEqual(r.data.world.nodes.length, 194);
  assert.deepStrictEqual(r.data.errors, []);

  const ev = { id: 'my_event', title: 'テスト', trigger: { type: 'conditions' }, conditions: [], repeat: false, priority: 0, kind: '', script: [{ side: 'none', name: '', text: 'やあ', outcome: 'ok' }], effects: [] };
  r = await api('PUT', '/api/scenarios/custom/my_story/events/my_event', ev);
  assert.strictEqual(r.status, 200);
  const onDisk = fs.readFileSync(path.join(config.customRoot, 'my_story', 'events', 'my_event.json'), 'utf8');
  assert.strictEqual(onDisk, JSON.stringify(ev, null, 2) + '\n');
  r = await api('GET', '/api/scenarios/custom/my_story');
  assert.strictEqual(r.data.events.length, 171);

  r = await api('DELETE', '/api/scenarios/custom/my_story/events/my_event');
  assert.strictEqual(r.status, 200);
  r = await api('DELETE', '/api/scenarios/custom/my_story/events/my_event');
  assert.strictEqual(r.status, 404);

  // デフォルトのシナリオには影響しない
  assert.strictEqual((await api('GET', '/api/scenarios/default/default')).data.events.length, 170);
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
