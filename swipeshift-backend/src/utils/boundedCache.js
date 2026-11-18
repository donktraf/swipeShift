// src/utils/boundedCache.js
// Kleine Map mit Obergrenze (aeltester Eintrag wird verdraengt; Map behaelt Einfuegereihenfolge).
// Fuer In-Memory-Drosselungen pro Prozess, damit sie bei vielen Usern nicht unbegrenzt wachsen.

function setBounded(map, key, value, max = 5000) {
  if (map.has(key)) map.delete(key); // ans Ende (zuletzt benutzt)
  map.set(key, value);
  while (map.size > max) map.delete(map.keys().next().value);
  return map;
}

// Zeitzonen-Write nur wenn: noch nichts gespeichert, oder Zone geaendert UND letzter Write >= minIntervalMs her
function shouldWriteTimeZone(entry, zone, now, minIntervalMs = 10 * 60 * 1000) {
  if (!zone) return false;
  if (!entry) return true;
  if (entry.zone === zone) return false;
  return now - entry.at >= minIntervalMs;
}

module.exports = { setBounded, shouldWriteTimeZone };
