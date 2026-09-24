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

const zip = require('./zip.js');
const Logic = require('./public/logic.js');

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
  // extra: 応答のJSONに足す項目(例: 取り込みで同じIDが既にある時の {exists: true, id, name})
  constructor(status, message, extra) { super(message); this.status = status; this.extra = extra; }
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

const WORLD_ID = /^[a-z0-9][a-z0-9_]{0,60}$/;

// ゲートの形の検査。ゲームは、種類ごとの決まったキーを、存在を前提に読む(WorldMap.can_pass_gate)ので、無いと読み込み後にエラーになる。
// 技能名は、ゲームがSkillTypes.Skillの名前で引く(不正な名前は、読み込みの時点でエラーになる)
function validateGateShape(gate, floorId) {
  const type = gate.type;
  if (type === undefined) {
    if (Object.keys(gate).length) throw new HttpError(400, `フロア(${floorId})のゲートに種類がありません`);
    return;
  }
  const number = (key) => typeof gate[key] === 'number' && Number.isFinite(gate[key]);
  const text = (key) => typeof gate[key] === 'string';
  const bad = (what) => { throw new HttpError(400, `フロア(${floorId})のゲートの${what}が正しくありません`); };
  if (type === 'combat') { if (gate.enemy_power !== undefined && !number('enemy_power')) bad('敵の戦闘力'); }
  else if (type === 'skill') {
    if (!text('skill') || !Object.prototype.hasOwnProperty.call(Logic.SKILL_NAMES, gate.skill)) bad('技能');
    if (!number('min_level')) bad('必要レベル');
  } else if (type === 'item') { if (!text('item')) bad('アイテム'); }
  else if (type === 'innate_trait') { if (!text('trait') || !text('value')) bad('特性'); }
  else throw new HttpError(400, `フロア(${floorId})のゲートの種類が正しくありません: ${type}`);
}

// world.jsonの形の検査。意味の検証(参照の整合など)は、エディタ側(worldlogic.js)とゲームの読み込みが受け持つ。
// ここでは、ゲームが読めなくなるほどの形の崩れ(型・ID)だけを止める
function validateWorldShape(world) {
  if (!world || typeof world !== 'object' || Array.isArray(world)) throw new HttpError(400, 'マップの形式が正しくありません');
  for (const key of ['items', 'areas', 'sections', 'nodes']) {
    if (!Array.isArray(world[key])) throw new HttpError(400, `マップの${key}は配列にしてください`);
    const seen = new Set();
    for (const entry of world[key]) {
      if (!entry || typeof entry !== 'object' || typeof entry.id !== 'string' || !WORLD_ID.test(entry.id)) throw new HttpError(400, `マップの${key}に、IDが正しくない項目があります`);
      if (typeof entry.name !== 'string') throw new HttpError(400, `マップの${key}(${entry.id})に名前がありません`);
      if (seen.has(entry.id)) throw new HttpError(400, `マップの${key}にIDの重複があります: ${entry.id}`);
      seen.add(entry.id);
    }
  }
  for (const section of world.sections) if (typeof section.area !== 'string') throw new HttpError(400, `セクション(${section.id})にエリアがありません`);
  for (const node of world.nodes) {
    if (typeof node.section !== 'string') throw new HttpError(400, `フロア(${node.id})にセクションがありません`);
    if (!Array.isArray(node.connections) || node.connections.some((c) => typeof c !== 'string')) throw new HttpError(400, `フロア(${node.id})の接続が正しくありません`);
    if (!node.gate || typeof node.gate !== 'object' || Array.isArray(node.gate)) throw new HttpError(400, `フロア(${node.id})のゲートが正しくありません`);
    validateGateShape(node.gate, node.id);
  }
  return { items: world.items, areas: world.areas, sections: world.sections, nodes: world.nodes };
}

