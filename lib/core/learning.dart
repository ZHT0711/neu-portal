import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import 'portal_client.dart';
import 'webvpn.dart';

enum LearningPlatform {
  cg('CG 实验', 'http://neucsecg.neu.edu.cn/assignment/index.jsp'),
  mooc('中国大学 MOOC', 'https://www.icourse163.org/home.htm#/home/course'),
  chaoxing('学习通', 'https://i.chaoxing.com/');

  const LearningPlatform(this.title, this.entryUrl);
  final String title;
  final String entryUrl;

  bool accepts(String url) {
    final uri = Uri.tryParse(WebVPN.unwrap(url));
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return false;
    return switch (this) {
      cg => uri.host == 'neucsecg.neu.edu.cn',
      mooc => uri.host == 'www.icourse163.org' || uri.host == 'icourse163.org',
      chaoxing =>
        uri.host == 'chaoxing.com' || uri.host.endsWith('.chaoxing.com'),
    };
  }
}

/// Platform timestamps without an explicit zone are Beijing time on every device.
DateTime? learningDate(Object? raw, {bool endOfDay = false}) {
  if (raw == null) return null;
  final text = '$raw'.trim();
  final number = num.tryParse(text);
  if (number != null) {
    if (!number.isFinite || number <= 0) return null;
    final milliseconds = number > 100000000000 ? number : number * 1000;
    if (milliseconds > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds.round(),
      isUtc: true,
    );
  }
  var normalized = text
      .replaceAll('/', '-')
      .replaceAll('年', '-')
      .replaceAll('月', '-')
      .replaceAll('日', ' ')
      .trim()
      .replaceFirst(RegExp(r'\s+'), 'T');
  normalized = normalized
      .replaceFirstMapped(
        RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})'),
        (m) => '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}',
      )
      .replaceFirstMapped(
        RegExp(r'T(\d{1,2}):'),
        (m) => 'T${m[1]!.padLeft(2, '0')}:',
      );
  if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$').hasMatch(normalized)) {
    normalized += endOfDay ? 'T23:59:59+08:00' : 'T00:00:00+08:00';
  } else if (!RegExp(
    r'(Z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    normalized += '+08:00';
  }
  return DateTime.tryParse(normalized);
}

String learningDateText(DateTime? date) {
  if (date == null) return '';
  final beijing = date.toUtc().add(const Duration(hours: 8));
  String two(int n) => '$n'.padLeft(2, '0');
  return '${beijing.year}-${two(beijing.month)}-${two(beijing.day)} '
      '${two(beijing.hour)}:${two(beijing.minute)}';
}

class LearningProgress {
  const LearningProgress(this.completed, this.total);
  final int completed;
  final int total;
  double get fraction => total == 0 ? 0 : completed / total;

  static LearningProgress chaoxing(Object? payload, String courseID) {
    List<Map> records(Object? raw) {
      if (raw is List) return raw.whereType<Map>().toList();
      if (raw is! Map) return [];
      if (raw.containsKey('data') || raw.containsKey('msg')) {
        return records(raw['data'] ?? raw['msg']);
      }
      return [raw];
    }

    final courses = records(payload).expand((c) => records(c['course']));
    final course = courses.where((c) => '${c['id']}' == courseID).firstOrNull;
    if (course == null || !course.containsKey('knowledge')) {
      throw PortalException('课程进度返回格式异常');
    }
    final nodes = records(course['knowledge']);
    if (nodes.isEmpty) return const LearningProgress(0, 0);
    final parents = nodes.map((n) => '${n['parentnodeid']}').toSet();
    final seen = <String>{};
    var done = 0, total = 0;
    int? count(Object? raw) {
      final n = int.tryParse('$raw');
      return n != null && n >= 0 ? n : null;
    }

    for (final node in nodes) {
      final id = '${node['id'] ?? ''}';
      if (id.isEmpty || parents.contains(id) || !seen.add(id)) continue;
      final finished = count(node['finishcount'] ?? node['jobFinishedCount']);
      final unfinished = count(
        node['unfinishcount'] ?? node['jobUnfinishedCount'],
      );
      final all =
          count(node['jobcount']) ??
          (finished != null && unfinished != null
              ? finished + unfinished
              : null);
      final completed =
          finished ??
          (all != null && unfinished != null ? all - unfinished : null);
      if (all == null ||
          completed == null ||
          completed < 0 ||
          completed > all) {
        throw PortalException('平台未提供完整的课程任务点统计');
      }
      done += completed;
      total += all;
    }
    if (seen.isEmpty) throw PortalException('课程任务点未读取');
    return LearningProgress(done, total);
  }
}

class LearningCourse {
  const LearningCourse({
    required this.id,
    required this.termID,
    required this.title,
    required this.url,
    this.activeTermID,
    this.progress,
    this.deadline,
    this.progressWarning,
  });
  final String id, termID, title, url;
  final String? activeTermID, progressWarning;
  final LearningProgress? progress;
  final DateTime? deadline;
  String get key => '$id.$termID';
  Map<String, Object?> toJson() => {
    'id': id,
    'termID': termID,
    'title': title,
    'url': url,
  };
  factory LearningCourse.fromJson(Map j) => LearningCourse(
    id: '${j['id']}',
    termID: '${j['termID']}',
    title: '${j['title']}',
    url: '${j['url']}',
    activeTermID: j['activeTermID'] as String?,
  );
}

