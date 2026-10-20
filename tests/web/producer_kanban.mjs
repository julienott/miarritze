// Kanban de /producer : colonnes Backlog → Done, cartes chapeau, historique,
// commentaires Julien/Claude, CLI (events), ordinateur + iPhone portrait/paysage.
// Prérequis : service lancé (docs/PRODUCER.md, « Tester en local »).
// Env : PRODUCER_URL, PRODUCER_TEST_PASSWORD, PRODUCER_TOKEN ;
//       PRODUCER_EXPECT_MIGRATION=1 si la base de départ est une base v1 de test
//       (cartes « Ancienne carte … », voir docs/PRODUCER.md) ;
//       PRODUCER_SHOTS : dossier des captures (défaut tests/out/producer_kanban).
import { chromium, webkit } from 'playwright';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

const BASE = process.env.PRODUCER_URL || 'http://127.0.0.1:8099/producer/';
const PASSWORD = process.env.PRODUCER_TEST_PASSWORD || '';
const TOKEN = process.env.PRODUCER_TOKEN || '';
if (!PASSWORD || !TOKEN) {
  console.error('PRODUCER_TEST_PASSWORD et PRODUCER_TOKEN requis');
  process.exit(2);
}
const ROOT = path.resolve(import.meta.dirname, '../..');
const OUT = process.env.PRODUCER_SHOTS || path.join(ROOT, 'tests/out/producer_kanban');
fs.mkdirSync(OUT, { recursive: true });

const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
}
const cli = (...args) => execFileSync('python3', [path.join(ROOT, 'tools/producer/cli.py'), ...args],
  { env: { ...process.env, PRODUCER_URL: BASE, PRODUCER_TOKEN: TOKEN }, encoding: 'utf8' });
const apiTok = async (route, body) => {
  const r = await fetch(BASE + 'index.php?r=' + route, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: 'Bearer ' + TOKEN, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return [r.status, await r.json()];
};
const tag = 'K' + Date.now().toString(36);   // titres uniques : le test peut tourner sur une base non vide
const t0 = Math.floor(Date.now() / 1000) - 1;

async function login(page) {
  await page.goto(BASE + '#/kanban');
  await page.waitForSelector('#login:not([hidden])');
  await page.fill('#password', PASSWORD);
  await page.click('#login-form button[type=submit]');
  await page.waitForSelector('#view-kanban:not([hidden]) #board');
}

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await context.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error' && !/40[0134]/.test(m.text())) errors.push(m.text()); });
page.on('dialog', (d) => d.accept());
const shot = (p, name, full = true) => p.screenshot({ path: path.join(OUT, name + '.png'), fullPage: full });

await login(page);
const cols = await page.$$eval('.column h3 span:first-child', (n) => n.map((x) => x.textContent));
check('5 colonnes', cols.join(',') === 'Backlog,Todo,Doing,QA,Done', cols.join(','));

if (process.env.PRODUCER_EXPECT_MIGRATION === '1') {
  const [, r] = await apiTok('cards');
  const by = Object.fromEntries(r.cards.map((c) => [c.title, c]));
  check('migration : review -> qa', by['Ancienne carte à vérifier']?.status === 'qa');
  check('migration : todo, doing, done gardés', by['Ancienne carte à faire']?.status === 'todo'
    && by['Ancien bug en cours']?.status === 'doing' && by['Ancienne carte faite']?.status === 'done');
  check('migration : notes conservées, agent -> claude',
    by['Ancienne carte à vérifier']?.notes.map((n) => n.author).join(',') === 'claude,julien');
  await shot(page, '00_migration');
}

// ------------------------------------------------- création rapide (Julien)
const hatTitle = `Perso ${tag}`;
await page.fill('.quick-add input', hatTitle);
await page.click('.quick-add button[type=submit]');
const hatCard = page.locator(`.column[data-status=backlog] .card:has-text("${hatTitle}")`);
await hatCard.waitFor();
check('création rapide dans Backlog', true);
check('origine affichée : Julien', (await hatCard.locator('.origin').textContent()) === 'Julien');
const hatId = Number(await hatCard.getAttribute('data-id'));
// Type « perso » via le détail.
await hatCard.locator('.title').click();
await page.waitForSelector('#card-dialog[open]');
await page.selectOption('#cf-type', 'perso');
await page.click('#cf-save');
await page.waitForSelector(`.card[data-id="${hatId}"] .badge.t-perso`);
check('type perso enregistré (badge)', true);

// ------------------------------------------------------ enfants (Claude, CLI)
const kidIds = ['référence', 'run', 'idle'].map((k, i) => Number(/#(\d+)/.exec(cli('add-card', '--type', i ? 'animation' : 'asset',
  '--title', `${tag} ${k}`, '--parent', String(hatId), ...(i === 2 ? ['--status', 'done'] : [])))[1]));
