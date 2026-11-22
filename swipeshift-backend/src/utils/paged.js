// src/utils/paged.js
// Stabil sortierte Seiten (Cursor auf id) durchlaufen und im Speicher filtern, bis `limit` Treffer da sind.
// Fuer Scheduler-Abfragen, bei denen SQL nur grob vorfiltert (positive Klauseln) und die genaue Pruefung
// pro Bewerbung im Speicher passiert — ohne dass nicht passende Zeilen die ersten `take` Zeilen belegen.
//   fetchPage(cursorId | null, take) → Zeilen { id, ... } in stabiler Reihenfolge
//   accept(row) → true/Wert; Treffer werden gesammelt (Rueckgabe: Zeilen)
async function collectPaged({ fetchPage, accept, limit, pageSize = limit, maxPages = 20 }) {
  const out = [];
  let cursor = null;
  for (let page = 0; page < maxPages && out.length < limit; page += 1) {
    const rows = await fetchPage(cursor, pageSize);
    for (const row of rows) {
      if (accept(row)) out.push(row);
      if (out.length >= limit) break;
    }
    if (rows.length < pageSize) break;
    cursor = rows[rows.length - 1].id;
  }
  return out;
}

module.exports = { collectPaged };
