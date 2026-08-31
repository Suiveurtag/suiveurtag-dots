# Serpantinum V2 — référence locale pour les futurs addons

Dernier relevé : 30 août 2026, sur l'installation réellement active de `suiveurtag`.

## État confirmé

- Produit : Serpantinum 2.0.0
- Commit installé : `e360577`
- Dépôt upstream utilisé par l'updater : `ilyamiro/serpantinum`
- Compositeur sélectionné : Hyprland
- Télémétrie : désactivée
- Processus principal : `serpantinumd start`
- Quickshell actif : `quickshell -p ~/.local/share/serpantinum/src/quickshell/Shell.qml`

La V2 est installée comme une application sous `~/.local/share/serpantinum`. Elle ne charge plus le shell depuis l'ancienne arborescence `~/.config/hypr/scripts/quickshell`.

## Nouvelle arborescence

| Rôle | Chemin actif |
| --- | --- |
| Installation | `~/.local/share/serpantinum/` |
| CLI utilisateur | `~/.local/bin/serpantinum` |
| Démon | `~/.local/bin/serpantinumd` |
| Sources QML | `~/.local/share/serpantinum/src/quickshell/` |
| Scripts Serpantinum | `~/.local/share/serpantinum/src/scripts/` |
| Assets | `~/.local/share/serpantinum/src/assets/` |
| Réglages persistants | `~/.config/serpantinum/settings.json` |
| État persistant | `~/.local/state/serpantinum/` |
| Cache | `~/.cache/serpantinum/` |
| Runtime et journaux temporaires | `${XDG_RUNTIME_DIR}/serpantinum/` |
| Socket IPC déclaré | `${XDG_RUNTIME_DIR}/serpantinum.sock` |
| Configuration Hyprland | `~/.config/hypr/hyprland.lua` et `~/.config/hypr/config/*.lua` |

Les anciennes configurations ont été conservées par l'installateur dans `~/.config/hypr_backup/`.

## Démarrage et cycle de vie

`~/.config/hypr/config/autostart.lua` exécute `serpantinumd start`. Le démon :

1. initialise les chemins de cache, d'état et de runtime ;
2. lance le daemon de suivi du temps d'écran ;
3. exécute la logique de premier lancement ;
4. lance Quickshell sur `src/quickshell/Shell.qml` ;
5. reste parent des processus et les arrête proprement à sa fermeture.

Commandes utiles :

```bash
serpantinum --version
serpantinumd --version
serpantinumd status
serpantinum reload
serpantinum kill
serpantinum msg toggle launcher
serpantinum msg toggle guide
serpantinum msg open network wifi
serpantinum msg workspace 1
serpantinum msg workspace 2 move
```

Il faut désormais préférer la CLI et l'IPC aux appels directs vers d'anciens scripts Quickshell.

## Composition du shell

`Shell.qml` instancie les surfaces principales :

- overlay de capture d'écran ;
- fenêtre principale et gestionnaire de popouts ;
- barre ;
- écran de verrouillage ;
- launcher et presse-papiers ;
- interface Polkit ;
- idle manager ;
- moteur de fond d'écran ;
- widgets flottants et quick actions.

Le mode `general.performance` désactive les composants les plus coûteux : idle, widgets par écran, fond d'écran et quick actions. `general.quickactions` peut désactiver seulement les actions flottantes.

`Main.qml` est le routeur des panneaux. Il expose un `IpcHandler` nommé `main`, met les widgets en cache et charge leurs composants à partir de `WindowRegistry.js`.

Widgets de panneau actuellement enregistrés :

- `network` → `network/NetworkPopup.qml`
- `volume` → `volume/VolumePopup.qml`
- `guide` → `guide/GuidePopup.qml`
- `calendar` → `calendar/CalendarPopup.qml`
- `wallpaper` → `wallpaper/WallpaperPicker.qml`
- `music` → `media/MusicPopup.qml`
- `notifications` → `notifications/NotificationCenter.qml`
- `system` → `syspanel/SystemPanel.qml`

Le launcher, le presse-papiers, la barre, le verrouillage et les widgets flottants sont des surfaces dédiées, pas des entrées ordinaires de ce registre.

## Organisation QML importante

