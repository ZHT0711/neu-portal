import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/learning.dart';
import '../core/links.dart';
import '../core/platform_style.dart';

class LearningPage extends StatefulWidget {
  const LearningPage({super.key});
  @override
  State<LearningPage> createState() => _LearningPageState();
}

class _LearningPageState extends State<LearningPage> {
  LearningPlatform _platform = LearningPlatform.mooc;
  String _filter = '待完成';
  String _query = '';

  bool _matches(String title, String course) =>
      '$title $course'.toLowerCase().contains(_query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final report = state.learningReports[_platform];
    final rows = report?.assignments ?? <LearningAssignment>[];
    final pending = rows.where((a) => !a.completed).length;
    final warnings = _platform == LearningPlatform.cg
        ? state.cgWarnings
        : report?.warnings ?? [];
    return Scaffold(
      appBar: PageAppBar(
        title: '学习任务',
        actions: [
          IconButton(
            tooltip: '打开平台并同步',
            onPressed: () => _openPlatform(context, state),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final platform in LearningPlatform.values)
                ChoiceChip(
                  label: Text(platform.title),
                  selected: platform == _platform,
                  onSelected: (_) => setState(() => _platform = platform),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _platform == LearningPlatform.cg
                        ? '${state.cgAssignments.where((a) => !a.isComplete).length} 份作业待完善'
                        : '$pending 项待完成 · ${rows.where((a) => a.overdue).length} 项已过期',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLinks.supportsDataSync
                        ? '在平台网页完成登录后，点击“同步”。读取结果保存在当前会话中。'
                        : '当前平台可打开官方网页，应用内同步支持 Android 和 iOS 客户端。',
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openPlatform(context, state),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(
                      AppLinks.supportsDataSync ? '打开平台并同步' : '打开平台网页',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索课程或作业',
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final filter in ['待完成', '已过期', '已完成', '全部'])
                ChoiceChip(
                  label: Text(filter),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                warning,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_platform == LearningPlatform.cg)
            ..._cgCards(state)
          else if (report == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('尚未同步，请先打开平台登录。'),
            )
          else
            ..._courseCards(report),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _openPlatform(BuildContext context, AppState state) =>
      AppLinks.open(
        context,
        _platform == LearningPlatform.cg
            ? state.cgEntryUrl
            : _platform.entryUrl,
        title: _platform.title,
      );

  bool _visible(LearningAssignment a) =>
      _matches(a.title, a.courseTitle) &&
      switch (_filter) {
        '待完成' => !a.completed,
        '已过期' => a.overdue,
        '已完成' => a.completed,
        _ => true,
      };

  List<Widget> _courseCards(LearningReport report) {
    final cards = <Widget>[];
    for (final course in report.courses) {
      final rows =
          report.assignments
              .where((a) => a.courseKey == course.key && _visible(a))
              .toList()
            ..sort(
              (a, b) => (a.deadline ?? DateTime(9999)).compareTo(
                b.deadline ?? DateTime(9999),
              ),
            );
      final progressOnly =
          _platform == LearningPlatform.chaoxing &&
          _query.isEmpty &&
          (course.progress != null ||
              course.deadline != null ||
              course.progressWarning != null);
      if (rows.isEmpty && !progressOnly) continue;
      final stale = !report.refreshedCourseKeys.contains(course.key);
      cards.add(
        Card(
          margin: const EdgeInsets.only(top: 14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        course.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '打开课程',
                      onPressed: () => AppLinks.open(
                        context,
                        course.url,
                        title: course.title,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 19),
                    ),
                  ],
                ),
                if (stale) const Text('本次作业未读取，已有作业来自上次同步'),
                if (course.progress != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: course.progress!.fraction),
                  const SizedBox(height: 6),
                  Text(
                    course.progress!.total == 0
                        ? '暂无任务点'
                        : '任务点 ${(course.progress!.fraction * 100).round()}% · ${course.progress!.completed}/${course.progress!.total}',
                  ),
                ],
                if (course.deadline != null)
                  Text('课程截止 ${learningDateText(course.deadline)}'),
                if (course.progressWarning != null)
                  Text(course.progressWarning!),
                for (final a in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      a.completed
                          ? Icons.check_circle_outline
                          : a.overdue
                          ? Icons.warning_amber
                          : Icons.assignment_outlined,
                      color: a.overdue
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    title: Text(a.title),
                    subtitle: Text(
                      [
                        a.kind,
                        a.statusText,
                        if (a.deadline != null)
                          '截止 ${learningDateText(a.deadline)}'
                        else if (a.deadlineText.isNotEmpty)
                          a.deadlineText,
                        if (a.scoreText.isNotEmpty) '得分 ${a.scoreText}',
                      ].where((s) => s.isNotEmpty).join('\n'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => AppLinks.open(context, a.url, title: a.title),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (cards.isEmpty) {
      cards.add(
        const Padding(padding: EdgeInsets.all(24), child: Text('当前筛选下没有任务。')),
      );
    }
    return cards;
  }

  List<Widget> _cgCards(AppState state) {
    final cards = <Widget>[];
    for (final a in state.cgAssignments) {
      final overdue =
          !a.isComplete && a.deadline?.isBefore(DateTime.now()) == true;
      if (!_matches(a.title, '') ||
          (_filter == '待完成' && a.isComplete) ||
          (_filter == '已完成' && !a.isComplete) ||
          (_filter == '已过期' && !overdue)) {
        continue;
      }
      cards.add(
        Card(
          child: ExpansionTile(
            title: Text(a.title),
            subtitle: Text(
              [
                '${a.completedCount}/${a.problemCount} 题完成',
                if (!a.loaded) '本次未读取',
                if (a.history) '历史作业',
                if (a.late) '补交',
                if (a.deadline != null) '截止 ${learningDateText(a.deadline)}',
              ].join(' · '),
            ),
            children: [
              for (final p in a.problems)
                ListTile(
                  title: Text(p.title),
                  subtitle: Text('${p.statusLabel}\n${p.statusText}'),
                  onTap: p.url.isEmpty
                      ? null
                      : () => AppLinks.open(context, p.url, title: p.title),
                ),
            ],
          ),
        ),
      );
    }
    if (cards.isEmpty) {
      cards.add(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            state.cgAssignments.isEmpty ? '尚未同步，请先打开 CG 平台登录。' : '当前筛选下没有作业。',
          ),
        ),
      );
    }
    return cards;
  }
}
