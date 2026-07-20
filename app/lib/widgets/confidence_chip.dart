import 'package:flutter/material.dart';

import '../theme/shoppa_theme.dart';

/// Visual confidence badge for reconciled prices (LOW / MEDIUM / HIGH).
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip({super.key, required this.confidence, this.compact = false});

  final String confidence;
  final bool compact;

  static String labelFor(String confidence) {
    final key = confidence.toLowerCase().trim();
    switch (key) {
      case 'high':
        return 'High';
      case 'medium':
        return 'Medium';
      case 'low':
        return 'Low';
      default:
        return confidence.isEmpty ? 'Unknown' : confidence;
    }
  }

  static Color colorFor(String confidence) {
    switch (confidence.toLowerCase().trim()) {
      case 'high':
        return ShoppaColors.green;
      case 'medium':
        return ShoppaColors.amber;
      case 'low':
        return ShoppaColors.rose;
      default:
        return ShoppaColors.mist;
    }
  }

  static String legendHint(String confidence) {
    switch (confidence.toLowerCase().trim()) {
      case 'high':
        return 'Multiple recent sources';
      case 'medium':
        return 'Some corroboration';
      case 'low':
        return 'Limited data';
      default:
        return 'Confidence unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(confidence);
    final label = labelFor(confidence);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        compact ? label : 'Confidence · $label',
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
