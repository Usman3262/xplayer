import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update.dart';

final pendingUpdateProvider = StateProvider<AppUpdateInfo?>((ref) => null);

/// Optional update found at start (client 23 Oct): Home shows it once per version.
final optionalUpdateProvider = StateProvider<AppUpdateInfo?>((ref) => null);
