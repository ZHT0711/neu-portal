/// 数据模型 — 与一号通门户真实接口结构对应。
library;

const String kPortalBase = 'https://personal.neu.edu.cn/portal';

String withScheme(String raw) {
  var u = raw.trim();
  if (u.isEmpty) return u;
  final schemeRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
  if (schemeRe.hasMatch(u)) return u;
  final looksLikeIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}').hasMatch(u);
  final hasPort = RegExp(r':\d+').hasMatch(u.split('/').first);
  final intranet = looksLikeIp || hasPort || u.startsWith('10.');
  return (intranet ? 'http://' : 'https://') + u;
}

class PortalUser {
  final String uid;
  final String name;
  final String sid; // 学号
  final String identity;
  final String department;
  final String email;
  final String avatarUrl;

  const PortalUser({
    required this.uid,
    required this.name,
    required this.sid,
    required this.identity,
    required this.department,
    required this.email,
    required this.avatarUrl,
  });

  factory PortalUser.fromInfoJson(Map<String, dynamic> j) => PortalUser(
        uid: '${j['uid'] ?? ''}',
        name: '${j['name'] ?? ''}',
        sid: '${j['xgh'] ?? ''}',
        identity: '${j['identity'] ?? ''}',
        department: '${j['depart'] ?? ''}',
        email: '${j['email'] ?? ''}',
        avatarUrl: '${j['avatar'] ?? ''}',
      );

  static const demo = PortalUser(
    uid: '0',
    name: '东大学子',
    sid: '20250001',
    identity: '本科生',
    department: '计算机科学与工程学院',
    email: 'student@mails.neu.edu.cn',
    avatarUrl: '',
  );
}

/// 一条课表事件（按周模板存放：weekday 1=周一 … 7=周日）。
class CourseSlot {
  final int weekday;
  final int startMinutes; // 距 00:00 的分钟数
  final int endMinutes;
  final String name;
  final String room;
  final String teacher;

  /// kind: course=课程 exam=考试 custom=自定义日程
  final String kind;

  /// 生效教学周范围（含两端）；0,0 表示不限（如自定义日程）。
  final int weekStart;
  final int weekEnd;

  const CourseSlot({
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    required this.name,
    required this.room,
    this.teacher = '',
    this.kind = 'course',
    this.weekStart = 1,
    this.weekEnd = 99,
  });

  bool coversWeek(int week) =>
      weekStart == 0 || (week >= weekStart && week <= weekEnd);

  String get timeText {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(startMinutes ~/ 60)}:${two(startMinutes % 60)}'
        '-${two(endMinutes ~/ 60)}:${two(endMinutes % 60)}';
  }
}

/// 手动添加 / 内置演示的日程（考试、事务、提醒…），落到具体某天。
class PlannerEvent {
  final String id;
  final String name;
  final String dateIso; // yyyy-MM-dd
  final int startMinutes;
  final int endMinutes;
  final String room;
  final String note;
  final String kind; // exam | custom
  final bool deletable; // 演示考试不可删，用户新建的可以

  const PlannerEvent({
    required this.id,
    required this.name,
    required this.dateIso,
    required this.startMinutes,
    required this.endMinutes,
    this.room = '',
    this.note = '',
    this.kind = 'custom',
    this.deletable = true,
  });

  PlannerEvent copyWith({String? name, String? room, String? note}) =>
      PlannerEvent(
        id: id,
        name: name ?? this.name,
        dateIso: dateIso,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        room: room ?? this.room,
        note: note ?? this.note,
        kind: kind,
        deletable: deletable,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dateIso': dateIso,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'room': room,
        'note': note,
        'kind': kind,
        'deletable': deletable,
      };

  factory PlannerEvent.fromJson(Map<String, dynamic> j) => PlannerEvent(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        dateIso: '${j['dateIso'] ?? ''}',
        startMinutes: int.tryParse('${j['startMinutes'] ?? 0}') ?? 0,
        endMinutes: int.tryParse('${j['endMinutes'] ?? 0}') ?? 0,
        room: '${j['room'] ?? ''}',
        note: '${j['note'] ?? ''}',
        kind: '${j['kind'] ?? 'custom'}',
        deletable: j['deletable'] != false,
      );

  /// 转成课表网格/时间轴可渲染的槽位。
  CourseSlot toSlot() {
    final d = DateTime.tryParse(dateIso);
    return CourseSlot(
      weekday: d?.weekday ?? 1,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      name: name,
      room: room.trim().isEmpty ? '待定' : room.trim(),
      kind: kind,
    );
  }
}

/// 展开到具体某一天的事件。
class CourseOccurrence {
  final DateTime date;
  final CourseSlot slot;

