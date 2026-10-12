# Delivery Simulator

Editable Godot demo **0.9.0**, restored from the verified 0.8.0 build. Open `GodotDemo/project.godot` with Godot 4.6.3.

The city map now matches the actual streets and buildings. Mini-map and M-map show the same route, turn arrows, player heading, route distance and confirmed pickup/delivery goal. Routes avoid solid buildings; walking/bicycle use paths, motor transport follows roads with a dashed final walking approach.

[Windows artifact](https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38282955933/artifacts/11762136467) · [macOS artifact](https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38282955933/artifacts/11761887835)

Unpack the download, then unpack the game ZIP inside it. Run the EXE on Windows or the app on macOS.

[Build evidence and limits](docs/BUILD_REPORT.md) · [Full navigation source/setup](docs/NAVIGATION.md) · [Recovery history](RECOVERY.md)

LAN: Host Game on one computer; Join Game with the Host's IPv4 address on the other. Use the same game version and local network; UDP port 7777. Ready → Start Game. Coordinates and orders are confirmed by the Host. Profile progress remains local.

CI passed 34 checks on source and on both exact target packs, 21 checks in two ENet processes, and map renders at 1280x720/960x540. Native OS launch, physical mixed-platform/four-device LAN and FPS still require acceptance testing.

This is the standalone Godot demo, separate from the Unity project in the original specification. The old recovery tag's automatically generated source ZIP contains its initial README; use the current source branches for the full editable project.
