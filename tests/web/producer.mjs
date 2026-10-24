// Test bout en bout du service /producer (Chromium).
// Prérequis : service lancé (voir docs/PRODUCER.md, « Tester en local »), base vide.
// Env : PRODUCER_URL (défaut http://127.0.0.1:8099/producer/), PRODUCER_TEST_PASSWORD,
//       PRODUCER_TOKEN. Captures dans tests/out/producer/.
import { chromium } from 'playwright';
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
const OUT = process.env.PRODUCER_SHOTS || path.join(ROOT, 'tests/out/producer');
fs.mkdirSync(OUT, { recursive: true });

const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
}
const cli = (...args) => execFileSync('python3', [path.join(ROOT, 'tools/producer/cli.py'), ...args],
  { env: { ...process.env, PRODUCER_URL: BASE, PRODUCER_TOKEN: TOKEN }, encoding: 'utf8' });
const url = (q) => BASE + 'index.php?' + q;
// Assets de Blackout servis par le build (Borroka retiré le 22/10).
const PERSO = 'blackout/persos/patxi/animations';
const FICHE = '#/assets/' + encodeURIComponent(PERSO) + '/run';

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 860 } });
const page = await context.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error' && !/401|403|404/.test(m.text())) errors.push(m.text()); });
const shot = (name) => page.screenshot({ path: path.join(OUT, name + '.png') });

// ------------------------------------------------------------- connexion
await page.goto(BASE);
await page.waitForSelector('#login:not([hidden])');
await shot('01_login');
await page.fill('#password', 'mauvais-mot-de-passe');
await page.click('#login-form button[type=submit]');
await page.waitForFunction(() => document.getElementById('login-error').textContent.length > 0);
check('mauvais mot de passe refusé', (await page.textContent('#login-error')).includes('incorrect'));
await shot('02_login_refuse');
await page.fill('#password', PASSWORD);
await page.click('#login-form button[type=submit]');
await page.waitForSelector('#tabs:not([hidden])');
await page.waitForSelector('.kpi-tile');
check('connexion avec le bon mot de passe', true);
const cookies = await context.cookies();
const sid = cookies.find((c) => c.name === 'producer_sid');
check('cookie HttpOnly + SameSite=Strict', sid && sid.httpOnly && sid.sameSite === 'Strict');
await shot('03_assets_grille');

// ------------------------------------------------------ perso colorisé
await page.goto(BASE + FICHE);
await page.waitForSelector('.fiche-main .stage canvas');
await page.waitForTimeout(600);
const colored = await page.evaluate(() => {
  const c = document.querySelector('.fiche-main .stage canvas');
  const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
  let px = 0; let chroma = 0;
  for (let i = 0; i < d.length; i += 4) {
    if (d[i + 3] > 0) { px++; if (Math.abs(d[i] - d[i + 1]) > 20 || Math.abs(d[i + 1] - d[i + 2]) > 20) chroma++; }
  }
  return { px, chroma };
});
check('sprite de Patxi colorisé (pixels de couleur)', colored.px > 100 && colored.chroma > colored.px * 0.3, JSON.stringify(colored));
await shot('04_patxi_run');

// --------------------------------------------- commentaire (avec tentative XSS)
// Base vide : l'amélioration crée une carte en Backlog liée à l'animation ; le texte s'affiche échappé.
const xss = '<img src=x onerror="window.__xss=1">Bras trop long <script>window.__xss=2</script>';
await page.fill('.fiche-side .pilot-form textarea', xss);
await page.click('.fiche-side .pilot-form button[type=submit]');
await page.waitForSelector('.fiche-side .lcard');
await page.waitForFunction(() => state.comments.length === 1);
const xssState = await page.evaluate(() => ({
  flag: window.__xss,
  card: state.cards.length === 1 && state.cards[0].description.includes('<script>'),
  imgs: document.querySelectorAll('.fiche-side img[src="x"], .fiche-main img[src="x"]').length,
}));
check('commentaire enregistré et XSS affiché échappé', xssState.flag === undefined && xssState.imgs === 0 && xssState.card, JSON.stringify(xssState));
// Un « validé » sans texte est accepté (reporté sur la carte créée).
await page.click('.fiche-side .pilot-form .kind-pick button[data-kind=valide]');
await page.click('.fiche-side .pilot-form button[type=submit]');
await page.waitForFunction(() => state.comments.length === 2);
check('« validé » sans texte accepté', true);
await shot('05_patxi_commentaires');

