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
