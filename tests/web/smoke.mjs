// Smoke test web : WebKit en émulation iPhone paysage (844×390, tactile),
// ou Chromium. Charge le build, vérifie l'absence d'erreurs console,
// capture l'écran. Usage : node smoke.mjs [webkit|chromium] [#scene=...] [secondes]
import { webkit, chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
import { serve } from './serve.mjs';

const engine = process.argv[2] || 'webkit';
const hash = process.argv[3] || '';
const seconds = Number(process.argv[4] || 8);
const root = path.resolve(import.meta.dirname, '../../web/build');
const outDir = path.resolve(import.meta.dirname, '../out');
fs.mkdirSync(outDir, { recursive: true });

const server = await serve(root, 8765);
const browser = await (engine === 'webkit' ? webkit : chromium).launch();
const context = await browser.newContext({
  viewport: { width: 844, height: 390 }, deviceScaleFactor: 3,
  isMobile: engine !== 'webkit' ? true : undefined, hasTouch: true,
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
});
const page = await context.newPage();
const errors = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto(`http://localhost:8765/index.html${hash}`);
await page.waitForSelector('canvas');
await page.waitForTimeout(seconds * 1000);
await page.touchscreen.tap(422, 200);
await page.waitForTimeout(1500);
const shot = path.join(outDir, `smoke_${engine}.png`);
await page.screenshot({ path: shot });
const isolated = await page.evaluate(() => self.crossOriginIsolated);
await browser.close();
server.close();
const fatal = errors.filter((e) => !/AudioContext|autoplay|gamepad/i.test(e));
console.log(JSON.stringify({ engine, isolated, errors: fatal, shot }, null, 1));
process.exit(fatal.length ? 1 : 0);
