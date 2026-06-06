import '../domain/events/events.dart';

enum SyncDeviceRole { mainAdmin, cashier }

enum Capability {
  recordSale,
  viewCashierInventory,
  viewOwnSales,
  recordRestock,
  createProduct,
  modifyProduct,
  archiveProduct,
  adjustInventory,
  voidSale,
  correctPurchase,
  viewReports,
  viewAllSales,
  viewAllRestocks,
  manageDevices,
  manageSyncSettings,
  exportData,
  createBackup,
  restoreBackup,
}

class DevicePrincipal {
  const DevicePrincipal({
    required this.deviceId,
    required this.role,
    required this.isLocalMainDevice,
  });

  final String deviceId;
  final SyncDeviceRole role;
  final bool isLocalMainDevice;
}

class AuthorizationException implements Exception {
  const AuthorizationException(this.code);

  static const permissionDenied = 'permission_denied';

  final String code;

  @override
  String toString() => 'AuthorizationException: $code';
}

class AuthorizationService {
  const AuthorizationService();

  static const capabilitiesByRole = <SyncDeviceRole, Set<Capability>>{
    SyncDeviceRole.mainAdmin: {
      Capability.recordSale,
      Capability.viewCashierInventory,
      Capability.viewOwnSales,
      Capability.recordRestock,
      Capability.createProduct,
      Capability.modifyProduct,
      Capability.archiveProduct,
      Capability.adjustInventory,
      Capability.voidSale,
      Capability.correctPurchase,
      Capability.viewReports,
      Capability.viewAllSales,
      Capability.viewAllRestocks,
      Capability.manageDevices,
      Capability.manageSyncSettings,
      Capability.exportData,
      Capability.createBackup,
      Capability.restoreBackup,
    },
    SyncDeviceRole.cashier: {
      Capability.recordSale,
      Capability.viewCashierInventory,
      Capability.viewOwnSales,
    },
  };

  bool isAllowed({
    required DevicePrincipal principal,
    required Capability capability,
  }) {
    return capabilitiesByRole[principal.role]?.contains(capability) ?? false;
  }

  void requireCapability({
    required DevicePrincipal principal,
    required Capability capability,
  }) {
    if (!isAllowed(principal: principal, capability: capability)) {
      throw const AuthorizationException(
        AuthorizationException.permissionDenied,
      );
    }
  }
}

Capability? capabilityForRemoteEvent(EventEnvelope event) {
  return switch (event.type) {
    EventTypes.inventorySaleRecorded => Capability.recordSale,
    EventTypes.inventoryPurchaseRecorded => Capability.recordRestock,
    EventTypes.productCreated => Capability.createProduct,
    EventTypes.productFieldSet => Capability.modifyProduct,
    EventTypes.productDeactivated => Capability.archiveProduct,
    EventTypes.inventoryAdjustmentRecorded => Capability.adjustInventory,
    EventTypes.saleVoided => Capability.voidSale,
    EventTypes.purchaseCorrected => Capability.correctPurchase,
    _ => null,
  };
}

EventEnvelope? cashierSafeEventFor({
  required EventEnvelope event,
  required String cashierDeviceId,
}) {
  final payload = event.payload;
  return switch (event.type) {
    EventTypes.productCreated => _copyEvent(
      event,
      payload: {
        'name': _string(payload, 'name', fallback: ''),
        'barcode': _nullableString(payload, 'barcode'),
        'unit': _string(payload, 'unit', fallback: 'each'),
        'sale_price_minor': _int(payload, 'sale_price_minor', fallback: 0),
        'active': _bool(payload, 'active', fallback: true),
      },
    ),
    EventTypes.productFieldSet => _cashierSafeProductFieldSet(event),
    EventTypes.productDeactivated => _copyEvent(event, payload: const {}),
    EventTypes.inventoryPurchaseRecorded => _stockOnlyAdjustment(
      event,
      quantityField: 'quantity',
      multiplier: 1,
    ),
    EventTypes.inventorySaleRecorded =>
      event.deviceId == cashierDeviceId
          ? event
          : _stockOnlyAdjustment(
              event,
              quantityField: 'quantity',
              multiplier: -1,
            ),
    EventTypes.inventoryAdjustmentRecorded => _stockOnlyAdjustment(
      event,
      quantityField: 'quantity_delta',
      multiplier: 1,
    ),
    EventTypes.saleVoided => _stockOnlyAdjustment(
      event,
      quantityField: 'quantity',
      multiplier: 1,
    ),
    EventTypes.purchaseCorrected => _stockOnlyAdjustment(
      event,
      quantityField: 'quantity_delta',
      multiplier: 1,
    ),
    _ => null,
  };
}

EventEnvelope? _cashierSafeProductFieldSet(EventEnvelope event) {
  final field = event.payload['field'];
  if (field is! String) return null;
  if (!const {
    'name',
    'barcode',
    'unit',
    'sale_price_minor',
    'active',
  }.contains(field)) {
    return null;
  }
  return _copyEvent(
    event,
    payload: {'field': field, 'value': event.payload['value']},
  );
}

EventEnvelope? _stockOnlyAdjustment(
  EventEnvelope event, {
  required String quantityField,
  required int multiplier,
}) {
  final lines = _stockOnlyLines(
    event.payload,
    quantityField: quantityField,
    multiplier: multiplier,
  );
  if (lines == null) return null;
  return _copyEvent(
    event,
    type: EventTypes.inventoryAdjustmentRecorded,
    payload: {'line_items': lines},
  );
}

List<Map<String, Object?>>? _stockOnlyLines(
  Map<String, Object?> payload, {
  required String quantityField,
  required int multiplier,
}) {
  final rawLines = payload['line_items'];
  if (rawLines is! List) return null;
  final lines = <Map<String, Object?>>[];
  for (final rawLine in rawLines) {
    if (rawLine is! Map) return null;
    final line = Map<String, Object?>.from(rawLine);
    final productId = line['product_id'];
    final quantity = line[quantityField];
    if (productId is! String || productId.trim().isEmpty) return null;
    if (quantity is! num || !quantity.isFinite) return null;
    lines.add({
      'product_id': productId,
      'quantity_delta': quantity.toDouble() * multiplier,
    });
  }
  return lines;
}

EventEnvelope _copyEvent(
  EventEnvelope event, {
  String? type,
  required Map<String, Object?> payload,
}) {
  return EventEnvelope.local(
    eventId: event.eventId,
    deviceId: event.deviceId,
    hlc: event.hlc,
    type: type ?? event.type,
    entityId: event.entityId,
    payload: payload,
    schemaVersion: event.schemaVersion,
    createdAt: event.createdAt,
  );
}

String _string(
  Map<String, Object?> payload,
  String key, {
  required String fallback,
}) {
  final value = payload[key];
  return value is String ? value : fallback;
}

String? _nullableString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  return value is String ? value : null;
}

int _int(Map<String, Object?> payload, String key, {required int fallback}) {
  final value = payload[key];
  return value is int && value >= 0 ? value : fallback;
}

bool _bool(Map<String, Object?> payload, String key, {required bool fallback}) {
  final value = payload[key];
  return value is bool ? value : fallback;
}
