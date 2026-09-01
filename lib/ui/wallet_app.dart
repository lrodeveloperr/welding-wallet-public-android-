import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../core/wallet_engine.dart';
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
      final localeName = widget.controller.wallet?.settings.locale ?? 'en';
      final parts = localeName.split('-');
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Welding Gas Wallet',
        theme: buildWalletTheme(),
        locale: Locale.fromSubtags(
          languageCode: parts.first,
          scriptCode: parts.length > 1 && parts[1].length == 4
              ? parts[1]
              : null,
        ),
        supportedLocales: supportedLocales.map((value) {
          final bits = value.split('-');
          return Locale.fromSubtags(
            languageCode: bits.first,
            scriptCode: bits.length > 1 ? bits[1] : null,
          );
        }),
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
  const _WalletShell({required this.controller, required this.wallet});
  final AppController controller;
  final WalletData wallet;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _DashboardScreen(
        wallet: wallet,
        onAdd: () => _openAddCylinder(context, controller),
        onRefill: () =>
            _openRecord(context, controller, CylinderEventType.refill),
        onExchange: () =>
            _openRecord(context, controller, CylinderEventType.exchange),
        onReminder: () => _openReminder(context, controller),
        onCylinder: (cylinder) => _openCylinder(context, controller, cylinder),
      ),
      _ActivityScreen(wallet: wallet),
      _RemindersScreen(
        wallet: wallet,
        onAdd: () => _openReminder(context, controller),
        onComplete: (id) => controller.run(
          () => controller.engine.completeReminder(id),
          success: 'Reminder completed.',
        ),
        onDelete: (id) => controller.run(
          () => controller.deleteReminder(id),
          success: 'Reminder deleted.',
        ),
      ),
      _SettingsScreen(
        wallet: wallet,
        onSuppliers: () => _openSuppliers(context, controller),
        onPro: () => _openPaywall(context, controller),
        onReminderToggle: (value) =>
            controller.run(() => controller.setRemindersEnabled(value)),
        onLocale: (value) => controller.run(
          () => controller.engine.updateSettings(locale: value),
        ),
        onCurrency: (value) => controller.run(
          () => controller.engine.updateSettings(currencyCode: value),
        ),
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
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Reminders',
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
    required this.onAdd,
    required this.onRefill,
    required this.onExchange,
    required this.onReminder,
    required this.onCylinder,
  });

  final WalletData wallet;
  final VoidCallback onAdd;
  final VoidCallback onRefill;
  final VoidCallback onExchange;
  final VoidCallback onReminder;
  final ValueChanged<Cylinder> onCylinder;

  @override
  Widget build(BuildContext context) {
    final current = wallet.cylinders
        .where((value) => value.consumesCurrentSlot)
        .toList();
    final dueSoon = wallet.reminders.where((value) {
      final remaining = value.dueAt.difference(DateTime.now().toUtc());
      return !value.completed && remaining.inDays <= 7 && !remaining.isNegative;
    }).length;
    final spend = WalletEngine(repository: _ReadOnlyRepository(wallet))
        .spendByCurrency(wallet);
    final formattedSpend = spend.isEmpty
        ? formatMoney(
            Money(minorUnits: 0, currencyCode: wallet.settings.currencyCode),
            wallet,
          )
        : spend.entries
              .take(2)
              .map(
                (entry) => formatMoney(
                  Money(minorUnits: entry.value, currencyCode: entry.key),
                  wallet,
                ),
              )
              .join(' + ');
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
                      'Welding Wallet Dashboard',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const _SectionLabel('QUICK ACTIONS'),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 720 ? 4 : 2;
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: columns == 4 ? 1.55 : 1.42,
                    children: [
                      _QuickAction(
                        label: 'Add cylinder',
                        caption: 'New record',
                        icon: Icons.add_circle_outline,
                        color: WalletColors.blue,
                        soft: WalletColors.blueSoft,
                        onTap: onAdd,
                      ),
                      _QuickAction(
                        label: 'Record refill',
                        caption: 'Track cost',
                        icon: Icons.local_gas_station_outlined,
                        color: WalletColors.green,
                        soft: WalletColors.greenSoft,
                        onTap: onRefill,
                      ),
                      _QuickAction(
                        label: 'Exchange',
                        caption: 'Swap cylinder',
                        icon: Icons.swap_horiz,
                        color: WalletColors.amber,
                        soft: WalletColors.amberSoft,
                        onTap: onExchange,
                      ),
                      _QuickAction(
                        label: 'Reminder',
                        caption: 'Plan ahead',
                        icon: Icons.notifications_active_outlined,
                        color: WalletColors.violet,
                        soft: WalletColors.violetSoft,
                        onTap: onReminder,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              const _SectionLabel('SUMMARY & COUNTS'),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final cards = <Widget>[
                    _SummaryCard(
                      label: 'CURRENT',
                      value: '${current.length}',
                      detail: current.length == 1 ? 'cylinder' : 'cylinders',
                      icon: Icons.inventory_2_outlined,
                      color: WalletColors.blue,
                    ),
                    _SummaryCard(
                      label: 'DUE SOON',
                      value: '$dueSoon',
                      detail: 'next 7 days',
                      icon: Icons.event_outlined,
                      color: WalletColors.amber,
                    ),
                    _SummaryCard(
                      label: 'RECORDED SPEND',
                      value: formattedSpend,
                      detail: 'all activity',
                      icon: Icons.payments_outlined,
                      color: WalletColors.green,
                    ),
                  ];
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: cards
                          .map(
                            (card) => Expanded(
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 12,
                                ),
                                child: card,
                              ),
                            ),
                          )
                          .toList(),
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 12),
                          Expanded(child: cards[1]),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, child: cards[2]),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  const Expanded(child: _SectionLabel('YOUR CYLINDERS')),
                  Text(
                    '${current.length} current',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (current.isEmpty)
                _EmptyCard(
                  icon: Icons.propane_tank_outlined,
                  title: 'No cylinders yet',
                  body: 'Add your first cylinder to track refills, exchanges, costs and return dates.',
                  action: 'Add cylinder',
                  onAction: onAdd,
                )
              else
                ...current.map(
                  (cylinder) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CylinderCard(
                      cylinder: cylinder,
                      wallet: wallet,
                      onTap: () => onCylinder(cylinder),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.caption,
    required this.icon,
    required this.color,
    required this.soft,
    required this.onTap,
  });
  final String label;
  final String caption;
  final IconData icon;
  final Color color;
  final Color soft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 3),
          Text(detail, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
  );
}

