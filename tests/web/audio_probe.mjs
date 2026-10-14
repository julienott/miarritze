// Sonde audio : charge une URL (prod par défaut), clique, puis inspecte les
// AudioContext créés par la page et la console. Usage :
//   node audio_probe.mjs [url] [chromium|webkit]
import { chromium, webkit } from 'playwright';

const url = process.argv[2] || 'https://miarritze.ijulien.com/';
const engine = process.argv[3] || 'chromium';
const browser = await (engine === 'webkit' ? webkit : chromium).launch({
  args: engine === 'chromium' ? ['--autoplay-policy=user-gesture-required'] : [],
});
const page = await browser.newPage({ viewport: { width: 1152, height: 648 } });
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e}`));
// Trace indépendante de audio-unlock.js : on espionne création + nœuds.
await page.addInitScript(() => {
  window.__probe = { ctxs: [], sources: 0, decodes: 0, worklets: 0 };
  const AC = window.AudioContext;
  window.AudioContext = new Proxy(AC, {
    construct(t, a, n) {
      const c = Reflect.construct(t, a, n);
      window.__probe.ctxs.push({ c, args: JSON.stringify(a) });
      return c;
    },
  });
  const p = AudioContext.prototype;
  const cbs = p.createBufferSource;
  p.createBufferSource = function () { window.__probe.sources++; return cbs.apply(this, arguments); };
  const dad = BaseAudioContext.prototype.decodeAudioData;
  BaseAudioContext.prototype.decodeAudioData = function () { window.__probe.decodes++; return dad.apply(this, arguments); };
  window.__probe.rms = [];
  const conn = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest) {
    if (dest instanceof AudioDestinationNode && !(this instanceof AudioBufferSourceNode) && !this.__tapped) {
      this.__tapped = true;
      const an = this.context.createAnalyser();
      an.fftSize = 2048;
      conn.call(this, an);
      const buf = new Float32Array(an.fftSize);
      setInterval(() => {
        an.getFloatTimeDomainData(buf);
        let s = 0; for (const v of buf) s += v * v;
        window.__probe.rms.push(Math.sqrt(s / buf.length).toFixed(4));
        if (window.__probe.rms.length > 20) window.__probe.rms.shift();
      }, 250);
      window.__probe.tapped = (window.__probe.tapped || 0) + 1;
      window.__probe.tapType = this.constructor.name;
    }
    return conn.apply(this, arguments);
  };
  if (window.AudioWorklet) {
    const am = AudioWorklet.prototype.addModule;
    AudioWorklet.prototype.addModule = function () { window.__probe.worklets++; return am.apply(this, arguments); };
  }
});
await page.goto(url);
await page.waitForSelector('canvas');
await page.waitForTimeout(8000);
const state = () => page.evaluate(() => ({
  isolated: self.crossOriginIsolated,
  unlockTag: !!document.querySelector('script[src*="audio-unlock"]'),
  ctxs: window.__probe.ctxs.map((x) => ({ state: x.c.state, sr: x.c.sampleRate, args: x.args })),
  sources: window.__probe.sources, tapped: window.__probe.tapped, tapType: window.__probe.tapType, rms: window.__probe.rms.join(' '), decodes: window.__probe.decodes, worklets: window.__probe.worklets,
}));
console.log('AVANT CLIC', JSON.stringify(await state()));
await page.mouse.click(576, 324);
await page.waitForTimeout(3000);
console.log('APRÈS CLIC', JSON.stringify(await state()));
await page.screenshot({ path: new URL('../out/audio_probe.png', import.meta.url).pathname });
console.log(logs.filter((l) => !/^\[(debug|verbose)\]/.test(l)).slice(-40).join('\n'));
await browser.close();
