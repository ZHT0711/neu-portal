// Stateful ASP.NET operations are sequential within this browser session.
const clean = value => (value || '').replace(/\s+/g, ' ').trim();
const current = new URL(location.href);
const marker = current.pathname.toLowerCase().indexOf('/selfsearch/');
if (marker < 0) return {error: '请先完成校园卡认证，进入个人基本信息后同步'};
const prefix = current.pathname.slice(0, marker);
const root = current.origin + prefix + '/selfsearch/';
const warnings = [];
const money = value => {
  const text = clean(value).replace(/[￥¥元\s]/g, '');
  return /^[+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?$/.test(text)
    ? Number(text.replace(/,/g, '')) : null;
};
const get = async (url, body) => {
  if (syncSignal.aborted) throw new Error('同步已取消');
  const controller = new AbortController();
  const abort = () => controller.abort();
  syncSignal.addEventListener('abort', abort, {once: true});
  const timeout = setTimeout(abort, 20000);
  try {
  const response = await fetch(url, {credentials: 'include',
    ...(body ? {method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body} : {}),
    signal: controller.signal});
  if (!response.ok) throw new Error('校园卡 HTTP ' + response.status);
  if (!new URL(response.url).pathname.startsWith(prefix + '/selfsearch/')) throw new Error('校园卡会话已失效，请在网页重新认证');
  const bytes = await response.arrayBuffer();
  const preview = new TextDecoder().decode(bytes);
  const charset = response.headers.get('content-type')?.match(/charset=([\w-]+)/i)?.[1]
    || preview.match(/charset=["']?([\w-]+)/i)?.[1] || 'utf-8';
  const doc = new DOMParser().parseFromString(new TextDecoder(charset).decode(bytes), 'text/html');
  if (doc.querySelector('input[type=password]')) throw new Error('请在网页完成校园卡认证');
  return doc;
  } finally { clearTimeout(timeout); syncSignal.removeEventListener('abort', abort); }
};
function balance(doc) {
  function field(names) {
    for (const el of doc.querySelectorAll('input, span, label, output')) {
      if ([el.id, el.getAttribute('name')].some(value => value && names.some(name =>
        value.toLowerCase() === name.toLowerCase() || value.toLowerCase().endsWith('_' + name.toLowerCase())
        || value.toLowerCase().endsWith('$' + name.toLowerCase())))) {
        const value = clean(el.value || el.textContent);
        if (value) return value;
      }
    }
    return '';
  }
  const copy = doc.documentElement.cloneNode(true);
  copy.querySelectorAll('script, style').forEach(el => el.remove());
  const text = clean(copy.textContent);
  const labelled = labels => text.match(new RegExp('(?:' + labels + ')\\s*[:：]?\\s*[￥¥]?\\s*([+-]?(?:\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.\\d{1,2})?)(?![\\d.,*＊])'))?.[1] || '';
  const wallet = money(field(['txtOddFare', 'lblOddFare', 'labOddFare']) || labelled('主钱包余额|主钱包|校园卡余额|卡内余额'));
  if (wallet === null) return null;
  return {balance: wallet, subsidy: money(field(['txtSpecialOddFare','lblSpecialOddFare','txtSubsidy','lblSubsidy']) || labelled('补助余额|补助钱包余额|补贴余额')),
    status: field(['txtStatus','lblStatus','labStatus']) || text.match(/卡状态\s*[:：]\s*([^\s]+)/)?.[1] || ''};
}
const visited = new Set();
function liveBalance(doc, depth = 0) {
  if (!doc || visited.has(doc) || depth > 4) return null;
  visited.add(doc);
  const found = balance(doc);
  if (found) return found;
  for (const frame of doc.querySelectorAll('frame,iframe')) {
    try { const result = liveBalance(frame.contentDocument, depth + 1); if (result) return result; } catch (_) {}
  }
  return null;
}
let wallet = liveBalance(document);
if (!wallet) {
  try { wallet = balance(await get(root + 'User/baseinfo.aspx')); }
  catch (e) { warnings.push(e.message); }
}
if (!wallet) warnings.push('主钱包余额未读取，请在个人基本信息页重试');
let bills = null, truncated = false;
try {
  const url = root + 'User/ConsumeInfo.aspx';
  let doc = await get(url);
  const fieldPrefix = 'ctl00$ContentPlaceHolder1$';
  const [year, monthNumber] = month.split('-').map(Number);
  const last = new Date(Date.UTC(year, monthNumber, 0)).getUTCDate();
  const fields = () => {
    const form = new URLSearchParams();
    for (const input of doc.querySelectorAll('input[type=hidden][name]')) form.set(input.name, input.value);
    form.set(fieldPrefix + 'txtStartDate', month + '-01');
    form.set(fieldPrefix + 'txtEndDate', month + '-' + String(last).padStart(2, '0'));
    form.set(fieldPrefix + 'rbtnType', '0');
    return form;
  };
  const search = fields(); search.set(fieldPrefix + 'btnSearch',
    doc.querySelector('input[name="' + fieldPrefix + 'btnSearch"]')?.value || '查  询');
  doc = await get(url, search.toString());
  const rows = [];
  const fingerprints = new Set();
  for (let page = 1; page <= 10; page++) {
    const pageStart = rows.length;
    let recognized = /暂无|没有|无记录|共\s*0\s*条/.test(doc.body.textContent);
    for (const table of doc.querySelectorAll('table')) {
      const tableRows = [...table.querySelectorAll('tr')].filter(tr => tr.closest('table') === table);
      const header = tableRows.find(tr => /时间|日期/.test(tr.textContent) && /金额/.test(tr.textContent));
      if (!header) continue;
      const labels = [...header.children].map(el => clean(el.textContent));
      const index = expression => labels.findIndex(label => expression.test(label));
      const timeIndex = index(/时间|日期/), amountIndex = index(/交易金额|发生额|金额/), subjectIndex = index(/交易类型|交易名称|摘要|类型|项目/);
      if (timeIndex < 0 || amountIndex < 0) continue;
      recognized = true;
      const feeIndex = index(/手续费/), balanceIndex = index(/余额/), stationIndex = index(/站点|终端|商户|地点/);
      for (const tr of tableRows) {
        if (tr === header) continue;
        const cells = [...tr.children].map(el => clean(el.textContent));
        const timeText = cells[timeIndex] || '';
        if (!/\d{4}[-/年]\d{1,2}[-/月]\d{1,2}/.test(timeText)) continue;
        let amount = money(cells[amountIndex] || '');
        if (amount === null) continue;
        const subject = cells[subjectIndex] || '';
        if (/物联网采集/.test(subject) || /物联网采集/.test(cells[stationIndex] || '') && amount === 0) continue;
        amount = /充值|转账|补助/.test(subject) ? Math.abs(amount) : -Math.abs(amount);
        rows.push({timeText, subject, amount, fee: money(cells[feeIndex] || ''),
          balanceAfter: money(cells[balanceIndex] || ''), station: cells[stationIndex] || ''});
      }
    }
    if (!recognized) throw new Error('流水页面结构未识别，请在网页核对');
    const fingerprint = JSON.stringify(rows.slice(pageStart));
    if (page > 1 && fingerprints.has(fingerprint)) throw new Error('流水翻页未推进，请在网页核对');
    fingerprints.add(fingerprint);
    const pager = doc.body.textContent.match(/共\s*(\d+)\s*页/);
    const pageCount = pager ? Number(pager[1]) : Math.max(1, ...[...doc.querySelectorAll('a[href*="AspNetPager1"]')].map(a => Number(a.textContent)).filter(Number.isFinite));
    if (page >= pageCount) break;
    if (page === 10) { truncated = true; break; }
    const next = fields();
    next.set('__EVENTTARGET', fieldPrefix + 'AspNetPager1'); next.set('__EVENTARGUMENT', String(page + 1));
    doc = await get(url, next.toString());
  }
  bills = rows;
} catch (e) { warnings.push('月流水未读取 · ' + e.message); }
return {balance: wallet, bills, month, truncated, warnings};
