import '../application/models.dart';

const cashierProjectionProductUpsert = 'product_upsert';
const cashierProjectionInventoryPatch = 'inventory_patch';
const cashierProjectionSnapshotRequired = 'snapshot_required';

class CashierProjectionUpdate {
  const CashierProjectionUpdate._({
    required this.projectionVersion,
    required this.type,
    this.product,
    this.products = const [],
  });

  factory CashierProjectionUpdate.fromJson(Object? value) {
    final map = _stringMap(value, 'cashier projection update');
    final type = _stringField(map, 'type');
    final projectionVersion = _projectionVersionField(
      map,
      'projection_version',
    );
    return switch (type) {
      cashierProjectionProductUpsert => CashierProjectionUpdate._(
        projectionVersion: projectionVersion,
        type: type,
        product: _productPayload(map['payload']),
      ),
      cashierProjectionInventoryPatch => CashierProjectionUpdate._(
        projectionVersion: projectionVersion,
        type: type,
        products: _productsPayload(map['payload']),
      ),
      cashierProjectionSnapshotRequired => CashierProjectionUpdate._(
        projectionVersion: projectionVersion,
        type: type,
      ),
      _ => throw FormatException('Unsupported Cashier projection type: $type.'),
    };
  }

  final int projectionVersion;
  final String type;
  final CashierProductProjection? product;
  final List<CashierInventoryPatchProduct> products;
}

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

  factory CashierProductProjection.fromJson(Object? value) {
    final map = _stringMap(value, 'cashier product projection');
    return CashierProductProjection(
      productId: _stringField(map, 'product_id'),
      barcode: _optionalStringField(map, 'barcode'),
      name: _stringField(map, 'name'),
      stockQuantity: _numberField(map, 'stock_quantity'),
      salePriceMinor: _nonNegativeIntField(map, 'sale_price_minor'),
      active: _boolField(map, 'active'),
    );
  }

  final String productId;
  final String? barcode;
  final String name;
  final double stockQuantity;
  final int salePriceMinor;
  final bool active;
}

class CashierInventorySnapshot {
  const CashierInventorySnapshot({
    required this.projectionVersion,
    required this.products,
  });

  factory CashierInventorySnapshot.fromJson(Object? value) {
    final map = _stringMap(value, 'cashier inventory snapshot');
    final rawProducts = map['products'];
    if (rawProducts is! List) {
      throw const FormatException('products must be a list.');
    }
    return CashierInventorySnapshot(
      projectionVersion: _projectionVersionField(map, 'projection_version'),
      products: [
        for (final rawProduct in rawProducts)
          CashierProductProjection.fromJson(rawProduct),
      ],
    );
  }

  final int projectionVersion;
  final List<CashierProductProjection> products;

  Map<String, Object?> toJson() {
    return serializeCashierInventorySnapshot(
      projectionVersion: projectionVersion,
      products: products,
    );
  }
}

class CashierInventoryPatchProduct {
  const CashierInventoryPatchProduct({
    required this.productId,
    required this.stockQuantity,
  });

  factory CashierInventoryPatchProduct.fromJson(Object? value) {
    final map = _stringMap(value, 'cashier inventory patch product');
    return CashierInventoryPatchProduct(
      productId: _stringField(map, 'product_id'),
      stockQuantity: _numberField(map, 'stock_quantity'),
    );
  }

  final String productId;
  final double stockQuantity;
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

Map<String, Object?> serializeCashierInventoryPatchMessage({
  required int projectionVersion,
  required Iterable<CashierInventoryPatchProduct> products,
}) {
  return {
    'projection_version': _projectionVersion(projectionVersion),
    'type': cashierProjectionInventoryPatch,
    'payload': {
      'products': [
        for (final product in products)
          _serializeInventoryPatchProduct(product),
      ],
    },
  };
}

Map<String, Object?> serializeCashierSnapshotRequiredMessage({
  required int projectionVersion,
}) {
  return {
    'projection_version': _projectionVersion(projectionVersion),
    'type': cashierProjectionSnapshotRequired,
    'payload': const <String, Object?>{},
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

Map<String, Object?> _serializeInventoryPatchProduct(
  CashierInventoryPatchProduct product,
) {
  if (product.productId.trim().isEmpty) {
    throw ArgumentError.value(product.productId, 'productId');
  }
  if (!product.stockQuantity.isFinite) {
    throw ArgumentError.value(product.stockQuantity, 'stockQuantity');
  }
  return {
    'product_id': product.productId,
    'stock_quantity': product.stockQuantity,
  };
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Map<String, Object?> _stringMap(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label must be an object.');
  }
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value as Object?,
  };
}

String _stringField(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw FormatException('$field must be a non-empty string.');
}

String? _optionalStringField(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value == null) return null;
  if (value is String) return _blankToNull(value);
  throw FormatException('$field must be a string or null.');
}

double _numberField(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('$field must be a finite number.');
}

int _nonNegativeIntField(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is int && value >= 0) return value;
  throw FormatException('$field must be a non-negative integer.');
}

int _projectionVersionField(Map<String, Object?> map, String field) {
  final value = _nonNegativeIntField(map, field);
  return _projectionVersion(value);
}

bool _boolField(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is bool) return value;
  throw FormatException('$field must be a boolean.');
}

CashierProductProjection _productPayload(Object? value) {
  final payload = _stringMap(value, 'cashier product-upsert payload');
  return CashierProductProjection.fromJson(payload['product']);
}

List<CashierInventoryPatchProduct> _productsPayload(Object? value) {
  final payload = _stringMap(value, 'cashier inventory-patch payload');
  final rawProducts = payload['products'];
  if (rawProducts is! List) {
    throw const FormatException('products must be a list.');
  }
  return [
    for (final rawProduct in rawProducts)
      CashierInventoryPatchProduct.fromJson(rawProduct),
  ];
}
