// Ported from NEU-Lumen. MOOC parser adapted from MOOC_reminder under MIT.
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const outlines = extractLearnOutlines([...doc.querySelectorAll('script')].map(el => el.textContent).join('\n'));
    const route = new URL(course.url);
    const term = html.match(/(?:moocTerm|term)Dto\s*=\s*\{\s*["']?id["']?\s*:\s*(\d+)/)
      || html.match(/"(?:moocTerm|term)Dto"\s*:\s*\{[^}]*?"id"\s*:\s*(\d+)/)
      || html.match(/(?:moocTerm|term)Dto\s*=\s*new\s+\w+\s*[({]\s*(\d+)/);
    const items = new Map();
    function merge(item) {
      const previous = items.get(item.uid);
      if (previous?.checkedOff && !item.checkedOff) {
        item = {...item, checkedOff: true, score: previous.score ?? item.score,
          totalScore: previous.totalScore ?? item.totalScore};
      }
      items.set(item.uid, item);
    }
    let recognized = outlines.length > 0;
    function hasOutline(value, depth = 0) {
      if (!value || typeof value !== 'object' || depth > 12) return false;
      if (Array.isArray(value.chapters)) return true;
      return Object.values(value).some(child => child && typeof child === 'object' && hasOutline(child, depth + 1));
    }
    for (const response of responses) {
      const data = coerceJson(response.raw);
      if (!hasOutline(data)) continue;
      recognized = true;
      const meta = {courseId: course.id, termId: response.termID, courseName: course.title, pageUrl: course.url};
      for (const item of extractHomeworkFromTermDto(data, meta)) merge(item);
    }
    for (const outline of outlines) {
      const meta = {courseId: course.id, termId: course.termID, courseName: course.title, pageUrl: course.url};
      for (const item of extractHomeworkFromTermDto(outline, meta)) merge(item);
    }
    function destination() {
      const url = new URL(course.url);
      if (/\/learn\/[^/]+\//.test(url.pathname)) {
        url.pathname = url.pathname.replace(/(\/learn\/[^/]+)\/.*/, '$1/assessments');
        url.hash = '';
      } else url.hash = '/learn/testlist';
      return url.href;
    }
    return {recognized, activeTermID: route.pathname.includes('/spoc/') && term ? term[1] : '',
      assignments: [...items.values()].filter(item => item.type === 'quiz' || item.type === 'homework').map(item => ({id: item.uid, courseKey: course.id + '.' + course.termID,
        courseTitle: course.title, title: item.title,
        kind: item.type === 'quiz' ? '测验' : '作业',
        url: destination(), deadline: item.deadline ? Date.parse(item.deadline) : null,
        deadlineText: '', completed: item.checkedOff === true,
        statusText: (item.checkedOff ? '已提交 / 已完成' : '未发现提交记录')
          + (item.hwPhase === 'peerreview' ? ' · 当前互评期' : ''),
        scoreText: item.score == null ? '' : String(item.score) + (item.totalScore == null ? '' : ' / ' + item.totalScore)}))};