  const CourseOccurrence(this.date, this.slot);
}

class NewsItem {
  final String id;
  final String title;
  final String date; // yyyy-MM-dd
  final String category;
  final String url;
  final String picUrl;

  const NewsItem({
    required this.id,
    required this.title,
    required this.date,
    required this.category,
    this.url = '',
    this.picUrl = '',
  });
}

class PortalApp {
  final String name;
  final String appId; // 门户应用市场 id，用于 mimipath 官方入口解析
  final String url;
  final String mobileUrl;
  final String iconUrl;
  final String desc;
  final String category;
  final int visits;

  const PortalApp({
    required this.name,
    required this.url,
    this.appId = '',
    this.mobileUrl = '',
    this.iconUrl = '',
    this.desc = '',
    this.category = '',
    this.visits = 0,
  });

  /// 官方入口解析（与门户 Web 端一致）：
  /// 移动端地址 → 应用地址 → mimipath 官方解析器。
  String entryUrl() {
    if (mobileUrl.trim().isNotEmpty) return withScheme(mobileUrl);
    if (url.trim().isNotEmpty) return withScheme(url);
    if (appId.trim().isNotEmpty) {
      return '$kPortalBase/pages/mimipath/mimipath?appId=$appId';
    }
    return '';
  }
}

class TodoItem {
  final String title;
  final String instance;
  final String node;
  final int percent;
  final String time;
  final String url;

  const TodoItem({
    required this.title,
    required this.instance,
    required this.node,
    required this.percent,
    required this.time,
    this.url = '',
  });
}

class DataCard {
  final String name;
  final String value;
  final String unit;

  const DataCard(this.name, this.value, {this.unit = ''});
}

class ServiceSection {
  final String name;
  final List<ServiceEntry> entries;

  const ServiceSection(this.name, this.entries);
}

class ServiceEntry {
  final String name;
  final String desc;
  final String url;

  const ServiceEntry(this.name, {this.desc = '', this.url = ''});
}

/// 成绩（演示数据，接口未开放；结构与教务系统一致，便于后续接入）。
class GradeCourse {
  final String name;
  final double credit;
  final double? score; // 数字成绩（可为空）
  final String category; // 必修 / 选修 / 实践课 / 体育 …
  final String scoreRaw; // 原始成绩文本（五级制如「良」，或数字字符串）

  const GradeCourse({
    required this.name,
    required this.credit,
    required this.category,
    this.score,
    this.scoreRaw = '',
  });

  String get scoreText {
    if (score != null) {
      return score!.toStringAsFixed(score! == score!.roundToDouble() ? 0 : 1);
    }
    return scoreRaw.isEmpty ? '暂无' : scoreRaw;
  }

  /// 绩点计算用数值：数字成绩直接用；五级制按校标换算
  /// （优≈95 / 良≈85 / 中≈75 / 及格≈65 / 不及格≈50）。
  double get scoreValue {
    if (score != null) return score!;
    switch (scoreRaw.trim()) {
      case '优':
      case '优秀':
        return 95;
      case '良':
      case '良好':
        return 85;
      case '中':
      case '中等':
        return 75;
      case '及格':
      case '合格':
        return 65;
      case '不及格':
      case '不合格':
        return 50;
      default:
        return 0;
    }
  }

  bool get hasScore => score != null || scoreRaw.isNotEmpty;
}

class GradeSemester {
  final String name;
  final String termCode; // 教务系统学期代码，如 2026-2027-1
  final bool current;
  final List<GradeCourse> courses;

  const GradeSemester(this.name,
      {this.termCode = '', this.current = false, required this.courses});

  double get credits =>
      courses.fold(0, (s, c) => s + (c.hasScore ? c.credit : 0));
  double get weightedAvg {
    double ws = 0, wc = 0;
    for (final c in courses) {
      if (!c.hasScore) continue;
      ws += c.scoreValue * c.credit;
      wc += c.credit;
    }
    return wc == 0 ? 0 : ws / wc;
  }

  double get gpa {
    double ws = 0, wc = 0;
    for (final c in courses) {
      if (!c.hasScore) continue;
      ws += _gpaOf(c.scoreValue) * c.credit;
      wc += c.credit;
    }
    return wc == 0 ? 0 : ws / wc;
  }

  static double _gpaOf(double s) {
    if (s >= 90) return 4.0;
    if (s >= 85) return 3.7;
    if (s >= 82) return 3.3;
    if (s >= 78) return 3.0;
    if (s >= 75) return 2.7;
    if (s >= 72) return 2.3;
    if (s >= 68) return 2.0;
    if (s >= 64) return 1.5;
    if (s >= 60) return 1.0;
    return 0;
  }
}
