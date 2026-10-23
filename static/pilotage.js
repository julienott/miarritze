// Miarritze Producer — outils communs du pilotage : liens assets ↔ cartes du kanban, statut d'un
// asset tiré du kanban, pastilles, jalons, texte markdown simple (sans HTML), et le bloc
// « cartes liées + commentaire » posé sur un asset, une règle, un écran, une carte de jeu.
// Chargé après app.js (mêmes globales : state, el, api, $…). Aucun innerHTML.
'use strict';

// Statut d'un asset, du plus urgent au plus calme : refusé à retraiter, à valider, en cours…
const ITEM_STATUSES = [
  ['rework', '↺ À retraiter'], ['qa', 'QA : à valider'], ['doing', 'En cours'], ['todo', 'Todo'],
  ['backlog', 'Backlog'], ['done', 'Fait'], ['none', 'Sans carte'],
];
const ITEM_STATUS_LABEL = Object.fromEntries(ITEM_STATUSES);
const STATUS_RANK = Object.fromEntries(ITEM_STATUSES.map(([k], i) => [k, i]));

/** Nom affiché d'un perso (Maïa, Karramarro…). */
function persoName(pid) {
  const noms = (state.index && state.index.blackout && state.index.blackout.noms) || {};
  return noms[pid] || (pid ? pid.charAt(0).toUpperCase() + pid.slice(1) : '');
}

/** Libellé d'une animation (titres des cartes « Louis · marche »). */
function animLabel(name) {
  const a = ((state.index && state.index.blackout && state.index.blackout.anims) || []).find((x) => x.name === name);
  return a && a.libelle ? a.libelle : name;
}

const norm = (s) => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

// ----------------------------------------------------------------- liens

let linkCache = { cards: null, index: null, map: null };

/**
 * Cartes liées à chaque asset : champ asset de la carte, et liens du build (tâches des cartes
 * Plage / Parc Mazon / décor de nuit, options de partie). Recalculé quand les cartes ou l'index
 * changent (comparaison d'identité des tableaux).
 */
function linkMap() {
  if (linkCache.cards === state.cards && linkCache.index === state.index && linkCache.map) return linkCache.map;
  const byAsset = new Map();
  const push = (k, c) => {
    if (!k || !c) return;
    if (!byAsset.has(k)) byAsset.set(k, []);
    const l = byAsset.get(k);
    if (!l.includes(c)) l.push(c);
  };
  const byId = new Map(state.cards.map((c) => [c.id, c]));
  for (const c of state.cards) push(c.asset, c);
  const liens = (state.index && state.index.blackout && state.index.blackout.liens) || {};
  for (const [aid, ids] of Object.entries(liens)) for (const id of ids) push(aid, byId.get(id));
  linkCache = { cards: state.cards, index: state.index, map: byAsset };
  return byAsset;
}

/** La carte vise-t-elle une animation précise (détail, ou titre « … · <libellé> ») ? Renvoie son nom. */
function cardAnimName(c) {
  if (c.detail) return c.detail;
  const t = norm(c.title);
  for (const a of ((state.index.blackout || {}).anims || [])) {
    for (const l of [a.libelle, a.name]) {
      if (l && t.endsWith(' · ' + norm(l))) return a.name;
    }
  }
  return '';
}

/**
 * Cartes d'un asset (et d'une animation) : `direct` (la carte parle de cet élément), `general`
 * (carte de tout l'asset, ex. « Perso : Louis » pour une de ses animations).
 */
function cardsFor(assetId, detail) {
  if (!assetId) return { direct: [], general: [] };
  const all = linkMap().get(assetId) || [];
  if (!detail) return { direct: all.slice(), general: [] };
  const direct = [];
  const general = [];
  for (const c of all) {
    const n = cardAnimName(c);
    if (n === detail) direct.push(c);
    else if (!n) general.push(c);
  }
  return { direct, general };
}

