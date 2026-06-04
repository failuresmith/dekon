import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../application/application.dart';
import '../backup/backup.dart';
import '../sync/sync.dart';
import 'product_form_dialog.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.repository,
    this.syncServer,
    this.backupService,
    this.backupFiles = const BackupFileActions(),
  });

  final DekonRepository repository;
  final LanSyncServer? syncServer;
  final BackupRunner? backupService;
  final BackupFileActions backupFiles;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<_ReportsData> _future = _load();
  var _serverBusy = false;
  var _backupBusy = false;
  String? _serverError;
  String? _backupStatus;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReportsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Reports failed: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.requireData;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _status(data.summary),
              const SizedBox(height: 12),
              _syncServerPanel(),
              const SizedBox(height: 12),
              _backupPanel(),
              const SizedBox(height: 12),
              _metrics(data.summary),
              const SizedBox(height: 16),
              Text('Stock', style: Theme.of(context).textTheme.titleLarge),
              if (data.summary.stockRows.isEmpty) const Text('No stock yet'),
              for (final row in data.summary.stockRows)
                ListTile(
                  title: Text(row.name),
                  subtitle: Text('Qty ${row.quantity.g}'),
                ),
              const SizedBox(height: 16),
              Text('Products', style: Theme.of(context).textTheme.titleLarge),
              for (final product in data.products)
                ListTile(
                  title: Text(product.name),
                  subtitle: Text(
                    '${product.barcode ?? 'No barcode'} - ${product.active ? 'Active' : 'Inactive'}',
                  ),
                  trailing: IconButton(
                    key: Key('edit-${product.productId}'),
                    tooltip: 'Edit product',
                    onPressed: () => _edit(product),
                    icon: const Icon(Icons.edit),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _status(ReportSummary summary) {
    final lastSync = summary.lastSyncAt?.toLocal().toString() ?? 'Never';
    return Text(
      'Unsynced events: ${summary.unsyncedEventCount} - Last sync: $lastSync',
      key: const Key('sync-status'),
    );
  }

  Widget _metrics(ReportSummary summary) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _metric('Daily sales', formatMoney(summary.dailySalesMinor)),
        _metric('Daily purchases', formatMoney(summary.dailyPurchasesMinor)),
        _metric('Gross margin', formatMoney(summary.grossMarginMinor)),
        _metric('Low stock', summary.lowStockRows.length.toString()),
      ],
    );
  }

  Widget _syncServerPanel() {
    final server = widget.syncServer;
    if (server == null) return const SizedBox.shrink();
    final running = server.isRunning;
    final qrData = server.pairingQrData;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LAN Sync', style: Theme.of(context).textTheme.titleMedium),
            if (_serverError != null) Text(_serverError!),
            if (running) ...[
              SelectableText(
                server.serverUrl ?? 'Starting',
                key: const Key('sync-server-url'),
              ),
              if (qrData != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: QrImageView(
                    key: const Key('sync-pairing-qr'),
                    data: qrData,
                    version: QrVersions.auto,
                    size: 160,
                    backgroundColor: Colors.white,
                  ),
                ),
              FilledButton.icon(
                key: const Key('stop-sync-server'),
                onPressed: _serverBusy ? null : _stopServer,
                icon: const Icon(Icons.stop),
                label: const Text('Stop LAN Sync'),
              ),
            ] else
              FilledButton.icon(
                key: const Key('start-sync-server'),
                onPressed: _serverBusy ? null : _startServer,
                icon: const Icon(Icons.sync),
                label: Text(_serverBusy ? 'Starting' : 'Start LAN Sync'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _backupPanel() {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backup and Recovery',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_backupStatus != null) Text(_backupStatus!),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('save-backup'),
                  onPressed: _backupBusy ? null : _saveBackup,
                  icon: const Icon(Icons.save_alt),
                  label: Text(_backupBusy ? 'Working' : 'Save Backup'),
                ),
                OutlinedButton.icon(
                  key: const Key('restore-backup'),
                  onPressed: _backupBusy ? null : _restoreBackup,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore Backup'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return SizedBox(
      width: 152,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }

  Future<_ReportsData> _load() async {
    final summary = await widget.repository.reportSummary();
    final products = await widget.repository.products();
    return _ReportsData(summary: summary, products: products);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _edit(ProductSummary product) async {
    await showProductFormDialog(
      context: context,
      repository: widget.repository,
      product: product,
    );
    await _refresh();
  }

  Future<void> _startServer() async {
    setState(() {
      _serverBusy = true;
      _serverError = null;
    });
    try {
      await widget.syncServer!.start();
    } catch (error) {
      _serverError = 'LAN sync failed: $error';
    } finally {
      if (mounted) setState(() => _serverBusy = false);
    }
  }

  Future<void> _stopServer() async {
    setState(() {
      _serverBusy = true;
      _serverError = null;
    });
    try {
      await widget.syncServer!.stop();
    } catch (error) {
      _serverError = 'LAN sync stop failed: $error';
    } finally {
      if (mounted) setState(() => _serverBusy = false);
    }
  }

  Future<void> _saveBackup() async {
    setState(() {
      _backupBusy = true;
      _backupStatus = null;
    });
    try {
      final directory = await widget.backupFiles.chooseExportDirectory();
      if (directory == null) return;
      final result = await _backupService.exportToDirectory(directory);
      _backupStatus = 'Saved ${result.eventCount} records';
      _message('Backup saved');
    } catch (error) {
      _backupStatus = 'Backup failed: $error';
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restoreBackup() async {
    setState(() {
      _backupBusy = true;
      _backupStatus = null;
    });
    try {
      final file = await widget.backupFiles.chooseImportFile();
      if (file == null) return;
      final preview = await _backupService.preview(file.contents);
      if (!mounted || await _confirmRestore(file, preview) != true) return;
      final result = await _backupService.importBackup(file.contents);
      _backupStatus =
          'Restored ${result.acceptedCount} records'
          '${result.duplicateCount == 0 ? '' : ', skipped ${result.duplicateCount}'}';
      _message('Backup restored');
      await _refresh();
    } catch (error) {
      _backupStatus = 'Restore failed: $error';
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  BackupRunner get _backupService {
    return widget.backupService ?? widget.repository.createBackupService();
  }

  Future<bool?> _confirmRestore(BackupImportFile file, BackupPreview preview) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
          '${file.name}\n'
          '${preview.eventCount} records\n'
          'Made ${preview.exportedAt.toLocal()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-restore-backup'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _ReportsData {
  const _ReportsData({required this.summary, required this.products});

  final ReportSummary summary;
  final List<ProductSummary> products;
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
