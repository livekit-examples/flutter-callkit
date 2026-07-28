// This example demonstrates the CallKit coordination APIs, which are
// currently marked experimental in livekit_client.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // CallKit owns audio session activation. LiveKit keeps configuring the
  // session category/mode from engine lifecycle but never activates or
  // deactivates it. The engine itself is gated natively: the AppDelegate
  // calls LiveKitPlugin.setEngineAvailability(false) at launch and flips it
  // inside CallKit's didActivate/didDeactivate window.
  if (Platform.isIOS) {
    await AudioManager.instance.setAudioSessionManagementMode(
      AudioSessionManagementMode.externalCallSystem,
    );
  }

  runApp(const CallKitExampleApp());
}

class CallKitExampleApp extends StatelessWidget {
  const CallKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveKit CallKit',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CallKitHomePage(),
    );
  }
}

class CallKitHomePage extends StatefulWidget {
  const CallKitHomePage({super.key});

  @override
  State<CallKitHomePage> createState() => _CallKitHomePageState();
}

class _CallKitHomePageState extends State<CallKitHomePage> {
  static const _channel = MethodChannel('io.livekit.example.callkit');

  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _callerController = TextEditingController(text: 'LiveKit Caller');

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _connecting = false;
  bool _disconnectingFromCallKit = false;
  bool _muted = false;
  String _status = 'Idle';
  String? _voipToken;
  String? _lastError;

