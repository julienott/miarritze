// Miarritze Producer — catalogue (#/assets) : tous les éléments du jeu (animations des persos une
// par une, décor des trois cartes, règles, options, écrans…), avec leur statut tiré du kanban,
// plusieurs groupements (type, carte de jeu, perso, statut, zone), des filtres, et la fiche de
// chaque élément (visionneuse, cartes liées, commentaire d'amélioration, prompt, pixelforge).
'use strict';

const CAT_TYPES = [
  ['anim', 'Animations des persos'], ['profil', 'Profils des persos'], ['masque', 'Masques de tenue'],
  ['cachette', 'Cachettes'], ['sortie', 'Sorties'], ['objet', 'Objets du décor'], ['sol', 'Sols'],
  ['decor_anim', 'Animations du décor'], ['carte', 'Cartes de jeu (plans)'], ['regles', 'Règles'],
  ['option', 'Options de partie'], ['ecran', 'Écrans de menu'], ['donnees', 'Données (JSON)'],
  ['mannequin', 'Mannequin'], ['texture', 'Textures & modèles'], ['audio', 'Audio'], ['borroka', 'Borroka (archive)'],
];
const CAT_TYPE_LABEL = Object.fromEntries(CAT_TYPES);
const GROUPINGS = [['type', 'Type'], ['carte', 'Carte de jeu'], ['perso', 'Perso'], ['statut', 'Statut kanban'],
  ['zone', 'Zone de la carte'], ['aucun', 'Sans groupe']];
const CAT_FILTERS = [
  ['manquant', 'Pas encore fait'], ['rework', '↺ À retraiter'], ['qa', 'En QA'], ['refuse', 'Déjà refusé'],
  ['sans_masque', 'Sans masque'], ['provisoire', 'Provisoire'], ['sans_carte', 'Sans carte kanban'], ['avis', 'Avis ouverts'],
];
const GROUP_PAGE = 60;            // éléments affichés par groupe avant « Afficher les autres »
const BORROKA_CATS = new Set(['Combattants', 'VFX', 'Décors', 'Fonds & sprites', 'UI']);
const AUDIO_CATS = new Set(['Musique', 'SFX', 'Voix']);
const KIND_PERSO = { modele: 'profil validé', candidat: 'candidat', src: 'source', masque: 'masques de tenue' };

const cat = {
  q: '', group: 'type', type: '', map: '', filters: new Set(), masks: false, recap: false, more: new Set(),
};

function initCatalogue() {
  try {
    const s = JSON.parse(store('producer-catalogue') || '{}');
    Object.assign(cat, { group: s.group || 'type', type: s.type || '', map: s.map || '', masks: !!s.masks, recap: !!s.recap });
    cat.filters = new Set(s.filters || []);
  } catch (e) { /* réglages illisibles : défauts */ }
}

function saveCatalogue() {
  store('producer-catalogue', JSON.stringify({ group: cat.group, type: cat.type, map: cat.map, masks: cat.masks,
    recap: cat.recap, filters: [...cat.filters] }));
}

// ------------------------------------------------------------------ éléments

let itemsCache = { index: null, items: [], byKey: new Map() };

function decorType(d, kind) {
  if (kind === 'sol' || /^tuile/.test((d && d.type) || '')) return 'sol';
  if (kind === 'decor_anim') return 'decor_anim';
  if (d && d.categorie === 'cachette') return 'cachette';
  if (d && (d.categorie === 'sortie' || d.type === 'decal')) return 'sortie';
  return 'objet';
}

function zonesOfDecor(d) {
  const out = [];
  const add = (carte, zones) => { for (const z of zones || []) out.push(`${carte}|${z}`); };
  if (!d) return out;
  add(d.carte, d.zones);
  for (const r of d.reprises || []) add(r.carte, r.zones);
  return out;
}

