import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/events/events.dart';
import '../backup/backup.dart';
import '../persistence/persistence.dart';
import '../platform/app_database_path.dart';
import '../sync/sync.dart';
import 'models.dart';
import 'persian_calendar.dart';

class DekonRepository {
  DekonRepository._(
    this._db,
    this._eventStore,
    this._projector, {
    required String deviceId,
    DateTime Function()? now,
    Uuid? uuid,
  }) : _deviceId = deviceId,
       _clock = HybridLogicalClock(nodeId: deviceId),
       _now = now ?? DateTime.now,
       _uuid = uuid ?? const Uuid(),
       _syncActivityBus = SyncActivityBus();

  final Database _db;
  final EventStore _eventStore;
  final DomainProjector _projector;
  final String _deviceId;
  final HybridLogicalClock _clock;
  final DateTime Function() _now;
  final Uuid _uuid;
  final SyncActivityBus _syncActivityBus;
  final _replicatedMutations = _SerializedAsyncQueue();

  static const _cashierVisibleProductFields = {
    'name',
    'barcode',
    'sale_price_minor',
    'active',
  };
  static const _mainSyncServerEnabledKey = 'main_sync_server_enabled';
  static const _cashierUnpairBackupRequiredKey =
      'cashier_unpair_backup_required';

  static Future<DekonRepository> open({Database? database}) async {
    final db = database ?? await AppDatabasePath.openCoreDatabase();
    final deviceId = await DeviceIdentityRepository(db).getOrCreate();
    return DekonRepository._(
      db,
      EventStore(db),
      DomainProjector(db),
      deviceId: deviceId,
    );
  }

  Stream<void> get eventsChanged => _syncActivityBus.eventsChanged;
  Stream<void> get syncStateChanged => _syncActivityBus.syncStateChanged;
  Stream<SyncTransferActivity> get syncTransfers => _syncActivityBus.transfers;
  Stream<SyncPeerMessage> get syncPeerMessages => _syncActivityBus.peerMessages;
  Stream<Map<String, Object?>> get cashierProjectionUpdates =>
      _syncActivityBus.cashierProjectionUpdates;

  List<SyncPeerMessage> recentSyncPeerMessages() {
    return _syncActivityBus.peerMessageSnapshot();
  }

  void clearSyncPeerMessages() {
    _syncActivityBus.clearPeerMessages();
  }

  Future<void> close() async {
    await _syncActivityBus.close();
    await _db.close();
  }

  SyncStore createSyncStore() {
    return SyncStore(
      database: _db,
      localDeviceId: _deviceId,
      activityBus: _syncActivityBus,
    );
  }

  LanSyncServer createLanSyncServer() {
    return LanSyncServer(store: createSyncStore());
  }

  LanSyncClient createLanSyncClient() {
    return LanSyncClient(store: createSyncStore());
  }

  BackupService createBackupService() {
    return BackupService(database: _db);
  }

  Future<BackupImportResult> restoreBackup(String contents) async {
    final result = await createBackupService().importBackup(contents);
    _syncActivityBus.notifyEventsChanged();
    _syncActivityBus.notifySyncStateChanged();
    return result;
  }

  Future<DeviceRole> deviceRole() async {
    return (await deviceRoleSettings()).role;
  }

