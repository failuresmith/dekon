import 'dart:math';

class HybridLogicalTimestamp implements Comparable<HybridLogicalTimestamp> {
  const HybridLogicalTimestamp({
    required this.physicalTimeMillis,
    required this.logicalCounter,
    required this.nodeId,
  });

  factory HybridLogicalTimestamp.parse(String value) {
    final parts = value.split(':');
    if (parts.length != 3) {
      throw FormatException('Invalid HLC timestamp.', value);
    }
    return HybridLogicalTimestamp(
      physicalTimeMillis: int.parse(parts[0]),
      logicalCounter: int.parse(parts[1]),
      nodeId: parts[2],
    );
  }

  final int physicalTimeMillis;
  final int logicalCounter;
  final String nodeId;

  @override
  int compareTo(HybridLogicalTimestamp other) {
    final physical = physicalTimeMillis.compareTo(other.physicalTimeMillis);
    if (physical != 0) return physical;
    final logical = logicalCounter.compareTo(other.logicalCounter);
    if (logical != 0) return logical;
    return nodeId.compareTo(other.nodeId);
  }

  @override
  bool operator ==(Object other) {
    return other is HybridLogicalTimestamp &&
        physicalTimeMillis == other.physicalTimeMillis &&
        logicalCounter == other.logicalCounter &&
        nodeId == other.nodeId;
  }

  @override
  int get hashCode => Object.hash(physicalTimeMillis, logicalCounter, nodeId);

  @override
  String toString() {
    final physical = physicalTimeMillis.toString().padLeft(16, '0');
    final logical = logicalCounter.toString().padLeft(8, '0');
    return '$physical:$logical:$nodeId';
  }
}

class HybridLogicalClock {
  HybridLogicalClock({required this.nodeId, HybridLogicalTimestamp? last})
    : _last =
          last ??
          HybridLogicalTimestamp(
            physicalTimeMillis: 0,
            logicalCounter: 0,
            nodeId: nodeId,
          );

  final String nodeId;
  HybridLogicalTimestamp _last;

  HybridLogicalTimestamp get last => _last;

  HybridLogicalTimestamp send(DateTime now) {
    final wallMillis = now.toUtc().millisecondsSinceEpoch;
    if (wallMillis > _last.physicalTimeMillis) {
      return _last = HybridLogicalTimestamp(
        physicalTimeMillis: wallMillis,
        logicalCounter: 0,
        nodeId: nodeId,
      );
    }
    return _last = HybridLogicalTimestamp(
      physicalTimeMillis: _last.physicalTimeMillis,
      logicalCounter: _last.logicalCounter + 1,
      nodeId: nodeId,
    );
  }

  HybridLogicalTimestamp receive(HybridLogicalTimestamp remote, DateTime now) {
    final wallMillis = now.toUtc().millisecondsSinceEpoch;
    final nextPhysical = max(
      wallMillis,
      max(_last.physicalTimeMillis, remote.physicalTimeMillis),
    );
    final nextLogical = _nextLogical(remote, nextPhysical);
    return _last = HybridLogicalTimestamp(
      physicalTimeMillis: nextPhysical,
      logicalCounter: nextLogical,
      nodeId: nodeId,
    );
  }

  int _nextLogical(HybridLogicalTimestamp remote, int nextPhysical) {
    if (nextPhysical == _last.physicalTimeMillis &&
        nextPhysical == remote.physicalTimeMillis) {
      return max(_last.logicalCounter, remote.logicalCounter) + 1;
    }
    if (nextPhysical == _last.physicalTimeMillis) {
      return _last.logicalCounter + 1;
    }
    if (nextPhysical == remote.physicalTimeMillis) {
      return remote.logicalCounter + 1;
    }
    return 0;
  }
}
