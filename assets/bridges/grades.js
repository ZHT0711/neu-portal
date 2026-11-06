// Ported from NEU-Lumen. MOOC parser adapted from MOOC_reminder under MIT.
    const root = location.href.split('/jwapp/')[0] + '/jwapp/sys/homeapp/';
    if (!location.pathname.includes('/jwapp/')) return {error: '请先完成认证，进入教务系统学生首页后再同步'};
    const get = async (path) => {
        if (syncSignal.aborted) throw new Error('同步已取消');
        const r = await fetch(root + path, {credentials: 'include', headers: {
            'Accept': 'application/json', 'Fetch-Api': 'true', 'X-Requested-With': 'XMLHttpRequest'
        }, signal: syncSignal});
        if (!r.ok) throw new Error('教务接口 HTTP ' + r.status);
        const text = await r.text();
        try { return JSON.parse(text); } catch (_) { throw new Error('教务会话尚未建立，请在网页中完成登录后重试'); }
    };
    const rows = (v) => {
        if (Array.isArray(v)) return v;
        if (v && typeof v === 'object') {
            for (const k of ['datas', 'data', 'rows', 'list']) {
                const list = rows(v[k]); if (list.length) return list;
            }
        }
        return [];
    };
    try {
        const calendar = await get('api/home/student/schoolCalendars.do');
        if (!['0','200'].includes(String(calendar.code)) && calendar.success !== true) return {error: calendar.msg || calendar.message || '学期列表获取失败'};
        const semesters = [];
        for (const t of rows(calendar)) {
            if (!t.itemCode) continue;
            let response;
            try { response = await get('api/home/student/scores.do?termCode=' + encodeURIComponent(t.itemCode)); }
            catch (_) { response = {code: '-1'}; }
            semesters.push({code: String(t.itemCode), name: String(t.itemName || t.itemCode),
                current: ['true','1'].includes(String(t.selected).toLowerCase()), response});
        }
        return {semesters};
    } catch (e) { return {error: e.message || '同步失败，请刷新教务网页后重试'}; }
