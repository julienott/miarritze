// /producer : Gordeka d'abord (persos, récapitulatif des animations, animations
// manquantes, lecteur plein écran, décor avec ou sans masques, filtre « sans masque »,
// sols répétés 2×2), Borroka replié mais accessible.
// Ordinateur (Chromium) + iPhone portrait et paysage (WebKit si installé, sinon Chromium).
// Env : PRODUCER_URL (défaut http://127.0.0.1:8099/producer/), PRODUCER_TEST_PASSWORD,
//       PRODUCER_SHOTS (dossier des captures, défaut tests/out/producer).
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
const OUT = process.env.PRODUCER_SHOTS || path.join(ROOT, 'tests/out/producer');
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
  for (let k = 0; k < 8; k++) { shots.push(snap()); await new Promise((r) => setTimeout(r, 120)); }
  const drawn = shots[shots.length - 1].filter(([n]) => n > 0).length;
  const moving = cs.filter((_, i) => new Set(shots.map((x) => x[i].join(':'))).size > 1).length;
  return { total: cs.length, drawn, moving };
}, sel);

let wk = null;
try { wk = await webkit.launch(); } catch (e) { console.log('     (WebKit indisponible : iPhone émulé dans Chromium)'); }
const cr = await chromium.launch();
const runs = [
  ['ordi', cr, { viewport: { width: 1366, height: 900 } }],
  ['iphone_portrait', wk || cr, devices['iPhone 13']],
  ['iphone_paysage', wk || cr, devices['iPhone 13 landscape']],
];
for (const [label, browser, opts] of runs) {
  const context = await browser.newContext(opts);
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  // WebKit signale les styles internes des <select> du formulaire de carte (CSP) : sans effet.
  page.on('console', (m) => {
    if (m.type() === 'error' && !(browser === wk && m.text().startsWith('Refused to apply a stylesheet'))) errors.push(m.text());
  });
  const shot = (n, full = false) => page.screenshot({ path: path.join(OUT, `${label}_${n}.png`), fullPage: full });
  await page.goto(BASE);
  await page.waitForSelector('#login:not([hidden])');
  await page.fill('#password', PASSWORD);
  await page.click('#login-form button[type=submit]');
  await page.waitForSelector('.gk-perso');
  await page.waitForTimeout(1500);

  // Ouverture : persos de Gordeka, récapitulatif, une section par perso dans l'ordre du casting.
  const active = await page.$eval('.cats button.active span', (s) => s.textContent);
  check(`${label} : ouverture sur les persos`, active === 'Persos', active);
  const persos = await page.$$eval('.gk-perso', (l) => l.map((x) => x.dataset.perso));
  check(`${label} : 12 persos dans l'ordre`, persos.length === 12 && persos[0] === 'louis' && persos[11] === 'peio', persos.join(','));
  const recap = await page.$$eval('.recap-table tbody tr', (r) => r.length);
  const cols = await page.$$eval('.recap-table thead th.v', (r) => r.length);
  check(`${label} : récapitulatif perso × animation`, recap === 12 && cols === 23, `${recap} lignes, ${cols} colonnes`);
  const louis = await page.$eval('.gk-perso[data-perso="louis"]', (s) => ({
    present: s.querySelectorAll('.gk-anim:not(.missing)').length,
    missing: [...s.querySelectorAll('.gk-anim.missing')].map((x) => x.dataset.anim),
    band: s.querySelector('.missing-band').textContent,
    profil: !!s.querySelector('.gk-profil .tile'),
  }));
  check(`${label} : Louis, profil et animations`, louis.profil && louis.present >= 15, JSON.stringify(louis.present));
  // Manquantes : celles que l'index ne contient pas (les données bougent chaque jour).
  const attendu = await page.evaluate(() => Object.fromEntries(['louis', 'amaia'].map((p) => [p, gkSlots(p).filter((x) => !x.anim).map((x) => x.name)])));
  check(`${label} : Louis, manquantes affichées`, louis.missing.join(',') === attendu.louis.join(',')
    && (louis.missing.length ? louis.band.includes('manquante') : louis.band.includes('Toutes')), louis.missing.join(','));
  const amaia = await page.$eval('.gk-perso[data-perso="amaia"]', (s) => s.querySelectorAll('.gk-anim.missing').length);
  check(`${label} : Amaia, manquantes affichées`, amaia === attendu.amaia.length, String(amaia));
  // Vignettes au repos : image fixe chargée paresseusement, aucune planche, aucun canvas ni minuteur.
  await page.mouse.move(1, 1);   // la souris ne doit survoler aucune vignette pendant le défilement
  await page.evaluate(() => document.querySelector('.gk-perso[data-perso="louis"] .gk-anims').scrollIntoView());
  await page.waitForTimeout(800);
  const still = await page.evaluate(() => {
    const imgs = [...document.querySelectorAll('.gk-perso .gk-anim img.mini')];
    const sheets = performance.getEntriesByType('resource').filter((r) => /%2Fanims%2F[^_]/.test(r.name)).length;
    return { imgs: imgs.length, lazy: imgs.every((i) => i.loading === 'lazy'), poster: imgs.every((i) => /_poster/.test(i.src)),
      canvases: document.querySelectorAll('#grid canvas').length, sheets,
      loaded: imgs.filter((i) => i.complete && i.naturalWidth > 0).length };
  });
  check(`${label} : vignettes fixes (image du milieu, chargement paresseux)`, still.imgs >= 100 && still.lazy && still.poster && still.loaded >= 1 && still.loaded < still.imgs, JSON.stringify(still));
  check(`${label} : au repos, ni canvas ni planche chargée`, still.canvases === 0 && still.sheets === 0, JSON.stringify(still));
  const walkCell = '.gk-perso[data-perso="louis"] .gk-anim[data-anim="walk"]';
  if (opts.hasTouch) {
    await page.locator(walkCell).tap();      // premier toucher : anime sans ouvrir
  } else {
    await page.hover(walkCell);
  }
  await page.waitForSelector(`${walkCell} canvas.mini`);
  await page.waitForTimeout(300);
  const vign = await animated(page, `${walkCell} canvas`);
  check(`${label} : ${opts.hasTouch ? 'toucher' : 'survol'} = la vignette s'anime`, vign.total === 1 && vign.moving === 1 && !(await page.$('.fs')), JSON.stringify(vign));
  await shot('01b_vignette_animee');
  if (opts.hasTouch) {
    await page.locator('.gk-perso[data-perso="louis"] .gk-anim[data-anim="idle"]').tap();
    await page.waitForTimeout(300);
    const n = await page.$$eval('#grid canvas', (c) => c.length);
    check(`${label} : une seule vignette animée à la fois`, n === 1, String(n));
  } else {
    await page.mouse.move(2, 2);
    await page.waitForTimeout(200);
    check(`${label} : souris sortie = canvas libéré, image fixe revenue`,
      (await page.$$('#grid canvas')).length === 0 && !!(await page.$(`${walkCell} img.mini`)));
  }
  await shot('01_persos');
  await page.evaluate(() => document.querySelector('.gk-perso[data-perso="louis"]').scrollIntoView());
  await page.waitForTimeout(400);
  await shot('02_louis');
  await page.evaluate(() => document.querySelector('.gk-perso[data-perso="mattin"]').scrollIntoView());
  await page.waitForTimeout(600);
  await shot('03_mattin_manquantes');

  // Lecteur plein écran : walk de Louis.
  await page.evaluate(() => window.scrollTo(0, 0));
  // Toucher suivant (ou clic) : ouvre le plein écran, qui joue tout seul.
  if (opts.hasTouch) {
    await page.locator(walkCell).tap();            // anime walk (run était actif)…
    await page.waitForTimeout(300);
    if (!(await page.$('.fs'))) await page.locator(walkCell).tap();   // …puis ouvre
  } else {
    await page.click(walkCell);
  }
  await page.waitForSelector('.fs canvas');
  await page.waitForTimeout(800);
  const fsBox = await page.$eval('.fs', (f) => { const r = f.getBoundingClientRect(); return [r.width, r.height, innerWidth, innerHeight]; });
  check(`${label} : plein écran couvre l'écran`, fsBox[0] >= fsBox[2] - 1 && fsBox[1] >= fsBox[3] - 1, fsBox.join(','));
  const cv = await page.$eval('.fs-canvas', (c) => { const r = c.getBoundingClientRect(); return [r.width, r.height]; });
  check(`${label} : grande image`, cv[1] > fsBox[3] * 0.45, cv.join('×'));
  const play = await animated(page, '.fs-canvas');
  check(`${label} : plein écran joue`, play.drawn === 1 && play.moving === 1, JSON.stringify(play));
  check(`${label} : titre`, (await page.textContent('.fs-title')) === 'louis · walk');
  await shot('04_plein_ecran_walk');
  await page.click('button[aria-label="Animation suivante"]');
  await page.waitForTimeout(300);
  check(`${label} : animation suivante`, (await page.textContent('.fs-title')) === 'louis · run_scared', await page.textContent('.fs-title'));
  await page.click('button[aria-label="Image suivante"]');   // met en pause
  const frameNo = async () => Number((await page.textContent('.fs-info')).match(/image (\d+)\//)[1]);
  const f0 = await frameNo();
  await page.click('button[aria-label="Image suivante"]');
  await page.click('button[aria-label="Image suivante"]');
  await page.waitForTimeout(300);
  const f1 = await frameNo();
  check(`${label} : image par image (en pause)`, f1 === f0 + 2, `${f0} -> ${f1}`);
  if (label === 'ordi') {
    await page.keyboard.press('ArrowLeft');
    await page.waitForTimeout(200);
    check(`${label} : flèche ← = animation précédente`, (await page.textContent('.fs-title')) === 'louis · walk');
    await page.keyboard.press('ArrowDown');
    await page.waitForTimeout(200);
    check(`${label} : flèche ↓ = perso suivant`, (await page.textContent('.fs-title')) === 'txomin · walk', await page.textContent('.fs-title'));
  } else if (browser === cr) {
    // Glissement vers la gauche : animation suivante (Touch constructible dans Chromium seulement).
    const before = await page.textContent('.fs-title');
    await page.evaluate(() => {
      const s = document.querySelector('.fs-stage');
      const mk = (type, x) => {
        const t = new Touch({ identifier: 1, target: s, clientX: x, clientY: 200 });
        s.dispatchEvent(new TouchEvent(type, { touches: type === 'touchend' ? [] : [t], changedTouches: [t], bubbles: true, cancelable: true }));
      };
      mk('touchstart', 300); mk('touchend', 120);
    }).catch((e) => console.log('     (TouchEvent non simulable : ' + e.message + ')'));
    await page.waitForTimeout(300);
    const after = await page.textContent('.fs-title');
    check(`${label} : glisser = animation suivante`, after !== before, `${before} -> ${after}`);
  }
  await page.click('.fs-bar button[title="Fond"]');
  await page.click('.fs-bar button[title="Masque de tenue par-dessus"]');
  await page.waitForTimeout(500);
  await shot('05_plein_ecran_fond_masque');
  await page.click('.fs-close');
  await page.waitForTimeout(300);
  check(`${label} : fermeture du plein écran`, (await page.$('.fs')) === null);

  // Récapitulatif : un ✓ ouvre le lecteur.
  await page.click('.recap-table tr[data-perso="maia"] td.yes button');
  await page.waitForSelector('.fs canvas');
  check(`${label} : ✓ du récapitulatif ouvre le lecteur`, (await page.textContent('.fs-title')).startsWith('maia · '));
  await page.click('.fs-close');

  // Page des animations (commentaires) : bouton plein écran et bandeau des manquantes.
  await page.goto(BASE + '#/assets/' + encodeURIComponent('gordeka/persos/louis/animations'));
  await page.waitForSelector('.anim-gallery .anim-cell');
  check(`${label} : page des animations, bandeau des manquantes`, !!(await page.$('#detail .missing-band')));
  check(`${label} : page des animations, bouton plein écran`, !!(await page.$('#detail button:has-text("Plein écran")')));

  // Décor : avec masques (défaut), sans masques, filtre « sans masque », sols.
  await page.goto(BASE + '#/assets');
  await page.click('.cats button:has(span:text-is("Décor"))');
  await page.waitForSelector('.dcard');
  await page.click('.decor-bar .seg button:has-text("Avec masques")');
  await page.waitForTimeout(1500);
  const objets = await page.$$eval('.dgrid:not(.sols) .dcard', (l) => l.length);
  const calques = await page.$$eval('.dgrid:not(.sols) .dcard img.calque', (l) => l.filter((i) => i.complete && i.naturalWidth > 0).length);
  check(`${label} : objets du décor avec calques`, objets >= 25 && calques >= objets - 1, `${objets} objets, ${calques} calques`);
  // Alignement : calque et image occupent exactement la même boîte.
  const align = await page.$$eval('.dgrid .dlayers', (l) => l.every((d) => {
    const [a, b] = d.querySelectorAll('img');
    if (!b) return true;
    const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
    return Math.abs(ra.x - rb.x) < 0.5 && Math.abs(ra.y - rb.y) < 0.5 && Math.abs(ra.width - rb.width) < 0.5;
  }));
  check(`${label} : calques alignés sur les images`, align);
  await shot('06_decor_masques');
  // Bascule d'un objet.
  const first = '.dgrid:not(.sols) .dcard:first-child';
  await page.click(`${first} .row button`);
  check(`${label} : bascule par objet (sans masques)`, (await page.$(`${first} img.calque`)) === null);
  await page.click('.decor-bar .seg button:has-text("Sans masques")');
  await page.waitForTimeout(800);
  check(`${label} : tout sans masques`, (await page.$$('.dgrid img.calque')).length === 0);
  await shot('07_decor_sans_masques');
  await page.check('#decor-sans-masque');
  await page.waitForTimeout(300);
  const sans = await page.$$eval('.dcard', (l) => l.map((x) => x.dataset.id.split('/').pop()));
  check(`${label} : filtre « sans masque »`, sans.length < objets, sans.join(','));
  await page.click('.decor-bar .seg button:has-text("Contrôle du jeu")');
  await page.waitForTimeout(800);
  await shot('08_decor_sans_masque_controle');
  await page.uncheck('#decor-sans-masque');
  await page.click('.decor-bar .seg button:has-text("Avec masques")');
  await page.evaluate(() => document.querySelector('.dgrid.sols').scrollIntoView());
  await page.waitForTimeout(800);
  const sols = await page.$$eval('.dgrid.sols .soltile', (l) => l.map((t) => getComputedStyle(t).backgroundSize));
  check(`${label} : sols répétés 2×2`, sols.length >= 9 && sols.every((s) => s === '50% 50%'), `${sols.length} sols`);
  await shot('09_decor_sols');

  // Détail d'un objet (repli).
  await page.goto(BASE + '#/assets/' + encodeURIComponent('gordeka/decor/objets/mur_soutenement.png'));
  await page.waitForSelector('.stage .dlayers');
  await page.click('#detail .seg button:has-text("Avec masques")');
  await page.waitForTimeout(800);
  const src = await page.evaluate(() => state.assetsById.get('gordeka/decor/objets/mur_soutenement.png').decor.source);
  const lib = { pixelforge: 'pixelforge', repli: 'repli', aucun: 'sans masque' }[src] || src;
  check(`${label} : détail, source des masques affichée`, (await page.textContent('#detail .credits')).includes(lib), src);
  await shot('10_detail_objet');
  await page.goto(BASE + '#/assets/' + encodeURIComponent('gordeka/decor/objets/fronton.png'));
  await page.waitForSelector('.stage .dlayers');
  await page.click('#detail .seg button:has-text("Avec masques")');
  await page.waitForTimeout(800);
  await shot('11_detail_fronton');

  // Borroka : replié, toujours accessible.
  await page.goto(BASE + '#/assets');
  await page.waitForSelector('.cats li.section');
  const folded = (await page.$$('.cats button:has(span:text-is("Combattants"))')).length === 0;
  check(`${label} : Borroka replié`, folded);
  await page.click('.cats li.section.foldable button');
  await page.click('.cats button:has(span:text-is("Combattants"))');
  await page.waitForSelector('.tile[data-id="fighters/maia/sheet.png"]');
  check(`${label} : combattants de Borroka accessibles`, true);
  await page.click('#tabs a[data-tab="kanban"]');
  await page.waitForSelector('#board .column.active, #board:not(.mobile) .column');
  check(`${label} : kanban`, true);
  check(`${label} : aucune erreur JavaScript`, errors.length === 0, errors.join(' | '));
  await context.close();
}
// Glissement tactile (Chromium : WebKit ne construit pas de TouchEvent depuis un script).
{
  const context = await cr.newContext(devices['iPhone 13 landscape']);
  const page = await context.newPage();
  await page.goto(BASE);
  await page.waitForSelector('#login:not([hidden])');
  await page.fill('#password', PASSWORD);
  await page.click('#login-form button[type=submit]');
  await page.waitForSelector('.gk-perso');
  await page.click('.gk-perso[data-perso="louis"] .gk-anim[data-anim="walk"]');
  await page.waitForSelector('.fs canvas');
  const swipe = (x0, y0, x1, y1) => page.evaluate(([x0, y0, x1, y1]) => {
    const s = document.querySelector('.fs-stage');
    const mk = (type, x, y) => {
      const t = new Touch({ identifier: 1, target: s, clientX: x, clientY: y });
      s.dispatchEvent(new TouchEvent(type, { touches: type === 'touchend' ? [] : [t], changedTouches: [t], bubbles: true, cancelable: true }));
    };
    mk('touchstart', x0, y0); mk('touchend', x1, y1);
  }, [x0, y0, x1, y1]);
  await swipe(400, 150, 200, 160);
  await page.waitForTimeout(200);
  check('tactile : glisser à gauche = animation suivante', (await page.textContent('.fs-title')) === 'louis · run_scared', await page.textContent('.fs-title'));
  await swipe(200, 150, 400, 150);
  await page.waitForTimeout(200);
  check('tactile : glisser à droite = animation précédente', (await page.textContent('.fs-title')) === 'louis · walk');
  await swipe(300, 250, 300, 80);
  await page.waitForTimeout(200);
  check('tactile : glisser vers le haut = perso suivant', (await page.textContent('.fs-title')) === 'txomin · walk', await page.textContent('.fs-title'));
  await context.close();
}
// Lecture case par case : entre deux images, la planche avance d'un multiple exact de la case
// (largeur de la planche / nombre d'images), en vignette, page d'animations et plein écran, même
// si l'index est périmé (planches réécrites pendant que la page est ouverte).
{
  const context = await cr.newContext({ viewport: { width: 1440, height: 900 } });
  await context.addInitScript(() => {
    window.__draws = [];
    const orig = CanvasRenderingContext2D.prototype.drawImage;
    CanvasRenderingContext2D.prototype.drawImage = function (img, ...a) {
      if (a.length === 8 && img.naturalWidth) window.__draws.push({ sx: a[0], sw: a[2], iw: img.naturalWidth, src: img.src });
      return orig.call(this, img, ...a);
    };
  });
  const page = await context.newPage();
  await page.goto(BASE);
  await page.waitForSelector('#login:not([hidden])');
  await page.fill('#password', PASSWORD);
  await page.click('#login-form button[type=submit]');
  await page.waitForSelector('.gk-perso');
  const CAS = [['txomin', 'ghost'], ['mattin', 'ghost'], ['amaia', 'hunter_reveal'], ['amaia', 'walk'], ['louis', 'walk']];
  const present = await page.evaluate((cas) => cas.filter(([p, n]) => gkAnims(p).some((x) => x.name === n)), CAS);
  const verifie = async (lieu, frames) => {
    const d = await page.evaluate(() => { const d = window.__draws; window.__draws = []; return d; });
    const faux = d.filter((x) => x.sw * frames !== x.iw || x.sx % x.sw !== 0);
    const sauts = new Set(d.map((x) => x.sx / x.sw)).size;
    check(`case par case : ${lieu}`, d.length >= 3 && faux.length === 0 && sauts >= 2, `${d.length} images, ${faux.length} fausses, ${sauts} cases`);
    return d;
  };
  for (const [pid, name] of present) {
    const frames = await page.evaluate(([p, n]) => gkAnims(p).find((x) => x.name === n).frames, [pid, name]);
    const cell = `.gk-perso[data-perso="${pid}"] .gk-anim[data-anim="${name}"]`;
    await page.locator(cell).scrollIntoViewIfNeeded();
    await page.evaluate(() => { window.__draws = []; });
    await page.hover(cell);
    await page.waitForTimeout(500);
    const d = await verifie(`${pid}/${name}, vignette`, frames);
    check(`${pid}/${name} : planche en URL versionnée (&v=)`, d.every((x) => /[?&]v=[0-9a-f]{10}/.test(x.src)));
    await page.click(cell);
    await page.waitForSelector('.fs canvas');
    await page.waitForTimeout(500);
    await verifie(`${pid}/${name}, plein écran`, frames);
    await page.click('.fs-close');
    await page.mouse.move(2, 2);
  }
  // Page des animations (lecteur du détail).
  await page.goto(BASE + '#/assets/' + encodeURIComponent('gordeka/persos/amaia/animations'));
  await page.waitForSelector('.stage canvas');
  await page.selectOption('.controls select[aria-label=Animation]', 'walk').catch(() => {});
  await page.evaluate(() => { window.__draws = []; });
  await page.waitForTimeout(600);
  await verifie('amaia/walk, page des animations', await page.evaluate(() => gkAnims('amaia').find((x) => x.name === 'walk').frames));
  // Index périmé : largeurs de case fausses dans l'index, la planche fait foi.
  await page.goto(BASE + '#/assets');
  await page.waitForSelector('.gk-perso');
  await page.evaluate(() => { for (const x of gkAnims('amaia')) x.w += 22; window.__draws = []; });
  const c2 = '.gk-perso[data-perso="amaia"] .gk-anim[data-anim="walk"]';
  await page.locator(c2).scrollIntoViewIfNeeded();
  await page.hover(c2);
  await page.waitForTimeout(500);
  await verifie('index périmé : la planche fait foi', await page.evaluate(() => gkAnims('amaia').find((x) => x.name === 'walk').frames));
  // En-têtes : URL versionnée immuable, sinon revalidée.
  const hdr = await page.evaluate(async () => {
    const f = gkAnims('amaia').find((x) => x.name === 'walk').file;
    const v = state.index.versions[f];
    const ok = await fetch('index.php?r=file&p=' + encodeURIComponent(f) + '&v=' + v);
    const vieux = await fetch('index.php?r=file&p=' + encodeURIComponent(f) + '&v=0000000000');
    return [ok.headers.get('cache-control'), vieux.headers.get('cache-control')];
  });
  check('cache : URL à jour immuable, empreinte périmée revalidée', /immutable/.test(hdr[0]) && /no-cache/.test(hdr[1]), hdr.join(' | '));
  await context.close();
}
await cr.close();
if (wk) await wk.close();
console.log(fails ? `${fails} échec(s)` : 'tout est vert');
process.exit(fails ? 1 : 0);
