// Outils Playwright « iPhone » : vrais événements tactiles (CDP, Chromium en
// émulation mobile) et toucher de boutons par libellé grâce à `?qa=1`
// (QaCapture publie window.__qa : scène courante + boutons visibles).
import { chromium, webkit } from 'playwright';

export const DEVICES = {
  // Tailles CSS en paysage.
  iphone13: { width: 844, height: 390, dpr: 3 },
  iphone_se: { width: 667, height: 375, dpr: 2 },
  iphone_pro_max: { width: 932, height: 430, dpr: 3 },
  ipad: { width: 1024, height: 768, dpr: 2 },
};

const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

export async function open(url, { device = 'iphone13', engine = 'chromium', portrait = false } = {}) {
  const d = DEVICES[device];
  const size = portrait ? { width: d.height, height: d.width } : { width: d.width, height: d.height };
  const browser = await (engine === 'webkit' ? webkit : chromium).launch();
  const ctx = await browser.newContext({ viewport: size, deviceScaleFactor: d.dpr, hasTouch: true,
    isMobile: engine === 'webkit' ? undefined : true, userAgent: UA });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    const t = m.text();
    if (m.type() === 'error' || /SCRIPT ERROR|ERROR:/.test(t)) errors.push(t);
  });
  const cdp = engine === 'chromium' ? await ctx.newCDPSession(page) : null;
  await page.goto(url);
  await page.waitForSelector('canvas');
  return new Phone(browser, page, cdp, errors);
}

export class Phone {
  constructor(browser, page, cdp, errors) {
    Object.assign(this, { browser, page, cdp, errors });
  }
  async qa() { return await this.page.evaluate(() => window.__qa || null); }
  async canvas() { return await this.page.evaluate(() => { const r = document.querySelector('canvas').getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; }); }
  async toCss(fx, fy) { const c = await this.canvas(); return [c.x + fx * c.w, c.y + fy * c.h]; }
  async wait(ms) { await this.page.waitForTimeout(ms); }
  /** Attend que la scène courante contienne `part` (chemin .tscn). */
  async waitScene(part, ms = 8000) {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) {
      const q = await this.qa();
      if (q && q.scene.includes(part)) return true;
      await this.wait(200);
    }
    return false;
  }
  async buttons() { const q = await this.qa(); return q ? q.buttons : []; }
  /** Touche le premier bouton visible dont le texte correspond (string ou RegExp). */
  async tapText(match, after = 900) {
    const re = match instanceof RegExp ? match : new RegExp(match.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
    for (let i = 0; i < 20; i++) {
      const b = (await this.buttons()).find((x) => re.test(x.t) && !x.off);
      if (b) { await this.tapFrac(b.x, b.y, after); return b; }
      await this.wait(200);
    }
    throw new Error(`bouton introuvable : ${match} (visibles : ${(await this.buttons()).map((x) => x.t).join(' | ')})`);
  }
  async tapFrac(fx, fy, after = 900) {
    const [x, y] = await this.toCss(fx, fy);
    await this.touch([[x, y]], 70);
    await this.wait(after);
  }
  /** Appui tactile (plusieurs doigts possibles) maintenu `ms`. */
  async touch(points, ms = 70) {
    if (this.cdp) {
      const tp = points.map(([x, y], i) => ({ x, y, id: i + 1 }));
      await this.cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: tp });
      await this.wait(ms);
      await this.cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    } else {
      await this.page.touchscreen.tap(points[0][0], points[0][1]);
    }
  }
  /** Glisser d'un doigt (fractions d'écran), maintenu `hold` ms à l'arrivée. */
  async drag(fx0, fy0, fx1, fy1, hold = 300, steps = 6) {
    const [x0, y0] = await this.toCss(fx0, fy0);
    const [x1, y1] = await this.toCss(fx1, fy1);
    await this.cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x0, y: y0, id: 1 }] });
    for (let i = 1; i <= steps; i++) {
      await this.wait(16);
      await this.cdp.send('Input.dispatchTouchEvent', { type: 'touchMove',
        touchPoints: [{ x: x0 + (x1 - x0) * i / steps, y: y0 + (y1 - y0) * i / steps, id: 1 }] });
    }
    await this.wait(hold);
    await this.cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  }
  async shot(path) { await this.page.screenshot({ path }); }
  async close() { await this.browser.close(); }
}
