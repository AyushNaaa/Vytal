import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../config/theme.dart';
import '../models/vital_scan_result.dart';
import '../providers/session_provider.dart';
import '../services/vitals_service.dart';
import '../widgets/vitals_display.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  // ---- Camera ----
  CameraController? _cameraController;
  bool _cameraReady = false;

  // ---- Vitals service ----
  VitalsService? _vitalsService;
  bool _usingMock = false;

  // ---- Live state ----
  CvStatusResponse _status = CvStatusResponse.initial();
  CvVitalsResponse? _latestVitals;
  bool _showFinalVitals = false;
  VitalScanResult? _finalResult;

  // ---- Timers ----
  Timer? _statusTimer;
  Timer? _vitalsTimer;
  Timer? _finalDisplayTimer;

  // ---- Oval border pulse animation ----
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> _init() async {
    await _initCamera();
    await _initVitalsService();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) return;
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      _showCameraPermissionDialog();
    }
  }

  Future<void> _initVitalsService() async {
    // Respect demo mode toggled from the language screen
    if (context.read<SessionProvider>().demoMode) {
      _vitalsService = MockVitalsService();
      _usingMock = true;
      await _startMeasurement();
      return;
    }

    final baseUrl =
        dotenv.env['CV_PIPELINE_URL'] ?? 'http://127.0.0.1:8000';

    final cvService = CvPipelineVitalsService(baseUrl: baseUrl);
    final reachable = await cvService.isReachable();

    if (!mounted) return;

    if (!reachable) {
      final useMock = await _showServerNotFoundDialog();
      if (!mounted) return;
      if (useMock) {
        _vitalsService = MockVitalsService();
        _usingMock = true;
      } else {
        // Retry once
        final retry = await cvService.isReachable();
        if (!mounted) return;
        _vitalsService = retry ? cvService : MockVitalsService();
        _usingMock = !retry;
      }
    } else {
      _vitalsService = cvService;
    }

    await _startMeasurement();
  }

  Future<void> _startMeasurement() async {
    if (_vitalsService == null) return;

    await _vitalsService!.startSession();
    _startFrameStream();
    _startPollingTimers();
  }

  // ---------------------------------------------------------------------------
  // Frame streaming
  // ---------------------------------------------------------------------------

  void _startFrameStream() {
    if (_cameraController == null || !_cameraReady) return;

    _cameraController!.startImageStream((CameraImage image) {
      _vitalsService?.sendFrame(image).then((resp) {
        if (!mounted || resp == null) return;

        // Auto-switch to mock after repeated failures
        if (_vitalsService is CvPipelineVitalsService &&
            (_vitalsService as CvPipelineVitalsService).hasRepeatedFailures) {
          _switchToMock();
        }
      });
    });
  }

  void _stopFrameStream() {
    try {
      _cameraController?.stopImageStream();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Polling timers
  // ---------------------------------------------------------------------------

  void _startPollingTimers() {
    // Status: every 500ms for live face/motion/brightness feedback
    _statusTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      try {
        final status = await _vitalsService!.getStatus();
        if (!mounted) return;
        setState(() => _status = status);
      } catch (_) {}
    });

    // Vitals: every 2 seconds
    _vitalsTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      try {
        final vitals = await _vitalsService!.getVitals();
        if (!mounted) return;
        setState(() => _latestVitals = vitals);

        if (vitals.measurementComplete) {
          _onMeasurementComplete(vitals);
        }
      } catch (_) {}
    });
  }

  void _stopPollingTimers() {
    _statusTimer?.cancel();
    _vitalsTimer?.cancel();
    _statusTimer = null;
    _vitalsTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Measurement complete
  // ---------------------------------------------------------------------------

  void _onMeasurementComplete(CvVitalsResponse vitals) {
    _stopPollingTimers();
    _stopFrameStream();

    final result = VitalScanResult(
      heartRate: vitals.hr ?? 72.0,
      hrvSdnn: vitals.hrvSdnn ?? 45.0,
      hrvRmssd: vitals.hrvRmssd ?? 38.0,
      respiratoryRate: vitals.rr ?? 15.0,
      confidence: vitals.confidence,
      actualFps: vitals.actualFps,
      timestamp: DateTime.now(),
    );

    setState(() {
      _finalResult = result;
      _showFinalVitals = true;
    });

    // Show vitals for 3 seconds, then navigate to chat
    _finalDisplayTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      context.read<SessionProvider>().setVitalScanResult(result);
      Navigator.of(context).pushReplacementNamed('/chat');
    });
  }

  // ---------------------------------------------------------------------------
  // Fallback / error helpers
  // ---------------------------------------------------------------------------

  void _switchToMock() {
    if (_usingMock) return;
    _usingMock = true;
    _vitalsService = MockVitalsService();
    _vitalsService!.startSession();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Using estimated vitals'),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _showServerNotFoundDialog() async {
    final lang = context.read<SessionProvider>().language;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Vitals Server'),
            content: Text(t(lang, 'server_not_found')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t(lang, 'retry')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t(lang, 'demo_vitals')),
              ),
            ],
          ),
        ) ??
        true;
  }

  void _showCameraPermissionDialog() {
    final lang = context.read<SessionProvider>().language;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Camera Access Required'),
        content: const Text(
            'VitalAccess needs camera access to measure your heart rate and other vitals.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _vitalsService = MockVitalsService();
              _usingMock = true;
              _vitalsService!.startSession();
              _startPollingTimers();
            },
            child: Text(t(lang, 'demo_vitals')),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _stopPollingTimers();
    _stopFrameStream();
    _finalDisplayTimer?.cancel();
    _pulseController.dispose();
    _vitalsService?.endSession();
    _cameraController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SessionProvider>().language;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ---- Camera preview ----
          if (_cameraReady && _cameraController != null)
            CameraPreview(_cameraController!)
          else
            Container(color: const Color(0xFF1A1A2E)),

          // ---- Main overlay ----
          _buildOverlay(context, lang),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, String lang) {
    if (_showFinalVitals && _finalResult != null) {
      return _buildFinalVitalsOverlay(lang);
    }
    return _buildScanningOverlay(context, lang);
  }

  // ---------------------------------------------------------------------------
  // Scanning overlay
  // ---------------------------------------------------------------------------

  Widget _buildScanningOverlay(BuildContext context, String lang) {
    final progress = _latestVitals != null
        ? (_latestVitals!.framesCollected / 900.0).clamp(0.0, 1.0)
        : (_status.secondsElapsed / 30.0).clamp(0.0, 1.0);

    final remaining = _status.secondsRemaining.ceil();
    final quality = _status.signalQualityScore;

    return SafeArea(
      child: Column(
        children: [
          // Top bar
          _buildTopBar(lang),

          const Spacer(),

          // Face oval guide
          _buildFaceOval(quality),

          const SizedBox(height: 24),

          // Guidance message
          _buildGuidanceText(lang, progress),

          const SizedBox(height: 16),

          // Signal quality dots
          _buildQualityDots(quality, lang),

          const Spacer(),

          // Countdown + progress
          _buildProgressSection(remaining, progress),

          // Provisional HR
          if (_latestVitals?.hr != null) _buildProvisionalHr(),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTopBar(String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              t(lang, 'scan_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_usingMock)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.urgent.withAlpha(200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'DEMO',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            )
          else
            TextButton(
              onPressed: _switchToMock,
              child: const Text(
                'Demo',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFaceOval(double quality) {
    final Color borderColor;
    final bool doPulse;

    if (quality > 0.6) {
      borderColor = AppColors.qualityHigh;
      doPulse = true;
    } else if (quality > 0.4) {
      borderColor = AppColors.qualityMedium;
      doPulse = false;
    } else {
      borderColor = AppColors.qualityLow;
      doPulse = false;
    }

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) {
        final width = doPulse ? 2.5 + _pulseAnim.value * 1.5 : 2.5;
        return Container(
          width: 220,
          height: 280,
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: width),
            borderRadius: BorderRadius.circular(200),
          ),
          child: _status.faceDetected
              ? null
              : Center(
                  child: Icon(
                    Icons.face_outlined,
                    color: Colors.white.withAlpha(100),
                    size: 64,
                  ),
                ),
        );
      },
    );
  }

  Widget _buildGuidanceText(String lang, double progress) {
    final String key;
    if (!_status.faceDetected) {
      key = 'face_guide_no_face';
    } else if (_status.motionLevel > 0.7) {
      key = 'face_guide_motion';
    } else if (!_status.brightnessOk) {
      key = 'face_guide_brightness';
    } else if (progress < 0.3) {
      key = 'face_guide_starting';
    } else if (progress < 0.7) {
      key = 'face_guide_good';
    } else {
      key = 'face_guide_almost';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: Text(
        t(lang, key),
        key: ValueKey(key),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
        ),
      ),
    );
  }

  Widget _buildQualityDots(double quality, String lang) {
    final filledDots = (quality * 5).round().clamp(0, 5);

    Color dotColor;
    if (quality > 0.7) {
      dotColor = AppColors.qualityHigh;
    } else if (quality > 0.4) {
      dotColor = AppColors.qualityMedium;
    } else {
      dotColor = AppColors.qualityLow;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${t(lang, 'signal_quality')}: ',
          style: TextStyle(
            color: Colors.white.withAlpha(180),
            fontSize: 13,
          ),
        ),
        ...List.generate(5, (i) {
          return Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filledDots
                  ? dotColor
                  : Colors.white.withAlpha(50),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildProgressSection(int remaining, double progress) {
    return Column(
      children: [
        // Circular progress ring with countdown
        SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 4,
                backgroundColor: Colors.white.withAlpha(40),
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress > 0.6
                      ? AppColors.qualityHigh
                      : AppColors.primary,
                ),
              ),
              Text(
                '${remaining}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t(context.read<SessionProvider>().language, 'scan_instruction'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withAlpha(160),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildProvisionalHr() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AnimatedOpacity(
        opacity: _latestVitals?.hr != null ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 600),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(25),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite_rounded,
                  color: AppColors.emergency, size: 16),
              const SizedBox(width: 6),
              Text(
                '${_latestVitals?.hr?.toStringAsFixed(0) ?? '--'} bpm',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Final vitals overlay (shown for 3 seconds before navigating)
  // ---------------------------------------------------------------------------

  Widget _buildFinalVitalsOverlay(String lang) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text(
                t(lang, 'face_guide_complete'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Moving to symptom intake...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.subtle,
                ),
              ),
              const SizedBox(height: 32),
              VitalsDisplay(vitals: _finalResult!),
            ],
          ),
        ),
      ),
    );
  }
}
