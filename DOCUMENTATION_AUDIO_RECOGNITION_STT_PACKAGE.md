# Readora Audio Recognition & Speech-to-Text (STT) Inbuilt Package
## Comprehensive Architecture, Creation Flow & Integration Guide

---

## 1. Executive Summary & Architecture

This document defines the complete creation flow, architecture, and integration steps for the **Readora Inbuilt Audio Recognition & STT Package** (`readora_audio_stt`). 

### Core Capabilities
1. **Audio File Recognition & Transcription**: Fetches and transcribes uploaded audio files (MP3, WAV, M4A, AAC, FLAC, OGG, OPUS) via the Node.js backend API.
2. **Device Microphone Voice Recognition**: Records live speech from the mobile device microphone with auto-gain, noise suppression, and volume level metering.
3. **Live Audio Streaming**: Streams real-time 16kHz PCM audio chunks over WebSocket to the Node.js backend for low-latency live transcription with interim and final results.
4. **Cloud Speech-to-Text Integration**: Powered by Cloud Speech-to-Text (Google Cloud Speech-to-Text / Regional Whisper) supporting **English (`en-IN`/`en`), Hindi (`hi-IN`/`hi`), and Marathi (`mr-IN`/`mr`)** for both audio input files and transcription output.
5. **Secure Authentication & Pre-flight Validation**: JWT Bearer token authentication, file integrity checks, MIME-type enforcement, duration bounds, and schema validation.

```
+-----------------------------------------------------------------------------------+
|                        READORA FLUTTER CLIENT APPLICATION                         |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  |                 Inbuilt Package: readora_audio_stt                          |  |
|  |                                                                             |  |
|  |  +------------------------+  +----------------------+  +------------------+  |  |
|  |  | AudioFileRecognizer    |  | LiveMicStreamer      |  | AudioSttState    |  |  |
|  |  | - Uploads audio files  |  | - 16kHz PCM Stream   |  | - Riverpod /     |  |  |
|  |  | - Multipart HTTP/REST  |  | - WebSocket client   |  |   StateNotifier  |  |  |
|  |  +-----------+------------+  +----------+-----------+  +--------+---------+  |  |
|  +--------------|--------------------------|-----------------------|-----------+  |
+-----------------|--------------------------|-----------------------|--------------+
                  | HTTP Multipart           | WebSocket Stream      |
                  | (Bearer JWT)             | (Bearer JWT)          |
                  v                          v                       v
+-----------------------------------------------------------------------------------+
|                          READORA NODE.JS BACKEND API                              |
|                                                                                   |
|  +----------------------+  +---------------------+  +--------------------------+  |
|  | Auth Middleware      |  | Multer Validation   |  | WebSocket STT Gateway    |  |
|  | - JWT verification   |  | - Max 50MB, formats |  | - Connection auth        |  |
|  | - User context       |  | - en, hi, mr checks |  | - Backpressure buffer    |  |
|  +----------+-----------+  +----------+----------+  +------------+-------------+  |
|             |                         |                          |                |
|             +-------------------------+--------------------------+                |
|                                       v                                           |
|                     +------------------------------------+                        |
|                     | speechToTextService.js             |                        |
|                     | - Google Cloud Speech Client       |                        |
|                     | - StreamingRecognize / Batch       |                        |
|                     +-----------------+------------------+                        |
+---------------------------------------|-------------------------------------------+
                                        v
+-----------------------------------------------------------------------------------+
|                            CLOUD SPEECH-TO-TEXT                                   |
|                 (Google Cloud Speech-to-Text / Regional Whisper)                  |
|                                                                                   |
|    * English (en-IN / en-US)    * Hindi (hi-IN)    * Marathi (mr-IN)              |
|    * Word-level timestamps      * Confidence score * Automatic punctuation        |
+-----------------------------------------------------------------------------------+
```

---

## 2. Inbuilt Package File Structure

The package is embedded as a modular internal sub-package inside the Flutter project under `packages/readora_audio_stt`:

