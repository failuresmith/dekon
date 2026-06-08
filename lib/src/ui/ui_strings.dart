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

  String moneyUnitLabel(MoneyUnit unit) {
    return switch (unit) {
      MoneyUnit.rial => _text(en: 'Rial', fa: 'ریال'),
      MoneyUnit.toman => _text(en: 'Toman', fa: 'تومان'),
    };
  }

  String get mainDevice => _text(en: 'Main device', fa: 'دستگاه اصلی');
  String get cashierDevice => _text(en: 'Cashier device', fa: 'دستگاه صندوق');
  String get cashier => _text(en: 'Cashier', fa: 'صندوق');
  String get setupThisDevice {
    return _text(en: 'Set up this device', fa: 'راه اندازی این دستگاه');
  }

  String get chooseDeviceUse {
    return _text(
      en: 'Choose how this device will be used.',
      fa: 'نقش این دستگاه را انتخاب کنید.',
    );
  }

  String get thisDeviceStoresInventoryDatabase {
    return _text(
      en: 'This device stores the inventory database.',
      fa: 'این دستگاه پایگاه داده موجودی را نگه می دارد.',
    );
  }

  String get pairWithMainDeviceBeforeUsingCashier {
    return _text(
      en: 'Pair with the main device before using cashier mode.',
      fa: 'قبل از استفاده از حالت صندوق، با دستگاه اصلی جفت شوید.',
    );
  }

  String setupFailed(Object error) {
    return _text(
      en: 'Setup failed. Try again.',
      fa: 'راه اندازی ناموفق بود. دوباره تلاش کنید.',
    );
  }

  String get chooseLanguage {
    return _text(en: 'Choose language', fa: 'انتخاب زبان');
  }

  String get chooseMoneyUnit {
    return _text(en: 'Choose money unit', fa: 'انتخاب واحد پول');
  }

  String languageChoiceLabel(AppLanguage value) {
    return switch (value) {
      AppLanguage.english => 'English',
      AppLanguage.farsi => 'فارسی',
    };
  }

  String languageSubtitle(AppLanguage value) {
    return _text(
      en: 'Current: ${languageChoiceLabel(value)}',
      fa: 'فعلی: ${languageChoiceLabel(value)}',
    );
  }

  String moneyUnitSubtitle(MoneyUnit value) {
    return _text(
      en: 'Current: ${moneyUnitLabel(value)}',
      fa: 'فعلی: ${moneyUnitLabel(value)}',
    );
  }

  String get languageSaved => _text(en: 'Language saved.', fa: 'زبان ذخیره شد.');
  String get languageSaveFailed {
    return _text(en: 'Language could not be saved.', fa: 'زبان ذخیره نشد.');
  }

  String get moneyUnitSaved {
    return _text(en: 'Money unit saved.', fa: 'واحد پول ذخیره شد.');
  }

  String get moneyUnitSaveFailed {
    return _text(en: 'Money unit could not be saved.', fa: 'واحد پول ذخیره نشد.');
  }

  String get settingsDeviceSyncSubtitle {
    return _text(en: 'Pair devices and review sync health.', fa: 'جفت سازی و وضعیت همگام سازی دستگاه ها.');
  }

  String get settingsBackupRestoreSubtitle {
    return _text(en: 'Save or restore app data.', fa: 'ذخیره یا بازیابی داده های برنامه.');
  }

  String get save => _text(en: 'Save', fa: 'ذخیره');
  String get saving => _text(en: 'Saving...', fa: 'در حال ذخیره...');
  String get working => _text(en: 'Working...', fa: 'در حال انجام...');
  String get cancel => _text(en: 'Cancel', fa: 'لغو');
  String get close => _text(en: 'Close', fa: 'بستن');
  String get back => _text(en: 'Back', fa: 'بازگشت');
  String get clear => _text(en: 'Clear', fa: 'پاک کردن');
  String get delete => _text(en: 'Delete', fa: 'حذف');
  String get restore => _text(en: 'Restore', fa: 'بازیابی');
  String get day => _text(en: 'Day', fa: 'روز');
  String get week => _text(en: 'Week', fa: 'هفته');
  String get month => _text(en: 'Month', fa: 'ماه');
  String get year => _text(en: 'Year', fa: 'سال');
  String get custom => _text(en: 'Custom', fa: 'دلخواه');
  String get today => _text(en: 'Today', fa: 'امروز');
  String get period => _text(en: 'Period', fa: 'دوره');
  String get net => _text(en: 'Net', fa: 'خالص');

  String get name => _text(en: 'Name', fa: 'نام');
  String get barcode => _text(en: 'Barcode', fa: 'بارکد');
  String get skuInternalProductCode {
    return _text(en: 'Internal product code', fa: 'کد داخلی کالا');
  }

  String get salePrice => _text(en: 'Sale price', fa: 'قیمت فروش');
  String get purchaseCost => _text(en: 'Purchase cost', fa: 'قیمت تأمین');
  String get requiredField {
    return _text(en: 'This field is required.', fa: 'این فیلد لازم است.');
  }

  String get createProduct => _text(en: 'Create product', fa: 'ایجاد کالا');
  String get editProduct => _text(en: 'Edit product', fa: 'ویرایش کالا');
  String get deleteProductQuestion {
    return _text(en: 'Delete this product?', fa: 'این کالا حذف شود؟');
  }

  String get deleteProductHelp {
    return _text(
      en: 'The product will be hidden but its history will remain.',
      fa: 'کالا پنهان می شود اما سابقه آن باقی می ماند.',
    );
  }

  String productSaveFailed(Object error) {
    return _text(en: 'Product could not be saved.', fa: 'کالا ذخیره نشد.');
  }

  String productDeleteFailed(Object error) {
    return _text(en: 'Product could not be deleted.', fa: 'کالا حذف نشد.');
  }

  String get inventoryUpdated {
    return _text(en: 'Inventory updated.', fa: 'موجودی به روز شد.');
  }

  String get saleCompleted {
    return _text(en: 'Sale completed', fa: 'فروش تکمیل شد');
  }

  String get cashierSaleQueued {
    return _text(
      en: 'Sale saved on this device. It will sync when connected.',
      fa: 'فروش روی این دستگاه ذخیره شد و پس از اتصال همگام می شود.',
    );
  }

  String get cashierSaleConflictSaved {
    return _text(
      en: 'Sale saved but needs review on the main device.',
      fa: 'فروش ذخیره شد اما نیاز به بررسی دستگاه اصلی دارد.',
    );
  }

  String get cashierSaleConnectionWarning {
    return _text(
      en: 'Some transactions have not synced yet. Check the device connection.',
      fa: 'برخی تراکنش ها هنوز همگام نشده اند. اتصال دستگاه را بررسی کنید.',
    );
  }

  String get cashierSaleConflictWarning {
    return _text(
      en: 'A cashier sale has a stock conflict. Resolve it before more sales.',
      fa: 'یک فروش صندوق مشکل موجودی دارد. قبل از فروش بعدی آن را حل کنید.',
    );
  }

  String get voidConflictedSale {
    return _text(en: 'Void conflicted sale', fa: 'ابطال فروش دارای مشکل');
  }

  String get cashierSaleConflictVoided {
    return _text(en: 'Conflicted sale voided.', fa: 'فروش دارای مشکل ابطال شد.');
  }

  String saveFailed(Object error) {
    return _text(en: 'Save failed. Try again.', fa: 'ذخیره ناموفق بود. دوباره تلاش کنید.');
  }

  String get sellEmptyState {
    return _text(
      en: 'Scan a barcode or search for a product to add the first item.',
      fa: 'برای افزودن اولین کالا، بارکد را اسکن کنید یا کالا را جستجو کنید.',
    );
  }

  String get restockEmptyState {
    return _text(
      en: 'Scan a barcode or search for a product to add the first item.',
      fa: 'برای افزودن اولین کالا، بارکد را اسکن کنید یا کالا را جستجو کنید.',
    );
  }

  String get cashierEmptyInventoryHelp {
    return _text(
      en: 'No synced products are available on this cashier device.',
      fa: 'هیچ کالای همگام شده ای روی این صندوق نیست.',
    );
  }

  String get noProductsAddedYet {
    return _text(en: 'No products added yet', fa: 'هنوز کالایی اضافه نشده است');
  }

  String get noProductsInInventory {
    return _text(en: 'No products in inventory', fa: 'موجودی خالی است');
  }

  String get emptyInventoryHelp {
    return _text(
      en: 'Add a product to start building inventory.',
      fa: 'برای شروع، یک کالا اضافه کنید.',
    );
  }

  String noProductsFoundFor(String query) {
    return _text(en: 'No products found for "$query"', fa: 'کالایی برای "$query" پیدا نشد');
  }

  String get noProductFoundForBarcode {
    return _text(en: 'No product found for this barcode.', fa: 'کالایی برای این بارکد پیدا نشد.');
  }

  String get thisBarcodeNotInInventory {
    return _text(en: 'This barcode is not in your inventory.', fa: 'این بارکد در موجودی شما نیست.');
  }

  String get productNotFoundRestockFirst {
    return _text(
      en: 'Product not found. Add it from Restock first.',
      fa: 'کالا پیدا نشد. ابتدا آن را از تأمین اضافه کنید.',
    );
  }

  String get scanUnavailableEnterBarcodeManually {
    return _text(en: 'Scanner unavailable. Enter barcode manually.', fa: 'اسکنر در دسترس نیست. بارکد را دستی وارد کنید.');
  }

  String get scanUnavailableSearchManually {
    return _text(en: 'Scanner unavailable. Search manually.', fa: 'اسکنر در دسترس نیست. دستی جستجو کنید.');
  }

  String get cameraUnavailableEnterManual {
    return _text(en: 'Camera unavailable. Enter code manually.', fa: 'دوربین در دسترس نیست. کد را دستی وارد کنید.');
  }

  String get manualEntry => _text(en: 'Manual entry', fa: 'ورود دستی');
  String get startingCamera => _text(en: 'Starting camera...', fa: 'در حال راه اندازی دوربین...');
  String get scanQrCode => _text(en: 'Scan QR code', fa: 'اسکن کد QR');
  String get scanQrFromCashier {
    return _text(en: 'Scan the QR code from the cashier device.', fa: 'کد QR دستگاه صندوق را اسکن کنید.');
  }

  String scannerError(String code) {
    return _text(en: 'Scanner error: $code', fa: 'خطای اسکنر: ${digits(code)}');
  }

  String platformCode(String code) => _text(en: 'Code: $code', fa: 'کد: ${digits(code)}');
  String platformMessage(String message) => _text(en: 'Message: $message', fa: 'پیام: $message');
  String platformDetails(String details) => _text(en: 'Details: $details', fa: 'جزئیات: $details');

  String eachPrice(String value) => _text(en: '$value each', fa: 'هر عدد $value');
  String currentStock(String value) => _text(en: 'Stock: $value', fa: 'موجودی: $value');
  String stockInline(String value) => _text(en: 'Stock: $value', fa: 'موجودی: $value');
  String stockLabel(String value) => _text(en: 'Stock: $value', fa: 'موجودی: $value');
  String quantityShort(String value) => _text(en: 'Qty: $value', fa: 'تعداد: $value');
  String itemsCount(int value) => _text(en: 'Items: ${integer(value)}', fa: 'کالاها: ${integer(value)}');
  String lineQuantity(String value) => _text(en: 'Quantity: $value', fa: 'تعداد: $value');
  String transactionTotal(String value) => _text(en: 'Total: $value', fa: 'مجموع: $value');
  String availableStockWarning(String value) {
    return _text(
      en: 'Only $value is available in stock. Restock this product before completing the sale.',
      fa: 'فقط $value در موجودی موجود است. قبل از تکمیل فروش این کالا را تأمین کنید.',
    );
  }

  String get decreaseQuantity => _text(en: 'Decrease quantity', fa: 'کاهش تعداد');
  String get increaseQuantity => _text(en: 'Increase quantity', fa: 'افزایش تعداد');
  String get removeProduct => _text(en: 'Remove product', fa: 'حذف کالا');

  String inventoryFailed(Object error) {
    return _text(en: 'Inventory could not load.', fa: 'موجودی بارگیری نشد.');
  }

  String inventoryProductSemantics({
    required String name,
    required String quantity,
  }) {
    return _text(en: '$name, stock $quantity', fa: '$name، موجودی $quantity');
  }

  String get noLowStockProducts {
    return _text(en: 'No low-stock products.', fa: 'کالای کم موجودی وجود ندارد.');
  }

  String reportsFailed(Object error) {
    return _text(en: 'Reports could not load.', fa: 'گزارش ها بارگیری نشد.');
  }

  String get localCashierTransactions {
    return _text(en: 'Local cashier transactions', fa: 'تراکنش های همین صندوق');
  }

  String get allDevices => _text(en: 'All devices', fa: 'همه دستگاه ها');
  String get selectedCashier => _text(en: 'Selected cashier', fa: 'صندوق انتخاب شده');
  String get cashierDeviceField => _text(en: 'Cashier device', fa: 'دستگاه صندوق');
  String get salesTrend => _text(en: 'Sales trend', fa: 'روند فروش');
  String get noTransactions => _text(en: 'No transactions yet.', fa: 'هنوز تراکنشی وجود ندارد.');
  String get noPreviousTransactions => _text(en: 'No previous transactions.', fa: 'تراکنش قبلی وجود ندارد.');
  String get noLineDetails => _text(en: 'No line details.', fa: 'جزئیات ردیف وجود ندارد.');
  String get transactionHistoryFailed {
    return _text(en: 'Transaction history could not load.', fa: 'سابقه تراکنش ها بارگیری نشد.');
  }

  String get selectedCreator => _text(en: 'Selected personnel', fa: 'کارمند انتخاب شده');
  String get allDates => _text(en: 'All dates', fa: 'همه تاریخ ها');
  String get clearDateRange => _text(en: 'Clear date range', fa: 'پاک کردن بازه تاریخ');
  String get customDateRange => _text(en: 'Custom date range', fa: 'بازه تاریخ دلخواه');
  String get startDate => _text(en: 'Start date', fa: 'تاریخ شروع');
  String get endDate => _text(en: 'End date', fa: 'تاریخ پایان');
  String get selectDate => _text(en: 'Select date', fa: 'انتخاب تاریخ');
  String get applyDateRange => _text(en: 'Apply range', fa: 'اعمال بازه');
  String get previousMonth => _text(en: 'Previous month', fa: 'ماه قبل');
  String get nextMonth => _text(en: 'Next month', fa: 'ماه بعد');
  String get periodUnitDay => _text(en: 'day', fa: 'روز');
  String get periodUnitWeek => _text(en: 'week', fa: 'هفته');
  String get periodUnitMonth => _text(en: 'month', fa: 'ماه');
  String get periodUnitRange => _text(en: 'range', fa: 'بازه');
  String previousPeriod(String unit) => _text(en: 'Previous $unit', fa: '$unit قبل');
  String nextPeriod(String unit) => _text(en: 'Next $unit', fa: '$unit بعد');
  String dateRangeEndpoint({required String label, required String value}) {
    return '$label: $value';
  }

  String unsyncedTransactionsWarning(int count) {
    return _text(
      en: '${integer(count)} transactions have not synced yet. Check the device connection.',
      fa: '${integer(count)} تراکنش هنوز همگام نشده است. اتصال دستگاه را بررسی کنید.',
    );
  }

  String get last7Days => _text(en: 'Last 7 days', fa: '۷ روز گذشته');
  String get last8Weeks => _text(en: 'Last 8 weeks', fa: '۸ هفته گذشته');
  String get last12Months => _text(en: 'Last 12 months', fa: '۱۲ ماه گذشته');
  String get last5Years => _text(en: 'Last 5 years', fa: '۵ سال گذشته');
  String get noSalesPurchasesInPeriod {
    return _text(en: 'No sales or restocks in this period.', fa: 'در این دوره فروش یا تأمین وجود ندارد.');
  }

  String noSalesPurchasesInWindow(String window) {
    return _text(en: 'No sales or restocks in $window.', fa: 'در $window فروش یا تأمین وجود ندارد.');
  }

  String trendSummary({
    required String window,
    required String revenueAmount,
    required String purchasesAmount,
    required String netAmount,
  }) {
    return _text(
      en: '$window: revenue $revenueAmount, restock $purchasesAmount, net $netAmount.',
      fa: '$window: فروش $revenueAmount، تأمین $purchasesAmount، خالص $netAmount.',
    );
  }

  String reportTrendBucketSemantics({
    required String label,
    required String revenueAmount,
    required String purchasesAmount,
  }) {
    return _text(
      en: '$label, revenue $revenueAmount, restock $purchasesAmount',
      fa: '$label، فروش $revenueAmount، تأمین $purchasesAmount',
    );
  }

  String chartFailed(Object error) {
    return _text(en: 'Chart could not load.', fa: 'نمودار بارگیری نشد.');
  }

  String get saveBackup => _text(en: 'Save backup', fa: 'ذخیره پشتیبان');
  String get restoreBackup => _text(en: 'Restore backup', fa: 'بازیابی پشتیبان');
  String get backupHelp {
    return _text(
      en: 'Back up your data before moving or resetting devices.',
      fa: 'قبل از جابه جایی یا بازنشانی دستگاه ها از داده ها پشتیبان بگیرید.',
    );
  }

  String get lastSuccessfulBackup {
    return _text(en: 'Last successful backup', fa: 'آخرین پشتیبان موفق');
  }

  String get noBackupSavedInThisSession {
    return _text(en: 'No backup saved in this session.', fa: 'در این نشست پشتیبانی ذخیره نشده است.');
  }

  String get backupSavedSuccessfully {
    return _text(en: 'Backup saved successfully', fa: 'پشتیبان با موفقیت ذخیره شد');
  }

  String get backupRestoredSuccessfully {
    return _text(en: 'Backup restored successfully', fa: 'پشتیبان با موفقیت بازیابی شد');
  }

  String backupRestoredWithSkippedDuplicates(int count) {
    return _text(
      en: 'Backup restored. ${integer(count)} duplicate records were skipped.',
      fa: 'پشتیبان بازیابی شد. ${integer(count)} رکورد تکراری رد شد.',
    );
  }

  String get chooseValidBackupFile {
    return _text(en: 'Choose a valid backup file.', fa: 'یک فایل پشتیبان معتبر انتخاب کنید.');
  }

  String get retryBackup => _text(en: 'Try backup again', fa: 'تلاش دوباره برای پشتیبان');
  String get restoreBackupQuestion {
    return _text(en: 'Restore this backup?', fa: 'این پشتیبان بازیابی شود؟');
  }

  String restoreBackupPreview({
    required String fileName,
    required int recordCount,
    required String exportedAt,
  }) {
    return _text(
      en: '$fileName contains ${integer(recordCount)} records from $exportedAt. Current data may be replaced.',
      fa: '$fileName شامل ${integer(recordCount)} رکورد از $exportedAt است. داده های فعلی ممکن است جایگزین شوند.',
    );
  }

  String couldNotSaveBackup(Object error) {
    return _text(en: 'Backup could not be saved. Try another location.', fa: 'پشتیبان ذخیره نشد. محل دیگری را امتحان کنید.');
  }

  String couldNotRestoreBackup(Object error) {
    return _text(en: 'Backup could not be restored.', fa: 'پشتیبان بازیابی نشد.');
  }

  String get connectedCashierDevices {
    return _text(en: 'Connected cashier devices', fa: 'دستگاه های صندوق متصل');
  }

  String connectedDeviceCount(int count) {
    return _text(en: '${integer(count)} devices connected', fa: '${integer(count)} دستگاه متصل');
  }

  String get pairCashierDevice {
    return _text(en: 'Pair cashier device', fa: 'جفت سازی صندوق');
  }

  String get pair => _text(en: 'Pair', fa: 'جفت سازی');
  String get pairing => _text(en: 'Pairing', fa: 'در حال جفت سازی');
  String get startingPairing => _text(en: 'Starting pairing...', fa: 'در حال شروع جفت سازی...');
  String get connectCashierBeforeUse {
    return _text(en: 'Connect a cashier device before using sync.', fa: 'قبل از استفاده از همگام سازی یک صندوق را وصل کنید.');
  }

  String get startPairingToCreateLocalAddress {
    return _text(en: 'Start pairing to create a local address.', fa: 'برای ساخت نشانی محلی جفت سازی را شروع کنید.');
  }

  String localAddress(String value) => _text(en: 'Local address: $value', fa: 'نشانی محلی: $value');
  String get mainDeviceIp => _text(en: 'Main device address', fa: 'نشانی دستگاه اصلی');
  String get ipAddressOrUrl => _text(en: 'IP address or URL', fa: 'نشانی IP یا URL');
  String get enterIpManually => _text(en: 'Enter address manually', fa: 'ورود دستی نشانی');
  String get pairedWithMainDevice => _text(en: 'Paired with main device', fa: 'با دستگاه اصلی جفت شده است');
  String cashierConnectionText(String? name) {
    final label = _blankDisplay(name) ?? _text(en: 'main device', fa: 'دستگاه اصلی');
    return _text(en: 'Connected to $label.', fa: 'به $label متصل است.');
  }

  String get cashierInventoryUpdatePending {
    return _text(en: 'Inventory update pending.', fa: 'به روزرسانی موجودی در انتظار است.');
  }

  String get unpairCashierQuestion {
    return _text(en: 'Unpair this cashier?', fa: 'این صندوق قطع جفت سازی شود؟');
  }

  String unpairCashierHelp(String label) {
    return _text(
      en: '$label will stop syncing. Sale history remains for audit.',
      fa: '$label دیگر همگام نمی شود. سابقه فروش برای حسابرسی باقی می ماند.',
    );
  }

  String get couldNotUnpairCashier {
    return _text(en: 'Could not unpair cashier.', fa: 'قطع جفت سازی صندوق ناموفق بود.');
  }

  String get couldNotStartPairing {
    return _text(en: 'Could not start pairing.', fa: 'شروع جفت سازی ناموفق بود.');
  }

  String get couldNotStopPairing {
    return _text(en: 'Could not stop pairing.', fa: 'توقف جفت سازی ناموفق بود.');
  }

  String get couldNotPairWithMainDevice {
    return _text(en: 'Could not pair with main device.', fa: 'جفت سازی با دستگاه اصلی ناموفق بود.');
  }

  String pairingFailed(Object error) {
    return _text(en: 'Pairing failed.', fa: 'جفت سازی ناموفق بود.');
  }

  String get deviceSyncCouldNotLoad {
    return _text(en: 'Device sync could not load.', fa: 'همگام سازی دستگاه بارگیری نشد.');
  }

  String get deviceSyncUnavailable {
    return _text(en: 'Device sync is unavailable.', fa: 'همگام سازی دستگاه در دسترس نیست.');
  }

  String get mdnsAdvertising => _text(en: 'Local discovery', fa: 'کشف محلی');
  String get mdnsAdvertisingInactive => _text(en: 'Local discovery is inactive.', fa: 'کشف محلی غیرفعال است.');
  String get mdnsAdvertisingUnsupported => _text(en: 'Local discovery is unsupported on this device.', fa: 'کشف محلی روی این دستگاه پشتیبانی نمی شود.');
  String get mdnsAdvertisingNeedsAttention => _text(en: 'Local discovery needs attention.', fa: 'کشف محلی نیاز به توجه دارد.');
  String mdnsAdvertisingActive({required int port, required String checkedAt}) {
    return _text(en: 'Local discovery is active on port ${integer(port)}. Checked $checkedAt.', fa: 'کشف محلی روی درگاه ${integer(port)} فعال است. بررسی $checkedAt.');
  }

  String mdnsAdvertisingFailed(String checkedAt) {
    return _text(en: 'Local discovery failed. Checked $checkedAt.', fa: 'کشف محلی ناموفق بود. بررسی $checkedAt.');
  }

  String get refreshMdnsAdvertising => _text(en: 'Refresh local discovery', fa: 'به روزرسانی کشف محلی');
  String get mdnsDiscovery => _text(en: 'Find main device', fa: 'یافتن دستگاه اصلی');
  String get scanMdns => _text(en: 'Scan network', fa: 'اسکن شبکه');
  String get scanningMdns => _text(en: 'Scanning...', fa: 'در حال اسکن...');
  String get mdnsScanNotRun => _text(en: 'Scan to find nearby main devices.', fa: 'برای یافتن دستگاه اصلی نزدیک اسکن کنید.');
  String get mdnsScanFailed => _text(en: 'Network scan failed.', fa: 'اسکن شبکه ناموفق بود.');
  String get mdnsNoMainDevicesFound => _text(en: 'No main devices found.', fa: 'دستگاه اصلی پیدا نشد.');
  String mdnsMainDevicesFound(int count) => _text(en: '${integer(count)} main devices found.', fa: '${integer(count)} دستگاه اصلی پیدا شد.');
  String mdnsDiscoveredMainDevice({
    required String deviceId,
    required String address,
    required String trustLabel,
  }) {
    return _text(en: '$deviceId at $address ($trustLabel)', fa: '$deviceId در $address ($trustLabel)');
  }

  String get trustedMainDevice => _text(en: 'trusted', fa: 'مطمئن');
  String get untrustedMainDevice => _text(en: 'not trusted', fa: 'نامطمئن');
  String get trustedCashierDevice => _text(en: 'trusted cashier', fa: 'صندوق مطمئن');
  String get cashierMdnsPresenceNote {
    return _text(en: 'Keep both devices on the same network.', fa: 'هر دو دستگاه را روی یک شبکه نگه دارید.');
  }

  String get notCheckedYet => _text(en: 'not checked yet', fa: 'هنوز بررسی نشده');

  String get backupSaleHistoryAndReset {
    return _text(en: 'Back up sale history and reset', fa: 'پشتیبان گیری از سابقه فروش و بازنشانی');
  }

  String get backingUpSaleHistory {
    return _text(en: 'Backing up sale history...', fa: 'در حال پشتیبان گیری از سابقه فروش...');
  }

  String get backupRequiredBeforeReset {
    return _text(en: 'A backup is required before reset.', fa: 'قبل از بازنشانی پشتیبان لازم است.');
  }

  String get cashierResetReadyToPair {
    return _text(en: 'Cashier reset. Ready to pair again.', fa: 'صندوق بازنشانی شد و آماده جفت سازی است.');
  }

  String get cashierUnpairedTitle {
    return _text(en: 'Cashier unpaired', fa: 'صندوق قطع جفت سازی شد');
  }

  String get cashierUnpairedHelp {
    return _text(
      en: 'Back up this cashier sale history before pairing again.',
      fa: 'قبل از جفت سازی دوباره، سابقه فروش این صندوق را پشتیبان بگیرید.',
    );
  }

  String openSyncPeerMessageDetails(int index) => _text(en: 'Open message ${integer(index)} details', fa: 'باز کردن جزئیات پیام ${integer(index)}');
  String syncPeer(String peer) => _text(en: 'Peer $peer', fa: 'همتا $peer');
  String syncMessageSent(String method, String path, String status) => _text(en: 'Sent $status$method $path', fa: 'ارسال $status$method $path');
  String syncMessageReceived(String method, String path, String status) => _text(en: 'Received $status$method $path', fa: 'دریافت $status$method $path');
  String get syncMessageTypeHealth => _text(en: 'Health', fa: 'سلامت');
  String get syncMessageTypeDeviceInfo => _text(en: 'Device info', fa: 'اطلاعات دستگاه');
  String get syncMessageTypePairing => _text(en: 'Pairing', fa: 'جفت سازی');
  String get syncMessageTypeEventPull => _text(en: 'Event pull', fa: 'دریافت رویداد');
  String get syncMessageTypeEventPush => _text(en: 'Event push', fa: 'ارسال رویداد');
  String get syncMessageTypeSyncState => _text(en: 'Sync state', fa: 'وضعیت همگام سازی');
  String syncMessageTypeHttp(String method, String path) => '$method $path';
  String get syncPeerMessageDetails => _text(en: 'Message details', fa: 'جزئیات پیام');
  String get syncPeerMessageIndexLabel => _text(en: 'Index', fa: 'شماره');
  String get syncPeerMessageTypeLabel => _text(en: 'Type', fa: 'نوع');
  String get syncPeerMessageRequestLabel => _text(en: 'Request', fa: 'درخواست');
  String get syncPeerMessageSummaryLabel => _text(en: 'Summary', fa: 'خلاصه');
  String get syncPeerMessagePeerLabel => _text(en: 'Peer', fa: 'همتا');
  String get syncPeerMessageContent => _text(en: 'Content', fa: 'محتوا');
  String get syncPeerMessageTimeSent => _text(en: 'Sent at', fa: 'زمان ارسال');
  String get syncPeerMessageTimeReceived => _text(en: 'Received at', fa: 'زمان دریافت');
  String get noSyncPeerMessageContent => _text(en: 'No message content.', fa: 'محتوای پیام وجود ندارد.');
  String syncPeerMessageIndex(int index) => integer(index);

  String get newSale => _text(en: 'New Sale', fa: 'فروش جدید');
  String get shareReceipt => _text(en: 'Share Receipt', fa: 'اشتراک رسید');
  String get searchCustomer => _text(en: 'Search customer by name or phone', fa: 'جستجوی مشتری با نام یا تلفن');
  String get newCustomer => _text(en: 'New customer', fa: 'مشتری جدید');
  String get phoneNumber => _text(en: 'Phone number', fa: 'شماره تلفن');
  String get fullNameOptional => _text(en: 'Full name optional', fa: 'نام کامل اختیاری');
  String get sendAndSaveCustomer => _text(en: 'Send and Save Customer', fa: 'ارسال و ذخیره مشتری');
  String get shareWithoutSaving => _text(en: 'Share without saving', fa: 'اشتراک بدون ذخیره');
  String get customerWillBeSavedForReceipts {
    return _text(
      en: 'Use Send and Save Customer to save this customer for future receipts.',
      fa: 'برای ذخیره این مشتری جهت رسیدهای آینده از ارسال و ذخیره مشتری استفاده کنید.',
    );
  }

  String receiptReadyToShare(String total) => _text(en: 'Receipt ready. Total: $total', fa: 'رسید آماده است. مجموع: $total');
  String saleReceiptNumber(String value) => _text(en: 'Receipt #$value', fa: 'رسید شماره $value');
  String saleReceiptLine(String name, String quantity, String amount) => _text(en: '$name x$quantity    $amount', fa: '$name x$quantity    $amount');
  String get receiptThankYou => _text(en: 'Thank you.', fa: 'سپاسگزاریم.');
  String get unknownProduct => _text(en: 'Unknown product', fa: 'کالای نامشخص');
  String get noCustomersFound => _text(en: 'No customers found.', fa: 'مشتری پیدا نشد.');
  String get customerSearchFailed => _text(en: 'Customer search failed.', fa: 'جستجوی مشتری ناموفق بود.');
  String get enterValidCustomerPhone {
    return _text(en: 'Enter a valid customer phone number.', fa: 'شماره تلفن معتبر وارد کنید.');
  }

  String get receiptShareFailed {
    return _text(en: 'Receipt could not be shared. Try another option.', fa: 'رسید اشتراک نشد. گزینه دیگری را امتحان کنید.');
  }

  String get customerSaveFailed {
    return _text(en: 'Customer could not be saved.', fa: 'مشتری ذخیره نشد.');
  }

  List<String> get persianWeekdayShortNames {
    return const ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];
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
    if (month < 1 || month > names.length) return integer(month);
    return names[month - 1];
  }

  String shortMonthName(int month) {
    final value = monthName(month);
    if (language == AppLanguage.farsi || value.length <= 3) return value;
    return value.substring(0, 3);
  }

  List<String> _timeParts(DateTime value) {
    return [
      value.hour.toString().padLeft(2, '0'),
      value.minute.toString().padLeft(2, '0'),
    ];
  }

  String? _blankDisplay(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _text({required String en, required String fa}) {
    return language == AppLanguage.farsi ? fa : en;
  }
}
