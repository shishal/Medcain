/// The exam player was opened for a reading session.
///
/// Reading mode must not create an `attempts` row. The player screen catches
/// this and opens the scroll reader instead.
class ReadingModeRedirect implements Exception {
  const ReadingModeRedirect();
}
