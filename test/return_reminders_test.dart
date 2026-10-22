import 'package:app_5/features/sharing/return_reminders.dart';
import 'package:app_5/features/sharing/sharing_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var permission = true;
  var pending = <Map<String, dynamic>>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    permission = true;
    pending = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          if (call.method == 'requestNotificationsPermission') {
            return permission;
          }
          if (call.method == 'pendingNotificationRequests') return pending;
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('denied notifications do not schedule a return reminder', () async {
    permission = false;
    expect(
      await ReturnReminders().schedule(
        'home',
        'loan',
        'Drill',
        DateTime.now().add(const Duration(days: 1)),
      ),
      isFalse,
    );
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
  });
  test(
    'schedules at the due instant without overwriting an existing reminder',
    () async {
      pending = [
        {
          'id': 1,
          'title': 'Return',
          'body': 'Other item',
          'payload': 'home/other',
        },
      ];
      final due = DateTime.now().toUtc().add(const Duration(days: 1));
      expect(
        await ReturnReminders().schedule('home', 'loan', 'Drill', due),
        isTrue,
      );
      final arguments =
          calls.singleWhere((call) => call.method == 'zonedSchedule').arguments
              as Map;
      expect(arguments['id'], 2);
      expect(arguments['payload'], 'home/loan');
      expect(arguments['timeZoneName'], 'UTC');
    },
  );
  test(
    'cancels returned loans while keeping active and other household reminders',
    () async {
      pending = [
        {'id': 1, 'title': 'Return', 'body': '', 'payload': 'home/returned'},
        {'id': 2, 'title': 'Return', 'body': '', 'payload': 'home/active'},
        {'id': 3, 'title': 'Return', 'body': '', 'payload': 'other/loan'},
      ];
      final now = DateTime.now();
      await ReturnReminders().reconcile('home', [
        Loan(
          id: 'active',
          itemId: 'item',
          borrower: 'Alex',
          recordedBy: 'user',
          dueDate: now,
          borrowedAt: now,
        ),
      ]);
      final cancelled = calls.where((call) => call.method == 'cancel').toList();
      expect(cancelled, hasLength(1));
      expect((cancelled.single.arguments as Map)['id'], 1);
    },
  );
}