/** Tous les éléments du catalogue (recalculés quand l'index change). */
function catalogueItems() {
  if (itemsCache.index === state.index) return itemsCache;
  const g = state.index.gordeka || {};
  const items = [];
  const mk = (a, type, extra = {}) => ({
    key: a.id, route: [a.id, ''], type, asset: a, assetId: a.id, detail: '', name: a.name, sub: '',
    cartes: [], zones: [], perso: '', missing: false, ...extra,
  });
  for (const a of state.index.assets) {
    if (a.cat === 'Persos') {
      if (a.kind === 'anim') continue;           // une entrée par animation, plus bas
      items.push(mk(a, a.kind === 'masque' ? 'masque' : 'profil', {
        perso: a.group, name: a.kind === 'candidat' ? a.name : `${persoName(a.group)} · ${KIND_PERSO[a.kind] || a.name}`,
        candidat: a.kind === 'candidat',
      }));
    } else if (a.cat === 'Décor') {
      const d = a.decor || {};
      const type = decorType(d, a.kind);
      items.push(mk(a, type, {
        cartes: d.cartes || (d.carte ? [d.carte] : []), zones: zonesOfDecor(d), sub: d.element || '',
        sansMasque: a.kind === 'objet' && !!d.sans_masque && type !== 'sol', provisoire: !!d.provisoire,
      }));
    } else if (a.cat === 'Carte') {
      items.push(mk(a, a.type === 'data' ? 'donnees' : 'carte', { cartes: [a.group] }));
    } else if (a.cat === 'Jeu') {
      items.push(mk(a, a.kind === 'regles' ? 'regles' : a.kind === 'option' ? 'option' : 'ecran',
        { name: a.name.replace(/^(Règles|Option|Écran) · /, '') }));
    } else if (a.cat === 'Mannequin') {
      items.push(mk(a, a.type === 'data' ? 'donnees' : 'mannequin'));
    } else if (a.cat === 'Textures & modèles') {
      items.push(mk(a, 'texture'));
    } else if (AUDIO_CATS.has(a.cat)) {
      items.push(mk(a, 'audio', { sub: a.cat }));
    } else {
      items.push(mk(a, 'borroka', { sub: a.cat }));
    }
  }
  // Animations : une entrée par animation attendue (présente ou manquante) de chaque perso.
  for (const pid of g.persos || []) {
    const aid = `gordeka/persos/${pid}/animations`;
    const a = state.assetsById.get(aid) || null;
    for (const s of gkSlots(pid)) {
      items.push({
        key: aid + '#' + s.name, route: [aid, s.name], type: 'anim', asset: a, assetId: aid, detail: s.name, anim: s.anim,
        perso: pid, name: `${persoName(pid)} · ${animLabel(s.name)}`, sub: s.name, missing: !s.anim, aVenir: s.a_venir,
        glisse: s.anim ? glisseOf(s.anim, true) : 0, cartes: [], zones: [],
      });
    }
  }
  // Décor sans image : une entrée « à venir » (carte du kanban retrouvée par son titre).
  for (const e of g.decor_a_venir || []) {
    const key = `a-venir/${e.carte}/${e.id}`;
    items.push({ key, route: [key, ''], type: decorType(e, ''), asset: null, assetId: '', detail: '', name: e.nom, sub: e.id,
      cartes: [e.carte], zones: zonesOfDecor(e), perso: '', missing: true, decorInfo: e });
  }
  for (const it of items) it.search = norm([it.name, it.sub, it.assetId, it.detail, CAT_TYPE_LABEL[it.type]].join(' '));
  itemsCache = { index: state.index, items, byKey: new Map(items.map((i) => [i.key, i])) };
  return itemsCache;
}

// Cartes retrouvées par leur titre : « <nom> », « <nom> : image », « <nom> : masque v3 »…
let titleCache = { cards: null, map: null };
function titleMap() {
  if (titleCache.cards === state.cards) return titleCache.map;
  const map = new Map();
  for (const c of state.cards) {
    const k = norm(c.title.split(' : ')[0].replace(/^décor · /i, ''));
    if (!map.has(k)) map.set(k, []);
    map.get(k).push(c);
  }
  titleCache = { cards: state.cards, map };
  return map;
}

