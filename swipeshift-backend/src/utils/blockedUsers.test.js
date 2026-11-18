const { test } = require("node:test");
const assert = require("node:assert/strict");
const { describeBlockedUser, buildBlockedList } = require("./blockedUsers");

test("describeBlockedUser: employer nutzt Firmenname + Logo", () => {
  const r = describeBlockedUser({ role: "employer", firstName: "A", lastName: "B" },
    { companyName: " Acme ", companyLogoUrl: "http://x/l.png" }, null);
  assert.deepEqual(r, { role: "employer", name: "Acme", photoUrl: "http://x/l.png" });
});

test("describeBlockedUser: worker nutzt vollen Namen + Foto", () => {
  const r = describeBlockedUser({ role: "worker", firstName: "Max", lastName: "Muster" }, null, { profilePhotoUrl: "p.png" });
  assert.deepEqual(r, { role: "worker", name: "Max Muster", photoUrl: "p.png" });
});

test("describeBlockedUser: Fallbacks ohne Daten", () => {
  assert.deepEqual(describeBlockedUser({}, null, null), { role: "worker", name: "User", photoUrl: null });
  assert.equal(describeBlockedUser({ role: "employer", firstName: "Eva" }, { companyName: "" }, null).name, "Eva");
});

test("buildBlockedList: mappt Reihenfolge, Rollen und Fotos", () => {
  const d = new Date();
  const list = buildBlockedList(
    [{ blockedId: "u1", createdAt: d }, { blockedId: "u2", createdAt: d }, { blockedId: "gone", createdAt: d }],
    [{ id: "u1", role: "worker", firstName: "Max", lastName: "M" }, { id: "u2", role: "employer" }],
    [{ userId: "u2", companyName: "Acme", companyLogoUrl: null }],
    [{ userId: "u1", profilePhotoUrl: "p" }],
  );
  assert.deepEqual(list.map(x => [x.userId, x.role, x.name, x.photoUrl]),
    [["u1", "worker", "Max M", "p"], ["u2", "employer", "Acme", null], ["gone", "worker", "User", null]]);
  assert.equal(list[0].createdAt, d);
});
