// Sonde du champ pseudo : où vont les frappes clavier sur desktop ?
import { chromium } from 'playwright';
import { serve } from './serve.mjs';
const server = await serve(new URL('../../web/build', import.meta.url).pathname, 8768);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1152, height: 648 } });
await page.addInitScript(() => { window.__focusLog = []; const f = HTMLElement.prototype.focus; HTMLElement.prototype.focus = function () { window.__focusLog.push(this.tagName + '#' + this.id + ' ' + new Error().stack.split('\n').slice(2, 4).join(' / ')); return f.apply(this, arguments); }; });
await page.goto('http://localhost:8768/index.html');
await page.waitForSelector('canvas');
await page.waitForTimeout(3500);
await page.keyboard.press('Enter');
await page.waitForTimeout(1500);
const info = () => page.evaluate(() => {
  const i = document.querySelector('input[id^=godot-text]');
  if (!i) return { input: null, active: document.activeElement?.tagName };
  const r = i.getBoundingClientRect();
  return { value: i.value, display: i.style.display, rect: [r.left, r.top, r.width, r.height].map(Math.round),
    active: document.activeElement?.outerHTML.slice(0, 160),
    hit: document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)?.tagName };
});
console.log('avant', JSON.stringify(await info()));
const r = await page.evaluate(() => { const b = document.querySelector('input[id^=godot-text]').getBoundingClientRect(); return [b.left + b.width / 2, b.top + b.height / 2]; });
await page.mouse.click(r[0], r[1]);
await page.waitForTimeout(300);
console.log('après clic', JSON.stringify(await info()));
await page.keyboard.type('Recette9', { delay: 60 });
await page.waitForTimeout(300);
console.log('après saisie', JSON.stringify(await info()));
console.log(JSON.stringify(await page.evaluate(() => window.__focusLog.slice(-6)), null, 1));
await page.screenshot({ path: new URL('../out/pseudo_probe.png', import.meta.url).pathname });
await browser.close(); server.close();
