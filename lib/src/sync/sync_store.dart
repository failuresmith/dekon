import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/events/events.dart';
import '../persistence/persistence.dart';
import 'cashier_product_projection.dart';
import 'sync_activity.dart';
import 'sync_protocol.dart';
import 'sync_security.dart';

enum CashierProjectionApplyStatus { applied, duplicate, gap, snapshotRequired }

class SyncStore {
  SyncStore({
    required Database database,
    required this.localDeviceId,
    EventStore? eventStore,
    DomainProjector? projector,
    this.activityBus,
    DateTime Function()? now,
  }) : _db = database,
       _eventStore = eventStore ?? EventStore(database),
       _projector = projector ?? DomainProjector(database),
       _now = now ?? DateTime.now;

  final Database _db;
  final String localDeviceId;
  final EventStore _eventStore;
  final DomainProjector _projector;
  final SyncActivityBus? activityBus;
  final DateTime Function() _now;

  static const cashierInventoryProjectionVersionSetting =
      'cashier_inventory_projection_version';
  static const lastAppliedCashierProjectionVersionSetting =
      'last_applied_cashier_projection_version';
  static const cashierSaleOutboxMaxActiveCommands = 500;

  SyncDeviceInfo deviceInfo() {
    return SyncDeviceInfo(deviceId: localDeviceId, displayName: 'Dekon phone');
  }

