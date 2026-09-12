/// Small shared widgets.
library;

import 'package:flutter/material.dart';

import '../models/food.dart';
import 'theme.dart';

/// A labelled bar comparing a planned nutrient against its target.
class NutrientBar extends StatelessWidget {
  const NutrientBar({
    super.key,
    required this.label,
    required this.planned,
    required this.target,
    required this.unit,
    this.caption,
  });

  final String label;
  final double planned;
  final double target;
  final String unit;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = target <= 0 ? 1.0 : planned / target;
    final color = nutrientStatusColor(scheme, ratio);
    final pct = ((ratio - 1) * 100);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(
                '${planned.round()} / ${target.round()} $unit',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(height: 8, color: scheme.surfaceContainerHighest),
                FractionallySizedBox(
                  widthFactor: ratio.clamp(0.0, 1.0).toDouble(),
                  child: Container(height: 8, color: color),
                ),
              ],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!,
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// Compact macro summary used on meal and day cards.
class MacroRow extends StatelessWidget {
  const MacroRow({super.key, required this.n, this.dense = false});

  final Nutrients n;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: dense ? 12 : 13,
      color: scheme.onSurfaceVariant,
    );
    return Wrap(
      spacing: 12,
      children: [
        Text('${n.kcal.round()} kcal', style: style),
        Text('P ${n.protein.round()}g', style: style),
        Text('F ${n.fat.round()}g', style: style),
        Text('C ${n.carb.round()}g', style: style),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