- `bar/` : barre, modules et modules latéraux ;
- `guide/` : paramètres Serpantinum, thème, barre, affichage, launcher, notifications, idle et bien-être numérique ;
- `launcher/` : nouveau lanceur d'applications ;
- `quickactions/actions/` : timer, dessin et autres actions flottantes ;
- `singletons/` : configuration, thème, updater, notifications et états partagés ;
- `reusables/` : composants UI communs ;
- `widgets/` : widgets par écran ;
- `network/`, `volume/`, `media/`, `wallpaper/`, `syspanel/` : panneaux métier ;
- `serp/Serpantinum.qml` : composant Serpantinum déclaré dans `qmldir` ;
- `WindowRegistry.js` : dimensions, positions et composants des panneaux principaux.

## Configuration persistante

Le fichier de réglages est maintenant `~/.config/serpantinum/settings.json`. Les familles confirmées sont :

- `general` : langue, avatar, météo, quick actions, effets sonores et mode performance ;
- `bar` : position, largeur, opacité, style, autohide, modules, groupes et workspaces ;
- `theme` : preset, Matugen, police, rayon et palette ;
- `idle` : activation et actions dim/lock/DPMS/suspend ;
- `notifications` : DND, position, son et fichier audio ;
- `display.monitors` : options propres à chaque écran ;
- `launcher` : position, largeur, nombre d'éléments, classement et terminal ;
- `wallpaperDir` : dossier des fonds d'écran ;
- `syspanel` : état persistant du panneau système.

Ne jamais recopier le contenu complet de ce fichier dans une issue ou un log : les données de localisation peuvent contenir l'adresse IP publique, la ville et les coordonnées.

Les scripts `config.sh` fournis par Serpantinum ne manipulent que les clés racine avec `get_setting`, `set_setting` et `update_settings_bulk`. Pour les objets imbriqués, la logique QML écrit généralement le JSON via le singleton `Config`. Avant un addon, il faut donc tracer le propriétaire réel de la clé au lieu de supposer que `config.sh` sait écrire un chemin pointé.

## Configuration Hyprland V2

Hyprland est maintenant configuré en Lua :

```text
~/.config/hypr/hyprland.lua
└── ~/.config/hypr/config/
    ├── variables.lua
    ├── env.lua
    ├── autostart.lua
    ├── monitors.lua
    ├── settings.lua
    └── keybinds.lua
```

`hyprland.lua` charge ces modules avec `require`. Les raccourcis Serpantinum passent par des commandes telles que `serpantinum msg toggle …`, `serpantinum lock`, `serpantinum screenshot` et `serpantinum volume …`.

Conséquence : les anciens patchers visant `keybindings.conf`, `autostart.conf` ou `settings.json` de l'ancienne version ne sont plus compatibles.

## Mise à jour upstream

L'updater lit `~/.local/state/serpantinum/version` et compare la version à :

`https://raw.githubusercontent.com/ilyamiro/serpantinum/master/version.txt`

L'installation locale n'est pas un checkout Git : `~/.local/share/serpantinum` contient les fichiers déployés sans dossier `.git`. Toute modification directe sous `src/` risque donc d'être remplacée par une mise à jour.

Pour les futurs addons, conserver les sources dans ce dépôt et générer des patchs idempotents reste pertinent, mais les nouvelles cibles sont sous `~/.local/share/serpantinum/src/`. Les watchers devront surveiller l'installation Serpantinum, pas l'ancienne configuration Hyprland/Quickshell.

## Migration de nos anciens addons

Tous les anciens addons ont été retirés avant l'installation de la V2. Aucun ne doit être considéré comme porté tant qu'il n'a pas été retracé et testé sur Serpantinum 2.

