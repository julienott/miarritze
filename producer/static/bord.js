// Miarritze Producer — tableau de bord (#/bord) : ce qui attend Julien (QA à valider, refus à
// retraiter), ce qui avance (Doing, file pixelforge), les jalons, l'activité récente ; et la page
// Aide (#/aide) : guide des sections, API (GET routes) et commandes de cli.py.
'use strict';

function kpi(label, n, hint, href, cls) {
  return el('a', { class: 'kpi-tile' + (cls ? ' ' + cls : '') + (n ? '' : ' zero'), href: href || '#/bord' },
    el('span', { class: 'kpi-n', text: String(n) }), el('span', { class: 'kpi-l', text: label }),
    hint ? el('span', { class: 'kpi-h muted', text: hint }) : null);
}

/** Va au kanban sur une colonne (et un filtre de recherche facultatif). */
function kanbanAt(status) {
  return () => { state.kbTab = status; store('producer-kb-tab', status); };
}

function eventLine(e) {
  const who = AUTHOR_LABEL[e.author] || e.author;
  const what = e.type === 'commentaire' ? `a commenté : « ${e.new.length > 90 ? e.new.slice(0, 89) + '…' : e.new} »`
    : e.type === 'refuse' ? `a refusé : « ${e.new.length > 90 ? e.new.slice(0, 89) + '…' : e.new} »` : eventText(e);
  const c = cardById(e.card_id);
  return el('li', { class: 'ev ev-' + e.type },
    el('span', { class: 'muted ev-t', text: new Date(e.at * 1000).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) }),
    el('strong', { text: who }), ' ', what, ' · ',
    c ? el('button', { type: 'button', class: 'link', onclick: () => openCardDialog(c, '') }, `#${c.id} ${c.title}`)
      : el('span', { class: 'muted', text: `#${e.card_id} ${e.card_title || '(supprimée)'}` }));
}

const DEPLOY_LABEL = { idle: 'à jour', en_attente: 'déploiement en attente', en_cours: 'déploiement en cours…', echec: 'échec du déploiement' };

