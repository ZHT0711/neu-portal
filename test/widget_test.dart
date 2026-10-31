import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neu_portal/core/app_state.dart';
import 'package:neu_portal/core/cas_crypto.dart';
import 'package:neu_portal/core/models.dart';
import 'package:neu_portal/core/semester.dart';
import 'package:neu_portal/core/theme.dart';

void main() {
  test('CAS RSA 加密输出为合法 base64 且长度正确（2048-bit → 256 字节）', () {
    final out = CasCrypto.encrypt('20250001' 'test-password-123');
    final decoded = base64Decode(out);
    expect(decoded.length, 256);
  });

  test('RSA 每次填充随机，相同明文得到不同密文', () {
    final a = CasCrypto.encrypt('userpwd');
    final b = CasCrypto.encrypt('userpwd');
    expect(a, isNot(equals(b)));
  });

  test('GPA / 加权平均分计算', () {
    const sem = GradeSemester('测试', courses: [
      GradeCourse(name: 'A', credit: 4, category: '必修', score: 90),
      GradeCourse(name: 'B', credit: 2, category: '必修', score: 80),
      GradeCourse(name: 'C', credit: 2, category: '选修'),
    ]);
    // (90*4 + 80*2) / 6
    expect(sem.weightedAvg, closeTo(86.67, 0.01));
    // (4.0*4 + 3.0*2) / 6
    expect(sem.gpa, closeTo(3.67, 0.01));
    expect(sem.credits, 6.0);
    expect(sem.courses.last.scoreText, '暂无');
  });

  test('节次映射：门户真实时间 → 教务节次', () {
    expect(Semester.startPeriodOf(8 * 60 + 30), 1);
    expect(Semester.endPeriodOf(10 * 60 + 10), 2);
    expect(Semester.startPeriodOf(10 * 60 + 30), 3);
    expect(Semester.endPeriodOf(12 * 60 + 10), 4);
    expect(Semester.startPeriodOf(14 * 60), 5);
    expect(Semester.startPeriodOf(16 * 60), 7);
    expect(Semester.startPeriodOf(18 * 60 + 30), 9);
    expect(Semester.endPeriodOf(20 * 60 + 30), 10); // 考试 20:30 结束
    expect(Semester.periodOf(7 * 60), 1); // 早于第1节 → 归第1节
  });

  test('课程色板确定性', () {
    final c1 = NeuColors.courseColor('高等数学①㈠', 0);
    final c2 = NeuColors.courseColor('高等数学①㈠', 0);
    expect(c1, c2);
  });

  test('学期周次：锚点周（2026-10-25）为第 9 教学周', () {
    expect(Semester.weekNumberOf(DateTime(2026, 10, 25)), 9);
    expect(Semester.weekNumberOf(DateTime(2026, 8, 30)), 1);
    expect(Semester.weekNumberOf(DateTime(2026, 8, 29)), 0);
    expect(Semester.isExamWeek(17), isTrue);
    expect(Semester.isExamWeek(16), isFalse);
    expect(Semester.isHoliday(DateTime(2026, 10, 1)), isTrue);
    expect(Semester.isHoliday(DateTime(2026, 10, 8)), isFalse);
  });

  test('课表智能周次：假期无课、周次范围生效、考试出现在指定日期', () {
    final s = AppState();
    // 第 9 周（锚点周）有全部课程
    expect(
        s.agendaForDate(DateTime(2026, 10, 26)).length, 3); // 周一：高数+心理+体育
    // 第 13 周起心理课结束（weekEnd=12）
    final monW13 = s.agendaForDate(DateTime(2026, 11, 30));
    expect(monW13.where((o) => o.slot.name.contains('心理')), isEmpty);
    // 国庆假期（2026-10-01，第 6 周）停课
    expect(s.agendaForDate(DateTime(2026, 10, 1)), isEmpty);
    // 考试日程：2026-11-04 有高数期中
    final examDay = s.agendaForDate(DateTime(2026, 11, 4));
    expect(examDay.any((o) => o.slot.kind == 'exam'), isTrue);
    // 考试周（第 17 周）没有课程，只有考试
    final examWeekDay = s.agendaForDate(DateTime(2027, 1, 13));
    expect(examWeekDay.where((o) => o.slot.kind == 'course'), isEmpty);
    expect(examWeekDay.where((o) => o.slot.kind == 'exam'), isNotEmpty);
  });

  test('添加 / 删除日程 并参与当日日程与“接下来”计算', () async {
    final s = AppState();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final iso = Semester.iso(tomorrow);
    await s.addEvent(PlannerEvent(
      id: 't1',
      name: '实验室例会',
      dateIso: iso,
      startMinutes: 19 * 60,
      endMinutes: 20 * 60,
      room: '信息楼B520',
    ));
    expect(s.events.length, 1);
    final agenda = s.agendaForDate(tomorrow);
    expect(agenda.any((o) => o.slot.name == '实验室例会'), isTrue);
    await s.removeEvent('t1');
    expect(s.events, isEmpty);
    expect(s.agendaForDate(tomorrow).any((o) => o.slot.name == '实验室例会'),
        isFalse);
  });
}
