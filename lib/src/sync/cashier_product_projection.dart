import '../application/models.dart';

const cashierProjectionProductUpsert = 'product_upsert';

class CashierProductProjection {
  const CashierProductProjection({
    required this.productId,
    required this.barcode,
    required this.name,
    required this.stockQuantity,
    required this.salePriceMinor,
    required this.active,
  }) : assert(productId.length > 0),
       assert(salePriceMinor >= 0);

  factory CashierProductProjection.fromProductSummary(ProductSummary product) {
    return CashierProductProjection(
      productId: product.productId,
      barcode: _blankToNull(product.barcode),
      name: product.name,
      stockQuantity: product.quantity,
      salePriceMinor: product.salePriceMinor,
      active: product.active,
    );
  }

  final String productId;
  final String? barcode;
  final String name;
  final double stockQuantity;
  final int salePriceMinor;
  final bool active;
}

Map<String, Object?> serializeCashierProductProjection(
  CashierProductProjection product,
) {
  _validateCashierProduct(product);
  return {
    'product_id': product.productId,
    'barcode': product.barcode,
    'name': product.name,
    'stock_quantity': product.stockQuantity,
    'sale_price_minor': product.salePriceMinor,
    'active': product.active,
  };
}

Map<String, Object?> serializeCashierInventorySnapshot({
  required int projectionVersion,
  required Iterable<CashierProductProjection> products,
}) {
  return {
    'projection_version': _projectionVersion(projectionVersion),
    'products': [
      for (final product in products)
        serializeCashierProductProjection(product),
    ],
  };
}

Map<String, Object?> serializeCashierProductUpsertMessage({
  required int projectionVersion,
  required CashierProductProjection product,
}) {
  return {
    'projection_version': _projectionVersion(projectionVersion),
    'type': cashierProjectionProductUpsert,
    'payload': {'product': serializeCashierProductProjection(product)},
  };
}

void _validateCashierProduct(CashierProductProjection product) {
  if (product.productId.trim().isEmpty) {
    throw ArgumentError.value(product.productId, 'productId');
  }
  if (!product.stockQuantity.isFinite) {
    throw ArgumentError.value(product.stockQuantity, 'stockQuantity');
  }
  if (product.salePriceMinor < 0) {
    throw ArgumentError.value(product.salePriceMinor, 'salePriceMinor');
  }
}

int _projectionVersion(int value) {
  if (value < 0) throw ArgumentError.value(value, 'projectionVersion');
  return value;
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
