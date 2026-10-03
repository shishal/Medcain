(() => {
  const panel = document.getElementById('panel');
  const params = new URLSearchParams(window.location.search);
  const prefilledEmail = params.get('email') || '';
  const requestedPlan = (params.get('plan') || 'pro').toLowerCase();

  const config = window.CHECKOUT_CONFIG;
  if (
    !config ||
    !config.supabaseUrl ||
    !config.supabaseAnonKey ||
    config.supabaseUrl.includes('YOUR_PROJECT')
  ) {
    const local =
      window.location.hostname === '127.0.0.1' ||
      window.location.hostname === 'localhost';
    panel.innerHTML = local
      ? '<p class="error">Checkout is not configured. Copy <code>config.example.js</code> to <code>config.js</code>, or run <code>python3 checkout/serve.py</code>.</p>'
      : '<p class="error">Checkout is not available right now. Email support@medico.shishal.com if this keeps happening.</p>';
    return;
  }

  const supabase = window.supabase.createClient(
    config.supabaseUrl,
    config.supabaseAnonKey,
  );

  let selectedPlan =
    requestedPlan === 'elite' || requestedPlan === 'pro' ? requestedPlan : 'pro';
  let busy = false;
  // List prices from paid_plan_catalog. Null until the first successful load.
  let catalogByPlan = null;
  // The server prices the order. These only remember what the student typed
  // and the last quote checkout_quote() returned.
  let draftCode = '';
  let discountError = '';
  let appliedQuote = null;
  let quoteSeq = 0;

  async function loadCatalog() {
    const { data, error } = await supabase
      .from('paid_plan_catalog')
      .select('plan, amount_paise');
    if (error || !Array.isArray(data)) return null;
    const byPlan = {};
    for (const row of data) {
      const paise = row && row.amount_paise;
      if (
        row &&
        (row.plan === 'pro' || row.plan === 'elite') &&
        Number.isInteger(paise) &&
        paise >= 100
      ) {
        byPlan[row.plan] = paise;
      }
    }
    if (!Number.isInteger(byPlan.pro) || !Number.isInteger(byPlan.elite)) {
      return null;
    }
    return byPlan;
  }

  function formatInr(paise) {
    return new Intl.NumberFormat('en-IN', {
      style: 'currency',
      currency: 'INR',
      maximumFractionDigits: 0,
    }).format(paise / 100);
  }

  function quoteError(error) {
    const raw = (error && error.message) || '';
    const known = [
      'That code is not valid.',
      'That code has expired.',
      'That code has been used up.',
      'Referral codes cannot be used on your own payment.',
      'You already used this code.',
      'That discount is too large for this plan.',
      'Sign in to continue.',
    ].find((item) => raw.includes(item));
    if (known) return known;
    if (raw && raw.length < 180) return raw;
    return 'That code is not valid.';
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  }

  async function currentUser() {
    const { data } = await supabase.auth.getUser();
    return data.user;
  }

  function showError(message) {
    const existing = panel.querySelector('.error');
    if (existing) existing.remove();
    const p = document.createElement('p');
    p.className = 'error';
    p.textContent = message;
    panel.prepend(p);
  }

  function renderLogin() {
    panel.innerHTML = `
      <form class="card" id="login-form">
        <p>Use the email and password from the Medico app.</p>
        <label for="email">Email</label>
        <input id="email" type="email" autocomplete="email" required />
        <label for="password">Password</label>
        <input id="password" type="password" autocomplete="current-password" required />
        <button class="primary" type="submit">Sign in</button>
      </form>
    `;
    panel.querySelector('#email').value = prefilledEmail;

    panel.querySelector('#login-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      const email = panel.querySelector('#email').value.trim();
      const password = panel.querySelector('#password').value;
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });
      if (error) {
        showError(error.message);
        return;
      }
      await renderApp();
    });
  }

  function renderPlans(user) {
    const plans = window.PAID_PLANS;
    if (!catalogByPlan) {
      panel.innerHTML =
        '<p class="error">Prices are unavailable right now. Reload the page and try again.</p>';
      return;
    }
    const cards = Object.entries(plans)
      .map(([id, plan]) => {
        const paise = catalogByPlan[id];
        if (!Number.isInteger(paise)) return '';
        const selected = id === selectedPlan ? ' selected' : '';
        return `
          <div class="card${selected}">
            <button class="plan-pick" type="button" data-plan="${id}">
              <div class="row">
                <strong>${escapeHtml(plan.label)}</strong>
                <span class="price">${formatInr(paise)}</span>
              </div>
              <p class="muted">${escapeHtml(plan.tagline)} · ${escapeHtml(plan.periodLabel)}</p>
            </button>
          </div>
        `;
      })
      .join('');

    const payLabel = appliedQuote
      ? `Pay ${formatInr(appliedQuote.amount_paise)}`
      : 'Pay with Razorpay';
    const discountHtml = discountError
      ? `<p class="error">${escapeHtml(discountError)}</p>`
      : appliedQuote
        ? `<p class="success">${escapeHtml(String(appliedQuote.percent_off))}% off · you pay ${formatInr(appliedQuote.amount_paise)}</p>`
        : '';

    panel.innerHTML = `
      <p class="muted">Signed in as ${escapeHtml(user.email)}</p>
      ${cards}
      <label for="code">Discount or referral code</label>
      <input id="code" name="code" type="text" maxlength="20" autocomplete="off" spellcheck="false" />
      <button class="ghost" id="apply-code" type="button">Apply code</button>
      ${discountHtml}
      <button class="primary" id="pay" type="button">${escapeHtml(payLabel)}</button>
      <button class="ghost" id="sign-out" type="button">Sign out</button>
    `;
    panel.querySelector('#code').value = draftCode;

    panel.querySelectorAll('[data-plan]').forEach((button) => {
      button.addEventListener('click', () => {
        draftCode = panel.querySelector('#code').value.trim();
        selectedPlan = button.getAttribute('data-plan');
        appliedQuote = null;
        discountError = '';
        renderPlans(user);
        if (draftCode) applyCode(user);
      });
    });

    panel.querySelector('#apply-code').addEventListener('click', () => applyCode(user));
    panel.querySelector('#pay').addEventListener('click', () => startPay(user));
    panel.querySelector('#sign-out').addEventListener('click', async () => {
      await supabase.auth.signOut();
      renderLogin();
    });
  }

  function renderSuccess() {
    panel.innerHTML = `
      <div class="card">
        <p class="success">Payment received.</p>
        <p>
          Your plan should update within a few seconds. Reopen Medico and tap
          refresh on Profile if it still shows Free.
        </p>
        <p class="muted">You can close this tab.</p>
      </div>
    `;
  }

  async function applyCode(user) {
    const seq = ++quoteSeq;
    draftCode = (panel.querySelector('#code')?.value || draftCode).trim();
    discountError = '';
    appliedQuote = null;
    if (!draftCode) {
      renderPlans(user);
      return;
    }

    const { data, error } = await supabase.rpc('checkout_quote', {
      p_plan: selectedPlan,
      p_code: draftCode,
    });
    if (seq !== quoteSeq) return;

    if (error || !data || typeof data.amount_paise !== 'number') {
      discountError = quoteError(error);
      renderPlans(user);
      return;
    }

    appliedQuote = data;
    draftCode = data.code || draftCode;
    renderPlans(user);
  }

  async function startPay(user) {
    if (busy) return;
    busy = true;
    draftCode = (panel.querySelector('#code')?.value || draftCode).trim();
    const payButton = panel.querySelector('#pay');
    if (payButton) {
      payButton.disabled = true;
      payButton.textContent = 'Opening Razorpay…';
    }

    const { data, error } = await supabase.functions.invoke(
      'create-razorpay-order',
      {
        body: {
          plan: selectedPlan,
          code: draftCode || null,
        },
      },
    );

    let invokeError = null;
    if (error) {
      invokeError = error.message || 'Could not start checkout.';
      try {
        const body = await error.context.json();
        if (body && body.error) invokeError = body.error;
      } catch {
        // Non-JSON error body from the gateway / undeployed function.
      }
    }

    if (invokeError || !data || !data.orderId) {
      busy = false;
      renderPlans(user);
      showError(invokeError || (data && data.error) || 'Could not start checkout.');
      return;
    }

    if (typeof window.Razorpay !== 'function') {
      busy = false;
      renderPlans(user);
      showError('Razorpay failed to load. Check your network and try again.');
      return;
    }

    const options = {
      key: data.keyId,
      amount: data.amount,
      currency: data.currency,
      name: data.name,
      description: data.description,
      order_id: data.orderId,
      prefill: { email: data.prefillEmail || user.email },
      theme: { color: '#008FD6' },
      handler() {
        busy = false;
        renderSuccess();
      },
      modal: {
        ondismiss() {
          busy = false;
          renderPlans(user);
        },
      },
    };

    const rzp = new window.Razorpay(options);
    rzp.on('payment.failed', () => {
      busy = false;
      renderPlans(user);
      showError('Payment failed. No charge was kept. You can try again.');
    });
    rzp.open();
  }

  async function renderApp() {
    const user = await currentUser();
    if (!user) {
      renderLogin();
      return;
    }
    catalogByPlan = await loadCatalog();
    renderPlans(user);
  }

  renderApp();
})();
