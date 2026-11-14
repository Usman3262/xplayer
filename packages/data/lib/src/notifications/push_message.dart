/// A message to show in the tray / handle on tap. Provider-neutral: no push
/// service is wired in (Firebase was removed). A future source (Supabase
/// realtime, etc.) builds one of these and calls `PushNotifications.show`.
class PushMessage {
  const PushMessage({
    this.id,
    this.title = '',
    this.body = '',
    this.data = const {},
  });

  final String? id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
}
