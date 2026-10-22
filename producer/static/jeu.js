// Miarritze Producer — section Jeu (#/jeu/<onglet>) : règles lisibles (rules.json), options de
// partie validées, écrans de menu (rôle, capture), cartes de jeu (plan, zones, sorties, cachettes,
// chiffres d'équilibrage) et bilans d'équilibrage. Chaque élément est relié à ses cartes du kanban
// et commentable (asset `jeu/…`, ou l'aperçu de la carte de jeu).
'use strict';

const JEU_TABS = [['regles', 'Règles'], ['options', 'Options de partie'], ['ecrans', 'Écrans'], ['cartes', 'Cartes de jeu'],
  ['equilibrage', 'Équilibrage']];

function initJeu() { /* rien à brancher : tout est rendu à l'ouverture */ }

function renderJeu(sub) {
  const tab = JEU_TABS.some(([k]) => k === sub) ? sub : (store('producer-jeu-tab') || 'regles');
  store('producer-jeu-tab', tab);
  $('jeu-tabs').replaceChildren(...JEU_TABS.map(([k, label]) => el('a', {
    href: '#/jeu/' + k, class: 'subtab' + (k === tab ? ' active' : ''), text: label,
  })));
  const box = $('jeu');
  const g = state.index.blackout || {};
  if (!g.regles) { box.replaceChildren(el('p', { class: 'empty', text: 'Index sans données de gameplay : reconstruire /producer.' })); return; }
  if (tab === 'regles') box.replaceChildren(...jeuRegles(g));
  else if (tab === 'options') box.replaceChildren(...jeuOptions(g));
  else if (tab === 'ecrans') box.replaceChildren(...jeuEcrans(g));
  else if (tab === 'cartes') box.replaceChildren(...jeuCartes(g));
  else box.replaceChildren(...jeuEquilibrage(g));
}

/** Cartes du kanban d'un élément de jeu (liées par l'asset, ou dont le titre en parle). */
function jeuCards(assetId, mots) {
  const { direct } = cardsFor(assetId, '');
  const ns = (mots || []).map(norm).filter((m) => m.length > 3);
  const suggest = ns.length ? state.cards.filter((c) => !direct.includes(c) && ns.some((m) => norm(c.title).includes(m))) : [];
  return { direct, suggest };
}

/** En-tête d'un bloc de jeu : titre, statut, lien vers la fiche, bouton « Kanban / commenter ». */
function jeuHead(title, assetId, mots, extra) {
  const { direct, suggest } = jeuCards(assetId, mots);
  const panel = el('div', { class: 'jeu-pilot', hidden: true });
  const toggle = el('button', {
    type: 'button', class: 'small', 'aria-expanded': 'false',
    onclick: () => {
      if (!panel.firstChild) {
        panel.append(pilotBlock({ asset: assetId, type: 'gameplay', title: `${title} : amélioration`, compact: true,
          extraCards: () => jeuCards(assetId, mots).direct }));
        if (suggest.length) {
          panel.append(el('details', { class: 'lgeneral' }, el('summary', { text: `Cartes qui en parlent (${suggest.length})` }),
            el('ul', { class: 'lcards' }, suggest.slice(0, 12).map((c) => el('li', { class: 'lcard' },
              el('button', { type: 'button', class: 'lcard-open', onclick: () => openCardDialog(c, '') },
                cardPill(c), el('span', { class: 'lcard-title', text: c.title }), el('span', { class: 'muted', text: '#' + c.id })),
              !c.asset && state.assetsById.has(assetId) ? el('button', {
                type: 'button', class: 'small', title: 'Lier cette carte à cet élément (champ asset)',
                onclick: async () => {
                  const ok = await guarded(async () => { await api('card_update', { method: 'POST', body: { id: c.id, asset: assetId } }); await reloadCards(); return true; });
                  if (ok) { toast(`Carte #${c.id} liée`); renderJeu(location.hash.split('/')[2] || ''); }
                },
              }, 'Lier') : null)))));
        }
      }
      panel.hidden = !panel.hidden;
      toggle.setAttribute('aria-expanded', panel.hidden ? 'false' : 'true');
    },
  }, `Kanban (${direct.length}) · commenter`);
  return [el('div', { class: 'jeu-head' },
    el('h3', { text: title }), direct.length ? statusPill(statusOfCards(direct)) : null, extra || null,
    el('span', { class: 'spacer' }),
    state.assetsById.has(assetId) ? el('a', { class: 'small', href: '#/assets/' + encodeURIComponent(assetId), text: 'fiche ›' }) : null,
    toggle), panel];
}

