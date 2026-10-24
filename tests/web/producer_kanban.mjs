// Kanban de /producer : colonnes Backlog → Todo → Doing → QA → Validé → En prod, cartes chapeau,
// historique, commentaires Julien/Claude, CLI (events), tâches pixelforge (jobs), ordinateur +
// iPhone portrait/paysage ; accès Tailscale si PRODUCER_TAILSCALE_URL est donné.
// Prérequis : service lancé (docs/PRODUCER.md, « Tester en local »).
// Env : PRODUCER_URL, PRODUCER_TEST_PASSWORD, PRODUCER_TOKEN ;
//       PRODUCER_EXPECT_MIGRATION=1 si la base de départ est une base v1 de test
//       (cartes « Ancienne carte … », voir docs/PRODUCER.md) ;
//       PRODUCER_SHOTS : dossier des captures (défaut tests/out/producer_kanban) ;
//       PRODUCER_TAILSCALE_URL : même service avec 'tailscale_auth' => true dans sa config (et une
//       base à part), pour tester la connexion par l'en-tête Tailscale-User-Login.
import { chromium, webkit } from 'playwright';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

const BASE = process.env.PRODUCER_URL || 'http://127.0.0.1:8099/producer/';
const PASSWORD = process.env.PRODUCER_TEST_PASSWORD || '';
const TOKEN = process.env.PRODUCER_TOKEN || '';
if (!PASSWORD || !TOKEN) {
  console.error('PRODUCER_TEST_PASSWORD et PRODUCER_TOKEN requis');
  process.exit(2);
}
const ROOT = path.resolve(import.meta.dirname, '../..');
const OUT = process.env.PRODUCER_SHOTS || path.join(ROOT, 'tests/out/producer_kanban');
fs.mkdirSync(OUT, { recursive: true });

const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
}
const cli = (...args) => execFileSync('python3', [path.join(ROOT, 'tools/producer/cli.py'), ...args],
  { env: { ...process.env, PRODUCER_URL: BASE, PRODUCER_TOKEN: TOKEN }, encoding: 'utf8' });
const apiTok = async (route, body) => {
  const r = await fetch(BASE + 'index.php?r=' + route, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: 'Bearer ' + TOKEN, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return [r.status, await r.json()];
};
const tag = 'K' + Date.now().toString(36);   // titres uniques : le test peut tourner sur une base non vide
const t0 = Math.floor(Date.now() / 1000) - 1;

async function login(page) {
  await page.goto(BASE + '#/kanban');
  await page.waitForSelector('#login:not([hidden])');
  await page.fill('#password', PASSWORD);
  await page.click('#login-form button[type=submit]');
  await page.waitForSelector('#view-kanban:not([hidden]) #board');
}

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await context.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error' && !/40[0134]/.test(m.text())) errors.push(m.text()); });
page.on('dialog', (d) => d.accept());
const shot = (p, name, full = true) => p.screenshot({ path: path.join(OUT, name + '.png'), fullPage: full });

await login(page);
const cols = await page.$$eval('.column h3 span:first-child', (n) => n.map((x) => x.textContent));
check('6 colonnes', cols.join(',') === 'Backlog,Todo,Doing,QA,Validé,En prod', cols.join(','));
check('ordinateur : 6 colonnes sur une ligne, sans défilement horizontal', await page.evaluate(() => {
  const tops = [...document.querySelectorAll('#board .column')].map((c) => Math.round(c.getBoundingClientRect().top));
  return tops.length === 6 && new Set(tops).size === 1 && document.documentElement.scrollWidth <= innerWidth + 1;
}));
check('lien « ▶ Jeu QA » vers /jeu/', (await page.getAttribute('#jeu-qa', 'href')) === '/jeu/' && await page.isVisible('#jeu-qa'));

if (process.env.PRODUCER_EXPECT_MIGRATION === '1') {
  const [, r] = await apiTok('cards');
  const by = Object.fromEntries(r.cards.map((c) => [c.title, c]));
  check('migration : review -> qa', by['Ancienne carte à vérifier']?.status === 'qa');
  check('migration : todo, doing, done gardés', by['Ancienne carte à faire']?.status === 'todo'
    && by['Ancien bug en cours']?.status === 'doing' && by['Ancienne carte faite']?.status === 'done');
  check('migration : notes conservées, agent -> claude',
    by['Ancienne carte à vérifier']?.notes.map((n) => n.author).join(',') === 'claude,julien');
  await shot(page, '00_migration');
}

// ------------------------------------------------- création rapide (Julien)
const hatTitle = `Perso ${tag}`;
await page.fill('.quick-add input', hatTitle);
await page.click('.quick-add button[type=submit]');
const hatCard = page.locator(`.column[data-status=backlog] .card:has-text("${hatTitle}")`);
await hatCard.waitFor();
check('création rapide dans Backlog', true);
check('origine affichée : Julien', (await hatCard.locator('.origin').textContent()) === 'Julien');
const hatId = Number(await hatCard.getAttribute('data-id'));
// Type « perso » via le détail.
await hatCard.locator('.title').click();
await page.waitForSelector('#card-dialog[open]');
await page.selectOption('#cf-type', 'perso');
await page.click('#cf-save');
await page.waitForSelector(`.card[data-id="${hatId}"] .badge.t-perso`);
check('type perso enregistré (badge)', true);

// ------------------------------------------------------ enfants (Claude, CLI)
const kidIds = ['référence', 'run', 'idle'].map((k, i) => Number(/#(\d+)/.exec(cli('add-card', '--type', i ? 'animation' : 'asset',
  '--title', `${tag} ${k}`, '--parent', String(hatId), ...(i === 2 ? ['--status', 'done'] : [])))[1]));
cli('move', String(kidIds[0]), 'review');       // ancien alias -> QA
cli('comment', String(kidIds[1]), 'Cycle de course trop rapide ?');
const shown = cli('show', String(hatId));
check('cli show : enfants et avancement', shown.includes('enfants 2/3') && shown.includes(`${tag} run`), shown.split('\n')[0]);
const [st, cyc] = await apiTok('card_update', { id: hatId, parent: kidIds[0] });
check('boucle de chapeaux refusée (400)', st === 400, cyc.error);

