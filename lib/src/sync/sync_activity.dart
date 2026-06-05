import 'dart:async';

class SyncActivityBus {
  final _eventsChanged = StreamController<void>.broadcast();
  final _transfers = StreamController<SyncTransferActivity>.broadcast();

  Stream<void> get eventsChanged => _eventsChanged.stream;
  Stream<SyncTransferActivity> get transfers => _transfers.stream;

  void notifyEventsChanged() {
    if (!_eventsChanged.isClosed) _eventsChanged.add(null);
  }

  void notifyTransfer(SyncTransferActivity activity) {
    if (activity.eventCount <= 0 || _transfers.isClosed) return;
    _transfers.add(activity);
  }

  Future<void> close() async {
    await _eventsChanged.close();
    await _transfers.close();
  }
}

class SyncTransferActivity {
  const SyncTransferActivity({
    required this.direction,
    required this.eventCount,
  });

  final SyncTransferDirection direction;
  final int eventCount;
}

enum SyncTransferDirection { sent, received }
