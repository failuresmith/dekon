class ProductSummary {
  const ProductSummary({
    required this.productId,
    required this.name,
    required this.barcode,
    required this.sku,
    required this.unit,
    required this.salePriceMinor,
    required this.purchaseCostMinor,
    required this.active,
    required this.quantity,
  });

  final String productId;
  final String name;
  final String? barcode;
  final String? sku;
  final String unit;
  final int salePriceMinor;
  final int purchaseCostMinor;
  final bool active;
  final double quantity;
}

enum DeviceRole {
  mainDevice('main_device'),
  cashierDevice('cashier_device');

  const DeviceRole(this.storageValue);

  final String storageValue;

  static DeviceRole fromStorage(String? value) {
    return DeviceRole.values.firstWhere(
      (role) => role.storageValue == value,
      orElse: () => DeviceRole.mainDevice,
    );
  }
}

class DeviceRoleSettings {
  const DeviceRoleSettings({
    required this.role,
    required this.locked,
    required this.onboardingCompleted,
    required this.mainSyncServerEnabled,
    required this.cashierUnpairBackupRequired,
    this.deviceDisplayName,
  });

  final DeviceRole role;
  final bool locked;
  final bool onboardingCompleted;
  final bool mainSyncServerEnabled;
  final bool cashierUnpairBackupRequired;
  final String? deviceDisplayName;
}

enum AppLanguage {
  english('en'),
  farsi('fa');

  const AppLanguage(this.storageValue);

  static const defaultLanguage = AppLanguage.farsi;

  final String storageValue;

  static AppLanguage fromStorage(String? value) {
    return AppLanguage.values.firstWhere(
      (language) => language.storageValue == value,
      orElse: () => AppLanguage.defaultLanguage,
    );
  }
}

enum MoneyUnit {
  rial('rial'),
  toman('toman');

  const MoneyUnit(this.storageValue);

  final String storageValue;

  static MoneyUnit fromStorage(String? value) {
    return MoneyUnit.values.firstWhere(
      (unit) => unit.storageValue == value,
      orElse: () => MoneyUnit.rial,
    );
  }
}

class TransactionLineDraft {
  TransactionLineDraft({
    required this.product,
    required this.quantity,
    int? unitPriceMinor,
    int? unitCostMinor,
  }) : unitPriceMinor = unitPriceMinor ?? product.salePriceMinor,
       unitCostMinor = unitCostMinor ?? product.purchaseCostMinor;

  final ProductSummary product;
  final double quantity;
  final int unitPriceMinor;
  final int unitCostMinor;

  int get saleTotalMinor => (quantity * unitPriceMinor).round();
  int get purchaseTotalMinor => (quantity * unitCostMinor).round();
}

enum SaleRecordStatus { completed, queued, conflict }

class SaleRecordResult {
  const SaleRecordResult({
    required this.status,
    this.saleId,
    this.commandId,
    this.occurredAt,
  });

  const SaleRecordResult.completed({
    required String this.saleId,
    required DateTime this.occurredAt,
  }) : status = SaleRecordStatus.completed,
      commandId = null;

  final SaleRecordStatus status;
  final String? saleId;
  final String? commandId;
  final DateTime? occurredAt;
}

class CustomerSummary {
  const CustomerSummary({
    required this.customerId,
    required this.phoneNumber,
    required this.fullName,
  });

  final String customerId;
  final String phoneNumber;
  final String? fullName;

  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return phoneNumber;
  }
}

class CashierSaleOutboxSummary {
  const CashierSaleOutboxSummary({
    required this.queuedCount,
    required this.syncingCount,
    required this.conflictCount,
  });

  static const empty = CashierSaleOutboxSummary(
    queuedCount: 0,
    syncingCount: 0,
    conflictCount: 0,
  );

  final int queuedCount;
  final int syncingCount;
  final int conflictCount;

  int get pendingCount => queuedCount + syncingCount;
  bool get hasConflict => conflictCount > 0;
  bool get hasPending => pendingCount > 0;
}

enum TransactionHistoryKind { sale, purchase }

enum ReportScope { allDevices, localDevice }

enum ReportCalendar { gregorian, persian }

enum ReportTrendPeriod { day, week, month, year }

class CashierReportFilter {
  const CashierReportFilter({
    required this.deviceId,
    required this.label,
    this.lastAppliedProjectionVersion,
    this.currentProjectionVersion = 0,
  });

  final String deviceId;
  final String label;
  final int? lastAppliedProjectionVersion;
  final int currentProjectionVersion;

  bool get projectionLagging {
    final applied = lastAppliedProjectionVersion;
    return applied != null && applied < currentProjectionVersion;
  }
}

class TransactionHistoryLine {
  const TransactionHistoryLine({
    required this.productName,
    required this.quantity,
    required this.lineTotalMinor,
  });

  final String productName;
  final double quantity;
  final int lineTotalMinor;
}

class TransactionHistoryEntry {
  const TransactionHistoryEntry({
    required this.id,
    required this.kind,
    required this.occurredAt,
    required this.totalMinor,
    required this.lines,
    required this.createdByDeviceId,
    required this.createdByLabel,
    this.pendingMainApproval = false,
  });

  final String id;
  final TransactionHistoryKind kind;
  final DateTime occurredAt;
  final int totalMinor;
  final List<TransactionHistoryLine> lines;
  final String createdByDeviceId;
  final String createdByLabel;
  final bool pendingMainApproval;
}

class TransactionCreatorFilter {
  const TransactionCreatorFilter({required this.deviceId, required this.label});

  final String deviceId;
  final String label;
}

class ReportDateRange {
  const ReportDateRange({
    required this.startLocal,
    required this.endLocalExclusive,
  });

  final DateTime startLocal;
  final DateTime endLocalExclusive;

  DateTime get startUtc => startLocal.toUtc();
  DateTime get endUtcExclusive => endLocalExclusive.toUtc();
}

class ReportTrendBucket {
  const ReportTrendBucket({
    required this.range,
    required this.salesMinor,
    required this.purchasesMinor,
  });

  final ReportDateRange range;
  final int salesMinor;
  final int purchasesMinor;

  int get maxMinor => salesMinor > purchasesMinor ? salesMinor : purchasesMinor;
}

class StockReportRow {
  const StockReportRow({
    required this.productId,
    required this.name,
    required this.quantity,
  });

  final String productId;
  final String name;
  final double quantity;
}

class ReportSummary {
  const ReportSummary({
    required this.range,
    required this.stockRows,
    required this.salesMinor,
    required this.purchasesMinor,
    required this.grossMarginMinor,
    required this.lowStockRows,
    required this.unsyncedEventCount,
    required this.lastSyncAt,
  });

  final ReportDateRange range;
  final List<StockReportRow> stockRows;
  final int salesMinor;
  final int purchasesMinor;
  final int grossMarginMinor;
  final List<StockReportRow> lowStockRows;
  final int unsyncedEventCount;
  final DateTime? lastSyncAt;

  int get dailySalesMinor => salesMinor;
  int get dailyPurchasesMinor => purchasesMinor;
}
