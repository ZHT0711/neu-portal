import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/tab_scroller.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// 成绩 — 教务系统真实数据（离线为演示快照）。
class GradesPage extends StatefulWidget {
  const GradesPage({super.key});

  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    TabScroller.attach(3, _scroll);
  }

  @override
  void dispose() {
    TabScroller.detach(3);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final sems = s.semesters;

    return Scaffold(
      appBar: AppBar(title: const Text('成绩')),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(Ds.gutter, 4, Ds.gutter, 34),
        children: [
          StaggerIn(index: 0, child: _GpaHero(sem: sems.first)),
          if (s.mode == SessionMode.demo) ...[
            const SizedBox(height: 14),
            const _DemoNote(),
          ],
          for (var si = 0; si < sems.length; si++) ...[
            Padding(
              padding: const EdgeInsets.only(top: Ds.blockV),
              child: StaggerIn(
                index: si + 1,
                child: Row(
                  children: [
                    Text(sems[si].name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Text(
                      '${sems[si].courses.length} 门课',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
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
        borderRadius: BorderRadius.circular(Ds.rMd),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 16, color: scheme.onTertiaryContainer),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '当前为离线演示数据；登录门户后自动展示教务系统真实成绩。',
              style:
                  TextStyle(fontSize: 11.5, color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// GPA 主卡：MD3 primaryContainer tonal 表面（无渐变/投影）。
class _GpaHero extends StatelessWidget {
  const _GpaHero({required this.sem});

  final GradeSemester sem;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(Ds.rXl),
      ),
      child: Row(
        children: [
          _stat(context, '平均分', sem.weightedAvg.toStringAsFixed(1)),
          _divider(scheme),
          _stat(context, '绩点 GPA', sem.gpa.toStringAsFixed(2)),
          _divider(scheme),
          _stat(context, '已修学分', sem.credits.toStringAsFixed(1)),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          CountUpText(
            value,
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Container(
        width: 1,
        height: 34,
        color: scheme.onPrimaryContainer.withValues(alpha: 0.25),
      );
}

class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.course});

  final GradeCourse course;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = NeuColors.slotTone(CourseSlot(
        weekday: 1,
        startMinutes: 0,
        endMinutes: 0,
        name: course.name,
        room: '',
        kind: course.score != null && course.score! < 60 ? 'exam' : 'course'));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${course.category} · ${course.credit.toStringAsFixed(1)} 学分',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant),
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
                                  widthFactor:
                                      (course.scoreValue.clamp(0, 100)) / 100,
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
                borderRadius: BorderRadius.circular(Ds.rSm),
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
