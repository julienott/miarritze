// Miarritze Producer — interface (JS vanilla, aucune dépendance).
// Sécurité : tout contenu venant de l'API est inséré via textContent / attributs,
// jamais via innerHTML.
'use strict';

const STATUSES = [
  ['todo', 'À faire'], ['doing', 'En cours'], ['review', 'À vérifier'], ['done', 'Fait'],
];
const STATUS_LABEL = Object.fromEntries(STATUSES);
const KIND_LABEL = { amelioration: 'Amélioration', valide: 'Validé' };
const PRIO_LABEL = { '': '', basse: 'Basse', normale: 'Normale', haute: 'Haute' };
const ZOOMS = [1, 2, 3, 4, 6, 8];

const state = {
  csrf: '',
  index: null,
  assetsById: new Map(),
  comments: [],
  cards: [],
  cat: '',
  group: '',
  search: '',
  stageBg: store('producer-stage') || 'light',
  zoom: 0,           // 0 = automatique
  player: null,      // lecteur d'animation en cours
  editing: null,     // carte en cours d'édition (null = nouvelle)
};

// ------------------------------------------------------------------ utilitaires

// Zoom entier le plus grand qui tient en largeur ET en hauteur (≈ 55 % de
// l'écran) : les commandes et les commentaires restent visibles sur mobile.
function autoZoom(stage, w, h, max) {
  const fitW = (Math.min(stage.clientWidth, 900) - 24) / w;
  const fitH = Math.max(160, window.innerHeight * 0.55) / h;
  return Math.max(1, Math.min(max, Math.floor(Math.min(fitW, fitH))));
}

function store(key, value) {
  try {
    if (value === undefined) return localStorage.getItem(key);
    localStorage.setItem(key, value);
  } catch (e) { /* stockage indisponible : on s'en passe */ }
  return null;
}

/** Crée un élément ; les enfants texte passent par des nœuds texte (zéro HTML). */
function el(tag, attrs, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === null || v === undefined || v === false) continue;
    if (k === 'class') node.className = v;
    else if (k === 'text') node.textContent = v;
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v === true ? '' : String(v));
  }
  for (const c of children.flat()) {
    if (c === null || c === undefined || c === false) continue;
    node.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return node;
}

const $ = (id) => document.getElementById(id);

function fmtDate(ts) {
  return new Date(ts * 1000).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' });
}

function fileUrl(p) {
  return 'index.php?r=file&p=' + encodeURIComponent(p);
}

let toastTimer = 0;
function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 2500);
}

class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

