// Captures responsive du service /producer : iPhone portrait/paysage, iPad,
// desktop. Signale tout débordement horizontal. Env comme producer.mjs.
import { webkit } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';

const BASE = process.env.PRODUCER_URL || 'http://127.0.0.1:8099/producer/';
const PASSWORD = process.env.PRODUCER_TEST_PASSWORD || '';
const OUT = path.resolve(import.meta.dirname, '../out/producer_mobile');
fs.mkdirSync(OUT, { recursive: true });
const VIEWS = {
  iphone_portrait: { width: 390, height: 844, isMobile: true },
  iphone_paysage: { width: 844, height: 390, isMobile: true },
  ipad: { width: 820, height: 1180, isMobile: true },
  desktop: { width: 1280, height: 800, isMobile: false },
};
const browser = await webkit.launch();
const report = [];
for (const [name, v] of Object.entries(VIEWS)) {
  const ctx = await browser.newContext({ viewport: { width: v.width, height: v.height }, isMobile: v.isMobile, hasTouch: v.isMobile, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  await page.goto(BASE);
  await page.waitForSelector('#login:not([hidden])');
  await page.screenshot({ path: `${OUT}/${name}_0_login.png` });
  await page.fill('#login input[type=password]', PASSWORD);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(1200);
  const overflow = async (step) => {
    const o = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth,
      wide: [...document.querySelectorAll('body *')].filter((e) => e.getBoundingClientRect().right > document.documentElement.clientWidth + 1 && getComputedStyle(e).position !== 'fixed').slice(0, 5).map((e) => e.tagName + '.' + e.className) }));
    if (o.sw > o.cw + 1) report.push(`${name}/${step}: débordement ${o.sw}>${o.cw} ${o.wide.join(' ')}`);
  };
  await page.screenshot({ path: `${OUT}/${name}_1_assets.png` }); await overflow('assets');
  const first = page.locator('[data-asset], .asset, .tile').first();
  if (await first.count()) { await first.click(); await page.waitForTimeout(900); await page.screenshot({ path: `${OUT}/${name}_2_detail.png` }); await overflow('détail'); }
  await page.goto(BASE + '#kanban'); await page.waitForTimeout(900);
  const tab = page.getByText(/kanban/i).first();
  if (await tab.count()) { await tab.click().catch(() => {}); await page.waitForTimeout(700); }
  await page.screenshot({ path: `${OUT}/${name}_3_kanban.png`, fullPage: true }); await overflow('kanban');
  await ctx.close();
}
await browser.close();
console.log(report.length ? report.join('\n') : 'aucun débordement horizontal');