/** Statut d'un ensemble de cartes : refus en cours > QA > Doing > Todo > Backlog > Done ; aucune = « none ». */
function statusOfCards(cards) {
  if (!cards.length) return 'none';
  if (cards.some((c) => c.rework)) return 'rework';
  let best = 'done';
  for (const c of cards) if (STATUS_RANK[c.status] < STATUS_RANK[best]) best = c.status;
  return best;
}

/** Dernier refus (note « refus ») parmi les cartes, ou null. */
function lastRefusal(cards) {
  let last = null;
  for (const c of cards) {
    for (const n of c.notes || []) {
      if (n.kind === 'refus' && (!last || n.created_at > last.created_at)) last = { ...n, card: c };
    }
  }
  return last;
}

function statusPill(st, extra) {
  return el('span', { class: 'pill p-' + st, title: extra || null, text: ITEM_STATUS_LABEL[st] || STATUS_LABEL[st] || st });
}

/** Pastille de colonne d'une carte (Backlog… Done, ↺ si refusée). */
function cardPill(c) {
  return statusPill(c.rework ? 'rework' : c.status);
}

// ----------------------------------------------------------------- jalons

async function reloadMilestones() {
  const r = await api('milestones');
  state.milestones = r.milestones;
}

function milestoneById(id) {
  return (state.milestones || []).find((m) => m.id === id) || null;
}

/** Jalon d'une carte : le sien, ou celui du plus proche chapeau qui en a un. */
function milestoneOf(c) {
  for (let cur = c, g = 0; cur && g < 10; g++) {
    if (cur.milestone_id) return cur.milestone_id;
    cur = cur.parent_id ? cardById(cur.parent_id) : null;
  }
  return null;
}

function todayIso() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function fmtDue(due) {
  if (!due) return '';
  const [y, m, d] = due.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' });
}

function dueBadge(due, done) {
  if (!due) return null;
  const late = !done && due < todayIso();
  return el('span', { class: 'badge due' + (late ? ' late' : ''), title: late ? 'Échéance dépassée' : 'Échéance', text: '⏱ ' + fmtDue(due) });
}

/** Feuilles (cartes sans enfant) de la famille d'une carte, elle comprise si c'est une feuille. */
function leavesOf(id) {
  return [...familyIds(id)].map(cardById).filter((c) => c && !c.children);
}

/** Barre empilée Done / QA / Doing / Todo / Backlog d'une liste de cartes ; renvoie [barre, résumé]. */
function stackBar(cards) {
  const n = cards.length || 1;
  const count = (s) => cards.filter((c) => c.status === s).length;
  const bar = el('div', { class: 'stack', role: 'img' });
  const parts = [['done', count('done')], ['qa', count('qa')], ['doing', count('doing')], ['todo', count('todo')], ['backlog', count('backlog')]];
  for (const [s, k] of parts) {
    if (!k) continue;
    const seg = el('span', { class: 'seg-' + s, title: `${STATUS_LABEL[s]} : ${k}` });
    seg.style.width = (100 * k / n) + '%';
    bar.append(seg);
  }
  const done = count('done');
  const qa = count('qa');
  bar.setAttribute('aria-label', `${done} faites, ${qa} en QA sur ${cards.length}`);
  const pct = cards.length ? Math.round(100 * (done + qa) / cards.length) : 0;
  return [bar, `${done} faites · ${qa} en QA · ${cards.length} en tout (${pct} %)`];
}

// ----------------------------------------------------------------- markdown simple

/** Texte en ligne : **gras**, `code`, liens https (texte seulement, jamais de HTML). */
function mdInline(text) {
  const out = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`|\*[^*\s][^*]*\*)/g;
  let pos = 0;
  for (const m of text.matchAll(re)) {
    if (m.index > pos) out.push(text.slice(pos, m.index));
    const t = m[0];
    if (t.startsWith('**')) out.push(el('strong', { text: t.slice(2, -2) }));
    else if (t.startsWith('`')) out.push(el('code', { text: t.slice(1, -1) }));
    else out.push(el('em', { text: t.slice(1, -1) }));
    pos = m.index + t.length;
  }
  if (pos < text.length) out.push(text.slice(pos));
  return out;
}

