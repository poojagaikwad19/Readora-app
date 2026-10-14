import 'dart:async';
import 'dart:typed_data';

abstract class LiveMicRecorder {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startStream({int sampleRate = 16000});
  Future<String?> stop();
  Future<void> dispose();
}

/// In-memory/mock recorder for test environments and fallback
class MockLiveMicRecorder implements LiveMicRecorder {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>.broadcast();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream({int sampleRate = 16000}) async {
    return _controller.stream;
  }

  void pushChunk(Uint8List chunk) {
    if (!_controller.isClosed) {
      _controller.add(chunk);
    }
  }

  @override
  Future<String?> stop() async {
    return null;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
