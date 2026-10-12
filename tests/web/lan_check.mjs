import { chromium } from 'playwright';
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1152, height: 648 } });
const errs = []; p.on('pageerror', e => errs.push(String(e)));
await p.goto('http://localhost:8080/index.html'); await p.waitForTimeout(6000);
await p.screenshot({ path: '../out/lan.png' }); console.log(JSON.stringify(errs)); await b.close();