/** « 24/10 14:32 » */
function fmtShort(ts) {
  const d = new Date(ts * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return `${p(d.getDate())}/${p(d.getMonth() + 1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

/**
 * Ligne sobre du studio (état écrit par le watcher, GET studio, sinon clé `studio` de l'index) :
 * build du jeu de QA (lien /jeu/) et déploiement groupé vers la prod (cartes Validé en attente).
 */
function studioRow() {
  const st = (state.studio && Object.keys(state.studio).length ? state.studio : (state.index && state.index.studio)) || {};
  const qb = st.qa_build && typeof st.qa_build === 'object' ? st.qa_build : null;
  const dep = st.deploy && typeof st.deploy === 'object' ? st.deploy : null;
  const valides = state.cards.filter((c) => c.status === 'valide' && !c.children).length;
  if (!qb && !dep && !valides) return null;
  const qaText = qb ? (qb.at ? `build du ${fmtShort(qb.at)}` : 'build') + (qb.commit ? ' · ' + String(qb.commit).slice(0, 7) : '')
    + (qb.ok === false ? ' · ✗ en échec' : '') : 'pas encore de build';
  const depState = dep ? String(dep.state || 'idle') : 'idle';
  let prodText = DEPLOY_LABEL[depState] || depState;
  if (dep && dep.at) prodText += ` (${fmtShort(dep.at)})`;
  if (valides) prodText += ` · ${valides} validée${valides > 1 ? 's' : ''} à déployer`;
  const tile = (cls, label, text, href, title) => el('a', { class: 'studio-tile ' + cls, href, title: title || null },
    el('strong', { text: label }), el('span', { text }));
  return el('div', { class: 'studio-row' },
    tile('s-qa' + (qb && qb.ok === false ? ' bad' : ''), '▶ Jeu QA', qaText, '/jeu/', 'Ouvrir le jeu local de QA'),
    tile('s-prod' + (depState === 'echec' ? ' bad' : ''), 'Prod', prodText, '#/kanban',
      dep && dep.message ? String(dep.message) : 'miarritze.ijulien.com'));
}

async function renderBord() {
  const box = $('bord');
  const g = state.index.blackout || {};
  const leaves = state.cards.filter((c) => !c.children);
  const qa = leaves.filter((c) => c.status === 'qa');
  const rework = state.cards.filter((c) => c.rework);
  const doing = leaves.filter((c) => c.status === 'doing');
  const todo = leaves.filter((c) => c.status === 'todo');
  const night = todo.filter((c) => c.night);
  const file = g.file_pixelforge || [];
  const enFile = file.filter((t) => t.statut === 'en_file');
  const { items } = catalogueItems();
  const animsMissing = items.filter((i) => i.type === 'anim' && i.missing && !i.aVenir).length;
  const decorMissing = items.filter((i) => i.missing && i.type !== 'anim').length;
  const sansMasque = items.filter((i) => i.sansMasque).length;
  const open = state.comments.filter((c) => c.status === 'open').length;
  const stale = staleCards();

  const tiles = el('div', { class: 'kpis' },
    kpi('à valider (QA)', qa.length, 'cartes sans enfant', '#/kanban', 'k-qa'),
    kpi('refusées à retraiter', rework.length, '↺ par Claude', '#/kanban', 'k-rework'),
    kpi('en cours (Doing)', doing.length, stale.length ? `${stale.length} immobile${stale.length > 1 ? 's' : ''} depuis ${STALE_DAYS} j` : '', '#/kanban', 'k-doing'),
    kpi('à faire (Todo)', todo.length, night.length ? `dont ${night.length} 🌙 cette nuit` : '', '#/kanban', 'k-todo'),
    kpi('en file pixelforge', enFile.length, file.length > enFile.length ? `+ ${file.length - enFile.length} en attente` : '', '#/bord', 'k-pf'),
    kpi('avis d\'asset ouverts', open, '', '#/comments', 'k-avis'),
    kpi('animations manquantes', animsMissing, '', '#/assets', 'k-cat'),
    kpi('décor sans image', decorMissing, sansMasque ? `${sansMasque} objets sans masque` : '', '#/assets', 'k-cat'));
  // Liens des tuiles : colonne du kanban, filtres du catalogue.
  tiles.children[0].addEventListener('click', kanbanAt('qa'));
  tiles.children[1].addEventListener('click', kanbanAt('doing'));
  tiles.children[2].addEventListener('click', kanbanAt('doing'));
  tiles.children[3].addEventListener('click', kanbanAt('todo'));
  tiles.children[6].addEventListener('click', () => { cat.type = 'anim'; cat.filters = new Set(['manquant']); cat.map = ''; saveCatalogue(); });
  tiles.children[7].addEventListener('click', () => { cat.type = ''; cat.filters = new Set(['manquant']); cat.group = 'carte'; saveCatalogue(); });
  const studio = studioRow();
  if (studio) {
    studio.children[0].target = '_blank';
    studio.children[1].addEventListener('click', kanbanAt('valide'));
  }

  const qaList = el('section', { class: 'panel bord-col' },
    el('h3', {}, el('span', { text: `À valider (${qa.length})` }), el('a', { href: '#/kanban', class: 'small', onclick: kanbanAt('qa'), text: 'kanban ›' })),
    qa.length ? el('div', { class: 'qa-grid' }, qa.slice(0, 12).map((c) => qaTile(c))) : el('p', { class: 'muted', text: 'Rien à valider.' }),
    qa.length > 12 ? el('p', { class: 'muted small', text: `… et ${qa.length - 12} autres dans la colonne QA.` }) : null);

  const reworkList = el('section', { class: 'panel bord-col' },
    el('h3', { text: `Refusées, à retraiter (${rework.length})` }),
    rework.length ? el('ul', { class: 'lcards' }, rework.map((c) => {
      const li = linkedCardRow(c);
      const r = lastRefusal([c]);
      if (r) li.append(el('p', { class: 'note refus small', text: r.body }));
      return li;
    })) : el('p', { class: 'muted', text: 'Aucun refus en attente.' }),
    stale.length ? [el('h4', { class: 'kind', text: `Doing immobile depuis ${STALE_DAYS} jours (${stale.length})` }),
      el('ul', { class: 'lcards' }, stale.slice(0, 6).map((c) => { const li = linkedCardRow(c); li.append(el('span', { class: 'muted small', text: sinceText(c.status_at) })); return li; }))] : null);

  const pf = el('section', { class: 'panel bord-col' },
    el('h3', { text: `File pixelforge (${file.length})` }),
    file.length ? el('div', { class: 'md-table' }, el('table', {}, el('thead', {}, el('tr', {},
      el('th', { text: 'état' }), el('th', { text: 'tâche' }), el('th', { text: 'déposée' }))),
    el('tbody', {}, file.slice(0, 40).map((t) => {
      const c = t.carte ? cardById(t.carte) : null;
      return el('tr', {}, el('td', {}, el('span', { class: 'badge pf-' + t.statut, text: t.statut_libelle })),
        el('td', {}, c ? el('button', { type: 'button', class: 'link', onclick: () => openCardDialog(c, '') }, t.titre) : t.titre,
          t.asset ? [' ', el('a', { href: '#/assets/' + encodeURIComponent(t.asset), class: 'small', text: '↗' })] : null),
        el('td', { class: 'muted small', text: t.depose || (t.depend ? `après #${t.depend}` : '') }));
    })))) : el('p', { class: 'muted', text: 'Rien dans la file de nuit du décor.' }),
    el('p', { class: 'muted small', text: 'Source : tools/blackout/taches_decor_nuit.json, au moment du build de /producer.' }));

  const msBox = el('section', { class: 'panel bord-col' }, el('h3', {}, el('span', { text: 'Jalons' }), el('a', { href: '#/roadmap', class: 'small', text: 'roadmap ›' })));
  if (!state.milestones.length) {
    msBox.append(el('p', { class: 'muted' }, 'Pas encore de jalon. ', el('a', { href: '#/roadmap', text: 'Les créer depuis la spec' }), '.'));
  }
  for (const m of state.milestones.filter((x) => !x.closed)) {
    const leavesM = state.cards.filter((c) => !c.children && milestoneOf(c) === m.id);
    const [bar, txt] = stackBar(leavesM);
    msBox.append(el('div', { class: 'ms-mini' }, el('div', { class: 'row' }, el('strong', { text: m.title }), el('span', { class: 'spacer' }), dueBadge(m.due, false)),
      bar, el('span', { class: 'muted small', text: txt })));
  }

  const act = el('section', { class: 'panel bord-col bord-act' }, el('h3', { text: 'Activité (48 h)' }), el('p', { class: 'muted', text: 'Chargement…' }));
  box.replaceChildren(...[studio, tiles, el('div', { class: 'bord-grid' }, qaList, reworkList, msBox, pf, act)].filter(Boolean));
  const r = await guarded(() => api('events', { query: { since: Math.floor(Date.now() / 1000) - 2 * 86400 } }));
  if (!r || !location.hash.startsWith('#/bord') && location.hash !== '') return;
  // Les tâches pixelforge (événements « jobs » du watcher) ne remplissent pas l'activité.
  const evs = r.events.filter((e) => e.type !== 'jobs').reverse().slice(0, 60);
  const byDay = new Map();
  for (const e of evs) {
    const d = new Date(e.at * 1000).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
    if (!byDay.has(d)) byDay.set(d, []);
    byDay.get(d).push(e);
  }
  act.replaceChildren(el('h3', { text: `Activité (48 h, ${evs.length} événements)` }),
    ...(evs.length ? [...byDay].flatMap(([d, list]) => [el('h4', { class: 'kind', text: d }), el('ul', { class: 'evs' }, list.map(eventLine))])
      : [el('p', { class: 'muted', text: 'Rien depuis 48 h.' })]));
}

