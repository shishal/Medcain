import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/data/auth_repository.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../../domain/watermark_identity.dart';

part 'watermark_label_provider.g.dart';

/// Identity tiled over question content.
///
/// The WhatsApp number comes from Auth when the profile phone is still
/// empty. A synthetic internal email is never painted.
@riverpod
String watermarkLabel(Ref ref) {
  final auth = ref.watch(authRepositoryProvider);
  final profile = ref.watch(userProfileProvider).asData?.value;
  final profilePhone = profile?.phone?.trim();
  return WatermarkIdentity.label(
    fullName: profile?.fullName,
    phone: (profilePhone != null && profilePhone.isNotEmpty)
        ? profilePhone
        : auth.currentPhone,
    email: auth.currentEmail,
  );
}