| Ancien addon | Nouvelle zone probable | Travail requis |
| --- | --- | --- |
| wallpaper-random | `quickshell/wallpaper/` et `scripts/wallpaper/` | Retracer le moteur et la sélection multi-écran. |
| emoji-picker | `quickshell/launcher/` ou nouvelle surface dédiée | Recréer l'entrée IPC et un raccourci Lua. |
| matugen-vibrant | `quickshell/guide/theme/`, `singletons/` et assets de thème | Étudier le nouveau moteur de presets/Matugen avant tout patch. |
| zoomit | `config/keybinds.lua` et service séparé | Porter les raccourcis vers `hl.bind`; le backend peut rester externe. |
| screenshot-freeze | `quickshell/screenshot/` et `scripts/screenshot.sh` | Retracer le pipeline de capture V2. |
| idle-inhibit | `quickshell/idle/` et `guide/IdleTab.qml` | Vérifier d'abord `idle.manualInhibit`, désormais natif. |
| music-preview-rounded | `bar/`, `media/` et modules de barre | Refaire l'intégration selon le nouveau système de modules configurables. |
| topbar-button-effects | `bar/` et ses modules | Retracer les composants communs des boutons avant de dupliquer des effets. |
| launcher-web-search | `quickshell/launcher/` | Le lanceur a été réécrit ; conserver Enter et définir précisément Tab. |
| custom-alarm-clock | `quickactions/actions/Timer.qml` et singletons | Le timer V2 exporte déjà un état partagé ; auditer les fonctions natives. |
| drawing-notes | `quickactions/actions/DrawAction.qml` | Le dessin existe encore mais son chemin et son architecture ont changé. |
| headset-mic-loopback | `quickshell/volume/` | Garder le backend externe et intégrer la nouvelle UI audio. |
| captive-portal | `quickshell/network/` | Vérifier les fonctions réseau natives avant d'ajouter un nouvel état. |
| speedtest | `quickshell/network/` | Recréer le panneau dans le routeur V2 ou comme vue interne. |
| loading-icon | `reusables/` et états de chargement concernés | Chercher d'abord un loader partagé natif. |
| wifi-text-scroll | `quickshell/network/` | Retrouver le composant exact du SSID actif. |
| dns-mode-toggle | `quickshell/network/` | Préserver NetworkManager comme backend et adapter seulement la vue. |
| tor-panel | `WindowRegistry.js`, `Main.qml`, launcher et backend externe | Ajouter proprement un nouveau widget routé par IPC et revoir le lancement d'apps. |

## Règles de travail pour la V2

1. Confirmer le processus et le chemin réellement chargés avec `pgrep -a -f 'serpantinum|quickshell'`.
2. Chercher d'abord si Serpantinum fournit déjà le comportement demandé.
3. Tracer la chaîne complète : raccourci Lua → CLI/IPC → registre/contrôleur → QML → script/backend → état/cache.
4. Ne jamais modifier l'ancienne arborescence `~/.config/hypr/scripts/quickshell` : elle n'est plus active.
5. Ne pas écrire directement dans l'installation sans sauvegarde et sans patcher idempotent conservé dans ce dépôt.
6. Cibler `~/.local/share/serpantinum/src/` avec des ancres structurelles tolérantes aux mises à jour.
7. Surveiller les fichiers réellement remplacés par l'updater et réappliquer seulement après la fin de l'installation.
8. Préserver `~/.config/serpantinum/settings.json` et `~/.local/state/serpantinum/` lors des mises à jour.
9. Valider séparément la syntaxe, le rechargement Quickshell, l'IPC et le comportement visible.
10. Vérifier une seconde application du patch pour prouver l'idempotence.

## Vérifications minimales après un futur addon

```bash
python3 -m py_compile addons/<nom>/apply.py
bash -n addons/<nom>/apply.sh
qmllint -I ~/.local/share/serpantinum/src/quickshell <fichiers-qml>
git diff --check
serpantinum reload
pgrep -a -f 'serpantinum|quickshell'
```

Puis tester l'action réelle via son raccourci ou `serpantinum msg …`. Un rechargement réussi ne prouve pas que le panneau, le backend ou la persistance fonctionne.

## Éléments encore à confirmer au moment du premier portage

- comportement exact de l'installateur lors d'une mise à jour et ordre de remplacement des fichiers ;
- existence éventuelle d'une API officielle de plugins/addons ;
- politique de migration automatique de `settings.json` ;
- meilleur point d'injection pour ajouter un panneau au launcher et à `WindowRegistry.js` ;
- commandes de lint recommandées par l'upstream ;
- compatibilité des anciens états persistants avec les nouveaux composants.

Ce document décrit le snapshot local 2.0.0 observé. Il faut le rafraîchir après une mise à jour Serpantinum qui change la version ou le commit installé.
