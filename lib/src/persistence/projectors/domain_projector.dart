import 'package:sqflite/sqflite.dart';

import '../../domain/events/events.dart';
import 'inventory_projector.dart';
import 'product_projector.dart';
import 'projection_result.dart';

class DomainProjector {
  DomainProjector(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;

  Future<ProjectionApplyResult> apply(EventEnvelope event) {
    if (!EventSchema.isSupported(event.schemaVersion)) {
      return Future.value(
        ProjectionApplyResult(ProjectionApplyStatus.unsupported, event.eventId),
      );
    }
    return _db.transaction((txn) async {
      if (await _isAlreadyApplied(txn, event.eventId)) {
        return ProjectionApplyResult(
          ProjectionApplyStatus.duplicate,
          event.eventId,
        );
      }
      await _applySupported(txn, event);
      await txn.insert('projection_applied_events', {
        'event_id': event.eventId,
        'applied_at': _now().toUtc().toIso8601String(),
      });
      return ProjectionApplyResult(
        ProjectionApplyStatus.applied,
        event.eventId,
      );
    });
  }

  Future<void> _applySupported(Transaction txn, EventEnvelope event) async {
    final productProjector = ProductProjector(txn);
    final inventoryProjector = InventoryProjector(txn);
    switch (event.type) {
      case EventTypes.productCreated:
        return productProjector.applyCreated(event);
      case EventTypes.productFieldSet:
        return productProjector.applyFieldSet(event);
      case EventTypes.productDeactivated:
        return productProjector.applyDeactivated(event);
      case EventTypes.inventoryPurchaseRecorded:
        return inventoryProjector.applyPurchase(event);
      case EventTypes.inventorySaleRecorded:
        return inventoryProjector.applySale(event);
      case EventTypes.inventoryAdjustmentRecorded:
        return inventoryProjector.applyAdjustment(event);
      case EventTypes.saleVoided:
        return inventoryProjector.applySaleVoided(event);
      case EventTypes.purchaseCorrected:
        return inventoryProjector.applyPurchaseCorrected(event);
      default:
        throw ProjectionException('Unsupported event type: ${event.type}.');
    }
  }

  Future<bool> _isAlreadyApplied(Transaction txn, String eventId) async {
    final rows = await txn.query(
      'projection_applied_events',
      columns: ['event_id'],
      where: 'event_id = ?',
      whereArgs: [eventId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
