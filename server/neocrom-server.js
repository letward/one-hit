// ============================================================
// Neocrom Game Backend — echter server-seitiger Login (CromID)
// Zero-Dependency: nur Node.js >= 22 (node:http + node:sqlite)
// Start:  node neocrom-server.js   (ENV: PORT, default 8080)
// Daten:  ./neocrom.db (SQLite, wird automatisch angelegt)
// ============================================================
import { createServer } from "node:http";
import { DatabaseSync } from "node:sqlite";
import { randomBytes, scryptSync, timingSafeEqual } from "node:crypto";

const PORT = parseInt(process.env.PORT || "8080", 10);
const BONUS_AMOUNT = 100;
const TOKEN_DAYS = 30;
const SERVER_TTL_S = 90;

const db = new DatabaseSync("neocrom.db");
db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY,
  crom_id TEXT UNIQUE NOT NULL COLLATE NOCASE,
  email TEXT UNIQUE NOT NULL COLLATE NOCASE,
  pass_hash TEXT NOT NULL,
  pass_salt TEXT NOT NULL,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_seen INTEGER NOT NULL DEFAULT 0,
  last_bonus_day TEXT NOT NULL DEFAULT '',
  credits INTEGER NOT NULL DEFAULT 0,
  kills INTEGER NOT NULL DEFAULT 0,
  deaths INTEGER NOT NULL DEFAULT 0,
  games INTEGER NOT NULL DEFAULT 0,
  best_wave INTEGER NOT NULL DEFAULT 0,
  skins_owned TEXT NOT NULL DEFAULT '["standard"]',
  skin_selected TEXT NOT NULL DEFAULT 'standard'
);
CREATE TABLE IF NOT EXISTS tokens (
  token TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS friendships (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(user_id, friend_id)
);
CREATE TABLE IF NOT EXISTS invites (
  id INTEGER PRIMARY KEY,
  from_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  game TEXT NOT NULL DEFAULT 'one-hit',
  join_ip TEXT NOT NULL DEFAULT '',
  join_port INTEGER NOT NULL DEFAULT 7777,
  seed INTEGER NOT NULL DEFAULT 0,
  server_id TEXT NOT NULL DEFAULT '',
  server_name TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS servers (
  id INTEGER PRIMARY KEY,
  owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  game TEXT NOT NULL DEFAULT 'one-hit',
  name TEXT NOT NULL,
  ip TEXT NOT NULL,
  port INTEGER NOT NULL DEFAULT 7777,
  seed INTEGER NOT NULL DEFAULT 0,
  players INTEGER NOT NULL DEFAULT 1,
  max_players INTEGER NOT NULL DEFAULT 8,
  updated_at INTEGER NOT NULL,
  UNIQUE(owner_id, game)
);
`);

// ---------- Helpers ----------
const json = (res, code, obj) => {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "GET, POST, PUT, OPTIONS",
  });
  res.end(body);
};
const ok = (res, data = {}) => json(res, 200, { ok: true, ...data });
const fail = (res, code, error) => json(res, code, { ok: false, error });

const RE_CROM = /^[A-Za-z0-9_]{3,16}$/;
const RE_MAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const nowS = () => Math.floor(Date.now() / 1000);

function hashPw(pw, salt) {
  return scryptSync(pw, salt, 64).toString("hex");
}
function newToken(userId) {
  const t = randomBytes(32).toString("hex");
  db.prepare("INSERT INTO tokens (token, user_id, expires_at) VALUES (?, ?, ?)")
    .run(t, userId, nowS() + TOKEN_DAYS * 86400);
  return t;
}
function authUser(req) {
  const h = req.headers["authorization"] || "";
  const m = /^Bearer\s+(.+)$/.exec(h);
  if (!m) return null;
  const row = db.prepare(
    "SELECT u.* FROM tokens t JOIN users u ON u.id = t.user_id WHERE t.token = ? AND t.expires_at > ?"
  ).get(m[1], nowS());
  if (!row) return null;
  db.prepare("UPDATE users SET last_seen = ? WHERE id = ?").run(nowS(), row.id);
  return row;
}
function publicStats(u) {
  return {
    credits: u.credits, kills: u.kills, deaths: u.deaths, games: u.games,
    best_wave: u.best_wave,
    skins_owned: JSON.parse(u.skins_owned || '["standard"]'),
    skin_selected: u.skin_selected,
  };
}

// Simpler In-Memory Rate-Limiter (pro IP)
const hits = new Map();
function limited(ip, max, windowS) {
  const t = Date.now();
  let arr = hits.get(ip) || [];
  arr = arr.filter((x) => t - x < windowS * 1000);
  arr.push(t);
  hits.set(ip, arr);
  return arr.length > max;
}

// ---------- Router ----------
const server = createServer((req, res) => {
  const url = new URL(req.url || "/", "http://x");
  const ip = req.socket.remoteAddress || "?";
  if (req.method === "OPTIONS") return json(res, 204, {});
  const isAuth = url.pathname.startsWith("/api/v1/auth/");
  if (limited(ip, isAuth ? 30 : 300, 60)) return fail(res, 429, "Zu viele Anfragen.");

  let raw = "";
  req.on("data", (c) => {
    raw += c;
    if (raw.length > 1024 * 1024) req.destroy();
  });
  req.on("end", () => {
    let body = {};
    if (raw) {
      try { body = JSON.parse(raw); }
      catch { return fail(res, 400, "Ungültiges JSON."); }
    }
    try {
      route(req, res, url, body);
    } catch (e) {
      console.error("ERR", e);
      fail(res, 500, "Serverfehler.");
    }
  });
});

function route(req, res, url, b) {
  const p = url.pathname;
  const M = req.method;

  if (M === "GET" && p === "/") return ok(res, { service: "neocrom", game: "one-hit" });
  if (M === "GET" && p === "/api/v1/status") {
    const n = db.prepare("SELECT COUNT(*) AS c FROM users").get().c;
    return ok(res, { online: true, users: n });
  }

  // ----- Auth -----
  if (M === "POST" && p === "/api/v1/auth/register") {
    const cid = String(b.crom_id || "").trim();
    const email = String(b.email || "").trim();
    const pw = String(b.password || "");
    if (!RE_CROM.test(cid)) return fail(res, 400, "CromID: 3-16 Zeichen (A-Z, 0-9, _).");
    if (!RE_MAIL.test(email) || email.length > 254) return fail(res, 400, "Ungültige E-Mail.");
    if (pw.length < 8 || pw.length > 128) return fail(res, 400, "Passwort: min. 8 Zeichen.");
    const taken = db.prepare("SELECT id FROM users WHERE crom_id = ? OR email = ?").get(cid, email);
    if (taken) return fail(res, 409, "CromID oder E-Mail bereits vergeben.");
    const salt = randomBytes(16).toString("hex");
    const r = db.prepare(
      "INSERT INTO users (crom_id, email, pass_hash, pass_salt, name, created_at, last_seen) VALUES (?, ?, ?, ?, ?, ?, ?)"
    ).run(cid, email, hashPw(pw, salt), salt, cid, nowS(), nowS());
    const token = newToken(Number(r.lastInsertRowid));
    return ok(res, { token, name: cid });
  }

  if (M === "POST" && p === "/api/v1/auth/login") {
    const id = String(b.crom_id || "").trim();
    const pw = String(b.password || "");
    if (!id || !pw) return fail(res, 400, "CromID und Passwort nötig.");
    const u = db.prepare("SELECT * FROM users WHERE crom_id = ? OR email = ?").get(id, id);
    if (!u) return fail(res, 401, "Unbekannte CromID / E-Mail.");
    const a = Buffer.from(u.pass_hash, "hex");
    const c = Buffer.from(hashPw(pw, u.pass_salt), "hex");
    if (a.length !== c.length || !timingSafeEqual(a, c))
      return fail(res, 401, "Falsches Passwort.");
    db.prepare("UPDATE users SET last_seen = ? WHERE id = ?").run(nowS(), u.id);
    return ok(res, { token: newToken(u.id), name: u.name });
  }

  const me = authUser(req);
  const needAuth = (M === "GET" && p === "/api/v1/users/me")
    || p.startsWith("/api/v1/cloud/") || p.startsWith("/api/v1/friends/")
    || p.startsWith("/api/v1/invites/");
  if (needAuth && !me) return fail(res, 401, "Login nötig.");

  // ----- Profil -----
  if (M === "GET" && p === "/api/v1/users/me")
    return ok(res, { name: me.name, email: me.email, avatar_url: "" });

  // ----- Cloud -----
  if (M === "GET" && p === "/api/v1/cloud/stats")
    return ok(res, { ...publicStats(me), name: me.name });

  if (M === "PUT" && p === "/api/v1/cloud/stats") {
    const owned = new Set(JSON.parse(me.skins_owned || "[]"));
    for (const s of (Array.isArray(b.skins_owned) ? b.skins_owned : []))
      if (typeof s === "string" && s.length < 32) owned.add(s);
    let sel = me.skin_selected;
    if (typeof b.skin_selected === "string" && owned.has(b.skin_selected)) sel = b.skin_selected;
    db.prepare(`UPDATE users SET credits = MAX(credits, ?), kills = MAX(kills, ?),
      deaths = MAX(deaths, ?), games = MAX(games, ?), best_wave = MAX(best_wave, ?),
      skins_owned = ?, skin_selected = ? WHERE id = ?`).run(
      num(b.credits), num(b.kills), num(b.deaths), num(b.games), num(b.best_wave),
      JSON.stringify([...owned]), sel, me.id);
    return ok(res, {});
  }

  if (M === "POST" && p === "/api/v1/cloud/bonus") {
    const day = String(b.day || "");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return fail(res, 400, "Ungültiges Datum.");
    if (me.last_bonus_day === day) return ok(res, { granted: false, amount: 0 });
    db.prepare("UPDATE users SET credits = credits + ?, last_bonus_day = ? WHERE id = ?")
      .run(BONUS_AMOUNT, day, me.id);
    return ok(res, { granted: true, amount: BONUS_AMOUNT });
  }

  // ----- Rangliste -----
  if (M === "GET" && p === "/api/v1/leaderboard") {
    const limit = Math.min(parseInt(url.searchParams.get("limit") || "25", 10) || 25, 100);
    const rows = db.prepare(
      "SELECT name, kills, best_wave, games FROM users ORDER BY kills DESC, best_wave DESC LIMIT ?"
    ).all(limit);
    return ok(res, { entries: rows });
  }
  if (M === "POST" && p === "/api/v1/leaderboard/submit") {
    db.prepare(`UPDATE users SET kills = MAX(kills, ?), best_wave = MAX(best_wave, ?),
      games = MAX(games, ?) WHERE id = ?`).run(num(b.kills), num(b.best_wave), num(b.games), me.id);
    const rank = db.prepare("SELECT COUNT(*) AS c FROM users WHERE kills > (SELECT kills FROM users WHERE id = ?)")
      .get(me.id).c + 1;
    return ok(res, { rank });
  }

  // ----- Freunde -----
  if (M === "GET" && p === "/api/v1/friends") {
    const rows = db.prepare(`SELECT u.crom_id, u.name, u.last_seen FROM friendships f
      JOIN users u ON u.id = f.friend_id WHERE f.user_id = ?`).all(me.id);
    return ok(res, {
      friends: rows.map((r) => ({
        crom_id: r.crom_id, name: r.name,
        online: nowS() - r.last_seen < 120, in_game: false,
      })),
    });
  }
  if (M === "POST" && p === "/api/v1/friends/add") {
    const cid = String(b.crom_id || "").trim();
    const f = db.prepare("SELECT id FROM users WHERE crom_id = ?").get(cid);
    if (!f) return fail(res, 404, "CromID unbekannt.");
    if (f.id === me.id) return fail(res, 400, "Das bist du selbst.");
    db.prepare("INSERT OR IGNORE INTO friendships (user_id, friend_id) VALUES (?, ?)").run(me.id, f.id);
    return ok(res, {});
  }
  if (M === "POST" && p === "/api/v1/friends/invite") {
    const cid = String(b.to || "").trim();
    const f = db.prepare("SELECT id FROM users WHERE crom_id = ?").get(cid);
    if (!f) return fail(res, 404, "CromID unbekannt.");
    const r = db.prepare(`INSERT INTO invites (from_id, to_id, game, join_ip, join_port, seed, server_id, server_name, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)`).run(me.id, f.id,
      String(b.game || "one-hit"), String(b.join_ip || ""), num(b.join_port, 7777),
      num(b.seed), String(b.server_id || ""), String(b.server_name || ""), nowS());
    return ok(res, { invite_id: Number(r.lastInsertRowid) });
  }

  // ----- Einladungen -----
  if (M === "GET" && p === "/api/v1/invites") {
    const rows = db.prepare(`SELECT i.id, u.crom_id AS from_id, u.name AS from_name, i.game,
      i.join_ip, i.join_port, i.seed, i.server_id, i.server_name FROM invites i
      JOIN users u ON u.id = i.from_id WHERE i.to_id = ? AND i.status = 'pending'
      ORDER BY i.id DESC LIMIT 20`).all(me.id);
    return ok(res, {
      invites: rows.map((r) => ({
        id: r.id, from: r.from_id, from_name: r.from_name, game: r.game,
        join_ip: r.join_ip, join_port: r.join_port, seed: r.seed,
        server_id: r.server_id, server_name: r.server_name,
      })),
    });
  }
  const mInv = /^\/api\/v1\/invites\/(\d+)\/(accept|decline)$/.exec(p);
  if (M === "POST" && mInv) {
    const inv = db.prepare("SELECT * FROM invites WHERE id = ? AND to_id = ?").get(mInv[1], me.id);
    if (!inv) return fail(res, 404, "Einladung unbekannt.");
    db.prepare("UPDATE invites SET status = ? WHERE id = ?").run(mInv[2] === "accept" ? "accepted" : "declined", inv.id);
    return ok(res, {});
  }

  // ----- Serverliste -----
  if (M === "GET" && p === "/api/v1/servers") {
    const game = url.searchParams.get("game") || "one-hit";
    const rows = db.prepare(`SELECT s.id AS sid, s.name, s.ip, s.port, s.seed, s.players, s.max_players,
      u.name AS owner FROM servers s JOIN users u ON u.id = s.owner_id
      WHERE s.game = ? AND s.updated_at > ? ORDER BY s.updated_at DESC LIMIT 50`)
      .all(game, nowS() - SERVER_TTL_S);
    return ok(res, {
      servers: rows.map((r) => ({
        id: "srv-" + r.sid, name: r.name + " (von " + r.owner + ")", ip: r.ip,
        port: r.port, seed: r.seed, players: r.players, max_players: r.max_players,
      })),
    });
  }
  if (M === "POST" && p === "/api/v1/servers/register") {
    const name = String(b.name || (me.name + "s Lobby")).slice(0, 40);
    db.prepare(`INSERT INTO servers (owner_id, game, name, ip, port, seed, players, max_players, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(owner_id, game) DO UPDATE SET name = excluded.name, ip = excluded.ip,
      port = excluded.port, seed = excluded.seed, players = excluded.players,
      max_players = excluded.max_players, updated_at = excluded.updated_at`).run(
      me.id, String(b.game || "one-hit"), name, String(b.ip || ""), num(b.port, 7777),
      num(b.seed), num(b.players, 1), num(b.max_players, 8), nowS());
    return ok(res, {});
  }

  return fail(res, 404, "Unbekannt.");
}

function num(v, d = 0) {
  const n = parseInt(v, 10);
  return Number.isFinite(n) && n >= 0 && n < 1000000000 ? n : d;
}

server.listen(PORT, () => console.log(`Neocrom backend läuft auf Port ${PORT}`));