/** Cartes d'un élément : liées par l'asset (et l'animation), par le build, ou par le titre. */
function itemCards(it) {
  const { direct, general } = cardsFor(it.assetId, it.detail);
  const byTitle = titleMap().get(norm(it.name)) || [];
  for (const c of byTitle) {
    if (direct.includes(c) || general.includes(c)) continue;
    // Une carte d'animation d'un autre élément du même asset n'est pas reprise.
    if (it.detail && c.asset === it.assetId && cardAnimName(c) && cardAnimName(c) !== it.detail) continue;
    direct.push(c);
  }
  return { direct, general };
}

function itemStatus(it) {
  return statusOfCards(itemCards(it).direct);
}

function passesFilters(it, info) {
  for (const f of cat.filters) {
    if (f === 'manquant' && !it.missing) return false;
    if (f === 'sans_masque' && !it.sansMasque) return false;
    if (f === 'provisoire' && !it.provisoire) return false;
    if (f === 'rework' && info.status !== 'rework') return false;
    if (f === 'qa' && !info.cards.some((c) => c.status === 'qa')) return false;
    if (f === 'refuse' && !info.cards.some((c) => (c.notes || []).some((n) => n.kind === 'refus'))) return false;
    if (f === 'sans_carte' && info.cards.length) return false;
    if (f === 'avis' && !(it.assetId && openCount(it.assetId))) return false;
  }
  return true;
}

function mapName(id) {
  const c = ((state.index.gordeka || {}).cartes || []).find((m) => m.id === id);
  if (!c) return id;
  return c.jouable ? c.nom : `${c.nom} (ancienne v${c.version || '?'})`;
}

// ------------------------------------------------------------------ rendu

function renderCatalogue() {
  stopPlayer();
  $('detail').hidden = true;
  $('cat-bar').hidden = false;
  const grid = $('grid');
  grid.hidden = false;
  grid.className = 'grid grouped';
  const { items } = catalogueItems();
  const words = norm(cat.q).split(/[\s·:,]+/).filter(Boolean);
  const shown = [];
  for (const it of items) {
    if (cat.type ? it.type !== cat.type : it.type === 'borroka') continue;
    if (cat.map && !it.cartes.includes(cat.map)) continue;
    if (words.length && !words.every((w) => it.search.includes(w))) continue;
    const { direct } = itemCards(it);
    const info = { cards: direct, status: statusOfCards(direct) };
    if (!passesFilters(it, info)) continue;
    shown.push([it, info]);
  }
  renderCatBar(shown.length);
  const groups = groupItems(shown);
  const blocks = [];
  if (cat.recap && state.index.gordeka) blocks.push(recapTable(state.index.gordeka.persos));
  if (!shown.length) blocks.push(el('p', { class: 'empty', text: 'Aucun élément ne correspond à ces filtres.' }));
  for (const gr of groups) blocks.push(groupSection(gr));
  grid.replaceChildren(...blocks);
}

