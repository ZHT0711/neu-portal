/// 在页面自身的 JS 环境读取词法全局变量；const/let 不一定挂在 window 上。
const portalDocumentScript = r'''
(() => {
  const visible = (el) => !!el && !el.disabled &&
    el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
  const loginForm = Array.from(document.querySelectorAll('input[type="password"]')).some(visible) ||
    !!document.querySelector('#second_auth_form');
  let user = {};
  try {
    if (typeof userInfoDSL !== 'undefined') user = userInfoDSL;
    else if (window.userInfoDSL) user = window.userInfoDSL;
    if (typeof user === 'string') user = JSON.parse(user);
  } catch (_) {}
  return JSON.stringify({user, loginForm,
    sources: Array.from(document.scripts).map(s => s.textContent || '')
      .filter(s => s.includes('userInfoDSL'))});
})()
''';
