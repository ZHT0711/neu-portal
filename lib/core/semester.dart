/// 2026-2027 学年第一学期的学期模型。
/// 锚点来自门户真实数据：2026-10-25 那周是第 9 教学周 → 第 1 周从 2026-08-30（周日）起。
library;

class Semester {
  Semester._();

  /// 第 1 教学周的第一天（周日，与门户周起始约定一致）。
  static final DateTime week1Start = DateTime(2026, 8, 30);

  static const int teachingWeeks = 16; // 上课周
  static const int examWeeks = 2; // 考试周
  static const int totalWeeks = teachingWeeks + examWeeks; // 18

  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 该日期所在教学周序号（1 起；返回值可能 <1 或 >totalWeeks，即假期）。
  static int weekNumberOf(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final sunday = d.subtract(Duration(days: d.weekday % 7));
    return sunday.difference(week1Start).inDays ~/ 7 + 1;
  }

  static DateTime weekStartOf(int week) =>
      DateTime(week1Start.year, week1Start.month, week1Start.day)
          .add(Duration(days: 7 * (week - 1)));

  /// 放假日（停课）：国庆周 + 元旦。
  static const Set<String> holidays = {
    '2026-10-01',
    '2026-10-02',
    '2026-10-03',
    '2026-10-04',
    '2026-10-05',
    '2026-10-06',
    '2026-10-07',
    '2027-01-01',
  };

  static bool isHoliday(DateTime day) => holidays.contains(iso(day));

  static bool isExamWeek(int week) => week > teachingWeeks && week <= totalWeeks;

  // ── 节次（东北大学作息，来自门户课表真实时间）──────────
  /// 10 个小节：(开始分钟, 结束分钟)。
  /// 第1节 8:30-9:15 第2节 9:25-10:10 第3节 10:30-11:15 第4节 11:25-12:10
  /// 第5节 14:00-14:45 第6节 14:55-15:40 第7节 16:00-16:45 第8节 16:55-17:40
  /// 第9节 18:30-19:15 第10节 19:25-20:10
  static const List<int> periodStarts = [
    510, 565, 630, 685, 840, 895, 960, 1015, 1110, 1165,
  ];
  static const List<int> periodEnds = [
    555, 610, 675, 730, 885, 940, 1005, 1060, 1155, 1250,
  ];

  static String two(int v) => v.toString().padLeft(2, '0');
  static String hm(int minutes) =>
      '${two(minutes ~/ 60)}:${two(minutes % 60)}';

  /// 分钟 → 所在小节序号（1..10）。
  static int periodOf(int minutes) {
    for (var i = 0; i < periodStarts.length; i++) {
      if (minutes >= periodStarts[i] && minutes < periodEnds[i]) return i + 1;
    }
    return minutes < periodStarts.first ? 1 : periodStarts.length;
  }

  static int startPeriodOf(int startMinutes) => periodOf(startMinutes);

  /// 结束时间落在某节结束时（如 12:10）→ 该节。
  static int endPeriodOf(int endMinutes) {
    for (var i = 0; i < periodStarts.length; i++) {
      if (endMinutes > periodStarts[i] && endMinutes <= periodEnds[i]) {
        return i + 1;
      }
    }
    return endMinutes < periodStarts.first ? 1 : periodStarts.length;
  }
}
