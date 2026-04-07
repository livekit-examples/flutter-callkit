# LiveKit Flutter CallKit Example

Flutter example showing how to pair the LiveKit Flutter SDK with native iOS CallKit and PushKit.

The example uses the following audio-session pattern:

- CallKit and PushKit stay in native iOS code.
- The LiveKit `Room` stays in Dart.
- Native CallKit actions call into Dart over a method channel.
- WebRTC audio engine availability is disabled until CallKit activates the `AVAudioSession`.
- WebRTC manual audio mode is also enabled as an extra guard while the Flutter WebRTC plugin is starting up.

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

## Android

Android is included only so the Flutter project can open/run there. CallKit and PushKit are iOS-only; an Android native-call UI example would need a separate ConnectionService implementation.
