# LiveKit Flutter CallKit Example

Flutter example showing how to pair the LiveKit Flutter SDK with native iOS CallKit and PushKit.

The example uses the following audio-session pattern:

- CallKit and PushKit stay in native iOS code.
- The LiveKit `Room` stays in Dart.
- Native CallKit actions call into Dart over a method channel.
- Dart sets `AudioSessionManagementMode.externalCallSystem` at startup, so LiveKit configures the session category and mode from engine lifecycle but never activates or deactivates the session. CallKit owns activation timing.
- The AppDelegate gates the WebRTC audio engine with `LiveKitPlugin.setEngineAvailability`: off at launch, on in `provider(didActivate:)`, off again in `provider(didDeactivate:)`. This is safe to call before the Flutter engine exists (killed-state VoIP push wake). The plugin stores the value and applies it at registration.
- Connecting the room and publishing the microphone happen inside CallKit action handlers while the engine is still gated off. The requests are honored as soon as CallKit activates the session and availability flips on.

Apps that handle CallKit events in Dart (for example via a CallKit plugin) can use the Dart equivalent, `AudioManager.instance.setEngineAvailability`, from those event handlers instead of the native static.

## What it does

- Starts an outgoing CallKit call and connects to a LiveKit room.
- Simulates an incoming CallKit call without a real VoIP push.
- Displays the PushKit VoIP token when running on a physical iOS device.
- Publishes the local microphone after the room connects.
- Maps CallKit mute/end actions back to the LiveKit room.

## iOS setup

CallKit does not work in the iOS Simulator. Use a physical iPhone.

Open `ios/Runner.xcworkspace` in Xcode and confirm:

- The `Runner` target has your development team selected.
- Background Modes includes `Voice over IP`, `Remote notifications`, and `Audio`.
- Push Notifications is enabled.
- The provisioning profile supports the entitlements in `ios/Runner/Runner.entitlements`.

Then run:

```sh
flutter pub get
flutter run -d <ios-device-id>
```

## Usage

1. Enter a LiveKit server URL and access token.
2. Tap `Start outgoing CallKit call` or `Simulate incoming call`.
3. For an incoming call, answer from the native CallKit UI.
4. Use the native CallKit UI or the in-app button to mute and end the call.

For real VoIP pushes, send a PushKit payload with optional `callerId` and `callerName` fields. The example reports the incoming call synchronously from `pushRegistry(_:didReceiveIncomingPushWith:for:completion:)` so the incoming-call UI can appear reliably when the app is woken in the background.

This example keeps the room connection in Dart. For a production app that must connect from a killed/background-only state, verify that a Flutter engine is available for your PushKit and CallKit answer path, or move the background connection path into native code.

## Development

Run `swiftformat .` and `dart format .` before committing.

## Android

Android is included only so the Flutter project can open/run there. CallKit and PushKit are iOS-only. The Android equivalent is the Telecom framework (`androidx.core.telecom`) plus a phoneCall foreground service and a CallStyle full-screen intent notification, which is planned as a follow-up. `AudioSessionManagementMode.externalCallSystem` currently behaves like automatic mode on Android, so setting it once at startup is safe for cross-platform apps, and the mode is reserved for that Telecom integration.