// マップの保存。IDの変更に伴うイベントの書き換え(events)も、同じ要求で受け取る。イベントを先に、マップを最後に書く
// (途中で失敗しても、同じ内容でやり直せる)。イベントは既存のものだけ(このAPIでは新しく作らない)
async function saveWorld(dir, body) {
  if (!body || typeof body !== 'object') throw new HttpError(400, '形式が正しくありません');
  const world = validateWorldShape(body.world);
  const events = body.events === undefined ? [] : body.events;
  if (!Array.isArray(events)) throw new HttpError(400, 'eventsは配列にしてください');
  for (const event of events) {
    if (!event || typeof event.id !== 'string' || !EVENT_ID.test(event.id)) throw new HttpError(400, 'イベントのIDが正しくありません');
    validateEventShape(event, event.id);
    if (!(await exists(path.join(dir, 'events', `${event.id}.json`)))) throw new HttpError(404, `イベントが見つかりません: ${event.id}`);
  }
  for (const event of events) await writeJson(path.join(dir, 'events', `${event.id}.json`), event);
  await writeJson(path.join(dir, 'world.json'), world);
  return { ok: true, eventsUpdated: events.length };
}

// --- シナリオのzip(書き出し/取り込み。docs/scenario_editor.md「スマホへの持ち込み」) ---
// 中身は、manifest.json(形式の印)と、シナリオのフォルダの中身そのまま(scenario.json / world.json / cast.json /
// events/*.json / images/*.png)。ゲーム(godot/scripts/scenario_transfer.gd)も、同じ形を、同じ規則で検査して読む。

const ZIP_FORMAT = 'worldseeker-scenario';
const ZIP_FORMAT_VERSION = 1;
const MAX_ZIP_BYTES = 48 * 1024 * 1024;
const ZIP_LIMITS = { maxEntries: 1500, maxEntryBytes: MAX_IMAGE_BYTES, maxTotalBytes: 64 * 1024 * 1024 };
const ZIP_JSON_FILE = /^(manifest|scenario|world|cast)\.json$/;
const ZIP_EVENT_FILE = /^events\/([a-z0-9][a-z0-9_]{0,80})\.json$/;
const ZIP_IMAGE_FILE = /^images\/([A-Za-z0-9_-]{1,60}\.png)$/;

async function buildScenarioZip(dir, id) {
  const meta = await readJson(path.join(dir, 'scenario.json'), null);
  if (!meta) throw new HttpError(404, 'シナリオが見つかりません');
  const manifest = { format: ZIP_FORMAT, version: ZIP_FORMAT_VERSION, id, name: meta.name || id, exported_at: new Date().toISOString() };
  const entries = [{ name: 'manifest.json', data: Buffer.from(stringify(manifest)) }];
  for (const file of ['scenario.json', 'world.json', 'cast.json']) {
    try { entries.push({ name: file, data: await fsp.readFile(path.join(dir, file)) }); }
    catch (e) { if (e.code !== 'ENOENT') throw e; }
  }
  let names = [];
  try { names = (await fsp.readdir(path.join(dir, 'events'))).sort(); } catch { /* イベント無し */ }
  for (const file of names) {
    if (file.endsWith('.json') && EVENT_ID.test(file.slice(0, -5))) entries.push({ name: `events/${file}`, data: await fsp.readFile(path.join(dir, 'events', file)) });
  }
  try { names = (await fsp.readdir(path.join(dir, 'images'))).sort(); } catch { names = []; }
  for (const file of names) {
    if (IMAGE_NAME.test(file)) entries.push({ name: `images/${file}`, data: await fsp.readFile(path.join(dir, 'images', file)), store: true });
  }
  return zip.createZip(entries);
}

function parseJsonEntry(entry) {
  if (entry.data.length > MAX_JSON_BYTES) throw new HttpError(400, `${entry.name}が大きすぎます`);
  try { return JSON.parse(entry.data.toString('utf8')); } catch { throw new HttpError(400, `${entry.name}をJSONとして読めません`); }
}

