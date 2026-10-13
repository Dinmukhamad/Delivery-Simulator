# Delivery Simulator

Editable Godot demo **0.11.0**. Open `GodotDemo/project.godot` with Godot 4.6.3.

The city is **516 × 516 metres**, three times wider and longer than the original map. It contains **104 buildings, 18 pickup points and 51 delivery addresses** across business, civic/retail, logistics, residential, park and old-town districts. The original starting block, garage and first delivery remain accessible.

M opens the full city map with district names. The mini-map shows the nearby 128 metres; navigation follows actual streets and paths, avoids buildings and marks the final walking approach. Beginning couriers get short local work, while owned transport unlocks longer trips.

LAN supports **Team Shift**: a fixed shared delivery goal, one-time personal bonus of 500 Money and 100 XP for a completed delivery contribution, and parcel handoffs requiring explicit consent through Tab. Competitive mode is the default.

[Windows artifact](https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38325332235/artifacts/11780622440) · [macOS artifact](https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38325332235/artifacts/11780537590)

Unpack the download, then unpack the game ZIP inside it. Run the EXE on Windows or the app on macOS. LAN: Host Game → choose mode; friends Join Game using the Host IPv4 address, then Ready → Start. Same version **0.11.0**, same local network, UDP port 7777. Career profiles remain local.

[City source/setup](docs/CITY_LAYOUT.md) · [Team Shift](docs/TEAM_SHIFT.md) · [Build evidence and screenshots](docs/BUILD_REPORT.md) · [Recovery history](RECOVERY.md)

CI passed **5358 checks** across source and both exact target packs, with three two-process ENet scenarios and actual UI/city renders. Native Windows/macOS launch, mixed-platform four-device LAN and FPS still require acceptance testing. This is the separately agreed Godot demo.

![Business district — actual engine capture](docs/screenshots/city-business-1280.png)
