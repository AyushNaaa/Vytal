import 'package:uuid/uuid.dart';
import 'vital_scan_result.dart';
import 'symptom_intake.dart';
import 'triage_result.dart';

class HealthSummary {
  final String sessionId;
  final DateTime timestamp;
  final String language;
  final VitalScanResult vitals;
  final SymptomIntake symptoms;
  final TriageResult triage;

  HealthSummary({
    String? sessionId,
    required this.timestamp,
    required this.language,
    required this.vitals,
    required this.symptoms,
    required this.triage,
  }) : sessionId = sessionId ?? const Uuid().v4().substring(0, 8).toUpperCase();

  /// Formats the summary as plain text for sharing via WhatsApp, SMS, or email.
  String toShareableText() {
    final vitalsMap = vitals.toReadableMap();
    final timestampStr =
        '${timestamp.day}/${timestamp.month}/${timestamp.year} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

    final buffer = StringBuffer();

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('VitalAccess Health Summary');
    buffer.writeln('$timestampStr  •  Session: $sessionId');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');

    buffer.writeln('\n📊 VITALS');
    vitalsMap.forEach((label, value) {
      buffer.writeln('  $label: $value');
    });

    if (symptoms.structuredSummary.isNotEmpty) {
      buffer.writeln('\n🗣 SYMPTOMS REPORTED');
      buffer.writeln(symptoms.structuredSummary);
    }

    buffer.writeln('\n🔔 TRIAGE RESULT');
    buffer.writeln('  ${triage.urgency.label.toUpperCase()}');
    buffer.writeln('\n${triage.plainExplanation}');

    if (triage.watchFor.isNotEmpty) {
      buffer.writeln('\n⚠️ SEEK IMMEDIATE CARE IF:');
      buffer.writeln(triage.watchFor);
    }

    buffer.writeln('\n━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln(
        '⚠ This is NOT a medical diagnosis. Please consult a healthcare professional.');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');

    return buffer.toString();
  }
}
