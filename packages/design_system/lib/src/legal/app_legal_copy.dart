import '../locale/app_locale.dart';
import 'package:domain/domain.dart' show AppBrand;

/// Client-provided legal copy for APP 4K (EN · AR · UR).
class AppLegalCopy {
  AppLegalCopy._();

  static String copyright(AppLang lang) => switch (lang) {
        AppLang.ar => '© 2026 ${AppBrand.name}. جميع الحقوق محفوظة.',
        AppLang.ur => '© 2026 ${AppBrand.name}۔ جملہ حقوق محفوظ ہیں۔',
        AppLang.en => '© 2026 ${AppBrand.name}. All Rights Reserved.',
      };

  static String privacyLastUpdated(AppLang lang) => switch (lang) {
        AppLang.ar => 'آخر تحديث: يونيو 2026',
        AppLang.ur => 'آخری اپ ڈیٹ: جون 2026',
        AppLang.en => 'Last updated: June 2026',
      };

  static String privacyTitle(AppLang lang) => switch (lang) {
        AppLang.ar => 'سياسة الخصوصية',
        AppLang.ur => 'رازداری کی پالیسی',
        AppLang.en => 'Privacy Policy',
      };

  static String termsTitle(AppLang lang) => switch (lang) {
        AppLang.ar => 'الشروط والأحكام',
        AppLang.ur => 'شرائط و ضوابط',
        AppLang.en => 'Terms and Conditions',
      };

  static List<({String title, String body})> privacySections(AppLang lang) {
    switch (lang) {
      case AppLang.ar:
        return const [
          (
            title: 'المعلومات التي نجمعها',
            body:
                'نجمع فقط بيانات تسجيل الدخول ومعرّف جهازك وتحليلات الاستخدام الأساسية بموافقتك.',
          ),
          (
            title: 'كيف نستخدم البيانات',
            body:
                'نستخدم البيانات لتقديم الخدمة وتحسين التطبيق وإرسال إشعارات متعلقة بحسابك فقط.',
          ),
          (
            title: 'مشاركة البيانات',
            body:
                'لا نبيع أو نشارك بياناتك الشخصية مع أي طرف ثالث تحت أي ظرف.',
          ),
          (
            title: 'أمن البيانات',
            body:
                'نحمي بيانات حسابك بتشفير كلمات المرور واتصالات آمنة بخوادمنا. روابط البث التي تضيفها يتحكم بها مزوّدك وقد تكون غير مشفّرة.',
          ),
          (
            title: 'حقوقك',
            body:
                'يمكنك حذف حسابك وبياناته في أي وقت من إعدادات التطبيق. يُحتفظ بمعرّف الجهاز المستخدم للتفعيل — ولا يحتوي بيانات شخصية — وتُحذف الملفات التي نزّلتها من قسم التنزيلات.',
          ),
          (
            title: 'المحتوى',
            body:
                'التطبيق أداة تشغيل فقط. المستخدم مسؤول بالكامل عن قانونية المحتوى الذي يصل إليه.',
          ),
        ];
      case AppLang.ur:
        return const [
          (
            title: 'ہم کون سی معلومات جمع کرتے ہیں',
            body:
                'ہم صرف لاگ اِن ڈیٹا، آپ کی ڈیوائس آئی ڈی، اور آپ کی رضامندی سے بنیادی استعمال کے تجزیات جمع کرتے ہیں۔',
          ),
          (
            title: 'ہم ڈیٹا کیسے استعمال کرتے ہیں',
            body:
                'ہم سروس فراہم کرنے، ایپ بہتر بنانے، اور صرف آپ کے اکاؤنٹ سے متعلق نوٹیفکیشن بھیجنے کے لیے ڈیٹا استعمال کرتے ہیں۔',
          ),
          (
            title: 'ڈیٹا شیئرنگ',
            body:
                'ہم کسی بھی صورت میں آپ کا ذاتی ڈیٹا کسی تیسرے فریق کو فروخت یا شیئر نہیں کرتے۔',
          ),
          (
            title: 'ڈیٹا سیکیورٹی',
            body:
                'ہم پاس ورڈ انکرپشن اور محفوظ کنکشنز سے آپ کے اکاؤنٹ ڈیٹا کی حفاظت کرتے ہیں۔ آپ جو سٹریمنگ لنکس شامل کرتے ہیں ان پر آپ کا پرووائیڈر کنٹرول رکھتا ہے اور وہ انکرپٹڈ نہ بھی ہو سکتے ہیں۔',
          ),
          (
            title: 'آپ کے حقوق',
            body:
                'آپ ایپ ترتیبات سے کسی بھی وقت اپنا اکاؤنٹ اور اس کا ڈیٹا حذف کر سکتے ہیں۔ ایکٹیویشن کے لیے استعمال ہونے والی ڈیوائس آئی ڈی محفوظ رہتی ہے — اس میں ذاتی ڈیٹا نہیں — اور ڈاؤن لوڈ شدہ فائلیں ڈاؤن لوڈز سیکشن سے ہٹا دی جاتی ہیں۔',
          ),
          (
            title: 'مواد',
            body:
                'یہ ایپ صرف پلیئر ٹول ہے۔ صارف اس مواد کی قانونی حیثیت کا مکمل ذمہ دار ہے جس تک وہ رسائی حاصل کرتا ہے۔',
          ),
        ];
      case AppLang.en:
        return const [
          (
            title: 'Information We Collect',
            body:
                'We only collect login data, your device ID, and basic usage analytics with your consent.',
          ),
          (
            title: 'How We Use Data',
            body:
                'We use data to provide the service, improve the app, and send notifications related to your account only.',
          ),
          (
            title: 'Data Sharing',
            body:
                'We never sell or share your personal data with any third party under any circumstances.',
          ),
          (
            title: 'Data Security',
            body:
                'We protect your account data with password encryption and secured connections to our servers. Streaming links you add are controlled by your provider and may be unencrypted.',
          ),
          (
            title: 'Your Rights',
            body:
                'You can delete your account and its data at any time from the app settings. The device identifier used for activation is kept — it holds no personal data — and files you downloaded are removed from the Downloads section.',
          ),
          (
            title: 'Content',
            body:
                'The app is a player tool only. The user is fully responsible for the legality of the content they access.',
          ),
        ];
    }
  }