await page.reload();
await page.waitForSelector(`.card[data-id="${hatId}"] .progress`);
const pct = await page.$eval(`.card[data-id="${hatId}"] .progress .bar`, (b) => b.style.width);
check('barre de progression du chapeau (2/3)', pct === '67%', pct);
await page.click(`.card[data-id="${hatId}"] .unfold`);
const kids = await page.$$eval(`.card[data-id="${hatId}"] .kids .kid`, (n) => n.length);
check('chapeau déplié : 3 enfants', kids === 3, String(kids));
const kidCard = page.locator(`.card[data-id="${kidIds[1]}"]`);
check('enfant : nom du parent affiché', (await kidCard.locator('.parent-link').textContent()).includes(hatTitle));
await shot(page, '01_board_chapeau_deplie');

// Lien vers le parent.
await kidCard.locator('.parent-link').click();
await page.waitForSelector('#card-dialog[open]');
check('lien parent : ouvre le chapeau', (await page.textContent('#card-dialog-title')).includes('#' + hatId));
await page.waitForSelector('#cf-children .kid');
await page.click('#cf-cancel');

// Filtre par chapeau et vue « chapeaux seulement ».
await page.selectOption('#kb-hat', String(hatId));
const fam = await page.$$eval('#board .column > .card', (n) => n.map((x) => Number(x.dataset.id)).sort());
check('filtre par chapeau : la famille seulement', fam.length === 4 && fam.includes(hatId), fam.join(','));
await shot(page, '02_filtre_chapeau');
await page.selectOption('#kb-hat', '');
await page.check('#kb-hats-only');
const onlyHats = await page.$$eval('#board .column > .card', (n) => n.map((x) => Number(x.dataset.id)));
check('chapeaux seulement : enfants masqués', onlyHats.includes(hatId) && !kidIds.some((k) => onlyHats.includes(k)));
await shot(page, '03_chapeaux_seulement');
// « Masquer les chapeaux » : l'inverse, exclusif avec « chapeaux seulement », retenu.
await page.check('#kb-no-hats');
check('masquer les chapeaux décoche « chapeaux seulement »', !(await page.isChecked('#kb-hats-only')));
const noHats = await page.$$eval('#board .column > .card', (l) => l.map((x) => Number(x.dataset.id)));
const allC = (await apiTok('cards'))[1].cards;
const leaves = allC.filter((c) => !c.children);
check('masquer les chapeaux : seulement les cartes sans enfant', !noHats.includes(hatId) && kidIds.every((k) => noHats.includes(k))
  && noHats.length === leaves.length, `${noHats.length}/${leaves.length}`);
const colCount = await page.$eval('.column[data-status=backlog] h3 .muted', (n) => Number(n.textContent));
check('masquer les chapeaux : compteurs filtrés', colCount === leaves.filter((c) => c.status === 'backlog').length, String(colCount));
await shot(page, '03b_chapeaux_masques');
await page.reload();
await page.waitForSelector('#board .column');
check('masquer les chapeaux : choix retenu', await page.isChecked('#kb-no-hats') && !(await page.$(`.card[data-id="${hatId}"]`)));
await page.check('#kb-hats-only');
check('chapeaux seulement décoche « masquer les chapeaux »', !(await page.isChecked('#kb-no-hats')));
await page.uncheck('#kb-hats-only');

// ------------------------------------ Julien priorise, commente, déplace
await page.locator(`.card[data-id="${hatId}"] button[aria-label="Colonne suivante"]`).click();
await page.waitForSelector(`.column[data-status=todo] .card[data-id="${hatId}"]`);
check('◀ ▶ : chapeau passé en Todo', true);
await page.click(`.card[data-id="${kidIds[1]}"] .title`);
await page.waitForSelector('#cf-feed .note.claude');
await page.selectOption('#cf-priority', 'haute');
await page.click('#cf-save');
await page.waitForSelector(`.card[data-id="${kidIds[1]}"] .badge.haute`);
await page.click(`.card[data-id="${kidIds[1]}"] .title`);
await page.waitForSelector('#cf-feed .note.claude');
await page.fill('#cf-note', 'Oui, ralentis à 8 i/s.\n<b>pas du HTML</b>');
await page.click('#cf-comment-send');
await page.waitForSelector('#cf-feed .note.julien');
const feed = await page.textContent('#cf-feed');
check('fil : création, priorité, commentaires Claude et Julien',
  feed.includes('a créé la carte') && feed.includes('priorité') && feed.includes('Cycle de course') && feed.includes('<b>pas du HTML</b>'));
check('commentaire échappé (pas de <b>)', (await page.$$('#cf-feed b')).length === 0);
await shot(page, '04_detail_fil', false);
await page.click('#cf-cancel');

// Création rapide avec chapeau.
await page.fill('.quick-add input', `${tag} hunter_reveal`);
await page.selectOption('.quick-add select', String(hatId));
await page.click('.quick-add button[type=submit]');
await page.waitForSelector(`.card:has-text("${tag} hunter_reveal") .parent-link`);
check('création rapide avec chapeau', true);
const hunterId = Number(await page.locator(`.card:not(.is-hat):has-text("${tag} hunter_reveal")`).getAttribute('data-id'));

// ------------------------------------------------ boucle de Claude : events
const ev = cli('events', '--since', String(t0));
check('cli events : déplacement en Todo par Julien', new RegExp(`julien +#${hatId} .*déplacement Backlog -> Todo`).test(ev));
check('cli events : commentaire de Julien', ev.includes('Oui, ralentis à 8 i/s.'));
check('cli events : priorité par Julien', /julien .*priorité — -> haute/.test(ev));
const evJson = JSON.parse(cli('events', '--since', String(t0), '--json'));
check('events --json : now + événements', evJson.now >= t0 && evJson.events.length >= 10, String(evJson.events.length));
check('cli cards --parent', cli('cards', '--parent', String(hatId)).trim().split('\n').length === 4);
cli('set', String(kidIds[2]), '--parent', '0');
check('cli set --parent 0 détache', !cli('cards', '--parent', String(hatId)).includes(`${tag} idle`));

