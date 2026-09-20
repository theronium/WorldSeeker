// 「登場人物・画像」タブ: 話者名→画像の割り当て(登場人物表)。名前を書いた会話の行は、ここの画像が自動で出る。
// 変更はその場で保存する(登場人物表は1つのファイル)。
(function (WS) {
  'use strict';
  const { h, select, textInput, iconButton, toast, api, confirmDialog, imageUrl } = WS;
  const S = WS.state;
  const L = window.Logic;

  async function saveCast() {
    try {
      await api('PUT', `/api/scenarios/${S.cur.source}/${S.cur.id}/cast`, S.bundle.cast);
      WS.recomputeIssues();
    } catch (e) { toast(e.message, 'error'); }
  }

  function thumbButton(entry, onchange) {
    const btn = h('button', { class: 'image-btn large', type: 'button', title: '画像を選ぶ' },
      entry.image ? h('img', { src: imageUrl(entry.image), alt: entry.image }) : h('span', { class: 'muted' }, '画像なし'),
      h('small', {}, entry.image || '未設定'));
    btn.addEventListener('click', async () => {
      const picked = await WS.pickImage({ speaker: entry.name, current: entry.image, scopes: false, title: `「${entry.name}」の画像を選ぶ` });
      if (!picked) return;
      entry.image = picked.image;
      await saveCast();
      onchange();
    });
    return btn;
  }

  function render(root) {
    const usage = L.usedSpeakers(S.bundle.events);
    const host = h('div', { class: 'cast-tab' });
    const draw = () => {
      const known = new Set(S.bundle.cast.map((c) => c.name));
      const unregistered = [...usage.keys()].filter((n) => !known.has(n)).sort();
      host.replaceChildren(...[
        h('div', { class: 'card' },
          h('div', { class: 'card-head' }, h('h3', {}, '登場人物表'), h('span', { class: 'muted' }, `${S.bundle.cast.length}人`), h('span', { class: 'spacer' }),
            h('button', { class: 'primary', onclick: async () => {
              const name = L.uniqueId('新しい人物', known);
              S.bundle.cast.push({ name, image: 'npc_01', side: 'left' });
              await saveCast(); draw();
            } }, '＋ 登場人物を追加')),
          h('p', { class: 'muted' }, '会話の行の話者名にここの名前を書くと、その画像が自動で出ます。表に無い名前は、名前から自動で画像が選ばれます(同じ名前は同じ画像)。'),
          h('div', { class: 'cast-grid' }, S.bundle.cast.map((entry) => h('div', { class: 'cast-row' },
            thumbButton(entry, draw),
            h('div', { class: 'cast-fields' },
              h('label', {}, '名前', (() => {
                const input = textInput(entry.name, null, { class: 'name-input' });
                input.addEventListener('change', async () => {
                  const value = input.value.trim();
                  if (!value || S.bundle.cast.some((c) => c !== entry && c.name === value)) { toast('名前が空か、他の人物と重複しています', 'error'); input.value = entry.name; return; }
                  entry.name = value; await saveCast(); draw();
                });
                return input;
              })()),
              h('label', {}, '既定の左右', select([{ value: 'left', label: '左(人物)' }, { value: 'right', label: '右(敵)' }], entry.side, async (v) => { entry.side = v; await saveCast(); })),
              h('span', { class: 'muted' }, `会話で ${usage.get(entry.name) || 0} 行に登場`)),
            iconButton('✕', 'この人物を削除', async () => {
              if (!await confirmDialog(`登場人物「${entry.name}」を削除しますか?\n(会話の行は残り、画像は名前からの自動選択に戻ります)`, '削除', true)) return;
              S.bundle.cast = S.bundle.cast.filter((c) => c !== entry); await saveCast(); draw();
            }))))),
        unregistered.length ? h('div', { class: 'card' },
          h('div', { class: 'card-head' }, h('h3', {}, '登場人物表に無い話者'), h('span', { class: 'muted' }, '会話には出てくるが、画像が名前からの自動選択になっている名前')),
          h('div', { class: 'chips' }, unregistered.map((name) => h('button', { class: 'chip', title: '登録して画像を選ぶ', onclick: async () => {
            const entry = { name, image: L.fallbackImage(name, ''), side: 'left' };
            const rightLines = S.bundle.events.flatMap((e) => e.script).filter((l) => l.name === name && l.side === 'right').length;
            entry.side = rightLines > (usage.get(name) || 0) / 2 ? 'right' : 'left';
            if (entry.side === 'right') entry.image = L.fallbackImage(name, 'boss');
            S.bundle.cast.push(entry);
            await saveCast(); draw();
            const picked = await WS.pickImage({ speaker: name, current: entry.image, scopes: false, title: `「${name}」の画像を選ぶ` });
            if (picked && picked.image) { entry.image = picked.image; await saveCast(); draw(); }
          } }, `${name} (${usage.get(name)}行)`)))) : null,
      ].filter(Boolean));
    };
    draw();
    root.replaceChildren(host);
  }

  WS.cast = { render };
})(window.WS);
