// Session longue (SPEC §14.3) : combats IA contre IA en boucle dans Chromium,
// mesure de la mémoire (measureUserAgentSpecificMemory, page isolée) toutes les
// 60 s. Usage : node long_session.mjs [minutes]
import { chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
import { serve } from './serve.mjs';

const minutes = Number(process.argv[2] || 30);
const root = path.resolve(import.meta.dirname, '../../web/build');
const out = path.resolve(import.meta.dirname, '../out/long');
fs.mkdirSync(out, { recursive: true });
const server = await serve(root, 8771);
const browser = await chromium.launch({ args: ['--enable-blink-features=ForceEagerMeasureMemory'] });
const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
const errors = [];
let fights = 0;
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { const t = m.text(); if (/autoloop: combat/.test(t)) fights++; if (/SCRIPT ERROR|out of memory|Aborted/i.test(t)) errors.push(t.slice(0, 200)); });
page.on('crash', () => errors.push('CRASH de la page'));
await page.goto('http://localhost:8771/index.html#scene=autoloop');
const samples = [];
const t0 = Date.now();
while (Date.now() - t0 < minutes * 60000 && errors.length === 0) {
  await page.waitForTimeout(60000);
  const mem = await page.evaluate(async () => {
    try { const r = await performance.measureUserAgentSpecificMemory(); return r.bytes; }
    catch (e) { return performance.memory ? performance.memory.usedJSHeapSize : -1; }
  });
  samples.push({ min: Math.round((Date.now() - t0) / 60000), mb: Math.round(mem / 1048576), fights });
  console.log(JSON.stringify(samples[samples.length - 1]));
}
await page.screenshot({ path: `${out}/end.png` });
await browser.close();
server.close();
const first = samples[1]?.mb ?? samples[0]?.mb, last = samples[samples.length - 1]?.mb;
const result = { minutes, fights, samples, growth_mb: last - first, errors };
fs.writeFileSync(`${out}/result.json`, JSON.stringify(result, null, 1));
console.log(JSON.stringify({ fights, first_mb: first, last_mb: last, growth_mb: last - first, errors }, null, 1));