/** Tuile d'une carte en QA : miniature de l'asset, titre, ✓ / ✗. */
function qaTile(c) {
  const tile = el('div', { class: 'qa-tile t-' + c.type });
  const th = cardThumbEl(c, tile);
  tile.append(th || el('span', { class: 'card-thumb none' }),
    el('button', { type: 'button', class: 'link qa-title', onclick: () => openCardDialog(c, '') }, c.title),
    el('div', { class: 'qa-actions' },
      el('button', { type: 'button', class: 'accept', onclick: async () => { await acceptCard(c); renderBord(); } }, '✓'),
      el('button', { type: 'button', class: 'refuse', onclick: () => openRefuse(c) }, '✗')));
  return tile;
}

// ================================================================== AIDE

const GUIDE = [
  ['Bord', 'Ce qui attend : état du jeu de QA (dernier build) et de la prod (déploiement, cartes validées en attente), cartes à valider (✓ / ✗ directement), refus à retraiter, Doing immobiles, file pixelforge, jalons et activité des 48 dernières heures. Les tuiles mènent à la bonne colonne du kanban ou au bon filtre du catalogue.'],
  ['Kanban', 'Backlog → Todo → Doing → QA → Validé → En prod. QA : à tester dans le jeu local de QA (« ▶ Jeu QA ») ; ✓ Accepter fait passer en Validé : la carte part en prod au prochain déploiement groupé ; En prod : en ligne sur miarritze.ijulien.com (déplacée par le déploiement). ✗ Refuser renvoie en haut du Backlog, à retraiter. Recherche (titre, #id), filtres par type, perso, carte de jeu, jalon et chapeau (retenus). « ☑ Sélection » : cocher des cartes puis les déplacer, passer en night shift, changer la priorité ou le jalon d\'un coup. Dans le détail d\'une carte : jalon et échéance s\'enregistrent aussitôt.'],
  ['Catalogue', 'Tous les éléments du jeu : chaque animation de chaque perso (présente ou manquante), le décor des trois cartes (objets, cachettes, sorties, sols, animations), les plans, règles, options et écrans. Grouper par type, carte de jeu, perso, statut kanban ou zone ; filtres « pas encore fait », « à retraiter », « en QA », « déjà refusé », « sans masque », « provisoire », « sans carte », « avis ouverts ». Le statut vient du kanban (carte liée par l\'asset, l\'animation, ou le titre). La fiche montre l\'élément, ses cartes, le dernier refus, le prompt, les tâches pixelforge et les versions ; « Envoyer » reporte le commentaire sur la carte choisie, ou crée une carte en Backlog.'],
  ['Jeu', 'Règles de rules.json avec des libellés, options de partie validées, écrans de menu (rôle et capture), cartes de jeu (plan, zones, sorties, cachettes, « chasseur gagne » F / N / M, bilan d\'équilibrage) et bilans d\'équilibrage. « Kanban · commenter » sur chaque bloc ; « Lier » rattache une carte qui en parle.'],
  ['Roadmap', 'Jalons (échéance, description) et chapeaux, avec leur avancement (feuilles En prod, Validé, QA, Doing, Todo, Backlog) et ce qui bloque. Un chapeau rattaché à un jalon y emmène toute sa famille. Sans jalon, « Créer ces jalons » reprend ceux de la spec (§14).'],
  ['Avis', 'Les commentaires d\'asset (versionnés), avec la carte où ils ont été reportés.'],
];