  Future<AppLanguage> appLanguage() async {
    final rows = await _db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: const ['language_code'],
      limit: 1,
    );
    return AppLanguage.fromStorage(
      rows.isEmpty ? null : rows.single['value'] as String?,
    );
  }

  Future<void> setAppLanguage(AppLanguage language) {
    return _setAppSetting('language_code', language.storageValue);
  }

  Future<MoneyUnit> appMoneyUnit() async {
    final rows = await _db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: const ['money_unit'],
      limit: 1,
    );
    return MoneyUnit.fromStorage(
      rows.isEmpty ? null : rows.single['value'] as String?,
    );
  }

  Future<void> setAppMoneyUnit(MoneyUnit unit) {
    return _setAppSetting('money_unit', unit.storageValue);
  }

  Future<DeviceRoleSettings> deviceRoleSettings() async {
    final rows = await _db.query(
      'app_settings',
      columns: ['key', 'value'],
      where: 'key IN (?, ?, ?, ?, ?)',
      whereArgs: const [
        'device_role',
        'device_role_locked',
        'device_onboarding_completed',
        _mainSyncServerEnabledKey,
        _cashierUnpairBackupRequiredKey,
      ],
    );
    final values = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    final deviceRows = await _db.query(
      'devices',
      columns: ['display_name'],
      where: 'device_id = ?',
      whereArgs: [_deviceId],
      limit: 1,
    );
    return DeviceRoleSettings(
      role: DeviceRole.fromStorage(values['device_role']),
      locked: values['device_role_locked'] == 'true',
      onboardingCompleted: values['device_onboarding_completed'] == 'true',
      mainSyncServerEnabled: values[_mainSyncServerEnabledKey] == 'true',
      cashierUnpairBackupRequired:
          values[_cashierUnpairBackupRequiredKey] == 'true',
      deviceDisplayName: deviceRows.isEmpty
          ? null
          : deviceRows.single['display_name'] as String?,
    );
  }

  Future<void> setDeviceRole(DeviceRole role) async {
    final settings = await deviceRoleSettings();
    if (settings.locked && settings.role != role) {
      throw StateError('Device role is locked after pairing.');
    }
    await _setAppSetting('device_role', role.storageValue);
  }

  Future<void> completeDeviceOnboarding(DeviceRole role) async {
    final settings = await deviceRoleSettings();
    if (settings.locked && settings.role != role) {
      throw StateError('Device role is locked after pairing.');
    }
    final now = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('app_settings', {
        'key': 'device_role',
        'value': role.storageValue,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': 'device_onboarding_completed',
        'value': 'true',
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> lockDeviceRole(DeviceRole role) async {
    final now = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('app_settings', {
        'key': 'device_role',
        'value': role.storageValue,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': 'device_role_locked',
        'value': 'true',
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': 'device_onboarding_completed',
        'value': 'true',
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> setMainSyncServerEnabled(bool enabled) {
    return _setAppSetting(_mainSyncServerEnabledKey, enabled.toString());
  }

  Future<void> markCashierUnpairBackupRequired() async {
    final now = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('app_settings', {
        'key': 'device_role',
        'value': DeviceRole.cashierDevice.storageValue,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': 'device_role_locked',
        'value': 'true',
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': 'device_onboarding_completed',
        'value': 'true',
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': _cashierUnpairBackupRequiredKey,
        'value': 'true',
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    _syncActivityBus.notifySyncStateChanged();
  }

  Future<void> resetCashierAfterUnpairBackup() async {
    final now = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.delete('unsupported_events');
      await txn.delete('projection_applied_events');
      await txn.delete('product_field_versions');
      await txn.delete('inventory_projection');
      await txn.delete('sales_projection');
      await txn.delete('purchase_projection');
      await txn.delete('products_projection');
      await txn.delete('events');
      await txn.delete('sync_peers');
      await txn.delete(
        'devices',
        where: 'device_id <> ?',
        whereArgs: [_deviceId],
      );
      await txn.update(
        'devices',
        {
          'display_name': 'This device',
          'trust_status': 'local',
          'shared_secret_hash': null,
          'updated_at': now,
          'last_seen_at': null,
        },
        where: 'device_id = ?',
        whereArgs: [_deviceId],
      );
      await txn.delete(
        'app_settings',
        where: 'key IN (?, ?, ?, ?, ?, ?)',
        whereArgs: const [
          'device_role_locked',
          'device_onboarding_completed',
          _mainSyncServerEnabledKey,
          _cashierUnpairBackupRequiredKey,
          SyncStore.cashierInventoryProjectionVersionSetting,
          SyncStore.lastAppliedCashierProjectionVersionSetting,
        ],
      );
      await txn.insert('app_settings', {
        'key': 'device_role',
        'value': DeviceRole.cashierDevice.storageValue,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    _syncActivityBus.notifyEventsChanged();
    _syncActivityBus.notifySyncStateChanged();
  }

  Future<ProductSummary> createProduct({
    required String name,
    String? barcode,
    String? sku,
    String unit = 'each',
    int salePriceMinor = 0,
    int purchaseCostMinor = 0,
  }) async {
    final productId = _uuid.v7();
    final event = _event(
      type: EventTypes.productCreated,
      entityId: productId,
      payload: {
        'name': name.trim(),
        'barcode': _blankToNull(barcode),
        'sku': _blankToNull(sku),
        'unit': unit.trim().isEmpty ? 'each' : unit.trim(),
        'sale_price_minor': salePriceMinor,
        'purchase_cost_minor': purchaseCostMinor,
        'active': true,
      },
    );
    await _commitEvents(
      [event],
      buildCashierProjectionUpdate: (version) {
        return _cashierProductUpsertMessage(version, productId);
      },
    );
    return (await productById(productId))!;
  }

  Future<void> updateProduct(ProductSummary product) async {
    final existing = await productById(product.productId);
    if (existing == null) {
      throw StateError('Product does not exist.');
    }
    final fields = _changedProductFields(existing, product);
    if (fields.isEmpty) return;
    final cashierVisible = fields.keys.any(
      _cashierVisibleProductFields.contains,
    );
    final events = [
      for (final entry in fields.entries)
        _event(
          type: EventTypes.productFieldSet,
          entityId: product.productId,
          payload: {'field': entry.key, 'value': entry.value},
        ),
    ];
    await _commitEvents(
      events,
      buildCashierProjectionUpdate: cashierVisible
          ? (version) =>
                _cashierProductUpsertMessage(version, product.productId)
          : null,
    );
  }

  Future<void> softDeleteProduct(String productId) async {
    await _commitEvents(
      [
        _event(
          type: EventTypes.productDeactivated,
          entityId: productId,
          payload: const {'reason': 'soft_delete'},
        ),
      ],
      buildCashierProjectionUpdate: (version) {
        return _cashierProductUpsertMessage(version, productId);
      },
    );
  }

  Map<String, Object?> _changedProductFields(
    ProductSummary existing,
    ProductSummary product,
  ) {
    final proposed = <String, Object?>{
      'name': product.name.trim(),
      'barcode': _blankToNull(product.barcode),
      'sku': _blankToNull(product.sku),
      'unit': product.unit.trim().isEmpty ? 'each' : product.unit.trim(),
      'sale_price_minor': product.salePriceMinor,
      'purchase_cost_minor': product.purchaseCostMinor,
      'active': product.active,
    };
    final current = <String, Object?>{
      'name': existing.name,
      'barcode': _blankToNull(existing.barcode),
      'sku': _blankToNull(existing.sku),
      'unit': existing.unit,
      'sale_price_minor': existing.salePriceMinor,
      'purchase_cost_minor': existing.purchaseCostMinor,
      'active': existing.active,
    };
    return {
      for (final entry in proposed.entries)
        if (current[entry.key] != entry.value) entry.key: entry.value,
    };
  }

  Future<Map<String, Object?>?> _cashierProductUpsertMessage(
    int projectionVersion,
    String productId,
  ) async {
    final product = await productById(productId);
    if (product == null) return null;
    return serializeCashierProductUpsertMessage(
      projectionVersion: projectionVersion,
      product: CashierProductProjection.fromProductSummary(product),
    );
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

  Future<void> _commitEvents(
    List<EventEnvelope> events, {
    Future<Map<String, Object?>?> Function(int projectionVersion)?
    buildCashierProjectionUpdate,
  }) {
    if (events.isEmpty) return Future.value();
    return _replicatedMutations.run(() async {
      int? projectionVersion;
      var committed = false;
      await _db.transaction((txn) async {
        for (final event in events) {
          final write = await _eventStore.appendInTransaction(txn, event);
          if (write.status == EventWriteStatus.duplicate) continue;
          committed = true;
          if (_isProjectable(event)) {
            await _projector.applyInTransaction(txn, event);
          }
        }
        if (committed && buildCashierProjectionUpdate != null) {
          projectionVersion =
              await SyncStore.incrementCashierProjectionVersionInTransaction(
                txn,
                now: _now().toUtc(),
              );
        }
      });
      if (!committed) return;
      _syncActivityBus.notifyEventsChanged();
      final version = projectionVersion;
      if (version == null || buildCashierProjectionUpdate == null) return;
      final update = await buildCashierProjectionUpdate(version);
      if (update != null) {
        _syncActivityBus.notifyCashierProjectionUpdate(update);
      }
    });
  }

  bool _isProjectable(EventEnvelope event) {
    return EventSchema.isSupported(event.schemaVersion) &&
        EventTypes.supported.contains(event.type);
  }

  Future<void> _commitWithStockPatch(
    EventEnvelope event,
    Iterable<TransactionLineDraft> lines,
  ) async {
    final productIds = {for (final line in lines) line.product.productId};
    await _commitEvents(
      [event],
      buildCashierProjectionUpdate: (version) {
        return _cashierInventoryPatchMessage(version, productIds);
      },
    );
  }

  Future<void> _commitSaleWithStockPatch(
    List<TransactionLineDraft> lines,
  ) async {
    final productIds = {for (final line in lines) line.product.productId};
    return _replicatedMutations.run(() async {
      int? projectionVersion;
      var committed = false;
      await _db.transaction((txn) async {
        final saleLines = await allocateFifoInventoryLots(txn, [
          for (final line in lines)
            InventorySaleCostRequest(
              productId: line.product.productId,
              quantity: line.quantity,
              unitPriceMinor: line.unitPriceMinor,
            ),
        ]);
        final event = _event(
          type: EventTypes.inventorySaleRecorded,
          entityId: _uuid.v7(),
          payload: {
            'occurred_at': _now().toUtc().toIso8601String(),
            'total_minor': saleLines.fold<int>(
              0,
              (sum, line) => sum + line.saleTotalMinor,
            ),
            'line_items': [for (final line in saleLines) line.toPayload()],
          },
        );
        final write = await _eventStore.appendInTransaction(txn, event);
        if (write.status == EventWriteStatus.duplicate) return;
        committed = true;
        await _projector.applyInTransaction(txn, event);
        projectionVersion =
            await SyncStore.incrementCashierProjectionVersionInTransaction(
              txn,
              now: _now().toUtc(),
            );
      });
      if (!committed) return;
      _syncActivityBus.notifyEventsChanged();
      final version = projectionVersion;
      if (version == null) return;
      _syncActivityBus.notifyCashierProjectionUpdate(
        await _cashierInventoryPatchMessage(version, productIds),
      );
    });
  }

  Future<ProductSummary?> productByBarcodeOrSku(String query) async {
    final value = query.trim();
    if (value.isEmpty) return null;
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, COALESCE(i.quantity, 0) AS quantity
      FROM products_projection p
      LEFT JOIN inventory_projection i ON i.product_id = p.product_id
      WHERE p.active = 1 AND (p.barcode = ? OR p.sku = ?)
      LIMIT 1
      ''',
      [value, value],
    );
    if (rows.isEmpty) return null;
    return _productFromRow(rows.single);
  }

  Future<List<ProductSummary>> productsMatchingName(String query) async {
    final value = query.trim().toLowerCase();
    if (value.isEmpty) return const [];
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, COALESCE(i.quantity, 0) AS quantity
      FROM products_projection p
      LEFT JOIN inventory_projection i ON i.product_id = p.product_id
      WHERE p.active = 1 AND LOWER(p.name) LIKE ? ESCAPE '\\'
      ORDER BY p.name ASC
      LIMIT 20
      ''',
      ['%${_escapeLike(value)}%'],
    );
    return rows.map(_productFromRow).toList(growable: false);
  }

  Future<ProductSummary?> productById(String productId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, COALESCE(i.quantity, 0) AS quantity
      FROM products_projection p
      LEFT JOIN inventory_projection i ON i.product_id = p.product_id
      WHERE p.product_id = ?
      LIMIT 1
      ''',
      [productId],
    );
    if (rows.isEmpty) return null;
    return _productFromRow(rows.single);
  }

  Future<List<ProductSummary>> products() async {
    final rows = await _db.rawQuery('''
      SELECT p.*, COALESCE(i.quantity, 0) AS quantity
      FROM products_projection p
      LEFT JOIN inventory_projection i ON i.product_id = p.product_id
      ORDER BY p.active DESC, p.name ASC
      ''');
    return rows.map(_productFromRow).toList(growable: false);
  }

  Future<Set<String>> negativeStockProductIds(
    List<TransactionLineDraft> lines,
  ) async {
    final stock = <String, double>{};
    for (final line in lines) {
      stock[line.product.productId] = await _stockFor(line.product.productId);
    }
    final negativeProductIds = <String>{};
    for (final line in lines) {
      final next = (stock[line.product.productId] ?? 0) - line.quantity;
      if (next < 0) negativeProductIds.add(line.product.productId);
      stock[line.product.productId] = next;
    }
    return negativeProductIds;
  }

  Future<bool> saleWouldMakeNegative(List<TransactionLineDraft> lines) async {
    return (await negativeStockProductIds(lines)).isNotEmpty;
  }

  Future<void> recordSale(List<TransactionLineDraft> lines) async {
    if (lines.isEmpty) throw StateError('Sale must have at least one item.');
    if (await _shouldSubmitCashierSaleCommand()) {
      await _submitCashierSaleCommand(lines);
      return;
    }
    await _commitSaleWithStockPatch(lines);
  }

  Future<bool> _shouldSubmitCashierSaleCommand() async {
    final settings = await deviceRoleSettings();
    if (settings.cashierUnpairBackupRequired) {
      throw StateError('Cashier must back up and reconnect before recording.');
    }
    return settings.role == DeviceRole.cashierDevice && settings.locked;
  }

  Future<void> _submitCashierSaleCommand(
    List<TransactionLineDraft> lines,
  ) async {
    final store = createSyncStore();
    final peers = await store.trustedPeers();
    TrustedPeer? mainPeer;
    for (final peer in peers) {
      if (peer.baseUrl != null) {
        mainPeer = peer;
        break;
      }
    }
    if (mainPeer == null) {
      throw SyncClientException('Main device is not paired.');
    }
    final command = CashierSaleCommand(
      commandId: _uuid.v7(),
      occurredAt: _now().toUtc(),
      lines: [
        for (final line in lines)
          CashierSaleCommandLine(
            productId: line.product.productId,
            quantity: line.quantity,
          ),
      ],
    );
    final client = LanSyncClient(store: store, now: _now);
    try {
      await client.submitCashierSaleCommand(mainPeer.deviceId, command);
    } finally {
      client.close();
    }
  }

  Future<void> recordPurchase(List<TransactionLineDraft> lines) async {
    if (lines.isEmpty) {
      throw StateError('Purchase must have at least one item.');
    }
    await _commitWithStockPatch(
      _event(
        type: EventTypes.inventoryPurchaseRecorded,
        entityId: _uuid.v7(),
        payload: {
          'occurred_at': _now().toUtc().toIso8601String(),
          'total_minor': lines.fold<int>(
            0,
            (sum, line) => sum + line.purchaseTotalMinor,
          ),
          'line_items': [
            for (final line in lines)
              {
                'product_id': line.product.productId,
                'quantity': line.quantity,
                'unit_cost_minor': line.unitCostMinor,
              },
          ],
        },
      ),
      lines,
    );
  }

  Future<ReportSummary> reportSummary({
    ReportDateRange? range,
    ReportScope scope = ReportScope.allDevices,
    String? deviceId,
  }) async {
    final reportRange = range ?? _localDayRange(_now());
    final stockRows = await _stockRows();
    return ReportSummary(
      range: reportRange,
      stockRows: stockRows,
      salesMinor: await _rangeTotal(
        TransactionHistoryKind.sale,
        reportRange,
        scope,
        deviceId,
      ),
      purchasesMinor: await _rangeTotal(
        TransactionHistoryKind.purchase,
        reportRange,
        scope,
        deviceId,
      ),
      grossMarginMinor: await _grossMarginEstimate(
        reportRange,
        scope,
        deviceId,
      ),
      lowStockRows: stockRows.where((row) => row.quantity <= 0).toList(),
      unsyncedEventCount: await _unsyncedEventCount(),
      lastSyncAt: await _lastSyncAt(),
    );
  }

  Future<List<CashierReportFilter>> cashierReportFilters() async {
    final rows = await _db.rawQuery('''
      SELECT device_id, display_name
      FROM devices
      WHERE trust_status = 'trusted'
      ORDER BY LOWER(COALESCE(NULLIF(display_name, ''), device_id)) ASC
      ''');
    return [
      for (final row in rows)
        CashierReportFilter(
          deviceId: row['device_id'] as String,
          label: _cashierLabel(
            row['device_id'] as String,
            row['display_name'] as String?,
          ),
        ),
    ];
  }

  Future<List<ReportTrendBucket>> reportTrend({
    ReportTrendPeriod period = ReportTrendPeriod.day,
    ReportCalendar calendar = ReportCalendar.gregorian,
    ReportScope scope = ReportScope.allDevices,
    String? deviceId,
    DateTime? anchorLocal,
  }) async {
    final ranges = _trendRanges(period, anchorLocal ?? _now(), calendar);
    final buckets = <ReportTrendBucket>[];
    for (final range in ranges) {
      buckets.add(
        ReportTrendBucket(
          range: range,
          salesMinor: await _rangeTotal(
            TransactionHistoryKind.sale,
            range,
            scope,
            deviceId,
          ),
          purchasesMinor: await _rangeTotal(
            TransactionHistoryKind.purchase,
            range,
            scope,
            deviceId,
          ),
        ),
      );
    }
    return buckets;
  }

  Future<bool> hasRecentlyConnectedCashier({
    Duration activeWindow = const Duration(seconds: 75),
  }) async {
    final cutoff = _now().toUtc().subtract(activeWindow).toIso8601String();
    final rows = await _db.rawQuery(
      '''
      SELECT 1
      FROM devices
      WHERE trust_status = 'trusted'
        AND last_seen_at IS NOT NULL
        AND last_seen_at >= ?
      LIMIT 1
      ''',
      [cutoff],
    );
    return rows.isNotEmpty;
  }

  Future<List<TransactionHistoryEntry>> transactionHistory(
    TransactionHistoryKind kind, {
    ReportDateRange? range,
    ReportScope scope = ReportScope.allDevices,
    String? deviceId,
    int? limit = 20,
  }) async {
    final source = _transactionSource(kind);
    final where = ['e.type = ?', '${source.alias}.${source.statusColumn} = 0'];
    final args = <Object?>[_transactionType(kind)];
    _addDeviceFilter(where, args, scope, deviceId);
    if (range != null) {
      where.add('${source.alias}.occurred_at >= ?');
      where.add('${source.alias}.occurred_at < ?');
      args
        ..add(range.startUtc.toIso8601String())
        ..add(range.endUtcExclusive.toIso8601String());
    }
    final sqlLimit = limit == null ? '' : 'LIMIT ${limit.clamp(1, 500)}';
    final rows = await _db.rawQuery('''
      SELECT e.entity_id, e.payload_json, e.created_at
      FROM events e
      JOIN ${source.table} ${source.alias}
        ON ${source.alias}.${source.idColumn} = e.entity_id
      WHERE ${where.join(' AND ')}
      ORDER BY ${source.alias}.occurred_at DESC, e.created_at DESC
      $sqlLimit
      ''', args);
    final entries = <TransactionHistoryEntry>[];
    for (final row in rows) {
      entries.add(await _historyFromRow(kind, row));
    }
    return entries;
  }

  EventEnvelope _event({
    required String type,
    required String entityId,
    required Map<String, Object?> payload,
  }) {
    return EventEnvelope.local(
      eventId: _uuid.v7(),
      deviceId: _deviceId,
      hlc: _clock.send(_now()),
      type: type,
      entityId: entityId,
      payload: payload,
      createdAt: _now().toUtc(),
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

  Future<List<StockReportRow>> _stockRows() async {
    final rows = await _db.rawQuery('''
      SELECT p.product_id, p.name, COALESCE(i.quantity, 0) AS quantity
      FROM products_projection p
      LEFT JOIN inventory_projection i ON i.product_id = p.product_id
      WHERE p.active = 1
      ORDER BY p.name ASC
      ''');
    return [
      for (final row in rows)
        StockReportRow(
          productId: row['product_id'] as String,
          name: row['name'] as String,
          quantity: (row['quantity'] as num).toDouble(),
        ),
    ];
  }

  ReportDateRange _localDayRange(DateTime value) {
    final start = DateTime(value.year, value.month, value.day);
    return ReportDateRange(
      startLocal: start,
      endLocalExclusive: start.add(const Duration(days: 1)),
    );
  }

  List<ReportDateRange> _trendRanges(
    ReportTrendPeriod period,
    DateTime anchorLocal,
    ReportCalendar calendar,
  ) {
    return switch (period) {
      ReportTrendPeriod.day => _dayTrendRanges(anchorLocal),
      ReportTrendPeriod.week => _weekTrendRanges(anchorLocal, calendar),
      ReportTrendPeriod.month => _monthTrendRanges(anchorLocal, calendar),
      ReportTrendPeriod.year => _yearTrendRanges(anchorLocal, calendar),
    };
  }

  List<ReportDateRange> _dayTrendRanges(DateTime anchorLocal) {
    final today = _dayStart(anchorLocal);
    final first = today.subtract(const Duration(days: 6));
    return List.generate(7, (index) {
      final start = first.add(Duration(days: index));
      return ReportDateRange(
        startLocal: start,
        endLocalExclusive: start.add(const Duration(days: 1)),
      );
    });
  }

  List<ReportDateRange> _weekTrendRanges(
    DateTime anchorLocal,
    ReportCalendar calendar,
  ) {
    final current = _weekStart(anchorLocal, calendar);
    final first = current.subtract(const Duration(days: 49));
    return List.generate(8, (index) {
      final start = first.add(Duration(days: 7 * index));
      return ReportDateRange(
        startLocal: start,
        endLocalExclusive: start.add(const Duration(days: 7)),
      );
    });
  }

  List<ReportDateRange> _monthTrendRanges(
    DateTime anchorLocal,
    ReportCalendar calendar,
  ) {
    if (calendar == ReportCalendar.persian) {
      final current = PersianCalendar.monthRangeContaining(anchorLocal);
      final first = PersianCalendar.addMonths(current.startLocal, -11);
      return List.generate(12, (index) {
        final start = PersianCalendar.addMonths(first, index);
        return PersianCalendar.monthRangeContaining(start);
      });
    }
    final first = DateTime(anchorLocal.year, anchorLocal.month - 11);
    return List.generate(12, (index) {
      final start = DateTime(first.year, first.month + index);
      return ReportDateRange(
        startLocal: start,
        endLocalExclusive: DateTime(first.year, first.month + index + 1),
      );
    });
  }

  List<ReportDateRange> _yearTrendRanges(
    DateTime anchorLocal,
    ReportCalendar calendar,
  ) {
    if (calendar == ReportCalendar.persian) {
      final current = PersianCalendar.yearRangeContaining(anchorLocal);
      final currentYear = PersianCalendar.fromGregorian(
        current.startLocal,
      ).year;
      return List.generate(5, (index) {
        return PersianCalendar.yearRangeContaining(
          PersianCalendar.toGregorianDate(
            year: currentYear - 4 + index,
            month: 1,
            day: 1,
          ),
        );
      });
    }
    final firstYear = anchorLocal.year - 4;
    return List.generate(5, (index) {
      final year = firstYear + index;
      return ReportDateRange(
        startLocal: DateTime(year),
        endLocalExclusive: DateTime(year + 1),
      );
    });
  }

  DateTime _dayStart(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _weekStart(DateTime value, ReportCalendar calendar) {
    final today = _dayStart(value);
    final daysSinceWeekStart = calendar == ReportCalendar.persian
        ? (value.weekday + 1) % 7
        : value.weekday - 1;
    return today.subtract(Duration(days: daysSinceWeekStart));
  }

  Future<int> _rangeTotal(
    TransactionHistoryKind kind,
    ReportDateRange range,
    ReportScope scope,
    String? deviceId,
  ) async {
    final source = _transactionSource(kind);
    final filterDeviceId = _filterDeviceId(scope, deviceId);
    final deviceFilter = _deviceFilterSql(filterDeviceId, 'e');
    final args = <Object?>[
      _transactionType(kind),
      range.startUtc.toIso8601String(),
      range.endUtcExclusive.toIso8601String(),
    ];
    if (filterDeviceId != null) args.add(filterDeviceId);
    final rows = await _db.rawQuery('''
      SELECT COALESCE(SUM(${source.alias}.total_minor), 0) AS total
      FROM ${source.table} ${source.alias}
      JOIN events e ON e.entity_id = ${source.alias}.${source.idColumn}
      WHERE e.type = ?
        AND ${source.alias}.occurred_at >= ?
        AND ${source.alias}.occurred_at < ?
        AND ${source.alias}.${source.statusColumn} = 0
        $deviceFilter
      ''', args);
    return rows.single['total'] as int;
  }

  Future<int> _grossMarginEstimate(
    ReportDateRange range,
    ReportScope scope,
    String? deviceId,
  ) async {
    final filterDeviceId = _filterDeviceId(scope, deviceId);
    final deviceFilter = _deviceFilterSql(filterDeviceId, 'e');
    final args = <Object?>[
      EventTypes.inventorySaleRecorded,
      range.startUtc.toIso8601String(),
      range.endUtcExclusive.toIso8601String(),
    ];
    if (filterDeviceId != null) args.add(filterDeviceId);
    final rows = await _db.rawQuery('''
      SELECT e.payload_json
      FROM events e
      JOIN sales_projection s ON s.sale_id = e.entity_id
      WHERE e.type = ?
        AND s.voided = 0
        AND s.occurred_at >= ?
        AND s.occurred_at < ?
        $deviceFilter
      ''', args);
    var margin = 0;
    for (final row in rows) {
      final payload = jsonDecode(row['payload_json'] as String) as Map;
      final lines = payload['line_items'] as List;
      for (final line in lines.cast<Map>()) {
        final quantity = (line['quantity'] as num).toDouble();
        final price = line['unit_price_minor'] as int;
        final revenue = (quantity * price).round();
        margin += revenue - _saleLineCostMinor(line);
      }
    }
    return margin;
  }

  int _saleLineCostMinor(Map line) {
    final costTotal = line['cost_total_minor'];
    if (costTotal is int) return costTotal;
    final allocations = line['cost_allocations'];
    if (allocations is List) {
      return allocations.fold<int>(0, (sum, raw) {
        if (raw is! Map) return sum;
        final cost = raw['cost_minor'];
        if (cost is int) return sum + cost;
        final quantity = raw['quantity'];
        final unitCost = raw['unit_cost_minor'];
        if (quantity is num && unitCost is int) {
          return sum + (quantity.toDouble() * unitCost).round();
        }
        return sum;
      });
    }
    final unitCost = line['unit_cost_minor'];
    final quantity = line['quantity'];
    if (unitCost is int && quantity is num) {
      return (quantity.toDouble() * unitCost).round();
    }
    return 0;
  }

  Future<DateTime?> _lastSyncAt() async {
    final rows = await _db.rawQuery(
      'SELECT MAX(last_successful_sync_at) AS last_sync FROM sync_peers',
    );
    final value = rows.single['last_sync'] as String?;
    if (value == null) return null;
    return DateTime.parse(value);
  }

  Future<int> _unsyncedEventCount() async {
    final peerRows = await _db.rawQuery('''
      SELECT p.last_pushed_hlc
      FROM sync_peers p
      JOIN devices d ON d.device_id = p.peer_device_id
      WHERE d.trust_status = 'trusted'
        AND p.base_url IS NOT NULL
        AND TRIM(p.base_url) <> ''
      ''');
    if (peerRows.isEmpty) return 0;

    final cursors = [
      for (final row in peerRows)
        SyncCursor.parse(row['last_pushed_hlc'] as String?),
    ];
    if (cursors.any((cursor) => cursor == null)) {
      return _localEventCountAfter(null);
    }

    final oldestCursor = cursors.cast<SyncCursor>().reduce(
      (oldest, cursor) =>
          _compareSyncCursor(oldest, cursor) <= 0 ? oldest : cursor,
    );
    return _localEventCountAfter(oldestCursor);
  }

  Future<int> _localEventCountAfter(SyncCursor? cursor) async {
    final where = [
      'device_id = ?',
      if (cursor != null) '(hlc > ? OR (hlc = ? AND event_id > ?))',
    ].join(' AND ');
    final args = <Object?>[
      _deviceId,
      if (cursor != null) ...[cursor.hlc, cursor.hlc, cursor.eventId],
    ];
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS count
      FROM events
      WHERE $where
      ''', args);
    return rows.single['count'] as int;
  }

  int _compareSyncCursor(SyncCursor a, SyncCursor b) {
    final hlc = a.hlc.compareTo(b.hlc);
    if (hlc != 0) return hlc;
    return a.eventId.compareTo(b.eventId);
  }

  Future<TransactionHistoryEntry> _historyFromRow(
    TransactionHistoryKind kind,
    Map<String, Object?> row,
  ) async {
    final payload = _decodePayload(row['payload_json'] as String);
    final createdAt = DateTime.parse(row['created_at'] as String);
    final lines = await _historyLines(kind, payload);
    final totalMinor =
        _optionalInt(payload, 'total_minor') ??
        lines.fold<int>(0, (sum, line) => sum + line.lineTotalMinor);
    return TransactionHistoryEntry(
      id: row['entity_id'] as String,
      kind: kind,
      occurredAt: _optionalDateTime(payload, 'occurred_at') ?? createdAt,
      totalMinor: totalMinor,
      lines: lines,
    );
  }

  Future<List<TransactionHistoryLine>> _historyLines(
    TransactionHistoryKind kind,
    Map<String, Object?> payload,
  ) async {
    final rawLines = payload['line_items'];
    if (rawLines is! List) return const [];
    final lines = <TransactionHistoryLine>[];
    for (final raw in rawLines) {
      if (raw is! Map) continue;
      final line = Map<String, Object?>.from(raw);
      final productId = line['product_id'];
      if (productId is! String) continue;
      final quantity = _optionalNumber(line, 'quantity') ?? 0;
      final unitMinor = switch (kind) {
        TransactionHistoryKind.sale =>
          _optionalInt(line, 'unit_price_minor') ?? 0,
        TransactionHistoryKind.purchase =>
          _optionalInt(line, 'unit_cost_minor') ?? 0,
      };
      final product = await productById(productId);
      lines.add(
        TransactionHistoryLine(
          productName: product?.name ?? 'Unknown product',
          quantity: quantity,
          lineTotalMinor: (quantity * unitMinor).round(),
        ),
      );
    }
    return lines;
  }

  Map<String, Object?> _decodePayload(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    return const {};
  }

  String _transactionType(TransactionHistoryKind kind) {
    return switch (kind) {
      TransactionHistoryKind.sale => EventTypes.inventorySaleRecorded,
      TransactionHistoryKind.purchase => EventTypes.inventoryPurchaseRecorded,
    };
  }

  _TransactionSource _transactionSource(TransactionHistoryKind kind) {
    return switch (kind) {
      TransactionHistoryKind.sale => const _TransactionSource(
        table: 'sales_projection',
        alias: 's',
        idColumn: 'sale_id',
        statusColumn: 'voided',
      ),
      TransactionHistoryKind.purchase => const _TransactionSource(
        table: 'purchase_projection',
        alias: 'p',
        idColumn: 'purchase_id',
        statusColumn: 'corrected',
      ),
    };
  }

  void _addDeviceFilter(
    List<String> where,
    List<Object?> args,
    ReportScope scope,
    String? deviceId,
  ) {
    final filterDeviceId = _filterDeviceId(scope, deviceId);
    if (filterDeviceId == null) return;
    where.add('e.device_id = ?');
    args.add(filterDeviceId);
  }

  String? _filterDeviceId(ReportScope scope, String? deviceId) {
    if (scope == ReportScope.localDevice) return _deviceId;
    final trimmed = deviceId?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _deviceFilterSql(String? deviceId, String alias) {
    return deviceId == null ? '' : 'AND $alias.device_id = ?';
  }

  String _cashierLabel(String deviceId, String? displayName) {
    final trimmed = displayName?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        trimmed == 'Peer' ||
        trimmed == 'Dekon phone') {
      return 'Cashier ${_shortDeviceId(deviceId)}';
    }
    return trimmed;
  }

  String _shortDeviceId(String deviceId) {
    return deviceId.length <= 8 ? deviceId : deviceId.substring(0, 8);
  }

  DateTime? _optionalDateTime(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  int? _optionalInt(Map<String, Object?> payload, String key) {
    final value = payload[key];
    return value is int ? value : null;
  }

  double? _optionalNumber(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  String _escapeLike(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  Future<void> _setAppSetting(String key, String value) {
    return _db.insert('app_settings', {
      'key': key,
      'value': value,
      'updated_at': _now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  ProductSummary _productFromRow(Map<String, Object?> row) {
    return ProductSummary(
      productId: row['product_id'] as String,
      name: row['name'] as String,
      barcode: row['barcode'] as String?,
      sku: row['sku'] as String?,
      unit: row['unit'] as String,
      salePriceMinor: row['sale_price_minor'] as int,
      purchaseCostMinor: row['purchase_cost_minor'] as int,
      active: row['active'] == 1,
      quantity: (row['quantity'] as num).toDouble(),
    );
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _TransactionSource {
  const _TransactionSource({
    required this.table,
    required this.alias,
    required this.idColumn,
    required this.statusColumn,
  });

  final String table;
  final String alias;
  final String idColumn;
  final String statusColumn;
}

class _SerializedAsyncQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_, _) {});
    return run;
  }
}