// Requête partielle (Safari, audio) : 206 sur un fichier servi.
const someFile = await page.evaluate(() => state.index.files.find((f) => f.endsWith('.png')));
const range = await page.evaluate(async (u) => {
  const r = await fetch(u, { headers: { Range: 'bytes=0-99' } });
  return [r.status, r.headers.get('content-range'), (await r.arrayBuffer()).byteLength];
}, url('r=file&p=' + encodeURIComponent(someFile)));
check('Range 206 sur un fichier servi', range[0] === 206 && range[2] === 100, JSON.stringify(range));

// ---------------------------------------------------------------- kanban
await page.goto(BASE + '#/kanban');
await page.click('#new-card');
await page.fill('#cf-title', 'Ajouter un costume d\'été à Peio');
await page.fill('#cf-desc', 'Maillot rayé, lunettes.\n<b>pas du HTML</b>');
await page.selectOption('#cf-priority', 'normale');
await page.fill('#cf-asset', 'blackout/persos/peio/animations');
await page.dispatchEvent('#cf-asset', 'change');   // l'aperçu de l'asset s'affiche avant le clic (pas de saut de mise en page)
await page.click('#cf-save');
await page.waitForSelector('.column[data-status=backlog] .card:has-text("costume d\'été")');
check('carte créée dans « Backlog »', true);
const card = page.locator('.card:has-text("costume d\'été")');
await card.locator('button[aria-label="Colonne suivante"]').click();
await page.waitForSelector('.column[data-status=todo] .card:has-text("costume d\'été")');
check('carte déplacée par bouton vers « Todo »', true);
await page.dragAndDrop('.column[data-status=todo] .card:has-text("costume d\'été")', '.column[data-status=qa]');
await page.waitForSelector('.column[data-status=qa] .card:has-text("costume d\'été")');
check('carte déplacée par glisser-déposer vers « QA »', true);
await shot('08_kanban');

// ----------------------------------------------------------- agent (cli.py)
const listed = cli('comments', '--open');
check('cli comments --open', listed.includes(PERSO) && listed.includes('Bras trop long'));
const cid = Number(/#(\d+) \[open\] amelioration/.exec(listed)[1]);
cli('reply', String(cid), 'Bras raccourcis de 2 px (exemple)', '--done');
const cards = cli('cards', '--full');
check('cli cards', cards.includes('costume d\'été'));
const kid = Number(/#(\d+) \[QA\]/.exec(cards)[1]);
cli('comment', String(kid), 'Palette prête, à valider');
cli('move', String(kid), 'done');   // le déploiement groupé : Validé -> En prod
const after = cli('comments');
check('cli reply + done', after.includes('[done]') && after.includes('Bras raccourcis'));
await page.goto(BASE + '#/comments');
await page.reload();
await page.waitForSelector('#view-comments:not([hidden])');
await page.uncheck('#only-open');
await page.waitForSelector('.comment .reply');
check('réponse de l\'agent visible', (await page.textContent('.comment .reply')).includes('Bras raccourcis'));
await shot('09_commentaires');
await page.goto(BASE + '#/kanban');
await page.waitForSelector('.column[data-status=done] .card:has-text("costume d\'été")');
await page.click('.column[data-status=done] .card:has-text("costume d\'été")');
await page.waitForSelector('#card-dialog[open] .note.claude');
check('commentaire de Claude visible sur la carte', true);
await shot('10_carte_notes');
await page.click('#cf-cancel');

// --------------------------------------------------------------- mobile
const mobile = await browser.newContext({
  viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
  storageState: await context.storageState(),
});
const mp = await mobile.newPage();
await mp.goto(BASE + '#/assets');
await mp.waitForSelector('.citem');
await mp.screenshot({ path: path.join(OUT, '11_mobile_assets.png') });
await mp.goto(BASE + FICHE);
await mp.waitForSelector('.fiche-main .stage canvas');
await mp.waitForTimeout(600);
await mp.screenshot({ path: path.join(OUT, '12_mobile_patxi.png'), fullPage: true });
await mp.goto(BASE + '#/kanban');
await mp.waitForSelector('.column.active');
await mp.screenshot({ path: path.join(OUT, '13_mobile_kanban.png'), fullPage: true });
const hscroll = await mp.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
check('mobile : pas de défilement horizontal', !hscroll);
await mobile.close();

// --------------------------------------------------------------- sécurité
const csrf = await page.evaluate(async () => (await (await fetch('index.php?r=session')).json()).csrf);
const noCsrf = await page.evaluate(async () => (await fetch('index.php?r=comment', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ asset: 'blackout/persos/louis/animations', kind: 'valide', body: 'x' }) })).status);
check('écriture sans CSRF refusée (403)', noCsrf === 403, String(noCsrf));
const badCsrf = await page.evaluate(async () => (await fetch('index.php?r=card', {
  method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': 'faux' },
  body: JSON.stringify({ type: 'bug', title: 'x' }) })).status);
