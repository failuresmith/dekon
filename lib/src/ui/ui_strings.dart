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

  String get saleDetail => _text(en: 'Sale detail', fa: 'جزئیات فروش');
  String get restockDetail {
    return _text(en: 'Restock detail', fa: 'جزئیات تأمین');
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
  String get revenue => _text(en: 'Revenue', fa: 'درآمد');
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
      fa: 'برای دیدن پیام های اخیر، دستگاهی را جفت یا همگام کنید.',
    );
  }

  String get clear => _text(en: 'Clear', fa: 'پاک کردن');
  String get back => _text(en: 'Back', fa: 'بازگشت');
  String get close => _text(en: 'Close', fa: 'بستن');
  String get saveBackup => _text(en: 'Save Backup', fa: 'ذخیره پشتیبان');
  String get restoreBackup =>
      _text(en: 'Restore Backup', fa: 'بازیابی پشتیبان');
  String get backupSavedSuccessfully {
    return _text(en: 'Backup saved successfully', fa: 'پشتیبان ذخیره شد');
  }

  String get backupRestoredSuccessfully {
    return _text(en: 'Backup restored successfully', fa: 'پشتیبان بازیابی شد');
  }

  String get inventoryUpdated {
    return _text(en: 'Inventory updated', fa: 'موجودی به روز شد');
  }

  String get saleCompleted => _text(en: 'Sale completed', fa: 'فروش تکمیل شد');

  String get cashierSaleConnectionWarning {
    return _text(
      en: 'Sales are blocked until this cashier reconnects to the main device. Check Device Sync in Settings.',
      fa: 'تا اتصال دوباره این صندوق به دستگاه اصلی، فروش ثبت نمی شود. همگام سازی دستگاه را در تنظیمات بررسی کنید.',
    );
  }

  String get noProductsAddedYet {
    return _text(en: 'No products added yet', fa: 'هنوز کالایی اضافه نشده است');
  }

  String get totalSaleAmount {
    return _text(en: 'Total sale amount', fa: 'مبلغ کل فروش');
  }

  String get totalRestockAmount {
    return _text(en: 'Total restock amount', fa: 'مبلغ کل تأمین');
  }

  String get productNotFoundRestockFirst {
    return _text(
      en: 'Product not found. Restock it into inventory first.',
      fa: 'کالا پیدا نشد. ابتدا آن را از بخش تأمین اضافه کنید.',
    );
  }

  String get sellEmptyState {
    return _text(
      en: 'Scan a barcode or search for a product\nto add the first product.',
      fa: 'برای افزودن اولین کالا، بارکد را اسکن کنید\nیا کالا را جستجو کنید.',
    );
  }

  String get restockEmptyState {
    return _text(
      en: 'Scan an existing product to add stock,\nor search for a product by name.',
      fa: 'برای افزودن موجودی، کالای موجود را اسکن کنید\nیا نام کالا را جستجو کنید.',
    );
  }

  String get settingsDeviceSyncSubtitle {
    return _text(
      en: 'Manage connected cashier devices',
      fa: 'مدیریت دستگاه های صندوق متصل',
    );
  }

  String get settingsBackupRestoreSubtitle {
    return _text(
      en: 'Save or restore store data',
      fa: 'ذخیره یا بازیابی داده فروشگاه',
    );
  }

  String languageSubtitle(AppLanguage selected) {
    return _text(
      en: 'Current language: ${languageChoiceLabel(selected)}',
      fa: 'زبان فعلی: ${languageChoiceLabel(selected)}',
    );
  }

  String languageChoiceLabel(AppLanguage option) {
    return switch (option) {
      AppLanguage.english => 'English',
      AppLanguage.farsi => 'Farsi',
    };
  }

  String moneyUnitSubtitle(MoneyUnit selected) {
    return _text(
      en: 'Displayed as ${moneyUnitLabel(selected)}. Stored as Rial.',
      fa: 'نمایش با ${moneyUnitLabel(selected)}. ذخیره همیشه ریال است.',
    );
  }

  String moneyUnitLabel(MoneyUnit option) {
    return switch (option) {
      MoneyUnit.rial => _text(en: 'Rial', fa: 'ریال'),
      MoneyUnit.toman => _text(en: 'Toman', fa: 'تومان'),
    };
  }

  String get chooseMoneyUnit {
    return _text(
      en: 'Choose how money is shown. Stored values always remain Rial.',
      fa: 'انتخاب کنید مبلغ ها چطور نمایش داده شوند. مقدار ذخیره شده همیشه ریال است.',
    );
  }

  String get moneyUnitSaved {
    return _text(en: 'Money unit updated', fa: 'واحد پول به روز شد');
  }

  String get moneyUnitSaveFailed {
    return _text(
      en: 'Money unit could not be saved. Try again.',
      fa: 'واحد پول ذخیره نشد. دوباره تلاش کنید.',
    );
  }

  String get chooseLanguage {
    return _text(
      en: 'Choose the app language.',
      fa: 'زبان برنامه را انتخاب کنید.',
    );
  }

  String get languageSaved {
    return _text(en: 'Language updated', fa: 'زبان به روز شد');
  }

  String get languageSaveFailed {
    return _text(
      en: 'Language could not be saved. Try again.',
      fa: 'زبان ذخیره نشد. دوباره تلاش کنید.',
    );
  }

  String get setupThisDevice {
    return _text(en: 'Set up this device', fa: 'راه اندازی این دستگاه');
  }

  String get pairCashierDevice {
    return _text(en: 'Pair cashier device', fa: 'جفت سازی دستگاه صندوق');
  }

  String get chooseDeviceUse {
    return _text(
      en: 'Choose how this device will be used.',
      fa: 'نحوه استفاده از این دستگاه را انتخاب کنید.',
    );
  }

  String get connectCashierBeforeUse {
    return _text(
      en: 'Connect this cashier to the main device before use.',
      fa: 'قبل از استفاده، این صندوق را به دستگاه اصلی وصل کنید.',
    );
  }

  String get mainDevice => _text(en: 'Main Device', fa: 'دستگاه اصلی');
  String get cashier => _text(en: 'Cashier', fa: 'صندوق');
  String get cashierDevice => _text(en: 'Cashier Device', fa: 'دستگاه صندوق');

  String setupFailed(Object error) {
    return _text(
      en: 'Setup failed: $error',
      fa: 'راه اندازی ناموفق بود: $error',
    );
  }

  String get deviceSyncCouldNotLoad {
    return _text(
      en: 'Device Sync could not load.',
      fa: 'همگام سازی دستگاه بارگیری نشد.',
    );
  }

  String get deviceSyncUnavailable {
    return _text(
      en: 'Device Sync is unavailable on this device.',
      fa: 'همگام سازی روی این دستگاه در دسترس نیست.',
    );
  }

  String get thisDeviceStoresInventoryDatabase {
    return _text(
      en: 'This device stores the inventory database.',
      fa: 'این دستگاه پایگاه داده موجودی را نگهداری می کند.',
    );
  }

  String get connectedCashierDevices {
    return _text(en: 'Connected Cashier Devices', fa: 'دستگاه های صندوق متصل');
  }

  String connectedDeviceCount(int count) {
    if (language == AppLanguage.farsi) return '${integer(count)} دستگاه متصل';
    return count == 1 ? '1 device connected' : '$count devices connected';
  }

  String get trustedCashierDevice {
    return _text(en: 'Trusted cashier device', fa: 'دستگاه صندوق مورد اعتماد');
  }

  String get unpairCashierQuestion {
    return _text(en: 'Unpair cashier device?', fa: 'جفت سازی صندوق قطع شود؟');
  }

  String unpairCashierHelp(String label) {
    return _text(
      en: '$label will back up its sale history, reset, and must pair with a main device again before use.',
      fa: '$label سابقه فروش خود را پشتیبان می گیرد، بازنشانی می شود و پیش از استفاده باید دوباره با دستگاه اصلی جفت شود.',
    );
  }

  String get couldNotUnpairCashier {
    return _text(
      en: 'Could not unpair this cashier. Check the connection and try again.',
      fa: 'قطع جفت سازی این صندوق انجام نشد. اتصال را بررسی کنید و دوباره تلاش کنید.',
    );
  }

  String get startingPairing =>
      _text(en: 'Starting pairing', fa: 'شروع جفت سازی');
  String get scanQrFromCashier {
    return _text(
      en: 'Scan this QR code from the cashier device.',
      fa: 'این کد QR را با دستگاه صندوق اسکن کنید.',
    );
  }

  String get startPairingToCreateLocalAddress {
    return _text(
      en: 'Start pairing to create a local address.',
      fa: 'برای ساخت نشانی محلی، جفت سازی را شروع کنید.',
    );
  }

  String localAddress(String address) {
    return _text(en: 'Local address\n$address', fa: 'نشانی محلی\n$address');
  }

  String cashierConnectionText(String? displayName) {
    final trimmed = displayName?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        trimmed == 'This device' ||
        trimmed == 'Dekon phone') {
      return _text(
        en: 'Connected to Main device.',
        fa: 'به دستگاه اصلی وصل است.',
      );
    }
    return _text(
      en: 'Connected to Main device as $trimmed',
      fa: 'به عنوان $trimmed به دستگاه اصلی وصل است',
    );
  }

  String get couldNotStartPairing {
    return _text(
      en: 'Could not start pairing. Check that this device is connected to Wi-Fi.',
      fa: 'جفت سازی شروع نشد. بررسی کنید دستگاه به Wi-Fi وصل باشد.',
    );
  }

  String get couldNotStopPairing {
    return _text(
      en: 'Could not stop pairing. Try again.',
      fa: 'جفت سازی متوقف نشد. دوباره تلاش کنید.',
    );
  }

  String get backupHelp {
    return _text(
      en: 'Save a backup file so your store data can be recovered if this device is lost or replaced.',
      fa: 'یک فایل پشتیبان ذخیره کنید تا در صورت گم شدن یا تعویض دستگاه، داده فروشگاه بازیابی شود.',
    );
  }

  String get lastSuccessfulBackup {
    return _text(en: 'Last successful backup', fa: 'آخرین پشتیبان موفق');
  }

  String get retryBackup =>
      _text(en: 'Retry Backup', fa: 'تلاش دوباره برای پشتیبان');
  String get working => _text(en: 'Working', fa: 'در حال انجام');
  String get restoreBackupQuestion {
    return _text(en: 'Restore backup?', fa: 'پشتیبان بازیابی شود؟');
  }

  String restoreBackupPreview({
    required String fileName,
    required int recordCount,
    required String exportedAt,
  }) {
    final displayRecordCount = integer(recordCount);
    return _text(
      en:
          'Current store data may be replaced by the selected backup file.\n\n'
          '$fileName\n'
          '$recordCount records\n'
          'Made $exportedAt',
      fa:
          'ممکن است داده فعلی فروشگاه با فایل پشتیبان انتخاب شده جایگزین شود.\n\n'
          '$fileName\n'
          '$displayRecordCount رکورد\n'
          'ساخته شده در $exportedAt',
    );
  }

  String get cancel => _text(en: 'Cancel', fa: 'لغو');
  String get restore => _text(en: 'Restore', fa: 'بازیابی');
  String get noBackupSavedInThisSession {
    return _text(
      en: 'No backup saved in this session',
      fa: 'در این نشست پشتیبانی ذخیره نشده است',
    );
  }

  String get couldNotSaveBackup {
    return _text(
      en: 'Could not save the backup.\nChoose another folder or check that the selected location is writable.',
      fa: 'پشتیبان ذخیره نشد.\nپوشه دیگری انتخاب کنید یا مطمئن شوید محل انتخاب شده قابل نوشتن است.',
    );
  }

  String backupRestoredWithSkippedDuplicates(int duplicateCount) {
    final displayDuplicateCount = integer(duplicateCount);
    return _text(
      en: '$backupRestoredSuccessfully. Skipped $duplicateCount duplicate records.',
      fa: '$backupRestoredSuccessfully. $displayDuplicateCount رکورد تکراری نادیده گرفته شد.',
    );
  }

  String couldNotRestoreBackup(String message) {
    return _text(
      en: 'Could not restore the backup.\n$message',
      fa: 'پشتیبان بازیابی نشد.\n$message',
    );
  }

  String get chooseValidBackupFile {
    return _text(
      en: 'Choose a valid Dekon backup file and try again.',
      fa: 'یک فایل پشتیبان معتبر Dekon انتخاب کنید و دوباره تلاش کنید.',
    );
  }

  String get pairWithMainDeviceBeforeUsingCashier {
    return _text(
      en: 'Pair with the main device before using this cashier.',
      fa: 'قبل از استفاده از این صندوق، آن را با دستگاه اصلی جفت کنید.',
    );
  }

  String get pairing => _text(en: 'Pairing', fa: 'در حال جفت سازی');
  String get scanQrCode => _text(en: 'Scan QR Code', fa: 'اسکن کد QR');
  String get enterIpManually {
    return _text(en: 'Enter IP Manually', fa: 'وارد کردن دستی IP');
  }

  String get pairedWithMainDevice {
    return _text(en: 'Paired with Main Device.', fa: 'با دستگاه اصلی جفت شد.');
  }

  String pairingFailed(String message) {
    return _text(
      en: 'Pairing failed: $message',
      fa: 'جفت سازی ناموفق بود: $message',
    );
  }

  String get couldNotPairWithMainDevice {
    return _text(
      en: 'Could not pair with the main device.',
      fa: 'اتصال به دستگاه اصلی انجام نشد.',
    );
  }

  String get mainDeviceIp => _text(en: 'Main device IP', fa: 'IP دستگاه اصلی');
  String get ipAddressOrUrl {
    return _text(en: 'IP address or URL', fa: 'نشانی IP یا URL');
  }

  String get pair => _text(en: 'Pair', fa: 'جفت کردن');

  String get cashierUnpairedTitle {
    return _text(en: 'Cashier unpaired', fa: 'صندوق قطع جفت سازی شد');
  }

  String get cashierUnpairedHelp {
    return _text(
      en: 'This cashier was unpaired by the main device. Sale history must be backed up before this device resets and pairs again.',
      fa: 'این صندوق توسط دستگاه اصلی قطع جفت سازی شد. پیش از بازنشانی و جفت سازی دوباره، سابقه فروش باید پشتیبان گیری شود.',
    );
  }

  String get backupSaleHistoryAndReset {
    return _text(
      en: 'Back up sale history and reset',
      fa: 'پشتیبان گیری سابقه فروش و بازنشانی',
    );
  }

  String get backingUpSaleHistory {
    return _text(
      en: 'Backing up sale history...',
      fa: 'در حال پشتیبان گیری سابقه فروش...',
    );
  }

  String get backupRequiredBeforeReset {
    return _text(
      en: 'Backup is required before reset. Choose where to save the backup and try again.',
      fa: 'پیش از بازنشانی، پشتیبان لازم است. محل ذخیره پشتیبان را انتخاب کنید و دوباره تلاش کنید.',
    );
  }

  String get cashierResetReadyToPair {
    return _text(
      en: 'Cashier reset. Pair with a main device to continue.',
      fa: 'صندوق بازنشانی شد. برای ادامه با یک دستگاه اصلی جفت کنید.',
    );
  }

  String get editProduct => _text(en: 'Edit Product', fa: 'ویرایش کالا');
  String get createProduct => _text(en: 'Create Product', fa: 'ایجاد کالا');
  String get name => _text(en: 'Name', fa: 'نام');
  String get barcode => _text(en: 'Barcode', fa: 'بارکد');
  String get skuInternalProductCode {
    return _text(en: 'SKU - Internal Product Code', fa: 'SKU - کد داخلی کالا');
  }

  String get salePrice => _text(en: 'Sale price', fa: 'قیمت فروش');
  String get purchaseCost => _text(en: 'Purchase cost', fa: 'قیمت خرید');
  String get delete => _text(en: 'Delete', fa: 'حذف');
  String get saving => _text(en: 'Saving', fa: 'در حال ذخیره');
  String get save => _text(en: 'Save', fa: 'ذخیره');
  String get deleteProductQuestion {
    return _text(en: 'Delete product?', fa: 'کالا حذف شود؟');
  }

  String get deleteProductHelp {
    return _text(
      en: 'This hides the item from Restock and Sell while keeping its history for reports.',
      fa: 'این کالا را از فروش و تأمین پنهان می کند اما سابقه آن برای گزارش ها باقی می ماند.',
    );
  }

  String productSaveFailed(Object error) {
    return _text(
      en: 'Product save failed: $error',
      fa: 'ذخیره کالا ناموفق بود: $error',
    );
  }

  String productDeleteFailed(Object error) {
    return _text(
      en: 'Product delete failed: $error',
      fa: 'حذف کالا ناموفق بود: $error',
    );
  }

  String get requiredField => _text(en: 'Required', fa: 'ضروری');

  String inventoryFailed(Object error) {
    return _text(
      en: 'Inventory failed: $error',
      fa: 'موجودی بارگیری نشد: $error',
    );
  }

  String get noProductsInInventory {
    return _text(
      en: 'No products in inventory',
      fa: 'هیچ کالایی در موجودی نیست',
    );
  }

  String get emptyInventoryHelp {
    return _text(
      en: 'Add the first product to start recording\nsales and restocks.',
      fa: 'اولین کالا را اضافه کنید تا ثبت\nفروش و تأمین شروع شود.',
    );
  }

  String get cashierEmptyInventoryHelp {
    return _text(
      en: 'Inventory appears after this cashier syncs with the main device.',
      fa: 'موجودی پس از همگام سازی این صندوق با دستگاه اصلی نمایش داده می شود.',
    );
  }

  String noProductsFoundFor(String query) {
    return _text(
      en: 'No products found for "$query"',
      fa: 'کالایی برای "$query" پیدا نشد',
    );
  }

  String get noLowStockProducts {
    return _text(en: 'No low-stock products', fa: 'کالای کم موجودی وجود ندارد');
  }

  String stockLabel(String quantity) {
    final displayQuantity = digits(quantity);
    return _text(en: 'Stock: $quantity', fa: 'موجودی: $displayQuantity');
  }

  String stockInline(String quantity) {
    final displayQuantity = digits(quantity);
    return _text(en: 'Stock $quantity', fa: 'موجودی $displayQuantity');
  }

  String inventoryProductSemantics({
    required String name,
    required String quantity,
  }) {
    final displayQuantity = digits(quantity);
    return _text(
      en: '$name. Stock $quantity. Open product details.',
      fa: '$name. موجودی $displayQuantity. باز کردن جزئیات کالا.',
    );
  }

  String get noProductFoundForBarcode {
    return _text(
      en: 'No product found for this barcode.',
      fa: 'برای این بارکد کالایی پیدا نشد.',
    );
  }

  String get scanUnavailableSearchManually {
    return _text(
      en: 'Scan unavailable. Search products manually.',
      fa: 'اسکن در دسترس نیست. کالا را دستی جستجو کنید.',
    );
  }

  String get scanUnavailableEnterBarcodeManually {
    return _text(
      en: 'Scan unavailable. Enter barcode manually.',
      fa: 'اسکن در دسترس نیست. بارکد را دستی وارد کنید.',
    );
  }

  String get thisBarcodeNotInInventory {
    return _text(
      en: 'This barcode is not in your inventory.',
      fa: 'این بارکد در موجودی شما نیست.',
    );
  }

  String eachPrice(String amount) =>
      _text(en: '$amount each', fa: 'هر عدد ${digits(amount)}');
  String currentStock(String quantity) {
    final displayQuantity = digits(quantity);
    return _text(
      en: 'Current stock: $quantity',
      fa: 'موجودی: $displayQuantity',
    );
  }

  String purchaseCostEach(String amount) {
    return _text(
      en: 'Purchase cost: $amount each',
      fa: 'قیمت خرید هر عدد: ${digits(amount)}',
    );
  }

  String get removeProduct => _text(en: 'Remove product', fa: 'حذف کالا');
  String get decreaseQuantity {
    return _text(en: 'Decrease quantity', fa: 'کم کردن تعداد');
  }

  String get increaseQuantity {
    return _text(en: 'Increase quantity', fa: 'زیاد کردن تعداد');
  }

  String availableStockWarning(String quantity) {
    final displayQuantity = digits(quantity);
    return _text(
      en: 'Only $quantity is available in stock. The sale needs confirmation before completion.',
      fa: 'فقط $displayQuantity عدد در موجودی است. فروش پیش از تکمیل نیاز به تایید دارد.',
    );
  }

  String itemsCount(int count) =>
      _text(en: 'Items: $count', fa: 'تعداد کالا: ${integer(count)}');

  String transactionTotal(String amount) {
    return _text(en: 'Total: $amount', fa: 'مجموع: $amount');
  }

  String lineQuantity(String quantity) {
    return _text(en: 'Quantity: $quantity', fa: 'تعداد: ${digits(quantity)}');
  }

  String saveFailed(Object error) {
    return _text(
      en: 'Save failed. Check the connection and try again.',
      fa: 'ذخیره ناموفق بود. اتصال را بررسی کنید و دوباره تلاش کنید.',
    );
  }

  String get negativeStockWarning {
    return _text(en: 'Negative stock warning', fa: 'هشدار موجودی منفی');
  }

  String negativeStockContent(String names) {
    return _text(
      en:
          'This sale will make stock negative for: $names.\n'
          'The affected row is highlighted.',
      fa:
          'این فروش موجودی این کالاها را منفی می کند: $names.\n'
          'ردیف مربوطه مشخص شده است.',
    );
  }

  String get continueAction => _text(en: 'Continue', fa: 'ادامه');
  String get noPreviousTransactions {
    return _text(en: 'No previous transactions', fa: 'تراکنش قبلی وجود ندارد');
  }

  String get noLineDetails {
    return _text(en: 'No line details', fa: 'جزئیات ردیف وجود ندارد');
  }

  String reportsFailed(Object error) {
    return _text(
      en: 'Reports failed: $error',
      fa: 'گزارش ها بارگیری نشد: $error',
    );
  }

  String get localCashierTransactions {
    return _text(en: 'Local cashier transactions', fa: 'تراکنش های محلی صندوق');
  }

  String get day => _text(en: 'Day', fa: 'روز');
  String get week => _text(en: 'Week', fa: 'هفته');
  String get month => _text(en: 'Month', fa: 'ماه');
  String get custom => _text(en: 'Custom', fa: 'دلخواه');
  String get year => _text(en: 'Year', fa: 'سال');
  String get customDateRange {
    return _text(en: 'Custom range', fa: 'بازه دلخواه');
  }

  String get startDate => _text(en: 'Start', fa: 'شروع');
  String get endDate => _text(en: 'End', fa: 'پایان');
  String get selectDate => _text(en: 'Select date', fa: 'انتخاب تاریخ');
  String get applyDateRange => _text(en: 'Apply', fa: 'اعمال');
  String get previousMonth => _text(en: 'Previous month', fa: 'ماه قبل');
  String get nextMonth => _text(en: 'Next month', fa: 'ماه بعد');
  List<String> get persianWeekdayShortNames {
    return const ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];
  }

  String dateRangeEndpoint({required String label, required String value}) {
    return _text(en: '$label: $value', fa: '$label: $value');
  }

  String previousPeriod(String unit) {
    return _text(en: 'Previous $unit', fa: '$unit قبلی');
  }

  String nextPeriod(String unit) => _text(en: 'Next $unit', fa: '$unit بعدی');
  String get selectedCashier {
    return _text(en: 'Selected cashier', fa: 'صندوق انتخاب شده');
  }

  String get cashierDeviceField {
    return _text(en: 'Cashier device', fa: 'دستگاه صندوق');
  }

  String get allDevices => _text(en: 'All devices', fa: 'همه دستگاه ها');

  String unsyncedTransactionsWarning(int count) {
    return _text(
      en: '$count transactions have not synced yet. Check Device Sync in Settings.',
      fa: '${integer(count)} تراکنش هنوز همگام نشده است. همگام سازی دستگاه را در تنظیمات بررسی کنید.',
    );
  }

  String quantityShort(String quantity) =>
      _text(en: 'Qty $quantity', fa: 'تعداد ${digits(quantity)}');
  String get noTransactions {
    return _text(en: 'No transactions', fa: 'تراکنشی وجود ندارد');
  }

  String get periodUnitDay => _text(en: 'day', fa: 'روز');
  String get periodUnitWeek => _text(en: 'week', fa: 'هفته');
  String get periodUnitMonth => _text(en: 'month', fa: 'ماه');
  String get periodUnitRange => _text(en: 'range', fa: 'بازه');
  String get today => _text(en: 'Today', fa: 'امروز');
  String get salesTrend => _text(en: 'Sales Trend', fa: 'روند فروش');

  String chartFailed(Object error) {
    return _text(en: 'Chart failed: $error', fa: 'نمودار بارگیری نشد: $error');
  }

  String get noSalesPurchasesInPeriod {
    return _text(
      en: 'No sales or restocks in this period',
      fa: 'در این بازه فروش یا تأمینی وجود ندارد',
    );
  }

  String get period => _text(en: 'Period', fa: 'بازه');
  String get net => _text(en: 'Net', fa: 'خالص');
  String reportTrendBucketSemantics({
    required String label,
    required String revenueAmount,
    required String purchasesAmount,
  }) {
    final displayLabel = digits(label);
    final displayRevenueAmount = digits(revenueAmount);
    final displayPurchasesAmount = digits(purchasesAmount);
    return _text(
      en: '$label revenue $revenueAmount restock amount $purchasesAmount',
      fa: '$displayLabel درآمد $displayRevenueAmount مبلغ تأمین $displayPurchasesAmount',
    );
  }

  String get last7Days => _text(en: 'Last 7 days', fa: '۷ روز گذشته');
  String get last8Weeks => _text(en: 'Last 8 weeks', fa: '۸ هفته گذشته');
  String get last12Months => _text(en: 'Last 12 months', fa: '۱۲ ماه گذشته');
  String get last5Years => _text(en: 'Last 5 years', fa: '۵ سال گذشته');

  String noSalesPurchasesInWindow(String window) {
    return _text(
      en: 'No sales or restocks in $window.',
      fa: 'در $window فروش یا تأمینی وجود ندارد.',
    );
  }

  String trendSummary({
    required String window,
    required String revenueAmount,
    required String purchasesAmount,
    required String netAmount,
  }) {
    final displayWindow = digits(window);
    final displayRevenueAmount = digits(revenueAmount);
    final displayPurchasesAmount = digits(purchasesAmount);
    final displayNetAmount = digits(netAmount);
    return _text(
      en: 'Sales trend for $window. Revenue: $revenueAmount. Restock amount: $purchasesAmount. Net: $netAmount.',
      fa: 'روند فروش برای $displayWindow. درآمد: $displayRevenueAmount. مبلغ تأمین: $displayPurchasesAmount. خالص: $displayNetAmount.',
    );
  }

  String monthName(int month) {
    final names = language == AppLanguage.farsi
        ? const [
            'فروردین',
            'اردیبهشت',
            'خرداد',
            'تیر',
            'مرداد',
            'شهریور',
            'مهر',
            'آبان',
            'آذر',
            'دی',
            'بهمن',
            'اسفند',
          ]
        : const [
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December',
          ];
    return names[month - 1];
  }

  String shortMonthName(int month) {
    final names = language == AppLanguage.farsi
        ? const [
            'فرو',
            'ارد',
            'خرد',
            'تیر',
            'مرد',
            'شهر',
            'مهر',
            'آبا',
            'آذر',
            'دی',
            'بهم',
            'اسف',
          ]
        : const [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec',
          ];
    return names[month - 1];
  }

  String get manualEntry => _text(en: 'Manual entry', fa: 'ورود دستی');
  String get cameraUnavailableEnterManual {
    return _text(
      en: 'Camera unavailable. Enter barcode manually.',
      fa: 'دوربین در دسترس نیست. بارکد را دستی وارد کنید.',
    );
  }

  String get cameraPermissionDeniedEnterManual {
    return _text(
      en: 'Camera permission denied. Enter barcode manually.',
      fa: 'اجازه دوربین داده نشده است. بارکد را دستی وارد کنید.',
    );
  }

  String get startingCamera =>
      _text(en: 'Starting camera...', fa: 'دوربین در حال شروع است...');
  String scannerError(String value) =>
      _text(en: 'Scanner error: $value', fa: 'خطای اسکنر: $value');
  String platformCode(String value) =>
      _text(en: 'Platform code: $value', fa: 'کد سیستم: $value');
  String platformMessage(String value) {
    return _text(en: 'Platform message: $value', fa: 'پیام سیستم: $value');
  }

  String platformDetails(String value) {
    return _text(en: 'Platform details: $value', fa: 'جزئیات سیستم: $value');
  }

  String syncMessageSent(String method, String path, String status) {
    return _text(
      en: 'Sent $status$method $path',
      fa: 'ارسال شد $status$method $path',
    );
  }

  String syncMessageReceived(String method, String path, String status) {
    return _text(
      en: 'Received $status$method $path',
      fa: 'دریافت شد $status$method $path',
    );
  }

  String syncMessageTypeGroup(String type, int count) {
    return _text(
      en: '$type (${integer(count)})',
      fa: '$type (${integer(count)})',
    );
  }

  String get syncMessageTypeHealth {
    return _text(en: 'Health check', fa: 'بررسی سلامت');
  }

  String get syncMessageTypeDeviceInfo {
    return _text(en: 'Device info', fa: 'اطلاعات دستگاه');
  }

  String get syncMessageTypePairing {
    return _text(en: 'Pairing', fa: 'جفت سازی');
  }

  String get syncMessageTypeEventPull {
    return _text(en: 'Event pull', fa: 'دریافت رویداد');
  }

  String get syncMessageTypeEventPush {
    return _text(en: 'Event push', fa: 'ارسال رویداد');
  }

  String get syncMessageTypeSyncState {
    return _text(en: 'Sync state', fa: 'وضعیت همگام سازی');
  }

  String syncMessageTypeHttp(String method, String path) {
    return _text(en: '$method $path', fa: '$method $path');
  }

  String syncPeer(String peer) => _text(en: 'Peer $peer', fa: 'همتا $peer');

  List<String> _timeParts(DateTime local) {
    return [
      local.hour,
      local.minute,
      local.second,
    ].map((value) => value.toString().padLeft(2, '0')).toList();
  }

  String _text({required String en, required String fa}) {
    return language == AppLanguage.farsi ? fa : en;
  }
}
