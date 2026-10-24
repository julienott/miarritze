// Miarritze Producer — roadmap (#/roadmap) : jalons (avec échéance) et chapeaux du kanban, leur
// avancement (feuilles En prod / Validé / QA / total, barres empilées), et ce qui bloque (refus à retraiter,
// cartes en Doing qui ne bougent plus, échéances dépassées). Un chapeau rattaché à un jalon y
// emmène toute sa famille.
'use strict';

const STALE_DAYS = 3;   // même seuil que GET stats

const rm = { mode: store('producer-rm-mode') || 'jalons', editing: 0 };

/** Chapeaux de premier niveau (cartes avec enfants et sans parent). */
function topHats() {
  return state.cards.filter((c) => c.children > 0 && !c.parent_id);
}

function staleCards() {
  const now = Date.now() / 1000;
  return state.cards.filter((c) => c.status === 'doing' && !c.rework && now - (c.status_at || c.updated_at) >= STALE_DAYS * 86400);
}

function sinceText(ts) {
  const d = Math.floor((Date.now() / 1000 - ts) / 86400);
  return d <= 0 ? 'aujourd\'hui' : d === 1 ? 'depuis 1 jour' : `depuis ${d} jours`;
}

/** Liste courte de cartes (pastille, titre, info) ; clic = détail de la carte. */
function cardList(cards, info, max = 8) {
  const shown = cards.slice(0, max);
  return el('ul', { class: 'lcards' }, shown.map((c) => linkedCardRow(c, () => renderRoadmap())),
    cards.length > max ? el('li', { class: 'muted small', text: `… et ${cards.length - max} autres` }) : null,
    info ? null : null);
}

function blockersPanel(scope) {
  const inScope = scope ? (c) => scope.has(c.id) : () => true;
  const rework = state.cards.filter((c) => c.rework && inScope(c));
  const stale = staleCards().filter(inScope);
  const late = state.cards.filter((c) => c.due && c.due < todayIso() && !FINISHED.has(c.status) && inScope(c));
  if (!rework.length && !stale.length && !late.length) return null;
  return el('div', { class: 'blockers' },
    rework.length ? el('div', {}, el('h4', { class: 'kind', text: `↺ Refusées, à retraiter (${rework.length})` }), cardList(rework)) : null,
    stale.length ? el('div', {}, el('h4', { class: 'kind', text: `En Doing depuis plus de ${STALE_DAYS} jours (${stale.length})` }),
      el('ul', { class: 'lcards' }, stale.slice(0, 8).map((c) => {
        const li = linkedCardRow(c);
        li.append(el('span', { class: 'muted small', text: sinceText(c.status_at) }));
        return li;
      }))) : null,
    late.length ? el('div', {}, el('h4', { class: 'kind', text: `Échéance dépassée (${late.length})` }), cardList(late)) : null);
}

function hatRow(h) {
  const leaves = leavesOf(h.id);
  const [bar, txt] = stackBar(leaves);
  const rework = leaves.filter((c) => c.rework).length;
  return el('div', { class: 'hat-line' },
    el('button', { type: 'button', class: 'link hat-title', onclick: () => openCardDialog(h, '') }, h.title),
    el('span', { class: 'muted small', text: '#' + h.id }), cardPill(h), dueBadge(h.due, FINISHED.has(h.status)),
    rework ? el('span', { class: 'rework', text: `↺ ${rework}` }) : null,
    el('a', { href: '#/kanban', class: 'small', onclick: () => { state.hat = h.id; store('producer-kb-hat', String(h.id)); }, text: 'kanban ›' }),
    el('div', { class: 'hat-bar' }, bar, el('span', { class: 'muted small', text: txt })));
}

