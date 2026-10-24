// Miarritze Producer — recette d'un character set dans la carte chapeau d'un perso (ou d'un PNJ,
// du fantôme, d'un animal, d'un boss) : le profil et le portrait en tête, puis toutes les animations,
// chacune animée en 32 px agrandi net et en HD si le build l'a, avec son libellé, ce qu'on doit
// voir, l'action demandée, l'objet, le clip Quaternius, les images, la cadence et la boucle.
// Un bouton par animation pose un commentaire d'asset (detail = nom de l'élément) reporté sur la
// carte ouverte ; les commentaires déjà posés sur l'élément s'affichent dessous.
// Chaque élément montre la colonne de sa carte enfant (base, expression, animation) et, en QA,
// ✓ Valider et ✗ Refuser (Refuser ou Refuser et refaire, commentaire obligatoire) (Julien, 24/10) ;
// les éléments prévus mais pas encore livrés sont listés aussi, avec leur colonne.
'use strict';

const SET_BGS = [['light', 'Clair'], ['dark', 'Sombre'], ['checker', 'Damier']];

/** Set dont le nom (ou l'id) apparaît dans le titre d'une carte « Perso : Louis ». */
function setFromTitle(title) {
  const t = norm(title || '');
  if (!t || !state.index || !state.index.blackout) return null;
  const g = state.index.blackout;
  const words = t.split(/[^a-z0-9_]+/);
  for (const key of [...(g.persos || []), ...(g.autres || [])]) {
    const a = state.assetsById.get(bkAssetId(key));
    if (a && a.set && words.includes(key.split('/').pop())) return a;
  }
  return null;
}

/** Élément visé par un commentaire d'asset (contexte « anim : <nom> … »), sinon ''. */
function commentElement(c) {
  const m = /^anim : ([A-Za-z0-9_]+)/.exec(c.context || '');
  return m ? m[1] : '';
}

// ------------------------------------------------------------------ lecture des planches

/**
 * Lecteur d'une planche (une rangée de cases) dans un canvas : chargé et animé seulement quand
 * il est à l'écran (IntersectionObserver), arrêté quand le canvas quitte la page. Une animation
 * sans boucle marque une pause sur sa dernière image, comme le lecteur plein écran.
 */
function sheetPlayer(anim, canvas, gal) {
  const p = { anim, canvas, img: null, frame: Math.floor(anim.frames / 2), timer: 0, visible: false };
  const ctx = canvas.getContext('2d');
  const draw = () => {
    if (!p.img) return;
    const w = p.img.naturalWidth / anim.frames;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(p.img, p.frame * w, 0, w, p.img.naturalHeight, 0, 0, canvas.width, canvas.height);
  };
  const tick = () => {
    clearTimeout(p.timer);
    if (!canvas.isConnected) { p.stop(); return; }
    if (!p.visible || gal.paused || !p.img) return;
    const last = p.frame === anim.frames - 1;
    p.timer = setTimeout(() => {
      p.frame = (p.frame + 1) % anim.frames;
      draw();
      tick();
    }, 1000 / anim.fps + (last && !anim.loop ? 600 : 0));
  };
  p.show = (on) => {
    p.visible = on;
    if (on && !p.img) {
      const img = new Image();
      img.onload = () => { p.img = img; draw(); tick(); };
      img.src = fileUrl(anim.file);
      return;
    }
    tick();
  };
  p.resume = tick;
  p.stop = () => {
    clearTimeout(p.timer);
    if (p.img) { p.img.onload = null; p.img = null; }
    gal.players.delete(p);
  };
  // Image fixe en attendant la planche : la case du milieu.
  if (anim.poster) {
    const poster = new Image();
    poster.onload = () => { if (!p.img) ctx.drawImage(poster, 0, 0, canvas.width, canvas.height); };
    poster.src = fileUrl(anim.poster);
  }
  gal.players.add(p);
  return p;
}

/** Zoom entier du 32 px : ×3 sur ordinateur, ×2 sur téléphone (cases de 64), moins pour les boss. */
function pxZoom(w, head) {
  const room = window.innerWidth < 700 ? (head ? 150 : 130) : (head ? 256 : 192);
  return Math.max(1, Math.floor(room / w));
}

/** Une vue (32 px ou HD) d'un élément : canvas à la taille d'affichage commune. */
function setView(anim, gal, kind, size, label) {
  const canvas = el('canvas', { class: 'sg-canvas ' + kind, width: anim.w, height: anim.h,
    'aria-label': label, role: 'img' });
  canvas.style.width = size + 'px';
  canvas.style.height = Math.round(size * anim.h / anim.w) + 'px';
  const p = sheetPlayer(anim, canvas, gal);
  gal.observer.observe(canvas);
  canvas.player = p;
  return el('figure', { class: 'sg-view ' + kind }, canvas, el('figcaption', { text: label }));
}

