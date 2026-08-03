// src/uploads-path.test.js
// Regressionstest fuer den Bug: express.static-Mount fuer "/uploads" in index.js zeigte
// auf ein anderes Verzeichnis als das multer diskStorage-Ziel in routes.upload.js
// (hochgeladene Dateien wurden gespeichert, waren aber per HTTP nicht abrufbar -> 404).
//
// Wichtig: index.js darf hier NICHT per require() geladen werden, da es app.listen()
// aufruft und den Testlauf haengen laesst. Stattdessen wird die relevante
// path.join(__dirname, ...)-Ausdruck-Definition aus dem Quelltext extrahiert und
// isoliert (mit dem jeweils korrekten __dirname der Ursprungsdatei) ausgewertet.

const fs = require("fs");
const path = require("path");
const { test } = require("node:test");
const assert = require("node:assert/strict");

// Extrahiert einen `path.join(__dirname, ...)`-Ausdruck aus Quelltext anhand eines Regex
// mit genau einer Capture-Gruppe, die den vollstaendigen path.join(...)-Aufruf enthaelt.
function extractPathJoinExpression(source, regex, label) {
  const match = source.match(regex);
  assert.ok(match, `Konnte ${label} nicht im Quelltext finden`);
  return match[1];
}

// Wertet einen `path.join(__dirname, "a", "b")`-Ausdruck sicher aus, wobei __dirname
// an das Verzeichnis der jeweiligen Ursprungsdatei gebunden wird. Es sind ausschliesslich
// path.join(...) mit __dirname und String-Literalen als Argumente erlaubt.
function resolvePathJoinExpression(expression, dirnameForFile) {
  assert.match(
    expression,
    /^path\.join\(__dirname(?:,\s*"[^"]*")*\)$/,
    `Unerwartetes Format fuer path.join-Ausdruck: ${expression}`
  );
  const evaluate = new Function("path", "__dirname", `return ${expression};`);
  return evaluate(path, dirnameForFile);
}

test("multer diskStorage destination (routes.upload.js) und express.static Mount (index.js) fuer /uploads loesen auf denselben absoluten Pfad auf", () => {
  const indexPath = path.join(__dirname, "index.js");
  const uploadRoutesPath = path.join(__dirname, "routes.upload.js");

  const indexSource = fs.readFileSync(indexPath, "utf8");
  const uploadRoutesSource = fs.readFileSync(uploadRoutesPath, "utf8");

  const staticMountExpr = extractPathJoinExpression(
    indexSource,
    /app\.use\(\s*"\/uploads",\s*express\.static\((path\.join\([^)]*\))\)\s*\)/,
    "express.static(...) Mount-Pfad in index.js"
  );

  const multerDestExpr = extractPathJoinExpression(
    uploadRoutesSource,
    /const\s+uploadDir\s*=\s*(path\.join\([^)]*\));/,
    "uploadDir-Definition in routes.upload.js"
  );

  const staticMountResolved = resolvePathJoinExpression(
    staticMountExpr,
    path.dirname(indexPath)
  );
  const multerDestResolved = resolvePathJoinExpression(
    multerDestExpr,
    path.dirname(uploadRoutesPath)
  );

  assert.equal(
    staticMountResolved,
    multerDestResolved,
    `express.static Mount (${staticMountResolved}) und multer destination (${multerDestResolved}) muessen identisch sein, sonst sind hochgeladene Dateien per HTTP nicht abrufbar (404)`
  );

  // Zusaetzliche Absicherung: beide muessen im Projekt-Root/uploads liegen (nicht in src/uploads),
  // da genau das die Ursache des urspruenglichen Bugs war.
  const expectedUploadsDir = path.join(__dirname, "..", "uploads");
  assert.equal(staticMountResolved, expectedUploadsDir);
});