function milestoneForm(m) {
  const title = el('input', { maxlength: 200, value: m ? m.title : '', placeholder: 'Nom du jalon (ex. Contenu v1)', 'aria-label': 'Nom du jalon', required: true });
  const due = el('input', { type: 'date', value: m ? m.due : '', 'aria-label': 'Échéance' });
  const desc = el('textarea', { rows: 2, maxlength: 8000, placeholder: 'Ce qu\'il faut pour l\'atteindre…', 'aria-label': 'Description' });
  desc.value = m ? m.description : '';
  const closed = el('input', { type: 'checkbox', checked: m && m.closed ? true : null });
  const form = el('form', { class: 'panel ms-form' },
    el('div', { class: 'row' }, el('label', {}, 'Jalon', title), el('label', {}, 'Échéance', due)),
    el('label', {}, 'Description', desc),
    m ? el('label', { class: 'inline' }, closed, 'Jalon clos (atteint ou abandonné)') : null,
    el('div', { class: 'row end' },
      m ? el('button', { type: 'button', class: 'danger small', onclick: async () => {
        if (!confirm(`Supprimer le jalon « ${m.title} » ? Ses cartes restent, sans jalon.`)) return;
        const ok = await guarded(async () => { await api('milestone_delete', { method: 'POST', body: { id: m.id } }); await Promise.all([reloadMilestones(), reloadCards()]); return true; });
        if (ok) { rm.editing = 0; renderRoadmap(); }
      } }, 'Supprimer') : null,
      el('span', { class: 'spacer' }),
      el('button', { type: 'button', class: 'ghost small', onclick: () => { rm.editing = 0; renderRoadmap(); } }, 'Annuler'),
      el('button', { type: 'submit', class: 'primary small' }, m ? 'Enregistrer' : 'Créer le jalon')));
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const body = { title: title.value.trim(), due: due.value, description: desc.value.trim() };
    if (!body.title) return;
    const ok = await guarded(async () => {
      if (m) await api('milestone_update', { method: 'POST', body: { id: m.id, ...body, closed: closed.checked } });
      else await api('milestone', { method: 'POST', body });
      await reloadMilestones();
      return true;
    });
    if (ok) { rm.editing = 0; toast(m ? 'Jalon enregistré' : 'Jalon créé'); renderRoadmap(); }
  });
  return form;
}

/** Ajoute un chapeau (ou une carte) à un jalon. */
function attachSelect(m) {
  const free = topHats().filter((h) => !h.milestone_id).sort((a, b) => a.title.localeCompare(b.title, 'fr'));
  const sel = el('select', { 'aria-label': 'Rattacher un chapeau à ce jalon' },
    el('option', { value: '', text: free.length ? '+ Rattacher un chapeau…' : 'Tous les chapeaux ont un jalon' }),
    free.map((h) => el('option', { value: h.id, text: `#${h.id} ${h.title}` })));
  sel.addEventListener('change', async () => {
    const id = Number(sel.value);
    if (!id) return;
    const ok = await guarded(async () => { await api('card_update', { method: 'POST', body: { id, milestone: m.id } }); await reloadCards(); return true; });
    if (ok) { toast('Chapeau rattaché au jalon'); renderRoadmap(); }
  });
  return sel;
}

function milestoneSection(m) {
  if (rm.editing === m.id) return milestoneForm(m);
  const fam = state.cards.filter((c) => milestoneOf(c) === m.id);
  const scope = new Set(fam.map((c) => c.id));
  const leaves = fam.filter((c) => !c.children);
  const [bar, txt] = stackBar(leaves);
  const direct = fam.filter((c) => c.milestone_id === m.id);
  const hats = direct.filter((c) => c.children > 0);
  const singles = direct.filter((c) => !c.children);
  const late = m.due && !m.closed && m.due < todayIso();
  const det = el('details', { class: 'panel milestone' + (m.closed ? ' closed' : ''), open: !m.closed || null, 'data-ms': m.id },
    el('summary', { class: 'ms-head' },
      el('span', { class: 'ms-title', text: '⚑ ' + m.title }),
      m.due ? el('span', { class: 'badge due' + (late ? ' late' : ''), text: '⏱ ' + fmtDue(m.due) + (late ? ' (dépassée)' : '') }) : null,
      m.closed ? el('span', { class: 'badge done', text: 'clos' }) : null,
      el('span', { class: 'spacer' }),
      el('button', { type: 'button', class: 'small ghost', onclick: (ev) => { ev.preventDefault(); rm.editing = m.id; renderRoadmap(); } }, 'Modifier')),
    el('div', { class: 'ms-bar' }, bar, el('span', { class: 'muted small', text: leaves.length ? txt : 'Aucune carte : rattache un chapeau à ce jalon.' })),
    m.description ? el('div', { class: 'ms-desc' }, ...md(m.description)) : null,
    blockersPanel(scope),
    hats.length ? el('div', { class: 'hats' }, hats.map(hatRow)) : null,
    singles.length ? el('div', {}, el('h4', { class: 'kind', text: 'Cartes seules' }), cardList(singles, null, 20)) : null,
    el('div', { class: 'row' }, attachSelect(m),
      el('a', { href: '#/kanban', class: 'small', onclick: () => { state.kb.ms = String(m.id); store('producer-kb-filters', JSON.stringify(state.kb)); }, text: 'voir dans le kanban ›' })));
  return det;
}

