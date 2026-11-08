/** Preview and transactionally apply the complete Questions CSV snapshot. */
function checkConfiguration() {
  var ui = SpreadsheetApp.getUi();
  try {
    var cfg = getSupabaseConfig_();
    ui.alert(
      'Configuration OK',
      'SUPABASE_URL is set (' + cfg.url + ').\n' +
        'SUPABASE_SERVICE_ROLE_KEY is set (value hidden).\n\n' +
        'Editor tab: Questions.\n' +
        'Required migrations through 20261108120000_question_public_codes.sql.',
      ui.ButtonSet.OK
    );
  } catch (e) {
    ui.alert('Configuration incomplete', String(e.message || e), ui.ButtonSet.OK);
  }
}

function syncToApp() {
  var ui = SpreadsheetApp.getUi();
  try {
    getSupabaseConfig_();
    ensureQuestionIdColumn_();
    // App edits land on the sheet before this snapshot is imported, so they
    // are not deleted as rows missing from the sheet.
    var pulled = pullAppEdits_({ silent: true });
    var rows = readQuestionsRows_();
    var preview = supabaseRpc_('sync_content_csv', {
      p_rows: rows,
      p_apply: false,
    });
    if (!preview.ok) {
      var errors = preview.errors || [];
      ui.alert(
        'Sync aborted — nothing written',
        errors.slice(0, 40).join('\n') +
          (errors.length > 40 ? '\n… and ' + (errors.length - 40) + ' more' : ''),
        ui.ButtonSet.OK
      );
      return;
    }

    var counts = preview.counts || {};
    var confirm = ui.prompt(
      'Preview content sync',
      'App edits written to the sheet first: ' + pulled +
        '\nQuestions to insert: ' + (counts.insert || 0) +
        '\nQuestions to update: ' + (counts.update || 0) +
        '\nQuestions to DELETE: ' + (counts.delete || 0) +
        '\nComplete attempts to DELETE: ' + (counts.attempt_delete || 0) +
        '\nDependent history to DELETE: ' + (counts.dependent_delete || 0) +
        '\n\nDeletes cannot be undone. Type APPLY to continue.',
      ui.ButtonSet.OK_CANCEL
    );
    if (
      confirm.getSelectedButton() !== ui.Button.OK ||
      trimStr_(confirm.getResponseText()) !== 'APPLY'
    ) return;

    var result = supabaseRpc_('sync_content_csv', {
      p_rows: rows,
      p_apply: true,
    });
    if (!result.ok || !result.applied) {
      throw new Error((result.errors || ['Apply failed.']).join('\n'));
    }
    var stamped = writeQuestionIds_(result.question_ids);
    ui.alert(
      'Sync complete',
      'Inserted: ' + (result.counts.insert || 0) +
        '\nUpdated: ' + (result.counts.update || 0) +
        '\nDeleted: ' + (result.counts.delete || 0) +
        '\nQuestion ids written: ' + stamped,
      ui.ButtonSet.OK
    );
  } catch (e) {
    ui.alert('Sync failed', String(e.message || e), ui.ButtonSet.OK);
  }
}

/** Keep question_id as text so 000123 is not stored as the number 123. */
function ensureQuestionIdColumn_() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(QUESTIONS_TAB);
  if (!sheet) return;
  var col = ensureQuestionColumn_(sheet, 'question_id');
  sheet.getRange(1, col, sheet.getMaxRows(), 1).setNumberFormat('@');
}

/** @return {number} cells written */
function writeQuestionIds_(assignments) {
  if (!assignments || !assignments.length) return 0;
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(QUESTIONS_TAB);
  if (!sheet) return 0;
  var col = ensureQuestionColumn_(sheet, 'question_id');
  var last = sheet.getLastRow();
  if (last < 2) return 0;
  var range = sheet.getRange(2, col, last - 1, 1);
  range.setNumberFormat('@');
  var values = range.getValues();
  var written = 0;
  for (var i = 0; i < assignments.length; i++) {
    var item = assignments[i];
    var idx = Number(item.row_number) - 2;
    if (idx < 0 || idx >= values.length || !item.question_id) continue;
    var code = String(item.question_id);
    if (String(values[idx][0]) !== code) written++;
    values[idx][0] = code;
  }
  range.setValues(values);
  return written;
}
