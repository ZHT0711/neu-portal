import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const raw = name => readFileSync(new URL('../assets/bridges/' + ({parser:'mooc_parser',readCourse:'mooc_course',discover:'mooc_discover'}[name]) + '.js', import.meta.url), 'utf8');
const helpers = raw("parser");
const parse = new Function("data", "course", helpers + "\nreturn extractHomeworkFromTermDto(data, course);");
const meta = { courseId: "NEU-1", termId: "42", courseName: "测试课程", pageUrl: "https://www.icourse163.org/spoc/learn/NEU-1?tid=42" };
const deadline = Date.UTC(2026, 10, 10, 15, 59);
const data = { result: { mocTermDto: { chapters: [
  { id: 1, lessons: [], homeworks: [{ id: 11, name: "本周作业", contentType: 3, test: { id: 111, name: "本周作业", deadline, usedTryCount: 1, type: 3 } }] },
  { id: 2, lessons: [], homeworks: [{ id: 12, name: "本周作业", contentType: 3, deadline }] },
] } } };
const rows = parse(data, meta);
assert.equal(rows.length, 2, "Same-name assignments in different weeks must both survive");
assert.equal(new Set(rows.map(row => row.uid)).size, 2);
assert.equal(rows[0].checkedOff, true);
assert.equal(rows[1].checkedOff, false);
assert.equal(Date.parse(rows[0].deadline), deadline);
const peer = parse({ chapters: [{ id: 1, lessons: [], homeworks: [{ id: 3, name: "互评作业", contentType: 3,
  deadline, enableEvaluation: true, evaluateStart: 1, evaluateEnd: Date.now() + 86400000, usedTryCount: 1 }] }] }, meta);
assert.equal(peer[0].hwPhase, "peerreview");
assert.equal(peer[0].checkedOff, true, "Submission survives a peer-review phase");
const zero = parse({ chapters: [{ id: 1, lessons: [], homeworks: [{ id: 4, name: "零分作业", contentType: 3,
  deadline, score: 0, totalScore: 10, usedTryCount: 1 }] }] }, meta);
assert.equal(zero[0].score, 0);
assert.equal(zero[0].checkedOff, true);

const statuses = [
  { userSubmitStatus: 1 }, { userSubmitStatus: "1" }, { userScore: 0 }, { usedTryCount: 1 },
  { userSubmitStatus: 0, usedTryCount: 0, userScore: -1 }, { score: 0, totalScore: 10 },
];
for (const [index, status] of statuses.entries()) {
  const [row] = parse({ chapters: [{ id: 1, lessons: [], homeworks: [
    { id: 5, name: "简答作业", contentType: 3, test: { deadline, ...status } },
  ] }] }, meta);
  assert.equal(row.checkedOff, index < 4, `Personal submission state ${JSON.stringify(status)}`);
}

const readCourse = new Function("DOMParser", "html", "responses", "course", helpers + raw("readCourse"));
const metadata = { chapters: [{ id: 1, lessons: [], homeworks: [
  { id: 5, name: "简答作业", contentType: 3, test: { deadline } },
] }] };
const personal = structuredClone(metadata);
personal.chapters[0].homeworks[0].test.userSubmitStatus = 1;
const staleFlight = `self.__next_f.push([1,${JSON.stringify('1:["$","div",null,{"outline":' + JSON.stringify(metadata) + '}]\n')}])`;
class FixtureDOMParser {
  parseFromString() { return { querySelectorAll: () => [{ textContent: staleFlight }] }; }
}
const merged = readCourse(FixtureDOMParser, "", [{ raw: JSON.stringify(personal), termID: "42" }],
  { id: "NEU-1", termID: "42", title: "测试课程", url: meta.pageUrl });
assert.equal(merged.assignments.length, 1);
assert.equal(merged.assignments[0].completed, true, "Outline metadata must not erase an authenticated submission");
const [withoutDeadline] = parse({ chapters: [{ id: 1, lessons: [], homeworks: [
  { id: 8, name: "未定期限作业", contentType: 3, test: { userSubmitStatus: 0, actionLabel: "查看成绩" } },
] }] }, meta);
assert.equal(withoutDeadline.checkedOff, false);
assert.equal(withoutDeadline.deadline, null);

const taskOnlyData = { id: 99, name: "软件测试课程", endTime: deadline, chapters: [
  { id: 1, name: "测试与作业", endTime: deadline, lessons: [
    { id: 2, name: "单元测验课程", contentType: 2, endTime: deadline, units: [
      { id: 3, name: "视频课程测试", contentType: 1, endTime: deadline },
      { id: 4, name: "本周测验", contentType: 2, test: { deadline, usedTryCount: 1 } },
      { id: 5, name: "简答任务", contentType: 3, test: { userSubmitStatus: 1 } },
      { id: 6, name: "期末考试", contentType: 6, test: { deadline } },
      { id: 7, name: "测试讨论", contentType: 4, endTime: deadline },
    ] },
  ], homeworks: [{ id: 8, name: "补充练习", deadline }] },
] };
const strict = parse(taskOnlyData, meta);
assert.deepEqual(strict.map(row => row.title), ["本周测验", "简答任务", "期末考试", "补充练习"],
  "Course, chapter, lesson, video and discussion metadata must not become tasks");
const filtered = readCourse(FixtureDOMParser, "", [{ raw: JSON.stringify(taskOnlyData), termID: "42" }],
  { id: "NEU-1", termID: "42", title: "测试课程", url: meta.pageUrl });
