// エディタの外枠: シナリオの選択・作成・複製・削除・基本情報、タブの切り替え、全体の検証、起動処理。
(function (WS) {
  'use strict';
  const { h, api, toast, openModal, confirmDialog, select, textInput, numberInput } = WS;
  const S = WS.state;
  const L = window.Logic;

  S.tab = 'events';
  S.issues = [];
  S.issueMap = new Map();

  const TABS = [
    { key: 'events', label: 'イベント', module: () => WS.events },
    { key: 'cast', label: '登場人物・画像', module: () => WS.cast },
    { key: 'map', label: 'マップ', module: () => WS.map },
  ];

  // ---- 検証 ----

  WS.recomputeIssues = function () {
    S.issues = L.validateScenario(S.bundle, { idx: S.idx, events: S.bundle.events, library: S.libraryIds, scenarioImages: new Set((S.bundle.images || []).map((i) => i.name)) })
      .concat(window.WorldLogic.validateWorld(S.bundle.world, { events: S.bundle.events }).map((i) => ({ eventId: null, ...i })));
    S.issueMap = new Map();
    for (const issue of S.issues) {
      if (!issue.eventId) continue;
      const entry = S.issueMap.get(issue.eventId) || { errors: 0, warns: 0 };
      if (issue.level === 'error') entry.errors++; else entry.warns++;
      S.issueMap.set(issue.eventId, entry);
    }
    const badge = document.getElementById('issue-count');
    if (badge) {
      const errors = S.issues.filter((i) => i.level === 'error').length;
      const warns = S.issues.length - errors;
      badge.textContent = S.issues.length ? [errors ? `⛔ エラー${errors}` : '', warns ? `⚠ 警告${warns}` : ''].filter(Boolean).join('  ') : '✓ 問題なし';
      badge.className = errors ? 'has-error' : warns ? 'has-warn' : 'clean';
    }
    if (WS.events && WS.events.refreshList) WS.events.refreshList();
  };

  function openValidation() {
    WS.recomputeIssues();
    const body = h('div', { class: 'validation-list' });
    if (!S.issues.length) body.append(h('p', { class: 'ok' }, '✓ シナリオ全体で、問題は見つかりませんでした。'));
    const byEvent = new Map();
    for (const issue of S.issues) {
      const key = issue.eventId || (issue.scope === 'map' ? '(マップ)' : '(シナリオ全体・登場人物表)');
      if (!byEvent.has(key)) byEvent.set(key, []);
      byEvent.get(key).push(issue);
    }
    let modal;
    for (const [key, issues] of byEvent) {
      const ev = S.bundle.events.find((e) => e.id === key);
      body.append(h('div', { class: 'validation-group' }, ev ? `${ev.title} (${ev.id})` : key));
      for (const issue of issues) {
        body.append(h('div', { class: `issue ${issue.level}`, onclick: async () => {
          if (issue.target) { modal.close(); WS.showTab('map'); WS.map.select(issue.target.kind, issue.target.id); return; }
          if (!ev) return;
          modal.close();
          WS.showTab('events');
          await WS.events.select(ev.id);
          if (issue.line !== undefined) setTimeout(() => WS.events.scrollToLine(issue.line), 50);
        } }, h('span', {}, issue.level === 'error' ? '⛔' : '⚠'), h('span', {}, issue.msg)));
      }
    }
    modal = openModal(`シナリオ全体の検証 (${S.issues.length}件)`, body, { wide: true, buttons: [{ label: '閉じる', primary: true, onclick: (close) => close() }] });
  }

  // ---- タブ ----

  WS.showTab = function (key) {
    S.tab = key;
    for (const btn of document.querySelectorAll('#tabs button')) btn.classList.toggle('active', btn.dataset.key === key);
    const content = document.getElementById('content');
    if (!content) return;
    const tab = TABS.find((t) => t.key === key);
    tab.module().render(content);
  };

  // ---- シナリオの操作 ----

  async function loadScenario(source, id, force) {
    if (!force && hasUnsaved() && !await confirmDialog('保存していない変更(イベントまたはマップ)があります。破棄して別のシナリオを開きますか?', '破棄して開く', true)) {
      renderShell(); // セレクトの表示を元に戻す
      return false;
    }
    try {
      const bundle = await api('GET', `/api/scenarios/${source}/${id}`);
      S.cur = { source, id };
      S.bundle = bundle;
      S.idx = L.worldIndex(bundle.world);
      WS.map.reset();
      S.working = null; S.dirty = false; S.isNew = false;
      S.imageVersion = Date.now();
      try { localStorage.setItem('ws-editor-last', `${source}/${id}`); } catch { /* 保存できなくても続行 */ }
      renderShell();
      WS.recomputeIssues();
      return true;
    } catch (e) {
      toast(e.message, 'error');
      return false;
    }
  }

  function hasUnsaved() { return WS.events.hasUnsaved() || WS.map.hasUnsaved(); }

  async function refreshScenarioList() {
    S.scenarios = await api('GET', '/api/scenarios');
  }

  function openCreateDialog(mode) {
    // mode: 'new' | 'copy'
    const cur = S.cur;
    const form = { name: mode === 'copy' ? `${S.bundle.meta.name}(コピー)` : '', id: '', source: 'custom', from: mode === 'copy' ? `${cur.source}/${cur.id}` : 'default/default' };
    const body = h('div', { class: 'form' },
      h('label', {}, 'シナリオの名前', textInput(form.name, (v) => { form.name = v; }, { placeholder: '例: 港町の事件' })),
      h('label', {}, 'ID(フォルダ名。小文字英字で始まる、英数字と_)', textInput(form.id, (v) => { form.id = v.trim(); }, { placeholder: '例: harbor_incident' })),
      h('label', {}, '保存先', select([
        { value: 'custom', label: 'カスタム(個人用・公開しない)' },
        { value: 'default', label: 'デフォルト(リポジトリに含めて公開する)' },
      ], form.source, (v) => { form.source = v; })),
      h('label', {}, '元にするもの', select([
        { value: '', label: '空のシナリオ(最小のマップだけ)' },
        ...S.scenarios.map((s) => ({ value: `${s.source}/${s.id}`, label: `コピー: ${s.name} (${s.source === 'default' ? 'デフォルト' : 'カスタム'}/${s.id})` })),
      ], form.from, (v) => { form.from = v; })),
      h('p', { class: 'muted' }, 'コピーすると、マップ・イベント・登場人物表・画像がそのまま複製されます。'));
    openModal(mode === 'copy' ? 'シナリオを複製' : 'シナリオを作成', body, {
      buttons: [
        { label: 'キャンセル', onclick: (close) => close() },
        { label: '作成', primary: true, onclick: async (close) => {
          if (!form.name.trim()) { toast('名前を入力してください', 'error'); return; }
          if (!/^[a-z][a-z0-9_]{1,40}$/.test(form.id)) { toast('IDは、小文字英字で始まる英数字と_(2〜41文字)にしてください', 'error'); return; }
          if (hasUnsaved() && !await confirmDialog('保存していない変更(イベントまたはマップ)があります。破棄して新しいシナリオを開きますか?', '破棄して進む', true)) return;
          try {
            const [fromSource, fromId] = form.from ? form.from.split('/') : [null, null];
            await api('POST', '/api/scenarios', { source: form.source, id: form.id, name: form.name.trim(), copyFrom: fromSource ? { source: fromSource, id: fromId } : undefined });
            close();
            await refreshScenarioList();
            await loadScenario(form.source, form.id, true);
            toast(`シナリオ「${form.name.trim()}」を作成しました`);
          } catch (e) { toast(e.message, 'error'); }
        } },
      ],
    });
  }

  // zipで書き出す(ブラウザのダウンロード)。中身は、ディスクに保存済みの内容。スマホへ運んで、ゲームの「シナリオを取り込む」で読む
  async function exportScenario() {
    const { source, id } = S.cur;
    if (hasUnsaved() && !await confirmDialog('保存していない変更(イベントまたはマップ)があります。zipには、保存済みの内容だけが入ります。このまま書き出しますか?', '書き出す')) return;
    const link = h('a', { href: `/api/scenarios/${source}/${id}/export`, download: `worldseeker_scenario_${id}.zip` });
    document.body.append(link);
    link.click();
    link.remove();
    toast(`zipを書き出しました(ダウンロードのフォルダなど)。スマホへ運んで、ゲームの「シナリオを取り込む」で選んでください`);
  }

  // zipを取り込む(スマホで作り直したもの・他のPCや人から受け取ったもの・書き出したバックアップ)
  function openImportDialog() {
    const form = { source: 'custom' };
    const fileInput = h('input', { type: 'file', accept: '.zip,application/zip', id: 'import-file' });
    const body = h('div', { class: 'form' },
      h('label', {}, 'シナリオのzipファイル(エディタで書き出したもの)', fileInput),
      h('label', {}, '取り込み先', select([
        { value: 'custom', label: 'カスタム(個人用・公開しない)' },
        { value: 'default', label: 'デフォルト(リポジトリに含めて公開する)' },
      ], form.source, (v) => { form.source = v; })),
      h('p', { class: 'muted' }, '中身を全て検査してから取り込みます。同じIDのシナリオが既にある時は、上書きするか確認します。'));
    openModal('zipから取り込む', body, {
      buttons: [
        { label: 'キャンセル', onclick: (close) => close() },
        { label: '取り込む', primary: true, onclick: async (close) => {
          const file = fileInput.files && fileInput.files[0];
          if (!file) { toast('zipファイルを選んでください', 'error'); return; }
          if (hasUnsaved() && !await confirmDialog('保存していない変更(イベントまたはマップ)があります。破棄して、取り込んだシナリオを開きますか?', '破棄して取り込む', true)) return;
          close();
          await importScenarioFile(file, form.source);
        } },
      ],
    });
  }

  async function importScenarioFile(file, source) {
    const buffer = await file.arrayBuffer();
    const post = (overwrite) => api('POST', `/api/scenarios/import?source=${source}${overwrite ? '&overwrite=1' : ''}`, buffer);
    let result;
    try {
      try { result = await post(false); }
      catch (e) {
        if (e.status !== 409 || !e.data || !e.data.exists) throw e;
        const where = source === 'default' ? 'デフォルト' : 'カスタム';
        if (!await confirmDialog(`同じIDのシナリオ「${e.data.name}」(${where}/${e.data.id})が既にあります。上書きして取り込みますか?\n上書きすると、今の内容は元に戻せません。`, '上書きして取り込む', true)) return;
        result = await post(true);
      }
    } catch (e) { toast(`取り込めません: ${e.message}`, 'error'); return; }
    await refreshScenarioList();
    await loadScenario(source, result.id, true);
    toast(`シナリオ「${result.name}」を${result.overwritten ? '上書きして' : ''}取り込みました(フロア${result.floorCount}・イベント${result.eventCount}本・画像${result.imageCount}枚)`);
  }

  async function deleteScenario() {
    const { source, id } = S.cur;
    if (source === 'default' && id === 'default') { toast('標準のシナリオ(default)は削除できません', 'error'); return; }
    if (!await confirmDialog(`シナリオ「${S.bundle.meta.name}」(${source}/${id})を削除しますか?\nフォルダごと削除され、元に戻せません。\n(このシナリオで遊び始めたセーブスロットは、そのまま遊べます)`, '削除', true)) return;
    try {
      await api('DELETE', `/api/scenarios/${source}/${id}`);
      await refreshScenarioList();
      await loadScenario('default', 'default', true);
      toast('削除しました');
    } catch (e) { toast(e.message, 'error'); }
  }

  function openMetaDialog() {
    const meta = { ...S.bundle.meta };
    const body = h('div', { class: 'form' },
      h('label', {}, '名前', textInput(meta.name, (v) => { meta.name = v; })),
      h('label', {}, '説明(ゲームの新規プレイのシナリオ選択に出ます)', (() => { const t = h('textarea', { rows: 3, oninput: (e) => { meta.description = e.target.value; } }); t.value = meta.description || ''; return t; })()),
      h('label', {}, '作者', textInput(meta.author || '', (v) => { meta.author = v; })),
      h('div', { class: 'row' },
        h('label', {}, '暦の開始(年)', numberInput(meta.start_year || 0, (v) => { meta.start_year = v || 0; }, { class: 'num' })),
        h('label', {}, '暦の開始(月 1〜12)', numberInput(meta.start_month || 1, (v) => { meta.start_month = Math.min(12, Math.max(1, v || 1)); }, { class: 'num', min: 1, max: 12 }))));
    openModal('シナリオの基本情報', body, {
      buttons: [
        { label: 'キャンセル', onclick: (close) => close() },
        { label: '保存', primary: true, onclick: async (close) => {
          if (!String(meta.name || '').trim()) { toast('名前は必須です', 'error'); return; }
          try {
            await api('PUT', `/api/scenarios/${S.cur.source}/${S.cur.id}/meta`, meta);
            S.bundle.meta = meta;
            close();
            await refreshScenarioList();
            renderShell();
            toast('保存しました');
          } catch (e) { toast(e.message, 'error'); }
        } },
      ],
    });
  }

  // ---- 外枠 ----

  function renderShell() {
    const app = document.getElementById('app');
    const selectEl = h('select', { id: 'scenario-select', title: 'シナリオを切り替える', onchange: (e) => { const [source, id] = e.target.value.split('/'); loadScenario(source, id); } },
      ['default', 'custom'].map((source) => h('optgroup', { label: source === 'default' ? 'デフォルト(リポジトリに含める)' : 'カスタム(個人用)' },
        S.scenarios.filter((s) => s.source === source).map((s) => h('option', { value: `${s.source}/${s.id}` }, `${s.name} (${s.eventCount}本)`)))));
    selectEl.value = `${S.cur.source}/${S.cur.id}`;
    const isDefault = S.cur.source === 'default';
    app.replaceChildren(
      h('header', { class: 'topbar' },
        h('div', { class: 'brand' }, 'WorldSeeker シナリオエディタ'),
        selectEl,
        h('span', { class: `source-badge ${S.cur.source}`, title: isDefault ? S.info.defaultRoot : S.info.customRoot }, isDefault ? 'デフォルト' : 'カスタム'),
        h('button', { onclick: openMetaDialog }, '基本情報'),
        h('button', { onclick: () => openCreateDialog('new') }, '新規'),
        h('button', { onclick: () => openCreateDialog('copy') }, '複製'),
        h('button', { class: 'danger', onclick: deleteScenario, disabled: S.cur.id === 'default' && isDefault }, '削除'),
        h('button', { id: 'export-btn', onclick: exportScenario, title: 'このシナリオを、1つのzipファイルに書き出す(スマホへ運ぶ・バックアップ用)' }, 'zip書き出し'),
        h('button', { id: 'import-btn', onclick: openImportDialog, title: '書き出したzipから、シナリオを取り込む' }, 'zip取り込み'),
        h('span', { class: 'spacer' }),
        h('button', { id: 'issue-count', onclick: openValidation, title: 'シナリオ全体を検証する' }, '検証')),
      h('nav', { id: 'tabs', class: 'tabs' }, TABS.map((t) => h('button', { 'data-key': t.key, class: t.key === S.tab ? 'active' : '', onclick: () => WS.showTab(t.key) }, t.label))),
      h('main', { id: 'content' }));
    WS.showTab(S.tab);
  }

  // ---- 起動 ----

  async function boot() {
    try {
      S.info = await api('GET', '/api/info');
      S.library = await api('GET', '/api/library');
      S.libraryIds = new Set(S.library.map((i) => i.id));
      await refreshScenarioList();
      let last = null;
      try { last = localStorage.getItem('ws-editor-last'); } catch { /* 無視 */ }
      const [source, id] = (last && S.scenarios.some((s) => `${s.source}/${s.id}` === last) ? last : 'default/default').split('/');
      if (!await loadScenario(source, id, true)) throw new Error('シナリオを読み込めませんでした');
    } catch (e) {
      document.getElementById('app').replaceChildren(h('div', { class: 'boot-error' }, h('h2', {}, '起動に失敗しました'), h('p', {}, e.message), h('p', { class: 'muted' }, 'サーバー(node server.js)が動いているか確認してください。')));
    }
  }

  document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
      e.preventDefault();
      if (S.tab === 'events' && S.working) WS.events.save();
      else if (S.tab === 'map') WS.map.save();
    }
  });
  window.addEventListener('beforeunload', (e) => { if ((S.working && S.dirty) || WS.map.hasUnsaved()) { e.preventDefault(); e.returnValue = ''; } });

  WS.boot = boot;
  document.addEventListener('DOMContentLoaded', boot);
})(window.WS);
