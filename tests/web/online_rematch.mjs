// Test en ligne automatisé (SPEC §14.3) : backend PHP local (php -S, base
// jetable), deux pages Chromium (deux contextes), défi → signalisation →
// WebRTC en loopback → combat complet piloté par des bots → rapports → Elo.
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';
import { serve } from './serve.mjs';

const ROOT = path.resolve(import.meta.dirname, '../..');
const out = path.join(ROOT, 'tests/out/online');
fs.mkdirSync(out, { recursive: true });
const API_PORT = 8098, WEB_PORT = 8770;
const db = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'mz-')), 'online.sqlite');
const php = spawn('php', ['-S', `127.0.0.1:${API_PORT}`, path.join(ROOT, 'backend/public/index.php')],
  { env: { ...process.env, MIARRITZE_DB: db }, stdio: 'ignore' });
await new Promise((r) => setTimeout(r, 800));
const server = await serve(path.join(ROOT, 'web/build'), WEB_PORT, API_PORT);
const api = async (method, p, body) => {
  const r = await fetch(`http://127.0.0.1:${API_PORT}/api${p}`, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return r.json();
};
const { code } = await api('POST', '/group');
const a = await api('POST', '/group/join', { code, pseudo: 'Louis' });
const b = await api('POST', '/group/join', { code, pseudo: 'Maia' });
console.log('groupe', code, a.player_id, b.player_id);

const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
const errors = [];
async function open(name, p, role, fighter) {
  const ctx = await browser.newContext({ viewport: { width: 960, height: 540 } });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(`${name}: ${e}`));
  page.on('console', (m) => { const t = m.text(); if (/SCRIPT ERROR|ERROR:/.test(t)) errors.push(`${name}: ${t.slice(0, 200)}`);
    if (/online_report/.test(t)) console.log(name, t.slice(0, 300)); });
  const hash = `#scene=online_qa&pid=${p.player_id}&sec=${p.secret}&code=${code}&pseudo=${name}&role=${role}&bot=1&rematch=1&fighter=${fighter}`;
  await page.goto(`http://localhost:${WEB_PORT}/index.html${hash}`);
  return page;
}
const pa = await open('Louis', a, 'invite', 'louis');
const pb = await open('Maia', b, 'accept', 'maia');
const t0 = Date.now();
let shot = 0, done = false, rating = null;
while (Date.now() - t0 < 560000 && !done) {
  await new Promise((r) => setTimeout(r, shot < 3 ? 2500 : 15000));
  await pa.screenshot({ path: `${out}/a_${String(shot).padStart(2, '0')}.png` });
  await pb.screenshot({ path: `${out}/b_${String(shot).padStart(2, '0')}.png` });
  shot++;
  const lb = await api('GET', `/leaderboard?code=${code}&type=rating`);
  if (lb.reduce((s, r) => s + r.wins + r.losses, 0) >= 4) { done = true; rating = lb; }
}
await pa.screenshot({ path: `${out}/a_end.png` });
await pb.screenshot({ path: `${out}/b_end.png` });
await browser.close();
server.close();
php.kill();
console.log(JSON.stringify({ seconds: Math.round((Date.now() - t0) / 1000), rated: done, leaderboard: rating, errors: errors.slice(0, 10) }, null, 1));
process.exit(done && errors.length === 0 ? 0 : 1);