```
c:\Users\PC\OneDrive\Desktop\Flutter\texttospeech\
  └── packages/
      └── readora_audio_stt/
          ├── pubspec.yaml
          ├── README.md
          ├── lib/
          │   ├── readora_audio_stt.dart                     # Main entry-point & exports
          │   ├── config/
          │   │   ├── stt_config.dart                       # Sample rate, endpoints, languages
          │   │   └── stt_language.dart                     # en, hi, mr definitions
          │   ├── domain/
          │   │   ├── audio_stt_result.dart                 # Transcript, confidence, words
          │   │   ├── timed_word.dart                       # startMs, endMs, word text
          │   │   └── live_stt_event.dart                   # Interim, final, error events
          │   ├── services/
          │   │   ├── audio_file_stt_service.dart           # HTTP multipart file upload
          │   │   ├── live_mic_recorder_service.dart        # Device mic PCM capture
          │   │   └── live_stt_websocket_service.dart       # WebSocket bidirectional stream
          │   ├── presentation/
          │   │   ├── providers/
          │   │   │   └── audio_stt_provider.dart           # Riverpod state controller
          │   │   └── widgets/
          │   │       ├── live_recording_visualizer.dart    # Waveform & pulse animation
          │   │       └── language_segmented_control.dart   # EN | HI | MR toggle
          │   └── utils/
          │       ├── audio_format_validator.dart           # Client-side file checks
          │       └── pcm_converter.dart                    # Sample rate conversion
          └── test/
              └── audio_stt_service_test.dart
```

---

## 3. Supported Languages & Speech Configuration

The package natively supports three languages for both input audio and recognized transcript output:

| Language | Language Code | Cloud STT Locale | Script | Engine Preference |
| :--- | :--- | :--- | :--- | :--- |
| **English** | `en` | `en-IN` (Indian English) / `en-US` | Latin | Cloud Speech-to-Text / Whisper |
| **Hindi** | `hi` | `hi-IN` (हिन्दी) | Devanagari | Cloud Speech-to-Text (v2 model) |
| **Marathi** | `mr` | `mr-IN` (मराठी) | Devanagari | Cloud Speech-to-Text (v2 Chirp/Universal) |

### Language Model Definition (`lib/config/stt_language.dart`)
```dart
enum SttLanguage {
  english(code: 'en', bcp47: 'en-IN', displayName: 'English', nativeName: 'English'),
  hindi(code: 'hi', bcp47: 'hi-IN', displayName: 'Hindi', nativeName: 'हिन्दी'),
  marathi(code: 'mr', bcp47: 'mr-IN', displayName: 'Marathi', nativeName: 'मराठी');

  final String code;
  final String bcp47;
  final String displayName;
  final String nativeName;

  const SttLanguage({
    required this.code,
    required this.bcp47,
    required this.displayName,
    required this.nativeName,
  });

  static SttLanguage fromCode(String code) {
    final clean = code.toLowerCase().trim();
    if (clean == 'hi' || clean == 'hin' || clean == 'hindi') return SttLanguage.hindi;
    if (clean == 'mr' || clean == 'mar' || clean == 'marathi') return SttLanguage.marathi;
    return SttLanguage.english;
  }
}
```

---

## 4. Mobile Client Implementation (Flutter Package)

### 4.1 Inbuilt Package `pubspec.yaml`
```yaml
name: readora_audio_stt
description: Inbuilt Audio Recognition & Speech-to-Text Package for Readora with File & Live Microphone Streaming.
version: 1.0.0
publish_to: 'none'

environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: ">=3.10.0"

dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  web_socket_channel: ^3.0.1
  record: ^5.2.0
  path: ^1.9.0
  flutter_riverpod: ^2.5.1
  permission_handler: ^11.3.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

### 4.2 Data Models (`lib/domain/audio_stt_result.dart`)
```dart
import 'timed_word.dart';

class AudioSttResult {
  final bool success;
  final String transcript;
  final String language;
  final double confidence;
  final List<TimedWord> timedWords;
  final String? audioPath;