  bool get _isIOS => Platform.isIOS;
  bool get _hasRoom => _room != null;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleCallKitMethod);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _urlController.dispose();
    _tokenController.dispose();
    _callerController.dispose();
    unawaited(_disposeCurrentRoom());
    super.dispose();
  }

  Future<dynamic> _handleCallKitMethod(MethodCall call) async {
    final args = Map<String, dynamic>.from(
      (call.arguments as Map?) ?? const {},
    );

    switch (call.method) {
      case 'connect':
        await _connectToRoom();
        return true;
      case 'disconnect':
        await _disconnectFromRoom(fromCallKit: true);
        return true;
      case 'setMuted':
        await _setMuted(args['muted'] as bool? ?? false, fromCallKit: true);
        return true;
      case 'voipToken':
        if (!mounted) return true;
        setState(() => _voipToken = args['token'] as String?);
        return true;
      case 'providerReset':
        await _disconnectFromRoom(fromCallKit: true);
        return true;
      default:
        throw MissingPluginException('Unknown CallKit method: ${call.method}');
    }
  }

  Future<void> _connectToRoom() async {
    if (_room != null) return;
    if (_connecting) return;

    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();
    if (url.isEmpty || token.isEmpty) {
      throw StateError('LiveKit URL and token are required before connecting.');
    }

    setState(() {
      _connecting = true;
      _lastError = null;
      _status = 'Connecting to LiveKit...';
    });

    final room = Room();
    final listener = room.createListener()
      ..on<RoomDisconnectedEvent>((event) {
        unawaited(_handleRoomDisconnected(event.reason));
      });

    try {
      await room.connect(url, token);
      await room.localParticipant?.setMicrophoneEnabled(true);

      if (!mounted) return;
      setState(() {
        _room = room;
        _listener = listener;
        _connecting = false;
        _muted = false;
        _status = 'Connected';
      });
    } catch (error) {
      await listener.dispose();
      await room.dispose();
      if (mounted) {
        setState(() {
          _connecting = false;
          _lastError = '$error';
          _status = 'Connect failed';
        });
      }
      rethrow;
    }
  }

  Future<void> _handleRoomDisconnected(DisconnectReason? reason) async {
    if (!_disconnectingFromCallKit && _isIOS) {
      unawaited(_invokeCallKit('endCall'));
    }

    await _disposeCurrentRoom();

    if (!mounted) return;
    setState(() {
      _connecting = false;
      _disconnectingFromCallKit = false;
      _muted = false;
      _status = reason == null ? 'Disconnected' : 'Disconnected: $reason';
    });
  }

  Future<void> _disconnectFromRoom({required bool fromCallKit}) async {
    _disconnectingFromCallKit = fromCallKit;
    final room = _room;

    if (room != null) {
      await room.disconnect();
    }

    await _disposeCurrentRoom();

    if (!mounted) return;
    setState(() {
      _connecting = false;
      _disconnectingFromCallKit = false;
      _muted = false;
      _status = 'Idle';
    });
  }

  Future<void> _disposeCurrentRoom() async {
    final listener = _listener;
    final room = _room;
    _listener = null;
    _room = null;
    await listener?.dispose();
    await room?.dispose();
  }

  Future<void> _setMuted(bool muted, {required bool fromCallKit}) async {
    final room = _room;
    if (room == null) return;

    await room.localParticipant?.setMicrophoneEnabled(!muted);

    if (!fromCallKit && _isIOS) {
      await _invokeCallKit('setMuted', {'muted': muted});
    }

    if (!mounted) return;
    setState(() => _muted = muted);
  }

  Future<void> _startOutgoingCall() async {
    if (!_isIOS) {
      _showSnackBar('CallKit is only available on iOS.');
      return;
    }

    await _invokeCallKit('startCall', {
      'handle': _callerController.text.trim(),
    });
  }

  Future<void> _simulateIncomingCall() async {
    if (!_isIOS) {
      _showSnackBar('CallKit is only available on iOS.');
      return;
    }

    await _invokeCallKit('simulateIncomingCall', {
      'callerId': 'livekit-demo',
      'callerName': _callerController.text.trim().isEmpty ? 'LiveKit Caller' : _callerController.text.trim(),
    });
  }

  Future<void> _endCall() async {
    if (_isIOS) {
      await _invokeCallKit('endCall');
    } else {
      await _disconnectFromRoom(fromCallKit: false);
    }
  }

  Future<dynamic> _invokeCallKit(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      return await _channel.invokeMethod<dynamic>(method, args);
    } catch (error) {
      if (mounted) {
        setState(() => _lastError = '$error');
        _showSnackBar('$error');
      }
      rethrow;
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyVoipToken() async {
    final token = _voipToken;
    if (token == null || token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: token));
    _showSnackBar('Copied VoIP token.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LiveKit CallKit Example')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'This example keeps CallKit and PushKit in native iOS code and keeps the LiveKit room in Dart.',
            ),
            const SizedBox(height: 16),
            _InfoCard(
              title: 'Status',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_status),
                  if (_lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _lastError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'LiveKit URL',
                hintText: 'wss://your-project.livekit.cloud',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Access token',
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _callerController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Caller / handle',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _connecting || _hasRoom ? null : _startOutgoingCall,
                  icon: const Icon(Icons.call),
                  label: const Text('Start outgoing CallKit call'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _connecting || _hasRoom ? null : _simulateIncomingCall,
                  icon: const Icon(Icons.call_received),
                  label: const Text('Simulate incoming call'),
                ),
                OutlinedButton.icon(
                  onPressed: _hasRoom || _connecting ? _endCall : null,
                  icon: const Icon(Icons.call_end),
                  label: const Text('End call'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Muted'),
              subtitle: const Text('Mirrors the CallKit mute action.'),
              value: _muted,
              onChanged: _hasRoom ? (muted) => unawaited(_setMuted(muted, fromCallKit: false)) : null,
            ),
            const SizedBox(height: 16),
            _InfoCard(
              title: 'VoIP push token',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _voipToken ?? 'Run on a physical iOS device to receive a PushKit token.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _voipToken == null ? null : _copyVoipToken,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy token'),
                  ),
                ],
              ),
            ),
            if (!_isIOS) ...[
              const SizedBox(height: 16),
              const _InfoCard(
                title: 'Platform note',
                child: Text(
                  'CallKit and PushKit are iOS-only. Android support would require a separate ConnectionService example.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