// ------------------------------------------- asset lié : vue, détail, commentaire
// Perso complet (Louis est en cours de refonte) ; « run » remplace l'ancienne « walk ».
const ASSET = 'blackout/persos/patxi/animations';
cli('set', String(kidIds[1]), '--asset', ASSET, '--detail', 'run');
cli('move', String(kidIds[1]), 'qa');
const DECOR = 'blackout/decor/objets/tour_phare.png';   // objet avec ses masques pixelforge (calque)
// Le décor n'est plus dans le build depuis le reboot Party Hard (21/10) : vérifications sautées sans lui.
const hasDecor = (await apiTok('index'))[1].assets.some((a) => a.id === DECOR);
const decorId = hasDecor ? Number(/#(\d+)/.exec(cli('add-card', '--type', 'asset', '--title', `${tag} fronton masques`, '--asset', DECOR, '--status', 'qa'))[1]) : 0;
if (!hasDecor) console.log(`     (${DECOR} absent du build : tuile décor non testée)`);
// Trace de chaque image dessinée (case source) : lecture case par case vérifiée sur la tuile.
await page.addInitScript(() => {
  window.__draws = [];
  const orig = CanvasRenderingContext2D.prototype.drawImage;
  CanvasRenderingContext2D.prototype.drawImage = function (img, ...a) {
    if (a.length === 8 && img.naturalWidth) window.__draws.push({ sx: a[0], sw: a[2], iw: img.naturalWidth });
    return orig.call(this, img, ...a);
  };
});
await page.reload();
const thumb = page.locator(`.card[data-id="${kidIds[1]}"] img.card-thumb`);
await thumb.waitFor();
check('tuile : miniature de l\'asset (image fixe de run, paresseuse)',
  (await thumb.getAttribute('loading')) === 'lazy' && decodeURIComponent(await thumb.getAttribute('src')).includes('_poster/run'));
// Survol de la tuile : la miniature joue l'animation, puis s'arrête et se libère.
await page.hover(`.card[data-id="${kidIds[1]}"] .title`);
await page.waitForSelector(`.card[data-id="${kidIds[1]}"] canvas.card-thumb`);
const moving = await page.evaluate(async (id) => {
  const c = document.querySelector(`.card[data-id="${id}"] canvas.card-thumb`);
  const snap = () => c.toDataURL().length + ':' + c.toDataURL().slice(-80);
  const a = snap();
  await new Promise((r) => setTimeout(r, 400));
  return a !== snap();
}, kidIds[1]);
check('tuile : l\'animation joue au survol', moving && (await page.$$('#board canvas')).length === 1);
const tdraws = await page.evaluate(() => window.__draws);
const walkFrames = await page.evaluate(() => state.assetsById.get('blackout/persos/patxi/animations').anims.find((x) => x.name === 'run').frames);
check('tuile : case par case (décalage multiple exact de la case)', tdraws.length >= 3
  && tdraws.every((d) => d.sw * walkFrames === d.iw && d.sx % d.sw === 0), `${tdraws.length} images`);
await shot(page, '04a_tuile_survol', false);
await page.mouse.move(2, 2);
await page.waitForTimeout(150);
check('tuile : souris sortie = animation arrêtée et libérée',
  (await page.$$('#board canvas')).length === 0 && !!(await page.$(`.card[data-id="${kidIds[1]}"] img.card-thumb`)));
// Décor avec masques : les masques apparaissent au survol, chargés à ce moment-là.
const dthumb = `.card[data-id="${decorId}"] .dthumb`;
if (hasDecor) {
check('tuile décor : masques non chargés au repos', !(await page.getAttribute(`${dthumb} img.calque`, 'src')));
await page.hover(`.card[data-id="${decorId}"] .title`);
await page.waitForFunction((s) => { const i = document.querySelector(s + ' img.calque'); return i && i.complete && i.naturalWidth > 0; }, dthumb);
check('tuile décor : masques au survol, superposés à l\'image', await page.$eval(dthumb, (b) => {
  const [base, cal] = b.querySelectorAll('img');
  const r1 = base.getBoundingClientRect(), r2 = cal.getBoundingClientRect();
  return b.classList.contains('masks') && getComputedStyle(cal).visibility === 'visible'
    && Math.abs(r1.top - r2.top) < 1 && Math.abs(r1.width - r2.width) < 1;
}));
}
// Ordinateur : l'asset en haut de la tuile, sur toute sa largeur.
const full = await page.$eval(`.card[data-id="${kidIds[1]}"]`, (c) => {
  const t = c.firstElementChild.getBoundingClientRect(), r = c.getBoundingClientRect();
  return { top: t.top - r.top, w: t.width / r.width, h: t.height };
});
check('tuile : asset en haut, pleine largeur, hauteur bornée', full.top < 12 && full.w > 0.85 && full.h <= 160, JSON.stringify(full));
await shot(page, '04a_tuile_decor_masques', false);
await page.mouse.move(2, 2);
if (hasDecor) check('tuile décor : masques cachés au départ de la souris', !(await page.$eval(dthumb, (b) => b.classList.contains('masks'))));
await page.click(`.card[data-id="${kidIds[1]}"] .title`);
await page.waitForSelector('#cf-asset-view:not([hidden]) .anim-cell img.mini');
check('détail : champ « détail » = run', (await page.inputValue('#cf-detail')) === 'run');
await page.hover('#cf-asset-view .anim-cell');
await page.waitForSelector('#cf-asset-view .anim-cell canvas.mini');
check('détail : l\'animation de l\'asset joue au survol', true);
await page.fill('#cf-asset-view .comment-form textarea', `${tag} : les pieds glissent`);
await page.click('#cf-asset-view .comment-form button[type=submit]');
await page.waitForSelector(`#cf-asset-view .comment:has-text("${tag} : les pieds glissent")`);
const [, cm] = await apiTok('comments');
const mine = cm.comments.find((c) => c.body === `${tag} : les pieds glissent`);
check('commentaire d\'asset depuis la carte (version + anim)', mine && mine.asset === ASSET && mine.version && mine.context === 'anim : run', JSON.stringify(mine && [mine.version, mine.context]));
await shot(page, '04b_detail_asset', false);
await page.click('#cf-asset-view .anim-cell');
await page.waitForSelector('.fs canvas');
{
  const fst = await page.textContent('.fs-title');
  check('détail : clic sur l\'animation = plein écran', fst.startsWith('Patxi · ') && fst.includes('run'), fst);
}
await page.click('.fs-close');
// Une amélioration de Julien sur une carte en QA la sort de QA (sommet du Backlog, « à retraiter », 21/10).
{
  const [, sc] = await apiTok('card&id=' + kidIds[1]);
  check('amélioration sur une carte en QA : sommet du Backlog', sc.card.status === 'backlog' && sc.card.rework, sc.card.status);
  cli('move', String(kidIds[1]), 'qa');
  await page.reload();
  await page.waitForSelector(`.card[data-id="${kidIds[1]}"] button.refuse`);
}

// ----------------------------------------------------- QA : refuser, retraiter, accepter
const qaCard = page.locator(`.card[data-id="${kidIds[1]}"]`);
check('QA : boutons Accepter et Refuser sur la tuile', await qaCard.locator('button.accept').isVisible() && await qaCard.locator('button.refuse').isVisible());
await shot(page, '04c_board_qa');
await qaCard.locator('button.refuse').click();
await page.waitForSelector('#refuse-dialog[open]');
await page.click('#rf-send');
check('refus sans commentaire bloqué', (await page.textContent('#rf-error')).length > 0);
await page.fill('#rf-body', 'La marche glisse encore, pieds à recaler.');
await shot(page, '04d_refus', false);
await page.click('#rf-send');
await page.waitForSelector(`.column[data-status=backlog] .card[data-id="${kidIds[1]}"] .rework`);
check('refus : sommet du Backlog, badge « à retraiter »', true);
const refused = cli('show', String(kidIds[1]));
check('cli show : refus visible', refused.includes('[À RETRAITER]') && refused.includes('REFUSÉE') && refused.includes('pieds à recaler'));
cli('qa', String(kidIds[1]), 'pieds recalés sur feet_anchor');
const back = JSON.parse(cli('show', String(kidIds[1]), '--json'));
check('cli qa : retour en QA, badge effacé, commentaire « retraité : »', back.card.status === 'qa' && !back.card.rework
  && back.card.notes.some((n) => n.body.startsWith('retraité : pieds recalés sur feet_anchor')
    && n.body.includes(`asset ${ASSET} · run version `)));
// « Refuser et refaire » : commentaire obligatoire aussi, puis sommet du Todo, « à retraiter ».
cli('move', String(kidIds[1]), 'qa');
await page.reload();
await page.locator(`.card[data-id="${kidIds[1]}"] button.refuse`).click();
await page.waitForSelector('#refuse-dialog[open]');
check('refus : deux boutons (Refuser, Refuser et refaire)', await page.isVisible('#rf-send') && await page.isVisible('#rf-redo'));
await page.click('#rf-redo');
check('refaire sans commentaire bloqué', (await page.textContent('#rf-error')).length > 0);
await page.fill('#rf-body', 'Les bras bougent trop peu, plus d\'ampleur.');
await page.click('#rf-redo');
await page.waitForSelector(`.column[data-status=todo] .card[data-id="${kidIds[1]}"] .rework`);
check('refaire : sommet du Todo, badge « à retraiter »', /Todo, à refaire/.test(await page.textContent('#toast')), await page.textContent('#toast'));
check('cli show : refus « à refaire »', cli('show', String(kidIds[1])).includes('QA -> Todo, à refaire'));
cli('qa', String(kidIds[1]), 'bras repris');
// Chapeau en QA : Accepter accepte aussi les enfants encore en QA (après confirmation).
cli('move', String(hatId), 'qa');
await page.reload();
const msgs = [];
page.removeAllListeners('dialog');
page.on('dialog', (d) => { msgs.push(d.message()); d.accept(); });
await page.locator(`.card[data-id="${hatId}"] button.accept`).click();
await page.waitForSelector(`.column[data-status=valide] .card[data-id="${hatId}"]`);
check('accepter : toast « → Validé »', /→ Validé/.test(await page.textContent('#toast')), await page.textContent('#toast'));
const st2 = Object.fromEntries((await apiTok('cards'))[1].cards.map((c) => [c.id, c.status]));
check('chapeau accepté avec confirmation (2 enfants en QA)', msgs.some((m) => m.includes('2 enfants')), msgs.join(' | '));
check('chapeau + enfants en QA -> Validé, les autres restent', st2[hatId] === 'valide' && st2[kidIds[0]] === 'valide'
  && st2[kidIds[1]] === 'valide' && st2[hunterId] === 'backlog', JSON.stringify([st2[hatId], st2[kidIds[0]], st2[kidIds[1]], st2[hunterId]]));
{
  const [, sh] = await apiTok('card&id=' + hatId);
  check('chapeau : Validé compte comme avancé (children_done)', sh.card.children_done === 2 && sh.card.children === 3,
    `${sh.card.children_done}/${sh.card.children}`);
  check('événement accepte : qa -> valide', sh.events.some((e) => e.type === 'accepte' && e.old === 'qa' && e.new === 'valide'));
}
const [stBad] = await apiTok('card_accept', { id: hunterId });
check('accepter hors QA refusé (400)', stBad === 400, String(stBad));
const evq = JSON.parse(cli('events', '--since', String(t0), '--json')).events;
check('events : types accepte et refuse (avec le texte)', evq.filter((e) => e.type === 'accepte').length === 3
  && evq.some((e) => e.type === 'refuse' && e.author === 'julien' && e.new.includes('pieds à recaler')));
check('cli events : ACCEPTÉE / REFUSÉE lisibles', /ACCEPTÉE QA -> Validé/.test(cli('events', '--since', String(t0))) && /REFUSÉE QA -> Backlog/.test(cli('events', '--since', String(t0))));
// Passage en prod (watcher du déploiement, jeton) : Validé -> En prod par card_move et cards_bulk.
{
  const [sm] = await apiTok('card_move', { id: kidIds[0], status: 'done' });
  const [sb, rb] = await apiTok('cards_bulk', { ids: [hatId, kidIds[1]], status: 'done' });
  const all = Object.fromEntries((await apiTok('cards'))[1].cards.map((c) => [c.id, c]));
  check('card_move / cards_bulk : Validé -> En prod (jeton)', sm === 200 && sb === 200 && rb.changed === 2
    && [hatId, kidIds[0], kidIds[1]].every((id) => all[id].status === 'done'), JSON.stringify([sm, sb, rb]));
  const evp = JSON.parse(cli('events', '--since', String(t0), '--json')).events;
  check('événement deplacement valide -> done par claude', evp.filter((e) => e.type === 'deplacement' && e.old === 'valide'
    && e.new === 'done' && e.author === 'claude').length === 3);
  check('cli : move … done affiché « En prod »', cli('show', String(kidIds[0])).includes('[En prod]'));
  await page.reload();
  await page.waitForSelector(`.column[data-status=done] .card[data-id="${hatId}"]`);
  check('colonne En prod : le chapeau y est', true);
}

// ------------------------------------------------------- tâches pixelforge (jobs)
{
  const jobs = [
    { id: 'c4897ae6d1f04b6e9a2b', role: 'A', label: 'animation run', status: 'running', keep: false },
    { id: '0aa1bb2cc3dd4ee5ff60', role: 'B', label: 'animation run (variante)', status: 'succeeded', keep: true },
  ];
  cli('set', String(hunterId), '--jobs', JSON.stringify(jobs));
  const [, sj] = await apiTok('card&id=' + hunterId);
  check('jobs : liste exposée par card', Array.isArray(sj.card.jobs) && sj.card.jobs.length === 2 && sj.card.jobs[1].keep === true);
  const cj = JSON.parse(cli('cards', '--json')).find((c) => c.id === hunterId);
  check('cli cards --json : jobs', cj && cj.jobs.length === 2 && cj.jobs[0].id === jobs[0].id);
  const [b1] = await apiTok('card_update', { id: hunterId, jobs: '{"pas": "une liste"}' });
  const [b2] = await apiTok('card_update', { id: hunterId, jobs: '[pas du json' });
  const [b3] = await apiTok('card_update', { id: hunterId, jobs: '[' + '"x",'.repeat(2100) + '"x"]' });
  check('jobs : objet, JSON invalide ou trop long refusés (400)', b1 === 400 && b2 === 400 && b3 === 400, [b1, b2, b3].join(','));
  // Même liste renvoyée : aucun nouvel événement.
  const [, same] = await apiTok('card_update', { id: hunterId, jobs: JSON.stringify(jobs) });
  const jev = (await apiTok('card&id=' + hunterId))[1].events.filter((e) => e.type === 'jobs');
  check('jobs : événement seulement si ça change', same.changed === 0 && jev.length === 1 && jev[0].new.startsWith('2 tâches'), JSON.stringify(jev.map((e) => e.new)));
  check('jobs : pas de commentaire ajouté', (await apiTok('card&id=' + hunterId))[1].card.notes.length === 0);
  await page.reload();
  await page.waitForSelector(`.card[data-id="${hunterId}"] .badge.job-run`);
  check('tuile : badge « tâche en cours »', (await page.textContent(`.card[data-id="${hunterId}"] .badge.job-run`)).includes('1'));
  await page.click(`.card[data-id="${hunterId}"] .title`);
  await page.waitForSelector('#cf-jobs-box:not([hidden]) #cf-jobs .job');
  const rows = await page.$$eval('#cf-jobs .job', (l) => l.map((x) => x.textContent));
  check('détail : section « Tâches pixelforge » (id court, rôle, libellé, statut, 📌)', rows.length === 2
    && rows[0].includes('c4897ae6') && !rows[0].includes('c4897ae6d') && rows[0].includes('animation run') && rows[0].includes('running')
    && rows[1].includes('📌') && !rows[0].includes('📌'), rows.join(' | '));
  await page.waitForSelector('#cf-feed .event');
  const jobLines = await page.$$eval('#cf-feed .event.jobs', (l) => l.length);
  check('fil : tâches pixelforge en une ligne compacte, hors commentaires', jobLines === 1 && !(await page.$('#cf-feed .note.claude')));
  await shot(page, '04h_jobs_detail', false);
  await page.click('#cf-cancel');
  cli('set', String(hunterId), '--jobs', JSON.stringify([{ ...jobs[0], status: 'failed' }]));
  await page.reload();
  await page.waitForSelector(`.card[data-id="${hunterId}"] .badge.job-failed`);
  check('tuile : badge « en échec »', true);
  cli('set', String(hunterId), '--jobs', '[]');
  const [, sz] = await apiTok('card&id=' + hunterId);
  check('jobs : "[]" vide la liste', sz.card.jobs.length === 0 && sz.events.filter((e) => e.type === 'jobs').length === 3);
}

// ------------------------------------------------------------- night shift
{
  const [, all] = await apiTok('cards');
  check('night : champ présent, faux pour les cartes existantes', all.cards.every((c) => typeof c.night === 'boolean')
    && all.cards.filter((c) => [hatId, hunterId, ...kidIds].includes(c.id)).every((c) => !c.night));
  await page.reload();
  await page.fill('.quick-add input', `${tag} nuit rapide`);
  await page.check('.quick-add .qa-night input');
  await page.click('.quick-add button[type=submit]');
  const nightCard = page.locator(`.card:not(.is-hat):has-text("${tag} nuit rapide")`);
  await nightCard.locator('.badge.night').waitFor();
  const nightId = Number(await nightCard.getAttribute('data-id'));
  check('night : création rapide avec 🌙, badge sur la tuile', (await apiTok('cards'))[1].cards.find((c) => c.id === nightId).night === true);
  // Chapeau : night shift coché puis appliqué aux enfants.
  await page.click(`.card[data-id="${hatId}"] .title`);
  await page.waitForSelector('#cf-night-children:not([hidden])');
  await page.check('#cf-night');
  await page.waitForSelector('#cf-saved.ok');   // le chapeau lui-même est enregistré aussitôt
  await page.click('#cf-night-children');
  await page.waitForFunction(() => /Night shift activé sur \d+ enfant/.test(document.getElementById('toast').textContent));
  const fam2 = (await apiTok('cards'))[1].cards.filter((c) => c.id === hatId || c.parent_id === hatId);
  check('night : appliqué au chapeau et à tous ses enfants', fam2.length >= 3 && fam2.every((c) => c.night), fam2.map((c) => c.id + ':' + c.night).join(','));
  await shot(page, '04e_night_detail', false);
  await page.click('#cf-cancel');
  // Enregistrement immédiat : cocher 🌙, fermer SANS « Enregistrer », rouvrir.
  const leaf = kidIds[2];
  await page.reload();
  await page.click(`.card[data-id="${leaf}"] .title`);
  await page.waitForSelector('#card-dialog[open]');
  await page.check('#cf-night');
  await page.waitForSelector('#cf-saved.ok');
  await page.selectOption('#cf-priority', 'basse');
  await page.waitForFunction(() => document.querySelector('#cf-saved').textContent.includes('enregistré') && !document.querySelector('#cf-priority').disabled);
  await page.click('#cf-cancel');
  check('night : badge 🌙 de la tuile à jour sans recharger', !!(await page.$(`.card[data-id="${leaf}"] .badge.night`)));
  const lc = (await apiTok('cards'))[1].cards.find((c) => c.id === leaf);
  check('night et priorité enregistrés sans « Enregistrer »', lc.night === true && lc.priority === 'basse', JSON.stringify([lc.night, lc.priority]));
  await page.click(`.card[data-id="${leaf}"] .title`);
  await page.waitForSelector('#card-dialog[open]');
  check('rouverte : la case 🌙 est cochée', await page.isChecked('#cf-night'));
  // Échec réseau : la case revient en arrière, erreur affichée.
  await page.route('**/index.php?r=card_update*', (r) => r.fulfill({ status: 500, contentType: 'application/json', body: '{"error":"panne simulée"}' }));
  await page.uncheck('#cf-night');
  await page.waitForSelector('#cf-saved.erreur');
  check('échec : la case revient à son état enregistré', await page.isChecked('#cf-night'));
  await page.unroute('**/index.php?r=card_update*');
  for (let k = errors.length - 1; k >= 0; k--) if (/status of 500/.test(errors[k])) errors.splice(k, 1);   // panne voulue
  // Champs texte : « modifications non enregistrées » tant qu'on n'a pas enregistré.
  await page.fill('#cf-title', 'titre modifié sans enregistrer');
  check('champ texte modifié : « modifications non enregistrées »', await page.isVisible('#cf-dirty'));
  await shot(page, '04g_enregistrement_immediat', false);
  await page.click('#cf-cancel');   // confirmation acceptée
  await page.waitForFunction(() => !document.querySelector('#card-dialog[open]'));
  // Filtre « night shift seulement ».
  await page.check('#kb-night-only');
  const shownN = await page.$$eval('#board .column > .card', (l) => l.map((c) => !!c.querySelector('.badge.night')));
  check('night : filtre « night shift seulement »', shownN.length >= 4 && shownN.every(Boolean), String(shownN.length));
  await shot(page, '04f_night_filtre');
  await page.uncheck('#kb-night-only');
  // CLI et events.
  cli('set', String(nightId), '--night', 'off');
  check('cli : set --night off, show sans marque', !cli('show', String(nightId)).includes('[NIGHT]'));
  const ln = cli('cards', '--night').trim().split('\n');
  check('cli : cards --night', ln.every((l) => l.includes('[NIGHT]')) && ln.some((l) => l.includes(`#${hatId} `)), ln.length + ' lignes');
  const evn = cli('events', '--since', String(t0));
  check('events : NIGHT ON / NIGHT OFF avec auteur', new RegExp(`julien +#${nightId} .*NIGHT ON`).test(evn)
    && new RegExp(`claude +#${nightId} .*NIGHT OFF`).test(evn));
  const evj = JSON.parse(cli('events', '--since', String(t0), '--json')).events.filter((e) => e.type === 'night');
  check('events --json : type night, new = on/off', evj.length >= 4 && evj.every((e) => ['on', 'off'].includes(e.new)));
}

// ------------------------------------------------------------------ iPhone
// Vue mobile : une colonne à la fois, onglets collants, tuiles compactes.
for (let k = 1; k <= 8; k++) {
  cli('add-card', '--type', 'animation', '--title', `${tag} QA mobile ${k}`, '--asset', ASSET, '--detail', 'run', '--status', 'qa');
}
const wk = await webkit.launch();
for (const [name, vp] of [['iphone_portrait', { width: 390, height: 844 }], ['iphone_paysage', { width: 844, height: 390 }]]) {
  const ctx = await wk.newContext({ viewport: vp, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const mp = await ctx.newPage();
  mp.on('dialog', (d) => d.accept());
  await login(mp);
  await mp.waitForSelector('#kb-tabs:not([hidden]) .kb-tab.active');
  const tabs = await mp.$$eval('#kb-tabs .kb-tab[data-status]', (l) => l.map((t) => [t.dataset.status, t.getBoundingClientRect().height]));
  check(`${name} : 6 onglets assez grands`, tabs.length === 6 && tabs.every(([, h]) => h >= 40), JSON.stringify(tabs));
  const tabFit = await mp.$$eval('#kb-tabs .kb-tab', (l) => l.every((t) => t.scrollWidth <= t.clientWidth + 1
    && t.getBoundingClientRect().right <= innerWidth + 1));
  check(`${name} : libellés des onglets lisibles (sans débordement)`, tabFit);
  check(`${name} : QA ouvert par défaut (cartes à tester)`, (await mp.getAttribute('.kb-tab.active', 'data-status')) === 'qa');
  const shown = await mp.$$eval('.column', (l) => l.filter((c) => c.getBoundingClientRect().height > 0).length);
  check(`${name} : une seule colonne à l'écran`, shown === 1, String(shown));
  const fit = await mp.evaluate(() => [...document.querySelectorAll('.column.active .card')]
    .filter((c) => { const b = c.getBoundingClientRect(); return b.top >= 0 && b.bottom <= innerHeight; }).length);
  check(`${name} : cartes à l'écran (≥ ${name.endsWith('portrait') ? 8 : 4})`, fit >= (name.endsWith('portrait') ? 8 : 4), String(fit));
  const btn = await mp.$eval('.column.active .card.compact button.accept', (b) => b.getBoundingClientRect().height);
  check(`${name} : ✓ / ✗ sur la tuile, au doigt`, btn >= 40, String(btn));
  const over = await mp.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  check(`${name} : pas de défilement horizontal`, !over);
  await shot(mp, `05_${name}_board`, false);
  // Onglet Backlog, puis « déplacer vers… » sans ouvrir la carte.
  await mp.locator('.kb-tab[data-status=backlog]').tap();
  await mp.waitForSelector(`.column.active[data-status=backlog] .card[data-id="${hunterId}"]`);
  await mp.selectOption(`.card[data-id="${hunterId}"] select.move`, 'todo');
  await mp.waitForSelector(`.column[data-status=todo] .card[data-id="${hunterId}"]`, { state: 'attached' });
  check(`${name} : déplacer vers… (menu de la tuile)`, (await apiTok('cards'))[1].cards.find((c) => c.id === hunterId).status === 'todo');
  await mp.reload();
  await mp.waitForSelector('#kb-tabs .kb-tab.active');
  check(`${name} : onglet mémorisé`, (await mp.getAttribute('.kb-tab.active', 'data-status')) === 'backlog');
  await mp.selectOption(`.card[data-id="${hunterId}"] select.move`, 'backlog').catch(() => {});
  await mp.locator('.kb-tab[data-status=todo]').tap();
  await mp.selectOption(`.card[data-id="${hunterId}"] select.move`, 'backlog');
  await mp.waitForSelector(`.column[data-status=backlog] .card[data-id="${hunterId}"]`, { state: 'attached' });
  // Filtres repliés derrière ☰.
  check(`${name} : filtres repliés`, !(await mp.isVisible('.kanban-bar')));
  await mp.locator('.kb-tab.kb-filters').tap();
  check(`${name} : ☰ déplie les filtres`, await mp.isVisible('#kb-hat'));
  check(`${name} : « Masquer les chapeaux » dans le menu ☰`, await mp.isVisible('#kb-no-hats'));
  await mp.locator('#kb-no-hats').tap();
  const qaN = Number(await mp.textContent('.kb-tab[data-status=qa] .n'));
  const qaLeaves = (await apiTok('cards'))[1].cards.filter((c) => c.status === 'qa' && !c.children).length;
  check(`${name} : compteurs des onglets filtrés`, qaN === qaLeaves, `${qaN}/${qaLeaves}`);
  await mp.locator('#kb-no-hats').tap();
  await shot(mp, `06_${name}_filtres`, false);
  await mp.locator('.kb-tab.kb-filters').tap();
  // Miniature au toucher : anime sans ouvrir la carte ; décor : masques au toucher.
  await mp.locator('.kb-tab[data-status=qa]').tap();
  const anim = mp.locator('.column.active .card.compact').filter({ hasText: `${tag} QA mobile` }).nth(1);
  await anim.locator('.thumb-box').tap();
  await mp.waitForSelector('.column.active canvas.card-thumb');
  check(`${name} : miniature animée au premier toucher, carte fermée`, !(await mp.$('#card-dialog[open]')));
  if (hasDecor) await mp.locator(`.card[data-id="${decorId}"]`).scrollIntoViewIfNeeded().catch(() => {});
  if (hasDecor && await mp.$(`.card[data-id="${decorId}"] .dthumb`)) {
    await mp.locator(`.card[data-id="${decorId}"] .dthumb`).tap();
    await mp.waitForTimeout(300);
    check(`${name} : décor, masques au toucher`, await mp.$eval(`.card[data-id="${decorId}"] .dthumb`, (b) => b.classList.contains('masks'))
      && !(await mp.$('#card-dialog[open]')));
    await shot(mp, `06b_${name}_miniatures`, false);
  }
  await mp.evaluate(() => scrollTo(0, 0));
  // Détail plein écran : asset en haut, Accepter / Refuser collés en bas, ← pour fermer.
  const qc = mp.locator('.column.active .card.compact').filter({ hasText: `${tag} QA mobile` }).first();
  const qid = Number(await qc.getAttribute('data-id'));
  await qc.locator('.title').tap();
  await mp.waitForSelector('#cf-asset-view .anim-cell img.mini');
  const geo = await mp.evaluate(() => {
    const r = (s) => document.querySelector(s).getBoundingClientRect();
    return { w: r('#card-dialog').width, vw: innerWidth, asset: r('#cf-asset-view').top, form: r('#card-form').top,
      bar: r('#cf-qa-bar').bottom, vh: innerHeight, back: r('#cf-back').height };
  });
  check(`${name} : détail plein écran, asset en haut`, Math.abs(geo.w - geo.vw) < 2 && geo.asset < geo.form, JSON.stringify(geo));
  check(`${name} : Accepter / Refuser collés en bas`, Math.abs(geo.bar - geo.vh) < 2, JSON.stringify(geo));
  await shot(mp, `07_${name}_detail`, false);
  await mp.locator('#cf-back').tap();
  check(`${name} : ← ferme le détail`, !(await mp.$('#card-dialog[open]')));
  await qc.locator('.title').tap();
  await mp.waitForSelector('#cf-qa-bar:not([hidden])');
  await mp.locator('#cf-accept2').tap();
  await mp.waitForFunction(() => !document.querySelector('#card-dialog[open]'));
  check(`${name} : Accepter depuis la barre collante -> Validé`, (await apiTok('cards'))[1].cards.find((c) => c.id === qid).status === 'valide');
  await ctx.close();
}
await wk.close();
// Balayage horizontal (Chromium : WebKit ne construit pas de TouchEvent depuis un script).
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const mp = await ctx.newPage();
  await login(mp);
  await mp.waitForSelector('#kb-tabs .kb-tab.active');
  const before = await mp.getAttribute('.kb-tab.active', 'data-status');
  const swipe = (x0, x1) => mp.evaluate(([x0, x1]) => {
    const b = document.getElementById('board');
    const mk = (type, x) => {
      const t = new Touch({ identifier: 1, target: b, clientX: x, clientY: 400 });
      b.dispatchEvent(new TouchEvent(type, { touches: type === 'touchend' ? [] : [t], changedTouches: [t], bubbles: true }));
    };
    mk('touchstart', x0); mk('touchend', x1);
  }, [x0, x1]);
  await swipe(320, 80);
  const after = await mp.getAttribute('.kb-tab.active', 'data-status');
  check('mobile : balayage à gauche = colonne suivante', before === 'qa' && after === 'valide', `${before} -> ${after}`);
  await swipe(80, 320);
  check('mobile : balayage à droite = colonne précédente', (await mp.getAttribute('.kb-tab.active', 'data-status')) === 'qa');
  await ctx.close();
}

// ------------------------------------------------- mise à jour en direct (kanban)
// Board et détail ouverts : un commentaire, un déplacement, un changement d'asset/détail par le CLI,
// puis une nouvelle version publiée de l'asset (PRODUCER_FILES_DIR = dossier files/ du build servi)
// apparaissent sans recharger la page. Sondage accéléré à 1 s pour le test.
{
  const live = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  await live.addInitScript(() => { try { localStorage.setItem('producer-kb-tick', '1000'); } catch (e) { /* */ } });
  const lp = await live.newPage();
  lp.on('pageerror', (e) => errors.push(String(e)));
  await login(lp);
  const lid = Number(/#(\d+)/.exec(cli('add-card', '--type', 'animation', '--title', `${tag} direct`, '--asset', ASSET, '--detail', 'run', '--status', 'todo'))[1]);
  await lp.waitForSelector(`.card[data-id="${lid}"]`, { timeout: 40000 });
  check('direct : une carte créée par le CLI apparaît sans recharger', true);
  await lp.click(`.card[data-id="${lid}"] .title`);
  await lp.waitForSelector('#cf-asset-view .anim-cell');
  cli('comment', String(lid), `${tag} commentaire en direct`);
  await lp.waitForFunction((t) => document.getElementById('cf-feed').textContent.includes(t), `${tag} commentaire en direct`, { timeout: 8000 });
  check('direct : commentaire de Claude dans le fil du détail ouvert', true);
  cli('move', String(lid), 'doing');
  await lp.waitForFunction(() => document.getElementById('card-dialog-title').textContent.includes('Doing'), null, { timeout: 8000 });
  check('direct : changement de colonne visible dans le détail ouvert', true);
  cli('set', String(lid), '--detail', 'idle');
  await lp.waitForFunction(() => document.getElementById('cf-detail').value === 'idle'
    && document.querySelector('#cf-asset-view .anim-cell span:last-child').textContent.startsWith('idle'), null, { timeout: 8000 });
  await lp.waitForFunction((id) => decodeURIComponent(document.querySelector(`.card[data-id="${id}"] img.card-thumb`).src).includes('_poster/idle'), lid, { timeout: 8000 });
  check('direct : set --detail met à jour la tuile et le détail ouvert', true);
  const FILES = process.env.PRODUCER_FILES_DIR || '';
  if (FILES) {
    // Nouvelle version publiée : la miniature (image fixe d'idle) change de contenu et d'empreinte.
    const idxPath = path.join(FILES, 'index.json');
    const idxSave = fs.readFileSync(idxPath);
    const idx = JSON.parse(idxSave);
    const a = idx.assets.find((x) => x.id === ASSET);
    const anim = a.anims.find((x) => x.name === 'idle');
    const posterPath = path.join(FILES, anim.poster);
    const posterSave = fs.readFileSync(posterPath);
    fs.copyFileSync(path.join(FILES, a.anims.find((x) => x.name === 'run').poster), posterPath);
    idx.versions[anim.poster] = 'abcdef0123';
    a.version = 'nouvelle01';
    fs.writeFileSync(idxPath, JSON.stringify(idx));
    try {
      await lp.waitForFunction((id) => /v=abcdef0123/.test(document.querySelector(`.card[data-id="${id}"] img.card-thumb`).src)
        && /v=abcdef0123/.test(document.querySelector('#cf-asset-view img.mini').src), lid, { timeout: 8000 });
      check('direct : nouvelle version de l\'asset dans la tuile et le détail, sans recharger', true);
      check('direct : signe « ↻ nouvelle version »', await lp.isVisible(`.card[data-id="${lid}"] .fresh`) && await lp.isVisible('#cf-asset-view .fresh'));
      await lp.screenshot({ path: path.join(OUT, '08_direct_nouvelle_version.png') });
      // Le plein écran ouvert recharge aussi l'animation.
      await lp.click('#cf-asset-view .anim-cell');
      await lp.waitForSelector('.fs canvas');
      idx.versions[anim.file] = 'fedcba9876';
      a.version = 'nouvelle02';
      fs.writeFileSync(idxPath, JSON.stringify(idx));
      await lp.waitForFunction(() => performance.getEntriesByType('resource').some((r) => /v=fedcba9876/.test(r.name)), null, { timeout: 8000 });
      check('direct : plein écran ouvert rechargé avec la nouvelle version', !!(await lp.$('.fs canvas')));
      await lp.click('.fs-close');
    } finally {
      fs.writeFileSync(idxPath, idxSave);
      fs.writeFileSync(posterPath, posterSave);
    }
  } else {
    console.log('     (PRODUCER_FILES_DIR absent : republication d\'asset non testée)');
  }
  await live.close();
}

// ------------------------------------------------- accès Tailscale (service local)
// Service lancé avec 'tailscale_auth' => true : une requête du proxy local (127.0.0.1) portant
// Tailscale-User-Login est connectée sans mot de passe ; sans l'en-tête, 401.
const TS = process.env.PRODUCER_TAILSCALE_URL || '';
if (TS) {
  const H = { 'Tailscale-User-Login': 'julien@example.com' };
  const get = (route, headers = {}) => fetch(TS + 'index.php?r=' + route, { headers });
  const s0 = await (await get('session')).json();
  check('tailscale : sans l\'en-tête, pas connecté', s0.auth === false && s0.mode === 'password');
  check('tailscale : sans l\'en-tête, 401', (await get('cards')).status === 401);
  const r1 = await get('session', H);
  const s1 = await r1.json();
  const cookie = (r1.headers.get('set-cookie') || '').split(';')[0];
  check('tailscale : en-tête -> connecté (session + csrf, mode tailscale)', s1.auth === true && s1.mode === 'tailscale'
    && s1.csrf.length === 64 && cookie.startsWith('producer_sid='), JSON.stringify({ auth: s1.auth, mode: s1.mode }));
  check('tailscale : lecture avec l\'en-tête', (await get('cards', { ...H, Cookie: cookie })).status === 200);
  const post = (headers) => fetch(TS + 'index.php?r=card', { method: 'POST', headers: { ...H, Cookie: cookie, 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify({ title: `${tag} tailscale` }) });
  check('tailscale : écriture sans CSRF refusée (403)', (await post({})).status === 403);
  check('tailscale : écriture avec CSRF (201)', (await post({ 'X-CSRF-Token': s1.csrf })).status === 201);
  check('tailscale : en-tête direct sans cookie, connecté aussi', (await get('cards', H)).status === 200);
  check('tailscale : même cookie sans l\'en-tête -> 401', (await get('cards', { Cookie: cookie })).status === 401);
  check('tailscale : le jeton de l\'agent marche toujours', (await get('cards', { Authorization: 'Bearer ' + TOKEN })).status === 200);
  // Navigateur : pas d'écran de connexion, pas de « Déconnexion ».
  const tctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, extraHTTPHeaders: H });
  const tp = await tctx.newPage();
  tp.on('pageerror', (e) => errors.push(String(e)));
  await tp.goto(TS + '#/kanban');
  await tp.waitForSelector('#view-kanban:not([hidden]) #board .column');
  check('tailscale : navigateur connecté sans mot de passe', await tp.isHidden('#login') && await tp.isHidden('#logout'));
  await tp.fill('.quick-add input', `${tag} depuis tailscale`);
  await tp.click('.quick-add button[type=submit]');
  await tp.waitForSelector(`.card:has-text("${tag} depuis tailscale") .origin`);
  check('tailscale : création depuis le navigateur (CSRF), auteur Julien',
    (await tp.textContent(`.card:has-text("${tag} depuis tailscale") .origin`)) === 'Julien');
  await tctx.close();
} else {
  console.log('     (PRODUCER_TAILSCALE_URL absent : accès Tailscale non testé)');
}

check('aucune erreur JS', errors.length === 0, errors.join(' | '));
await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} vérifications OK — captures : ${OUT}`);
process.exit(failed.length ? 1 : 0);
