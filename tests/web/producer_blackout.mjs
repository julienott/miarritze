// /producer, catalogue de Blackout : character sets pixelforge (13 persos aux éléments du GDD §8.1,
// fantôme, PNJ, animaux, boss), récapitulatif, vignettes au survol, lecteur plein écran, recette
// d'un perso dans sa carte chapeau (toutes les animations, descriptions, 💬 Commenter), badge
// placeholder. (Le décor de l'ancien visuel est archivé : plus de contrôle du décor ici.)
// Ordinateur (Chromium) + iPhone portrait et paysage (WebKit si installé, sinon Chromium).
// Crée une carte « Perso : Louis … » et un commentaire dans la base du service testé : à lancer
// sur un build local (docs/PRODUCER.md, « Tester en local »), jamais sur la prod.
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
const tag = 'B' + Date.now().toString(36);   // titres uniques : le test peut tourner sur une base non vide

// Éléments d'un perso (GDD-BLACKOUT §8.1) : propres à Blackout, puis les 9 standards.
const ELEMENTS_BLACKOUT = ['profile', 'portrait', 'idle', 'run', 'jump_hide', 'lift', 'idle_long', 'cast_chasse', 'cast_chasseur'];
const NB_STANDARDS = 9;
const NB_PERSOS = 13;

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
  for (let k = 0; k < 10; k++) { shots.push(snap()); await new Promise((r) => setTimeout(r, 150)); }
  const drawn = shots[shots.length - 1].filter(([n]) => n > 0).length;
  const moving = cs.filter((_, i) => new Set(shots.map((x) => x[i].join(':'))).size > 1).length;
  return { total: cs.length, drawn, moving };
}, sel);

