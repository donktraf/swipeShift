// Liest die Job-ID aus /jobs/<id> und setzt den Deep Link swipeshift://job/<id>.
// Strikte Validierung: nur [A-Za-z0-9-]; sonst bleibt der Button ohne Link versteckt.
(function () {
  var m = /^\/jobs\/([A-Za-z0-9-]{1,64})\/?$/.exec(window.location.pathname);
  var btn = document.getElementById("open-app");
  var hint = document.getElementById("open-app-hint");
  if (!btn) return;
  if (m) {
    btn.href = "swipeshift://job/" + m[1];
    btn.hidden = false;
    if (hint) hint.hidden = true;
  }
})();
