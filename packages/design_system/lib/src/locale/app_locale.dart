import 'package:flutter/widgets.dart';
import 'package:domain/domain.dart' show AppBrand;
// Shared UI language helpers for the app (mobile + TV).
// Prefs key matches the old APK convention: `app.lang` → `en` | `ar` | `ur`.
import '../utils/display_name.dart';

enum AppLang { en, ar, ur }

abstract final class AppLocale {
  static const prefsKey = 'app.lang';
  static const english = 'English';
  static const arabic = 'العربية';
  static const urdu = 'اردو';

  // Task #143 #7: Urdu removed from all app versions (EN + AR only).
  static const allLabels = [english, arabic];

  static bool isArabic(String? language) => resolve(language) == AppLang.ar;
  static bool isUrdu(String? language) => false;
  static bool isRtl(String? language) => resolve(language) == AppLang.ar;

  static AppLang resolve(String? raw) {
    if (raw == null) return AppLang.en;
    final v = raw.trim().toLowerCase();
    if (v == 'ar' ||
        v == 'arabic' ||
        raw.trim() == arabic ||
        v.contains('arab')) {
      return AppLang.ar;
    }
    // Legacy Urdu prefs map to English (language no longer offered).
    if (v == 'ur' ||
        v == 'urdu' ||
        raw.trim() == urdu ||
        v.contains('urdo') ||
        v.contains('اردو')) {
      return AppLang.en;
    }
    return AppLang.en;
  }

  /// Normalize any legacy value to a display label.
  static String normalize(String? raw) {
    switch (resolve(raw)) {
      case AppLang.ar:
        return arabic;
      case AppLang.ur:
      case AppLang.en:
        return english;
    }
  }

  static String toPrefsCode(String language) {
    switch (resolve(language)) {
      case AppLang.ar:
        return 'ar';
      case AppLang.ur:
      case AppLang.en:
        return 'en';
    }
  }

  static String fromPrefsCode(String? code) {
    switch (code) {
      case 'ar':
        return arabic;
      case 'ur':
        // Migrated off Urdu.
        return english;
      default:
        return english;
    }
  }

  static LocaleCode localeFor(String? language) {
    switch (resolve(language)) {
      case AppLang.ar:
        return const LocaleCode('ar');
      case AppLang.ur:
      case AppLang.en:
        return const LocaleCode('en');
    }
  }

  /// Cycle EN → AR → EN.
  static String next(String? current) {
    switch (resolve(current)) {
      case AppLang.en:
        return arabic;
      case AppLang.ar:
      case AppLang.ur:
        return english;
    }
  }

  /// Strip catalog language prefixes like `AR:`, `SUBS:`, `4K-AR:`.
  /// Never returns the catalog placeholder literal "Title".
  static String cleanTitle(String? raw) {
    if (raw == null) return '';
    final cleaned = cleanDisplayName(raw).trim();
    if (cleaned.isEmpty || cleaned.toLowerCase() == 'title') return '';
    return cleaned;
  }
}

/// Tiny locale id without importing Flutter in pure helpers.
class LocaleCode {
  const LocaleCode(this.languageCode);
  final String languageCode;
}

/// All chrome / settings / browse / auth strings for EN · AR · UR.
class AppCopy {
  const AppCopy(this.lang);

  /// From the surrounding text direction (Arabic is the only RTL language
  /// the apps ship), for small widgets without access to the session.
  factory AppCopy.ofContext(BuildContext context) => AppCopy.ofLanguage(
        Directionality.maybeOf(context) == TextDirection.rtl ? 'ar' : 'en',
      );

  factory AppCopy.ofLanguage(String? language) =>
      AppCopy(AppLocale.resolve(language));

  final AppLang lang;

  /// Set by the Windows desktop build: texts that say "TV" for the TV apps
  /// use PC wording. Phone and TV builds keep false (texts unchanged).
  static bool pcWording = false;

  bool get isRtl => lang == AppLang.ar || lang == AppLang.ur;

  String _t(String en, String ar, String ur) {
    switch (lang) {
      case AppLang.ar:
        return ar;
      case AppLang.ur:
        return ur;
      case AppLang.en:
        return en;
    }
  }

  // ── Nav ──────────────────────────────────────────────────────────
  String get home => _t('Home', 'الرئيسية', 'ہوم');
  String get movies => _t('Movies', 'أفلام', 'فلمیں');
  String get series => _t('Series', 'مسلسلات', 'سیریز');
  /// Banner button, as on LG ("More Info" / "مزيد من المعلومات").
  String get moreInfo => _t('More Info', 'المزيد', 'مزید معلومات');
  String get liveTv => _t('Live TV', 'بث مباشر', 'لائیو ٹی وی');
  String get channelList => _t('Channel list', 'قائمة القنوات', 'چینل فہرست');
  String get liveNow => _t('LIVE NOW', 'مباشر الآن', 'ابھی لائیو');
  String get watchFullscreen =>
      _t('Watch Fullscreen', 'مشاهدة بملء الشاشة', 'فل اسکرین دیکھیں');
  String get favorite => _t('Favorite', 'المفضلة', 'پسندیدہ');
  String get favorited => _t('Favorited', 'في المفضلة', 'پسندیدہ میں');
  String get favoritesCategory => _t('Favourites', 'المفضلة', 'پسندیدہ');
  /// Live TV / Sports top rail of favorited channels (C20).
  String get myFavorites =>
      _t('My Favorites', 'مفضلتي', 'میرے پسندیدہ');
  String get categories => _t('Categories', 'الفئات', 'زمرے');
  /// Section total next to "LIVE TV" / "SPORTS" (client 23 Oct #4).
  String channelsTotal(int n) => _t('$n channels', '$n قناة', '$n channels');
  String channelsCount(int n) =>
      _t('CHANNELS ($n)', 'القنوات ($n)', 'چینلز ($n)');
  String get channelListHint => _t(
        'OK to watch • ★ to add to Favourites • Back to close',
        'موافق للمشاهدة • ★ للإضافة إلى المفضلة • رجوع للإغلاق',
        'دیکھنے کے لیے OK • پسندیدہ کے لیے ★ • بند کرنے کے لیے Back',
      );
  String get sports => _t('Sports', 'رياضة', 'سپورٹس');
  String get settings => _t('Settings', 'الإعدادات', 'ترتیبات');
  String get search => _t('Search', 'بحث', 'تلاش');
  String get all => _t('All', 'الكل', 'سب');
  String get allMovies => _t('All Movies', 'كل الأفلام', 'تمام فلمیں');
  String get allSeries => _t('All Series', 'كل المسلسلات', 'تمام سیریز');
  String get viewAll => _t('View All', 'عرض الكل', 'سب دیکھیں');
  String titlesCount(int n) => _t('$n Titles', '$n عنوان', '$n عنوانات');
  String get featuredMovie => _t('FEATURED MOVIE', 'فيلم مميز', 'نمایاں فلم');
  String get featuredSeries =>
      _t('FEATURED SERIES', 'مسلسل مميز', 'نمایاں سیریز');
  String get kids => _t('Kids', 'أطفال', 'بچے');
  String get clips => _t('Clips', 'مقاطع', 'کلپس');
  String get neu => _t('New', 'جديد', 'نیا');
  String get newAndPopular =>
      _t('New & Popular', 'جديد وشائع', 'نیا اور مقبول');

  // ── Common actions ───────────────────────────────────────────────
  String get seeAll => _t('SEE ALL', 'عرض الكل', 'سب دیکھیں');
  String get exploreAll =>
      _t('EXPLORE ALL', 'استكشف الكل', 'سب دریافت کریں');
  /// Live / Movies / Series: next page of packages (15 at a time).
  String get loadMorePackages =>
      _t('Load more packages', 'تحميل المزيد من الباقات', 'مزید پیکجز لوڈ کریں');
  String get watchNow => _t('Watch Now', 'شاهد الآن', 'ابھی دیکھیں');
  /// Not released yet (client 4 Nov, as on LG): instead of Watch Now.
  String get soon => _t('Soon', 'قريبًا', 'جلد آ رہا ہے');
  /// Series button after an episode was watched (client 18 Oct #13).
  String continueEpisode(int season, int episode) => _t(
    'Continue Watching S$season E$episode',
    'متابعة المشاهدة · الموسم $season الحلقة $episode',
    'دیکھنا جاری رکھیں S$season E$episode',
  );
  String get watchNow4kHdr =>
      _t('Watch Now (4K HDR)', 'شاهد الآن (4K HDR)', 'ابھی دیکھیں (4K HDR)');
  String get details => _t('Details', 'التفاصيل', 'تفصیلات');
  String get detailsAndEpisodes =>
      _t('Details & Episodes', 'التفاصيل والحلقات', 'تفصیلات اور اقساط');
  String get detailsAndSpecs =>
      _t('Details & Specs', 'التفاصيل والمواصفات', 'تفصیلات و اسپیکس');
  String get resume => _t('Resume', 'متابعة', 'جاری رکھیں');
  String resumePercent(int pct) =>
      _t('Resume ($pct%)', 'متابعة ($pct%)', 'جاری رکھیں ($pct%)');
  /// Resume button in minutes (client 23 Oct #8: not a percentage).
  String resumeMinutes(int positionSec, double progress) {
    final m = (positionSec / 60).floor();
    final total = progress > 0.01 && progress <= 1 ? (positionSec / progress / 60).round() : 0;
    if (total > m) {
      final left = total - m;
      return _t('Resume · $m / $total min ($left min left)', 'متابعة · $m / $total د (متبقٍ $left د)', 'Resume · $m / $total min ($left min left)');
    }
    return _t('Resume · $m min', 'متابعة · $m د', 'Resume · $m min');
  }
  String get download => _t('Download', 'تحميل', 'ڈاؤن لوڈ');
  String get trailer => _t('Trailer', 'إعلان', 'ٹریلر');
  String get trailerUnavailable => _t(
    'YouTube is not available on this device.',
    'يوتيوب غير متاح على هذا الجهاز.',
    'اس ڈیوائس پر یوٹیوب دستیاب نہیں۔',
  );
  String get myList => _t('My List', 'قائمتي', 'میری فہرست');
  String get inMyList => _t('In My List', 'في قائمتي', 'میری فہرست میں');
  String get likedLabel => _t('Liked', 'أعجبني', 'پسند');
  String get reminded => _t('Reminded', 'تم التذكير', 'یاد دلایا');
  String get remindMe => _t('Remind Me', 'ذكّرني', 'یاد دلائیں');
  String get like => _t('Like', 'أعجبني', 'پسند');
  String get dislike => _t('Dislike', 'لم يعجبني', 'ناپسند');
  String get watch => _t('Watch', 'شاهد', 'دیکھیں');
  String get play => _t('Play', 'تشغيل', 'چلائیں');
  String get loading => _t('Loading', 'جارٍ التحميل', 'لوڈ ہو رہا ہے');
  String get closingPlayback => _t('Closing', 'جارٍ الإغلاق', 'بند ہو رہا ہے');
  String get comingSoon => _t('Coming soon', 'قريباً', 'جلد آرہا ہے');
  String get configure => _t('CONFIGURE', 'تهيئة', 'ترتیب دیں');
  String get manage => _t('Manage', 'إدارة', 'منتظم');
  String get skip => _t('Skip', 'تخطي', 'چھوڑیں');
  String get orDivider => _t('OR', 'أو', 'یا');
  String get active => _t('ACTIVE', 'نشط', 'فعال');
  String get personal => _t('PERSONAL', 'شخصي', 'ذاتی');
  String get live => _t('LIVE', 'مباشر', 'لائیو');
  String get signOutShort => _t('Sign out', 'تسجيل الخروج', 'سائن آؤٹ');
  String get enabled => _t('Enabled', 'مفعّل', 'فعال');
  String get off => _t('Off', 'إيقاف', 'بند');

  // ── Auth / onboarding ────────────────────────────────────────────
  String get signIn => _t('Sign In', 'تسجيل الدخول', 'سائن اِن');
  String get welcomeBack => _t('Welcome Back', 'مرحباً بعودتك', 'خوش آمدید');
  String get signInContinue => _t(
    'Sign in to continue watching.',
    'سجّل الدخول لمتابعة المشاهدة.',
    'دیکھنا جاری رکھنے کے لیے سائن اِن کریں۔',
  );
  String get rememberMe => _t('Remember me', 'تذكرني', 'مجھے یاد رکھیں');
  String get username => _t('Username', 'اسم المستخدم', 'صارف نام');
  // Task #143 #3: no "Email" wording on login.
  String get emailOrUsername =>
      _t('USERNAME', 'اسم المستخدم', 'صارف نام');
  String get password => _t('Password', 'كلمة المرور', 'پاس ورڈ');
  String get passwordLabel => _t('PASSWORD', 'كلمة المرور', 'پاس ورڈ');
  String get emailHint => _t(
    'e.g. my_user',
    'مثال: app_user',
    'مثال: app_user',
  );
  String get activateTv => pcWording
      ? _t('Sign in with your phone', 'تسجيل الدخول بهاتفك',
          'اپنے فون سے سائن اِن کریں')
      : _t(
    'Activate TV or Another Device',
    'تفعيل التلفزيون أو جهاز آخر',
    'ٹی وی یا دوسرا آلہ فعال کریں',
  );
  String get tvActivationSnack => pcWording
      ? _t('Enter the 6-digit code in the ${AppBrand.name} app on your phone',
          'أدخل الرمز المكوّن من 6 أرقام في تطبيق ${AppBrand.name} على هاتفك',
          'اپنے فون پر ${AppBrand.name} ایپ میں 6 ہندسوں کا کوڈ درج کریں')
      : _t(
    'TV activation: enter 6-digit PIN on your TV',
    'تفعيل التلفزيون: أدخل رمز PIN المكوّن من 6 أرقام على التلفزيون',
    'ٹی وی فعال کریں: اپنی TV پر 6 ہندسوں کا PIN درج کریں',
  );
  String get tvCodeHint => pcWording
      ? _t('Using a code? Enter your 6-digit activation PIN',
          'تستخدم رمزًا؟ أدخل رمز التفعيل المكوّن من 6 أرقام',
          'کوڈ استعمال کر رہے ہیں؟ 6 ہندسوں کا پن درج کریں')
      : _t(
    'Using a TV code? Enter your 6-digit activation PIN',
    'تستخدم رمز تلفزيون؟ أدخل رمز التفعيل المكوّن من 6 أرقام',
    'ٹی وی کوڈ استعمال کر رہے ہیں؟ 6 ہندسوں کا پن درج کریں',
  );
  String get needHelpSub => _t(
    'Need help signing in?',
    'تحتاج مساعدة في تسجيل الدخول؟',
    'سائن اِن میں مدد چاہیے؟',
  );
  String get loginHelpTitle =>
      _t('Sign-in help', 'مساعدة تسجيل الدخول', 'سائن اِن مدد');
  // Login help form (client: no "Email" wording on login / help).
  String get helpContactLabel => _t('Phone / WhatsApp', 'الهاتف / واتساب', 'Phone / WhatsApp');
  String get helpDescribeIssue => _t('Describe the issue', 'صف المشكلة', 'Describe the issue');
  String get helpSubmitRequest => _t('Submit request', 'إرسال الطلب', 'Submit request');
  String get helpContactAndIssueMissing => _t(
    'Enter your phone number and your issue.',
    'أدخل رقم هاتفك ووصف المشكلة.',
    'Enter your phone number and your issue.',
  );
  String get helpRequestSent => _t(
    'Request sent. Our team will contact you soon.',
    'تم إرسال طلبك. سيتواصل معك فريقنا قريبًا.',
    'Request sent. Our team will contact you soon.',
  );
  String get helpSavedOnDevice => _t(
    'Could not reach our server. Your request is saved on this device; please try again later.',
    'تعذّر الوصول إلى الخادم. تم حفظ طلبك على هذا الجهاز، يرجى المحاولة لاحقًا.',
    'Could not reach our server. Your request is saved on this device; please try again later.',
  );

  String get loginHelpBody => _t(
    'Sign in with the username and password of the account you already have with your service provider. '
        '${AppBrand.name} is a media player only. It does not provide or sell subscriptions.\n\n'
        '• Tap the eye icon to show or hide your password.\n'
        '• Keep “Remember me” on to stay signed in on this device.\n'
        '• Switch language anytime from the welcome screen or Settings.\n\n'
        'If your username or password does not work, check them with your service provider. For a problem with the app itself, send us a request below.',
    'سجّل الدخول باسم المستخدم وكلمة المرور الخاصين بحسابك لدى مزوّد الخدمة. '
        '${AppBrand.name} مشغّل وسائط فقط. لا يقدّم الاشتراكات ولا يبيعها.\n\n'
        '• اضغط أيقونة العين لإظهار أو إخفاء كلمة المرور.\n'
        '• أبقِ «تذكرني» مفعّلاً للبقاء مسجّل الدخول على هذا الجهاز.\n'
        '• غيّر اللغة في أي وقت من شاشة الترحيب أو الإعدادات.\n\n'
        'إذا لم يعمل اسم المستخدم أو كلمة المرور، فتحقّق منهما مع مزوّد الخدمة. ولأي مشكلة في التطبيق نفسه، أرسل لنا طلبًا بالأسفل.',
    'اپنے سروس فراہم کنندہ کے اکاؤنٹ کا یوزرنیم اور پاس ورڈ استعمال کریں۔ '
        '${AppBrand.name} صرف میڈیا پلیئر ہے۔ یہ سبسکرپشن نہ فراہم کرتا ہے نہ بیچتا ہے۔\n\n'
        '• پاس ورڈ دکھانے/چھپانے کے لیے آنکھ کا آئیکن دبائیں۔\n'
        '• اس ڈیوائس پر سائن اِن رہنے کے لیے «مجھے یاد رکھیں» آن رکھیں۔\n'
        '• زبان کسی بھی وقت خوش آمدید اسکرین یا سیٹنگز سے بدلیں۔\n\n'
        'اگر یوزرنیم یا پاس ورڈ کام نہ کرے تو اپنے سروس فراہم کنندہ سے چیک کریں۔ ایپ کے کسی مسئلے کے لیے نیچے درخواست بھیجیں۔',
  );
  String get sslBadge =>
      _t('Encrypted connection', 'اتصال مشفّر', 'محفوظ کنکشن');
  String get rightsReserved => _t(
    '© 2026 ${AppBrand.name}. All Rights Reserved.',
    '© 2026 ${AppBrand.name}. جميع الحقوق محفوظة.',
    '© 2026 ${AppBrand.name}. جملہ حقوق محفوظ ہیں۔',
  );
  String get termsOfUse =>
      _t('Terms of Use', 'شروط الاستخدام', 'استعمال کی شرائط');
  String get termsOfService =>
      _t('Terms of Service', 'شروط الخدمة', 'سروس کی شرائط');
  String get privacyPolicy =>
      _t('Privacy Policy', 'سياسة الخصوصية', 'رازداری کی پالیسی');
  String get whosWatching =>
      _t("Who's watching?", 'من يشاهد؟', 'کون دیکھ رہا ہے؟');
  String get chooseProfile => _t(
    'Choose a profile to continue',
    'اختر ملفاً للمتابعة',
    'جاری رکھنے کے لیے پروفائل منتخب کریں',
  );
  String get switchProfileManage => _t(
    'Switch profile · Manage',
    'تبديل الملف · إدارة',
    'پروفائل بدلیں · منتظم',
  );
  String get kidsExperience =>
      _t('Kids experience', 'تجربة الأطفال', 'بچوں کا تجربہ');
  // No full stops in RTL: the glowing stop showed as a lone blue dot beside
  // "بدون تنازل" (client 19 Oct).
  String get welcomeHeadline => _t(
    'Premium media.\nZero compromise.',
    'ترفيه فاخر\nبدون تنازل',
    'پریمیم میڈیا\nبغیر سمجھوتہ',
  );
  String get welcomeBody => _t(
    'A media player for the movies, series and live channels of your service provider, in up to 4K.',
    'مشغّل وسائط لأفلام ومسلسلات وقنوات مزوّد خدمتك، بجودة تصل إلى 4K.',
    'آپ کے سروس پرووائیڈر کی فلموں، سیریز اور لائیو چینلز کے لیے میڈیا پلیئر، 4K تک۔',
  );
  String get accountFromPanel => _t(
    'Sign in with the account you already have with your service provider. Contact your provider if you need a password reset.',
    'سجّل الدخول بالحساب الموجود لديك لدى مزوّد خدمتك. تواصل مع المزوّد لإعادة تعيين كلمة المرور.',
    'اپنے سروس پرووائیڈر کے موجودہ اکاؤنٹ سے سائن ان کریں۔ پاس ورڈ ری سیٹ کے لیے اپنے پرووائیڈر سے رابطہ کریں۔',
  );

