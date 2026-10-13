// Tournée QA iPhone : tous les écrans et interactions au doigt (Chromium mobile,
// vrais événements tactiles CDP), backend PHP local jetable. Captures dans
// tests/out/iphone_tour/<appareil>/. Usage :
//   node tests/web/iphone_tour.mjs <section[,section…]> [appareil] [moteur]
// sections : onboard skip menu tower versus versusEnd training profile selectors
//            settings abandon direct portrait webkit screens all
// (débogage : tutodbg tapdbg scrolldbg)
import { spawn } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';
import { serve } from './serve.mjs';
import { open } from './iphone_lib.mjs';

const ROOT = path.resolve(import.meta.dirname, '../..');
const SECTION = process.argv[2] || 'all';
const DEVICE = process.argv[3] || 'iphone13';
const ENGINE = process.argv[4] || 'chromium';
const OUT = path.join(ROOT, 'tests/out/iphone_tour', `${DEVICE}${ENGINE === 'webkit' ? '_webkit' : ''}`);
fs.mkdirSync(OUT, { recursive: true });
const API_PORT = 8000 + Math.floor(Math.random() * 900), WEB_PORT = API_PORT + 1000;
const db = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mz-tour-')), 'tour.sqlite');
const php = spawn('php', ['-S', `127.0.0.1:${API_PORT}`, path.join(ROOT, 'backend/public/index.php')],
  { env: { ...process.env, MIARRITZE_DB: db }, stdio: 'ignore' });
await new Promise((r) => setTimeout(r, 800));
const server = await serve(path.join(ROOT, 'web/build'), WEB_PORT, API_PORT);
const BASE = `http://localhost:${WEB_PORT}/index.html?qa=1`;

const log = [];
const note = (s) => { console.log(s); log.push(s); };
let shotN = 0;
let SUB = OUT;

/** Capture + inventaire des boutons (signale ceux qui débordent de l'écran). */
async function snap(ph, name) {
  const file = path.join(SUB, `${String(++shotN).padStart(2, '0')}_${name}.png`);
  await ph.shot(file);
  const q = await ph.qa();
  const bad = [];
  for (const b of (q?.buttons || [])) {
    const l = b.x - b.w / 2, r = b.x + b.w / 2, t = b.y - b.h / 2, btm = b.y + b.h / 2;
    if (l < -0.001 || r > 1.001 || t < -0.001 || btm > 1.001) bad.push(`${b.t}[${l.toFixed(2)},${t.toFixed(2)},${r.toFixed(2)},${btm.toFixed(2)}]`);
  }
  note(`[${name}] scène=${q?.scene?.split('/').pop()} vue=${q?.view} boutons=${(q?.buttons || []).map((b) => b.t + (b.off ? '(off)' : '')).join(' | ')}${bad.length ? '  HORS ÉCRAN: ' + bad.join(' ') : ''}  -> ${path.basename(file)}`);
  return q;
}

async function boot(hash = '', opts = {}) {
  const ph = await open(BASE + hash, { device: DEVICE, engine: ENGINE, ...opts });
  for (let i = 0; i < 60; i++) { if ((await ph.qa())?.scene) break; await ph.wait(250); }
  await ph.wait(1500);
  return ph;
}

// ------------------------------------------------------------ multi-touch
class Fingers {
  constructor(ph) { this.ph = ph; this.pts = new Map(); }
  async send(type) {
    const tp = [...this.pts.entries()].map(([id, [x, y]]) => ({ x, y, id }));
    await this.ph.cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' && tp.length === 0 ? [] : tp });
  }
  async down(id, fx, fy) { this.pts.set(id, await this.ph.toCss(fx, fy)); await this.send('touchStart'); }
  async move(id, fx, fy, steps = 5) {
    const [x0, y0] = this.pts.get(id); const [x1, y1] = await this.ph.toCss(fx, fy);
    for (let i = 1; i <= steps; i++) { this.pts.set(id, [x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps]); await this.send('touchMove'); await this.ph.wait(16); }
  }
  async up(id) {
    // CDP : touchEnd liste les doigts restants.
    this.pts.delete(id);
    await this.send('touchEnd');
  }
  async upAll() { this.pts.clear(); await this.send('touchEnd'); }
}

/** Centres des boutons de la manette virtuelle (formule de touch_controls.gd). */
async function pad(ph) {
  const q = await ph.qa();
  const [w, h] = q.view;
  const css = await ph.canvas();
  const sc = h / Math.max(css.h, 200);
  const r = 64 * sc * 1.15 * 0.5, gap = r * 2.05, edge = 44 * sc;
  const c = [w - edge - gap - r * 1.15, h - edge - gap - r];
  const f = ([x, y]) => [x / w, y / h];
  return {
    guard: f([c[0], c[1] - gap]), punch: f([c[0] - gap, c[1]]), special: f([c[0] + gap, c[1]]),
    kick: f([c[0], c[1] + gap]), maree: f([c[0], c[1] - 2 * gap]), r: r / h,
  };
}

