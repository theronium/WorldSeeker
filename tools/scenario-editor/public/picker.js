// 画像の選択(ライブラリの町人/敵/探索者と、このシナリオ固有の画像)とアップロード。
(function (WS) {
  'use strict';
  const { h, api, toast, openModal, imageUrl } = WS;
  const S = WS.state;

  const GROUPS = [
    { key: 'npc', label: '町人・人物' },
    { key: 'enemy', label: '敵' },
    { key: 'char', label: '探索者' },
    { key: 'scenario', label: 'このシナリオの画像' },
  ];

  // 画像を選ぶ。{speaker, current, scopes} → Promise<{image, scope}|null>。
  //   scopes: 適用先の選択肢を出すか(話者名があれば「この話者すべて(登場人物表)」と「この行だけ」を選べる)
  //   image==='' は「指定を解除」(その行の指定を外す / 登場人物表から外す)
  function pickImage(opts) {
    return new Promise((resolve) => {
      let chosen = opts.current || '';
      let group = chosen.startsWith('@') ? 'scenario' : (chosen.split('_')[0] || 'npc');
      if (!GROUPS.some((g) => g.key === group)) group = 'npc';
      let scope = opts.scopes ? 'cast' : 'line';
      const body = h('div', { class: 'picker' });
      const tabs = h('div', { class: 'tabs small' });
      const grid = h('div', { class: 'image-grid' });
      const scopeBox = opts.scopes ? h('div', { class: 'scope-box' },
        h('span', {}, '適用先: '),
        h('label', {}, h('input', { type: 'radio', name: 'scope', value: 'cast', checked: true, onchange: () => { scope = 'cast'; } }), ` 「${opts.speaker}」の標準の画像(登場人物表)`),
        h('label', {}, h('input', { type: 'radio', name: 'scope', value: 'line', onchange: () => { scope = 'line'; } }), ' この行だけ')) : null;

      function renderTabs() {
        tabs.replaceChildren(...GROUPS.map((g) => h('button', { class: g.key === group ? 'active' : '', onclick: () => { group = g.key; render(); } }, g.label)));
      }

      function thumb(id, extra) {
        return h('button', { class: `thumb ${id === chosen ? 'selected' : ''}`, title: id, onclick: () => { chosen = id; render(); }, ondblclick: () => { chosen = id; finish(); } },
          h('img', { src: imageUrl(id), loading: 'lazy', alt: id }), h('span', {}, id.replace(/^@/, '')), extra);
      }

      function render() {
        renderTabs();
        grid.replaceChildren();
        if (group === 'scenario') {
          const images = S.bundle.images || [];
          const input = h('input', { type: 'file', accept: 'image/png', onchange: async () => {
            const file = input.files[0];
            if (!file) return;
            const name = (file.name.replace(/[^A-Za-z0-9_.-]/g, '_').replace(/\.png$/i, '') || 'image').slice(0, 56) + '.png';
            try {
              S.bundle.images = await api('POST', `/api/scenarios/${S.cur.source}/${S.cur.id}/images?name=${encodeURIComponent(name)}`, file);
              S.imageVersion = (S.imageVersion || 0) + 1;
              chosen = '@' + name;
              toast(`画像「${name}」を追加しました`);
              render();
            } catch (e) { toast(e.message, 'error'); }
          } });
          grid.append(h('div', { class: 'upload-row' },
            h('div', {}, h('strong', {}, 'PNG画像を追加'), ' (正方形・256px程度を推奨。ゲームは正方形の枠に表示します)'), input));
          for (const img of images) {
            const badTip = img.width !== img.height ? `正方形ではありません(${img.width}x${img.height})。枠に合わせて引き伸ばされます。` : (img.width > 1024 ? '大きすぎます(1024px以下を推奨)' : '');
            const del = h('span', { class: 'thumb-del', title: 'この画像を削除', onclick: async (e) => {
              e.stopPropagation();
              if (!await WS.confirmDialog(`画像「${img.name}」を削除しますか?\n使っている会話や登場人物表では、画像が出なくなります。`, '削除', true)) return;
              try { S.bundle.images = await api('DELETE', `/api/scenarios/${S.cur.source}/${S.cur.id}/images/${encodeURIComponent(img.name)}`); if (chosen === '@' + img.name) chosen = ''; render(); } catch (err) { toast(err.message, 'error'); }
            } }, '✕');
            const el = thumb('@' + img.name, del);
            if (badTip) el.append(h('em', { class: 'warn-mark', title: badTip }, '⚠'));
            grid.append(el);
          }
          if (!images.length) grid.append(h('p', { class: 'muted' }, 'まだ画像がありません。上のボタンからPNGを追加できます。'));
        } else {
          for (const item of S.library.filter((i) => i.group === group)) grid.append(thumb(item.id));
        }
      }

      function finish() {
        modal.close();
        resolve({ image: chosen, scope });
      }

      body.append(...[tabs, grid, scopeBox].filter(Boolean));
      render();
      const modal = openModal(opts.title || '画像を選ぶ', body, {
        wide: true, noFocus: true, onCancel: () => resolve(null),
        buttons: [
          { label: 'キャンセル', onclick: (close) => { close(); resolve(null); } },
          { label: '指定を解除', onclick: () => { chosen = ''; finish(); } },
          { label: '決定', primary: true, onclick: () => { if (!chosen) { toast('画像を選んでください(外すには「指定を解除」)', 'error'); return; } finish(); } },
        ],
      });
    });
  }

  WS.pickImage = pickImage;
})(window.WS);
