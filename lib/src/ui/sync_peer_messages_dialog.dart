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
    return AlertDialog(
      title: Text(strings.peerMessages),
      content: SizedBox(
        width: width,
        height: height,
        child: _messages.isEmpty ? _emptyState() : _messageList(),
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
    );
  }

  Widget _emptyState() {
    final strings = context.strings;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sync_alt),
          const SizedBox(height: 8),
          Text(strings.noPeerMessagesYet),
          const SizedBox(height: 4),
          Text(strings.peerMessagesHint, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _messageList() {
    final messages = _messages.reversed.toList(growable: false);
    return ListView.separated(
      itemCount: messages.length,
      separatorBuilder: (context, index) => const Divider(height: 20),
      itemBuilder: (context, index) => _messageTile(messages[index]),
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