async function renderAide() {
  const box = $('aide');
  box.replaceChildren(el('section', { class: 'panel' }, el('h3', { text: 'Les sections' }),
    el('dl', { class: 'credits' }, GUIDE.flatMap(([k, v]) => [el('dt', { text: k }), el('dd', { text: v })]))),
  el('section', { class: 'panel', id: 'aide-api' }, el('h3', { text: 'API' }), el('p', { class: 'muted', text: 'Chargement…' })));
  const r = await guarded(() => api('routes'));
  if (!r) return;
  const groups = new Map();
  for (const x of r.routes) {
    if (!groups.has(x.group)) groups.set(x.group, []);
    groups.get(x.group).push(x);
  }
  $('aide-api').replaceChildren(
    el('h3', { text: `API (schéma v${r.schema})` }),
    el('p', {}, 'Toutes les routes passent par ', el('code', { text: 'index.php?r=<route>' }), ' et répondent en JSON. Agent : ',
      el('code', { text: 'Authorization: Bearer <jeton>' }), ' (ou ', el('code', { text: 'X-Producer-Token' }),
      ') ; navigateur : session + en-tête ', el('code', { text: 'X-CSRF-Token' }), ' sur toute écriture. Colonnes : ',
      r.statuses.join(', '), ' ; types : ', r.types.join(', '), '.'),
    ...[...groups].flatMap(([grp, list]) => [el('h4', { class: 'kind', text: grp }), el('div', { class: 'md-table api' }, el('table', {},
      el('thead', {}, el('tr', {}, el('th', { text: 'route' }), el('th', { text: 'paramètres' }), el('th', { text: 'effet' }), el('th', { text: 'cli.py' }))),
      el('tbody', {}, list.map((x) => el('tr', {},
        el('td', {}, el('span', { class: 'badge m-' + x.method, text: x.method }), ' ', el('code', { text: x.route })),
        el('td', {}, x.params ? el('code', { text: x.params }) : ''), el('td', { text: x.effect }),
        el('td', {}, x.cli ? el('code', { text: x.cli }) : ''))))))]),
    el('h4', { class: 'kind', text: 'Client terminal' }),
    el('pre', { class: 'data', text: [
      'PRODUCER_URL=https://miarritze.ijulien.com/producer/   # par défaut ; adresse du service local sinon',
      'PRODUCER_TOKEN=…                                      # ou .producer_token à la racine du dépôt',
      'tools/producer/cli.py stats                    # tableau de bord (QA, refus, Doing immobiles, jalons)',
      'tools/producer/cli.py cards --status qa --type animation --search louis',
      'tools/producer/cli.py bulk 12 13 14 --status todo --night on',
      'tools/producer/cli.py milestones · add-milestone --title "Contenu v1" --due 2026-12-01',
      'tools/producer/cli.py set 4 --milestone 2 --due 2026-11-15',
      'tools/producer/cli.py move 4 done                # Validé -> En prod (fait par le déploiement)',
      'tools/producer/cli.py set 4 --jobs \'[{"id":"c4897ae6…","role":"A","label":"animation run","status":"running","keep":false}]\'',
      'tools/producer/cli.py asset-comment blackout/persos/louis/animations "pieds qui glissent" --detail walk',
      'tools/producer/cli.py routes                   # cette liste',
    ].join('\n') }));
}
