# Delivery Simulator

Editable Godot demo **0.13.0**. Open `GodotDemo/project.godot` with Godot 4.6.3.

**Customization** is available from Profile and Garage: select courier outfits, backpack shapes and vehicle paint. Free styles work from the beginning; extra styles use earned Money. Purchases and equipped choices are saved in the local career profile and displayed to LAN friends. Cosmetic styles do not change movement, vehicle handling or parcel quality. Old 0.12.0 profiles retain their career progress.

The city is **516 × 516 metres**, with **104 buildings, 18 pickup points and 51 delivery addresses** across six districts. M opens the full map, the mini-map shows nearby streets, and routes follow the real city geometry.

**Lunch Rush** starts 45 seconds into a shift: for three minutes, up to three extra cafe-to-office orders appear in the business district alongside six normal offers. Timely delivery pays 50% extra Money; accepted parcels remain worth their base reward afterwards.

LAN supports **Team Shift** goals, one-time contribution bonuses and explicit parcel handoffs through Tab. The Host controls common orders, event times, rewards and in-session cosmetic purchases.

Build verification for 0.13.0 is in progress. Download links and evidence will be recorded after successful CI exports.

LAN: select appearance in Profile before Host/Join, or visit Garage during the shift. Friends Join Game using the Host IPv4 address, then Ready → Start. Same version **0.13.0**, same local network, UDP port 7777. Career profiles remain local.

[Customization: source, setup and testing](docs/CUSTOMIZATION.md) · [District events](docs/DISTRICT_EVENTS.md) · [City](docs/CITY_LAYOUT.md) · [Team Shift](docs/TEAM_SHIFT.md) · [Build evidence](docs/BUILD_REPORT.md)

Native Windows/macOS launch, mixed-platform four-device LAN and FPS still require acceptance testing. This is the separately agreed Godot demo.
