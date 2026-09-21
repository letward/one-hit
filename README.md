# ONE-HIT

Simpler, immersiver Arena-Shooter mit Godot 4.7 — **Solo gegen Bots** oder **Online gegen Freunde** (self-hosted ENet-Lobby, bis 8 Spieler).

- First-Person, 6 Waffen (Blaster, Schrot, Railgun, SMG, DMR, LMG)
- Bot-KI mit Wellen-System (Soldaten-Modelle, Heavy- & Runner-Varianten)
- **Realistisch-Modus**: düstere Optik, Detail-Waffen, stärkere Bots
- **Grafik**: prozedurale PBR-Texturen, GI/SSAO/Reflexionen, Filmkorn (Ultra-FX)
- Loot-Boxen, Explosiv-Fässer, Item-Shop, 8 Skins
- Credits, Speicherstand, Statistiken — alles ohne externe Assets

## Start

1. Godot 4.7.x öffnen
2. `project.godot` importieren
3. `F5` (Hauptszene: `scenes/main.tscn`)

## Steuerung

| Taste | Aktion |
|---|---|
| WASD + Maus | Laufen / Zielen |
| Linksklick / Rechtsklick | Schießen / Zielen (ADS) |
| 1–6, Mausrad | Waffe wechseln |
| SHIFT / LEER | Sprint / Springen |
| E / R | Loot öffnen / Nachladen |
| B | Item-Shop (Waffen, Heal, Schild) |
| F3 | FPS-Anzeige |
| F11 | Vollbild an/aus |
| ESC | Pause |

Das Menü hat drei Tabs: **Spielen** (Solo/Online + Start), **Pilot**
(Name, Sound, FOV, Skins, Statistiken) und **Grafik** (Auflösung bis
Full HD, Vollbild, MSAA, Glow, Schatten, VSync).

## Online spielen

Einer klickt **Hosten** (Port, Standard 7777), Freunde **Joinen** per IP + Port. Deathmatch bis 10 Kills.

## Neocrom-Server selbst hosten

Echter server-seitiger Login (CromID + E-Mail + Passwort, scrypt-Hash,
Token-Sessions), CromCloud, Tagesbonus, Rangliste, Friends, Einladungen,
Serverliste. Zero-Dependency — nur Node.js ≥ 22 nötig:

```
cd server
node neocrom-server.js   # PORT=8080, DB: neocrom.db (wird angelegt)
```

Im Spiel (Overlay [F4] → API-URL) auf `http://SERVER-IP:8080/api/v1`
zeigen. Fürs Internet: Port freigeben / Reverse-Proxy mit HTTPS davor.

## Neocrom (CromID · CromCloud · Rangliste)

Zum Spielen meldest du dich mit deiner **CromID** an. Alle Stats
(Credits, Kills, Wellen, Skins) werden in der **CromCloud** gespeichert,
es gibt einen **Tagesbonus (+100 ⚙)** und eine **Rangliste by Neocrom**
im Menü. Ohne Verbindung läuft das Spiel als Offline-Sitzung weiter und
synchronisiert später. Client: `scripts/neocrom_api.gd`, Basis-URL
`https://neocrom.pro/api/v1` (REST-Vertrag steht als Kommentar im File).

**Overlay [F4]** — überall verfügbar: Account mit Profilbild, Friends
einladen (Self-hosted per IP/Port oder offizielle Neocrom-Server),
Einladungen annehmen, Self-Hosting per Klick.

## Struktur

```
scenes/   main.tscn  arena.tscn  player.tscn  bot.tscn  loot_box.tscn
scripts/  game.gd  player.gd  bot.gd  hud.gd  shop.gd  main_menu.gd
          weapon_defs.gd  skin_defs.gd
          Autoloads: game_config.gd (GameConfig)  audio_manager.gd (AudioManager)
                     network_manager.gd (NetworkManager)  save_manager.gd (Save)
```
Schrott (⚙) gibt's pro Kill (+25), Welle (+50) und Loot (+75). Der Speicherstand
liegt unter `user://onehit_save.cfg`.
