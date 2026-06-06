import 'package:flutter/material.dart';

import '../application/application.dart';
import '../sync/sync.dart';
import 'barcode_scanner_dialog.dart';
import 'ui_strings.dart';

typedef MainDevicePairer = Future<void> Function(SyncPairingPayload payload);
typedef MainDeviceAddressPairer = Future<void> Function(String address);

class CashierPairingPanel extends StatefulWidget {
  const CashierPairingPanel({
    super.key,
    required this.repository,
    this.scanBarcode = showBarcodeScannerDialog,
    this.pairWithMainDevice,
    this.pairWithMainDeviceAddress,
    this.syncServiceDiscovery = const NoopSyncServiceDiscovery(),
    this.onPaired,
  });

  final DekonRepository repository;
  final BarcodeScanLauncher scanBarcode;
  final MainDevicePairer? pairWithMainDevice;
  final MainDeviceAddressPairer? pairWithMainDeviceAddress;
  final SyncServiceDiscovery syncServiceDiscovery;
  final VoidCallback? onPaired;

  @override
  State<CashierPairingPanel> createState() => _CashierPairingPanelState();
}

class _CashierPairingPanelState extends State<CashierPairingPanel> {
  var _busy = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.pairWithMainDeviceBeforeUsingCashier),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('pair-main-device'),
              onPressed: _busy ? null : _pairWithQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(_busy ? strings.pairing : strings.scanQrCode),
            ),
            OutlinedButton.icon(
              key: const Key('pair-main-device-manual'),
              onPressed: _busy ? null : _pairWithManualAddress,
              icon: const Icon(Icons.edit_location_alt),
              label: Text(strings.enterIpManually),
            ),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!),
          ),
      ],
    );
  }

  Future<void> _pairWithQr() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final scanned = await widget.scanBarcode(context);
      if (!mounted || scanned == null || scanned.trim().isEmpty) return;
      final payload = SyncPairingPayload.fromQrJson(scanned.trim());
      await _pairWithMainDevice(payload);
      await _completePairing();
    } catch (error) {
      _showPairingError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pairWithManualAddress() async {
    final address = await _requestManualAddress();
    if (!mounted || address == null || address.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await _pairWithMainDeviceAddress(address);
      await _completePairing();
    } catch (error) {
      _showPairingError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _requestManualAddress() async {
    return showDialog<String>(
      context: context,
      builder: (context) => const _ManualPairingDialog(),
    );
  }

  Future<void> _pairWithMainDevice(SyncPairingPayload payload) async {
    final injected = widget.pairWithMainDevice;
    if (injected != null) {
      await injected(payload);
      return;
    }
    final client = widget.repository.createLanSyncClient(
      serviceDiscovery: widget.syncServiceDiscovery,
    );
    try {
      await client.pairWithServer(payload, displayName: 'Cashier Device');
    } finally {
      client.close();
    }
  }

  Future<void> _pairWithMainDeviceAddress(String address) async {
    final injected = widget.pairWithMainDeviceAddress;
    if (injected != null) {
      await injected(address);
      return;
    }
    final client = widget.repository.createLanSyncClient(
      serviceDiscovery: widget.syncServiceDiscovery,
    );
    try {
      await client.pairWithManualAddress(
        address,
        displayName: 'Cashier Device',
      );
    } finally {
      client.close();
    }
  }

  Future<void> _completePairing() async {
    await widget.repository.lockDeviceRole(DeviceRole.cashierDevice);
    if (!mounted) return;
    setState(() => _status = context.strings.pairedWithMainDevice);
    widget.onPaired?.call();
  }

  void _showPairingError(Object error) {
    if (!mounted) return;
    setState(
      () => _status = context.strings.pairingFailed(_safePairingError(error)),
    );
  }

  String _safePairingError(Object error) {
    if (error is FormatException) return error.message;
    if (error is SyncClientException) return error.message;
    return context.strings.couldNotPairWithMainDevice;
  }
}

class _ManualPairingDialog extends StatefulWidget {
  const _ManualPairingDialog();

  @override
  State<_ManualPairingDialog> createState() => _ManualPairingDialogState();
}

class _ManualPairingDialogState extends State<_ManualPairingDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.strings.mainDeviceIp),
      content: TextField(
        key: const Key('manual-main-device-address'),
        controller: _controller,
        decoration: InputDecoration(
          labelText: context.strings.ipAddressOrUrl,
          hintText: '192.168.1.10:1234',
        ),
        keyboardType: TextInputType.url,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.strings.cancel),
        ),
        FilledButton(
          key: const Key('confirm-manual-main-device'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(context.strings.pair),
        ),
      ],
    );
  }
}
