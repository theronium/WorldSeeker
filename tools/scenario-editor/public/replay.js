// 会話のリプレイ: ゲームの会話ウィンドウ(左右の画像枠・話者名・セリフ・選択肢・種別の色)と同じ見た目と進み方で再生する。
// 編集中の会話(WS.state.working)をそのまま再生する(保存前でも確認できる)。
(function (WS) {
  'use strict';
  const { h, imageUrl } = WS;
  const S = WS.state;
  const L = window.Logic;

  const RESULT_LABELS = { pass: '突破', fail: '失敗' };

  // リプレイの状態(会話ごとに作り直す)
  function fresh() { return { pos: null, left: null, right: null, history: [], ended: null, choicesUsed: [] }; }
  S.replay = fresh();

  function currentKind() {
    const ev = S.working;
    return ev ? L.effectiveKind(ev, S.idx) : '';
  }

  function slotOf(line) {
    // 話者の枠に出す画像。話者名が空、または画像なしのside=noneでは枠を変えない(ゲームと同じ)
    const image = L.resolveImage(line, S.bundle.cast, currentKind());
    return { name: line.name, image };
  }

  function show(pos, pushHistory) {
    const r = S.replay;
    const script = S.working.script;
    if (pushHistory && r.pos !== null) r.history.push({ pos: r.pos, left: r.left, right: r.right });
    r.pos = pos;
    r.ended = null;
    const line = script[pos];
    if (line.side === 'left' && line.name) r.left = slotOf(line);
    if (line.side === 'right' && line.name) r.right = slotOf(line);
  }

  function start(at) {
    const script = S.working.script;
    S.replay = fresh();
    if (!script.length) return;
    show(Math.min(Math.max(at || 0, 0), script.length - 1), false);
    WS.refreshReplay();
  }

  function goTo(step, pos) {
    const target = L.stepTarget(step, pos, S.working.script.length);
    if (target.end) {
      S.replay.history.push({ pos: S.replay.pos, left: S.replay.left, right: S.replay.right });
      S.replay.ended = { outcome: target.outcome };
    } else show(target.to, true);
    WS.refreshReplay();
  }

  function back() {
    const r = S.replay;
    if (r.ended) { r.ended = null; r.history.pop(); WS.refreshReplay(); return; }
    const prev = r.history.pop();
    if (!prev) return;
    r.pos = prev.pos; r.left = prev.left; r.right = prev.right;
    WS.refreshReplay();
  }

  function slotEl(slot, speaking, side) {
    const img = slot && slot.image ? h('img', { src: imageUrl(slot.image), alt: slot.name }) : null;
    return h('div', { class: `slot ${side} ${speaking ? 'speaking' : 'dim'}` },
      h('div', { class: 'slot-image' }, img),
      h('div', { class: 'slot-name' }, speaking && slot ? slot.name : ''));
  }

  function panel() {
    const ev = S.working;
    const r = S.replay;
    const kind = currentKind();
    const style = L.KIND_STYLES[kind];
    const result = ev.trigger.type === 'gate' ? ev.trigger.result : '';
    const accent = style ? (result === 'fail' ? 'rgb(134,120,118)' : style.accent) : null;
    const wrap = h('div', { class: 'replay', style: accent ? { '--accent': accent } : {} });

    const controls = h('div', { class: 'replay-controls' },
      h('button', { class: 'primary', onclick: () => start(0), disabled: !ev.script.length }, '▶ 最初から'),
      h('button', { onclick: back, disabled: !r.history.length && !r.ended }, '◀ 一つ戻る'),
      h('span', { class: 'muted' }, r.pos === null ? '' : `行 ${r.pos + 1} / ${ev.script.length}`));

    if (r.pos === null) {
      wrap.append(h('div', { class: 'replay-empty' }, ev.script.length ? '「▶ 最初から」で、ゲームの会話ウィンドウと同じ見た目で再生します。行の「▶」ボタンで、その行から再生できます。' : '会話の行がありません。'), controls);
      return wrap;
    }

    const line = ev.script[r.pos];
    const speakingLeft = line.side === 'left';
    const speakingRight = line.side === 'right';
    const badgeText = style ? style.label + (RESULT_LABELS[result] ? ` ― ${RESULT_LABELS[result]}` : '') : '';

    const center = h('div', { class: 'replay-center' },
      badgeText ? h('div', { class: 'replay-badge' }, badgeText) : null,
      h('div', { class: 'replay-name' }, line.name || ' '),
      h('div', { class: 'replay-text' }, line.text || ''));

    if (r.ended) {
      center.append(h('div', { class: 'replay-end' }, `会話終了 ― 結果コード: 「${r.ended.outcome || '(なし)'}」`));
      const applied = (ev.effects || []).filter((e) => !e.on || e.on === '*' || e.on === r.ended.outcome);
      if (applied.length) center.append(h('ul', { class: 'replay-effects' }, applied.map((e) => h('li', {}, L.describeEffect(e, S.idx)))));
      else center.append(h('div', { class: 'muted' }, 'この結果で起きる効果はありません。'));
    } else if (line.choices && line.choices.length) {
      center.append(h('div', { class: 'replay-choices' }, line.choices.map((c) => h('button', { onclick: () => goTo(c, r.pos) }, c.label || '(ラベル無し)'))));
    } else {
      center.append(h('button', { class: 'replay-next', onclick: () => goTo(line, r.pos) }, '次へ ▶'));
    }

    wrap.append(h('div', { class: 'replay-stage' }, slotEl(r.left, speakingLeft, 'left'), center, slotEl(r.right, speakingRight, 'right')), controls);
    return wrap;
  }

  WS.replay = { start, panel, reset() { S.replay = fresh(); } };
  WS.refreshReplay = function () {
    const host = document.getElementById('replay-host');
    if (host && S.working) host.replaceChildren(panel());
  };
})(window.WS);
