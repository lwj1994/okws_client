import 'package:okws_client/okws_client.dart';
import 'package:test/test.dart';

void main() {
  group('OkWsClient Logging Tests', () {
    test('should use custom log adapter', () async {
      final logs = <String>[];
      
      OkWsClient.init(
        isLoggingEnable: true,
        logAdapter: (message) {
          logs.add(message);
        },
      );

      // Trigger a log (we need to trigger wslog somehow, creating a client and connecting triggers logs)
      // But we don't want to depend on actual network here if possible.
      // However, we can use the fact that OkWsClient constructor doesn't log, but connect does.
      // Or simply, verify that init calls initOkWsLog correctly.
      // Since we can't easily access private wslog, we'll test the effect via integration or by exposing a test helper if needed.
      // But wait, wslog is internal. 
      // Let's rely on the fact that OkWsClient calls wslog internally.
      
      final client = OkWsClient('ws://invalid-url');
      try {
        await client.connect(); // This will log "Connecting to..."
      } catch (_) {}
      
      expect(logs, isNotEmpty);
      expect(logs.any((log) => log.contains('Connecting to ws://invalid-url')), isTrue);
    });
  });
}