async function tapPad(ph, P, name, ms = 80) {
  const [x, y] = await ph.toCss(...P[name]);
  await ph.touch([[x, y]], ms);
}

async function holdPad(ph, P, name, ms) { const [x, y] = await ph.toCss(...P[name]); await ph.touch([[x, y]], ms); }

/** Crée un profil via l'input HTML (écran « Qui joue ? »). */
async function typePseudo(ph, pseudo) {
  const loc = ph.page.locator('input[id^="godot-text"]').first();
  await loc.waitFor({ state: 'visible', timeout: 5000 });
  if (ENGINE === 'webkit') await loc.click(); else await loc.tap();
  await ph.page.keyboard.press('ControlOrMeta+A');
  await ph.page.keyboard.press('Backspace');
  await ph.page.keyboard.type(pseudo);
  await ph.wait(300);
}

async function newProfileAndMenu(ph, pseudo = 'Louis9') {
  await ph.tapFrac(0.5, 0.6, 1500);
  await ph.waitScene('profile_select');
  await typePseudo(ph, pseudo);
  await ph.tapText("C'est parti", 2500);
  await ph.waitScene('fight_scene');
  await ph.wait(1500);
  await ph.tapText('Passer', 2500);
  return await ph.waitScene('main_menu', 6000);
}

/** Combat au doigt : avance et frappe pendant `sec` secondes. */
async function brawl(ph, sec, { attack = true } = {}) {
  const P = await pad(ph);
  const F = new Fingers(ph);
  const t0 = Date.now();
  while (Date.now() - t0 < sec * 1000) {
    await F.down(1, 0.22, 0.75); await F.move(1, 0.30, 0.75, 3);
    if (attack) {
      for (const b of ['punch', 'punch', 'kick', 'special']) {
        await F.down(2, ...P[b]); await ph.wait(70); await F.up(2); await ph.wait(120);
      }
    } else await ph.wait(500);
    await F.upAll(); await ph.wait(100);
  }
}

// ------------------------------------------------------------ sections
const S = {};

