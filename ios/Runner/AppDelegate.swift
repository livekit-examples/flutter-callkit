/*
 * Copyright 2026 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import AVFoundation
import CallKit
import Flutter
import livekit_client
import PushKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private let callKit = CallKitBridge()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
    ) -> Bool {
        callKit.setWebRTCAudioAvailable(false)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CallKitBridge") else {
            NSLog("Unable to create Flutter registrar for CallKitBridge")
            return
        }
        callKit.attach(binaryMessenger: registrar.messenger())
        callKit.setWebRTCAudioAvailable(false)
    }
}

private final class CallKitBridge: NSObject {
    private let callController = CXCallController()
    private let provider: CXProvider
    private let pushRegistry = PKPushRegistry(queue: DispatchQueue.main)

    private var channel: FlutterMethodChannel?
    private var activeCallUUID: UUID?

    override init() {
        let configuration = CXProviderConfiguration(localizedName: "LiveKit")
        configuration.supportedHandleTypes = [.generic]
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportsVideo = false
        provider = CXProvider(configuration: configuration)

        super.init()

        provider.setDelegate(self, queue: nil)
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]
    }

    func attach(binaryMessenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "io.livekit.example.callkit", binaryMessenger: binaryMessenger)
        channel.setMethodCallHandler(handleMethodCall)
        self.channel = channel
    }

    func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "startCall":
            let handle = args["handle"] as? String ?? "LiveKit Call"
            startOutgoingCall(handle: handle, result: result)
        case "simulateIncomingCall":
            let callerId = args["callerId"] as? String ?? UUID().uuidString
            let callerName = args["callerName"] as? String ?? "LiveKit Caller"
            reportIncomingCall(callerId: callerId, callerName: callerName, result: result)
        case "endCall":
            endActiveCall(result: result)
        case "setMuted":
            let muted = args["muted"] as? Bool ?? false
            setCallMuted(muted, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Gates whether the WebRTC audio engine may run. The engine must only run
    /// inside CallKit's didActivate/didDeactivate window.
    ///
    /// Safe to call before the Flutter engine exists (for example on a
    /// killed-state VoIP push wake). The LiveKit plugin stores the value and
    /// applies it at plugin registration, before anything can start the engine.
    func setWebRTCAudioAvailable(_ isAvailable: Bool) {
        LiveKitPlugin.setEngineAvailability(
            isInputAvailable: isAvailable,
            isOutputAvailable: isAvailable,
        )
    }

    /// Sets the call category before CallKit activates the session, so the
    /// activation happens with a recording-capable category. LiveKit
    /// re-applies the session policy (without activating) from engine
    /// lifecycle under AudioSessionManagementMode.externalCallSystem, but
    /// CallKit's own activation can happen before the engine starts, and on a
    /// background push wake the microphone fails to initialize unless the
    /// category is set before reportNewIncomingCall.
    private func configureCallAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .mixWithOthers],
        )
    }

    private func startOutgoingCall(handle: String, result: @escaping FlutterResult) {
        do {
            try configureCallAudioSession()
        } catch {
            NSLog("Failed to pre-configure AVAudioSession before outgoing call: \(error.localizedDescription)")
        }

        let callUUID = UUID()
        let action = CXStartCallAction(call: callUUID, handle: CXHandle(type: .generic, value: handle.isEmpty ? "LiveKit Call" : handle))
        let transaction = CXTransaction(action: action)

        callController.request(transaction) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    result(FlutterError(code: "start_call_failed", message: error.localizedDescription, details: nil))
                    return
                }

                self?.activeCallUUID = callUUID
                result(true)
            }
        }
    }

    private func reportIncomingCall(callerId: String, callerName: String, result: @escaping FlutterResult) {
        reportIncomingCall(callerId: callerId, callerName: callerName) { error in
            DispatchQueue.main.async {
                if let error {
                    result(FlutterError(code: "report_incoming_failed", message: error.localizedDescription, details: nil))
                } else {
                    result(true)
                }
            }
        }
    }

    private func reportIncomingCall(callerId: String, callerName: String, completion: @escaping (Error?) -> Void) {
        do {
            try configureCallAudioSession()
        } catch {
            NSLog("Failed to pre-configure AVAudioSession before incoming call: \(error.localizedDescription)")
        }

        let callUUID = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerId)
        update.localizedCallerName = callerName
        update.hasVideo = false

        provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] error in
            if error == nil {
                self?.activeCallUUID = callUUID
            }
            completion(error)
        }
    }

    private func endActiveCall(result: @escaping FlutterResult) {
        guard let callUUID = activeCallUUID else {
            result(true)
            return
        }

        let action = CXEndCallAction(call: callUUID)
        callController.request(CXTransaction(action: action)) { error in
            DispatchQueue.main.async {
                if let error {
                    result(FlutterError(code: "end_call_failed", message: error.localizedDescription, details: nil))
                } else {
                    result(true)
                }
            }
        }
    }

    private func setCallMuted(_ muted: Bool, result: @escaping FlutterResult) {
        guard let callUUID = activeCallUUID else {
            result(true)
            return
        }

        let action = CXSetMutedCallAction(call: callUUID, muted: muted)
        callController.request(CXTransaction(action: action)) { error in
            DispatchQueue.main.async {
                if let error {
                    result(FlutterError(code: "set_muted_failed", message: error.localizedDescription, details: nil))
                } else {
                    result(true)
                }
            }
        }
    }

    private func requestDart(_ method: String, arguments: [String: Any], action: CXAction, callUUID: UUID) {
        guard let channel else {
            action.fail()
            provider.reportCall(with: callUUID, endedAt: Date(), reason: .failed)
            activeCallUUID = nil
            return
        }

        DispatchQueue.main.async {
            channel.invokeMethod(method, arguments: arguments) { [weak self] response in
                guard let self else { return }

                if let error = response as? FlutterError {
                    NSLog("Dart method \(method) failed: \(error.message ?? error.code)")
                    action.fail()
                    provider.reportCall(with: callUUID, endedAt: Date(), reason: .failed)
                    activeCallUUID = nil
                    return
                }

                if let success = response as? Bool, success {
                    if action is CXStartCallAction {
                        provider.reportOutgoingCall(with: callUUID, connectedAt: Date())
                    }
                    action.fulfill()
                } else {
                    action.fail()
                    provider.reportCall(with: callUUID, endedAt: Date(), reason: .failed)
                    activeCallUUID = nil
                }
            }
        }
    }

    private func notifyDart(_ method: String, arguments: [String: Any] = [:]) {
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod(method, arguments: arguments)
        }
    }
}

extension CallKitBridge: CXProviderDelegate {
    func providerDidReset(_: CXProvider) {
        activeCallUUID = nil
        setWebRTCAudioAvailable(false)
        notifyDart("providerReset")
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        activeCallUUID = action.callUUID
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        requestDart("connect", arguments: ["callUUID": action.callUUID.uuidString, "direction": "outgoing"], action: action, callUUID: action.callUUID)
    }

    func provider(_: CXProvider, perform action: CXAnswerCallAction) {
        activeCallUUID = action.callUUID
        requestDart("connect", arguments: ["callUUID": action.callUUID.uuidString, "direction": "incoming"], action: action, callUUID: action.callUUID)
    }

    func provider(_: CXProvider, perform action: CXEndCallAction) {
        requestDart("disconnect", arguments: ["callUUID": action.callUUID.uuidString], action: action, callUUID: action.callUUID)
        activeCallUUID = nil
    }

    func provider(_: CXProvider, perform action: CXSetMutedCallAction) {
        requestDart(
            "setMuted",
            arguments: ["callUUID": action.callUUID.uuidString, "muted": action.isMuted],
            action: action,
            callUUID: action.callUUID,
        )
    }

    func provider(_: CXProvider, didActivate _: AVAudioSession) {
        do {
            try configureCallAudioSession()
            setWebRTCAudioAvailable(true)
        } catch {
            NSLog("Failed to configure CallKit audio session: \(error.localizedDescription)")
        }
    }

    func provider(_: CXProvider, didDeactivate _: AVAudioSession) {
        setWebRTCAudioAvailable(false)
    }
}

extension CallKitBridge: PKPushRegistryDelegate {
    func pushRegistry(_: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        notifyDart("voipToken", arguments: ["token": token])
    }

    func pushRegistry(_: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        notifyDart("voipToken", arguments: ["token": NSNull()])
    }

    func pushRegistry(_: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }

        let callerId = payload.dictionaryPayload["callerId"] as? String ?? UUID().uuidString
        let callerName = payload.dictionaryPayload["callerName"] as? String ?? "LiveKit Caller"

        reportIncomingCall(callerId: callerId, callerName: callerName) { error in
            if let error {
                NSLog("Failed to report VoIP push as incoming call: \(error.localizedDescription)")
            }
            completion()
        }
    }
}