async function api(route, { method = 'GET', body, query } = {}) {
  let url = 'index.php?r=' + encodeURIComponent(route);
  for (const [k, v] of Object.entries(query || {})) {
    url += '&' + encodeURIComponent(k) + '=' + encodeURIComponent(v);
  }
  const headers = { Accept: 'application/json' };
  if (method !== 'GET') {
    headers['Content-Type'] = 'application/json';
    headers['X-CSRF-Token'] = state.csrf;
  }
  const res = await fetch(url, {
    method, headers, credentials: 'same-origin', cache: 'no-store',
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data = null;
  try { data = await res.json(); } catch (e) { data = null; }
  if (!res.ok) {
    if (res.status === 401 && route !== 'login') showLogin();
    throw new ApiError(res.status, (data && data.error) || ('Erreur ' + res.status));
  }
  return data;
}

async function guarded(fn) {
  try {
    return await fn();
  } catch (e) {
    toast(e.message || 'Erreur');
    return null;
  }
}

// ------------------------------------------------------------------ thème

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  store('producer-theme', theme);
}

function initTheme() {
  const saved = store('producer-theme');
  const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  applyTheme(saved || (prefersDark ? 'dark' : 'light'));
  $('theme').addEventListener('click', () => {
    applyTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');
  });
}

// ---------------------------------------------------------------- connexion

function showLogin() {
  stopPlayer();
  $('login').hidden = false;
  $('tabs').hidden = true;
  $('logout').hidden = true;
  for (const v of document.querySelectorAll('.view')) v.hidden = true;
  setTimeout(() => $('password').focus(), 0);
}

async function boot() {
  initTheme();
  $('login-form').addEventListener('submit', onLogin);
  $('logout').addEventListener('click', onLogout);
  initAssetsView();
  initKanban();
  initCommentsView();
  window.addEventListener('hashchange', route);
  const s = await guarded(() => api('session'));
  if (!s) return;
  state.csrf = s.csrf;
  if (s.auth) await enter();
  else showLogin();
}

async function onLogin(ev) {
  ev.preventDefault();
  $('login-error').textContent = '';
  try {
    const r = await api('login', { method: 'POST', body: { password: $('password').value } });
    state.csrf = r.csrf;
    $('password').value = '';
    await enter();
  } catch (e) {
    $('login-error').textContent = e.message;
  }
}

async function onLogout() {
  await guarded(() => api('logout', { method: 'POST', body: {} }));
  state.index = null;
  const s = await guarded(() => api('session'));
  if (s) state.csrf = s.csrf;
  location.hash = '';
  showLogin();
}

async function enter() {
  $('login').hidden = true;
  $('tabs').hidden = false;
  $('logout').hidden = false;
  const [index] = await Promise.all([api('index'), reloadComments(), reloadCards()]);
  state.index = index;
  state.assetsById = new Map(index.assets.map((a) => [a.id, a]));
  const dl = $('asset-ids');
  dl.replaceChildren(...index.assets.map((a) => el('option', { value: a.id })));
  renderCats();
  route();
}

async function reloadComments() {
  const r = await api('comments');
  state.comments = r.comments;
}

async function reloadCards() {
  const r = await api('cards');
  state.cards = r.cards;
}

// ---------------------------------------------------------------- routage

function route() {
  if (!state.index) return;
  const hash = location.hash || '#/assets';
  const [, tab, ...rest] = hash.split('/');
  const current = ['assets', 'kanban', 'comments'].includes(tab) ? tab : 'assets';
  for (const a of document.querySelectorAll('#tabs a')) {
    a.classList.toggle('active', a.dataset.tab === current);
  }
  for (const v of document.querySelectorAll('.view')) v.hidden = v.id !== 'view-' + current;
  stopPlayer();
  if (current === 'assets') {
    const id = rest.length ? decodeURIComponent(rest.join('/')) : '';
    if (id && state.assetsById.has(id)) showDetail(state.assetsById.get(id));
    else showGrid();
  } else if (current === 'kanban') {
    renderBoard();
  } else {
    renderCommentList();
  }
}

// ================================================================== ASSETS

function initAssetsView() {
  $('search').addEventListener('input', (e) => {
    state.search = e.target.value.trim().toLowerCase();
    if (location.hash.startsWith('#/assets/')) location.hash = '#/assets';
    else showGrid();
  });
  applyStageBg();
}

function applyStageBg() {
  document.body.classList.toggle('stage-dark', state.stageBg === 'dark');
}

function openCount(assetId) {
  return state.comments.filter((c) => c.asset === assetId && c.status === 'open').length;
}

function renderCats() {
  const ul = $('cats');
  const assets = state.index.assets;
  const items = [];
  const mk = (label, cat, group, count, sub) => {
    const active = state.cat === cat && state.group === group;
    const li = el('li', { class: sub ? 'sub' + (state.cat === cat ? ' show' : '') : '' },
      el('button', {
        type: 'button', class: active ? 'active' : '',
        onclick: () => {
          state.cat = cat; state.group = group;
          renderCats();
          if (location.hash.startsWith('#/assets/')) location.hash = '#/assets';
          else showGrid();
        },
      }, el('span', { text: label }), el('span', { class: 'muted', text: String(count) })));
    items.push(li);
  };
  mk('Tout', '', '', assets.length, false);
  for (const cat of state.index.categories) {
    const inCat = assets.filter((a) => a.cat === cat);
    if (!inCat.length) continue;
    mk(cat, cat, '', inCat.length, false);
    const groups = [...new Set(inCat.map((a) => a.group))];
    if (groups.length > 1) {
      for (const g of groups) mk(g, cat, g, inCat.filter((a) => a.group === g).length, true);
    }
  }
  ul.replaceChildren(...items);
}

function filteredAssets() {
  const q = state.search;
  return state.index.assets.filter((a) =>
    (!state.cat || a.cat === state.cat) &&
    (!state.group || a.group === state.group) &&
    (!q || a.id.toLowerCase().includes(q) || a.name.toLowerCase().includes(q) ||
      (a.anims || []).some((x) => x.name.includes(q))));
}

function showGrid() {
  stopPlayer();
  $('detail').hidden = true;
  const grid = $('grid');
  grid.hidden = false;
  const list = filteredAssets();
  if (!list.length) {
    grid.replaceChildren(el('p', { class: 'empty', text: 'Aucun asset ne correspond.' }));
    return;
  }
  grid.replaceChildren(...list.map(tile));
}

function tile(a) {
  const n = openCount(a.id);
  const idle = a.type === 'sprite' && (a.anims.find((x) => x.name === 'idle') || a.anims[0]);
  const thumb = a.type === 'audio'
    ? el('div', { class: 'thumb audio', text: '♪' })
    : idle
      ? el('div', { class: 'thumb' }, miniAnim(idle, 0))
      : el('div', { class: 'thumb' }, el('img', { src: fileUrl(a.preview), alt: '', loading: 'lazy' }));
  return el('button', {
    type: 'button', class: 'tile', 'data-id': a.id,
    onclick: () => { location.hash = '#/assets/' + encodeURIComponent(a.id); },
  }, thumb, el('span', { class: 'name', text: a.name }),
  n ? el('span', { class: 'count' }, el('span', { class: 'badge amelioration', text: n + ' ouvert' + (n > 1 ? 's' : '') })) : null);
}

function stopPlayer() {
  if (state.player) {
    clearTimeout(state.player.timer);
    state.player = null;
  }
}

// Mini-animations (vignettes des persos, galerie des animations) : une seule
// boucle requestAnimationFrame ; une vignette retirée de la page est oubliée.
const minis = new Set();
let minisRunning = false;

function miniAnim(anim, box) {
  const canvas = el('canvas', { width: anim.w, height: anim.h });
  const m = { anim, canvas, ctx: canvas.getContext('2d'), img: null, frame: 0, next: 0 };
  const img = new Image();
  img.onload = () => { m.img = img; drawMini(m); };
  img.src = fileUrl(anim.file);
  // Taille d'affichage : zoom entier qui tient dans la case (pixels nets) ;
  // sans case, c'est la feuille de style qui ajuste (vignettes de la grille).
  if (box) {
    const z = Math.max(1, Math.floor(Math.min(box / anim.w, box / anim.h)));
    canvas.style.width = anim.w * z + 'px';
    canvas.style.height = anim.h * z + 'px';
  }
  minis.add(m);
  if (!minisRunning) { minisRunning = true; requestAnimationFrame(tickMinis); }
  return canvas;
}

function drawMini(m) {
  m.ctx.clearRect(0, 0, m.anim.w, m.anim.h);
  m.ctx.drawImage(m.img, m.frame * m.anim.w, 0, m.anim.w, m.anim.h, 0, 0, m.anim.w, m.anim.h);
}

function tickMinis(t) {
  for (const m of minis) {
    if (!m.canvas.isConnected && m.img) { minis.delete(m); continue; }
    if (!m.img || t < m.next) continue;
    const last = m.frame === m.anim.frames - 1;
    m.frame = (m.frame + 1) % m.anim.frames;
    drawMini(m);
    // Comme le lecteur : une animation sans boucle marque une pause avant de recommencer.
    m.next = t + 1000 / m.anim.fps + (last && !m.anim.loop ? 500 : 0);
  }
  if (minis.size) requestAnimationFrame(tickMinis);
  else minisRunning = false;
}

function showDetail(a) {
  stopPlayer();
  $('grid').hidden = true;
  const d = $('detail');
  d.hidden = false;
  const stage = el('div', { class: 'stage ' + state.stageBg });
  const bgButtons = [['light', 'Clair'], ['dark', 'Sombre'], ['checker', 'Damier']].map(([v, label]) =>
    el('button', {
      type: 'button', class: 'small' + (state.stageBg === v ? ' primary' : ''),
      onclick: () => {
        state.stageBg = v; store('producer-stage', v); applyStageBg();
        stage.className = 'stage ' + v;
        for (const b of bgButtons) b.classList.toggle('primary', b.dataset.bg === v);
      },
      'data-bg': v,
    }, label));
  const zoomSel = el('select', { 'aria-label': 'Zoom' },
    el('option', { value: '0', text: 'Zoom auto' }),
    ZOOMS.map((z) => el('option', { value: String(z), text: '×' + z })));
  zoomSel.value = String(state.zoom);

  const controls = el('div', { class: 'controls' });
  let gallery = null;
  let context = () => '';
  let applyZoom = () => {};

  if (a.type === 'audio') {
    // MP3 d'abord : Safari iOS ne lit pas toujours le Vorbis.
    const isMp3 = (s) => (s.endsWith('.mp3') ? 1 : 0);
    const sources = [...(a.sources || [a.file])].sort((x, y) => isMp3(y) - isMp3(x));
    const audio = el('audio', { controls: true, preload: 'metadata' },
      sources.map((s) => el('source', { src: fileUrl(s), type: s.endsWith('.mp3') ? 'audio/mpeg' : 'audio/ogg' })));
    stage.append(audio);
    stage.classList.add('audio-stage');
    if (a.credits && a.credits.length) {
      const part = (p) => (p.url && /^https:\/\//.test(p.url)
        ? el('a', { href: p.url, target: '_blank', rel: 'noopener noreferrer', text: p.t })
        : document.createTextNode(p.t));
      controls.append(el('dl', { class: 'credits' },
        a.credits.flatMap((c) => [el('dt', { text: c.label }), el('dd', {}, c.parts.map(part))])));
    }
  } else if (a.type === 'sprite') {
    const animSel = el('select', { 'aria-label': 'Animation' },
      a.anims.map((x) => el('option', { value: x.name, text: `${x.name} (${x.frames})` })));
    const def = a.anims.find((x) => x.name === 'idle') || a.anims[0];
    animSel.value = def.name;
    const canvas = el('canvas');
    const ctx = canvas.getContext('2d');
    const frameLbl = el('span', { class: 'muted' });
    const playBtn = el('button', { type: 'button', class: 'small', text: '⏸ Pause' });
    stage.append(canvas);
    const p = { anim: def, img: null, frame: 0, playing: true, timer: 0 };
    state.player = p;
    const draw = () => {
      if (!p.img) return;
      const { w, h } = p.anim;
      ctx.clearRect(0, 0, w, h);
      ctx.drawImage(p.img, p.frame * w, 0, w, h, 0, 0, w, h);
      frameLbl.textContent = `frame ${p.frame + 1}/${p.anim.frames} · ${p.anim.fps} i/s` + (p.anim.loop ? ' · boucle' : '');
    };
    const tick = () => {
      if (state.player !== p || !p.playing) return;
      const last = p.frame === p.anim.frames - 1;
      p.frame = (p.frame + 1) % p.anim.frames;
      draw();
      // Une animation sans boucle marque une pause avant de recommencer.
      const delay = 1000 / p.anim.fps + (last && !p.anim.loop ? 500 : 0);
      p.timer = setTimeout(tick, delay);
    };
    applyZoom = () => {
      const z = state.zoom || autoZoom(stage, p.anim.w, p.anim.h, 4);
      canvas.style.width = p.anim.w * z + 'px';
      canvas.style.height = p.anim.h * z + 'px';
    };
    const load = (anim) => {
      clearTimeout(p.timer);
      p.anim = anim; p.frame = 0; p.img = null;
      canvas.width = anim.w; canvas.height = anim.h;
      applyZoom();
      const img = new Image();
      img.onload = () => {
        if (p.anim !== anim) return;
        p.img = img; draw();
        if (p.playing) p.timer = setTimeout(tick, 1000 / anim.fps);
      };
      img.src = fileUrl(anim.file);
    };
    animSel.addEventListener('change', () => load(a.anims.find((x) => x.name === animSel.value)));
    // Toutes les animations du perso en même temps ; un clic l'ouvre dans le lecteur.
    gallery = el('div', { class: 'anim-gallery' }, a.anims.map((x) =>
      el('button', {
        type: 'button', class: 'anim-cell', title: `${x.name} (${x.frames} images)`,
        onclick: () => { animSel.value = x.name; load(x); stage.scrollIntoView({ behavior: 'smooth', block: 'nearest' }); },
      }, el('div', { class: 'anim-box' }, miniAnim(x, 88)), el('span', { text: x.name }))));
    playBtn.addEventListener('click', () => {
      p.playing = !p.playing;
      playBtn.textContent = p.playing ? '⏸ Pause' : '▶ Lecture';
      clearTimeout(p.timer);
      if (p.playing) p.timer = setTimeout(tick, 1000 / p.anim.fps);
    });
    const step = (dir) => {
      p.playing = false; clearTimeout(p.timer); playBtn.textContent = '▶ Lecture';
      p.frame = (p.frame + dir + p.anim.frames) % p.anim.frames; draw();
    };
    controls.append(animSel, playBtn,
      el('button', { type: 'button', class: 'small', onclick: () => step(-1), 'aria-label': 'Frame précédente' }, '◀'),
      el('button', { type: 'button', class: 'small', onclick: () => step(1), 'aria-label': 'Frame suivante' }, '▶'),
      frameLbl);
    context = () => 'anim : ' + p.anim.name + (p.playing ? '' : ` (frame ${p.frame + 1})`);
    requestAnimationFrame(() => load(def));
  } else {
    const img = el('img', { src: fileUrl(a.file), alt: a.name, width: a.w, height: a.h });
    stage.append(img);
    applyZoom = () => {
      const z = state.zoom || autoZoom(stage, a.w, a.h, 8);
      img.style.width = a.w * z + 'px';
      img.style.height = a.h * z + 'px';
    };
    requestAnimationFrame(applyZoom);
  }
  zoomSel.addEventListener('change', () => { state.zoom = Number(zoomSel.value); applyZoom(); });

  const toolbar = el('div', { class: 'controls' }, bgButtons,
    a.type !== 'audio' ? zoomSel : null);

  const commentsBox = el('div', { class: 'asset-comments' });
  const renderAssetComments = () => {
    const list = state.comments.filter((c) => c.asset === a.id);
    commentsBox.replaceChildren(...(list.length ? list.map((c) => commentEl(c, false, renderAssetComments))
      : [el('p', { class: 'muted', text: 'Aucun commentaire pour l\'instant.' })]));
  };
  renderAssetComments();

  d.replaceChildren(
    el('div', { class: 'detail-head' },
      el('button', { type: 'button', class: 'small', onclick: () => { location.hash = '#/assets'; } }, '← Retour'),
      el('h2', { text: a.name }),
      el('button', { type: 'button', class: 'small', onclick: () => openCardDialog(null, a.id) }, '+ Carte liée')),
    toolbar,
    stage,
    controls,
    gallery ? el('h3', { text: 'Toutes les animations' }) : null,
    gallery,
    el('p', { class: 'meta' },
      `${a.id} · version ${a.version} · build ${state.index.commit}` +
      (a.w ? ` · ${a.w}×${a.h}` : '') + (a.note ? ' · ' + a.note : '')),
    el('h3', { text: 'Ton avis' }),
    commentForm(a, context, renderAssetComments),
    el('h3', { text: 'Historique' }),
    commentsBox,
  );
}

function commentForm(a, context, after) {
  let kind = 'amelioration';
  const text = el('textarea', { rows: 3, maxlength: 8000, placeholder: 'Ce qu\'il faudrait changer, ou pourquoi c\'est bon…', 'aria-label': 'Commentaire' });
  const kinds = ['amelioration', 'valide'].map((k) => el('button', {
    type: 'button', class: k + (k === kind ? ' on' : ''), 'data-kind': k,
    onclick: () => { kind = k; for (const b of kinds) b.classList.toggle('on', b.dataset.kind === k); },
  }, KIND_LABEL[k]));
  const send = el('button', { type: 'submit', class: 'primary' }, 'Envoyer');
  const form = el('form', { class: 'panel comment-form' }, el('div', { class: 'kind-pick' }, kinds), text,
    el('div', { class: 'row end' }, el('span', { class: 'spacer' }), send));
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    send.disabled = true;
    const ok = await guarded(async () => {
      await api('comment', { method: 'POST', body: { asset: a.id, kind, body: text.value, context: context() } });
      await reloadComments();
      return true;
    });
    send.disabled = false;
    if (ok) {
      text.value = '';
      toast('Commentaire enregistré');
      after();
    }
  });
  return form;
}