S.onboard = async () => {
  const ph = await boot();
  await snap(ph, 'titre');
  await ph.tapFrac(0.5, 0.6, 1800);
  const ok = await ph.waitScene('profile_select');
  await snap(ph, 'qui_joue');
  note(`titre -> qui joue : ${ok}`);
  const inputs = await ph.page.$$eval('input[id^="godot-text"]', (els) => els.map((e) => ({ d: e.style.display, l: e.style.left, t: e.style.top, w: e.style.width, h: e.style.height })));
  note(`inputs HTML : ${JSON.stringify(inputs)}`);
  // pseudo invalide
  await typePseudo(ph, 'a');
  await ph.tapText("C'est parti", 1200);
  await snap(ph, 'pseudo_invalide_1car');
  await typePseudo(ph, 'Jean Pierre');
  await ph.tapText("C'est parti", 1200);
  await snap(ph, 'pseudo_invalide_espace');
  note(`scène après invalide : ${(await ph.qa()).scene}`);
  // Entrée au clavier iOS (« done ») sur pseudo valide ? on garde le bouton.
  await typePseudo(ph, 'Louis9');
  await snap(ph, 'pseudo_valide_saisi');
  await ph.tapText("C'est parti", 2500);
  const inFight = await ph.waitScene('fight_scene');
  note(`tutoriel lancé : ${inFight}`);
  await ph.wait(2500);
  await snap(ph, 'tuto_0_debut');
  const P = await pad(ph);
  note(`pad : ${JSON.stringify(P)}`);
  const F = new Fingers(ph);
  // 1 BOUGER : glisser vers l'avant
  await F.down(1, 0.2, 0.7); await F.move(1, 0.3, 0.7); await ph.wait(1200); await snap(ph, 'tuto_1_bouger_pendant'); await F.upAll();
  await ph.wait(1200); await snap(ph, 'tuto_1_bouger_apres');
  // 2 FRAPPER : P en rafale (comme un enfant)
  for (let k = 0; k < 3; k++) { for (let i = 0; i < 3; i++) { await tapPad(ph, P, 'punch', 50); await ph.wait(60); } await ph.wait(700); }
  await snap(ph, 'tuto_2_frapper_apres');
  await ph.wait(800);
  // 3 GARDER : maintenir G pendant que Hondar attaque
  await holdPad(ph, P, 'guard', 4000);
  await ph.wait(900);
  await snap(ph, 'tuto_3_garde_apres');
  // 4 UPPERCUT : bas-arrière + P (deux doigts)
  for (let k = 0; k < 3; k++) {
    await F.down(1, 0.25, 0.7); await F.move(1, 0.19, 0.8); await ph.wait(150);
    await F.down(2, ...P.punch); await ph.wait(60); await snap(ph, 'tuto_4_uppercut_pendant_' + k); await F.up(2); await ph.wait(200); await F.upAll();
    await ph.wait(900);
  }
  await snap(ph, 'tuto_4_uppercut_apres');
  // 5 SPÉCIAL
  await tapPad(ph, P, 'special', 60); await ph.wait(300); await snap(ph, 'tuto_5_special_pendant'); await ph.wait(1500);
  await snap(ph, 'tuto_5_special_apres');
  // 6 SUPER : bouton MARÉE
  await tapPad(ph, P, 'maree', 60); await ph.wait(600); await snap(ph, 'tuto_6_super_pendant'); await ph.wait(3500);
  await snap(ph, 'tuto_6_super_apres');
  // 7 K.O.
  await brawl(ph, 12);
  await snap(ph, 'tuto_7_ko');
  await ph.wait(4000);
  await snap(ph, 'tuto_fin');
  note(`après tutoriel : ${(await ph.qa()).scene}`);
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

S.tutodbg = async () => {
  const ph = await boot('#scene=tutorial');
  await ph.wait(2500);
  const P = await pad(ph);
  const F = new Fingers(ph);
  await F.down(1, 0.2, 0.7); await F.move(1, 0.3, 0.7); await ph.wait(1200); await F.upAll(); await ph.wait(1200);
  for (let k = 0; k < 4; k++) { for (let i = 0; i < 3; i++) { await tapPad(ph, P, 'punch', 50); await ph.wait(60); } await ph.wait(700); }
  await ph.wait(1500);
  await snap(ph, 'dbg_garde_debut');
  if (process.env.KEYB) { await ph.page.keyboard.down('Space'); for (let i = 0; i < 6; i++) { await ph.wait(700); await snap(ph, 'dbg_kb_' + i); } await ph.page.keyboard.up('Space'); await ph.close(); return; }
  await ph.page.evaluate(() => { window.__tl = []; for (const t of ['touchstart', 'touchend', 'touchcancel', 'contextmenu']) document.addEventListener(t, (e) => window.__tl.push(t + '@' + Math.round(performance.now())), true); });
  const [x, y] = await ph.toCss(...P.guard);
  await ph.cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y, id: 1 }] });
  for (let i = 0; i < 6; i++) { await ph.wait(700); if (process.env.JITTER) await ph.cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x + (i % 2), y, id: 1 }] }); await snap(ph, 'dbg_garde_tenue_' + i); }
  note('événements DOM : ' + JSON.stringify(await ph.page.evaluate(() => window.__tl)));
  await ph.cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await ph.wait(1000); await snap(ph, 'dbg_garde_fin');
  await ph.close();
};

S.tapdbg = async () => {
  const ph = await boot('#scene=tutorial');
  await ph.wait(2500);
  const P = await pad(ph);
  await ph.page.evaluate(() => { window.__tl = []; for (const t of ['touchstart', 'touchend', 'touchcancel']) document.addEventListener(t, (e) => window.__tl.push(t + ':' + [...e.changedTouches].map((x) => x.identifier).join(',') + '/' + e.touches.length), true); });
  let id = 10;
  await ph.wait(Number(process.env.PRE || 0));
  if (process.env.DRAGFIRST) { const F = new Fingers(ph); await F.down(1, 0.2, 0.7); await F.move(1, 0.21, 0.7); await F.upAll(); await ph.wait(300); }
  for (let i = 0; i < 6; i++) {
    const [x, y] = await ph.toCss(...P.punch);
    const tid = process.env.NEWID ? id++ : 1;
    await ph.cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y, id: tid }] });
    await ph.wait(Number(process.env.HOLD || 70));
    await ph.cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await ph.wait(500);
    await snap(ph, 'tapdbg_' + i);
  }
  note('DOM : ' + JSON.stringify(await ph.page.evaluate(() => window.__tl)));
  await ph.close();
};

S.scrolldbg = async () => {
  const ph = await boot('#scene=settings');
  await snap(ph, 'sc_0');
  // glisser depuis un bouton, puis depuis l'étiquette SONS, puis sur la barre de défilement, avec mouvement lent
  await ph.drag(0.5, 0.85, 0.5, 0.25, 300, 20); await ph.wait(500); await snap(ph, 'sc_1_bouton');
  await ph.drag(0.12, 0.71, 0.12, 0.2, 300, 20); await ph.wait(500); await snap(ph, 'sc_2_label');
  await ph.drag(0.905, 0.3, 0.905, 0.9, 300, 20); await ph.wait(500); await snap(ph, 'sc_3_barre');
  await ph.page.mouse.move(400, 250); await ph.page.mouse.wheel(0, 400); await ph.wait(500); await snap(ph, 'sc_4_molette');
  await ph.close();
};