  const AudioSttResult({
    required this.success,
    required this.transcript,
    required this.language,
    this.confidence = 0.95,
    this.timedWords = const [],
    this.audioPath,
  });

  factory AudioSttResult.fromJson(Map<String, dynamic> json) {
    final rawWords = json['words'] as List? ?? [];
    return AudioSttResult(
      success: json['success'] ?? true,
      transcript: json['transcript'] ?? '',
      language: json['language'] ?? 'en',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.95,
      timedWords: rawWords.map((w) => TimedWord.fromJson(Map<String, dynamic>.from(w))).toList(),
      audioPath: json['audioPath'],
    );
  }
}
```

### 4.3 Uploaded Audio File Transcription (`lib/services/audio_file_stt_service.dart`)
```dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/stt_config.dart';
import '../config/stt_language.dart';
import '../domain/audio_stt_result.dart';

class AudioFileSttService {
  final http.Client _client;
  final String baseUrl;

  AudioFileSttService({http.Client? client, required this.baseUrl})
      : _client = client ?? http.Client();

  Future<AudioSttResult> transcribeAudioFile({
    required String filePath,
    required SttLanguage language,
    required String jwtToken,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('Audio file not found at path: $filePath');
    }

    final fileSize = file.lengthSync();
    if (fileSize > 50 * 1024 * 1024) {
      throw Exception('Audio file exceeds maximum size limit of 50 MB.');
    }

    final uri = Uri.parse('$baseUrl/api/files/speech-to-text');
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $jwtToken';
    request.fields['language'] = language.code;
    request.fields['bcp47'] = language.bcp47;

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
        filename: filePath.split(Platform.pathSeparator).last,
      ),
    );

    final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body);
      throw Exception(errorBody['message'] ?? 'Transcription failed with status ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return AudioSttResult.fromJson(data);
  }
}
```

### 4.4 Live Device Microphone Streaming (`lib/services/live_stt_websocket_service.dart`)
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/stt_language.dart';
import '../domain/live_stt_event.dart';

class LiveSttWebSocketService {
  final String baseWsUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  LiveSttWebSocketService({required this.baseWsUrl});

  Stream<LiveSttEvent> connectAndStream({
    required Stream<Uint8List> pcmAudioStream,
    required SttLanguage language,
    required String jwtToken,
  }) {
    final controller = StreamController<LiveSttEvent>();

    final uri = Uri.parse('$baseWsUrl/api/files/live-stt?token=$jwtToken&language=${language.code}&bcp47=${language.bcp47}&sampleRate=16000');
    _channel = WebSocketChannel.connect(uri);

    // 1. Pipe incoming audio chunks to the WebSocket
    final audioSub = pcmAudioStream.listen(
      (chunk) {
        _channel?.sink.add(chunk);
      },
      onError: (err) {
        controller.add(LiveSttErrorEvent(err.toString()));
      },
      onDone: () {
        // Send EOF control packet
        _channel?.sink.add(jsonEncode({'action': 'STOP'}));
      },
    );

    // 2. Receive live transcripts from backend
    _subscription = _channel?.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          if (data['isFinal'] == true) {
            controller.add(LiveSttFinalEvent(
              transcript: data['transcript'],
              confidence: (data['confidence'] as num?)?.toDouble() ?? 0.95,
              words: data['words'] ?? [],
            ));
          } else {
            controller.add(LiveSttInterimEvent(
              partialTranscript: data['transcript'],
            ));
          }
        } catch (e) {
          controller.add(LiveSttErrorEvent('Parse error: $e'));
        }
      },
      onError: (err) {
        controller.add(LiveSttErrorEvent(err.toString()));
      },
      onDone: () {
        audioSub.cancel();
        controller.close();
      },
    );

    return controller.stream;
  }

  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
```

---

## 5. Node.js Backend API Implementation

