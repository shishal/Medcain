/**
 * Read the one Questions tab as JSON-ready objects.
 * Headers are case-insensitive and may contain spaces or hyphens.
 */
function headerKey_(value) {
  return trimStr_(value)
    .replace(/^\uFEFF/, '')
    .toLowerCase()
    .replace(/[\s-]+/g, '_');
}

function readQuestionsRows_() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(QUESTIONS_TAB);
  if (!sheet) {
    throw new Error('Missing tab "Questions". Import tabs/Questions.csv and keep that tab name.');
  }
  var range = sheet.getDataRange();
  var values = range.getValues();
  var displays = range.getDisplayValues();
  if (!values.length) return [];

  var headers = values[0].map(headerKey_);
  var required = [
    'university_alias', 'university_name', 'exam_type', 'year', 'month',
    'subject_name', 'question_type', 'question_text'
  ];
  for (var i = 0; i < required.length; i++) {
    if (headers.indexOf(required[i]) < 0) {
      throw new Error('Questions is missing column ' + required[i] + '. Import tabs/Questions.csv.');
    }
  }

  var rows = [];
  for (var r = 1; r < values.length; r++) {
    var row = {};
    var hasValue = false;
    for (var c = 0; c < headers.length; c++) {
      if (!headers[c]) continue;
      // Display strings keep CSV and Sheets behavior identical (notably dates,
      // checkboxes, and numeric years).
      var value = trimStr_(displays[r][c]);
      if (value !== '') {
        row[headers[c]] = value;
        hasValue = true;
      }
    }
    if (hasValue) {
      row._row_number = r + 1;
      rows.push(row);
    }
  }
  return rows;
}