assert.deepEqual(filtered.assignments.map(row => row.title).sort(), ["本周测验", "简答任务", "补充练习", "简答作业"].sort());
assert.ok(filtered.assignments.every(row => ["作业", "测验"].includes(row.kind)));

const outline = { chapters: [], exams: [{ id: 99, name: "期末考试", taskType: "exam", parts: [{ endTime: deadline, usedTryCount: 1 }] }] };
const flight = `self.__next_f.push([1,${JSON.stringify('14:["$","div",null,{"outline":' + JSON.stringify(outline) + '}]\n')}])`;
const decode = new Function("text", helpers + "\nreturn extractLearnOutlines(text);");
const outlines = decode(flight);
assert.equal(outlines.length, 1);
const exams = parse(outlines[0], meta);
assert.equal(exams.length, 1);
assert.equal(exams[0].type, "exam");
assert.equal(exams[0].checkedOff, true);
assert.equal(Date.parse(exams[0].deadline), deadline);

// Compile each script as WebKit does, including its named native arguments.
new Function("html", "responses", "course", helpers + raw("readCourse"));
new Function(raw("discover"));
const cg = readFileSync(new URL('../assets/bridges/cg.js', import.meta.url), 'utf8');
new (Object.getPrototypeOf(async function () {}).constructor)('rootURL', 'originalRootURL', cg);
const cx = readFileSync(new URL('../assets/bridges/chaoxing_page.js', import.meta.url), 'utf8');
new Function('html', 'pageURL', 'courseKey', 'courseTitle', cx);
for (const name of ['card', 'grades']) {
  new (Object.getPrototypeOf(async function () {}).constructor)('month', readFileSync(new URL('../assets/bridges/' + name + '.js', import.meta.url), 'utf8'));
}
console.log('Learning bridge regressions passed. Card, CG and grade scripts compiled.');

// Exercise the card workflow with stateful form fixtures and live input values.
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const readCard = new AsyncFunction('month', 'document', 'location', 'DOMParser', 'syncSignal', 'fetch',
  readFileSync(new URL('../assets/bridges/card.js', import.meta.url), 'utf8'));
function cardDocument({wallet = false, page = 0, unrecognized = false} = {}) {
  const inputs = wallet ? [
    {id: 'ctl00_txtOddFare', value: '0.00', getAttribute: () => null},
    {id: 'ctl00_lblSubsidy', textContent: '1,234.56', getAttribute: () => null},
  ] : [];
  let table;
  const row = values => ({children: values.map(textContent => ({textContent})),
    textContent: values.join(' '), closest: () => table});
  const rows = [row(['交易时间','交易类型','交易金额','手续费','余额','商户']),
    row([`2026-11-0${page} 12:00:00`, page === 1 ? '消费' : '充值', '10.00', '0.00', '0.00', '食堂'])];
  table = {querySelectorAll: () => rows};
  return {
    body: {textContent: page ? '共 2 页' : ''},
    documentElement: {cloneNode: () => ({textContent: '', querySelectorAll: () => []})},
    querySelector: () => null,
    querySelectorAll: selector => selector === 'input, span, label, output' ? inputs
      : selector === 'input[type=hidden][name]' ? [{name: '__VIEWSTATE', value: `state-${page}`}]
      : selector === 'table' && page && !unrecognized ? [table] : [],
  };
}
const requests = [];
class CardDOMParser {
  parseFromString(text) { return cardDocument({page: Number(text)}); }
}
const result = await readCard('2026-11', cardDocument({wallet: true}),
  {href: 'https://webvpn.neu.edu.cn/http/cardprefix/selfsearch/User/baseinfo.aspx'},
  CardDOMParser, new AbortController().signal, async (url, options) => {
    requests.push({url, options});
    const form = new URLSearchParams(options.body || '');
    const page = form.has('ctl00$ContentPlaceHolder1$btnSearch') ? 1
      : Number(form.get('__EVENTARGUMENT') || 0);
    return {ok: true, status: 200, url, headers: new Headers(),
      arrayBuffer: async () => new TextEncoder().encode(String(page)).buffer};
  });
assert.equal(result.balance.balance, 0, 'A live zero is a valid balance');
assert.equal(result.balance.subsidy, 1234.56);
assert.equal(result.bills.length, 2);
assert.equal(result.bills[0].amount, -10);
assert.equal(result.bills[1].amount, 10);
const searchForm = new URLSearchParams(requests[1].options.body);
assert.equal(searchForm.get('ctl00$ContentPlaceHolder1$txtStartDate'), '2026-11-01');
assert.equal(searchForm.get('ctl00$ContentPlaceHolder1$txtEndDate'), '2026-11-30');
const nextForm = new URLSearchParams(requests[2].options.body);
assert.equal(nextForm.get('__VIEWSTATE'), 'state-1', 'Pagination must inherit the latest viewstate');
assert.equal(nextForm.get('__EVENTTARGET'), 'ctl00$ContentPlaceHolder1$AspNetPager1');
assert.equal(nextForm.get('__EVENTARGUMENT'), '2');
assert.ok(requests.every(r => r.url.includes('/http/cardprefix/selfsearch/')));
assert.ok(requests.every(r => r.options.credentials === 'include'));
assert.deepEqual(result.warnings, []);
console.log('Card bridge passed for live zero, comma amounts, gateway prefix, signed bills and latest ASP.NET state.');