cli('move', String(kidIds[0]), 'review');       // ancien alias -> QA
cli('comment', String(kidIds[1]), 'Cycle de course trop rapide ?');
const shown = cli('show', String(hatId));
check('cli show : enfants et avancement', shown.includes('enfants 2/3') && shown.includes(`${tag} run`), shown.split('\n')[0]);
const [st, cyc] = await apiTok('card_update', { id: hatId, parent: kidIds[0] });
check('boucle de chapeaux refusée (400)', st === 400, cyc.error);

await page.reload();
await page.waitForSelector(`.card[data-id="${hatId}"] .progress`);
const pct = await page.$eval(`.card[data-id="${hatId}"] .progress .bar`, (b) => b.style.width);
check('barre de progression du chapeau (2/3)', pct === '67%', pct);
await page.click(`.card[data-id="${hatId}"] .unfold`);
const kids = await page.$$eval(`.card[data-id="${hatId}"] .kids .kid`, (n) => n.length);
check('chapeau déplié : 3 enfants', kids === 3, String(kids));
const kidCard = page.locator(`.card[data-id="${kidIds[1]}"]`);
check('enfant : nom du parent affiché', (await kidCard.locator('.parent-link').textContent()).includes(hatTitle));
await shot(page, '01_board_chapeau_deplie');

// Lien vers le parent.
await kidCard.locator('.parent-link').click();
await page.waitForSelector('#card-dialog[open]');
check('lien parent : ouvre le chapeau', (await page.textContent('#card-dialog-title')).includes('#' + hatId));
await page.waitForSelector('#cf-children .kid');
await page.click('#cf-cancel');

// Filtre par chapeau et vue « chapeaux seulement ».
await page.selectOption('#kb-hat', String(hatId));
const fam = await page.$$eval('#board .column > .card', (n) => n.map((x) => Number(x.dataset.id)).sort());
check('filtre par chapeau : la famille seulement', fam.length === 4 && fam.includes(hatId), fam.join(','));
await shot(page, '02_filtre_chapeau');
await page.selectOption('#kb-hat', '');
await page.check('#kb-hats-only');
const onlyHats = await page.$$eval('#board .column > .card', (n) => n.map((x) => Number(x.dataset.id)));
check('chapeaux seulement : enfants masqués', onlyHats.includes(hatId) && !kidIds.some((k) => onlyHats.includes(k)));
await shot(page, '03_chapeaux_seulement');
await page.uncheck('#kb-hats-only');

// ------------------------------------ Julien priorise, commente, déplace
await page.locator(`.card[data-id="${hatId}"] button[aria-label="Colonne suivante"]`).click();
await page.waitForSelector(`.column[data-status=todo] .card[data-id="${hatId}"]`);
check('◀ ▶ : chapeau passé en Todo', true);
await page.click(`.card[data-id="${kidIds[1]}"] .title`);
await page.waitForSelector('#cf-feed .note.claude');
await page.selectOption('#cf-priority', 'haute');
await page.click('#cf-save');
await page.waitForSelector(`.card[data-id="${kidIds[1]}"] .badge.haute`);
await page.click(`.card[data-id="${kidIds[1]}"] .title`);
await page.waitForSelector('#cf-feed .note.claude');
await page.fill('#cf-note', 'Oui, ralentis à 8 i/s.\n<b>pas du HTML</b>');
await page.click('#cf-comment-send');
await page.waitForSelector('#cf-feed .note.julien');
const feed = await page.textContent('#cf-feed');
check('fil : création, priorité, commentaires Claude et Julien',
  feed.includes('a créé la carte') && feed.includes('priorité') && feed.includes('Cycle de course') && feed.includes('<b>pas du HTML</b>'));
