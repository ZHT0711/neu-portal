import 'models.dart';
import 'portal_client.dart';

class GradeReport {
  const GradeReport(this.semesters, {this.failedTerms = const []});
  final List<GradeSemester> semesters;
  final List<String> failedTerms;

  GradeReport merging(List<GradeSemester> previous) {
    final updated = {
      for (final semester in semesters) semester.termCode: semester,
    };
    for (final semester in previous) {
      if (failedTerms.contains(semester.termCode)) {
        updated.putIfAbsent(semester.termCode, () => semester);
      }
    }
    return GradeReport(updated.values.toList(), failedTerms: failedTerms);
  }

  factory GradeReport.fromBrowser(Map payload) {
    if (payload['error'] != null) throw PortalException('${payload['error']}');
    final out = <GradeSemester>[];
    final failed = <String>[];
    for (final row in (payload['semesters'] as List? ?? []).whereType<Map>()) {
      final code = '${row['code'] ?? ''}';
      if (code.isEmpty) continue;
      try {
        out.add(
          parseGradeSemester(
            row['response'],
            code,
            '${row['name'] ?? code}',
            row['current'] == true,
          ),
        );
      } catch (_) {
        failed.add(code);
      }
    }
    if (out.isEmpty) throw PortalException('本次未读取到成绩，请在教务网页完成认证后重试');
    return GradeReport(out, failedTerms: failed);
  }
}

List<Map> academicRecords(Object? raw) {
  if (raw is List) return raw.whereType<Map>().toList();
  if (raw is Map) {
    for (final key in ['datas', 'data', 'rows', 'list']) {
      if (raw.containsKey(key)) return academicRecords(raw[key]);
    }
  }
  return [];
}

void validateAcademic(Object? raw) {
  if (raw is! Map ||
      (!['0', '200'].contains('${raw['code']}') && raw['success'] != true)) {
    throw PortalException(
      raw is Map ? '${raw['msg'] ?? raw['message'] ?? '教务数据读取失败'}' : '教务返回格式异常',
    );
  }
}

GradeSemester parseGradeSemester(
  Object? payload,
  String code,
  String name,
  bool current,
) {
  validateAcademic(payload);
  final courses = academicRecords(payload)
      .map((c) {
        final raw = '${c['score'] ?? ''}'.trim();
        final score = double.tryParse(raw);
        return GradeCourse(
          name: '${c['courseName'] ?? ''}',
          credit: double.tryParse('${c['credit']}') ?? 0,
          category: '${c['courseType'] ?? ''}',
          score: score?.isFinite == true ? score : null,
          scoreRaw: score?.isFinite == true ? '' : raw,
        );
      })
      .where((c) => c.name.isNotEmpty)
      .toList();
  return GradeSemester(
    name,
    termCode: code,
    current: current,
    courses: courses,
  );
}
