import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_5/main.dart';

void main() {
  testWidgets('requires a name and adds an item with trimmed details', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('No items yet'), findsOneWidget);
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '   ');
    await tester.ensureVisible(find.text('Save item'));
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an item name'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '  Toolbox  ');
    await tester.enterText(find.byType(TextFormField).at(1), '  Tools  ');
    await tester.enterText(find.byType(TextFormField).at(2), '  Blue case  ');
    await tester.ensureVisible(find.text('Save item'));
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();
    expect(find.text('No items yet'), findsNothing);
    expect(find.text('Toolbox'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    await tester.tap(find.text('Toolbox'));
    await tester.pumpAndSettle();
    expect(find.text('Tools\n\nBlue case'), findsOneWidget);
  });

  testWidgets('back cancels without adding an item', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Unsaved');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('No items yet'), findsOneWidget);
    expect(find.text('Unsaved'), findsNothing);
  });
}