function commentEl(c, withAsset, after) {
  const asset = state.assetsById.get(c.asset);
  const head = el('div', { class: 'head' },
    el('span', { class: 'badge ' + c.kind, text: KIND_LABEL[c.kind] || c.kind }),
    el('span', { class: 'badge ' + (c.status === 'done' ? 'done' : ''), text: c.status === 'done' ? 'Traité' : 'Ouvert' }),
    c.outdated ? el('span', { class: 'badge old', text: 'version précédente' }) : null,
    withAsset ? el('a', { href: '#/assets/' + encodeURIComponent(c.asset), text: asset ? asset.name : c.asset }) : null,
    el('span', { class: 'muted', text: `#${c.id} · v ${c.version} · ${fmtDate(c.created_at)}` + (c.context ? ' · ' + c.context : '') }));
  const toggle = el('button', {
    type: 'button', class: 'small',
    onclick: async () => {
      const ok = await guarded(async () => {
        await api('comment_update', { method: 'POST', body: { id: c.id, status: c.status === 'done' ? 'open' : 'done' } });
        await reloadComments();
        return true;
      });
      if (ok) after();
    },
  }, c.status === 'done' ? 'Rouvrir' : 'Marquer traité');
  const del = el('button', {
    type: 'button', class: 'small danger',
    onclick: async () => {
      if (!confirm('Supprimer ce commentaire ?')) return;
      const ok = await guarded(async () => {
        await api('comment_delete', { method: 'POST', body: { id: c.id } });
        await reloadComments();
        return true;
      });
      if (ok) after();
    },
  }, 'Supprimer');
  return el('div', { class: 'comment' + (c.status === 'done' ? ' is-done' : ''), 'data-id': c.id },
    head,
    c.body ? el('p', { class: 'body', text: c.body }) : null,
    c.reply ? el('p', { class: 'reply', text: 'Agent : ' + c.reply }) : null,
    el('div', { class: 'actions' }, toggle, del));
}

