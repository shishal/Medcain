/**
 * Phase 2.2 — Medico Google Sheet → Supabase sync
 *
 * Install: see README.md in this folder.
 * Secrets: Script Properties SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY only.
 */

var QUESTIONS_TAB = 'Questions';

var PROP = {
  URL: 'SUPABASE_URL',
  KEY: 'SUPABASE_SERVICE_ROLE_KEY',
};

function trimStr_(value) {
  if (value == null) return '';
  // Sheets often pastes NBSP; treat it as a normal space so keys still match.
  return String(value).replace(/\u00a0/g, ' ').trim();
}

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Medico')
    .addItem('Pull app edits', 'pullAppEdits')
    .addItem('Sync to App', 'syncToApp')
    .addItem('Check configuration', 'checkConfiguration')
    .addToUi();
}
