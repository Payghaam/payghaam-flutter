import 'package:engagekaro_flutter/engagekaro_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EngageKaroExampleApp());
}

/// Minimal demo app showing EngageKaro SDK initialization, login, and events.
class EngageKaroExampleApp extends StatefulWidget {
  const EngageKaroExampleApp({super.key});

  @override
  State<EngageKaroExampleApp> createState() => _EngageKaroExampleAppState();
}

class _EngageKaroExampleAppState extends State<EngageKaroExampleApp> {
  bool _initialized = false;
  String _status = 'Tap Initialize to start';

  Future<void> _initialize() async {
    await EngageKaro.instance.initialize(
      const EngageKaroConfig(
        appId: 'YOUR_PROJECT_ID',
        apiKey: 'ek_client_...',
        baseUrl: 'https://api.yourhost.com',
        debug: true,
      ),
    );
    setState(() {
      _initialized = true;
      _status = 'SDK initialized';
    });
  }

  Future<void> _login() async {
    await EngageKaro.instance.login('example-user');
    setState(() => _status = 'Logged in as example-user');
  }

  Future<void> _trackEvent() async {
    await EngageKaro.instance.trackEvent('example_tap', {
      'source': 'example_app',
    });
    setState(() => _status = 'Tracked example_tap event');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('EngageKaro Example')),
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
            ],
          ),
        ),
      ),
    );
  }
}
