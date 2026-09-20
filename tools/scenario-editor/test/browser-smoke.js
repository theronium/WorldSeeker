'use strict';
// 実際のブラウザ(Edge/Chrome)をリモート操作して、エディタの画面を通しで確かめるスモークテスト。
//   node test/browser-smoke.js [スクリーンショットの保存先ディレクトリ]
// サーバーは一時ディレクトリの複製(デフォルト/カスタム)で起動するので、リポジトリのシナリオには触れない。
// ブラウザが見つからなければ何もせず終了する。依存パッケージなし(Node 22のWebSocketを使う)。
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const assert = require('assert');
const { createServer, config } = require('../server.js');

const CANDIDATES = [
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
];
const browserPath = process.env.BROWSER || CANDIDATES.find((p) => fs.existsSync(p));
if (!browserPath) { console.log('ブラウザが見つからないので、スモークテストを省略します'); process.exit(0); }

const shotDir = process.argv[2] || null;
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ws-smoke-'));
const REAL_DEFAULT = path.resolve(__dirname, '..', '..', '..', 'godot', 'scenarios');
fs.cpSync(REAL_DEFAULT, path.join(tmp, 'default_root'), { recursive: true });
config.defaultRoot = path.join(tmp, 'default_root');
config.customRoot = path.join(tmp, 'custom_root');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
function check(label, cond, detail) {
  if (!cond) failures++;
  console.log(`${cond ? 'OK  ' : 'NG  '} ${label}${detail ? '  (' + detail + ')' : ''}`);
}

