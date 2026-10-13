// Déblocage audio iOS Safari — doit charger AVANT l'export Godot.
// iOS n'autorise la reprise d'un AudioContext QUE dans un handler synchrone
// d'un geste utilisateur. Si le contexte a été créé avant interaction, il
// faut aussi y jouer un buffer silencieux dans ce même handler.
(function () {
  var ctxs = [];
  var OrigAC = window.AudioContext || window.webkitAudioContext;
  if (!OrigAC) return;

  function wrap(Base) {
    function Patched() {
      var inst = new Base();
      try { ctxs.push(inst); } catch (e) {}
      return inst;
    }
    Patched.prototype = Base.prototype;
    return Patched;
  }
  try { window.AudioContext = wrap(window.AudioContext || OrigAC); } catch (e) {}
  try { window.webkitAudioContext = wrap(window.webkitAudioContext || OrigAC); } catch (e) {}
  window.__miarritzeAudioCtxs = ctxs;

  var unlocked = false;
  function unlock() {
    if (unlocked) return;
    unlocked = true;
    ctxs.forEach(function (c) {
      try {
        if (c.state === 'suspended' && c.resume) c.resume();
        // Buffer silencieux de 1 sample — iOS a besoin d'un son effectif.
        var buf = c.createBuffer(1, 1, 22050);
        var src = c.createBufferSource();
        src.buffer = buf;
        src.connect(c.destination);
        if (src.start) src.start(0); else src.noteOn(0);
      } catch (e) {}
    });
    ['touchstart', 'touchend', 'click', 'keydown'].forEach(function (ev) {
      document.removeEventListener(ev, unlock, true);
    });
  }
  ['touchstart', 'touchend', 'click', 'keydown'].forEach(function (ev) {
    document.addEventListener(ev, unlock, true);
  });
})();
