/**
 * Write queued in-app question edits into the Questions tab.
 * Sync to App calls this first so the next import does not wipe them.
 *
 * App edits of a row win over unsaved sheet edits of that same stem.
 * Other sheet-only edits still flow into Postgres on Sync to App.
 */

var PULL_HEADERS = ['required_plan', 'is_active'];

function pullAppEdits() {
  var ui = SpreadsheetApp.getUi();
  try {
    var count = pullAppEdits_({ silent: true });
    ui.alert(
      count
        ? 'Pulled ' + count + ' app edit(s) into Questions.\nRun Sync to App when the sheet should update the database.'
        : 'No app edits waiting.',
      ui.ButtonSet.OK
    );
  } catch (e) {
    ui.alert('Pull failed', String(e.message || e), ui.ButtonSet.OK);
  }
}

/** @return {number} rows applied */
function pullAppEdits_(options) {
  options = options || {};
  var items = supabaseRpc_('export_sheet_outbox', {});
  if (!items || !items.length) return 0;

  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(QUESTIONS_TAB);
  if (!sheet) {
    throw new Error('Missing tab "Questions".');
  }
  for (var h = 0; h < PULL_HEADERS.length; h++) {
    ensureQuestionColumn_(sheet, PULL_HEADERS[h]);
  }

  var applied = [];
  for (var i = 0; i < items.length; i++) {
    try {
      applyOutboxItem_(sheet, items[i]);
      applied.push(items[i].id);
    } catch (e) {
      if (applied.length) {
        supabaseRpc_('ack_sheet_outbox', { p_ids: applied });
      }
      throw e;
    }
  }
  supabaseRpc_('ack_sheet_outbox', { p_ids: applied });
  return applied.length;
}

function applyOutboxItem_(sheet, item) {
  var rowNumber = item.match ? findQuestionRow_(sheet, item.match) : 0;
  if (item.op === 'delete') {
    if (rowNumber > 1) sheet.deleteRow(rowNumber);
    return;
  }
  if (!item.row) {
    throw new Error('App edit is missing a sheet row.');
  }
  if (rowNumber > 1) {
    writePayload_(sheet, rowNumber, item.row);
  } else {
    appendPayload_(sheet, item.row);
  }
}

function findQuestionRow_(sheet, match) {
  var range = sheet.getDataRange();
  var displays = range.getDisplayValues();
  if (displays.length < 2) return 0;
  var headers = displays[0].map(headerKey_);
  for (var r = 1; r < displays.length; r++) {
    if (rowMatches_(displays[r], headers, match)) return r + 1;
  }
  return 0;
}

function rowMatches_(displayRow, headers, match) {
  function cell(name) {
    var idx = headers.indexOf(name);
    if (idx < 0) return '';
    return displayRow[idx];
  }
  if (normKey_(cell('subject_name')) !== normKey_(match.subject_name)) return false;
  if (normKey_(cell('question_type')) !== normKey_(match.question_type)) return false;
  if (normKey_(cell('question_text')) !== normKey_(match.question_text)) return false;
  if (normKey_(cell('university_alias')) !== normKey_(match.university_alias)) return false;
  if (normKey_(cell('college_alias')) !== normKey_(match.college_alias || '')) return false;
  if (examKey_(cell('exam_type')) !== examKey_(match.exam_type)) return false;
  if (yearKey_(cell('year')) !== yearKey_(match.year)) return false;
  if (monthKey_(cell('month')) !== monthKey_(match.month)) return false;
  if (normKey_(cell('paper_number')) !== normKey_(match.paper_number || '')) return false;
  return true;
}

function ensureQuestionColumn_(sheet, headerName) {
  var last = Math.max(sheet.getLastColumn(), 1);
  var headers = sheet.getRange(1, 1, 1, last).getValues()[0];
  var wanted = headerKey_(headerName);
  for (var i = 0; i < headers.length; i++) {
    if (headerKey_(headers[i]) === wanted) return i + 1;
  }
  var col = sheet.getLastColumn() + 1;
  sheet.getRange(1, col).setValue(headerName);
  return col;
}

function writePayload_(sheet, rowNumber, payload) {
  var last = sheet.getLastColumn();
  var headers = sheet.getRange(1, 1, 1, last).getValues()[0].map(headerKey_);
  for (var key in payload) {
    if (!Object.prototype.hasOwnProperty.call(payload, key)) continue;
    var idx = headers.indexOf(headerKey_(key));
    if (idx < 0) continue;
    var value = payload[key];
    sheet.getRange(rowNumber, idx + 1).setValue(value == null ? '' : value);
  }
}

function appendPayload_(sheet, payload) {
  var last = sheet.getLastColumn();
  var headers = sheet.getRange(1, 1, 1, last).getValues()[0].map(headerKey_);
  var row = [];
  for (var i = 0; i < headers.length; i++) {
    var value = payload[headers[i]];
    row.push(value == null ? '' : value);
  }
  sheet.appendRow(row);
}

function normKey_(value) {
  return trimStr_(value).replace(/\s+/g, ' ').toLowerCase();
}

function yearKey_(value) {
  return normKey_(value).replace(/\.0$/, '');
}

function examKey_(value) {
  var v = normKey_(value).replace(/[^a-z]+/g, '');
  if (v === 'preproff') return 'preprof';
  return v;
}

function monthKey_(value) {
  var v = trimStr_(value).toLowerCase();
  if (!v) return '';
  if (/^[0-9]+(\.0+)?$/.test(v)) {
    var n = parseInt(v, 10);
    return n >= 1 && n <= 12 ? String(n) : '';
  }
  var word = v.split(' ')[0].replace(/[^a-z]/g, '');
  var months = {
    january: '1', jan: '1',
    february: '2', feb: '2',
    march: '3', mar: '3',
    april: '4', apr: '4',
    may: '5',
    june: '6', jun: '6',
    july: '7', jul: '7',
    august: '8', aug: '8',
    september: '9', sep: '9', sept: '9',
    october: '10', oct: '10',
    november: '11', nov: '11',
    december: '12', dec: '12',
  };
  return months[word] || '';
}
