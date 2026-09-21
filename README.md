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

## Neocrom-Integration (echt)

Das Spiel spricht die echte Neocrom-API (`https://neocrom.pro/api`):

- **Login/Register** mit CromID/Handle/E-Mail + Passwort (JWT-Sessions mit
  Refresh), **Launcher-SSO** via `--launcher-token`/`--launcher-user`
- **Zugriff**: Preview gratis bis **01.10.2026**, exklusiv für eingeloggte
  Members — Start wird ohne Zugriff verweigert
- **CromCloud-Spielstand**, echter **Tagesbonus** (CromCoins + Streak),
  **Rangliste**, **Friends**, **Spiel-Einladungen**, **Lobby-Liste**,
  **Präsenz-Heartbeat**. Offline läuft alles lokal weiter.

Backend-Änderungen (Repo `neocrom`, Branch `feat/one-hit-preview`):
`GET/POST /api/games/*` (Launch-Verify, Access, Scores, Lobbys, Invites),
neue Tabellen (`game_scores`, `game_lobbies`, `game_invites`,
`game_previews`, `games.slug`), OneHit-Seed (Listing + Preview-Fenster),
Artifact-Limit 600 MB für Game-Builds.

**Overlay [F4]** — überall verfügbar: Account mit Profilbild, Friends
einladen, Einladungen annehmen, Self-Hosting per Klick.

## Build & Upload

```
# Windows-Build (Export-Templates nötig)
godot --headless --path . --export-release "Windows" "builds/windows/OneHit.exe"
# Upload ins Neocrom-Store-Backend:
.\tools\upload-build.ps1 -Jwt <JWT> -GameId <ID>   # Version 1.0.0
```

`builds/` enthält `OneHit.exe` (eigenständig, PCK eingebettet),
`manifest.json` (Launcher) und `cover.png` (1200×630 Store-Cover).
Hinweis: Laut Publishing-Guide ist langfristig ein NSIS/MSI-Installer
fällig — für die Preview reicht die portable Exe.

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