check('commentaire échappé (pas de <b>)', (await page.$$('#cf-feed b')).length === 0);
await shot(page, '04_detail_fil', false);
await page.click('#cf-cancel');

// Création rapide avec chapeau.
await page.fill('.quick-add input', `${tag} hunter_reveal`);
await page.selectOption('.quick-add select', String(hatId));
await page.click('.quick-add button[type=submit]');
await page.waitForSelector(`.card:has-text("${tag} hunter_reveal") .parent-link`);
check('création rapide avec chapeau', true);
const hunterId = Number(await page.locator(`.card:not(.is-hat):has-text("${tag} hunter_reveal")`).getAttribute('data-id'));

// ------------------------------------------------ boucle de Claude : events
const ev = cli('events', '--since', String(t0));
check('cli events : déplacement en Todo par Julien', new RegExp(`julien +#${hatId} .*déplacement Backlog -> Todo`).test(ev));
check('cli events : commentaire de Julien', ev.includes('Oui, ralentis à 8 i/s.'));
check('cli events : priorité par Julien', /julien .*priorité — -> haute/.test(ev));
const evJson = JSON.parse(cli('events', '--since', String(t0), '--json'));
check('events --json : now + événements', evJson.now >= t0 && evJson.events.length >= 10, String(evJson.events.length));
check('cli cards --parent', cli('cards', '--parent', String(hatId)).trim().split('\n').length === 4);
cli('set', String(kidIds[2]), '--parent', '0');
check('cli set --parent 0 détache', !cli('cards', '--parent', String(hatId)).includes(`${tag} idle`));

