// Parcours des écrans au clavier (Chromium) avec captures à chaque étape.
// Usage : node flow.mjs <nom> "<étapes>" ; étapes séparées par ";" :
//   k:Enter  (touche)   w:1500 (attente ms)   s:nom (capture)   d:d/u:d (appui/relâche)
import { chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
import { serve } from './serve.mjs';

const name = process.argv[2] || 'flow';
const steps = (process.argv[3] || '').split(';').filter(Boolean);
const root = path.resolve(import.meta.dirname, '../../web/build');
const out = path.resolve(import.meta.dirname, `../out/${name}`);
fs.mkdirSync(out, { recursive: true });
const server = await serve(root, 8767);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1152, height: 648 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error' || /SCRIPT ERROR|ERROR:/.test(m.text())) errors.push(m.text()); });
await page.goto('http://localhost:8767/index.html');
await page.waitForSelector('canvas');
await page.waitForTimeout(3500);
await page.click('canvas', { position: { x: 5, y: 5 } });
let n = 0;
for (const step of steps) {
  const [op, arg] = [step.slice(0, step.indexOf(':')), step.slice(step.indexOf(':') + 1)];
  if (op === 'k') await page.keyboard.press(arg);
  else if (op === 'w') await page.waitForTimeout(Number(arg));
  else if (op === 'd') await page.keyboard.down(arg);
  else if (op === 'u') await page.keyboard.up(arg);
  else if (op === 's') await page.screenshot({ path: `${out}/${String(n++).padStart(2, '0')}_${arg}.png` });
  else if (op === 'c') { const [x, y] = arg.split(',').map(Number); await page.mouse.click(x, y); }
}
await browser.close();
server.close();
console.log(JSON.stringify({ errors: errors.slice(0, 10) }, null, 1));
process.exit(errors.length ? 1 : 0);
