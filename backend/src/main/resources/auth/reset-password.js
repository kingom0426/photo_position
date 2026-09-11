(() => {
  // Fragment is never sent in HTTP requests or referrer headers. Clear it from browser history.
  let token;
  const form = document.getElementById('reset-form');
  const button = document.getElementById('submit');
  const result = document.getElementById('result');
  function loadToken() {
    token = new URLSearchParams(location.hash.slice(1)).get('token');
    history.replaceState(null, '', location.pathname);
    const valid = token && /^[A-Za-z0-9_-]{43}$/.test(token);
    form.reset();
    form.hidden = !valid;
    button.disabled = false;
    result.textContent = valid ? '' : '链接无效，请在 Lumen 登录页重新申请。';
  }
  loadToken();
  // Mail apps may reopen a second link in the same tab without a full navigation.
  window.addEventListener('hashchange', loadToken);
  form.addEventListener('submit', async event => {
    event.preventDefault();
    const password = document.getElementById('password').value;
    if (password !== document.getElementById('confirm').value) {
      result.textContent = '两次输入的密码不一致。';
      return;
    }
    button.disabled = true;
    result.textContent = '正在重置…';
    const submittedToken = token;
    try {
      const response = await fetch('/api/auth/reset-password', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({token, password}), credentials: 'omit', cache: 'no-store'
      });
      const body = await response.json();
      if (submittedToken !== token) return;
      if (!response.ok) throw new Error(body.error || '重置失败，请稍后再试。');
      form.reset();
      form.hidden = true;
      result.textContent = body.message;
    } catch (error) {
      if (submittedToken !== token) return;
      result.textContent = error.message || '网络异常，请重试。';
      button.disabled = false;
    }
  });
})();
