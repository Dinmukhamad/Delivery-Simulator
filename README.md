# Delivery Simulator

Editable Godot demo **0.10.0**, restored from the verified 0.8.0 build. Open `GodotDemo/project.godot` with Godot 4.6.3.

LAN now offers **Team Shift**: complete a shared goal of four deliveries per starting player and earn a one-time personal bonus of 500 Money and 100 XP after contributing a completed delivery. Use Tab to offer an already picked parcel to a nearby free teammate; they explicitly accept or decline. The Host validates every transfer and retains the parcel deadline and fragile quality. Competitive mode remains the default.

The city map now matches the actual streets and buildings. Mini-map and M-map show the same route, turn arrows, player heading, route distance and confirmed pickup/delivery goal. Routes avoid solid buildings; walking/bicycle use paths, motor transport follows roads with a dashed final walking approach.

[Windows artifact](https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38297836122/artifacts/11768749891) · [macOS artifact](https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38297836122/artifacts/11768744775)

Unpack the download, then unpack the game ZIP inside it. Run the EXE on Windows or the app on macOS.

[Team Shift rules and setup](docs/TEAM_SHIFT.md) · [Build evidence and limits](docs/BUILD_REPORT.md) · [Full navigation source/setup](docs/NAVIGATION.md) · [Recovery history](RECOVERY.md)

LAN: Host Game on one computer; Join Game with the Host's IPv4 address on the other. Use the same game version and local network; UDP port 7777. Ready → Start Game. Coordinates and orders are confirmed by the Host. Profile progress remains local.

CI passed 498 checks across navigation/Solo, Team Shift source and both exact target packs, and two-process ENet sessions. Isolated profile saves and actual UI renders also passed. Native OS launch, physical mixed-platform/four-device LAN and FPS still require acceptance testing.

This is the standalone Godot demo, separate from the Unity project in the original specification. The old recovery tag's automatically generated source ZIP contains its initial README; use the current source branches for the full editable project.
