# FlyChat Example

A runnable UIKit demo for the FlyChat Swift Package.

## Run

1. Open `FlyChatExample.xcodeproj` in Xcode 16 or later.
2. The local FlyChat package (one directory up) resolves automatically.
3. Select the **FlyChatExample** scheme and an iOS 17+ simulator, then Run.

## What it shows

The entry screen offers two integration styles, each wiring the `FCLUIKitBridge` wrappers into a
themed chat list and conversation:

- **Liquid Glass** — translucent glass chrome (`FCLVisualStyle.liquidGlass`; native on iOS 26,
  layered fallback on iOS 17/18).
- **Solid Backgrounds** — opaque, solid element backgrounds (`FCLVisualStyle.default`).

The photo-library attachment flow works on the simulator; the camera requires a physical device.

See [`../Documentation/ExampleApp.md`](../Documentation/ExampleApp.md) for the full guide.