// ------------------------------------------- asset lié : vue, détail, commentaire
const ASSET = 'gordeka/persos/louis/animations';
cli('set', String(kidIds[1]), '--asset', ASSET, '--detail', 'walk');
cli('move', String(kidIds[1]), 'qa');
const DECOR = 'gordeka/decor/objets/fronton.png';
const decorId = Number(/#(\d+)/.exec(cli('add-card', '--type', 'asset', '--title', `${tag} fronton masques`, '--asset', DECOR, '--status', 'qa'))[1]);
await page.reload();
const thumb = page.locator(`.card[data-id="${kidIds[1]}"] img.card-thumb`);
await thumb.waitFor();
check('tuile : miniature de l\'asset (image fixe de walk, paresseuse)',
  (await thumb.getAttribute('loading')) === 'lazy' && decodeURIComponent(await thumb.getAttribute('src')).includes('_poster/walk'));
// Survol de la tuile : la miniature joue l'animation, puis s'arrête et se libère.
await page.hover(`.card[data-id="${kidIds[1]}"] .title`);
await page.waitForSelector(`.card[data-id="${kidIds[1]}"] canvas.card-thumb`);
const moving = await page.evaluate(async (id) => {
  const c = document.querySelector(`.card[data-id="${id}"] canvas.card-thumb`);
  const snap = () => c.toDataURL().length + ':' + c.toDataURL().slice(-80);
  const a = snap();
  await new Promise((r) => setTimeout(r, 400));
  return a !== snap();
}, kidIds[1]);
check('tuile : l\'animation joue au survol', moving && (await page.$$('#board canvas')).length === 1);
await shot(page, '04a_tuile_survol', false);
await page.mouse.move(2, 2);
await page.waitForTimeout(150);
check('tuile : souris sortie = animation arrêtée et libérée',
  (await page.$$('#board canvas')).length === 0 && !!(await page.$(`.card[data-id="${kidIds[1]}"] img.card-thumb`)));
// Décor avec masques : les masques apparaissent au survol, chargés à ce moment-là.
const dthumb = `.card[data-id="${decorId}"] .dthumb`;
check('tuile décor : masques non chargés au repos', !(await page.getAttribute(`${dthumb} img.calque`, 'src')));
await page.hover(`.card[data-id="${decorId}"] .title`);
await page.waitForFunction((s) => { const i = document.querySelector(s + ' img.calque'); return i && i.complete && i.naturalWidth > 0; }, dthumb);
check('tuile décor : masques au survol', await page.$eval(dthumb, (b) => b.classList.contains('masks') && getComputedStyle(b.querySelector('.calque')).visibility === 'visible'));
await shot(page, '04a_tuile_decor_masques', false);
await page.mouse.move(2, 2);
check('tuile décor : masques cachés au départ de la souris', !(await page.$eval(dthumb, (b) => b.classList.contains('masks'))));
await page.click(`.card[data-id="${kidIds[1]}"] .title`);
await page.waitForSelector('#cf-asset-view:not([hidden]) .anim-cell img.mini');
check('détail : champ « détail » = walk', (await page.inputValue('#cf-detail')) === 'walk');
await page.hover('#cf-asset-view .anim-cell');
await page.waitForSelector('#cf-asset-view .anim-cell canvas.mini');
check('détail : l\'animation de l\'asset joue au survol', true);
await page.fill('#cf-asset-view .comment-form textarea', `${tag} : les pieds glissent`);
await page.click('#cf-asset-view .comment-form button[type=submit]');
await page.waitForSelector(`#cf-asset-view .comment:has-text("${tag} : les pieds glissent")`);
const [, cm] = await apiTok('comments');
const mine = cm.comments.find((c) => c.body === `${tag} : les pieds glissent`);
check('commentaire d\'asset depuis la carte (version + anim)', mine && mine.asset === ASSET && mine.version && mine.context === 'anim : walk', JSON.stringify(mine && [mine.version, mine.context]));
await shot(page, '04b_detail_asset', false);
await page.click('#cf-asset-view .anim-cell');
await page.waitForSelector('.fs canvas');
check('détail : clic sur l\'animation = plein écran', (await page.textContent('.fs-title')) === 'louis · walk');
await page.click('.fs-close');

// ----------------------------------------------------- QA : refuser, retraiter, accepter
const qaCard = page.locator(`.card[data-id="${kidIds[1]}"]`);
check('QA : boutons Accepter et Refuser sur la tuile', await qaCard.locator('button.accept').isVisible() && await qaCard.locator('button.refuse').isVisible());
await shot(page, '04c_board_qa');
await qaCard.locator('button.refuse').click();
await page.waitForSelector('#refuse-dialog[open]');
await page.click('#rf-send');
check('refus sans commentaire bloqué', (await page.textContent('#rf-error')).length > 0);
await page.fill('#rf-body', 'La marche glisse encore, pieds à recaler.');
await shot(page, '04d_refus', false);
await page.click('#rf-send');
await page.waitForSelector(`.column[data-status=doing] .card[data-id="${kidIds[1]}"] .rework`);
check('refus : retour en Doing, badge « à retraiter »', true);
const refused = cli('show', String(kidIds[1]));
check('cli show : refus visible', refused.includes('[À RETRAITER]') && refused.includes('REFUSÉE') && refused.includes('pieds à recaler'));
cli('qa', String(kidIds[1]), 'pieds recalés sur feet_anchor');
const back = JSON.parse(cli('show', String(kidIds[1]), '--json'));
check('cli qa : retour en QA, badge effacé, commentaire « retraité : »', back.card.status === 'qa' && !back.card.rework
  && back.card.notes.some((n) => n.body === 'retraité : pieds recalés sur feet_anchor'));
// Chapeau en QA : Accepter accepte aussi les enfants encore en QA (après confirmation).
cli('move', String(hatId), 'qa');
await page.reload();
const msgs = [];
page.removeAllListeners('dialog');
page.on('dialog', (d) => { msgs.push(d.message()); d.accept(); });
await page.locator(`.card[data-id="${hatId}"] button.accept`).click();
await page.waitForSelector(`.column[data-status=done] .card[data-id="${hatId}"]`);
const st2 = Object.fromEntries((await apiTok('cards'))[1].cards.map((c) => [c.id, c.status]));
check('chapeau accepté avec confirmation (2 enfants en QA)', msgs.some((m) => m.includes('2 enfants')), msgs.join(' | '));
check('chapeau + enfants en QA -> Done, les autres restent', st2[hatId] === 'done' && st2[kidIds[0]] === 'done'
  && st2[kidIds[1]] === 'done' && st2[hunterId] === 'backlog', JSON.stringify([st2[hatId], st2[kidIds[0]], st2[kidIds[1]], st2[hunterId]]));
const [stBad] = await apiTok('card_accept', { id: hunterId });
check('accepter hors QA refusé (400)', stBad === 400, String(stBad));
const evq = JSON.parse(cli('events', '--since', String(t0), '--json')).events;
check('events : types accepte et refuse (avec le texte)', evq.filter((e) => e.type === 'accepte').length === 3
  && evq.some((e) => e.type === 'refuse' && e.author === 'julien' && e.new.includes('pieds à recaler')));
check('cli events : ACCEPTÉE / REFUSÉE lisibles', /ACCEPTÉE/.test(cli('events', '--since', String(t0))) && /REFUSÉE QA -> Doing/.test(cli('events', '--since', String(t0))));

// ------------------------------------------------------------------ iPhone
// Vue mobile : une colonne à la fois, onglets collants, tuiles compactes.
for (let k = 1; k <= 8; k++) {
  cli('add-card', '--type', 'animation', '--title', `${tag} QA mobile ${k}`, '--asset', ASSET, '--detail', 'walk', '--status', 'qa');
}
const wk = await webkit.launch();
for (const [name, vp] of [['iphone_portrait', { width: 390, height: 844 }], ['iphone_paysage', { width: 844, height: 390 }]]) {
  const ctx = await wk.newContext({ viewport: vp, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const mp = await ctx.newPage();
  mp.on('dialog', (d) => d.accept());
  await login(mp);
  await mp.waitForSelector('#kb-tabs:not([hidden]) .kb-tab.active');
  const tabs = await mp.$$eval('#kb-tabs .kb-tab[data-status]', (l) => l.map((t) => [t.dataset.status, t.getBoundingClientRect().height]));
  check(`${name} : 5 onglets assez grands`, tabs.length === 5 && tabs.every(([, h]) => h >= 40), JSON.stringify(tabs));
  check(`${name} : QA ouvert par défaut (cartes à tester)`, (await mp.getAttribute('.kb-tab.active', 'data-status')) === 'qa');
  const shown = await mp.$$eval('.column', (l) => l.filter((c) => c.getBoundingClientRect().height > 0).length);
  check(`${name} : une seule colonne à l'écran`, shown === 1, String(shown));
  const fit = await mp.evaluate(() => [...document.querySelectorAll('.column.active .card')]
    .filter((c) => { const b = c.getBoundingClientRect(); return b.top >= 0 && b.bottom <= innerHeight; }).length);
  check(`${name} : cartes à l'écran (≥ ${name.endsWith('portrait') ? 8 : 4})`, fit >= (name.endsWith('portrait') ? 8 : 4), String(fit));
  const btn = await mp.$eval('.column.active .card.compact button.accept', (b) => b.getBoundingClientRect().height);
  check(`${name} : ✓ / ✗ sur la tuile, au doigt`, btn >= 40, String(btn));
  const over = await mp.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  check(`${name} : pas de défilement horizontal`, !over);
  await shot(mp, `05_${name}_board`, false);
  // Onglet Backlog, puis « déplacer vers… » sans ouvrir la carte.
  await mp.locator('.kb-tab[data-status=backlog]').tap();
  await mp.waitForSelector(`.column.active[data-status=backlog] .card[data-id="${hunterId}"]`);
  await mp.selectOption(`.card[data-id="${hunterId}"] select.move`, 'todo');
  await mp.waitForSelector(`.column[data-status=todo] .card[data-id="${hunterId}"]`, { state: 'attached' });
  check(`${name} : déplacer vers… (menu de la tuile)`, (await apiTok('cards'))[1].cards.find((c) => c.id === hunterId).status === 'todo');
  await mp.reload();
  await mp.waitForSelector('#kb-tabs .kb-tab.active');
  check(`${name} : onglet mémorisé`, (await mp.getAttribute('.kb-tab.active', 'data-status')) === 'backlog');
  await mp.selectOption(`.card[data-id="${hunterId}"] select.move`, 'backlog').catch(() => {});
  await mp.locator('.kb-tab[data-status=todo]').tap();
  await mp.selectOption(`.card[data-id="${hunterId}"] select.move`, 'backlog');
  await mp.waitForSelector(`.column[data-status=backlog] .card[data-id="${hunterId}"]`, { state: 'attached' });
  // Filtres repliés derrière ☰.
  check(`${name} : filtres repliés`, !(await mp.isVisible('.kanban-bar')));
  await mp.locator('.kb-tab.kb-filters').tap();
  check(`${name} : ☰ déplie les filtres`, await mp.isVisible('#kb-hat'));
  await shot(mp, `06_${name}_filtres`, false);
  await mp.locator('.kb-tab.kb-filters').tap();
  // Miniature au toucher : anime sans ouvrir la carte ; décor : masques au toucher.
  await mp.locator('.kb-tab[data-status=qa]').tap();
  const anim = mp.locator('.column.active .card.compact').filter({ hasText: `${tag} QA mobile` }).nth(1);
  await anim.locator('.thumb-box').tap();
  await mp.waitForSelector('.column.active canvas.card-thumb');
  check(`${name} : miniature animée au premier toucher, carte fermée`, !(await mp.$('#card-dialog[open]')));
  await mp.locator(`.card[data-id="${decorId}"]`).scrollIntoViewIfNeeded().catch(() => {});
  if (await mp.$(`.card[data-id="${decorId}"] .dthumb`)) {
    await mp.locator(`.card[data-id="${decorId}"] .dthumb`).tap();
    await mp.waitForTimeout(300);
    check(`${name} : décor, masques au toucher`, await mp.$eval(`.card[data-id="${decorId}"] .dthumb`, (b) => b.classList.contains('masks'))
      && !(await mp.$('#card-dialog[open]')));
    await shot(mp, `06b_${name}_miniatures`, false);
  }
  await mp.evaluate(() => scrollTo(0, 0));
  // Détail plein écran : asset en haut, Accepter / Refuser collés en bas, ← pour fermer.
  const qc = mp.locator('.column.active .card.compact').filter({ hasText: `${tag} QA mobile` }).first();
  const qid = Number(await qc.getAttribute('data-id'));
  await qc.locator('.title').tap();
  await mp.waitForSelector('#cf-asset-view .anim-cell img.mini');
  const geo = await mp.evaluate(() => {
    const r = (s) => document.querySelector(s).getBoundingClientRect();
    return { w: r('#card-dialog').width, vw: innerWidth, asset: r('#cf-asset-view').top, form: r('#card-form').top,
      bar: r('#cf-qa-bar').bottom, vh: innerHeight, back: r('#cf-back').height };
  });
  check(`${name} : détail plein écran, asset en haut`, Math.abs(geo.w - geo.vw) < 2 && geo.asset < geo.form, JSON.stringify(geo));
  check(`${name} : Accepter / Refuser collés en bas`, Math.abs(geo.bar - geo.vh) < 2, JSON.stringify(geo));
  await shot(mp, `07_${name}_detail`, false);
  await mp.locator('#cf-back').tap();
  check(`${name} : ← ferme le détail`, !(await mp.$('#card-dialog[open]')));
  await qc.locator('.title').tap();
  await mp.waitForSelector('#cf-qa-bar:not([hidden])');
  await mp.locator('#cf-accept2').tap();
  await mp.waitForFunction(() => !document.querySelector('#card-dialog[open]'));
  check(`${name} : Accepter depuis la barre collante`, (await apiTok('cards'))[1].cards.find((c) => c.id === qid).status === 'done');
  await ctx.close();
}
await wk.close();
// Balayage horizontal (Chromium : WebKit ne construit pas de TouchEvent depuis un script).
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const mp = await ctx.newPage();
  await login(mp);
  await mp.waitForSelector('#kb-tabs .kb-tab.active');
  const before = await mp.getAttribute('.kb-tab.active', 'data-status');
  const swipe = (x0, x1) => mp.evaluate(([x0, x1]) => {
    const b = document.getElementById('board');
    const mk = (type, x) => {
      const t = new Touch({ identifier: 1, target: b, clientX: x, clientY: 400 });
      b.dispatchEvent(new TouchEvent(type, { touches: type === 'touchend' ? [] : [t], changedTouches: [t], bubbles: true }));
    };
    mk('touchstart', x0); mk('touchend', x1);
  }, [x0, x1]);
  await swipe(320, 80);
  const after = await mp.getAttribute('.kb-tab.active', 'data-status');
  check('mobile : balayage à gauche = colonne suivante', before === 'qa' && after === 'done', `${before} -> ${after}`);
  await swipe(80, 320);
  check('mobile : balayage à droite = colonne précédente', (await mp.getAttribute('.kb-tab.active', 'data-status')) === 'qa');
  await ctx.close();
}

check('aucune erreur JS', errors.length === 0, errors.join(' | '));
await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} vérifications OK — captures : ${OUT}`);
process.exit(failed.length ? 1 : 0);
