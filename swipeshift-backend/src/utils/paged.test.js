const { test } = require("node:test");
const assert = require("node:assert/strict");
const { collectPaged } = require("./paged");

const rows = Array.from({ length: 25 }, (_, i) => ({ id: `r${String(i).padStart(2, "0")}`, n: i }));
const fetchPage = async (cursor, take) => {
  const start = cursor ? rows.findIndex((r) => r.id === cursor) + 1 : 0;
  return rows.slice(start, start + take);
};

test("collectPaged: sammelt ueber mehrere Seiten bis limit", async () => {
  const r = await collectPaged({ fetchPage, accept: (x) => x.n % 5 === 0, limit: 3, pageSize: 4 });
  assert.deepEqual(r.map((x) => x.n), [0, 5, 10]);
});

test("collectPaged: weniger Treffer als limit, Ende der Daten, maxPages", async () => {
  assert.equal((await collectPaged({ fetchPage, accept: (x) => x.n > 22, limit: 10, pageSize: 4 })).length, 2);
  assert.equal((await collectPaged({ fetchPage, accept: () => false, limit: 5, pageSize: 4, maxPages: 2 })).length, 0);
});
