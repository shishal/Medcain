(() => {
  const panel = document.getElementById('panel');
  const params = new URLSearchParams(window.location.search);
  let prefilledPhone = params.get('phone') || '';
  const requestedPlan = (params.get('plan') || '').trim().toLowerCase();
  const requestedCode = params.get('code') || '';

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
      : '<p class="error">Checkout is not available right now. Email medcain@shishal.com if this keeps happening.</p>';
    return;
  }

  const supabase = window.supabase.createClient(
    config.supabaseUrl,
    config.supabaseAnonKey,
  );

  let selectedPlanId = '';
  let busy = false;
  // Public paid plans from the plans table. The page never invents a price.
  let catalog = [];
  // The server prices the order. These only remember what the student typed
  // and the last quote checkout_quote() returned.
  let draftCode = requestedCode;
  let discountError = '';
  let appliedQuote = null;
  let quoteSeq = 0;
  let autoApplied = false;
  let pollTimer = 0;
  let pollGen = 0;
  let pollBusy = false;

  async function loadCatalog() {
    const { data, error } = await supabase
      .from('plans')
      .select(
        'id, code, name, tagline, benefits, amount_paise, duration_months, duration_label, promo_headline, promo_detail, featured_discount_code, sort_order',
      )
      .eq('is_public', true)
      .eq('is_active', true)
      .order('sort_order');
    if (error || !Array.isArray(data)) return null;
    const rows = data.filter((row) => {
      return row &&
        typeof row.id === 'string' &&
        Number.isInteger(row.amount_paise) &&
        row.amount_paise >= 100 &&
        Number.isInteger(row.duration_months) &&
        row.duration_months >= 1;
    });
    return rows.length ? rows : null;
  }

  function selectedPlan() {
    return catalog.find((row) => row.id === selectedPlanId) || null;
  }

  function chooseInitialPlan() {
    const match = catalog.find((row) => {
      return row.id === requestedPlan || String(row.code || '').toLowerCase() === requestedPlan;
    });
    selectedPlanId = (match || catalog[0]).id;
    const plan = selectedPlan();
    if (!draftCode && plan && plan.featured_discount_code) {
      draftCode = plan.featured_discount_code;
    }
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
      'Choose a plan.',
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

  function accountLabel(user) {
    if (user && user.phone) return user.phone;
    const email = (user && user.email) || '';
    if (!email || email.endsWith('@auth.medico.internal')) {
      return 'your WhatsApp number';
    }
    return email;
  }

  function stopPoll() {
    pollGen += 1;
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = 0;
    }
  }

  async function invokeFunction(name, body) {
    const { data, error } = await supabase.functions.invoke(name, { body });
    if (!error) return { data };
    let message = error.message || 'Could not sign in. Please try again.';
    try {
      const parsed = await error.context.json();
      if (parsed && parsed.error) message = parsed.error;
    } catch {
      // Non-JSON error body from the gateway / undeployed function.
    }
    return { error: message, data };
  }

  function renderLogin() {
    stopPoll();
    panel.innerHTML = `
      <form class="card" id="login-form">
        <p>Enter the WhatsApp number for this account. You send us a message — we never text you a code. A new number creates the account.</p>
        <label for="phone">WhatsApp number</label>
        <input id="phone" type="tel" autocomplete="tel" inputmode="tel" required placeholder="9876543210" />
        <button class="primary" type="submit">Continue with WhatsApp</button>
      </form>
    `;
    panel.querySelector('#phone').value = prefilledPhone;

    panel.querySelector('#login-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      const phone = panel.querySelector('#phone').value.trim();
      const button = panel.querySelector('#login-form button');
      if (button) button.disabled = true;
      // Open during the click, before the network wait, or the browser blocks it.
      const popup = window.open('about:blank', '_blank');
      const result = await invokeFunction('whatsapp-auth-start', { phone });
      const data = result.data || {};
      const waUrl = typeof data.wa_url === 'string' ? data.wa_url : '';
      if (
        result.error ||
        !waUrl.startsWith('https://wa.me/') ||
        !data.challenge_id ||
        !data.secret
      ) {
        if (popup) popup.close();
        prefilledPhone = phone;
        renderLogin();
        showError(result.error || 'Could not start WhatsApp sign-in. Please try again.');
        return;
      }
      if (popup) popup.location = waUrl;
      renderWaiting({
        phone: data.phone || phone,
        message: data.message || '',
        waUrl,
        challengeId: data.challenge_id,
        secret: data.secret,
      });
    });
  }

  function renderWaiting(state) {
    panel.innerHTML = `
      <div class="card">
        <p>Send this message from <strong>${escapeHtml(state.phone)}</strong>. Don't edit it. We sign you in when it arrives.</p>
        <p><strong>${escapeHtml(state.message)}</strong></p>
        <button class="primary" id="open-wa" type="button">Open WhatsApp</button>
        <p class="muted" id="wait-status">Waiting for your message…</p>
        <button class="ghost" id="cancel-wa" type="button">Use a different number</button>
      </div>
    `;
    panel.querySelector('#open-wa').addEventListener('click', () => {
      window.open(state.waUrl, '_blank', 'noopener');
    });
    panel.querySelector('#cancel-wa').addEventListener('click', () => {
      renderLogin();
    });
    const gen = pollGen;
    const tick = () => pollOnce(gen, state.challengeId, state.secret);
    tick();
    pollTimer = window.setInterval(tick, 2000);
  }

  async function pollOnce(gen, challengeId, secret) {
    if (gen !== pollGen || pollBusy) return;
    pollBusy = true;
    try {
    const result = await invokeFunction('whatsapp-auth-status', {
      challenge_id: challengeId,
      secret,
    });
    if (gen !== pollGen) return;
    const data = result.data || {};
    if (data.status === 'pending') return;
    if (
      data.status === 'ready' &&
      data.access_token &&
      data.refresh_token
    ) {
      stopPoll();
      const { error } = await supabase.auth.setSession({
        access_token: data.access_token,
        refresh_token: data.refresh_token,
      });
      if (error) {
        renderLogin();
        showError('Could not finish sign-in. Please try again.');
        return;
      }
      await renderApp();
      return;
    }
    stopPoll();
    renderLogin();
    showError(result.error || data.error || 'Could not finish sign-in. Please try again.');
    } finally {
      pollBusy = false;
    }
  }

  function durationText(plan) {
    if (plan.duration_label) return plan.duration_label;
    if (plan.duration_months) return `${plan.duration_months} months`;
    return '';
  }

  function renderPlans(user) {
    const current = selectedPlan();
    if (!catalog.length || !current) {
      panel.innerHTML =
        '<p class="error">Prices are unavailable right now. Reload the page and try again.</p>';
      return;
    }

    const planCards = catalog
      .map((plan) => {
        const selected = plan.id === selectedPlanId ? ' selected' : '';
        const promo = plan.promo_headline
          ? `<p class="success">${escapeHtml(plan.promo_headline)}${plan.promo_detail ? ` · ${escapeHtml(plan.promo_detail)}` : ''}</p>`
          : '';
        const benefits = Array.isArray(plan.benefits)
          ? plan.benefits.map((line) => `<p class="muted">${escapeHtml(line)}</p>`).join('')
          : '';
        return `
          <div class="card${selected}">
            <button class="plan-pick" type="button" data-plan="${escapeHtml(plan.id)}">
              <div class="row">
                <strong>${escapeHtml(plan.name)}</strong>
                <span class="price">${formatInr(plan.amount_paise)}</span>
              </div>
              <p class="muted">${escapeHtml(durationText(plan))}${plan.tagline ? ` · ${escapeHtml(plan.tagline)}` : ''}</p>
              ${benefits}
              ${promo}
            </button>
          </div>
        `;
      })
      .join('');

    const payLabel = appliedQuote
      ? `Pay ${formatInr(appliedQuote.amount_paise)}`
      : `Pay ${formatInr(current.amount_paise)}`;
    const discountHtml = discountError
      ? `<p class="error">${escapeHtml(discountError)}</p>`
      : appliedQuote
        ? `<p class="success">${escapeHtml(String(appliedQuote.percent_off))}% off · you pay ${formatInr(appliedQuote.amount_paise)}</p>`
        : '';

    panel.innerHTML = `
      <p class="muted">Signed in as ${escapeHtml(accountLabel(user))}</p>
      ${planCards}
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
        const typed = panel.querySelector('#code').value.trim();
        selectedPlanId = button.getAttribute('data-plan');
        const next = selectedPlan();
        draftCode = typed || (next && next.featured_discount_code) || '';
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
      p_plan_id: selectedPlanId,
      p_code: draftCode,
    });
    if (seq !== quoteSeq) return;

    if (error || !data || typeof data.amount_paise !== 'number') {
      discountError = quoteError(error);
      renderPlans(user);
      return;
    }

    appliedQuote = data;
    draftCode = data.discount_code || draftCode;
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
          plan_id: selectedPlanId,
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

    const prefill = {};
    if (data.prefillEmail) prefill.email = data.prefillEmail;
    const contact = data.prefillPhone || (user && user.phone);
    if (contact) prefill.contact = contact;

    const options = {
      key: data.keyId,
      amount: data.amount,
      currency: data.currency,
      name: data.name,
      description: data.description,
      order_id: data.orderId,
      prefill,
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
    stopPoll();
    const user = await currentUser();
    if (!user) {
      renderLogin();
      return;
    }
    catalog = (await loadCatalog()) || [];
    if (catalog.length) chooseInitialPlan();
    renderPlans(user);
    if (!autoApplied && draftCode && selectedPlan()) {
      autoApplied = true;
      await applyCode(user);
    }
  }

  renderApp();
})();