  // ── Home / sections ──────────────────────────────────────────────
  String get continueWatching =>
      _t('Continue Watching', 'متابعة المشاهدة', 'جاری دیکھیں');
  // Client 10 Nov: remove a title from Continue Watching (LG wording).
  String get removeFromContinue => _t(
        'Remove from Continue Watching',
        'إزالة من متابعة المشاهدة',
        'جاری دیکھیں سے ہٹائیں',
      );
  /// TV hint on a focused Continue Watching card (client 12 Nov: a
  /// remote-friendly way to remove, as on LG).
  String get holdOkToRemove => _t(
        'Hold OK to remove',
        'اضغط مطولاً على موافق للإزالة',
        'ہٹانے کے لیے OK دبائے رکھیں',
      );
  String get removeFromContinueFailed => _t(
        'Could not remove. Please try again.',
        'تعذّرت الإزالة. حاول مرة أخرى.',
        'ہٹایا نہیں جا سکا۔ دوبارہ کوشش کریں۔',
      );
  String get history => _t('History', 'السجل', 'تاریخ');
  // Kids home (client 21 Oct): weekly random selection, Top 10 design.
  String get top10KidsSeries =>
      _t('Top 10 Kids Series', 'أفضل 10 مسلسلات أطفال', 'ٹاپ 10 بچوں کی سیریز');
  String get top10KidsMovies =>
      _t('Top 10 Kids Movies', 'أفضل 10 أفلام أطفال', 'ٹاپ 10 بچوں کی فلمیں');
  String get watchLater =>
      _t('Watch later', 'المشاهدة لاحقاً', 'بعد میں دیکھیں');
  String get libraryHub => _t('My Library', 'مكتبتي', 'میری لائبریری');
  String get libraryHubHint => _t(
    'Watch later, history & more',
    'المشاهدة لاحقاً والسجل والمزيد',
    'بعد میں دیکھیں، تاریخ اور مزید',
  );
  String get historyEmpty => _t(
    'No watch history yet.',
    'لا سجل مشاهدة بعد.',
    'ابھی کوئی واچ ہسٹری نہیں۔',
  );
  String get continueEmpty => _t(
    'Nothing to continue right now.',
    'لا شيء للمتابعة حالياً.',
    'ابھی جاری رکھنے کے لیے کچھ نہیں۔',
  );
  String get remindersEmpty =>
      _t('No reminders yet.', 'لا تذكيرات بعد.', 'ابھی کوئی یاددہانی نہیں۔');
  String get screenRecordBlockTitle => _t(
    'Screen recording blocked',
    'تسجيل الشاشة محظور',
    'اسکرین ریکارڈنگ بلاک ہے',
  );
  String get screenRecordBlockMessage => _t(
    '${AppBrand.name} does not allow screen recording. Stop recording to keep watching.',
    '${AppBrand.name} لا يسمح بتسجيل الشاشة. أوقف التسجيل لمتابعة المشاهدة.',
    '${AppBrand.name} اسکرین ریکارڈنگ کی اجازت نہیں دیتا۔ دیکھنا جاری رکھنے کے لیے ریکارڈنگ بند کریں۔',
  );
  String get screenRecordProtectTesting => _t(
    'Screen protection',
    'حماية الشاشة',
    'اسکرین تحفظ',
  );
  String get screenRecordProtectTestingHint => _t(
    'Blocks screenshots and screen recording. On iPhone the screen turns black while it is recorded or mirrored.',
    'يمنع لقطات الشاشة وتسجيلها. على iPhone تصبح الشاشة سوداء أثناء التسجيل أو النسخ.',
    'اسکرین شاٹ اور ریکارڈنگ بلاک کرتا ہے۔ iPhone پر ریکارڈنگ یا مررنگ کے دوران اسکرین سیاہ ہو جاتی ہے۔',
  );
  // Client 2 Nov #4: newest titles across the catalog (was "Top Movies").
  String get weeklyMoviePicks =>
      _t('Recently Added', 'أضيف حديثاً', 'حال ہی میں شامل');
  String get weeklySeriesPicks => _t(
        'Recently Added Series',
        'مسلسلات أضيفت حديثاً',
        'حال ہی میں شامل سیریز',
      );
  /// Ranked Home rows, as on LG (client 5 Nov: "Top 10 disappeared").
  String get top10Movies => _t('Top 10 Movies', 'أفضل 10 أفلام', 'ٹاپ 10 فلمیں');
  String get top10Series => _t('Top 10 Series', 'أفضل 10 مسلسلات', 'ٹاپ 10 سیریز');
  String get top10 => _t(
    'Top 10 in Your Region Today',
    'أفضل 10 في منطقتك اليوم',
    'آج آپ کے علاقے میں ٹاپ 10',
  );
  String get moreLikeThis =>
      _t('More Like This', 'المزيد مثل هذا', 'اس جیسے مزید');
  String get exclusivePremiere => _t(
    '${AppBrand.name.toUpperCase()} EXCLUSIVE PREMIERE',
    'عرض حصري من ${AppBrand.name}',
    '${AppBrand.name} خصوصی پریمیئر',
  );
  String inAppTop10(int n) => _t(
    'IN ${AppBrand.name.toUpperCase()} TOP 10 #$n',
    'ضمن أفضل 10 في ${AppBrand.name} #$n',
    '${AppBrand.name} ٹاپ 10 میں #$n',
  );
  String get myAccount => _t('My ${AppBrand.name}', 'ماي كرنش', 'مائی کرنچ');
  String get myAccountHint => _t(
    'Continue Watching, reminders, liked titles & profile',
    'متابعة المشاهدة والتذكيرات والعناوين المعجبة والملف',
    'جاری دیکھیں، یاددہانیاں، پسندیدہ اور پروفائل',
  );
  String get titlesYouLiked =>
      _t('Titles You Liked', 'عناوين أعجبتك', 'پسندیدہ عنوانات');
  String get account => _t('Account', 'الحساب', 'اکاؤنٹ');
  String get parentalControls =>
      _t('Parental controls', 'الرقابة الأبوية', 'والدین کنٹرول');
  String get devices => _t('Devices', 'الأجهزة', 'آلات');
  String get subscription => _t('Package', 'الباقة', 'پیکج');

  // ── Search hints ─────────────────────────────────────────────────
  String get searchMovies =>
      _t('Search movies…', 'ابحث عن أفلام…', 'فلمیں تلاش کریں…');
  String get searchSeries =>
      _t('Search series…', 'ابحث عن مسلسلات…', 'سیریز تلاش کریں…');
  String get searchLive => _t(
    'Search live channels…',
    'ابحث عن قنوات مباشرة…',
    'لائیو چینلز تلاش کریں…',
  );
  String get searchSports => _t(
    'Search your sports channels…',
    'ابحث عن قنوات الرياضة…',
    'سپورٹس چینلز تلاش کریں…',
  );
  String searchGlobal({required bool sportsOn}) => sportsOn
      ? _t(
          'Search movies, series, live, and sports…',
          'ابحث عن أفلام ومسلسلات وبث ورياضة…',
          'فلمیں، سیریز، لائیو اور سپورٹس تلاش کریں…',
        )
      : _t(
          'Search movies, series, and live…',
          'ابحث عن أفلام ومسلسلات وبث مباشر…',
          'فلمیں، سیریز اور لائیو تلاش کریں…',
        );

  String get sportsChannels =>
      _t('Sports channels', 'قنوات الرياضة', 'سپورٹس چینلز');
  String get couldNotLoad =>
      _t('Could not load', 'تعذّر التحميل', 'لوڈ نہیں ہو سکا');
  String get contentUpdateTitle => _t(
    'New content available',
    'يتوفر محتوى جديد',
    'نیا مواد دستیاب ہے',
  );
  String get contentUpdateBody => _t(
    'Channels, movies or series were updated in your package.',
    'تم تحديث القنوات أو الأفلام أو المسلسلات في باقتك.',
    'آپ کے پیکج میں چینلز، فلمیں یا سیریز اپ ڈیٹ ہوئی ہیں۔',
  );
  /// iPhone Picture-in-Picture button (client 5 Nov).
  String get pictureInPicture => _t('Picture in picture', 'صورة داخل صورة', 'تصویر میں تصویر');
  String get pipUnavailable => _t(
    'Picture in picture is not available for this video.',
    'ميزة صورة داخل صورة غير متاحة لهذا الفيديو.',
    'اس ویڈیو کے لیے تصویر میں تصویر دستیاب نہیں ہے۔',
  );
  /// Manual refresh (client 5 Nov: a "Refresh Package Content" option).
  String get refreshContent => _t('Refresh content', 'تحديث المحتوى', 'مواد ریفریش کریں');
  String get refreshContentHint => _t(
    'Load the newest movies, series and channels of your package',
    'تحميل أحدث الأفلام والمسلسلات والقنوات في باقتك',
    'اپنے پیکج کی تازہ فلمیں، سیریز اور چینلز لوڈ کریں',
  );
  String get refreshContentDone => _t('Content refreshed', 'تم تحديث المحتوى', 'مواد ریفریش ہو گئے');
  String get contentUpdateRefresh => _t('Refresh', 'تحديث', 'ریفریش');
  String get contentUpdateLater => _t('Later', 'لاحقاً', 'بعد میں');
  String get packageLoadFailed => _t(
    'This package could not be loaded.',
    'تعذّر تحميل هذه الباقة.',
    'یہ پیکج لوڈ نہیں ہو سکا۔',
  );
  String get noChannelsInPackage => _t(
    'No channels in this package.',
    'لا توجد قنوات في هذه الباقة.',
    'اس پیکج میں کوئی چینل نہیں۔',
  );
  String liveCount(int n) => _t('LIVE ($n)', 'مباشر ($n)', 'لائیو ($n)');
  String get kidsProfileOpenHub => _t(
    'Kids profile · open Kids hub',
    'ملف أطفال · افتح قسم الأطفال',
    'بچوں کا پروفائل · بچوں کا ہب کھولیں',
  );
  String get noLiveChannels => _t(
    'No live channels right now.',
    'لا توجد قنوات مباشرة حالياً.',
    'اس وقت کوئی لائیو چینل نہیں۔',
  );
  String get reminders => _t('Reminders', 'التذكيرات', 'یاددہانیاں');
  String get downloads => _t('Downloads', 'التنزيلات', 'ڈاؤن لوڈز');
  String get downloadsComingSoon =>
      _t('Downloads coming soon', 'التنزيلات قريباً', 'ڈاؤن لوڈز جلد آرہے ہیں');
  String get clipsComingSoon =>
      _t('Clips coming soon', 'المقاطع قريباً', 'کلپس جلد آرہے ہیں');
  String get clipsComingSoonHint => _t(
    'Short previews will open here in a later update.',
    'ستُفتح المعاينات القصيرة هنا في تحديث لاحق.',
    'مختصر پری ویوز بعد کے اپ ڈیٹ میں یہاں کھلیں گے۔',
  );
  String get downloadsComingSoonHint => _t(
    'Titles will save inside the ${AppBrand.name} app (private app storage) — not to your phone gallery or shared Downloads folder. DRM packaging APIs are required first.',
    'ستُحفظ العناوين داخل تطبيق ${AppBrand.name.toUpperCase()} (تخزين خاص بالتطبيق) — وليس في معرض الهاتف أو مجلد التنزيلات المشترك. يلزم أولاً ربط واجهات تغليف DRM.',
    'عنوانات ${AppBrand.name} ایپ کے اندر محفوظ ہوں گی (پرائیویٹ ایپ سٹوریج) — فون گیلری یا مشترکہ ڈاؤن لوڈز فولڈر میں نہیں۔ پہلے DRM پیکجنگ APIs درکار ہیں۔',
  );

  String get signOutConfirmTitle =>
      _t('Sign out?', 'تسجيل الخروج؟', 'سائن آؤٹ؟');
  String get signOutConfirmMessage => _t(
    'This removes your panels and signs you out on this device. You will start again at "Choose your panel".',
    'سيؤدي هذا إلى حذف لوحاتك وتسجيل خروجك على هذا الجهاز. ستبدأ من جديد من "اختر لوحتك".',
    'This removes your panels and signs you out on this device. You will start again at "Choose your panel".',
  );
  String get offlineDownloadsSoon => _t(
    'Offline saves coming soon',
    'الحفظ دون اتصال قريباً',
    'آف لائن محفوظ جلد آرہا ہے',
  );
  String get badgeSoon => _t('SOON', 'قريباً', 'جلد');
  String get listEmptyTitle => _t(
    'Your List is Currently Empty',
    'قائمتك فارغة حالياً',
    'آپ کی فہرست خالی ہے',
  );
  String get listEmptySubtitle => _t(
    'Save movies, series and live events to watch later.',
    'احفظ أفلاماً ومسلسلات وبثاً لمشاهدتها لاحقاً.',
    'بعد میں دیکھنے کے لیے فلمیں، سیریز اور لائیو محفوظ کریں۔',
  );
  String get exploreTrending =>
      _t('Explore Trending', 'استكشف الرائج', 'ٹرینڈنگ دیکھیں');
  String itemsSaved(int n) =>
      _t('$n Items Saved', '$n عناصر محفوظة', '$n آئٹمز محفوظ');
  String get savedVipHint => _t(
    '★ Saved titles sync to your profile  •  VIP',
    '★ العناوين المحفوظة تتزامن مع ملفك  •  VIP',
    '★ محفوظ عنوانات پروفائل سے ہم آہنگ  •  VIP',
  );
  String get remove => _t('Remove', 'إزالة', 'ہٹائیں');
  String get add => _t('Add', 'إضافة', 'شامل کریں');
  String get liveTvLabel => _t('LIVE TV', 'بث مباشر', 'لائیو ٹی وی');
  String get moviesLabel => _t('MOVIES', 'أفلام', 'فلمیں');
  String get seriesLabel => _t('SERIES', 'مسلسلات', 'سیریز');

  // ── Settings sections ────────────────────────────────────────────
  String get language => _t('Language', 'اللغة', 'زبان');
  String get languageHint => _t(
    'App UI language. Content audio/subs remain selectable in player.',
    'لغة واجهة التطبيق. صوت الترجمة يبقى اختياراً في المشغّل.',
    'ایپ کی زبان۔ مواد کی آڈیو/سب ٹائٹلز پلیئر میں الگ منتخب ہوں گی۔',
  );
  String get about =>
      _t('About ${AppBrand.name}', 'حول ${AppBrand.name}', '${AppBrand.name} کے بارے میں');
  String get notifications => _t('Notifications', 'الإشعارات', 'اطلاعات');
  String get noNotificationsYet => _t(
    'No messages yet',
    'لا رسائل بعد',
    'ابھی کوئی پیغام نہیں',
  );
  String get markAllRead => _t(
    'Mark all read',
    'تمييز الكل كمقروء',
    'سب پڑھے ہوئے نشان زد کریں',
  );
  String get couldNotLoadNotifications => _t(
    'Could not load notifications',
    'تعذّر تحميل الإشعارات',
    'اطلاعات لوڈ نہیں ہو سکیں',
  );
  String get updateAvailableBanner => pcWording
      ? _t('A new app update is available', 'يتوفر تحديث جديد للتطبيق',
          'ایپ کا نیا اپڈیٹ دستیاب ہے')
      : _t(
    'A new TV app update is available',
    'يتوفر تحديث جديد لتطبيق التلفزيون',
    'TV ایپ کا نیا اپڈیٹ دستیاب ہے',
  );
  String get parental =>
      _t('Parental Controls', 'الرقابة الأبوية', 'والدین کنٹرول');
  String get signOut => _t(
    'Sign Out of ${AppBrand.name}',
    'تسجيل الخروج من ${AppBrand.name}',
    '${AppBrand.name} سے سائن آؤٹ',
  );
  String get application => _t('APPLICATION', 'التطبيق', 'ایپلیکیشن');
  String get support => _t('SUPPORT', 'الدعم', 'سپورٹ');
  String get sectionAccount => _t('ACCOUNT', 'الحساب', 'اکاؤنٹ');
  String get sectionPlayback => _t('PLAYBACK', 'التشغيل', 'پلے بیک');
  String get sectionLookSound =>
      _t('LOOK & SOUND', 'المظهر والصوت', 'نظر و آواز');
  String get sectionPersonalization =>
      _t('PERSONALIZATION', 'التخصيص', 'ذاتی سازی');
  String get sectionExtras => _t('EXTRAS', 'إضافات', 'اضافی');
  String get sectionLabTesting =>
      _t('LAB / TESTING', 'المختبر / الاختبار', 'لیب / ٹیسٹنگ');
  String get splashPreview =>
      _t('Splash preview', 'معاينة الشاشة الافتتاحية', 'اسپلش پیش نظارہ');
  String get splashPreviewHint => _t(
    'Preview splash, then return',
    'معاينة الشاشة ثم العودة',
    'اسپلش دیکھیں، پھر واپس',
  );

  String get profiles => _t('Profiles', 'الملفات', 'پروفائلز');
  String get subscriptionPackageSubtitle => _t(
    'Your account details from your service provider',
    'تفاصيل حسابك لدى مزوّد الخدمة',
    'آپ کے سروس فراہم کنندہ کے اکاؤنٹ کی تفصیل',
  );
  String get subscriptionPackage =>
      _t('Account / Package', 'الحساب / الباقة', 'اکاؤنٹ / پیکج');
  String get devicesSessions =>
      _t('Devices & Sessions', 'الأجهزة والجلسات', 'آلات اور سیشنز');
  String get security => _t('Security', 'الأمان', 'سیکیورٹی');
  String get playbackPrefs =>
      _t('Playback Preferences', 'تفضيلات التشغيل', 'پلے بیک ترجیحات');
  /// M2 Usman: Settings stream session from GET /playback/lease.
  String get streamSession =>
      _t('Stream session', 'جلسة البث', 'اسٹریم سیشن');
  String streamSessionStatus(String status, String label) =>
      _t('$status · $label', '$status · $label', '$status · $label');
  String get streamingOnThisDevice => _t(
    'Streaming on this device',
    'البث على هذا الجهاز',
    'اس آلہ پر سٹریمنگ',
  );
  String get streamingOnOtherDevice => _t(
    'Streaming on another device',
    'البث على جهاز آخر',
    'دوسرے آلہ پر سٹریمنگ',
  );
  String get streamSessionIdle => _t(
    'No active stream',
    'لا يوجد بث نشط',
    'کوئی فعال اسٹریم نہیں',
  );
  String get audioSubtitles =>
      _t('Audio & Subtitles', 'الصوت والترجمة', 'آڈیو اور سب ٹائٹلز');
  String get autoplay => _t('Autoplay', 'تشغيل تلقائي', 'آٹو پلے');
  // Client 23 Oct #12: "Speed Test" only, on every platform.
  String get connectionDiagnostic =>
      _t('Speed Test', 'اختبار السرعة', 'Speed Test');
  String get connectionDiagnosticHint => _t(
    'Measures how fast ${AppBrand.name} servers respond on this network.',
    'يقيس سرعة استجابة خوادم ${AppBrand.name} على هذه الشبكة.',
    'اس نیٹ ورک پر ${AppBrand.name} سرورز کی رفتار ناپتا ہے۔',
  );
  String get diagApiConfig =>
      _t('App config', 'إعدادات التطبيق', 'ایپ کنفگ');
  String get diagApiAccount =>
      _t('Account', 'الحساب', 'اکاؤنٹ');
  String get diagApiCatalog =>
      _t('Catalog', 'الكتالوج', 'کیٹلاگ');
  String get diagApproxSpeed =>
      _t('Approx. transfer', 'تقريب سرعة النقل', 'تقریبی منتقلی');
  String get diagCheckedAt =>
      _t('Checked at', 'وقت الفحص', 'چیک وقت');
  String get diagRunAgain =>
      _t('Run again', 'أعد الفحص', 'دوبارہ چلائیں');
  String get diagUnavailable =>
      _t('Unavailable', 'غير متاح', 'دستیاب نہیں');

  String get appearanceThemes =>
      _t('Appearance & Themes', 'المظهر والسمات', 'ظاہری شکل اور تھیمز');
  String get appliesAcross => _t(
    'Applies across the app',
    'يُطبَّق على التطبيق بالكامل',
    'پوری ایپ پر لاگو',
  );
  String get uiSounds => _t('UI sounds', 'أصوات الواجهة', 'UI آوازیں');
  String get uiSoundsHint => _t(
    'Soft click when tapping options',
    'نقرة خفيفة عند الضغط على الخيارات',
    'آپشن دبانے پر نرم کلک',
  );
  String get personalHub => _t('Personal hub', 'مساحتك الشخصية', 'ذاتی ہب');
  String get savedTitles =>
      _t('Saved titles', 'عناوين محفوظة', 'محفوظ عنوانات');
  String get trendingComing => _t(
    'Newest additions and this week\'s picks',
    'أحدث الإضافات واختيارات الأسبوع',
    'تازہ ترین اضافے اور اس ہفتے کے انتخاب',
  );
  String get loadFailed => _t(
    'Could not load this list. Check the connection and retry.',
    'تعذر تحميل هذه القائمة. تحقق من الاتصال وأعد المحاولة.',
    'یہ فہرست لوڈ نہیں ہو سکی۔ کنکشن چیک کریں اور دوبارہ کوشش کریں۔',
  );
  String get newMovies =>
      _t('New Movies', 'أفلام جديدة', 'نئی فلمیں');
  String get newSeries =>
      _t('New Series', 'مسلسلات جديدة', 'نئی سیریز');
  String get familyTitles =>
      _t('Family titles', 'عناوين عائلية', 'خاندانی عنوانات');
  String get customizeHome =>
      _t('Customize Home', 'تخصيص الرئيسية', 'ہوم حسب ضرورت');
  String get verticalTrailers =>
      _t('Vertical trailer feed', 'مقاطع إعلانية عمودية', 'عمودی ٹریلر فیڈ');
  String get helpSupport =>
      _t('Help & Support', 'المساعدة والدعم', 'مدد اور سپورٹ');
  String get passwordMfa =>
      _t('Password & MFA', 'كلمة المرور والمصادقة', 'پاس ورڈ اور MFA');
  String get mfaOn => _t('MFA on', 'المصادقة مفعّلة', 'MFA آن');
  String get pinSet => _t('PIN Set', 'رمز PIN مضبوط', 'PIN سیٹ');
  String get signedInVia => _t(
    'Signed in.',
    'تم تسجيل الدخول.',
    'سائن اِن ہو گیا۔',
  );

  String profilesActive(int n) => _t('$n Active', 'نشط: $n', 'فعال: $n');
  String profilesOfLimitActive(int count, {int max = 5}) => _t(
    '$count of $max profiles active',
    '$count من $max ملفات نشطة',
    '$max میں سے $count پروفائلز فعال',
  );
  String get manageProfiles =>
      _t('Manage Profiles', 'إدارة الملفات', 'پروفائلز کا انتظام');
  String get profileActive => _t('Active', 'نشط', 'فعال');
  String get pinProtected =>
      _t('PIN protected', 'محمي برمز PIN', 'PIN سے محفوظ');
  String get addProfile =>
      _t('Add Profile', 'إضافة ملف شخصي', 'پروفائل شامل کریں');
  String get profileName => _t('Profile name', 'اسم الملف', 'پروفائل کا نام');
  String get kidsProfile => _t('Kids profile', 'ملف أطفال', 'بچوں کا پروفائل');
  String get createProfile =>
      _t('Create Profile', 'إنشاء ملف', 'پروفائل بنائیں');

