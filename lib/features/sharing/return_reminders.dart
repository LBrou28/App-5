import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'sharing_repository.dart';

/// Device-local reminders: scheduling happens only after this device records a loan.
class ReturnReminders {
  static final instance = ReturnReminders();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  Future<bool> _initialize() async {
    if (!supported) return false;
    if (_ready) return true;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
    return true;
  }

  Future<bool> schedule(
    String householdId,
    String loanId,
    String itemName,
    DateTime due,
  ) async {
    if (!await _initialize()) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final allowed = android != null
        ? await android.requestNotificationsPermission()
        : await ios?.requestPermissions(alert: true, badge: true, sound: true);
    if (allowed != true || !due.isAfter(DateTime.now())) return false;
    final pending = await _plugin.pendingNotificationRequests();
    final used = pending.map((p) => p.id).toSet();
    var id = 1;
    while (used.contains(id)) {
      id++;
    }
    await _plugin.zonedSchedule(
      id,
      'Return reminder',
      '$itemName is due back.',
      tz.TZDateTime.from(due, tz.UTC),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'loan_returns',
          'Item returns',
          channelDescription: 'Reminders for borrowed household items',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: '$householdId/$loanId',
    );
    return true;
  }

  Future<void> reconcile(String householdId, List<Loan> loans) async {
    if (!await _initialize()) return;
    final active = loans
        .where((loan) => loan.active)
        .map((loan) => '$householdId/${loan.id}')
        .toSet();
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (pending.payload?.startsWith('$householdId/') == true &&
          !active.contains(pending.payload)) {
        await _plugin.cancel(pending.id);
      }
    }
  }

  Future<void> clear() async {
    if (await _initialize()) await _plugin.cancelAll();
  }
}