const CONDITION_KEYS = { day_min: [['day', 'number']], flag: [['flag', 'string']], floor_found: [['floor', 'string']], floor_passed: [['floor', 'string']], section_entered: [['section', 'string']], area_entered: [['area', 'string']] };
const EFFECT_KEYS = { set_flag: [['flag', 'string']], funds: [['amount', 'number']], grant_item: [['item', 'string']], open_floor: [['floor', 'string']], join: [['name', 'string'], ['bloodline', 'string'], ['job', 'string']] };

// 取り込むイベントの検査。ゲーム(ScenarioEvents)が、種類ごとの決まったキーを、存在を前提に読む(無いと発生の時にエラーになる)
function validateEventDeep(event, fileId) {
  validateEventShape(event, fileId);
  const where = `イベント(${fileId})`;
  if (!['gate', 'conditions', 'system'].includes(event.trigger.type)) throw new HttpError(400, `${where}の発生のしかたが正しくありません: ${event.trigger.type}`);
  const isObject = (x) => x && typeof x === 'object' && !Array.isArray(x);
  const checkList = (list, table, what) => {
    for (const item of list || []) {
      if (!isObject(item) || !table[item.type]) throw new HttpError(400, `${where}の${what}に、対応していない種類があります: ${isObject(item) ? item.type : '(形式不正)'}`);
      for (const [key, kind] of table[item.type]) {
        if (typeof item[key] !== kind) throw new HttpError(400, `${where}の${what}(${item.type})の${key}が正しくありません`);
      }
    }
  };
  checkList(event.conditions, CONDITION_KEYS, '条件');
  checkList(event.effects, EFFECT_KEYS, '効果');
  for (const line of event.script) {
    if (!isObject(line)) throw new HttpError(400, `${where}の会話に、形式が正しくない行があります`);
    if (line.choices !== undefined && (!Array.isArray(line.choices) || line.choices.some((c) => !isObject(c)))) throw new HttpError(400, `${where}の選択肢の形式が正しくありません`);
  }
}

// zipを読み、決まった名前のファイルだけを拾って、全て検査する(ファイル名は信用しない)。
// 戻り値: {meta, world, files: [{name(フォルダ内の相対パス), data}], summary}。何も書かない
function parseScenarioZip(buffer) {
  let entries;
  try { entries = zip.readZip(buffer, ZIP_LIMITS); }
  catch (e) { if (e instanceof zip.ZipError) throw new HttpError(400, e.message); throw e; }
  const json = {};
  const events = new Map();
  const images = new Map();
  let ignored = 0;
  for (const entry of entries) {
    let m;
    if ((m = ZIP_JSON_FILE.exec(entry.name))) json[m[1]] = entry;
    else if ((m = ZIP_EVENT_FILE.exec(entry.name))) events.set(m[1], entry);
    else if ((m = ZIP_IMAGE_FILE.exec(entry.name))) images.set(m[1], entry);
    else ignored++;
  }
  if (!json.manifest) throw new HttpError(400, 'WorldSeekerのシナリオのファイルではありません');
  const manifest = parseJsonEntry(json.manifest);
  if (!manifest || manifest.format !== ZIP_FORMAT) {
    throw new HttpError(400, manifest && manifest.format === 'worldseeker-saves' ? 'これはセーブのファイルです(シナリオのファイルではありません)' : 'WorldSeekerのシナリオのファイルではありません');
  }
  if (Number(manifest.version) > ZIP_FORMAT_VERSION) throw new HttpError(400, '新しい版のエディタで書き出したファイルです。エディタを更新してください');
  if (!json.scenario || !json.world) throw new HttpError(400, 'シナリオの必須ファイル(scenario.json / world.json)がありません');
  const meta = parseJsonEntry(json.scenario);
  if (!meta || typeof meta !== 'object' || Array.isArray(meta) || typeof meta.id !== 'string' || !SCENARIO_ID.test(meta.id)) throw new HttpError(400, 'scenario.jsonのIDが正しくありません');
  if (meta.format !== undefined && Number(meta.format) > 1) throw new HttpError(400, 'scenario.jsonが新しい形式です。エディタを更新してください');
  if (typeof meta.name !== 'string') throw new HttpError(400, 'scenario.jsonに名前がありません');
  const world = validateWorldShape(parseJsonEntry(json.world));
  const files = [{ name: 'scenario.json', data: json.scenario.data }, { name: 'world.json', data: json.world.data }];
  if (json.cast) {
    const cast = parseJsonEntry(json.cast);
    if (!Array.isArray(cast) || cast.some((c) => !c || typeof c !== 'object' || typeof c.name !== 'string')) throw new HttpError(400, 'cast.jsonの形式が正しくありません');
    files.push({ name: 'cast.json', data: json.cast.data });
  }
  for (const [id, entry] of events) {
    validateEventDeep(parseJsonEntry(entry), id);
    files.push({ name: `events/${id}.json`, data: entry.data });
  }
  for (const [name, entry] of images) {
    if (!pngInfo(entry.data)) throw new HttpError(400, `画像がPNGではありません: ${name}`);
    files.push({ name: `images/${name}`, data: entry.data });
  }
  return { meta, world, files, summary: { eventCount: events.size, floorCount: world.nodes.length, imageCount: images.size, ignored } };
}

