class SttConfig {
  final String baseUrl;
  final List<String> candidateBaseUrls;
  final String baseWsUrl;
  final int sampleRate;
  final int timeoutSeconds;
  final int maxFileSizeBytes;

  SttConfig({
    required this.baseUrl,
    List<String>? candidateBaseUrls,
    String? baseWsUrl,
    this.sampleRate = 16000,
    this.timeoutSeconds = 120,
    this.maxFileSizeBytes = 50 * 1024 * 1024, // 50MB
  })  : candidateBaseUrls = candidateBaseUrls ?? const [],
        baseWsUrl = baseWsUrl ??
            (baseUrl.startsWith('https://')
                ? baseUrl.replaceFirst('https://', 'wss://')
                : baseUrl.replaceFirst('http://', 'ws://'));
}
