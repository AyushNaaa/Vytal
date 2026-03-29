import 'package:flutter/material.dart';
import '../config/theme.dart';

enum UrgencyLevel { emergency, urgent, routine, selfCare }

extension UrgencyLevelExtension on UrgencyLevel {
  Color get color {
    switch (this) {
      case UrgencyLevel.emergency:
        return AppColors.emergency;
      case UrgencyLevel.urgent:
        return AppColors.urgent;
      case UrgencyLevel.routine:
        return AppColors.routine;
      case UrgencyLevel.selfCare:
        return AppColors.selfCare;
    }
  }

  Color get lightColor {
    switch (this) {
      case UrgencyLevel.emergency:
        return AppColors.emergencyLight;
      case UrgencyLevel.urgent:
        return AppColors.urgentLight;
      case UrgencyLevel.routine:
        return AppColors.routineLight;
      case UrgencyLevel.selfCare:
        return AppColors.selfCareLight;
    }
  }

  String get label {
    switch (this) {
      case UrgencyLevel.emergency:
        return 'Seek emergency care now';
      case UrgencyLevel.urgent:
        return 'See a doctor within 48 hours';
      case UrgencyLevel.routine:
        return 'Schedule a visit when convenient';
      case UrgencyLevel.selfCare:
        return 'Monitor at home';
    }
  }

  IconData get icon {
    switch (this) {
      case UrgencyLevel.emergency:
        return Icons.emergency_rounded;
      case UrgencyLevel.urgent:
        return Icons.schedule_rounded;
      case UrgencyLevel.routine:
        return Icons.calendar_today_rounded;
      case UrgencyLevel.selfCare:
        return Icons.home_rounded;
    }
  }

  /// The JSON string value returned by the Claude triage pipeline.
  String get jsonValue {
    switch (this) {
      case UrgencyLevel.emergency:
        return 'emergency';
      case UrgencyLevel.urgent:
        return 'urgent';
      case UrgencyLevel.routine:
        return 'routine';
      case UrgencyLevel.selfCare:
        return 'selfCare';
    }
  }
}

class TriageResult {
  final UrgencyLevel urgency;
  final String clinicalReasoning;
  final String plainExplanation;
  final String watchFor;

  const TriageResult({
    required this.urgency,
    required this.clinicalReasoning,
    required this.plainExplanation,
    required this.watchFor,
  });

  factory TriageResult.fromJson(Map<String, dynamic> json) {
    final urgencyStr = json['urgency'] as String? ?? 'urgent';
    final urgency = UrgencyLevel.values.firstWhere(
      (u) => u.jsonValue == urgencyStr,
      orElse: () => UrgencyLevel.urgent,
    );
    return TriageResult(
      urgency: urgency,
      clinicalReasoning: json['clinicalReasoning'] as String? ?? '',
      plainExplanation: json['plainExplanation'] as String? ?? '',
      watchFor: json['watchFor'] as String? ?? '',
    );
  }

  /// Safe fallback used when the pipeline call fails.
  factory TriageResult.fallback() => const TriageResult(
        urgency: UrgencyLevel.urgent,
        clinicalReasoning: 'Unable to complete analysis.',
        plainExplanation:
            'We were unable to complete the triage analysis. Please consult a healthcare professional.',
        watchFor: 'Any worsening symptoms — seek care immediately.',
      );
}