S.selectors = async () => {
  const ph = await boot();
  await newProfileAndMenu(ph);
  await ph.tapText('Profil', 2200);
  await snap(ph, 'sel_avant');
  const rows = (await ph.buttons()).filter((b) => b.t === '>').sort((a, b) => a.y - b.y);
  for (const b of rows) { await ph.tapFrac(b.x, b.y, 500); }
  await snap(ph, 'sel_apres_un_suivant');
  for (const b of rows) { await ph.tapFrac(b.x, b.y, 500); }
  await snap(ph, 'sel_apres_deux_suivants');
  // Pyramide : changer de costume au doigt ? (aucun bouton attendu)
  await ph.tapText('Retour', 2000);
  await ph.tapText('Pyramide du Phare', 2200);
  const q = await snap(ph, 'sel_costume_boutons');
  note('boutons sélection : ' + q.buttons.map((b) => b.t).join(' | '));
  // glisser verticalement sur l'aperçu (geste possible pour costume ?)
  await ph.drag(0.12, 0.7, 0.12, 0.4, 100); await ph.wait(500);
  await snap(ph, 'sel_costume_glisse');
  await ph.close();
};

S.abandon = async () => {
  const ph = await boot();
  await newProfileAndMenu(ph);
  await ph.tapText('Pyramide du Phare', 2200);
  await ph.tapText(/^OK$/, 1200);
  await ph.tapText('Facile', 2500);
  await ph.waitScene('tower'); await ph.wait(1500);
  await ph.tapText('Abandonner', 300);
  for (let i = 0; i < 8; i++) { const q = await ph.qa(); note(`t+${i * 400} ms : ${q.scene.split('/').pop()}`); await ph.wait(400); }
  await snap(ph, 'apres_abandonner');
  // Lobby sans groupe : boutons Classement / Match rapide
  await ph.page.goto(BASE); await ph.wait(3500); await ph.tapFrac(0.5, 0.6, 1800); await ph.tapText('Louis9', 2000);
  await ph.tapText('En ligne', 2200);
  await ph.tapText('Classement', 1500); await snap(ph, 'salon_sans_groupe_classement');
  await ph.tapText('Match rapide', 2500); await snap(ph, 'salon_sans_groupe_match');
  note('erreurs : ' + JSON.stringify(ph.errors));
  await ph.close();
};

S.skip = async () => {
  const ph = await boot();
  await ph.tapFrac(0.5, 0.6, 1800);
  await ph.waitScene('profile_select');
  await typePseudo(ph, 'Maia7');
  await ph.tapText("C'est parti", 2500);
  await ph.waitScene('fight_scene'); await ph.wait(2000);
  await snap(ph, 'tuto_avec_passer');
  const b = await ph.tapText('Passer', 2500);
  note(`Passer touché en ${JSON.stringify(b)}`);
  await snap(ph, 'apres_passer');
  note(`scène après Passer : ${(await ph.qa()).scene}`);
  // Le tutoriel est-il marqué fait ? relancer le titre
  await ph.close();
};

