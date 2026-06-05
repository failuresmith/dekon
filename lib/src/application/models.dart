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
  });

  final DeviceRole role;
  final bool locked;
  final bool onboardingCompleted;
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

enum TransactionHistoryKind { sale, purchase }

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
  });

  final String id;
  final TransactionHistoryKind kind;
  final DateTime occurredAt;
  final int totalMinor;
  final List<TransactionHistoryLine> lines;
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
    required this.stockRows,
    required this.dailySalesMinor,
    required this.dailyPurchasesMinor,
    required this.grossMarginMinor,
    required this.lowStockRows,
    required this.unsyncedEventCount,
    required this.lastSyncAt,
  });

  final List<StockReportRow> stockRows;
  final int dailySalesMinor;
  final int dailyPurchasesMinor;
  final int grossMarginMinor;
  final List<StockReportRow> lowStockRows;
  final int unsyncedEventCount;
  final DateTime? lastSyncAt;
}
