enum CashierSyncVisualState {
  disconnected,
  syncing,
  synced,
  degraded,
  conflicted,
  unpaired,
}

class CashierSyncStatus {
  const CashierSyncStatus({
    required this.transportReachable,
    required this.projectionStreamConnected,
    required this.snapshotSyncInProgress,
    required this.pendingOutboxCount,
    required this.conflictedOutboxCount,
    required this.stale,
    required this.degraded,
    this.lastAppliedProjectionVersion,
    this.lastErrorCode,
    this.unpaired = false,
  });

  static const disconnected = CashierSyncStatus(
    transportReachable: false,
    projectionStreamConnected: false,
    snapshotSyncInProgress: false,
    pendingOutboxCount: 0,
    conflictedOutboxCount: 0,
    stale: true,
    degraded: false,
  );

  static const syncing = CashierSyncStatus(
    transportReachable: true,
    projectionStreamConnected: true,
    snapshotSyncInProgress: true,
    pendingOutboxCount: 0,
    conflictedOutboxCount: 0,
    stale: false,
    degraded: false,
  );

  static const synced = CashierSyncStatus(
    transportReachable: true,
    projectionStreamConnected: true,
    snapshotSyncInProgress: false,
    pendingOutboxCount: 0,
    conflictedOutboxCount: 0,
    stale: false,
    degraded: false,
  );

  static const unpairedStatus = CashierSyncStatus(
    transportReachable: false,
    projectionStreamConnected: false,
    snapshotSyncInProgress: false,
    pendingOutboxCount: 0,
    conflictedOutboxCount: 0,
    stale: true,
    degraded: true,
    lastErrorCode: 'peer_unpaired',
    unpaired: true,
  );

  final bool transportReachable;
  final bool projectionStreamConnected;
  final bool snapshotSyncInProgress;
  final int? lastAppliedProjectionVersion;
  final int pendingOutboxCount;
  final int conflictedOutboxCount;
  final bool stale;
  final bool degraded;
  final String? lastErrorCode;
  final bool unpaired;

  bool get hasOutboxConflict => conflictedOutboxCount > 0;
  bool get blocksNormalCashierUse => unpaired || hasOutboxConflict;
  bool get needsAttention {
    return unpaired ||
        hasOutboxConflict ||
        !transportReachable ||
        stale ||
        degraded;
  }

  CashierSyncVisualState get visualState {
    if (unpaired) return CashierSyncVisualState.unpaired;
    if (hasOutboxConflict) return CashierSyncVisualState.conflicted;
    if (snapshotSyncInProgress) return CashierSyncVisualState.syncing;
    if (!transportReachable) return CashierSyncVisualState.disconnected;
    if (stale || degraded || !projectionStreamConnected) {
      return CashierSyncVisualState.degraded;
    }
    return CashierSyncVisualState.synced;
  }

  CashierSyncStatus copyWith({
    bool? transportReachable,
    bool? projectionStreamConnected,
    bool? snapshotSyncInProgress,
    int? lastAppliedProjectionVersion,
    bool clearLastAppliedProjectionVersion = false,
    int? pendingOutboxCount,
    int? conflictedOutboxCount,
    bool? stale,
    bool? degraded,
    String? lastErrorCode,
    bool clearLastErrorCode = false,
    bool? unpaired,
  }) {
    return CashierSyncStatus(
      transportReachable: transportReachable ?? this.transportReachable,
      projectionStreamConnected:
          projectionStreamConnected ?? this.projectionStreamConnected,
      snapshotSyncInProgress:
          snapshotSyncInProgress ?? this.snapshotSyncInProgress,
      lastAppliedProjectionVersion: clearLastAppliedProjectionVersion
          ? null
          : lastAppliedProjectionVersion ?? this.lastAppliedProjectionVersion,
      pendingOutboxCount: pendingOutboxCount ?? this.pendingOutboxCount,
      conflictedOutboxCount:
          conflictedOutboxCount ?? this.conflictedOutboxCount,
      stale: stale ?? this.stale,
      degraded: degraded ?? this.degraded,
      lastErrorCode: clearLastErrorCode
          ? null
          : lastErrorCode ?? this.lastErrorCode,
      unpaired: unpaired ?? this.unpaired,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CashierSyncStatus &&
        other.transportReachable == transportReachable &&
        other.projectionStreamConnected == projectionStreamConnected &&
        other.snapshotSyncInProgress == snapshotSyncInProgress &&
        other.lastAppliedProjectionVersion == lastAppliedProjectionVersion &&
        other.pendingOutboxCount == pendingOutboxCount &&
        other.conflictedOutboxCount == conflictedOutboxCount &&
        other.stale == stale &&
        other.degraded == degraded &&
        other.lastErrorCode == lastErrorCode &&
        other.unpaired == unpaired;
  }

  @override
  int get hashCode {
    return Object.hash(
      transportReachable,
      projectionStreamConnected,
      snapshotSyncInProgress,
      lastAppliedProjectionVersion,
      pendingOutboxCount,
      conflictedOutboxCount,
      stale,
      degraded,
      lastErrorCode,
      unpaired,
    );
  }
}