function renderCatBar(count) {
  const bar = $('cat-bar');
  const search = el('input', { type: 'search', id: 'cat-search', value: cat.q, placeholder: 'Rechercher (louis, walk, fronton, gâteaux…)', 'aria-label': 'Rechercher' });
  let t = 0;
  search.addEventListener('input', () => {
    clearTimeout(t);
    t = setTimeout(() => {
      cat.q = search.value.trim();
      if (location.hash !== '#/assets' && location.hash !== '#/assets/') return;   // fiche ouverte entre-temps
      renderCatalogue();
      const s = $('cat-search');
      s.focus();
      s.setSelectionRange(s.value.length, s.value.length);
    }, 200);
  });
  const select = (id, label, opts, value, apply) => {
    const s = el('select', { id, 'aria-label': label }, opts.map(([v, txt]) => el('option', { value: v, text: txt })));
    s.value = value;
    s.classList.toggle('on', !!value && id !== 'cat-group');
    s.addEventListener('change', () => { apply(s.value); saveCatalogue(); renderCatalogue(); });
    return s;
  };
  const cartes = ((state.index.gordeka || {}).cartes || []).filter((c) => c.jouable);
  const chips = CAT_FILTERS.map(([k, label]) => el('button', {
    type: 'button', class: 'chip-btn' + (cat.filters.has(k) ? ' on' : ''), 'aria-pressed': cat.filters.has(k) ? 'true' : 'false',
    'data-filter': k,
    onclick: () => { if (cat.filters.has(k)) cat.filters.delete(k); else cat.filters.add(k); saveCatalogue(); renderCatalogue(); },
  }, label));
  bar.replaceChildren(
    el('div', { class: 'cat-row' },
      search,
      el('label', { class: 'inline' }, 'Grouper par',
        select('cat-group', 'Grouper par', GROUPINGS, cat.group, (v) => { cat.group = v; cat.more.clear(); })),
      select('cat-type', 'Type', [['', 'Tous les types'], ...CAT_TYPES], cat.type, (v) => { cat.type = v; }),
      select('cat-map', 'Carte de jeu', [['', 'Toutes les cartes'], ...cartes.map((c) => [c.id, c.nom])], cat.map, (v) => { cat.map = v; })),
    el('div', { class: 'cat-row chips' }, chips,
      el('span', { class: 'spacer' }),
      el('button', { type: 'button', class: 'chip-btn' + (cat.masks ? ' on' : ''), title: 'Masques du décor toujours visibles (sinon au survol)',
        onclick: () => { cat.masks = !cat.masks; saveCatalogue(); renderCatalogue(); } }, 'Masques visibles'),
      el('button', { type: 'button', class: 'chip-btn' + (cat.recap ? ' on' : ''), title: 'Tableau perso × animation',
        onclick: () => { cat.recap = !cat.recap; saveCatalogue(); renderCatalogue(); } }, 'Récap animations'),
      el('span', { class: 'muted cat-count', text: `${count} élément${count > 1 ? 's' : ''}` })));
}

/** Groupes [{key, title, items, head?}] selon le groupement choisi. */
function groupItems(shown) {
  const g = state.index.gordeka || {};
  const groups = new Map();
  const put = (key, title, pair, extra) => {
    if (!groups.has(key)) groups.set(key, { key, title, items: [], ...extra });
    groups.get(key).items.push(pair);
  };
  for (const pair of shown) {
    const [it, info] = pair;
    switch (cat.group) {
      case 'type': put(it.type, CAT_TYPE_LABEL[it.type], pair); break;
      case 'carte':
        if (it.cartes.length) for (const m of it.cartes) put('m:' + m, mapName(m), pair, { map: m });
        else put('commun', it.perso || it.type === 'anim' ? 'Persos (toutes les cartes)' : 'Commun à toutes les cartes', pair);
        break;
      case 'perso': put(it.perso ? 'p:' + it.perso : 'autres', it.perso ? persoName(it.perso) : 'Sans perso', pair, { perso: it.perso }); break;
      case 'statut': put('s:' + info.status, ITEM_STATUS_LABEL[info.status], pair, { status: info.status }); break;
      case 'zone':
        if (it.zones.length) {
          for (const z of it.zones) { const [m, name] = z.split('|'); put('z:' + z, `${mapName(m)} · ${name}`, pair); }
        } else put('sans-zone', 'Sans zone', pair);
        break;
      default: put('tout', 'Tous les éléments', pair);
    }
  }
  let list = [...groups.values()];
  const order = {
    type: (gr) => CAT_TYPES.findIndex(([k]) => k === gr.key),
    carte: (gr) => (gr.map ? (g.cartes || []).findIndex((c) => c.id === gr.map) : 99),
    perso: (gr) => (gr.perso ? (g.persos || []).indexOf(gr.perso) : 999),
    statut: (gr) => STATUS_RANK[gr.status],
  }[cat.group];
  if (order) list.sort((a, b) => order(a) - order(b));
  else if (cat.group === 'zone') list.sort((a, b) => (a.key === 'sans-zone') - (b.key === 'sans-zone') || a.title.localeCompare(b.title, 'fr'));
  return list;
}

