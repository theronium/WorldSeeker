// 画面の共通部品: DOM生成、APIの呼び出し、モーダル、通知。全体の状態は WS.state に置く。
window.WS = window.WS || { state: {} };
(function (WS) {
  'use strict';

  // h('div', {class:'x', onclick: fn}, 子...) でDOMを作る。falsy(null/false/undefined)の子や属性は無視する
  function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
      if (value === undefined || value === null || value === false) continue;
      if (key === 'class') el.className = value;
      else if (key === 'style' && typeof value === 'object') {
        for (const [name, v] of Object.entries(value)) { if (name.startsWith('--')) el.style.setProperty(name, v); else el.style[name] = v; }
      } else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2), value);
      else if (key === 'value') continue; // 子を入れた後に設定する(selectのため)
      else if (key === 'checked' || key === 'disabled' || key === 'readOnly' || key === 'selected') el[key] = value;
      else el.setAttribute(key, value === true ? '' : value);
    }
    for (const child of children.flat(Infinity)) {
      if (child === null || child === undefined || child === false) continue;
      el.append(child.nodeType ? child : document.createTextNode(String(child)));
    }
    if (attrs && attrs.value !== undefined && attrs.value !== null) el.value = attrs.value;
    return el;
  }

  const SVG_NS = 'http://www.w3.org/2000/svg';
  function svg(tag, attrs, ...children) {
    const el = document.createElementNS(SVG_NS, tag);
    for (const [key, value] of Object.entries(attrs || {})) {
      if (value === undefined || value === null) continue;
      if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2), value);
      else el.setAttribute(key, value);
    }
    for (const child of children.flat(Infinity)) if (child) el.append(child.nodeType ? child : document.createTextNode(String(child)));
    return el;
  }

  async function api(method, url, body) {
    const init = { method, headers: { 'X-WS-Editor': '1' } };
    if (body instanceof Blob || body instanceof ArrayBuffer) init.body = body;
    else if (body !== undefined) { init.body = JSON.stringify(body); init.headers['Content-Type'] = 'application/json'; }
    const res = await fetch(url, init);
    const data = await res.json().catch(() => null);
    if (!res.ok) {
      const error = new Error(data && data.error ? data.error : `通信に失敗しました (HTTP ${res.status})`);
      error.status = res.status;
      error.data = data; // 応答のJSON(取り込みで同じIDが既にある時の {exists, id, name} など)
      throw error;
    }
    return data;
  }

  // ---- 通知 ----
  function toast(message, kind) {
    let box = document.getElementById('toasts');
    if (!box) { box = h('div', { id: 'toasts' }); document.body.append(box); }
    const el = h('div', { class: `toast ${kind || ''}` }, message);
    box.append(el);
    setTimeout(() => el.remove(), kind === 'error' ? 8000 : 3500);
  }

  // ---- モーダル ----
  // openModal(タイトル, 中身, {buttons:[{label, primary, onclick(close)}], wide}) → {close, el}
  function openModal(title, content, opts) {
    opts = opts || {};
    const backdrop = h('div', { class: 'modal-backdrop' });
    const close = () => { backdrop.remove(); document.removeEventListener('keydown', onKey); };
    const onKey = (e) => { if (e.key === 'Escape') { close(); if (opts.onCancel) opts.onCancel(); } };
    const buttons = (opts.buttons || []).map((b) => h('button', { class: b.primary ? 'primary' : '', onclick: () => b.onclick(close) }, b.label));
    const modal = h('div', { class: `modal ${opts.wide ? 'wide' : ''}`, role: 'dialog' },
      h('div', { class: 'modal-title' }, title),
      h('div', { class: 'modal-body' }, content),
      buttons.length ? h('div', { class: 'modal-buttons' }, buttons) : null);
    backdrop.append(modal);
    backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop && opts.onCancel) { close(); opts.onCancel(); } });
    document.addEventListener('keydown', onKey);
    document.body.append(backdrop);
    const first = modal.querySelector('input, select, textarea');
    if (first && !opts.noFocus) first.focus();
    return { close, el: modal };
  }

  function confirmDialog(message, okLabel, danger) {
    return new Promise((resolve) => {
      openModal('確認', h('p', { style: { whiteSpace: 'pre-wrap' } }, message), {
        onCancel: () => resolve(false),
        buttons: [
          { label: 'キャンセル', onclick: (close) => { close(); resolve(false); } },
          { label: okLabel || 'OK', primary: !danger, onclick: (close) => { close(); resolve(true); } },
        ],
      });
      if (danger) document.querySelector('.modal-buttons button:last-child').classList.add('danger');
    });
  }

  // ---- 入力部品 ----
  function select(options, value, onchange, attrs) {
    const el = h('select', attrs || {}, options.map((o) => h('option', { value: o.value }, o.label)));
    el.value = value === undefined || value === null ? '' : value;
    if (onchange) el.addEventListener('change', () => onchange(el.value));
    return el;
  }

  function textInput(value, oninput, attrs) {
    const el = h('input', { type: 'text', ...(attrs || {}) });
    el.value = value === undefined || value === null ? '' : value;
    if (oninput) el.addEventListener('input', () => oninput(el.value));
    return el;
  }

  function numberInput(value, oninput, attrs) {
    const el = h('input', { type: 'number', step: '1', ...(attrs || {}) });
    el.value = value === undefined || value === null ? '' : value;
    if (oninput) el.addEventListener('input', () => oninput(el.value === '' ? null : parseInt(el.value, 10)));
    return el;
  }

  function iconButton(label, title, onclick, disabled) {
    return h('button', { class: 'icon', title, onclick, disabled: !!disabled, type: 'button' }, label);
  }

  function truncate(text, n) {
    const s = String(text || '').replace(/\s+/g, ' ');
    return s.length > n ? s.slice(0, n) + '…' : s;
  }

  // 画像のidから、表示用のURLを返す(ライブラリのidか、"@ファイル名.png"=このシナリオの画像)
  function imageUrl(id) {
    if (!id) return '';
    const s = WS.state;
    if (id.startsWith('@')) return s.cur ? `/scenario-images/${s.cur.source}/${s.cur.id}/${encodeURIComponent(id.slice(1))}?v=${s.imageVersion || 0}` : '';
    return `/library/${id}.png`;
  }

  Object.assign(WS, { h, svg, api, toast, openModal, confirmDialog, select, textInput, numberInput, iconButton, truncate, imageUrl });
})(window.WS);
