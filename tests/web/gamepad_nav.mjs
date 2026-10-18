// Parcours complet À LA MANETTE dans le build web (Chromium, sans tactile) :
// une manette « standard » simulée (navigator.getGamepads) enchaîne titre →
// création du profil au clavier manette → tutoriel → pause → passer →
// menu principal → sélection → retour. Vérifie la scène à chaque étape
// (window.__qa, ?qa=1) et capture les écrans dans tests/out/gamepad_nav/.
// Usage : node gamepad_nav.mjs
import { chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
import { serve } from './serve.mjs';

const root = path.resolve(import.meta.dirname, '../../web/build');
const out = path.resolve(import.meta.dirname, '../out/gamepad_nav');
fs.mkdirSync(out, { recursive: true });
const server = await serve(root, 8771);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1152, height: 648 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error' || /SCRIPT ERROR/.test(m.text())) errors.push(m.text()); });

// Manette simulée (disposition « standard » du W3C : 0 = A, 1 = B, 9 = START,
// 12-15 = croix haut/bas/gauche/droite).
await page.addInitScript(() => {
  const buttons = Array.from({ length: 17 }, () => ({ pressed: false, touched: false, value: 0 }));
  const pad = { id: 'Xbox Wireless Controller (STANDARD GAMEPAD Vendor: 045e Product: 0b13)', index: 0,
    connected: true, mapping: 'standard', timestamp: 0, axes: [0, 0, 0, 0], buttons, vibrationActuator: null };
  window.__pad = pad;
  navigator.getGamepads = () => [pad, null, null, null];
  window.__padSet = (i, on) => {
    buttons[i] = { pressed: on, touched: on, value: on ? 1 : 0 };
    pad.timestamp = performance.now();
    if (!window.__padAnnounced) {
      window.__padAnnounced = true;
      const ev = new Event('gamepadconnected');
      ev.gamepad = pad;
      window.dispatchEvent(ev);
    }
  };
});

const BTN = { a: 0, b: 1, start: 9, up: 12, down: 13, left: 14, right: 15 };
async function press(name, hold = 120) {
  await page.evaluate(([i]) => window.__padSet(i, true), [BTN[name]]);
  await page.waitForTimeout(hold);
  await page.evaluate(([i]) => window.__padSet(i, false), [BTN[name]]);
  await page.waitForTimeout(180);
}
const scene = () => page.evaluate(() => (window.__qa && window.__qa.scene) || '');
let n = 0;
const shot = async (name) => page.screenshot({ path: `${out}/${String(++n).padStart(2, '0')}_${name}.png` });
const checks = [];
async function expectScene(part, label) {
  await page.waitForTimeout(900);
  const s = await scene();
  checks.push({ label, ok: s.includes(part), scene: s });
  await shot(label);
}

await page.goto('http://localhost:8771/index.html?qa=1');
await page.waitForSelector('canvas');
await page.waitForTimeout(4500);
await press('a');                                   // titre → « Qui joue ? »
await expectScene('profile_select', 'profil_creation');
await press('a');                                   // « Écrire à la manette » → clavier
await page.waitForTimeout(400);
await shot('clavier_manette');
for (const k of ['a', 'right', 'a', 'right', 'a']) await press(k);   // « ABC »
await shot('clavier_abc');
await press('start');                               // valider → tutoriel
await page.waitForTimeout(2500);
await expectScene('fight_scene', 'tutoriel');
// En combat, B = SPÉCIAL : il ne doit PAS ouvrir la pause.
const pauseShown = () => page.evaluate(() => (window.__qa?.buttons || []).some((b) => b.t === 'Reprendre'));
await press('b');
await page.waitForTimeout(500);
checks.push({ label: 'b_ne_met_pas_en_pause', ok: !(await pauseShown()) });
await press('start');                               // pause
await page.waitForTimeout(500);
checks.push({ label: 'start_met_en_pause', ok: await pauseShown() });
await shot('pause');
await press('down'); await press('down');           // « Passer le tutoriel »
await press('a');
await page.waitForTimeout(1500);
await expectScene('main_menu', 'menu_principal');
await press('a');                                   // Pyramide du Phare
await expectScene('fighter_select', 'selection');
await press('right');
await press('b');                                   // retour
await expectScene('main_menu', 'retour_menu');
await press('down'); await press('down'); await press('down'); // Profil
await press('a');
await expectScene('profile_edit', 'profil');
await press('b');
await expectScene('main_menu', 'retour_menu_2');

await browser.close();
server.close();
const failed = checks.filter((c) => !c.ok);
console.log(JSON.stringify({ checks, errors }, null, 1));
process.exit(failed.length || errors.length ? 1 : 0);
