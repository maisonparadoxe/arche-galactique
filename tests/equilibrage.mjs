// Lancer le jeu accéléré (godot --path . -- --test --speed=8), puis : node tests/equilibrage.mjs paikan
// Équilibrage : combats laissés en automatique total (personne ne répare, personne ne vise).
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ship = process.argv[2] || "paikan";
const enemies = (process.argv[3] || "eclaireur,corsaire,corrompu,avatar").split(",");
const ws = new WebSocket("ws://127.0.0.1:9080");
const inbox = [];
ws.onmessage = (e) => inbox.push(JSON.parse(e.data));
await new Promise((r) => (ws.onopen = r));
const send = (o) => ws.send(JSON.stringify(o));
const dbg = async () => { const n = inbox.length; send({ t: "dbg" }); for (let i = 0; i < 60; i++) { await sleep(25); const m = inbox.slice(n).find((m) => m.t === "dbg"); if (m) return m; } };
send({ t: "hello", name: "Bot", token: "bot", color: 0, species: "humain" });
await sleep(300);
send({ t: "dbg_cmd", cmd: "goto", scene: "choix" }); await sleep(400);
send({ t: "vote", id: ship }); await sleep(3500);
for (const e of enemies) {
  send({ t: "dbg_cmd", cmd: "goto", scene: "combat", args: { enemy: e } }); await sleep(300);
  let d = await dbg();
  // la coque est remise au maximum pour chaque essai
  send({ t: "dbg_cmd", cmd: "hull", value: d.run.hull_max }); await sleep(100);
  const t0 = Date.now();
  let last = d;
  while (Date.now() - t0 < 240000) {
    d = await dbg();
    if (d.scene !== "combat" || d.state !== "fight") { if (d.scene !== "combat") d = last; break; }
    last = d;
    await sleep(250);
  }
  const secs = d.time ?? "?";
  console.log(`${ship} vs ${e}: ${d.state ?? d.scene} en ${secs}s, coque ${d.run.hull}/${d.run.hull_max}, incendies ${d.fires ? d.fires.length : "-"}, dégâts ${JSON.stringify(d.sys_damage)}`);
  await sleep(1500);
  send({ t: "dbg_cmd", cmd: "goto", scene: "carte" }); await sleep(300);
}
process.exit(0);
