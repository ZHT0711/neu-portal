// Ported from NEU-Lumen. MOOC parser adapted from MOOC_reminder under MIT.
    const clean = value => (value || '').replace(/\s+/g, ' ').trim();
    const courses = new Map();
    function add(raw, title) {
      try {
        const url = new URL(raw, location.href);
        if (url.hostname !== 'www.icourse163.org' || /forum|detail/.test(url.hash)) return;
        const match = url.pathname.match(/\/(?:mooc\/|spoc\/)?learn\/([^/?#]+)/);
        const tid = url.searchParams.get('tid');
        if (!match || !tid || !/^\d+$/.test(tid)) return;
        courses.set(match[1] + '.' + tid, {id: match[1], termID: tid,
          title: clean(title) || match[1], url: url.href});
      } catch (_) {}
    }
    const own = /\/(?:mooc\/|spoc\/)?learn\//.test(location.pathname);
    if (own) {
      add(location.href, document.querySelector('.course-name, .f-cb .f-fl h4, h1')?.textContent || document.title);
      const active = window.moocTermDto?.id || window.termDto?.id;
      if (location.pathname.includes('/spoc/') && active) {
        for (const course of courses.values()) course.activeTermID = String(active);
      }
    }
    else for (const link of document.querySelectorAll('a[href*="/learn/"]')) {
      add(link.href, link.getAttribute('title') || link.textContent);
    }
    return {courses: [...courses.values()]};