class LearningAssignment {
  const LearningAssignment({
    required this.id,
    required this.courseKey,
    required this.courseTitle,
    required this.title,
    required this.kind,
    required this.url,
    this.deadline,
    this.deadlineText = '',
    this.statusText = '',
    this.completed = false,
    this.scoreText = '',
  });
  final String id, courseKey, courseTitle, title, kind, url;
  final DateTime? deadline;
  final String deadlineText, statusText, scoreText;
  final bool completed;
  bool get overdue =>
      !completed && deadline != null && deadline!.isBefore(DateTime.now());
  factory LearningAssignment.fromJson(Map j, LearningPlatform platform) {
    final url = '${j['url'] ?? ''}';
    if ('${j['id'] ?? ''}'.isEmpty || !platform.accepts(url)) {
      throw PortalException('作业记录或链接无效');
    }
    final timestamp = j['deadline'];
    return LearningAssignment(
      id: '${j['id']}',
      courseKey: '${j['courseKey']}',
      courseTitle: '${j['courseTitle'] ?? ''}',
      title: '${j['title'] ?? ''}',
      kind: '${j['kind'] ?? '作业'}',
      url: url,
      deadline: timestamp is num && timestamp.isFinite
          ? DateTime.fromMillisecondsSinceEpoch(timestamp.round(), isUtc: true)
          : null,
      deadlineText: '${j['deadlineText'] ?? ''}',
      statusText: '${j['statusText'] ?? ''}',
      completed: j['completed'] == true,
      scoreText: '${j['scoreText'] ?? ''}',
    );
  }
}

class LearningReport {
  const LearningReport({
    required this.accountKey,
    required this.courses,
    required this.assignments,
    required this.refreshedCourseKeys,
    this.warnings = const [],
  });
  final String accountKey;
  final List<LearningCourse> courses;
  final List<LearningAssignment> assignments;
  final Set<String> refreshedCourseKeys;
  final List<String> warnings;

  LearningReport merging(LearningReport? previous) {
    final sameAccount =
        accountKey.isNotEmpty && previous?.accountKey == accountKey;
    final courseMap = {
      if (sameAccount)
        for (final c in previous!.courses) c.key: c,
      for (final c in courses) c.key: c,
    };
    final rows = {
      if (sameAccount)
        for (final a in previous!.assignments)
          if (!refreshedCourseKeys.contains(a.courseKey))
            '${a.courseKey}|${a.id}': a,
      for (final a in assignments) '${a.courseKey}|${a.id}': a,
    };
    return LearningReport(
      accountKey: accountKey,
      courses: courseMap.values.toList(),
      assignments: rows.values.toList(),
      refreshedCourseKeys: refreshedCourseKeys,
      warnings: warnings,
    );
  }
}

String learningAccountKey(
  LearningPlatform platform,
  List<Map<String, dynamic>> cookies,
) {
  final names = platform == LearningPlatform.mooc
      ? ['NTESSTUDYSI']
      : ['_uid', 'UID'];
  final identity =
      cookies
          .where(
            (c) =>
                names.contains(c['name']) &&
                platform.accepts(
                  'https://${'${c['domain']}'.replaceFirst(RegExp(r'^\.'), '')}/',
                ) &&
                '${c['value'] ?? ''}'.isNotEmpty,
          )
          .map((c) => '${c['name']}=${c['value']}')
          .toSet()
          .toList()
        ..sort();
  if (identity.isEmpty) throw PortalException('请先在平台网页完成登录后同步');
  return SHA256Digest()
      .process(Uint8List.fromList(utf8.encode(identity.join('|'))))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

enum CGStatus { notSubmitted, needsWork, complete, submitted }

class CGProblem {
  CGProblem(Map row)
    : id = '${row['id']}',
      title = '${row['title']}',
      url = '${row['url'] ?? ''}',
      statusText = '${row['statusText'] ?? ''}';
  final String id, title, url, statusText;
  CGStatus get status {
    if (RegExp('还未提交|尚未提交|未提交').hasMatch(statusText)) {
      return CGStatus.notSubmitted;
    }
    if (RegExp('未通过|错误|部分正确|超时|超限|异常|失败').hasMatch(statusText)) {
      return CGStatus.needsWork;
    }
    final tests = RegExp(
      r'测试数据\s*\d+\s*[^测]+?(?=测试数据\s*\d+|详细|$)',
    ).allMatches(statusText).map((m) => m[0]!).toList();
    if (tests.isNotEmpty) {
      final expected = int.tryParse(
        RegExp(r'共有测试数据\s*[:：]\s*(\d+)').firstMatch(statusText)?[1] ?? '',
      );
      if (expected != null && expected > tests.length) {
        return CGStatus.submitted;
      }
      return tests.every((t) => t.contains('完全正确'))
          ? CGStatus.complete
          : CGStatus.submitted;
    }
    return statusText.contains('完全正确') ? CGStatus.complete : CGStatus.submitted;
  }

  String get statusLabel => switch (status) {
    CGStatus.notSubmitted => '未提交',
    CGStatus.needsWork => '需完善',
    CGStatus.complete => '已完成',
    CGStatus.submitted => '评判待确认',
  };
}

class CGAssignment {
  CGAssignment(Map row)
    : id = '${row['id']}',
      title = '${row['title']}',
      url = '${row['url'] ?? ''}',
      deadline = learningDate(row['deadline']),
      loaded = row['loaded'] == true,
      late = row['late'] == true,
      history = row['history'] == true,
      expectedProblemCount = row['expectedCount'] as int?,
      problems = (row['problems'] as List? ?? [])
          .whereType<Map>()
          .map(CGProblem.new)
          .toList();
  final String id, title, url;
  final DateTime? deadline;
  final bool loaded, late, history;
  final int? expectedProblemCount;
  final List<CGProblem> problems;
  int get completedCount =>
      problems.where((p) => p.status == CGStatus.complete).length;
  int get problemCount => (expectedProblemCount ?? 0) > problems.length
      ? expectedProblemCount!
      : problems.length;
  bool get isComplete =>
      loaded && problems.isNotEmpty && completedCount == problemCount;
}
