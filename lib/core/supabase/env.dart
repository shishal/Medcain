import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads Supabase credentials from the gitignored `assets/env` file.
///
/// Those three public values start in the repo-root `.env` (see
/// `.env.example`). The bundled copy cannot be named `.env`: Android's
/// package tool drops assets whose names start with a dot, so a release
/// APK never contained the file and [main] stopped before `runApp`.
abstract final class SupabaseEnv {
  static Future<void> load() async {
    await dotenv.load(fileName: 'assets/env');
  }

  static String get url {
    final value = dotenv.env['SUPABASE_URL'];
    if (value == null || value.isEmpty || value.contains('YOUR_PROJECT')) {
      throw StateError(
        'SUPABASE_URL is missing or still a placeholder. '
        'Copy it from .env into assets/env.',
      );
    }
    return value;
  }

  static String get anonKey {
    final value = dotenv.env['SUPABASE_ANON_KEY'];
    if (value == null || value.isEmpty || value == 'your_anon_key') {
      throw StateError(
        'SUPABASE_ANON_KEY is missing or still a placeholder. '
        'Copy it from .env into assets/env.',
      );
    }
    return value;
  }
}
