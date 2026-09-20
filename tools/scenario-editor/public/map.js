// 「マップ(参照)」タブ: エリア>セクション>フロアの一覧と、各フロアのゲート・報酬・付いているイベント。
// マップの編集は今後(初版は参照のみ)。フロアに会話を付ける入口としても使う。
(function (WS) {
  'use strict';
  const { h } = WS;
  const S = WS.state;
  const L = window.Logic;

  function render(root) {
    const world = S.bundle.world;
    const gateEvent = (floorId, result) => S.bundle.events.find((e) => e.trigger.type === 'gate' && e.trigger.floor === floorId && e.trigger.result === result);
    const chip = (floor, result) => {
      const ev = gateEvent(floor.id, result);
      const label = result === 'pass' ? '突破' : '失敗';
      if (ev) {
        return h('button', { class: `chip ${result}`, title: ev.title, onclick: () => { WS.showTab('events'); WS.events.select(ev.id); } }, `${label}の会話`);
      }
      return h('button', { class: 'chip add', title: `${floor.name}に「${label}」の会話を追加`, onclick: () => WS.events.startNew(L.newGateEvent(S.idx, floor.id, result, new Set(S.bundle.events.map((e) => e.id)))) }, `＋${label}の会話`);
    };
    const tree = h('div', { class: 'map-tab' },
      h('p', { class: 'muted pad' }, 'マップの編集は今後の予定です(今は参照のみ)。フロアの「＋」から、そのフロアの会話を追加できます。'),
      world.areas.map((area, areaIndex) => h('div', { class: 'card' },
        h('div', { class: 'card-head' }, h('h3', {}, `${areaIndex + 1}. ${area.name}`), h('span', { class: 'muted' }, area.id)),
        world.sections.filter((s) => s.area === area.id).map((section) => h('div', { class: 'map-section' },
          h('h4', {}, section.name, h('span', { class: 'muted' }, ` ${section.id} ・ ${(S.idx.floorsBySection.get(section.id) || []).length}フロア`)),
          h('table', { class: 'map-table' }, (S.idx.floorsBySection.get(section.id) || []).map((floor) => h('tr', {},
            h('td', { class: 'floor-name' }, floor.name, floor.initially_passed ? h('span', { class: 'badge sys' }, '開始地点') : null, h('div', { class: 'muted small' }, floor.id)),
            h('td', {}, L.gateSummary(floor.gate, S.idx)),
            h('td', { class: 'muted' }, floor.item_reward ? `報酬: ${(S.idx.items.get(floor.item_reward) || { name: floor.item_reward }).name}` : ''),
            h('td', { class: 'chips' }, chip(floor, 'pass'), chip(floor, 'fail'))))))))));
    root.replaceChildren(tree);
  }

  WS.map = { render };
})(window.WS);