// Catalogue groupé par perso, animations seulement, récapitulatif affiché.
const persosView = async (page) => {
  await page.evaluate(() => {
    Object.assign(cat, { group: 'perso', type: 'anim', map: '', recap: true, q: '' });
    cat.filters = new Set();
    cat.more.clear();
    if (location.hash !== '#/assets') location.hash = '#/assets'; else renderCatalogue();
  });
  await page.waitForSelector('.cgroup[data-perso] .citem');
};
// Clé d'un set : « louis », ou famille/id hors persos (« pnj/ado », « boss/tartalo »).
const assetOf = (pid) => (pid.includes('/') ? `blackout/${pid}/animations` : `blackout/persos/${pid}/animations`);
const cell = (pid, name) => `.citem[data-key="${assetOf(pid)}#${name}"]`;
// Titre attendu du lecteur plein écran (« Louis · course (run) »), d'après l'index.
const fsTitle = (page, pid, name) => page.evaluate(([p, n]) => {
  const a = bkAnims(p).find((x) => x.name === n);
  return `${persoName(p)} · ${a.libelle ? `${a.libelle} (${a.name})` : a.name}`;
}, [pid, name]);
// Élément voisin dans l'ordre du set.
const voisin = (page, pid, name, d) => page.evaluate(([p, n, d]) => {
  const l = bkAnims(p); const i = l.findIndex((x) => x.name === n);
  return l[(i + d + l.length) % l.length].name;
}, [pid, name, d]);
const login = async (page) => {
  await page.goto(BASE);
  await page.waitForSelector('#login:not([hidden])');
  await page.fill('#password', PASSWORD);
  await page.click('#login-form button[type=submit]');
  await page.waitForSelector('#view-bord:not([hidden])');
};
// Détail d'une carte (ou nouvelle carte liée à un asset) : la recette s'affiche dans #cf-asset-view.
const openGallery = async (page, cardId, assetId) => {
  await page.evaluate(([id, aid]) => {
    if ($('card-dialog').open) $('card-dialog').close();
    openCardDialog(id ? cardById(id) : null, aid || '');
  }, [cardId, assetId]);
  await page.waitForSelector('#cf-asset-view .set-gal .sg-el');
};
const closeDialog = (page) => page.evaluate(() => { if ($('card-dialog').open) $('card-dialog').close(); });

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
  page.on('dialog', (d) => d.accept());
  const shot = (n, full = false) => page.screenshot({ path: path.join(OUT, `${label}_${n}.png`), fullPage: full });
  await login(page);
  await persosView(page);
  await page.waitForTimeout(1500);

  // ---------------------------------------------------------------- catalogue des sets
  const g = await page.evaluate(() => ({ persos: state.index.blackout.persos, autres: state.index.blackout.autres || [],
    elements: state.index.blackout.anims.map((x) => x.name) }));
  check(`${label} : ${NB_PERSOS} persos au casting, Louis en tête`, g.persos.length === NB_PERSOS && g.persos[0] === 'louis', g.persos.join(','));
  const manque = ELEMENTS_BLACKOUT.filter((e) => !g.elements.includes(e));
  check(`${label} : éléments du GDD §8.1 (9 de Blackout + ${NB_STANDARDS} standards)`,
    manque.length === 0 && g.elements.length === ELEMENTS_BLACKOUT.length + NB_STANDARDS, manque.length ? 'manquent ' + manque : g.elements.join(','));
  const familles = ['fantome', 'pnj', 'animaux', 'boss'];
  const parFamille = Object.fromEntries(familles.map((f) => [f, g.autres.filter((k) => k.startsWith(f + '/')).length]));
  check(`${label} : fantôme, PNJ, animaux et boss indexés`, parFamille.fantome === 1 && familles.every((f) => parFamille[f] >= 1), JSON.stringify(parFamille));
  // Une section par set : les persos dans l'ordre du casting, puis les autres familles.
  const groupes = await page.$$eval('.cgroup[data-perso]', (l) => l.map((x) => x.dataset.perso));
  check(`${label} : une section par set, persos puis autres familles`,
    groupes.join(',') === [...g.persos, ...g.autres].join(','), `${groupes.length} sections, ${groupes.slice(0, 3).join(',')}…${groupes.slice(-2).join(',')}`);
  const recap = await page.$$eval('.recap-table tbody tr', (r) => r.map((x) => x.dataset.perso));
  const cols = await page.$$eval('.recap-table thead th.v', (r) => r.length);
  check(`${label} : récapitulatif perso × élément`, recap.join(',') === g.persos.join(',') && cols === g.elements.length + 1, `${recap.length} lignes, ${cols} colonnes`);
  // Chaque perso : un emplacement par élément attendu ; manquantes = celles que l'index n'a pas.
  const cases = await page.evaluate(() => state.index.blackout.persos.map((p) => {
    const s = document.querySelector(`.cgroup[data-perso="${p}"]`);
    return [p, s.querySelectorAll('.citem').length, [...s.querySelectorAll('.citem.missing')].map((x) => x.dataset.key.split('#')[1]).join(','),
      bkSlots(p).filter((x) => !x.anim).map((x) => x.name).join(',')];
  }));
  const fausses = cases.filter(([, n, vu, att]) => n !== g.elements.length || vu !== att);
  check(`${label} : chaque perso, ${g.elements.length} éléments dont les manquants marqués`, fausses.length === 0, JSON.stringify(fausses));
  const louis = cases.find(([p]) => p === 'louis');
  check(`${label} : Louis complet`, louis[2] === '', louis[2] || `${louis[1]} éléments`);
  // Autres familles : les éléments présents de leur set.
  const autresOk = await page.evaluate(() => (state.index.blackout.autres || []).filter((p) => {
    const s = document.querySelector(`.cgroup[data-perso="${p}"]`);
    return !s || s.querySelectorAll('.citem:not(.missing)').length !== bkAnims(p).length;
  }));
  check(`${label} : fantôme, PNJ, animaux, boss, chaque élément présent`, autresOk.length === 0, autresOk.join(','));
  // Badge placeholder : sur les éléments d'un PNJ placeholder, jamais sur un set définitif.
  const ph = await page.evaluate(() => {
    const autres = state.index.blackout.autres || [];
    const isPh = (p) => !!state.assetsById.get(bkAssetId(p)).set.placeholder;
    const pnjPh = autres.find((p) => p.startsWith('pnj/') && isPh(p));
    const nonPh = ['louis', ...autres.filter((p) => !isPh(p))];
    const badges = (p) => [...document.querySelectorAll(`.cgroup[data-perso="${p}"] .citem`)]
      .filter((x) => x.querySelector('.badge.placeholder')).length;
    return { pnjPh, n: pnjPh ? badges(pnjPh) : 0, total: pnjPh ? bkAnims(pnjPh).length : 0,
      faux: nonPh.filter((p) => badges(p) > 0) };
  });
  check(`${label} : badge placeholder sur un PNJ placeholder`, !!ph.pnjPh && ph.n === ph.total && ph.n > 0, `${ph.pnjPh} ${ph.n}/${ph.total}`);
  check(`${label} : pas de badge placeholder sur un set définitif`, ph.faux.length === 0, ph.faux.join(','));
  // Vignettes au repos : image fixe chargée paresseusement, aucune planche, aucun canvas ni minuteur.
  await page.mouse.move(1, 1);   // la souris ne doit survoler aucune vignette pendant le défilement
  await page.evaluate(() => document.querySelector('.cgroup[data-perso="louis"] .citems').scrollIntoView());
  await page.waitForTimeout(800);
  const still = await page.evaluate(() => {
    const imgs = [...document.querySelectorAll('.cgroup .citem img.mini')];
    const sheets = performance.getEntriesByType('resource').filter((r) => /%2Fpx32%2F[^_]/.test(r.name)).length;
    return { imgs: imgs.length, lazy: imgs.every((i) => i.loading === 'lazy'), poster: imgs.every((i) => /_poster/.test(i.src)),
      canvases: document.querySelectorAll('#grid canvas').length, sheets,
      loaded: imgs.filter((i) => i.complete && i.naturalWidth > 0).length };
  });
  check(`${label} : vignettes fixes (image du milieu, chargement paresseux)`, still.imgs >= 200 && still.lazy && still.poster && still.loaded >= 1 && still.loaded < still.imgs, JSON.stringify(still));
  check(`${label} : au repos, ni canvas ni planche chargée`, still.canvases === 0 && still.sheets === 0, JSON.stringify(still));
  const runCell = cell('louis', 'run');
  if (opts.hasTouch) {
    await page.locator(runCell).tap();      // premier toucher : anime sans ouvrir
  } else {
    await page.hover(runCell);
  }
  await page.waitForSelector(`${runCell} canvas.mini`);
  await page.waitForTimeout(300);
  const vign = await animated(page, `${runCell} canvas`);
  check(`${label} : ${opts.hasTouch ? 'toucher' : 'survol'} = la vignette s'anime`, vign.total === 1 && vign.moving === 1 && page.url().endsWith('#/assets'), JSON.stringify(vign));
  await shot('01b_vignette_animee');
  if (opts.hasTouch) {
    await page.locator(cell('louis', 'idle')).tap();
    await page.waitForTimeout(300);
    const n = await page.$$eval('#grid canvas', (c) => c.length);
    check(`${label} : une seule vignette animée à la fois`, n === 1, String(n));
  } else {
    await page.mouse.move(2, 2);
    await page.waitForTimeout(200);
    check(`${label} : souris sortie = canvas libéré, image fixe revenue`,
      (await page.$$('#grid canvas')).length === 0 && !!(await page.$(`${runCell} img.mini`)));
  }
  await shot('01_persos');
  await page.evaluate((p) => document.querySelector(`.cgroup[data-perso="${p}"]`).scrollIntoView(), ph.pnjPh);
  await page.waitForTimeout(600);
  await shot('02_pnj_placeholder');
  await page.evaluate(() => document.querySelector('.cgroup[data-perso^="boss/"]').scrollIntoView());
  await page.waitForTimeout(600);
  await shot('03_boss');

  // ---------------------------------------------------------------- lecteur plein écran
  // Course de Louis, depuis sa fiche (toucher suivant ou clic = la fiche).
  await page.evaluate(() => window.scrollTo(0, 0));
  if (opts.hasTouch) {
    await page.locator(runCell).tap();
    await page.waitForTimeout(300);
    if (page.url().endsWith('#/assets')) await page.locator(runCell).tap();
  } else {
    await page.click(runCell);
  }
  await page.waitForSelector('#detail button:has-text("Plein écran")');
  await page.click('#detail button:has-text("Plein écran")');
  await page.waitForSelector('.fs canvas');
  await page.waitForTimeout(800);
  const fsBox = await page.$eval('.fs', (f) => { const r = f.getBoundingClientRect(); return [r.width, r.height, innerWidth, innerHeight]; });
  check(`${label} : plein écran couvre l'écran`, fsBox[0] >= fsBox[2] - 1 && fsBox[1] >= fsBox[3] - 1, fsBox.join(','));
  const cv = await page.$eval('.fs-canvas', (c) => { const r = c.getBoundingClientRect(); return [r.width, r.height, c.classList.contains('px')]; });
  check(`${label} : grande image, pixel art net`, cv[1] > fsBox[3] * 0.45 && cv[2], cv.join('×'));
  const play = await animated(page, '.fs-canvas');
  check(`${label} : plein écran joue`, play.drawn === 1 && play.moving === 1, JSON.stringify(play));
  const tRun = await fsTitle(page, 'louis', 'run');
  check(`${label} : titre`, (await page.textContent('.fs-title')) === tRun, await page.textContent('.fs-title'));
  await shot('04_plein_ecran_run');
  const apres = await voisin(page, 'louis', 'run', 1);
  await page.click('button[aria-label="Animation suivante"]');
  await page.waitForTimeout(300);
  check(`${label} : animation suivante`, (await page.textContent('.fs-title')) === await fsTitle(page, 'louis', apres), await page.textContent('.fs-title'));
  await page.click('button[aria-label="Image suivante"]');   // met en pause
  const frameNo = async () => Number((await page.textContent('.fs-info')).match(/image (\d+)\//)[1]);
  const f0 = await frameNo();
  await page.click('button[aria-label="Image suivante"]');
  await page.click('button[aria-label="Image suivante"]');
  await page.waitForTimeout(300);
  const f1 = await frameNo();
  const nf = await page.evaluate((n) => bkAnims('louis').find((x) => x.name === n).frames, apres);
  check(`${label} : image par image (en pause)`, f1 === ((f0 - 1 + 2) % nf) + 1, `${f0} -> ${f1} / ${nf}`);
  if (label === 'ordi') {
    await page.keyboard.press('ArrowLeft');
    await page.waitForTimeout(200);
    check(`${label} : flèche ← = animation précédente`, (await page.textContent('.fs-title')) === tRun, await page.textContent('.fs-title'));
    await page.keyboard.press('ArrowDown');
    await page.waitForTimeout(200);
    const t2 = await fsTitle(page, g.persos[1], 'run');
    check(`${label} : flèche ↓ = perso suivant`, (await page.textContent('.fs-title')) === t2, await page.textContent('.fs-title'));
    await page.keyboard.press('ArrowUp');
    await page.waitForTimeout(200);
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
  // Les sets pixelforge n'ont pas de masque de tenue : le bouton est grisé.
  const maskOff = await page.$eval('.fs-bar button[title="Masque de tenue par-dessus"]', (b) => b.disabled);
  const hasMask = await page.evaluate(() => !!state.assetsById.get('blackout/persos/louis/masques'));
  check(`${label} : bouton Masque grisé sans masque de tenue`, maskOff === !hasMask, `masques : ${hasMask}`);
  await page.click('.fs-bar button[title="Ligne des pieds (feet_anchor)"]');
  await page.waitForTimeout(500);
  await shot('05_plein_ecran_fond_pieds');
  await page.click('.fs-close');
  await page.waitForTimeout(300);
  check(`${label} : fermeture du plein écran`, (await page.$('.fs')) === null);

  // Récapitulatif : un ✓ ouvre le lecteur.
  await persosView(page);
  await page.click('.recap-table tr[data-perso="maia"] td.yes button');
  await page.waitForSelector('.fs canvas');
  check(`${label} : ✓ du récapitulatif ouvre le lecteur`, (await page.textContent('.fs-title')).startsWith(await page.evaluate(() => persoName('maia')) + ' · '));
  await page.click('.fs-close');

  // Fiche des animations : galerie de tous les éléments, plein écran, bandeau des manquantes s'il y en a.
  await page.goto(BASE + '#/assets/' + encodeURIComponent('blackout/persos/louis/animations'));
  await page.waitForSelector('.anim-gallery .anim-cell');
  const galCells = await page.$$eval('.anim-gallery .anim-cell', (l) => l.length);
  const nLouis = await page.evaluate(() => bkAnims('louis').length);
  check(`${label} : fiche des animations, tous les éléments`, galCells === nLouis, `${galCells}/${nLouis}`);
  check(`${label} : fiche des animations, bandeau des manquantes seulement s'il en manque`,
    !!(await page.$('#detail .missing-band')) === (louis[2] !== ''));
  check(`${label} : fiche des animations, bouton plein écran`, !!(await page.$('#detail button:has-text("Plein écran")')));

  // ---------------------------------------------------------------- recette : carte chapeau de Louis
  const cardId = await page.evaluate(async (t) => {
    const r = await api('card', { method: 'POST', body: { title: `Perso : Louis ${t}`, type: 'perso', asset: 'blackout/persos/louis/animations', status: 'qa' } });
    await reloadCards();
    return r.id;
  }, tag);
  await openGallery(page, cardId, '');
  await page.waitForTimeout(800);
  const rec = await page.evaluate(() => {
    const box = document.querySelector('#cf-asset-view .set-gal');
    const els = [...box.querySelectorAll('.sg-el')];
    return {
      titre: box.querySelector('.sg-head h3').textContent,
      badges: [...box.querySelectorAll('.sg-title .badge')].map((b) => b.textContent),
      placeholder: !!box.querySelector('.sg-title .badge.placeholder'),
      prompt: (box.querySelector('.sg-head > .sg-desc') || {}).textContent || '',
      tete: [...box.querySelectorAll('.sg-top .sg-el')].map((x) => x.dataset.el),
      noms: els.map((x) => x.dataset.el),
      attendus: bkAnims('louis').map((x) => x.name),
      sansDesc: els.filter((x) => !(x.querySelector('.sg-text .sg-desc') || {}).textContent).map((x) => x.dataset.el),
      sansCode: els.filter((x) => (x.querySelector('h4 code') || {}).textContent !== x.dataset.el).map((x) => x.dataset.el),
      sansBouton: els.filter((x) => !x.querySelector('button.sg-comment')).map((x) => x.dataset.el),
      sansPlein: els.filter((x) => ![...x.querySelectorAll('.sg-actions button')].some((b) => b.textContent === '⛶')).map((x) => x.dataset.el),
      vues: els.map((x) => x.querySelectorAll('.sg-view canvas').length),
      hd: state.assetsById.get('blackout/persos/louis/animations').set.hd,
      wide: $('card-dialog').classList.contains('wide'),
      deborde: $('card-dialog').scrollWidth - $('card-dialog').clientWidth,
    };
  });
  check(`${label} : carte chapeau, recette de Louis`, rec.titre.includes('Louis') && rec.wide, rec.titre);
  check(`${label} : recette, en-tête (éléments, HD, prompt)`,
    rec.badges.includes(`${rec.attendus.length} éléments`) && rec.badges.includes(rec.hd ? 'HD disponible' : '32 px seulement') && rec.prompt.startsWith('Prompt : '),
    rec.badges.join(' | '));
  check(`${label} : recette, pas de badge PLACEHOLDER pour Louis`, !rec.placeholder);
  check(`${label} : recette, profil et portrait en tête`, rec.tete.join(',') === 'profile,portrait', rec.tete.join(','));
  check(`${label} : recette, toutes les animations dans l'ordre du set`, [...rec.noms].sort().join(',') === [...rec.attendus].sort().join(',')
    && rec.noms.slice(2).join(',') === rec.attendus.filter((n) => !['profile', 'portrait'].includes(n)).join(','), `${rec.noms.length}/${rec.attendus.length}`);
  check(`${label} : recette, chaque élément décrit (libellé, nom, ce qu'on doit voir)`, rec.sansDesc.length === 0 && rec.sansCode.length === 0,
    JSON.stringify([rec.sansDesc, rec.sansCode]));
  check(`${label} : recette, un bouton 💬 Commenter et ⛶ par élément`, rec.sansBouton.length === 0 && rec.sansPlein.length === 0,
    JSON.stringify([rec.sansBouton, rec.sansPlein]));
  check(`${label} : recette, 32 px${rec.hd ? ' et HD' : ''} pour chaque élément`, rec.vues.every((n) => n === (rec.hd ? 2 : 1)), rec.vues.join(','));
  check(`${label} : recette, rien ne déborde en largeur`, rec.deborde <= 1, String(rec.deborde));
  // Les animations à l'écran tournent (32 px et HD).
  // Planches chargées seulement quand l'élément est à l'écran (on y revient tant que le détail
  // de la carte finit de se remplir et décale la page).
  await page.waitForFunction(() => {
    const cs = [...document.querySelectorAll('#cf-asset-view .sg-el[data-el="run"] canvas')];
    if (cs.every((c) => c.player && c.player.img)) return true;
    cs[0].scrollIntoView({ block: 'center' });
    return false;
  }, null, { timeout: 15000, polling: 300 });
  const runVues = await animated(page, '#cf-asset-view .sg-el[data-el="run"] canvas');
  check(`${label} : recette, la course tourne`, runVues.total >= 1 && runVues.moving === runVues.total, JSON.stringify(runVues));
  // Zoom entier : ×3 sur un écran large, ×2 sous 700 px de large (iPhone portrait).
  const pxZ = await page.$eval('#cf-asset-view .sg-el[data-el="run"] canvas.px', (c) => [c.getBoundingClientRect().width / c.width,
    getComputedStyle(c).imageRendering, innerWidth < 700 ? 2 : 3]);
  check(`${label} : recette, 32 px agrandi net ×${pxZ[2]}`, Math.abs(pxZ[0] - pxZ[2]) < 0.05 && pxZ[1] !== 'auto', pxZ.join(' '));
  await shot('12_recette_louis');
  // Pause : la galerie entière s'arrête.
  await page.click('#cf-asset-view .sg-bar button:has-text("Pause")');
  await page.waitForTimeout(200);
  const pause = await animated(page, '#cf-asset-view .sg-el[data-el="run"] canvas');
  check(`${label} : recette, Pause arrête la galerie`, pause.moving === 0, JSON.stringify(pause));
  await page.click('#cf-asset-view .sg-bar button:has-text("Lecture")');
  // 💬 Commenter : formulaire sous l'élément ; envoyé, le commentaire porte l'élément et la carte.
  const elx = '#cf-asset-view .sg-el[data-el="run"]';
  await page.click(`${elx} button.sg-comment`);
  await page.waitForSelector(`${elx} form.sg-form textarea`);
  check(`${label} : 💬 Commenter ouvre le formulaire (Amélioration / Validé)`,
    (await page.$$(`${elx} form.sg-form .kind-pick button`)).length === 2 && (await page.textContent(`${elx} button.sg-comment`)).includes('Annuler'));
  if (label === 'ordi') {
    const corps = `Bras trop courts ${tag}`;
    const avant = await page.evaluate(() => state.comments.filter((c) => c.asset === 'blackout/persos/louis/animations' && /^anim : run\b/.test(c.context || '')).length);
    await page.fill(`${elx} form.sg-form textarea`, corps);
    await page.click(`${elx} form.sg-form button[type=submit]`);
    await page.waitForSelector(`${elx} .sg-comments .comment:has-text("${corps}")`);
    const c = await page.evaluate((b) => state.comments.find((x) => x.body === b), corps);
    check(`${label} : commentaire sur l'élément, reporté sur la carte chapeau`,
      !!c && c.asset === 'blackout/persos/louis/animations' && /^anim : run/.test(c.context) && c.card_id === cardId, JSON.stringify(c || {}).slice(0, 200));
    check(`${label} : commentaire affiché sous son élément seulement`,
      (await page.textContent(`${elx} .sg-comments`)).includes(corps)
      && !(await page.textContent('#cf-asset-view .sg-el[data-el="idle"] .sg-comments')).includes(corps)
      && (await page.textContent(`${elx} h4 .badge.amelioration`)) === `💬 ${avant + 1}`);
    const carte = await page.evaluate(async (id) => { await reloadCards(); return cardById(id); }, cardId);
    check(`${label} : une amélioration laisse la carte Perso en QA (Julien décide du renvoi)`, carte && carte.status === 'qa', carte && carte.status);
    await page.waitForTimeout(400);
    await shot('13_recette_commentaire');
  } else {
    await page.click(`${elx} button.sg-comment`);
    check(`${label} : ✕ Annuler referme le formulaire`, !(await page.$(`${elx} form.sg-form`)));
  }
  // ⛶ d'un élément : lecteur plein écran sur cet élément, détail fermé.
  await page.click('#cf-asset-view .sg-el[data-el="jump_hide"] .sg-actions button:has-text("⛶")');
  await page.waitForSelector('.fs canvas');
  check(`${label} : ⛶ de la recette ouvre le lecteur sur l'élément`,
    (await page.textContent('.fs-title')) === await fsTitle(page, 'louis', 'jump_hide') && !(await page.evaluate(() => $('card-dialog').open)),
    await page.textContent('.fs-title'));
  await page.click('.fs-close');
  check(`${label} : la galerie fermée, ses lecteurs s'arrêtent`, await page.evaluate(() => !$('cf-asset-view').gallery));
  // Carte Perso sans asset : le set est retrouvé par le nom dans le titre.
  const sansAsset = await page.evaluate(async (t) => {
    if ($('card-dialog').open) $('card-dialog').close();
    openCardDialog(null, '');
    $('cf-type').value = 'perso';
    $('cf-title').value = `Perso : Amaia ${t}`;
    renderCardAsset();
    const h = document.querySelector('#cf-asset-view .sg-head h3');
    return h ? h.textContent : '';
  }, tag);
  check(`${label} : carte Perso sans asset, set retrouvé par le titre`, sansAsset.includes('Amaia'), sansAsset);
  await closeDialog(page);
  // PNJ placeholder : badge PLACEHOLDER en tête de sa recette ; un PNJ définitif n'en a pas.
  await openGallery(page, 0, assetOf(ph.pnjPh));
  const phHead = await page.evaluate(() => ({
    badge: (document.querySelector('#cf-asset-view .sg-title .badge.placeholder') || {}).textContent || '',
    n: document.querySelectorAll('#cf-asset-view .sg-el').length,
  }));
  const nPh = await page.evaluate((p) => bkAnims(p).length, ph.pnjPh);
  check(`${label} : recette d'un PNJ placeholder, badge PLACEHOLDER`, phHead.badge === 'PLACEHOLDER' && phHead.n === nPh, `${ph.pnjPh} : ${JSON.stringify(phHead)}`);
  await shot('14_recette_pnj_placeholder');
  const pnjDef = await page.evaluate(() => (state.index.blackout.autres || []).find((p) => p.startsWith('pnj/') && !state.assetsById.get(bkAssetId(p)).set.placeholder));
  if (pnjDef) {
    await openGallery(page, 0, assetOf(pnjDef));
    check(`${label} : recette d'un PNJ définitif, sans badge`, !(await page.$('#cf-asset-view .sg-title .badge.placeholder')), pnjDef);
  }
  // Boss (cases de 128) et fantôme : même recette.
  const boss = g.autres.find((k) => k.startsWith('boss/'));
  await openGallery(page, 0, assetOf(boss));
  const bossW = await page.$eval('#cf-asset-view .sg-el canvas.px', (c) => c.width);
  check(`${label} : recette d'un boss, cases de 128`, bossW === 128, `${boss} ${bossW}`);
  await openGallery(page, 0, assetOf('fantome/fantome'));
  check(`${label} : recette du fantôme`, (await page.$$('#cf-asset-view .sg-el')).length === await page.evaluate(() => bkAnims('fantome/fantome').length));
  await closeDialog(page);

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
  await login(page);
  await page.goto(BASE + '#/assets/' + encodeURIComponent('blackout/persos/louis/animations') + '/run');
  await page.click('#detail button:has-text("Plein écran")');
  await page.waitForSelector('.fs canvas');
  const swipe = (x0, y0, x1, y1) => page.evaluate(([x0, y0, x1, y1]) => {
    const s = document.querySelector('.fs-stage');
    const mk = (type, x, y) => {
      const t = new Touch({ identifier: 1, target: s, clientX: x, clientY: y });
      s.dispatchEvent(new TouchEvent(type, { touches: type === 'touchend' ? [] : [t], changedTouches: [t], bubbles: true, cancelable: true }));
    };
    mk('touchstart', x0, y0); mk('touchend', x1, y1);
  }, [x0, y0, x1, y1]);
  const tRun = await fsTitle(page, 'louis', 'run');
  const tSuiv = await fsTitle(page, 'louis', await voisin(page, 'louis', 'run', 1));
  const persos = await page.evaluate(() => state.index.blackout.persos);
  await swipe(400, 150, 200, 160);
  await page.waitForTimeout(200);
  check('tactile : glisser à gauche = animation suivante', (await page.textContent('.fs-title')) === tSuiv, await page.textContent('.fs-title'));
  await swipe(200, 150, 400, 150);
  await page.waitForTimeout(200);
  check('tactile : glisser à droite = animation précédente', (await page.textContent('.fs-title')) === tRun, await page.textContent('.fs-title'));
  await swipe(300, 250, 300, 80);
  await page.waitForTimeout(200);
  check('tactile : glisser vers le haut = perso suivant', (await page.textContent('.fs-title')) === await fsTitle(page, persos[1], 'run'), await page.textContent('.fs-title'));
  await context.close();
}
// Lecture case par case : entre deux images, la planche avance d'un multiple exact de la case
// (largeur de la planche / nombre d'images), en vignette, page d'animations et plein écran, même
// si l'index est périmé (planches réécrites pendant que la page est ouverte). Persos, fantôme,
// PNJ et boss (cases de 128).
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
  await login(page);
  await persosView(page);
  const CAS = await page.evaluate(() => {
    const autres = state.index.blackout.autres || [];
    const multi = (p) => (bkAnims(p).find((x) => x.frames > 1) || {}).name;
    const boss = autres.find((p) => p.startsWith('boss/'));
    const pnj = autres.find((p) => p.startsWith('pnj/'));
    return [['louis', 'run'], ['amaia', 'run'], ['louis', 'jump_hide'], ['fantome/fantome', multi('fantome/fantome')],
      [pnj, multi(pnj)], [boss, multi(boss)]].filter(([p, n]) => p && n && bkAnims(p).some((x) => x.name === n && x.frames > 1));
  });
  // `nom` : seules les images de cette planche comptent (la souris peut frôler une autre vignette en chemin).
  const verifie = async (lieu, frames, file) => {
    let d = await page.evaluate(() => { const d = window.__draws; window.__draws = []; return d; });
    if (file) d = d.filter((x) => x.src.includes(encodeURIComponent(file)));
    const faux = d.filter((x) => x.sw * frames !== x.iw || x.sx % x.sw !== 0);
    const sauts = new Set(d.map((x) => x.sx / x.sw)).size;
    check(`case par case : ${lieu}`, d.length >= 3 && faux.length === 0 && sauts >= 2, `${d.length} images, ${faux.length} fausses, ${sauts} cases` + (faux.length ? ' ' + JSON.stringify(faux[0]).slice(0, 300) : ''));
    return d;
  };
  const animOf = (pid, name) => page.evaluate(([p, n]) => { const x = bkAnims(p).find((y) => y.name === n); return { frames: x.frames, file: x.file }; }, [pid, name]);
  for (const [pid, name] of CAS) {
    const { frames, file } = await animOf(pid, name);
    const vign = cell(pid, name);
    await persosView(page);
    await page.locator(vign).scrollIntoViewIfNeeded();
    await page.evaluate(() => { window.__draws = []; });
    await page.hover(vign);
    await page.waitForTimeout(800);
    const d = await verifie(`${pid}/${name}, vignette`, frames, file);
    check(`${pid}/${name} : planche en URL versionnée (&v=)`, d.every((x) => /[?&]v=[0-9a-f]{10}/.test(x.src)));
    await page.click(vign);
    await page.click('#detail button:has-text("Plein écran")');
    await page.waitForSelector('.fs canvas');
    await page.waitForTimeout(800);
    await verifie(`${pid}/${name}, plein écran`, frames, file);
    // « Défile » : planche brute image par image (touche « . »), position de la tête et des pieds
    // mesurée sur le canvas affiché ; le glissement vu doit être celui de la planche (index « glisse »).
    const jeuOn = await page.evaluate(() => state.fs.jeu);
    if (jeuOn) await page.click('.fs-bar button:has-text("Comme en jeu")');
    const pos = [];
    for (let f = 0; f < frames; f++) {
      await page.keyboard.press('.');
      pos.push(await page.evaluate(() => {
        const c = document.querySelector('.fs-canvas');
        const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
        let y0 = c.height, y1 = -1;
        for (let i = 3; i < d.length; i += 4) if (d[i] > 128) { const y = Math.floor((i >> 2) / c.width); if (y < y0) y0 = y; if (y > y1) y1 = y; }
        const band = (lo, hi) => { let s = 0, n = 0; for (let y = lo; y <= hi; y++) for (let x = 0; x < c.width; x++) if (d[(y * c.width + x) * 4 + 3] > 128) { s += x; n++; } return n ? s / n : null; };
        const h = (y1 - y0) * 0.2;
        return [band(y0, Math.floor(y0 + h)), band(Math.ceil(y1 - Math.min(h, 10)), y1)];
      }));
    }
    const ec = (k) => { const v = pos.map((p) => p[k]).filter((x) => x !== null); return Math.max(...v) - Math.min(...v); };
    const vu = Math.min(ec(0), ec(1));
    const attendu = await page.evaluate(([p, n]) => (bkAnims(p).find((x) => x.name === n).glisse || [0])[0], [pid, name]);
    check(`${pid}/${name} : glissement vu = celui de la planche (${Math.round(vu)} px, index ${attendu})`,
      attendu ? Math.abs(vu - attendu) <= 2 : vu < 8, pos.slice(0, 4).map((p) => p.map((x) => Math.round(x)).join('/')).join(' '));
    if (attendu >= 8) check(`${pid}/${name} : le lecteur l'annonce (⚠ glisse)`, (await page.textContent('.fs-info')).includes('glisse'));
    if (jeuOn) await page.click('.fs-bar button:has-text("Comme en jeu")');
    await page.click('.fs-close');
    await page.mouse.move(2, 2);
  }
  // Page des animations (lecteur du détail), ouverte sur la course (laisse le lecteur plein écran
  // finir de se fermer : il revient en arrière dans l'historique).
  await page.waitForTimeout(500);
  await page.goto(BASE + '#/assets/' + encodeURIComponent('blackout/persos/amaia/animations') + '/run');
  // HD d'abord quand le set en a une (Julien 24/10) ; le bouton « HD » repasse au 32 px.
  await page.waitForFunction(() => state.player && state.player.anim.src && state.player.anim.src.name === 'run');
  if (await page.evaluate(() => !!state.player.anim.src.hd)) {
    check('page des animations : HD affichée d\'abord', await page.evaluate(() => state.player.anim.file.includes('/hd/')));
    await page.click('.controls button:has-text("HD : oui")');
  }
  await page.waitForFunction(() => state.player && state.player.anim.file.endsWith('/amaia/px32/run.png') && state.player.img);
  await page.evaluate(() => { window.__draws = []; });
  await page.waitForTimeout(800);
  const amaiaRun = await animOf('amaia', 'run');
  await verifie('amaia/run, page des animations', amaiaRun.frames, amaiaRun.file);
  // Index périmé : largeurs de case fausses dans l'index, la planche fait foi.
  await persosView(page);
  await page.evaluate(() => { for (const x of bkAnims('amaia')) x.w += 22; window.__draws = []; });
  const c2 = cell('amaia', 'run');
  await page.locator(c2).scrollIntoViewIfNeeded();
  await page.hover(c2);
  await page.waitForTimeout(800);
  await verifie('index périmé : la planche fait foi', amaiaRun.frames, amaiaRun.file);
  // En-têtes : URL versionnée immuable, sinon revalidée.
  const hdr = await page.evaluate(async () => {
    const f = bkAnims('amaia').find((x) => x.name === 'run').file;
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
