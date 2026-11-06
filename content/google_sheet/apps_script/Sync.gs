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
        'Required migrations through 20261103180000_admin_console.sql.',
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
    ui.alert(
      'Sync complete',
      'Inserted: ' + (result.counts.insert || 0) +
        '\nUpdated: ' + (result.counts.update || 0) +
        '\nDeleted: ' + (result.counts.delete || 0),
      ui.ButtonSet.OK
    );
  } catch (e) {
    ui.alert('Sync failed', String(e.message || e), ui.ButtonSet.OK);
  }
}
