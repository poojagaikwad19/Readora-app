import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageProcessingResult {
  final String path;
  final String filename;
  final String mimeType;
  final int sizeBytes;

  const ImageProcessingResult({
    required this.path,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
  });
}

class ImageProcessingService {
  static const int maxDimension = 1024;
  static const int jpegQuality = 85;

  /// Detects image format, normalizes orientation, resizes if oversized,
  /// extracts static frame for animations, and encodes to genuine JPEG.
  static Future<ImageProcessingResult> processAvatarImage(String inputPath) async {
    final file = File(inputPath);
    if (!await file.exists()) {
      throw const FormatException("This photo couldn't be opened. Please choose another photo.");
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException("This photo couldn't be opened. Please choose another photo.");
    }

    img.Image? decodedImage;

    // 1. Try decoding with package:image (supports JPEG, PNG, GIF, WebP, BMP, TIFF, TGA)
    try {
      decodedImage = img.decodeImage(bytes);
    } catch (e) {
      debugPrint('[ImageProcessingService] package:image decode notice: $e');
    }

    // 2. If package:image couldn't decode (e.g. platform-specific HEIC/HEIF), fallback to Flutter's native engine codec
    if (decodedImage == null) {
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final codec = await descriptor.instantiateCodec();
        final frameInfo = await codec.getNextFrame();
        final uiImage = frameInfo.image;
        final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final pngBytes = byteData.buffer.asUint8List();
          decodedImage = img.decodeImage(pngBytes);
        }
      } catch (e) {
        debugPrint('[ImageProcessingService] Native engine decode fallback notice: $e');
      }
    }

    if (decodedImage == null) {
      throw const FormatException("This photo couldn't be opened. Please choose another photo.");
    }

    img.Image workingImage = decodedImage;

    // 3. For animated images (e.g. GIF, animated WebP), use the first static frame
    if (workingImage.numFrames > 1) {
      workingImage = workingImage.frames.first;
    }

    // 4. Normalize EXIF orientation (rotate/flip according to camera EXIF tag)
    try {
      workingImage = img.bakeOrientation(workingImage);
    } catch (e) {
      debugPrint('[ImageProcessingService] Orientation bake notice: $e');
    }

    // 5. Resize oversized photos while preserving aspect ratio
    if (workingImage.width > maxDimension || workingImage.height > maxDimension) {
      if (workingImage.width >= workingImage.height) {
        workingImage = img.copyResize(workingImage, width: maxDimension);
      } else {
        workingImage = img.copyResize(workingImage, height: maxDimension);
      }
    }

    // 6. Convert actual image data to JPEG
    final encodedJpeg = Uint8List.fromList(img.encodeJpg(workingImage, quality: jpegQuality));

    // 7. Write to temporary file for upload
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outFilename = 'avatar_$timestamp.jpg';
    final outFile = File('${tempDir.path}/$outFilename');
    await outFile.writeAsBytes(encodedJpeg);

    return ImageProcessingResult(
      path: outFile.path,
      filename: outFilename,
      mimeType: 'image/jpeg',
      sizeBytes: encodedJpeg.length,
    );
  }
}