/** Petits compteurs par statut, en tête d'un groupe. */
function statusSummary(pairs) {
  const n = {};
  for (const [, info] of pairs) n[info.status] = (n[info.status] || 0) + 1;
  return el('span', { class: 'gsum' }, ITEM_STATUSES.filter(([k]) => n[k]).map(([k]) =>
    el('span', { class: 'pill small p-' + k, title: ITEM_STATUS_LABEL[k], text: `${n[k]} ${k === 'none' ? 'sans carte' : ITEM_STATUS_LABEL[k].replace('QA : à valider', 'QA')}` })));
}

function groupSection(gr) {
  const open = store('producer-cat-closed-' + gr.key) !== '1';
  const all = gr.items;
  const more = cat.more.has(gr.key);
  const visible = more ? all : all.slice(0, GROUP_PAGE);
  let face = null;
  let extra = null;
  if (gr.perso) {
    const f = faceOf('Persos', gr.perso);
    face = f ? el('img', { src: fileUrl(f.preview), alt: '', class: 'smooth' }) : null;
    const slots = gkSlots(gr.perso);
    extra = el('span', { class: 'muted', text: `${slots.filter((s) => s.anim).length}/${slots.length} animations` });
  }
  if (gr.map) extra = el('a', { href: '#/jeu/cartes', class: 'small', text: 'plan et zones ›' });
  const det = el('details', { class: 'group cgroup', open: open || null, 'data-perso': gr.perso || null, 'data-group': gr.key },
    el('summary', { class: 'group-head' }, face, el('span', { class: 'group-name', text: gr.title }),
      el('span', { class: 'muted', text: String(all.length) }), extra, statusSummary(all)),
    el('div', { class: 'citems' }, visible.map(([it, info]) => catTile(it, info))),
    all.length > visible.length ? el('button', { type: 'button', class: 'small more', onclick: () => { cat.more.add(gr.key); renderCatalogue(); } },
      `Afficher les ${all.length - visible.length} autres`) : null);
  det.addEventListener('toggle', () => store('producer-cat-closed-' + gr.key, det.open ? '0' : '1'));
  return det;
}

function itemHash(it) {
  return '#/assets/' + encodeURIComponent(it.route[0]) + (it.route[1] ? '/' + encodeURIComponent(it.route[1]) : '');
}

/** Aperçu d'un élément : animation (au survol), décor avec masques (au survol), sol, gameplay… */
function itemThumb(it, host) {
  const a = it.asset;
  const box = el('div', { class: 'cthumb' + (a && a.smooth ? ' smooth' : '') });
  if (it.type === 'anim') {
    if (it.anim) {
      const mini = miniAnim(it.anim, 0);
      box.append(mini);
      hoverMini(host, mini);
    } else box.append(el('span', { class: 'cmissing', text: it.aVenir ? 'à venir' : 'manquante' }));
    return box;
  }
  if (!a) { box.append(el('span', { class: 'cmissing', text: 'pas d\'image' })); return box; }
  if (a.type === 'sprite' && a.anims && a.anims.length) {
    const mini = miniAnim(a.anims.find((x) => x.name === 'idle') || a.anims[0], 0);
    box.append(mini);
    hoverMini(host, mini);
    return box;
  }
  if (a.kind === 'sol') { box.classList.add('checker'); box.append(solTile(a)); return box; }
  if (a.decor && a.kind === 'objet') {
    box.classList.add('checker', 'dthumb');
    const base = el('img', { src: fileUrl(a.file), alt: '', loading: 'lazy', decoding: 'async' });
    box.append(base);
    if (a.decor.calque) {
      const calque = el('img', { class: 'calque', alt: '', decoding: 'async', src: cat.masks ? fileUrl(a.decor.calque) : null });
      box.append(calque);
      box.classList.toggle('masks', cat.masks);
      const show = (on) => {
        if (on && !calque.getAttribute('src')) calque.src = fileUrl(a.decor.calque);
        box.classList.toggle('masks', on || cat.masks);
      };
      host.addEventListener('pointerenter', (ev) => { if (ev.pointerType === 'mouse') show(true); });
      host.addEventListener('pointerleave', (ev) => { if (ev.pointerType === 'mouse') show(false); });
    }
    return box;
  }
  if (a.type === 'jeu') {
    const j = a.jeu || {};
    if (j.capture) box.append(el('img', { src: fileUrl(j.capture.file), alt: '', loading: 'lazy' }));
    else box.append(el('span', { class: 'cjeu', text: j.sorte === 'regles' ? `${(j.items || []).length} réglages`
      : j.sorte === 'option' ? `⚙ ${j.groupe || 'option'}` : '▭ ' + (j.nom || 'écran') }));
    return box;
  }
  if (a.type === 'audio') { box.append(el('span', { class: 'cjeu', text: '♪' })); return box; }
  if (a.type === 'data') { box.append(el('span', { class: 'cjeu', text: '{ }' })); return box; }
  box.append(el('img', { src: fileUrl(a.preview), alt: '', loading: 'lazy', decoding: 'async' }));
  return box;
}

