import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../config/theme.dart';
import '../models/health_summary.dart';
import '../providers/session_provider.dart';
import '../services/claude_service.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with TickerProviderStateMixin {
  // Pipeline step labels (indices match _stepIndex)
  static const _steps = [
    'processing_vitals',
    'processing_symptoms',
    'processing_urgency',
    'processing_summary',
  ];

  int _stepIndex = 0;
  bool _hasError = false;
  String _errorMessage = '';

  // Pulse animation on the heart icon
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Step-label fade animation
  late final AnimationController _labelCtrl;
  late final Animation<double> _labelAnim;

  // Timer that advances the displayed step label during the API call
  Timer? _stepTimer;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _labelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..value = 1.0;

    _labelAnim =
        CurvedAnimation(parent: _labelCtrl, curve: Curves.easeInOut);

    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _labelCtrl.dispose();
    _stepTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Pipeline execution
  // ---------------------------------------------------------------------------

  Future<void> _run() async {
    setState(() {
      _hasError = false;
      _stepIndex = 0;
    });

    // Advance the step label every ~3 seconds while the real call runs.
    _stepTimer?.cancel();
    _stepTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_stepIndex < _steps.length - 1) _advanceStep();
    });

    final session = context.read<SessionProvider>();
    final vitals = session.vitalScanResult;
    final intake = session.symptomIntake;
    final language = session.language;

    if (vitals == null || intake == null) {
      _stepTimer?.cancel();
      _showError('Session data missing. Please restart the scan.');
      return;
    }

    final apiKey = dotenv.env['ANTHROPIC_API_KEY'] ?? '';
    final claude = ClaudeService(apiKey: apiKey);

    try {
      final triage = await claude.runTriagePipeline(
        vitals: vitals,
        symptomSummary: intake.structuredSummary,
        language: language,
      );

      _stepTimer?.cancel();

      // Jump to final step label before navigating
      await _advanceToStep(_steps.length - 1);
      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;

      final summary = HealthSummary(
        timestamp: DateTime.now(),
        language: language,
        vitals: vitals,
        symptoms: intake,
        triage: triage,
      );

      session.setHealthSummary(summary);
      Navigator.of(context).pushReplacementNamed(AppRoutes.result);
    } on ClaudeApiException catch (e) {
      _stepTimer?.cancel();
      _showError(e.message);
    } catch (e) {
      _stepTimer?.cancel();
      _showError('Something went wrong. Please try again.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _errorMessage = message;
    });
    _pulseCtrl.stop();
  }

  Future<void> _advanceStep() async {
    if (!mounted) return;
    await _labelCtrl.reverse();
    if (!mounted) return;
    setState(() {
      if (_stepIndex < _steps.length - 1) _stepIndex++;
    });
    _labelCtrl.forward();
  }

  Future<void> _advanceToStep(int target) async {
    while (_stepIndex < target && mounted) {
      await _advanceStep();
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SessionProvider>().language;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _hasError ? _buildErrorView(lang) : _buildLoadingView(lang),
      ),
    );
  }

  Widget _buildLoadingView(String lang) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPulsingHeart(),
            const SizedBox(height: 48),
            _buildStepLabel(lang),
            const SizedBox(height: 32),
            _buildStepDots(),
          ],
        ),
      ),
    );
  }

  Widget _buildPulsingHeart() {
    return ScaleTransition(
      scale: _pulseAnim,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: AppColors.primary,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepLabel(String lang) {
    return FadeTransition(
      opacity: _labelAnim,
      child: Text(
        t(lang, _steps[_stepIndex]),
        key: ValueKey(_stepIndex),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  Widget _buildStepDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_steps.length, (i) {
        final isActive = i == _stepIndex;
        final isDone = i < _stepIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: isActive ? 20 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isDone || isActive
                ? AppColors.primary
                : AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Error view
  // ---------------------------------------------------------------------------

  Widget _buildErrorView(String lang) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.emergencyLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: AppColors.emergency,
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Analysis failed',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.onSurface,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.subtle,
                  ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed(AppRoutes.language),
              child: Text(
                t(lang, 'start_over'),
                style: const TextStyle(color: AppColors.subtle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
