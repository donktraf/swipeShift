const test = require("node:test");
const assert = require("node:assert/strict");
const { isBannedEmailAlias, hashCanonicalEmail, hashAppleSub } = require("./emailBan");

const P1 = Buffer.alloc(32, 1);
const P2 = Buffer.alloc(32, 2);
const now = new Date("2026-11-25T12:00:00Z");

// Minimaler prisma-Stub: users (gebannte Live-Konten) + tombstones, wertet die where-Klauseln wie die Query aus
function stub({ users = [], tombs = [] } = {}) {
  return {
    user: { findFirst: async ({ where }) => users.find((u) => u.emailCanonical === where.emailCanonical && u.bannedAt) ?? null },
    deletedAccount: {
      findFirst: async ({ where }) => tombs.find((t) => {
        const idMatch = where.OR.some((c) => (c.emailCanonicalHash && c.emailCanonicalHash.in.includes(t.emailCanonicalHash)) || (c.appleSubHash && c.appleSubHash.in.includes(t.appleSubHash)));
        const stateOr = where.AND[0].OR;
        const state = (t.bannedAt && stateOr[0]) || (t.suspendedUntil && t.suspendedUntil > stateOr[1].suspendedUntil.gt && stateOr[1]);
        return idMatch && state;
      }) ?? null,
    },
  };
}

test("hashes: aliases share hash, pepper-dependent, no plaintext", () => {
  const h = hashCanonicalEmail("Max.Muster+x@gmail.com", P1);
  assert.equal(h, hashCanonicalEmail("maxmuster@googlemail.com", P1));
  assert.notEqual(h, hashCanonicalEmail("maxmuster@gmail.com", P2));
  assert.match(h, /^[0-9a-f]{64}$/);
  assert.equal(hashCanonicalEmail("", P1), null);
  assert.equal(hashAppleSub("", P1), null);
  assert.notEqual(hashAppleSub("sub1", P1), hashAppleSub("sub1", P2));
});

test("isBannedEmailAlias: tombstone banned / suspended / expired / unbanned", async () => {
  const base = { emailCanonicalHash: hashCanonicalEmail("a.b@gmail.com", P1), appleSubHash: null };
  const run = (t, email = "ab+x@gmail.com", extra = {}) => isBannedEmailAlias(email, { db: stub({ tombs: [t] }), now, pepperList: [P1], ...extra });
  assert.equal(await run({ ...base, bannedAt: now, suspendedUntil: null }), true);
  assert.equal(await run({ ...base, bannedAt: null, suspendedUntil: new Date(+now + 1000) }), true);
  assert.equal(await run({ ...base, bannedAt: null, suspendedUntil: new Date(+now - 1000) }), false);
  assert.equal(await run({ ...base, bannedAt: null, suspendedUntil: null }), false);
  assert.equal(await run({ ...base, bannedAt: now }, "other@gmail.com"), false);
});

test("isBannedEmailAlias: PREV pepper still matches, unknown pepper does not", async () => {
  const t = { emailCanonicalHash: hashCanonicalEmail("x@example.org", P2), appleSubHash: null, bannedAt: now, suspendedUntil: null };
  const db = stub({ tombs: [t] });
  assert.equal(await isBannedEmailAlias("x@example.org", { db, now, pepperList: [P1, P2] }), true);
  assert.equal(await isBannedEmailAlias("x@example.org", { db, now, pepperList: [P1] }), false);
});

test("isBannedEmailAlias: Apple sub of banned tombstone blocks despite different email", async () => {
  const t = { emailCanonicalHash: hashCanonicalEmail("old@example.org", P1), appleSubHash: hashAppleSub("apple-1", P1), bannedAt: now, suspendedUntil: null };
  const db = stub({ tombs: [t] });
  assert.equal(await isBannedEmailAlias("new@example.org", { db, now, pepperList: [P1], appleSub: "apple-1" }), true);
  assert.equal(await isBannedEmailAlias("new@example.org", { db, now, pepperList: [P1], appleSub: "apple-2" }), false);
});

test("isBannedEmailAlias: banned live user alias", async () => {
  const db = stub({ users: [{ emailCanonical: "a@b.de", bannedAt: now }] });
  assert.equal(await isBannedEmailAlias("a@b.de", { db, now, pepperList: [P1] }), true);
});
