import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Persistent offline queue for fire-and-forget SDK calls (events, tags,
/// receipts, subscriptions). Calls that fail with a retryable error (network,
/// timeout, 5xx) are parked in shared_preferences and drained FIFO on the next
/// app-resume / successful send — offline activity is no longer lost.
class OfflineQueue {
  static const _key = 'engagekaro.queue.v1';
  static const _maxQueue = 200;
  static const _maxAge = Duration(days: 7);

  final Future<void> Function(String method, String path, Map<String, dynamic> body) _sender;
  bool _flushing = false;

  OfflineQueue(this._sender);

  /// 4xx (except 408/429) will never be accepted; everything else retries.
  static bool isRetryable(Object error) {
    if (error is EngageKaroApiException) {
      return error.statusCode == 408 ||
          error.statusCode == 429 ||
          error.statusCode >= 500;
    }
    return error is SocketException ||
        error is HttpException ||
        true; // timeouts and unknown transport errors retry
  }

  Future<List<Map<String, dynamic>>> _load(SharedPreferences p) async {
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      final cutoff = DateTime.now().subtract(_maxAge).millisecondsSinceEpoch;
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .where((o) => (o['queuedAt'] as int? ?? 0) > cutoff)
          .toList();
    } catch (_) {
      return []; // corrupt queue: start fresh rather than wedge the SDK
    }
  }

  Future<void> _save(SharedPreferences p, List<Map<String, dynamic>> ops) =>
      p.setString(_key, jsonEncode(ops));

  Future<void> enqueue(String method, String path, Map<String, dynamic> body) async {
    final p = await SharedPreferences.getInstance();
    final ops = await _load(p);
    ops.add({
      'method': method,
      'path': path,
      'body': body,
      'queuedAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (ops.length > _maxQueue) ops.removeRange(0, ops.length - _maxQueue);
    await _save(p, ops);
  }

  /// Drain FIFO. Stops at the first retryable failure (still offline); drops
  /// ops the server permanently rejects. Safe to call repeatedly.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final p = await SharedPreferences.getInstance();
      while (true) {
        final ops = await _load(p);
        if (ops.isEmpty) return;
        final op = ops.first;
        try {
          await _sender(
            op['method'] as String,
            op['path'] as String,
            (op['body'] as Map).cast<String, dynamic>(),
          );
        } catch (e) {
          if (isRetryable(e)) return; // still offline — retry later
          // permanently rejected: fall through and drop
        }
        final after = await _load(p);
        if (after.isNotEmpty) after.removeAt(0);
        await _save(p, after);
      }
    } finally {
      _flushing = false;
    }
  }
}