### 5.1 Route Definition (`routes/fileRoutes.js`)
```javascript
const express = require("express");
const multer = require("multer");
const path = require("path");
const { protect } = require("../middleware/authMiddleware");
const { speechToText, liveStreamingStt } = require("../controllers/fileController");

const router = express.Router();

const audioUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, path.join(__dirname, "../uploads")),
    filename: (req, file, cb) => {
      const unique = `${Date.now()}_${Math.round(Math.random() * 1e9)}`;
      cb(null, `stt_${unique}${path.extname(file.originalname).toLowerCase()}`);
    },
  }),
  limits: { fileSize: 50 * 1024 * 1024 }, // 50 MB
  fileFilter: (req, file, cb) => {
    const allowed = new Set([".mp3", ".wav", ".m4a", ".aac", ".ogg", ".flac", ".opus"]);
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowed.has(ext)) return cb(null, true);
    cb(new Error(`Unsupported audio format: ${ext}. Supported: MP3, WAV, M4A, AAC, OGG, FLAC, OPUS.`));
  },
});

// Authenticated audio file transcription
router.post("/speech-to-text", protect, audioUpload.single("file"), speechToText);

module.exports = router;
```

### 5.2 Controller Implementation (`controllers/fileController.js`)
```javascript
const fs = require("fs");
const { transcribeWithCloudStt } = require("../services/cloudSpeechService");

const speechToText = async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ success: false, message: "No audio file uploaded." });
  }

  const audioPath = req.file.path;
  const rawLang = (req.body.language || "en").toLowerCase().trim();
  const validLanguages = { en: "en-IN", hi: "hi-IN", mr: "mr-IN" };
  const bcp47 = validLanguages[rawLang] || "en-IN";

  try {
    // Recognize audio using Cloud Speech-to-Text
    const result = await transcribeWithCloudStt({
      filePath: audioPath,
      languageCode: bcp47,
      originalLanguage: rawLang,
    });

    return res.status(200).json({
      success: true,
      transcript: result.transcript,
      language: rawLang,
      confidence: result.confidence,
      words: result.words || [],
    });
  } catch (error) {
    console.error("[STT Error]:", error);
    return res.status(500).json({
      success: false,
      message: error.message || "Cloud Speech-to-Text transcription failed.",
    });
  } finally {
    // Delete temp file after processing
    if (audioPath && fs.existsSync(audioPath)) {
      try {
        fs.unlinkSync(audioPath);
      } catch (_) {}
    }
  }
};
```

### 5.3 Cloud Speech-to-Text Integration (`services/cloudSpeechService.js`)
```javascript
const fs = require("fs");
const speech = require("@google-cloud/speech");

// Initialize Google Cloud Speech Client
const speechClient = new speech.SpeechClient({
  keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
});

/**
 * Transcribe audio file with Google Cloud Speech-to-Text
 */
const transcribeWithCloudStt = async ({ filePath, languageCode, originalLanguage }) => {
  const fileBytes = fs.readFileSync(filePath);
  const audio = { content: fileBytes.toString("base64") };

  const config = {
    enableWordTimeOffsets: true,
    enableAutomaticPunctuation: true,
    languageCode: languageCode, // 'en-IN', 'hi-IN', or 'mr-IN'
    model: "latest_long",
    useEnhanced: true,
  };

  const request = {
    audio: audio,
    config: config,
  };

  const [response] = await speechClient.recognize(request);
  const results = response.results || [];

  let fullTranscript = "";
  const timedWords = [];

  for (const result of results) {
    const alternative = result.alternatives[0];
    if (alternative) {
      fullTranscript += (fullTranscript ? " " : "") + alternative.transcript.trim();

      if (alternative.words) {
        for (const w of alternative.words) {
          const startMs = Math.round(
            (Number(w.startTime.seconds || 0) * 1000) +
            (Number(w.startTime.nanos || 0) / 1e6)
          );
          const endMs = Math.round(
            (Number(w.endTime.seconds || 0) * 1000) +
            (Number(w.endTime.nanos || 0) / 1e6)
          );
          timedWords.push({
            word: w.word,
            startMs: startMs,
            endMs: endMs,
          });
        }
      }
    }
  }

  return {
    transcript: fullTranscript,
    language: originalLanguage,
    confidence: results[0]?.alternatives[0]?.confidence || 0.95,
    words: timedWords,
  };
};

/**
 * Live WebSocket Streaming Recognize
 */
const setupStreamingStt = (ws, req) => {
  const language = req.query.language || "en";
  const bcp47 = language === "mr" ? "mr-IN" : language === "hi" ? "hi-IN" : "en-IN";

  const request = {
    config: {
      encoding: "LINEAR16",
      sampleRateHertz: 16000,
      languageCode: bcp47,
      enableAutomaticPunctuation: true,
      enableWordTimeOffsets: true,
    },
    interimResults: true,
  };

  const recognizeStream = speechClient
    .streamingRecognize(request)
    .on("error", (err) => {
      ws.send(JSON.stringify({ error: err.message }));
    })
    .on("data", (data) => {
      const result = data.results[0];
      if (result && result.alternatives[0]) {
        ws.send(
          JSON.stringify({
            isFinal: result.isFinal,
            transcript: result.alternatives[0].transcript,
            confidence: result.alternatives[0].confidence,
          })
        );
      }
    });

  ws.on("message", (chunk) => {
    if (Buffer.isBuffer(chunk)) {
      recognizeStream.write(chunk);
    }
  });

  ws.on("close", () => {
    recognizeStream.end();
  });
};

module.exports = {
  transcribeWithCloudStt,
  setupStreamingStt,
};
```

