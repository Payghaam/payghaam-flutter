import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:payghaam_flutter/payghaam_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PayghaamExampleApp());
}

/// Minimal demo app showing Payghaam SDK initialization, login, events, and
/// (on iOS) Live Activities local start via host Swift + payghaam-ios observe.
class PayghaamExampleApp extends StatefulWidget {
  const PayghaamExampleApp({super.key});

  @override
  State<PayghaamExampleApp> createState() => _PayghaamExampleAppState();
}

class _PayghaamExampleAppState extends State<PayghaamExampleApp> {
  bool _initialized = false;
  String _status = 'Tap Initialize to start';
  String? _localActivityId;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    final baseUrl = Platform.isAndroid ? 'http://10.0.2.2:4000' : 'http://127.0.0.1:4000';
    await Payghaam.instance.initialize(
      PayghaamConfig(
        appId: 'cmqy0h7a8000xfcypq66nw18d',
        apiKey: 'ek_client_simulator_test_key_456',
        baseUrl: baseUrl,
        debug: true,
      ),
    );
    _subs.add(
      PayghaamLiveActivities.onUpdateTokenRegistered.listen((e) {
        setState(
          () => _status = 'LA update token ok=${e['ok']} id=${e['activityId']}',
        );
      }),
    );
    setState(() {
      _initialized = true;
      _status = 'SDK initialized';
    });
  }

  Future<void> _login() async {
    await Payghaam.instance.login('example-user');
    setState(() => _status = 'Logged in as example-user');
  }

  Future<void> _trackEvent() async {
    await Payghaam.instance.trackEvent('example_tap', {
      'source': 'example_app',
    });
    setState(() => _status = 'Tracked example_tap event');
  }

  Future<void> _addTags() async {
    await Payghaam.instance.user.addTags({
      'tier': 'pro',
      'device_type': Platform.isAndroid ? 'android' : 'ios',
    });
    setState(() => _status = 'Added debounced tags (tier=pro)');
  }

  Future<void> _startLiveActivity() async {
    if (Platform.isAndroid) {
      await const MethodChannel('payghaam/methods').invokeMethod('simulateLiveUpdate', {
        'liveId': 'order_4821',
        'event': 'start',
        'progress': '25',
        'title': 'Order #4821 • Preparing',
        'body': 'Restaurant is preparing your order',
      });
      setState(() {
        _localActivityId = 'order_4821';
        _status = 'Android Live Update started (25% progress)';
      });
      return;
    }
    final id = await PayghaamLiveActivities.startActivity(
      orderId: '4821',
      stage: 'picked_up',
      etaMinutes: 25,
    );
    setState(() {
      _localActivityId = id;
      _status = id == null
          ? 'Local LA start failed (iOS device + host channel required)'
          : 'Started local LA kitId=$id';
    });
  }

  Future<void> _updateLiveActivity() async {
    if (Platform.isAndroid) {
      await const MethodChannel('payghaam/methods').invokeMethod('simulateLiveUpdate', {
        'liveId': 'order_4821',
        'event': 'update',
        'progress': '75',
        'title': 'Order #4821 • On the way',
        'body': 'Driver is 5 mins away',
      });
      setState(() => _status = 'Android Live Update updated (75% progress)');
      return;
    }
    final ok = await PayghaamLiveActivities.updateActivity(
      activityId: _localActivityId,
      orderId: '4821',
      stage: 'on_the_way',
      etaMinutes: 12,
    );
    setState(() => _status = ok ? 'Updated local LA' : 'Update failed');
  }

  Future<void> _endLiveActivity() async {
    if (Platform.isAndroid) {
      await const MethodChannel('payghaam/methods').invokeMethod('simulateLiveUpdate', {
        'liveId': 'order_4821',
        'event': 'end',
      });
      setState(() {
        _localActivityId = null;
        _status = 'Android Live Update ended (dismissed)';
      });
      return;
    }
    final ok = await PayghaamLiveActivities.endActivity(
      activityId: _localActivityId,
      orderId: '4821',
    );
    setState(() {
      if (ok) _localActivityId = null;
      _status = ok ? 'Ended local LA' : 'End failed';
    });
  }

  Future<void> _refreshLiveActivities() async {
    await PayghaamLiveActivities.refresh();
    setState(() => _status = 'Called PayghaamLiveActivities.refresh()');
  }

  Future<void> _simulateCampaignPush() async {
    await const MethodChannel('payghaam/methods').invokeMethod('simulateCampaignPush', {
      'title': 'Engagekaro Summer Sale',
      'body': 'Tap here to see special discount!',
      'url': 'https://engagekaro.com',
    });
    setState(() => _status = 'Campaign push posted with ek_url=https://engagekaro.com');
  }

  Future<void> _openBrowserDirect() async {
    final opened = await const MethodChannel('payghaam/methods').invokeMethod<bool>('openUrl', {
      'url': 'https://engagekaro.com',
    });
    setState(() => _status = opened == true ? 'Browser opened to https://engagekaro.com' : 'Failed to open browser');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Payghaam Example')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _initialize,
                child: const Text('Initialize'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _initialized ? _login : null,
                child: const Text('Login'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _initialized ? _trackEvent : null,
                child: const Text('Track event'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _initialized ? _addTags : null,
                child: const Text('Add Tags (Debounced)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _initialized ? _simulateCampaignPush : null,
                child: const Text('Simulate Campaign Push (Deep Link)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _initialized ? _openBrowserDirect : null,
                child: const Text('Direct Open Browser (Deep Link)'),
              ),
              const SizedBox(height: 16),
              Text(
                Platform.isAndroid
                    ? 'Live Activities / Updates (Android)'
                    : 'Live Activities (iOS)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _initialized ? _startLiveActivity : null,
                child: const Text('Start local LA'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _initialized ? _updateLiveActivity : null,
                child: const Text('Update local LA'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _initialized ? _endLiveActivity : null,
                child: const Text('End local LA'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _initialized ? _refreshLiveActivities : null,
                child: const Text('Refresh LA tokens'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