  static List<({String title, String body})> termsSections(AppLang lang) {
    switch (lang) {
      case AppLang.ar:
        return [
          (
            title: 'قبول الشروط',
            body:
                'باستخدام تطبيق ${AppBrand.name} فإنك تقبل هذه الشروط والأحكام بالكامل.',
          ),
          (
            title: 'مشغّل وسائط فقط',
            body:
                '${AppBrand.name} مشغّل وسائط فقط. لا يقدّم التطبيق ولا يبيع أي اشتراكات أو قنوات أو محتوى، ولا يتضمن أي محتوى. تستخدمه مع الحساب الذي لديك مسبقًا من مزوّد الخدمة الخاص بك، وهو المسؤول عن هذه الخدمة وعن الاشتراك وتجديده.',
          ),
          (
            title: 'الاستخدام المسموح',
            body:
                'التطبيق للاستخدام الشخصي فقط. يُحظر إعادة التوزيع أو الاستخدام التجاري.',
          ),
          (
            title: 'مسؤولية المحتوى',
            body:
                'المستخدم مسؤول بالكامل عن طبيعة وقانونية المحتوى الذي يصل إليه.',
          ),
          (
            title: 'إنهاء الحساب',
            body:
                'نحتفظ بحق إنهاء حسابك عند مخالفة هذه الشروط أو للاستخدام غير القانوني.',
          ),
          (
            title: 'التغييرات',
            body:
                'نحتفظ بحق تعديل هذه الشروط. استمرار الاستخدام يعني قبول الشروط المحدّثة.',
          ),
        ];
      case AppLang.ur:
        return [
          (
            title: 'شرائط کی قبولیت',
            body:
                '${AppBrand.name} ایپ استعمال کر کے آپ ان شرائط و ضوابط کو مکمل طور پر قبول کرتے ہیں۔',
          ),
          (
            title: 'صرف میڈیا پلیئر',
            body:
                '${AppBrand.name} صرف ایک میڈیا پلیئر ہے۔ یہ ایپ کوئی سبسکرپشن، چینل یا مواد نہ فراہم کرتی ہے نہ بیچتی ہے، اور اس میں کوئی مواد شامل نہیں۔ آپ اسے اپنے سروس فراہم کنندہ کے موجودہ اکاؤنٹ کے ساتھ استعمال کرتے ہیں، اور وہی اس سروس، سبسکرپشن اور اس کی تجدید کا ذمہ دار ہے۔',
          ),
          (
            title: 'اجازت شدہ استعمال',
            body:
                'ایپ صرف ذاتی استعمال کے لیے ہے۔ دوبارہ تقسیم یا تجارتی استعمال ممنوع ہے۔',
          ),
          (
            title: 'مواد کی ذمہ داری',
            body:
                'صارف اس مواد کی نوعیت اور قانونی حیثیت کا مکمل ذمہ دار ہے جس تک وہ رسائی حاصل کرتا ہے۔',
          ),
          (
            title: 'خاتمہ',
            body:
                'ان شرائط کی خلاف ورزی یا غیر قانونی استعمال پر ہم آپ کا اکاؤنٹ ختم کرنے کا حق محفوظ رکھتے ہیں۔',
          ),
          (
            title: 'تبدیلیاں',
            body:
                'ہم ان شرائط میں ترمیم کا حق محفوظ رکھتے ہیں۔ مسلسل استعمال کا مطلب اپ ڈیٹ شدہ شرائط کی قبولیت ہے۔',
          ),
        ];
      case AppLang.en:
        return [
          (
            title: 'Acceptance of Terms',
            body:
                'By using the ${AppBrand.name} app, you fully accept these terms and conditions.',
          ),
          (
            title: 'Media Player Only',
            body:
                '${AppBrand.name} is a media player only. The app does not provide or sell any subscriptions, channels or content, and it does not include any content. You use it with the account you already have from your own service provider, who is responsible for that service, the subscription and its renewal.',
          ),
          (
            title: 'Permitted Use',
            body:
                'The app is for personal use only. Redistribution or commercial use is prohibited.',
          ),
          (
            title: 'Content Responsibility',
            body:
                'The user is fully responsible for the nature and legality of the content they access.',
          ),
          (
            title: 'Termination',
            body:
                'We reserve the right to terminate your account for violating these terms or for illegal use.',
          ),
          (
            title: 'Changes',
            body:
                'We reserve the right to modify these terms. Continued use means acceptance of the updated terms.',
          ),
        ];
    }
  }
}