class _CylinderCard extends StatelessWidget {
  const _CylinderCard({
    required this.cylinder,
    required this.wallet,
    required this.onTap,
  });
  final Cylinder cylinder;
  final WalletData wallet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final supplier = _firstOrNull(
      wallet.suppliers.where((value) => value.id == cylinder.supplierId),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
                child: const Icon(Icons.propane_tank, color: WalletColors.blue),
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
                          '${formatDecimal(cylinder.capacityValue!)} ${cylinder.capacityUnit ?? ''}'
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
              _StatusPill(cylinder.lifecycle),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: WalletColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.lifecycle);
  final CylinderLifecycle lifecycle;

  @override
  Widget build(BuildContext context) {
    final (label, color, soft) = switch (lifecycle) {
      CylinderLifecycle.active => (
        'ACTIVE',
        WalletColors.green,
        WalletColors.greenSoft,
      ),
      CylinderLifecycle.exchanged => (
        'EXCHANGED',
        WalletColors.amber,
        WalletColors.amberSoft,
      ),
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
    };
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
          fontSize: 9,
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
      title: 'Activity',
      subtitle: 'A permanent timeline of cylinder changes and costs.',
      child: events.isEmpty
          ? const _EmptyCard(
              icon: Icons.receipt_long_outlined,
              title: 'No activity yet',
              body: 'Refills, exchanges, costs and reminders will appear here.',
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
    required this.onPro,
    required this.onReminderToggle,
    required this.onLocale,
    required this.onCurrency,
  });
  final WalletData wallet;
  final VoidCallback onSuppliers;
  final VoidCallback onPro;
  final ValueChanged<bool> onReminderToggle;
  final ValueChanged<String> onLocale;
  final ValueChanged<String> onCurrency;