// ------------------------------------------------------------------ galerie

/**
 * Remplit `box` (#cf-asset-view) avec la recette du set de l'asset `a` (asset « animations » qui
 * porte `set`) : en-tête (nom, placeholder, HD, avertissements de set.json), profil et portrait,
 * puis une fiche par animation. Les commentaires vont sur la carte ouverte (state.editing).
 */
function renderSetGallery(box, a) {
  const s = a.set;
  const key = s.famille === 'persos' ? s.id : `${s.famille}/${s.id}`;
  const cardId = state.editing ? state.editing.id : 0;
  $('card-dialog').classList.add('wide');
  if (box.gallery) box.gallery.close();
  const gal = { players: new Set(), paused: false, observer: null };
  gal.observer = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.target.player) e.target.player.show(e.isIntersecting);
  }, { rootMargin: '120px' });
  gal.close = () => { gal.observer.disconnect(); for (const p of [...gal.players]) p.stop(); };
  box.gallery = gal;

  let bg = store('producer-set-bg') || 'light';
  let showHd = store('producer-set-hd') !== '0';
  const root = el('div', { class: `set-gal bg-${bg}` + (showHd ? '' : ' no-hd') });
  const bgBtn = el('button', { type: 'button', class: 'small' });
  const setBg = (v) => {
    bg = v; store('producer-set-bg', v);
    root.classList.remove('bg-light', 'bg-dark', 'bg-checker');
    root.classList.add('bg-' + v);
    bgBtn.textContent = 'Fond : ' + SET_BGS.find(([k]) => k === v)[1];
  };
  bgBtn.addEventListener('click', () => setBg(SET_BGS[(SET_BGS.findIndex(([k]) => k === bg) + 1) % SET_BGS.length][0]));
  setBg(bg);
  const playBtn = el('button', { type: 'button', class: 'small' }, '⏸ Pause');
  playBtn.addEventListener('click', () => {
    gal.paused = !gal.paused;
    playBtn.textContent = gal.paused ? '▶ Lecture' : '⏸ Pause';
    for (const p of gal.players) p.resume();
  });
  const hdBtn = s.hd ? el('button', { type: 'button', class: 'small' + (showHd ? ' on' : '') }, 'HD : ' + (showHd ? 'oui' : 'non')) : null;
  if (hdBtn) {
    hdBtn.addEventListener('click', () => {
      showHd = !showHd; store('producer-set-hd', showHd ? '1' : '0');
      root.classList.toggle('no-hd', !showHd);
      hdBtn.classList.toggle('on', showHd);
      hdBtn.textContent = 'HD : ' + (showHd ? 'oui' : 'non');
    });
  }

  const head = ['profile', 'portrait'];
  const anims = a.anims || [];
  // Cartes enfants du chapeau ouvert, par élément : base -> profil et portrait.
  // Toute la famille : les lancements sont sous leur coup, les portraits sous « portraits ».
  const kids = cardId ? [...familyIds(cardId)].filter((id) => id !== cardId).map(cardById).filter((k) => k && k.detail) : [];
  const kidOf = (name) => kids.find((k) => k.detail === (name === 'profile' ? 'base' : name === 'portrait' ? 'portrait:menus' : name))
    || (name === 'portrait' ? kids.find((k) => k.detail === 'base') : null) || null;
  /** Colonne de la carte de l'élément, et ✓ / ✗ si elle est en QA. */
  const verdict = (k) => {
    if (!k) return null;
    const box = el('span', { class: 'sg-verdict' }, cardPill(k),
      el('a', { href: '#', class: 'small-note', text: `#${k.id}`, title: k.title,
        onclick: (ev) => { ev.preventDefault(); openCardDialog(k); } }));
    if (k.status === 'qa') {
      box.append(
        el('button', { type: 'button', class: 'small accept', title: 'Valider cet élément', onclick: () => acceptCard(k) }, '✓ Valider'),
        el('button', { type: 'button', class: 'small refuse', title: 'Refuser, ou refuser et refaire (commentaire obligatoire)',
          onclick: () => openRefuse(k) }, '✗ Refuser'));
    }
    return box;
  };
  const fiches = new Map();      // élément -> fonction qui redessine ses commentaires
  const general = el('div', { class: 'asset-comments' });
  const refresh = () => {
    for (const f of fiches.values()) f();
    renderGeneral();
    if (state.editing) loadFeed(state.editing.id);
  };
  const renderGeneral = () => {
    const mine = state.comments.filter((c) => c.asset === a.id && !anims.some((x) => x.name === commentElement(c)));
    general.replaceChildren(...(mine.length ? mine.map((c) => commentEl(c, false, refresh))
      : [el('p', { class: 'muted', text: 'Aucun commentaire sur l\'ensemble du set.' })]));
  };

  /** Fiche d'un élément : vues, libellé, description, infos, commentaires. */
  const fiche = (x, big) => {
    const z = pxZoom(x.w, big);
    const size = x.w * z;
    const views = el('div', { class: 'sg-views' },
      setView(x, gal, 'px', size, `32 px ×${z}`),
      x.hd ? setView(x.hd, gal, 'hd', size, `HD ${x.hd.w} px`) : null);
    const list = el('div', { class: 'sg-comments' });
    const renderList = () => {
      const mine = state.comments.filter((c) => c.asset === a.id && commentElement(c) === x.name);
      list.replaceChildren(...mine.map((c) => commentEl(c, false, refresh)));
      count.textContent = mine.length ? `💬 ${mine.length}` : '';
      count.hidden = !mine.length;
    };
    const count = el('span', { class: 'badge amelioration', hidden: true });
    fiches.set(x.name, renderList);
    let form = null;
    const commentBtn = el('button', { type: 'button', class: 'small primary sg-comment' }, '💬 Commenter');
    const node = el('article', { class: 'sg-el' + (big ? ' big' : ''), 'data-el': x.name });
    commentBtn.addEventListener('click', () => {
      if (form) { form.remove(); form = null; commentBtn.textContent = '💬 Commenter'; return; }
      form = commentForm(a, () => 'anim : ' + x.name, () => {
        if (form) { form.remove(); form = null; commentBtn.textContent = '💬 Commenter'; }
        refresh();
      }, cardId, x.name);
      form.classList.add('sg-form');
      list.before(form);
      commentBtn.textContent = '✕ Annuler';
      form.querySelector('textarea').focus();
    });
    const facts = [x.clip ? `clip ${x.clip}` : null, `${x.frames} image${x.frames > 1 ? 's' : ''}`,
      `${x.fps} i/s`, x.frames > 1 ? (x.loop ? 'boucle' : 'une fois') : null].filter(Boolean).join(' · ');
    node.append(views,
      el('div', { class: 'sg-text' },
        el('h4', {}, el('span', { text: x.libelle || x.name }), ' ', el('code', { text: x.name }), ' ', count),
        x.description ? el('p', { class: 'sg-desc', text: x.description }) : null,
        x.action ? el('p', { class: 'sg-action' }, el('span', { class: 'muted', text: 'Action demandée : ' }), `« ${x.action} »`) : null,
        x.objet ? el('p', { class: 'sg-action' }, el('span', { class: 'muted', text: 'Objet : ' }), x.objet) : null,
        el('p', { class: 'sg-facts muted', text: facts }),
        verdict(kidOf(x.name)),
        el('div', { class: 'sg-actions' }, commentBtn,
          el('button', { type: 'button', class: 'small', title: 'Lecteur plein écran (image par image, ligne des pieds)',
            onclick: () => { $('card-dialog').close(); openPlayer(key, x.name); } }, '⛶'))),
      list);
    renderList();
    return node;
  };

  const warns = s.warnings || [];
  const top = el('div', { class: 'sg-head' },
    el('div', { class: 'sg-title' },
      el('h3', {}, 'Recette : ', el('a', { href: '#/assets/' + encodeURIComponent(a.id), text: s.nom,
        onclick: (ev) => { ev.preventDefault(); $('card-dialog').close(); location.hash = '#/assets/' + encodeURIComponent(a.id); } })),
      s.placeholder ? el('span', { class: 'badge placeholder', title: 'Set provisoire (set.json : placeholder) : à remplacer par le vrai rendu pixelforge', text: 'PLACEHOLDER' }) : null,
      el('span', { class: 'badge', text: `${anims.length} éléments` }),
      el('span', { class: 'badge', text: s.hd ? 'HD disponible' : '32 px seulement' }),
      warns.length ? el('span', { class: 'badge warn', text: `⚠ ${warns.length}` }) : null),
    s.description ? el('p', { class: 'sg-desc' }, el('span', { class: 'muted', text: 'Prompt : ' }), s.description
      + (s.signature ? ` · signature : ${s.signature}` : '')) : null,
    warns.length ? el('ul', { class: 'warns sg-warns' }, warns.map((w) => el('li', { text: w }))) : null,
    el('div', { class: 'controls sg-bar' }, playBtn, bgBtn, hdBtn,
      el('span', { class: 'muted small-note', text: `${a.id} · version ${a.version}` })));

  const heads = anims.filter((x) => head.includes(x.name));
  const rest = anims.filter((x) => !head.includes(x.name));
  const livres = new Set(anims.map((x) => x.name));
  /** Élément prévu (carte enfant) sans rendu dans le build : titre et colonne. */
  const prevu = (k) => el('article', { class: 'sg-el sg-missing', 'data-el': k.detail },
    el('div', { class: 'sg-text' },
      el('h4', {}, el('span', { text: k.title.replace(/^.*·\s*/, '') }), ' ', el('code', { text: k.detail })),
      el('p', { class: 'muted', text: k.status === 'qa' || k.status === 'valide' || k.status === 'done'
        ? 'Livré, pas encore dans ce build du board' : 'Pas encore livré' }),
      verdict(k)));
  const expressions = kids.filter((k) => k.detail.startsWith('expr:'));
  const portraits = kids.filter((k) => k.detail.startsWith('portrait:') && k.detail !== 'portrait:menus');
  const manquants = kids.filter((k) => k.detail !== 'base' && !/^(expr|portrait|objet|effet|icone)/.test(k.detail) && !livres.has(k.detail));
  const baseKid = kids.find((k) => k.detail === 'base');
  // Profils de référence (Julien 24/10) : le profil porte toutes les variations ; le neutre en grand,
  // puis un profil par expression, chacun avec sa carte (base, expr:<clé>).
  const profils = s.profils || [];
  // Usages de portrait de chaque expression (GDD §8.5 ; index : set.portraits), l'expression les porte (Julien 24/10).
  const USAGES = { menus: 'menus', versus_chasseur: 'versus chasseur', versus_chasse: 'versus chassé',
    podium_gagnant: 'podium gagnant', podium_perdant: 'podium perdant' };
  const usagesDe = (k) => Object.entries(s.portraits || {}).filter(([, v]) => v === k).map(([u]) => USAGES[u] || u).join(', ');
  const avecImage = new Set(profils.map((x) => x.expression));
  const profilEl = (x, big) => {
    const k = x.expression === 'neutre' ? kids.find((c) => c.detail === 'base') : kids.find((c) => c.detail === 'expr:' + x.expression);
    return el('figure', { class: 'sg-profil' + (big ? ' big' : ''), 'data-el': x.expression },
      el('div', { class: 'sg-profil-img' },
        el('img', { src: fileUrl(x.profile), alt: `profil ${x.expression}`, loading: 'lazy' }),
        x.portrait ? el('img', { src: fileUrl(x.portrait), alt: `portrait ${x.expression}`, loading: 'lazy' }) : null),
      el('figcaption', {}, el('strong', { text: x.expression === 'neutre' ? 'Profil neutre (référence)' : x.expression }),
        usagesDe(x.expression) ? el('span', { class: 'muted small-note', text: ' · portrait ' + usagesDe(x.expression) }) : null,
        verdict(k || null)));
  };
  const blocProfils = profils.length ? el('section', { class: 'sg-profils' },
    el('h3', { text: 'Profils de référence' }),
    el('p', { class: 'muted small-note', text: 'Toutes les expressions, portraits et animations sont faits depuis ces profils (HD).' }),
    el('div', { class: 'sg-profils-grid' }, profils.map((x) => profilEl(x, x.expression === 'neutre')))) : null;
  const exprSansImage = expressions.filter((k) => !avecImage.has(k.detail.slice(5)));
  root.append(...[top, blocProfils,
    heads.length ? el('div', { class: 'sg-grid sg-top' }, heads.map((x) => fiche(x, true)))
      : baseKid ? el('div', { class: 'sg-grid sg-top' }, prevu(baseKid)) : null,
    portraits.length ? el('h3', { text: `Autres portraits (${portraits.length}) : versus, podium` }) : null,
    portraits.length ? el('div', { class: 'sg-expr' }, portraits.map((k) => el('div', { class: 'sg-expr-row', 'data-el': k.detail },
      el('strong', { text: k.title.replace(/^.*·\s*portrait\s*/, '') }), ' ', verdict(k)))) : null,
    exprSansImage.length ? el('h3', { text: `Expressions pas encore livrées (${exprSansImage.length})` }) : null,
    exprSansImage.length ? el('div', { class: 'sg-expr' }, exprSansImage.map((k) => el('div', { class: 'sg-expr-row', 'data-el': k.detail },
      el('strong', { text: k.detail.slice(5) }), ' ', verdict(k)))) : null,
    el('h3', { text: `Animations (${rest.length}${manquants.length ? ` livrées, ${manquants.length} pas encore` : ''})` }),
    el('div', { class: 'sg-grid' }, rest.map((x) => fiche(x, false)), manquants.map(prevu)),
    el('h3', { text: 'Sur l\'ensemble du set' }),
    commentForm(a, () => '', refresh, cardId),
    general].filter(Boolean));
  renderGeneral();
  box.replaceChildren(root);
}

// Le détail de la carte se ferme : on arrête les lecteurs de la galerie.
document.addEventListener('DOMContentLoaded', () => {
  const dlg = $('card-dialog');
  if (dlg) dlg.addEventListener('close', () => {
    const box = $('cf-asset-view');
    if (box && box.gallery) { box.gallery.close(); box.gallery = null; }
  });
});
