# ONE-HIT

Simpler, immersiver Arena-Shooter mit Godot 4.7 — **Solo gegen Bots** oder **Online gegen Freunde** (self-hosted ENet-Lobby, bis 8 Spieler).

- First-Person, 6 Waffen (Blaster, Schrot, Railgun, SMG, DMR, LMG)
- Bot-KI mit Wellen-System (Soldaten-Modelle, Heavy- & Runner-Varianten)
- **Realistisch-Modus**: düstere Optik, Detail-Waffen, stärkere Bots
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
