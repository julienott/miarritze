// Déblocage audio Safari (macOS + iOS) — DOIT charger AVANT l'export Godot.
// Safari refuse resume() d'un AudioContext hors d'un handler synchrone d'un
// geste utilisateur. Et sur iOS, il faut en plus jouer un son effectif
// (buffer silencieux) dans ce même handler pour que l'autoplay s'ouvre.
(function () {
  var OrigAC = window.AudioContext || window.webkitAudioContext;
  if (!OrigAC) return;
  var ctxs = [];
  window.__miarritzeAudioCtxs = ctxs;

  // Proxy pour conserver les arguments (sampleRate, latencyHint…) que Godot
  // peut passer. Un wrapper naïf qui fait `new Base()` les perd.
  function wrap(Base) {
    try {
      return new Proxy(Base, {
        construct: function (target, args, newTarget) {
          var inst = Reflect.construct(target, args, newTarget);
          try { ctxs.push(inst); } catch (e) {}
          return inst;
        }
      });
    } catch (e) {
      return Base;
    }
  }
  try { window.AudioContext = wrap(OrigAC); } catch (e) {}
  if (window.webkitAudioContext && window.webkitAudioContext !== OrigAC) {
    try { window.webkitAudioContext = wrap(window.webkitAudioContext); } catch (e) {}
  } else if (window.webkitAudioContext) {
    try { window.webkitAudioContext = window.AudioContext; } catch (e) {}
  }

  function resumeAll() {
    // Rattrape aussi les contextes créés avant notre patch, s'ils sont
    // exposés par Godot sur window (défensif, probablement vide).
    try {
      var extra = [];
      if (window.Godot && window.Godot.audio_context) extra.push(window.Godot.audio_context);
      if (window.engine && window.engine.audioCtx) extra.push(window.engine.audioCtx);
      extra.forEach(function (c) { if (c && ctxs.indexOf(c) === -1) ctxs.push(c); });
    } catch (e) {}
    ctxs.forEach(function (c) {
      try {
        if (c.state === 'suspended' && c.resume) c.resume();
        var buf = c.createBuffer(1, 1, 22050);
        var src = c.createBufferSource();
        src.buffer = buf;
        src.connect(c.destination);
        if (src.start) src.start(0); else if (src.noteOn) src.noteOn(0);
      } catch (e) {}
    });
  }

  var unlocked = false;
  function unlock() {
    resumeAll();
    // On re-tente plusieurs fois : certains contextes sont créés en retard
    // par Godot (audio worklet, decodeAudioData), ou passent de 'running'
    // à 'suspended' après un onglet en arrière-plan.
    setTimeout(resumeAll, 100);
    setTimeout(resumeAll, 500);
    setTimeout(resumeAll, 2000);
    if (unlocked) return;
    unlocked = true;
    ['touchstart', 'touchend', 'click', 'keydown', 'pointerdown'].forEach(function (ev) {
      document.removeEventListener(ev, unlock, true);
    });
  }
  ['touchstart', 'touchend', 'click', 'keydown', 'pointerdown'].forEach(function (ev) {
    document.addEventListener(ev, unlock, true);
  });

  // Si l'onglet redevient visible, re-résumer (Safari suspend parfois).
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) resumeAll();
  }, true);
})();