// ========================================================== COMMENTAIRES (liste)

function initCommentsView() {
  $('only-open').addEventListener('change', renderCommentList);
}

async function renderCommentList() {
  const box = $('comment-list');
  const only = $('only-open').checked;
  const list = state.comments.filter((c) => !only || c.status === 'open');
  box.replaceChildren(...(list.length ? list.map((c) => commentEl(c, true, renderCommentList))
    : [el('p', { class: 'empty', text: 'Aucun commentaire.' })]));
}

// ================================================================== KANBAN

function initKanban() {
  $('new-card').addEventListener('click', () => openCardDialog(null, ''));
  $('cf-cancel').addEventListener('click', () => $('card-dialog').close());
  $('card-form').addEventListener('submit', saveCard);
  $('cf-delete').addEventListener('click', deleteCard);
}

function renderBoard() {
  const board = $('board');
  board.replaceChildren(...STATUSES.map(([status, label], col) => {
    const cards = state.cards.filter((c) => c.status === status);
    const column = el('div', { class: 'column', 'data-status': status },
      el('h3', {}, el('span', { text: label }), el('span', { class: 'muted', text: String(cards.length) })),
      cards.map((c) => cardEl(c, col)));
    column.addEventListener('dragover', (ev) => { ev.preventDefault(); column.classList.add('over'); });
    column.addEventListener('dragleave', () => column.classList.remove('over'));
    column.addEventListener('drop', (ev) => {
      ev.preventDefault();
      column.classList.remove('over');
      const id = Number(ev.dataTransfer.getData('text/plain'));
      if (!id) return;
      // Position d'insertion : avant la première carte dont le milieu est sous le curseur.
      const others = [...column.querySelectorAll('.card')].filter((n) => Number(n.dataset.id) !== id);
      let index = others.length;
      for (let i = 0; i < others.length; i++) {
        const r = others[i].getBoundingClientRect();
        if (ev.clientY < r.top + r.height / 2) { index = i; break; }
      }
      moveCard(id, status, index);
    });
    return column;
  }));
}

