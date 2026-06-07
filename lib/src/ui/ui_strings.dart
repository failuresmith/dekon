import 'package:flutter/widgets.dart';

import '../application/application.dart';

class AppLanguageController extends ChangeNotifier {
  AppLanguageController({
    required AppLanguage initialLanguage,
    required MoneyUnit initialMoneyUnit,
    required this.saveLanguage,
    required this.saveMoneyUnit,
  }) : _language = initialLanguage,
       _moneyUnit = initialMoneyUnit;

  final Future<void> Function(AppLanguage language) saveLanguage;
  final Future<void> Function(MoneyUnit unit) saveMoneyUnit;
  AppLanguage _language;
  MoneyUnit _moneyUnit;

  AppLanguage get language => _language;
  MoneyUnit get moneyUnit => _moneyUnit;
  UiStrings get strings =>
      UiStrings.forPreferences(language: _language, moneyUnit: _moneyUnit);

  Future<void> setLanguage(AppLanguage language) async {
    if (language == _language) return;
    final previous = _language;
    _language = language;
    notifyListeners();
    try {
      await saveLanguage(language);
    } catch (_) {
      _language = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setMoneyUnit(MoneyUnit unit) async {
    if (unit == _moneyUnit) return;
    final previous = _moneyUnit;
    _moneyUnit = unit;
    notifyListeners();
    try {
      await saveMoneyUnit(unit);
    } catch (_) {
      _moneyUnit = previous;
      notifyListeners();
      rethrow;
    }
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController controllerOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    assert(scope != null, 'AppLanguageScope was not found in the widget tree.');
    return scope!.notifier!;
  }

  static UiStrings stringsOf(BuildContext context) {
    return controllerOf(context).strings;
  }
}

extension UiStringsBuildContext on BuildContext {
  UiStrings get strings => AppLanguageScope.stringsOf(this);
}

class UiStrings {
  const UiStrings._(this.language, this.moneyUnit);

  static final _asciiDigitPattern = RegExp('[0-9]');
  static const _farsiDigits = [
    '۰',
    '۱',
    '۲',
    '۳',
    '۴',
    '۵',
    '۶',
    '۷',
    '۸',
    '۹',
  ];

  final AppLanguage language;
  final MoneyUnit moneyUnit;

  static UiStrings forLanguage(AppLanguage language) {
    return UiStrings.forPreferences(
      language: language,
      moneyUnit: MoneyUnit.rial,
    );
  }

  static UiStrings forPreferences({
    required AppLanguage language,
    required MoneyUnit moneyUnit,
  }) {
    return switch (language) {
      AppLanguage.english => UiStrings._(AppLanguage.english, moneyUnit),
      AppLanguage.farsi => UiStrings._(AppLanguage.farsi, moneyUnit),
    };
  }

  TextDirection get textDirection {
    return language == AppLanguage.farsi
        ? TextDirection.rtl
        : TextDirection.ltr;
  }

  String digits(String value) {
    if (language != AppLanguage.farsi) return value;
    return value.replaceAllMapped(_asciiDigitPattern, (match) {
      return _farsiDigits[int.parse(match[0]!)];
    });
  }

  String integer(int value) => digits(value.toString());

  String money(int rialValue) {
    final value = digits(formatMoneyForUnit(rialValue, unit: moneyUnit));
    return '$value ${moneyUnitLabel(moneyUnit)}';
  }

  String moneyInput(int rialValue) {
    return digits(formatMoneyForUnit(rialValue, unit: moneyUnit));
  }

  String quantity(double value) {
    final formatted = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    return digits(formatted);
  }

  String timestamp(DateTime dateTime) {
    final local = dateTime.toLocal();
    if (language != AppLanguage.farsi) {
      return digits(local.toString().split('.').first);
    }
    final date = PersianCalendar.fromGregorian(local);
    return digits(
      '${date.year.toString().padLeft(4, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')} '
      '${_timeParts(local).join(':')}',
    );
  }

  String timeOfDay(DateTime dateTime) {
    return digits(_timeParts(dateTime.toLocal()).join(':'));
  }

  String shortNumericDate(DateTime dateTime) {
    if (language == AppLanguage.farsi) {
      final date = PersianCalendar.fromGregorian(dateTime);
      return digits('${date.month}/${date.day}');
    }
    return digits('${dateTime.month}/${dateTime.day}');
  }

  String yearNumber(int year) => digits(year.toString());

  String yearNumberForDate(DateTime dateTime) {
    if (language == AppLanguage.farsi) {
      return integer(PersianCalendar.fromGregorian(dateTime).year);
    }
    return yearNumber(dateTime.year);
  }

  String humanDate(DateTime dateTime) {
    if (language == AppLanguage.farsi) {
      final date = PersianCalendar.fromGregorian(dateTime);
      return '${integer(date.day)} ${monthName(date.month)} ${integer(date.year)}';
    }
    return '${integer(dateTime.day)} ${monthName(dateTime.month)} ${yearNumber(dateTime.year)}';
  }

  String monthYear(DateTime dateTime) {
    if (language == AppLanguage.farsi) {
      final date = PersianCalendar.fromGregorian(dateTime);
      return '${monthName(date.month)} ${integer(date.year)}';
    }
    return '${monthName(dateTime.month)} ${yearNumber(dateTime.year)}';
  }

  String shortMonthNameForDate(DateTime dateTime) {
    if (language == AppLanguage.farsi) {
      return shortMonthName(PersianCalendar.fromGregorian(dateTime).month);
    }
    return shortMonthName(dateTime.month);
  }

  ReportCalendar get reportCalendar {
    return language == AppLanguage.farsi
        ? ReportCalendar.persian
        : ReportCalendar.gregorian;
  }

