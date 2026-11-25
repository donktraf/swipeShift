// App-Store-Button: EINZIGE Stelle zum Umstellen.
// Sobald die App live ist, hier den echten Link eintragen, z. B.
//   var APP_STORE_URL = "https://apps.apple.com/app/idXXXXXXXXXX";
// Leer lassen = "Coming soon"-Hinweis ohne Link.
(function () {
  var APP_STORE_URL = "";
  if (!/^https:\/\/apps\.apple\.com\//.test(APP_STORE_URL)) return;
  var slots = document.querySelectorAll("[data-store-badge]");
  for (var i = 0; i < slots.length; i++) {
    var a = document.createElement("a");
    a.className = "store-badge";
    a.href = APP_STORE_URL;
    a.textContent = "Download on the App Store";
    slots[i].replaceWith(a);
  }
})();