// 検査済みのシナリオをフォルダへ書く。同じIDが既にある時は、overwriteの時だけ置き換える(一時フォルダに完成させてから入れ替える)
async function installScenario(source, parsed, overwrite) {
  const id = parsed.meta.id;
  if (source === 'default' && id === 'default') throw new HttpError(400, '標準のシナリオ(default)は上書きできません');
  const root = rootFor(source);
  const target = path.join(root, id);
  const already = await exists(target);
  if (already && !overwrite) {
    const current = await readJson(path.join(target, 'scenario.json'), null).catch(() => null);
    throw new HttpError(409, `同じIDのシナリオが既にあります: ${id}`, { exists: true, id, name: (current && current.name) || id });
  }
  await fsp.mkdir(root, { recursive: true });
  const tmp = path.join(root, `.import_${process.pid}_${Date.now()}`);
  const old = `${tmp}_old`;
  try {
    for (const file of parsed.files) {
      await fsp.mkdir(path.dirname(path.join(tmp, file.name)), { recursive: true });
      await fsp.writeFile(path.join(tmp, file.name), file.data);
    }
    if (already) {
      await fsp.rename(target, old);
      try { await fsp.rename(tmp, target); } catch (e) { await fsp.rename(old, target); throw e; }
      await fsp.rm(old, { recursive: true, force: true });
    } else {
      await fsp.rename(tmp, target);
    }
  } catch (e) {
    await fsp.rm(tmp, { recursive: true, force: true });
    throw e;
  }
  return { source, id, name: parsed.meta.name, overwritten: already, ...parsed.summary };
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
  if (method === 'POST' && parts.length === 2 && parts[1] === 'import') {
    const source = url.searchParams.get('source') || 'custom';
    rootFor(source);
    const parsed = parseScenarioZip(await readBody(req, MAX_ZIP_BYTES));
    return sendJson(res, 200, await installScenario(source, parsed, url.searchParams.get('overwrite') === '1'));
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
  if (parts.length === 4 && method === 'GET' && section === 'export') {
    const data = await buildScenarioZip(dir, id);
    res.writeHead(200, { 'Content-Type': 'application/zip', 'Content-Disposition': `attachment; filename="worldseeker_scenario_${id}.zip"`, 'Cache-Control': 'no-store' });
    return res.end(data);
  }
  if (parts.length === 4 && method === 'PUT' && section === 'world') {
    return sendJson(res, 200, await saveWorld(dir, await readJsonBody(req)));
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
      sendJson(res, status, { error: err.message, ...(err.extra || {}) });
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

module.exports = { createServer, config, buildScenarioZip, parseScenarioZip };