// ------------------------------------------------------------------ règles

function fmtVal(v, unite) {
  if (unite === 'on/off') return el('span', { class: 'badge ' + (v ? 'valide' : ''), text: v ? 'activé' : 'désactivé' });
  if (typeof v === 'number') return `${String(v).replace('.', ',')}${unite && unite !== 'on/off' ? ' ' + unite : ''}`;
  if (typeof v === 'boolean') return v ? 'oui' : 'non';
  return JSON.stringify(v);
}

/** Valeur complexe d'une règle : score, couleurs, niveaux d'IA, réglages par animation. */
function ruleValue(item) {
  const v = item.valeur;
  if (item.cle === 'score' && v && typeof v === 'object') {
    return el('ul', { class: 'md-ul' }, Object.entries(v).map(([k, n]) => el('li', {}, `${(item.details || {})[k] || k} : `, el('strong', { text: `${n} pt` }))));
  }
  if (item.cle === 'colors' && Array.isArray(v)) {
    return el('span', { class: 'swatches' }, v.map((c) => { const s = el('span', { class: 'swatch', title: c }); s.style.background = c; return s; }));
  }
  if (item.cle === 'ai' && v && typeof v === 'object') {
    const levels = Object.keys(v);
    const keys = [...new Set(levels.flatMap((l) => Object.keys(v[l])))];
    return el('div', { class: 'md-table' }, el('table', {},
      el('thead', {}, el('tr', {}, el('th', { text: 'réglage' }), levels.map((l) => el('th', { text: l })))),
      el('tbody', {}, keys.map((k) => el('tr', {}, el('td', {}, el('code', { text: k })), levels.map((l) => el('td', { text: String(v[l][k]) })))))));
  }
  if (Array.isArray(v)) return el('span', { class: 'chips' }, v.map((x) => el('span', { class: 'chip', text: String(x) })));
  if (v && typeof v === 'object') {
    return el('dl', { class: 'credits small' }, Object.entries(v).flatMap(([k, x]) => [el('dt', {}, el('code', { text: k })),
      el('dd', { text: typeof x === 'object' ? JSON.stringify(x).replace(/[{}"]/g, '').replace(/,/g, ', ').replace(/:/g, ' : ') : String(x) })]));
  }
  return fmtVal(v, item.unite);
}

function rulesTable(j) {
  return el('div', { class: 'md-table rules' }, el('table', {}, el('tbody', {}, (j.items || []).map((it) => el('tr', {},
    el('th', {}, el('span', { text: it.libelle }), el('code', { class: 'rkey', text: it.cle })),
    el('td', {}, ruleValue(it)))))));
}

function jeuRegles(g) {
  const out = [el('p', { class: 'muted intro' }, ...mdInline(g.doc_regles || ''), ' Source : ', el('code', { text: 'data/blackout/rules.json' }),
    '. Les options validées se règlent dans la partie rapide ; le reste se change dans le fichier.')];
  for (const r of g.regles) {
    const a = state.assetsById.get(r.asset);
    if (!a) continue;
    const j = a.jeu;
    const sec = el('section', { class: 'panel jeu-block', id: 'regles-' + r.id }, ...jeuHead(j.titre, a.id, [j.titre]),
      j.doc ? el('details', { class: 'jdoc' }, el('summary', { text: 'Ce que disent les notes du fichier' }), el('p', {}, ...mdInline(j.doc))) : null,
      rulesTable(j));
    out.push(sec);
  }
  return out;
}

// ------------------------------------------------------------------ options

function optionBody(o) {
  return [
    el('p', { class: 'jaide', text: o.aide || '' }),
    el('ul', { class: 'md-ul' }, (o.reglages || []).map((r) => el('li', {},
      el('strong', { text: r.libelle }), ' : ',
      r.type === 'on_off' ? fmtVal(r.defaut, 'on/off') : `${String(r.defaut).replace('.', ',')} (de ${String(r.min).replace('.', ',')} à ${String(r.max).replace('.', ',')}, pas ${String(r.pas).replace('.', ',')})`,
      el('code', { class: 'rkey', text: r.cle })))),
    el('p', { class: 'muted small' }, `Validée le ${o.valide_le || '?'}`, o.carte_kanban ? ` · carte #${o.carte_kanban}` : ''),
  ];
}

function jeuOptions(g) {
  const out = [el('p', { class: 'muted intro' }, ...mdInline(g.doc_options || ''))];
  const byGroup = new Map();
  for (const id of g.options || []) {
    const a = state.assetsById.get(id);
    if (!a) continue;
    const grp = a.jeu.groupe || 'Autres';
    if (!byGroup.has(grp)) byGroup.set(grp, []);
    byGroup.get(grp).push(a);
  }
  for (const [grp, list] of byGroup) {
    out.push(el('h4', { class: 'kind', text: grp }), el('div', { class: 'jeu-grid' }, list.map((a) => el('section', { class: 'panel jeu-block' },
      ...jeuHead(a.jeu.libelle, a.id, [a.jeu.libelle]), ...optionBody(a.jeu)))));
  }
  return out;
}

// ------------------------------------------------------------------ écrans

function ecranCapture(j, big) {
  if (j.capture) {
    return el('a', { href: fileUrl(j.capture.file), target: '_blank', rel: 'noopener', class: 'ecap' + (big ? ' big' : '') },
      el('img', { src: fileUrl(j.capture.file), alt: 'Capture : ' + j.nom, loading: 'lazy', width: j.capture.w, height: j.capture.h }));
  }
  return el('div', { class: 'ecap none' + (big ? ' big' : '') }, el('span', { text: j.nom }), el('small', { text: 'pas de capture (tools/producer/captures_ecrans.sh)' }));
}

function ecranBody(j, big) {
  return [ecranCapture(j, big), el('p', { class: 'jaide' }, ...mdInline(j.role || '')),
    el('p', { class: 'muted small' }, el('code', { text: j.script }), j.scene ? ' · ' : '', j.scene ? el('code', { text: j.scene }) : null)];
}

function jeuEcrans(g) {
  return [el('p', { class: 'muted intro', text: 'Le parcours des écrans, dans l\'ordre (SPEC-GORDEKA §6). Le rôle vient du commentaire en tête de chaque script ; les captures de docs/captures/ecrans.' }),
    el('div', { class: 'jeu-grid ecrans' }, (g.ecrans || []).map((id) => state.assetsById.get(id)).filter(Boolean).map((a) =>
      el('section', { class: 'panel jeu-block' }, ...jeuHead(a.jeu.nom, a.id, [a.jeu.nom]), ...ecranBody(a.jeu, false))))];
}

// ------------------------------------------------------------------ cartes de jeu

/** Chiffres du décor d'une carte dans le catalogue : objets, cachettes, sans image, provisoires, sans masque. */
function decorStats(mid) {
  const its = catalogueItems().items.filter((it) => it.cartes.includes(mid));
  const n = (f) => its.filter(f).length;
  return [
    ['éléments de décor', its.length, ''], ['modèles de cachette', n((i) => i.type === 'cachette'), 'cachette'],
    ['sans image', n((i) => i.missing), 'manquant'], ['provisoires', n((i) => i.provisoire), 'provisoire'],
    ['sans masque', n((i) => i.sansMasque), 'sans_masque'],
    ['à retraiter', n((i) => itemStatus(i) === 'rework'), 'rework'], ['en QA', n((i) => itemCards(i).direct.some((c) => c.status === 'qa')), 'qa'],
  ];
}

function openCatalogueFor(mid, filter) {
  cat.map = mid; cat.type = filter === 'cachette' ? 'cachette' : ''; cat.group = 'type';
  cat.filters = new Set(filter && filter !== 'cachette' ? [filter] : []);
  saveCatalogue();
  location.hash = '#/assets';
}

function jeuCartes(g) {
  const out = [];
  for (const m of g.cartes || []) {
    const a = state.assetsById.get(m.asset);
    const hat = m.chapeau ? cardById(m.chapeau) : null;
    const facts = [
      ['Taille', `${m.taille[0]} × ${m.taille[1]} cases`], ['Sol', `${m.sol} cases`], ['Zones', String(m.zones.length)],
      ['Cachettes', String(m.cachettes)], ['Sorties', m.sorties.join(', ')],
      ['Réglages propres', Object.entries(m.regles || {}).map(([k, v]) => `${k} = ${v}`).join(', ')],
      ['Version', m.version ? 'v' + m.version : ''],
    ];
    const stats = m.jouable ? decorStats(m.id) : [];
    const sec = el('section', { class: 'panel jeu-block carte-jeu' + (m.jouable ? '' : ' ancienne'), id: 'carte-' + m.id },
      ...jeuHead(m.nom + (m.jouable ? '' : ' (ancienne version, non jouable)'), m.asset, [m.nom, m.nom_menu],
        m.chasseur_gagne ? el('span', { class: 'badge kpi', title: 'Chasseur gagne (% des rounds) : IA facile / normal / malin, version retenue', text: `chasseur gagne ${m.chasseur_gagne} %` }) : null),
      el('div', { class: 'carte-body' },
        a ? el('a', { href: '#/assets/' + encodeURIComponent(a.id), class: 'carte-plan' },
          el('img', { src: fileUrl(a.preview), alt: 'Plan de ' + m.nom, loading: 'lazy', width: a.w, height: a.h })) : null,
        el('div', { class: 'carte-facts' },
          infoList(facts),
          m.zones.length ? el('p', { class: 'chips' }, m.zones.map((z) => el('span', { class: 'chip' + (z.sombre ? ' sombre' : ''), title: z.sombre ? 'zone sombre (grotte, tunnel)' : '', text: z.name }))) : null,
          stats.length ? el('p', { class: 'chips' }, stats.map(([label, n, f]) => el('button', {
            type: 'button', class: 'chip-btn' + (n ? '' : ' zero'), onclick: () => openCatalogueFor(m.id, f),
            title: 'Voir dans le catalogue',
          }, `${n} ${label}`))) : null,
          hat ? el('div', { class: 'hat-prog' }, el('button', { type: 'button', class: 'link', onclick: () => openCardDialog(hat, '') }, `Chapeau #${hat.id} : ${hat.title}`),
            ...stackBarRow(leavesOf(hat.id))) : null)),
      m.equilibrage.length ? el('details', { class: 'jdoc' }, el('summary', { text: `Bilan d'équilibrage (${m.equilibrage.length})` }),
        ...m.equilibrage.flatMap((s) => [el('h4', { class: 'md-h', text: s.titre }), ...md(s.texte)])) : null);
    out.push(sec);
  }
  return out;
}

function stackBarRow(cards) {
  const [bar, txt] = stackBar(cards);
  return [bar, el('span', { class: 'muted small', text: txt })];
}

// ------------------------------------------------------------------ équilibrage

function jeuEquilibrage(g) {
  const out = [el('p', { class: 'muted intro' }, 'Bilans des parties IA contre IA (', el('code', { text: 'docs/GORDEKA_EQUILIBRAGE.md' }),
    '). Les bilans propres à une carte sont aussi dans l\'onglet Cartes de jeu.')];
  for (const s of g.equilibrage_general || []) {
    out.push(el('details', { class: 'panel jdoc' }, el('summary', { text: s.titre }), ...md(s.texte)));
  }
  for (const m of g.cartes || []) {
    for (const s of m.equilibrage) out.push(el('details', { class: 'panel jdoc' }, el('summary', { text: `${m.nom} · ${s.titre}` }), ...md(s.texte)));
  }
  return out;
}

// ------------------------------------------------------------------ fiche d'un élément de jeu

/** Contenu d'un asset « jeu » dans sa fiche (catalogue). */
function jeuView(a) {
  const j = a.jeu || {};
  if (j.sorte === 'regles') {
    return el('div', { class: 'jeu-view' }, j.doc ? el('p', { class: 'jaide' }, ...mdInline(j.doc)) : null, rulesTable(j));
  }
  if (j.sorte === 'option') {
    return el('div', { class: 'jeu-view' }, el('h3', { text: `${j.groupe} · ${j.libelle}` }), ...optionBody(j));
  }
  if (j.sorte === 'ecran') return el('div', { class: 'jeu-view' }, ...ecranBody(j, true));
  return el('pre', { class: 'data', text: JSON.stringify(j, null, 1) });
}
