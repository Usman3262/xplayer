class SportsMatch {
  const SportsMatch({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeScore,
    required this.awayScore,
    required this.minute,
    required this.stadium,
    required this.broadcaster,
    this.isLive = true,
    this.imageUrl,
    this.streamUrl,
  });

  final String id;
  final String homeTeam;
  final String awayTeam;
  final int homeScore;
  final int awayScore;
  final String minute;
  final String stadium;
  final String broadcaster;
  final bool isLive;
  final String? imageUrl;
  final String? streamUrl;
}