check('écriture avec mauvais CSRF refusée (403)', badCsrf === 403, String(badCsrf));
check('jeton CSRF disponible', csrf && csrf.length === 64);
for (const p of ['../config.php', 'fighters/maia/../../config.php', '..%2Fconfig.php', '/etc/passwd',
  'index.json/../../config.php', '../data/producer.sqlite', '../lib/app.php']) {
  const st = await page.evaluate(async (u) => (await fetch(u)).status, url('r=file&p=' + encodeURIComponent(p)));
  check(`traversée refusée : ${p}`, st === 404, String(st));
}
const anon = await browser.newContext();
const ap = await anon.newPage();
await ap.goto(BASE);
for (const [r, m] of [['comments', 'GET'], ['cards', 'GET'], ['index', 'GET'], ['card', 'POST']]) {
  const st = await ap.evaluate(async ([u, method]) => (await fetch(u, { method, body: method === 'POST' ? '{}' : undefined })).status, [url('r=' + r), m]);
  check(`sans session ni jeton : ${m} ${r} -> 401`, st === 401, String(st));
}
const fileAnon = await ap.evaluate(async (u) => (await fetch(u)).status, url('r=file&p=' + encodeURIComponent(someFile)));
check('fichier d\'aperçu sans session -> 401', fileAnon === 401, String(fileAnon));
const badTok = await ap.evaluate(async (u) => (await fetch(u, { headers: { Authorization: 'Bearer faux-jeton' } })).status, url('r=cards'));
check('API avec mauvais jeton -> 401', badTok === 401, String(badTok));

// ----------------------------------------------------------- déconnexion
await page.goto(BASE + '#/assets');
await page.waitForSelector('#logout:not([hidden])');
await page.click('#logout');
await page.waitForSelector('#login:not([hidden])');
const afterLogout = await page.evaluate(async (u) => (await fetch(u)).status, url('r=cards'));
check('déconnexion : API refusée ensuite', afterLogout === 401, String(afterLogout));
await shot('14_deconnecte');

// Limitation : 1 échec déjà (mauvais jeton ; la connexion réussie a remis le
// compteur à zéro) ; 4 de plus -> 5 échecs, la 6e tentative reçoit 429.
const statuses = [];
for (let i = 0; i < 5; i++) {
  statuses.push(await ap.evaluate(async (u) => {
    const s = await (await fetch(u + 'session')).json();
    return (await fetch(u + 'login', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': s.csrf },
      body: JSON.stringify({ password: 'non' }) })).status;
  }, url('r=')));
}
check('limitation des tentatives (429 après 5 échecs)', statuses.at(-1) === 429, statuses.join(','));

check('aucune erreur JS', errors.length === 0, errors.join(' | '));
await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} vérifications OK`);
process.exit(failed.length ? 1 : 0);
