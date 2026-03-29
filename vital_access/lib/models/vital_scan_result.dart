class VitalScanResult {
  final double heartRate;       // bpm
  final double hrvSdnn;         // ms — SDNN (overall HRV)
  final double hrvRmssd;        // ms — RMSSD (parasympathetic activity)
  final double respiratoryRate; // breaths/min
  final String confidence;      // 'high', 'medium', or 'low'
  final double actualFps;       // measured fps from CV Pipeline
  final DateTime timestamp;

  const VitalScanResult({
    required this.heartRate,
    required this.hrvSdnn,
    required this.hrvRmssd,
    required this.respiratoryRate,
    required this.confidence,
    required this.actualFps,
    required this.timestamp,
  });

  /// Full JSON for passing to the Claude triage pipeline.
  Map<String, dynamic> toJson() => {
        'heart_rate_bpm': heartRate,
        'hrv_sdnn_ms': hrvSdnn,
        'hrv_rmssd_ms': hrvRmssd,
        'respiratory_rate_bpm': respiratoryRate,
        'confidence': confidence,
        'actual_fps': actualFps,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Human-friendly labels for display and shareable text.
  Map<String, String> toReadableMap() => {
        'Heart Rate': '${heartRate.toStringAsFixed(0)} bpm',
        'HRV (SDNN)': '${hrvSdnn.toStringAsFixed(0)} ms',
        'HRV (RMSSD)': '${hrvRmssd.toStringAsFixed(0)} ms',
        'Respiratory Rate': '${respiratoryRate.toStringAsFixed(0)}/min',
        'Confidence': confidence[0].toUpperCase() + confidence.substring(1),
      };
}
