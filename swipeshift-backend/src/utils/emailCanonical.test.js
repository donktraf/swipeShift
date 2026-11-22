const test = require("node:test");
const assert = require("node:assert/strict");
const { canonicalEmail } = require("./emailCanonical");

test("canonicalEmail: lowercase + trim", () => {
  assert.equal(canonicalEmail("  Foo@Example.COM \n"), "foo@example.com");
});

test("canonicalEmail: Gmail-Punkte und +tag fallen weg, googlemail wird gmail", () => {
  assert.equal(canonicalEmail("Kevin.Owusu+spam@Gmail.com"), "kevinowusu@gmail.com");
  assert.equal(canonicalEmail("k.e.v.i.n@googlemail.com"), "kevin@gmail.com");
  assert.equal(canonicalEmail("kevin+a+b@gmail.com"), "kevin@gmail.com");
  assert.equal(canonicalEmail("kevin@googlemail.com"), canonicalEmail("ke.vin+x@gmail.com"));
});

test("canonicalEmail: andere Domains behalten Punkte, nur +tag faellt weg", () => {
  assert.equal(canonicalEmail("first.last+job@example.com"), "first.last@example.com");
  assert.equal(canonicalEmail("a.b@outlook.com"), "a.b@outlook.com");
  assert.equal(canonicalEmail("a@gmail.com.evil.com"), "a@gmail.com.evil.com"); // Subdomain-/Suffix-Tricks sind kein Gmail
});

test("canonicalEmail: Randfaelle", () => {
  assert.equal(canonicalEmail("+tag@example.com"), "+tag@example.com");   // leerer Local-Part nach +tag → unveraendert
  assert.equal(canonicalEmail("...@gmail.com"), "...@gmail.com");          // nur Punkte → nicht leer machen
  assert.equal(canonicalEmail("no-at-sign"), "no-at-sign");
  assert.equal(canonicalEmail("trailing@"), "trailing@");
  assert.equal(canonicalEmail(undefined), "");
  assert.equal(canonicalEmail(5), "");
  assert.equal(canonicalEmail("a@b@gmail.com"), "a@b@gmail.com"); // letztes @ trennt
});
