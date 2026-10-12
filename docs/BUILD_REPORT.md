# Delivery Simulator Demo 0.9.0 build report

Code commit: 18e2f0805a19f4273cc9a8894474d5ddc30f96cc.
Successful CI: https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38282955933.
Engine: Godot 4.6.3; restored base: 0.8.0.

## Delivered behaviour

Both maps use actual city geometry instead of the former generic four-street grid. Delivery guidance follows streets/paths around solid buildings, provides remaining route length and meaningful turn hints, updates on confirmed pickup, and replans after deviation or vehicle changes. Walking/bicycle shortcuts differ from motor road routes; final walking access is dashed gold. Goal colour and local orientation are visible.

LAN coordinate RPCs now use ordered reliable delivery. A genuine two-process test exposed stale Host positions that blocked pickup with unreliable ordered packets. Sender/session validation, collision/finite checks, movement credit, order ownership and rewards remain on the Host.

## Verification performed

- Source editor import passed.
- 34 navigation/Solo checks passed against source.
- The same 34 checks passed against the exact Windows embedded PCK.
- The same 34 checks passed against the exact macOS PCK.
- ENet loopback in two separate processes: Host 10 checks, Client 11 checks, all passed; confirmed acceptance/pickup, separate personal routes, peer marker and client disconnect.
- Full map rendered and inspected at 1280x720 and 960x540 using software OpenGL.
- Windows PE architecture checked: x86_64.
- macOS fat Mach-O checked: Intel x86_64 and Apple Silicon arm64.
- Release ZIP CRC checks passed.
- All ten recovered audio files exactly matched their original manifest SHA256 values.

## Downloads

GitHub build artifacts:

- Windows: https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38282955933/artifacts/11762136467 — 38,822,063 bytes.
- macOS: https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38282955933/artifacts/11761887835 — 65,309,361 bytes.

These are the GitHub artifact ZIP wrappers. Unpack the downloaded ZIP, then unpack the game ZIP inside it. macOS executable permissions are preserved by the inner ZIP.

GitHub artifact SHA256:
- Windows: 0b8ad6870d43494eafbda53a9a9e3410d65709fd440139f525d9bcb6a36f4872.
- macOS: 2a2490e413046ff99c5652212b3792f52be1890f86ff3eceeb42db80101389a2.
- Source: 07f5fe997871bb126207335bab1f4d2ef083357f1bf74cd56804743ca120af7a.

Source artifact: https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38282955933/artifacts/11761857966.
Reports and images: https://github.com/Dinmukhamad/Delivery-Simulator/actions/runs/38282955933/artifacts/11762101426.

## Practical limits

Target packs were executed through the Linux Godot engine. Native Windows/macOS launch, physical Windows Host + Windows Client + macOS Client, four-device LAN, actual speaker output and FPS measurements remain manual acceptance tasks. This is the separately authorised Godot demo, not completion of the Unity 1.0 specification. macOS notarization for internet distribution is not performed.

Full change and setup instructions: NAVIGATION.md.