S.menu = async () => {
  const ph = await boot();
  await newProfileAndMenu(ph);
  await snap(ph, 'menu');
  const labels = ['Pyramide du Phare', 'Versus', 'En ligne', 'Entraînement', 'Tutoriel', 'Profil', 'Réglages'];
  for (const l of labels) {
    await ph.waitScene('main_menu');
    await ph.wait(500);
    await ph.tapText(l, 2200);
    const q = await snap(ph, `menu_${l.replace(/\W+/g, '_')}`);
    note(`menu « ${l} » -> ${q.scene}`);
    // retour au menu
    const back = q.buttons.find((b) => /Retour|Passer|Abandonner/.test(b.t));
    if (back) await ph.tapText(back.t, 2000);
    if (!(await ph.waitScene('main_menu', 4000))) {
      note(`  pas de retour direct depuis ${q.scene}`);
      await ph.page.goto(BASE); await ph.wait(3000); await ph.tapFrac(0.5, 0.6, 1800);
      await ph.tapText('Louis9', 2000);
    }
  }
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

S.tower = async () => {
  const ph = await boot();
  await newProfileAndMenu(ph);
  await ph.tapText('Pyramide du Phare', 2200);
  await snap(ph, 'sel_pyramide');
  // tap sur une case (Maia, 2e) puis re-tap = confirmer
  const q = await ph.qa();
  const [w, h] = q.view;
  const cell = (i) => { const gx = Math.floor((w - 180) / 2), gy = h - 60 - 8; return [(gx + (i % 6) * 30 + 15) / w, (gy + Math.floor(i / 6) * 30 + 15) / h]; };
  await ph.tapFrac(...cell(3), 800);
  await snap(ph, 'sel_tap_case3');
  await ph.tapFrac(...cell(7), 800);
  await snap(ph, 'sel_tap_case7');
  await ph.tapFrac(...cell(1), 800);
  await snap(ph, 'sel_tap_case1');
  // Bouton OK
  await ph.tapText(/^OK$/, 1200);
  await snap(ph, 'sel_difficulte');
  await ph.tapText('Facile', 2500);
  await ph.waitScene('tower');
  await ph.wait(1500);
  await snap(ph, 'pyramide');
  await ph.tapText('Combattre', 3500);
  await snap(ph, 'vs_pyramide');
  await ph.waitScene('fight_scene', 6000);
  await ph.wait(3500);
  await snap(ph, 'combat_debut');
  // Joystick + boutons
  await brawl(ph, 4);
  await snap(ph, 'combat_brawl');
  // Pause
  await ph.tapText(/^II$/, 900);
  await snap(ph, 'pause');
  await ph.tapText('Liste des coups', 900);
  await snap(ph, 'pause_liste_coups');
  // drag pour faire défiler la liste
  await ph.drag(0.5, 0.75, 0.5, 0.25, 200);
  await snap(ph, 'pause_liste_coups_defilee');
  await ph.tapText('Fermer', 900);
  await snap(ph, 'pause_apres_fermer');
  await ph.tapText('Reprendre', 900);
  await snap(ph, 'apres_reprendre');
  // Perdre : ne rien faire
  note('on laisse l\'ordi gagner…');
  for (let i = 0; i < 40; i++) {
    await ph.wait(3000);
    const s = (await ph.qa()).scene;
    if (!s.includes('fight_scene')) break;
  }
  await ph.wait(1500);
  await snap(ph, 'apres_defaite');
  note(`après défaite : ${(await ph.qa()).scene}`);
  // Réessayer = Combattre !
  if ((await ph.qa()).scene.includes('tower')) {
    await ph.tapText('Combattre', 3500);
    await ph.waitScene('fight_scene', 6000); await ph.wait(3000);
    await ph.tapText(/^II$/, 900);
    await ph.tapText('Quitter', 2500);
    await snap(ph, 'pause_quitter');
    note(`après Quitter : ${(await ph.qa()).scene}`);
    if ((await ph.qa()).scene.includes('tower')) {
      await ph.tapText('Abandonner', 2500);
      await snap(ph, 'apres_abandonner');
      note(`après Abandonner : ${(await ph.qa()).scene}`);
    }
  }
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

S.versus = async () => {
  const ph = await boot();
  await newProfileAndMenu(ph);
  await ph.tapText('Versus', 2200);
  await snap(ph, 'vs_sel');
  const q = await ph.qa();
  const [w, h] = q.view;
  const cell = (i) => { const gx = Math.floor((w - 180) / 2), gy = h - 60 - 8; return [(gx + (i % 6) * 30 + 15) / w, (gy + Math.floor(i / 6) * 30 + 15) / h]; };
  await ph.tapFrac(...cell(2), 700); await ph.tapFrac(...cell(2), 900);
  await snap(ph, 'vs_sel_j1_ok');
  await ph.tapFrac(...cell(9), 700);
  await snap(ph, 'vs_sel_j2_tap');
  await ph.tapText(/^OK$/, 1200);
  await snap(ph, 'vs_difficulte');
  await ph.tapText('Facile', 2200);
  await snap(ph, 'vs_map');
  await ph.tapText('Aléatoire', 1200);
  await snap(ph, 'vs_splash');
  await ph.waitScene('fight_scene', 6000); await ph.wait(3500);
  await snap(ph, 'vs_combat');
  await brawl(ph, 3);
  await snap(ph, 'vs_combat_brawl');
  for (let i = 0; i < 50; i++) { await ph.wait(3000); if (!(await ph.qa()).scene.includes('fight_scene')) break; }
  await ph.wait(1500);
  await snap(ph, 'vs_resultats');
  note(`après combat : ${(await ph.qa()).scene}`);
  await ph.tapText('Revanche', 3500);
  await snap(ph, 'vs_revanche');
  await ph.waitScene('fight_scene', 6000); await ph.wait(3000);
  await snap(ph, 'vs_revanche_combat');
  note(`revanche -> ${(await ph.qa()).scene}`);
  await ph.tapText(/^II$/, 900);
  await ph.tapText('Quitter', 2500);
  await snap(ph, 'vs_quitter');
  note(`Quitter en versus -> ${(await ph.qa()).scene}`);
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

S.versusEnd = async () => {
  // Fin de versus et boutons de résultats (Changer de combattant, Menu).
  const ph = await boot();
  await newProfileAndMenu(ph);
  await ph.tapText('Versus', 2200);
  const q = await ph.qa(); const [w, h] = q.view;
  const cell = (i) => { const gx = Math.floor((w - 180) / 2), gy = h - 60 - 8; return [(gx + (i % 6) * 30 + 15) / w, (gy + Math.floor(i / 6) * 30 + 15) / h]; };
  await ph.tapFrac(...cell(0), 700); await ph.tapFrac(...cell(0), 900);
  await ph.tapFrac(...cell(0), 700); await ph.tapFrac(...cell(0), 900);
  await snap(ph, 'vs2_meme_perso');
  await ph.tapText('Facile', 2200);
  await snap(ph, 'vs2_map');
  // chaque bouton de map visible ?
  await ph.tapText(/Grande Plage/i, 1200).catch(async () => ph.tapText('Aléatoire', 1200));
  await ph.waitScene('fight_scene', 6000); await ph.wait(3000);
  await snap(ph, 'vs2_combat_miroir');
  for (let i = 0; i < 50; i++) { await ph.wait(3000); if (!(await ph.qa()).scene.includes('fight_scene')) break; }
  await ph.wait(1500);
  await snap(ph, 'vs2_resultats');
  await ph.tapText('Changer de combattant', 2200);
  await snap(ph, 'vs2_changer');
  note(`Changer -> ${(await ph.qa()).scene}`);
  await ph.tapText('Retour', 2200);
  note(`Retour sélection -> ${(await ph.qa()).scene}`);
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

S.training = async () => {
  const ph = await boot();
  await newProfileAndMenu(ph);
  await ph.tapText('Entraînement', 2200);
  await snap(ph, 'tr_sel');
  await ph.tapText(/^OK$/, 2500);
  await ph.waitScene('fight_scene', 6000); await ph.wait(2500);
  await snap(ph, 'tr_combat');
  for (let i = 0; i < 4; i++) {
    const b = await ph.tapText(/Mannequin/, 900);
    await snap(ph, `tr_mannequin_${i}`);
  }
  await brawl(ph, 3);
  await snap(ph, 'tr_brawl');
  await ph.tapText(/^Coups$/, 1000);
  await snap(ph, 'tr_coups');
  // « Fermer » est en bas de la liste : il faut faire défiler au doigt
  for (let i = 0; i < 3; i++) { await ph.drag(0.3, 0.8, 0.3, 0.2, 150, 12); await ph.wait(300); }
  await snap(ph, 'tr_coups_defile');
  await ph.tapText('Fermer', 900);
  await snap(ph, 'tr_coups_ferme');
  await ph.tapText(/^II$/, 900);
  await snap(ph, 'tr_pause');
  await ph.tapText('Quitter', 2500);
  await snap(ph, 'tr_quitter');
  note(`Quitter entraînement -> ${(await ph.qa()).scene}`);
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

S.profile = async () => {
  const ph = await boot();
  await newProfileAndMenu(ph);
  // En ligne sans groupe
  await ph.tapText('En ligne', 2200);
  await snap(ph, 'salon_sans_groupe');
  await ph.tapText('Aller au profil', 2200);
  await snap(ph, 'profil');
  // chaque sélecteur
  for (let k = 0; k < 2; k++) {
    const bs = (await ph.buttons()).filter((b) => b.t === '>' || b.t === '<');
    note(`sélecteurs : ${bs.length}`);
    for (const b of bs) { await ph.tapFrac(b.x, b.y, 500); }
  }
  await snap(ph, 'profil_apres_selecteurs');
  await ph.tapText('Créer', 2500);
  await snap(ph, 'profil_cree');
  const txt = await ph.page.$$eval('input[id^="godot-text"]', (els) => els.map((e) => e.style.display + ' ' + e.style.top));
  note(`inputs profil : ${JSON.stringify(txt)}`);
  // code invalide via input
  try {
    await typePseudo(ph, 'ABC');
    await ph.tapText('Rejoindre', 1500);
    await snap(ph, 'profil_code_invalide');
    await typePseudo(ph, 'ZZZZZZ');
    await ph.tapText('Rejoindre', 2000);
    await snap(ph, 'profil_code_inconnu');
  } catch (e) { note('input code : ' + e.message); }
  // défilement de la liste
  await ph.drag(0.7, 0.8, 0.7, 0.3, 200);
  await snap(ph, 'profil_defile');
  await ph.tapText('Retour', 2000);
  await ph.tapText('En ligne', 2500);
  await ph.wait(3000);
  await snap(ph, 'salon_avec_groupe');
  await ph.tapText('Classement', 2000);
  await snap(ph, 'salon_classement');
  const bs = await ph.buttons();
  const close = bs.find((b) => /Fermer|OK|Retour/.test(b.t) && b.y > 0.2);
  if (close) { await ph.tapFrac(close.x, close.y, 1000); await snap(ph, 'salon_classement_ferme'); }
  await ph.tapText('Match rapide', 2500);
  await snap(ph, 'salon_match_rapide');
  await ph.wait(3000);
  await snap(ph, 'salon_match_rapide_3s');
  await ph.tapText('Retour', 2000);
  note(`Retour salon -> ${(await ph.qa()).scene}`);
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

S.settings = async () => {
  const ph = await boot();
  await newProfileAndMenu(ph);
  await ph.tapText('Réglages', 2200);
  await snap(ph, 'reglages');
  // tap sur chaque option visible une fois
  const opts = ['Mode', 'Afficher la manette', 'Taille des boutons', 'Opacité'];
  for (const o of opts) { await ph.tapText(new RegExp('^' + o + ' :'), 600); }
  await snap(ph, 'reglages_apres_taps');
  // défilement au doigt
  await ph.drag(0.5, 0.85, 0.5, 0.3, 300);
  await ph.wait(600);
  await snap(ph, 'reglages_defile1');
  await ph.drag(0.5, 0.85, 0.5, 0.2, 300);
  await ph.wait(600);
  await snap(ph, 'reglages_defile2');
  for (const o of ['Musique', 'Effets', 'Voix', 'Couleurs pour daltoniens', 'Vibrations']) {
    try { await ph.tapText(new RegExp('^' + o + ' :'), 600); } catch (e) { note('option introuvable/non visible : ' + o); }
  }
  await snap(ph, 'reglages_apres_taps2');
  // Touche clavier sur tactile (inutile mais doit pas bloquer)
  for (let i = 0; i < 4; i++) { await ph.drag(0.5, 0.85, 0.5, 0.15, 200); await ph.wait(300); }
  await snap(ph, 'reglages_bas');
  await ph.tapText('Retour', 2000);
  // Effet en combat : mode gestes + opacité + taille → entraînement
  await ph.tapText('Entraînement', 2200);
  await ph.tapText(/^OK$/, 2500);
  await ph.waitScene('fight_scene', 6000); await ph.wait(2500);
  await snap(ph, 'reglages_effet_combat');
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

S.direct = async () => {
  for (const sc of ['ending:louis', 'vs', 'results', 'tutorial', 'touchfight', 'stage_select']) {
    const ph = await boot('#scene=' + sc);
    await ph.wait(1500);
    await snap(ph, `direct_${sc.replace(/\W/g, '_')}`);
    if (sc.startsWith('ending')) {
      for (let i = 0; i < 12; i++) { await ph.wait(2500); const b = await ph.buttons(); if (b.some((x) => x.t === 'Menu')) break; }
      await snap(ph, 'direct_ending_fin');
      await ph.tapText('Menu', 2000).catch((e) => note(e.message));
      note(`ending Menu -> ${(await ph.qa()).scene}`);
    }
    if (sc === 'vs') { await ph.wait(3000); await snap(ph, 'direct_vs_apres'); }
    if (sc === 'results') {
      await ph.tapText('Revanche', 2500).catch((e) => note('results revanche: ' + e.message));
      await snap(ph, 'direct_results_revanche');
      note(`results Revanche sans contexte -> ${(await ph.qa()).scene}`);
    }
    note(`erreurs console ${sc} : ${JSON.stringify(ph.errors.slice(0, 6))}`);
    await ph.close();
  }
};

S.portrait = async () => {
  const ph = await boot('', { portrait: true });
  await snap(ph, 'portrait_titre');
  // passer en paysage
  const d = { iphone13: [844, 390], iphone_se: [667, 375], iphone_pro_max: [932, 430] }[DEVICE];
  await ph.page.setViewportSize({ width: d[0], height: d[1] }); await ph.wait(1500);
  await snap(ph, 'portrait_retour_paysage');
  await ph.tapFrac(0.5, 0.6, 1800);
  await snap(ph, 'portrait_qui_joue');
  await ph.page.setViewportSize({ width: d[1], height: d[0] }); await ph.wait(1500);
  await snap(ph, 'portrait_qui_joue_portrait');
  await ph.page.setViewportSize({ width: d[0], height: d[1] }); await ph.wait(1500);
  await typePseudo(ph, 'Rot8');
  await ph.tapText("C'est parti", 2500); await ph.wait(2000);
  await ph.page.setViewportSize({ width: d[1], height: d[0] }); await ph.wait(1500);
  await snap(ph, 'portrait_en_combat');
  await ph.page.setViewportSize({ width: d[0], height: d[1] }); await ph.wait(1500);
  await snap(ph, 'portrait_combat_repris');
  const P = await pad(ph);
  await tapPad(ph, P, 'punch'); await ph.wait(400);
  await snap(ph, 'portrait_combat_coup');
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

S.webkit = async () => {
  const ph = await boot();
  await snap(ph, 'wk_titre');
  await ph.tapFrac(0.5, 0.6, 1800);
  await snap(ph, 'wk_qui_joue');
  await typePseudo(ph, 'Wk123');
  await ph.tapText("C'est parti", 3000);
  await ph.wait(2000);
  await snap(ph, 'wk_tuto');
  await ph.tapText('Passer', 2500);
  await snap(ph, 'wk_menu');
  await ph.tapText('Pyramide du Phare', 2200);
  await snap(ph, 'wk_selection');
  await ph.tapText(/^OK$/, 1200);
  await ph.tapText('Facile', 2500);
  await snap(ph, 'wk_pyramide');
  await ph.tapText('Combattre', 3500);
  await ph.wait(4000);
  await snap(ph, 'wk_combat');
  const P = await pad(ph);
  for (let i = 0; i < 4; i++) { await tapPad(ph, P, 'punch'); await ph.wait(200); }
  await snap(ph, 'wk_combat_coups');
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

S.screens = async () => {
  // Écrans principaux (autres appareils) : titre, qui joue, menu, sélection, pyramide, combat, map, réglages, profil.
  const ph = await boot();
  await snap(ph, 'titre');
  await ph.tapFrac(0.5, 0.6, 1800);
  await snap(ph, 'qui_joue');
  await typePseudo(ph, 'Petit9');
  await ph.tapText("C'est parti", 2500); await ph.wait(2500);
  await snap(ph, 'tuto');
  await ph.tapText('Passer', 2500);
  await snap(ph, 'menu');
  await ph.tapText('Pyramide du Phare', 2200);
  await snap(ph, 'selection');
  await ph.tapText(/^OK$/, 1200);
  await snap(ph, 'difficulte');
  await ph.tapText('Facile', 2500); await ph.wait(1200);
  await snap(ph, 'pyramide');
  await ph.tapText('Combattre', 3500); await ph.wait(3500);
  await snap(ph, 'combat');
  await ph.tapText(/^II$/, 900);
  await snap(ph, 'pause');
  await ph.tapText('Quitter', 2500);
  if ((await ph.qa()).scene.includes('tower')) await ph.tapText('Abandonner', 2500);
  if ((await ph.qa()).scene.includes('title')) { await ph.tapFrac(0.5, 0.6, 1800); await snap(ph, 'liste_profils'); await ph.tapText('Petit9', 2000); }
  await ph.tapText('Versus', 2200);
  const q = await ph.qa(); const [w, h] = q.view;
  const cell = (i) => { const gx = Math.floor((w - 180) / 2), gy = h - 60 - 8; return [(gx + (i % 6) * 30 + 15) / w, (gy + Math.floor(i / 6) * 30 + 15) / h]; };
  await ph.tapFrac(...cell(4), 600); await ph.tapFrac(...cell(4), 800);
  await ph.tapFrac(...cell(5), 600); await ph.tapFrac(...cell(5), 800);
  await ph.tapText('Facile', 2200);
  await snap(ph, 'map');
  await ph.tapText('Retour', 1500).catch(() => {});
  await ph.page.goto(BASE); await ph.wait(3500); await ph.tapFrac(0.5, 0.6, 1800);
  await ph.tapText('Petit9', 2000);
  await ph.tapText('Réglages', 2200);
  await snap(ph, 'reglages');
  await ph.tapText('Retour', 2000);
  await ph.tapText('Profil', 2200);
  await snap(ph, 'profil');
  await ph.tapText('Retour', 2000);
  await ph.tapText('Entraînement', 2200);
  await ph.tapText(/^OK$/, 2500); await ph.wait(2500);
  await snap(ph, 'entrainement');
  note(`erreurs console : ${JSON.stringify(ph.errors.slice(0, 10))}`);
  await ph.close();
};

const order = SECTION === 'all' ? ['onboard', 'skip', 'menu', 'tower', 'versus', 'versusEnd', 'training', 'profile', 'selectors', 'settings', 'abandon', 'direct', 'portrait'] : SECTION.split(',');
for (const s of order) {
  note(`===== ${s} (${DEVICE}, ${ENGINE})`);
  SUB = path.join(OUT, s); fs.rmSync(SUB, { recursive: true, force: true }); fs.mkdirSync(SUB, { recursive: true }); shotN = 0;
  try { await S[s](); } catch (e) { note(`ÉCHEC section ${s} : ${e.message}`); }
}
fs.writeFileSync(path.join(OUT, `log_${SECTION}.txt`), log.join('\n'));
server.close();
php.kill();
process.exit(0);
