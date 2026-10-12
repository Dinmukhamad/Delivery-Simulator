# Navigation update 0.9.0

This changes local navigation in the standalone Godot demo. It does not port the game to Unity.

## Files and full source

Created: [navigation_service.gd](../GodotDemo/scripts/navigation_service.gd), [navigation_routes.gd](../GodotDemo/tests/navigation_routes.gd), [export_presets.cfg](../GodotDemo/export_presets.cfg), [.github/workflows/build-demo.yml](../.github/workflows/build-demo.yml).
Changed: [world.gd](../GodotDemo/scripts/world.gd), [hud.gd](../GodotDemo/scripts/hud.gd), [main.gd](../GodotDemo/scripts/main.gd), [lan_session.gd](../GodotDemo/scripts/lan_session.gd), [project.godot](../GodotDemo/project.godot). These links contain the complete files.

## Scene objects, components and Inspector

Open Godot 4.6.3 and import GodotDemo/project.godot. Run main.tscn. Its existing Main script creates City, Player and HUD. No manual nodes, components, Inspector assignments or new scene files are required. Main creates the RefCounted navigation service after City is built and provides the same static layout to the router and both map views.

## Input

M opens the large map and closes it. The existing map input action is reused. WASD, mouse, E and F remain the existing movement, interaction and vehicle actions. No new Input Actions are needed.

## Behaviour and architecture

The old map drew four generic streets per axis while the physical city has three. World now records actual road, pavement, park-path and building footprints as those objects are created. Both maps draw those footprints, an orientation triangle, pickup/delivery marker colours, and the same remaining polyline with direction arrows. Full map uses a square world projection and a scrolling overlay at small window sizes.

Walking/bicycle prefer paths and pavement; scooters/cars use the road network. The final off-road approach for motor vehicles is displayed as a gold dashed walking segment. Order status remains confirmed by the existing Solo/Host logic before the goal changes. No navigation RPC, reward request, movement authority or save schema has been introduced.

The bounded AStar grid validates cell centres and every edge against expanded obstacles instead of requiring an entire three-metre cell to fit in a narrow passage. Successful paths are checked again before use. Simplification removes only safe collinear points; unavailable paths show a message and marker without a straight-line substitute. Guidance caches paths, updates remaining route length as the player progresses, and rebuilds after deviation or goal/vehicle changes. Footprints are static; dynamic player vehicles are not GPS obstacles.

## Verification

Run: godot --headless --path GodotDemo --script tests/navigation_routes.gd -- --test-mode.
The guard prevents using a real profile. Tests cover building detours, exact goals, a pedestrian shortcut versus a U-shaped motor road, disconnected roads, blocked addresses, a shifted two-metre passage, query caching, deviations, objective switching, the real city, both HUD maps, actual pickup/delivery and Money/XP.

The CI imports scripts before testing, exports Windows x86_64 and macOS Universal, then runs the same meaningful checks against the exact target PCKs through the Linux editor. This does not replace native OS launch, physical mixed-platform LAN or FPS measurements.

## Potential errors and limitations

If the source editor differs from Godot 4.6.3, use the version matching the restored project. If an address is blocked or isolated, the map reports an unavailable route. Vehicle endpoint access is short and visible, not arbitrary cross-city off-road routing. This is guidance, not automatic steering; sharp turns still require the player to slow down. The grid is configured for this compact demo city; much larger maps or narrow passages on a coarser capped grid require a corridor graph or another navigation representation.

Original Git history and scripts excluded from the export are unavailable; recovered GDScript may have lost original comments and formatting. See RECOVERY.md. Career files stay in the existing custom user-data directory. Version 0.9.0 peers must match for LAN.

## Manual acceptance

Accept a delivery; follow the gold pickup marker and route. Pick up using E; verify the teal delivery goal and route replace it. Move away from the route and check rebuilding. Open M and compare with the mini-map. Enter each owned vehicle and inspect the road route and final walking leg. Complete/abandon/expire an order and confirm route removal. Test 1280x720 and 960x540; scroll the large map if needed. Run one Windows Host, one Windows Client and one macOS Client, then four players, checking personal routes and shared order ownership.