function cardEl(c, col) {
  const asset = c.asset ? state.assetsById.get(c.asset) : null;
  const move = (dir) => (ev) => {
    ev.stopPropagation();
    moveCard(c.id, STATUSES[col + dir][0]);
  };
  const card = el('div', {
    class: 'card ' + c.type, draggable: 'true', 'data-id': c.id, tabindex: '0',
    onclick: () => openCardDialog(c, ''),
    onkeydown: (ev) => { if (ev.key === 'Enter') openCardDialog(c, ''); },
  },
  el('div', { class: 'foot' },
    el('span', { class: 'badge ' + c.type, text: c.type === 'bug' ? 'Bug' : 'Feature' }),
    c.priority ? el('span', { class: 'badge ' + c.priority, text: PRIO_LABEL[c.priority] }) : null,
    el('span', { class: 'muted', text: '#' + c.id })),
  el('div', { class: 'title', text: c.title }),
  c.description ? el('div', { class: 'desc', text: c.description }) : null,
  c.asset ? el('a', {
    class: 'asset-link', href: '#/assets/' + encodeURIComponent(c.asset),
    onclick: (ev) => ev.stopPropagation(), text: '↗ ' + (asset ? asset.name : c.asset),
  }) : null,
  el('div', { class: 'foot' },
    c.notes.length ? el('span', { class: 'muted', text: `${c.notes.length} note${c.notes.length > 1 ? 's' : ''}` }) : null,
    el('span', { class: 'spacer' }),
    col > 0 ? el('button', { type: 'button', class: 'small', onclick: move(-1), 'aria-label': 'Colonne précédente', title: STATUSES[col - 1][1] }, '◀') : null,
    col < STATUSES.length - 1 ? el('button', { type: 'button', class: 'small', onclick: move(1), 'aria-label': 'Colonne suivante', title: STATUSES[col + 1][1] }, '▶') : null));
  card.addEventListener('dragstart', (ev) => {
    ev.dataTransfer.setData('text/plain', String(c.id));
    ev.dataTransfer.effectAllowed = 'move';
    card.classList.add('dragging');
  });
  card.addEventListener('dragend', () => card.classList.remove('dragging'));
  return card;
}

