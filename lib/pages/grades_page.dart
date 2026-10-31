import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';

/// 成绩查询（演示数据；教务系统未开放独立接口）。
class GradesPage extends StatelessWidget {
  const GradesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final sems = s.semesters;

    return Scaffold(
      appBar: AppBar(title: const Text('成绩')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 34),
        children: [
          StaggerIn(index: 0, child: _GpaHero(sem: sems.first)),
          if (s.mode == SessionMode.demo) ...[
            const SizedBox(height: 14),
            const _DemoNote(),
          ],
          for (var si = 0; si < sems.length; si++) ...[
            Padding(
              padding: const EdgeInsets.only(top: 26),
              child: StaggerIn(
                index: si + 1,
                child: Row(
                  children: [
                    Text(
                      sems[si].name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      '${sems[si].courses.length} 门课',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < sems[si].courses.length; i++)
              StaggerIn(
                index: si + i + 1,
                child: _GradeRow(course: sems[si].courses[i]),
              ),
          ],
        ],
      ),
    );
  }
}

class _DemoNote extends StatelessWidget {
  const _DemoNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: scheme.onTertiaryContainer),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '成绩为演示数据（教务系统未开放独立接口），仅供界面预览。',
              style:
                  TextStyle(fontSize: 11.5, color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpaHero extends StatelessWidget {
  const _GpaHero({required this.sem});

  final GradeSemester sem;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.55)!,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _stat('平均分', sem.weightedAvg.toStringAsFixed(1)),
          _divider(),
          _stat('绩点 GPA', sem.gpa.toStringAsFixed(2)),
          _divider(),
          _stat('已修学分', sem.credits.toStringAsFixed(1)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          children: [
            CountUpText(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );

  Widget _divider() => Container(
        width: 1,
        height: 34,
        color: Colors.white.withValues(alpha: 0.25),
      );
}

class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.course});

  final GradeCourse course;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = course.score;
    final tone = s == null
        ? scheme.outline
        : s >= 85
            ? const Color(0xFF1E7A5A)
            : s >= 75
                ? const Color(0xFF7A5900)
                : s >= 60
                    ? const Color(0xFFB4345C)
                    : scheme.error;
    return Panel(
      padding: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${course.category} · ${course.credit.toStringAsFixed(1)} 学分',
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(
                            height: 4,
                            child: Stack(
                              children: [
                                ColoredBox(
                                  color: scheme.surfaceContainerHighest,
                                  child: const SizedBox.expand(),
                                ),
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: (s ?? 0) / 100,
                                  child: ColoredBox(color: tone),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                course.scoreText,
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
