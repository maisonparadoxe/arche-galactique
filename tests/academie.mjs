// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/academie.mjs
// Deux faux téléphones jouent toutes les épreuves de l'Académie.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const N = [false, false, false, false];
let failures = 0;
const check = (ok, label) => { console.log(`${ok ? "OK  " : "FAIL"} ${label}`); if (!ok) failures++; };

async function phone(profile) {
  const ws = new WebSocket("ws://127.0.0.1:9080");
  const inbox = [];
  ws.onmessage = (e) => inbox.push(JSON.parse(e.data));
  await new Promise((r) => (ws.onopen = r));
  const p = {
    ws, inbox, x: 0, y: 0, b: N,
    send: (o) => ws.send(JSON.stringify(o)),
    last: (t) => [...inbox].reverse().find((m) => m.t === t),
    async dbg() { const n = inbox.length; p.send({ t: "dbg" }); for (let i = 0; i < 40; i++) { await sleep(25); const m = inbox.slice(n).find((m) => m.t === "dbg"); if (m) return m; } },
    async tp(x, y) { p.send({ t: "dbg_tp", x, y }); await sleep(80); },
  };
  setInterval(() => p.send({ t: "in", x: p.x, y: p.y, b: p.b }), 33);
  p.send({ t: "hello", token: profile.name + "-tok", ...profile });
  await sleep(250);
  return p;
}
async function hold(p, b, ms) { p.b = b; await sleep(ms); p.b = N; await sleep(120); }

const a = await phone({ name: "Éléa", color: 1, species: "salamandrin", ornament: "fleur" });
const b = await phone({ name: "Païkan", color: 1, species: "humain", ornament: "couronne" });
const wa = a.last("welcome"), wb = b.last("welcome");
check(wa.slot === 1 && wa.species === "salamandrin", `Éléa a la couleur demandée et son espèce (${wa.slot}, ${wa.species})`);
check(wb.slot !== 1 && b.last("toast"), `Païkan reçoit une autre couleur et un message (${wb.slot})`);

// Murs : avancer vers la droite depuis la salle des machines, hors de la porte -> bloqué
await a.tp(300, 200); a.x = 1; await sleep(600); a.x = 0;
let d = await a.dbg();
check(d.x < 347 - 18, `le mur arrête le joueur (x = ${d.x.toFixed(0)})`);
// Par la porte (y = 292) -> on passe
await a.tp(300, 292); a.x = 1; await sleep(500); a.x = 0;
d = await a.dbg();
check(d.x > 360, `la porte laisse passer (x = ${d.x.toFixed(0)})`);

// Feu
d = await a.dbg();
await a.tp(d.fire_x - 30, d.fire_y);
await hold(a, [false, true, false, false], 2200);
d = await a.dbg();
check(d.done.feu === 1 && a.last("medal"), `feu éteint par la Salamandrine (${d.done.feu})`);

// Réparation (humain : deux fois plus vite, < 2,5 s)
await b.tp(500, 300);
await hold(b, [false, true, false, false], 2400);
d = await b.dbg();
check(d.done.repa === 1, `atelier réparé par l'Humain (${d.done.repa})`);

// Cellule d'énergie
await a.tp(110, 600);
await hold(a, [false, false, true, false], 100);
d = await a.dbg();
check(d.carrying, "cellule prise à la soute");
await a.tp(890, 520);
await hold(a, [false, false, true, false], 100);
d = await a.dbg();
check(!d.carrying && d.done.cellule === 1, `cellule livrée au socle (${d.done.cellule})`);

// Réacteur à deux
await a.tp(712, 610); await b.tp(900, 610);
a.b = [true, false, false, false]; await sleep(1000);
d = await a.dbg();
check(d.done.reacteur === 0, "un seul levier ne suffit pas");
b.b = [true, false, false, false]; await sleep(2400);
a.b = N; b.b = N; await sleep(150);
d = await a.dbg();
check(d.done.reacteur === 1, `réacteur redémarré à deux (${d.done.reacteur})`);

// Stand de tir
await b.tp(690, 292);
await hold(b, [true, false, false, false], 100);
check(b.last("layout").mode === "armes", "la manette passe en mode poste de tir");
for (let shot = 0; shot < 60; shot++) {
  d = await b.dbg();
  const alive = d.targets.filter((t) => t[2]);
  if (!alive.length) break;
  const [tx, ty] = alive[0];
  const dx = tx - d.cross_x, dy = ty - d.cross_y, dist = Math.hypot(dx, dy);
  if (dist < 14) { b.x = 0; b.y = 0; b.send({ t: "act", a: "fire" }); await sleep(60); continue; }
  const k = Math.min(1, dist / 60);
  b.x = dx / dist * k; b.y = dy / dist * k; await sleep(50);
}
b.x = 0; b.y = 0;
d = await b.dbg();
check(d.done.tir === 1, `trois cibles abattues (${d.done.tir})`);
b.send({ t: "act", a: "quit" }); await sleep(150);
check(b.last("layout").mode === "base", "retour à la manette de base");

const da = await a.dbg(), db = await b.dbg();
check(da.medals === 3 && db.medals === 3, `médailles : Éléa ${da.medals}, Païkan ${db.medals}`);
console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