function renderRoadmap() {
  const box = $('roadmap');
  const modes = [['jalons', 'Par jalon'], ['chapeaux', 'Par chapeau']];
  const g = state.index.blackout || {};
  const head = el('div', { class: 'rm-bar' },
    el('div', { class: 'seg' }, modes.map(([k, label]) => el('button', {
      type: 'button', class: 'small' + (rm.mode === k ? ' primary' : ''),
      onclick: () => { rm.mode = k; store('producer-rm-mode', k); renderRoadmap(); },
    }, label))),
    el('span', { class: 'spacer' }),
    el('button', { type: 'button', class: 'small primary', onclick: () => { rm.editing = -1; renderRoadmap(); } }, '+ Jalon'));
  const blocks = [head];
  const globalBlockers = blockersPanel(null);
  if (rm.mode === 'jalons') {
    if (rm.editing === -1) blocks.push(milestoneForm(null));
    if (!state.milestones.length && (g.jalons_spec || []).length) {
      blocks.push(el('div', { class: 'panel' },
        el('p', {}, 'Aucun jalon pour l\'instant. La spec en propose ', el('strong', { text: String(g.jalons_spec.length) }), ' (GDD-BLACKOUT.md) :'),
        el('ol', {}, g.jalons_spec.map((j) => el('li', {}, el('strong', { text: j.titre }), j.description ? ' — ' + j.description.replace(/\n/g, ' ') : ''))),
        el('button', { type: 'button', class: 'primary small', onclick: seedMilestones }, 'Créer ces jalons')));
    }
    for (const m of state.milestones) blocks.push(milestoneSection(m));
    const orphans = topHats().filter((h) => !milestoneOf(h));
    if (orphans.length) {
      blocks.push(el('details', { class: 'panel milestone' }, el('summary', { class: 'ms-head' },
        el('span', { class: 'ms-title', text: `Sans jalon (${orphans.length} chapeaux)` })),
      el('div', { class: 'hats' }, orphans.map(hatRow))));
    }
  } else {
    // Par chapeau : arbre des chapeaux, les moins avancés d'abord.
    const prog = (h) => { const l = leavesOf(h.id); return l.length ? l.filter((c) => ADVANCED.has(c.status)).length / l.length : 1; };
    const tree = (h, depth) => [el('div', { class: 'hat-tree d' + depth }, hatRow(h)),
      ...childrenOf(h.id).filter((k) => k.children > 0).sort((a, b) => prog(a) - prog(b)).flatMap((k) => tree(k, depth + 1))];
    blocks.push(el('section', { class: 'panel' }, el('h3', { text: 'Chapeaux et sous-chapeaux' }),
      ...topHats().sort((a, b) => prog(a) - prog(b)).flatMap((h) => tree(h, 0))));
  }
  if (globalBlockers) blocks.splice(1, 0, el('section', { class: 'panel' }, el('h3', { text: 'Ce qui bloque' }), globalBlockers));
  box.replaceChildren(...blocks);
}

/** Crée les jalons de la spec (§14), dans l'ordre. */
async function seedMilestones() {
  const list = (state.index.blackout || {}).jalons_spec || [];
  const ok = await guarded(async () => {
    for (const j of list) await api('milestone', { method: 'POST', body: { title: j.titre, description: j.description } });
    await reloadMilestones();
    return true;
  });
  if (ok) { toast(`${list.length} jalons créés`); renderRoadmap(); }
}
