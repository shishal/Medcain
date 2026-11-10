/* MEDCAIN website admin. Talks to Supabase with the public anon key only. */
(function () {
  const page = document.body.getAttribute('data-page') || 'home';
  const app = document.getElementById('app');
  const handlers = { submit: null, click: null, change: null };
  let supabase = null;
  let pollTimer = 0;
  let pollGen = 0;
  let pollBusy = false;

  const PLANS = [
    ['free', 'Free'],
    ['pro', 'Pro'],
    ['elite', 'Elite'],
  ];
  const PAID_PLANS = [
    ['pro', 'Pro'],
    ['elite', 'Elite'],
  ];
  const KINDS = [
    ['pyq_theory', 'Theory'],
    ['mcq', 'MCQ'],
  ];
  const DIFFICULTIES = [
    ['must', 'Must'],
    ['should', 'Should'],
    ['could', 'Could'],
  ];
  const EXAMS = [
    ['prof', 'Prof'],
    ['supply', 'Supply'],
    ['pre_prof', 'Pre prof'],
    ['internal', 'Internal'],
  ];
  const MONTHS = [
    [1, 'January'],
    [2, 'February'],
    [3, 'March'],
    [4, 'April'],
    [5, 'May'],
    [6, 'June'],
    [7, 'July'],
    [8, 'August'],
    [9, 'September'],
    [10, 'October'],
    [11, 'November'],
    [12, 'December'],
  ];
  const CATEGORIES = [
    ['general', 'News'],
    ['version', 'Update'],
    ['offer', 'Offer'],
    ['payment', 'Payment'],
  ];
  const PERIODS = {
    y1: '1 year',
    y2: '2 years + 1 month extra',
    y3: '3 years + 2 months extra',
    y4: '4 years + 3 months extra',
  };

  const pages = {
    home: renderHome,
    questions: renderQuestions,
    question: renderQuestion,
    catalog: renderCatalog,
    users: renderUsers,
    user: renderUser,
    announcements: renderAnnouncements,
    pricing: renderPricing,
    coupons: renderCoupons,
    backup: renderBackup,
  };

  function esc(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  }

  function errorText(error) {
    const raw = (error && (error.message || error.details)) || 'Something went wrong.';
    const text = String(raw);
    return text.length > 400 ? 'Something went wrong. Try again.' : text;
  }

  function clip(text, max) {
    const flat = String(text || '').replace(/\s+/g, ' ').trim();
    if (flat.length <= max) return flat;
    return flat.slice(0, max - 1) + '…';
  }

  function labelOf(pairs, value) {
    const found = pairs.find((item) => String(item[0]) === String(value));
    return found ? found[1] : value || '';
  }

  function monthName(month) {
    return labelOf(MONTHS, Number(month));
  }

  function queryParam(name) {
    return new URLSearchParams(location.search).get(name) || '';
  }

  function message(kind, text) {
    const slot = document.getElementById('msg');
    if (!slot) return;
    slot.innerHTML = text ? `<p class="msg ${kind}">${esc(text)}</p>` : '';
  }

  function field(label, control) {
    return `<label>${esc(label)}${control}</label>`;
  }

  function inputControl(id, value, extra) {
    return `<input id="${esc(id)}" name="${esc(id)}" value="${esc(value ?? '')}" ${extra || ''} />`;
  }

  function areaControl(id, value, rows) {
    return `<textarea id="${esc(id)}" name="${esc(id)}" rows="${rows || 4}">${esc(value || '')}</textarea>`;
  }

  function replaceSelect(id, pairs, selected, placeholder) {
    const current = document.getElementById(id);
    if (!current) return;
    const wrap = document.createElement('div');
    wrap.innerHTML = selectControl(id, pairs, selected, placeholder);
    current.replaceWith(wrap.firstElementChild);
  }

  function selectControl(id, pairs, selected, placeholder) {
    const options = [];
    if (placeholder !== undefined) {
      options.push(`<option value="">${esc(placeholder)}</option>`);
    }
    for (const pair of pairs) {
      const value = pair[0];
      const label = pair[1];
      const on = String(value) === String(selected ?? '') ? ' selected' : '';
      options.push(`<option value="${esc(value)}"${on}>${esc(label)}</option>`);
    }
    return `<select id="${esc(id)}" name="${esc(id)}">${options.join('')}</select>`;
  }

  function checkControl(id, label, on) {
    return `<label class="check"><input id="${esc(id)}" name="${esc(id)}" type="checkbox"${on ? ' checked' : ''} /> ${esc(label)}</label>`;
  }

  function markdownControl(id, labelText, value) {
    return `<div class="md-field span-2">
      <div class="md-tabs">
        <strong>${esc(labelText)}</strong>
        <button class="btn btn-ghost btn-small" type="button" data-md="${esc(id)}" data-mode="write" aria-pressed="true">Write</button>
        <button class="btn btn-ghost btn-small" type="button" data-md="${esc(id)}" data-mode="preview" aria-pressed="false">Preview</button>
      </div>
      <textarea id="${esc(id)}" name="${esc(id)}">${esc(value || '')}</textarea>
      <div class="md-preview" id="${esc(id)}-preview" hidden></div>
    </div>`;
  }

  function renderMarkdown(text) {
    const source = esc(text || '');
    if (!window.marked || typeof window.marked.parse !== 'function') {
      return `<p>${source}</p>`;
    }
    let html = '';
    try {
      html = window.marked.parse(source, { headerIds: false, mangle: false });
    } catch (error) {
      return `<p>${source}</p>`;
    }
    const doc = new DOMParser().parseFromString(html, 'text/html');
    doc.querySelectorAll('script,style,iframe,object,embed,link,meta').forEach((node) => {
      node.remove();
    });
    doc.body.querySelectorAll('*').forEach((el) => {
      [...el.attributes].forEach((attr) => {
        const name = attr.name.toLowerCase();
        if (name.startsWith('on') || name === 'style') el.removeAttribute(attr.name);
      });
      if (el.tagName === 'A') {
        const href = el.getAttribute('href') || '';
        if (!/^https?:\/\//i.test(href) && !/^mailto:/i.test(href)) {
          el.removeAttribute('href');
        } else {
          el.setAttribute('rel', 'noopener noreferrer');
          el.setAttribute('target', '_blank');
        }
      }
      if (el.tagName === 'IMG') el.remove();
    });
    return doc.body.innerHTML;
  }

  function val(id) {
    const node = document.getElementById(id);
    return node ? node.value.trim() : '';
  }

  function checked(id) {
    const node = document.getElementById(id);
    return !!(node && node.checked);
  }

  function toDateInput(iso) {
    if (!iso) return '';
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return '';
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  function endOfLocalDay(dateStr) {
    if (!dateStr) return null;
    const parts = dateStr.split('-').map(Number);
    if (parts.length !== 3 || parts.some((part) => !part)) return null;
    return new Date(parts[0], parts[1] - 1, parts[2], 23, 59, 59).toISOString();
  }

  function formatWhen(iso) {
    if (!iso) return '';
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return '';
    return date.toLocaleString();
  }

  function phoneCount(count) {
    const n = Number(count) || 0;
    return `${n} phone${n === 1 ? '' : 's'}`;
  }

  function rupeesFromPaise(paise) {
    const rupees = Number(paise) / 100;
    if (!Number.isFinite(rupees)) return '';
    return String(Math.round(rupees * 100) / 100);
  }

  function paiseFromRupees(text) {
    const rupees = Number(String(text).replace(/,/g, ''));
    if (!Number.isFinite(rupees)) return null;
    return Math.round(rupees * 100);
  }

  async function rpc(name, args) {
    const { data, error } = await supabase.rpc(name, args || {});
    if (error) throw new Error(errorText(error));
    return data;
  }

  async function invoke(name, body) {
    const { data, error } = await supabase.functions.invoke(name, { body });
    if (!error) return data || {};
    let message = error.message || 'Could not finish that request.';
    try {
      const parsed = await error.context.json();
      if (parsed && parsed.error) message = parsed.error;
    } catch (parseError) {
      // Gateway returned a non-JSON body.
    }
    throw new Error(message);
  }

  function stopPoll() {
    pollGen += 1;
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = 0;
    }
  }

  function setSignedIn(on) {
    const button = document.getElementById('sign-out');
    if (button) button.hidden = !on;
  }

  function renderLogin(errorMessage) {
    stopPoll();
    setSignedIn(false);
    handlers.submit = null;
    handlers.click = null;
    handlers.change = null;
    app.innerHTML = `
      ${errorMessage ? `<p class="msg error">${esc(errorMessage)}</p>` : ''}
      <form class="card" id="login-form">
        <p>Sign in with the WhatsApp number on your admin account. You send one message. We never text you a code.</p>
        <label for="phone">WhatsApp number</label>
        <input id="phone" type="tel" autocomplete="tel" inputmode="tel" required placeholder="9876543210" />
        <button class="btn btn-primary" type="submit">Continue with WhatsApp</button>
      </form>
    `;
    app.querySelector('#login-form').addEventListener('submit', async (event) => {
      event.preventDefault();
      const phone = val('phone');
      const button = event.target.querySelector('button');
      if (button) button.disabled = true;
      const popup = window.open('about:blank', '_blank');
      try {
        const data = await invoke('whatsapp-auth-start', { phone });
        const waUrl = typeof data.wa_url === 'string' ? data.wa_url : '';
        if (!waUrl.startsWith('https://wa.me/') || !data.challenge_id || !data.secret) {
          throw new Error('Could not start WhatsApp sign-in. Please try again.');
        }
        if (popup) popup.location = waUrl;
        renderWaiting({
          phone: data.phone || phone,
          message: data.message || '',
          waUrl,
          challengeId: data.challenge_id,
          secret: data.secret,
        });
      } catch (error) {
        if (popup) popup.close();
        renderLogin(errorText(error));
        const phoneInput = document.getElementById('phone');
        if (phoneInput) phoneInput.value = phone;
      }
    });
  }

  function renderWaiting(state) {
    app.innerHTML = `
      <div class="card">
        <p>Send this message from <strong>${esc(state.phone)}</strong>. Don't edit it. We sign you in when it arrives.</p>
        <p><strong>${esc(state.message)}</strong></p>
        <p class="actions">
          <button class="btn btn-primary" id="open-wa" type="button">Open WhatsApp</button>
          <button class="btn btn-ghost" id="cancel-wa" type="button">Use a different number</button>
        </p>
        <p class="hint" id="wait-status">Waiting for your message…</p>
      </div>
    `;
    document.getElementById('open-wa').addEventListener('click', () => {
      window.open(state.waUrl, '_blank', 'noopener');
    });
    document.getElementById('cancel-wa').addEventListener('click', () => {
      renderLogin('');
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
      const data = await invoke('whatsapp-auth-status', {
        challenge_id: challengeId,
        secret,
      });
      if (gen !== pollGen) return;
      if (data.status === 'pending') return;
      if (data.status === 'ready' && data.access_token && data.refresh_token) {
        stopPoll();
        const { error } = await supabase.auth.setSession({
          access_token: data.access_token,
          refresh_token: data.refresh_token,
        });
        if (error) throw new Error('Could not finish sign-in. Please try again.');
        await enterApp();
        return;
      }
      stopPoll();
      renderLogin(data.error || 'Could not finish sign-in. Please try again.');
    } catch (error) {
      if (gen !== pollGen) return;
      stopPoll();
      renderLogin(errorText(error));
    } finally {
      pollBusy = false;
    }
  }

  async function enterApp() {
    const { error } = await supabase.rpc('assert_admin');
    if (error) {
      await supabase.auth.signOut();
      const denied = String(error.message || '').includes('Admin only');
      renderLogin(denied ? 'Admin only.' : errorText(error));
      return;
    }
    setSignedIn(true);
    const render = pages[page] || renderHome;
    try {
      await render();
    } catch (error) {
      app.innerHTML = `<p class="msg error">${esc(errorText(error))}</p>`;
    }
  }

  function handleMarkdownClick(event) {
    const button = event.target.closest('[data-md]');
    if (!button) return;
    const id = button.getAttribute('data-md');
    const area = document.getElementById(id);
    const preview = document.getElementById(`${id}-preview`);
    if (!area || !preview) return;
    const writing = button.getAttribute('data-mode') !== 'preview';
    area.hidden = !writing;
    preview.hidden = writing;
    if (!writing) preview.innerHTML = renderMarkdown(area.value);
    button.parentElement.querySelectorAll('button').forEach((item) => {
      item.setAttribute('aria-pressed', item === button ? 'true' : 'false');
    });
  }

  function renderHome() {
    handlers.submit = null;
    handlers.click = null;
    handlers.change = null;
    app.innerHTML = `
      <p class="lede">Operator tools. Students never see these pages.</p>
      <div class="tiles">
        <a class="tile" href="/admin/questions/"><strong>Questions</strong><span>Search, edit, and add</span></a>
        <a class="tile" href="/admin/catalog/"><strong>Catalog</strong><span>Universities, colleges, subjects</span></a>
        <a class="tile" href="/admin/users/"><strong>Users</strong><span>Profile, plan, block, admin</span></a>
        <a class="tile" href="/admin/announcements/"><strong>Announcements</strong><span>In-app inbox on Home</span></a>
        <a class="tile" href="/admin/pricing/"><strong>Pricing</strong><span>Pro and Elite list prices</span></a>
        <a class="tile" href="/admin/coupons/"><strong>Coupons</strong><span>Percent-off codes</span></a>
        <a class="tile" href="/admin/backup/"><strong>Backup</strong><span>Download or restore the database</span></a>
      </div>
    `;
  }

  async function renderQuestions() {
    const [universities, subjects] = await Promise.all([
      rpc('admin_list_universities'),
      rpc('admin_list_subjects'),
    ]);
    const states = [...new Set(universities.map((item) => item.state).filter(Boolean))].sort();
    let offset = 0;
    const limit = 50;

    function universityPairs(state) {
      return universities
        .filter((item) => !state || item.state === state)
        .map((item) => [item.id, `${item.code} · ${item.name}`]);
    }

    function drawShell() {
      app.innerHTML = `
        <div id="msg"></div>
        <form id="filters" class="card filters">
          ${field('Stem, subject, or id', inputControl('query', '', 'placeholder="Search"'))}
          ${field('State', selectControl('state', states.map((item) => [item, item]), '', 'Any state'))}
          ${field('University', selectControl('university_id', universityPairs(''), '', 'Any university'))}
          ${field('College', selectControl('college_id', [], '', 'Any college'))}
          ${field('Year', inputControl('exam_year', '', 'inputmode="numeric" placeholder="2024"'))}
          ${field('Month', selectControl('exam_month', MONTHS, '', 'Any month'))}
          ${field('Exam type', selectControl('exam_type', EXAMS, '', 'Any type'))}
          ${field('Subject', selectControl('subject_id', subjects.map((item) => [item.id, item.name]), '', 'Any subject'))}
          ${field('Type', selectControl('kind', KINDS, '', 'Any type'))}
          ${field('Plan', selectControl('required_plan', PLANS, '', 'Any plan'))}
          ${field('Visibility', selectControl('visibility', [['visible', 'Visible'], ['hidden', 'Hidden']], '', 'Any'))}
          <div class="actions span-2">
            <button class="btn btn-primary" type="submit">Search</button>
            <a class="btn btn-ghost" href="/admin/question/">New question</a>
          </div>
        </form>
        <div id="results"></div>
      `;
      const college = document.getElementById('college_id');
      college.disabled = true;
    }

    async function loadColleges(universityId, selected) {
      const college = document.getElementById('college_id');
      if (!universityId) {
        college.innerHTML = '<option value="">Any college</option>';
        college.disabled = true;
        return;
      }
      const rows = await rpc('admin_list_colleges', { p_university_id: universityId });
      replaceSelect(
        'college_id',
        rows.map((item) => [item.id, `${item.short_form} · ${item.name}`]),
        selected || '',
        'Any college',
      );
    }

    function readFilters() {
      const filters = { limit, offset };
      const query = val('query');
      const state = val('state');
      const universityId = val('university_id');
      const collegeId = val('college_id');
      const year = val('exam_year');
      const month = val('exam_month');
      const examType = val('exam_type');
      const subjectId = val('subject_id');
      const kind = val('kind');
      const plan = val('required_plan');
      const visibility = val('visibility');
      if (query) filters.query = query;
      if (state) filters.state = state;
      if (universityId) filters.university_id = universityId;
      if (collegeId) filters.college_id = collegeId;
      if (year) filters.exam_year = Number(year);
      if (month) filters.exam_month = Number(month);
      if (examType) filters.exam_type = examType;
      if (subjectId) filters.subject_id = subjectId;
      if (kind) filters.kind = kind;
      if (plan) filters.required_plan = plan;
      if (visibility === 'visible') filters.is_active = true;
      if (visibility === 'hidden') filters.is_active = false;
      return filters;
    }

    async function search() {
      const results = document.getElementById('results');
      results.textContent = 'Loading…';
      try {
        const data = await rpc('admin_search_questions_filtered', { p_filters: readFilters() });
        const rows = data.questions || [];
        const total = data.total || 0;
        const from = total === 0 ? 0 : offset + 1;
        const to = Math.min(offset + rows.length, total);
        const body = rows.map((row) => `
          <tr>
            <td><a href="/admin/question/?id=${esc(row.id)}">${esc(row.public_code || '—')}</a></td>
            <td>${esc(row.subject_name || '')}</td>
            <td>${esc(labelOf(KINDS, row.kind))}</td>
            <td>${esc(labelOf(PLANS, row.required_plan))}</td>
            <td>${row.is_active ? '' : '<span class="badge-inline">Hidden</span>'}</td>
            <td>${esc(row.appearance_count)}</td>
            <td class="stem">${esc(clip(row.question_text, 140))}</td>
          </tr>
        `).join('');
        results.innerHTML = `
          <p class="hint">${total === 0 ? 'No questions match.' : `Showing ${from}–${to} of ${total}.`}</p>
          <div class="table-wrap">
            <table>
              <thead><tr><th>Code</th><th>Subject</th><th>Type</th><th>Plan</th><th></th><th>Papers</th><th>Question</th></tr></thead>
              <tbody>${body || '<tr><td colspan="7">No questions match.</td></tr>'}</tbody>
            </table>
          </div>
          <div class="pager">
            <button class="btn btn-ghost btn-small" type="button" id="page-prev" ${offset <= 0 ? 'disabled' : ''}>Previous</button>
            <button class="btn btn-ghost btn-small" type="button" id="page-next" ${offset + limit >= total ? 'disabled' : ''}>Next</button>
          </div>
        `;
        document.getElementById('page-prev').addEventListener('click', () => {
          offset = Math.max(0, offset - limit);
          search();
        });
        document.getElementById('page-next').addEventListener('click', () => {
          offset += limit;
          search();
        });
      } catch (error) {
        results.innerHTML = `<p class="msg error">${esc(errorText(error))}</p>`;
      }
    }

    drawShell();
    handlers.submit = async (event) => {
      if (event.target.id !== 'filters') return;
      event.preventDefault();
      offset = 0;
      await search();
    };
    handlers.change = async (event) => {
      if (event.target.id === 'state') {
        const select = document.getElementById('university_id');
        const current = select.value;
        const pairs = universityPairs(val('state'));
        replaceSelect(
          'university_id',
          pairs,
          pairs.some((item) => item[0] === current) ? current : '',
          'Any university',
        );
        if (!pairs.some((item) => item[0] === current)) {
          await loadColleges('', '');
        }
      }
      if (event.target.id === 'university_id') {
        await loadColleges(val('university_id'), '');
      }
    };
    handlers.click = handleMarkdownClick;
    await search();
  }

  async function renderQuestion() {
    const questionId = queryParam('id');
    const [subjects, universities] = await Promise.all([
      rpc('admin_list_subjects'),
      rpc('admin_list_universities'),
    ]);
    let question = null;
    if (questionId) {
      question = await rpc('admin_get_question', { p_question_id: questionId });
    }
    let editingPaperId = '';

    function uniPairs() {
      return universities.map((item) => [item.id, `${item.code} · ${item.name}`]);
    }

    async function fillCollegeSelect(selectId, universityId, selected) {
      let pairs = [];
      if (universityId) {
        const rows = await rpc('admin_list_colleges', { p_university_id: universityId });
        pairs = rows.map((item) => [item.id, `${item.short_form} · ${item.name}`]);
      }
      replaceSelect(selectId, pairs, selected || '', 'No college');
      const select = document.getElementById(selectId);
      if (select) select.disabled = !universityId;
    }

    function paperLabel(paper) {
      const bits = [
        paper.university_name,
        paper.college_name,
        `${monthName(paper.exam_month)} ${paper.exam_year || ''}`.trim(),
        labelOf(EXAMS, paper.exam_type),
        paper.paper_name,
      ].filter(Boolean);
      return bits.join(' · ');
    }

    async function draw() {
      const q = question || {};
      const textbook = q.textbook || {};
      const resource = q.resource || {};
      const creating = !questionId;
      const sitting = creating
        ? `<h2 class="section-title">First paper</h2>
          <div class="form-grid">
            ${field('University', selectControl('sit_university_id', uniPairs(), '', 'Choose'))}
            ${field('College', selectControl('sit_college_id', [], '', 'No college'))}
            ${field('Year', inputControl('sit_exam_year', '', 'inputmode="numeric" required'))}
            ${field('Month', selectControl('sit_exam_month', MONTHS, '5'))}
            ${field('Exam type', selectControl('sit_exam_type', EXAMS, 'prof'))}
            ${field('Paper', inputControl('sit_paper_name', '', 'placeholder="Paper I"'))}
          </div>`
        : '';
      const papers = (q.appearances || []).map((paper) => `
        <li>
          ${esc(paperLabel(paper))}
          <button class="btn btn-ghost btn-small" type="button" data-action="edit-paper" data-id="${esc(paper.exam_paper_id)}">Edit</button>
          <button class="btn btn-ghost btn-small" type="button" data-action="delete-paper" data-id="${esc(paper.exam_paper_id)}" ${(q.appearances || []).length < 2 ? 'disabled' : ''}>Remove</button>
        </li>
      `).join('');
      const paperEditor = creating
        ? ''
        : `<h2 class="section-title">Papers</h2>
          <ul>${papers || '<li>No papers yet.</li>'}</ul>
          <form id="paper-form" class="card" data-form="paper">
            <h3>${editingPaperId ? 'Edit paper' : 'Add paper'}</h3>
            ${field('University', selectControl('paper_university_id', uniPairs(), '', 'Choose'))}
            ${field('College', selectControl('paper_college_id', [], '', 'No college'))}
            ${field('Year', inputControl('paper_exam_year', '', 'inputmode="numeric" required'))}
            ${field('Month', selectControl('paper_exam_month', MONTHS, '5'))}
            ${field('Exam type', selectControl('paper_exam_type', EXAMS, 'prof'))}
            ${field('Paper', inputControl('paper_paper_name', '', 'placeholder="Paper I"'))}
            <div class="actions">
              <button class="btn btn-primary" type="submit">${editingPaperId ? 'Save paper' : 'Add paper'}</button>
              ${editingPaperId ? '<button class="btn btn-ghost" type="button" data-action="cancel-paper">Cancel</button>' : ''}
            </div>
          </form>`;

      app.innerHTML = `
        <div id="msg"></div>
        ${q.public_code ? `<p class="hint">Code ${esc(q.public_code)}.</p>` : ''}
        <form id="question-form" class="card" data-form="question">
          <div class="form-grid">
            ${field('Subject', selectControl('subject_id', subjects.map((item) => [item.id, item.name]), q.subject_id || '', 'Choose'))}
            ${field('Type', selectControl('kind', KINDS, q.kind || 'pyq_theory'))}
            ${markdownControl('question_text', 'Question', q.question_text || '')}
            ${field('Marks', inputControl('marks', q.marks ?? '', 'inputmode="decimal"'))}
            ${field('Difficulty', selectControl('difficulty', DIFFICULTIES, q.difficulty || 'should'))}
            ${field('Plan required', selectControl('required_plan', PLANS, q.required_plan || 'free'))}
            <div class="span-2">${checkControl('is_active', 'Visible to students', q.is_active !== false)}</div>
            ${field('Chapter', inputControl('chapter_name', q.chapter_name || ''))}
            ${field('Topic', inputControl('topic_name', q.topic_name || '', 'placeholder="Needs a chapter"'))}
            <div id="mcq-fields" class="span-2 form-grid">
              ${field('Option A', inputControl('option_a', q.option_a || ''))}
              ${field('Option B', inputControl('option_b', q.option_b || ''))}
              ${field('Option C', inputControl('option_c', q.option_c || ''))}
              ${field('Option D', inputControl('option_d', q.option_d || ''))}
              ${field('Correct option', selectControl('correct_option', [['A', 'A'], ['B', 'B'], ['C', 'C'], ['D', 'D']], q.correct_option || 'A'))}
            </div>
            ${markdownControl('explanation_text', 'Short explanation', q.explanation_text || '')}
            ${markdownControl('explanation_deep', 'Longer explanation', q.explanation_deep || '')}
            ${markdownControl('sample_answer', 'Model answer', q.sample_answer || '')}
            <h2 class="section-title span-2">Textbook</h2>
            ${field('Title', inputControl('tb_title', textbook.title || ''))}
            ${field('Authors', inputControl('tb_authors', textbook.authors || ''))}
            ${field('Edition', inputControl('tb_edition', textbook.edition || ''))}
            ${field('Page', inputControl('tb_page', textbook.page ?? '', 'inputmode="numeric"'))}
            ${field('Section', inputControl('tb_section', textbook.section_heading || ''))}
            <h2 class="section-title span-2">Link</h2>
            ${field('Title', inputControl('res_title', resource.title || ''))}
            ${field('URL', inputControl('res_url', resource.url || '', 'placeholder="https://"'))}
            ${field('Source label', inputControl('res_source', resource.source_label || ''))}
            <div class="span-2">${checkControl('res_free', 'Free for every plan', resource.is_free !== false)}</div>
          </div>
          ${sitting}
          <div class="actions">
            <button class="btn btn-primary" type="submit">${creating ? 'Create question' : 'Save question'}</button>
            <a class="btn btn-ghost" href="/admin/questions/">Back to questions</a>
          </div>
        </form>
        ${paperEditor}
      `;
      syncKind();
      const sitCollege = document.getElementById('sit_college_id');
      if (sitCollege) sitCollege.disabled = true;
      const paperCollege = document.getElementById('paper_college_id');
      if (paperCollege) paperCollege.disabled = true;
      if (editingPaperId) {
        const paper = (q.appearances || []).find((item) => item.exam_paper_id === editingPaperId);
        if (paper) {
          document.getElementById('paper_university_id').value = paper.university_id || '';
          document.getElementById('paper_exam_year').value = paper.exam_year || '';
          document.getElementById('paper_exam_month').value = String(paper.exam_month || 5);
          document.getElementById('paper_exam_type').value = paper.exam_type || 'prof';
          document.getElementById('paper_paper_name').value = paper.paper_name || '';
          await fillCollegeSelect('paper_college_id', paper.university_id, paper.college_id || '');
        }
      }
    }

    function syncKind() {
      const block = document.getElementById('mcq-fields');
      if (!block) return;
      block.hidden = val('kind') !== 'mcq';
    }

    function textbookPayload() {
      const title = val('tb_title');
      const authors = val('tb_authors');
      const edition = val('tb_edition');
      const pageNumber = val('tb_page');
      const section = val('tb_section');
      if (!title && !authors && !edition && !pageNumber && !section) return null;
      return {
        title,
        authors,
        edition,
        page: pageNumber,
        section_heading: section,
      };
    }

    function resourcePayload() {
      const title = val('res_title');
      const url = val('res_url');
      const source = val('res_source');
      if (!title && !url && !source) return null;
      return {
        title,
        url,
        source_label: source,
        is_free: checked('res_free'),
      };
    }

    handlers.change = async (event) => {
      if (event.target.id === 'kind') syncKind();
      if (event.target.id === 'sit_university_id') {
        await fillCollegeSelect('sit_college_id', val('sit_university_id'), '');
      }
      if (event.target.id === 'paper_university_id') {
        await fillCollegeSelect('paper_college_id', val('paper_university_id'), '');
      }
    };

    handlers.click = async (event) => {
      handleMarkdownClick(event);
      const button = event.target.closest('[data-action]');
      if (!button) return;
      const action = button.getAttribute('data-action');
      const id = button.getAttribute('data-id') || '';
      if (action === 'edit-paper') {
        editingPaperId = id;
        await draw();
      }
      if (action === 'cancel-paper') {
        editingPaperId = '';
        await draw();
      }
      if (action === 'delete-paper') {
        if (!window.confirm('Remove this paper from the question?')) return;
        try {
          await rpc('admin_delete_appearance', {
            p_question_id: questionId,
            p_exam_paper_id: id,
          });
          question = await rpc('admin_get_question', { p_question_id: questionId });
          editingPaperId = '';
          await draw();
          message('ok', 'Paper removed.');
        } catch (error) {
          message('error', errorText(error));
        }
      }
    };

    handlers.submit = async (event) => {
      event.preventDefault();
      const formName = event.target.getAttribute('data-form');
      try {
        if (formName === 'question') {
          if (val('topic_name') && !val('chapter_name')) {
            throw new Error('Add a chapter before a topic.');
          }
          const body = {
            subject_id: val('subject_id'),
            kind: val('kind'),
            question_text: document.getElementById('question_text').value,
            marks: val('marks') === '' ? null : val('marks'),
            difficulty: val('difficulty'),
            required_plan: val('required_plan'),
            is_active: checked('is_active'),
            chapter_name: val('chapter_name'),
            topic_name: val('topic_name'),
            explanation_text: document.getElementById('explanation_text').value,
            explanation_deep: document.getElementById('explanation_deep').value,
            sample_answer: document.getElementById('sample_answer').value,
            textbook: textbookPayload(),
            resource: resourcePayload(),
          };
          if (val('kind') === 'mcq') {
            body.option_a = val('option_a');
            body.option_b = val('option_b');
            body.option_c = val('option_c');
            body.option_d = val('option_d');
            body.correct_option = val('correct_option');
          }
          if (!questionId) {
            body.sitting = {
              university_id: val('sit_university_id'),
              college_id: val('sit_college_id') || null,
              exam_year: Number(val('sit_exam_year')),
              exam_month: Number(val('sit_exam_month')),
              exam_type: val('sit_exam_type'),
              paper_name: val('sit_paper_name') || null,
            };
          } else {
            body.id = questionId;
          }
          const saved = await rpc('admin_save_question', { p_body: body });
          if (!questionId && saved && saved.id) {
            location.href = `/admin/question/?id=${encodeURIComponent(saved.id)}`;
            return;
          }
          question = await rpc('admin_get_question', { p_question_id: questionId });
          await draw();
          message('ok', 'Question saved.');
        }
        if (formName === 'paper') {
          const payload = {
            question_id: questionId,
            university_id: val('paper_university_id'),
            college_id: val('paper_college_id') || null,
            exam_year: Number(val('paper_exam_year')),
            exam_month: Number(val('paper_exam_month')),
            exam_type: val('paper_exam_type'),
            paper_name: val('paper_paper_name') || null,
          };
          if (editingPaperId) payload.exam_paper_id = editingPaperId;
          await rpc('admin_save_appearance', { p_body: payload });
          question = await rpc('admin_get_question', { p_question_id: questionId });
          editingPaperId = '';
          await draw();
          message('ok', 'Paper saved.');
        }
      } catch (error) {
        message('error', errorText(error));
      }
    };

    await draw();
  }

  async function renderCatalog() {
    let universities = await rpc('admin_list_universities');
    let subjects = await rpc('admin_list_subjects');
    const phases = await rpc('admin_list_phases');
    let collegeUniversityId = universities[0] ? universities[0].id : '';
    let colleges = collegeUniversityId
      ? await rpc('admin_list_colleges', { p_university_id: collegeUniversityId })
      : [];
    const editing = { university: null, college: null, subject: null };

    function draw() {
      const uni = editing.university || {};
      const college = editing.college || {};
      const subject = editing.subject || {};
      app.innerHTML = `
        <div id="msg"></div>
        <h2>Universities</h2>
        <form class="card form-grid" data-form="university">
          ${field('Code', inputControl('uni_code', uni.code || '', 'required'))}
          ${field('Name', inputControl('uni_name', uni.name || '', 'required'))}
          ${field('State', inputControl('uni_state', uni.state || '', 'required'))}
          ${field('Slug', inputControl('uni_slug', uni.slug || '', 'placeholder="Leave blank to build it from the name"'))}
          <div class="actions span-2">
            <button class="btn btn-primary" type="submit">${uni.id ? 'Save university' : 'Add university'}</button>
            ${uni.id ? '<button class="btn btn-ghost" type="button" data-action="clear-university">Cancel</button>' : ''}
          </div>
        </form>
        <div class="table-wrap"><table>
          <thead><tr><th>Code</th><th>Name</th><th>State</th><th></th></tr></thead>
          <tbody>${universities.map((item) => `
            <tr>
              <td>${esc(item.code)}</td>
              <td>${esc(item.name)}</td>
              <td>${esc(item.state)}</td>
              <td>
                <button class="btn btn-ghost btn-small" type="button" data-action="edit-university" data-id="${esc(item.id)}">Edit</button>
                <button class="btn btn-ghost btn-small" type="button" data-action="delete-university" data-id="${esc(item.id)}">Delete</button>
              </td>
            </tr>`).join('')}</tbody>
        </table></div>

        <h2 class="section-title">Colleges</h2>
        <div class="card">
          ${field('University', selectControl('college_university', universities.map((item) => [item.id, `${item.code} · ${item.name}`]), collegeUniversityId, 'Choose'))}
          <form class="form-grid" data-form="college">
            ${field('Name', inputControl('col_name', college.name || '', 'required'))}
            ${field('Short form', inputControl('col_short', college.short_form || '', 'required placeholder="MAMC"'))}
            <p class="hint span-2">Short form is the college alias. Unique in this university.</p>
            <div class="actions span-2">
              <button class="btn btn-primary" type="submit" ${collegeUniversityId ? '' : 'disabled'}>${college.id ? 'Save college' : 'Add college'}</button>
              ${college.id ? '<button class="btn btn-ghost" type="button" data-action="clear-college">Cancel</button>' : ''}
            </div>
          </form>
        </div>
        <div class="table-wrap"><table>
          <thead><tr><th>Short form</th><th>Name</th><th></th></tr></thead>
          <tbody>${colleges.map((item) => `
            <tr>
              <td>${esc(item.short_form)}</td>
              <td>${esc(item.name)}</td>
              <td>
                <button class="btn btn-ghost btn-small" type="button" data-action="edit-college" data-id="${esc(item.id)}">Edit</button>
                <button class="btn btn-ghost btn-small" type="button" data-action="delete-college" data-id="${esc(item.id)}">Delete</button>
              </td>
            </tr>`).join('') || '<tr><td colspan="3">No colleges for this university.</td></tr>'}</tbody>
        </table></div>

        <h2 class="section-title">Subjects</h2>
        <form class="card form-grid" data-form="subject">
          ${field('Name', inputControl('sub_name', subject.name || '', 'required'))}
          ${field('MBBS year', selectControl('sub_phase', phases.map((item) => [item.id, item.name]), subject.mbbs_phase_id || '', 'Choose'))}
          ${field('Display order', inputControl('sub_order', subject.display_order ?? '', 'inputmode="numeric"'))}
          ${field('Plan required', selectControl('sub_plan', PLANS, subject.required_plan || 'free'))}
          <div class="actions span-2">
            <button class="btn btn-primary" type="submit">${subject.id ? 'Save subject' : 'Add subject'}</button>
            ${subject.id ? '<button class="btn btn-ghost" type="button" data-action="clear-subject">Cancel</button>' : ''}
          </div>
        </form>
        <div class="table-wrap"><table>
          <thead><tr><th>Order</th><th>Name</th><th>Year</th><th>Plan</th><th></th></tr></thead>
          <tbody>${subjects.map((item) => `
            <tr>
              <td>${esc(item.display_order)}</td>
              <td>${esc(item.name)}</td>
              <td>${esc(item.phase_name || '')}</td>
              <td>${esc(labelOf(PLANS, item.required_plan))}</td>
              <td>
                <button class="btn btn-ghost btn-small" type="button" data-action="edit-subject" data-id="${esc(item.id)}">Edit</button>
                <button class="btn btn-ghost btn-small" type="button" data-action="delete-subject" data-id="${esc(item.id)}">Delete</button>
              </td>
            </tr>`).join('')}</tbody>
        </table></div>
      `;
    }

    handlers.change = async (event) => {
      if (event.target.id !== 'college_university') return;
      collegeUniversityId = val('college_university');
      editing.college = null;
      colleges = collegeUniversityId
        ? await rpc('admin_list_colleges', { p_university_id: collegeUniversityId })
        : [];
      draw();
    };

    handlers.click = async (event) => {
      const button = event.target.closest('[data-action]');
      if (!button) return;
      const action = button.getAttribute('data-action');
      const id = button.getAttribute('data-id') || '';
      if (action === 'edit-university') editing.university = universities.find((item) => item.id === id) || null;
      if (action === 'clear-university') editing.university = null;
      if (action === 'edit-college') editing.college = colleges.find((item) => item.id === id) || null;
      if (action === 'clear-college') editing.college = null;
      if (action === 'edit-subject') editing.subject = subjects.find((item) => item.id === id) || null;
      if (action === 'clear-subject') editing.subject = null;
      if (action === 'delete-university') {
        const row = universities.find((item) => item.id === id);
        if (!row || !window.confirm(`Delete ${row.name}?`)) return;
        try {
          await rpc('admin_delete_university', { p_university_id: id });
          universities = await rpc('admin_list_universities');
          editing.university = null;
          message('ok', 'University deleted.');
        } catch (error) {
          draw();
          message('error', errorText(error));
          return;
        }
      }
      if (action === 'delete-college') {
        const row = colleges.find((item) => item.id === id);
        if (!row || !window.confirm(`Delete ${row.name}?`)) return;
        try {
          await rpc('admin_delete_college', { p_college_id: id });
          colleges = await rpc('admin_list_colleges', { p_university_id: collegeUniversityId });
          editing.college = null;
          message('ok', 'College deleted.');
        } catch (error) {
          draw();
          message('error', errorText(error));
          return;
        }
      }
      if (action === 'delete-subject') {
        const row = subjects.find((item) => item.id === id);
        if (!row || !window.confirm(`Delete ${row.name}?`)) return;
        try {
          await rpc('admin_delete_subject', { p_subject_id: id });
          subjects = await rpc('admin_list_subjects');
          editing.subject = null;
          message('ok', 'Subject deleted.');
        } catch (error) {
          draw();
          message('error', errorText(error));
          return;
        }
      }
      const note = document.getElementById('msg') ? document.getElementById('msg').innerHTML : '';
      draw();
      const slot = document.getElementById('msg');
      if (slot && note) slot.innerHTML = note;
    };

    handlers.submit = async (event) => {
      event.preventDefault();
      const formName = event.target.getAttribute('data-form');
      try {
        if (formName === 'university') {
          const body = {
            code: val('uni_code'),
            name: val('uni_name'),
            state: val('uni_state'),
            slug: val('uni_slug'),
          };
          if (editing.university) body.id = editing.university.id;
          await rpc('admin_upsert_university', { p_body: body });
          universities = await rpc('admin_list_universities');
          editing.university = null;
          draw();
          message('ok', 'University saved.');
        }
        if (formName === 'college') {
          const body = {
            university_id: collegeUniversityId,
            name: val('col_name'),
            short_form: val('col_short'),
          };
          if (editing.college) body.id = editing.college.id;
          await rpc('admin_upsert_college', { p_body: body });
          colleges = await rpc('admin_list_colleges', { p_university_id: collegeUniversityId });
          editing.college = null;
          draw();
          message('ok', 'College saved.');
        }
        if (formName === 'subject') {
          const body = {
            name: val('sub_name'),
            mbbs_phase_id: val('sub_phase'),
            display_order: val('sub_order'),
            required_plan: val('sub_plan'),
          };
          if (editing.subject) body.id = editing.subject.id;
          await rpc('admin_upsert_subject', { p_body: body });
          subjects = await rpc('admin_list_subjects');
          editing.subject = null;
          draw();
          message('ok', 'Subject saved.');
        }
      } catch (error) {
        message('error', errorText(error));
      }
    };

    draw();
  }

  async function renderUsers() {
    app.innerHTML = `
      <div id="msg"></div>
      <form id="user-search" class="card">
        <p class="hint">Name or phone. An empty search shows the newest 40 accounts.</p>
        ${field('Name or phone', inputControl('user_query', ''))}
        <button class="btn btn-primary" type="submit">Search</button>
      </form>
      <div id="user-results"></div>
    `;

    async function search() {
      const slot = document.getElementById('user-results');
      slot.textContent = 'Loading…';
      try {
        const rows = await rpc('admin_search_users', { p_query: val('user_query') });
        const list = rows || [];
        slot.innerHTML = `
          <div class="table-wrap"><table>
            <thead><tr><th>Name</th><th>Contact</th><th>Plan</th><th></th></tr></thead>
            <tbody>${list.map((user) => `
              <tr>
                <td><a href="/admin/user/?id=${esc(user.id)}">${esc(user.full_name || 'No name')}</a></td>
                <td>${esc(user.phone || user.email || '')}</td>
                <td>${esc(labelOf(PLANS, user.plan))}${user.plan_expires_at ? ` until ${esc(formatWhen(user.plan_expires_at))}` : ''}</td>
                <td>${user.blocked_at ? '<span class="badge-inline">Blocked</span>' : ''}${user.plan_suspended_at ? ' <span class="badge-inline">Suspended</span>' : ''}</td>
              </tr>`).join('') || '<tr><td colspan="4">No accounts match.</td></tr>'}</tbody>
          </table></div>
        `;
      } catch (error) {
        slot.innerHTML = `<p class="msg error">${esc(errorText(error))}</p>`;
      }
    }

    handlers.submit = async (event) => {
      if (event.target.id !== 'user-search') return;
      event.preventDefault();
      await search();
    };
    handlers.click = null;
    handlers.change = null;
    await search();
  }

  async function renderUser() {
    const userId = queryParam('id');
    if (!userId) {
      app.innerHTML = '<p class="msg error">Missing user.</p>';
      return;
    }
    let user = await rpc('admin_get_user', { p_user_id: userId });
    const [universities, phases, session] = await Promise.all([
      rpc('admin_list_universities'),
      rpc('admin_list_phases'),
      supabase.auth.getUser(),
    ]);
    const selfId = session.data.user ? session.data.user.id : '';

    async function colleges(universityId) {
      if (!universityId) return [];
      return rpc('admin_list_colleges', { p_university_id: universityId });
    }

    function deviceTableFor(account) {
      const list = Array.isArray(account.devices) ? account.devices : [];
      if (!list.length) return '<p>No phone has signed in yet.</p>';
      return `<div class="table-wrap"><table>
        <thead><tr><th>Phone</th><th>Last seen</th><th>Slot</th><th></th></tr></thead>
        <tbody>${list.map((device) => `
          <tr>
            <td><code>${esc(device.device_id)}</code></td>
            <td>${esc(formatWhen(device.last_seen_at))}</td>
            <td>${device.registered_at ? '<span class="badge-inline">Registered</span>' : 'Seen'}</td>
            <td>${device.registered_at ? `<button class="btn btn-ghost btn-small" type="button" data-release="${esc(device.device_id)}">Remove</button>` : ''}</td>
          </tr>`).join('')}</tbody>
      </table></div>`;
    }

    async function draw() {
      const collegeRows = await colleges(user.university_id);
      const whatsapp = !user.email;
      const planLimit = Number(user.plan_device_limit) || 1;
      const allowed = Number(user.device_limit) || planLimit;
      const registered = Number(user.registered_device_count) || 0;
      const deviceTable = deviceTableFor(user);
      const overLimit = registered > allowed
        ? '<p class="hint">More phones are registered than this account allows. Saving the limit signs out the extra phones and keeps the most recently used.</p>'
        : '';
      app.innerHTML = `
        <div id="msg"></div>
        <p><a href="/admin/users/">Back to users</a></p>
        <form class="card" data-form="profile">
          <h2>Profile</h2>
          ${field('Full name', inputControl('full_name', user.full_name || ''))}
          ${field('Phone', inputControl('phone', user.phone || ''))}
          ${field('University', selectControl('university_id', universities.map((item) => [item.id, `${item.code} · ${item.name}`]), user.university_id || '', 'None'))}
          ${field('College', selectControl('college_id', collegeRows.map((item) => [item.id, `${item.short_form} · ${item.name}`]), user.college_id || '', 'None'))}
          ${field('Batch year', inputControl('batch_year', user.batch_year ?? '', 'inputmode="numeric"'))}
          ${field('MBBS year', selectControl('mbbs_phase_id', phases.map((item) => [item.id, item.name]), user.mbbs_phase_id || '', 'None'))}
          <button class="btn btn-primary" type="submit">Save profile</button>
        </form>
        <form class="card" data-form="plan">
          <h2>Plan</h2>
          ${field('Plan', selectControl('plan', PLANS, user.plan || 'free'))}
          ${field('Expiry', `<input id="plan_expires" type="date" value="${esc(toDateInput(user.plan_expires_at))}" />`)}
          <p class="hint">Leave the date empty to clear the expiry. The day ends at 23:59. Saving a plan with fewer phones signs out the extra ones, unless the device limit below is higher.</p>
          <button class="btn btn-primary" type="submit">Save plan</button>
        </form>
        ${user.plan_suspended_at ? `<form class="card" data-form="suspension"><h2>Device suspension</h2><p>Suspended ${esc(formatWhen(user.plan_suspended_at))}.</p><button class="btn btn-primary" type="submit">Clear device suspension</button></form>` : ''}
        <form class="card" data-form="devices">
          <h2>Devices</h2>
          <p>This plan allows ${esc(phoneCount(planLimit))}. ${esc(phoneCount(registered))} registered.</p>
          ${deviceTable}
          ${overLimit}
          ${field('Phones this account may register', inputControl('device_limit', allowed, `inputmode="numeric" min="${planLimit}" max="10"`))}
          <p class="hint">Type a higher number to allow more phones on this account, up to 10. It cannot go below the plan. Leave the box empty to follow the plan again. This number stays if the plan changes.</p>
          <div class="actions">
            <button class="btn btn-primary" type="submit" name="intent" value="limit">Save device limit</button>
            <button class="btn btn-ghost" type="submit" name="intent" value="reset">Reset devices</button>
          </div>
          <p class="hint">Reset signs every phone out and frees every slot. The next sign-in can register a phone.</p>
        </form>
        <form class="card" data-form="auth">
          <h2>Sign-in</h2>
          ${whatsapp
            ? '<p>This account signs in with WhatsApp. There is no password.</p>'
            : `${field('Email', inputControl('email', user.email || ''))}
               ${field('New password', '<input id="password" type="password" autocomplete="new-password" />')}
               ${field('Confirm password', '<input id="password2" type="password" autocomplete="new-password" />')}
               <div class="actions">
                 <button class="btn btn-primary" type="submit" name="intent" value="email">Save email</button>
                 <button class="btn btn-ghost" type="submit" name="intent" value="password">Reset password</button>
               </div>`}
        </form>
        <form class="card" data-form="block">
          <h2>${user.blocked_at ? 'Unblock' : 'Block'}</h2>
          ${user.blocked_at ? `<p>Blocked ${esc(formatWhen(user.blocked_at))}. ${esc(user.blocked_reason || '')}</p>` : ''}
          ${field('Reason', areaControl('block_reason', user.blocked_reason || '', 3))}
          <button class="btn btn-primary" type="submit">${user.blocked_at ? 'Unblock user' : 'Block user'}</button>
        </form>
        <form class="card" data-form="admin">
          <h2>Admin</h2>
          ${selfId === user.id ? '<p>You cannot remove your own admin access.</p>' : ''}
          ${checkControl('is_admin', 'This account is an admin', user.is_admin === true)}
          <button class="btn btn-primary" type="submit" ${selfId === user.id && user.is_admin ? 'disabled' : ''}>Save admin access</button>
        </form>
      `;
      if (selfId === user.id && user.is_admin) {
        const box = document.getElementById('is_admin');
        if (box) box.disabled = true;
      }
    }

    handlers.change = async (event) => {
      if (event.target.id !== 'university_id') return;
      const rows = await colleges(val('university_id'));
      replaceSelect(
        'college_id',
        rows.map((item) => [item.id, `${item.short_form} · ${item.name}`]),
        '',
        'None',
      );
    };

    handlers.click = async (event) => {
      const button = event.target.closest('[data-release]');
      if (!button) return;
      const deviceId = button.getAttribute('data-release');
      if (!deviceId) return;
      if (!window.confirm('Sign this phone out and free its slot?')) return;
      user = await rpc('admin_release_device', {
        p_user_id: userId,
        p_device_id: deviceId,
      });
      await draw();
      message('ok', 'Phone removed. That install can no longer use the plan.');
    };
    handlers.submit = async (event) => {
      event.preventDefault();
      const formName = event.target.getAttribute('data-form');
      const intent = event.submitter ? event.submitter.value : '';
      try {
        if (formName === 'profile') {
          user = await rpc('admin_update_profile', {
            p_user_id: userId,
            p_full_name: val('full_name') || null,
            p_phone: val('phone') || null,
            p_university_id: val('university_id') || null,
            p_college_id: val('college_id') || null,
            p_batch_year: val('batch_year') ? Number(val('batch_year')) : null,
            p_mbbs_phase_id: val('mbbs_phase_id') || null,
          });
          await draw();
          message('ok', 'Profile saved.');
        }
        if (formName === 'plan') {
          user = await rpc('admin_set_plan', {
            p_user_id: userId,
            p_plan: val('plan'),
            p_expires_at: endOfLocalDay(val('plan_expires')),
          });
          await draw();
          message('ok', 'Plan saved.');
        }
        if (formName === 'suspension') {
          user = await rpc('admin_clear_device_suspension', { p_user_id: userId });
          await draw();
          message('ok', 'Device suspension cleared.');
        }
        if (formName === 'devices' && intent === 'limit') {
          const raw = val('device_limit');
          if (raw && !/^\d+$/.test(raw)) throw new Error('Enter a whole number of phones.');
          user = await rpc('admin_set_device_limit', {
            p_user_id: userId,
            p_max: raw ? Number(raw) : null,
          });
          await draw();
          message('ok', 'Device limit saved.');
        }
        if (formName === 'devices' && intent === 'reset') {
          if (!window.confirm('Sign this user out of every phone and free every device slot?')) return;
          user = await rpc('admin_reset_devices', { p_user_id: userId });
          await draw();
          message('ok', 'Devices reset. The next sign-in can register a phone.');
        }
        if (formName === 'auth' && intent === 'email') {
          await invoke('admin-user-auth', {
            action: 'set_email',
            user_id: userId,
            email: val('email'),
          });
          user = await rpc('admin_get_user', { p_user_id: userId });
          await draw();
          message('ok', 'Email saved.');
        }
        if (formName === 'auth' && intent === 'password') {
          const password = document.getElementById('password').value;
          const again = document.getElementById('password2').value;
          if (password.length < 6) throw new Error('Password must be at least 6 characters.');
          if (password !== again) throw new Error('Passwords do not match.');
          await invoke('admin-user-auth', {
            action: 'set_password',
            user_id: userId,
            password,
          });
          await draw();
          message('ok', 'Password updated.');
        }
        if (formName === 'block') {
          const blocked = !user.blocked_at;
          const verb = blocked ? 'Block' : 'Unblock';
          if (!window.confirm(`${verb} this user?`)) return;
          await invoke('admin-user-auth', {
            action: blocked ? 'block' : 'unblock',
            user_id: userId,
            reason: val('block_reason'),
          });
          user = await rpc('admin_get_user', { p_user_id: userId });
          await draw();
          message('ok', blocked ? 'User blocked.' : 'User unblocked.');
        }
        if (formName === 'admin') {
          user = await rpc('admin_set_admin', {
            p_user_id: userId,
            p_is_admin: checked('is_admin'),
          });
          await draw();
          message('ok', 'Admin access saved.');
        }
      } catch (error) {
        message('error', errorText(error));
      }
    };

    await draw();
  }

  async function renderAnnouncements() {
    let rows = await rpc('admin_list_announcements');
    const requested = queryParam('id');
    let current = rows.find((item) => item.id === requested) || null;

    function draw() {
      const item = current || {};
      app.innerHTML = `
        <div id="msg"></div>
        <form class="card" data-form="announcement">
          <h2>${item.id ? 'Edit announcement' : 'New announcement'}</h2>
          ${field('Title', inputControl('ann_title', item.title || '', 'required'))}
          ${field('Body', areaControl('ann_body', item.body || '', 6))}
          ${field('Category', selectControl('ann_category', CATEGORIES, item.category || 'general'))}
          ${field('App path', inputControl('ann_link', item.deep_link || '', 'placeholder="/upgrade"'))}
          ${checkControl('ann_active', 'Published', item.is_active === true)}
          ${field('Expiry', `<input id="ann_expires" type="date" value="${esc(toDateInput(item.expires_at))}" />`)}
          <p class="hint">Leave the date empty for no expiry. Students see this on Home. It is not a lock-screen push.</p>
          <div class="actions">
            <button class="btn btn-primary" type="submit">Save</button>
            <button class="btn btn-ghost" type="button" data-action="new-announcement">New</button>
          </div>
        </form>
        <div class="table-wrap"><table>
          <thead><tr><th>Title</th><th>Category</th><th>Status</th><th>Expires</th></tr></thead>
          <tbody>${(rows || []).map((row) => `
            <tr>
              <td><a href="/admin/announcements/?id=${esc(row.id)}">${esc(row.title)}</a></td>
              <td>${esc(labelOf(CATEGORIES, row.category))}</td>
              <td>${row.is_active ? 'Published' : 'Draft'}</td>
              <td>${esc(formatWhen(row.expires_at))}</td>
            </tr>`).join('') || '<tr><td colspan="4">No announcements yet.</td></tr>'}</tbody>
        </table></div>
      `;
    }

    handlers.change = null;
    handlers.click = (event) => {
      const button = event.target.closest('[data-action="new-announcement"]');
      if (!button) return;
      current = null;
      history.replaceState(null, '', '/admin/announcements/');
      draw();
    };
    handlers.submit = async (event) => {
      event.preventDefault();
      try {
        const body = {
          title: val('ann_title'),
          body: document.getElementById('ann_body').value,
          category: val('ann_category'),
          deep_link: val('ann_link'),
          is_active: checked('ann_active'),
          expires_at: endOfLocalDay(val('ann_expires')),
        };
        if (current && current.id) body.id = current.id;
        const saved = await rpc('admin_upsert_announcement', { p_body: body });
        rows = await rpc('admin_list_announcements');
        current = rows.find((item) => item.id === (saved && saved.id)) || current;
        if (current) history.replaceState(null, '', `/admin/announcements/?id=${encodeURIComponent(current.id)}`);
        draw();
        message('ok', 'Announcement saved.');
      } catch (error) {
        message('error', errorText(error));
      }
    };
    draw();
  }

  async function renderPricing() {
    const rows = await rpc('admin_list_plan_prices');
    app.innerHTML = `
      <div id="msg"></div>
      <p class="lede">List price in rupees. The next checkout uses the saved price. The length of each period stays as it is.</p>
      <div class="table-wrap"><table>
        <thead><tr><th>Plan</th><th>Period</th><th>Months</th><th>Price (₹)</th><th></th></tr></thead>
        <tbody>${(rows || []).map((row) => `
          <tr>
            <td>${esc(labelOf(PAID_PLANS, row.plan))}</td>
            <td>${esc(PERIODS[row.period] || row.period)}</td>
            <td>${esc(row.duration_months)}</td>
            <td><input id="price-${esc(row.plan)}-${esc(row.period)}" inputmode="decimal" value="${esc(rupeesFromPaise(row.amount_paise))}" /></td>
            <td><button class="btn btn-primary btn-small" type="button" data-action="save-price" data-plan="${esc(row.plan)}" data-period="${esc(row.period)}">Save</button></td>
          </tr>`).join('')}</tbody>
      </table></div>
    `;
    handlers.submit = null;
    handlers.change = null;
    handlers.click = async (event) => {
      const button = event.target.closest('[data-action="save-price"]');
      if (!button) return;
      const plan = button.getAttribute('data-plan');
      const period = button.getAttribute('data-period');
      const paise = paiseFromRupees(val(`price-${plan}-${period}`));
      if (paise === null || paise < 100) {
        message('error', 'Price must be at least ₹1.');
        return;
      }
      button.disabled = true;
      try {
        await rpc('admin_set_plan_price', {
          p_plan: plan,
          p_period: period,
          p_amount_paise: paise,
        });
        message('ok', `${labelOf(PAID_PLANS, plan)} ${PERIODS[period] || period} saved.`);
      } catch (error) {
        message('error', errorText(error));
      } finally {
        button.disabled = false;
      }
    };
  }

  async function renderCoupons() {
    let rows = [];

    async function reload() {
      rows = await rpc('admin_list_discount_codes');
    }

    function draw() {
      app.innerHTML = `
        <div id="msg"></div>
        <form class="card form-grid" data-form="coupon">
          <h2 class="span-2">New coupon</h2>
          ${field('Percent off', inputControl('coupon_percent', '', 'inputmode="numeric" required placeholder="20"'))}
          ${field('Code', inputControl('coupon_code', '', 'placeholder="Leave blank to generate"'))}
          ${field('Max uses', inputControl('coupon_max', '', 'inputmode="numeric" placeholder="No limit"'))}
          ${field('Expiry', '<input id="coupon_expires" type="date" />')}
          ${field('Owner user id', inputControl('coupon_owner', '', 'placeholder="Blank = anyone can enter it"'))}
          <p class="hint span-2">1–99 percent. A code with an owner is a referral: their previous referral code is turned off, and they cannot redeem it.</p>
          <div class="actions span-2"><button class="btn btn-primary" type="submit">Create coupon</button></div>
        </form>
        <div class="table-wrap"><table>
          <thead><tr><th>Code</th><th>%</th><th>Uses</th><th>Owner</th><th>Expires</th><th>Status</th><th></th></tr></thead>
          <tbody>${(rows || []).map((row) => `
            <tr>
              <td>${esc(row.code)}</td>
              <td>${esc(row.percent_off)}</td>
              <td>${esc(row.redemption_count)}${row.max_redemptions ? ` / ${esc(row.max_redemptions)}` : ''}</td>
              <td>${esc(row.owner_name || (row.owner_user_id ? 'Referral' : 'Anyone'))}</td>
              <td>${esc(formatWhen(row.expires_at))}</td>
              <td>${row.active ? 'Active' : 'Off'}</td>
              <td><button class="btn btn-ghost btn-small" type="button" data-action="toggle-code" data-code="${esc(row.code)}" data-active="${row.active ? 'true' : 'false'}">${row.active ? 'Turn off' : 'Turn on'}</button></td>
            </tr>`).join('') || '<tr><td colspan="7">No coupons yet.</td></tr>'}</tbody>
        </table></div>
      `;
    }

    handlers.change = null;
    handlers.submit = async (event) => {
      event.preventDefault();
      if (event.target.getAttribute('data-form') !== 'coupon') return;
      try {
        const percent = Number(val('coupon_percent'));
        const maxUses = val('coupon_max');
        const saved = await rpc('admin_create_discount_code', {
          p_percent_off: percent,
          p_code: val('coupon_code') || null,
          p_max_redemptions: maxUses ? Number(maxUses) : null,
          p_expires_at: endOfLocalDay(document.getElementById('coupon_expires').value),
          p_owner_user_id: val('coupon_owner') || null,
        });
        await reload();
        draw();
        message('ok', `Created ${saved.code}.`);
      } catch (error) {
        message('error', errorText(error));
      }
    };
    handlers.click = async (event) => {
      const button = event.target.closest('[data-action="toggle-code"]');
      if (!button) return;
      const code = button.getAttribute('data-code');
      const active = button.getAttribute('data-active') === 'true';
      try {
        await rpc('admin_set_discount_active', { p_code: code, p_active: !active });
        await reload();
        draw();
        message('ok', active ? `${code} turned off.` : `${code} turned on.`);
      } catch (error) {
        message('error', errorText(error));
      }
    };

    await reload();
    draw();
  }

  function renderBackup() {
    handlers.submit = null;
    handlers.change = null;
    let openFile = null;
    let busy = false;

    function setStatus(text) {
      const el = document.getElementById('backup-status');
      if (el) el.textContent = text || '';
    }

    function syncRestore() {
      const button = document.getElementById('run-restore');
      const confirm = document.getElementById('restore-confirm');
      if (!button || !confirm) return;
      button.disabled = busy || !openFile || confirm.value.trim() !== 'RESTORE';
    }

    function setBusy(on) {
      busy = on;
      window.onbeforeunload = on ? () => true : null;
      app.querySelectorAll('button, input').forEach((el) => {
        if (el.id === 'run-restore') return;
        el.disabled = on;
      });
      syncRestore();
    }

    function saveFile(filename, text, type) {
      const blob = new Blob([text], { type: type || 'application/octet-stream' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1500);
    }

    function showFile(file) {
      openFile = file;
      const extra = document.getElementById('extra-downloads');
      const summary = document.getElementById('restore-summary');
      if (extra) extra.hidden = false;
      if (!summary) return;
      const tables = file.tables || {};
      const names = Array.isArray(file.load_order) ? file.load_order : Object.keys(tables);
      const rows = names.reduce((sum, name) => {
        const list = tables[name];
        return sum + (Array.isArray(list) ? list.length : 0);
      }, 0);
      const accounts = file.auth && Array.isArray(file.auth.users) ? file.auth.users.length : 0;
      const when = formatWhen(file.generated_at) || file.generated_at || '';
      summary.innerHTML = `
        <ul class="summary-list">
          <li>Taken ${esc(when)}</li>
          <li>${esc(names.length)} tables, ${esc(rows)} rows</li>
          <li>${esc(accounts)} sign-in accounts</li>
        </ul>
      `;
      syncRestore();
    }

    function parseBackup(text) {
      let file;
      try {
        file = JSON.parse(text);
      } catch (error) {
        throw new Error('That file is not a backup JSON file.');
      }
      if (!file || file.format !== 'medcain-backup' || file.version !== 1) {
        throw new Error('That file is not a MEDCAIN backup.');
      }
      if (typeof file.schema_sql !== 'string' || !Array.isArray(file.load_order) || !file.tables) {
        throw new Error('That backup file is missing the schema or the tables.');
      }
      file.load_order.forEach((name) => {
        if (!Array.isArray(file.tables[name])) file.tables[name] = [];
      });
      if (!file.auth) file.auth = { users: [], identities: [] };
      if (!Array.isArray(file.auth.users)) file.auth.users = [];
      if (!Array.isArray(file.auth.identities)) file.auth.identities = [];
      return file;
    }

    async function readTable(schema, table, expected) {
      const rows = [];
      let offset = 0;
      for (;;) {
        const chunk = await rpc('admin_backup_rows', {
          p_schema: schema,
          p_table: table,
          p_offset: offset,
          p_limit: 40,
        });
        const part = chunk && Array.isArray(chunk.rows) ? chunk.rows : [];
        rows.push(...part);
        const ofTotal = expected == null ? '' : ` of ${expected}`;
        setStatus(`Reading ${table} (${rows.length}${ofTotal})…`);
        if (chunk && chunk.done) return rows;
        if (!part.length) throw new Error(`Backup stopped early while reading ${table}.`);
        offset += part.length;
        if (offset > 2000000) throw new Error(`Backup of ${table} is too large to finish here.`);
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
    }

    async function stageChunks(schema, table, rows) {
      if (!rows.length) {
        await rpc('admin_restore_stage', { p_schema: schema, p_table: table, p_rows: [] });
        return;
      }
      let size = 20;
      let index = 0;
      while (index < rows.length) {
        const slice = rows.slice(index, index + size);
        try {
          await rpc('admin_restore_stage', {
            p_schema: schema,
            p_table: table,
            p_rows: slice,
          });
          index += slice.length;
          setStatus(`Uploading ${table} (${index} of ${rows.length})…`);
          await new Promise((resolve) => setTimeout(resolve, 0));
        } catch (error) {
          const text = String(error && error.message ? error.message : error);
          if (size > 1 && /too large|payload|timeout|Failed to fetch|network/i.test(text)) {
            size = Math.max(1, Math.floor(size / 2));
            continue;
          }
          throw error;
        }
      }
    }

    app.innerHTML = `
      <div id="msg"></div>
      <p class="hint" id="backup-status"></p>
      <section class="card">
        <h2>Download</h2>
        <p>Saves a file on this computer. It contains the table definitions, every row, the SQL functions, row-level security, and grants. Keep it private. It includes password hashes, phone numbers, and payment records.</p>
        <p class="hint">Edge Functions (WhatsApp sign-in, Razorpay, admin password changes) and their secret keys are not in the database, so they are not in the file. That code lives in the git repo under <code>supabase/functions</code>. The keys stay in the Supabase dashboard.</p>
        <div class="actions">
          <button class="btn btn-primary" type="button" data-action="download-backup">Download backup</button>
        </div>
        <p class="actions" id="extra-downloads" hidden>
          <button class="btn btn-ghost btn-small" type="button" data-action="save-schema">Download schema SQL</button>
          <button class="btn btn-ghost btn-small" type="button" data-action="save-reset">Download reset SQL</button>
        </p>
      </section>
      <section class="card">
        <h2>Restore</h2>
        <p>Replaces the tables in the file with that file's rows. Tables that are not in the file are left as they are. The account you are signed in as stays an admin, and that account's profile has to be in the file.</p>
        <p class="hint">The live database changes only at the last step. If the upload stops, nothing is replaced. To rebuild a brand-new Supabase project, apply the git migrations (or the schema SQL, after the reset SQL) and put the Edge Function secrets back, then restore this file.</p>
        <label for="backup-file">Backup file</label>
        <input id="backup-file" type="file" accept="application/json,.json" />
        <div id="restore-summary"></div>
        <label class="check" for="restore-auth">
          <input id="restore-auth" type="checkbox" checked />
          <span>Also restore sign-in accounts, so people can log in as they did when this file was saved.</span>
        </label>
        <label for="restore-confirm">Type RESTORE to confirm</label>
        <input id="restore-confirm" autocomplete="off" />
        <div class="actions">
          <button class="btn btn-primary" id="run-restore" type="button" data-action="run-restore" disabled>Restore data</button>
        </div>
      </section>
    `;

    document.getElementById('restore-confirm').addEventListener('input', syncRestore);
    document.getElementById('backup-file').addEventListener('change', async (event) => {
      const input = event.target;
      const file = input.files && input.files[0];
      message('', '');
      if (!file) return;
      try {
        showFile(parseBackup(await file.text()));
        setStatus('File read. Type RESTORE and choose Restore data when you mean to replace the database.');
      } catch (error) {
        openFile = null;
        const summary = document.getElementById('restore-summary');
        if (summary) summary.innerHTML = '';
        syncRestore();
        message('error', errorText(error));
      }
    });

    handlers.click = async (event) => {
      const button = event.target.closest('[data-action]');
      if (!button || busy) return;
      const action = button.getAttribute('data-action');

      if (action === 'save-schema' || action === 'save-reset') {
        if (!openFile) return;
        const text = action === 'save-schema' ? openFile.schema_sql : openFile.reset_public_sql;
        if (!text) {
          message('error', 'This backup does not include that SQL script.');
          return;
        }
        const stamp = String(openFile.generated_at || 'backup').replace(/[:.]/g, '-');
        saveFile(
          action === 'save-schema' ? `medcain-schema-${stamp}.sql` : `medcain-reset-${stamp}.sql`,
          text,
          'application/sql',
        );
        return;
      }

      if (action === 'download-backup') {
        setBusy(true);
        message('', '');
        try {
          setStatus('Counting tables…');
          const manifest = await rpc('admin_backup_manifest');
          setStatus('Reading the schema…');
          const schema = await rpc('admin_backup_schema');
          if (!schema || typeof schema.schema_sql !== 'string') {
            throw new Error('The schema could not be read.');
          }
          const tables = {};
          const order = manifest.load_order || [];
          for (const item of manifest.tables || []) {
            tables[item.name] = await readTable('public', item.name, item.rows);
          }
          setStatus('Reading sign-in accounts…');
          const backup = {
            format: 'medcain-backup',
            version: 1,
            generated_at: manifest.generated_at,
            postgres_version: manifest.postgres_version,
            not_included: manifest.not_included || [],
            load_order: order,
            schema_sql: schema.schema_sql || '',
            reset_public_sql: schema.reset_public_sql || '',
            tables,
            auth: {
              users: await readTable('auth', 'users', manifest.auth_users),
              identities: await readTable('auth', 'identities', manifest.auth_identities),
            },
          };
          const stamp = String(backup.generated_at || new Date().toISOString()).replace(/[:.]/g, '-');
          saveFile(`medcain-backup-${stamp}.json`, JSON.stringify(backup), 'application/json');
          showFile(backup);
          setStatus('Backup saved. Store the file somewhere private.');
          message('ok', 'Backup downloaded.');
        } catch (error) {
          setStatus('');
          message('error', errorText(error));
        } finally {
          setBusy(false);
        }
        return;
      }

      if (action !== 'run-restore') return;
      if (!openFile || document.getElementById('restore-confirm').value.trim() !== 'RESTORE') {
        message('error', 'Type RESTORE to confirm.');
        return;
      }
      const restoreAuth = document.getElementById('restore-auth').checked;
      if (restoreAuth && !openFile.auth.users.length && !openFile.auth.identities.length) {
        message('error', 'This backup has no sign-in accounts. Uncheck that option, or use a full backup.');
        return;
      }
      setBusy(true);
      message('', '');
      try {
        const names = openFile.load_order.filter(
          (name) => name !== 'admin_restore_runs' && name !== 'admin_restore_staging',
        );
        setStatus('Opening the restore…');
        await rpc('admin_restore_begin', {
          p_confirm: 'RESTORE',
          p_tables: names,
          p_restore_auth: restoreAuth,
        });
        if (restoreAuth) {
          await stageChunks('auth', 'users', openFile.auth.users);
          await stageChunks('auth', 'identities', openFile.auth.identities);
        }
        for (const name of names) {
          await stageChunks('public', name, openFile.tables[name] || []);
        }
        setStatus('Applying the backup…');
        await rpc('admin_restore_commit');
        setStatus('Restore finished.');
        message('ok', 'The database matches this backup. Your account is still an admin.');
      } catch (error) {
        try {
          await rpc('admin_restore_cancel');
        } catch (cancelError) {
          // The upload is also discarded the next time a restore starts.
        }
        setStatus('');
        message('error', errorText(error));
      } finally {
        setBusy(false);
      }
    };
  }

  function report(error) {
    message('error', errorText(error));
  }

  app.addEventListener('submit', (event) => {
    if (!handlers.submit) return;
    Promise.resolve(handlers.submit(event)).catch(report);
  });
  app.addEventListener('click', (event) => {
    if (!handlers.click) return;
    Promise.resolve(handlers.click(event)).catch(report);
  });
  app.addEventListener('change', (event) => {
    if (!handlers.change) return;
    Promise.resolve(handlers.change(event)).catch(report);
  });

  const signOut = document.getElementById('sign-out');
  if (signOut) {
    signOut.addEventListener('click', async () => {
      stopPoll();
      if (supabase) await supabase.auth.signOut();
      renderLogin('');
    });
  }

  const config = window.ADMIN_CONFIG || {};
  if (
    !config.supabaseUrl ||
    !config.supabaseAnonKey ||
    String(config.supabaseUrl).includes('YOUR_PROJECT')
  ) {
    app.innerHTML = '<p class="msg error">Admin is not configured. Copy <code>config.example.js</code> to <code>config.js</code>, or start the site container so it can write <code>config.js</code>.</p>';
    return;
  }
  if (!window.supabase || !window.supabase.createClient) {
    app.innerHTML = '<p class="msg error">Sign-in library failed to load.</p>';
    return;
  }

  supabase = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey, {
    auth: {
      storageKey: 'medcain-admin-auth',
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false,
    },
  });

  supabase.auth.getSession().then(({ data }) => {
    if (data.session) enterApp();
    else renderLogin('');
  }).catch((error) => {
    renderLogin(errorText(error));
  });
})();
