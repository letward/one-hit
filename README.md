# ONE-HIT

Simpler, immersiver Arena-Shooter mit Godot 4.7 — **Solo gegen Bots** oder **Online gegen Freunde** (self-hosted ENet-Lobby, bis 8 Spieler).

- First-Person, 6 Waffen (Blaster, Schrot, Railgun, SMG, DMR, LMG)
- Bot-KI mit Wellen-System, Loot-Boxen, Item-Shop, Skins
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
| B | Item-Shop |
| F3 | FPS-Anzeige |
| ESC | Pause |

## Online spielen

Einer klickt **Hosten** (Port, Standard 7777), Freunde **Joinen** per IP + Port. Deathmatch bis 10 Kills.

## Struktur

```
scenes/   main.tscn  arena.tscn  player.tscn  bot.tscn  loot_box.tscn
scripts/  game.gd  player.gd  bot.gd  hud.gd  shop.gd  main_menu.gd
          weapon_defs.gd  skin_defs.gd  save_manager.gd (Autoload: Save)
          game_config.gd  audio_manager.gd  network_manager.gd (Autoloads)
```
