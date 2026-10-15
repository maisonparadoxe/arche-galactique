// Lancer le jeu en mode test (godot --path . -- --test), puis : node tests/equipage.mjs
// Un seul téléphone : changement de personnage, équipage automatique, reconnexion.
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
    send: (o) => ws.readyState === 1 && ws.send(JSON.stringify(o)),
    last: (t) => [...inbox].reverse().find((m) => m.t === t),
    async dbg() { const n = inbox.length; p.send({ t: "dbg" }); for (let i = 0; i < 60; i++) { await sleep(25); const m = inbox.slice(n).find((m) => m.t === "dbg"); if (m) return m; } throw new Error("pas de réponse dbg"); },
    async cmd(o) { p.send({ t: "dbg_cmd", ...o }); await sleep(80); },
    async tp(x, y) { p.send({ t: "dbg_tp", x, y }); await sleep(80); },
  };
  p.timer = setInterval(() => p.send({ t: "in", x: p.x, y: p.y, b: p.b }), 33);
  p.send({ t: "hello", token: "solo-tok", ...profile });
  await sleep(300);
  return p;
}
async function hold(p, b, ms) { p.b = b; await sleep(ms); p.b = N; await sleep(120); }
const Y = [false, false, false, true], A = [true, false, false, false];
async function waitScene(p, name, ms = 15000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const d = await p.dbg(); if (d.scene === name) return d; await sleep(150); }
  throw new Error(`scène attendue ${name}`);
}
async function openRoster(p) { await hold(p, Y, 120); return p.last("layout"); }

let a = await phone({ name: "Pascal", color: 0, species: "humain", ornament: "couronne" });
let d = await a.dbg();
const avatarId = d.me;
check(d.crew.length === 4 && d.crew.filter((c) => c.peer === 0).length === 3, `Académie : 1 joueur, équipage de ${d.crew.length} dont 3 recrues libres`);

// --- Liste de l'équipage et bouton Retour
let lay = await openRoster(a);
check(lay.mode === "equipage" && lay.crew.length === 4, "Y ouvre la liste de l'équipage sur le téléphone");
check(lay.crew.filter((c) => c.status === "toi").length === 1 && lay.crew.find((c) => c.status === "toi").avatar, "son propre personnage est marqué « Toi » et ★");
check(lay.crew.every((c) => c.where !== undefined), `chaque membre indique où il est (${lay.crew.map((c) => c.where).join(", ")})`);
a.send({ t: "act", a: "back" }); await sleep(150);
check(a.last("layout").mode === "base", "Retour : la manette revient");

// --- Touches mises en avant selon l'endroit
await a.tp(500, 640); await sleep(150);
check(a.last("hint") && a.last("hint").hints["0"] === "Lancer", `sur la table de départ, A devient « ${a.last("hint")?.hints["0"]} »`);
await a.tp(500, 300); await sleep(150);
check(a.last("hint") && a.last("hint").hints["1"] === "Réparer", `près de la console de l'atelier, B devient « ${a.last("hint")?.hints["1"]} »`);
await a.tp(500, 530); await sleep(150);
check(a.last("hint") && Object.keys(a.last("hint").hints).length === 0, "loin de tout, aucune touche mise en avant");

// --- Réacteur à deux, tout seul : laisser son avatar au levier A, prendre une recrue
await a.tp(712, 640);
lay = await openRoster(a);
const recruit = lay.crew.find((c) => c.free);
a.send({ t: "act", a: "pick", id: recruit.id }); await sleep(200);
d = await a.dbg();
check(d.me === recruit.id && a.last("layout").mode === "base", `prise de contrôle de ${recruit.name} (${recruit.species_label})`);
check(a.last("controle") && a.last("controle").name === recruit.name && a.last("controle").own === false, "le téléphone affiche le personnage contrôlé");
check(d.crew.find((c) => c.id === avatarId).peer === 0, "l'avatar laissé au levier devient libre");
await a.tp(900, 640); await sleep(150);
check(a.last("hint").hints["0"] === "Levier", "près d'un levier, A devient « Levier »");
await hold(a, A, 2500);
d = await a.dbg();
check(d.done.reacteur >= 1, `réacteur redémarré seul, avec l'avatar resté au levier (${d.done.reacteur})`);
check(d.medals >= 1, `médaille attribuée au joueur (${d.medals})`);

