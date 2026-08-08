import 'package:payghaam_flutter/payghaam_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PayghaamExampleApp());
}

/// Minimal demo app showing Payghaam SDK initialization, login, and events.
class PayghaamExampleApp extends StatefulWidget {
  const PayghaamExampleApp({super.key});

  @override
  State<PayghaamExampleApp> createState() => _PayghaamExampleAppState();
}

class _PayghaamExampleAppState extends State<PayghaamExampleApp> {
  bool _initialized = false;
  String _status = 'Tap Initialize to start';

  Future<void> _initialize() async {
    await Payghaam.instance.initialize(
      const PayghaamConfig(
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
    await Payghaam.instance.login('example-user');
    setState(() => _status = 'Logged in as example-user');
  }

  Future<void> _trackEvent() async {
    await Payghaam.instance.trackEvent('example_tap', {
      'source': 'example_app',
    });
    setState(() => _status = 'Tracked example_tap event');
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
            ],
          ),
        ),
      ),
    );
  }
}
