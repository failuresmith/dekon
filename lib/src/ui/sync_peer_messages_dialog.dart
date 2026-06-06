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
    final groups = _messageGroups(direction);
    if (groups.isEmpty) return _emptyState(direction);
    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (context, index) => const Divider(height: 20),
      itemBuilder: (context, index) => _messageGroup(groups[index]),
    );
  }

  List<_MessageGroup> _messageGroups(SyncPeerMessageDirection direction) {
    final grouped = <String, List<SyncPeerMessage>>{};
    for (final message in _messages.reversed) {
      if (message.direction != direction) continue;
      final type = _messageType(message);
      grouped.putIfAbsent(type, () => <SyncPeerMessage>[]).add(message);
    }
    return [
      for (final entry in grouped.entries)
        _MessageGroup(type: entry.key, messages: entry.value),
    ];
  }

  Widget _messageGroup(_MessageGroup group) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.strings.syncMessageTypeGroup(
            group.type,
            group.messages.length,
          ),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < group.messages.length; i++) ...[
          if (i > 0) const Divider(height: 16),
          _messageTile(group.messages[i]),
        ],
      ],
    );
  }

  Widget _messageTile(SyncPeerMessage message) {
    final colorScheme = Theme.of(context).colorScheme;
    final bodyPreview = message.bodyPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_title(message), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(_metadata(message), style: Theme.of(context).textTheme.bodySmall),
        if (bodyPreview != null) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  bodyPreview,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ],
      ],
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

  String _metadata(SyncPeerMessage message) {
    return [
      _timeLabel(message.timestamp),
      if (message.summary != null) message.summary!,
      if (message.peerDeviceId != null)
        context.strings.syncPeer(_shortPeer(message.peerDeviceId!)),
    ].join(' | ');
  }

  String _timeLabel(DateTime timestamp) {
    return context.strings.timeOfDay(timestamp);
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

class _MessageGroup {
  const _MessageGroup({required this.type, required this.messages});

  final String type;
  final List<SyncPeerMessage> messages;
}
