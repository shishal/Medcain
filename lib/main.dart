import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase/env.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseEnv.load();
  await Supabase.initialize(
    url: SupabaseEnv.url,
    publishableKey: SupabaseEnv.anonKey,
  );

  // ProviderScope is Riverpod's root: every provider lives under this widget.
  // Without it, ref.watch / Consumer widgets have nothing to read from.
  runApp(
    const ProviderScope(
      child: MedicoApp(),
    ),
  );
}
