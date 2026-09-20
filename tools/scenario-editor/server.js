#!/usr/bin/env node
'use strict';
// シナリオ・イベントエディタのローカルサーバー(docs/scenario_editor.md)。依存パッケージなし(Node.js 18以上)。
//
//   node server.js [--port 8765] [--custom-root <dir>] [--default-root <dir>]
//
// ブラウザ単体ではディスク上のフォルダを自由に読み書きできないため、このサーバーがシナリオのフォルダと画像を扱う。
//   デフォルトシナリオ: <リポジトリ>/godot/scenarios/<id>/            (リポジトリに含めて公開する)
//   カスタムシナリオ:   %APPDATA%\Godot\app_userdata\WorldSeeker\scenarios\<id>\   (個人用。ゲームの user://scenarios と同じ場所)
// 127.0.0.1 にだけ待ち受ける。変更系のAPIは、別のサイトからの操作を防ぐため、独自ヘッダ X-WS-Editor を必須にしている。

const http = require('http');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const os = require('os');
const { spawn } = require('child_process');

const REPO_ROOT = path.resolve(__dirname, '..', '..');

function argValue(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function defaultCustomRoot() {
  if (process.env.WS_CUSTOM_ROOT) return process.env.WS_CUSTOM_ROOT;
  if (process.platform === 'win32' && process.env.APPDATA) {
    return path.join(process.env.APPDATA, 'Godot', 'app_userdata', 'WorldSeeker', 'scenarios');
  }
  if (process.platform === 'darwin') {
    return path.join(os.homedir(), 'Library', 'Application Support', 'Godot', 'app_userdata', 'WorldSeeker', 'scenarios');
  }
  return path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share'), 'godot', 'app_userdata', 'WorldSeeker', 'scenarios');
}

const config = {
  port: Number(argValue('--port') || process.env.PORT || 8765),
  defaultRoot: path.resolve(argValue('--default-root') || path.join(REPO_ROOT, 'godot', 'scenarios')),
  customRoot: path.resolve(argValue('--custom-root') || defaultCustomRoot()),
  libraryDir: path.resolve(argValue('--library-dir') || path.join(REPO_ROOT, 'godot', 'assets', 'portraits')),
  publicDir: path.join(__dirname, 'public'),
};

const SCENARIO_ID = /^[a-z][a-z0-9_]{1,40}$/;
const EVENT_ID = /^[a-z0-9][a-z0-9_]{0,80}$/;
const IMAGE_NAME = /^[A-Za-z0-9_-]{1,60}\.png$/;
const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
const MAX_JSON_BYTES = 2 * 1024 * 1024;

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

function rootFor(source) {
  if (source === 'default') return config.defaultRoot;
  if (source === 'custom') return config.customRoot;
  throw new HttpError(400, `不明な種別: ${source}`);
}

function scenarioDir(source, id) {
  if (!SCENARIO_ID.test(id)) throw new HttpError(400, `シナリオIDが正しくありません: ${id}`);
  return path.join(rootFor(source), id);
}

// JSONは整形(インデント2、キー順は入れた順)+末尾に改行。ゲーム(ScenarioStore.write_json)と同じ書式にして、Gitの差分を小さくする
function stringify(data) { return JSON.stringify(data, null, 2) + '\n'; }

async function exists(p) { try { await fsp.access(p); return true; } catch { return false; } }

async function readJson(p, fallback) {
  try { return JSON.parse(await fsp.readFile(p, 'utf8')); }
  catch (e) { if (e.code === 'ENOENT' && fallback !== undefined) return fallback; throw e; }
}

async function writeJson(p, data) {
  await fsp.mkdir(path.dirname(p), { recursive: true });
  const tmp = p + '.tmp';
  await fsp.writeFile(tmp, stringify(data), 'utf8');
  await fsp.rename(tmp, p); // 書き込み途中で壊れないように、一時ファイル経由で置き換える
}

function pngInfo(buffer) {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (buffer.length < 24 || !buffer.subarray(0, 8).equals(signature)) return null;
  return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
}

// --- シナリオ ---

async function listScenarios() {
  const result = [];
  for (const source of ['default', 'custom']) {
    let names = [];
    try { names = await fsp.readdir(rootFor(source)); } catch { continue; }
    for (const id of names.sort()) {
      if (!SCENARIO_ID.test(id)) continue;
      const meta = await readJson(path.join(rootFor(source), id, 'scenario.json'), null).catch(() => null);
      if (!meta) continue;
      let eventCount = 0;
      try { eventCount = (await fsp.readdir(path.join(rootFor(source), id, 'events'))).filter((f) => f.endsWith('.json')).length; } catch { /* イベント無し */ }
      result.push({ source, id, name: meta.name || id, description: meta.description || '', author: meta.author || '', eventCount });
    }
  }
  return result;
}

async function listImages(dir) {
  const out = [];
  let names = [];
  try { names = await fsp.readdir(path.join(dir, 'images')); } catch { return out; }
  for (const name of names.sort()) {
    if (!IMAGE_NAME.test(name)) continue;
    const buffer = await fsp.readFile(path.join(dir, 'images', name));
    const info = pngInfo(buffer);
    out.push({ name, size: buffer.length, width: info ? info.width : 0, height: info ? info.height : 0 });
  }
  return out;
}

async function loadBundle(source, id) {
  const dir = scenarioDir(source, id);
  const meta = await readJson(path.join(dir, 'scenario.json'), null);
  if (!meta) throw new HttpError(404, 'シナリオが見つかりません');
  const world = await readJson(path.join(dir, 'world.json'), { items: [], areas: [], sections: [], nodes: [] });
  const cast = await readJson(path.join(dir, 'cast.json'), []);
  const events = [];
  const errors = [];
  let files = [];
  try { files = (await fsp.readdir(path.join(dir, 'events'))).filter((f) => f.endsWith('.json')).sort(); } catch { /* イベント無し */ }
  for (const file of files) {
    try {
      const event = await readJson(path.join(dir, 'events', file));
      if (event.id !== file.slice(0, -5)) errors.push(`events/${file}: idとファイル名が一致しません`);
      events.push(event);
    } catch (e) { errors.push(`events/${file}: 読み込めません(${e.message})`); }
  }
  return { source, id, meta, world, cast, events, errors, images: await listImages(dir) };
}

function validateEventShape(event, eventId) {
  if (!event || typeof event !== 'object') throw new HttpError(400, 'イベントの形式が正しくありません');
  if (event.id !== eventId) throw new HttpError(400, 'イベントのidとURLが一致しません');
  if (!event.trigger || typeof event.trigger.type !== 'string') throw new HttpError(400, 'triggerがありません');
  if (!Array.isArray(event.script)) throw new HttpError(400, 'scriptがありません');
  for (const key of ['conditions', 'effects']) {
    if (event[key] !== undefined && !Array.isArray(event[key])) throw new HttpError(400, `${key}は配列にしてください`);
  }
}

async function copyDir(from, to) {
  await fsp.mkdir(to, { recursive: true });
  for (const entry of await fsp.readdir(from, { withFileTypes: true })) {
    const src = path.join(from, entry.name);
    const dst = path.join(to, entry.name);
    if (entry.isDirectory()) await copyDir(src, dst);
    else await fsp.copyFile(src, dst);
  }
}

const BLANK_WORLD = {
  items: [],
  areas: [{ id: 'area_1', name: '最初のエリア' }],
  sections: [{ id: 'section_1', name: '最初のセクション', area: 'area_1' }],
  nodes: [
    { id: 'start', name: '出発点', section: 'section_1', connections: ['first_gate'], gate: {}, item_reward: '', initially_passed: true },
    { id: 'first_gate', name: '最初の関門', section: 'section_1', connections: ['start'], gate: { type: 'combat', enemy_power: 30 }, item_reward: '', initially_passed: false },
  ],
};

async function createScenario(body) {
  const { source, id, name } = body;
  if (source !== 'default' && source !== 'custom') throw new HttpError(400, '種別が正しくありません');
  const dir = scenarioDir(source, id);
  if (await exists(dir)) throw new HttpError(409, `同じIDのシナリオが既にあります: ${id}`);
  if (body.copyFrom) {
    const from = scenarioDir(body.copyFrom.source, body.copyFrom.id);
    if (!(await exists(from))) throw new HttpError(404, 'コピー元のシナリオが見つかりません');
    await copyDir(from, dir);
    const meta = await readJson(path.join(dir, 'scenario.json'));
    await writeJson(path.join(dir, 'scenario.json'), { ...meta, id, name: name || meta.name });
  } else {
    await writeJson(path.join(dir, 'scenario.json'), { format: 1, id, name: name || id, description: '', author: '', start_year: 0, start_month: 1 });
    await writeJson(path.join(dir, 'world.json'), BLANK_WORLD);
    await writeJson(path.join(dir, 'cast.json'), []);
    await fsp.mkdir(path.join(dir, 'events'), { recursive: true });
  }
  return { source, id };
}

// --- ルーティング ---

function sendJson(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(body);
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) { reject(new HttpError(413, 'データが大きすぎます')); req.destroy(); return; }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

async function readJsonBody(req) {
  const buffer = await readBody(req, MAX_JSON_BYTES);
  try { return JSON.parse(buffer.toString('utf8')); } catch { throw new HttpError(400, 'JSONとして読めません'); }
}

async function serveFile(res, filePath, extraHeaders = {}) {
  try {
    const data = await fsp.readFile(filePath);
    res.writeHead(200, { 'Content-Type': MIME[path.extname(filePath)] || 'application/octet-stream', 'Cache-Control': 'no-store', ...extraHeaders });
    res.end(data);
  } catch { throw new HttpError(404, 'ファイルが見つかりません'); }
}

function safeJoin(base, relative) {
  const target = path.resolve(base, relative);
  if (target !== base && !target.startsWith(base + path.sep)) throw new HttpError(400, '不正なパスです');
  return target;
}

async function handleApi(req, res, url) {
  const parts = url.pathname.split('/').filter(Boolean).slice(1).map(decodeURIComponent); // 'api'を除く
  const method = req.method;

  if (method === 'GET' && parts[0] === 'info' && parts.length === 1) {
    return sendJson(res, 200, { defaultRoot: config.defaultRoot, customRoot: config.customRoot, libraryDir: config.libraryDir });
  }
  if (method === 'GET' && parts[0] === 'library' && parts.length === 1) {
    const files = (await fsp.readdir(config.libraryDir)).filter((f) => /^(npc|enemy|char)_\d+\.png$/.test(f)).sort();
    return sendJson(res, 200, files.map((f) => ({ id: f.slice(0, -4), group: f.split('_')[0] })));
  }
  if (parts[0] !== 'scenarios') throw new HttpError(404, 'APIが見つかりません');

  if (parts.length === 1) {
    if (method === 'GET') return sendJson(res, 200, await listScenarios());
    if (method === 'POST') return sendJson(res, 201, await createScenario(await readJsonBody(req)));
  }

  const [, source, id, section, name] = parts;
  const dir = scenarioDir(source, id);
  if (parts.length === 3) {
    if (method === 'GET') return sendJson(res, 200, await loadBundle(source, id));
    if (method === 'DELETE') {
      if (!(await exists(dir))) throw new HttpError(404, 'シナリオが見つかりません');
      if (source === 'default' && id === 'default') throw new HttpError(400, '標準のシナリオ(default)は削除できません');
      await fsp.rm(dir, { recursive: true, force: true });
      return sendJson(res, 200, { ok: true });
    }
  }
  if (!(await exists(path.join(dir, 'scenario.json')))) throw new HttpError(404, 'シナリオが見つかりません');

  if (parts.length === 4 && method === 'PUT' && (section === 'meta' || section === 'cast')) {
    const body = await readJsonBody(req);
    if (section === 'meta' && (typeof body !== 'object' || Array.isArray(body) || !body.name)) throw new HttpError(400, '名前が必要です');
    if (section === 'cast' && !Array.isArray(body)) throw new HttpError(400, '配列にしてください');
    await writeJson(path.join(dir, section === 'meta' ? 'scenario.json' : 'cast.json'), section === 'meta' ? { ...body, id } : body);
    return sendJson(res, 200, { ok: true });
  }
  if (parts.length === 5 && section === 'events') {
    if (!EVENT_ID.test(name)) throw new HttpError(400, `イベントIDが正しくありません: ${name}`);
    const file = path.join(dir, 'events', `${name}.json`);
    if (method === 'PUT') {
      const event = await readJsonBody(req);
      validateEventShape(event, name);
      await writeJson(file, event);
      return sendJson(res, 200, { ok: true });
    }
    if (method === 'DELETE') {
      if (!(await exists(file))) throw new HttpError(404, 'イベントが見つかりません');
      await fsp.unlink(file);
      return sendJson(res, 200, { ok: true });
    }
  }
  if (section === 'images') {
    if (parts.length === 4 && method === 'POST') {
      const imageName = url.searchParams.get('name') || '';
      if (!IMAGE_NAME.test(imageName)) throw new HttpError(400, '画像のファイル名は、英数字・_・-と「.png」にしてください');
      const buffer = await readBody(req, MAX_IMAGE_BYTES);
      if (!pngInfo(buffer)) throw new HttpError(400, 'PNG画像ではありません');
      await fsp.mkdir(path.join(dir, 'images'), { recursive: true });
      await fsp.writeFile(path.join(dir, 'images', imageName), buffer);
      return sendJson(res, 200, await listImages(dir));
    }
    if (parts.length === 5 && method === 'DELETE') {
      if (!IMAGE_NAME.test(name)) throw new HttpError(400, 'ファイル名が正しくありません');
      await fsp.rm(path.join(dir, 'images', name), { force: true });
      return sendJson(res, 200, await listImages(dir));
    }
  }
  throw new HttpError(404, 'APIが見つかりません');
}

async function handle(req, res) {
  const url = new URL(req.url, 'http://localhost');
  // DNSリバインディング対策: 自分宛て(localhost/127.0.0.1)以外のHostは受け付けない
  if (!/^(localhost|127\.0\.0\.1)(:\d+)?$/.test(req.headers.host || '')) throw new HttpError(403, '許可されていないホストです');
  if (url.pathname.startsWith('/api/')) {
    if (req.method !== 'GET' && req.headers['x-ws-editor'] !== '1') throw new HttpError(403, '変更にはX-WS-Editorヘッダが必要です');
    return handleApi(req, res, url);
  }
  if (req.method !== 'GET') throw new HttpError(405, '許可されていないメソッドです');

  let m;
  if ((m = url.pathname.match(/^\/library\/((?:npc|enemy|char)_\d+)\.png$/))) {
    return serveFile(res, path.join(config.libraryDir, `${m[1]}.png`));
  }
  if ((m = url.pathname.match(/^\/scenario-images\/(default|custom)\/([a-z][a-z0-9_]+)\/([A-Za-z0-9_-]+\.png)$/))) {
    return serveFile(res, path.join(scenarioDir(m[1], m[2]), 'images', m[3]));
  }
  const relative = url.pathname === '/' ? 'index.html' : decodeURIComponent(url.pathname.slice(1));
  return serveFile(res, safeJoin(config.publicDir, relative));
}

function createServer() {
  return http.createServer((req, res) => {
    handle(req, res).catch((err) => {
      if (res.headersSent) { res.end(); return; }
      const status = err instanceof HttpError ? err.status : 500;
      if (status === 500) console.error(err);
      sendJson(res, status, { error: err.message });
    });
  });
}

// 既定のブラウザでURLを開く(--open指定時)。サーバーが待ち受けを始めてから呼ぶので、接続エラーにならない
function openBrowser(url) {
  const [command, args] = process.platform === 'win32' ? ['cmd', ['/c', 'start', '', url]]
    : process.platform === 'darwin' ? ['open', [url]] : ['xdg-open', [url]];
  try { spawn(command, args, { stdio: 'ignore', detached: true }).on('error', () => {}).unref(); } catch { /* 開けなくても続行(URLは表示してある) */ }
}

if (require.main === module) {
  const url = `http://localhost:${config.port}/`;
  const shouldOpen = process.argv.includes('--open');
  const server = createServer();
  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      // 既に起動している(前回のサーバーが残っている)ことが多いので、それを開く
      console.log(`ポート${config.port}は既に使われています。既に起動しているエディタを開きます: ${url}`);
      if (shouldOpen) openBrowser(url);
    } else {
      console.error(err);
      process.exitCode = 1;
    }
  });
  server.listen(config.port, '127.0.0.1', () => {
    console.log(`シナリオ・イベントエディタ: ${url}`);
    console.log(`  デフォルト: ${config.defaultRoot}`);
    console.log(`  カスタム:   ${config.customRoot}`);
    console.log('(終了するには、このウィンドウを閉じるか Ctrl+C)');
    if (shouldOpen) openBrowser(url);
  });
}

module.exports = { createServer, config };
