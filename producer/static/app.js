// Miarritze Producer — interface (JS vanilla, aucune dépendance).
// Sécurité : tout contenu venant de l'API est inséré via textContent / attributs,
// jamais via innerHTML.
'use strict';

// QA = le jeu local de QA ; Validé = part en prod au prochain déploiement groupé ; En prod (done) = en ligne.
const STATUSES = [
  ['backlog', 'Backlog'], ['todo', 'Todo'], ['doing', 'Doing'], ['qa', 'QA'], ['valide', 'Validé'], ['done', 'En prod'],
];
// Onglets du kanban sur iPhone : libellés courts (6 colonnes sur 390 px).
const STATUS_SHORT = { done: 'Prod' };
// Travail fini (plus d'échéance dépassée, plus proposé pour un commentaire) ; « avancé » pour les barres.
const FINISHED = new Set(['valide', 'done']);
const ADVANCED = new Set(['qa', 'valide', 'done']);
// Tâches pixelforge (cards.jobs) : en cours, en échec.
const JOB_RUNNING = new Set(['pending', 'queued', 'running']);
const JOB_FAILED = new Set(['failed', 'error']);
const TYPE_LABEL = {
  feature: 'Feature', bug: 'Bug', perso: 'Perso', animation: 'Animation', asset: 'Asset',
  gameplay: 'Gameplay', pixelforge: 'Pixelforge',
};
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
  hat: 0,            // filtre « par chapeau » du kanban (0 = tous)
  hatsOnly: false,   // kanban : enfants masqués (vue chapeaux seulement)
  nightOnly: false,  // kanban : cartes night shift seulement
  noHats: false,     // kanban : chapeaux masqués (inverse de hatsOnly, exclusifs)
  indexV: '',        // version de l'index des assets (sondée par le board)
  fresh: new Map(),  // asset -> instant où une nouvelle version est arrivée
  expanded: new Set(),  // chapeaux dépliés sur le board
  decorMode: store('producer-decor-mode') || 'masques',   // image | masques | controle
  decorSansMasque: false,  // filtre « sans masque » du décor
  fs: null,          // lecteur plein écran ouvert
  milestones: [],    // jalons de la roadmap
  kb: { q: '', type: '', perso: '', map: '', ms: '' },   // filtres du kanban (retenus)
  selecting: false,  // kanban : mode sélection (actions groupées)
  selected: new Set(),
};

// ------------------------------------------------------------------ utilitaires

