/// Match times in the 12-hour format with AM / PM (client 23 Oct round 3
/// #13), e.g. "06:30 PM". [d] is already in the device's own timezone
/// (`MatchFixture.kickoff` is parsed with `toLocal()`). The reference apps
/// keep "AM / PM" in Arabic too.
String matchClock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${h.toString().padLeft(2, '0')}:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
