// Capture de la fiche d'une musique avec son attribution (/producer).
import { webkit } from 'playwright';
const BASE = process.env.PRODUCER_URL || 'http://127.0.0.1:8099/producer/';
const out = new URL('../out/producer_credits_', import.meta.url).pathname;
const browser = await webkit.launch();
for (const [name, vp] of [['desktop', { width: 1280, height: 900 }], ['iphone', { width: 390, height: 844 }]]) {
  const page = await browser.newPage({ viewport: vp, deviceScaleFactor: 2 });
  await page.goto(BASE);
  await page.fill('#login input[type=password]', process.env.PRODUCER_TEST_PASSWORD || '');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(1000);
  await page.fill('input[type=search], input[placeholder^=Rechercher]', 'halles');
  await page.waitForTimeout(500);
  await page.locator('.tile', { hasText: /halles/ }).filter({ has: page.locator('.thumb.audio') }).first().click();
  await page.waitForTimeout(800);
  await page.screenshot({ path: out + name + '.png', fullPage: true });
  await page.close();
}
await browser.close();
