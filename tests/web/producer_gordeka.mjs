// /producer : ouverture sur Gordeka (persos, animations HD, masques de tenue,
// profils validés et candidats, carte, chorégraphies) et Borroka toujours accessible
// (Chromium, ordinateur + iPhone).
// Env : PRODUCER_URL (défaut http://127.0.0.1:8099/producer/), PRODUCER_TEST_PASSWORD.
// Captures dans tests/out/producer/.
import { chromium, devices } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';

const BASE = process.env.PRODUCER_URL || 'http://127.0.0.1:8099/producer/';
const PASSWORD = process.env.PRODUCER_TEST_PASSWORD || '';
if (!PASSWORD) {
  console.error('PRODUCER_TEST_PASSWORD requis');
  process.exit(2);
}
const ROOT = path.resolve(import.meta.dirname, '../..');
const OUT = path.join(ROOT, 'tests/out/producer');
fs.mkdirSync(OUT, { recursive: true });
let fails = 0;
const check = (name, ok, detail = '') => {
  if (!ok) fails++;
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
};

// Canvas dessinés (pixels opaques) et qui changent dans le temps.
const animated = (page, sel) => page.evaluate(async (s) => {
  const cs = [...document.querySelectorAll(s)];
  const snap = () => cs.map((c) => {
    const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let h = 0, n = 0;
    for (let i = 0; i < d.length; i += 16) if (d[i + 3]) { n++; h = (h * 31 + i + d[i] + d[i + 1] * 7) | 0; }
    return [n, h];
  });
  const shots = [];
  for (let k = 0; k < 6; k++) { shots.push(snap()); await new Promise((r) => setTimeout(r, 120)); }
  const drawn = shots[shots.length - 1].filter(([n]) => n > 0).length;
  const moving = cs.filter((_, i) => new Set(shots.map((x) => x[i].join(':'))).size > 1).length;
  return { total: cs.length, drawn, moving };
}, sel);

const browser = await chromium.launch();
for (const [label, opts] of [['ordi', { viewport: { width: 1280, height: 900 } }], ['iphone', devices['iPhone 13']]]) {
  const context = await browser.newContext(opts);
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(BASE);
  await page.waitForSelector('#login:not([hidden])');
  await page.fill('#password', PASSWORD);
  await page.click('#login-form button[type=submit]');
  await page.waitForSelector('.group .group-head');
  await page.waitForTimeout(1500);

  // Ouverture : les persos de Gordeka, une section par perso, Louis en premier.
  const active = await page.$eval('.cats button.active span', (s) => s.textContent);
  check(`${label} : ouverture sur les persos de Gordeka`, active === 'Persos', active);
  const sections = await page.$$eval('.cats li.section', (l) => l.map((x) => x.textContent));
  check(`${label} : sections Gordeka puis Borroka`, sections[0] === 'Gordeka' && sections.includes('Borroka'), sections.join(','));
  const heads = await page.$$eval('.group .group-name', (h) => h.map((x) => x.textContent));
  check(`${label} : une section par perso, Louis d'abord`, heads[0] === 'louis' && heads.length >= 5, heads.join(','));
  const kinds = await page.$eval('.group:has(.group-name:text-is("louis"))', (g) => [...g.querySelectorAll('.kind')].map((k) => k.textContent));
  check(`${label} : Louis, animations puis masques`, kinds[0] === 'Animations' && kinds[1] === 'Masques', kinds.join(','));
  const thumb = await animated(page, '#grid > .group:first-child .tile .thumb canvas');
  check(`${label} : vignettes de Louis animées`, thumb.total === 2 && thumb.moving === 2, JSON.stringify(thumb));
  const kinds2 = await page.$$eval('.group .kind', (k) => [...new Set(k.map((x) => x.textContent))]);
  check(`${label} : profils validés présents`, kinds2.includes('Profil validé'), kinds2.join(','));
  if (!kinds2.includes('Profils candidats')) console.log('     (pas de profils candidats : tools/rd/out absent)');
  await page.screenshot({ path: path.join(OUT, `gordeka_${label}_ouverture.png`) });

  // Lecteur : animations de Louis (galerie et lecteur).
  await page.click('.tile[data-id="gordeka/persos/louis/animations"]');
  await page.waitForSelector('.anim-gallery .anim-cell');
  await page.waitForTimeout(1500);
  const g = await animated(page, '.anim-gallery canvas');
  check(`${label} : galerie, toutes les animations dessinées`, g.total >= 13 && g.drawn === g.total, JSON.stringify(g));
  check(`${label} : galerie, les animations bougent`, g.moving >= g.total - 2, JSON.stringify(g));
  const p = await animated(page, '.stage canvas');
  check(`${label} : le lecteur joue`, p.drawn === 1 && p.moving === 1, JSON.stringify(p));
  const fits = await page.$eval('.stage canvas', (c) => c.getBoundingClientRect().width <= window.innerWidth);
  check(`${label} : le lecteur tient dans l'écran`, fits);
  await page.click('.anim-cell:has(span:text-is("walk"))');
  await page.waitForTimeout(300);
  check(`${label} : un clic ouvre l'animation dans le lecteur`,
    (await page.$eval('.controls select[aria-label="Animation"]', (s) => s.value)) === 'walk');
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: path.join(OUT, `gordeka_${label}_louis_anims.png`) });

  // Masques de tenue.
  await page.goto(BASE + '#/assets/' + encodeURIComponent('gordeka/persos/louis/masques'));
  await page.waitForSelector('.anim-gallery .anim-cell');
  await page.waitForTimeout(1200);
  const m = await animated(page, '.stage canvas');
  check(`${label} : masque de tenue affiché`, m.drawn === 1, JSON.stringify(m));
  await page.screenshot({ path: path.join(OUT, `gordeka_${label}_louis_masques.png`) });

  // Carte : aperçu rendu depuis map.txt.
  await page.goto(BASE + '#/assets/' + encodeURIComponent('maps/port_pecheurs/map.txt'));
  await page.waitForSelector('.stage img');
  const map = await page.$eval('.stage img', (i) => i.decode().then(() => [i.naturalWidth, i.naturalHeight]));
  check(`${label} : aperçu de la carte`, map[0] > 0 && map[1] > 0, map.join('×'));
  await page.screenshot({ path: path.join(OUT, `gordeka_${label}_carte.png`) });

  // Chorégraphie (JSON en texte).
  await page.goto(BASE + '#/assets/' + encodeURIComponent('gordeka/choreo/walk.json'));
  await page.waitForFunction(() => (document.querySelector('pre.data') || {}).textContent?.includes('"tracks"'));
  check(`${label} : chorégraphie lisible`, true);

  // Borroka reste accessible.
  await page.goto(BASE + '#/assets');
  await page.click('.cats button:has-text("Combattants")');
  await page.waitForSelector('.tile[data-id="fighters/maia/sheet.png"]');
  check(`${label} : combattants de Borroka accessibles`, true);
  check(`${label} : aucune erreur JavaScript`, errors.length === 0, errors.join(' | '));
  await context.close();
}
await browser.close();
console.log(fails ? `${fails} échec(s)` : 'tout est vert');
process.exit(fails ? 1 : 0);
