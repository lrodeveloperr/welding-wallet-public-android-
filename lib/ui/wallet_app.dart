import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../services/billing_service.dart';
import 'theme.dart';

class WeldingWalletApp extends StatefulWidget {
  const WeldingWalletApp({
    required this.controller,
    this.autoInitialize = true,
    super.key,
  });

  final AppController controller;
  final bool autoInitialize;

  @override
  State<WeldingWalletApp> createState() => _WeldingWalletAppState();
}

class _WeldingWalletAppState extends State<WeldingWalletApp> {
  @override
  void initState() {
    super.initState();
    if (widget.autoInitialize) widget.controller.initialize();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Welding Gas Wallet',
        theme: buildWalletTheme(),
        locale: const Locale('en'),
        supportedLocales: const <Locale>[Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: _WalletRoot(controller: widget.controller),
      );
    },
  );
}

class _WalletRoot extends StatelessWidget {
  const _WalletRoot({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final wallet = controller.wallet;
    if (wallet == null) {
      return Scaffold(
        body: _FatalState(
          message: controller.error ?? 'The wallet could not be opened.',
          onRetry: controller.initialize,
        ),
      );
    }
    if (!wallet.settings.onboardingComplete) {
      return _OnboardingScreen(
        onContinue: () => controller.run(
          controller.engine.completeOnboarding,
          success: 'Your private wallet is ready.',
        ),
      );
    }
    return _WalletShell(controller: controller, wallet: wallet);
  }
}

class _WalletShell extends StatelessWidget {
  const _WalletShell({
    required this.controller,
    required this.wallet,
  });
  final AppController controller;
  final WalletData wallet;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _DashboardScreen(
        wallet: wallet,
        onAddCylinder: () => _openAddCylinder(context, controller),
        onCylinder: (cylinder) => _openCylinder(context, controller, cylinder),
        onState: (cylinder, state) {
          unawaited(
            controller.run(
              () => controller.engine.changeCylinderState(cylinder.id, state),
              success: '${cylinderStateLabel(state)}.',
            ),
          );
        },
        onReminder: (cylinder) {
          unawaited(_openReminder(context, controller, target: cylinder));
        },
      ),
      _ActivityScreen(wallet: wallet),
      _SettingsScreen(
        wallet: wallet,
        onSuppliers: () => _openSuppliers(context, controller),
        onReminders: () => _openReminders(context, controller),
        onPro: () => _openPaywall(context, controller),
        onReminderToggle: (value) =>
            controller.run(() => controller.setRemindersEnabled(value)),
        onCurrency: (value) => controller.run(
          () => controller.engine.updateSettings(currencyCode: value),
        ),
        onMassUnit: (value) => controller.run(
          () => controller.engine.updateSettings(defaultMassUnit: value),
        ),
        onVolumeUnit: (value) => controller.run(
          () => controller.engine.updateSettings(defaultVolumeUnit: value),
        ),
        onBackup: controller.exportBackup,
        onRestore: () => _restoreBackup(context, controller),
        onDelete: () => _deleteWallet(context, controller),
        onFreeRecords: () => _openFreeRecordPicker(context, controller),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (controller.error != null || controller.notice != null)
              _MessageBar(
                message: controller.error ?? controller.notice!,
                isError: controller.error != null,
                onClose: controller.clearMessage,
              ),
            Expanded(
              child: IndexedStack(index: controller.tabIndex, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: controller.tabIndex,
        onDestinationSelected: controller.selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.propane_tank_outlined),
            selectedIcon: Icon(Icons.propane_tank),
            label: 'Gas',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _DashboardScreen extends StatelessWidget {
  const _DashboardScreen({
    required this.wallet,
    required this.onAddCylinder,
    required this.onCylinder,
    required this.onState,
    required this.onReminder,
  });

  final WalletData wallet;
  final VoidCallback onAddCylinder;
  final ValueChanged<Cylinder> onCylinder;
  final void Function(Cylinder cylinder, CylinderState state) onState;
  final ValueChanged<Cylinder> onReminder;

  @override
  Widget build(BuildContext context) {
    final current = wallet.cylinders
        .where((value) => value.consumesCurrentSlot)
        .toList();
    final past = wallet.cylinders
        .where((value) => !value.consumesCurrentSlot)
        .toList();
    return CustomScrollView(
      key: const Key('dashboard-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: WalletColors.blue,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    child: const Icon(Icons.propane_tank, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Welding Gas Wallet',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (current.isEmpty)
                _EmptyCard(
                  icon: Icons.propane_tank_outlined,
                  title: 'No cylinders',
                  body: 'Add a cylinder to track its status, refill and cost.',
                  action: 'Add',
                  onAction: onAddCylinder,
                )
              else ...[
                Row(
                  children: [
                    const Expanded(child: _SectionLabel('CYLINDERS')),
                    TextButton.icon(
                      onPressed: onAddCylinder,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...current.map(
                  (cylinder) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CylinderCard(
                      cylinder: cylinder,
                      wallet: wallet,
                      onTap: () => onCylinder(cylinder),
                      onState: (state) => onState(cylinder, state),
                      onReminder: () => onReminder(cylinder),
                    ),
                  ),
                ),
              ],
              if (past.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: _SectionLabel('PAST')),
                    Text(
                      '${past.length} saved',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...past.map(
                  (cylinder) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CylinderCard(
                      cylinder: cylinder,
                      wallet: wallet,
                      onTap: () => onCylinder(cylinder),
                      onState: (_) {},
                      onReminder: () {},
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CylinderCard extends StatelessWidget {
  const _CylinderCard({
    required this.cylinder,
    required this.wallet,
    required this.onTap,
    required this.onState,
    required this.onReminder,
  });

  final Cylinder cylinder;
  final WalletData wallet;
  final VoidCallback onTap;
  final ValueChanged<CylinderState> onState;
  final VoidCallback onReminder;

  @override
  Widget build(BuildContext context) {
    final supplier = _firstOrNull(
      wallet.suppliers.where((value) => value.id == cylinder.supplierId),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: WalletColors.blueSoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.propane_tank,
                      color: WalletColors.blue,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cylinder.nickname,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          <String>[
                            cylinder.gasType,
                            if (cylinder.capacityValue != null)
                              '${formatDecimal(cylinder.capacityValue!)} ${capacityUnitLabel(cylinder.capacityUnit ?? '')}'
                                  .trim(),
                            if (supplier != null) supplier.name,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(cylinder),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: WalletColors.muted),
                ],
              ),
            ),
          ),
          if (cylinder.consumesCurrentSlot) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: _CylinderStateActions(
                state: cylinder.state,
                onChanged: onState,
                onReminder: onReminder,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CylinderStateActions extends StatelessWidget {
  const _CylinderStateActions({
    required this.state,
    required this.onChanged,
    this.onReminder,
  });

  final CylinderState state;
  final ValueChanged<CylinderState> onChanged;
  final VoidCallback? onReminder;

  @override
  Widget build(BuildContext context) {
    final actions = switch (state) {
      CylinderState.ready => const <(CylinderState, String)>[
        (CylinderState.low, 'Low'),
        (CylinderState.empty, 'Empty'),
        (CylinderState.away, 'Away'),
      ],
      CylinderState.low => const <(CylinderState, String)>[
        (CylinderState.ready, 'Ready'),
        (CylinderState.empty, 'Empty'),
        (CylinderState.away, 'Away'),
      ],
      CylinderState.empty => const <(CylinderState, String)>[
        (CylinderState.ready, 'Ready'),
        (CylinderState.away, 'Away'),
      ],
      CylinderState.away => const <(CylinderState, String)>[
        (CylinderState.ready, 'Ready'),
        (CylinderState.empty, 'Empty'),
      ],
    };
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 2,
      children: [
        for (final action in actions)
          TextButton(
            onPressed: () => onChanged(action.$1),
            child: Text(action.$2),
          ),
        if (state != CylinderState.ready && onReminder != null)
          TextButton(onPressed: onReminder, child: const Text('Reminder')),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.cylinder);
  final Cylinder cylinder;

  @override
  Widget build(BuildContext context) {
    late final (String, Color, Color) status;
    if (cylinder.consumesCurrentSlot) {
      status = switch (cylinder.state) {
        CylinderState.ready => (
          'READY',
          WalletColors.green,
          WalletColors.greenSoft,
        ),
        CylinderState.low => (
          'LOW',
          WalletColors.amber,
          WalletColors.amberSoft,
        ),
        CylinderState.empty => (
          'EMPTY',
          WalletColors.danger,
          const Color(0xFFFFECEC),
        ),
        CylinderState.away => (
          'AWAY',
          WalletColors.violet,
          WalletColors.violetSoft,
        ),
      };
    } else {
      status = switch (cylinder.lifecycle) {
        CylinderLifecycle.returned => (
          'RETURNED',
          WalletColors.muted,
          WalletColors.background,
        ),
        CylinderLifecycle.archived => (
          'ARCHIVED',
          WalletColors.muted,
          WalletColors.background,
        ),
        CylinderLifecycle.active || CylinderLifecycle.exchanged => (
          'READY',
          WalletColors.green,
          WalletColors.greenSoft,
        ),
      };
    }
    final (label, color, soft) = status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: WalletColors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.05,
    ),
  );
}

class _ActivityScreen extends StatelessWidget {
  const _ActivityScreen({required this.wallet});
  final WalletData wallet;

  @override
  Widget build(BuildContext context) {
    final events = wallet.events.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return _ScreenFrame(
      title: 'History',
      subtitle: 'Cylinder activity in one permanent timeline.',
      child: events.isEmpty
          ? const _EmptyCard(
              icon: Icons.receipt_long_outlined,
              title: 'No history yet',
              body: 'Cylinder actions will appear here.',
            )
          : Column(
              children: events
                  .map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _EventCard(event: event, wallet: wallet),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.wallet});
  final CylinderEvent event;
  final WalletData wallet;

  @override
  Widget build(BuildContext context) {
    final cylinder = _firstOrNull(
      wallet.cylinders.where((value) => value.id == event.cylinderId),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: WalletColors.blueSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                eventIcon(event.type),
                color: WalletColors.blue,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eventLabel(event.type),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cylinder?.nickname ?? 'Deleted cylinder'} · ${formatDateTime(event.occurredAt, wallet)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (event.note != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      event.note!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            if (event.amount != null)
              Text(
                formatMoney(event.amount!, wallet),
                style: Theme.of(context).textTheme.titleMedium,
              ),
          ],
        ),
      ),
    );
  }
}

class _RemindersScreen extends StatelessWidget {
  const _RemindersScreen({
    required this.wallet,
    required this.onAdd,
    required this.onComplete,
    required this.onDelete,
  });
  final WalletData wallet;
  final VoidCallback onAdd;
  final ValueChanged<String> onComplete;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final reminders = wallet.reminders.toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return _ScreenFrame(
      title: 'Reminders',
      subtitle: 'Keep rental, refill and return dates in view.',
      trailing: FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_alert),
        label: const Text('Add'),
      ),
      child: reminders.isEmpty
          ? _EmptyCard(
              icon: Icons.notifications_none,
              title: 'Nothing scheduled',
              body: 'Create a reminder for a refill, rental payment or safety check.',
              action: 'Create reminder',
              onAction: onAdd,
            )
          : Column(
              children: reminders.map((reminder) {
                final cylinder = _firstOrNull(
                  wallet.cylinders.where(
                    (value) => value.id == reminder.cylinderId,
                  ),
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                      child: Row(
                        children: [
                          Checkbox(
                            value: reminder.completed,
                            onChanged: reminder.completed
                                ? null
                                : (_) => onComplete(reminder.id),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reminder.title,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        decoration: reminder.completed
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                ),
                                Text(
                                  '${cylinder?.nickname ?? 'Cylinder'} · ${formatDateTime(reminder.dueAt, wallet)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete reminder',
                            onPressed: () => onDelete(reminder.id),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen({
    required this.wallet,
    required this.onSuppliers,
    required this.onReminders,
    required this.onPro,
    required this.onReminderToggle,
    required this.onCurrency,
    required this.onMassUnit,
    required this.onVolumeUnit,
    required this.onBackup,
    required this.onRestore,
    required this.onDelete,
    required this.onFreeRecords,
  });
  final WalletData wallet;
  final VoidCallback onSuppliers;
  final VoidCallback onReminders;
  final VoidCallback onPro;
  final ValueChanged<bool> onReminderToggle;
  final ValueChanged<String> onCurrency;
  final ValueChanged<String> onMassUnit;
  final ValueChanged<String> onVolumeUnit;
  final Future<bool> Function() onBackup;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final VoidCallback onFreeRecords;

  @override
  Widget build(BuildContext context) {
    final isPro = wallet.entitlementCache.isProAt(DateTime.now().toUtc());
    final currentCount = wallet.cylinders
        .where((value) => value.consumesCurrentSlot)
        .length;
    final needsFreeChoice = !isPro && currentCount > freeEditableCylinderLimit;
    return _ScreenFrame(
      title: 'Settings',
      subtitle: 'Preferences, suppliers, privacy and plan controls.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: WalletColors.ink,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.workspace_premium,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPro ? 'Welding Gas Wallet Pro' : 'Free plan',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPro
                              ? 'Unlimited cylinders'
                              : 'Up to 3 current cylinders',
                          style: const TextStyle(color: Color(0xFFBFC9D7)),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onPro,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(isPro ? 'Manage' : 'Upgrade'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionLabel('WALLET SETUP'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.store_outlined),
                title: const Text('Suppliers'),
                subtitle: Text('${wallet.suppliers.length} saved'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onSuppliers,
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Reminders'),
                subtitle: Text('${wallet.reminders.length} saved'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onReminders,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Device alerts'),
                subtitle: const Text('Use local notifications for due dates'),
                value: wallet.settings.remindersEnabled,
                onChanged: onReminderToggle,
              ),
              if (needsFreeChoice)
                ListTile(
                  leading: const Icon(Icons.checklist_outlined),
                  title: const Text('Free cylinders'),
                  subtitle: const Text('Choose the three editable cylinders'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onFreeRecords,
                ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionLabel('CURRENCY & UNITS'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Default currency'),
                trailing: DropdownButton<String>(
                  value:
                      <String>{
                        'USD',
                        'EUR',
                        'GBP',
                        'CAD',
                        'AUD',
                        'INR',
                        'CNY',
                      }.contains(wallet.settings.currencyCode)
                      ? wallet.settings.currencyCode
                      : 'USD',
                  underline: const SizedBox.shrink(),
                  items: const ['USD', 'EUR', 'GBP', 'CAD', 'AUD', 'INR', 'CNY']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onCurrency(value);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.scale_outlined),
                title: const Text('Mass'),
                trailing: DropdownButton<String>(
                  value: wallet.settings.defaultMassUnit,
                  underline: const SizedBox.shrink(),
                  items: const ['kg', 'lb']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onMassUnit(value);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.straighten_outlined),
                title: const Text('Volume'),
                trailing: DropdownButton<String>(
                  value: wallet.settings.defaultVolumeUnit,
                  underline: const SizedBox.shrink(),
                  items: const ['L', 'm3', 'ft3']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(capacityUnitLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onVolumeUnit(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionLabel('BACKUP'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Backup'),
                subtitle: Text(
                  Platform.isIOS
                      ? 'Files or iCloud Drive'
                      : 'Files or Google Drive',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onBackup,
              ),
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('Restore'),
                subtitle: const Text('Preview before replacing this wallet'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onRestore,
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Delete wallet'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionLabel('LEGAL & SUPPORT'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _LinkTile(label: 'Privacy policy', path: 'privacy'),
              _LinkTile(label: 'Terms of use', path: 'terms'),
              _LinkTile(label: 'Safety disclaimer', path: 'disclaimer'),
              _LinkTile(label: 'Support', path: 'support'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.label, required this.path});
  final String label;
  final String path;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.open_in_new),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => launchUrl(
      Uri.parse(
        'https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/$path/',
      ),
      mode: LaunchMode.externalApplication,
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1)
            const Divider(height: 1, indent: 56, color: WalletColors.border),
        ],
      ],
    ),
  );
}

class _ScreenFrame extends StatelessWidget {
  const _ScreenFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
            const SizedBox(height: 28),
            child,
          ],
        ),
      ),
    ),
  );
}

class _OnboardingScreen extends StatefulWidget {
  const _OnboardingScreen({required this.onContinue});
  final Future<bool> Function() onContinue;

  @override
  State<_OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<_OnboardingScreen> {
  bool accepted = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 36),
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: WalletColors.blue,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.propane_tank,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Your welding gas cylinders. One simple wallet.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Welding Gas Wallet keeps your cylinder records on this device.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 26),
                const _FeatureLine(
                  icon: Icons.lock_outline,
                  title: 'Private by default',
                  body: 'Wallet data stays in app storage unless you export a backup.',
                ),
                const _FeatureLine(
                  icon: Icons.offline_bolt_outlined,
                  title: 'Works offline',
                  body: 'Core records do not require an account or network connection.',
                ),
                const _FeatureLine(
                  icon: Icons.notifications_active_outlined,
                  title: 'Useful due dates',
                  body: 'Optional local reminders help with refills, rentals and returns.',
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: const [
                            _LegalButton(label: 'Privacy', path: 'privacy'),
                            _LegalButton(label: 'Terms', path: 'terms'),
                            _LegalButton(label: 'Safety', path: 'disclaimer'),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Free includes up to three current editable cylinders.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        CheckboxListTile(
                          value: accepted,
                          onChanged: (value) =>
                              setState(() => accepted = value ?? false),
                          title: const Text('I accept'),
                          subtitle: const Text(
                            'Record wallet only—not safety or compliance advice.',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: accepted ? widget.onContinue : null,
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _LegalButton extends StatelessWidget {
  const _LegalButton({required this.label, required this.path});
  final String label;
  final String path;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => launchUrl(
      Uri.parse(
        'https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/$path/',
      ),
      mode: LaunchMode.externalApplication,
    ),
    child: Text(label),
  );
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: WalletColors.blue),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(body, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> _openAddCylinder(
  BuildContext context,
  AppController controller,
) async {
  final draft = await showModalBottomSheet<AddCylinderDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddCylinderSheet(controller: controller),
  );
  if (draft == null) return;
  final result = await controller.addCylinder(draft);
  if (!context.mounted || result == null || result.wasAdded) return;
  await _openPaywall(context, controller);
}

Future<void> _openRecord(
  BuildContext context,
  AppController controller,
  CylinderEventType type, {
  Cylinder? target,
}) async {
  final cylinder = target ?? await _chooseCylinder(context, controller.wallet!);
  if (!context.mounted || cylinder == null) return;
  final result = await showModalBottomSheet<_RecordDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RecordSheet(
      wallet: controller.wallet!,
      cylinder: cylinder,
      type: type,
    ),
  );
  if (result == null) return;
  await controller.run(
    () async {
      if (type == CylinderEventType.refill) {
        await controller.engine.recordRefill(
          cylinder.id,
          amount: result.amount,
          supplierId: result.supplierId,
          note: result.note,
        );
      } else {
        await controller.engine.recordExchange(
          cylinder.id,
          amount: result.amount,
          supplierId: result.supplierId,
          newSerialNumber: result.serialNumber,
          note: result.note,
        );
      }
    },
    success: type == CylinderEventType.refill
        ? 'Refill recorded.'
        : 'Exchange recorded.',
  );
}

Future<void> _openReminder(
  BuildContext context,
  AppController controller, {
  Cylinder? target,
}) async {
  final cylinder = target ?? await _chooseCylinder(context, controller.wallet!);
  if (!context.mounted || cylinder == null) return;
  final draft = await showModalBottomSheet<_ReminderDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReminderSheet(cylinder: cylinder),
  );
  if (draft == null) return;
  await controller.run(() async {
    await controller.createReminder(
      cylinderId: cylinder.id,
      kind: draft.kind,
      title: draft.title,
      dueAt: draft.dueAt,
    );
  }, success: 'Reminder created.');
}

Future<Cylinder?> _chooseCylinder(
  BuildContext context,
  WalletData wallet,
) async {
  final current = wallet.cylinders
      .where((value) => value.consumesCurrentSlot)
      .toList();
  if (current.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Add a cylinder first.')));
    return null;
  }
  if (current.length == 1) return current.first;
  return showModalBottomSheet<Cylinder>(
    context: context,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHeader(title: 'Choose a cylinder'),
          const SizedBox(height: 12),
          ...current.map(
            (cylinder) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.propane_tank)),
              title: Text(cylinder.nickname),
              subtitle: Text(cylinder.gasType),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, cylinder),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _openCylinder(
  BuildContext context,
  AppController controller,
  Cylinder cylinder,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _CylinderSheet(controller: controller, cylinderId: cylinder.id),
  );
}

Future<void> _openReminders(
  BuildContext context,
  AppController controller,
) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: SafeArea(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _RemindersScreen(
              wallet: controller.wallet!,
              onAdd: () => _openReminder(context, controller),
              onComplete: (id) => controller.run(
                () => controller.completeReminder(id),
                success: 'Reminder completed.',
              ),
              onDelete: (id) => controller.run(
                () => controller.deleteReminder(id),
                success: 'Reminder deleted.',
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSuppliers(
  BuildContext context,
  AppController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SuppliersSheet(controller: controller),
  );
}

Future<void> _openPaywall(
  BuildContext context,
  AppController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PaywallSheet(controller: controller),
  );
}

Future<void> _restoreBackup(
  BuildContext context,
  AppController controller,
) async {
  final backup = await controller.chooseBackup();
  if (!context.mounted || backup == null) return;
  final preview = backup.preview;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Restore backup?'),
      content: Text(
        '${preview.cylinders.length} cylinder · '
        '${preview.reminders.length} reminder\n\n'
        'This replaces the wallet on this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.restoreBackup(backup);
}

Future<void> _deleteWallet(
  BuildContext context,
  AppController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete wallet?'),
      content: const Text(
        'All local cylinder records and reminders will be removed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.deleteAllData();
}

Future<void> _openFreeRecordPicker(
  BuildContext context,
  AppController controller,
) async {
  final wallet = controller.wallet!;
  final cylinders = wallet.cylinders
      .where((value) => value.consumesCurrentSlot)
      .toList();
  final chosen = <String>{
    ...(wallet.freeEditableSelection.isEmpty
        ? cylinders.take(freeEditableCylinderLimit).map((value) => value.id)
        : wallet.freeEditableSelection),
  };
  final selection = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            const Center(child: _Grabber()),
            const SizedBox(height: 18),
            const _SheetHeader(
              title: 'Free cylinders',
              subtitle: 'Choose up to three editable cylinders.',
            ),
            const SizedBox(height: 16),
            ...cylinders.map(
              (value) => CheckboxListTile(
                value: chosen.contains(value.id),
                title: Text(value.nickname),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (checked) {
                  setState(() {
                    if (checked == true &&
                        chosen.length < freeEditableCylinderLimit) {
                      chosen.add(value.id);
                    } else if (checked != true) {
                      chosen.remove(value.id);
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen.toList()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
  if (selection == null) return;
  await controller.run(
    () => controller.engine.selectFreeEditable(selection),
    success: 'Free cylinders updated.',
  );
}

class _SupplierField extends StatelessWidget {
  const _SupplierField({
    required this.suppliers,
    required this.supplierId,
    required this.onChanged,
    required this.onAdd,
  });

  final List<Supplier> suppliers;
  final String? supplierId;
  final ValueChanged<String?> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: DropdownButtonFormField<String?>(
          key: ValueKey(supplierId),
          initialValue: supplierId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Supplier (optional)'),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem(value: null, child: Text('None')),
            ...suppliers.map(
              (value) => DropdownMenuItem(
                value: value.id,
                child: Text(value.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        tooltip: 'Add supplier',
        onPressed: onAdd,
        icon: const Icon(Icons.add),
      ),
    ],
  );
}

Future<Supplier?> _quickCreateSupplier(
  BuildContext context,
  AppController controller,
) async {
  final name = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add supplier'),
      content: TextField(
        controller: name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isNotEmpty) {
              Navigator.pop(context, name.text.trim());
            }
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
  name.dispose();
  if (value == null) return null;
  Supplier? created;
  final saved = await controller.run(() async {
    created = await controller.engine.createSupplier(value);
  });
  return saved ? created : null;
}

class _AddCylinderSheet extends StatefulWidget {
  const _AddCylinderSheet({required this.controller});
  final AppController controller;

  @override
  State<_AddCylinderSheet> createState() => _AddCylinderSheetState();
}

class _AddCylinderSheetState extends State<_AddCylinderSheet> {
  final name = TextEditingController();
  final capacity = TextEditingController();
  final serial = TextEditingController();
  String gas = 'Argon';
  late String capacityUnit;
  RelationshipType relationship = RelationshipType.owned;
  String? supplierId;
  String? formError;

  @override
  void initState() {
    super.initState();
    capacityUnit = widget.controller.wallet!.settings.defaultVolumeUnit;
  }

  @override
  void dispose() {
    name.dispose();
    capacity.dispose();
    serial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
    title: 'Add cylinder',
    subtitle: 'Choose the gas. Everything else is optional.',
    action: 'Save',
    onAction: () {
      final capacityText = capacity.text.trim();
      final parsedCapacity = capacityText.isEmpty
          ? null
          : double.tryParse(capacityText.replaceAll(',', '.'));
      final normalizedCode = serial.text.trim().toLowerCase();
      final duplicateCode =
          normalizedCode.isNotEmpty &&
          widget.controller.wallet!.cylinders.any(
            (value) =>
                value.serialNumber?.trim().toLowerCase() == normalizedCode,
          );
      final error = capacityText.isNotEmpty &&
              (parsedCapacity == null || parsedCapacity <= 0)
          ? 'Check capacity.'
          : duplicateCode
          ? 'Serial already saved.'
          : null;
      if (error != null) {
        setState(() => formError = error);
        return;
      }
      Navigator.pop(
        context,
        AddCylinderDraft(
          nickname: name.text,
          gasType: gas,
          relationship: relationship,
          capacityValue: parsedCapacity,
          capacityUnit: parsedCapacity == null ? null : capacityUnit,
          serialNumber: serial.text,
          supplierId: supplierId,
        ),
      );
    },
    children: [
      if (formError != null) ...[
        _InlineError(formError!),
        const SizedBox(height: 12),
      ],
      DropdownButtonFormField<String>(
        initialValue: gas,
        decoration: const InputDecoration(labelText: 'Gas'),
        items:
            const [
                  'Argon',
                  'CO₂',
                  'Oxygen',
                  'Acetylene',
                  'Nitrogen',
                  'Helium',
                  'Mixed gas',
                ]
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
        onChanged: (value) => setState(() => gas = value ?? gas),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: capacity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Capacity',
                hintText: '80',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: capacityUnit,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: const ['ft3', 'L', 'm3', 'kg', 'lb']
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(capacityUnitLabel(value)),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => capacityUnit = value ?? capacityUnit),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      TextField(
        controller: name,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Name (optional)',
          helperText: 'Uses gas and size when blank.',
        ),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<RelationshipType>(
        initialValue: relationship,
        decoration: const InputDecoration(labelText: 'Ownership'),
        items: RelationshipType.values
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(relationshipLabel(value)),
              ),
            )
            .toList(),
        onChanged: (value) =>
            setState(() => relationship = value ?? relationship),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: serial,
        decoration: const InputDecoration(labelText: 'Serial (optional)'),
      ),
      const SizedBox(height: 14),
      _SupplierField(
        suppliers: widget.controller.wallet!.suppliers,
        supplierId: supplierId,
        onChanged: (value) => setState(() => supplierId = value),
        onAdd: () async {
          final supplier = await _quickCreateSupplier(
            context,
            widget.controller,
          );
          if (mounted && supplier != null) {
            setState(() => supplierId = supplier.id);
          }
        },
      ),
    ],
  );
}

class _RecordDraft {
  const _RecordDraft({
    this.amount,
    this.supplierId,
    this.serialNumber,
    this.note,
  });
  final Money? amount;
  final String? supplierId;
  final String? serialNumber;
  final String? note;
}

class _RecordSheet extends StatefulWidget {
  const _RecordSheet({
    required this.wallet,
    required this.cylinder,
    required this.type,
  });
  final WalletData wallet;
  final Cylinder cylinder;
  final CylinderEventType type;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  final amount = TextEditingController();
  final serial = TextEditingController();
  final note = TextEditingController();
  String? supplierId;
  String? formError;

  @override
  void dispose() {
    amount.dispose();
    serial.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRefill = widget.type == CylinderEventType.refill;
    return _FormSheet(
      title: isRefill ? 'Record refill' : 'Record exchange',
      subtitle: widget.cylinder.nickname,
      action: isRefill ? 'Save refill' : 'Save exchange',
      onAction: () {
        final amountText = amount.text.trim();
        final parsed = amountText.isEmpty
            ? null
            : double.tryParse(amountText.replaceAll(',', '.'));
        if (amountText.isNotEmpty && (parsed == null || parsed < 0)) {
          setState(() => formError = 'Check cost.');
          return;
        }
        final normalizedSerial = serial.text.trim().toLowerCase();
        if (!isRefill &&
            normalizedSerial.isNotEmpty &&
            (widget.wallet.cylinders.any(
              (value) =>
                  value.id != widget.cylinder.id &&
                  value.serialNumber?.trim().toLowerCase() == normalizedSerial,
            ))) {
          setState(() => formError = 'Serial already saved.');
          return;
        }
        Navigator.pop(
          context,
          _RecordDraft(
            amount: parsed == null
                ? null
                : Money(
                    minorUnits: (parsed * 100).round(),
                    currencyCode: widget.wallet.settings.currencyCode,
                  ),
            supplierId: supplierId,
            serialNumber: isRefill ? null : serial.text,
            note: note.text,
          ),
        );
      },
      children: [
        if (formError != null) ...[
          _InlineError(formError!),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Cost (${widget.wallet.settings.currencyCode})',
            hintText: '0.00',
          ),
        ),
        if (!isRefill) ...[
          const SizedBox(height: 14),
          TextField(
            controller: serial,
            decoration: const InputDecoration(
              labelText: 'New serial (optional)',
              helperText: 'Leave blank if the replacement serial is unknown.',
            ),
          ),
        ],
        if (widget.wallet.suppliers.isNotEmpty) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            initialValue: supplierId,
            decoration: const InputDecoration(labelText: 'Supplier'),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem(value: null, child: Text('No supplier')),
              ...widget.wallet.suppliers.map(
                (value) =>
                    DropdownMenuItem(value: value.id, child: Text(value.name)),
              ),
            ],
            onChanged: (value) => setState(() => supplierId = value),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
      ],
    );
  }
}

class _ReminderDraft {
  const _ReminderDraft({
    required this.kind,
    required this.title,
    required this.dueAt,
  });
  final ReminderKind kind;
  final String title;
  final DateTime dueAt;
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({required this.cylinder});
  final Cylinder cylinder;

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  final title = TextEditingController(text: 'Check cylinder');
  ReminderKind kind = ReminderKind.check;
  late DateTime dueAt = DateTime.now().add(const Duration(days: 7));

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
    title: 'Create reminder',
    subtitle: widget.cylinder.nickname,
    action: 'Save reminder',
    onAction: () => Navigator.pop(
      context,
      _ReminderDraft(kind: kind, title: title.text, dueAt: dueAt),
    ),
    children: [
      TextField(
        controller: title,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Reminder title'),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<ReminderKind>(
        initialValue: kind,
        decoration: const InputDecoration(labelText: 'Type'),
        items: ReminderKind.values
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(reminderKindLabel(value)),
              ),
            )
            .toList(),
        onChanged: (value) => setState(() => kind = value ?? kind),
      ),
      const SizedBox(height: 14),
      Card(
        child: ListTile(
          leading: const Icon(Icons.event_outlined),
          title: const Text('Due date'),
          subtitle: Text(DateFormat.yMMMd().add_jm().format(dueAt)),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: dueAt,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 3650)),
            );
            if (!context.mounted || date == null) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(dueAt),
            );
            if (!context.mounted || time == null) return;
            setState(() {
              dueAt = DateTime(
                date.year,
                date.month,
                date.day,
                time.hour,
                time.minute,
              );
            });
          },
        ),
      ),
    ],
  );
}

class _CylinderSheet extends StatelessWidget {
  const _CylinderSheet({required this.controller, required this.cylinderId});
  final AppController controller;
  final String cylinderId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final wallet = controller.wallet!;
      final cylinder = _firstOrNull(
        wallet.cylinders.where((value) => value.id == cylinderId),
      );
      if (cylinder == null) return const SizedBox.shrink();
      final events =
          wallet.events
              .where((value) => value.cylinderId == cylinderId)
              .toList()
            ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      final totals = controller.engine.spendByCurrency(
        wallet,
        cylinderId: cylinderId,
      );
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.55,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            const Center(child: _Grabber()),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: WalletColors.blueSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.propane_tank,
                    color: WalletColors.blue,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cylinder.nickname,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        '${cylinder.gasType} · ${relationshipLabel(cylinder.relationship)}',
                      ),
                    ],
                  ),
                ),
                _StatusPill(cylinder),
              ],
            ),
            if (cylinder.consumesCurrentSlot) ...[
              const SizedBox(height: 18),
              const _SectionLabel('STATUS'),
              const SizedBox(height: 6),
              _CylinderStateActions(
                state: cylinder.state,
                onChanged: (state) {
                  unawaited(
                    controller.run(
                      () => controller.engine.changeCylinderState(
                        cylinder.id,
                        state,
                      ),
                      success: '${cylinderStateLabel(state)}.',
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final spend = totals.entries
                    .map(
                      (entry) => formatMoney(
                        Money(minorUnits: entry.value, currencyCode: entry.key),
                        wallet,
                      ),
                    )
                    .join(' + ');
                return Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'CAPACITY',
                        value: cylinder.capacityValue == null
                            ? '—'
                            : '${formatDecimal(cylinder.capacityValue!)} ${capacityUnitLabel(cylinder.capacityUnit ?? '')}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        label: 'SPEND',
                        value: spend.isEmpty ? '—' : spend,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            const _SectionLabel('ACTIONS'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: cylinder.consumesCurrentSlot
                      ? () => _openRecord(
                          context,
                          controller,
                          CylinderEventType.refill,
                          target: cylinder,
                        )
                      : null,
                  icon: const Icon(Icons.local_gas_station_outlined),
                  label: const Text('Refill'),
                ),
                OutlinedButton.icon(
                  onPressed: cylinder.consumesCurrentSlot
                      ? () => _openRecord(
                          context,
                          controller,
                          CylinderEventType.exchange,
                          target: cylinder,
                        )
                      : null,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Exchange'),
                ),
                OutlinedButton.icon(
                  onPressed: cylinder.consumesCurrentSlot
                      ? () =>
                            _openReminder(context, controller, target: cylinder)
                      : null,
                  icon: const Icon(Icons.add_alert),
                  label: const Text('Reminder'),
                ),
                OutlinedButton.icon(
                  onPressed: cylinder.consumesCurrentSlot
                      ? () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Mark cylinder returned?'),
                              content: const Text(
                                'The record and its cost history will remain available.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Mark returned'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await controller.run(
                              () => controller.engine.markReturned(cylinder.id),
                              success: 'Cylinder marked returned.',
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Return'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionLabel('HISTORY'),
            const SizedBox(height: 10),
            if (events.isEmpty)
              const _EmptyCard(
                icon: Icons.history,
                title: 'No history',
                body: 'Actions for this cylinder will appear here.',
              )
            else
              ...events.map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _EventCard(event: event, wallet: wallet),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: WalletColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}

class _SuppliersSheet extends StatelessWidget {
  const _SuppliersSheet({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final suppliers = controller.wallet!.suppliers;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.84,
        minChildSize: 0.5,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            const Center(child: _Grabber()),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Suppliers',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _createSupplier(context, controller),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Names used by cylinder records and cost history.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            if (suppliers.isEmpty)
              _EmptyCard(
                icon: Icons.store_outlined,
                title: 'No suppliers saved',
                body: 'Add a gas supplier to attach it to cylinders and costs.',
                action: 'Add supplier',
                onAction: () => _createSupplier(context, controller),
              )
            else
              ...suppliers.map(
                (supplier) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.store_outlined),
                      ),
                      title: Text(supplier.name),
                      subtitle: supplier.notes == null
                          ? null
                          : Text(supplier.notes!),
                      trailing: IconButton(
                        tooltip: 'Delete supplier',
                        onPressed: () => controller.run(
                          () => controller.engine.deleteSupplier(supplier.id),
                          success: 'Supplier deleted.',
                        ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

Future<void> _createSupplier(
  BuildContext context,
  AppController controller,
) async {
  final name = TextEditingController();
  final notes = TextEditingController();
  String? validationError;
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: validationError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final cleaned = name.text.trim();
              final duplicate = controller.wallet!.suppliers.any(
                (value) => value.name.toLowerCase() == cleaned.toLowerCase(),
              );
              if (cleaned.isEmpty || duplicate) {
                setDialogState(
                  () => validationError = cleaned.isEmpty
                      ? 'Enter a name.'
                      : 'Already saved.',
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Add supplier'),
          ),
        ],
      ),
    ),
  );
  if (submitted == true) {
    await controller.run(() async {
      await controller.engine.createSupplier(name.text, notes: notes.text);
    }, success: 'Supplier added.');
  }
  name.dispose();
  notes.dispose();
}

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet({required this.controller});
  final AppController controller;

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  late final Future<List<ProductDetails>> products = widget.controller
      .products();

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.82,
    minChildSize: 0.56,
    builder: (context, scrollController) => ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      children: [
        const Center(child: _Grabber()),
        const SizedBox(height: 22),
        Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WalletColors.violetSoft,
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(
            Icons.workspace_premium,
            color: WalletColors.violet,
            size: 32,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Pro: unlimited cylinder records',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          Platform.isIOS ? 'One purchase. Every record stays editable.' : 'Unlimited while Pro is active. Saved history remains if Pro ends.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        const _FeatureLine(
          icon: Icons.all_inclusive,
          title: 'Unlimited records',
          body: 'Add and edit every active cylinder.',
        ),
        const _FeatureLine(
          icon: Icons.lock_outline,
          title: 'No account required',
          body: 'Your wallet remains local to this device.',
        ),
        FutureBuilder<List<ProductDetails>>(
          future: products,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final values = snapshot.data ?? const <ProductDetails>[];
            if (values.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Store plans are unavailable right now. No access has been granted.',
                  ),
                ),
              );
            }
            values.sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
            return Column(
              children: values
                  .map(
                    (product) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => widget.controller.purchase(product),
                          child: Text(_paywallProductLabel(product)),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: widget.controller.restorePurchases,
          child: const Text('Restore purchases'),
        ),
        if (!Platform.isIOS)
          TextButton(
            onPressed: widget.controller.openPurchaseManagement,
            child: const Text('Manage subscription'),
          ),
        const SizedBox(height: 6),
        Text(
          Platform.isIOS
              ? 'One-time purchase charged to your Apple Account. No subscription or automatic renewal.'
              : 'Payment is charged by Google Play. Subscriptions renew automatically unless cancelled before renewal; access continues through the paid period after cancellation.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        const Wrap(
          alignment: WrapAlignment.center,
          children: [
            _LegalButton(label: 'Terms of use', path: 'terms'),
            _LegalButton(label: 'Privacy policy', path: 'privacy'),
          ],
        ),
      ],
    ),
  );
}

String _paywallProductLabel(ProductDetails product) {
  if (Platform.isIOS) return 'Lifetime Pro · ${product.price} one time';
  return switch (product.id) {
    monthlyProductId => 'Monthly Pro · ${product.price} per month',
    annualProductId => 'Annual Pro · ${product.price} per year',
    _ => '${product.title} · ${product.price}',
  };
}

class _FormSheet extends StatelessWidget {
  const _FormSheet({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onAction,
    required this.children,
  });
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _Grabber()),
          const SizedBox(height: 18),
          _SheetHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 22),
          ...children,
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onAction, child: Text(action)),
          ),
        ],
      ),
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      if (subtitle != null) ...[
        const SizedBox(height: 5),
        Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ],
  );
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 4,
    decoration: BoxDecoration(
      color: WalletColors.border,
      borderRadius: BorderRadius.circular(99),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: WalletColors.blue, size: 34),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _MessageBar extends StatelessWidget {
  const _MessageBar({
    required this.message,
    required this.isError,
    required this.onClose,
  });
  final String message;
  final bool isError;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: isError ? const Color(0xFFFFE9EA) : WalletColors.greenSoft,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? WalletColors.danger : WalletColors.green,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: WalletColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close),
              tooltip: 'Close',
            ),
          ],
        ),
      ),
    ),
  );
}

class _FatalState extends StatelessWidget {
  const _FatalState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 44, color: WalletColors.danger),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

String relationshipLabel(RelationshipType value) => switch (value) {
  RelationshipType.owned => 'Owned',
  RelationshipType.rented => 'Rented',
  RelationshipType.leased => 'Leased',
  RelationshipType.deposit => 'Deposit',
  RelationshipType.notSure => 'Not sure',
};

String reminderKindLabel(ReminderKind value) => switch (value) {
  ReminderKind.refill => 'Refill',
  ReminderKind.rental => 'Rental payment',
  ReminderKind.lease => 'Lease payment',
  ReminderKind.deposit => 'Deposit',
  ReminderKind.check => 'Safety check',
  ReminderKind.custom => 'Custom',
};

String eventLabel(CylinderEventType type) => switch (type) {
  CylinderEventType.created => 'Cylinder added',
  CylinderEventType.acquisitionUpdated => 'Acquisition updated',
  CylinderEventType.cylinderUpdated => 'Cylinder updated',
  CylinderEventType.stateChanged => 'Status changed',
  CylinderEventType.refill => 'Refill recorded',
  CylinderEventType.exchange => 'Cylinder exchanged',
  CylinderEventType.purchase => 'Purchase recorded',
  CylinderEventType.rentalPayment => 'Rental payment',
  CylinderEventType.leasePayment => 'Lease payment',
  CylinderEventType.depositPaid => 'Deposit paid',
  CylinderEventType.depositReturned => 'Deposit returned',
  CylinderEventType.cost => 'Cost recorded',
  CylinderEventType.supplierChanged => 'Supplier changed',
  CylinderEventType.relationshipChanged => 'Ownership changed',
  CylinderEventType.note => 'Note added',
  CylinderEventType.photoAdded => 'Photo added',
  CylinderEventType.reminderCreated => 'Reminder created',
  CylinderEventType.reminderUpdated => 'Reminder updated',
  CylinderEventType.reminderCompleted => 'Reminder completed',
  CylinderEventType.reminderDeleted => 'Reminder deleted',
  CylinderEventType.returned => 'Cylinder returned',
  CylinderEventType.archived => 'Cylinder archived',
};

IconData eventIcon(CylinderEventType type) => switch (type) {
  CylinderEventType.refill => Icons.local_gas_station_outlined,
  CylinderEventType.exchange => Icons.swap_horiz,
  CylinderEventType.cost ||
  CylinderEventType.purchase ||
  CylinderEventType.rentalPayment ||
  CylinderEventType.leasePayment ||
  CylinderEventType.depositPaid ||
  CylinderEventType.depositReturned => Icons.payments_outlined,
  CylinderEventType.reminderCreated ||
  CylinderEventType.reminderUpdated ||
  CylinderEventType.reminderCompleted ||
  CylinderEventType.reminderDeleted => Icons.notifications_outlined,
  CylinderEventType.stateChanged => Icons.sync_alt,
  CylinderEventType.returned => Icons.assignment_return_outlined,
  CylinderEventType.archived => Icons.archive_outlined,
  _ => Icons.history,
};

String formatMoney(Money money, WalletData wallet) {
  final scale = <String>{'JPY', 'KRW', 'VND'}.contains(money.currencyCode)
      ? 0
      : 2;
  final amount = money.minorUnits / (scale == 0 ? 1 : 100);
  try {
    return NumberFormat.simpleCurrency(
      locale: wallet.settings.locale,
      name: money.currencyCode,
      decimalDigits: scale,
    ).format(amount);
  } catch (_) {
    return '${money.currencyCode} ${amount.toStringAsFixed(scale)}';
  }
}

String formatDateTime(DateTime value, WalletData wallet) {
  try {
    return DateFormat.yMMMd(wallet.settings.locale)
        .add_jm()
        .format(value.toLocal());
  } catch (_) {
    return DateFormat.yMMMd('en').add_jm().format(value.toLocal());
  }
}

String formatDecimal(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

T? _firstOrNull<T>(Iterable<T> values) => values.isEmpty ? null : values.first;
