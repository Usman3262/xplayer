/// Remote-input rules for the TV player, as pure functions so they can be
/// unit-tested without a player (client 16 Oct #5, #13, #14, #16, #18).
///
/// Back priority (one Back press = exactly one step):
///   1. a channel being chosen with Up/Down -> cancel that choice
///   2. channel list open                  -> close it, back to playback
///      (client 18 Oct TV #3); the next Back within a few seconds asks to
///      exit, so live TV can still be left
///   3. live with a channel list           -> open the channel list
///      (also while loading, buffering, paused or failed)
///   4. failed, or a movie/series still loading -> leave (nothing playing)
///   5. otherwise (movie/series playing or paused) -> exit confirmation
/// Dialogs (exit confirmation, settings) sit on top as their own routes and
/// take Back before the player sees it.
enum TvBackAction {
  cancelPendingZap,
  confirmExit,
  openChannelList,
  closeChannelList,
  leave,
}

TvBackAction tvBackAction({
  required bool pendingZap,
  required bool listOpen,
  required bool live,
  required bool hasChannelList,
  required bool failed,
  required bool ready,
  bool exitArmed = false,
}) {
  if (pendingZap) return TvBackAction.cancelPendingZap;
  if (listOpen) return TvBackAction.closeChannelList;
  if (live && exitArmed) return TvBackAction.confirmExit;
  if (live && hasChannelList) return TvBackAction.openChannelList;
  if (failed || (!ready && !live)) return TvBackAction.leave;
  return TvBackAction.confirmExit;
}

/// Live Up/Down while no control button has focus:
///   - channel list open -> move focus into the list (list handles keys)
///   - info bar hidden    -> first press only reveals the bar
///   - bar visible        -> change channel: Up = next (+1), Down = previous
///                           (-1), the same in Arabic and English.
/// The channel list wraps at both ends (last -> first, first -> last).
enum TvLiveKeyAction { focusList, revealBar, changeChannel }

TvLiveKeyAction tvLiveKeyAction({
  required bool listOpen,
  required bool barVisible,
  required bool pendingZap,
}) {
  if (listOpen) return TvLiveKeyAction.focusList;
  if (!barVisible && !pendingZap) return TvLiveKeyAction.revealBar;
  return TvLiveKeyAction.changeChannel;
}

/// Channel step for a key: Up / Channel+ = next, Down / Channel- = previous.
int tvChannelDelta({required bool upKey}) => upKey ? 1 : -1;
