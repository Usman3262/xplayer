import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update.dart';

final pendingUpdateProvider = StateProvider<AppUpdateInfo?>((ref) => null);
