class Episode {
  const Episode({
    required this.id,
    required this.seriesId,
    required this.season,
    required this.number,
    required this.title,
    // Empty when the provider sends no duration (never invent one).
    this.durationLabel = '',
    this.synopsis,
    this.stillUrl,
    this.streamUrl,
    this.containerExtension,
  });

  final String id;
  final String seriesId;
  final int season;
  final int number;
  final String title;
  final String durationLabel;
  final String? synopsis;
  final String? stillUrl;
  final String? streamUrl;
  final String? containerExtension;
}