  @override
  Widget build(BuildContext context) {
    final isPro = wallet.entitlementCache.isProAt(DateTime.now().toUtc());
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
                          isPro ? 'Welding Wallet Pro' : 'Free plan',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPro
                              ? 'All cylinders are editable.'
                              : 'Up to three current cylinders.',
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
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Device reminders'),
                subtitle: const Text('Use local notifications for due dates'),
                value: wallet.settings.remindersEnabled,
                onChanged: onReminderToggle,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionLabel('REGION & UNITS'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('Language'),
                trailing: DropdownButton<String>(
                  value:
                      const <String>{
                        'en',
                        'es',
                        'fr',
                        'de',
                        'ar',
                        'zh-Hans',
                      }.contains(wallet.settings.locale)
                      ? wallet.settings.locale
                      : 'en',
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'es', child: Text('Español')),
                    DropdownMenuItem(value: 'fr', child: Text('Français')),
                    DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'zh-Hans', child: Text('简体中文')),
                  ],
                  onChanged: (value) {
                    if (value != null) onLocale(value);
                  },
                ),
              ),
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
              _LinkTile(label: 'Data deletion', path: 'deletion'),
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
  bool privacy = false;
  bool terms = false;
  bool safety = false;

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
                  'Your cylinders. Clear costs. Fewer surprises.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Welding Gas Wallet keeps ownership, supplier, refill and return records on this device.',
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
                        CheckboxListTile(
                          value: privacy,
                          onChanged: (value) =>
                              setState(() => privacy = value ?? false),
                          title: const Text('I have read the privacy policy.'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        CheckboxListTile(
                          value: terms,
                          onChanged: (value) =>
                              setState(() => terms = value ?? false),
                          title: const Text('I agree to the terms of use.'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        CheckboxListTile(
                          value: safety,
                          onChanged: (value) =>
                              setState(() => safety = value ?? false),
                          title: const Text(
                            'I understand this app is not a cylinder safety system.',
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
                    onPressed: privacy && terms && safety
                        ? widget.onContinue
                        : null,
                    child: const Text('Create my wallet'),
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
  final wallet = controller.wallet!;
  final draft = await showModalBottomSheet<AddCylinderDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddCylinderSheet(wallet: wallet),
  );
  if (draft == null) return;
  final result = await controller.addCylinder(draft);
  if (!context.mounted || result == null || result.wasAdded) return;
  await _openPaywall(context, controller);
}

Future<void> _openRecord(
  BuildContext context,
  AppController controller,
  CylinderEventType type,
) async {
  final cylinder = await _chooseCylinder(context, controller.wallet!);
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
  AppController controller,
) async {
  final cylinder = await _chooseCylinder(context, controller.wallet!);
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

class _AddCylinderSheet extends StatefulWidget {
  const _AddCylinderSheet({required this.wallet});
  final WalletData wallet;

  @override
  State<_AddCylinderSheet> createState() => _AddCylinderSheetState();
}

class _AddCylinderSheetState extends State<_AddCylinderSheet> {
  final name = TextEditingController();
  final capacity = TextEditingController();
  final serial = TextEditingController();
  String gas = 'Argon';
  RelationshipType relationship = RelationshipType.owned;
  String? supplierId;

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
    subtitle: 'Start with the details you know. You can add costs later.',
    action: 'Save cylinder',
    onAction: () {
      Navigator.pop(
        context,
        AddCylinderDraft(
          nickname: name.text,
          gasType: gas,
          relationship: relationship,
          capacityValue: double.tryParse(capacity.text.replaceAll(',', '.')),
          capacityUnit: widget.wallet.settings.defaultMassUnit,
          serialNumber: serial.text,
          supplierId: supplierId,
        ),
      );
    },
    children: [
      TextField(
        controller: name,
        autofocus: true,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Cylinder name',
          hintText: 'Workshop argon',
        ),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: gas,
        decoration: const InputDecoration(labelText: 'Gas type'),
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
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: capacity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    'Capacity (${widget.wallet.settings.defaultMassUnit})',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: serial,
              decoration: const InputDecoration(labelText: 'Serial (optional)'),
            ),
          ),
        ],
      ),
      if (widget.wallet.suppliers.isNotEmpty) ...[
        const SizedBox(height: 14),
        DropdownButtonFormField<String?>(
          initialValue: supplierId,
          decoration: const InputDecoration(labelText: 'Supplier (optional)'),
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
    ],
  );
}

class _RecordDraft {
  const _RecordDraft({this.amount, this.supplierId, this.note});
  final Money? amount;
  final String? supplierId;
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
  final note = TextEditingController();
  String? supplierId;

  @override
  void dispose() {
    amount.dispose();
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
        final parsed = double.tryParse(amount.text.replaceAll(',', '.'));
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
            note: note.text,
          ),
        );
      },
      children: [
        TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Cost (${widget.wallet.settings.currencyCode})',
            hintText: '0.00',
          ),
        ),
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
            if (!mounted || date == null) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(dueAt),
            );
            if (!mounted || time == null) return;
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
                _StatusPill(cylinder.lifecycle),
              ],
            ),
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
                            : '${formatDecimal(cylinder.capacityValue!)} ${cylinder.capacityUnit ?? ''}',
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
                  onPressed: () => _openRecord(
                    context,
                    controller,
                    CylinderEventType.refill,
                  ),
                  icon: const Icon(Icons.local_gas_station_outlined),
                  label: const Text('Refill'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openRecord(
                    context,
                    controller,
                    CylinderEventType.exchange,
                  ),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Exchange'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openReminder(context, controller),
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
              fontSize: 10,
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
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add supplier'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
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
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Add supplier'),
        ),
      ],
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
          'Keep every cylinder editable',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Pro removes the three-current-cylinder editing limit. Existing history is always preserved, even if Pro ends.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        const _FeatureLine(
          icon: Icons.all_inclusive,
          title: 'Unlimited current cylinders',
          body: 'Add and edit every active, rented or exchanged cylinder.',
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
                          onPressed: () =>
                              widget.controller.billing.purchase(product),
                          child: Text('${product.title} · ${product.price}'),
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
          onPressed: widget.controller.billing.restore,
          child: const Text('Restore purchases'),
        ),
        TextButton(
          onPressed: widget.controller.billing.openManagement,
          child: const Text('Manage subscription'),
        ),
      ],
    ),
  );
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

class _ReadOnlyRepository implements WalletRepository {
  const _ReadOnlyRepository(this.data);
  final WalletData data;

  @override
  Future<WalletData> read() async => data;

  @override
  Future<void> purge() => throw UnsupportedError('read only');

  @override
  Future<void> replace(WalletData data) => throw UnsupportedError('read only');

  @override
  Future<WalletData> transact(WalletData Function(WalletData current) update) =>
      throw UnsupportedError('read only');
}
