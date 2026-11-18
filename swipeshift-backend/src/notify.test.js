const { test } = require("node:test");
const assert = require("node:assert/strict");
const { createNotifier } = require("./notify");

const silent = { log() {}, error() {} };
const baseUser = { id: "u", email: "u@x.com", emailVerifiedAt: new Date(), settings: null, timeZone: "UTC", pausedAt: null };
const event = { category: "jobActivity", push: { title: "t", body: "b", data: {} }, email: { subject: "s", html: "<p>h</p>", text: "h" } };

function setup(user, { mailFails = false, pushFails = false, devices = [{ token: "tok", environment: "sandbox" }], now } = {}) {
  const calls = { mail: [], push: [] };
  const notify = createNotifier({
    loadUser: async () => user,
    loadDevices: async () => devices,
    sendMail: async (m) => { if (mailFails) throw new Error("smtp"); calls.mail.push(m); },
    sendPush: async (d, m) => { if (pushFails) throw new Error("apns"); calls.push.push({ d, m }); },
    log: silent,
    now: now ? () => now : undefined,
  });
  return { notify, calls };
}

test("Defaults jobActivity: Mail und Push", async () => {
  const { notify, calls } = setup(baseUser);
  assert.deepEqual(await notify("u", event), { email: true, push: true });
  assert.equal(calls.mail[0].to, "u@x.com");
  assert.equal(calls.push[0].d[0].token, "tok");
});

test("Kanal aus → nicht gesendet; unverifizierte Mail → keine Mail", async () => {
  const off = setup({ ...baseUser, settings: { notifications: { jobActivity: { push: false, email: false } } } });
  assert.deepEqual(await off.notify("u", event), { email: false, push: false });
  const unv = setup({ ...baseUser, emailVerifiedAt: null });
  assert.equal((await unv.notify("u", event)).email, false);
  assert.equal(unv.calls.mail.length, 0);
});

test("Ruhezeiten: nur Push stumm, Mail geht raus", async () => {
  const user = { ...baseUser, settings: { quietHours: { enabled: true, from: "22:00", to: "07:00" } } };
  const { notify, calls } = setup(user, { now: new Date("2026-11-18T23:30:00Z") });
  assert.deepEqual(await notify("u", event), { email: true, push: false });
  assert.equal(calls.push.length, 0);
});

test("pausiertes Konto: jobActivity/messages nein, account ja", async () => {
  const user = { ...baseUser, pausedAt: new Date(), settings: { notifications: { account: { push: true, email: true } } } };
  const a = setup(user);
  assert.deepEqual(await a.notify("u", event), { email: false, push: false });
  const b = setup(user);
  assert.deepEqual(await b.notify("u", { ...event, category: "account" }), { email: false, push: false }); // z.B. Review
  const c = setup(user);
  assert.deepEqual(await c.notify("u", { ...event, category: "account", pausedOk: true }), { email: true, push: true });
});

test("Fehler beim Senden werfen nie; anderer Kanal laeuft weiter", async () => {
  const m = setup(baseUser, { mailFails: true });
  assert.deepEqual(await m.notify("u", event), { email: false, push: true });
  const p = setup(baseUser, { pushFails: true });
  assert.deepEqual(await p.notify("u", event), { email: true, push: false });
});

test("loadUser wirft / User fehlt / keine Geraete → kein Throw", async () => {
  const n1 = createNotifier({ loadUser: async () => { throw new Error("db"); }, loadDevices: async () => [], sendMail: async () => {}, sendPush: async () => {}, log: silent });
  assert.equal((await n1("u", event)).error, true);
  const n2 = setup(null);
  assert.deepEqual(await n2.notify("u", event), { email: false, push: false });
  const n3 = setup(baseUser, { devices: [] });
  assert.equal((await n3.notify("u", event)).push, false);
  assert.deepEqual(await n3.notify(null, event), { email: false, push: false });
});

test("Push-Daten tragen die Empfaenger-ID", async () => {
  const { notify, calls } = setup(baseUser);
  await notify("u", event);
  assert.equal(calls.push[0].m.data.userId, "u");
});

test("Event als Builder bekommt den User (Zeitzone)", async () => {
  const { notify, calls } = setup({ ...baseUser, timeZone: "Europe/Berlin" });
  await notify("u", (u) => ({ ...event, push: { ...event.push, body: u.timeZone } }));
  assert.equal(calls.push[0].m.body, "Europe/Berlin");
});

test("nur E-Mail-Event (ohne push) / nur Push-Event", async () => {
  const { notify, calls } = setup(baseUser);
  await notify("u", { category: "jobActivity", email: event.email });
  assert.equal(calls.push.length, 0);
  await notify("u", { category: "jobActivity", push: event.push });
  assert.equal(calls.mail.length, 1);
});
