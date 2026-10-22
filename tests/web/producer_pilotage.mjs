// /producer, refonte « pilotage » : navigation, tableau de bord, catalogue (groupements, filtres,
// statut kanban, fiche avec commentaire reporté sur une carte), Jeu (règles, options, écrans,
// cartes de jeu), roadmap (jalons), kanban (filtres, sélection et actions groupées), aide/API.
// Ordinateur (Chromium 1440×900) puis iPhone (390×844, WebKit si installé) ; captures de chaque section.
// Env : PRODUCER_URL (défaut http://127.0.0.1:8099/producer/), PRODUCER_TEST_PASSWORD, PRODUCER_THEME (dark),
//       PRODUCER_SHOTS (dossier des captures, défaut tests/out/producer_pilotage).
// Base de test quelconque (cartes de remplit_kanban.py conseillées) ; le test crée un jalon,
// une carte et des commentaires (titres uniques).
import { chromium, webkit, devices } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';

const BASE = process.env.PRODUCER_URL || 'http://127.0.0.1:8099/producer/';
const PASSWORD = process.env.PRODUCER_TEST_PASSWORD || '';
if (!PASSWORD) {
  console.error('PRODUCER_TEST_PASSWORD requis');
  process.exit(2);
}
const ROOT = path.resolve(import.meta.dirname, '../..');
const OUT = process.env.PRODUCER_SHOTS || path.join(ROOT, 'tests/out/producer_pilotage');
fs.mkdirSync(OUT, { recursive: true });
let fails = 0;
const check = (name, ok, detail = '') => {
  if (!ok) fails++;
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
};
const stamp = Date.now().toString(36);

let wk = null;
if (!process.env.PRODUCER_NO_WEBKIT) {
  try { wk = await webkit.launch(); } catch (e) { console.log('     (WebKit indisponible : iPhone émulé dans Chromium)'); }
}
const cr = await chromium.launch();
const runs = [
  ['ordi', cr, { viewport: { width: 1440, height: 900 } }],
  ['iphone', wk || cr, { ...devices['iPhone 13'], viewport: { width: 390, height: 844 } }],
];