  String devicesOfLimit(int used, int limit, int sessions) => _t(
    '$used of $limit · $sessions sessions',
    '$used/$limit أجهزة · $sessions جلسات',
    '$used/$limit آلات · $sessions سیشنز',
  );
  String get devicesBadge => _t('DEVICES', 'الأجهزة', 'آلات');
  String devicesCount(int n) => _t('$n devices', '$n جهاز', '$n آلات');
  String devicesLimitHint(int limit) => _t(
    'Limit $limit. Manage sessions under Settings → Security → Sessions.',
    'الحد $limit. أدر الجلسات من الإعدادات ← الأمان ← الجلسات.',
    'حد $limit۔ سیشنز ترتیبات ← سیکیورٹی ← Sessions سے منتظم کریں۔',
  );
  String get noDevicesYet => _t(
    'No devices registered yet.',
    'لا أجهزة مسجّلة بعد.',
    'ابھی کوئی آلہ رجسٹر نہیں۔',
  );
  String get thisDevice => _t('THIS DEVICE', 'هذا الجهاز', 'یہ آلہ');
  /// Device has a hardware-bound sign-in key (Keystore / Secure Enclave).
  String get hardwareKey => _t('HARDWARE KEY', 'مفتاح أمان في الجهاز', 'ہارڈویئر کلید');
  String get rename => _t('Rename', 'إعادة تسمية', 'نام بدلیں');
  String get devicesRefreshed =>
      _t('Devices refreshed', 'تم تحديث الأجهزة', 'آلات تازہ ہو گئیں');
  String get couldNotLoadDevices => _t(
    'Could not load devices',
    'تعذّر تحميل الأجهزة',
    'آلات لوڈ نہیں ہو سکیں',
  );
  String get renameDevice =>
      _t('Rename device', 'إعادة تسمية الجهاز', 'آلہ کا نام بدلیں');
  String get deviceName => _t('Device name', 'اسم الجهاز', 'آلہ کا نام');
  String get decoderLimited => _t(
    'This device is struggling to decode this 4K video. Open a lower-resolution version if available.',
    'يواجه هذا الجهاز صعوبة في فك ترميز فيديو 4K هذا. افتح نسخة بدقة أقل إن كانت متوفرة.',
    'اس ڈیوائس پر یہ 4K ویڈیو روانی سے نہیں چل رہی۔ اگر دستیاب ہو تو کم ریزولوشن والا ورژن کھولیں.',
  );
  String get playbackBack => _t('Back', 'رجوع', 'واپس');
  String get resumeUnconfirmed => _t(
    'Could not confirm the saved playback position. Your previous bookmark has been kept; try seeking manually.',
    'تعذر تأكيد موضع المشاهدة المحفوظ. تم الاحتفاظ بالموضع السابق؛ حاول الانتقال يدويًا.',
    'محفوظ مقام کی تصدیق نہیں ہو سکی۔ پچھلا مقام محفوظ ہے؛ ویڈیو میں خود آگے جائیں۔',
  );
  String get cancel => _t('Cancel', 'إلغاء', 'منسوخ');
  String get save => _t('Save', 'حفظ', 'محفوظ');
  /// Package order: Back after a change asks first (as on LG 6.1.24).
  String get saveOrderTitle => _t('Save changes?', 'حفظ الترتيب؟', 'تبدیلیاں محفوظ کریں؟');
  String get saveOrderBody => _t(
    'You changed the order of the packages.',
    'غيّرت ترتيب الباقات.',
    'آپ نے پیکجز کی ترتیب بدلی ہے۔',
  );
  String get discard => _t('Discard', 'تجاهل', 'رد کریں');
  String get downloadLimitReached => _t(
    'Your download storage is full. Remove a download to free space.',
    'مساحة التنزيلات ممتلئة. احذف تنزيلاً لتوفير مساحة.',
    'ڈاؤن لوڈ کی جگہ بھر گئی ہے۔ جگہ خالی کرنے کے لیے کوئی ڈاؤن لوڈ حذف کریں۔',
  );
  String get downloadDeviceFull => _t(
    'Not enough free space on this device for this download.',
    'لا توجد مساحة كافية على هذا الجهاز لهذا التنزيل.',
    'اس ڈاؤن لوڈ کے لیے اس ڈیوائس پر کافی جگہ نہیں۔',
  );
  // Client 18 Oct #3: two different limits, labelled so they are not
  // confused. The allowance is the app's; free space is the device's own.
  String downloadQuotaLine(String used, String limit) => _t(
    '${AppBrand.name} download allowance: $used of $limit used (shared by all your devices)',
    'حصة تنزيلات ${AppBrand.name}: $used من $limit مستخدمة (مشتركة بين كل أجهزتك)',
    '${AppBrand.name} ڈاؤن لوڈ حد: $limit میں سے $used استعمال (آپ کے تمام آلات میں مشترک)',
  );
  String get arrangePackages =>
      _t('Arrange packages', 'ترتيب الباقات', 'پیکجز ترتیب دیں');
  String get sortLabel => _t('Sort', 'رتب', 'ترتیب');
  String get speedNormalLabel => _t('Normal', 'عادي', 'نارمل');
  String get arrangePackagesHint => _t(
    'Drag to set the order. Saved for this profile on all your devices.',
    'اسحب لتحديد الترتيب. يُحفظ لهذا الملف الشخصي على جميع أجهزتك.',
    'ترتیب کے لیے گھسیٹیں۔ اس پروفائل کے لیے آپ کے تمام آلات پر محفوظ۔',
  );
  String get resetOrder =>
      _t('Original order', 'الترتيب الأصلي', 'اصل ترتیب');
  String get moveUp => _t('Move up', 'تحريك للأعلى', 'اوپر');
  String get moveDown => _t('Move down', 'تحريك للأسفل', 'نیچے');
  String seriesTitlesCount(int n) =>
      _t('$n series', '$n مسلسل', '$n سیریز');
  String get deviceRenamed =>
      _t('Device renamed', 'تمت إعادة تسمية الجهاز', 'آلہ کا نام بدل گیا');
  String get deviceLabelUpdated => _t(
    'Your device label was updated',
    'تم تحديث اسم جهازك',
    'آپ کے آلہ کا لیبل اپ ڈیٹ ہو گیا',
  );
  String get renameFailed =>
      _t('Rename failed', 'فشلت إعادة التسمية', 'نام بدلنا ناکام');
  String get revokeThisDevice =>
      _t('Revoke this device?', 'إلغاء هذا الجهاز؟', 'یہ آلہ منسوخ کریں؟');
  String revokeDeviceMessage(String name) => _t(
    '"$name" will be removed from your account.',
    'سيُزال «$name» من حسابك.',
    '«$name» آپ کے اکاؤنٹ سے ہٹا دیا جائے گا۔',
  );
  String get revoke => _t('Revoke', 'إلغاء', 'منسوخ');
  String get deviceRevoked =>
      _t('Device revoked', 'تم إلغاء الجهاز', 'آلہ منسوخ ہو گیا');
  String deviceNoLongerLinked(String name) => _t(
    '"$name" is no longer linked to your account.',
    '«$name» لم يعد مرتبطاً بحسابك.',
    '«$name» اب آپ کے اکاؤنٹ سے منسلک نہیں۔',
  );
  String get revokeFailed => _t('Revoke failed', 'فشل الإلغاء', 'منسوخی ناکام');

  String get priorityDevice =>
      _t('Primary phone', 'الهاتف الأساسي', 'مرکزی فون');
  String get setAsPriority => _t(
    'Set as primary phone',
    'تعيين كهاتف أساسي',
    'بطور مرکزی فون سیٹ کریں',
  );
  String get priorityUpdated =>
      _t('Primary phone updated', 'تم تحديث الهاتف الأساسي', 'مرکزی فون اپ ڈیٹ');
  String get priorityUpdateFailed => _t(
    'Could not set primary phone',
    'تعذّر تعيين الهاتف الأساسي',
    'مرکزی فون سیٹ نہیں ہو سکا',
  );
  String get revokeAllDevices =>
      _t('Revoke all devices', 'إلغاء كل الأجهزة', 'تمام آلات منسوخ کریں');
  String get revokeAllDevicesTitle => _t(
    'Revoke all other devices?',
    'إلغاء كل الأجهزة الأخرى؟',
    'دیگر تمام آلات منسوخ کریں؟',
  );
  String get revokeAllDevicesMessage => _t(
    'Every other phone and TV will be signed out and removed. This device stays signed in.',
    'سيتم تسجيل خروج وإزالة كل الهواتف وأجهزة التلفاز الأخرى. يبقى هذا الجهاز متصلاً.',
    'دیگر تمام فون اور TV سائن آؤٹ اور ہٹا دیے جائیں گے۔ یہ آلہ سائن اِن رہے گا۔',
  );
  String get revokeAllDone =>
      _t('Other devices revoked', 'أُلغيت الأجهزة الأخرى', 'دیگر آلات منسوخ');
  String get waitingForApprovalTitle => _t(
    'Waiting for approval',
    'بانتظار الموافقة',
    'منظوری کا انتظار',
  );
  String get waitingForApprovalBody => _t(
    'Approve this sign-in on your primary phone to continue.',
    'وافق على هذا الدخول من هاتفك الأساسي للمتابعة.',
    'جاری رکھنے کے لیے اپنے مرکزی فون سے اس سائن اِن کو منظور کریں۔',
  );
  String get waitingForApprovalLostDevice => _t(
    "I don't have my phone",
    'ليس لدي هاتفي',
    'میرے پاس فون نہیں ہے',
  );
  String get waitingForApprovalClaimHint => _t(
    'If you wiped or lost your primary phone, prove account ownership here to continue on this device.',
    'إذا مسحت هاتفك الأساسي أو فقدته، أثبت ملكية الحساب هنا للمتابعة على هذا الجهاز.',
    'اگر آپ نے مرکزی فون صاف یا گم کر دیا ہے، تو اس آلے پر جاری رکھنے کے لیے اکاؤنٹ کی ملکیت ثابت کریں۔',
  );
  String get waitingForApprovalClaimAction => _t(
    'Continue on this device',
    'المتابعة على هذا الجهاز',
    'اس آلے پر جاری رکھیں',
  );
  String get primaryRecoveryTitle => _t(
    'Recover without primary phone',
    'الاستعادة بدون الهاتف الأساسي',
    'مرکزی فون کے بغیر بازیابی',
  );
  String get primaryRecoveryBody => _t(
    'Enter your account password, then verify with MFA, a recovery code, or email code.',
    'أدخل كلمة مرور حسابك، ثم أكّد عبر MFA أو رمز الاستعادة أو رمز البريد.',
    'اکاؤنٹ پاس ورڈ درج کریں، پھر MFA، ریکوری کوڈ، یا ای میل کوڈ سے تصدیق کریں۔',
  );
  String get primaryRecoveryMethodTotp =>
      _t('Authenticator code', 'رمز المصادقة', 'تصدیقی کوڈ');
  String get primaryRecoveryMethodRecoveryCode =>
      _t('Recovery code', 'رمز الاستعادة', 'ریکوری کوڈ');
  String get primaryRecoveryMethodEmailOtp =>
      _t('Email code', 'رمز البريد', 'ای میل کوڈ');
  String get primaryRecoverySendEmailOtp =>
      _t('Send email code', 'إرسال رمز البريد', 'ای میل کوڈ بھیجیں');
  String get primaryRecoveryComplete =>
      _t('Verify and continue', 'تحقق ومتابعة', 'تصدیق اور جاری');
  String get primaryRecoverySupportHint => _t(
    'No recovery methods on this account. Contact support to clear your primary phone.',
    'لا توجد طرق استعادة لهذا الحساب. تواصل مع الدعم لإزالة هاتفك الأساسي.',
    'اس اکاؤنٹ پر کوئی ریکوری طریقہ نہیں۔ مرکزی فون صاف کرنے کے لیے سپورٹ سے رابطہ کریں۔',
  );
  String get watchHereTakeOver =>
      _t('Watch here', 'المشاهدة هنا', 'یہاں دیکھیں');
  String get keepOtherDevicePlaying =>
      _t('Keep other device', 'الإبقاء على الجهاز الآخر', 'دوسرا آلہ رہنے دیں');
  String playbackHeldByDevice(String name) => _t(
    'Playing on $name',
    'يُشغَّل على $name',
    '$name پر چل رہا ہے',
  );
  String get playbackLeaseHeldTitle => _t(
    'Another device is watching',
    'جهاز آخر يشاهد الآن',
    'دوسرا آلہ دیکھ رہا ہے',
  );
  /// Control Panel stop — neutral title (not "another device").
  String get playbackStoppedByOperatorTitle => _t(
    'Playback stopped by the operator',
    'أوقف المشغّل التشغيل',
    'آپریٹر نے پلے بیک روک دیا',
  );
  String get playbackStoppedByOperatorBody => _t(
    'Streaming was stopped from the control panel. Try again in a moment.',
    'تم إيقاف البث من لوحة التحكم. حاول مرة أخرى بعد لحظات.',
    'کنٹرول پینل سے سٹریمنگ روک دی گئی۔ تھوڑی دیر بعد دوبارہ کوشش کریں۔',
  );
  String get deviceCouldNotBeVerified => _t(
    'This device could not be verified. Sign in again.',
    'تعذّر التحقق من هذا الجهاز. سجّل الدخول مرة أخرى.',
    'اس آلہ کی تصدیق نہیں ہو سکی۔ دوبارہ سائن ان کریں۔',
  );
  String get deviceUnreachableBadge =>
      _t('Unreachable', 'غير متاح', 'ناقابل رسائی');
  String get deviceStaleBadge => _t('Stale', 'قديم', 'پرانا');
  String get priorityRequiredTitle => _t(
    'Primary phone required',
    'يلزم الهاتف الأساسي',
    'مرکزی فون درکار',
  );
  String get priorityRequiredBody => _t(
    'Only your primary phone can approve this. Use recovery if you lost that phone.',
    'هاتفك الأساسي فقط يمكنه الموافقة. استخدم الاستعادة إذا فقدت ذلك الهاتف.',
    'صرف مرکزی فون اس کی منظوری دے سکتا ہے۔ اگر فون گم ہے تو بازیابی استعمال کریں۔',
  );
  String get cannotRevokePrimaryTitle => _t(
    'Cannot remove primary phone',
    'لا يمكن إزالة الهاتف الأساسي',
    'مرکزی فون نہیں ہٹا سکتے',
  );
  String get cannotRevokePrimaryBody => _t(
    'Another device cannot revoke your primary phone. On the primary phone, set a new primary first, then remove the old one. If you lost that phone, sign in elsewhere and use “I don’t have my phone” recovery.',
    'لا يمكن لجهاز آخر إلغاء هاتفك الأساسي. من الهاتف الأساسي عيّن هاتفاً أساسياً جديداً ثم أزل القديم. إذا فقدت الهاتف، سجّل الدخول من جهاز آخر واستخدم استعادة «ليس لدي هاتفي».',
    'دوسرا آلہ مرکزی فون کو ریوووک نہیں کر سکتا۔ مرکزی فون پر پہلے نیا پرائمری سیٹ کریں، پھر پرانا ہٹائیں۔ اگر فون گم ہے تو کہیں اور سائن اِن کر کے «میرے پاس فون نہیں ہے» بازیابی استعمال کریں۔',
  );
  String get cannotRevokeAllWithoutPrimaryTitle => _t(
    'Use primary phone for this',
    'استخدم الهاتف الأساسي لهذا',
    'اس کے لیے مرکزی فون استعمال کریں',
  );
  String get cannotRevokeAllWithoutPrimaryBody => _t(
    'Revoke all would remove your primary phone. Open Devices on the primary phone, or use lost-phone recovery.',
    'إلغاء الكل سيزيل هاتفك الأساسي. افتح الأجهزة من الهاتف الأساسي، أو استخدم استعادة الهاتف المفقود.',
    'سب ریوووک کرنے سے مرکزی فون بھی ہٹ جائے گا۔ مرکزی فون پر آلات کھولیں، یا گم شدہ فون بازیابی استعمال کریں۔',
  );
  String get deviceLimitReachedTitle => _t(
    'Device limit reached',
    'تم بلوغ حد الأجهزة',
    'آلات کی حد پوری',
  );
  String get deviceLimitReachedBody => _t(
    'Remove an unused device, then try again.',
    'أزل جهازاً غير مستخدم ثم أعد المحاولة.',
    'غیر استعمال شدہ آلہ ہٹا کر دوبارہ کوشش کریں۔',
  );
  String get manageDevices =>
      _t('Manage devices', 'إدارة الأجهزة', 'آلات کا انتظام');
  String get loginDeniedTitle =>
      _t('Sign-in denied', 'تم رفض الدخول', 'سائن اِن مسترد');
  String get loginDeniedBody => _t(
    'Your primary phone denied this sign-in.',
    'رفض هاتفك الأساسي هذا الدخول.',
    'آپ کے مرکزی فون نے یہ سائن اِن مسترد کر دیا۔',
  );
  String get newSignInTitle =>
      _t('New sign-in request', 'طلب دخول جديد', 'نیا سائن اِن درخواست');
  String newSignInBody(String name, String platform) => _t(
    'Allow "$name" ($platform) to access your account?',
    'السماح لـ «$name» ($platform) بالوصول إلى حسابك؟',
    'کیا «$name» ($platform) کو آپ کے اکاؤنٹ تک رسائی دیں؟',
  );
  String get allowSignIn => _t('Allow', 'سماح', 'اجازت دیں');
  String get denySignIn => _t('Deny', 'رفض', 'مسترد');
  String get signInRequestsTitle =>
      _t('Sign-in requests', 'طلبات تسجيل الدخول', 'سائن اِن درخواستیں');
  String get signInRequestsSubtitle => _t(
    'Approve a TV or new device',
    'وافق على تلفاز أو جهاز جديد',
    'ٹی وی یا نئے آلے کو اجازت دیں',
  );
  String get signInRequestsHelpTitle =>
      _t('About sign-in requests', 'عن طلبات تسجيل الدخول', 'سائن اِن درخواستوں کے بارے میں');
  String get signInRequestsHelpBody => _t(
    'When a TV or another device signs in with your account, the request appears here on every device where you are signed in. Allow only devices you know. Lost a device? Ask your reseller to remove it.',
    'عندما يسجّل تلفاز أو جهاز آخر الدخول بحسابك، يظهر الطلب هنا على كل جهاز سجّلت الدخول عليه. وافق فقط على الأجهزة التي تعرفها. فقدت جهازًا؟ اطلب من الموزّع حذفه.',
    'جب کوئی ٹی وی یا دوسرا آلہ آپ کے اکاؤنٹ سے سائن اِن کرے تو درخواست ہر اُس آلے پر یہاں نظر آتی ہے جہاں آپ سائن اِن ہیں۔ صرف اپنے آلات کو اجازت دیں۔ آلہ گم ہو گیا؟ اپنے ری سیلر سے اسے ہٹانے کو کہیں۔',
  );
  String get noSignInRequests => _t(
    'No sign-in requests waiting.',
    'لا توجد طلبات تسجيل دخول بالانتظار.',
    'کوئی سائن اِن درخواست زیرِ التوا نہیں۔',
  );
  String pendingSignInRequests(int n) => _t(
    '$n waiting',
    '$n بالانتظار',
    '$n زیرِ التوا',
  );
  String get signInAllowed => _t('Sign-in allowed', 'تم السماح بالدخول', 'سائن اِن کی اجازت دی گئی');
  String get signInDenied => _t('Sign-in denied', 'تم رفض الدخول', 'سائن اِن مسترد کر دیا گیا');
  String get pairTvTitle =>
      _t('Link a TV', 'ربط تلفاز', 'TV لنک کریں');
  String get pairTvSubtitle => _t(
    'Scan QR or enter 6-digit code',
    'امسح QR أو أدخل رمزاً من 6 أرقام',
    'QR اسکین کریں یا 6 ہندسوں کا کوڈ',
  );
  String get pairTvScanHint => _t(
    'Point your camera at the QR code on your TV.',
    'وجّه الكاميرا نحو رمز QR على التلفاز.',
    'کیمرہ TV پر QR کی طرف رکھیں۔',
  );
  String get pairTvScanTab => _t('Scan QR', 'مسح QR', 'QR اسکین');
  String get pairTvCodeTab => _t('Enter code', 'إدخال الرمز', 'کوڈ درج کریں');
  String get pairTvInvalidCode => _t(
    'Could not read a valid 6-digit TV code.',
    'تعذّر قراءة رمز تلفاز صالح من 6 أرقام.',
    'درست 6 ہندسوں والا TV کوڈ نہیں پڑھا جا سکا۔',
  );
  String get pairTvCodeLabel =>
      _t('TV code', 'رمز التلفاز', 'TV کوڈ');
  String get pairTvApprove =>
      _t('Approve TV', 'الموافقة على التلفاز', 'TV منظور کریں');
  String get pairTvSuccess =>
      _t('TV linked', 'تم ربط التلفاز', 'TV لنک ہو گیا');
  String get pairTvFailed =>
      _t('Could not link TV', 'تعذّر ربط التلفاز', 'TV لنک نہیں ہو سکا');
  String get pairTvCameraNeedsRestart => _t(
    'Camera could not start. Tap Retry, or enter the 6-digit code instead.',
    'تعذّر تشغيل الكاميرا. اضغط إعادة المحاولة، أو أدخل الرمز المكوّن من 6 أرقام.',
    'کیمرہ شروع نہیں ہو سکا۔ Retry دبائیں، یا 6 ہندسوں والا کوڈ درج کریں۔',
  );
  String get pairTvCameraPermission => _t(
    'Camera access is required to scan the TV QR code. Allow camera permission, then tap Retry.',
    'يلزم الوصول إلى الكاميرا لمسح رمز QR على التلفاز. اسمح بإذن الكاميرا ثم اضغط إعادة المحاولة.',
    'TV کا QR اسکین کرنے کے لیے کیمرہ اجازت درکار ہے۔ کیمرہ اجازت دیں، پھر Retry دبائیں۔',
  );
  String get pairTvOpenSettings => _t(
    'Open Settings',
    'فتح الإعدادات',
    'سیٹنگز کھولیں',
  );
  String get notPriorityDevice => _t(
    'Approve only from your primary phone',
    'الموافقة فقط من هاتفك الأساسي',
    'صرف اپنے مرکزی فون سے منظور کریں',
  );
  String get deviceLimitReached => _t(
    'Device limit reached. Revoke an old device first.',
    'تم بلوغ حد الأجهزة. ألغِ جهازاً قديماً أولاً.',
    'آلات کی حد پوری۔ پہلے کوئی پرانا آلہ منسوخ کریں۔',
  );
  String get tvQrLoginTitle =>
      _t('Sign in with phone', 'تسجيل الدخول بالهاتف', 'فون سے سائن اِن');
  String get tvQrLoginHint => _t(
    'Scan this QR or enter the code in the ${AppBrand.name} app on your primary phone.',
    'امسح رمز QR هذا أو أدخل الرمز في تطبيق ${AppBrand.name} على هاتفك الأساسي.',
    'یہ QR اسکین کریں یا اپنے مرکزی فون پر ${AppBrand.name} ایپ میں کوڈ درج کریں۔',
  );
  String get tvQrWaiting => _t(
    'Waiting for your phone…',
    'بانتظار هاتفك…',
    'فون کا انتظار…',
  );
  String get tvQrRefresh =>
      _t('New code', 'رمز جديد', 'نیا کوڈ');
  String get tvPasswordInstead => _t(
    'Sign in with password',
    'تسجيل الدخول بكلمة المرور',
    'پاس ورڈ سے سائن اِن',
  );
  String get tvQrInstead => _t(
    'Sign in with QR code',
    'تسجيل الدخول برمز QR',
    'QR کوڈ سے سائن اِن',
  );

  String get sessionsBadge => _t('SESSIONS', 'الجلسات', 'سیشنز');
  String get sessionsTitle => _t('Sessions', 'الجلسات', 'سیشنز');
  String get sessionsSubtitle => _t(
    'Active logins on your account. Revoke anything you do not recognize.',
    'تسجيلات الدخول النشطة على حسابك. ألغِ ما لا تعرفه.',
    'آپ کے اکاؤنٹ پر فعال لاگ اِن۔ جو پہچان میں نہ آئے منسوخ کر دیں۔',
  );
  String get aboutSessions =>
      _t('About sessions', 'حول الجلسات', 'سیشنز کے بارے میں');
  String get sessionsHelpBody => _t(
    'Each successful login creates a session. Revoke a session to force that login off.\n\n'
        'Sign out all devices revokes every session (including this phone).',
    'كل تسجيل دخول ناجح يُنشئ جلسة. ألغِ الجلسة لإنهاء ذلك الدخول.\n\n'
        'تسجيل الخروج من كل الأجهزة يلغي جميع الجلسات (بما فيها هذا الهاتف).',
    'ہر کامیاب لاگ اِن ایک سیشن بناتا ہے۔ سیشن منسوخ کریں تو وہ لاگ اِن بند ہو جائے گا۔\n\n'
        'تمام آلات سے سائن آؤٹ ہر سیشن منسوخ کر دیتا ہے (اس فون سمیت)۔',
  );
  String get sessionsRefreshed =>
      _t('Sessions refreshed', 'تم تحديث الجلسات', 'سیشنز تازہ ہو گئیں');
  String get couldNotLoadSessions => _t(
    'Could not load sessions',
    'تعذّر تحميل الجلسات',
    'سیشنز لوڈ نہیں ہو سکیں',
  );
  String get revokeThisSession =>
      _t('Revoke this session?', 'إلغاء هذه الجلسة؟', 'یہ سیشن منسوخ کریں؟');
  String get revokeSessionMessage => _t(
    'That login will be signed out immediately.',
    'سيُنهى ذلك الدخول فوراً.',
    'وہ لاگ اِن فوراً سائن آؤٹ ہو جائے گا۔',
  );
  String get sessionRevoked =>
      _t('Session revoked', 'تم إلغاء الجلسة', 'سیشن منسوخ');
  String get deviceSignedOut => _t(
    'That device was signed out',
    'تم تسجيل خروج ذلك الجهاز',
    'وہ آلہ سائن آؤٹ ہو گیا',
  );
  String get signOutEverywhere => _t(
    'Sign out everywhere?',
    'تسجيل الخروج من كل الأماكن؟',
    'ہر جگہ سے سائن آؤٹ؟',
  );
  String get signOutAllMessage => _t(
    'This revokes all sessions, including this phone. You will return to sign-in.',
    'يلغي جميع الجلسات بما فيها هذا الهاتف. ستعود إلى تسجيل الدخول.',
    'یہ تمام سیشنز منسوخ کر دیتا ہے، اس فون سمیت۔ آپ سائن اِن پر واپس جائیں گے۔',
  );
  String get signOutAllLabel =>
      _t('Sign out all', 'تسجيل الخروج من الكل', 'سب سائن آؤٹ');
  String get signedOutTitle => _t('Signed out', 'تم تسجيل الخروج', 'سائن آؤٹ');
  String get allSessionsRevoked => _t(
    'All sessions were revoked.',
    'تم إلغاء جميع الجلسات.',
    'تمام سیشنز منسوخ ہو گئیں۔',
  );
  String get signOutFailed =>
      _t('Sign out failed', 'فشل تسجيل الخروج', 'سائن آؤٹ ناکام');
  String activeSessionsCount(int n) => _t('$n active', '$n نشطة', '$n فعال');
  String get noActiveSessions =>
      _t('No active sessions.', 'لا جلسات نشطة.', 'کوئی فعال سیشن نہیں۔');
  String lastUsed(String when) =>
      _t('Last used $when', 'آخر استخدام $when', 'آخری استعمال $when');
  String get currentSession => _t('CURRENT', 'الحالية', 'موجودہ');
  String get signingOut =>
      _t('Signing out…', 'جارٍ تسجيل الخروج…', 'سائن آؤٹ ہو رہا ہے…');
  String get signOutAllDevices => _t(
    'Sign out all devices',
    'تسجيل الخروج من كل الأجهزة',
    'تمام آلات سے سائن آؤٹ',
  );

