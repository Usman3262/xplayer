import 'package:domain/domain.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The channel row a live stream was opened from, so the player can switch
/// channels with Up/Down and show a channel list without another API call.
class LiveZapList {
  const LiveZapList(this.channels, {this.title});
  final List<MediaItem> channels;
  final String? title;

  int indexOf(String id) => channels.indexWhere((c) => c.id == id);

  /// Neighbour of [id], wrapping at both ends. Null when unknown or alone.
  MediaItem? step(String id, int delta) {
    if (channels.length < 2) return null;
    final i = indexOf(id);
    if (i < 0) return null;
    final n = channels.length;
    return channels[((i + delta) % n + n) % n];
  }
}

final liveZapProvider = StateProvider<LiveZapList?>((_) => null);

/// Opens [channel] in the player and remembers [row] for channel switching.
void openTvLiveChannel(
  BuildContext context,
  WidgetRef ref,
  MediaItem channel,
  List<MediaItem> row, {
  String? title,
}) {
  ref.read(liveZapProvider.notifier).state = LiveZapList(
    [for (final c in row) if (c.kind == MediaKind.live || c.isLive) c],
    title: title,
  );
  final name = channel.displayTitle.trim();
  final titleQ = name.isNotEmpty
      ? '&title=${Uri.encodeQueryComponent(name)}'
      : '';
  context.push('/player/${channel.id}?kind=live$titleQ', extra: channel);
}

/// Remote Back can arrive twice for one press on TCL (key event + system
/// back), and users press again while a player is still closing. Leaving the
/// player suppresses Back here for a short window so the extra press does not
/// fall through to the shell, which sends you to Home (client video 15 Oct).
DateTime? _backSuppressedUntil;

void tvSuppressBack([Duration d = const Duration(milliseconds: 900)]) {
  final until = DateTime.now().add(d);
  final cur = _backSuppressedUntil;
  if (cur == null || until.isAfter(cur)) _backSuppressedUntil = until;
}

bool tvBackSuppressed() {
  final until = _backSuppressedUntil;
  return until != null && DateTime.now().isBefore(until);
}
