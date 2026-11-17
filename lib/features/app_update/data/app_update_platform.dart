import 'app_update_platform_stub.dart'
    if (dart.library.io) 'app_update_platform_io.dart'
    as platform;

/// Android release and debug builds enforce the minimum. Other targets
/// (iOS, desktop, tests on a Mac) skip it — the button opens Play, which
/// those targets do not have.
bool get appUpdateEnforced => platform.appUpdateEnforcedOnThisPlatform;