  String get noActiveSubscription => _t(
    'This account is not active. Please check it with your service provider.',
    'هذا الحساب غير نشط. يرجى التحقق منه مع مزوّد الخدمة.',
    'یہ اکاؤنٹ فعال نہیں ہے۔ براہ کرم اپنے سروس فراہم کنندہ سے چیک کریں۔',
  );
  /// Login footer under the sign-in button (client 19 Oct: must follow UI language).
  String get thankYouChoosingApp => _t(
    'Thank you for choosing ${AppBrand.name}',
    'شكراً لاختيارك ${AppBrand.name}',
    '${AppBrand.name} کا انتخاب کرنے کا شکریہ',
  );
  String get badgeVerified => _t('VERIFIED', 'موثّق', 'تصدیق شدہ');
  String get badgeActive => _t('ACTIVE', 'نشط', 'فعال');
  String get expiresToday =>
      _t('Expires today', 'ينتهي اليوم', 'آج ختم ہوتا ہے');
  String daysRemaining(int n) => n == 1
      ? _t('1 day remaining', 'يوم واحد متبقٍ', '1 دن باقی')
      : _t('$n days remaining', '$n أيام متبقية', '$n دن باقی');
  String subscriptionStatusLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'active':
        return badgeActive;
      case 'verified':
        return badgeVerified;
      default:
        return raw;
    }
  }
  String renewsOn(String date) =>
      _t('Renews $date', 'يتجدد في $date', 'تجدید $date کو');
  // The subscription does not renew by itself; it ends on this date (client
  // 20 Oct: "Renews" was wrong).
  String expiresOn(String date) =>
      _t('Expires on $date', 'ينتهي في $date', 'ختم ہونے کی تاریخ $date');
  String get liveSportsPackageIncluded => _t(
    'Live Sports package included',
    'باقة الرياضة المباشرة مشمولة',
    'لائیو سپورٹس پیکج شامل ہے',
  );
  String upToRegisteredDevices(int n) => _t(
    'Up to $n registered devices',
    'حتى $n أجهزة مسجّلة',
    '$n تک رجسٹرڈ آلات',
  );
  String activeStreamsAtTime(int n) => n == 1
      ? _t(
          '1 active stream at a time',
          'بث واحد نشط في الوقت نفسه',
          'ایک وقت میں ایک فعال سٹریم',
        )
      : _t(
          '$n active streams at a time',
          '$n بثوث نشطة في الوقت نفسه',
          'ایک وقت میں $n فعال سٹریمز',
        );
  String subscriptionFeatureLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'live':
        return _t('Live TV', 'بث مباشر', 'لائیو ٹی وی');
      case 'vod':
        return _t('Movies on demand', 'أفلام حسب الطلب', 'فلمیں آن ڈیمانڈ');
      case 'series':
        return series;
      case 'sports':
        return sports;
      default:
        return raw;
    }
  }

  String get subscriptionBillingFooter => _t(
    '${AppBrand.name} is a media player only. It does not provide or sell subscriptions. Your account, package and renewal are managed by your service provider.',
    '${AppBrand.name} مشغّل وسائط فقط. لا يقدّم الاشتراكات ولا يبيعها. حسابك وباقتك وتجديدها تُدار عبر مزوّد الخدمة.',
    '${AppBrand.name} صرف میڈیا پلیئر ہے۔ یہ سبسکرپشن نہ فراہم کرتا ہے نہ بیچتا ہے۔ آپ کا اکاؤنٹ، پیکج اور تجدید آپ کا سروس فراہم کنندہ سنبھالتا ہے۔',
  );

  String get maxQuality =>
      _t('Max quality', 'أقصى جودة', 'زیادہ سے زیادہ کوالٹی');
  String get autoplayNextEpisode => _t(
    'Autoplay next episode',
    'تشغيل الحلقة التالية تلقائياً',
    'اگلی قسط خودکار چلائیں',
  );
  String get autoplayNextSubtitle => _t(
    'Neon transition between episodes',
    'انتقال نيون بين الحلقات',
    'قسطوں کے درمیان نیون ٹرانزیشن',
  );
  String get preferredSubtitles =>
      _t('Preferred subtitles', 'الترجمة المفضّلة', 'ترجیحی سب ٹائٹلز');
  String get preferredSubtitlesList => _t(
    'Arabic, English, French, Spanish, Japanese',
    'عربية، إنجليزية، فرنسية، إسبانية، يابانية',
    'عربی، انگریزی، فرانسیسی، ہسپانوی، جاپانی',
  );

  String get kidsSafeBadge => _t('SAFE', 'آمن', 'محفوظ');

  /// Client 2 Nov: shown clearly on every platform (sign-in + About).
  String get mediaPlayerOnlyNotice => _t(
    '${AppBrand.name} is a media player only. It does not provide or sell subscriptions.',
    '${AppBrand.name} مشغّل وسائط فقط. لا يقدّم الاشتراكات ولا يبيعها.',
    '${AppBrand.name} صرف میڈیا پلیئر ہے۔ یہ سبسکرپشن نہ فراہم کرتا ہے نہ بیچتا ہے۔',
  );
  // ── Demo mode (store review: real app, sample content, no account) ──
  String get tryDemo => _t('Try demo', 'جرّب العرض التجريبي', 'ڈیمو آزمائیں');
  String get demoSignInTitle => _t(
    'Sign in to use this',
    'سجّل الدخول لاستخدام هذه الميزة',
    'اسے استعمال کرنے کے لیے سائن اِن کریں',
  );
  String get demoSignInBody => _t(
    'You are in demo mode with openly licensed sample videos. Profiles, '
        'downloads, devices and account settings need you to sign in with the account from your service provider. '
        '${AppBrand.name} is a media player only. It does not provide or sell subscriptions.',
    'أنت في الوضع التجريبي مع فيديوهات نموذجية مرخّصة ترخيصًا مفتوحًا. '
        'الملفات الشخصية والتنزيلات والأجهزة وإعدادات الحساب تتطلب تسجيل الدخول بحسابك لدى مزوّد الخدمة. '
        '${AppBrand.name} مشغّل وسائط فقط. لا يقدّم الاشتراكات ولا يبيعها.',
    'آپ ڈیمو موڈ میں ہیں جس میں کھلے لائسنس والی نمونہ ویڈیوز ہیں۔ پروفائلز، '
        'ڈاؤن لوڈز، ڈیوائسز اور اکاؤنٹ سیٹنگز کے لیے اپنے سروس فراہم کنندہ کے اکاؤنٹ سے سائن اِن کریں۔ '
        '${AppBrand.name} صرف میڈیا پلیئر ہے۔ یہ سبسکرپشن نہ فراہم کرتا ہے نہ بیچتا ہے۔',
  );
  String get exitDemoSignIn => _t(
    'Exit demo · Sign in',
    'الخروج من العرض التجريبي · تسجيل الدخول',
    'ڈیمو سے باہر · سائن اِن',
  );
  String get demoCredits => _t(
    'Demo credits & licences',
    'حقوق وتراخيص المحتوى التجريبي',
    'ڈیمو کریڈٹس اور لائسنس',
  );
  String get demoCreditsIntro => _t(
    'Demo mode shows only openly licensed films and public test streams. '
        'No content from any service provider is used.',
    'يعرض الوضع التجريبي أفلامًا مرخّصة ترخيصًا مفتوحًا وبثوث اختبار عامة فقط. '
        'لا يُستخدم أي محتوى من أي مزوّد خدمة.',
    'ڈیمو موڈ صرف کھلے لائسنس والی فلمیں اور عوامی ٹیسٹ اسٹریمز دکھاتا ہے۔ '
        'کسی سروس فراہم کنندہ کا مواد استعمال نہیں ہوتا۔',
  );
  String get kidsMaturitySubtitle => _t(
    'Maturity-limited titles for family profiles',
    'عناوين محدودة النضج لملفات العائلة',
    'خاندانی پروفائلز کے لیے عمر محدود عنوانات',
  );
  String get noKidsTitlesYet => _t(
    'No kids titles yet',
    'لا عناوين أطفال بعد',
    'ابھی بچوں کے عنوانات نہیں',
  );
  String get kidsCatalogEmpty => _t(
    'Catalog filter returned an empty set.',
    'أعادت التصفية مجموعة فارغة.',
    'فلٹر نے خالی نتیجہ دیا۔',
  );
  String get searchKids =>
      _t('Search Kids…', 'ابحث في الأطفال…', 'کڈز میں تلاش…');

  String get curatedVaultBadge =>
      _t('CURATED VAULT', 'خزانة منتقاة', 'منتخب والٹ');
  String get imaxEnhancedBadge =>
      _t('IMAX ENHANCED', 'IMAX ENHANCED', 'IMAX ENHANCED');
  String get cinemaVaultTitle =>
      _t('${AppBrand.name} Cinema Vault', 'خزانة ${AppBrand.name} السينمائية', '${AppBrand.name} سنیما والٹ');
  /// Client 23 Oct round 3 #17: only titles that are really in 4K.
  String get cinemaVaultBlurb => _t(
    'Movies and series in true 4K only, Arabic and international.',
    'أفلام ومسلسلات بجودة 4K حقيقية فقط، عربية وعالمية.',
    'صرف اصل 4K میں فلمیں اور سیریز، عربی اور بین الاقوامی۔',
  );
  String get exploreVault => _t('Explore the 4K collection', 'استكشف مجموعة 4K', '4K مجموعہ دیکھیں');
  String get cinemaVaultEmpty => _t('No 4K titles in your package yet.', 'لا توجد عناوين 4K في باقتك حالياً.', 'آپ کے پیکج میں ابھی 4K عنوانات نہیں۔');
  String exploreCollectionTitles(int n) => _t(
    'Explore Collection ($n Titles)',
    'استكشف المجموعة ($n عنواناً)',
    'مجموعہ دیکھیں ($n عنوانات)',
  );

  // ── Details meta ─────────────────────────────────────────────────
  String get director => _t('Director', 'المخرج', 'ڈائریکٹر');
  String get audioDubs => _t('Audio Dubs', 'الدبلجة', 'ڈب آڈیو');
  String get subtitles => _t('Subtitles', 'الترجمة', 'سب ٹائٹلز');
  String get masterSpec => _t('Master Spec', 'مواصفات الماستر', 'ماسٹر سپیک');

  // ── In-player sheets ─────────────────────────────────────────────
  String get playbackSpeed =>
      _t('Playback speed', 'سرعة التشغيل', 'پلے بیک اسپیڈ');
  String get quality => _t('Quality', 'الجودة', 'کوالٹی');
  String get audio => _t('Audio', 'الصوت', 'آڈیو');
  String get qualityAuto => _t('Auto', 'تلقائي', 'آٹو');
  String get audioDefault => _t('Default', 'افتراضي', 'ڈیفالٹ');
  String get audioAuto => _t('Audio auto', 'صوت تلقائي', 'آڈیو آٹو');
  String get singleCdnSource =>
      _t('single CDN source', 'مصدر CDN واحد', 'واحد CDN سورس');
  String get streamSource => _t('Stream', 'بث', 'سٹریم');
  String get localSampleSource =>
      _t('Local sample', 'عينة محلية', 'مقامی نمونہ');
  String get noEmbeddedSubtitles => _t(
    'No embedded subtitle tracks found in this file.',
    'لا توجد مسارات ترجمة مضمّنة في هذا الملف.',
    'اس فائل میں ایمبیڈڈ سب ٹائٹل ٹریکس نہیں ملے۔',
  );
  String get noEmbeddedAudio => _t(
    'No alternate audio tracks found in this file.',
    'لا توجد مسارات صوت بديلة في هذا الملف.',
    'اس فائل میں متبادل آڈیو ٹریکس نہیں ملے۔',
  );
  String get noAlternateQuality => _t(
    'This stream is a single CDN source (no quality ladder).',
    'هذا البث مصدر CDN واحد (بدون سلم جودة).',
    'یہ سٹریم واحد CDN سورس ہے (کوالٹی لیڈر نہیں).',
  );
  String audioTrackFallback(Object id) =>
      _t('Audio $id', 'صوت $id', 'آڈیو $id');
  String trackFallback(Object id) => _t('Track $id', 'مسار $id', 'ٹریک $id');
  String videoTrackFallback(Object id) =>
      _t('Video $id', 'فيديو $id', 'ویڈیو $id');
  String qualityLine(String quality, String source) =>
      '$quality · $source · $singleCdnSource';
  String get unmute => _t('Unmute', 'إلغاء كتم الصوت', 'آواز چالو');
  String get volume => _t('Volume', 'مستوى الصوت', 'والیوم');
  String get brightness => _t('Brightness', 'السطوع', 'Brightness');
  String get rotate => _t('Rotate', 'تدوير', 'گھمائیں');
  String get videoFit =>
      _t('Fit: whole picture', 'ملاءمة: الصورة كاملة', 'فٹ: پوری تصویر');
  String get videoFill =>
      _t('Zoom: fills screen, crops edges', 'تكبير: يملأ الشاشة ويقص الأطراف',
          'زوم: اسکرین بھرتا ہے، کنارے کٹتے ہیں');
  // Player settings row (client 20 Oct I4: "Fill" read as a bug; say it crops).
  String get videoModeFit => _t('Fit (whole picture)', 'ملاءمة (الصورة كاملة)',
      'فٹ (پوری تصویر)');
  String get videoModeZoom =>
      _t('Zoom (crops edges)', 'تكبير (يقص الأطراف)', 'زوم (کنارے کٹتے ہیں)');
  String get videoModeFitHint => _t('Whole picture, black bars if needed',
      'الصورة كاملة مع أشرطة سوداء عند الحاجة', 'پوری تصویر، ضرورت ہو تو کالی پٹیاں');
  String get videoModeZoomHint => _t('Closer view; more of the edges is cut',
      'يملأ الشاشة؛ يُقص الأعلى والأسفل أو الجانبان', 'اسکرین بھرتا ہے؛ اوپر نیچے یا سائیڈ کٹتی ہیں');
  String get notificationsBlocked => _t('Notifications are off on this phone',
      'الإشعارات متوقفة على هذا الهاتف', 'اس فون پر نوٹیفیکیشنز بند ہیں');
  String get notificationsBlockedHint => _t('Tap to allow them in phone settings',
      'اضغط للسماح بها من إعدادات الهاتف', 'فون سیٹنگز میں اجازت دینے کے لیے ٹیپ کریں');
  // Screen modes (client 21 Oct mobile #5: full screen without cropping).
  String get videoScreenMode =>
      _t('Screen mode', 'وضع الشاشة', 'اسکرین موڈ');
  String get videoModeStretchFull => _t('Stretch', 'تمدد', 'پھیلائیں');
  String get videoModeStretchFullHint => _t('Whole picture on the whole screen, nothing cut; the picture is a little wider',
      'الصورة كاملة على الشاشة كاملة دون قص؛ تصبح الصورة أعرض قليلاً', 'پوری تصویر پوری اسکرین پر، کچھ نہیں کٹتا؛ تصویر تھوڑی چوڑی ہو جاتی ہے');
  String get videoModeStretch => _t('Fill screen',
      'ملء الشاشة', 'پوری اسکرین');
  String get videoModeStretchHint => _t('Whole screen, picture not stretched; a little of the top and bottom may be outside',
      'الشاشة كاملة دون تمدد للصورة؛ قد يخرج جزء بسيط من الأعلى والأسفل', 'پوری اسکرین، تصویر کھنچتی نہیں');
  String get videoModeRatioHint => _t('For channels that show the wrong shape',
      'للقنوات التي تظهر بشكل غير صحيح', 'ان چینلز کے لیے جن کی شکل غلط آتی ہے');
  /// Crop-to-fill mode (client C14 name: Zoom, not Fill).
  String get videoZoom =>
      _t('Zoom: crop to screen', 'تكبير: قص لملء الشاشة', 'زوم: اسکرین بھریں');
  String get lockScreen => _t('Lock screen', 'قفل الشاشة', 'اسکرین لاک');
  // Match centre (client: schedules, lineups, formations, events, stats).
  String get matchCentre =>
      _t('Matches & Lineups', 'المباريات والتشكيلات', 'میچز اور لائن اپس');
  String get matchCentreHint => _t('Schedules, lineups, events and statistics',
      'المواعيد والتشكيلات والأحداث والإحصائيات', 'شیڈول، لائن اپس، واقعات اور اعداد و شمار');
  String get matchToday => _t('Today', 'اليوم', 'آج');
  String get matchYesterday => _t('Yesterday', 'أمس', 'کل (گزشتہ)');
  String get matchTomorrow => _t('Tomorrow', 'غدًا', 'کل');
  String get matchLineups => _t('Lineups', 'التشكيلات', 'لائن اپس');
  String get matchTimeline => _t('Timeline', 'مجريات المباراة', 'ٹائم لائن');
  String get matchStatistics => _t('Statistics', 'الإحصائيات', 'اعداد و شمار');
  String get matchSubstitutes => _t('Substitutes', 'البدلاء', 'متبادل کھلاڑی');
  String get matchCoach => _t('Coach', 'المدرب', 'کوچ');
  String get matchNone =>
      _t('No matches on this day', 'لا توجد مباريات في هذا اليوم', 'اس دن کوئی میچ نہیں');
  String get matchLineupsLater => _t(
      // Provider (API-Football) publishes them 20-40 min before kickoff.
      'Lineups are usually published 20–40 minutes before kickoff.',
      'تُعلن التشكيلات عادةً قبل المباراة بـ 20 إلى 40 دقيقة.',
      'لائن اپس عموماً میچ سے 20 سے 40 منٹ پہلے آتی ہیں۔');
  String get matchNoEvents =>
      _t('No events yet', 'لا توجد أحداث بعد', 'ابھی کوئی واقعہ نہیں');
  String get matchNoStats =>
      _t('Statistics appear once the match starts', 'تظهر الإحصائيات بعد بدء المباراة', 'اعداد و شمار میچ شروع ہونے کے بعد');
  String get matchUnavailable => _t('Match centre is unavailable right now',
      'مركز المباريات غير متاح حاليًا', 'میچ سینٹر ابھی دستیاب نہیں');
  String get matchFullTime => _t('FT', 'انتهت', 'ختم');
  String get matchHalfTime => _t('HT', 'استراحة', 'وقفہ');
  String get matchLive => _t('LIVE', 'مباشر', 'لائیو');
  String matchUpdated(String time) =>
      _t('Last update $time', 'آخر تحديث $time', 'آخری اپڈیٹ $time');
  String matchAssist(String name) => _t('Assist: $name', 'صناعة: $name', 'اسسٹ: $name');
  String matchSubstitution(String a, String b) =>
      _t('Substitution: $a ⇄ $b', 'تبديل: $a ⇄ $b', 'تبدیلی: $a ⇄ $b');
  // Match centre design (client 20 Oct).
  // Client 20 Oct (10-point list #3): the Home section is "Today's Matches".
  String get matchTodayTomorrow => _t("Today's Matches", 'مباريات اليوم', 'آج کے میچز');
  String get matchSeeAll => _t('See all', 'عرض الكل', 'سب دیکھیں');
  String get matchKeyEvents => _t('Key Match Events', 'أبرز أحداث المباراة', 'میچ کے اہم واقعات');
  String get matchHeadToHead => _t('Head-to-Head Stats', 'إحصائيات المواجهة', 'آمنے سامنے کے اعداد');
  String get matchLiveHeadToHead => _t('Live Head-to-Head Stats', 'إحصائيات المواجهة المباشرة', 'لائیو آمنے سامنے کے اعداد');
  String get matchStandings => _t('Standings', 'الترتيب', 'پوائنٹس ٹیبل');
  String get matchEvents => _t('Events', 'الأحداث', 'واقعات');
  String get matchStats => _t('Stats', 'الإحصائيات', 'اعداد');
  String get matchNoStandings => _t('The league standings are not available for this competition yet',
      'ترتيب الدوري غير متاح لهذه البطولة حالياً', 'اس مقابلے کا ٹیبل دستیاب نہیں');
  /// API-Football season 2024 = "2024/25".
  static String seasonLabel(int season) => '$season/${((season + 1) % 100).toString().padLeft(2, '0')}';
  String matchSeason(int season) => _t('Season ${seasonLabel(season)}', 'موسم ${seasonLabel(season)}', 'سیزن ${seasonLabel(season)}');
  /// Table of an older season because the match-data plan does not include the current one.
  String matchStandingsOlderSeason(int shown, int asked) => _t(
      'Showing the ${seasonLabel(shown)} table. The current match-data plan does not include the ${seasonLabel(asked)} season; it will appear here automatically once the plan includes it.',
      'يتم عرض ترتيب موسم ${seasonLabel(shown)}. باقة بيانات المباريات الحالية لا تشمل موسم ${seasonLabel(asked)}، وسيظهر هنا تلقائياً عند إضافته إلى الباقة.',
      '${seasonLabel(shown)} کا ٹیبل دکھایا جا رہا ہے۔ موجودہ میچ ڈیٹا پلان میں ${seasonLabel(asked)} سیزن شامل نہیں؛ پلان میں شامل ہوتے ہی یہاں خود ظاہر ہو جائے گا۔');
  /// No table could be shown: the plan does not include the season.
  String matchStandingsNotInPlan(int asked) => _t(
      'The ${seasonLabel(asked)} league table is not included in the current match-data plan. It will appear here automatically once the plan includes this season.',
      'ترتيب موسم ${seasonLabel(asked)} غير مشمول في باقة بيانات المباريات الحالية، وسيظهر هنا تلقائياً عند إضافة هذا الموسم إلى الباقة.',
      '${seasonLabel(asked)} کا لیگ ٹیبل موجودہ میچ ڈیٹا پلان میں شامل نہیں۔ پلان میں یہ سیزن شامل ہوتے ہی یہاں خود ظاہر ہو جائے گا۔');
  String matchManager(String name) => _t('Manager: $name', 'المدرب: $name', 'مینیجر: $name');
  String matchBench(String team) => _t('Bench reserves ($team)', 'البدلاء ($team)', 'بینچ ($team)');
  String get matchOnBench => _t('Bench', 'احتياط', 'بینچ');
  String matchCameOn(String minute) => _t('On $minute', 'دخل $minute', 'آئے $minute');
  String get matchAttack => _t('Attack', 'الهجوم', 'حملہ');
  String matchRatingCaption(String rating, int goals, int keyPasses) {
    final parts = <String>[_t('Rating $rating', 'التقييم $rating', 'ریٹنگ $rating')];
    if (goals > 0) parts.add(_t(goals == 1 ? '1 goal' : '$goals goals', '$goals هدف', '$goals گول'));
    if (keyPasses > 0) {
      parts.add(_t(keyPasses == 1 ? '1 key pass' : '$keyPasses key passes', '$keyPasses تمريرات مفتاحية', '$keyPasses اہم پاس'));
    }
    return parts.join(' • ');
  }
  String get matchYellowCard => _t('Yellow card', 'بطاقة صفراء', 'پیلا کارڈ');
  String get matchRedCard => _t('Red card', 'بطاقة حمراء', 'سرخ کارڈ');
  String get matchVar => _t('VAR check', 'مراجعة الفيديو', 'وی اے آر');
  String get matchPossession => _t('Possession', 'الاستحواذ', 'گیند پر قبضہ');
  String get matchXg => _t('Expected goals (xG)', 'الأهداف المتوقعة', 'متوقع گول (xG)');
  String get matchShotsTarget => _t('Shots (target)', 'التسديدات (على المرمى)', 'شاٹس (ہدف پر)');
  String get matchPassAccuracy => _t('Pass accuracy', 'دقة التمرير', 'پاس کی درستگی');
  String get matchCorners => _t('Corners', 'الركنيات', 'کارنرز');
  String get matchFouls => _t('Fouls', 'الأخطاء', 'فاؤلز');
  /// League table columns: #, Team, P, W, D, L, Goals, +/-, Pts.
  List<String> get matchTableHeaders => [
        '#',
        _t('Team', 'الفريق', 'ٹیم'),
        _t('P', 'لعب', 'م'),
        _t('W', 'ف', 'ج'),
        _t('D', 'ت', 'ب'),
        _t('L', 'خ', 'ہ'),
        _t('Goals', 'الأهداف', 'گول'),
        '+/-',
        _t('Pts', 'نقاط', 'پوائنٹس'),
        _t('Form', 'آخر 5', 'فارم'),
      ];
  /// Overall / Home / Away tables.
  List<String> get matchStandingsViews => [
        _t('Overall', 'الترتيب', 'مجموعی'),
        _t('Home', 'داخل الأرض', 'ہوم'),
        _t('Away', 'خارج الأرض', 'اوے'),
      ];
  /// Legend name for a provider zone ("Promotion - AFC Champions League Elite", "Relegation").
  String matchZoneLabel(String zone) {
    final z = zone.toLowerCase();
    final name = zone.replaceFirst(RegExp(r'^(Promotion|Qualification)\s*-\s*', caseSensitive: false), '');
    if (z.contains('relegation')) {
      return z.contains('play')
          ? _t('Relegation play-off', 'ملحق الهبوط', 'ریلیگیشن پلے آف')
          : _t('Relegation', 'الهبوط', 'ریلیگیشن');
    }
    return _t(name, 'التأهل: $name', 'کوالیفائی: $name');
  }
  String get matchKickoff => _t('Kickoff', 'البداية', 'آغاز');
  // Internet speed test (client 20 Oct #10).
  String get speedTitle => _t('Internet download speed', 'سرعة تنزيل الإنترنت', 'انٹرنیٹ ڈاؤن لوڈ اسپیڈ');
  String get speedUhd => _t('Good for 4K', 'مناسبة لـ 4K', '4K کے لیے مناسب');
  String get speedHd => _t('Good for HD; 4K may buffer', 'مناسبة لـ HD؛ قد يتقطع 4K', 'HD کے لیے مناسب؛ 4K رک سکتا ہے');
  String get speedSd => _t('SD only; HD and 4K will buffer', 'SD فقط؛ سيتقطع HD و4K', 'صرف SD؛ HD اور 4K رکیں گے');
  String get speedPoor => _t('Too slow for video', 'بطيئة جدًا للفيديو', 'ویڈیو کے لیے بہت سست');
  String get speedFailed => _t('Speed test could not run. Check the connection.', 'تعذر قياس السرعة. تحقق من الاتصال.', 'اسپیڈ ٹیسٹ نہیں چل سکا۔ کنکشن چیک کریں۔');

  /// Provider statistic names in the interface language.
  // Match page, approved reference design (client 22 Oct).
  String get matchOverview => _t('Overview', 'نظرة عامة', 'جائزہ');
  String get matchInfo => _t('Match Info', 'معلومات المباراة', 'میچ کی معلومات');
  /// Fifth match tab (client 23 Oct: replaces Match Info, table only).
  String get matchStandingsTab => _t('League Standings', 'ترتيب الدوري', 'League Standings');
  String get matchCompetition => _t('Competition', 'البطولة', 'مقابلہ');
  String get matchEventsTitle => _t('Match Events', 'الأحداث', 'میچ کے واقعات');
  String get matchStatisticsTitle => _t('Match Statistics', 'إحصائيات المباراة', 'میچ کے اعداد و شمار');
  String get matchViewAllEvents => _t('View All Events', 'عرض كل الأحداث', 'تمام واقعات دیکھیں');
  String get matchViewAllStats => _t('View All Statistics', 'عرض كل الإحصائيات', 'تمام اعداد و شمار دیکھیں');
  String get matchGoal => _t('Goal', 'هدف', 'گول');
  String get matchSubstitutionLabel => _t('Substitution', 'تبديل', 'تبدیلی');
  String get matchVenue => _t('Stadium', 'الملعب', 'اسٹیڈیم');
  String get matchReferee => _t('Referee', 'الحكم', 'ریفری');
  String get matchRound => _t('Round', 'الجولة', 'راؤنڈ');
  String get matchDate => _t('Date', 'التاريخ', 'تاریخ');
  String get matchTime => _t('Kickoff', 'موعد المباراة', 'آغاز');
  String get matchStatusLabel => _t('Status', 'الحالة', 'صورتحال');
  String get matchNotStarted => _t('Not started', 'لم تبدأ', 'شروع نہیں ہوا');
  String get matchChannelsLabel => _t('Channels', 'القنوات الناقلة', 'چینلز');
  String get matchInfoTitle => _t('Match Information', 'معلومات المباراة', 'میچ کی معلومات');
  String get matchFormation => _t('Formation', 'التشكيل', 'فارمیشن');
  String get matchLiveBadge => _t('LIVE', 'مباشر', 'لائیو');
  /// Live data too old to trust (finished match no longer shown as LIVE).
  String get matchUpdating => _t('Updating', 'جارٍ التحديث', 'اپ ڈیٹ ہو رہا ہے');
  String get matchShots => _t('Total Shots', 'التسديدات', 'کل شاٹس');
  String get matchShotsOnTarget => _t('Shots on Target', 'التسديدات على المرمى', 'ہدف پر شاٹس');
  String get matchPasses => _t('Passes', 'التمريرات', 'پاسز');
  String get matchYellowCards => _t('Yellow Cards', 'البطاقات الصفراء', 'پیلے کارڈ');
  String get matchRedCards => _t('Red Cards', 'البطاقات الحمراء', 'سرخ کارڈ');
  String get matchFoulsLabel => _t('Fouls', 'الأخطاء', 'فاؤلز');
  String get matchLeagueTable => _t('League Table', 'جدول الترتيب', 'لیگ ٹیبل');
  String matchStat(String type) {
    if (lang != AppLang.ar) return type;
    const ar = {
      'Shots on Goal': 'تسديدات على المرمى',
      'Shots off Goal': 'تسديدات خارج المرمى',
      'Total Shots': 'إجمالي التسديدات',
      'Blocked Shots': 'تسديدات مصدودة',
      'Shots insidebox': 'تسديدات داخل المنطقة',
      'Shots outsidebox': 'تسديدات خارج المنطقة',
      'Fouls': 'الأخطاء',
      'Corner Kicks': 'الركلات الركنية',
      'Offsides': 'التسلل',
      'Ball Possession': 'الاستحواذ',
      'Yellow Cards': 'البطاقات الصفراء',
      'Red Cards': 'البطاقات الحمراء',
      'Goalkeeper Saves': 'تصديات الحارس',
      'Total passes': 'إجمالي التمريرات',
      'Passes accurate': 'التمريرات الصحيحة',
      'Passes %': 'دقة التمرير',
      'expected_goals': 'الأهداف المتوقعة',
    };
    return ar[type] ?? type;
  }
  String get tapToUnlock =>
      _t('Tap to unlock', 'اضغط لإلغاء القفل', 'ان لاک کرنے کے لیے ٹیپ کریں');
  String get retry => _t('Retry', 'إعادة المحاولة', 'دوبارہ کوشش');

  String get searchLoadError => _t(
    'Search could not reach the server. Check the connection and try again.',
    'تعذّر الوصول إلى الخادم للبحث. تحقّق من الاتصال وحاول مجددًا.',
    'تلاش کے لیے سرور سے رابطہ نہیں ہو سکا۔ کنکشن چیک کر کے دوبارہ کوشش کریں۔',
  );
  String get playerExitTitle =>
      _t('Stop watching?', 'إيقاف المشاهدة؟', 'دیکھنا بند کریں؟');
  String get playerExitMessage => _t(
    'Playback will stop and you will return to the previous screen.',
    'سيتوقف التشغيل وستعود إلى الشاشة السابقة.',
    'پلے بیک بند ہو جائے گا اور آپ پچھلی اسکرین پر واپس جائیں گے۔',
  );
  String get playerExitConfirm => _t('Exit', 'خروج', 'باہر نکلیں');
  String get castLabel => _t('Cast', 'بطولة', 'کاسٹ');
  String get close => _t('Close', 'إغلاق', 'بند کریں');
  String get playHdVersion => _t('Play HD version', 'تشغيل نسخة HD', 'HD ورژن چلائیں');
  /// Player / API error texts (English from the data layer) in the app
  /// language (client 20 Oct: English errors with a leading "." in Arabic).
  /// Unknown texts are returned unchanged.
  String errorText(String raw) {
    if (lang == AppLang.en) return raw;
    final t = _errorTexts[raw.trim()];
    if (t == null) return raw;
    return lang == AppLang.ar ? t.$1 : t.$2;
  }

  static const _errorTexts = <String, (String, String)>{
    'No access token stored. Please sign in again.': ('انتهت جلستك. يرجى تسجيل الدخول مرة أخرى.', 'آپ کا سیشن ختم ہو گیا۔ دوبارہ سائن ان کریں۔'),
    'Session expired. Please sign in again.': ('انتهت جلستك. يرجى تسجيل الدخول مرة أخرى.', 'آپ کا سیشن ختم ہو گیا۔ دوبارہ سائن ان کریں۔'),
    'Please sign in again.': ('يرجى تسجيل الدخول مرة أخرى.', 'دوبارہ سائن ان کریں۔'),
    'Sign in to play': ('سجّل الدخول للتشغيل', 'چلانے کے لیے سائن ان کریں'),
    'Could not refresh your session right now. Please try again.': ('تعذّر تحديث جلستك الآن. يرجى المحاولة مرة أخرى.', 'ابھی سیشن تازہ نہیں ہو سکا۔ دوبارہ کوشش کریں۔'),
    'Network error. Check connection and try again.': ('خطأ في الشبكة. تحقّق من الاتصال وحاول مرة أخرى.', 'نیٹ ورک کی خرابی۔ کنکشن چیک کر کے دوبارہ کوشش کریں۔'),
    'Playback unavailable. Please try again.': ('التشغيل غير متاح. يرجى المحاولة مرة أخرى.', 'چلانا ممکن نہیں۔ دوبارہ کوشش کریں۔'),
    'Playback unavailable': ('التشغيل غير متاح', 'چلانا ممکن نہیں'),
    'Playback failed. Please try again.': ('فشل التشغيل. يرجى المحاولة مرة أخرى.', 'چلانا ناکام ہوا۔ دوبارہ کوشش کریں۔'),
    'Playback lease lost. Tap Retry.': ('انقطع التشغيل. اضغط إعادة المحاولة.', 'پلے بیک منقطع ہو گیا۔ دوبارہ کوشش دبائیں۔'),
    'Android playback failed. Try the default player.': ('تعذّر التشغيل على هذا الجهاز. جرّب المشغّل الافتراضي من الإعدادات.', 'اس ڈیوائس پر چلانا ناکام ہوا۔ سیٹنگز سے ڈیفالٹ پلیئر آزمائیں۔'),
    'Hardware video failed. Select Auto in playback settings and retry.': ('فشل فك ترميز الفيديو. اختر «تلقائي» في إعدادات التشغيل وأعد المحاولة.', 'ویڈیو ڈی کوڈ نہیں ہوئی۔ پلے بیک سیٹنگز میں آٹو منتخب کر کے دوبارہ کوشش کریں۔'),
    'This device is struggling to decode this 4K video. Open a lower-resolution version if available.': ('هذا الجهاز لا يدعم تشغيل هذا الفيديو بدقة 4K. افتح نسخة بدقة أقل إن وُجدت.', 'یہ ڈیوائس اس 4K ویڈیو کو نہیں چلا پا رہی۔ کم ریزولوشن والا ورژن کھولیں۔'),
    'The stream server refused this title (access denied). Tap Retry.': ('رفض خادم البث هذا العنوان. اضغط إعادة المحاولة.', 'اسٹریم سرور نے یہ ٹائٹل مسترد کیا۔ دوبارہ کوشش دبائیں۔'),
    'This title is not available on the stream server right now.': ('هذا العنوان غير متاح على خادم البث حاليًا.', 'یہ ٹائٹل ابھی اسٹریم سرور پر دستیاب نہیں۔'),
    'The stream server refused this line. It may be in use on another device, or blocked on this network. Close other devices and tap Retry.': ('رفض خادم البث هذا الحساب. قد يكون مستخدمًا على جهاز آخر أو محظورًا على هذه الشبكة. أغلق الأجهزة الأخرى واضغط إعادة المحاولة.', 'اسٹریم سرور نے یہ لائن مسترد کی۔ شاید یہ کسی اور ڈیوائس پر چل رہی ہے۔ دوسری ڈیوائسز بند کر کے دوبارہ کوشش دبائیں۔'),
    'The stream server had a problem. Tap Retry.': ('حدثت مشكلة في خادم البث. اضغط إعادة المحاولة.', 'اسٹریم سرور میں مسئلہ ہوا۔ دوبارہ کوشش دبائیں۔'),
    'Could not reach the stream server. Check your connection and tap Retry.': ('تعذّر الوصول إلى خادم البث. تحقّق من الاتصال واضغط إعادة المحاولة.', 'اسٹریم سرور تک رسائی نہیں ہوئی۔ کنکشن چیک کر کے دوبارہ کوشش دبائیں۔'),
    'This video format could not be opened.': ('تعذّر فتح صيغة هذا الفيديو.', 'اس ویڈیو کا فارمیٹ نہیں کھل سکا۔'),
    'Playback timed out. Tap Retry.': ('انتهت مهلة التشغيل. اضغط إعادة المحاولة.', 'پلے بیک کا وقت ختم ہو گیا۔ دوبارہ کوشش دبائیں۔'),
    'Playback stopped. Please check your connection and try again.': ('توقف التشغيل. تحقّق من الاتصال وحاول مرة أخرى.', 'پلے بیک رک گیا۔ کنکشن چیک کر کے دوبارہ کوشش کریں۔'),
    'This title could not be played. Try again or pick another episode.': ('تعذّر تشغيل هذا العنوان. حاول مرة أخرى أو اختر حلقة أخرى.', 'یہ ٹائٹل نہیں چل سکا۔ دوبارہ کوشش کریں یا دوسری قسط چنیں۔'),
    'This device was removed. Sign in again.': ('تمت إزالة هذا الجهاز. سجّل الدخول مرة أخرى.', 'یہ ڈیوائس ہٹا دی گئی۔ دوبارہ سائن ان کریں۔'),
    'This device could not be verified. Sign in again.': ('تعذّر التحقق من هذا الجهاز. سجّل الدخول مرة أخرى.', 'اس ڈیوائس کی تصدیق نہیں ہو سکی۔ دوبارہ سائن ان کریں۔'),
    'Sports is not included in your package.': ('الرياضة غير مشمولة في باقتك.', 'اسپورٹس آپ کے پیکیج میں شامل نہیں۔'),
    'Playback stopped by the operator': ('أوقف المشغّل التشغيل', 'آپریٹر نے پلے بیک روک دیا'),
  };
  String get directorLabel => _t('Director', 'إخراج', 'ہدایت کار');
  String get epgNow => _t('Now', 'الآن', 'اب');
  String get epgNext => _t('Next', 'التالي', 'اگلا');
  String get remindProgram =>
      _t('Remind me', 'ذكّرني', 'یاد دلائیں');
  String get reminderSet =>
      _t('Reminder set', 'تم ضبط التذكير', 'یاد دہانی لگ گئی');
  String reminderStarting(String program) => _t(
    '$program is starting',
    'يبدأ الآن: $program',
    '$program شروع ہو رہا ہے',
  );
  String episodesCount(int n) => _t(
    n == 1 ? '1 episode' : '$n episodes',
    n == 1 ? 'حلقة واحدة' : '$n حلقات',
    '$n اقساط',
  );
  String get playerNowPlaying =>
      _t('Now playing', 'يُعرض الآن', 'اب چل رہا ہے');

  String get downloadsOffline =>
      _t('Watch offline', 'شاهد بدون إنترنت', 'آف لائن دیکھیں');
  String get downloaded => _t('Downloaded', 'تم التنزيل', 'ڈاؤن لوڈ ہو گیا');
  static const _genresAr = <String, String>{
    'action': 'أكشن', 'adventure': 'مغامرة', 'action & adventure': 'أكشن ومغامرة',
    'animation': 'رسوم متحركة', 'anime': 'أنمي', 'biography': 'سيرة ذاتية',
    'comedy': 'كوميديا', 'crime': 'جريمة', 'documentary': 'وثائقي',
    'drama': 'دراما', 'family': 'عائلي', 'fantasy': 'فانتازيا',
    'history': 'تاريخي', 'horror': 'رعب', 'kids': 'أطفال', 'music': 'موسيقى',
    'musical': 'موسيقي', 'mystery': 'غموض', 'news': 'أخبار',
    'reality': 'واقعي', 'romance': 'رومانسي', 'science fiction': 'خيال علمي',
    'sci-fi': 'خيال علمي', 'sci-fi & fantasy': 'خيال علمي وفانتازيا',
    'soap': 'مسلسل درامي', 'sport': 'رياضة', 'talk': 'حواري',
    'thriller': 'إثارة', 'tv movie': 'فيلم تلفزيوني', 'war': 'حرب',
    'war & politics': 'حرب وسياسة', 'western': 'غربي',
  };

  /// Provider genre in the interface language (17 Oct: genres stayed in
  /// English in Arabic). Unknown genres are shown as sent.
  String genre(String raw) {
    if (lang != AppLang.ar) return raw;
    return _genresAr[raw.trim().toLowerCase()] ?? raw;
  }

  List<String> genres(List<String> raw) => [for (final g in raw) genre(g)];

  /// Runtime label ("153m", "1h 46m", "01:46:50") in the interface language.
  String durationText(String? label) {
    final t = label?.trim() ?? '';
    if (t.isEmpty) return '';
    final m = _runtimeMinutes(t);
    return m == null || m <= 0 ? t : runtime(m);
  }

  static int? _runtimeMinutes(String t) {
    final hm = RegExp(r'^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m(?:in)?)?$').firstMatch(t);
    if (hm != null && (hm.group(1) != null || hm.group(2) != null)) {
      return int.parse(hm.group(1) ?? '0') * 60 + int.parse(hm.group(2) ?? '0');
    }
    final c = RegExp(r'^(\d+):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(t);
    if (c != null) {
      return c.group(3) != null
          ? int.parse(c.group(1)!) * 60 + int.parse(c.group(2)!)
          : int.parse(c.group(1)!);
    }
    return null;
  }

  /// Continue Watching (client 17 Oct #7): where the viewer stopped, in
  /// minutes, and for series the episode ("S1 E3 · Reached 23 min").
  String? continueLabel({
    required int? positionSec,
    required String title,
    required bool series,
    double? progress,
  }) {
    final pos = positionSec ?? 0;
    if (pos <= 0) return null;
    final m = (pos / 60).floor();
    // Total from the saved fraction (client 20 Oct I5: show the minutes).
    final p = progress ?? 0;
    final total = p > 0.01 && p <= 1 ? (pos / p / 60).round() : 0;
    final reached = m < 1
        ? _t('Just started', 'بدأت للتو', 'ابھی شروع')
        : total > m
            ? _t('$m / $total min', '$m / $total د', '$m / $total منٹ')
            : _t('Reached $m min', 'وصلت إلى $m دقيقة', '$m منٹ تک دیکھا');
    if (!series) return reached;
    final ep = RegExp(r'S(\d{1,2})\s*[:·]?\s*E(\d{1,3})', caseSensitive: false)
        .firstMatch(title);
    if (ep == null) return reached;
    final s = int.parse(ep.group(1)!);
    final e = int.parse(ep.group(2)!);
    return '${_t('S$s E$e', 'م$s ح$e', 'S$s E$e')} · $reached';
  }

  /// Runtime in the interface language: "1h 46m" / "1 س 46 د".
  String runtime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return _t('${m}m', '$m د', '$m منٹ');
    return _t('${h}h ${m}m', '$h س $m د', '$h گھنٹے $m منٹ');
  }
  String timeLeft(Duration d) {
    final m = (d.inSeconds / 60).ceil();
    if (m < 1) return _t('under a minute left', 'أقل من دقيقة متبقية', 'ایک منٹ سے کم باقی');
    if (m < 60) return _t('$m min left', 'متبقٍ $m دقيقة', '$m منٹ باقی');
    final h = m ~/ 60;
    final r = m % 60;
    return _t('${h}h ${r}m left', 'متبقٍ $h س $r د', '$h گھنٹے $r منٹ باقی');
  }
  String freeStorage(String free, String total) => _t(
    'Free storage on this device: $free of $total (reported by the device; downloads also need room here)',
    'المساحة الفارغة على هذا الجهاز: $free من $total (حسب الجهاز؛ تحتاج التنزيلات إلى مساحة هنا أيضاً)',
    'اس ڈیوائس پر خالی جگہ: $total میں سے $free (ڈیوائس کے مطابق؛ ڈاؤن لوڈز کو یہاں بھی جگہ چاہیے)',
  );
  String get downloadQueued => _t('Waiting', 'في الانتظار', 'انتظار میں');
  String get downloadPaused => _t('Paused', 'متوقف مؤقتاً', 'رکا ہوا');
  String get downloadFailed => _t('Failed', 'فشل', 'ناکام');
  String get downloadPause => _t('Pause', 'إيقاف مؤقت', 'روکیں');
  String get downloadResume => _t('Resume', 'استئناف', 'دوبارہ شروع');
  String get downloadRetry => _t('Retry', 'إعادة المحاولة', 'دوبارہ کوشش');
  String get downloadRemove => _t('Remove', 'إزالة', 'ہٹائیں');
  String get downloadStopAndStart => _t(
    'Stop playback and download',
    'إيقاف التشغيل والتنزيل',
    'پلے بیک روک کر ڈاؤن لوڈ کریں',
  );
  // Download row texts by status (were internal English messages, and the
  // phone said "this TV").
  String get downloadNeedsPlaybackStop => _t(
    'Something is playing on this device. Stop it to download?',
    'يوجد تشغيل على هذا الجهاز. هل تريد إيقافه للتنزيل؟',
    'اس ڈیوائس پر کچھ چل رہا ہے۔ ڈاؤن لوڈ کے لیے اسے روکیں؟',
  );
  String get downloadOtherDevicePlaying => _t(
    'Another device is playing on this account.',
    'جهاز آخر يشغّل المحتوى على هذا الحساب.',
    'اس اکاؤنٹ پر کوئی اور ڈیوائس چل رہی ہے۔',
  );
  String get downloadsEmpty =>
      _t('No downloads yet', 'لا توجد تنزيلات بعد', 'ابھی کوئی ڈاؤن لوڈ نہیں');
  // Downloads of the profile on all devices (client 12 Nov #6/#7).
  String get downloadsOnThisDevice =>
      _t('On this device', 'على هذا الجهاز', 'اس ڈیوائس پر');
  String get downloadsOnOtherDevices =>
      _t('On your other devices', 'على أجهزتك الأخرى', 'آپ کی دوسری ڈیوائسز پر');
  String get downloadHere => _t('Download here', 'نزّل هنا', 'یہاں ڈاؤن لوڈ کریں');
  String downloadedOn(String device) =>
      _t('Downloaded on $device', 'تم تنزيله على $device', '$device پر ڈاؤن لوڈ شدہ');
  String get downloadsEmptyHint => _t(
    'Open a movie and choose Download. Files stay inside the ${AppBrand.name} app. One download runs at a time and pauses while you watch online.',
    'افتح فيلماً واختر تنزيل. تبقى الملفات داخل تطبيق ${AppBrand.name}. يعمل تنزيل واحد في كل مرة ويتوقف أثناء المشاهدة عبر الإنترنت.',
    'کوئی فلم کھولیں اور ڈاؤن لوڈ منتخب کریں۔ فائلیں ${AppBrand.name} ایپ کے اندر رہتی ہیں۔ ایک وقت میں ایک ڈاؤن لوڈ چلتا ہے اور آن لائن دیکھتے وقت رک جاتا ہے۔',
  );

  String get offlineBanner => _t(
    'No internet. You can watch your downloads.',
    'لا يوجد اتصال بالإنترنت. يمكنك مشاهدة تنزيلاتك.',
    'انٹرنیٹ نہیں ہے۔ آپ اپنے ڈاؤن لوڈز دیکھ سکتے ہیں۔',
  );
  String get noInternetPlay => _t(
    'No internet connection. Check Wi-Fi or mobile data, then tap Retry. Downloads play without internet.',
    'لا يوجد اتصال بالإنترنت. تحقق من Wi-Fi أو بيانات الجوال ثم اضغط إعادة المحاولة. التنزيلات تعمل بدون إنترنت.',
    'انٹرنیٹ کنکشن نہیں ہے۔ Wi-Fi یا موبائل ڈیٹا چیک کریں، پھر دوبارہ کوشش کریں۔ ڈاؤن لوڈز انٹرنیٹ کے بغیر چلتے ہیں۔',
  );
  String get pressBackAgainToExit => _t(
    'Press Back again to exit',
    'اضغط رجوع مرة أخرى للخروج',
    'باہر نکلنے کے لیے دوبارہ بیک دبائیں',
  );
  String noResultsFor(String q) => _t(
    'No titles match "$q" in this package',
    'لا توجد عناوين تطابق "$q" في هذه الباقة',
    'اس پیکیج میں "$q" سے کوئی عنوان نہیں ملا',
  );
  String searchInPackage(String name) => _t(
    'Search in $name',
    'ابحث في $name',
    '$name میں تلاش کریں',
  );
  /// Client 18 Oct #2: the provider allows one connection per subscription.
  String downloadPausedForPlayback(String title) => _t(
    'Download of "$title" is paused while you watch: your account allows one connection at a time. It continues by itself when you stop watching.',
    'تم إيقاف تنزيل "$title" مؤقتاً أثناء المشاهدة: يسمح حسابك باتصال واحد في كل مرة. سيستأنف التنزيل تلقائياً عند إيقاف المشاهدة.',
    '"$title" کا ڈاؤن لوڈ دیکھنے کے دوران رکا ہوا ہے: آپ کے اکاؤنٹ میں ایک وقت میں ایک کنکشن ہے۔ دیکھنا بند کرنے پر یہ خود جاری ہو جائے گا۔',
  );
  /// Client 5 Nov: the internet works, our server does not answer.
  String get serverUnavailablePlay => _t(
    '${AppBrand.name} could not reach its server. Your internet is working; the problem is on our side. Please tap Retry in a moment.',
    'تعذّر على ${AppBrand.name} الوصول إلى الخادم. اتصالك بالإنترنت يعمل، والمشكلة من جهتنا. يرجى الضغط على إعادة المحاولة بعد قليل.',
    '${AppBrand.name} اپنے سرور تک نہیں پہنچ سکا۔ آپ کا انٹرنیٹ ٹھیک ہے، مسئلہ ہماری طرف ہے۔ تھوڑی دیر بعد دوبارہ کوشش کریں۔',
  );
  String get homeServerUnavailable => _t(
    'The ${AppBrand.name} server is not answering right now. Your internet is working. Your downloads still play, and the content comes back by itself.',
    'خادم ${AppBrand.name} لا يستجيب حاليًا. اتصالك بالإنترنت يعمل. تنزيلاتك تعمل، وسيعود المحتوى تلقائيًا.',
    '${AppBrand.name} کا سرور اس وقت جواب نہیں دے رہا۔ آپ کا انٹرنیٹ ٹھیک ہے۔ ڈاؤن لوڈز چلتے رہیں گے اور مواد خود واپس آ جائے گا۔',
  );
  String get offlineBannerServer => _t(
    'Server not reachable right now (your internet works). You can watch your downloads.',
    'الخادم غير متاح حاليًا (اتصالك يعمل). يمكنك مشاهدة تنزيلاتك.',
    'سرور ابھی دستیاب نہیں (انٹرنیٹ ٹھیک ہے)۔ آپ اپنے ڈاؤن لوڈز دیکھ سکتے ہیں۔',
  );
  String get homeOffline => _t(
    'Could not reach ${AppBrand.name}. Check Wi-Fi or mobile data. Your downloads still play without internet.',
    'تعذر الوصول إلى ${AppBrand.name}. تحقق من Wi-Fi أو بيانات الجوال. تنزيلاتك تعمل بدون إنترنت.',
    '${AppBrand.name} تک رسائی نہیں ہو سکی۔ Wi-Fi یا موبائل ڈیٹا چیک کریں۔ آپ کے ڈاؤن لوڈز انٹرنیٹ کے بغیر چلتے ہیں۔',
  );
  /// TV order dialog: the remote moves packages, Back saves.
  String get arrangePackagesTvHint => _t(
    'OK picks a package up, Up / Down moves it, OK drops it. Back jumps to Save.',
    'موافق لاختيار الباقة، أعلى / أسفل لتحريكها، موافق لتثبيتها. رجوع للانتقال إلى حفظ.',
    'پیکیج اٹھانے کے لیے OK، منتقل کرنے کے لیے اوپر / نیچے، رکھنے کے لیے OK۔ Back سے محفوظ کریں پر جائیں۔',
  );
  String get backOnline =>
      _t('Back online', 'تم الاتصال مجدداً', 'دوبارہ آن لائن');

  /// Season tab label from the provider's own season number (0 = specials).
  String seasonTab(int n) => n == 0
      ? _t('Specials', 'حلقات خاصة', 'خصوصی اقساط')
      : _t('Season $n', 'الموسم $n', 'سیزن $n');
  String seasonsCount(int n) => n == 1
      ? _t('1 Season', 'موسم واحد', '1 سیزن')
      : _t('$n Seasons', '$n مواسم', '$n سیزن');
  String get episodes => _t('Episodes', 'الحلقات', 'اقساط');
  String get noEpisodesForSeason => _t(
    'No episodes are available for this season.',
    'لا توجد حلقات متاحة لهذا الموسم.',
    'اس سیزن کی کوئی قسط دستیاب نہیں۔',
  );
  /// The provider (Xtream source) refused or failed — not an app error.
  String get episodesSourceError => _t(
    'The content provider did not send the episodes for this series (source error). Please try again later.',
    'لم يرسل مزوّد المحتوى حلقات هذا المسلسل (خطأ من المصدر). يُرجى المحاولة لاحقًا.',
    'مواد فراہم کنندہ نے اس سیریز کی اقساط نہیں بھیجیں (سورس کی خرابی)۔ بعد میں دوبارہ کوشش کریں۔',
  );
  String get episodesLoadError => _t(
    'Could not load the episodes. Check the connection and try again.',
    'تعذّر تحميل الحلقات. تحقّق من الاتصال وحاول مجددًا.',
    'اقساط لوڈ نہیں ہو سکیں۔ کنکشن چیک کر کے دوبارہ کوشش کریں۔',
  );

  String get pressAgainToExit => _t(
    'Press again to exit',
    'اضغط مرة أخرى للخروج',
    'باہر نکلنے کے لیے دوبارہ دبائیں',
  );
  String get exitAppTitle =>
      _t('Exit ${AppBrand.name}?', 'الخروج من ${AppBrand.name}؟', '${AppBrand.name} سے باہر نکلیں؟');
  String get exitAppMessage => _t(
    'Are you sure you want to exit?',
    'هل أنت متأكد أنك تريد الخروج؟',
    'کیا آپ واقعی باہر نکلنا چاہتے ہیں؟',
  );
  String get exitAppConfirm => _t('Exit', 'خروج', 'باہر نکلیں');

  // ── Common chrome ────────────────────────────────────────────────
  String get next => _t('Next', 'التالي', 'اگلا');
  /// Autoplay countdown at the end of an episode.
  String nextEpisodeIn(int s) =>
      _t('Next episode in $s s', 'الحلقة التالية خلال $s ث', 'Next episode in $s s');
  String get getStarted => _t('Get Started', 'ابدأ', 'شروع کریں');
  String get howTo => _t('How to', 'كيف', 'کیسے');
  String get gotIt => _t('Got it', 'حسنًا', 'سمجھ گیا');
  String get confirm => _t('Confirm', 'تأكيد', 'تصدیق');
  String get success => _t('Success', 'نجاح', 'کامیاب');
  String get failed => _t('Failed', 'فشل', 'ناکام');
  String get searchTooltip => search;
  String get noTitlesInCategory => _t(
    'No titles in this category.',
    'لا عناوين في هذه الفئة.',
    'اس زمرے میں کوئی عنوان نہیں۔',
  );
  String get searchInSection =>
      _t('Search in this section…', 'ابحث في هذا القسم…', 'اس سیکشن میں تلاش…');
  String get livePreview =>
      _t('LIVE PREVIEW', 'معاينة مباشرة', 'لائیو پیش منظر');

  // ── Onboarding pages ─────────────────────────────────────────────
  String get onboardTitle1 =>
      _t('Up to 4K Playback', 'تشغيل حتى 4K', '4K تک پلے بیک');
  String get onboardBody1 => _t(
    'Plays 4K, HDR and Dolby Atmos when the stream and your device support them.',
    'يشغّل 4K وHDR وDolby Atmos عندما يدعمها البث وجهازك.',
    'جب اسٹریم اور آپ کا ڈیوائس سپورٹ کرے تو 4K، HDR اور Dolby Atmos چلاتا ہے۔',
  );
  String get onboardTitle2 =>
      _t('Live TV & Sports', 'بث مباشر ورياضة', 'لائیو ٹی وی اور سپورٹس');
  String get onboardBody2 => _t(
    'Follow matches, switch channels, and open the Match Center when your package includes Sports.',
    'تابع المباريات، بدّل القنوات، وافتح مركز المباريات عندما تشمل باقتك الرياضة.',
    'میچز فالو کریں، چینلز بدلیں، اور جب آپ کے پیکج میں سپورٹس ہو تو میچ سینٹر کھولیں۔',
  );
  String get onboardTitle3 => _t(
    'One Account, Every Screen',
    'حساب واحد، كل الشاشات',
    'ایک اکاؤنٹ، ہر اسکرین',
  );
  String get onboardBody3 => _t(
    'Profiles, Continue Watching and My List stay in sync across mobile and TV.',
    'الملفات ومتابعة المشاهدة وقائمتي تبقى متزامنة على الجوال والتلفزيون.',
    'پروفائلز، Continue Watching اور میری فہرست موبائل اور TV پر ہم آہنگ رہتی ہیں۔',
  );
  String get onboardTitle4 =>
      _t("You're in Control", 'أنت المتحكّم', 'آپ کنٹرول میں ہیں');
  String get onboardBody4 => _t(
    'Parental PIN, device sessions and theme ambience. Customize ${AppBrand.name} your way.',
    'رمز PIN للأهل وجلسات الأجهزة وأجواء السمة. خصّص ${AppBrand.name} بطريقتك.',
    'پیرنٹل PIN، ڈیوائس سیشنز اور تھیم ماحول۔ ${AppBrand.name} کو اپنے انداز میں بنائیں۔',
  );

  // ── Customize home ───────────────────────────────────────────────
  String get customizeHomeHint => _t(
    'Drag to reorder sections. Sports rows hide automatically without Sports package (when backend is live).',
    'اسحب لإعادة ترتيب الأقسام. صفوف الرياضة تُخفى تلقائياً بدون باقة الرياضة (عند تفعيل الخادم).',
    'سیکشنز دوبارہ ترتیب دینے کے لیے کھینچیں۔ سپورٹس پیکج کے بغیر سپورٹس قطاریں خود چھپ جاتی ہیں (جب بیک اینڈ لائیو ہو)۔',
  );
  String priorityN(int n) => _t('Priority $n', 'الأولوية $n', 'ترجیح $n');
  String get saveHomeLayout =>
      _t('Save Home Layout', 'حفظ تخطيط الرئيسية', 'ہوم لے آؤٹ محفوظ کریں');

  /// Localized label for persisted home-section ids (English titles are keys).
  String homeSectionLabel(String id) {
    switch (id) {
      case "Today's Matches":
        // Client 20 Oct: Home + Sports label is Matches & Lineups.
        return _t('Matches & Lineups', 'المباريات والتشكيلة', 'میچز اور لائن اپ');
      case 'Continue Watching':
        return _t('Continue Watching', 'متابعة المشاهدة', 'دیکھنا جاری رکھیں');
      // Stored section id kept; there is no ranking data, so not "Top 10".
      case 'Top 10 in Your Region':
        return _t('Weekly Picks', 'اختيارات الأسبوع', 'ہفتے کے انتخاب');
      case 'Arabic Originals':
        // Not "Originals": the app produces no content (client 6 Nov #6).
        return _t('Arabic Movies & Series', 'أفلام ومسلسلات عربية', 'عربی فلمیں اور سیریز');
      case 'Live TV & Channels':
        return _t(
          'Live TV & Channels',
          'بث مباشر وقنوات',
          'لائیو ٹی وی اور چینلز',
        );
      case 'Movies & 4K Blockbusters':
        return _t(
          'Movies & 4K Blockbusters',
          'أفلام وبلوك باسترز 4K',
          'فلمیں اور 4K بلاک بسٹرز',
        );
      case 'Series & Exclusive Seasons':
        return _t(
          'Series & Exclusive Seasons',
          'مسلسلات ومواسم حصرية',
          'سیریز اور خصوصی سیزنز',
        );
      case 'Kids':
        return kids;
      default:
        return id;
    }
  }

  /// Map common catalog/API category names (and slug-ish keys) to UI language.
  /// Task #143 #9: keep real names (beIN Sports, Alwan, MBC…). Only rewrite
  /// generic single-bucket labels, never collapse every sports-like name to Sports.
  String catalogCategoryLabel(String raw) {
    final trimmed = raw.trim();
    final k = trimmed.toLowerCase();
    if (k.isEmpty || k == 'all') return all;
    // Exact generic buckets only.
    if (k == 'sport' || k == 'sports' || k == 'رياضة') return sports;
    if (k == 'movie' || k == 'movies' || k == 'film' || k == 'films' || k == 'أفلام') {
      return movies;
    }
    if (k == 'series' || k == 'shows' || k == 'مسلسلات') return series;
    if (k == 'live' || k == 'live tv' || k == 'channels' || k == 'بث') {
      return liveTv;
    }
    if (k == 'kids' || k == 'kid' || k == 'children' || k == 'أطفال') return kids;
    if (k == 'news' || k == 'أخبار') return _t('News', 'أخبار', 'خبریں');
    if (k == 'music' || k == 'موسيقى') return _t('Music', 'موسيقى', 'موسیقی');
    // Preserve provider names as delivered by the catalog.
    return trimmed;
  }

  /// Drop category chips that display the same label (API often repeats names).
  List<T> withoutDuplicateCategoryLabels<T>(
    Iterable<T> items,
    String Function(T item) rawName,
  ) {
    final seen = <String>{};
    final out = <T>[];
    final allLabel = all.trim().toLowerCase();
    for (final item in items) {
      final label = catalogCategoryLabel(rawName(item)).trim().toLowerCase();
      if (label.isEmpty || label == allLabel) continue;
      if (seen.add(label)) out.add(item);
    }
    return out;
  }

  // ── Appearance ───────────────────────────────────────────────────
  String get curatedThemes => _t(
    'Curated Platform Themes',
    'سمات المنصة المختارة',
    'منتخب پلیٹ فارم تھیمز',
  );
  String get chooseThemeHint => _t(
    'Choose a theme. Changes apply across the app after you save.',
    'اختر سمة. تُطبَّق التغييرات على التطبيق بعد الحفظ.',
    'تھیم منتخب کریں۔ محفوظ کرنے کے بعد پوری ایپ پر لاگو ہوگا۔',
  );
  String get depth => _t('Depth', 'العمق', 'گہرائی');
  String get depthSoft => _t('Soft', 'ناعم', 'نرم');
  String get depthBalanced => _t('Balanced', 'متوازن', 'متوازن');
  String get depthStrong => _t('Strong', 'قوي', 'مضبوط');
  String get neonGlow => _t('Neon glow', 'توهج نيون', 'نیون گلو');
  String get reduceMotion =>
      _t('Reduce motion', 'تقليل الحركة', 'حرکت کم کریں');
  String get applyThemeSave => _t(
    'Apply Theme & Save Ambience',
    'تطبيق السمة وحفظ الأجواء',
    'تھیم لگائیں اور ماحول محفوظ کریں',
  );
  String get themeApplied => _t(
    'Theme applied across the app',
    'تم تطبيق السمة على التطبيق',
    'تھیم پوری ایپ پر لاگو ہو گئی',
  );
  String get themeCinematic =>
      _t('Cinematic', '${AppBrand.name} سينمائي', '${AppBrand.name} سنیماٹک');
  String get themeCinematicDesc => _t(
    'Pitch black base with electric cyan and magenta neon accents.',
    'قاعدة سوداء مع لمسات نيون سماوية وأرجوانية.',
    'گہرا سیاہ بیس برقی سائین اور میجنٹا نیون کے ساتھ۔',
  );
  String get themeMidnight => _t('Midnight', 'منتصف الليل', 'منصف رات');
  String get themeMidnightDesc => _t(
    'Deep navy base with crystalline electric cyan highlights.',
    'قاعدة كحلي عميق مع إبرازات سماوية كهربائية.',
    'گہرا نیوی بیس برقی سائین ہائی لائٹس کے ساتھ۔',
  );
  String get themeCarbon => _t('Carbon', 'كربون', 'کاربن');
  String get themeCarbonDesc => _t(
    'Matte charcoal base with subtle, dialed-in magenta lines.',
    'قاعدة فحم مطفية مع خطوط أرجوانية دقيقة.',
    'میٹ چارکول بیس ہلکی میجنٹا لائنز کے ساتھ۔',
  );
  String get themeDeepCinema => _t('Deep Cinema', 'سينما عميقة', 'ڈیپ سنیما');
  String get themeDeepCinemaDesc => _t(
    'Pure near-black with atmospheric vignette gradients.',
    'أسود شبه نقي مع تدرجات vignette جوية.',
    'قریب سیاہ پس منظر ماحولاتی vignette گریڈیئنٹس کے ساتھ۔',
  );

  // ── About ────────────────────────────────────────────────────────
  String get aboutAppName =>
      _t('${AppBrand.name} Mobile', '${AppBrand.name} للجوال', '${AppBrand.name} موبائل');
  /// The installed version and build (client 6 Nov #9: "v5.1.3 • Phase 1" was a
  /// fixed development label, not the installed app).
  String aboutVersionBadge(String version) =>
      _t('Version $version', 'الإصدار $version', 'ورژن $version');
  String get termsSubtitle => _t(
    'Acceptance, permitted use, and content responsibility',
    'القبول والاستخدام المسموح ومسؤولية المحتوى',
    'قبول، اجازت شدہ استعمال، اور مواد کی ذمہ داری',
  );
  String get privacySubtitle => _t(
    'Data collection, use, sharing, and your rights',
    'جمع البيانات واستخدامها ومشاركتها وحقوقك',
    'ڈیٹا جمع، استعمال، شیئرنگ اور آپ کے حقوق',
  );
  String get replayOnboarding =>
      _t('Replay Onboarding', 'إعادة التعريف', 'آن بورڈنگ دوبارہ');
  String get copyrightLine => _t(
    '© 2026 ${AppBrand.name}. All Rights Reserved.',
    '© 2026 ${AppBrand.name}. جميع الحقوق محفوظة.',
    '© 2026 ${AppBrand.name}۔ جملہ حقوق محفوظ ہیں۔',
  );

  // ── Audio prefs (ids stay EN; labels localize) ───────────────────
  String audioPrefLabel(String id) {
    switch (id) {
      case 'Dolby Atmos':
        return _t('Dolby Atmos', 'دولبي أتموس', 'ڈولبی اٹموس');
      case 'Stereo':
        return _t('Stereo', 'ستيريو', 'سٹیریو');
      case 'Arabic (Master)':
        return _t('Arabic (Master)', 'عربي (ماستر)', 'عربی (ماسٹر)');
      case 'English':
        return _t('English', 'إنجليزي', 'انگریزی');
      default:
        return id;
    }
  }

  // ── Security hub ─────────────────────────────────────────────────
  String get accountSecurityBadge =>
      _t('ACCOUNT SECURITY', 'أمان الحساب', 'اکاؤنٹ سیکیورٹی');
  String get signInToManageSecurity => _t(
    'Sign in to manage security.',
    'سجّل الدخول لإدارة الأمان.',
    'سیکیورٹی منتظم کرنے کے لیے سائن اِن کریں۔',
  );
  String securityStatusLine({
    required bool mfa,
    required bool emailVerified,
  }) => _t(
    'MFA ${mfa ? 'on' : 'off'} · Email ${emailVerified ? 'verified' : 'unverified'}',
    'المصادقة ${mfa ? 'مفعّلة' : 'متوقفة'} · البريد ${emailVerified ? 'موثّق' : 'غير موثّق'}',
    'MFA ${mfa ? 'آن' : 'آف'} · ای میل ${emailVerified ? 'تصدیق شدہ' : 'غیر تصدیق شدہ'}',
  );
  String get changePassword =>
      _t('Change password', 'تغيير كلمة المرور', 'پاس ورڈ تبدیل کریں');
  String get changePasswordSubtitle => _t(
    'Update your account password',
    'حدّث كلمة مرور حسابك',
    'اپنے اکاؤنٹ کا پاس ورڈ اپ ڈیٹ کریں',
  );
  String get changePasswordHint => _t(
    'Keep your account safe with a strong unique password.',
    'احمِ حسابك بكلمة مرور قوية وفريدة.',
    'مضبوط منفرد پاس ورڈ سے اکاؤنٹ محفوظ رکھیں۔',
  );
  String get passwordBadge => _t('PASSWORD', 'كلمة المرور', 'پاس ورڈ');
  String get changePasswordHelpTitle => _t(
    'How password change works',
    'كيف يعمل تغيير كلمة المرور',
    'پاس ورڈ تبدیل کیسے ہوتا ہے',
  );
  String get changePasswordHelpBody => _t(
    '1. Enter your current password\n'
        '2. Choose a new password (at least 8 characters)\n'
        '3. Tap Update. Revoke other sessions under Sessions if needed',
    '١. أدخل كلمة مرورك الحالية\n'
        '٢. اختر كلمة مرور جديدة (٨ أحرف على الأقل)\n'
        '٣. اضغط تحديث. ألغِ الجلسات الأخرى من الجلسات إن لزم',
    '١. اپنا موجودہ پاس ورڈ درج کریں\n'
        '٢. نیا پاس ورڈ چنیں (کم از کم ٨ حروف)\n'
        '٣. اپ ڈیٹ دبائیں۔ ضرورت ہو تو سیشنز سے دیگر سیشن منسوخ کریں',
  );
  String get currentPassword =>
      _t('Current password', 'كلمة المرور الحالية', 'موجودہ پاس ورڈ');
  String get newPassword =>
      _t('New password', 'كلمة المرور الجديدة', 'نیا پاس ورڈ');
  String get updatePassword =>
      _t('Update password', 'تحديث كلمة المرور', 'پاس ورڈ اپ ڈیٹ');
  String get updating => _t('Updating…', 'جارٍ التحديث…', 'اپ ڈیٹ ہو رہا ہے…');
  String get checkFields =>
      _t('Check fields', 'تحقق من الحقول', 'فیلڈز چیک کریں');
  String get passwordFieldsHint => _t(
    'Enter your current password and a new password (min 8 characters).',
    'أدخل كلمة مرورك الحالية وكلمة مرور جديدة (٨ أحرف على الأقل).',
    'موجودہ پاس ورڈ اور نیا پاس ورڈ درج کریں (کم از کم ٨ حروف)۔',
  );
  String get passwordUpdated =>
      _t('Password updated', 'تم تحديث كلمة المرور', 'پاس ورڈ اپ ڈیٹ ہو گیا');
  String get passwordUpdatedMsg => _t(
    'Your password was changed successfully.',
    'تم تغيير كلمة مرورك بنجاح.',
    'آپ کا پاس ورڈ کامیابی سے بدل گیا۔',
  );
  String get updateFailed => _t('Update failed', 'فشل التحديث', 'اپ ڈیٹ ناکام');

  String get mfaTitle => _t(
    'Multi-factor authentication',
    'المصادقة متعددة العوامل',
    'ملٹی فیکٹر تصدیق',
  );
  String get mfaSubtitleSetup => _t(
    'Set up authenticator app (QR / secret)',
    'إعداد تطبيق المصادقة (QR / السر)',
    'تصدیق ایپ سیٹ اپ (QR / خفیہ)',
  );
  String get mfaEnabledLabel =>
      _t('MFA is enabled', 'المصادقة مفعّلة', 'MFA فعال ہے');
  String get mfaProtectHint => _t(
    'Protect sign-in with an authenticator app.',
    'احمِ تسجيل الدخول بتطبيق مصادقة.',
    'تصدیق ایپ سے سائن اِن محفوظ کریں۔',
  );
  String get mfaBadge => _t('MFA', 'MFA', 'MFA');
  String get mfaStatusOff =>
      _t('Status: MFA is OFF', 'الحالة: المصادقة متوقفة', 'اسٹیٹس: MFA آف');
  String get mfaStatusOn =>
      _t('Status: MFA is ON', 'الحالة: المصادقة مفعّلة', 'اسٹیٹس: MFA آن');
  String get startMfaEnrollment =>
      _t('Start MFA enrollment', 'بدء تفعيل المصادقة', 'MFA اندراج شروع کریں');
  String get mfaHelpTitle => _t(
    'How to connect an authenticator',
    'كيف تربط تطبيق مصادقة',
    'تصدیق ایپ کیسے جوڑیں',
  );
  String get mfaHelpBody => _t(
    '1. Tap Start MFA enrollment\n'
        '2. Open Google Authenticator, Microsoft Authenticator, Authy, or similar\n'
        '3. Prefer Scan QR code. If scanning fails, choose Enter setup key and paste the secret\n'
        '4. Wait for a fresh 6-digit code (changes every ~30 seconds)\n'
        '5. Enter that code and tap Confirm MFA\n'
        '6. Copy and store the recovery codes offline',
    '١. اضغط بدء تفعيل المصادقة\n'
        '٢. افتح Google Authenticator أو Microsoft Authenticator أو Authy أو مشابهاً\n'
        '٣. فضّل مسح رمز QR. إن فشل المسح، اختر إدخال مفتاح الإعداد والصق السر\n'
        '٤. انتظر رمزاً جديداً من ٦ أرقام (يتغير كل ~٣٠ ثانية)\n'
        '٥. أدخل الرمز واضغط تأكيد المصادقة\n'
        '٦. انسخ رموز الاستعادة واحفظها دون اتصال',
    '١. MFA اندراج شروع دبائیں\n'
        '٢. Google Authenticator، Microsoft Authenticator، Authy یا ملتی جلتی ایپ کھولیں\n'
        '٣. QR اسکین ترجیح دیں۔ ناکام ہو تو سیٹ اپ کلید درج کریں اور خفیہ چسپاں کریں\n'
        '٤. تازہ ٦ ہندسوں کا کوڈ انتظار کریں (ہر ~٣٠ سیکنڈ بدلتا ہے)\n'
        '٥. کوڈ درج کریں اور MFA تصدیق دبائیں\n'
        '٦. ریکوری کوڈز کاپی کر کے آف لائن محفوظ کریں',
  );
  String get mfaWrongCodeHint => _t(
    'Wrong code? Wait for the next 30s code — do not reuse an old one.',
    'رمز خاطئ؟ انتظر الرمز التالي خلال ٣٠ ثانية — لا تُعد استخدام رمز قديم.',
    'غلط کوڈ؟ اگلا ٣٠ سیکنڈ والا کوڈ انتظار کریں — پرانا دوبارہ استعمال نہ کریں۔',
  );

  String get emailVerification =>
      _t('Email verification', 'توثيق البريد', 'ای میل تصدیق');
  String get emailVerifiedShort =>
      _t('Email verified', 'البريد موثّق', 'ای میل تصدیق شدہ');
  String get emailVerifySubtitle => _t(
    'Resend or confirm verification code',
    'أعد الإرسال أو أكّد رمز التوثيق',
    'کوڈ دوبارہ بھیجیں یا تصدیق کریں',
  );
  String get emailVerifyHint => _t(
    'Confirm ownership of the email on your account.',
    'أكّد ملكية البريد المرتبط بحسابك.',
    'اپنے اکاؤنٹ کی ای میل کی ملکیت تصدیق کریں۔',
  );
  String get emailBadge => _t('EMAIL', 'البريد', 'ای میل');
  String get emailVerifyHelpTitle => _t(
    'How email verification works',
    'كيف يعمل توثيق البريد',
    'ای میل تصدیق کیسے ہوتی ہے',
  );
  String get emailVerifyHelpBody => _t(
    '1. Confirm the email/username for your account\n'
        '2. Tap Resend code — if the account exists, a code is sent\n'
        '3. Enter the code and tap Verify email',
    '١. أكّد البريد/اسم المستخدم لحسابك\n'
        '٢. اضغط إعادة إرسال الرمز — إن وُجد الحساب يُرسل رمز\n'
        '٣. أدخل الرمز واضغط توثيق البريد',
    '١. اپنے اکاؤنٹ کی ای میل/یوزرنیم تصدیق کریں\n'
        '٢. کوڈ دوبارہ بھیجیں دبائیں — اکاؤنٹ موجود ہو تو کوڈ جاتا ہے\n'
        '٣. کوڈ درج کر کے ای میل تصدیق دبائیں',
  );
  String emailStatusVerified(String email) => _t(
    'Status: verified ($email)',
    'الحالة: موثّق ($email)',
    'اسٹیٹس: تصدیق شدہ ($email)',
  );
  String get emailStatusUnverified =>
      _t('Status: not verified', 'الحالة: غير موثّق', 'اسٹیٹس: غیر تصدیق شدہ');
  String get resendCode =>
      _t('Resend code', 'إعادة إرسال الرمز', 'کوڈ دوبارہ بھیجیں');
  String get verificationCode =>
      _t('Verification code', 'رمز التوثيق', 'تصدیقی کوڈ');
  String get verifyEmail => _t('Verify email', 'توثيق البريد', 'ای میل تصدیق');
  String get sessionsNavSubtitle => _t(
    'Active logins · sign out everywhere',
    'تسجيلات نشطة · الخروج من كل الأماكن',
    'فعال لاگ اِن · ہر جگہ سائن آؤٹ',
  );

  String get scanThisQr =>
      _t('Scan this QR', 'امسح رمز QR', 'یہ QR اسکین کریں');
  String get orEnterSecretManually => _t(
    'Or enter this secret manually',
    'أو أدخل هذا السر يدوياً',
    'یا یہ خفیہ دستی درج کریں',
  );
  String get copySecret => _t('Copy secret', 'نسخ السر', 'خفیہ کاپی کریں');
  String get secretCopied =>
      _t('Secret copied', 'تم نسخ السر', 'خفیہ کاپی ہو گیا');
  String get authenticatorCode => _t(
    '6-digit authenticator code',
    'رمز المصادقة (٦ أرقام)',
    '٦ ہندسوں کا تصدیقی کوڈ',
  );
  String get confirmMfa => _t('Confirm MFA', 'تأكيد المصادقة', 'MFA تصدیق');
  String get disableMfa => _t('Disable MFA', 'تعطيل المصادقة', 'MFA بند کریں');
  String get passwordToDisableMfa => _t(
    'Account password to disable MFA',
    'كلمة مرور الحساب لتعطيل المصادقة',
    'MFA بند کرنے کے لیے اکاؤنٹ پاس ورڈ',
  );
  String get recoveryCodesSaveNow => _t(
    'Recovery codes (save now)',
    'رموز الاستعادة (احفظها الآن)',
    'ریکوری کوڈز (ابھی محفوظ کریں)',
  );
  String get copyAllCodes =>
      _t('Copy all codes', 'نسخ كل الرموز', 'سب کوڈز کاپی کریں');
  String get recoveryCodesCopied => _t(
    'Recovery codes copied',
    'تم نسخ رموز الاستعادة',
    'ریکوری کوڈز کاپی ہو گئے',
  );
  String get mfaEnrollSnack => _t(
    'Scan the QR or enter the secret, then confirm with a fresh code.',
    'امسح رمز QR أو أدخل السر، ثم أكّد برمز جديد.',
    'QR اسکین کریں یا خفیہ درج کریں، پھر تازہ کوڈ سے تصدیق کریں۔',
  );
  String get enrollmentFailed =>
      _t('Enrollment failed', 'فشل التفعيل', 'اندراج ناکام');
  String get codeRequired => _t('Code required', 'الرمز مطلوب', 'کوڈ درکار');
  String get enterSixDigitCode => _t(
    'Enter the current 6-digit code from your authenticator app.',
    'أدخل الرمز الحالي من ٦ أرقام من تطبيق المصادقة.',
    'اپنی تصدیق ایپ سے موجودہ ٦ ہندسوں کا کوڈ درج کریں۔',
  );
  String get emailConfirmedMsg => _t(
    'Your email is confirmed on this account.',
    'تم تأكيد بريدك على هذا الحساب.',
    'آپ کی ای میل اس اکاؤنٹ پر تصدیق ہو گئی۔',
  );
  String get verificationFailed =>
      _t('Verification failed', 'فشل التوثيق', 'تصدیق ناکام');
  String get missingLogin =>
      _t('Missing login', 'بيانات الدخول ناقصة', 'لاگ اِن غائب');
  String get enterLoginFirst => _t(
    'Enter email / username first.',
    'أدخل البريد / اسم المستخدم أولاً.',
    'پہلے ای میل / یوزرنیم درج کریں۔',
  );
  String get codeSent => _t('Code sent', 'تم إرسال الرمز', 'کوڈ بھیج دیا');
  String get couldNotResend =>
      _t('Could not resend', 'تعذّر إعادة الإرسال', 'دوبارہ نہیں بھیج سکے');
  String get missingFields => _t('Missing fields', 'حقول ناقصة', 'فیلڈز غائب');
  String get vipPriorityChat =>
      _t('VIP priority chat', 'دردشة VIP أولوية', 'VIP ترجیحی چیٹ');
  String get vipPriorityChatHint => _t(
    'Support channel for VIP Ultra',
    'قناة دعم لـ VIP Ultra',
    'VIP Ultra کے لیے سپورٹ چینل',
  );
  String get accountPinComingSoon => _t(
    'Account PIN coming soon',
    'رمز PIN للحساب قريباً',
    'اکاؤنٹ PIN جلد آرہا ہے',
  );
  String get accountPinComingSoonHint => _t(
    'Set and sync household PINs with the backend when parental APIs are available. Profile PINs still work locally when selecting a locked profile.',
    'اضبط رموز PIN للمنزل وزامنها مع الخادم عند توفر واجهات الرقابة الأبوية. رموز PIN للملفات ما زالت تعمل محلياً عند اختيار ملف مقفل.',
    'پیرنٹل APIs دستیاب ہوں تو گھریلو PIN سیٹ اور ہم آہنگ کریں۔ مقفل پروفائل منتخب کرتے وقت مقامی PIN اب بھی کام کرتی ہے۔',
  );

  // ── Notifications / parental ─────────────────────────────────────
  String get notificationsDeviceHint => _t(
    'These preferences are stored on this device.',
    'تُحفظ هذه التفضيلات على هذا الجهاز.',
    'یہ ترجیحات اس آلے پر محفوظ ہیں۔',
  );
  String get pushNotifications =>
      _t('Push notifications', 'إشعارات الدفع', 'پش نوٹیفکیشنز');
  String get pushNotificationsHint => _t(
    'New episodes, reminders, and account alerts',
    'حلقات جديدة وتذكيرات وتنبيهات الحساب',
    'نئے اقساط، یاد دہانیاں اور اکاؤنٹ الرٹس',
  );
  String get savedOnDevice =>
      _t('Saved on device', 'حُفظ على الجهاز', 'آلے پر محفوظ');
  String get emailAlerts =>
      _t('Email alerts', 'تنبيهات البريد', 'ای میل الرٹس');
  String get comingWithBackend =>
      _t('Coming with backend', 'قريباً مع الخادم', 'بیک اینڈ کے ساتھ جلد');
  String get profileDisplayName => _t('Display name', 'الاسم', 'Display name');
  String get profileKidsMode => _t('Kids mode', 'وضع الأطفال', 'Kids mode');
  String get profileKidsModeHint => _t("Only children's titles and channels", 'محتوى ومحطات الأطفال فقط', "Only children's titles and channels");
  String get profileLock => _t('Profile lock', 'قفل الملف', 'Profile lock');
  String get profileLockHint => _t('Ask for the Kids PIN to open this profile', 'طلب رمز الأطفال لفتح هذا الملف', 'Ask for the Kids PIN to open this profile');
  String get profileLockNeedsPin => _t('Set up the Kids PIN first (Parental controls).', 'اضبط رمز الأطفال أولاً (الرقابة الأبوية).', 'Set up the Kids PIN first (Parental controls).');
  String get profileSaved => _t('Profile saved', 'تم حفظ الملف', 'Profile saved');
  String get profileSwitchTo => _t('Switch to this profile', 'التبديل إلى هذا الملف', 'Switch to this profile');
  String get profileActiveNow => _t('Currently active', 'الملف الحالي', 'Currently active');
  String get profileAppLanguageHint => _t('App language (all profiles)', 'لغة التطبيق (لكل الملفات)', 'App language (all profiles)');
  String get liveSeekNotReady => _t(
    'Rewind is available after a few seconds of watching.',
    'الترجيع متاح بعد بضع ثوانٍ من المشاهدة.',
    'Rewind is available after a few seconds of watching.',
  );
  String get updateAvailableTitle => _t('Update available', 'تحديث متاح', 'Update available');
  String updateAvailableBody(String v) => _t(
    'A new version of ${AppBrand.name} ($v) is ready.',
    'إصدار جديد من ${AppBrand.name} ($v) جاهز.',
    'A new version of ${AppBrand.name} ($v) is ready.',
  );
  String get updateNow => _t('Update', 'تحديث', 'Update');
  String get updateLater => _t('Later', 'لاحقاً', 'Later');
  // Update screen (phone + TV): was English only.
  String get updateAppTitle =>
      _t('Update App', 'تحديث التطبيق', 'Update App');
  String get updateRequiredBody => _t(
    'A new version of ${AppBrand.name} is available. Please update to continue.',
    'يتوفر إصدار جديد من ${AppBrand.name}. يرجى التحديث للمتابعة.',
    'A new version of ${AppBrand.name} is available. Please update to continue.',
  );
  String updateInstalledLine(String version, int build, String latest) => _t(
    'Installed v$version ($build)\nLatest $latest',
    'المثبّت v$version ($build)\nالأحدث $latest',
    'Installed v$version ($build)\nLatest $latest',
  );
  String get updateOpenDownloadPage =>
      _t('Open download page', 'فتح صفحة التنزيل', 'Open download page');
  String updateDownloaderHint(String url) => _t(
    'Or open Downloader and use:\n$url',
    'أو افتح تطبيق Downloader واستخدم:\n$url',
    'Or open Downloader and use:\n$url',
  );
  String get updateDownloading =>
      _t('Downloading update', 'جارٍ تنزيل التحديث', 'Downloading update');
  String get updateStarting => _t('Starting…', 'جارٍ البدء…', 'Starting…');
  // Texts that were English only on some screens (10 Nov audit).
  String get back => _t('Back', 'رجوع', 'واپس');
  String get ok => _t('OK', 'حسناً', 'ٹھیک ہے');
  String get refresh => _t('Refresh', 'تحديث', 'ریفریش');
  String get copyText => _t('Copy', 'نسخ', 'کاپی');
  String get copiedForSupport => _t(
    'Copied. Paste it to support.',
    'تم النسخ. ألصقه في رسالة الدعم.',
    'کاپی ہو گیا۔ اسے سپورٹ کو بھیجیں۔',
  );
  String get playbackDetails =>
      _t('Playback details', 'تفاصيل التشغيل', 'پلے بیک کی تفصیلات');
  String get playbackDetailsHint => _t(
    'Timing report for support (no account data)',
    'تقرير توقيت للدعم (بدون بيانات الحساب)',
    'سپورٹ کے لیے ٹائمنگ رپورٹ (اکاؤنٹ ڈیٹا کے بغیر)',
  );
  String get couldNotSaveSetting => _t(
    'Could not save the setting',
    'تعذر حفظ الإعداد',
    'سیٹنگ محفوظ نہیں ہو سکی',
  );
  String get profileNotFound =>
      _t('Profile not found', 'الملف غير موجود', 'پروفائل نہیں ملا');
  String removeProfileTitle(String name) =>
      _t('Remove $name?', 'إزالة $name؟', '$name کو ہٹائیں؟');
  String get removeProfileBody => _t(
    'This deletes the profile from your account.',
    'سيؤدي هذا إلى حذف الملف من حسابك.',
    'یہ پروفائل آپ کے اکاؤنٹ سے حذف ہو جائے گا۔',
  );
  String get profileRemoveRow =>
      _t('Remove profile', 'إزالة الملف', 'پروفائل ہٹائیں');
  String get profileRemoveRowHint =>
      _t('Delete from account', 'حذف من الحساب', 'اکاؤنٹ سے حذف کریں');
  String get profileStatus => _t('Status', 'الحالة', 'حیثیت');
  String get profileInactive => _t('Inactive', 'غير نشط', 'غیر فعال');
  String get pinLock => _t('PIN lock', 'قفل الرمز', 'PIN لاک');
  String get pinNotSet => _t('Not set', 'غير مضبوط', 'سیٹ نہیں');
  String get pinRemove => _t('Remove PIN', 'إزالة الرمز', 'PIN ہٹائیں');
  String get pinRemoveHint =>
      _t('Unlock profile', 'فتح قفل الملف', 'پروفائل اَن لاک کریں');
  String get pinSetTitle => _t('Set PIN', 'تعيين الرمز', 'PIN سیٹ کریں');
  String get pinChangeTitle => _t('Change PIN', 'تغيير الرمز', 'PIN تبدیل کریں');
  String get pinEnterFour => _t(
    'Enter a 4-digit PIN',
    'أدخل رمزاً من 4 أرقام',
    '4 ہندسوں کا PIN درج کریں',
  );
  String get saving => _t('Saving…', 'جارٍ الحفظ…', 'محفوظ ہو رہا ہے…');
  // Badges on the shared alerts / toasts (were English capitals).
  String get alertSuccess => _t('SUCCESS', 'تم', 'کامیاب');
  String get alertFailed => _t('FAILED', 'فشل', 'ناکام');
  String get alertWarning => _t('WARNING', 'تنبيه', 'انتباہ');
  String get alertAttention => _t('ATTENTION', 'ملاحظة', 'توجہ');
  String get alertConfirm => _t('CONFIRM', 'تأكيد', 'تصدیق');
  String get alertSuccessTitle => _t('Success', 'تم بنجاح', 'کامیاب');
  String get alertFailedTitle => _t('Failed', 'فشل', 'ناکام');
  String get displaySettings =>
      _t('Display Settings', 'إعدادات العرض', 'ڈسپلے سیٹنگز');
  String get backgroundIntensity =>
      _t('Background Intensity', 'شدة الخلفية', 'پس منظر کی شدت');
  String get accentGlow => _t('Accent Glow', 'توهج اللون', 'رنگ کی چمک');
  String get motionLabel => _t('Motion', 'الحركة', 'حرکت');
  String get cardFocusAnimation =>
      _t('Card Focus Animation', 'حركة تحديد البطاقة', 'کارڈ فوکس اینیمیشن');
  String get primaryBadge => _t('PRIMARY', 'رئيسي', 'بنیادی');
  String get titleLoadFailed => _t(
    'This title could not be loaded. Go back and try again.',
    'تعذر تحميل هذا العنوان. ارجع وحاول مرة أخرى.',
    'یہ ٹائٹل لوڈ نہیں ہو سکا۔ واپس جا کر دوبارہ کوشش کریں۔',
  );
  String get offlineFileMissing => _t(
    'The downloaded file is missing.',
    'الملف الذي تم تنزيله غير موجود.',
    'ڈاؤن لوڈ کی گئی فائل موجود نہیں۔',
  );
  String get offlineCannotPlay => _t(
    'This file cannot be played.',
    'لا يمكن تشغيل هذا الملف.',
    'یہ فائل نہیں چل سکتی۔',
  );
  String get offlineSubscriptionEnded => _t(
    'Your subscription has ended. Downloads can be watched again after renewal.',
    'انتهى اشتراكك. يمكن مشاهدة التنزيلات مرة أخرى بعد التجديد.',
    'آپ کی سبسکرپشن ختم ہو گئی ہے۔ تجدید کے بعد ڈاؤن لوڈز دوبارہ دیکھے جا سکتے ہیں۔',
  );
  String get offlineCheckInNeeded => _t(
    'Connect to the internet once so ${AppBrand.name} can confirm your subscription, then play your downloads.',
    'اتصل بالإنترنت مرة واحدة ليتحقق ${AppBrand.name} من اشتراكك، ثم شغّل التنزيلات.',
    'ایک بار انٹرنیٹ سے جڑیں تاکہ ${AppBrand.name} آپ کی سبسکرپشن کی تصدیق کر سکے، پھر ڈاؤن لوڈز چلائیں۔',
  );
  String get offlineClockChanged => _t(
    "Your device's date and time look wrong. Connect to the internet and try again.",
    'يبدو أن تاريخ ووقت جهازك غير صحيحين. اتصل بالإنترنت وحاول مرة أخرى.',
    'آپ کی ڈیوائس کی تاریخ اور وقت غلط لگتے ہیں۔ انٹرنیٹ سے جڑیں اور دوبارہ کوشش کریں۔',
  );
  String get devicesRegisteredShort => _t(
    'Registered phones & TVs',
    'الهواتف وأجهزة التلفاز المسجلة',
    'رجسٹرڈ فون اور ٹی وی',
  );
  String devicesHelpBody(String here) => _t(
    'Rename devices. Revoke others you do not trust. The primary phone cannot be revoked from $here; use recovery if it is lost.',
    'أعد تسمية الأجهزة. ألغِ الأجهزة التي لا تثق بها. لا يمكن إلغاء الهاتف الرئيسي من $here؛ استخدم الاستعادة إذا فُقد.',
    'ڈیوائسز کا نام بدلیں۔ جن پر بھروسہ نہیں انہیں ہٹا دیں۔ بنیادی فون $here سے نہیں ہٹایا جا سکتا؛ گم ہونے پر ریکوری استعمال کریں۔',
  );
  String get thisTvWord => _t('this TV', 'هذا التلفاز', 'اس ٹی وی');
  String get thisPcWord => _t('this PC', 'هذا الكمبيوتر', 'اس پی سی');
  String get sportsNotInPackage => _t(
    'Sports is not included in your current package.',
    'الرياضة غير مشمولة في باقتك الحالية.',
    'اسپورٹس آپ کے موجودہ پیکیج میں شامل نہیں۔',
  );
  String get recoveryLoginHint => _t(
    'Sign in with password plus a one-time recovery code. This revokes other sessions.',
    'سجّل الدخول بكلمة المرور ورمز استعادة لمرة واحدة. سيؤدي ذلك إلى إنهاء الجلسات الأخرى.',
    'پاس ورڈ اور ایک بار کے ریکوری کوڈ سے سائن اِن کریں۔ اس سے دوسرے سیشن ختم ہو جائیں گے۔',
  );
  String get emailOrUsernameLabel =>
      _t('Email or username', 'البريد الإلكتروني أو اسم المستخدم', 'ای میل یا صارف نام');
  String get playbackLiveNoSeek =>
      _t('Playback: Live (no seek)', 'التشغيل: مباشر (بدون تقديم)', 'پلے بیک: لائیو (آگے پیچھے نہیں)');
  String infoCategory(String v) => _t('Category: $v', 'الفئة: $v', 'زمرہ: $v');
  String infoEpisode(String v) => _t('Episode: $v', 'الحلقة: $v', 'قسط: $v');
  String infoYear(String v) => _t('Year: $v', 'السنة: $v', 'سال: $v');
  String infoDuration(String v) => _t('Duration: $v', 'المدة: $v', 'دورانیہ: $v');
  String infoQuality(String v) => _t('Quality: $v', 'الجودة: $v', 'کوالٹی: $v');
  String get playAnyway => _t('Play anyway', 'شغّل على أي حال', 'پھر بھی چلائیں');
  String get renameProfile =>
      _t('Rename profile', 'إعادة تسمية الملف', 'پروفائل کا نام بدلیں');
  String get editProfileDetails => _t(
    'Edit Profile Details',
    'تعديل بيانات الملف',
    'پروفائل کی تفصیلات میں ترمیم',
  );
  String get smoothTransitionsHint => _t(
    'Smooth interface transitions',
    'انتقالات سلسة في الواجهة',
    'انٹرفیس میں ہموار تبدیلیاں',
  );
  String get devicesRegisteredHint => _t(
    'Phones and TVs registered to this account',
    'الهواتف وأجهزة التلفاز المسجلة في هذا الحساب',
    'اس اکاؤنٹ پر رجسٹرڈ فون اور ٹی وی',
  );
  String get addedToMyList =>
      _t('Added to My List', 'أُضيف إلى قائمتي', 'میری فہرست میں شامل');
  String get removedFromMyList =>
      _t('Removed from My List', 'أُزيل من قائمتي', 'میری فہرست سے ہٹا دیا');
  String get noEpisodesYet => _t(
    'No episodes available yet. Try again.',
    'لا توجد حلقات متاحة بعد. حاول مرة أخرى.',
    'ابھی کوئی قسط دستیاب نہیں۔ دوبارہ کوشش کریں۔',
  );
  String searchNoResults(String q) =>
      _t('No results for “$q”', 'لا نتائج لـ «$q»', '“$q” کے کوئی نتائج نہیں');
  String get searchNoResultsHint => _t(
    'Try another title or genre.',
    'جرّب عنواناً أو نوعاً آخر.',
    'کوئی اور عنوان یا صنف آزمائیں۔',
  );
  String get mfaPasswordRequired =>
      _t('Password required', 'كلمة المرور مطلوبة', 'پاس ورڈ درکار ہے');
  String get mfaDisablePasswordHint => _t(
    'Enter your account password to disable MFA.',
    'أدخل كلمة مرور حسابك لإيقاف المصادقة الثنائية.',
    'MFA بند کرنے کے لیے اکاؤنٹ کا پاس ورڈ درج کریں۔',
  );
  String get mfaDisableTitle =>
      _t('Disable MFA?', 'إيقاف المصادقة الثنائية؟', 'MFA بند کریں؟');
  String get mfaDisableBody => _t(
    'Authenticator codes will no longer be required at sign-in.',
    'لن تكون رموز تطبيق المصادقة مطلوبة عند تسجيل الدخول.',
    'سائن اِن پر تصدیقی کوڈ کی ضرورت نہیں رہے گی۔',
  );
  String get mfaDisabledDone => _t(
    'Two-factor authentication is off.',
    'تم إيقاف المصادقة الثنائية.',
    'دو مرحلہ تصدیق بند ہے۔',
  );
  String get mfaCodeTitle =>
      _t('Two-factor code', 'رمز التحقق الثنائي', 'دو مرحلہ کوڈ');
  String get mfaCodeHint => _t(
    'Enter the 6-digit code from your authenticator app.',
    'أدخل الرمز المكوّن من 6 أرقام من تطبيق المصادقة.',
    'تصدیقی ایپ سے 6 ہندسوں کا کوڈ درج کریں۔',
  );
  String get mfaCodeLabel =>
      _t('Authentication code', 'رمز المصادقة', 'تصدیقی کوڈ');
  String get mfaVerifyContinue =>
      _t('Verify and continue', 'تحقق وتابع', 'تصدیق کریں اور جاری رکھیں');
  String get mfaUseRecoveryCode =>
      _t('Use a recovery code', 'استخدم رمز الاستعادة', 'ریکوری کوڈ استعمال کریں');
  String get recoveryLoginTitle =>
      _t('Recovery login', 'الدخول برمز الاستعادة', 'ریکوری لاگ اِن');
  String get recoveryCodeLabel =>
      _t('Recovery code', 'رمز الاستعادة', 'ریکوری کوڈ');
  String get recoverySignIn => _t(
    'Sign in with recovery',
    'تسجيل الدخول بالاستعادة',
    'ریکوری کے ساتھ سائن اِن',
  );
  String get updateAllowInstall => _t(
    'Allow ${AppBrand.name} to install updates, then press Update again.',
    'اسمح لـ ${AppBrand.name} بتثبيت التحديثات، ثم اضغط تحديث مرة أخرى.',
    'Allow ${AppBrand.name} to install updates, then press Update again.',
  );
  String get kidsPinTitle => _t('Kids PIN', 'رمز الأطفال', 'Kids PIN');
  String get kidsPinHint => _t('Asked when someone leaves a Kids profile for another profile.', 'يُطلب عند الخروج من ملف الأطفال إلى ملف آخر.', 'Asked when someone leaves a Kids profile for another profile.');
  String get kidsPinSetUp => _t('Set up Kids PIN', 'إعداد رمز الأطفال', 'Set up Kids PIN');
  String get kidsPinChange => _t('Change PIN / forgot PIN', 'تغيير الرمز / نسيت الرمز', 'Change PIN / forgot PIN');
  String get kidsPinRemove => _t('Turn off Kids PIN', 'إيقاف رمز الأطفال', 'Turn off Kids PIN');
  String get kidsPinEnter => _t('Enter the Kids PIN', 'أدخل رمز الأطفال', 'Enter the Kids PIN');
  String get kidsPinEnterHint => _t('Needed to leave the Kids profile.', 'مطلوب للخروج من ملف الأطفال.', 'Needed to leave the Kids profile.');
  String get kidsPinNew => _t('New 4-digit PIN', 'رمز جديد من 4 أرقام', 'New 4-digit PIN');
  String get kidsPinRepeat => _t('Repeat the PIN', 'أعد إدخال الرمز', 'Repeat the PIN');
  String get kidsPinMismatch => _t('The PINs do not match.', 'الرمزان غير متطابقين.', 'The PINs do not match.');
  String get kidsPinFormat => _t('The PIN must be 4 digits.', 'يجب أن يتكون الرمز من 4 أرقام.', 'The PIN must be 4 digits.');
  String get kidsPinAccountPassword => _t('${AppBrand.name} account password', 'كلمة مرور حساب ${AppBrand.name}', '${AppBrand.name} account password');
  String get kidsPinPasswordHint => _t('Your account password confirms it is you. Forgot the PIN? Set a new one here with your password.', 'كلمة مرور الحساب تؤكد أنك صاحب الحساب. نسيت الرمز؟ اضبط رمزًا جديدًا هنا بكلمة المرور.', 'Your account password confirms it is you. Forgot the PIN? Set a new one here with your password.');
  String get kidsPinLocked => _t('Too many wrong PINs. Try again in 15 minutes, or set a new PIN in Settings → Parental controls.', 'محاولات خاطئة كثيرة. حاول بعد 15 دقيقة، أو اضبط رمزًا جديدًا من الإعدادات ← الرقابة الأبوية.', 'Too many wrong PINs. Try again in 15 minutes, or set a new PIN in Settings → Parental controls.');
  String get kidsPinWrongPassword => _t('Wrong account password.', 'كلمة مرور الحساب غير صحيحة.', 'Wrong account password.');
  String get kidsPinSaved => _t('Kids PIN saved.', 'تم حفظ رمز الأطفال.', 'Kids PIN saved.');
  String get kidsPinRemoved => _t('Kids PIN turned off.', 'تم إيقاف رمز الأطفال.', 'Kids PIN turned off.');
  String get kidsPinOffline => _t('No connection, so the PIN could not be checked. Try again.', 'لا يوجد اتصال، تعذّر التحقق من الرمز. حاول مجددًا.', 'No connection, so the PIN could not be checked. Try again.');
  String get kidsPinOnPhone => _t('Set, change or turn off the Kids PIN in the phone app: Settings → Parental controls.', 'اضبط رمز الأطفال أو غيّره أو أوقفه من تطبيق الهاتف: الإعدادات ← الرقابة الأبوية.', 'Set, change or turn off the Kids PIN in the phone app: Settings → Parental controls.');
  String get kidsPinIsOn => _t('On', 'مفعّل', 'On');
  String kidsPinWrong(int? left) => left == null
      ? _t('Wrong PIN.', 'رمز خاطئ.', 'Wrong PIN.')
      : _t('Wrong PIN. $left tries left.', 'رمز خاطئ. المحاولات المتبقية: $left', 'Wrong PIN. $left tries left.');
  String get parentalPinTitle => _t(
    'Require PIN for kids profile',
    'اطلب PIN لملف الأطفال',
    'کڈز پروفائل کے لیے PIN',
  );
  String get parentalPinHint => _t(
    'Ask for PIN when switching into a kids profile',
    'اطلب PIN عند التحويل لملف أطفال',
    'کڈز پروفائل میں جانے پر PIN مانگیں',
  );

  // ── Panels: "Choose your panel", connect form, My panels (Phase 5.6) ──
  String get choosePanelTitle => _t('Choose your panel', 'اختر لوحتك', 'Choose your panel');
  String get choosePanelBody => _t('Connect the IPTV service you already have. Your login stays on this device.', 'اربط خدمة IPTV التي لديك. بيانات الدخول تبقى على هذا الجهاز.', 'Connect the IPTV service you already have. Your login stays on this device.');
  String get panelXtream => _t('Xtream Codes', 'Xtream Codes', 'Xtream Codes');
  String get panelXtreamDesc => _t('Server URL, username and password', 'رابط الخادم واسم المستخدم وكلمة المرور', 'Server URL, username and password');
  String get panelM3u => _t('M3U playlist', 'قائمة M3U', 'M3U playlist');
  String get panelM3uDesc => _t('Playlist link', 'رابط قائمة التشغيل', 'Playlist link');
  String get panelStalker => _t('Stalker portal (MAC)', 'بوابة Stalker (MAC)', 'Stalker portal (MAC)');
  String get panelStalkerDesc => _t('Portal URL and MAC address', 'رابط البوابة وعنوان MAC', 'Portal URL and MAC address');
  String get fieldServerUrl => _t('Server URL', 'رابط الخادم', 'Server URL');
  String get fieldUsername => _t('Username', 'اسم المستخدم', 'Username');
  String get fieldPassword => _t('Password', 'كلمة المرور', 'Password');
  String get fieldPlaylistUrl => _t('Playlist URL', 'رابط قائمة التشغيل', 'Playlist URL');
  String get fieldEpgUrl => _t('EPG URL (optional)', 'رابط دليل البرامج (اختياري)', 'EPG URL (optional)');
  String get fieldPortalUrl => _t('Portal URL', 'رابط البوابة', 'Portal URL');
  String get fieldMac => _t('MAC address', 'عنوان MAC', 'MAC address');
  String get fieldPanelName => _t('Name (optional)', 'الاسم (اختياري)', 'Name (optional)');
  String get macDeviceHint => _t('This is your device MAC. Give it to your provider, or type the MAC they registered. It keeps working on any Wi-Fi.', 'هذا عنوان MAC لجهازك. أعطه لمزوّدك أو اكتب العنوان المسجّل لديه. يعمل على أي شبكة Wi-Fi.', 'This is your device MAC. Give it to your provider, or type the MAC they registered. It keeps working on any Wi-Fi.');
  String get macCopied => _t('MAC copied', 'تم نسخ عنوان MAC', 'MAC copied');
  String get connectPanel => _t('Connect', 'اتصال', 'Connect');
  String get panelConnected => _t('Connected', 'تم الاتصال', 'Connected');
  String get errFieldRequired => _t('Required', 'مطلوب', 'Required');
  String get errInvalidUrl => _t('Enter a valid link (http://…)', 'أدخل رابطًا صحيحًا (http://…)', 'Enter a valid link (http://…)');
  String get errInvalidMac => _t('MAC looks like 00:1A:79:12:34:56', 'عنوان MAC بالشكل 00:1A:79:12:34:56', 'MAC looks like 00:1A:79:12:34:56');
  String get panelErrUnauthorized => _t('Wrong login, or this line is not active. Check the details from your provider.', 'بيانات الدخول خاطئة أو الاشتراك غير مفعّل. تحقق من البيانات من مزوّدك.', 'Wrong login, or this line is not active. Check the details from your provider.');
  String get panelErrExpired => _t('This subscription has expired. Renew it with your provider.', 'انتهى هذا الاشتراك. جدّده لدى مزوّدك.', 'This subscription has expired. Renew it with your provider.');
  String get panelErrBanned => _t('This line is blocked by the provider.', 'هذا الخط محظور من المزوّد.', 'This line is blocked by the provider.');
  String get panelErrNetwork => _t("Can't reach the server. Check the link and your internet.", 'تعذّر الوصول إلى الخادم. تحقق من الرابط والإنترنت.', "Can't reach the server. Check the link and your internet.");
  String get panelErrTimeout => _t('The server took too long to answer. Try again.', 'الخادم تأخر في الرد. حاول مرة أخرى.', 'The server took too long to answer. Try again.');
  String get panelErrBusy => _t('The server is busy. Wait a moment and try again.', 'الخادم مشغول. انتظر قليلًا وحاول مجددًا.', 'The server is busy. Wait a moment and try again.');
  String get panelErrServer => _t('The server has a problem right now. Try again later.', 'الخادم يواجه مشكلة الآن. حاول لاحقًا.', 'The server has a problem right now. Try again later.');
  String get panelErrBadResponse => _t("This link didn't answer like a panel. Check the link.", 'هذا الرابط لم يستجب كلوحة. تحقق من الرابط.', "This link didn't answer like a panel. Check the link.");
  String get panelErrUnsupported => _t("This panel doesn't allow this login type. Try the Xtream login.", 'هذه اللوحة لا تسمح بنوع الدخول هذا. جرّب دخول Xtream.', "This panel doesn't allow this login type. Try the Xtream login.");
  String get panelErrTypeOff => _t('This panel type is not available right now.', 'نوع اللوحة هذا غير متاح حاليًا.', 'This panel type is not available right now.');
  String panelErrTooMany(int n) => _t('You can save up to $n panels. Remove one first.', 'يمكنك حفظ $n لوحات كحد أقصى. احذف واحدة أولًا.', 'You can save up to $n panels. Remove one first.');
  String get myPanels => _t('My panels', 'لوحاتي', 'My panels');
  String get addPanel => _t('Add panel', 'إضافة لوحة', 'Add panel');
  String get mainPanel => _t('Main', 'رئيسية', 'Main');
  String get makeMainPanel => _t('Make main panel', 'اجعلها اللوحة الرئيسية', 'Make main panel');
  String get checkPanelNow => _t('Check now', 'تحقق الآن', 'Check now');
  String get panelTurnOff => _t('Turn off', 'إيقاف', 'Turn off');
  String get panelTurnOn => _t('Turn on', 'تشغيل', 'Turn on');
  String get removePanelConfirm => _t('Remove this panel and its login from this device?', 'حذف هذه اللوحة وبيانات دخولها من هذا الجهاز؟', 'Remove this panel and its login from this device?');
  String get panelStatusActive => _t('Active', 'نشط', 'Active');
  String get panelStatusExpired => _t('Expired', 'منتهي', 'Expired');
  String get panelStatusRefused => _t('Login refused', 'الدخول مرفوض', 'Login refused');
  String get panelStatusUnreachable => _t('Unreachable', 'غير متاح', 'Unreachable');
  String get panelStatusOff => _t('Off', 'متوقف', 'Off');
  String get panelStatusChecking => _t('Checking…', 'جارٍ التحقق…', 'Checking…');
  String get panelStatusCheckDetails => _t('Check details', 'تحقق من البيانات', 'Check details');
  String panelExpiresOn(String date) => _t('Expires $date', 'ينتهي $date', 'Expires $date');
  String get panelNoExpiry => _t('No expiry date', 'بدون تاريخ انتهاء', 'No expiry date');
  String get panelsEmpty => _t('No panels yet. Add the IPTV service you use.', 'لا توجد لوحات بعد. أضف خدمة IPTV التي تستخدمها.', 'No panels yet. Add the IPTV service you use.');

  // ── Optional app account (Supabase Auth, Phase 5.7) ──
  String get accountOfferTitle => _t('Save your stuff across devices', 'احفظ بياناتك على كل أجهزتك', 'Save your stuff across devices');
  String get accountOfferBody => _t('Create a free ${AppBrand.name} account to keep favorites, watch history and settings when you change phone. Optional: your panel works without it.', 'أنشئ حساب ${AppBrand.name} مجانيًا لتحتفظ بالمفضلة وسجل المشاهدة والإعدادات عند تغيير هاتفك. اختياري: لوحتك تعمل بدونه.', 'Create a free ${AppBrand.name} account to keep favorites, watch history and settings when you change phone. Optional: your panel works without it.');
  String get accountCreate => _t('Create account', 'إنشاء حساب', 'Create account');
  String get accountNotNow => _t('Not now', 'ليس الآن', 'Not now');
  String get accountSignInLink => _t('Already have an account? Sign in', 'لديك حساب؟ سجّل الدخول', 'Already have an account? Sign in');
  String get accountCreateLink => _t('No account yet? Create one', 'ليس لديك حساب؟ أنشئ حسابًا', 'No account yet? Create one');
  String get forgotPasswordLink => _t('Forgot password?', 'نسيت كلمة المرور؟', 'Forgot password?');
  String get registerTitle => _t('Join ${AppBrand.name}', 'انضم إلى ${AppBrand.name}', 'Join ${AppBrand.name}');
  String get registerSubtitle => _t('Your panel stays on this device. The account keeps your favorites and history.', 'لوحتك تبقى على هذا الجهاز. الحساب يحفظ المفضلة وسجل المشاهدة.', 'Your panel stays on this device. The account keeps your favorites and history.');
  String get newMemberBadge => _t('NEW MEMBER', 'عضو جديد', 'NEW MEMBER');
  String get fieldFullName => _t('Full name', 'الاسم الكامل', 'Full name');
  String get fieldEmail => _t('Email', 'البريد الإلكتروني', 'Email');
  String get accountCheckEmail => _t('Check your email to confirm your account, then sign in.', 'تحقق من بريدك لتأكيد الحساب، ثم سجّل الدخول.', 'Check your email to confirm your account, then sign in.');
  String get resetEmailSent => _t('If this email has an account, a reset link is on its way.', 'إذا كان لهذا البريد حساب، فرابط إعادة التعيين في الطريق.', 'If this email has an account, a reset link is on its way.');
  String get authErrInvalid => _t('Wrong email or password.', 'البريد أو كلمة المرور غير صحيحة.', 'Wrong email or password.');
  String get authErrNotConfirmed => _t('Confirm your email first: check your inbox.', 'أكّد بريدك أولًا: تحقق من صندوق الوارد.', 'Confirm your email first: check your inbox.');
  String get authErrExists => _t('This email already has an account. Sign in instead.', 'هذا البريد لديه حساب بالفعل. سجّل الدخول بدلًا من ذلك.', 'This email already has an account. Sign in instead.');
  String get authErrWeakPassword => _t('Use a stronger password (at least 8 characters).', 'استخدم كلمة مرور أقوى (8 أحرف على الأقل).', 'Use a stronger password (at least 8 characters).');
  String get authErrBadEmail => _t('Enter a valid email address.', 'أدخل بريدًا إلكترونيًا صحيحًا.', 'Enter a valid email address.');
  String get authErrRateLimit => _t('Too many attempts. Wait a few minutes and try again.', 'محاولات كثيرة. انتظر بضع دقائق وحاول مجددًا.', 'Too many attempts. Wait a few minutes and try again.');
  String get authErrSignupOff => _t('New accounts are closed right now.', 'إنشاء الحسابات الجديدة متوقف حاليًا.', 'New accounts are closed right now.');
  String get authErrNetwork => _t("Can't reach ${AppBrand.name} right now. Check your internet.", 'تعذّر الوصول إلى ${AppBrand.name} الآن. تحقق من الإنترنت.', "Can't reach ${AppBrand.name} right now. Check your internet.");
  String get authErrNotConfigured => _t('Accounts are not available in this version of the app.', 'الحسابات غير متاحة في هذا الإصدار من التطبيق.', 'Accounts are not available in this version of the app.');
  String get authErrGeneric => _t('Something went wrong. Try again.', 'حدث خطأ. حاول مجددًا.', 'Something went wrong. Try again.');
  String get accountRowTitle => _t('${AppBrand.name} account', 'حساب ${AppBrand.name}', '${AppBrand.name} account');
  String get accountNotSignedIn => _t('Not signed in', 'غير مسجّل الدخول', 'Not signed in');
  String get signOutConfirm => _t('Sign out of your account? Your panels stay on this device.', 'تسجيل الخروج من حسابك؟ لوحاتك تبقى على هذا الجهاز.', 'Sign out of your account? Your panels stay on this device.');
  String get accountRequiredBody => _t('Sign in to your ${AppBrand.name} account to continue.', 'سجّل الدخول إلى حساب ${AppBrand.name} للمتابعة.', 'Sign in to your ${AppBrand.name} account to continue.');

  List<(String, String)> get appearanceThemesList => [
    (themeCinematic, themeCinematicDesc),
    (themeMidnight, themeMidnightDesc),
    (themeCarbon, themeCarbonDesc),
    (themeDeepCinema, themeDeepCinemaDesc),
  ];
}
