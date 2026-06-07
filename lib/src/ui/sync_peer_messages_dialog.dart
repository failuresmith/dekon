import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../application/application.dart';
import '../sync/sync.dart';
import 'ui_strings.dart';

Future<void> showSyncPeerMessagesDialog({
  required BuildContext context,
  required DekonRepository repository,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => SyncPeerMessagesDialog(repository: repository),
  );
}

class SyncPeerMessagesDialog extends StatefulWidget {
  const SyncPeerMessagesDialog({super.key, required this.repository});

  final DekonRepository repository;

  @override
  State<SyncPeerMessagesDialog> createState() => _SyncPeerMessagesDialogState();
}

class _SyncPeerMessagesDialogState extends State<SyncPeerMessagesDialog> {
  late List<SyncPeerMessage> _messages = widget.repository
      .recentSyncPeerMessages();
  StreamSubscription<SyncPeerMessage>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.repository.syncPeerMessages.listen((_) {
      if (!mounted) return;
      setState(() {
        _messages = widget.repository.recentSyncPeerMessages();
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final strings = context.strings;
    final width = min(max(viewport.width - 48, 280), 520).toDouble();
    final height = min(max(viewport.height * 0.5, 260), 420).toDouble();
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: Text(strings.peerMessages),
        content: SizedBox(
          width: width,
          height: height,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(
                    key: const Key('sync-peer-messages-sent-tab'),
                    text: strings.peerMessagesSent,
                  ),
                  Tab(
                    key: const Key('sync-peer-messages-received-tab'),
                    text: strings.peerMessagesReceived,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    _messageList(SyncPeerMessageDirection.sent),
                    _messageList(SyncPeerMessageDirection.received),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('clear-sync-peer-messages'),
            onPressed: _messages.isEmpty ? null : _clearMessages,
            child: Text(strings.clear),
          ),
          TextButton(
            key: const Key('close-sync-peer-messages'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.close),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(SyncPeerMessageDirection direction) {
    final strings = context.strings;
    final message = switch (direction) {
      SyncPeerMessageDirection.sent => strings.noSentPeerMessagesYet,
      SyncPeerMessageDirection.received => strings.noReceivedPeerMessagesYet,
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sync_alt),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 4),
          Text(strings.peerMessagesHint, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _messageList(SyncPeerMessageDirection direction) {
    final rows = _messageRows(direction);
    if (rows.isEmpty) return _emptyState(direction);
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _messageTile(rows[index]),
    );
  }

  List<_IndexedMessage> _messageRows(SyncPeerMessageDirection direction) {
    final rows = <_IndexedMessage>[];
    for (final message in _messages) {
      if (message.direction != direction) continue;
      rows.add(
        _IndexedMessage(
          index: rows.length + 1,
          message: message,
          type: _messageType(message),
        ),
      );
    }
    return rows;
  }

  Widget _messageTile(_IndexedMessage row) {
    final strings = context.strings;
    final message = row.message;
    final indexLabel = strings.syncPeerMessageIndex(row.index);
    return Semantics(
      button: true,
      label: strings.openSyncPeerMessageDetails(row.index),
      child: ListTile(
        key: Key('sync-peer-message-${message.direction.name}-${row.index}'),
        minVerticalPadding: 8,
        leading: SizedBox(
          width: 44,
          child: Text(
            indexLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        title: Text(row.type),
        subtitle: Text(
          '${_timeField(message)}: ${_timeLabel(message.timestamp)}'
          '\n${_title(message)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showMessageDetails(row),
      ),
    );
  }

  Future<void> _showMessageDetails(_IndexedMessage row) {
    return showDialog<void>(
      context: context,
      builder: (context) => _SyncPeerMessageDetailsDialog(
        row: row,
        title: _title(row.message),
        timeField: _timeField(row.message),
        timeLabel: _timeLabel(row.message.timestamp),
        peerLabel: row.message.peerDeviceId == null
            ? null
            : context.strings.syncPeer(_shortPeer(row.message.peerDeviceId!)),
      ),
    );
  }

  String _title(SyncPeerMessage message) {
    final status = message.statusCode == null ? '' : '${message.statusCode} ';
    return switch (message.direction) {
      SyncPeerMessageDirection.sent => context.strings.syncMessageSent(
        message.method,
        message.path,
        status,
      ),
      SyncPeerMessageDirection.received => context.strings.syncMessageReceived(
        message.method,
        message.path,
        status,
      ),
    };
  }

  String _timeLabel(DateTime timestamp) {
    return context.strings.timeOfDay(timestamp);
  }

  String _timeField(SyncPeerMessage message) {
    return switch (message.direction) {
      SyncPeerMessageDirection.sent => context.strings.syncPeerMessageTimeSent,
      SyncPeerMessageDirection.received =>
        context.strings.syncPeerMessageTimeReceived,
    };
  }

  String _messageType(SyncPeerMessage message) {
    final strings = context.strings;
    final path = _pathWithoutQuery(message.path);
    if (message.method == 'GET' && path == '/health') {
      return strings.syncMessageTypeHealth;
    }
    if (message.method == 'GET' && path == '/device') {
      return strings.syncMessageTypeDeviceInfo;
    }
    if (message.method == 'POST' && path == '/pair') {
      return strings.syncMessageTypePairing;
    }
    if (message.method == 'GET' && path == '/events') {
      return strings.syncMessageTypeEventPull;
    }
    if (message.method == 'POST' && path == '/events') {
      return strings.syncMessageTypeEventPush;
    }
    if (message.method == 'GET' && path == '/sync/state') {
      return strings.syncMessageTypeSyncState;
    }
    return strings.syncMessageTypeHttp(message.method, path);
  }

  String _pathWithoutQuery(String path) {
    final queryStart = path.indexOf('?');
    if (queryStart == -1) return path;
    return path.substring(0, queryStart);
  }

  String _shortPeer(String peerDeviceId) {
    if (peerDeviceId.length <= 12) return peerDeviceId;
    return '...${peerDeviceId.substring(peerDeviceId.length - 8)}';
  }

  void _clearMessages() {
    widget.repository.clearSyncPeerMessages();
    setState(() {
      _messages = const <SyncPeerMessage>[];
    });
  }
}

class _SyncPeerMessageDetailsDialog extends StatelessWidget {
  const _SyncPeerMessageDetailsDialog({
    required this.row,
    required this.title,
    required this.timeField,
    required this.timeLabel,
    required this.peerLabel,
  });

  final _IndexedMessage row;
  final String title;
  final String timeField;
  final String timeLabel;
  final String? peerLabel;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final strings = context.strings;
    final width = min(max(viewport.width - 48, 280), 600).toDouble();
    final height = min(max(viewport.height * 0.62, 320), 560).toDouble();
    final message = row.message;
    return AlertDialog(
      title: Text(strings.syncPeerMessageDetails),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailLine(
              context,
              strings.syncPeerMessageIndexLabel,
              strings.syncPeerMessageIndex(row.index),
            ),
            _detailLine(context, timeField, timeLabel),
            _detailLine(context, strings.syncPeerMessageTypeLabel, row.type),
            _detailLine(context, strings.syncPeerMessageRequestLabel, title),
            if (message.summary != null)
              _detailLine(
                context,
                strings.syncPeerMessageSummaryLabel,
                message.summary!,
              ),
            if (peerLabel != null)
              _detailLine(
                context,
                strings.syncPeerMessagePeerLabel,
                peerLabel!,
              ),
            const SizedBox(height: 12),
            Text(
              strings.syncPeerMessageContent,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(child: _messageContent(context, message.bodyContent)),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('close-sync-peer-message-details'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.close),
        ),
      ],
    );
  }

  Widget _detailLine(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _messageContent(BuildContext context, String? content) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: content == null
            ? Center(child: Text(context.strings.noSyncPeerMessageContent))
            : SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    content,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ),
      ),
    );
  }
}

class _IndexedMessage {
  const _IndexedMessage({
    required this.index,
    required this.message,
    required this.type,
  });

  final int index;
  final SyncPeerMessage message;
  final String type;
}