/** Markdown réduit (titres ###, listes, tableaux, paragraphes) en nœuds DOM. */
function md(text) {
  const nodes = [];
  const lines = String(text || '').split('\n');
  let i = 0;
  while (i < lines.length) {
    const ln = lines[i];
    if (!ln.trim()) { i++; continue; }
    if (/^#{2,4} /.test(ln)) {
      nodes.push(el('h4', { class: 'md-h' }, mdInline(ln.replace(/^#+ /, ''))));
      i++;
    } else if (ln.startsWith('|')) {
      const rows = [];
      while (i < lines.length && lines[i].startsWith('|')) {
        const cells = lines[i].trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
        if (!cells.every((c) => /^[-: ]*$/.test(c))) rows.push(cells);
        i++;
      }
      const [head, ...body] = rows;
      nodes.push(el('div', { class: 'md-table' }, el('table', {},
        el('thead', {}, el('tr', {}, head.map((c) => el('th', {}, mdInline(c))))),
        el('tbody', {}, body.map((r) => el('tr', {}, r.map((c) => el('td', {}, mdInline(c)))))))));
    } else if (/^\s*[-*] /.test(ln)) {
      const items = [];
      while (i < lines.length && (/^\s*[-*] /.test(lines[i]) || (/^\s{2,}\S/.test(lines[i]) && items.length))) {
        if (/^\s*[-*] /.test(lines[i])) items.push(lines[i].replace(/^\s*[-*] /, ''));
        else items[items.length - 1] += ' ' + lines[i].trim();
        i++;
      }
      nodes.push(el('ul', { class: 'md-ul' }, items.map((t) => el('li', {}, mdInline(t)))));
    } else {
      const para = [];
      while (i < lines.length && lines[i].trim() && !/^(#{2,4} |\||\s*[-*] )/.test(lines[i])) { para.push(lines[i].trim()); i++; }
      nodes.push(el('p', { class: 'md-p' }, mdInline(para.join(' '))));
    }
  }
  return nodes;
}

// ------------------------------------------------- bloc « cartes liées + commentaire »

/** Ligne d'une carte liée : pastille, titre, #id ; ✓ / ✗ si elle est en QA. */
function linkedCardRow(c, after) {
  const qa = c.status === 'qa' ? [
    el('button', { type: 'button', class: 'small accept', title: 'Accepter', 'aria-label': 'Accepter', onclick: async (ev) => { ev.stopPropagation(); await acceptCard(c); if (after) after(); } }, '✓'),
    el('button', { type: 'button', class: 'small refuse', title: 'Refuser', 'aria-label': 'Refuser', onclick: (ev) => { ev.stopPropagation(); openRefuse(c); } }, '✗'),
  ] : [];
  return el('li', { class: 'lcard' },
    el('button', { type: 'button', class: 'lcard-open', onclick: () => openCardDialog(c, '') },
      cardPill(c), el('span', { class: 'lcard-title', text: c.title }), el('span', { class: 'muted', text: '#' + c.id }),
      c.night ? el('span', { class: 'badge night', text: '🌙' }) : null, dueBadge(c.due, c.status === 'done')),
    qa.length ? el('span', { class: 'lcard-qa' }, qa) : null);
}

/**
 * Bloc de pilotage d'un élément : cartes liées (directes puis générales), dernier refus, et
 * formulaire « Amélioration / Validé » qui passe par asset_comment (reporté sur la carte choisie,
 * ou nouvelle carte en Backlog). `opts` : {asset, detail, title, type, parent, context, after,
 * extraCards (cartes suggérées), compact}.
 */
function pilotBlock(opts) {
  const box = el('div', { class: 'pilot' + (opts.compact ? ' compact' : '') });
  const render = () => {
    const { direct, general } = cardsFor(opts.asset, opts.detail);
    for (const c of opts.extraCards ? opts.extraCards() : []) if (!direct.includes(c)) direct.push(c);
    const st = statusOfCards(direct);
    const refus = lastRefusal(direct.filter((c) => c.rework));
    const open = direct.filter((c) => c.status !== 'done');
    // Carte proposée : la plus avancée des cartes ouvertes ; sinon nouvelle carte.
    const sorted = open.slice().sort((a, b) => STATUS_RANK[a.rework ? 'rework' : a.status] - STATUS_RANK[b.rework ? 'rework' : b.status]);
    const target = el('select', { 'aria-label': 'Carte où reporter le commentaire' },
      sorted.map((c) => el('option', { value: c.id, text: `#${c.id} ${c.title} (${STATUS_LABEL[c.status]})` })),
      el('option', { value: '0', text: '+ Nouvelle carte en Backlog' }));
    let kind = 'amelioration';
    const text = el('textarea', { rows: opts.compact ? 2 : 3, maxlength: 8000, placeholder: 'Ce qu\'il faudrait améliorer (ou pourquoi c\'est bon)…', 'aria-label': 'Commentaire' });
    const kinds = ['amelioration', 'valide'].map((k) => el('button', {
      type: 'button', class: 'small ' + k + (k === kind ? ' on' : ''), 'data-kind': k,
      onclick: () => { kind = k; for (const b of kinds) b.classList.toggle('on', b.dataset.kind === k); },
    }, KIND_LABEL[k]));
    const send = el('button', { type: 'submit', class: 'small primary' }, 'Envoyer');
    const form = el('form', { class: 'pilot-form' },
      el('div', { class: 'kind-pick' }, kinds), text,
      el('div', { class: 'row pilot-send' }, el('label', { class: 'inline grow' }, 'Sur ', target), send));
    form.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      if (kind === 'amelioration' && !text.value.trim()) { toast('Décris l\'amélioration souhaitée'); return; }
      send.disabled = true;
      const body = { body: text.value.trim(), kind, card: Number(target.value) || 'new' };
      if (opts.asset && state.assetsById.has(opts.asset)) body.asset = opts.asset;
      if (opts.detail) body.detail = opts.detail;
      if (body.card === 'new') {
        if (opts.title) body.title = opts.title;
        if (opts.type) body.type = opts.type;
        if (opts.parent) body.parent = opts.parent;
      }
      if (opts.context) body.context = opts.context();
      const r = await guarded(async () => {
        const res = await api('asset_comment', { method: 'POST', body });
        await Promise.all([reloadCards(), reloadComments()]);
        return res;
      });
      send.disabled = false;
      if (!r) return;
      text.value = '';
      toast(r.created ? `Carte #${r.card} créée dans le Backlog` : r.card ? `Reporté sur la carte #${r.card}` : 'Commentaire enregistré');
      render();
      if (opts.after) opts.after();
    });
    if (!body0(direct, general)) target.value = '0';
    // replaceChildren écrirait « null » : les blocs absents sont retirés.
    box.replaceChildren(...[
      el('div', { class: 'pilot-head' }, statusPill(st), refus ? el('span', { class: 'muted small', text: 'refusée le ' + fmtDate(refus.created_at) }) : null),
      refus ? el('p', { class: 'note refus' }, el('strong', { text: '✗ Dernier refus : ' }), refus.body) : null,
      direct.length ? el('ul', { class: 'lcards' }, direct.map((c) => linkedCardRow(c, render)))
        : el('p', { class: 'muted small', text: 'Aucune carte du kanban ne parle de cet élément.' }),
      general.length ? el('details', { class: 'lgeneral' }, el('summary', { text: `Aussi lié (${general.length})` }),
        el('ul', { class: 'lcards' }, general.map((c) => linkedCardRow(c, render)))) : null,
      form].filter(Boolean));
  };
  // Au moins une carte ouverte à proposer ?
  const body0 = (direct) => direct.some((c) => c.status !== 'done');
  render();
  box.refresh = render;
  return box;
}