  Future<void> trustPeer({
    required String deviceId,
    required String displayName,
    required String sharedSecret,
    String? baseUrl,
  }) async {
    if (deviceId == localDeviceId) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Cannot trust self.');
    }
    final now = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await _trustPeerInTransaction(
        txn,
        deviceId: deviceId,
        displayName: displayName,
        sharedSecret: sharedSecret,
        baseUrl: baseUrl,
        now: now,
      );
    });
    activityBus?.notifySyncStateChanged();
  }

  Future<String> trustCashierPeer({
    required String deviceId,
    required String sharedSecret,
    String? baseUrl,
  }) async {
    if (deviceId == localDeviceId) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Cannot trust self.');
    }
    final now = _now().toUtc().toIso8601String();
    final assignedDisplayName = await _db.transaction((txn) async {
      final displayName = await _cashierDisplayNameForPairing(txn, deviceId);
      await _trustPeerInTransaction(
        txn,
        deviceId: deviceId,
        displayName: displayName,
        sharedSecret: sharedSecret,
        baseUrl: baseUrl,
        now: now,
        lastSeenAt: now,
      );
      return displayName;
    });
    activityBus?.notifySyncStateChanged();
    return assignedDisplayName;
  }

  Future<void> updateLocalDeviceDisplayName(String displayName) async {
    final now = _now().toUtc().toIso8601String();
    await _db.update(
      'devices',
      {'display_name': _displayName(displayName), 'updated_at': now},
      where: 'device_id = ?',
      whereArgs: [localDeviceId],
    );
  }

  Future<TrustedPeer?> trustedPeer(String deviceId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT d.device_id, d.display_name, d.trust_status, p.base_url,
             p.shared_secret, p.last_pulled_hlc, p.last_pushed_hlc,
             p.last_applied_cashier_projection_version
      FROM devices d
      JOIN sync_peers p ON p.peer_device_id = d.device_id
      WHERE d.device_id = ? AND d.trust_status = 'trusted'
      LIMIT 1
      ''',
      [deviceId],
    );
    if (rows.isEmpty) return null;
    return _trustedPeerFromRow(rows.single);
  }

  Future<void> updateTrustedPeerBaseUrl({
    required String deviceId,
    required String baseUrl,
  }) async {
    if (deviceId == localDeviceId) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Cannot update self.');
    }
    final now = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      final trusted = Sqflite.firstIntValue(
        await txn.rawQuery(
          '''
          SELECT COUNT(*)
          FROM devices
          WHERE device_id = ? AND trust_status = 'trusted'
          ''',
          [deviceId],
        ),
      );
      if ((trusted ?? 0) <= 0) return;
      await txn.update(
        'sync_peers',
        {'base_url': baseUrl, 'updated_at': now},
        where: 'peer_device_id = ?',
        whereArgs: [deviceId],
      );
    });
    activityBus?.notifySyncStateChanged();
  }

  Future<TrustedPeer?> revokedPeer(String deviceId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT d.device_id, d.display_name, d.trust_status, p.base_url,
             p.shared_secret, p.last_pulled_hlc, p.last_pushed_hlc,
             p.last_applied_cashier_projection_version
      FROM devices d
      JOIN sync_peers p ON p.peer_device_id = d.device_id
      WHERE d.device_id = ? AND d.trust_status = 'revoked'
      LIMIT 1
      ''',
      [deviceId],
    );
    if (rows.isEmpty) return null;
    return _trustedPeerFromRow(rows.single);
  }

  Future<List<TrustedPeer>> trustedPeers() async {
    final rows = await _db.rawQuery('''
      SELECT d.device_id, d.display_name, d.trust_status, p.base_url,
             p.shared_secret, p.last_pulled_hlc, p.last_pushed_hlc,
             p.last_applied_cashier_projection_version
      FROM devices d
      JOIN sync_peers p ON p.peer_device_id = d.device_id
      WHERE d.trust_status = 'trusted'
      ORDER BY d.updated_at DESC, d.device_id ASC
      ''');
    final peers = <TrustedPeer>[];
    for (final row in rows) {
      final peer = _trustedPeerFromRow(row);
      if (peer != null) peers.add(peer);
    }
    return peers;
  }

  Future<void> revokePeer(String deviceId) async {
    if (deviceId == localDeviceId) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Cannot revoke self.');
    }
    final now = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.update(
        'devices',
        {'trust_status': 'revoked', 'updated_at': now, 'last_seen_at': null},
        where: 'device_id = ? AND trust_status = ?',
        whereArgs: [deviceId, 'trusted'],
      );
      await txn.update(
        'sync_peers',
        {'last_error': 'peer_unpaired', 'updated_at': now},
        where: 'peer_device_id = ?',
        whereArgs: [deviceId],
      );
    });
    activityBus?.notifySyncStateChanged();
  }

  TrustedPeer? _trustedPeerFromRow(Map<String, Object?> row) {
    final secret = row['shared_secret'] as String?;
    if (secret == null || secret.isEmpty) return null;
    return TrustedPeer(
      deviceId: row['device_id'] as String,
      displayName: row['display_name'] as String? ?? 'Peer',
      sharedSecret: secret,
      baseUrl: row['base_url'] as String?,
      lastPulledCursor: SyncCursor.parse(row['last_pulled_hlc'] as String?),
      lastPushedCursor: SyncCursor.parse(row['last_pushed_hlc'] as String?),
      lastAppliedCashierProjectionVersion:
          row['last_applied_cashier_projection_version'] as int?,
    );
  }

  Future<void> markPeerSuccess(
    String deviceId, {
    int? lastAppliedCashierProjectionVersion,
  }) async {
    final now = _now().toUtc().toIso8601String();
    if (lastAppliedCashierProjectionVersion != null &&
        lastAppliedCashierProjectionVersion < 0) {
      throw ArgumentError.value(
        lastAppliedCashierProjectionVersion,
        'lastAppliedCashierProjectionVersion',
      );
    }
    final peerUpdate = <String, Object?>{
      'last_successful_sync_at': now,
      'last_error': null,
      'updated_at': now,
      'last_applied_cashier_projection_version':
          ?lastAppliedCashierProjectionVersion,
    };
    await _db.update(
      'devices',
      {'last_seen_at': now, 'updated_at': now},
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    await _db.update(
      'sync_peers',
      peerUpdate,
      where: 'peer_device_id = ?',
      whereArgs: [deviceId],
    );
    activityBus?.notifySyncStateChanged();
  }

  Future<void> markPeerFailure(String deviceId, String errorCode) async {
    final now = _now().toUtc().toIso8601String();
    await _db.update(
      'sync_peers',
      {'last_error': errorCode, 'updated_at': now},
      where: 'peer_device_id = ?',
      whereArgs: [deviceId],
    );
    activityBus?.notifySyncStateChanged();
  }

  Future<String?> firstTrustedPeerLastError() async {
    final rows = await _db.rawQuery('''
      SELECT p.last_error
      FROM sync_peers p
      JOIN devices d ON d.device_id = p.peer_device_id
      WHERE d.trust_status = 'trusted' AND p.last_error IS NOT NULL
      ORDER BY p.updated_at DESC, p.peer_device_id ASC
      LIMIT 1
      ''');
    if (rows.isEmpty) return null;
    return rows.single['last_error'] as String?;
  }

  Future<void> updatePullCursor(String deviceId, SyncCursor? cursor) {
    return _updateCursor(deviceId, 'last_pulled_hlc', cursor);
  }

  Future<void> updatePushCursor(String deviceId, SyncCursor? cursor) {
    return _updateCursor(deviceId, 'last_pushed_hlc', cursor);
  }

  Future<int> cashierInventoryProjectionVersion() {
    return readIntSetting(_db, cashierInventoryProjectionVersionSetting);
  }

  Future<int> lastAppliedCashierProjectionVersion() {
    return readIntSetting(_db, lastAppliedCashierProjectionVersionSetting);
  }

  Future<void> setLastAppliedCashierProjectionVersion(int version) async {
    if (version < 0) {
      throw ArgumentError.value(version, 'version');
    }
    await writeIntSetting(
      _db,
      lastAppliedCashierProjectionVersionSetting,
      version,
      now: _now().toUtc(),
    );
    activityBus?.notifySyncStateChanged();
  }

  Future<void> enqueueCashierSaleCommand({
    required CashierSaleCommand command,
    required List<CashierSaleOutboxLine> lines,
  }) async {
    if (lines.isEmpty || lines.length != command.lines.length) {
      throw ArgumentError.value(lines, 'lines');
    }
    final now = _now().toUtc();
    final nowText = now.toIso8601String();
    await _db.transaction((txn) async {
      final activeCount = Sqflite.firstIntValue(
        await txn.rawQuery(
          '''
          SELECT COUNT(*)
          FROM cashier_sale_command_outbox
          WHERE status IN (?, ?, ?)
          ''',
          const ['queued', 'syncing', 'conflict'],
        ),
      );
      if ((activeCount ?? 0) >= cashierSaleOutboxMaxActiveCommands) {
        throw StateError('Cashier sale outbox is full.');
      }
      final projectionVersion = await readIntSetting(
        txn,
        lastAppliedCashierProjectionVersionSetting,
      );
      await txn.insert('cashier_sale_command_outbox', {
        'command_id': command.commandId,
        'status': CashierSaleCommandOutboxStatus.queued.storageValue,
        'command_json': jsonEncode(command.toJson()),
        'local_total_minor': lines.fold<int>(
          0,
          (sum, line) => sum + line.lineTotalMinor,
        ),
        'snapshot_projection_version': projectionVersion,
        'error_code': null,
        'error_product_ids_json': null,
        'accepted_event_id': null,
        'resolution_note': null,
        'created_at': nowText,
        'updated_at': nowText,
        'last_attempted_at': null,
      });
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        await txn.insert('cashier_sale_command_outbox_lines', {
          'command_id': command.commandId,
          'line_index': index,
          'product_id': line.productId,
          'product_name': line.productName,
          'quantity': line.quantity,
          'unit_price_minor': line.unitPriceMinor,
          'line_total_minor': line.lineTotalMinor,
        });
      }
    });
    activityBus?.notifySyncStateChanged();
  }

  Future<CashierSaleOutboxCommand?> nextCashierSaleCommandForSync() async {
    if (await hasCashierSaleOutboxConflict()) return null;
    final rows = await _db.query(
      'cashier_sale_command_outbox',
      where: 'status IN (?, ?)',
      whereArgs: const ['queued', 'syncing'],
      orderBy: 'created_at ASC, command_id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _cashierSaleOutboxCommandFromRow(rows.single);
  }

  Future<bool> hasCashierSaleOutboxConflict() async {
    final count = Sqflite.firstIntValue(
      await _db.rawQuery(
        '''
        SELECT COUNT(*)
        FROM cashier_sale_command_outbox
        WHERE status = ?
        ''',
        const ['conflict'],
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<CashierSaleCommandOutboxStatus?> cashierSaleCommandStatus(
    String commandId,
  ) async {
    final rows = await _db.query(
      'cashier_sale_command_outbox',
      columns: ['status'],
      where: 'command_id = ?',
      whereArgs: [commandId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CashierSaleCommandOutboxStatus.fromStorage(
      rows.single['status'] as String,
    );
  }

  Future<Map<CashierSaleCommandOutboxStatus, int>>
  cashierSaleOutboxCounts() async {
    final rows = await _db.rawQuery('''
      SELECT status, COUNT(*) AS count
      FROM cashier_sale_command_outbox
      GROUP BY status
      ''');
    return {
      for (final row in rows)
        CashierSaleCommandOutboxStatus.fromStorage(row['status'] as String):
            row['count'] as int,
    };
  }

  Future<void> markCashierSaleCommandSyncing(String commandId) async {
    final nowText = _now().toUtc().toIso8601String();
    await _db.update(
      'cashier_sale_command_outbox',
      {
        'status': CashierSaleCommandOutboxStatus.syncing.storageValue,
        'error_code': null,
        'error_product_ids_json': null,
        'updated_at': nowText,
        'last_attempted_at': nowText,
      },
      where: 'command_id = ? AND status IN (?, ?)',
      whereArgs: [
        commandId,
        CashierSaleCommandOutboxStatus.queued.storageValue,
        CashierSaleCommandOutboxStatus.syncing.storageValue,
      ],
    );
    activityBus?.notifySyncStateChanged();
  }

  Future<void> markCashierSaleCommandQueued(String commandId) async {
    final nowText = _now().toUtc().toIso8601String();
    await _db.update(
      'cashier_sale_command_outbox',
      {
        'status': CashierSaleCommandOutboxStatus.queued.storageValue,
        'updated_at': nowText,
      },
      where: 'command_id = ? AND status = ?',
      whereArgs: [
        commandId,
        CashierSaleCommandOutboxStatus.syncing.storageValue,
      ],
    );
    activityBus?.notifySyncStateChanged();
  }

  Future<void> markCashierSaleCommandAccepted({
    required String commandId,
    required String acceptedEventId,
  }) async {
    final nowText = _now().toUtc().toIso8601String();
    await _db.update(
      'cashier_sale_command_outbox',
      {
        'status': CashierSaleCommandOutboxStatus.accepted.storageValue,
        'accepted_event_id': acceptedEventId,
        'error_code': null,
        'error_product_ids_json': null,
        'updated_at': nowText,
      },
      where: 'command_id = ?',
      whereArgs: [commandId],
    );
    activityBus?.notifySyncStateChanged();
  }

  Future<void> markCashierSaleCommandConflict({
    required String commandId,
    required String errorCode,
    required List<String> productIds,
  }) async {
    final nowText = _now().toUtc().toIso8601String();
    await _db.update(
      'cashier_sale_command_outbox',
      {
        'status': CashierSaleCommandOutboxStatus.conflict.storageValue,
        'error_code': errorCode,
        'error_product_ids_json': jsonEncode(productIds),
        'updated_at': nowText,
      },
      where: 'command_id = ?',
      whereArgs: [commandId],
    );
    activityBus?.notifySyncStateChanged();
  }

  Future<void> voidOldestConflictedCashierSaleCommand({
    String resolutionNote = 'voided_by_cashier',
  }) async {
    final rows = await _db.query(
      'cashier_sale_command_outbox',
      columns: ['command_id'],
      where: 'status = ?',
      whereArgs: [CashierSaleCommandOutboxStatus.conflict.storageValue],
      orderBy: 'created_at ASC, command_id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return;
    final nowText = _now().toUtc().toIso8601String();
    await _db.update(
      'cashier_sale_command_outbox',
      {
        'status': CashierSaleCommandOutboxStatus.voided.storageValue,
        'resolution_note': resolutionNote,
        'updated_at': nowText,
      },
      where: 'command_id = ? AND status = ?',
      whereArgs: [
        rows.single['command_id'] as String,
        CashierSaleCommandOutboxStatus.conflict.storageValue,
      ],
    );
    activityBus?.notifySyncStateChanged();
  }

  CashierSaleOutboxCommand _cashierSaleOutboxCommandFromRow(
    Map<String, Object?> row,
  ) {
    return CashierSaleOutboxCommand(
      command: CashierSaleCommand.fromJson(
        jsonDecode(row['command_json'] as String),
      ),
      status: CashierSaleCommandOutboxStatus.fromStorage(
        row['status'] as String,
      ),
      createdAt: DateTime.parse(row['created_at'] as String),
      localTotalMinor: row['local_total_minor'] as int,
      errorCode: row['error_code'] as String?,
      errorProductIds: _decodeStringList(
        row['error_product_ids_json'] as String?,
      ),
    );
  }

  List<String> _decodeStringList(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is String) item,
    ];
  }

  Future<CashierInventorySnapshot> cashierInventorySnapshot() {
    return _db.transaction((txn) async {
      final version = await readIntSetting(
        txn,
        cashierInventoryProjectionVersionSetting,
      );
      final rows = await txn.rawQuery('''
        SELECT p.product_id, p.barcode, p.name, p.sale_price_minor, p.active,
               COALESCE(i.quantity, 0) AS quantity
        FROM products_projection p
        LEFT JOIN inventory_projection i ON i.product_id = p.product_id
        ORDER BY p.active DESC, p.name ASC, p.product_id ASC
        ''');
      return CashierInventorySnapshot(
        projectionVersion: version,
        products: [
          for (final row in rows)
            CashierProductProjection(
              productId: row['product_id'] as String,
              barcode: row['barcode'] as String?,
              name: row['name'] as String,
              stockQuantity: (row['quantity'] as num).toDouble(),
              salePriceMinor: row['sale_price_minor'] as int,
              active: row['active'] == 1,
            ),
        ],
      );
    });
  }

  Future<void> applyCashierInventorySnapshot(
    CashierInventorySnapshot snapshot,
  ) async {
    final now = _now().toUtc();
    final nowText = now.toIso8601String();
    final marker = _cashierSnapshotMarker(snapshot.projectionVersion);
    await _db.transaction((txn) async {
      await txn.delete('product_field_versions');
      await txn.delete('inventory_projection');
      await txn.delete('products_projection');
      for (final product in snapshot.products) {
        await _replaceCashierProductInTransaction(
          txn,
          product,
          nowText: nowText,
          marker: marker,
        );
      }
      await writeIntSetting(
        txn,
        lastAppliedCashierProjectionVersionSetting,
        snapshot.projectionVersion,
        now: now,
      );
    });
    activityBus?.notifyEventsChanged();
    activityBus?.notifySyncStateChanged();
  }

  Future<CashierProjectionApplyStatus> applyCashierProjectionUpdate(
    CashierProjectionUpdate update,
  ) async {
    final now = _now().toUtc();
    final nowText = now.toIso8601String();
    final marker = _cashierProjectionMarker(update.projectionVersion);
    var applied = false;
    final status = await _db.transaction((txn) async {
      final lastApplied = await readIntSetting(
        txn,
        lastAppliedCashierProjectionVersionSetting,
      );
      if (update.type == cashierProjectionSnapshotRequired) {
        return CashierProjectionApplyStatus.snapshotRequired;
      }
      if (update.projectionVersion <= lastApplied) {
        return CashierProjectionApplyStatus.duplicate;
      }
      if (update.projectionVersion != lastApplied + 1) {
        return CashierProjectionApplyStatus.gap;
      }
      switch (update.type) {
        case cashierProjectionProductUpsert:
          final product = update.product;
          if (product == null) {
            throw const FormatException(
              'product_upsert update is missing product.',
            );
          }
          await _replaceCashierProductInTransaction(
            txn,
            product,
            nowText: nowText,
            marker: marker,
          );
        case cashierProjectionInventoryPatch:
          if (!await _cashierPatchProductsExist(txn, update.products)) {
            return CashierProjectionApplyStatus.snapshotRequired;
          }
          for (final product in update.products) {
            await _replaceCashierInventoryInTransaction(
              txn,
              product.productId,
              stockQuantity: product.stockQuantity,
              nowText: nowText,
              marker: marker,
            );
          }
        default:
          throw FormatException(
            'Unsupported Cashier projection type: ${update.type}.',
          );
      }
      await writeIntSetting(
        txn,
        lastAppliedCashierProjectionVersionSetting,
        update.projectionVersion,
        now: now,
      );
      applied = true;
      return CashierProjectionApplyStatus.applied;
    });
    if (applied) {
      activityBus?.notifyEventsChanged();
      activityBus?.notifySyncStateChanged();
    } else if (status == CashierProjectionApplyStatus.gap ||
        status == CashierProjectionApplyStatus.snapshotRequired) {
      activityBus?.notifySyncStateChanged();
    }
    return status;
  }

  Future<void> _replaceCashierProductInTransaction(
    DatabaseExecutor db,
    CashierProductProjection product, {
    required String nowText,
    required String marker,
  }) async {
    await db.delete(
      'product_field_versions',
      where: 'product_id = ?',
      whereArgs: [product.productId],
    );
    await db.insert('products_projection', {
      'product_id': product.productId,
      'name': product.name,
      'barcode': product.barcode,
      'sku': null,
      'unit': 'each',
      'sale_price_minor': product.salePriceMinor,
      'purchase_cost_minor': 0,
      'active': product.active ? 1 : 0,
      'created_at': nowText,
      'updated_at': nowText,
      'updated_hlc': marker,
      'updated_device_id': localDeviceId,
      'updated_event_id': marker,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _replaceCashierInventoryInTransaction(
      db,
      product.productId,
      stockQuantity: product.stockQuantity,
      nowText: nowText,
      marker: marker,
    );
  }

  Future<void> _replaceCashierInventoryInTransaction(
    DatabaseExecutor db,
    String productId, {
    required double stockQuantity,
    required String nowText,
    required String marker,
  }) async {
    await db.insert('inventory_projection', {
      'product_id': productId,
      'quantity': stockQuantity,
      'updated_at': nowText,
      'updated_hlc': marker,
      'updated_device_id': localDeviceId,
      'updated_event_id': marker,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> _cashierPatchProductsExist(
    DatabaseExecutor db,
    List<CashierInventoryPatchProduct> products,
  ) async {
    for (final product in products) {
      final rows = await db.query(
        'products_projection',
        columns: ['product_id'],
        where: 'product_id = ?',
        whereArgs: [product.productId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
    }
    return true;
  }

  String _cashierSnapshotMarker(int version) => 'cashier_snapshot:$version';

  String _cashierProjectionMarker(int version) => 'cashier_projection:$version';

  static Future<int> incrementCashierProjectionVersionInTransaction(
    Transaction txn, {
    required DateTime now,
  }) async {
    final current = await readIntSetting(
      txn,
      cashierInventoryProjectionVersionSetting,
    );
    final next = current + 1;
    await writeIntSetting(
      txn,
      cashierInventoryProjectionVersionSetting,
      next,
      now: now,
    );
    return next;
  }

  static Future<int> readIntSetting(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.single['value'] as String? ?? '') ?? 0;
  }

  static Future<void> writeIntSetting(
    DatabaseExecutor db,
    String key,
    int value, {
    required DateTime now,
  }) async {
    if (value < 0) {
      throw ArgumentError.value(value, 'value');
    }
    await db.insert('app_settings', {
      'key': key,
      'value': value.toString(),
      'updated_at': now.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<EventEnvelope>> fetchEventsAfter(
    SyncCursor? cursor, {
    required int limit,
  }) {
    return _eventStore.fetchEventsAfter(
      hlc: cursor?.hlc,
      eventId: cursor?.eventId.isEmpty == true ? null : cursor?.eventId,
      limit: limit,
    );
  }

  Future<List<EventEnvelope>> fetchLocalEventsAfter(
    SyncCursor? cursor, {
    required int limit,
  }) {
    return _eventStore.fetchEventsAfter(
      hlc: cursor?.hlc,
      eventId: cursor?.eventId.isEmpty == true ? null : cursor?.eventId,
      deviceId: localDeviceId,
      limit: limit,
    );
  }

  Future<void> waitForEventsAfter(
    SyncCursor? cursor, {
    required Duration timeout,
  }) async {
    final eventsChanged = activityBus?.eventsChanged;
    if (eventsChanged == null || timeout <= Duration.zero) return;
    final deadline = DateTime.now().add(timeout);

    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return;
      final changed = Completer<void>();
      final subscription = eventsChanged.listen((_) {
        if (!changed.isCompleted) changed.complete();
      });
      try {
        final events = await fetchEventsAfter(cursor, limit: 1);
        if (events.isNotEmpty) return;
        await changed.future.timeout(remaining);
      } on TimeoutException {
        return;
      } finally {
        await subscription.cancel();
      }
    }
  }

  Future<PostEventsResult> importEvents(List<EventEnvelope> events) async {
    final accepted = <String>[];
    final duplicate = <String>[];
    final unsupported = <String>[];
    final rejected = <EventRejection>[];

    final orderedEvents = events.toList(growable: false)
      ..sort(_compareEventCreation);
    for (final event in orderedEvents) {
      try {
        final status = await _db.transaction((txn) async {
          final write = await _eventStore.appendInTransaction(txn, event);
          if (_isProjectable(event)) {
            await _projector.applyInTransaction(txn, event);
          }
          return write.status;
        });
        switch (status) {
          case EventWriteStatus.accepted:
            accepted.add(event.eventId);
          case EventWriteStatus.duplicate:
            duplicate.add(event.eventId);
          case EventWriteStatus.unsupported:
            unsupported.add(event.eventId);
        }
      } on Object catch (error) {
        rejected.add(
          EventRejection(eventId: event.eventId, reason: _safeReason(error)),
        );
      }
    }

    if (accepted.isNotEmpty || unsupported.isNotEmpty) {
      activityBus?.notifyEventsChanged();
    }

    return PostEventsResult(
      accepted: accepted,
      duplicate: duplicate,
      unsupported: unsupported,
      rejected: rejected,
    );
  }

  Future<CashierSaleCommandResult> recordCashierSaleCommand({
    required String cashierDeviceId,
    required CashierSaleCommand command,
  }) async {
    CashierSaleCommandResult? commandResult;
    int? projectionVersion;
    var accepted = false;
    var affectedProductIds = <String>{};
    final now = _now().toUtc();
    await _db.transaction((txn) async {
      final existing = await txn.query(
        'events',
        where: 'event_id = ?',
        whereArgs: [command.commandId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final event = EventEnvelope.fromStorage(existing.single);
        if (event.type != EventTypes.inventorySaleRecorded ||
            event.deviceId != cashierDeviceId ||
            event.entityId != command.commandId) {
          throw const CashierSaleCommandException(
            CashierSaleCommandException.commandConflict,
          );
        }
        commandResult = CashierSaleCommandResult(
          commandId: command.commandId,
          saleId: event.entityId,
          duplicate: true,
          event: event,
        );
        return;
      }

      final saleLines = await _cashierSaleLinesForCommand(txn, command);
      affectedProductIds = {for (final line in saleLines) line.productId};
      final event = EventEnvelope.local(
        eventId: command.commandId,
        deviceId: cashierDeviceId,
        hlc: HybridLogicalTimestamp(
          physicalTimeMillis: now.millisecondsSinceEpoch,
          logicalCounter: 0,
          nodeId: cashierDeviceId,
        ),
        type: EventTypes.inventorySaleRecorded,
        entityId: command.commandId,
        payload: {
          'occurred_at': command.occurredAt.toUtc().toIso8601String(),
          'total_minor': saleLines.fold<int>(
            0,
            (sum, line) => sum + line.lineTotalMinor,
          ),
          'line_items': [for (final line in saleLines) line.toPayload()],
        },
        createdAt: now,
      );
      final write = await _eventStore.appendInTransaction(txn, event);
      if (write.status != EventWriteStatus.accepted) {
        throw const CashierSaleCommandException(
          CashierSaleCommandException.commandConflict,
        );
      }
      await _projector.applyInTransaction(txn, event);
      projectionVersion =
          await SyncStore.incrementCashierProjectionVersionInTransaction(
            txn,
            now: now,
          );
      accepted = true;
      commandResult = CashierSaleCommandResult(
        commandId: command.commandId,
        saleId: event.entityId,
        duplicate: false,
        projectionVersion: projectionVersion,
        event: event,
      );
    });

    if (accepted) {
      activityBus?.notifyEventsChanged();
      final version = projectionVersion;
      if (version != null) {
        activityBus?.notifyCashierProjectionUpdate(
          await _cashierInventoryPatchMessage(version, affectedProductIds),
        );
      }
    }
    return commandResult!;
  }

  Future<List<_CashierSaleEventLine>> _cashierSaleLinesForCommand(
    Transaction txn,
    CashierSaleCommand command,
  ) async {
    if (command.lines.isEmpty) {
      throw const CashierSaleCommandException(
        CashierSaleCommandException.invalidCommand,
      );
    }
    final quantitiesByProductId = <String, double>{};
    for (final line in command.lines) {
      final productId = line.productId.trim();
      if (productId.isEmpty || !line.quantity.isFinite || line.quantity <= 0) {
        throw const CashierSaleCommandException(
          CashierSaleCommandException.invalidCommand,
        );
      }
      quantitiesByProductId[productId] =
          (quantitiesByProductId[productId] ?? 0) + line.quantity;
    }

    final requests = <InventorySaleCostRequest>[];
    final unavailable = <String>[];
    final insufficient = <String>[];
    for (final productId in quantitiesByProductId.keys.toList()..sort()) {
      final quantity = quantitiesByProductId[productId]!;
      final rows = await txn.rawQuery(
        '''
        SELECT p.product_id, p.sale_price_minor, p.active,
               COALESCE(i.quantity, 0) AS quantity
        FROM products_projection p
        LEFT JOIN inventory_projection i ON i.product_id = p.product_id
        WHERE p.product_id = ?
        LIMIT 1
        ''',
        [productId],
      );
      if (rows.isEmpty || rows.single['active'] != 1) {
        unavailable.add(productId);
        continue;
      }
      final stockQuantity = (rows.single['quantity'] as num).toDouble();
      if (stockQuantity < quantity) {
        insufficient.add(productId);
        continue;
      }
      requests.add(
        InventorySaleCostRequest(
          productId: productId,
          quantity: quantity,
          unitPriceMinor: rows.single['sale_price_minor'] as int,
        ),
      );
    }
    if (unavailable.isNotEmpty) {
      throw CashierSaleCommandException(
        CashierSaleCommandException.productUnavailable,
        productIds: unavailable,
      );
    }
    if (insufficient.isNotEmpty) {
      throw CashierSaleCommandException(
        CashierSaleCommandException.insufficientStock,
        productIds: insufficient,
      );
    }
    final costedLines = await allocateFifoInventoryLots(txn, requests);
    return [
      for (final line in costedLines)
        _CashierSaleEventLine(
          productId: line.productId,
          quantity: line.quantity,
          unitPriceMinor: line.unitPriceMinor,
          costTotalMinor: line.costTotalMinor,
          allocations: line.allocations,
        ),
    ];
  }

  Future<Map<String, Object?>> _cashierInventoryPatchMessage(
    int projectionVersion,
    Set<String> productIds,
  ) async {
    final products = <CashierInventoryPatchProduct>[];
    for (final productId in productIds.toList()..sort()) {
      products.add(
        CashierInventoryPatchProduct(
          productId: productId,
          stockQuantity: await _stockFor(productId),
        ),
      );
    }
    return serializeCashierInventoryPatchMessage(
      projectionVersion: projectionVersion,
      products: products,
    );
  }

  Future<double> _stockFor(String productId) async {
    final rows = await _db.query(
      'inventory_projection',
      columns: ['quantity'],
      where: 'product_id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.single['quantity'] as num).toDouble();
  }

  int _compareEventCreation(EventEnvelope a, EventEnvelope b) {
    final created = a.createdAt.compareTo(b.createdAt);
    if (created != 0) return created;
    final hlc = a.hlc.compareTo(b.hlc);
    if (hlc != 0) return hlc;
    return a.eventId.compareTo(b.eventId);
  }

  Future<SyncState> state() async {
    final unsupportedRows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM unsupported_events',
    );
    final peerRows = await _db.rawQuery('''
      SELECT COUNT(*) AS count
      FROM devices
      WHERE trust_status = 'trusted'
      ''');
    final lastSyncRows = await _db.rawQuery(
      'SELECT MAX(last_successful_sync_at) AS value FROM sync_peers',
    );
    final lastSync = lastSyncRows.single['value'] as String?;
    return SyncState(
      deviceId: localDeviceId,
      eventCount: await _eventStore.count(),
      unsupportedEventCount: unsupportedRows.single['count'] as int,
      trustedPeerCount: peerRows.single['count'] as int,
      lastSuccessfulSyncAt: lastSync == null ? null : DateTime.parse(lastSync),
    );
  }

  void notifyTransfer(SyncTransferDirection direction, int eventCount) {
    activityBus?.notifyTransfer(
      SyncTransferActivity(direction: direction, eventCount: eventCount),
    );
  }

  void recordPeerMessage(SyncPeerMessage message) {
    activityBus?.recordPeerMessage(message);
  }

  Future<void> _updateCursor(
    String deviceId,
    String column,
    SyncCursor? cursor,
  ) async {
    final now = _now().toUtc().toIso8601String();
    await _db.update(
      'sync_peers',
      {column: cursor?.encode(), 'updated_at': now},
      where: 'peer_device_id = ?',
      whereArgs: [deviceId],
    );
    activityBus?.notifySyncStateChanged();
  }

  Future<void> _trustPeerInTransaction(
    Transaction txn, {
    required String deviceId,
    required String displayName,
    required String sharedSecret,
    required String now,
    String? baseUrl,
    String? lastSeenAt,
  }) async {
    await txn.insert('devices', {
      'device_id': deviceId,
      'display_name': _displayName(displayName),
      'trust_status': 'trusted',
      'shared_secret_hash': SyncSecrets.hash(sharedSecret),
      'created_at': now,
      'updated_at': now,
      'last_seen_at': ?lastSeenAt,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await txn.update(
      'devices',
      {
        'display_name': _displayName(displayName),
        'trust_status': 'trusted',
        'shared_secret_hash': SyncSecrets.hash(sharedSecret),
        'updated_at': now,
        'last_seen_at': ?lastSeenAt,
      },
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    await txn.insert('sync_peers', {
      'peer_device_id': deviceId,
      'base_url': baseUrl,
      'shared_secret': sharedSecret,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await txn.update(
      'sync_peers',
      {
        'base_url': baseUrl,
        'shared_secret': sharedSecret,
        'last_error': null,
        'updated_at': now,
      },
      where: 'peer_device_id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<String> _cashierDisplayNameForPairing(
    Transaction txn,
    String deviceId,
  ) async {
    final existing = await txn.query(
      'devices',
      columns: ['display_name'],
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final displayName = existing.single['display_name'] as String?;
      if (_cashierNumber(displayName) != null) return displayName!.trim();
    }

    final rows = await txn.query(
      'devices',
      columns: ['display_name'],
      where: 'trust_status = ?',
      whereArgs: const ['trusted'],
    );
    final used = <int>{};
    for (final row in rows) {
      final number = _cashierNumber(row['display_name'] as String?);
      if (number != null) used.add(number);
    }
    var next = 1;
    while (used.contains(next)) {
      next++;
    }
    return 'Cashier-$next';
  }

  int? _cashierNumber(String? displayName) {
    final match = RegExp(
      r'^Cashier-([1-9][0-9]*)$',
    ).firstMatch(displayName?.trim() ?? '');
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  bool _isProjectable(EventEnvelope event) {
    return EventSchema.isSupported(event.schemaVersion) &&
        EventTypes.supported.contains(event.type);
  }

  String _safeReason(Object error) {
    if (error is EventValidationException) return error.errors.join('; ');
    if (error is ConflictingDuplicateEventException) {
      return 'conflicting duplicate event';
    }
    return 'event could not be applied';
  }

  String _displayName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Peer' : trimmed;
  }
}

class _CashierSaleEventLine {
  const _CashierSaleEventLine({
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

  int get lineTotalMinor => (quantity * unitPriceMinor).round();

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