function catTile(it, info) {
  const n = it.assetId ? state.comments.filter((c) => c.asset === it.assetId && c.status === 'open'
    && (!it.detail || (c.context || '').includes(it.detail))).length : 0;
  const host = el('a', { class: `citem t-${it.type} s-${info.status}` + (it.missing ? ' missing' : ''), href: itemHash(it), 'data-key': it.key });
  host.append(itemThumb(it, host),
    el('span', { class: 'cinfo' },
      el('span', { class: 'cname', text: it.name }),
      it.sub && it.sub !== it.name ? el('span', { class: 'csub muted', text: it.sub }) : null,
      el('span', { class: 'cbadges' },
        statusPill(info.status, info.cards.map((c) => `#${c.id} ${c.title} (${STATUS_LABEL[c.status]})`).join('\n')),
        it.missing ? el('span', { class: 'badge warn', text: it.aVenir ? 'à venir' : 'à faire' }) : null,
        it.sansMasque ? el('span', { class: 'badge src-aucun', text: 'sans masque' }) : null,
        it.provisoire ? el('span', { class: 'badge', text: 'provisoire' }) : null,
        it.glisse >= 6 ? el('span', { class: 'badge warn', title: `glisse de ${it.glisse} px dans la planche`, text: '⚠ glisse' }) : null,
        n ? el('span', { class: 'badge amelioration', text: `💬 ${n}` }) : null,
        it.cartes.length > 1 ? el('span', { class: 'badge', title: it.cartes.map(mapName).join(', '), text: `${it.cartes.length} cartes` }) : null)));
  return host;
}

// ------------------------------------------------------------------ fiche

function itemFromRoute(id, detail) {
  const { byKey } = catalogueItems();
  if (detail) return byKey.get(id + '#' + detail) || null;
  return byKey.get(id) || null;
}

/** Fiche d'un élément : visionneuse à gauche, pilotage à droite (dessous sur iPhone). */
function showFiche(id, detail) {
  const it = itemFromRoute(id, detail);
  const a = state.assetsById.get(id) || null;
  const ref = {};
  const side = ficheSide(it, a, detail, ref);
  const pill = it ? statusPill(itemStatus(it)) : null;
  if (a) {
    showDetail(a, {
      detail, side, pill, contextRef: ref,
      title: it ? it.name : a.name,
      onAnim: a.id.startsWith('gordeka/persos/') && a.kind === 'anim'
        ? (name) => { location.hash = '#/assets/' + encodeURIComponent(a.id) + '/' + encodeURIComponent(name); } : null,
    });
    window.scrollTo(0, 0);
    return;
  }
  // Élément sans asset : animation manquante, décor sans image.
  stopPlayer();
  $('grid').hidden = true;
  $('cat-bar').hidden = true;
  const d = $('detail');
  d.hidden = false;
  if (!it) {
    d.replaceChildren(el('p', { class: 'empty', text: 'Élément introuvable dans le build actuel.' }),
      el('a', { href: '#/assets', text: '← Catalogue' }));
    return;
  }
  d.replaceChildren(
    el('div', { class: 'detail-head' },
      el('button', { type: 'button', class: 'small', onclick: () => { location.hash = '#/assets'; } }, '← Catalogue'),
      el('h2', { text: it.name }), pill),
    el('div', { class: 'fiche' },
      el('div', { class: 'fiche-main' },
        el('div', { class: 'stage placeholder' }, el('span', { text: it.type === 'anim' ? (it.aVenir ? 'Clip sur mesure à venir' : 'Animation pas encore générée') : 'Pas encore d\'image' })),
        el('p', { class: 'meta', text: it.decorInfo ? `${it.decorInfo.id} · ${it.decorInfo.categorie} · ${mapName(it.decorInfo.carte)}` : `${it.assetId} · ${it.detail}` })),
      side));
  window.scrollTo(0, 0);
}

