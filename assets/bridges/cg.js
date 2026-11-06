// Ported from NEU-Lumen. MOOC parser adapted from MOOC_reminder under MIT.
    const root = new URL(rootURL);
    const original = new URL(originalRootURL);
    const prefix = root.pathname.slice(0, root.pathname.indexOf('/assignment/'));
    const assignments = new Map();
    const warnings = [];
    const clean = value => (value || '').replace(/\s+/g, ' ').trim();
    function route(raw, pageURL) {
      try {
        let url = new URL(raw, pageURL);
        if (url.origin === original.origin) url = new URL(prefix + url.pathname + url.search, root.origin);
        else if (raw.startsWith('/assignment/')) url = new URL(prefix + raw, root.origin);
        if (url.origin !== root.origin || !url.pathname.startsWith(prefix + '/assignment/')) return null;
        url.hash = '';
        return url;
      } catch (_) { return null; }
    }
    async function get(url) {
      if (syncSignal.aborted) throw new Error('同步已取消');
      const controller = new AbortController();
      const abort = () => controller.abort();
      syncSignal.addEventListener('abort', abort, {once: true});
      const timeout = setTimeout(() => controller.abort(), 12000);
      try {
        const response = await fetch(url, {credentials: 'include', signal: controller.signal});
        if (!response.ok) throw new Error('HTTP ' + response.status);
        const bytes = await response.arrayBuffer();
        const header = response.headers.get('content-type') || '';
        const preview = new TextDecoder().decode(bytes);
        const charset = header.match(/charset=([\w-]+)/i)?.[1] || preview.match(/charset=["']?([\w-]+)/i)?.[1] || 'utf-8';
        const html = new TextDecoder(charset).decode(bytes);
        const doc = new DOMParser().parseFromString(html, 'text/html');
        if (!html.trim() || doc.querySelector('input[type="password"]') || !route(response.url, rootURL)) {
          throw new Error('请打开 CG 网页完成登录后同步作业');
        }
        return {doc, url: response.url};
      } finally { clearTimeout(timeout); syncSignal.removeEventListener('abort', abort); }
    }
    function parse(doc, pageURL, requestedID) {
      let history = false;
      for (const el of doc.querySelectorAll('.col-2 span.text-muted, a[href*="index.jsp"][href*="assignID="]')) {
        if (el.matches('span.text-muted')) { history = el.textContent.includes('历史'); continue; }
        const url = route(el.getAttribute('href'), pageURL);
        const id = url && url.searchParams.get('assignID');
        if (!id) continue;
        const copy = el.cloneNode(true);
        copy.querySelectorAll('.badge').forEach(badge => badge.remove());
        if (!assignments.has(id)) assignments.set(id, {id, title: clean(copy.textContent) || ('作业 ' + id),
          url: url.href, history, late: /补交/.test(el.textContent), loaded: false, deadline: '', problems: []});
      }
      const text = clean(doc.body.textContent);
      const time = text.match(/作业时间[:：]\s*[\d-]+\s+[\d:]+\s*至\s*([\d-]+\s+[\d:]+)/);
      const pageID = new URL(pageURL).searchParams.get('assignID') || requestedID;
      if (pageID && assignments.has(pageID) && time) assignments.get(pageID).deadline = time[1];
      const count = text.match(/共\s*(\d+)\s*道?\s*题/);
      if (pageID && assignments.has(pageID) && count) assignments.get(pageID).expectedCount = Number(count[1]);
      const seen = new Set();
      for (const link of doc.querySelectorAll('a[href]')) {
        const raw = link.getAttribute('href') || '';
        // Current CG pages open a problem in an AI side panel. Extract its URL as data.
        const panel = raw.match(/openAILeftFrame\s*\(\s*'[^']*'\s*,\s*'([^']*problemContent\.jsp[^']*)'\s*\)/)
          || raw.match(/openAILeftFrame\s*\(\s*"[^"]*"\s*,\s*"([^"]*problemContent\.jsp[^"]*)"\s*\)/);
        if (!/programList(?:_ce)?\.jsp|problemContent\.jsp/.test(raw)) continue;
        const url = route(panel ? panel[1] : raw, pageURL);
        const id = url && (url.searchParams.get('assignID') || pageID);
        const number = url && (url.searchParams.get('proNum') || url.searchParams.get('problemID'));
        if (!id || !number || seen.has(id + '.' + number)) continue;
        seen.add(id + '.' + number);
        if (!assignments.has(id)) assignments.set(id, {id, title: clean(doc.querySelector('h4')?.textContent) || ('作业 ' + id),
          url: pageURL, history: false, late: false, loaded: false, deadline: '', problems: []});
        const assignment = assignments.get(id);
        if (time) assignment.deadline = time[1];
        const row = link.closest('tr');
        const cells = row ? [...row.children].filter(el => el.tagName === 'TD') : [];
        const status = cells.at(-1);
        const problem = {id: number, title: clean(link.textContent).replace(/^\d+[.、]\s*/, '') || ('第 ' + number + ' 题'), url: url.href,
          statusText: clean(status?.textContent)};
        const index = assignment.problems.findIndex(item => item.id === number);
        if (index < 0) assignment.problems.push(problem); else assignment.problems[index] = problem;
        assignment.loaded = true;
      }
      if (pageID && assignments.has(pageID) && !assignments.get(pageID).loaded) {
        warnings.push(assignments.get(pageID).title + '的题目未读取，请在网页核对');
      }
      if (pageID && count && assignments.has(pageID) && assignments.get(pageID).problems.length < Number(count[1])) {
        warnings.push(assignments.get(pageID).title + '的题目数据不完整，请在网页核对');
      }
    }
    try {
      const first = await get(rootURL);
      const current = first.doc.querySelector('a.active[href*="assignID="], .active a[href*="assignID="]');
      const currentID = current && route(current.getAttribute('href'), first.url)?.searchParams.get('assignID');
      parse(first.doc, first.url, currentID);
      const pending = [...assignments.values()].filter(item => !item.loaded);
      if (pending.length > 100) warnings.push('作业数量超过单次同步上限，部分作业尚未读取');
      // The JSP platform keeps the selected assignment in the session. Read serially.
      for (const item of pending.slice(0, 100)) {
          try { const page = await get(item.url); parse(page.doc, page.url, item.id); }
          catch (error) { warnings.push(item.title + '：' + error.message); }
      }
      if (!assignments.size) return {error: '未读取到 CG 作业，请打开平台登录后同步'};
      return {assignments: [...assignments.values()], warnings: [...new Set(warnings)]};
    } catch (error) { return {error: 'CG 作业同步失败：' + error.message}; }