// Zoom entier le plus grand qui tient en largeur ET en hauteur (≈ 55 % de
// l'écran) : les commandes et les commentaires restent visibles sur mobile.
// Un asset plus grand que la scène (HD de Blackout) est réduit, sans arrondi.
function autoZoom(stage, w, h, max) {
  const fitW = (Math.min(stage.clientWidth, 900) - 24) / w;
  // Fiche sur téléphone : visionneuse plus basse, le pilotage reste à portée de pouce.
  const part = stage.closest('.fiche') && window.innerWidth < 900 ? 0.36 : 0.55;
  const fitH = Math.max(160, window.innerHeight * part) / h;
  const fit = Math.min(fitW, fitH);
  return fit < 1 ? Math.max(0.1, fit) : Math.min(max, Math.floor(fit));
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

/** URL d'un fichier servi, avec l'empreinte de son contenu (&v) : une planche réécrite
 *  sous le même nom change d'URL, le navigateur ne ressert pas l'ancienne. */
function fileUrl(p) {
  const v = state.index && state.index.versions ? state.index.versions[p] : '';
  return 'index.php?r=file&p=' + encodeURIComponent(p) + (v ? '&v=' + v : '');
}

/**
 * Case d'une planche d'après l'image réellement chargée : largeur = largeur de la planche /
 * nombre d'images. Si l'index ne correspond plus à la planche (rebuild pendant que la page était
 * ouverte), on suit la planche (lecture case par case, jamais de glissement) et on recharge l'index.
 */
function sheetCell(anim, img) {
  const w = img.naturalWidth / anim.frames;
  const h = img.naturalHeight;
  if (Math.abs(w - anim.w) > 0.01 || h !== anim.h) {
    console.warn(`planche ${anim.file} : ${img.naturalWidth}×${h} pour ${anim.frames} cases de ${anim.w}×${anim.h} (index périmé)`);
    refreshIndexSoon();
    return { w: Math.floor(w), h };
  }
  return { w: anim.w, h: anim.h };
}

let indexRefreshing = null;
function refreshIndexSoon() {
  if (indexRefreshing) return;
  indexRefreshing = api('index').then((index) => {
    state.index = index;
    state.assetsById = new Map(index.assets.map((a) => [a.id, a]));
  }).catch(() => {}).finally(() => { indexRefreshing = null; });
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
  initCatalogue();
  initJeu();
  window.addEventListener('hashchange', route);
  const s = await guarded(() => api('session'));
  if (!s) return;
  state.csrf = s.csrf;
  state.authMode = s.mode || 'password';
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
  // Connecté par Tailscale : pas de déconnexion possible (la session revient à la requête suivante).
  $('logout').hidden = state.authMode === 'tailscale';
  const [index, iv] = await Promise.all([api('index'), api('index_version'), reloadComments(), reloadCards(),
    reloadMilestones(), reloadStudio()]);
  state.indexV = iv.v;
  state.index = index;
  state.assetsById = new Map(index.assets.map((a) => [a.id, a]));
  const dl = $('asset-ids');
  dl.replaceChildren(...index.assets.map((a) => el('option', { value: a.id })));
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

/** État du studio (build du jeu de QA, déploiement) écrit par le watcher ; {} s'il n'y en a pas. */
async function reloadStudio() {
  const r = await api('studio').catch(() => null);
  state.studio = r && typeof r === 'object' ? r : {};
}

// ---------------------------------------------------------------- routage

const TABS = ['bord', 'kanban', 'assets', 'jeu', 'roadmap', 'comments', 'aide'];

function route() {
  if (!state.index) return;
  const hash = location.hash || '#/bord';
  const [, tab, ...rest] = hash.split('/');
  const current = TABS.includes(tab) ? tab : 'bord';
  for (const a of document.querySelectorAll('#tabs a')) {
    a.classList.toggle('active', a.dataset.tab === current);
  }
  for (const v of document.querySelectorAll('.view')) v.hidden = v.id !== 'view-' + current;
  stopPlayer();
  if (state.fs) closePlayer(false);
  renderNavBadges();
  if (current === 'assets') {
    // #/assets/<id encodé>[/<détail encodé>] : fiche d'un élément (asset, animation d'un perso…).
    const parts = rest.map((x) => { try { return decodeURIComponent(x); } catch (e) { return x; } });
    if (parts[0]) showFiche(parts[0], parts[1] || '');
    else renderCatalogue();
  } else if (current === 'kanban') {
    renderBoard();
  } else if (current === 'jeu') {
    renderJeu(rest[0] || '');
  } else if (current === 'roadmap') {
    renderRoadmap();
  } else if (current === 'bord') {
    renderBord();
  } else if (current === 'aide') {
    renderAide();
  } else {
    renderCommentList();
  }
}

/** Pastilles de la navigation : cartes à valider (QA), commentaires d'asset ouverts. */
function renderNavBadges() {
  const qa = state.cards.filter((c) => c.status === 'qa' && !c.children).length;
  const open = state.comments.filter((c) => c.status === 'open').length;
  $('nav-qa').textContent = qa ? String(qa) : '';
  $('nav-qa').title = qa ? `${qa} carte(s) à valider` : '';
  $('nav-comments').textContent = open ? String(open) : '';
}

// ================================================================== ASSETS

function initAssetsView() {
  applyStageBg();
}

function applyStageBg() {
  document.body.classList.toggle('stage-dark', state.stageBg === 'dark');
}

function openCount(assetId) {
  return state.comments.filter((c) => c.asset === assetId && c.status === 'open').length;
}

// Catégories rangées par famille, une section par perso.
const BY_KIND = ['Persos'];

// Visage d'un perso pour l'en-tête de sa section.
function faceOf(cat, group) {
  if (cat !== 'Persos') return null;
  const mine = state.index.assets.filter((x) => x.cat === cat && x.group === group);
  return mine.find((x) => x.kind === 'modele') || mine.find((x) => x.kind === 'anim') || mine.find((x) => x.kind === 'candidat');
}

// Familles d'assets d'un combattant, dans l'ordre de la review.
// Blackout donne la famille dans l'index (a.kind).
const KINDS = [
  ['anim', 'Animations'], ['masque', 'Masques'], ['modele', 'Profil validé'], ['candidat', 'Profils candidats'],
  ['portrait', 'Portraits'], ['ending', 'Image de fin'],
  ['proj', 'Projectiles'], ['fx', 'Effets des spéciaux'], ['palette', 'Palettes'], ['src', 'Sources'],
];

function kindOf(a) {
  if (a.kind && KINDS.some(([k]) => k === a.kind)) return a.kind;
  const n = a.id.split('/').pop();
  if (a.type === 'sprite') return 'anim';
  if (a.id.startsWith('vfx/')) return n.startsWith('proj_') ? 'proj' : 'fx';
  if (n.startsWith('portrait')) return 'portrait';
  if (n.startsWith('ending')) return 'ending';
  if (n.startsWith('palettes')) return 'palette';
  return 'src';
}

function kindBlocks(items) {
  return KINDS.flatMap(([k, label]) => {
    const sub = items.filter((a) => kindOf(a) === k);
    return sub.length ? [el('h4', { class: 'kind', text: label }), el('div', { class: 'group-tiles' }, sub.map(tile))] : [];
  });
}

// ============================================================ BLACKOUT : PERSOS

// Clé d'un character set : id du perso (« louis »), ou famille/id hors persos (« pnj/amona »,
// « fantome/fantome », « boss/basajaun »). Id de son asset « animations ».
function bkAssetId(pid) {
  return pid.includes('/') ? `blackout/${pid}/animations` : `blackout/persos/${pid}/animations`;
}

/** Clé du set d'un asset « animations » ou « masques » de Blackout, sinon null. */
function bkKeyOf(assetId) {
  const m = /^blackout\/([^/]+)\/([^/]+)\/(animations|masques)$/.exec(assetId || '');
  if (!m) return null;
  return m[1] === 'persos' ? m[2] : `${m[1]}/${m[2]}`;
}

// Animations d'un perso (asset « animations ») et masques de tenue.
function bkAnims(pid) {
  const a = state.assetsById.get(bkAssetId(pid));
  return a ? a.anims : [];
}

// Liste ordonnée des animations du perso : attendues (présentes ou manquantes),
// puis celles qui existent sans être attendues. Hors persos : les éléments présents.
function bkSlots(pid) {
  const have = new Map(bkAnims(pid).map((x) => [x.name, x]));
  const exp = pid.includes('/') ? [] : state.index.blackout.anims;
  const slots = exp.map((e) => ({ ...e, anim: have.get(e.name) || null }));
  for (const [n, x] of have) if (!exp.some((e) => e.name === n)) slots.push({ name: n, loop: x.loop, a_venir: false, anim: x });
  return slots;
}

// Récapitulatif global perso × animation.
function recapTable(persos) {
  const exp = state.index.blackout.anims;
  const head = el('tr', {}, el('th', { class: 'corner', text: 'Perso' }),
    exp.map((e) => el('th', { class: 'v' + (e.a_venir ? ' a-venir' : ''), title: e.a_venir ? 'à venir (clip sur mesure)' : '' }, el('span', { text: e.name }))),
    el('th', { class: 'v' }, el('span', { text: 'total' })));
  const rows = persos.map((pid) => {
    const have = new Set(bkAnims(pid).map((x) => x.name));
    const n = exp.filter((e) => have.has(e.name)).length;
    return el('tr', { 'data-perso': pid },
      el('th', {}, el('button', {
        type: 'button', class: 'link',
        onclick: () => { const s = $('perso-' + pid); if (s) s.scrollIntoView({ behavior: 'smooth' }); },
      }, pid)),
      exp.map((e) => (have.has(e.name)
        ? el('td', { class: 'yes' }, el('button', { type: 'button', title: `${pid} · ${e.name}`, 'aria-label': `${pid} ${e.name}`, onclick: () => openPlayer(pid, e.name) }, '✓'))
        : el('td', { class: 'no', title: `${pid} · ${e.name} : manquante` }, '·'))),
      el('td', { class: 'total', text: `${n}/${exp.length}` }));
  });
  return el('section', { class: 'group recap' },
    el('h4', { class: 'kind', text: 'Récapitulatif des animations' }),
    el('div', { class: 'recap-scroll' }, el('table', { class: 'recap-table' }, el('thead', {}, head), el('tbody', {}, rows))),
    el('p', { class: 'muted small-note', text: '✓ présente (toucher pour la lire en plein écran) · « · » manquante · en italique : clips sur mesure à venir.' }));
}

// ------------------------------------------------- lecteur plein écran

const FS_BGS = [['light', 'Clair'], ['dark', 'Sombre'], ['checker', 'Damier']];

function openPlayer(pid, name) {
  closePlayer(false);
  const g = state.index.blackout;
  const persos = [...g.persos, ...(g.autres || [])].filter((p) => bkAnims(p).length);
  const fs = { pid, anims: [], anim: null, img: null, mask: null, frame: 0, playing: true, timer: 0,
    showMask: false, showFeet: false, bg: store('producer-fs-bg') || state.stageBg || 'checker' };
  state.fs = fs;
  const canvas = el('canvas', { class: 'fs-canvas' });
  const ctx = canvas.getContext('2d');
  const title = el('span', { class: 'fs-title' });
  const info = el('span', { class: 'fs-info' });
  const playBtn = el('button', { type: 'button', 'aria-label': 'Lecture ou pause' }, '⏸');
  const maskBtn = el('button', { type: 'button', title: 'Masque de tenue par-dessus' }, 'Masque');
  const feetBtn = el('button', { type: 'button', title: 'Ligne des pieds (feet_anchor)' }, 'Pieds');
  // « Comme en jeu » : recalage par image (frame_offsets), décalage et échelle de la planche,
  // appliqués comme bk_perso.gd ; sinon la planche brute, case par case.
  fs.jeu = store('producer-fs-jeu') !== '0';
  const jeuBtn = el('button', { type: 'button', class: fs.jeu ? 'on' : null,
    title: 'Comme en jeu : recalage par image (frame_offsets), décalage et échelle appliqués ; sinon planche brute' }, 'Comme en jeu');
  const bgBtn = el('button', { type: 'button', title: 'Fond' });
  const stage = el('div', { class: 'fs-stage' }, canvas);
  const root = el('div', { class: 'fs bg-' + fs.bg, role: 'dialog', 'aria-label': 'Lecteur plein écran' },
    el('div', { class: 'fs-bar top' },
      el('button', { type: 'button', class: 'fs-close', 'aria-label': 'Fermer', onclick: () => closePlayer(true) }, '✕'),
      title, el('span', { class: 'spacer' }), info),
    stage,
    el('div', { class: 'fs-bar bottom' },
      el('button', { type: 'button', 'aria-label': 'Animation précédente', title: 'Animation précédente (←, glisser à droite)', onclick: () => go(-1) }, '‹ anim'),
      el('button', { type: 'button', 'aria-label': 'Image précédente', title: 'Image précédente (,)', onclick: () => step(-1) }, '◀'),
      playBtn,
      el('button', { type: 'button', 'aria-label': 'Image suivante', title: 'Image suivante (.)', onclick: () => step(1) }, '▶'),
      el('button', { type: 'button', 'aria-label': 'Animation suivante', title: 'Animation suivante (→, glisser à gauche)', onclick: () => go(1) }, 'anim ›'),
      bgBtn, maskBtn, feetBtn, jeuBtn,
      document.fullscreenEnabled ? el('button', { type: 'button', title: 'Plein écran du navigateur', onclick: toggleRealFs }, '⛶') : null));
  fs.root = root;

  const setBg = (v) => {
    fs.bg = v; store('producer-fs-bg', v);
    root.className = 'fs bg-' + v;
    bgBtn.textContent = 'Fond : ' + FS_BGS.find(([k]) => k === v)[1];
  };
  bgBtn.addEventListener('click', () => {
    const i = FS_BGS.findIndex(([k]) => k === fs.bg);
    setBg(FS_BGS[(i + 1) % FS_BGS.length][0]);
  });
  setBg(fs.bg);

  const draw = () => {
    const a = fs.anim;
    const L = fs.layout;
    if (!a || !fs.img || !L) return;
    const { w, h } = L.cell;
    const [ox, oy] = L.off(fs.frame);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.save();
    // Pieds de la case sur l'ancre (comme le jeu) ; la source est toujours une case entière.
    ctx.translate(L.ax, L.ay);
    ctx.scale(L.e, L.e);
    ctx.translate(-L.feet[0] + ox, -L.feet[1] + oy);
    ctx.drawImage(fs.img, fs.frame * w, 0, w, h, 0, 0, w, h);
    if (fs.showMask && fs.mask) {
      ctx.globalAlpha = 0.6;
      ctx.drawImage(fs.mask, fs.frame * w, 0, w, h, 0, 0, w, h);
      ctx.globalAlpha = 1;
    }
    ctx.restore();
    if (fs.showFeet && a.feet) {
      ctx.strokeStyle = '#ce3434'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(0, Math.round(L.ay) + 0.5); ctx.lineTo(canvas.width, Math.round(L.ay) + 0.5);
      ctx.moveTo(Math.round(L.ax) + 0.5, L.ay - 6); ctx.lineTo(Math.round(L.ax) + 0.5, L.ay + 6); ctx.stroke();
    }
    const i = fs.anims.indexOf(a);
    const g = glisseOf(a, fs.jeu);
    info.textContent = `image ${fs.frame + 1}/${a.frames} · ${a.fps} i/s` + (a.loop ? ' · boucle' : '') +
      ` · ${i + 1}/${fs.anims.length}` + (g >= 6 ? ` · ⚠ glisse de ${g} px dans la planche` : '');
  };
  const schedule = () => {
    clearTimeout(fs.timer);
    if (!fs.playing || !fs.img) return;
    const a = fs.anim;
    // Une animation sans boucle marque une pause sur sa dernière image.
    const last = fs.frame === a.frames - 1;
    fs.timer = setTimeout(() => {
      if (state.fs !== fs) return;
      fs.frame = (fs.frame + 1) % a.frames; draw(); schedule();
    }, 1000 / a.fps + (last && !a.loop ? 600 : 0));
  };
  const setPlaying = (on) => { fs.playing = on; playBtn.textContent = on ? '⏸' : '▶︎ Lire'; schedule(); };
  playBtn.addEventListener('click', () => setPlaying(!fs.playing));
  const step = (d) => { setPlaying(false); fs.frame = (fs.frame + d + fs.anim.frames) % fs.anim.frames; draw(); };
  jeuBtn.addEventListener('click', () => {
    fs.jeu = !fs.jeu; store('producer-fs-jeu', fs.jeu ? '1' : '0');
    jeuBtn.classList.toggle('on', fs.jeu);
    if (fs.img) { fs.layout = gameLayout(fs.anim, fs.layout.cell, fs.jeu); canvas.width = fs.layout.W; canvas.height = fs.layout.H; draw(); }
  });
  maskBtn.addEventListener('click', () => { fs.showMask = !fs.showMask; maskBtn.classList.toggle('on', fs.showMask); draw(); });
  feetBtn.addEventListener('click', () => { fs.showFeet = !fs.showFeet; feetBtn.classList.toggle('on', fs.showFeet); draw(); });

  const load = (p, n) => {
    fs.pid = p;
    fs.anims = bkAnims(p);
    const masks = (state.assetsById.get(`blackout/persos/${p}/masques`) || { anims: [] }).anims;
    const a = fs.anims.find((x) => x.name === n) || fs.anims[0];
    if (!a) return;
    const m = masks.find((x) => x.name === a.name);
    fs.anim = a; fs.frame = 0; fs.img = null; fs.mask = null; fs.layout = null;
    clearTimeout(fs.timer);
    canvas.width = a.w; canvas.height = a.h;
    // Pixel art 32 px (cases de 64 à 128) : agrandi net ; l'ancienne HD reste lissée.
    canvas.classList.toggle('px', a.w <= 128);
    title.textContent = `${persoName(p)} · ${a.libelle ? `${a.libelle} (${a.name})` : a.name}`;
    maskBtn.disabled = !m;
    feetBtn.disabled = !a.feet;
    info.textContent = 'chargement…';
    const img = new Image();
    img.onload = () => {
      if (fs.anim !== a) return;
      fs.layout = gameLayout(a, sheetCell(a, img), fs.jeu);
      canvas.width = fs.layout.W; canvas.height = fs.layout.H;
      fs.img = img; draw(); schedule();
    };
    img.src = fileUrl(a.file);
    if (m) {
      const mi = new Image();
      // Masque teinté en magenta : visible quel que soit le gris du masque et la couleur de la tenue.
      mi.onload = () => {
        if (fs.anim !== a) return;
        const t = el('canvas', { width: mi.width, height: mi.height });
        const tc = t.getContext('2d');
        tc.drawImage(mi, 0, 0);
        tc.globalCompositeOperation = 'source-in';
        tc.fillStyle = '#e0219b';
        tc.fillRect(0, 0, t.width, t.height);
        fs.mask = t; draw();
      };
      mi.src = fileUrl(m.file);
    }
  };
  // Nouvelle version publiée : on recharge l'animation affichée, mêmes réglages.
  fs.reload = () => { if (state.fs === fs && fs.anim) load(fs.pid, fs.anim.name); };
  const go = (d) => {
    const i = fs.anims.indexOf(fs.anim);
    load(fs.pid, fs.anims[(i + d + fs.anims.length) % fs.anims.length].name);
  };
  const goPerso = (d) => {
    const i = persos.indexOf(fs.pid);
    if (i < 0 || persos.length < 2) return;
    load(persos[(i + d + persos.length) % persos.length], fs.anim.name);
  };
  fs.onKey = (ev) => {
    if (ev.target && /^(INPUT|TEXTAREA|SELECT)$/.test(ev.target.tagName)) return;
    const k = ev.key;
    if (k === 'Escape' && !document.fullscreenElement) closePlayer(true);
    else if (k === 'ArrowLeft') go(-1);
    else if (k === 'ArrowRight') go(1);
    else if (k === 'ArrowUp') goPerso(-1);
    else if (k === 'ArrowDown') goPerso(1);
    else if (k === ',' || k === '<') step(-1);
    else if (k === '.' || k === '>') step(1);
    else if (k === ' ') setPlaying(!fs.playing);
    else return;
    ev.preventDefault();
  };
  document.addEventListener('keydown', fs.onKey);
  // Glisser : gauche/droite = animation suivante/précédente, haut/bas = perso ; toucher = pause.
  let t0 = null;
  stage.addEventListener('touchstart', (ev) => { const t = ev.changedTouches[0]; t0 = { x: t.clientX, y: t.clientY }; }, { passive: true });
  stage.addEventListener('touchend', (ev) => {
    if (!t0) return;
    const t = ev.changedTouches[0];
    const dx = t.clientX - t0.x, dy = t.clientY - t0.y;
    t0 = null;
    if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) go(dx < 0 ? 1 : -1);
    else if (Math.abs(dy) > 60) goPerso(dy < 0 ? 1 : -1);
    else if (Math.abs(dx) < 10 && Math.abs(dy) < 10) setPlaying(!fs.playing);
    ev.preventDefault();
  });
  stage.addEventListener('click', () => setPlaying(!fs.playing));

  document.body.append(root);
  document.body.classList.add('fs-open');
  history.pushState({ fs: true }, '');
  fs.pushed = true;
  load(pid, name);
}

/**
 * Mise en place d'une planche dans le lecteur plein écran. `jeu` : comme bk_perso.gd, chaque case
 * est posée pieds sur l'ancre, décalée de frame_offsets[f] + decalage et mise à l'échelle `echelle`
 * autour des pieds ; le canvas englobe toutes les images. Sinon : la case brute.
 */
function gameLayout(a, cell, jeu) {
  const feet = a.feet || [cell.w / 2, cell.h];
  const offs = jeu && a.offs ? a.offs : [];
  const dec = jeu && a.dec ? a.dec : [0, 0];
  const e = jeu && a.echelle ? a.echelle : 1;
  const off = (f) => [(offs[f] ? offs[f][0] : 0) + dec[0], (offs[f] ? offs[f][1] : 0) + dec[1]];
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (let f = 0; f < a.frames; f++) {
    const [ox, oy] = off(f);
    x0 = Math.min(x0, (-feet[0] + ox) * e); x1 = Math.max(x1, (cell.w - feet[0] + ox) * e);
    y0 = Math.min(y0, (-feet[1] + oy) * e); y1 = Math.max(y1, (cell.h - feet[1] + oy) * e);
  }
  return { cell, feet, e, off, ax: -x0, ay: -y0, W: Math.ceil(x1 - x0), H: Math.ceil(y1 - y0) };
}

function toggleRealFs() {
  const fs = state.fs;
  if (!fs) return;
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  else if (fs.root.requestFullscreen) fs.root.requestFullscreen().catch(() => {});
}

// back = true : fermé par l'interface (on retire l'entrée d'historique ajoutée).
function closePlayer(back) {
  const fs = state.fs;
  if (!fs) return;
  state.fs = null;
  clearTimeout(fs.timer);
  document.removeEventListener('keydown', fs.onKey);
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  fs.root.remove();
  document.body.classList.remove('fs-open');
  if (back && fs.pushed) history.back();
}

window.addEventListener('popstate', () => { if (state.fs) { state.fs.pushed = false; closePlayer(false); } });

// ============================================================ BLACKOUT : DÉCOR

const DECOR_MODES = [['image', 'Sans masques'], ['masques', 'Avec masques'], ['controle', 'Contrôle du jeu']];
const SOURCE_LABEL = { pixelforge: 'pixelforge', repli: 'repli local', aucun: 'sans masque' };

function decorBadges(d) {
  return el('span', { class: 'dbadges' },
    el('span', { class: 'badge src-' + d.source, text: SOURCE_LABEL[d.source] || d.source }),
    d.confidence !== null && d.confidence !== undefined ? el('span', { class: 'badge' + (d.confidence < 0.8 ? ' warn' : ''), text: 'confiance ' + d.confidence }) : null,
    d.blocks_view ? el('span', { class: 'badge', text: 'bloque la vue' }) : null,
    d.warnings && d.warnings.length ? el('span', { class: 'badge warn', title: d.warnings.join('\n'), text: '⚠ ' + d.warnings.length }) : null);
}

// Image d'un objet du décor, seule ou avec son calque de masques (même taille,
// superposé pixel pour pixel), ou l'image de contrôle du jeu.
function decorView(a, mode) {
  const d = a.decor;
  if (mode === 'controle' && d.controle) {
    return el('div', { class: 'dview', 'data-mode': 'controle' },
      el('img', { src: fileUrl(d.controle.file), alt: a.name + ' · contrôle du jeu', loading: 'lazy', width: d.controle.w, height: d.controle.h }));
  }
  const withMask = mode !== 'image' && d.calque;
  const layers = el('div', { class: 'dlayers' },
    el('img', { src: fileUrl(a.file), alt: a.name, loading: 'lazy', width: a.w, height: a.h }),
    withMask ? el('img', { class: 'calque', src: fileUrl(d.calque), alt: '', loading: 'lazy', width: a.w, height: a.h }) : null);
  return el('div', { class: 'dview', 'data-mode': withMask ? 'masques' : 'image' }, layers);
}

function decorLegend() {
  return el('p', { class: 'legend' },
    el('span', { class: 'sw occ' }), ' cache le perso (occluder) ',
    el('span', { class: 'sw foot' }), ' emprise au sol, bloque (footprint) ',
    el('span', { class: 'sw gc' }), ' contact au sol');
}

function decorCard(a) {
  const d = a.decor;
  let mode = state.decorMode === 'controle' && !d.controle ? 'masques' : state.decorMode;
  const box = el('div', { class: 'dbox' }, decorView(a, mode));
  const toggle = el('button', {
    type: 'button', class: 'small' + (mode !== 'image' ? ' on' : ''), disabled: !d.calque && !d.controle,
    title: 'Avec ou sans masques',
    onclick: (ev) => {
      ev.stopPropagation();
      mode = mode === 'image' ? 'masques' : 'image';
      toggle.classList.toggle('on', mode !== 'image');
      toggle.textContent = mode === 'image' ? 'Masques : non' : 'Masques : oui';
      box.replaceChildren(decorView(a, mode));
    },
  }, mode === 'image' ? 'Masques : non' : 'Masques : oui');
  const n = openCount(a.id);
  return el('div', { class: 'dcard' + (d.sans_masque ? ' sans' : ''), 'data-id': a.id },
    el('button', { type: 'button', class: 'dopen', onclick: () => { location.hash = '#/assets/' + encodeURIComponent(a.id); } }, box),
    el('div', { class: 'dcap' },
      el('span', { class: 'dname', text: a.name }),
      el('span', { class: 'muted did', text: a.id.split('/').pop().replace(/\.png$/, '') + ' · ' + d.categorie + ` · ${a.w}×${a.h}` }),
      decorBadges(d),
      el('span', { class: 'row' }, toggle,
        n ? el('span', { class: 'badge amelioration', text: n + ' ouvert' + (n > 1 ? 's' : '') }) : null)));
}

function solTile(a) {
  const t = el('div', { class: 'soltile' });
  t.style.backgroundImage = `url("${fileUrl(a.file)}")`;
  return t;
}

function solCard(a) {
  return el('button', {
    type: 'button', class: 'dcard sol', 'data-id': a.id,
    onclick: () => { location.hash = '#/assets/' + encodeURIComponent(a.id); },
  }, solTile(a),
  el('span', { class: 'dname', text: a.name }),
  el('span', { class: 'muted did', text: a.id.split('/').pop().replace(/\.png$/, '') + ' · répété 2×2' }),
  el('span', { class: 'muted did', text: 'tuile de sol : pas de masque (collision par case)' }));
}

function tile(a) {
  const n = openCount(a.id);
  const idle = a.type === 'sprite' && (a.anims.find((x) => x.name === 'idle') || a.anims[0]);
  const cls = 'thumb' + (a.smooth ? ' smooth' : '');
  const thumb = a.type === 'audio'
    ? el('div', { class: 'thumb audio', text: '♪' })
    : a.type === 'data'
      ? el('div', { class: 'thumb audio', text: '{ }' })
      : idle
        ? el('div', { class: cls }, miniAnim(idle, 0))
        : el('div', { class: cls }, el('img', { src: fileUrl(a.preview), alt: '', loading: 'lazy' }));
  const btn = el('button', {
    type: 'button', class: 'tile', 'data-id': a.id,
    onclick: () => { location.hash = '#/assets/' + encodeURIComponent(a.id); },
  }, thumb, el('span', { class: 'name', text: a.name }),
  n ? el('span', { class: 'count' }, el('span', { class: 'badge amelioration', text: n + ' ouvert' + (n > 1 ? 's' : '') })) : null);
  const mini = idle ? thumb.querySelector('img.mini') : null;
  return mini ? hoverMini(btn, mini) : btn;
}

function stopPlayer() {
  if (state.player) {
    clearTimeout(state.player.timer);
    state.player = null;
  }
}

// Mini-animations (vignettes des persos, galerie des animations, tuiles) :
// au repos, une image fixe (case du milieu, `anim.poster`, chargée paresseusement).
// La planche n'est chargée et animée qu'au survol de la souris, ou au premier
// toucher sur écran tactile (le toucher suivant ouvre l'animation) ; quand la
// souris sort, le minuteur est coupé et le canvas et la planche sont libérés.
// Une seule vignette tourne à la fois.
let activeMini = null;

function miniAnim(anim, box) {
  const poster = el('img', {
    class: 'mini', alt: '', loading: 'lazy', decoding: 'async', draggable: 'false',
    width: anim.w, height: anim.h, src: anim.poster ? fileUrl(anim.poster) : null,
  });
  // Taille d'affichage : zoom entier qui tient dans la case (pixels nets) ;
  // sans case, c'est la feuille de style qui ajuste (vignettes de la grille).
  if (box) {
    const fit = Math.min(box / anim.w, box / anim.h);
    const z = fit < 1 ? fit : Math.floor(fit);
    poster.style.width = anim.w * z + 'px';
    poster.style.height = anim.h * z + 'px';
  }
  poster.mini = { anim, poster, canvas: null, img: null, timer: 0, frame: 0 };
  return poster;
}

function startMini(m) {
  if (m.canvas) return;
  if (activeMini && activeMini !== m) stopMini(activeMini);
  activeMini = m;
  const a = m.anim;
  const canvas = el('canvas', { class: m.poster.className, width: a.w, height: a.h });
  canvas.style.cssText = m.poster.style.cssText;
  m.canvas = canvas;
  m.frame = Math.floor(a.frames / 2);   // repart de l'image fixe affichée
  const img = new Image();
  m.img = img;
  img.onload = () => {
    if (m.img !== img) return;
    const cell = sheetCell(a, img);
    canvas.width = cell.w; canvas.height = cell.h;
    m.poster.replaceWith(canvas);
    const ctx = canvas.getContext('2d');
    const tick = () => {
      if (m.img !== img) return;
      if (!canvas.isConnected) { stopMini(m); return; }
      ctx.clearRect(0, 0, cell.w, cell.h);
      ctx.drawImage(img, m.frame * cell.w, 0, cell.w, cell.h, 0, 0, cell.w, cell.h);
      const last = m.frame === a.frames - 1;
      m.frame = (m.frame + 1) % a.frames;
      // Comme le lecteur : une animation sans boucle marque une pause avant de recommencer.
      m.timer = setTimeout(tick, 1000 / a.fps + (last && !a.loop ? 500 : 0));
    };
    tick();
  };
  img.src = fileUrl(a.file);
}

function stopMini(m) {
  clearTimeout(m.timer);
  m.timer = 0;
  if (m.img) { m.img.onload = null; m.img.src = ''; m.img = null; }
  if (m.canvas) {
    if (m.canvas.isConnected) m.canvas.replaceWith(m.poster);
    m.canvas.width = 0; m.canvas.height = 0;   // libère la mémoire du canvas
    m.canvas = null;
  }
  if (activeMini === m) activeMini = null;
}

/**
 * Anime `mini` (rendu par miniAnim) au survol de `host`. Sur tactile, le premier
 * toucher anime (le clic est absorbé), le suivant fait l'action de `host`.
 * Le défilement n'est pas gêné : on n'écoute que le clic, jamais touchmove.
 */
/**
 * Le perso se déplace-t-il DANS la planche (mesuré au build sur la tête, brut et comme en jeu) ?
 * Un « défilement » visible vient alors de la planche elle-même, pas du lecteur.
 */
function glisseOf(anim, jeu) {
  return anim && anim.glisse ? anim.glisse[jeu ? 1 : 0] : 0;
}

function glisseNote(anim, jeu = true) {
  const g = glisseOf(anim, jeu);
  return g >= 6 ? el('span', {
    class: 'glisse', title: `Dans la planche elle-même, le perso se déplace de ${g} px d'une image à l'autre`
      + (jeu ? ' (raccord du jeu compris : frame_offsets, decalage)' : '') + ' : ce n\'est pas le lecteur.',
    text: `⚠ glisse de ${g} px dans la planche`,
  }) : null;
}

/** Remplit `host` avec parts(mini) et branche l'animation au survol. */
function hoverAnimCell(anim, box, host, parts) {
  const mini = miniAnim(anim, box);
  host.append(...parts(mini));
  return hoverMini(host, mini);
}

function hoverMini(host, mini, tapHost = host) {
  const m = mini.mini;
  let touch = false;
  host.addEventListener('pointerenter', (ev) => { if (ev.pointerType === 'mouse') startMini(m); });
  host.addEventListener('pointerleave', (ev) => { if (ev.pointerType === 'mouse') stopMini(m); });
  tapHost.addEventListener('pointerdown', (ev) => { touch = ev.pointerType !== 'mouse'; });
  tapHost.addEventListener('click', (ev) => {
    if (touch && !m.canvas) {
      touch = false;
      ev.preventDefault();
      ev.stopImmediatePropagation();
      startMini(m);
    }
  }, { capture: true });
  return host;
}

/**
 * Fiche d'un asset : visionneuse (planche, image, décor avec masques, audio, données, gameplay)
 * et, à côté, `opts.side` (bloc de pilotage du catalogue). `opts.detail` : animation affichée ;
 * `opts.onAnim(nom)` : clic dans la galerie des animations (sinon, lecture dans la visionneuse).
 */
function showDetail(a, opts = {}) {
  stopPlayer();
  $('grid').hidden = true;
  $('cat-bar').hidden = true;
  const d = $('detail');
  d.hidden = false;
  const smooth = a.smooth ? ' smooth' : '';
  const stage = el('div', { class: 'stage ' + state.stageBg + smooth });
  const bgButtons = [['light', 'Clair'], ['dark', 'Sombre'], ['checker', 'Damier']].map(([v, label]) =>
    el('button', {
      type: 'button', class: 'small' + (state.stageBg === v ? ' primary' : ''),
      onclick: () => {
        state.stageBg = v; store('producer-stage', v); applyStageBg();
        stage.className = 'stage ' + v + smooth;
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
  } else if (a.type === 'data') {
    // JSON (chorégraphie, rig, zones) : texte brut, jamais interprété comme HTML.
    const pre = el('pre', { class: 'data', text: 'Chargement…' });
    stage.append(pre);
    stage.classList.add('data-stage');
    fetch(fileUrl(a.file), { credentials: 'same-origin', cache: 'no-store' })
      .then((r) => (r.ok ? r.text() : Promise.reject(new Error('Erreur ' + r.status))))
      .then((t) => { pre.textContent = t; })
      .catch((e) => { pre.textContent = e.message; });
  } else if (a.type === 'sprite') {
    const animSel = el('select', { 'aria-label': 'Animation' },
      a.anims.map((x) => el('option', { value: x.name, text: `${x.name} (${x.frames})` })));
    const def = a.anims.find((x) => x.name === opts.detail) || a.anims.find((x) => x.name === 'idle') || a.anims[0];
    animSel.value = def.name;
    const canvas = el('canvas');
    const ctx = canvas.getContext('2d');
    const frameLbl = el('span', { class: 'muted' });
    const playBtn = el('button', { type: 'button', class: 'small', text: '⏸ Pause' });
    stage.append(canvas);
    const p = { anim: def, img: null, cell: null, frame: 0, playing: true, timer: 0 };
    state.player = p;
    const draw = () => {
      if (!p.img) return;
      const { w, h } = p.cell;
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
    // Julien 24/10 : la HD s'affiche d'abord quand l'élément en a une ; le bouton passe au 32 px.
    let showHd = true;
    const hdBtn = a.anims.some((x) => x.hd) ? el('button', { type: 'button', class: 'small on' }) : null;
    const load = (src) => {
      const anim = showHd && src.hd ? { ...src.hd, name: src.name, src } : { ...src, src };
      if (hdBtn) hdBtn.textContent = src.hd ? (showHd ? 'HD : oui' : 'HD : non') : '32 px seulement';
      clearTimeout(p.timer);
      p.anim = anim; p.frame = 0; p.img = null;
      canvas.width = anim.w; canvas.height = anim.h;
      applyZoom();
      const img = new Image();
      img.onload = () => {
        if (p.anim !== anim) return;
        p.cell = sheetCell(anim, img);
        canvas.width = p.cell.w; canvas.height = p.cell.h;
        p.img = img; draw();
        if (p.playing) p.timer = setTimeout(tick, 1000 / anim.fps);
      };
      img.src = fileUrl(anim.file);
    };
    animSel.addEventListener('change', () => load(a.anims.find((x) => x.name === animSel.value)));
    // Toutes les animations du perso en même temps ; un clic l'ouvre dans le lecteur.
    gallery = el('div', { class: 'anim-gallery' }, a.anims.map((x) =>
      hoverAnimCell(x, 88, el('button', {
        type: 'button', class: 'anim-cell', title: `${x.name} (${x.frames} images)`,
        onclick: () => {
          if (opts.onAnim) { opts.onAnim(x.name); return; }
          animSel.value = x.name; load(x); stage.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        },
      }), (mini) => [el('div', { class: 'anim-box' }, mini), el('span', { text: x.name })])));
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
    // Persos de Blackout : lecteur plein écran (animations et masques ont les mêmes noms).
    const bkKey = bkKeyOf(a.id);
    const bk = bkKey ? [a.id, bkKey] : null;
    if (hdBtn) {
      hdBtn.addEventListener('click', () => { showHd = !showHd; hdBtn.classList.toggle('on', showHd); load(p.anim.src); });
    }
    controls.append(animSel, playBtn, hdBtn,
      el('button', { type: 'button', class: 'small', onclick: () => step(-1), 'aria-label': 'Frame précédente' }, '◀'),
      el('button', { type: 'button', class: 'small', onclick: () => step(1), 'aria-label': 'Frame suivante' }, '▶'),
      bk && state.index.blackout ? el('button', { type: 'button', class: 'small primary', onclick: () => openPlayer(bk[1], p.anim.name) }, '⛶ Plein écran') : null,
      frameLbl);
    if (bk && state.index.blackout && a.kind === 'anim') {
      const missing = bkSlots(bk[1]).filter((x) => !x.anim).map((x) => x.name);
      if (missing.length) {
        controls.append(el('p', { class: 'missing-band' },
          el('strong', { text: `${missing.length} manquante${missing.length > 1 ? 's' : ''} : ` }), missing.join(', ')));
      }
    }
    context = () => 'anim : ' + p.anim.name + (p.playing ? '' : ` (frame ${p.frame + 1})`);
    requestAnimationFrame(() => load(def));
  } else if (a.decor && a.kind === 'sol') {
    // Sol : la tuile répétée 2×2, puis la tuile seule.
    stage.classList.add('sol-stage');
    stage.append(solTile(a));
    controls.append(el('p', { class: 'muted sol-note', text: 'Tuile de sol : pas de masque (collision par case).' }));
  } else if (a.decor && a.kind === 'objet') {
    const d = a.decor;
    const views = [['image', 'Sans masques', a], ['masques', 'Avec masques', d.calque ? a : null],
      ['controle', 'Contrôle du jeu', d.controle], ['apercu_pf', 'Aperçu pixelforge', d.apercu_pf], ['ombre', 'Ombre', d.ombre]]
      .filter((v) => v[2]);
    let mode = views.some((v) => v[0] === state.decorMode) ? state.decorMode : 'image';
    const img = el('img', { alt: a.name });
    const calque = el('img', { class: 'calque', alt: '' });
    const layers = el('div', { class: 'dlayers' }, img, calque);
    stage.append(layers);
    const btns = views.map(([v, label]) => el('button', {
      type: 'button', class: 'small', 'data-v': v, onclick: () => { mode = v; show(); },
    }, label));
    const cur = () => {
      const v = views.find((x) => x[0] === mode);
      return v[0] === 'image' || v[0] === 'masques' ? { file: a.file, w: a.w, h: a.h } : v[2];
    };
    applyZoom = () => {
      const c = cur();
      const z = state.zoom || autoZoom(stage, c.w, c.h, 4);
      layers.style.width = c.w * z + 'px';
      layers.style.height = c.h * z + 'px';
    };
    const show = () => {
      const c = cur();
      img.src = fileUrl(c.file);
      calque.hidden = mode !== 'masques';
      if (mode === 'masques') calque.src = fileUrl(d.calque);
      for (const b of btns) b.classList.toggle('primary', b.dataset.v === mode);
      applyZoom();
    };
    requestAnimationFrame(show);
    const warn = d.warnings || [];
    controls.append(el('div', { class: 'seg' }, btns), decorLegend(),
      el('dl', { class: 'credits' },
        el('dt', { text: 'Masques' }), el('dd', {}, decorBadges(d)),
        el('dt', { text: 'Source' }), el('dd', { text: d.source === 'pixelforge' ? 'masques pixelforge utilisés par le jeu'
          : d.source === 'repli' ? 'repli : le jeu calcule la forme localement' + (d.refus ? ` (pixelforge refusé : ${d.refus})` : '')
            : 'aucun masque' }),
        el('dt', { text: 'Calques' }), el('dd', { text: (d.masques || []).join(', ') || '—' }),
        d.camera ? [el('dt', { text: 'Caméra' }), el('dd', { text: d.camera })] : null,
        d.shapes && d.shapes.length ? [el('dt', { text: 'Formes' }), el('dd', { text: d.shapes.join(', ') })] : null,
        el('dt', { text: 'Zones' }), el('dd', { text: (d.zones || []).join(', ') || '—' }),
        el('dt', { text: 'Avertissements' }), el('dd', {}, warn.length ? el('ul', { class: 'warns' }, warn.map((w) => el('li', { text: w }))) : '—')));
    context = () => 'vue : ' + mode;
  } else if (a.type === 'jeu') {
    // Règles, option de partie, écran de menu : rendus par jeu.js.
    stage.classList.add('data-stage', 'jeu-stage');
    stage.append(jeuView(a));
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

  const toolbar = a.type === 'jeu' ? null : el('div', { class: 'controls' }, bgButtons,
    a.type !== 'audio' && a.type !== 'data' ? zoomSel : null);

  const commentsBox = el('div', { class: 'asset-comments' });
  const renderAssetComments = () => {
    const list = state.comments.filter((c) => c.asset === a.id);
    commentsBox.replaceChildren(...(list.length ? list.map((c) => commentEl(c, false, renderAssetComments))
      : [el('p', { class: 'muted', text: 'Aucun commentaire pour l\'instant.' })]));
  };
  renderAssetComments();

  if (opts.contextRef) { opts.contextRef.get = context; opts.contextRef.comments = renderAssetComments; }
  // replaceChildren écrirait « null » : les blocs absents sont retirés.
  const main = el('div', { class: 'fiche-main' }, ...[
    toolbar,
    stage,
    controls,
    gallery ? el('h3', { text: 'Toutes les animations' }) : null,
    gallery,
    el('p', { class: 'meta' },
      `${a.id} · version ${a.version} · build ${state.index.commit}` +
      (a.w ? ` · ${a.w}×${a.h}` : '') + (a.note ? ' · ' + a.note : '')),
    opts.side ? null : el('h3', { text: 'Ton avis' }),
    opts.side ? null : commentForm(a, context, renderAssetComments),
    el('h3', { text: 'Commentaires de l\'asset (toutes versions)' }),
    commentsBox,
  ].filter(Boolean));
  d.replaceChildren(...[
    el('div', { class: 'detail-head' },
      el('button', { type: 'button', class: 'small', onclick: () => { location.hash = opts.back || '#/assets'; } }, '← Catalogue'),
      el('h2', { text: opts.title || a.name }),
      opts.pill || null,
      el('button', { type: 'button', class: 'small', onclick: () => openCardDialog(null, a.id) }, '+ Carte liée')),
    opts.side ? el('div', { class: 'fiche' }, main, opts.side) : main,
  ].filter(Boolean));
}

function commentForm(a, context, after, cardId, detail) {
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
      if (cardId) {
        // Depuis une carte : le commentaire d'asset est aussi reporté sur cette carte.
        await api('asset_comment', { method: 'POST', body: { asset: a.id, detail: detail || '', kind, body: text.value, context: context(), card: cardId } });
        await Promise.all([reloadComments(), reloadCards()]);
      } else {
        await api('comment', { method: 'POST', body: { asset: a.id, kind, body: text.value, context: context() } });
        await reloadComments();
      }
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
    c.card_id ? el('a', { href: '#/kanban', class: 'small', text: '→ carte #' + c.card_id,
      onclick: (ev) => { ev.preventDefault(); const k = cardById(c.card_id); if (k) openCardDialog(k, ''); else toast('Carte introuvable'); } }) : null,
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
// Colonnes Backlog → Todo → Doing → QA → Validé → En prod. Une carte peut avoir une carte
// « chapeau » (parent_id) : le chapeau affiche l'avancement de ses enfants et
// peut les déplier ; les enfants restent des cartes qui vivent leur vie.

const AUTHOR_LABEL = { julien: 'Julien', claude: 'Claude' };
// Mise à jour en direct du kanban : toutes les 10 s, on sonde la version de l'index des assets
// (une nouvelle version publiée recharge tuiles, détail et plein écran) ; les cartes sont relues
// toutes les 30 s, et à chaque fois tant que le détail d'une carte est ouvert.
const KANBAN_TICK_MS = Number(store('producer-kb-tick')) || 10000;   // réglable pour les tests
const KANBAN_CARDS_EVERY = 3;
const FRESH_MS = 8000;               // durée du signe « ↻ nouvelle version »

function cardById(id) {
  return state.cards.find((c) => c.id === id) || null;
}

function childrenOf(id) {
  return state.cards.filter((c) => c.parent_id === id);
}

/** Ids de la carte et de tous ses descendants. */
function familyIds(id) {
  const out = new Set([id]);
  for (let added = true; added;) {
    added = false;
    for (const c of state.cards) {
      if (c.parent_id !== null && out.has(c.parent_id) && !out.has(c.id)) { out.add(c.id); added = true; }
    }
  }
  return out;
}

/** Cartes proposées comme chapeau : celles qui ont des enfants, et les persos. */
function hatCards() {
  return state.cards.filter((c) => c.children > 0 || c.type === 'perso')
    .sort((a, b) => a.title.localeCompare(b.title, 'fr'));
}

function parentOptions(select, current, excluded) {
  select.replaceChildren(el('option', { value: '' }, '— aucun —'),
    ...state.cards.filter((c) => !excluded.has(c.id))
      .sort((a, b) => (b.children - a.children) || a.title.localeCompare(b.title, 'fr'))
      .map((c) => el('option', { value: c.id }, `#${c.id} ${c.title}`)));
  select.value = current ? String(current) : '';
}

function initKanban() {
  KB_MOBILE.addEventListener('change', () => { if (state.index && location.hash.startsWith('#/kanban')) renderBoard(); });
  // Balayage horizontal sur le board (mobile) : colonne voisine.
  let sw = null;
  $('board').addEventListener('touchstart', (ev) => {
    const t = ev.changedTouches[0];
    sw = ev.target.closest('select, input, textarea') ? null : { x: t.clientX, y: t.clientY };
  }, { passive: true });
  $('board').addEventListener('touchend', (ev) => {
    if (!sw || !isKbMobile()) return;
    const t = ev.changedTouches[0];
    const dx = t.clientX - sw.x, dy = t.clientY - sw.y;
    sw = null;
    if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
    const i = STATUSES.findIndex(([k]) => k === kbTab()) + (dx < 0 ? 1 : -1);
    if (i >= 0 && i < STATUSES.length) setKbTab(STATUSES[i][0]);
  }, { passive: true });
  // Détail en plein écran mobile : « ← » ou balayage vers la droite pour fermer.
  $('cf-back').addEventListener('click', closeCardDialog);
  $('cf-accept2').addEventListener('click', () => { if (state.editing) acceptCard(state.editing); });
  $('cf-refuse2').addEventListener('click', () => { if (state.editing) openRefuse(state.editing); });
  let dsw = null;
  $('card-dialog').addEventListener('touchstart', (ev) => {
    const t = ev.changedTouches[0];
    dsw = ev.target.closest('input, textarea, select, .anim-cell') ? null : { x: t.clientX, y: t.clientY };
  }, { passive: true });
  $('card-dialog').addEventListener('touchend', (ev) => {
    if (!dsw || !isKbMobile()) return;
    const t = ev.changedTouches[0];
    const dx = t.clientX - dsw.x, dy = t.clientY - dsw.y;
    dsw = null;
    if (dx > 90 && Math.abs(dy) < 60) closeCardDialog();
  }, { passive: true });
  $('new-card').addEventListener('click', () => openCardDialog(null, ''));
  $('cf-cancel').addEventListener('click', closeCardDialog);
  // Échap : même garde-fou que « Fermer ».
  $('card-dialog').addEventListener('cancel', (ev) => { if (state.dirty) { ev.preventDefault(); closeCardDialog(); } });
  // Enregistrement immédiat (carte existante) : night shift, type, priorité, chapeau.
  $('cf-night').addEventListener('change', () => saveNow('night', $('cf-night'), () => $('cf-night').checked));
  $('cf-type').addEventListener('change', () => saveNow('type', $('cf-type'), () => $('cf-type').value));
  $('cf-priority').addEventListener('change', () => saveNow('priority', $('cf-priority'), () => $('cf-priority').value));
  $('cf-parent').addEventListener('change', () => saveNow('parent', $('cf-parent'), () => Number($('cf-parent').value) || 0));
  $('cf-milestone').addEventListener('change', () => saveNow('milestone', $('cf-milestone'), () => Number($('cf-milestone').value) || 0));
  $('cf-due').addEventListener('change', () => saveNow('due', $('cf-due'), () => $('cf-due').value));
  // Champs texte : enregistrés avec « Enregistrer » ; on le signale tant que ce n'est pas fait.
  for (const id of ['cf-title', 'cf-desc', 'cf-asset', 'cf-detail']) {
    $(id).addEventListener('input', () => setDirty(!!state.editing));
  }
  $('card-form').addEventListener('submit', saveCard);
  $('cf-delete').addEventListener('click', deleteCard);
  $('cf-comment-send').addEventListener('click', sendComment);
  $('cf-asset').addEventListener('change', () => { fillDetailOptions(); renderCardAsset(); });
  $('cf-detail').addEventListener('change', renderCardAsset);
  $('cf-accept').addEventListener('click', () => { if (state.editing) acceptCard(state.editing); });
  $('cf-refuse').addEventListener('click', () => { if (state.editing) openRefuse(state.editing); });
  $('rf-cancel').addEventListener('click', () => $('refuse-dialog').close());
  $('refuse-form').addEventListener('submit', sendRefuse);
  $('cf-add-child').addEventListener('click', () => {
    const parent = state.editing;
    if (parent) openCardDialog(null, '', parent.id);
  });
  state.hat = Number(store('producer-kb-hat')) || 0;
  state.noHats = store('producer-kb-no-hats') === '1';
  state.hatsOnly = !state.noHats && store('producer-kb-hats-only') === '1';
  $('kb-hats-only').checked = state.hatsOnly;
  $('kb-no-hats').checked = state.noHats;
  // « Chapeaux seulement » et « Masquer les chapeaux » s'excluent : cocher l'une décoche l'autre.
  const setHatView = (hatsOnly, noHats) => {
    state.hatsOnly = hatsOnly;
    state.noHats = noHats;
    $('kb-hats-only').checked = hatsOnly;
    $('kb-no-hats').checked = noHats;
    store('producer-kb-hats-only', hatsOnly ? '1' : '0');
    store('producer-kb-no-hats', noHats ? '1' : '0');
    renderBoard();
  };
  $('kb-no-hats').addEventListener('change', () => setHatView(false, $('kb-no-hats').checked));
  state.nightOnly = store('producer-kb-night-only') === '1';
  $('kb-night-only').checked = state.nightOnly;
  $('kb-night-only').addEventListener('change', () => {
    state.nightOnly = $('kb-night-only').checked;
    store('producer-kb-night-only', state.nightOnly ? '1' : '0');
    renderBoard();
  });
  $('cf-night-children').addEventListener('click', nightToChildren);
  initKbFilters();
  $('kb-hat').addEventListener('change', () => {
    state.hat = Number($('kb-hat').value) || 0;
    store('producer-kb-hat', String(state.hat));
    renderBoard();
  });
  $('kb-hats-only').addEventListener('change', () => setHatView($('kb-hats-only').checked, false));
  let tick = 0;
  setInterval(() => { kanbanTick(++tick).catch(() => {}); }, KANBAN_TICK_MS);
}

/** Le board peut-il être redessiné sans gêner (glisser en cours, saisie dans le board) ? */
function boardIdle() {
  if (document.querySelector('.card.dragging')) return false;
  const active = document.activeElement;
  return !(active && active.closest('#board') && /INPUT|SELECT|TEXTAREA/.test(active.tagName));
}

async function kanbanTick(n) {
  // Julien 21/10 : toute vue ouverte (Bord, Kanban, Catalogue, fiche, Jeu, Roadmap) suit en direct les nouvelles
  // versions d'assets et les changements de statut des cartes.
  if (!state.index || document.hidden) return;
  // 1. Nouvelle version des assets ?
  const r = await api('index_version');
  let assetsChanged = false;
  if (r && r.v && state.indexV && r.v !== state.indexV) {
    assetsChanged = await reloadIndex();
  }
  if (r && r.v) state.indexV = r.v;
  // 2. Cartes : à chaque tour (10 s) ; état du studio tous les 3 tours.
  const before = JSON.stringify(state.cards);
  const studioBefore = JSON.stringify(state.studio || {});
  await reloadCards();
  if (n % KANBAN_CARDS_EVERY === 0) await reloadStudio();
  if (JSON.stringify(state.studio || {}) !== studioBefore && (location.hash.startsWith('#/bord') || !location.hash)) rerenderView();
  const cardsChanged = JSON.stringify(state.cards) !== before;
  if (!cardsChanged && !assetsChanged) return;
  renderNavBadges();
  const open = $('card-dialog').open;
  if (open) refreshOpenCard(assetsChanged);
  if (assetsChanged && state.fs && state.fs.reload) state.fs.reload();
  if (location.hash.startsWith('#/kanban') || !location.hash) {
    if (location.hash.startsWith('#/kanban') && boardIdle()) renderBoard();
    else if (!location.hash) rerenderView();
  } else {
    rerenderView();
  }
}

/** Redessine la vue courante sans perdre la place (rien si on est en train de saisir ou si un lecteur est ouvert). */
function rerenderView() {
  const a = document.activeElement;
  if (a && /INPUT|SELECT|TEXTAREA/.test(a.tagName)) return;
  if (state.fs || document.querySelector('dialog[open]')) return;
  const y = window.scrollY;
  route();
  window.scrollTo(0, y);
}

/**
 * Recharge l'index des assets ; note les assets dont la version a changé (signe « ↻ nouvelle
 * version » sur leurs cartes). Renvoie vrai si au moins un asset a changé.
 */
async function reloadIndex() {
  const old = state.assetsById;
  const index = await api('index');
  state.index = index;
  state.assetsById = new Map(index.assets.map((a) => [a.id, a]));
  const now = Date.now();
  let changed = false;
  for (const [id, a] of state.assetsById) {
    const o = old.get(id);
    if (!o || o.version !== a.version) { state.fresh.set(id, now); changed = true; }
  }
  return changed;
}

function isFresh(assetId) {
  const t = assetId ? state.fresh.get(assetId) : 0;
  return !!t && Date.now() - t < FRESH_MS;
}

/** Détail ouvert : suit la carte (colonne, asset, commentaires…) sans écraser une saisie en cours. */
function refreshOpenCard(assetsChanged) {
  const cur = state.editing;
  if (!cur) return;
  const c = cardById(cur.id);
  if (!c) { toast('Cette carte a été supprimée'); setDirty(false); $('card-dialog').close(); return; }
  const same = JSON.stringify(c) === JSON.stringify(cur);
  if (same && !(assetsChanged && isFresh(c.asset))) return;
  state.editing = c;
  $('card-dialog-title').textContent = `Carte #${c.id} · ${STATUS_LABEL[c.status]}`;
  $('cf-mtitle').textContent = `#${c.id} · ${STATUS_LABEL[c.status]}`;
  $('cf-qa').hidden = c.status !== 'qa';
  $('cf-qa-bar').hidden = c.status !== 'qa';
  $('cf-rework').hidden = !c.rework;
  $('cf-night-children').hidden = !c.children;
  renderJobs(c);
  const free = (id) => document.activeElement !== $(id) && !$(id).disabled;
  if (free('cf-night')) $('cf-night').checked = !!c.night;
  if (free('cf-type')) $('cf-type').value = c.type;
  if (free('cf-priority')) $('cf-priority').value = c.priority;
  if (free('cf-parent')) parentOptions($('cf-parent'), c.parent_id, familyIds(c.id));
  if (free('cf-milestone')) milestoneOptions($('cf-milestone'), c.milestone_id);
  if (free('cf-due')) $('cf-due').value = c.due || '';
  const assetMoved = c.asset !== cur.asset || c.detail !== cur.detail;
  if (!state.dirty) {
    for (const [id, v] of [['cf-title', c.title], ['cf-desc', c.description], ['cf-asset', c.asset], ['cf-detail', c.detail]]) {
      if (free(id)) $(id).value = v;
    }
    if (assetMoved) fillDetailOptions();
  }
  if (assetMoved || (assetsChanged && isFresh(c.asset))) {
    renderCardAsset();
    if (isFresh(c.asset)) flashFresh($('cf-asset-view'));
  }
  loadFeed(c.id);
}

/** Petit signe « ↻ nouvelle version » quelques secondes. */
function flashFresh(node) {
  if (!node) return;
  const b = el('span', { class: 'fresh', text: '↻ nouvelle version' });
  node.prepend(b);
  setTimeout(() => b.remove(), FRESH_MS);
}

function renderHatFilter() {
  const sel = $('kb-hat');
  const hats = hatCards();
  if (state.hat && !cardById(state.hat)) state.hat = 0;
  sel.replaceChildren(el('option', { value: '' }, 'Tous'),
    ...hats.map((c) => el('option', { value: c.id }, `${c.title} (${c.children_done}/${c.children})`)));
  // Un chapeau choisi qui n'a pas (encore) d'enfant reste sélectionnable.
  if (state.hat && !hats.some((c) => c.id === state.hat)) {
    const c = cardById(state.hat);
    sel.append(el('option', { value: c.id }, c.title));
  }
  sel.value = state.hat ? String(state.hat) : '';
}

// ---------------------------------------------------- filtres, recherche, sélection

const KB_FILTERS = ['q', 'type', 'perso', 'map', 'ms'];

function initKbFilters() {
  try { Object.assign(state.kb, JSON.parse(store('producer-kb-filters') || '{}')); } catch (e) { /* filtres illisibles */ }
  const save = () => store('producer-kb-filters', JSON.stringify(state.kb));
  $('kb-search').value = state.kb.q || '';
  let t = 0;
  $('kb-search').addEventListener('input', () => {
    clearTimeout(t);
    t = setTimeout(() => { state.kb.q = $('kb-search').value.trim(); save(); renderBoard(); }, 150);
  });
  for (const [id, key] of [['kb-type', 'type'], ['kb-perso', 'perso'], ['kb-map', 'map'], ['kb-ms', 'ms']]) {
    $(id).addEventListener('change', () => { state.kb[key] = $(id).value; save(); renderBoard(); });
  }
  $('kb-reset').addEventListener('click', () => {
    state.kb = { q: '', type: '', perso: '', map: '', ms: '' };
    $('kb-search').value = '';
    state.hat = 0; store('producer-kb-hat', '0');
    state.nightOnly = false; $('kb-night-only').checked = false; store('producer-kb-night-only', '0');
    save();
    renderBoard();
  });
  $('kb-select').addEventListener('click', () => setSelecting(!state.selecting));
}

/** Remplit les listes de filtres (types, persos, cartes de jeu, jalons) en gardant le choix. */
function renderKbFilters() {
  const fill = (id, first, opts, value) => {
    const sel = $(id);
    sel.replaceChildren(el('option', { value: '', text: first }), ...opts.map(([v, t]) => el('option', { value: v, text: t })));
    sel.value = opts.some(([v]) => v === value) ? value : '';
    sel.classList.toggle('on', !!sel.value);
  };
  const g = state.index.blackout || {};
  fill('kb-type', 'Tous les types', Object.entries(TYPE_LABEL), state.kb.type);
  fill('kb-perso', 'Tous les persos', (g.persos || []).map((p) => [p, persoName(p)]), state.kb.perso);
  fill('kb-map', 'Toutes les cartes de jeu', (g.cartes || []).filter((c) => c.jouable).map((c) => [c.id, c.nom]), state.kb.map);
  fill('kb-ms', 'Tous les jalons', [['none', 'Sans jalon'], ...state.milestones.map((m) => [String(m.id), m.title])], state.kb.ms);
  const n = KB_FILTERS.filter((k) => state.kb[k]).length + (state.hat ? 1 : 0) + (state.nightOnly ? 1 : 0);
  $('kb-reset').hidden = !n;
}

/** La carte, ou un de ses chapeaux, vérifie `test` ? */
function selfOrAncestor(c, test) {
  for (let cur = c, g = 0; cur && g < 10; g++) {
    if (test(cur)) return true;
    cur = cur.parent_id ? cardById(cur.parent_id) : null;
  }
  return false;
}

function cardMatchesPerso(c, pid) {
  const nom = norm(persoName(pid));
  return selfOrAncestor(c, (x) => (x.asset || '').includes(`/persos/${pid}/`) || new RegExp(`(^|[^a-z])${nom}([^a-z]|$)`).test(norm(x.title)));
}

function cardMatchesMap(c, mid) {
  const carte = ((state.index.blackout || {}).cartes || []).find((m) => m.id === mid);
  const nom = carte ? norm(carte.nom) : mid;
  return selfOrAncestor(c, (x) => {
    if (carte && carte.chapeau === x.id) return true;
    const a = x.asset ? state.assetsById.get(x.asset) : null;
    if (a && a.decor && (a.decor.cartes || [a.decor.carte]).includes(mid)) return true;
    if ((x.asset || '').startsWith(`maps/${mid}/`)) return true;
    return !!nom && norm(x.title).includes(nom);
  });
}

function kbFiltered(cards) {
  const { q, type, perso, map, ms } = state.kb;
  if (type) cards = cards.filter((c) => c.type === type);
  if (perso) cards = cards.filter((c) => cardMatchesPerso(c, perso));
  if (map) cards = cards.filter((c) => cardMatchesMap(c, map));
  if (ms) cards = cards.filter((c) => (ms === 'none' ? milestoneOf(c) === null : milestoneOf(c) === Number(ms)));
  if (q) {
    const n = norm(q);
    const id = /^#?(\d+)$/.exec(q);
    cards = cards.filter((c) => (id && c.id === Number(id[1])) || norm(c.title + ' ' + c.description).includes(n));
  }
  return cards;
}

function setSelecting(on) {
  state.selecting = on;
  if (!on) state.selected.clear();
  $('kb-select').classList.toggle('primary', on);
  $('kb-select').setAttribute('aria-pressed', on ? 'true' : 'false');
  renderBoard();
}

function toggleSelected(id, on) {
  if (on) state.selected.add(id); else state.selected.delete(id);
  renderBulkBar();
  const node = document.querySelector(`#board .card[data-id="${id}"]`);
  if (node) node.classList.toggle('selected', on);
}

/** Barre des actions groupées : déplacer, night shift, priorité, jalon. */
function renderBulkBar() {
  const bar = $('kb-bulk');
  bar.hidden = !state.selecting;
  if (!state.selecting) return;
  const ids = [...state.selected].filter((id) => cardById(id));
  const run = async (body, label) => {
    if (!ids.length) { toast('Aucune carte sélectionnée'); return; }
    const r = await guarded(async () => {
      const res = await api('cards_bulk', { method: 'POST', body: { ids, ...body } });
      await reloadCards();
      return res;
    });
    if (!r) return;
    toast(`${label} : ${r.changed} carte${r.changed > 1 ? 's' : ''} modifiée${r.changed > 1 ? 's' : ''}`);
    renderBoard();
  };
  const sel = (label, opts, apply) => {
    const s = el('select', { 'aria-label': label },
      el('option', { value: '', text: label }), opts.map(([v, t]) => el('option', { value: v, text: t })));
    s.addEventListener('change', () => { if (s.value !== '') apply(s.value); s.value = ''; });
    return s;
  };
  const visible = [...document.querySelectorAll('#board .card[data-id]')].map((n) => Number(n.dataset.id));
  bar.replaceChildren(
    el('strong', { text: `${ids.length} sélectionnée${ids.length > 1 ? 's' : ''}` }),
    el('button', { type: 'button', class: 'small', onclick: () => { for (const id of visible) state.selected.add(id); renderBoard(); } }, 'Tout ce qui est affiché'),
    el('button', { type: 'button', class: 'small ghost', onclick: () => { state.selected.clear(); renderBoard(); } }, 'Aucune'),
    sel('Déplacer vers…', STATUSES, (v) => run({ status: v }, 'Déplacées')),
    sel('🌙 Night shift…', [['1', 'Activer'], ['0', 'Désactiver']], (v) => run({ night: v === '1' }, 'Night shift')),
    sel('Priorité…', [['haute', 'Haute'], ['normale', 'Normale'], ['basse', 'Basse'], ['-', 'Aucune']],
      (v) => run({ priority: v === '-' ? '' : v }, 'Priorité')),
    sel('Jalon…', [...state.milestones.map((m) => [String(m.id), m.title]), ['0', 'Aucun jalon']],
      (v) => run({ milestone: Number(v) }, 'Jalon')),
    el('button', { type: 'button', class: 'small', onclick: () => setSelecting(false) }, 'Terminer'));
}

function visibleCards() {
  let cards = kbFiltered(state.cards);
  if (state.nightOnly) cards = cards.filter((c) => c.night);
  if (state.hat) {
    const fam = familyIds(state.hat);
    cards = cards.filter((c) => fam.has(c.id));
  }
  // Masquer les chapeaux : seules les cartes sans enfant restent, chacune dans sa colonne.
  if (state.noHats) cards = cards.filter((c) => !c.children);
  if (state.hatsOnly) {
    // Un enfant dont le chapeau est affiché est caché (il se voit en dépliant).
    const shown = new Set(cards.map((c) => c.id));
    cards = cards.filter((c) => c.parent_id === null || !shown.has(c.parent_id));
  }
  return cards;
}

function quickAdd() {
  const title = el('input', { maxlength: 200, placeholder: 'Nouvelle idée…', 'aria-label': 'Titre de la nouvelle carte', required: true });
  const parent = el('select', { 'aria-label': 'Chapeau (optionnel)', class: 'qa-parent' });
  parentOptions(parent, state.hat, new Set());
  parent.options[0].textContent = 'sans chapeau';
  const send = el('button', { type: 'submit', class: 'small primary' }, 'Ajouter');
  const night = el('input', { type: 'checkbox', 'aria-label': 'Night shift' });
  const nightLbl = el('label', { class: 'inline qa-night', title: 'Night shift : à traiter la nuit (1 h – 8 h)' }, night, '🌙');
  const form = el('form', { class: 'quick-add' }, title, el('div', { class: 'row' }, parent, nightLbl, send));
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    if (!title.value.trim()) return;
    send.disabled = true;
    const body = { title: title.value.trim(), status: 'backlog' };
    if (parent.value) body.parent = Number(parent.value);
    if (night.checked) body.night = true;
    const ok = await guarded(async () => {
      await api('card', { method: 'POST', body });
      await reloadCards();
      return true;
    });
    send.disabled = false;
    if (ok) {
      toast('Carte ajoutée au Backlog');
      renderBoard();
      const again = document.querySelector('.quick-add input');
      if (again) again.focus();
    }
  });
  return form;
}

// ------------------------------------------------------------ vue mobile
// Téléphone (portrait, ou paysage étroit) : une colonne à la fois, onglets
// collants, tuiles compactes avec leurs actions. La vue ordinateur ne change pas.
const KB_MOBILE = window.matchMedia('(max-width: 760px), (max-height: 500px) and (max-width: 1000px)');

function isKbMobile() {
  return KB_MOBILE.matches;
}

/** Onglet actif : mémorisé, sinon QA s'il y a des cartes à tester, sinon Todo. */
function kbTab() {
  if (STATUSES.some(([k]) => k === state.kbTab)) return state.kbTab;
  const saved = store('producer-kb-tab');
  if (STATUSES.some(([k]) => k === saved)) return saved;
  return state.cards.some((c) => c.status === 'qa') ? 'qa' : 'todo';
}

function setKbTab(status) {
  state.kbTab = status;
  store('producer-kb-tab', status);
  renderBoard();
  window.scrollTo(0, 0);
}

function renderKbTabs(cards) {
  const active = kbTab();
  $('kb-tabs').replaceChildren(...STATUSES.map(([status, label]) => el('button', {
    type: 'button', class: 'kb-tab' + (status === active ? ' active' : ''), 'data-status': status,
    'aria-pressed': status === active ? 'true' : 'false', onclick: () => setKbTab(status),
  }, el('span', { class: 'l', text: STATUS_SHORT[status] || label }), el('span', { class: 'n', text: String(cards.filter((c) => c.status === status).length) }))),
  el('button', {
    type: 'button', class: 'kb-tab kb-filters' + ($('view-kanban').classList.contains('filters-open') ? ' active' : '')
      + (state.hat || state.hatsOnly || state.noHats || state.nightOnly || KB_FILTERS.some((k) => state.kb[k]) ? ' on' : ''),
    'aria-label': 'Filtres et nouvelle carte', title: 'Filtres et nouvelle carte',
    onclick: () => { $('view-kanban').classList.toggle('filters-open'); renderBoard(); },
  }, '☰'));
  // Les onglets collent sous l'en-tête, dont la hauteur varie (portrait : 2 lignes).
  document.documentElement.style.setProperty('--top-h', document.querySelector('header.top').offsetHeight + 'px');
}

/** Tuile compacte (mobile) : miniature, titre, badges, et l'action du moment. */
function cardCompact(c) {
  const stop = (ev) => ev.stopPropagation();
  let act;
  if (c.status === 'qa') {
    act = [
      el('button', { type: 'button', class: 'accept', 'aria-label': 'Accepter', title: 'Accepter', onclick: (ev) => { ev.stopPropagation(); acceptCard(c); } }, '✓'),
      el('button', { type: 'button', class: 'refuse', 'aria-label': 'Refuser', title: 'Refuser', onclick: (ev) => { ev.stopPropagation(); openRefuse(c); } }, '✗'),
    ];
  } else {
    const sel = el('select', { class: 'move', 'aria-label': 'Déplacer vers…', onclick: stop },
      el('option', { value: '', text: '⇄' }),
      STATUSES.filter(([k]) => k !== c.status).map(([k, label]) => el('option', { value: k, text: '→ ' + label })));
    sel.addEventListener('change', () => { if (sel.value) moveCard(c.id, sel.value); });
    act = [sel];
  }
  const card = el('div', {
    class: 'card compact t-' + c.type + (state.selected.has(c.id) ? ' selected' : ''), 'data-id': c.id, tabindex: '0',
    onclick: () => (state.selecting ? toggleSelected(c.id, !state.selected.has(c.id)) : openCardDialog(c, '')),
  },
  state.selecting ? selectBox(c) : null,
  el('span', { class: 'card-thumb none' }),
  el('div', { class: 'cbody' },
    el('div', { class: 'title', text: c.title }),
    el('div', { class: 'cmeta' },
      typeBadge(c.type),
      c.priority ? el('span', { class: 'badge ' + c.priority, text: PRIO_LABEL[c.priority] }) : null,
      c.rework ? el('span', { class: 'rework', text: '↺ à retraiter' }) : null,
      isFresh(c.asset) ? el('span', { class: 'fresh', text: '↻' }) : null,
      c.night ? el('span', { class: 'badge night', title: 'Night shift', text: '🌙' }) : null,
      jobsBadge(c),
      dueBadge(c.due, FINISHED.has(c.status)),
      c.children > 0 ? el('span', { class: 'muted', text: `▤ ${c.children_done}/${c.children}` }) : null,
      el('span', { class: 'muted', text: '#' + c.id }))),
  el('div', { class: 'cact' }, act));
  const th = cardThumbEl(c, card);
  if (th) card.querySelector('.card-thumb.none').replaceWith(th);
  return card;
}

function renderBoard() {
  renderHatFilter();
  renderKbFilters();
  renderBulkBar();
  renderNavBadges();
  const board = $('board');
  const cards = visibleCards();
  const mobile = isKbMobile();
  const active = mobile ? kbTab() : '';
  board.classList.toggle('mobile', mobile);
  $('kb-tabs').hidden = !mobile;
  if (mobile) renderKbTabs(cards);
  board.replaceChildren(...STATUSES.map(([status, label], col) => {
    const list = cards.filter((c) => c.status === status);
    const column = el('div', { class: 'column' + (status === active ? ' active' : ''), 'data-status': status },
      el('h3', {}, el('span', { text: label }), el('span', { class: 'muted', text: String(list.length) })),
      status === 'backlog' ? quickAdd() : null,
      list.map((c) => (mobile ? cardCompact(c) : cardEl(c, col))),
      mobile && !list.length ? el('p', { class: 'empty', text: 'Aucune carte ici.' }) : null);
    column.addEventListener('dragover', (ev) => { ev.preventDefault(); column.classList.add('over'); });
    column.addEventListener('dragleave', () => column.classList.remove('over'));
    column.addEventListener('drop', (ev) => {
      ev.preventDefault();
      column.classList.remove('over');
      const id = Number(ev.dataTransfer.getData('text/plain'));
      if (!id) return;
      // Position d'insertion parmi TOUTES les cartes de la colonne (filtrées ou
      // non) : avant la première carte affichée dont le milieu est sous le curseur.
      const others = [...column.querySelectorAll(':scope > .card')].filter((n) => Number(n.dataset.id) !== id);
      const all = state.cards.filter((c) => c.status === status && c.id !== id).map((c) => c.id);
      let index = all.length;
      for (const n of others) {
        const r = n.getBoundingClientRect();
        if (ev.clientY < r.top + r.height / 2) { index = all.indexOf(Number(n.dataset.id)); break; }
      }
      moveCard(id, status, index);
    });
    return column;
  }));
}

/** Case à cocher d'une tuile en mode sélection. */
function selectBox(c) {
  const box = el('input', { type: 'checkbox', class: 'kb-check', 'aria-label': 'Sélectionner #' + c.id, checked: state.selected.has(c.id) || null });
  box.addEventListener('click', (ev) => { ev.stopPropagation(); toggleSelected(c.id, box.checked); });
  return box;
}

function typeBadge(type) {
  return el('span', { class: 'badge t-' + type, text: TYPE_LABEL[type] || type });
}

function cardEl(c, col) {
  const asset = c.asset ? state.assetsById.get(c.asset) : null;
  const parent = c.parent_id ? cardById(c.parent_id) : null;
  const move = (dir) => (ev) => {
    ev.stopPropagation();
    moveCard(c.id, STATUSES[col + dir][0]);
  };
  const stop = (ev) => ev.stopPropagation();
  let hat = null;
  if (c.children > 0) {
    const pct = Math.round((100 * c.children_done) / c.children);
    const open = state.expanded.has(c.id);
    const kids = childrenOf(c.id);
    hat = el('div', { class: 'hat' },
      el('div', { class: 'progress', title: `${c.children_done} sur ${c.children} en QA, Validé ou En prod`, role: 'img', 'aria-label': `Avancement ${pct} %` },
        el('span', { style: null, class: 'bar' })),
      el('div', { class: 'hat-row' },
        el('span', { class: 'muted', text: `${c.children_done}/${c.children}` }),
        el('button', {
          type: 'button', class: 'small ghost unfold', 'aria-expanded': open ? 'true' : 'false',
          onclick: (ev) => {
            ev.stopPropagation();
            if (state.expanded.has(c.id)) state.expanded.delete(c.id); else state.expanded.add(c.id);
            renderBoard();
          },
        }, (open ? '▾ ' : '▸ ') + `${kids.length} enfant${kids.length > 1 ? 's' : ''}`)),
      open ? el('ul', { class: 'kids' }, kids.map((k) => el('li', {},
        el('button', {
          type: 'button', class: 'kid',
          onclick: (ev) => { ev.stopPropagation(); openCardDialog(k, ''); },
        }, el('span', { class: 'st st-' + k.status, text: STATUS_LABEL[k.status] }), el('span', { text: k.title }))))) : null);
    // La largeur passe par le style de l'élément (CSP : pas d'attribut style).
    hat.querySelector('.bar').style.width = pct + '%';
  }
  const comments = c.notes.length;
  const qa = c.status === 'qa' ? el('div', { class: 'qa-actions' },
    el('button', { type: 'button', class: 'accept', onclick: (ev) => { ev.stopPropagation(); acceptCard(c); } }, '✓ Accepter'),
    el('button', { type: 'button', class: 'refuse', onclick: (ev) => { ev.stopPropagation(); openRefuse(c); } }, '✗ Refuser')) : null;
  const ms = c.milestone_id ? milestoneById(c.milestone_id) : null;
  const card = el('div', {
    class: 'card t-' + c.type + (c.children > 0 ? ' is-hat' : '') + (state.selected.has(c.id) ? ' selected' : ''),
    draggable: 'true', 'data-id': c.id, tabindex: '0',
    onclick: () => (state.selecting ? toggleSelected(c.id, !state.selected.has(c.id)) : openCardDialog(c, '')),
    onkeydown: (ev) => { if (ev.key === 'Enter' && ev.target === ev.currentTarget) openCardDialog(c, ''); },
  },
  state.selecting ? selectBox(c) : null,
  el('span', { class: 'thumb-slot' }),   // asset en pleine largeur, en haut (s'il y en a un)
  el('div', { class: 'foot' },
    typeBadge(c.type),
    c.priority ? el('span', { class: 'badge ' + c.priority, text: PRIO_LABEL[c.priority] }) : null,
    c.night ? el('span', { class: 'badge night', title: 'Night shift : traitée la nuit (1 h – 8 h)', text: '🌙' }) : null,
    jobsBadge(c),
    dueBadge(c.due, FINISHED.has(c.status)),
    ms ? el('span', { class: 'badge ms', title: 'Jalon', text: '⚑ ' + ms.title }) : null,
    el('span', { class: 'muted', text: '#' + c.id }),
    el('span', { class: 'spacer' }),
    el('span', { class: 'origin', title: 'Créée par ' + (AUTHOR_LABEL[c.origin] || c.origin), text: AUTHOR_LABEL[c.origin] || c.origin })),
  c.rework ? el('div', { class: 'rework', text: '↺ à retraiter' }) : null,
  isFresh(c.asset) ? el('div', { class: 'fresh', text: '↻ nouvelle version' }) : null,
  parent ? el('a', {
    class: 'parent-link', href: '#/kanban', title: 'Ouvrir le chapeau',
    onclick: (ev) => { ev.preventDefault(); ev.stopPropagation(); openCardDialog(parent, ''); },
    text: '↑ ' + parent.title,
  }) : null,
  el('div', { class: 'card-main' },
    el('div', { class: 'card-text' },
      el('div', { class: 'title', text: c.title }),
      c.description ? el('div', { class: 'desc', text: c.description }) : null,
      c.asset ? el('a', {
        class: 'asset-link', href: '#/assets/' + encodeURIComponent(c.asset),
        onclick: stop, text: '↗ ' + (asset ? asset.name : c.asset) + (c.detail ? ' · ' + c.detail : ''),
      }) : null)),
  hat,
  qa,
  el('div', { class: 'foot' },
    comments ? el('span', { class: 'muted', text: `${comments} commentaire${comments > 1 ? 's' : ''}` }) : null,
    el('span', { class: 'spacer' }),
    col > 0 ? el('button', { type: 'button', class: 'small', onclick: move(-1), 'aria-label': 'Colonne précédente', title: STATUSES[col - 1][1] }, '◀') : null,
    col < STATUSES.length - 1 ? el('button', { type: 'button', class: 'small', onclick: move(1), 'aria-label': 'Colonne suivante', title: STATUSES[col + 1][1] }, '▶') : null));
  const slot = card.querySelector('.thumb-slot');
  const th = cardThumbEl(c, card);
  if (th) slot.replaceWith(th); else slot.remove();
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

// ------------------------------------------------------------- détail d'une carte

function eventText(e) {
  const st = (s) => STATUS_LABEL[s] || s;
  const ref = (id) => {
    if (!id) return 'aucun';
    const c = cardById(Number(id));
    return c ? `« ${c.title} »` : '#' + id;
  };
  switch (e.type) {
    case 'creation': return `a créé la carte dans ${st(e.new)}`;
    case 'deplacement': return `a déplacé la carte : ${st(e.old)} → ${st(e.new)}`;
    case 'titre': return `a renommé la carte (avant : « ${e.old} »)`;
    case 'description': return 'a modifié la description';
    case 'priorite': return `a changé la priorité : ${PRIO_LABEL[e.old] || 'aucune'} → ${PRIO_LABEL[e.new] || 'aucune'}`;
    case 'type': return `a changé le type : ${TYPE_LABEL[e.old] || e.old} → ${TYPE_LABEL[e.new] || e.new}`;
    case 'asset': return `a changé l'asset lié : ${e.new || 'aucun'}`;
    case 'parent': return `a changé le chapeau : ${ref(e.old)} → ${ref(e.new)}`;
    case 'detail': return `a changé le détail de l'asset : ${e.new || 'aucun'}`;
    case 'accepte': return `a accepté la carte : QA → ${st(e.new || 'valide')}`;
    case 'jobs': return `tâches pixelforge : ${e.new || 'aucune'}`;
    case 'night': return e.new === 'on' ? 'a activé le night shift 🌙' : 'a désactivé le night shift';
    case 'jalon': {
      const m = (id) => (id ? (milestoneById(Number(id)) || { title: '#' + id }).title : 'aucun');
      return `a changé le jalon : ${m(e.old)} → ${m(e.new)}`;
    }
    case 'echeance': return `a changé l'échéance : ${e.old ? fmtDue(e.old) : 'aucune'} → ${e.new ? fmtDue(e.new) : 'aucune'}`;
    default: return e.type;
  }
}

/** Fil chronologique : événements et commentaires mêlés. */
function renderFeed(events) {
  const feed = $('cf-feed');
  // Tâches pixelforge : seul le dernier état est montré, en petit (le watcher en écrit souvent).
  const lastJobs = events.filter((e) => e.type === 'jobs').pop();
  events = events.filter((e) => e.type !== 'jobs' || e === lastJobs);
  feed.replaceChildren(...events.map((e) => {
    if (e.type === 'jobs') {
      return el('div', { class: 'event jobs muted' }, fmtDate(e.at) + ' · ' + eventText(e));
    }
    const who = AUTHOR_LABEL[e.author] || e.author;
    if (e.type === 'commentaire') {
      return el('div', { class: 'note ' + e.author },
        el('strong', { text: `${who} · ${fmtDate(e.at)}` }), el('br'), e.new);
    }
    if (e.type === 'refuse') {
      return el('div', { class: 'note refus' },
        el('strong', { text: `✗ Refusée par ${who} · ${fmtDate(e.at)} · ${e.old === 'qa>todo' ? 'à refaire (Todo)' : 'retour en Backlog'}` }), el('br'), e.new);
    }
    return el('div', { class: 'event' },
      el('span', { class: 'muted', text: fmtDate(e.at) + ' · ' }), el('strong', { text: who }), ' ' + eventText(e));
  }));
  if (!events.length) feed.append(el('p', { class: 'muted', text: 'Pas encore d\'historique.' }));
}

async function loadFeed(id) {
  const r = await guarded(() => api('card', { query: { id } }));
  if (!r || !state.editing || state.editing.id !== id) return;
  renderFeed(r.events);
  const kids = r.children;
  $('cf-children').replaceChildren(...kids.map((k) => el('li', {},
    el('button', { type: 'button', class: 'kid', onclick: () => openCardDialog(k, '') },
      el('span', { class: 'st st-' + k.status, text: STATUS_LABEL[k.status] }), typeBadge(k.type), el('span', { text: k.title })))));
  $('cf-children-title').textContent = kids.length
    ? `Enfants (${r.card.children_done}/${r.card.children} en QA, Validé ou En prod)` : 'Enfants';
}

function openCardDialog(card, assetId, parentId) {
  state.editing = card;
  $('card-dialog-title').textContent = card ? `Carte #${card.id} · ${STATUS_LABEL[card.status]}` : 'Nouvelle carte (Backlog)';
  $('cf-origin').textContent = card ? `Créée par ${AUTHOR_LABEL[card.origin] || card.origin} le ${fmtDate(card.created_at)}` : '';
  $('cf-type').value = card ? card.type : 'feature';
  $('cf-priority').value = card ? card.priority : '';
  $('cf-title').value = card ? card.title : '';
  $('cf-desc').value = card ? card.description : '';
  $('cf-asset').value = card ? card.asset : assetId;
  $('cf-detail').value = card ? card.detail : '';
  $('cf-night').checked = card ? !!card.night : false;
  milestoneOptions($('cf-milestone'), card ? card.milestone_id : 0);
  $('cf-due').value = card ? card.due || '' : '';
  setDirty(false);
  setSaveState('');
  $('cf-night-children').hidden = !card || !card.children;
  fillDetailOptions();
  renderCardAsset();
  $('cf-qa').hidden = !card || card.status !== 'qa';
  $('cf-qa-bar').hidden = !card || card.status !== 'qa';
  $('cf-mtitle').textContent = card ? `#${card.id} · ${STATUS_LABEL[card.status]}` : 'Nouvelle carte';
  $('cf-rework').hidden = !card || !card.rework;
  renderJobs(card);
  parentOptions($('cf-parent'), card ? card.parent_id : (parentId || 0), card ? familyIds(card.id) : new Set());
  $('cf-note').value = '';
  $('card-error').textContent = '';
  $('cf-delete').hidden = !card;
  $('cf-thread').hidden = !card;
  $('cf-feed').replaceChildren();
  $('cf-children').replaceChildren();
  $('cf-children-title').textContent = 'Enfants';
  if (!$('card-dialog').open) $('card-dialog').showModal();
  $('card-dialog').scrollTop = 0;
  if (card) loadFeed(card.id);
}

function cardBody() {
  return {
    type: $('cf-type').value, priority: $('cf-priority').value, title: $('cf-title').value,
    description: $('cf-desc').value, asset: $('cf-asset').value.trim(), detail: $('cf-detail').value.trim(),
    night: $('cf-night').checked,
    parent: Number($('cf-parent').value) || 0,
    milestone: Number($('cf-milestone').value) || 0,
    due: $('cf-due').value,
  };
}

function milestoneOptions(select, current) {
  select.replaceChildren(el('option', { value: '', text: '— aucun —' }),
    ...state.milestones.map((m) => el('option', { value: m.id, text: m.title + (m.closed ? ' (clos)' : '') })));
  select.value = current ? String(current) : '';
}

/** Ferme le détail ; demande confirmation s'il reste des champs texte non enregistrés. */
function closeCardDialog() {
  if (state.dirty && !confirm('Des modifications ne sont pas enregistrées. Fermer quand même ?')) return;
  setDirty(false);
  $('card-dialog').close();
}

function setDirty(on) {
  state.dirty = on;
  $('cf-dirty').hidden = !on;
}

/** Retour visuel de l'enregistrement immédiat : '' | 'en cours' | 'ok' | 'erreur'. */
let saveStateTimer = 0;
function setSaveState(st, msg) {
  const n = $('cf-saved');
  clearTimeout(saveStateTimer);
  n.className = 'save-state ' + st;
  n.textContent = { '': '', 'en cours': 'enregistrement…', ok: '✓ enregistré', erreur: '✗ ' + (msg || 'non enregistré') }[st];
  if (st === 'ok') saveStateTimer = setTimeout(() => { n.textContent = ''; }, 2500);
}

/**
 * Enregistre tout de suite un champ d'une carte existante (sans « Enregistrer »).
 * En cas d'échec, le champ revient à sa valeur précédente.
 */
async function saveNow(field, input, value) {
  const card = state.editing;
  if (!card) return;   // nouvelle carte : tout part à la création
  const old = field === 'parent' ? (card.parent_id || 0) : field === 'night' ? !!card.night
    : field === 'milestone' ? (card.milestone_id || 0) : card[field];
  const v = value();
  if (v === old) return;
  input.disabled = true;
  setSaveState('en cours');
  try {
    await api('card_update', { method: 'POST', body: { id: card.id, [field]: v } });
    await reloadCards();
  } catch (e) {
    if (input.type === 'checkbox') input.checked = old; else input.value = String(old || '');
    setSaveState('erreur', e.message);
    input.disabled = false;
    return;
  }
  input.disabled = false;
  setSaveState('ok');
  state.editing = cardById(card.id) || card;
  if (field === 'parent') parentOptions($('cf-parent'), state.editing.parent_id, familyIds(card.id));
  if (location.hash.startsWith('#/roadmap')) renderRoadmap();
  loadFeed(card.id);
  if (location.hash.startsWith('#/kanban')) renderBoard();
}

async function sendComment() {
  const card = state.editing;
  const text = $('cf-note').value.trim();
  if (!card || !text) return;
  $('cf-comment-send').disabled = true;
  const ok = await guarded(async () => {
    await api('card_comment', { method: 'POST', body: { id: card.id, body: text } });
    await reloadCards();
    return true;
  });
  $('cf-comment-send').disabled = false;
  if (!ok) return;
  $('cf-note').value = '';
  state.editing = cardById(card.id) || card;
  loadFeed(card.id);
  if (location.hash.startsWith('#/kanban')) renderBoard();
}

async function saveCard(ev) {
  ev.preventDefault();
  const card = state.editing;
  const body = cardBody();
  try {
    if (card) {
      await api('card_update', { method: 'POST', body: { id: card.id, ...body } });
      const note = $('cf-note').value.trim();
      if (note) await api('card_comment', { method: 'POST', body: { id: card.id, body: note } });
    } else {
      await api('card', { method: 'POST', body: { ...body, status: 'backlog' } });
    }
    await reloadCards();
  } catch (e) {
    $('card-error').textContent = e.message;
    return;
  }
  setDirty(false);
  $('card-dialog').close();
  toast(card ? 'Carte mise à jour' : 'Carte créée dans le Backlog');
  if (location.hash.startsWith('#/kanban')) renderBoard();
}

// ------------------------------------------------- asset lié à une carte

/** Animation visée par une carte (champ « détail »), ou l'idle, ou la première. */
function cardAnim(a, detail) {
  if (!a || !a.anims || !a.anims.length) return null;
  return a.anims.find((x) => x.name === detail) || a.anims.find((x) => x.name === 'idle') || a.anims[0];
}

/**
 * Miniature d'une tuile du kanban (ordinateur et mobile), branchée sur `card` :
 * - animation : image fixe, l'animation joue au survol de la tuile (premier
 *   toucher sur la miniature en tactile), comme la page Persos ;
 * - objet du décor avec masques : les masques se superposent au survol
 *   (toucher la miniature les bascule), chargés seulement à ce moment-là ;
 * - sinon l'aperçu de l'asset. Renvoie null s'il n'y a rien à montrer.
 */
function cardThumbEl(c, card) {
  const a = c.asset ? state.assetsById.get(c.asset) : null;
  if (!a || a.type === 'audio' || a.type === 'data') return null;
  const smooth = a.smooth ? ' smooth' : '';
  const anim = cardAnim(a, c.detail);
  if (anim && anim.poster) {
    const mini = miniAnim(anim, 0);
    mini.className = 'mini card-thumb' + smooth;
    const box = el('span', { class: 'thumb-box', title: 'Survoler pour animer' }, mini);
    hoverMini(card, mini, box);
    return box;
  }
  const src = cardThumb(c);
  if (!src) return null;
  const base = el('img', { src: fileUrl(src), alt: '', loading: 'lazy', decoding: 'async' });
  if (!(a.decor && a.kind === 'objet' && a.decor.calque)) {
    base.className = 'card-thumb' + smooth;
    return base;
  }
  const calque = el('img', { class: 'calque', alt: '', decoding: 'async' });
  const box = el('span', { class: 'card-thumb dthumb', title: 'Survoler pour voir les masques' }, base, calque);
  const show = (on) => {
    if (on && !calque.getAttribute('src')) calque.src = fileUrl(a.decor.calque);
    box.classList.toggle('masks', on);
  };
  card.addEventListener('pointerenter', (ev) => { if (ev.pointerType === 'mouse') show(true); });
  card.addEventListener('pointerleave', (ev) => { if (ev.pointerType === 'mouse') show(false); });
  let touch = false;
  box.addEventListener('pointerdown', (ev) => { touch = ev.pointerType !== 'mouse'; });
  box.addEventListener('click', (ev) => {
    if (!touch) return;
    ev.preventDefault();
    ev.stopImmediatePropagation();
    show(!box.classList.contains('masks'));
  }, { capture: true });
  return box;
}

/** Miniature de la tuile : image fixe de l'animation visée, sinon l'aperçu de l'asset. */
function cardThumb(c) {
  const a = c.asset ? state.assetsById.get(c.asset) : null;
  if (!a || a.type === 'audio' || a.type === 'data') return '';
  const anim = cardAnim(a, c.detail);
  return (anim && anim.poster) || a.preview || '';
}

function fillDetailOptions() {
  const a = state.assetsById.get($('cf-asset').value.trim());
  $('detail-ids').replaceChildren(...(a && a.anims ? a.anims.map((x) => el('option', { value: x.name })) : []));
  $('cf-detail-label').hidden = !(a && a.anims);
}

/** Vue de l'asset lié, puis le formulaire de commentaire d'asset et ses commentaires. */
function renderCardAsset() {
  const box = $('cf-asset-view');
  const type = $('cf-type').value;
  // Carte « Perso » sans asset : le set est retrouvé par le nom du perso dans le titre.
  const a = state.assetsById.get($('cf-asset').value.trim()) || (type === 'perso' ? setFromTitle($('cf-title').value) : null);
  $('card-dialog').classList.remove('wide');
  if (!a) { box.replaceChildren(); box.hidden = true; return; }
  box.hidden = false;
  const detail = $('cf-detail').value.trim();
  // Carte chapeau d'un perso (type Perso, ou asset « animations » sans détail) : toutes les
  // animations du set, décrites et commentables une par une (recette.js).
  if (a.set && (type === 'perso' || !detail)) { renderSetGallery(box, a); return; }
  const anim = cardAnim(a, detail);
  const bkKey = bkKeyOf(a.id);
  const bk = bkKey ? [a.id, bkKey] : null;
  const openAsset = () => { $('card-dialog').close(); location.hash = '#/assets/' + encodeURIComponent(a.id); };
  let view;
  if (anim) {
    const cell = hoverAnimCell(anim, 150, el('button', {
      type: 'button', class: 'anim-cell big', title: 'Survoler pour animer, cliquer pour le plein écran',
      onclick: () => {
        $('card-dialog').close();
        if (bk) openPlayer(bk[1], anim.name); else openAsset();
      },
    }), (mini) => [el('div', { class: 'anim-box' }, mini), el('span', { text: `${anim.name} · ${anim.frames} im. · ${anim.fps} i/s` })]);
    view = el('div', { class: 'ca-anim' + (a.smooth ? ' smooth' : '') }, cell,
      bk ? el('button', { type: 'button', class: 'small primary', onclick: () => { $('card-dialog').close(); openPlayer(bk[1], anim.name); } }, '⛶ Plein écran') : null);
  } else if (a.decor && a.kind === 'objet') {
    let mode = a.decor.calque ? 'masques' : 'image';
    const holder = el('div', { class: 'dbox' }, decorView(a, mode));
    const toggle = el('button', {
      type: 'button', class: 'small', disabled: !a.decor.calque,
      onclick: () => {
        mode = mode === 'image' ? 'masques' : 'image';
        toggle.textContent = mode === 'image' ? 'Masques : non' : 'Masques : oui';
        holder.replaceChildren(decorView(a, mode));
      },
    }, mode === 'image' ? 'Masques : non' : 'Masques : oui');
    view = el('div', { class: 'ca-decor' }, holder, decorBadges(a.decor), toggle);
  } else if (a.decor && a.kind === 'sol') {
    view = el('div', { class: 'ca-sol' }, solTile(a), el('p', { class: 'muted', text: 'Tuile de sol : pas de masque (collision par case).' }));
  } else if (a.type === 'audio') {
    view = el('audio', { controls: true, preload: 'none', src: fileUrl(a.file) });
  } else if (a.preview) {
    view = el('div', { class: 'ca-img' + (a.smooth ? ' smooth' : '') }, el('img', { src: fileUrl(a.preview), alt: a.name, loading: 'lazy' }));
  }
  const list = el('div', { class: 'asset-comments' });
  const renderList = () => {
    const mine = state.comments.filter((c) => c.asset === a.id);
    list.replaceChildren(...(mine.length ? mine.map((c) => commentEl(c, false, renderList))
      : [el('p', { class: 'muted', text: 'Aucun commentaire sur cet asset.' })]));
  };
  renderList();
  // replaceChildren écrirait « null » : les blocs absents sont retirés.
  box.replaceChildren(...[
    el('h3', {}, 'Asset : ', el('a', { href: '#/assets/' + encodeURIComponent(a.id), onclick: (ev) => { ev.preventDefault(); openAsset(); }, text: a.name })),
    view || el('p', { class: 'muted', text: a.id }),
    el('p', { class: 'meta', text: `${a.id} · version ${a.version}` }),
    anim ? glisseNote(anim) : null,
    commentForm(a, () => (anim ? 'anim : ' + anim.name : ''), () => { renderList(); if (state.editing) loadFeed(state.editing.id); },
      state.editing ? state.editing.id : 0),
    list].filter(Boolean));
}

// ------------------------------------------------------- night shift

/** Chapeau : applique son night shift (case du détail) à tous ses descendants. */
async function nightToChildren() {
  const card = state.editing;
  if (!card) return;
  const night = $('cf-night').checked;
  const ids = [...familyIds(card.id)].filter((id) => id !== card.id && !!(cardById(id) || {}).night !== night);
  $('cf-night-children').disabled = true;
  setSaveState('en cours');
  const ok = await guarded(async () => {
    if (!!card.night !== night) await api('card_update', { method: 'POST', body: { id: card.id, night } });
    for (const id of ids) await api('card_update', { method: 'POST', body: { id, night } });
    await reloadCards();
    return true;
  });
  $('cf-night-children').disabled = false;
  setSaveState(ok ? 'ok' : 'erreur');
  if (!ok) return;
  toast(`Night shift ${night ? 'activé' : 'désactivé'} sur ${ids.length} enfant${ids.length > 1 ? 's' : ''}`);
  state.editing = cardById(card.id) || card;
  loadFeed(card.id);
  renderBoard();
}

// ------------------------------------------------------- tâches pixelforge (cards.jobs)

/** Tâches pixelforge d'une carte (liste écrite par le watcher), toujours un tableau d'objets. */
function cardJobs(c) {
  return c && Array.isArray(c.jobs) ? c.jobs.filter((j) => j && typeof j === 'object') : [];
}

/** Petit badge de tuile : tâche en cours (pending / running) ou en échec ; rien sinon. */
function jobsBadge(c) {
  const jobs = cardJobs(c);
  const failed = jobs.filter((j) => JOB_FAILED.has(j.status)).length;
  const running = jobs.filter((j) => JOB_RUNNING.has(j.status)).length;
  if (failed) return el('span', { class: 'badge job-failed', title: `${failed} tâche${failed > 1 ? 's' : ''} pixelforge en échec`, text: '⚠ pf' });
  if (running) return el('span', { class: 'badge job-run', title: `${running} tâche${running > 1 ? 's' : ''} pixelforge en cours`, text: '⚙ ' + running });
  return null;
}

/** Section « Tâches pixelforge » du détail : id court, rôle, libellé, statut, 📌 si gardée. */
function renderJobs(c) {
  const jobs = cardJobs(c);
  $('cf-jobs-box').hidden = !jobs.length;
  $('cf-jobs').replaceChildren(...jobs.map((j) => {
    const st = String(j.status || '?');
    const cls = JOB_FAILED.has(st) ? 'job-failed' : JOB_RUNNING.has(st) ? 'job-run' : st === 'succeeded' ? 'job-ok' : '';
    return el('li', { class: 'job' },
      el('code', { title: String(j.id || ''), text: String(j.id || '?').slice(0, 8) }),
      j.role ? el('span', { class: 'badge', text: String(j.role) }) : null,
      el('span', { class: 'job-label', text: String(j.label || '') }),
      el('span', { class: 'badge ' + cls, text: st }),
      j.keep ? el('span', { title: 'Gardée', text: '📌' }) : null);
  }));
}

// ------------------------------------------------------- QA : accepter / refuser

async function acceptCard(c) {
  const kids = [...familyIds(c.id)].filter((id) => id !== c.id && (cardById(id) || {}).status === 'qa').length;
  if (kids && !confirm(`Accepter « ${c.title} » et ses ${kids} enfant${kids > 1 ? 's' : ''} encore en QA ?`)) return;
  const r = await guarded(async () => {
    const res = await api('card_accept', { method: 'POST', body: { id: c.id } });
    await reloadCards();
    return res;
  });
  if (!r) return;
  toast(r.accepted.length > 1 ? `${r.accepted.length} cartes acceptées → Validé` : 'Acceptée → Validé');
  apresVerdict(c);
}

function openRefuse(c) {
  state.refusing = c;
  $('refuse-title').textContent = `Refuser « ${c.title} »`;
  $('rf-body').value = '';
  $('rf-error').textContent = '';
  $('refuse-dialog').showModal();
  $('rf-body').focus();
}

async function sendRefuse(ev) {
  ev.preventDefault();
  const c = state.refusing;
  const text = $('rf-body').value.trim();
  const refaire = (ev.submitter || {}).id === 'rf-redo';
  if (!c) return;
  if (!text) { $('rf-error').textContent = 'Dis ce qui ne va pas : c\'est la consigne pour refaire.'; return; }
  try {
    await api('card_refuse', { method: 'POST', body: { id: c.id, body: text, refaire } });
    await reloadCards();
  } catch (e) {
    $('rf-error').textContent = e.message;
    return;
  }
  $('refuse-dialog').close();
  toast(refaire ? 'Refusée → sommet du Todo, à refaire' : 'Refusée → sommet du Backlog, à retraiter');
  apresVerdict(c);
}

/** Après ✓ / ✗ : le détail de la carte jugée se ferme ; jugée depuis la recette de son chapeau
 *  (un élément), le chapeau reste ouvert et sa recette se redessine. */
function apresVerdict(c) {
  if ($('card-dialog').open) {
    if (state.editing && state.editing.id !== c.id) renderCardAsset();
    else $('card-dialog').close();
  }
  renderBoard();
}

async function deleteCard() {
  const card = state.editing;
  if (!card) return;
  const kids = childrenOf(card.id).length;
  if (!confirm(`Supprimer la carte #${card.id} ?` + (kids ? ` Ses ${kids} enfant(s) seront détachés, pas supprimés.` : ''))) return;
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