function infoList(pairs) {
  const rows = pairs.filter(([, v]) => v !== null && v !== undefined && v !== '' && !(Array.isArray(v) && !v.length));
  return el('dl', { class: 'credits fiche-dl' }, rows.flatMap(([k, v]) => [el('dt', { text: k }),
    el('dd', {}, v instanceof Node ? v : Array.isArray(v) ? v.join(', ') : String(v))]));
}

function ficheSide(it, a, detail, ref) {
  const side = el('aside', { class: 'fiche-side' });
  const g = state.index.gordeka || {};
  const assetId = a ? a.id : it ? it.assetId : '';
  const pid = it ? it.perso : '';
  // 1. Pilotage : cartes liées et commentaire.
  const persoHat = pid ? state.cards.find((c) => c.type === 'perso' && norm(c.title) === norm('Perso : ' + persoName(pid))) : null;
  side.append(el('h3', { text: 'Kanban' }), pilotBlock({
    asset: assetId, detail: detail || '',
    title: it && !a ? (it.type === 'anim' ? it.name : `${it.name} : image`) : it ? `${it.name} : amélioration` : '',
    type: it && it.type === 'anim' ? 'animation' : it && ['regles', 'option', 'ecran'].includes(it.type) ? 'gameplay' : '',
    parent: persoHat ? persoHat.id : 0,
    extraCards: () => (it ? itemCards(it).direct : []),
    context: () => (ref.get ? ref.get() : detail ? 'anim : ' + detail : ''),
    after: () => { if (ref.comments) ref.comments(); if (it) { const p = $('detail').querySelector('.detail-head .pill'); if (p) p.replaceWith(statusPill(itemStatus(it))); } },
  }));
  // 2. Infos.
  const d = (a && a.decor) || (it && it.decorInfo) || null;
  const mapLinks = (it ? it.cartes : []).map((m) => el('a', { href: '#/jeu/cartes', text: mapName(m) }));
  side.append(el('h3', { text: 'Infos' }), infoList([
    ['Type', it ? CAT_TYPE_LABEL[it.type] : a ? a.cat : ''],
    ['Perso', pid ? persoName(pid) : ''],
    ['Animation', detail ? `${detail} (${animLabel(detail)})` : ''],
    ['Cartes de jeu', mapLinks.length ? el('span', { class: 'links' }, mapLinks) : ''],
    ['Zones', d ? (d.zones || []).join(', ') : ''],
    ['Repris dans', d && d.reprises ? d.reprises.map((r) => `${mapName(r.carte)} (${r.nom})`).join(', ') : ''],
    ['Taille', d && d.cases ? `${d.cases.join(' × ')} cases` : a && a.w ? `${a.w} × ${a.h} px` : ''],
    ['Provisoire', d && d.provisoire ? 'oui : dessiné par le code ou placeholder, à remplacer' : ''],
    ['Masques', d && d.source ? (SOURCE_LABEL[d.source] || d.source) + (d.masques && d.masques.length ? ` (${d.masques.join(', ')})` : '') : ''],
    ['Animation prévue', d && d.anim ? d.anim : ''],
    ['Version', a ? a.version : ''],
    ['Id', assetId || (it ? it.key : '')],
  ]));
  // 3. Prompt utilisé (et retouche de recette).
  const prompt = promptBlock(it, a, detail, d);
  if (prompt) side.append(prompt);
  // 4. Tâches pixelforge.
  const tasks = ((g.pixelforge || {})[detail ? `${assetId}#${detail}` : assetId] || []);
  if (tasks.length) {
    side.append(el('h3', { text: 'Pixelforge' }), el('ul', { class: 'tasks' }, tasks.map((t) => el('li', {},
      el('code', { text: t.tid.slice(0, 8) }), ' ', t.quoi || '', t.style ? el('span', { class: 'muted', text: ' · ' + t.style }) : null,
      t.statut ? el('span', { class: 'badge', text: t.statut }) : null, t.date ? el('span', { class: 'muted', text: ' · ' + t.date }) : null,
      t.carte ? el('span', { class: 'muted', text: ' · carte #' + t.carte }) : null))));
  }
  // 5. Versions vues dans les commentaires.
  if (a) {
    const vs = new Map();
    for (const c of state.comments.filter((x) => x.asset === a.id)) {
      const v = vs.get(c.version) || { n: 0, first: c.created_at };
      v.n++; v.first = Math.min(v.first, c.created_at);
      vs.set(c.version, v);
    }
    side.append(el('h3', { text: 'Versions' }), el('ul', { class: 'tasks' },
      el('li', {}, el('code', { text: a.version }), ' version actuelle · build ', el('code', { text: state.index.commit || '?' }),
        isFresh(a.id) ? el('span', { class: 'fresh', text: '↻ nouvelle' }) : null),
      [...vs].filter(([v]) => v !== a.version).map(([v, x]) => el('li', { class: 'muted' },
        el('code', { text: v }), ` version précédente · ${x.n} commentaire${x.n > 1 ? 's' : ''} depuis le ${fmtDate(x.first)}`))));
  }
  // 6. Fil des cartes liées (commentaires et refus), du plus récent au plus ancien.
  if (it) {
    const notes = itemCards(it).direct.flatMap((c) => (c.notes || []).map((n) => ({ ...n, card: c })))
      .sort((x, y) => y.created_at - x.created_at).slice(0, 12);
    if (notes.length) {
      side.append(el('h3', { text: 'Fil des cartes' }), el('div', { class: 'feed' }, notes.map((n) => el('div', {
        class: 'note ' + (n.kind === 'refus' ? 'refus' : n.author),
      }, el('strong', { text: `${n.kind === 'refus' ? '✗ ' : ''}${AUTHOR_LABEL[n.author] || n.author} · ${fmtDate(n.created_at)} · #${n.card.id}` }),
      el('br'), n.body))));
    }
  }
  return side;
}

