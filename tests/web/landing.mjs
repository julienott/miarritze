// Page d'accueil (web/shell.html) : captures chromium desktop, webkit iPhone
// paysage + portrait, puis clic sur JOUER et capture du jeu lancé.
// Vérifie aussi le manifest PWA (icônes et start_url résolus).
// Usage : node landing.mjs   (build déjà exporté dans web/build, landing/ copié)
import { webkit, chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
import { serve } from './serve.mjs';

const root = path.resolve(import.meta.dirname, '../../web/build');
const outDir = path.resolve(import.meta.dirname, '../out/landing');
fs.mkdirSync(outDir, { recursive: true });
const PORT = 8765;
// ?landing : force la landing même sous navigateur piloté (sinon auto-start).
const URL_LANDING = `http://localhost:${PORT}/index.html?landing`;
const IPHONE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

const server = await serve(root, PORT);
const report = {};

async function run(name, browserType, ctxOpts, { play = false, slowPck = false } = {}) {
  const browser = await browserType.launch();
  const context = await browser.newContext(ctxOpts);
  const page = await context.newPage();
  // Ralentit le .pck pour voir la barre de chargement et le clic anticipé.
  if (slowPck) await page.route('**/index.pck', async (r) => { await new Promise((ok) => setTimeout(ok, 3000)); await r.continue(); });
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('requestfailed', (r) => errors.push(`requestfailed ${r.url()}`));
  page.on('response', (r) => { if (r.status() >= 400) errors.push(`${r.status()} ${r.url()}`); });
  const t0 = Date.now();
  await page.goto(URL_LANDING);
  await page.waitForFunction(() => document.fonts.status === 'loaded');
  await page.waitForTimeout(400);
  await page.screenshot({ path: path.join(outDir, `${name}_landing.png`) });
  const info = { isolated: await page.evaluate(() => self.crossOriginIsolated) };
  if (slowPck && play) {
    // clic avant la fin du chargement : le bouton passe en « CHARGEMENT… »
    await page.click('#play');
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(outDir, `${name}_clic_anticipe.png`) });
    await page.waitForFunction(() => !document.getElementById('landing'), null, { timeout: 120000 });
    await page.waitForTimeout(5000);
    await page.screenshot({ path: path.join(outDir, `${name}_game.png`) });
    info.earlyClick = 'ok';
    info.errors = errors.filter((e) => !/gamepad/i.test(e));
    report[name] = info;
    await browser.close();
    return;
  }
  // attend la fin du préchargement (« Prêt ! »)
  await page.waitForFunction(() => document.getElementById('loading-text').textContent.startsWith('Prêt'), null, { timeout: 120000 });
  info.preloadMs = Date.now() - t0;
  await page.screenshot({ path: path.join(outDir, `${name}_ready.png`) });
  if (play) {
    const box = await page.locator('#play').boundingBox();
    if (ctxOpts.hasTouch) await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
    else await page.click('#play');
    await page.waitForFunction(() => !document.getElementById('landing'), null, { timeout: 30000 });
    await page.waitForTimeout(5000);
    await page.screenshot({ path: path.join(outDir, `${name}_game.png`) });
    info.audioState = await page.evaluate(() => (window.__ac ? window.__ac.state : 'n/a'));
  }
  info.errors = errors.filter((e) => !/gamepad/i.test(e));
  report[name] = info;
  await browser.close();
}

await run('desktop_chromium', chromium, { viewport: { width: 1152, height: 648 } }, { play: true });
await run('iphone_paysage_webkit', webkit, {
  viewport: { width: 844, height: 390 }, deviceScaleFactor: 3, hasTouch: true, userAgent: IPHONE_UA,
}, { play: true });
await run('iphone_portrait_webkit', webkit, {
  viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, hasTouch: true, userAgent: IPHONE_UA,
});
await run('desktop_lent_chromium', chromium, { viewport: { width: 1152, height: 648 } }, { play: true, slowPck: true });

// Démarrage auto des navigateurs pilotés (les autres tests web en dépendent).
{
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1152, height: 648 } });
  await page.goto(`http://localhost:${PORT}/index.html`);
  await page.waitForFunction(() => !document.getElementById('landing'), null, { timeout: 120000 });
  report.autostart = 'ok';
  // Manifest PWA vu par Chromium (URLs résolues).
  const cdp = await page.context().newCDPSession(page);
  const m = await cdp.send('Page.getAppManifest');
  const parsed = JSON.parse(m.data);
  const base = new URL(m.url);
  const icons = [];
  for (const ic of parsed.icons) {
    const u = new URL(ic.src, base).href;
    icons.push(`${(await page.request.get(u)).status()} ${u}`);
  }
  report.manifest = { url: m.url, errors: m.errors, start_url: new URL(parsed.start_url, base).href, icons };
  await browser.close();
}

server.close();
console.log(JSON.stringify(report, null, 1));