for (const [label, browser, opts] of runs) {
  const context = await browser.newContext(opts);
  // PRODUCER_THEME=dark : mêmes parcours en thème sombre.
  if (process.env.PRODUCER_THEME) await context.addInitScript((t) => { localStorage.setItem('producer-theme', t); }, process.env.PRODUCER_THEME);
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    if (m.type() === 'error' && !(browser === wk && m.text().startsWith('Refused to apply a stylesheet'))) errors.push(m.text());
  });
  page.on('dialog', (d) => d.accept());
  const shot = (n, full = false) => page.screenshot({ path: path.join(OUT, `${label}_${n}.png`), fullPage: full });
  const go = async (hash, sel) => {
    await page.evaluate((h) => { location.hash = h; }, hash);
    if (sel) await page.waitForSelector(sel, { timeout: 15000, state: 'attached' });
    await page.waitForTimeout(500);
  };

  await page.goto(BASE);
  await page.waitForSelector('#login:not([hidden])');
  await page.fill('#password', PASSWORD);
  await page.click('#login-form button[type=submit]');
  // Ouverture : tableau de bord.
  await page.waitForSelector('#view-bord:not([hidden]) .kpis');
  await page.waitForSelector('.bord-act .evs, .bord-act p.muted:not(:empty)');
  await page.waitForTimeout(800);
  const navTabs = await page.$$eval('#tabs a', (l) => l.map((a) => a.dataset.tab));
  check(`${label} : navigation à 7 sections`, navTabs.join(',') === 'bord,kanban,assets,jeu,roadmap,comments,aide', navTabs.join(','));
  const kpis = await page.$$eval('.kpi-tile', (l) => l.length);
  check(`${label} : tableau de bord, tuiles`, kpis === 8, String(kpis));
  if (label === 'iphone') {
    const nav = await page.evaluate(() => {
      const n = document.querySelector('#tabs');
      return { w: n.scrollWidth, cw: n.clientWidth, page: document.documentElement.scrollWidth };
    });
    check(`${label} : la navigation tient en largeur`, nav.w <= nav.cw + 1 && nav.page <= 391, JSON.stringify(nav));
  }
  await shot('01_bord');
  await shot('01_bord_page', true);

  // ---------------------------------------------------------------- catalogue
  await go('#/assets', '.cgroup .citem');
  await page.evaluate(() => { localStorage.removeItem('producer-catalogue'); });
  const groups = await page.$$eval('.cgroup .group-name', (l) => l.map((x) => x.textContent));
  check(`${label} : catalogue groupé par type`, groups.includes('Animations des persos') && groups.includes('Cachettes') && groups.includes('Règles'), groups.slice(0, 8).join(' | '));
  await shot('02_catalogue');
  // Animation au survol (ou premier toucher) : la vignette s'anime sans quitter la page.
  const animTile = '.citem.t-anim:not(.missing)';
  if (opts.hasTouch) await page.locator(animTile).first().tap();
  else await page.hover(animTile);
  await page.waitForTimeout(600);
  check(`${label} : vignette animée`, (await page.$$('#grid .citem canvas')).length === 1 && page.url().endsWith('#/assets'));
  // Groupement par carte de jeu, puis par statut.
  await page.selectOption('#cat-group', 'carte');
  await page.waitForTimeout(400);
  const byMap = await page.$$eval('.cgroup .group-name', (l) => l.map((x) => x.textContent));
  check(`${label} : groupement par carte de jeu`, byMap.some((t) => t.includes('Parc Mazon')) && byMap.some((t) => t.includes('Plage')), byMap.join(' | '));
  await shot('03_catalogue_cartes');
  await page.selectOption('#cat-group', 'statut');
  await page.waitForTimeout(400);
  const bySt = await page.$$eval('.cgroup .group-name', (l) => l.map((x) => x.textContent));
  check(`${label} : groupement par statut kanban`, bySt.some((t) => t.includes('QA')) && bySt.some((t) => t.includes('Sans carte')), bySt.join(' | '));
  await shot('04_catalogue_statut');
  await page.selectOption('#cat-group', 'perso');
  await page.waitForTimeout(400);
  await shot('05_catalogue_perso');
  await page.selectOption('#cat-group', 'zone');
  await page.waitForTimeout(400);
  const byZone = await page.$$eval('.cgroup .group-name', (l) => l.length);
  check(`${label} : groupement par zone`, byZone > 10, String(byZone));
  await page.selectOption('#cat-group', 'type');
  // Filtre « sans masque » : que des objets du décor marqués.
  await page.click('.chip-btn[data-filter="sans_masque"]');
  await page.waitForTimeout(400);
  const sm = await page.$$eval('.citem', (l) => l.map((x) => !!x.querySelector('.badge.src-aucun')));
  check(`${label} : filtre sans masque`, sm.length > 0 && sm.every(Boolean), `${sm.length} éléments`);
  await shot('06_catalogue_sans_masque');
  await page.click('.chip-btn[data-filter="sans_masque"]');
  // Recherche.
  await page.fill('#cat-search', 'louis marche');
  await page.waitForTimeout(600);
  const found = await page.$$eval('.citem .cname', (l) => l.map((x) => x.textContent));
  check(`${label} : recherche`, found.includes('Louis · marche'), found.join(' | '));
  // Fiche : Louis · marche.
  // Sur écran tactile, le premier toucher anime la vignette, le second ouvre la fiche.
  await page.click('.citem[data-key$="#walk"]');
  await page.waitForTimeout(400);
  if (page.url().endsWith('#/assets')) await page.click('.citem[data-key$="#walk"]');
  await page.waitForSelector('.fiche .fiche-side .pilot');
  await page.waitForTimeout(800);
  const fiche = await page.evaluate(() => ({
    title: document.querySelector('.detail-head h2').textContent,
    cards: document.querySelectorAll('.fiche-side .lcard').length,
    prompt: !!document.querySelector('.fiche-side .prompt'),
    canvas: !!document.querySelector('.fiche-main .stage canvas'),
  }));
  check(`${label} : fiche d'une animation (cartes, prompt, lecture)`, fiche.title === 'Louis · marche' && fiche.cards >= 1 && fiche.prompt && fiche.canvas, JSON.stringify(fiche));
  await shot('07_fiche_anim');
  await page.evaluate(() => { location.hash = '#/assets'; });
  await page.fill('#cat-search', '');
  await page.waitForTimeout(500);
  // Fiche d'un objet du décor sans carte : le commentaire crée une carte en Backlog.
  await page.fill('#cat-search', 'tourniquet');
  await page.waitForTimeout(500);
  const decor = await page.$('.citem.t-objet, .citem.t-cachette');
  if (decor) {
    await decor.click();
    await page.waitForSelector('.fiche-side .pilot-form textarea');
    const before = await page.evaluate(() => state.cards.length);
    await page.fill('.fiche-side .pilot-form textarea', `Plus de couleurs (${label} ${stamp})`);
    await page.selectOption('.fiche-side .pilot-form select', '0');
    await page.click('.fiche-side .pilot-form button[type=submit]');
    await page.waitForFunction((n) => state.cards.length === n + 1, before, { timeout: 8000 }).catch(() => {});
    const made = await page.evaluate((st) => state.cards.find((c) => c.description.includes(st)), `${label} ${stamp}`);
    check(`${label} : commentaire d'amélioration = nouvelle carte en Backlog liée à l'asset`, !!made && made.status === 'backlog' && !!made.asset, made ? `#${made.id} ${made.title}` : 'aucune');
    await page.waitForTimeout(300);
    await shot('08_fiche_decor');
  } else check(`${label} : objet « tourniquet » trouvé`, false);
  await page.evaluate(() => { location.hash = '#/assets'; });
  await page.fill('#cat-search', '');

  // --------------------------------------------------------------------- jeu
  for (const [tab, sel, n] of [['regles', '.jeu-block .md-table.rules', '09_jeu_regles'], ['options', '.jeu-grid .jeu-block', '10_jeu_options'],
    ['ecrans', '.jeu-grid.ecrans .jeu-block', '11_jeu_ecrans'], ['cartes', '.carte-jeu', '12_jeu_cartes'], ['equilibrage', 'details.jdoc', '13_jeu_equilibrage']]) {
    await go('#/jeu/' + tab, sel);
    await shot(n);
  }
  const caps = await page.evaluate(() => state.index.blackout.ecrans.filter((id) => (state.assetsById.get(id).jeu || {}).capture).length);
  check(`${label} : écrans de menu avec capture`, caps >= 5, String(caps));
  await go('#/jeu/cartes', '.carte-jeu');
  const maps = await page.$$eval('.carte-jeu .jeu-head h3', (l) => l.map((x) => x.textContent));
  const cg = await page.$$eval('.carte-jeu .badge.kpi', (l) => l.map((x) => x.textContent));
  check(`${label} : cartes de jeu et chiffres d'équilibrage`, maps.length >= 3 && cg.length >= 3, `${maps.join(' | ')} · ${cg.join(' | ')}`);
  await page.click('.carte-jeu .jeu-head button.small');
  await page.waitForTimeout(300);
  await shot('12b_jeu_carte_kanban');

  // ----------------------------------------------------------------- roadmap
  await go('#/roadmap', '.rm-bar');
  if (label === 'ordi' && !(await page.evaluate(() => state.milestones.length))) {
    const seed = await page.$('button:has-text("Créer ces jalons")');
    if (seed) { await seed.click(); await page.waitForSelector('.milestone[data-ms]'); }
  }
  const ms = await page.$$eval('.milestone[data-ms]', (l) => l.length);
  check(`${label} : jalons de la roadmap`, ms >= 1, String(ms));
  if (label === 'ordi') {
    // Rattache le premier chapeau libre au premier jalon : l'avancement apparaît.
    const sel = page.locator('.milestone[data-ms] select').first();
    const opt = (await sel.locator('option').count()) > 1 ? await sel.locator('option').nth(1).getAttribute('value') : '';
    if (opt) { await sel.selectOption(opt); await page.waitForTimeout(800); }
    const bar = await page.$$eval('.milestone[data-ms] .ms-bar .stack span', (l) => l.length);
    check(`${label} : avancement d'un jalon`, bar >= 1, String(bar));
  }
  await shot('14_roadmap');
  await page.click('.rm-bar .seg button:nth-child(2)');
  await page.waitForTimeout(400);
  await shot('15_roadmap_chapeaux');
  await page.click('.rm-bar .seg button:nth-child(1)');

  // ------------------------------------------------------------------ kanban
  await go('#/kanban', '#board .column[data-status]');
  if (label === 'iphone') await page.click('.kb-tab.kb-filters');
  await page.selectOption('#kb-type', 'animation');
  await page.waitForTimeout(400);
  const types = await page.evaluate(() => [...document.querySelectorAll('#board .card[data-id]')].map((n) => cardById(Number(n.dataset.id)).type));
  check(`${label} : filtre par type`, types.length > 0 && types.every((t) => t === 'animation'), `${types.length} cartes`);
  await page.selectOption('#kb-perso', 'louis');
  await page.waitForTimeout(400);
  const louis = await page.evaluate(() => [...document.querySelectorAll('#board .card[data-id]')].map((n) => cardById(Number(n.dataset.id)).title));
  // Une carte d'un perso : son titre, son asset (blackout/persos/<id>/…) ou son chapeau le nomme.
  check(`${label} : filtre par perso`, louis.some((t) => /louis/i.test(t)) && !louis.some((t) => /txomin|amaia|patxi/i.test(t)), `${louis.length} cartes`);
  await shot('16_kanban_filtres');
  // Sélection + action groupée : night shift sur les cartes affichées.
  await page.click('#kb-select');
  await page.waitForSelector('#kb-bulk:not([hidden])');
  await page.click('#kb-bulk button:has-text("Tout ce qui est affiché")');
  await page.waitForTimeout(300);
  const nsel = await page.evaluate(() => state.selected.size);
  await page.selectOption('#kb-bulk select >> nth=1', '1');
  await page.waitForTimeout(800);
  const nights = await page.evaluate(() => [...state.selected].map((id) => cardById(id).night));
  check(`${label} : action groupée (night shift)`, nsel > 0 && nights.length === nsel && nights.every(Boolean), `${nsel} sélectionnées`);
  await shot('17_kanban_selection');
  await page.selectOption('#kb-bulk select >> nth=1', '0');
  await page.waitForTimeout(600);
  await page.click('#kb-bulk button:has-text("Terminer")');
  await page.click('#kb-reset');
  await page.waitForTimeout(300);
  // Détail d'une carte : jalon et échéance.
  const firstId = await page.evaluate(() => Number(document.querySelector('#board .card[data-id]').dataset.id));
  await page.evaluate((id) => openCardDialog(cardById(id), ''), firstId);
  await page.waitForSelector('#card-dialog[open]');
  const hasMs = await page.$$eval('#cf-milestone option', (l) => l.length);
  if (hasMs > 1) {
    await page.selectOption('#cf-milestone', { index: 1 });
    await page.waitForTimeout(600);
  }
  await page.fill('#cf-due', '2026-11-30');
  await page.dispatchEvent('#cf-due', 'change');
  await page.waitForTimeout(800);
  const saved = await page.evaluate((id) => cardById(id), firstId);
  check(`${label} : jalon et échéance enregistrés aussitôt`, saved.due === '2026-11-30' && (hasMs <= 1 || saved.milestone_id > 0), `due ${saved.due}, jalon ${saved.milestone_id}`);
  await shot('18_carte_jalon');
  await page.evaluate(() => closeCardDialog());

  // ------------------------------------------------------------- avis, aide
  await go('#/comments', '#comment-list');
  await shot('19_avis');
  await go('#/aide', '.md-table.api');
  const routes = await page.$$eval('.md-table.api tbody tr', (l) => l.length);
  check(`${label} : page API (routes)`, routes >= 25, String(routes));
  await shot('20_aide');

  check(`${label} : aucune erreur JS`, errors.length === 0, errors.slice(0, 3).join(' | '));
  await context.close();
}
await cr.close();
if (wk) await wk.close();
console.log(fails ? `${fails} échec(s)` : 'tout est vert');
process.exit(fails ? 1 : 0);