// --- Membre déjà contrôlé : refusé ; reprendre son avatar
lay = await openRoster(a);
a.send({ t: "act", a: "pick", id: avatarId }); await sleep(200);
d = await a.dbg();
check(d.me === avatarId, "on reprend son propre avatar");

// --- Expédition en solo
await a.tp(500, 618);
await hold(a, A, 120);
await waitScene(a, "choix");
a.send({ t: "vote", id: "nautile" });
d = await waitScene(a, "carte", 8000);
check(d.crew.length === 5 && d.me === d.crew.find((c) => c.avatar).id, `Nautile : équipage de ${d.crew.length}, le joueur reprend son avatar`);
const combat = d.choices.find((c) => c.type === "combat");
a.send({ t: "vote", id: String(combat.id) });
d = await waitScene(a, "combat", 8000);
await a.cmd({ cmd: "freeze_enemy" });
d = await a.dbg();
const roomOf = (c) => d.rooms.reduce((best, r) => (Math.hypot(r.x - c.x, r.y - c.y) < Math.hypot(best.x - c.x, best.y - c.y) ? r : best));
const posted = d.crew.filter((c) => !c.avatar).map((c) => roomOf(c).system);
check(posted.includes("armes") && posted.includes("boucliers"), `les recrues sont à leurs postes (${posted.join(", ")})`);
// Réparation automatique par la recrue de la salle des armes
await a.cmd({ cmd: "damage", system: "armes" });
d = await a.dbg();
check(d.sys_damage.armes === 1, "les armes sont endommagées");
let repaired = false;
for (let i = 0; i < 40 && !repaired; i++) { await sleep(300); repaired = (await a.dbg()).sys_damage.armes === 0; }
check(repaired, "la recrue de la salle des armes répare toute seule");
await a.cmd({ cmd: "damage", system: "boucliers" });
const bouc = d.rooms.find((r) => r.id === "boucliers");
await a.tp(bouc.x + 40, bouc.y - 30); await sleep(200);
check(a.last("hint").hints["1"] === "Réparer" || a.last("hint").hints["1"] === "Éteindre", `en combat, dans une salle endommagée, B devient « ${a.last("hint").hints["1"]} »`);
// Incendie dans la salle des boucliers : la recrue l'éteint seule
await a.cmd({ cmd: "fire", room: "boucliers" });
let out = false;
for (let i = 0; i < 60 && !out; i++) { await sleep(300); out = !(await a.dbg()).fires.some((f) => f[2] === "boucliers"); }
check(out, "la recrue des boucliers éteint l'incendie de sa salle");
// Changer de personnage en combat
lay = await openRoster(a);
check(lay.mode === "equipage" && lay.crew.some((c) => c.where === "Armes"), "liste de l'équipage en combat, avec les salles");
const gunnerRecruit = lay.crew.find((c) => c.free && c.where === "Armes");
a.send({ t: "act", a: "pick", id: gunnerRecruit.id }); await sleep(200);
d = await a.dbg();
check(d.me === gunnerRecruit.id, `on prend ${gunnerRecruit.name}, déjà dans la salle des armes`);
await a.tp(d.console_x - 40, d.console_y);
await hold(a, A, 120);
check(a.last("layout").mode === "armes", "et on s'installe directement au poste d'armes");
await hold(a, Y, 120);
check(a.last("layout").mode === "armes", "Y ne fait rien quand on est au poste (il faut le quitter d'abord)");

// --- Déconnexion / reconnexion
clearInterval(a.timer); a.ws.close(); await sleep(400);
a = await phone({ name: "Pascal", color: 0, species: "humain", ornament: "couronne" });
d = await a.dbg();
check(d.me === d.crew.find((c) => c.avatar).id, "après reconnexion, le joueur retrouve son avatar");
check(d.crew.find((c) => c.id === gunnerRecruit.id).peer === 0, "la recrue lâchée reste à bord, libre");

console.log(failures ? `${failures} échec(s)` : "Tout est bon.");
process.exit(failures ? 1 : 0);