  String get sell => _text(en: 'Sell', fa: 'فروش');
  String get restock => _text(en: 'Restock', fa: 'تأمین');
  String get inventory => _text(en: 'Inventory', fa: 'موجودی');
  String get reports => _text(en: 'Reports', fa: 'گزارش ها');
  String get thisDeviceReports {
    return _text(en: 'This Device Reports', fa: 'گزارش های این دستگاه');
  }

  String get settings => _text(en: 'Settings', fa: 'تنظیمات');
  String get about => _text(en: 'About', fa: 'درباره');
  String get aboutUrl => 'https://ble.ir/dekon';
  String aboutVersion(String version) {
    return _text(en: 'Version $version', fa: 'نسخه ${digits(version)}');
  }

  String get aboutLinkError {
    return _text(
      en: 'Could not open the link. Try again.',
      fa: 'لینک باز نشد. دوباره تلاش کنید.',
    );
  }

  String startupFailed(Object error) {
    return _text(
      en: 'Startup failed: $error',
      fa: 'شروع برنامه ناموفق بود: $error',
    );
  }

  String get languageLabel => _text(en: 'Language', fa: 'زبان');
  String get moneyUnitLabelTitle {
    return _text(en: 'Money unit', fa: 'واحد پول');
  }

  String get deviceSync => _text(en: 'Device Sync', fa: 'همگام سازی دستگاه');
  String get backupAndRestore {
    return _text(en: 'Backup and Restore', fa: 'پشتیبان گیری و بازیابی');
  }

  String get saleHistory => _text(en: 'Sale history', fa: 'سابقه فروش');
  String get restockHistory {
    return _text(en: 'Restock history', fa: 'سابقه تأمین');
  }

  String get allPersonnel {
    return _text(en: 'All personnel', fa: 'همه کارکنان');
  }

  String get createdByField {
    return _text(en: 'Created by', fa: 'ثبت شده توسط');
  }

  String createdBy(String label) {
    return _text(en: 'Created by: $label', fa: 'ثبت شده توسط: $label');
  }

  String get saleDetail => _text(en: 'Sale detail', fa: 'جزئیات فروش');
  String get restockDetail {
    return _text(en: 'Restock detail', fa: 'جزئیات تأمین');
  }

  String get salePendingMainApproval {
    return _text(
      en: 'Not approved by main device yet',
      fa: 'هنوز توسط دستگاه اصلی تأیید نشده است',
    );
  }

  String get scan => _text(en: 'Scan', fa: 'اسکن');
  String get scanBarcode => _text(en: 'Scan barcode', fa: 'اسکن بارکد');
  String get scanBarcodeOrSearchProduct {
    return _text(
      en: 'Scan barcode or search product',
      fa: 'جستجوی کالا یا اسکن بارکد',
    );
  }

  String get searchProductsOrScanBarcode {
    return _text(
      en: 'Search products or scan barcode',
      fa: 'جستجوی کالا یا اسکن بارکد',
    );
  }

  String get completeSale => _text(en: 'Complete Sale', fa: 'تکمیل فروش');
  String get addToInventory {
    return _text(en: 'Add to Inventory', fa: 'افزودن به موجودی');
  }

  String get createNewProduct {
    return _text(en: 'Create New Product', fa: 'ایجاد کالای جدید');
  }

  String get addProduct => _text(en: 'Add Product', fa: 'افزودن کالا');
  String get all => _text(en: 'All', fa: 'همه');
  String get lowStock => _text(en: 'Low Stock', fa: 'موجودی کم');
  String get revenue => _text(en: 'Sales Amount', fa: 'فروش');
  String get purchases => _text(en: 'Restock Amount', fa: 'مبلغ تأمین');
  String get grossProfit => _text(en: 'Gross Profit', fa: 'سود ناخالص');
  String get lowStockItems {
    return _text(en: 'Low-stock Items', fa: 'کالاهای کم موجودی');
  }

  String get viewSalesTrend {
    return _text(en: 'View Sales Trend', fa: 'نمایش روند فروش');
  }

  String get connectAnotherDevice {
    return _text(en: 'Connect Another Device', fa: 'اتصال دستگاه دیگر');
  }

  String get stopPairing => _text(en: 'Stop Pairing', fa: 'توقف جفت سازی');
  String get unpair => _text(en: 'Unpair', fa: 'قطع جفت سازی');
  String get technicalDetails {
    return _text(en: 'Technical details', fa: 'جزئیات فنی');
  }

  String get peerMessages => _text(en: 'Peer messages', fa: 'پیام های همتا');
  String get peerMessagesSent => _text(en: 'Sent', fa: 'ارسال شده');
  String get peerMessagesReceived {
    return _text(en: 'Received', fa: 'دریافت شده');
  }

  String get noPeerMessagesYet {
    return _text(en: 'No peer messages yet.', fa: 'هنوز پیامی وجود ندارد.');
  }

  String get noSentPeerMessagesYet {
    return _text(
      en: 'No sent peer messages yet.',
      fa: 'هنوز پیام ارسالی وجود ندارد.',
    );
  }

  String get noReceivedPeerMessagesYet {
    return _text(
      en: 'No received peer messages yet.',
      fa: 'هنوز پیام دریافتی وجود ندارد.',
    );
  }

  String get peerMessagesHint {
    return _text(
      en: 'Pair or sync a device to see recent messages.',
      fa: 'برای دیدن پیام های اخیر، دستگاهی را جفت یا همگام سازی کنید.',
    );
  }

  String get reportsCouldNotLoad {
    return _text(en: 'Reports could not load.', fa: 'گزارش ها بارگیری نشد.');
  }
}
