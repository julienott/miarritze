// /producer : page d'un perso (animations, portraits, fin, effets) et galerie
// des animations jouées en aperçu (Chromium, ordinateur + iPhone).
// Env : PRODUCER_URL (défaut http://127.0.0.1:8099/producer/), PRODUCER_TEST_PASSWORD,
//       FIGHTER (défaut karramarro). Captures dans tests/out/producer/.
import { chromium, devices } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';

const BASE = process.env.PRODUCER_URL || 'http://127.0.0.1:8099/producer/';
const PASSWORD = process.env.PRODUCER_TEST_PASSWORD || '';
const FID = process.env.FIGHTER || 'karramarro';
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

// Part des vignettes dont le canvas a des pixels opaques ET qui changent dans le temps.
const animatedShare = (page, sel) => page.evaluate(async (s) => {
  const cs = [...document.querySelectorAll(s)];
  const snap = () => cs.map((c) => {
    const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let h = 0, n = 0;
    for (let i = 0; i < d.length; i += 4) if (d[i + 3]) { n++; h = (h * 31 + i + d[i] + d[i + 1] * 7) | 0; }
    return [n, h];
  });
  const shots = [];
  for (let k = 0; k < 6; k++) { shots.push(snap()); await new Promise((r) => setTimeout(r, 170)); }
  const drawn = shots[0].filter(([n]) => n > 0).length;
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
  await page.waitForSelector('.tile');
  // Vue d'ensemble : une section par combattant, tuiles rangées par famille.
  await page.waitForSelector('.group .group-head');
  const heads = await page.$$eval('.group .group-name', (h) => h.map((x) => x.textContent));
  check(`${label} : une section par combattant à l'ouverture`, heads.length >= 13 && heads.includes(FID), heads.join(','));
  const kinds = await page.$eval(`.group:has(.group-name:text-is("${FID}"))`, (g) => [...g.querySelectorAll('.kind')].map((k) => k.textContent));
  check(`${label} : familles dans l'ordre de la review`,
    kinds[0] === 'Animations' && kinds[1] === 'Portraits' && kinds.includes('Effets des spéciaux'), kinds.join(','));
  await page.screenshot({ path: path.join(OUT, `anims_${label}_combattants.png`) });
  await page.click('.cats button:has-text("Combattants")');
  await page.click(`.cats li.sub button:has(span:text-is("${FID}"))`);
  await page.waitForTimeout(800);
  const ids = await page.$$eval('.tile', (ts) => ts.map((t) => t.dataset.id));
  check(`${label} : la page du perso commence par ses animations`, ids[0] === `fighters/${FID}/sheet.png`, ids[0]);
  check(`${label} : portraits, fin et effets sur la page du perso`,
    ids.some((i) => i.includes('portrait')) && ids.some((i) => i.includes('ending')) && ids.some((i) => i.startsWith(`vfx/${FID}/`)),
    `${ids.length} tuiles`);
  const thumb = await animatedShare(page, '.tile .thumb canvas');
  check(`${label} : vignette du perso animée`, thumb.total === 1 && thumb.moving === 1, JSON.stringify(thumb));
  await page.screenshot({ path: path.join(OUT, `anims_${FID}_${label}_page.png`) });
  await page.click(`.tile[data-id="fighters/${FID}/sheet.png"]`);
  await page.waitForSelector('.anim-gallery .anim-cell');
  await page.waitForTimeout(800);
  const g = await animatedShare(page, '.anim-gallery canvas');
  check(`${label} : galerie, toutes les animations dessinées`, g.total >= 30 && g.drawn === g.total, JSON.stringify(g));
  check(`${label} : galerie, les animations bougent`, g.moving >= g.total - 2, JSON.stringify(g));
  await page.click('.anim-cell:has(span:text-is("punch_1"))');
  await page.waitForTimeout(300);
  check(`${label} : un clic ouvre l'animation dans le lecteur`,
    (await page.$eval('.controls select[aria-label="Animation"]', (s) => s.value)) === 'punch_1');
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: path.join(OUT, `anims_${FID}_${label}_detail.png`), fullPage: true });
  await page.click('.detail-head button:has-text("Retour")');
  await page.waitForSelector('.tile');
  check(`${label} : aucune erreur JavaScript`, errors.length === 0, errors.join(' | '));
  await context.close();
}
await browser.close();
console.log(fails ? `${fails} échec(s)` : 'tout est vert');
process.exit(fails ? 1 : 0);