---

## 6. Step-by-Step Package Creation Flow

Follow these execution steps to create and link the package in your Flutter application:

### Step 1: Scaffold Package Structure
Run inside `c:\Users\PC\OneDrive\Desktop\Flutter\texttospeech`:
```bash
# 1. Create packages directory
mkdir packages
cd packages

# 2. Create inbuilt Flutter package
flutter create --template=package readora_audio_stt
```

### Step 2: Configure Dependencies in Parent App
In `c:\Users\PC\OneDrive\Desktop\Flutter\texttospeech\pubspec.yaml`, add the local package reference:
```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Link Inbuilt STT Package
  readora_audio_stt:
    path: packages/readora_audio_stt
```

Run in project root:
```bash
flutter pub get
```

### Step 3: Configure Device Permissions

#### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
</manifest>
```

#### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Readora requires microphone access to record and transcribe your voice in real time.</string>
```

---

## 7. Client Usage Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:readora_audio_stt/readora_audio_stt.dart';

void transcribeSampleFile(WidgetRef ref, String audioPath, String token) async {
  final sttService = AudioFileSttService(baseUrl: 'http://localhost:5000');
  
  // 1. Transcribe uploaded Marathi audio file
  final result = await sttService.transcribeAudioFile(
    filePath: audioPath,
    language: SttLanguage.marathi,
    jwtToken: token,
  );

  print('Transcript in Marathi: ${result.transcript}');
  for (var word in result.timedWords) {
    print('${word.word} [${word.startMs}ms - ${word.endMs}ms]');
  }
}
```

---

## 8. Verification & Test Plan

1. **Unit Test File Upload**:
   - Provide MP3 with English speech -> Validate `en-IN` transcription and timed words array.
   - Provide WAV with Hindi speech -> Validate `hi-IN` Devanagari text output.
   - Provide M4A with Marathi speech -> Validate `mr-IN` Devanagari output.
2. **Authentication Gate**:
   - Send request without `Authorization` header -> Verify `401 Unauthorized`.
   - Send request with expired token -> Verify `401 Token Expired`.
3. **Format & Size Validation**:
   - Send `.txt` file to audio endpoint -> Verify `400 Bad Request` (`Invalid audio file type`).
   - Send audio file > 50MB -> Verify `400 Bad Request` (`File exceeds limit`).
4. **Live Microphone Stream**:
   - Speak "नमस्कार" in Marathi -> Verify streaming interim text updates in real time and finalized Devanagari text on stop.