function promptBlock(it, a, detail, d) {
  const g = state.index.gordeka || {};
  const parts = [];
  const retouches = g.retouches || {};
  if (it && it.type === 'anim' && detail) {
    const pa = g.prompts_anims || {};
    const an = (pa.animations || {})[detail];
    if (an) parts.push(['Action', an.action], ['Expression', an.expression]);
    if ((pa.persos || {})[it.perso]) parts.push(['Perso', pa.persos[it.perso]]);
    if (retouches[`perso/${it.perso}/${detail}`]) parts.push(['Retouche de recette', retouches[`perso/${it.perso}/${detail}`]]);
    if (pa.regles_communes) parts.push(['Consigne commune', pa.regles_communes]);
  } else if (d) {
    if (d.prompt) parts.push(['Prompt de l\'élément', d.prompt]);
    const r = Object.entries(retouches).filter(([k]) => k.startsWith(`decor/${d.element}/`)).map(([, v]) => v);
    if (r.length) parts.push(['Retouche de recette', r.join('\n')]);
    const style = (g.prompts_decor_style || {})[d.carte];
    if (style) parts.push(['Style commun de la carte', style]);
  }
  if (!parts.length) return null;
  return el('details', { class: 'prompt' }, el('summary', {}, el('h3', { text: 'Prompt utilisé' })),
    el('dl', { class: 'credits fiche-dl' }, parts.flatMap(([k, v]) => [el('dt', { text: k }), el('dd', { class: 'prompt-text', text: v })])));
}
