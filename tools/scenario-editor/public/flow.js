// 会話の簡易フロー図: 行を縦に並べ、分岐(飛び先・選択肢)を右側の曲線で、終わり(結果コード)を右端のバッジで示す。
// 分岐の全体像(どの選択肢がどこへ行き、どの結果で終わるか)を、行リストを読まずに確認するための図。
(function (WS) {
  'use strict';
  const { svg, truncate } = WS;
  const L = window.Logic;

  const ROW_H = 30;
  const BOX_W = 210;
  const BOX_H = 22;
  const X0 = 8;
  const TOP = 8;

  function flowSvg(script, onSelect) {
    const n = script.length;
    const seen = L.reachable(script);
    const intervals = []; // {lo, hi, lane}
    const edges = [];
    script.forEach((line, i) => {
      L.edgesOf(script, i).forEach((e) => {
        if (e.end) { edges.push({ from: i, end: true, outcome: e.outcome, label: e.label }); return; }
        const isChoice = !!(line.choices && line.choices.length);
        if (e.to === i + 1 && !isChoice) { edges.push({ from: i, to: e.to, straight: true }); return; }
        edges.push({ from: i, to: e.to, label: e.label, choice: isChoice });
      });
    });
    // 曲線の走る筋(lane): 区間が重ならない最小の筋に置く
    let lanes = 0;
    for (const e of edges.filter((x) => !x.end && !x.straight)) {
      const lo = Math.min(e.from, e.to);
      const hi = Math.max(e.from, e.to);
      let lane = 0;
      while (intervals.some((iv) => iv.lane === lane && !(hi < iv.lo || lo > iv.hi))) lane++;
      intervals.push({ lo, hi, lane });
      e.lane = lane;
      lanes = Math.max(lanes, lane + 1);
    }
    const width = X0 + BOX_W + 26 + lanes * 12;
    const height = TOP + n * ROW_H + 8;
    const root = svg('svg', { class: 'flow-svg', width, height, viewBox: `0 0 ${width} ${height}` },
      svg('defs', {},
        svg('marker', { id: 'flow-arrow', viewBox: '0 0 8 8', refX: 7, refY: 4, markerWidth: 7, markerHeight: 7, orient: 'auto' }, svg('path', { d: 'M0,0 L8,4 L0,8 z', class: 'flow-arrow-head' }))));

    const yOf = (i) => TOP + i * ROW_H;
    for (const e of edges) {
      if (e.end) continue;
      if (e.straight) {
        root.append(svg('line', { class: 'flow-edge', x1: X0 + 20, y1: yOf(e.from) + BOX_H, x2: X0 + 20, y2: yOf(e.to) - 1, 'marker-end': 'url(#flow-arrow)' }));
        continue;
      }
      const xr = X0 + BOX_W;
      const off = 16 + e.lane * 12;
      const y1 = yOf(e.from) + BOX_H / 2;
      const y2 = yOf(e.to) + BOX_H / 2;
      const path = svg('path', { class: `flow-edge ${e.choice ? 'choice' : 'jump'}`, d: `M${xr},${y1} C${xr + off},${y1} ${xr + off},${y2} ${xr + 1},${y2}`, fill: 'none', 'marker-end': 'url(#flow-arrow)' });
      if (e.label) path.append(svg('title', {}, `選択肢: ${e.label}`));
      root.append(path);
    }
    script.forEach((line, i) => {
      const own = edges.filter((e) => e.from === i && e.end);
      const g = svg('g', { class: `flow-node side-${line.side} ${seen.has(i) ? '' : 'unreachable'}`, onclick: () => onSelect(i) },
        svg('rect', { x: X0, y: yOf(i), width: BOX_W, height: BOX_H, rx: 4 }),
        svg('text', { x: X0 + 6, y: yOf(i) + 15 }, `${i + 1}. ${truncate((line.name ? line.name + ': ' : '') + (line.text || ''), own.length ? 13 : 20)}`));
      g.append(svg('title', {}, `${i + 1}行目: ${line.name || ''} ${line.text || ''}${seen.has(i) ? '' : '\n(どこからも到達できません)'}`));
      if (own.length) {
        // この行で終わる道の結果コード(選択肢が別々の結果で終わるなら、「pass/fail」のように並べる)
        const outcomes = [...new Set(own.map((e) => e.outcome || '終'))];
        const cls = outcomes.length === 1 ? (outcomes[0] === 'pass' ? 'pass' : outcomes[0] === 'fail' ? 'fail' : 'other') : 'other';
        g.append(svg('text', { class: `flow-end ${cls}`, x: X0 + BOX_W - 4, y: yOf(i) + 15, 'text-anchor': 'end' }, '■' + outcomes.join('/')));
      }
      root.append(g);
    });
    return root;
  }

  WS.flowSvg = flowSvg;
})(window.WS);
