import 'package:flutter/material.dart';

import '../application/application.dart';
import 'barcode_scanner_dialog.dart';
import 'cashier_pairing_panel.dart';

class DeviceOnboardingScreen extends StatefulWidget {
  const DeviceOnboardingScreen({
    super.key,
    required this.repository,
    required this.initialSettings,
    required this.onCompleted,
    this.scanBarcode = showBarcodeScannerDialog,
    this.pairWithMainDevice,
    this.pairWithMainDeviceAddress,
  });

  final DekonRepository repository;
  final DeviceRoleSettings initialSettings;
  final VoidCallback onCompleted;
  final BarcodeScanLauncher scanBarcode;
  final MainDevicePairer? pairWithMainDevice;
  final MainDeviceAddressPairer? pairWithMainDeviceAddress;

  @override
  State<DeviceOnboardingScreen> createState() => _DeviceOnboardingScreenState();
}

class _DeviceOnboardingScreenState extends State<DeviceOnboardingScreen> {
  late var _step = widget.initialSettings.role == DeviceRole.cashierDevice
      ? _OnboardingStep.pairCashier
      : _OnboardingStep.chooseRole;
  var _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dekon')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _step == _OnboardingStep.chooseRole
                ? 'Set up this device'
                : 'Pair cashier device',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _step == _OnboardingStep.chooseRole
                ? 'Choose how this device will be used.'
                : 'Connect this cashier to the main device before use.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          if (_step == _OnboardingStep.chooseRole) _roleChoices(),
          if (_step == _OnboardingStep.pairCashier)
            CashierPairingPanel(
              repository: widget.repository,
              scanBarcode: widget.scanBarcode,
              pairWithMainDevice: widget.pairWithMainDevice,
              pairWithMainDeviceAddress: widget.pairWithMainDeviceAddress,
              onPaired: widget.onCompleted,
            ),
        ],
      ),
    );
  }

  Widget _roleChoices() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('onboarding-main-device'),
          onPressed: _busy ? null : _chooseMainDevice,
          icon: const Icon(Icons.inventory_2),
          label: const Text('Main Device'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('onboarding-cashier-device'),
          onPressed: _busy ? null : _chooseCashierDevice,
          icon: const Icon(Icons.point_of_sale),
          label: const Text('Cashier'),
        ),
      ],
    );
  }

  Future<void> _chooseMainDevice() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.completeDeviceOnboarding(DeviceRole.mainDevice);
      widget.onCompleted();
    } catch (error) {
      if (mounted) setState(() => _error = 'Setup failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseCashierDevice() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.setDeviceRole(DeviceRole.cashierDevice);
      if (mounted) setState(() => _step = _OnboardingStep.pairCashier);
    } catch (error) {
      if (mounted) setState(() => _error = 'Setup failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

enum _OnboardingStep { chooseRole, pairCashier }