async function moveCard(id, status, index) {
  const body = { id, status };
  if (Number.isInteger(index)) body.index = index;
  await guarded(async () => {
    await api('card_move', { method: 'POST', body });
    await reloadCards();
  });
  renderBoard();
}

function openCardDialog(card, assetId) {
  state.editing = card;
  $('card-dialog-title').textContent = card ? `Carte #${card.id} · ${STATUS_LABEL[card.status]}` : 'Nouvelle carte';
  $('cf-type').value = card ? card.type : 'feature';
  $('cf-priority').value = card ? card.priority : '';
  $('cf-title').value = card ? card.title : '';
  $('cf-desc').value = card ? card.description : '';
  $('cf-asset').value = card ? card.asset : assetId;
  $('cf-note').value = '';
  $('card-error').textContent = '';
  $('cf-delete').hidden = !card;
  $('cf-note-label').hidden = !card;
  $('cf-notes').replaceChildren(...(card ? card.notes.map((n) => el('div', { class: 'note ' + n.author },
    el('strong', { text: (n.author === 'agent' ? 'Agent' : 'Julien') + ' · ' + fmtDate(n.created_at) }),
    el('br'), n.body)) : []));
  $('card-dialog').showModal();
}

async function saveCard(ev) {
  ev.preventDefault();
  const card = state.editing;
  const body = {
    type: $('cf-type').value, priority: $('cf-priority').value, title: $('cf-title').value,
    description: $('cf-desc').value, asset: $('cf-asset').value.trim(),
  };
  try {
    if (card) {
      await api('card_update', { method: 'POST', body: { id: card.id, ...body } });
      const note = $('cf-note').value.trim();
      if (note) await api('card_note', { method: 'POST', body: { id: card.id, body: note } });
    } else {
      await api('card', { method: 'POST', body });
    }
    await reloadCards();
  } catch (e) {
    $('card-error').textContent = e.message;
    return;
  }
  $('card-dialog').close();
  toast(card ? 'Carte mise à jour' : 'Carte créée');
  if (location.hash.startsWith('#/kanban')) renderBoard();
}

async function deleteCard() {
  const card = state.editing;
  if (!card || !confirm(`Supprimer la carte #${card.id} ?`)) return;
  const ok = await guarded(async () => {
    await api('card_delete', { method: 'POST', body: { id: card.id } });
    await reloadCards();
    return true;
  });
  if (ok) {
    $('card-dialog').close();
    renderBoard();
  }
}

document.addEventListener('DOMContentLoaded', boot);
