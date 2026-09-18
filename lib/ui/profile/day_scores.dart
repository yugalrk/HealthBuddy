/// Your days, scored out of 100 from the evening check-in.
library;

import 'package:flutter/material.dart';

import '../../engine/day_score.dart';
import '../../models/profile.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

/// Colour for a score: green for a proper day, amber for close, red below.
Color scoreColor(ColorScheme scheme, int score) {
  if (score >= properDayScore) {
    return scheme.brightness == Brightness.dark
        ? const Color(0xFF6FCF97)
        : const Color(0xFF2E7D52);
  }
  if (score >= 60) return const Color(0xFFE08A00);
  return scheme.error;
}

/// The latest score, how the week is going, and the last two weeks at a
/// glance. Tap a day for what it lost points on.
class DayScoresCard extends StatelessWidget {
  const DayScoresCard({super.key, required this.app});
  final AppState app;

  static const _span = 14;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final log = app.scores;
    final today = app.today;

    if (log.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.emoji_events_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Answer the evening check-in on the Plan tab, and each day '
                  'gets a score out of 100 here: full marks when you hit your '
                  'protein, calories and nutrients with no junk.',
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final latest = log.days.last;
    final week = log.lastDays(7, today);
    final proper = week.where((d) => d.isProperDay).length;
    final recent = log.lastDays(_span, today);
    final avg = recent.isEmpty
        ? null
        : (recent.map((d) => d.score).reduce((a, b) => a + b) / recent.length)
            .round();
    final streak = log.properStreak;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showDayScore(context, app, latest),
              child: Row(
                children: [
                  _ScoreRing(score: latest.score, size: 76),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dayLabel(latest.date, today),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _verdict(latest.score),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latest.misses.isEmpty
                              ? 'Every goal met.'
                              : latest.misses.first,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(
                  value: '$proper of ${week.length}',
                  label: 'proper this week',
                ),
                _Stat(value: avg == null ? '–' : '$avg', label: '2-week average'),
                _Stat(
                  value: '$streak',
                  label: streak == 1 ? 'day streak' : 'days streak',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Chart(app: app, span: _span),
            const SizedBox(height: 8),
            Text(
              'A proper day scores $properDayScore or more.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

String _verdict(int score) => score >= 100
    ? 'Perfect day'
    : score >= properDayScore
        ? 'Proper day'
        : score >= 60
            ? 'Nearly there'
            : 'An off day';

String _dayLabel(DateTime d, DateTime today) {
  final ago = today.difference(d).inDays;
  if (ago == 0) return 'Today';
  if (ago == 1) return 'Yesterday';
  return '${weekdayName(d)} ${formatShortDate(d)}';
}

String weekdayName(DateTime d) => weekdayNames[d.weekday - 1];

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(label,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.size});
  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: size / 11,
              strokeCap: StrokeCap.round,
              color: scoreColor(scheme, score),
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          Text(
            '$score',
            style: TextStyle(
                fontSize: size * 0.34, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// One bar per day over the last [span] days; empty days show as a stub.
class _Chart extends StatelessWidget {
  const _Chart({required this.app, required this.span});
  final AppState app;
  final int span;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = app.today;
    const barMax = 56.0;
    return SizedBox(
      height: barMax + 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = span - 1; i >= 0; i--)
            Expanded(
              child: () {
                final date =
                    DateTime(today.year, today.month, today.day - i);
                final s = app.scores.on(date);
                final bar = Container(
                  height: s == null ? 4 : 4 + (barMax - 4) * s.score / 100,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: s == null
                        ? scheme.surfaceContainerHighest
                        : scoreColor(scheme, s.score),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
                return Semantics(
                  label: s == null
                      ? '${weekdayName(date)}, not scored'
                      : '${weekdayName(date)}, score ${s.score}',
                  button: s != null,
                  child: InkWell(
                    onTap: s == null ? null : () => showDayScore(context, app, s),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        bar,
                        const SizedBox(height: 4),
                        Text(
                          weekdayName(date).substring(0, 1),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == 0 ? FontWeight.w800 : null,
                              color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }(),
            ),
        ],
      ),
    );
  }
}

/// What a day scored on each goal, and what cost it points.
Future<void> showDayScore(BuildContext context, AppState app, DayScore s) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        Widget part(String label, double got, double of, String detail) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(detail,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Text(
                    '${got.round()} / ${of.round()}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: got >= of - 0.5
                          ? scoreColor(scheme, 100)
                          : const Color(0xFFE08A00),
                    ),
                  ),
                ],
              ),
            );
        String pct(double r) => '${(r * 100).round()}% of your target';

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _ScoreRing(score: s.score, size: 64),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_dayLabel(s.date, app.today),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant)),
                          Text(_verdict(s.score),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                part('Protein', s.proteinPoints, ScorePoints.protein,
                    pct(s.protein)),
                part('Calories', s.energyPoints, ScorePoints.energy,
                    pct(s.energy)),
                part(
                    'Fibre, iron and calcium',
                    s.microPoints,
                    ScorePoints.fibre + ScorePoints.iron + ScorePoints.calcium,
                    '${(s.fibre * 100).round()}%, ${(s.iron * 100).round()}% '
                        'and ${(s.calcium * 100).round()}% of target'),
                part(
                    'No junk',
                    s.junkPoints,
                    ScorePoints.junk,
                    s.junkSnacks == 0
                        ? 'None'
                        : '${s.junkSnacks} junk '
                            '${s.junkSnacks == 1 ? 'snack' : 'snacks'}'),
                if (s.misses.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Where the points went',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  for (final m in s.misses)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('• $m', style: const TextStyle(fontSize: 13)),
                    ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Your share of what the household ate, in proportion to '
                  'your needs, plus any junk you logged — against your own '
                  'targets.',
                  style: TextStyle(
                      fontSize: 12, height: 1.35, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