async function main() {
  const server = createServer();
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const appPort = server.address().port;
  const debugPort = 9300 + Math.floor(Math.random() * 500);
  const browser = spawn(browserPath, [
    '--headless=new', '--disable-gpu', `--remote-debugging-port=${debugPort}`, `--user-data-dir=${path.join(tmp, 'profile')}`,
    '--no-first-run', '--no-default-browser-check', '--window-size=1500,1000', 'about:blank',
  ], { stdio: 'ignore' });

  try {
    let target;
    for (let i = 0; i < 50 && !target; i++) {
      await sleep(200);
      try { target = (await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json()).find((t) => t.type === 'page'); } catch { /* 起動待ち */ }
    }
    assert.ok(target, 'ブラウザのデバッグ接続に失敗');
    const ws = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((r) => { ws.onopen = r; });
    let nextId = 1;
    const pending = new Map();
    const problems = [];
    ws.onmessage = (msg) => {
      const data = JSON.parse(msg.data);
      if (data.id && pending.has(data.id)) { pending.get(data.id)(data); pending.delete(data.id); return; }
      if (data.method === 'Runtime.exceptionThrown') problems.push(data.params.exceptionDetails.exception ? data.params.exceptionDetails.exception.description : data.params.exceptionDetails.text);
      if (data.method === 'Runtime.consoleAPICalled' && data.params.type === 'error') problems.push('console.error: ' + data.params.args.map((a) => a.value || a.description).join(' '));
    };
    const send = (method, params) => new Promise((resolve) => { const id = nextId++; pending.set(id, resolve); ws.send(JSON.stringify({ id, method, params })); });
    const evaluate = async (expression) => {
      const res = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
      if (res.result.exceptionDetails) throw new Error(res.result.exceptionDetails.exception ? res.result.exceptionDetails.exception.description : res.result.exceptionDetails.text);
      return res.result.result.value;
    };
    const waitFor = async (expression, ms = 5000) => { for (let t = 0; t < ms; t += 100) { if (await evaluate(expression)) return true; await sleep(100); } return false; };
    const shot = async (name) => {
      if (!shotDir) return;
      fs.mkdirSync(shotDir, { recursive: true });
      await sleep(900); // 画像の読み込みを待つ
      const res = await send('Page.captureScreenshot', { format: 'png' });
      fs.writeFileSync(path.join(shotDir, name + '.png'), Buffer.from(res.result.data, 'base64'));
    };
    const click = (selector, text) => evaluate(`(() => { const els = [...document.querySelectorAll(${JSON.stringify(selector)})]; const el = els.find(e => ${JSON.stringify(text || '')} === '' || e.textContent.includes(${JSON.stringify(text || '')})); if (!el) return false; el.click(); return true; })()`);
    const setValue = (selector, value, eventName) => evaluate(`(() => { const el = document.querySelector(${JSON.stringify(selector)}); if (!el) return false; el.value = ${JSON.stringify(value)}; el.dispatchEvent(new Event(${JSON.stringify(eventName || 'input')}, {bubbles: true})); return true; })()`);

    await send('Runtime.enable'); await send('Page.enable');
    await send('Emulation.setDeviceMetricsOverride', { width: 1500, height: 1000, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: `http://127.0.0.1:${appPort}/` });

    check('起動: イベント一覧が出る', await waitFor(`document.querySelectorAll('.list-item').length > 100`));
    check('起動: 一覧の総数(170本)', (await evaluate(`document.querySelector('.list-panel .muted').textContent`)).includes('170 / 170'));
    check('起動: シナリオ検証が終わっている(エラー0)', (await evaluate(`document.getElementById('issue-count').textContent`)).startsWith('✓') || (await evaluate(`document.getElementById('issue-count').className`)) !== 'has-error');

    // 古い祠(突破)を開く
    check('一覧から古い祠(突破)を開く', await click('.list-item', '古い祠(突破)'));
    check('編集画面: 3行の会話', await waitFor(`document.querySelectorAll('.line-card').length === 3`));
    check('編集画面: フロアの選択が古い祠', (await evaluate(`[...document.querySelectorAll('.editor-main select')].some(s => s.value === 'old_shrine')`)));
    await shot('01_event_selected');

    // リプレイ: 最初から → 次へ → 次へ → 終了(結果コードpass)
    await click('.replay-controls button', '最初から');
    check('リプレイ: 1行目が出る', (await evaluate(`document.querySelector('.replay-text').textContent`)).includes('三つの問い'));
    await click('.replay-next', '次へ'); await click('.replay-next', '次へ');
    check('リプレイ: 3行目', (await evaluate(`document.querySelector('.replay-text').textContent`)).includes('正解だ'));
    await click('.replay-next', '次へ');
    check('リプレイ: 結果コードpassで終了', (await evaluate(`document.querySelector('.replay-end') && document.querySelector('.replay-end').textContent`) || '').includes('pass'));
    await shot('02_replay_end');

    // セリフを編集して保存 → ファイルに反映
    await setValue('.line-card:nth-child(2) textarea', '同行した探索者は、じっくりと考え込んだ。');
    check('編集: 未保存の表示', (await evaluate(`document.querySelector('.dirty-badge').textContent`)).includes('未保存'));
    await click('#save-btn');
    await sleep(500);
    console.log('   (通知: ' + await evaluate(`[...document.querySelectorAll('.toast')].map(t => t.textContent).join(' / ')`) + ')');
    const shrineFile = path.join(config.defaultRoot, 'default', 'events', 'floor_old_shrine_pass.json');
    check('保存: ファイルにセリフが反映', fs.readFileSync(shrineFile, 'utf8').includes('じっくりと考え込んだ'));
    check('保存: 保存済みの表示に戻る', (await evaluate(`document.querySelector('.dirty-badge').textContent`)).includes('保存済み'));

    // 行を追加し、選択肢を作る(分岐)
    await click('.line-card:nth-child(1) button[title="この下に行を追加"]');
    check('行の追加: 4行になる', await waitFor(`document.querySelectorAll('.line-card').length === 4`));
    // 2行目(追加した行)を選択肢の行にする
    await evaluate(`(() => { const sel = document.querySelector('.line-card:nth-child(2) .flow-editor select'); sel.value = 'choices'; sel.dispatchEvent(new Event('change', {bubbles: true})); })()`);
    check('選択肢の行: 選択肢が2つ出る', await waitFor(`document.querySelectorAll('.line-card:nth-child(2) .choice-row').length === 2`));
    await shot('03_choices');

    // 変更を破棄(元に戻す)
    await click('button', '元に戻す');
    await click('.modal-buttons button', '元に戻す');
    check('元に戻す: 3行に戻る', await waitFor(`document.querySelectorAll('.line-card').length === 3`));

    // 新しい条件イベントを作って保存
    await click('button', 'イベントを追加');
    await evaluate(`(() => { const sel = document.querySelector('.modal select'); sel.value = 'conditions'; sel.dispatchEvent(new Event('change', {bubbles: true})); })()`);
    await sleep(100);
    await setValue('.modal input[type="text"]', '二日目の来訪者');
    await click('.modal-buttons button', '追加');
    check('新規イベント: 未保存で開く', await waitFor(`document.querySelector('.dirty-badge') && document.querySelector('.dirty-badge').textContent.includes('新規')`));
    await setValue('.id-input', 'second_day_visitor');
    await click('.editor-main select[class=""], .editor-main select', '');
    // 効果: 資金を追加
    await evaluate(`(() => { const sels = [...document.querySelectorAll('.editor-main select')]; const add = sels.find(s => [...s.options].some(o => o.textContent.includes('効果を追加'))); add.value = 'funds'; add.dispatchEvent(new Event('change', {bubbles: true})); })()`);
    await click('#save-btn');
    await sleep(600);
    const newFile = path.join(config.defaultRoot, 'default', 'events', 'second_day_visitor.json');
    check('新規イベント: ファイルが作られる', fs.existsSync(newFile));
    if (fs.existsSync(newFile)) {
      const saved = JSON.parse(fs.readFileSync(newFile, 'utf8'));
      check('新規イベント: 中身(条件・効果)', saved.trigger.type === 'conditions' && saved.conditions[0].type === 'day_min' && saved.effects[0].type === 'funds' && saved.effects[0].amount === 100, JSON.stringify(saved.effects));
    }
    await shot('04_new_event');

    // 登場人物タブ・マップタブ
    await click('#tabs button', '登場人物');
    check('登場人物タブ: 40人が並ぶ', await waitFor(`document.querySelectorAll('.cast-row').length === 40`));
    await shot('05_cast');
    await click('#tabs button', 'マップ');
    check('マップタブ: フロア194行', await waitFor(`document.querySelectorAll('.map-table tr').length === 194`));
    await shot('06_map');

    // 画像ピッカー(ライブラリ)
    await click('#tabs button', 'イベント');
    await click('.list-item', '古い祠(突破)');
    await waitFor(`document.querySelectorAll('.line-card').length === 3`);
    await click('.line-card:nth-child(1) .flow-editor', ''); // 何もしない(フォーカス)
    await evaluate(`(() => { const sel = document.querySelector('.line-card:nth-child(1) .line-head select'); sel.value = 'left'; sel.dispatchEvent(new Event('change', {bubbles: true})); })()`);
    await sleep(200);
    await click('.line-card:nth-child(1) .image-btn', '');
    check('画像ピッカー: ライブラリの画像が並ぶ', await waitFor(`document.querySelectorAll('.image-grid .thumb').length >= 32`));
    await shot('07_picker');
    await click('.modal-buttons button', 'キャンセル');

    // 新規シナリオ(カスタム)の作成
    await click('.topbar button', '新規');
    await setValue('.modal input[type="text"]:nth-of-type(1)', '試験用');
    await evaluate(`(() => { const inputs = document.querySelectorAll('.modal input[type="text"]'); inputs[0].value = '試験用'; inputs[0].dispatchEvent(new Event('input', {bubbles: true})); inputs[1].value = 'smoke_test'; inputs[1].dispatchEvent(new Event('input', {bubbles: true})); })()`);
    await click('.modal-buttons button', '作成');
    // 未保存の変更(上で行の左右を変えた)があるので、破棄してよいかの確認が出る
    check('未保存の変更があると、別のシナリオを開く前に確認が出る', await waitFor(`[...document.querySelectorAll('.modal')].some(m => m.textContent.includes('保存していない変更があります'))`));
    await click('.modal-buttons button', '破棄して進む');
    check('新規シナリオ: カスタムとして作られ、開く', await waitFor(`document.querySelector('.source-badge.custom') !== null`));
    check('新規シナリオ: フォルダができる', fs.existsSync(path.join(config.customRoot, 'smoke_test', 'scenario.json')));
    check('新規シナリオ: 元(デフォルト)のコピー(先に足した1本を含む171本)', (await evaluate(`document.querySelector('.list-panel .muted').textContent`)).includes('171'));

    check('JSエラーが出ていない', problems.length === 0, problems.join(' | '));
    ws.close();
  } finally {
    browser.kill();
    server.close();
    await sleep(300);
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch { /* 使用中でも続行 */ }
  }
  console.log(failures ? `=== 失敗 ${failures}件 ===` : '=== 全て成功 ===');
  process.exit(failures ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
