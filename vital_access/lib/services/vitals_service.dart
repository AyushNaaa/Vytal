import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
// CV Pipeline Response Models
// ---------------------------------------------------------------------------

class FrameResponse {
  final bool frameAccepted;
  final int framesCollected;
  final int framesNeeded;
  final String quality; // "good" | "poor" | "no_face"
  final double progressPercent;

  const FrameResponse({
    required this.frameAccepted,
    required this.framesCollected,
    required this.framesNeeded,
    required this.quality,
    required this.progressPercent,
  });

  factory FrameResponse.fromJson(Map<String, dynamic> json) => FrameResponse(
        frameAccepted: json['frame_accepted'] as bool,
        framesCollected: json['frames_collected'] as int,
        framesNeeded: json['frames_needed'] as int? ?? 900,
        quality: json['quality'] as String? ?? 'poor',
        progressPercent: (json['progress_percent'] as num).toDouble(),
      );
}

class CvVitalsResponse {
  final double? hr;
  final double? hrvSdnn;
  final double? hrvRmssd;
  final double? rr;
  final String confidence; // "high" | "medium" | "low"
  final bool measurementComplete;
  final int framesCollected;
  final double actualFps;

  const CvVitalsResponse({
    this.hr,
    this.hrvSdnn,
    this.hrvRmssd,
    this.rr,
    required this.confidence,
    required this.measurementComplete,
    required this.framesCollected,
    required this.actualFps,
  });

  factory CvVitalsResponse.fromJson(Map<String, dynamic> json) => CvVitalsResponse(
        hr: (json['hr'] as num?)?.toDouble(),
        hrvSdnn: (json['hrv_sdnn'] as num?)?.toDouble(),
        hrvRmssd: (json['hrv_rmssd'] as num?)?.toDouble(),
        rr: (json['rr'] as num?)?.toDouble(),
        confidence: json['confidence'] as String? ?? 'low',
        measurementComplete: json['measurement_complete'] as bool? ?? false,
        framesCollected: json['frames_collected'] as int? ?? 0,
        actualFps: (json['actual_fps'] as num?)?.toDouble() ?? 0.0,
      );
}

class CvStatusResponse {
  final double signalQualityScore;
  final double motionLevel;
  final bool faceDetected;
  final bool brightnessOk;
  final double secondsElapsed;
  final double secondsRemaining;

  const CvStatusResponse({
    required this.signalQualityScore,
    required this.motionLevel,
    required this.faceDetected,
    required this.brightnessOk,
    required this.secondsElapsed,
    required this.secondsRemaining,
  });

  factory CvStatusResponse.fromJson(Map<String, dynamic> json) => CvStatusResponse(
        signalQualityScore: (json['signal_quality_score'] as num).toDouble(),
        motionLevel: (json['motion_level'] as num).toDouble(),
        faceDetected: json['face_detected'] as bool,
        brightnessOk: json['brightness_ok'] as bool,
        secondsElapsed: (json['seconds_elapsed'] as num).toDouble(),
        secondsRemaining: (json['seconds_remaining'] as num).toDouble(),
      );

  factory CvStatusResponse.initial() => const CvStatusResponse(
        signalQualityScore: 0.0,
        motionLevel: 0.0,
        faceDetected: false,
        brightnessOk: true,
        secondsElapsed: 0.0,
        secondsRemaining: 30.0,
      );
}

// ---------------------------------------------------------------------------
// Abstract VitalsService interface
// ---------------------------------------------------------------------------

abstract class VitalsService {
  Future<void> startSession();
  Future<FrameResponse?> sendFrame(CameraImage image);
  Future<CvVitalsResponse> getVitals();
  Future<CvStatusResponse> getStatus();
  Future<void> endSession();
}

// ---------------------------------------------------------------------------
// CvPipelineVitalsService — talks to the local Python FastAPI server
// ---------------------------------------------------------------------------

class CvPipelineVitalsService implements VitalsService {
  final String baseUrl;
  final Dio _dio;

  // Backpressure guard: skip frames if previous send is still in flight
  bool _processing = false;
  int _consecutiveFailures = 0;

  static const int _maxConsecutiveFailures = 10;

