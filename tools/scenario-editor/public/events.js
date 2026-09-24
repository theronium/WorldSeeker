// 「イベント」タブ: 一覧(検索・種別絞り込み・フロア別の並び)と、選んだイベントの編集画面
// (発生のしかた・条件・効果・会話の行リスト)、右側のリプレイ・検証・フロー図。
(function (WS) {
  'use strict';
  const { h, select, textInput, numberInput, iconButton, toast, api, openModal, confirmDialog, truncate, imageUrl } = WS;
  const S = WS.state;
  const L = window.Logic;

  const els = {};
  S.filter = S.filter || { text: '', type: 'all' };

  // ---- 補助 ----

  function eventsWithWorking() {
    const events = S.bundle.events.filter((e) => !S.working || e.id !== S.working.id);
    if (S.working) events.push(L.canonicalEvent(S.working));
    return events;
  }

  function ctxFor(events) {
    return { idx: S.idx, events: events || eventsWithWorking(), library: S.libraryIds, scenarioImages: new Set((S.bundle.images || []).map((i) => i.name)) };
  }

  // 編集中のイベントを検証する。検証対象(canon)が、文脈のイベント一覧の中に(同じ物として)入っている必要がある
  // (validateEventは、一覧の中の別の物だけを「同じIDの他のイベント」と見なす)
  function validateWorking() {
    const canon = L.canonicalEvent(S.working);
    const events = S.bundle.events.filter((e) => e.id !== canon.id);
    events.push(canon);
    return L.validateEvent(canon, ctxFor(events));
  }

  function currentKind() { return S.working ? L.effectiveKind(S.working, S.idx) : ''; }
  function castEntry(name) { return S.bundle.cast.find((c) => c.name === name); }

  function flagNames() {
    const set = new Set();
    for (const ev of eventsWithWorking()) {
      for (const e of ev.effects || []) if (e.type === 'set_flag' && e.flag) set.add(e.flag);
      for (const c of ev.conditions || []) if (c.type === 'flag' && c.flag) set.add(c.flag);
    }
    return [...set].sort();
  }

  function outcomeNames() {
    const set = new Set(['pass', 'fail', 'ok']);
    for (const line of S.working ? S.working.script : []) {
      if (line.outcome) set.add(line.outcome);
      for (const c of line.choices || []) if (c.outcome) set.add(c.outcome);
    }
    return [...set];
  }

  function speakerNames() {
    const set = new Set(S.bundle.cast.map((c) => c.name));
    for (const name of L.usedSpeakers(eventsWithWorking()).keys()) set.add(name);
    return [...set].sort();
  }

  function optionsOf(values, placeholder) {
    return [placeholder ? h('option', { value: '' }, placeholder) : null, ...values.map((v) => h('option', { value: v.value }, v.label))];
  }

  // フロアの選択肢(エリア/セクションごとにoptgroupにまとめる)
  function floorSelect(value, onchange) {
    const el = h('select', {});
    for (const area of S.bundle.world.areas) {
      for (const section of S.bundle.world.sections.filter((s) => s.area === area.id)) {
        const floors = S.idx.floorsBySection.get(section.id) || [];
        if (!floors.length) continue;
        el.append(h('optgroup', { label: `${area.name} / ${section.name}` }, floors.map((f) => h('option', { value: f.id }, `${f.name} (${f.id})`))));
      }
    }
    if (value && !S.idx.floors.has(value)) el.prepend(h('option', { value }, `${value} (存在しない)`));
    el.value = value || '';
    el.addEventListener('change', () => onchange(el.value));
    return el;
  }

  function refSelect(map, value, onchange) {
    const values = [...map.values()].map((v) => ({ value: v.id, label: `${v.name} (${v.id})` }));
    if (value && !map.has(value)) values.unshift({ value, label: `${value} (存在しない)` });
    return select(values, value, onchange);
  }

  function fieldEditor(spec, item, onchange, boolLabels) {
    switch (spec.kind) {
      case 'int': return numberInput(item[spec.key], (v) => { item[spec.key] = v === null ? 0 : v; onchange(); }, { class: 'num' });
      case 'flag': return textInput(item[spec.key] || '', (v) => { item[spec.key] = v.trim(); onchange(); }, { list: 'flag-names', placeholder: 'フラグ名(英数字と_)', class: 'flag-input' });
      case 'bool': return select(boolLabels, String(item[spec.key] !== false), (v) => { item[spec.key] = v === 'true'; onchange(); });
      case 'floor': return floorSelect(item[spec.key], (v) => { item[spec.key] = v; onchange(); });
      case 'section': return refSelect(S.idx.sections, item[spec.key], (v) => { item[spec.key] = v; onchange(); });
      case 'area': return refSelect(S.idx.areas, item[spec.key], (v) => { item[spec.key] = v; onchange(); });
      case 'item': return refSelect(S.idx.items, item[spec.key], (v) => { item[spec.key] = v; onchange(); });
      case 'text': return textInput(item[spec.key] || '', (v) => { item[spec.key] = v; onchange(); }, { placeholder: '名前' });
      case 'bloodline': return select(L.BLOODLINES.map((b) => ({ value: b, label: b })), item[spec.key], (v) => { item[spec.key] = v; onchange(); });
      case 'job': return select(Object.entries(L.JOB_NAMES).map(([value, label]) => ({ value, label })), item[spec.key], (v) => { item[spec.key] = v; onchange(); });
      case 'portrait': return portraitSelect(item, spec.key, onchange);
      case 'skills': return skillLevels(item, spec.key, onchange);
      default: return h('span', {}, '?');
    }
  }

  // 加入する探索者の肖像: 探索者の画像(char_XX)から選ぶ。空なら、ゲームが血筋から自動で選ぶ
  function portraitSelect(item, key, onchange) {
    const preview = h('img', { class: 'join-portrait', alt: '' });
    const show = () => { preview.src = item[key] ? imageUrl(item[key]) : ''; preview.style.visibility = item[key] ? 'visible' : 'hidden'; };
    const ids = (S.library || []).filter((i) => i.group === 'char').map((i) => i.id);
    if (item[key] && !ids.includes(item[key])) ids.unshift(item[key]);
    const el = select([{ value: '', label: '(肖像: 血筋から自動)' }, ...ids.map((id) => ({ value: id, label: id }))], item[key] || '', (v) => {
      if (v) item[key] = v; else delete item[key];
      show(); onchange();
    });
    show();
    return h('span', { class: 'join-portrait-box' }, el, preview);
  }

  // 加入する探索者の初期スキルLv(0なら書かない)
  function skillLevels(item, key, onchange) {
    return h('span', { class: 'skill-levels' }, Object.entries(L.SKILL_NAMES).map(([skill, label]) => h('label', {}, label,
      numberInput((item[key] || {})[skill] || 0, (v) => {
        const levels = { ...(item[key] || {}) };
        if (v && v > 0) levels[skill] = v; else delete levels[skill];
        if (Object.keys(levels).length) item[key] = levels; else delete item[key];
        onchange();
      }, { class: 'num', min: '0' }))));
  }

  function defaultFieldValue(spec) {
    switch (spec.kind) {
      case 'int': return spec.default;
      case 'text': return '';
      case 'bloodline': return spec.default;
      case 'job': return spec.default;
      case 'bool': return spec.default;
      case 'flag': return '';
      case 'floor': return (S.bundle.world.nodes[0] || {}).id || '';
      case 'section': return (S.bundle.world.sections[0] || {}).id || '';
      case 'area': return (S.bundle.world.areas[0] || {}).id || '';
      case 'item': return (S.bundle.world.items[0] || {}).id || '';
      default: return '';
    }
  }

  function makeItem(spec) {
    const item = { type: spec.type };
    for (const f of spec.fields) {
      if (f.kind === 'portrait' || f.kind === 'skills') continue; // 任意の項目(空なら書かない)
      item[f.key] = defaultFieldValue(f);
    }
    return item;
  }

  // ---- 一覧 ----

  function triggerBadge(ev) {
    const t = ev.trigger || {};
    if (t.type === 'gate') return h('span', { class: `badge ${t.result}` }, t.result === 'pass' ? '突破' : '失敗');
    if (t.type === 'system') return h('span', { class: 'badge sys' }, '案内');
    return h('span', { class: 'badge cond' }, '条件');
  }

  function matchesFilter(ev) {
    const f = S.filter;
    const type = (ev.trigger || {}).type;
    if (f.type !== 'all' && f.type !== type) return false;
    const q = f.text.trim().toLowerCase();
    if (!q) return true;
    if (ev.id.toLowerCase().includes(q) || (ev.title || '').toLowerCase().includes(q)) return true;
    return (ev.script || []).some((l) => (l.text || '').toLowerCase().includes(q) || (l.name || '').toLowerCase().includes(q));
  }

  function listItem(ev) {
    const issues = S.issueMap.get(ev.id);
    const active = S.working && S.working.id === ev.id;
    return h('button', { class: `list-item ${active ? 'active' : ''} ${active && S.dirty ? 'dirty' : ''}`, onclick: () => selectEvent(ev.id), title: ev.id },
      triggerBadge(ev),
      h('span', { class: 'list-title' }, active && S.working ? S.working.title || ev.id : ev.title || ev.id),
      issues && issues.errors ? h('span', { class: 'mark error', title: `${issues.errors}件のエラー` }, '⛔') : null,
      issues && !issues.errors && issues.warns ? h('span', { class: 'mark warn', title: `${issues.warns}件の警告` }, '⚠') : null);
  }

  function renderList() {
    if (!els.list) return;
    const events = S.bundle.events.filter(matchesFilter);
    const gate = events.filter((e) => e.trigger.type === 'gate');
    const groups = [];
    const placed = new Set();
    for (const area of S.bundle.world.areas) {
      for (const section of S.bundle.world.sections.filter((s) => s.area === area.id)) {
        const items = [];
        for (const floor of S.idx.floorsBySection.get(section.id) || []) {
          for (const result of ['pass', 'fail']) {
            const ev = gate.find((e) => e.trigger.floor === floor.id && e.trigger.result === result);
            if (ev) { items.push(ev); placed.add(ev.id); }
          }
        }
        if (items.length) groups.push({ label: `${area.name} / ${section.name}`, items });
      }
    }
    const orphans = gate.filter((e) => !placed.has(e.id));
    if (orphans.length) groups.push({ label: '(存在しないフロアのイベント)', items: orphans });
    const cond = events.filter((e) => e.trigger.type === 'conditions');
    if (cond.length) groups.unshift({ label: '条件で発生するイベント', items: cond });
    const sys = events.filter((e) => e.trigger.type === 'system');
    if (sys.length) groups.unshift({ label: '案内会話(ゲームの決まった場面)', items: sys });
    const other = events.filter((e) => !['gate', 'conditions', 'system'].includes(e.trigger.type));
    if (other.length) groups.push({ label: '(発生のしかたが不明)', items: other });

    els.list.replaceChildren();
    if (S.isNew && S.working) els.list.append(h('div', { class: 'list-group' }, '新規(未保存)'), h('button', { class: 'list-item active dirty' }, triggerBadge(S.working), h('span', { class: 'list-title' }, S.working.title || S.working.id)));
    for (const g of groups) els.list.append(h('div', { class: 'list-group' }, g.label), ...g.items.map(listItem));
    if (!groups.length) els.list.append(h('p', { class: 'muted pad' }, '該当するイベントがありません。'));
    els.count.textContent = `${events.length} / ${S.bundle.events.length} 本`;
  }

  async function selectEvent(id) {
    if (S.working && S.working.id === id && !S.isNew) return;
    if (S.working && S.dirty && !(await confirmDialog('保存していない変更があります。破棄して別のイベントを開きますか?', '破棄して移る', true))) return;
    const ev = S.bundle.events.find((e) => e.id === id);
    if (ev) setWorking(L.clone(ev), false);
  }

  function setWorking(ev, isNew) {
    S.working = ev;
    S.isNew = !!isNew;
    S.workingOrig = JSON.stringify(L.canonicalEvent(ev));
    S.dirty = !!isNew;
    WS.replay.reset();
    if (els.list) { renderList(); renderEditor(); }
  }

  // ---- 新規・複製・削除 ----

  function openNewEventDialog(preset) {
    const taken = new Set(S.bundle.events.map((e) => e.id));
    const floors = S.bundle.world.nodes;
    let type = preset ? preset.type : 'gate';
    let floor = preset ? preset.floor : (floors[0] || {}).id;
    let result = preset ? preset.result : 'pass';
    let scene = (L.SYSTEM_SCENES.find((s) => !S.bundle.events.some((e) => e.trigger.type === 'system' && e.trigger.name === s.value)) || L.SYSTEM_SCENES[0]).value;
    let title = '';
    const body = h('div', { class: 'form' });
    const renderBody = () => {
      body.replaceChildren(
        h('label', {}, '種類', select([
          { value: 'gate', label: 'フロアの会話(ゲートを突破した/できなかった時に再生)' },
          { value: 'conditions', label: '条件で発生する会話(日数・フラグ・到達など)' },
          { value: 'system', label: '案内会話(ゲームの決まった場面)' },
        ], type, (v) => { type = v; renderBody(); })),
        type === 'gate' ? [
          h('label', {}, 'フロア', floorSelect(floor, (v) => { floor = v; })),
          h('label', {}, '結果', select([{ value: 'pass', label: '突破した時' }, { value: 'fail', label: '突破できなかった時' }], result, (v) => { result = v; })),
        ] : null,
        type === 'system' ? h('label', {}, '場面', select(L.SYSTEM_SCENES, scene, (v) => { scene = v; })) : null,
        type === 'conditions' ? h('label', {}, 'タイトル', textInput(title, (v) => { title = v; }, { placeholder: '例: 二日目の来訪者' })) : null);
    };
    renderBody();
    openModal('イベントを追加', body, {
      buttons: [
        { label: 'キャンセル', onclick: (close) => close() },
        { label: '追加', primary: true, onclick: async (close) => {
          if (S.working && S.dirty && !(await confirmDialog('保存していない変更があります。破棄して新しいイベントを作りますか?', '破棄して作る', true))) return;
          close();
          const ev = type === 'gate' ? L.newGateEvent(S.idx, floor, result, taken) : type === 'system' ? L.newSystemEvent(scene, taken) : L.newConditionEvent(title, taken);
          WS.showTab('events');
          setWorking(ev, true);
        } },
      ],
    });
  }

  function startNew(ev) {
    WS.showTab('events');
    setWorking(ev, true);
  }

  async function duplicateEvent() {
    if (S.dirty && !(await confirmDialog('保存していない変更があります。今の内容のまま複製しますか?', '複製する'))) return;
    const copy = L.clone(L.canonicalEvent(S.working));
    copy.id = L.uniqueId(`${S.working.id}_copy`, new Set(S.bundle.events.map((e) => e.id)));
    copy.title = `${S.working.title}(コピー)`;
    setWorking(copy, true);
  }

  async function deleteEvent() {
    if (!await confirmDialog(`イベント「${S.working.title}」(${S.working.id})を削除しますか?${S.isNew ? '' : '\nファイルが削除されます。'}`, '削除', true)) return;
    try {
      if (!S.isNew) await api('DELETE', `/api/scenarios/${S.cur.source}/${S.cur.id}/events/${S.working.id}`);
      S.bundle.events = S.bundle.events.filter((e) => e.id !== S.working.id);
      S.working = null; S.dirty = false; S.isNew = false;
      WS.recomputeIssues();
      renderList(); renderEditor();
      toast('削除しました');
    } catch (e) { toast(e.message, 'error'); }
  }

  async function saveEvent() {
    if (!S.working) return;
    const canon = L.canonicalEvent(S.working);
    const errors = validateWorking().filter((i) => i.level === 'error');
    if (errors.length) { toast(`エラーがあるため保存できません: ${errors[0].msg}`, 'error'); return; }
    try {
      await api('PUT', `/api/scenarios/${S.cur.source}/${S.cur.id}/events/${canon.id}`, canon);
      const i = S.bundle.events.findIndex((e) => e.id === canon.id);
      if (i >= 0) S.bundle.events[i] = L.clone(canon); else S.bundle.events.push(L.clone(canon));
      S.bundle.events.sort((a, b) => (a.id < b.id ? -1 : 1));
      S.working = L.clone(canon);
      S.workingOrig = JSON.stringify(canon);
      S.isNew = false; S.dirty = false;
      WS.recomputeIssues();
      renderList(); renderEditor();
      toast(`保存しました。ゲームの「新規プレイ」でこのシナリオを選ぶと反映されます。`);
    } catch (e) { toast(e.message, 'error'); }
  }

  async function revertEvent() {
    if (S.isNew) { S.working = null; S.dirty = false; S.isNew = false; renderList(); renderEditor(); return; }
    if (S.dirty && !await confirmDialog('変更を破棄して、保存済みの内容に戻しますか?', '元に戻す', true)) return;
    setWorking(L.clone(S.bundle.events.find((e) => e.id === S.working.id)), false);
  }

  // ---- 変更の反映 ----

  let sideTimer = null;
  function markDirty() {
    S.dirty = S.isNew || JSON.stringify(L.canonicalEvent(S.working)) !== S.workingOrig;
    updateBadge();
    clearTimeout(sideTimer);
    sideTimer = setTimeout(refreshSide, 200);
  }

  function updateBadge() {
    if (els.dirty) {
      els.dirty.textContent = S.isNew ? '新規(未保存)' : S.dirty ? '未保存の変更あり' : '保存済み';
      els.dirty.className = `dirty-badge ${S.dirty ? 'on' : ''}`;
    }
    if (els.saveBtn) els.saveBtn.disabled = !S.dirty;
    if (els.revertBtn) els.revertBtn.disabled = !S.dirty;
  }

  function refreshSide() {
    if (!S.working) return;
    if (els.issues) els.issues.replaceChildren(issuesPanel());
    if (els.flow) els.flow.replaceChildren(flowPanel());
    const r = S.replay;
    if (r.pos !== null && r.pos >= S.working.script.length) WS.replay.reset();
    WS.refreshReplay();
  }

  function structural() {
    markDirty();
    renderLines();
    refreshSide();
  }

  // ---- 編集画面 ----

  function renderEditor() {
    if (!els.editor) return;
    els.editor.replaceChildren();
    updateDatalists();
    if (!S.working) {
      els.editor.append(h('div', { class: 'empty-state' },
        h('h3', {}, 'イベントを選んでください'),
        h('p', {}, '左の一覧からイベントを選ぶか、「＋ イベントを追加」で新しく作れます。'),
        h('p', { class: 'muted' }, 'イベント = シナリオ内の1つの会話(導入・戦闘・謎解きなど)です。')));
      return;
    }
    els.lines = h('div', { class: 'lines' });
    els.issues = h('div', { class: 'issues-host' });
    els.flow = h('div', { class: 'flow-host' });
    els.editor.append(
      h('div', { class: 'editor-main' }, headerSection(), S.working.trigger.type === 'conditions' ? conditionsSection() : null, effectsSection(), scriptSection()),
      h('div', { class: 'editor-side' }, h('div', { id: 'replay-host', class: 'card' }), els.issues, els.flow));
    renderLines();
    refreshSide();
    updateBadge();
  }

  function updateDatalists() {
    els.datalists.replaceChildren(
      h('datalist', { id: 'flag-names' }, flagNames().map((f) => h('option', { value: f }))),
      h('datalist', { id: 'outcome-names' }, outcomeNames().map((o) => h('option', { value: o }))),
      h('datalist', { id: 'speaker-names' }, speakerNames().map((n) => h('option', { value: n }))));
  }

  function headerSection() {
    const ev = S.working;
    const trigger = ev.trigger;
    els.dirty = h('span', { class: 'dirty-badge' });
    els.saveBtn = h('button', { class: 'primary', id: 'save-btn', onclick: saveEvent }, '保存 (Ctrl+S)');
    els.revertBtn = h('button', { onclick: revertEvent }, S.isNew ? '破棄' : '元に戻す');

    let triggerEditor;
    if (trigger.type === 'gate') {
      triggerEditor = h('div', { class: 'row' },
        h('label', {}, 'フロア', floorSelect(trigger.floor, (v) => { trigger.floor = v; refreshAfterHeader(); })),
        h('label', {}, '結果', select([{ value: 'pass', label: '突破した時' }, { value: 'fail', label: '突破できなかった時' }], trigger.result, (v) => { trigger.result = v; refreshAfterHeader(); })));
    } else if (trigger.type === 'system') {
      triggerEditor = h('label', {}, '場面', select(L.SYSTEM_SCENES, trigger.name, (v) => { trigger.name = v; refreshAfterHeader(); }));
    } else {
      triggerEditor = h('div', { class: 'row' },
        h('label', { class: 'inline' }, h('input', { type: 'checkbox', checked: !!ev.repeat, onchange: (e) => { ev.repeat = e.target.checked; markDirty(); } }), ' 条件が成り立つ間、毎日発生する(繰り返し)'),
        h('label', {}, '優先度', numberInput(ev.priority || 0, (v) => { ev.priority = v || 0; markDirty(); }, { class: 'num', title: '同じ日に複数が成り立つ時、大きい方を先に再生する' })));
    }

    return h('section', { class: 'card' },
      h('div', { class: 'card-head' },
        h('h3', {}, 'イベントの基本'), els.dirty, h('span', { class: 'spacer' }),
        els.saveBtn, els.revertBtn,
        h('button', { onclick: duplicateEvent, disabled: S.isNew }, '複製'),
        h('button', { class: 'danger', onclick: deleteEvent }, '削除')),
      h('div', { class: 'form' },
        h('div', { class: 'row' },
          h('label', { class: 'grow' }, 'タイトル', textInput(ev.title, (v) => { ev.title = v; markDirty(); renderList(); })),
          h('label', {}, 'ID', textInput(ev.id, (v) => { ev.id = v.trim(); markDirty(); }, { class: 'id-input', readOnly: !S.isNew, title: S.isNew ? 'ファイル名になります(小文字英数字と_)' : '保存済みのIDは変えられません(複製して作り直してください)' }))),
        triggerEditor,
        h('label', {}, '会話の見た目(種別)', select(L.KIND_OPTIONS, ev.kind === undefined ? 'auto' : ev.kind, (v) => { ev.kind = v; markDirty(); renderLines(); WS.refreshReplay(); }))));
  }

  function refreshAfterHeader() {
    markDirty();
    renderLines(); // 種別(自動)が変わると、画像の自動選択も変わる
    WS.refreshReplay();
  }

  function conditionsSection() {
    const ev = S.working;
    const rows = h('div', { class: 'rows' });
    const renderRows = () => {
      rows.replaceChildren(...ev.conditions.map((c, i) => {
        const spec = L.CONDITION_TYPES.find((s) => s.type === c.type) || { fields: [], label: c.type };
        return h('div', { class: 'cond-row' },
          h('span', { class: 'and' }, i === 0 ? '条件' : 'かつ'),
          select(L.CONDITION_TYPES.map((t) => ({ value: t.type, label: t.label })), c.type, (v) => { ev.conditions[i] = makeItem(L.CONDITION_TYPES.find((t) => t.type === v)); renderRows(); markDirty(); }),
          spec.fields.map((f) => fieldEditor(f, c, markDirty, [{ value: 'true', label: '立っている' }, { value: 'false', label: '立っていない' }])),
          iconButton('✕', 'この条件を削除', () => { ev.conditions.splice(i, 1); renderRows(); markDirty(); }));
      }));
      if (!ev.conditions.length) rows.append(h('p', { class: 'muted' }, '条件がありません(ゲーム開始の翌日に発生します)。'));
    };
    renderRows();
    const add = select([{ value: '', label: '＋ 条件を追加…' }, ...L.CONDITION_TYPES.map((t) => ({ value: t.type, label: t.label }))], '', (v) => {
      if (!v) return;
      ev.conditions.push(makeItem(L.CONDITION_TYPES.find((t) => t.type === v)));
      add.value = '';
      renderRows(); markDirty();
    });
    return h('section', { class: 'card' }, h('div', { class: 'card-head' }, h('h3', {}, '発生する条件'), h('span', { class: 'muted' }, 'すべて成り立った日に発生します')), rows, add);
  }

  function effectsSection() {
    const ev = S.working;
    const rows = h('div', { class: 'rows' });
    const renderRows = () => {
      rows.replaceChildren(...ev.effects.map((e, i) => {
        const spec = L.EFFECT_TYPES.find((s) => s.type === e.type) || { fields: [] };
        return h('div', { class: 'cond-row' },
          h('span', { class: 'and' }, '結果が'),
          textInput(e.on === undefined ? '*' : e.on, (v) => { e.on = v.trim() || '*'; markDirty(); }, { list: 'outcome-names', class: 'outcome-input', title: '会話の終わりの結果コード。*ならどの結果でも' }),
          h('span', { class: 'and' }, 'の時:'),
          select(L.EFFECT_TYPES.map((t) => ({ value: t.type, label: t.label })), e.type, (v) => { ev.effects[i] = { on: e.on, ...makeItem(L.EFFECT_TYPES.find((t) => t.type === v)) }; renderRows(); markDirty(); }),
          spec.fields.map((f) => fieldEditor(f, e, markDirty, [{ value: 'true', label: '立てる' }, { value: 'false', label: '降ろす' }])),
          iconButton('✕', 'この効果を削除', () => { ev.effects.splice(i, 1); renderRows(); markDirty(); }));
      }));
      if (!ev.effects.length) rows.append(h('p', { class: 'muted' }, '効果がありません。'));
    };
    renderRows();
    const add = select([{ value: '', label: '＋ 効果を追加…' }, ...L.EFFECT_TYPES.map((t) => ({ value: t.type, label: t.label }))], '', (v) => {
      if (!v) return;
      ev.effects.push({ on: '*', ...makeItem(L.EFFECT_TYPES.find((t) => t.type === v)) });
      add.value = '';
      renderRows(); markDirty();
    });
    return h('section', { class: 'card' },
      h('div', { class: 'card-head' }, h('h3', {}, '会話が終わった時の効果'), h('span', { class: 'muted' }, '結果コード(会話の終わりの「結果」)ごとに指定できます')), rows, add);
  }

  function scriptSection() {
    const ev = S.working;
    return h('section', { class: 'card' },
      h('div', { class: 'card-head' }, h('h3', {}, '会話'), h('span', { class: 'muted' }, `${ev.script.length}行`), h('span', { class: 'spacer' }),
        h('button', { onclick: () => { ev.script.push(L.defaultLine(ev.script[ev.script.length - 1])); structural(); scrollToLine(ev.script.length - 1); } }, '＋ 行を末尾に追加')),
      els.lines);
  }

  // ---- 会話の行 ----

  function renderLines() {
    if (!els.lines || !S.working) return;
    els.lines.replaceChildren(...S.working.script.map(lineCard));
    const count = els.lines.parentElement && els.lines.parentElement.querySelector('.card-head .muted');
    if (count) count.textContent = `${S.working.script.length}行`;
  }

  function scrollToLine(i) {
    const el = document.getElementById(`line-${i}`);
    if (!el) return;
    el.scrollIntoView({ block: 'center', behavior: 'smooth' });
    el.classList.add('flash');
    setTimeout(() => el.classList.remove('flash'), 1200);
  }

  // 次の行(i+1)を明示した next は、省略と同じ動き(ゲームのデータは全ての行に明示してある)なので、「次の行へ」と見せる
  function lineMode(line, i) {
    if (line.choices) return 'choices';
    if (line.outcome !== undefined) return 'end';
    if (line.next !== undefined && line.next !== i + 1) return 'jump';
    return 'next';
  }

  function lineTargetSelect(script, value, onchange) {
    return select(script.map((l, j) => ({ value: String(j), label: `${j + 1}: ${truncate((l.name ? l.name + ' ' : '') + l.text, 18)}` })), String(value), (v) => onchange(parseInt(v, 10)), { class: 'target' });
  }

  function flowEditor(line, i) {
    const script = S.working.script;
    const mode = lineMode(line, i);
    const box = h('div', { class: 'flow-editor' });
    const setMode = (m) => {
      delete line.next; delete line.outcome; delete line.choices;
      if (m === 'jump') line.next = Math.min(i + 1, script.length - 1);
      if (m === 'end') line.outcome = S.working.trigger.type === 'gate' ? S.working.trigger.result : 'ok';
      if (m === 'choices') line.choices = [{ label: '選択肢1' }, { label: '選択肢2' }];
      structural();
    };
    box.append(h('span', { class: 'and' }, '進み方'), select([
      { value: 'next', label: `次の行へ(${i + 2 <= script.length ? i + 2 : '終了'})` },
      { value: 'jump', label: '指定の行へ' },
      { value: 'end', label: 'ここで会話を終える(結果コード)' },
      { value: 'choices', label: '選択肢を出す' },
    ], mode, setMode));
    if (mode === 'jump') box.append(lineTargetSelect(script, line.next, (v) => { line.next = v; markDirty(); refreshSide(); }));
    if (mode === 'end') box.append(textInput(line.outcome, (v) => { line.outcome = v.trim(); markDirty(); refreshSide(); }, { list: 'outcome-names', class: 'outcome-input', placeholder: '結果コード(pass/fail/ok…)' }));
    if (mode === 'choices') {
      const list = h('div', { class: 'choices' });
      const renderChoices = () => {
        list.replaceChildren(...line.choices.map((c, k) => {
          const cm = c.outcome !== undefined ? 'end' : c.next !== undefined && c.next !== i + 1 ? 'jump' : 'next';
          const setCm = (m) => {
            delete c.next; delete c.outcome;
            if (m === 'jump') c.next = Math.min(i + 1, script.length - 1);
            if (m === 'end') c.outcome = 'ok';
            renderChoices(); markDirty(); refreshSide();
          };
          return h('div', { class: 'choice-row' },
            h('span', { class: 'and' }, `選択肢${k + 1}`),
            textInput(c.label, (v) => { c.label = v; markDirty(); refreshSide(); WS.refreshReplay(); }, { class: 'choice-label', placeholder: '選択肢の文言' }),
            select([{ value: 'next', label: '次の行へ' }, { value: 'jump', label: '指定の行へ' }, { value: 'end', label: '終える(結果コード)' }], cm, setCm),
            cm === 'jump' ? lineTargetSelect(script, c.next, (v) => { c.next = v; markDirty(); refreshSide(); }) : null,
            cm === 'end' ? textInput(c.outcome, (v) => { c.outcome = v.trim(); markDirty(); refreshSide(); WS.refreshReplay(); }, { list: 'outcome-names', class: 'outcome-input', placeholder: '結果コード' }) : null,
            iconButton('✕', 'この選択肢を削除', () => { line.choices.splice(k, 1); if (!line.choices.length) delete line.choices; structural(); }));
        }));
        list.append(h('button', { class: 'small', onclick: () => { line.choices.push({ label: `選択肢${line.choices.length + 1}` }); renderChoices(); markDirty(); refreshSide(); } }, '＋ 選択肢を追加'));
      };
      renderChoices();
      box.append(list);
    }
    return box;
  }

  function imageButton(line) {
    const btn = h('button', { class: 'image-btn', type: 'button', disabled: line.side === 'none', title: line.side === 'none' ? '「なし(語り)」の行には画像を出しません' : '画像を選ぶ' });
    const fill = () => {
      const id = line.side === 'none' ? '' : L.resolveImage(line, S.bundle.cast, currentKind());
      const source = line.image ? '指定' : castEntry(line.name) ? '登場人物表' : line.name ? '自動' : '';
      btn.replaceChildren(...[id ? h('img', { src: imageUrl(id), alt: id }) : h('span', { class: 'muted' }, line.side === 'none' ? '—' : '画像なし'), source ? h('small', {}, source) : null].filter(Boolean));
    };
    fill();
    btn.addEventListener('click', async () => {
      const current = line.side === 'none' ? '' : L.resolveImage(line, S.bundle.cast, currentKind());
      const picked = await WS.pickImage({ speaker: line.name, current, scopes: !!line.name, title: line.name ? `「${line.name}」の画像を選ぶ` : '画像を選ぶ' });
      if (!picked) return;
      if (picked.scope === 'line') {
        if (picked.image) line.image = picked.image; else delete line.image;
        markDirty();
      } else {
        delete line.image;
        const entry = castEntry(line.name);
        if (picked.image) {
          if (entry) entry.image = picked.image; else S.bundle.cast.push({ name: line.name, image: picked.image, side: line.side === 'right' ? 'right' : 'left' });
        } else if (entry) S.bundle.cast = S.bundle.cast.filter((c) => c !== entry);
        try { await api('PUT', `/api/scenarios/${S.cur.source}/${S.cur.id}/cast`, S.bundle.cast); toast(`登場人物表の「${line.name}」を更新しました`); } catch (e) { toast(e.message, 'error'); }
        markDirty();
      }
      renderLines();
      WS.refreshReplay();
    });
    return btn;
  }

  function lineCard(line, i) {
    const script = S.working.script;
    const at = (n) => (n < 0 || n >= script.length) ? null : n;
    const nameInput = textInput(line.name || '', (v) => { line.name = v; markDirty(); }, { list: 'speaker-names', class: 'name-input', placeholder: '話者名(空なら語り)' });
    nameInput.addEventListener('change', () => { renderLines(); WS.refreshReplay(); }); // 登場人物表の画像が変わることがある
    const card = h('div', { class: `line-card side-${line.side}`, id: `line-${i}` },
      h('div', { class: 'line-head' },
        h('span', { class: 'line-no' }, `#${i + 1}`),
        select(L.SIDES, line.side, (v) => { line.side = v; structural(); WS.refreshReplay(); }),
        nameInput,
        imageButton(line),
        h('span', { class: 'spacer' }),
        iconButton('▶', 'この行からリプレイ', () => { WS.replay.start(i); }),
        iconButton('↑', '上へ', () => { if (at(i - 1) !== null) { S.working.script = L.moveLine(script, i, i - 1); structural(); } }, i === 0),
        iconButton('↓', '下へ', () => { if (at(i + 1) !== null) { S.working.script = L.moveLine(script, i, i + 1); structural(); } }, i === script.length - 1),
        iconButton('＋', 'この下に行を追加', () => { S.working.script = L.insertLine(script, i + 1, L.defaultLine(line)); structural(); scrollToLine(i + 1); }),
        iconButton('⧉', 'この行を複製', () => { S.working.script = L.insertLine(script, i + 1, L.clone(line)); structural(); scrollToLine(i + 1); }),
        iconButton('✕', 'この行を削除', () => { if (script.length === 1 && !confirm('最後の1行です。削除すると会話が空になります。')) return; S.working.script = L.deleteLine(script, i); structural(); })),
      h('textarea', { rows: 2, placeholder: 'セリフ', oninput: (e) => { line.text = e.target.value; markDirty(); }, onblur: () => { refreshSide(); } }, line.text || ''),
      flowEditor(line, i));
    const ta = card.querySelector('textarea');
    ta.value = line.text || '';
    return card;
  }

  // ---- 右側: 検証・フロー図 ----

  function issuesPanel() {
    const issues = validateWorking();
    const wrap = h('div', { class: 'card' }, h('div', { class: 'card-head' }, h('h3', {}, '検証'),
      h('span', { class: `muted` }, issues.length ? `エラー${issues.filter((i) => i.level === 'error').length} / 警告${issues.filter((i) => i.level === 'warn').length}` : '問題なし')));
    if (!issues.length) wrap.append(h('p', { class: 'ok' }, '✓ 問題は見つかりませんでした。'));
    for (const issue of issues) {
      wrap.append(h('div', { class: `issue ${issue.level}`, onclick: () => { if (issue.line !== undefined) scrollToLine(issue.line); } },
        h('span', {}, issue.level === 'error' ? '⛔' : '⚠'), h('span', {}, issue.msg)));
    }
    return wrap;
  }

  function flowPanel() {
    return h('div', { class: 'card' },
      h('div', { class: 'card-head' }, h('h3', {}, '分岐の全体図'), h('span', { class: 'muted' }, '箱をクリックでその行へ')),
      h('div', { class: 'flow-scroll' }, WS.flowSvg(S.working.script, scrollToLine)));
  }

  // ---- タブの土台 ----

  function render(root) {
    els.count = h('span', { class: 'muted' });
    els.list = h('div', { class: 'event-list' });
    els.editor = h('div', { class: 'editor' });
    els.datalists = h('div', { class: 'hidden' });
    const search = h('input', { type: 'search', placeholder: 'タイトル・ID・セリフで検索', value: S.filter.text, oninput: (e) => { S.filter.text = e.target.value; renderList(); } });
    search.value = S.filter.text;
    root.replaceChildren(h('div', { class: 'events-layout' },
      h('aside', { class: 'list-panel' },
        h('div', { class: 'list-tools' },
          search,
          select([{ value: 'all', label: 'すべて' }, { value: 'gate', label: 'フロアの会話' }, { value: 'conditions', label: '条件で発生' }, { value: 'system', label: '案内会話' }], S.filter.type, (v) => { S.filter.type = v; renderList(); }),
          h('div', { class: 'row' }, els.count, h('span', { class: 'spacer' }), h('button', { class: 'primary', onclick: () => openNewEventDialog() }, '＋ イベントを追加'))),
        els.list),
      els.editor, els.datalists));
    renderList();
    renderEditor();
  }

  WS.events = { render, refreshList: renderList, startNew, openNewEventDialog, save: saveEvent, select: selectEvent, scrollToLine, hasUnsaved: () => !!(S.working && S.dirty), discard: () => { S.working = null; S.dirty = false; S.isNew = false; } };
})(window.WS);
