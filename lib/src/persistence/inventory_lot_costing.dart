import 'package:sqflite/sqflite.dart';

const _lotQuantityEpsilon = 0.000000001;

class InventoryLotAllocationException implements Exception {
  const InventoryLotAllocationException(this.productId);

  final String productId;

  @override
  String toString() => 'Insufficient costed inventory for product $productId.';
}

class InventorySaleCostRequest {
  const InventorySaleCostRequest({
    required this.productId,
    required this.quantity,
    required this.unitPriceMinor,
  });

  final String productId;
  final double quantity;
  final int unitPriceMinor;
}

class InventorySaleCostedLine {
  const InventorySaleCostedLine({
    required this.productId,
    required this.quantity,
    required this.unitPriceMinor,
    required this.costTotalMinor,
    required this.allocations,
  });

  final String productId;
  final double quantity;
  final int unitPriceMinor;
  final int costTotalMinor;
  final List<InventoryLotCostAllocation> allocations;

  int get saleTotalMinor => (quantity * unitPriceMinor).round();

  Map<String, Object?> toPayload() => {
    'product_id': productId,
    'quantity': quantity,
    'unit_price_minor': unitPriceMinor,
    'cost_total_minor': costTotalMinor,
    'cost_allocations': [
      for (final allocation in allocations) allocation.toPayload(),
    ],
  };
}

class InventoryLotCostAllocation {
  const InventoryLotCostAllocation({
    required this.lotId,
    required this.sourceEventId,
    required this.quantity,
    required this.unitCostMinor,
    required this.costMinor,
  });

  final String lotId;
  final String sourceEventId;
  final double quantity;
  final int unitCostMinor;
  final int costMinor;

  Map<String, Object?> toPayload() => {
    'lot_id': lotId,
    'source_event_id': sourceEventId,
    'quantity': quantity,
    'unit_cost_minor': unitCostMinor,
    'cost_minor': costMinor,
  };
}

Future<List<InventorySaleCostedLine>> allocateFifoInventoryLots(
  DatabaseExecutor db,
  List<InventorySaleCostRequest> requests,
) async {
  final lotsByProductId = <String, List<_AvailableLot>>{};
  final costedLines = <InventorySaleCostedLine>[];
  for (final request in requests) {
    if (!request.quantity.isFinite || request.quantity <= 0) {
      throw ArgumentError.value(request.quantity, 'quantity');
    }
    final lots =
        lotsByProductId[request.productId] ??
        await _loadLots(db, request.productId);
    lotsByProductId[request.productId] = lots;
    var remaining = request.quantity;
    final allocations = <InventoryLotCostAllocation>[];
    for (final lot in lots) {
      if (remaining <= _lotQuantityEpsilon) break;
      if (lot.remainingQuantity <= _lotQuantityEpsilon) continue;
      final allocated = lot.remainingQuantity < remaining
          ? lot.remainingQuantity
          : remaining;
      lot.remainingQuantity -= allocated;
      remaining -= allocated;
      allocations.add(
        InventoryLotCostAllocation(
          lotId: lot.lotId,
          sourceEventId: lot.sourceEventId,
          quantity: allocated,
          unitCostMinor: lot.unitCostMinor,
          costMinor: (allocated * lot.unitCostMinor).round(),
        ),
      );
    }
    if (remaining > _lotQuantityEpsilon) {
      throw InventoryLotAllocationException(request.productId);
    }
    costedLines.add(
      InventorySaleCostedLine(
        productId: request.productId,
        quantity: request.quantity,
        unitPriceMinor: request.unitPriceMinor,
        costTotalMinor: allocations.fold<int>(
          0,
          (sum, allocation) => sum + allocation.costMinor,
        ),
        allocations: List.unmodifiable(allocations),
      ),
    );
  }
  return List.unmodifiable(costedLines);
}

Future<List<_AvailableLot>> _loadLots(
  DatabaseExecutor db,
  String productId,
) async {
  final rows = await db.query(
    'inventory_lots_projection',
    columns: [
      'lot_id',
      'source_event_id',
      'remaining_quantity',
      'unit_cost_minor',
    ],
    where: 'product_id = ? AND remaining_quantity > ?',
    whereArgs: [productId, _lotQuantityEpsilon],
    orderBy: 'received_at ASC, updated_hlc ASC, lot_id ASC',
  );
  return [
    for (final row in rows)
      _AvailableLot(
        lotId: row['lot_id'] as String,
        sourceEventId: row['source_event_id'] as String,
        remainingQuantity: (row['remaining_quantity'] as num).toDouble(),
        unitCostMinor: row['unit_cost_minor'] as int,
      ),
  ];
}

class _AvailableLot {
  _AvailableLot({
    required this.lotId,
    required this.sourceEventId,
    required this.remainingQuantity,
    required this.unitCostMinor,
  });

  final String lotId;
  final String sourceEventId;
  double remainingQuantity;
  final int unitCostMinor;
}