  CvPipelineVitalsService({required this.baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 5),
        ));

  bool get hasRepeatedFailures => _consecutiveFailures >= _maxConsecutiveFailures;

  @override
  Future<void> startSession() async {
    _consecutiveFailures = 0;
    try {
      await _dio.post('/start');
    } on DioException catch (e) {
      throw Exception('CV Pipeline /start failed ($baseUrl): ${e.message}');
    }
  }

  @override
  Future<FrameResponse?> sendFrame(CameraImage image) async {
    // Skip if still processing the previous frame
    if (_processing) return null;
    _processing = true;

    try {
      final jpegBytes = await compute(_convertCameraImageToJpeg, image);
      if (jpegBytes == null || jpegBytes.isEmpty) return null;

      final b64 = base64Encode(jpegBytes);
      final ts = DateTime.now().millisecondsSinceEpoch / 1000.0;

      final response = await _dio.post<Map<String, dynamic>>(
        '/frame',
        data: {'frame': b64, 'timestamp': ts},
      );

      _consecutiveFailures = 0;
      return FrameResponse.fromJson(response.data!);
    } on DioException {
      _consecutiveFailures++;
      return null;
    } finally {
      _processing = false;
    }
  }

  @override
  Future<CvVitalsResponse> getVitals() async {
    final response = await _dio.get<Map<String, dynamic>>('/vitals');
    return CvVitalsResponse.fromJson(response.data!);
  }

  @override
  Future<CvStatusResponse> getStatus() async {
    final response = await _dio.get<Map<String, dynamic>>('/status');
    return CvStatusResponse.fromJson(response.data!);
  }

  @override
  Future<void> endSession() async {
    try {
      await _dio.delete('/session');
    } catch (_) {}
  }

  /// Check that the CV Pipeline server is reachable.
  Future<bool> isReachable() async {
    try {
      final resp = await _dio.get('/health');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// MockVitalsService — realistic fake vitals for demo / server-unavailable
// ---------------------------------------------------------------------------

class MockVitalsService implements VitalsService {
  DateTime? _startTime;
  final _rng = Random();
  static const _scanDuration = Duration(seconds: 30);

  @override
  Future<void> startSession() async {
    _startTime = DateTime.now();
  }

  @override
  Future<FrameResponse?> sendFrame(CameraImage image) async {
    // Mock: just track progress
    final elapsed = _elapsed;
    final progress = (elapsed.inMilliseconds / _scanDuration.inMilliseconds)
        .clamp(0.0, 1.0);
    return FrameResponse(
      frameAccepted: true,
      framesCollected: (progress * 900).round(),
      framesNeeded: 900,
      quality: 'good',
      progressPercent: progress * 100,
    );
  }

  @override
  Future<CvVitalsResponse> getVitals() async {
    final progress = (_elapsed.inMilliseconds / _scanDuration.inMilliseconds)
        .clamp(0.0, 1.0);
    final complete = progress >= 1.0;

    double? hr;
    if (progress >= 0.33) {
      // Show provisional HR after 10 sec
      hr = 65.0 + _rng.nextInt(36).toDouble() + _rng.nextDouble();
    }

    return CvVitalsResponse(
      hr: hr,
      hrvSdnn: complete ? 30.0 + _rng.nextInt(35).toDouble() : null,
      hrvRmssd: complete ? 25.0 + _rng.nextInt(25).toDouble() : null,
      rr: complete ? 12.0 + _rng.nextInt(9).toDouble() : null,
      confidence: complete ? 'high' : 'medium',
      measurementComplete: complete,
      framesCollected: (progress * 900).round(),
      actualFps: 29.5 + _rng.nextDouble(),
    );
  }

  @override
  Future<CvStatusResponse> getStatus() async {
    final elapsed = _elapsed;
    final progress = (elapsed.inMilliseconds / _scanDuration.inMilliseconds)
        .clamp(0.0, 1.0);

    return CvStatusResponse(
      signalQualityScore: progress > 0.1 ? 0.8 + _rng.nextDouble() * 0.2 : 0.3,
      motionLevel: _rng.nextDouble() * 0.15,
      faceDetected: true,
      brightnessOk: true,
      secondsElapsed: elapsed.inMilliseconds / 1000.0,
      secondsRemaining: (_scanDuration.inSeconds - elapsed.inSeconds)
          .clamp(0, _scanDuration.inSeconds)
          .toDouble(),
    );
  }

  @override
  Future<void> endSession() async {
    _startTime = null;
  }

  Duration get _elapsed {
    if (_startTime == null) return Duration.zero;
    return DateTime.now().difference(_startTime!);
  }
}

// ---------------------------------------------------------------------------
// Frame conversion (runs in compute isolate — off the UI thread)
// ---------------------------------------------------------------------------

/// Converts a CameraImage (YUV420 or BGRA8888) to a JPEG byte array.
/// Downsamples to 320×240 for efficiency — sufficient for rPPG face detection.
Uint8List? _convertCameraImageToJpeg(CameraImage cameraImage) {
  try {
    img.Image? converted;

    final format = cameraImage.format.group;

    if (format == ImageFormatGroup.bgra8888) {
      converted = _convertBgra(cameraImage);
    } else if (format == ImageFormatGroup.yuv420) {
      converted = _convertYuv420(cameraImage);
    } else {
      return null;
    }

    if (converted == null) return null;

    // Resize to 320×240 — reduces byte size and speeds up server processing
    final resized = img.copyResize(converted, width: 320, height: 240);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
  } catch (_) {
    return null;
  }
}

img.Image? _convertBgra(CameraImage image) {
  final bytes = image.planes[0].bytes;
  final w = image.width;
  final h = image.height;
  final out = img.Image(width: w, height: h);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final i = (y * image.planes[0].bytesPerRow) + x * 4;
      if (i + 3 >= bytes.length) continue;
      out.setPixelRgb(x, y, bytes[i + 2], bytes[i + 1], bytes[i]);
    }
  }
  return out;
}

img.Image? _convertYuv420(CameraImage image) {
  final w = image.width;
  final h = image.height;
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  final out = img.Image(width: w, height: h);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final yIdx = y * yRowStride + x;
      final uvRow = (y >> 1) * uvRowStride;
      final uvCol = (x >> 1) * uvPixelStride;

      if (yIdx >= yPlane.bytes.length) continue;
      if (uvRow + uvCol >= uPlane.bytes.length) continue;
      if (uvRow + uvCol >= vPlane.bytes.length) continue;

      final yVal = yPlane.bytes[yIdx];
      final uVal = uPlane.bytes[uvRow + uvCol];
      final vVal = vPlane.bytes[uvRow + uvCol];

      final r = (yVal + 1.370705 * (vVal - 128)).round().clamp(0, 255);
      final g = (yVal - 0.698001 * (vVal - 128) - 0.337633 * (uVal - 128))
          .round()
          .clamp(0, 255);
      final b = (yVal + 1.732446 * (uVal - 128)).round().clamp(0, 255);

      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}
