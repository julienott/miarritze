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
  await page.waitForSelector('#view-kanban:not([hidden]) .column');
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

// ------------------------------------------------------------------ iPhone
const wk = await webkit.launch();
for (const [name, vp] of [['iphone_portrait', { width: 390, height: 844 }], ['iphone_paysage', { width: 844, height: 390 }]]) {
  const ctx = await wk.newContext({ viewport: vp, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const mp = await ctx.newPage();
  mp.on('dialog', (d) => d.accept());
  await login(mp);
  await mp.waitForSelector(`.card[data-id="${hatId}"]`);
  await mp.locator(`.card[data-id="${hatId}"]`).scrollIntoViewIfNeeded();
  await shot(mp, `05_${name}_board`, false);
  await shot(mp, `06_${name}_board_entier`);
  const over = await mp.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  check(`${name} : pas de défilement horizontal`, !over);
  await mp.locator(`.card[data-id="${kidIds[0]}"] button[aria-label="Colonne suivante"]`).tap();
  await mp.waitForSelector(`.column[data-status=done] .card[data-id="${kidIds[0]}"]`);
  check(`${name} : ▶ au toucher`, true);
  await mp.locator(`.card[data-id="${kidIds[0]}"] button[aria-label="Colonne précédente"]`).tap();
  await mp.waitForSelector(`.column[data-status=qa] .card[data-id="${kidIds[0]}"]`);
  await mp.locator(`.card[data-id="${hatId}"] .title`).tap();
  await mp.waitForSelector('#cf-feed .event');
  await shot(mp, `07_${name}_detail`, false);
  await ctx.close();
}
await wk.close();

check('aucune erreur JS', errors.length === 0, errors.join(' | '));
await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} vérifications OK — captures : ${OUT}`);
process.exit(failed.length ? 1 : 0);
