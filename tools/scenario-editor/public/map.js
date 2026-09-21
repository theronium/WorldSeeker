// 「マップ」タブ: エリア>セクション>フロアのツリーと、選んだものの編集フォーム(名前・ID・並び・ゲート・接続・報酬・アイテム定義)。
// 編集は「下書き」(保存済みの世界の複製)に対して行い、保存でworld.jsonを書く。IDの変更・削除の、イベントへの波及は
// worldlogic.js(diffIds/remapEvents)が計算し、保存時に、書き換えたイベントも一緒に送る(サーバーの PUT .../world)。
(function (WS) {
  'use strict';
  const { h, select, textInput, numberInput, iconButton, toast, api, openModal, confirmDialog } = WS;
  const S = WS.state;
  const L = window.Logic;
  const W = window.WorldLogic;

  const M = { draft: null, savedJson: '', selected: null, open: new Set(), filter: '', issues: [], issueMap: new Map(), els: {} };

  // ---- 下書き ----

  function ensureDraft() {
    if (M.draft) return;
    M.draft = W.startDraft(S.bundle.world);
    M.savedJson = JSON.stringify(W.canonicalWorld(S.bundle.world));
    M.issues = [];
    if (!M.open.size) for (const a of M.draft.areas) M.open.add(`area:${a.id}`);
  }

  function reset() { M.draft = null; M.selected = null; M.open = new Set(); M.filter = ''; }
  function isDirty() { return !!M.draft && JSON.stringify(W.canonicalWorld(M.draft)) !== M.savedJson; }
  function hasUnsaved() { return isDirty(); }

  // 保存済みのイベントを、下書きのIDの変更に合わせた形にしたもの(検証の文脈に使う)
  function eventsForValidation() {
    const changed = new Map(W.remapEvents(S.bundle.events, W.diffIds(S.bundle.world, M.draft)).map((e) => [e.id, e]));
    return S.bundle.events.map((e) => changed.get(e.id) || e);
  }

  function computeIssues() {
    M.issues = W.validateWorld(M.draft, { events: eventsForValidation() });
    M.issueMap = new Map();
    const bump = (key, level) => {
      const entry = M.issueMap.get(key) || { errors: 0, warns: 0 };
      if (level === 'error') entry.errors++; else entry.warns++;
      M.issueMap.set(key, entry);
    };
    for (const issue of M.issues) {
      if (!issue.target) continue;
      bump(`${issue.target.kind}:${issue.target.id}`, issue.level);
      // 中身の問題は、親の行にも印を出す(折りたたまれていても気付けるように)
      if (issue.target.kind === 'floor') {
        const node = W.find(M.draft, 'floor', issue.target.id);
        const section = node && W.find(M.draft, 'section', node.section);
        if (section) { bump(`section:${section.id}`, issue.level); bump(`area:${section.area}`, issue.level); }
      } else if (issue.target.kind === 'section') {
        const section = W.find(M.draft, 'section', issue.target.id);
        if (section) bump(`area:${section.area}`, issue.level);
      }
    }
  }

  function refresh(opts) {
    computeIssues();
    renderBar();
    renderTree();
    if (!opts || opts.detail !== false) renderDetail(opts && opts.scroll === 'top');
  }

  // ---- 選択 ----

  function selectEntity(kind, id) {
    M.selected = { kind, id };
    if (kind === 'floor') {
      const node = W.find(M.draft, 'floor', id);
      const section = node && W.find(M.draft, 'section', node.section);
      if (section) { M.open.add(`section:${section.id}`); M.open.add(`area:${section.area}`); }
    } else if (kind === 'section') {
      const section = W.find(M.draft, 'section', id);
      if (section) M.open.add(`area:${section.area}`);
    }
    renderTree();
    renderDetail(true);
    const row = M.els.tree && M.els.tree.querySelector('.tree-row.active');
    if (row) row.scrollIntoView({ block: 'nearest' });
  }

  function retarget(kind, oldId, newId) {
    if (M.selected && M.selected.kind === kind && M.selected.id === oldId) M.selected.id = newId;
    if (M.open.delete(`${kind}:${oldId}`)) M.open.add(`${kind}:${newId}`);
  }

  // ---- 上部のバー ----

  function renderBar() {
    if (!M.els.bar) return;
    const dirty = isDirty();
    const errors = M.issues.filter((i) => i.level === 'error').length;
    const warns = M.issues.length - errors;
    const w = M.draft;
    M.els.bar.replaceChildren(
      h('span', { class: `dirty-badge ${dirty ? 'on' : ''}` }, dirty ? '未保存の変更あり' : '保存済み'),
      h('button', { class: 'primary', disabled: !dirty, onclick: save, title: 'Ctrl+S' }, 'マップを保存'),
      h('button', { disabled: !dirty, onclick: revert }, '元に戻す'),
      h('span', { class: 'spacer' }),
      errors || warns ? h('button', { class: errors ? 'has-error' : 'has-warn', onclick: () => selectEntity_overview(), title: '問題の一覧を開く' }, [errors ? `⛔ エラー${errors}` : '', warns ? `⚠ 警告${warns}` : ''].filter(Boolean).join('  ')) : h('span', { class: 'ok' }, '✓ 問題なし'),
      h('span', { class: 'muted' }, `エリア${w.areas.length}・セクション${w.sections.length}・フロア${w.nodes.length}・アイテム${w.items.length}`));
    const tab = document.querySelector('#tabs button[data-key="map"]');
    if (tab) tab.textContent = dirty ? 'マップ ●' : 'マップ';
  }

  function selectEntity_overview() { M.selected = null; renderTree(); renderDetail(true); }

  // ---- ツリー ----

  function gateMark(node) { return W.gateShort(node.gate); }

  function issueMarks(kind, id) {
    const entry = M.issueMap.get(`${kind}:${id}`);
    if (!entry) return null;
    return h('span', { class: `mark ${entry.errors ? 'mark-error' : 'mark-warn'}`, title: `エラー${entry.errors}件・警告${entry.warns}件` }, entry.errors ? '⛔' : '⚠');
  }

  function toggleOpen(key) {
    if (M.open.has(key)) M.open.delete(key); else M.open.add(key);
    renderTree();
  }

  function treeRow(kind, id, depth, label, sub, openKey, isOpen) {
    const active = M.selected && M.selected.kind === kind && M.selected.id === id;
    return h('div', { class: `tree-row depth${depth} ${active ? 'active' : ''}`, onclick: () => selectEntity(kind, id) },
      openKey ? h('span', { class: 'tree-toggle', onclick: (e) => { e.stopPropagation(); toggleOpen(openKey); } }, isOpen ? '▾' : '▸') : h('span', { class: 'tree-toggle' }),
      h('span', { class: 'tree-label' }, label),
      sub ? h('span', { class: 'tree-sub' }, sub) : null,
      issueMarks(kind, id));
  }

  function renderTree() {
    const box = M.els.tree;
    if (!box) return;
    const top = box.scrollTop;
    const w = M.draft;
    const f = M.filter.trim().toLowerCase();
    const match = (e) => (e.name || '').toLowerCase().includes(f) || (e.id || '').includes(f);
    const rows = [];
    const itemsActive = M.selected && M.selected.kind === 'items';
    rows.push(h('div', { class: `tree-row depth0 items-row ${itemsActive ? 'active' : ''}`, onclick: () => selectEntity('items', '') },
      h('span', { class: 'tree-toggle' }), h('span', { class: 'tree-label' }, '🎒 アイテム定義'), h('span', { class: 'tree-sub' }, `${w.items.length}`)));
    for (const area of w.areas) {
      const areaMatch = !f || match(area);
      const sectionRows = [];
      for (const section of W.sectionsIn(w, area.id)) {
        const sectionMatch = !f || areaMatch || match(section);
        const floors = W.floorsIn(w, section.id);
        const shown = f && !sectionMatch ? floors.filter(match) : floors;
        if (f && !sectionMatch && !shown.length) continue;
        const isOpen = f ? true : M.open.has(`section:${section.id}`);
        sectionRows.push(treeRow('section', section.id, 1, section.name || section.id, `${floors.length}`, `section:${section.id}`, isOpen));
        if (isOpen) {
          for (const node of shown) sectionRows.push(treeRow('floor', node.id, 2, `${node.initially_passed ? '★ ' : ''}${node.name || node.id}`, gateMark(node), null, false));
        }
      }
      if (f && !areaMatch && !sectionRows.length) continue;
      const isOpen = f ? true : M.open.has(`area:${area.id}`);
      rows.push(treeRow('area', area.id, 0, `${w.areas.indexOf(area) + 1}. ${area.name || area.id}`, `${W.sectionsIn(w, area.id).length}`, `area:${area.id}`, isOpen));
      if (isOpen) rows.push(...sectionRows);
    }
    if (rows.length === 1 && f) rows.push(h('p', { class: 'muted pad' }, '一致するものがありません'));
    box.replaceChildren(...rows);
    box.scrollTop = top;
  }

  // ---- 部品 ----

  const kindLabel = (kind) => W.KINDS[kind].label;

  function card(title, ...children) {
    return h('div', { class: 'card' }, h('div', { class: 'card-head' }, h('h3', {}, title)), ...children);
  }

  function nameField(entity) {
    return h('label', { class: 'grow' }, '名前', textInput(entity.name, (v) => { entity.name = v; refresh({ detail: false }); }));
  }

  function idField(kind, entity) {
    const input = textInput(entity.id, null, { class: 'id-input' });
    input.addEventListener('change', () => {
      const oldId = entity.id;
      const err = W.renameId(M.draft, kind, oldId, input.value.trim());
      if (err) { toast(err, 'error'); input.value = oldId; return; }
      retarget(kind, oldId, entity.id);
      refresh();
    });
    const renamed = entity._orig && entity._orig !== entity.id;
    return h('label', {}, 'ID(参照が自動で付け替わります)', input,
      renamed ? h('span', { class: 'muted small' }, `保存すると、「${entity._orig}」を参照しているイベントも、「${entity.id}」に書き換えます`) : null);
  }

  function orderControls(text, index, count, move) {
    return h('div', { class: 'order-controls' },
      h('span', {}, `${text}: ${index + 1}番目 / ${count}`),
      iconButton('▲', '前へ', () => { if (move(-1)) refresh(); }, index <= 0),
      iconButton('▼', '後ろへ', () => { if (move(+1)) refresh(); }, index >= count - 1));
  }

  function link(kind, id, label) {
    return h('button', { class: 'link', onclick: () => selectEntity(kind, id), type: 'button' }, label);
  }

  function floorSelect(value, onchange, exclude, blankLabel) {
    const el = h('select', {});
    if (blankLabel !== undefined) el.append(h('option', { value: '' }, blankLabel));
    for (const area of M.draft.areas) {
      for (const section of W.sectionsIn(M.draft, area.id)) {
        const floors = W.floorsIn(M.draft, section.id).filter((n) => !exclude || !exclude.has(n.id));
        if (floors.length) el.append(h('optgroup', { label: `${area.name} / ${section.name}` }, floors.map((n) => h('option', { value: n.id }, `${n.name} (${n.id})`))));
      }
    }
    el.value = value || '';
    el.addEventListener('change', () => onchange(el.value));
    return el;
  }

  function sectionSelect(value, onchange) {
    const el = h('select', {});
    for (const area of M.draft.areas) {
      const sections = W.sectionsIn(M.draft, area.id);
      if (sections.length) el.append(h('optgroup', { label: area.name }, sections.map((s) => h('option', { value: s.id }, `${s.name} (${s.id})`))));
    }
    el.value = value;
    el.addEventListener('change', () => onchange(el.value));
    return el;
  }

  function issuesBox(kind, id) {
    const mine = M.issues.filter((i) => i.target && i.target.kind === kind && i.target.id === id);
    if (!mine.length) return null;
    return h('div', { class: 'issue-box' }, mine.map((i) => h('div', { class: `issue ${i.level}` }, h('span', {}, i.level === 'error' ? '⛔' : '⚠'), h('span', {}, i.msg))));
  }

  // この要素(保存済みのときのID)を参照している、保存済みのイベント
  function usageBox(kind, entity) {
    if (!entity._orig) return null;
    // フロアの突破/失敗の会話は、専用のボタンで出すので、ここには出さない
    const users = W.eventsUsing(S.bundle.events, kind, entity._orig)
      .map((u) => ({ event: u.event, refs: kind === 'floor' ? u.refs.filter((r) => r.where === '条件' || r.where === '効果') : u.refs }))
      .filter((u) => u.refs.length);
    if (!users.length) return null;
    return h('div', { class: 'usage-box' },
      h('div', { class: 'muted small' }, `この${kindLabel(kind)}を参照しているイベント(${users.length}本)`),
      h('div', { class: 'chips' }, users.slice(0, 40).map(({ event, refs }) => h('button', {
        class: 'chip', type: 'button', title: `${event.id}(${[...new Set(refs.map((r) => r.where))].join('・')})`,
        onclick: () => { WS.showTab('events'); WS.events.select(event.id); },
      }, event.title || event.id)), users.length > 40 ? h('span', { class: 'muted small' }, `…ほか${users.length - 40}本`) : null));
  }

  // ---- 追加ダイアログ ----

  function openAddDialog(kind, parentId) {
    const w = M.draft;
    const base = { area: 'new_area', section: 'new_section', floor: 'new_floor', item: 'new_item' }[kind];
    const form = { name: '', id: W.uniqueId(w, kind, base), connectTo: '' };
    if (kind === 'floor') {
      // つなぎ先は、選んでいるフロアか、そのセクションの最後のフロアを初期値にする
      const inSection = W.floorsIn(w, parentId);
      form.connectTo = M.selected && M.selected.kind === 'floor' && W.find(w, 'floor', M.selected.id) ? M.selected.id : (inSection.length ? inSection[inSection.length - 1].id : '');
    }
    const body = h('div', { class: 'form' },
      h('label', {}, `${kindLabel(kind)}の名前`, textInput('', (v) => { form.name = v; }, { placeholder: kind === 'floor' ? '例: 地下の礼拝堂' : '' })),
      h('label', {}, 'ID(参照に使われる。あとから変えても、参照は付け替わります)', textInput(form.id, (v) => { form.id = v.trim(); }, { class: 'id-input' })),
      kind === 'floor' ? h('label', {}, 'つなぐフロア(任意。双方向の接続になります)', floorSelect(form.connectTo, (v) => { form.connectTo = v; }, null, '(つながない)')) : null);
    openModal(`${kindLabel(kind)}を追加`, body, {
      buttons: [
        { label: 'キャンセル', onclick: (close) => close() },
        { label: '追加', primary: true, onclick: (close) => {
          const name = form.name.trim() || `新しい${kindLabel(kind)}`;
          const result = kind === 'area' ? W.addArea(w, { id: form.id, name })
            : kind === 'section' ? W.addSection(w, parentId, { id: form.id, name })
              : kind === 'floor' ? W.addFloor(w, parentId, { id: form.id, name, connectTo: form.connectTo })
                : W.addItem(w, { id: form.id, name });
          if (result.error) { toast(result.error, 'error'); return; }
          close();
          if (kind === 'section') M.open.add(`area:${parentId}`);
          else if (kind === 'floor') M.open.add(`section:${parentId}`);
          else if (kind === 'area') M.open.add(`area:${form.id}`);
          computeIssues(); renderBar();
          selectEntity(kind === 'item' ? 'items' : kind, kind === 'item' ? '' : form.id);
        } },
      ],
    });
  }

  // ---- 削除 ----

  async function deleteEntity(kind, entity) {
    const w = M.draft;
    const plan = W.collectDeletion(w, kind, entity.id);
    const affected = W.eventsReferencing(S.bundle.events, plan);
    const lines = [];
    if (kind === 'area') lines.push(`エリア「${entity.name}」と、その中の${plan.ids.sections.size}セクション・${plan.ids.floors.size}フロアを削除します。`);
    else if (kind === 'section') lines.push(`セクション「${entity.name}」と、その中の${plan.ids.floors.size}フロアを削除します。`);
    else if (kind === 'floor') lines.push(`フロア「${entity.name}」を削除します。他のフロアからの接続も外れます。`);
    else {
      const gates = w.nodes.filter((n) => n.gate && n.gate.type === 'item' && n.gate.item === entity.id).length;
      const rewards = w.nodes.filter((n) => n.item_reward === entity.id).length;
      lines.push(`アイテム「${entity.name}」を削除します。`);
      if (gates || rewards) lines.push(`(ゲートに使っているフロアが${gates}件、突破報酬にしているフロアが${rewards}件あります。それらは、エラーとして残ります)`);
    }
    if (affected.length) {
      lines.push('', `次のイベントが、消えるものを参照しています。イベント自体は削除されませんが、保存後の検証でエラーになります(イベントタブで直してください):`);
      for (const { event, refs } of affected.slice(0, 8)) lines.push(`・${event.title || event.id}(${[...new Set(refs.map((r) => r.where))].join('・')})`);
      if (affected.length > 8) lines.push(`…ほか${affected.length - 8}本`);
    }
    lines.push('', '(保存するまでは、「元に戻す」で取り消せます)');
    if (!await confirmDialog(lines.join('\n'), '削除', true)) return;
    const parent = kind === 'floor' ? { kind: 'section', id: entity.section } : kind === 'section' ? { kind: 'area', id: entity.area } : null;
    W.deleteEntity(w, kind, entity.id);
    M.selected = parent && W.find(w, parent.kind, parent.id) ? parent : null;
    refresh({ scroll: 'top' });
  }

  // ---- フォーム: エリア ----

  function areaForm(area) {
    const w = M.draft;
    const index = w.areas.indexOf(area);
    const sections = W.sectionsIn(w, area.id);
    return h('div', { class: 'map-form' },
      card('エリア',
        issuesBox('area', area.id),
        h('div', { class: 'form' },
          h('div', { class: 'row' }, nameField(area), idField('area', area)),
          orderControls('エリアの並び', index, w.areas.length, (d) => W.moveArea(w, area.id, d)),
          h('p', { class: 'muted small' }, `エリアの並びは、収入・報酬の倍率になります(このエリアは ×${index + 1}。後のエリアほど高倍率)。また、探索者を「先へ進む」で動かす時の順序にもなります。`)),
        usageBox('area', area)),
      card(`セクション(${sections.length})`,
        h('div', { class: 'rows' }, sections.map((section, i) => h('div', { class: 'list-row' },
          link('section', section.id, section.name || section.id),
          h('span', { class: 'muted small' }, `${W.floorsIn(w, section.id).length}フロア`),
          h('span', { class: 'spacer' }),
          iconButton('▲', '前へ', () => { if (W.moveSection(w, section.id, -1)) refresh(); }, i === 0),
          iconButton('▼', '後ろへ', () => { if (W.moveSection(w, section.id, +1)) refresh(); }, i === sections.length - 1)))),
        h('button', { onclick: () => openAddDialog('section', area.id) }, '＋ セクションを追加'),
        h('p', { class: 'muted small' }, 'セクションの並びは、マップ画面の上からの並びです。また、勝てない敵から退避する時、並びで前にある攻略済みのセクションが退避先になります。')),
      h('div', { class: 'danger-zone' }, h('button', { class: 'danger', onclick: () => deleteEntity('area', area) }, 'このエリアを削除')));
  }

  // ---- フォーム: セクション ----

  function sectionForm(section) {
    const w = M.draft;
    const siblings = W.sectionsIn(w, section.area);
    const floors = W.floorsIn(w, section.id);
    const area = W.find(w, 'area', section.area);
    return h('div', { class: 'map-form' },
      card('セクション',
        issuesBox('section', section.id),
        h('div', { class: 'form' },
          h('div', { class: 'row' }, nameField(section), idField('section', section)),
          h('div', { class: 'row' },
            h('label', {}, '所属エリア(変えると、そのエリアの最後に移ります)', select(w.areas.map((a) => ({ value: a.id, label: `${a.name} (${a.id})` })), section.area, (v) => { if (W.moveSectionToArea(w, section.id, v)) { M.open.add(`area:${v}`); refresh(); } })),
            orderControls('エリア内の並び', siblings.indexOf(section), siblings.length, (d) => W.moveSection(w, section.id, d))),
          area ? h('p', { class: 'muted small' }, '所属: ', link('area', area.id, area.name)) : null),
        usageBox('section', section)),
      card(`フロア(${floors.length}) ― ゲームのマップ画面での並び`,
        floors.length ? h('div', { class: 'floor-grid', style: { '--cols': W.MAP_COLUMNS } }, floors.map((n) => h('button', {
          class: `floor-cell ${n.initially_passed ? 'start' : ''}`, type: 'button', title: `${n.name} (${n.id})`, onclick: () => selectEntity('floor', n.id),
        }, h('span', { class: 'floor-cell-name' }, `${n.initially_passed ? '★ ' : ''}${n.name}`), h('span', { class: 'muted small' }, W.gateShort(n.gate) || 'ゲートなし'), issueMarks('floor', n.id)))) : h('p', { class: 'muted' }, 'フロアがありません'),
        h('p', { class: 'muted small' }, `フロアの並びは、ゲームのマップ画面での配置になります(左上から右へ、${W.MAP_COLUMNS}個ずつ折り返し)。並べ替えは、フロアを選んで「◀ 前へ / 後ろへ ▶」で行います。`),
        h('button', { onclick: () => openAddDialog('floor', section.id) }, '＋ フロアを追加')),
      h('div', { class: 'danger-zone' }, h('button', { class: 'danger', onclick: () => deleteEntity('section', section) }, 'このセクションを削除(中のフロアごと)')));
  }

  // ---- フォーム: フロア ----

  function gateEditor(node) {
    const w = M.draft;
    const gate = node.gate = node.gate || {};
    const field = (label, control) => h('label', {}, label, control);
    const num = (key, fallback) => numberInput(gate[key], (v) => { gate[key] = v === null ? fallback : v; refresh({ detail: false }); }, { class: 'num', min: 1 });
    let fields = null;
    if (gate.type === 'combat') fields = [field('敵の戦闘力', num('enemy_power', 1))];
    else if (gate.type === 'skill') {
      fields = [
        field('技能', select(Object.entries(L.SKILL_NAMES).map(([value, label]) => ({ value, label })), gate.skill, (v) => { gate.skill = v; refresh({ detail: false }); })),
        field('必要レベル(パーティの誰か1人が満たせばよい)', num('min_level', 1)),
      ];
    } else if (gate.type === 'item') {
      const options = w.items.map((i) => ({ value: i.id, label: `${i.name} (${i.id})` }));
      if (gate.item && !W.find(w, 'item', gate.item)) options.unshift({ value: gate.item, label: `${gate.item}(未定義)` });
      fields = [field('必要なアイテム(誰か1人が持っていれば通れる)', select(options, gate.item, (v) => { gate.item = v; refresh({ detail: false }); }))];
    } else if (gate.type === 'innate_trait') {
      const values = [...new Set(w.nodes.filter((n) => n.gate && n.gate.type === 'innate_trait' && n.gate.value).map((n) => n.gate.value))];
      fields = [
        field('特性の項目名', textInput(gate.trait || '', (v) => { gate.trait = v.trim(); refresh({ detail: false }); }, { list: 'trait-names', placeholder: '例: bloodline' })),
        field('必要な値', textInput(gate.value || '', (v) => { gate.value = v.trim(); refresh({ detail: false }); }, { list: 'trait-values', placeholder: '例: 王家の落胤' })),
        h('datalist', { id: 'trait-names' }, h('option', { value: 'bloodline' })),
        h('datalist', { id: 'trait-values' }, values.map((v) => h('option', { value: v }))),
      ];
    }
    return h('div', { class: 'form' },
      h('div', { class: 'row' },
        field('ゲートの種類', select(W.GATE_TYPES, gate.type || '', (v) => { node.gate = W.defaultGate(v, w); refresh(); })),
        fields),
      h('p', { class: 'muted small' }, `会話の見た目(自動): ${(L.KIND_STYLES[L.autoKind(L.worldIndex(w), node.id)] || { label: '従来の見た目(ゲート無し)' }).label}`));
  }

  function connectionsEditor(node) {
    const w = M.draft;
    const rows = node.connections.map((id) => {
      const other = W.find(w, 'floor', id);
      const oneWay = other && !other.connections.includes(node.id);
      const section = other && W.find(w, 'section', other.section);
      return h('div', { class: 'list-row' },
        other ? link('floor', id, other.name || id) : h('span', { class: 'issue-text' }, `${id}(存在しません)`),
        h('span', { class: 'muted small' }, other ? `${section ? section.name : other.section}` : ''),
        oneWay ? h('button', { class: 'small', title: `「${other.name}」側にも、このフロアへの接続を足す`, onclick: () => { W.connect(w, node.id, id); refresh(); } }, '片方向 → 双方向にそろえる') : null,
        h('span', { class: 'spacer' }),
        iconButton('✕', '接続を外す(双方向)', () => { W.disconnect(w, node.id, id); refresh(); }));
    });
    let chosen = '';
    const exclude = new Set([node.id, ...node.connections]);
    const picker = floorSelect('', (v) => { chosen = v; }, exclude, '(つなぐフロアを選ぶ)');
    return h('div', {},
      h('div', { class: 'rows' }, rows.length ? rows : h('p', { class: 'muted' }, '接続がありません(このフロアは、ほかのフロアから発見されません)')),
      h('div', { class: 'row' }, picker, h('button', { onclick: () => { if (chosen && W.connect(w, node.id, chosen)) refresh(); } }, '＋ 接続を追加')),
      h('p', { class: 'muted small' }, '探索者は、突破済みのフロアの隣にあるフロアを発見していきます。接続は常に双方向で保存されます。'));
  }

  function eventChips(node) {
    if (!node._orig) return h('p', { class: 'muted small' }, 'このフロアは、まだ保存されていません。マップを保存すると、会話を追加できます。');
    const renamed = node._orig !== node.id;
    const chip = (result) => {
      const ev = S.bundle.events.find((e) => e.trigger.type === 'gate' && e.trigger.floor === node._orig && e.trigger.result === result);
      const label = result === 'pass' ? '突破' : '失敗';
      if (ev) return h('button', { class: `chip ${result}`, type: 'button', title: ev.title, onclick: () => { WS.showTab('events'); WS.events.select(ev.id); } }, `${label}の会話`);
      return h('button', {
        class: 'chip add', type: 'button', title: `${node.name}に「${label}」の会話を追加`,
        onclick: () => { WS.showTab('events'); WS.events.startNew(L.newGateEvent(S.idx, node._orig, result, new Set(S.bundle.events.map((e) => e.id)))); },
      }, `＋${label}の会話`);
    };
    return h('div', {}, h('div', { class: 'chips' }, chip('pass'), chip('fail')),
      renamed ? h('p', { class: 'muted small' }, 'IDを変えたので、保存するまで、会話は元のID(' + node._orig + ')で扱われます。') : null);
  }

  function floorForm(node) {
    const w = M.draft;
    const section = W.find(w, 'section', node.section);
    const area = section && W.find(w, 'area', section.area);
    const floors = W.floorsIn(w, node.section);
    const rewardOptions = [{ value: '', label: '(なし)' }, ...w.items.map((i) => ({ value: i.id, label: `${i.name} (${i.id})` }))];
    if (node.item_reward && !W.find(w, 'item', node.item_reward)) rewardOptions.push({ value: node.item_reward, label: `${node.item_reward}(未定義)` });
    return h('div', { class: 'map-form' },
      card('フロア',
        issuesBox('floor', node.id),
        h('div', { class: 'form' },
          h('div', { class: 'row' }, nameField(node), idField('floor', node)),
          h('div', { class: 'row' },
            h('label', {}, '所属セクション(変えると、そのセクションの最後に移ります)', sectionSelect(node.section, (v) => { if (W.moveFloorToSection(w, node.id, v)) { M.open.add(`section:${v}`); refresh(); } })),
            h('div', { class: 'order-controls' },
              h('span', {}, `マップ上の位置: ${floors.indexOf(node) + 1} / ${floors.length}`),
              iconButton('◀', '前へ(左へ)', () => { if (W.moveFloor(w, node.id, -1)) refresh(); }, floors.indexOf(node) <= 0),
              iconButton('▶', '後ろへ(右へ)', () => { if (W.moveFloor(w, node.id, +1)) refresh(); }, floors.indexOf(node) >= floors.length - 1))),
          h('label', { class: 'inline' }, h('input', { type: 'checkbox', checked: !!node.initially_passed, onchange: (e) => { node.initially_passed = e.target.checked; refresh(); } }), '開始地点(最初から突破済みにする。探索者はここから発見を始める)'),
          section ? h('p', { class: 'muted small' }, '所属: ', area ? [link('area', area.id, area.name), ' ＞ '] : null, link('section', section.id, section.name)) : null)),
      card('ゲート(このフロアを通る条件)', gateEditor(node)),
      card('突破報酬',
        h('div', { class: 'form' }, h('label', {}, '突破した探索者に渡るアイテム', select(rewardOptions, node.item_reward || '', (v) => { node.item_reward = v; refresh({ detail: false }); })))),
      card(`接続(${node.connections.length})`, connectionsEditor(node)),
      card('このフロアの会話', eventChips(node), usageBox('floor', node)),
      h('div', { class: 'danger-zone' }, h('button', { class: 'danger', onclick: () => deleteEntity('floor', node) }, 'このフロアを削除')));
  }

  // ---- フォーム: アイテム定義 ----

  function itemsForm() {
    const w = M.draft;
    const rows = w.items.map((item, i) => {
      const gates = w.nodes.filter((n) => n.gate && n.gate.type === 'item' && n.gate.item === item.id).length;
      const rewards = w.nodes.filter((n) => n.item_reward === item.id).length;
      const users = item._orig ? W.eventsUsing(S.bundle.events, 'item', item._orig).length : 0;
      const idInput = textInput(item.id, null, { class: 'id-input' });
      idInput.addEventListener('change', () => {
        const oldId = item.id;
        const err = W.renameId(w, 'item', oldId, idInput.value.trim());
        if (err) { toast(err, 'error'); idInput.value = oldId; return; }
        refresh();
      });
      const issues = M.issues.filter((x) => x.target && x.target.kind === 'item' && x.target.id === item.id);
      return h('tr', {},
        h('td', {}, textInput(item.name, (v) => { item.name = v; refresh({ detail: false }); }, { class: 'name-input' })),
        h('td', {}, idInput),
        h('td', { class: 'muted small' }, `ゲート${gates}・報酬${rewards}・イベント${users}`, issues.length ? h('span', { class: 'mark mark-warn' }, ' ⚠') : null),
        h('td', {}, iconButton('▲', '前へ', () => { if (W.moveItem(w, item.id, -1)) refresh(); }, i === 0), iconButton('▼', '後ろへ', () => { if (W.moveItem(w, item.id, +1)) refresh(); }, i === w.items.length - 1), iconButton('✕', '削除', () => deleteEntity('item', item))));
    });
    return h('div', { class: 'map-form' },
      card(`アイテム定義(${w.items.length})`,
        h('p', { class: 'muted small' }, 'ゲートの条件・フロアの突破報酬・イベントの効果(アイテムを渡す)で使うアイテムです。IDを変えると、参照が自動で付け替わります。'),
        h('table', { class: 'map-table' }, h('thead', {}, h('tr', {}, h('th', {}, '名前'), h('th', {}, 'ID'), h('th', {}, '使われ方'), h('th', {}))), h('tbody', {}, rows)),
        h('button', { onclick: () => openAddDialog('item') }, '＋ アイテムを追加')));
  }

  // ---- 何も選んでいない時 ----

  function overview() {
    const w = M.draft;
    const problems = M.issues;
    return h('div', { class: 'map-form' },
      card('マップの編集',
        h('p', {}, '左のツリーから、エリア・セクション・フロアを選んで編集します。'),
        h('ul', { class: 'hint-list' },
          h('li', {}, 'エリアの並び=収入・報酬の倍率(後ろほど高い)。セクションの並び=マップの上下と、撤退先の判定。フロアの並び=マップ画面での配置。'),
          h('li', {}, 'IDを変えても、接続・所属・アイテムの参照とイベントの参照は自動で付け替わります(保存時に、イベントのファイルも書き換えます)。'),
          h('li', {}, '削除しても、それを参照するイベントは消えません(保存後の検証でエラーになるので、イベントタブで直します)。'),
          h('li', {}, 'ゲームに反映されるのは、新規プレイでこのシナリオを選んだ時です(遊び始めたセーブは、その時点のマップのまま)。')),
        h('div', { class: 'row' },
          h('button', { onclick: () => openAddDialog('area') }, '＋ エリアを追加'),
          h('button', { onclick: () => { M.open = new Set(w.areas.map((a) => `area:${a.id}`)); renderTree(); } }, 'セクションをたたむ'),
          h('button', { onclick: () => { M.open = new Set([...w.areas.map((a) => `area:${a.id}`), ...w.sections.map((s) => `section:${s.id}`)]); renderTree(); } }, 'すべて開く'))),
      card(`問題(${problems.length})`,
        problems.length ? h('div', { class: 'validation-list' }, problems.map((i) => h('div', { class: `issue ${i.level}`, onclick: () => { if (i.target) selectEntity(i.target.kind, i.target.id); } }, h('span', {}, i.level === 'error' ? '⛔' : '⚠'), h('span', {}, i.msg)))) : h('p', { class: 'ok' }, '✓ マップに問題は見つかりませんでした。')));
  }

  function renderDetail(scrollTop) {
    const box = M.els.detail;
    if (!box) return;
    const top = box.scrollTop;
    const sel = M.selected;
    let content;
    if (!sel) content = overview();
    else if (sel.kind === 'items') content = itemsForm();
    else {
      const entity = W.find(M.draft, sel.kind, sel.id);
      if (!entity) { M.selected = null; content = overview(); }
      else content = { area: areaForm, section: sectionForm, floor: floorForm }[sel.kind](entity);
    }
    box.replaceChildren(content);
    box.scrollTop = scrollTop ? 0 : top;
  }

  // ---- 保存・取り消し ----

  async function save() {
    if (!isDirty()) return;
    computeIssues();
    const fatal = M.issues.filter((i) => i.fatal);
    if (fatal.length) {
      toast(`保存できない問題があります: ${fatal[0].msg}${fatal.length > 1 ? `(ほか${fatal.length - 1}件)` : ''}`, 'error');
      return;
    }
    const world = W.canonicalWorld(M.draft);
    const changed = W.remapEvents(S.bundle.events, W.diffIds(S.bundle.world, M.draft)).map(L.canonicalEvent);
    if (changed.length && WS.events.hasUnsaved()) {
      toast(`IDの変更に合わせて、${changed.length}本のイベントを書き換える必要があります。先に、イベントタブで、保存していない変更を保存(または破棄)してください`, 'error');
      return;
    }
    try {
      await api('PUT', `/api/scenarios/${S.cur.source}/${S.cur.id}/world`, { world, events: changed });
    } catch (e) { toast(e.message, 'error'); return; }
    S.bundle.world = world;
    S.idx = L.worldIndex(world);
    for (const ev of changed) {
      const i = S.bundle.events.findIndex((e) => e.id === ev.id);
      if (i >= 0) S.bundle.events[i] = ev;
      if (S.working && !S.dirty && !S.isNew && S.working.id === ev.id) { S.working = L.clone(ev); S.workingOrig = JSON.stringify(ev); }
    }
    M.draft = W.startDraft(world);
    M.savedJson = JSON.stringify(world);
    WS.recomputeIssues();
    refresh();
    toast(changed.length ? `マップを保存しました(IDの変更に合わせて、イベント${changed.length}本も更新しました)` : 'マップを保存しました');
  }

  async function revert() {
    if (!isDirty()) return;
    if (!await confirmDialog('マップの、保存していない変更を全て破棄して、保存済みの内容に戻しますか?', '元に戻す', true)) return;
    M.draft = W.startDraft(S.bundle.world);
    refresh({ scroll: 'top' });
  }

  // ---- 表示 ----

  function render(root) {
    ensureDraft();
    const bar = h('div', { class: 'map-bar' });
    const filter = textInput(M.filter, (v) => { M.filter = v; renderTree(); }, { type: 'search', placeholder: '名前・IDで絞り込み', class: 'tree-filter' });
    const tree = h('div', { class: 'map-tree' });
    const detail = h('section', { class: 'map-detail' });
    M.els = { bar, tree, detail };
    root.replaceChildren(h('div', { class: 'map-layout' },
      bar,
      h('aside', { class: 'map-tree-panel' },
        h('div', { class: 'list-tools' }, filter, h('div', { class: 'row-tight' }, h('button', { class: 'small', onclick: () => openAddDialog('area') }, '＋ エリア'), h('button', { class: 'small', onclick: selectEntity_overview }, '概要・問題'))),
        tree),
      detail));
    computeIssues();
    renderBar();
    renderTree();
    renderDetail(true);
  }

  WS.map = { render, reset, hasUnsaved, save, select: (kind, id) => { ensureDraft(); if (W.find(M.draft, kind, id)) selectEntity(kind, id); } };
})(window.WS);
