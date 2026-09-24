import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:neo_note_pro/main.dart';

Future<NotesProvider> openEditor(WidgetTester tester, NoteType type) async {
  final state = NotesProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(home: NoteEditorScreen(initialType: type)),
    ),
  );
  await tester.pump();
  return state;
}

void main() {
  testWidgets(
    'Shopping removal preserves neighboring fields and undo restores row',
    (tester) async {
      await openEditor(tester, NoteType.shopping);
      Finder names() => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Item',
      );
      await tester.enterText(names().first, 'Apples');
      await tester.tap(find.text('Add item'));
      await tester.pump();
      await tester.enterText(names().last, 'Bread');
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));
      await tester.tap(find.byTooltip('Remove item').first);
      await tester.pump();
      expect(find.text('Apples'), findsNothing);
      expect(find.text('Bread'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(find.text('Apples'), findsNothing);
    },
  );

  testWidgets('Checking an item strikes through its text', (tester) async {
    await openEditor(tester, NoteType.checklist);
    await tester.enterText(find.byType(TextFormField), 'Read book');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(TextFormField),
        matching: find.byType(TextField),
      ),
    );
    expect(field.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('Options stay in bottom menu and text supports undo and redo', (
    tester,
  ) async {
    await openEditor(tester, NoteType.text);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byTooltip('Pin'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'A draft');
    await tester.pump();
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(find.text('A draft'), findsNothing);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(find.text('A draft'), findsOneWidget);
    await tester.tap(find.byTooltip('Note options'));
    await tester.pumpAndSettle();
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Reminder'), findsOneWidget);
  });

  testWidgets('Shopping reorder keeps names attached to their rows', (
    tester,
  ) async {
    await openEditor(tester, NoteType.shopping);
    Finder names() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Item',
    );
    await tester.enterText(names().first, 'Apples');
    await tester.tap(find.text('Add item'));
    await tester.pump();
    await tester.enterText(names().last, 'Bread');
    await tester.pump();
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorder!(0, 2);
    await tester.pump();
    expect(tester.widget<TextField>(names().first).controller!.text, 'Bread');
    expect(tester.widget<TextField>(names().last).controller!.text, 'Apples');
  });

  testWidgets('Image viewer handles invalid image data and offers reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AttachmentViewerScreen(
          attachment: NoteAttachment(
            id: 'image',
            type: 'drawing',
            data: 'invalid!',
          ),
        ),
      ),
    );
    expect(find.text('Image unavailable'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Reset zoom'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shopping summary updates for blank, zero and decimal prices', (
    tester,
  ) async {
    await openEditor(tester, NoteType.shopping);
    String metric(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    Finder prices() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '\u09f3',
    );
    expect(metric('shopping-listed'), '1');
    expect(metric('shopping-summed'), '0');
    expect(metric('shopping-total'), '\u09f30.00');
    await tester.enterText(prices().first, '0');
    await tester.pump();
    expect(metric('shopping-summed'), '1');
    await tester.tap(find.text('Add item'));
    await tester.pump();
    await tester.enterText(prices().last, '12.50');
    await tester.pump();
    expect(metric('shopping-listed'), '2');
    expect(metric('shopping-summed'), '2');
    expect(metric('shopping-total'), '\u09f312.50');
    await tester.enterText(prices().last, '');
    await tester.pump();
    expect(metric('shopping-summed'), '1');
    expect(metric('shopping-total'), '\u09f30.00');
    await tester.tap(find.byTooltip('Remove item').first);
    await tester.pump();
    await tester.tap(find.byTooltip('Remove item').first);
    await tester.pump();
    expect(metric('shopping-listed'), '0');
    expect(metric('shopping-summed'), '0');
    expect(find.byKey(const ValueKey('shopping-summary')), findsOneWidget);
  });

  testWidgets(
    'Shopping summary stays fixed during scrolling and above keyboard',
    (tester) async {
      await openEditor(tester, NoteType.shopping);
      for (var i = 0; i < 18; i++) {
        final add = find.ancestor(
          of: find.text('Add item'),
          matching: find.byType(FilledButton),
        );
        tester.widget<FilledButton>(add).onPressed!();
        await tester.pump();
      }
      final summary = find.byKey(const ValueKey('shopping-summary'));
      final position = tester.getTopLeft(summary);
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(summary), position);
      expect(tester.getBottomRight(summary).dy, lessThan(600));
      tester.view.viewInsets = FakeViewPadding(
        bottom: 250 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.getBottomRight(summary).dy, lessThan(600 - 250));
      expect(tester.takeException(), isNull);
    },
  );

  test('Shopping price presence survives copies and backup serialization', () {
    for (final item in [
      ShoppingItem(id: 'blank', name: ''),
      ShoppingItem(id: 'zero', name: 'Free', unitPrice: 0),
      ShoppingItem(id: 'priced', name: 'Milk', unitPrice: 12.5),
    ]) {
      expect(item.copy().hasPrice, item.hasPrice);
      final restored = ShoppingItem.fromJson(
        jsonDecode(jsonEncode(item.toJson())),
      );
      expect(restored.hasPrice, item.hasPrice);
      expect(restored.unitPrice, item.unitPrice);
    }
    expect(
      ShoppingItem.fromJson({
        'id': 'old',
        'name': 'Blank',
        'unitPrice': 0,
      }).hasPrice,
      isFalse,
    );
    expect(
      ShoppingItem.fromJson({
        'id': 'old',
        'name': 'Milk',
        'unitPrice': 90,
      }).hasPrice,
      isTrue,
    );
  });

  test('Invalid backups leave existing state untouched', () {
    final state = NotesProvider();
    final before = state.generateJsonBackup();
    expect(state.importJsonBackup('{}'), isFalse);
    final invalid = jsonDecode(before) as Map<String, dynamic>;
    invalid['folders'] = [42];
    expect(state.importJsonBackup(jsonEncode(invalid)), isFalse);
    expect(state.generateJsonBackup(), before);
    expect(state.importJsonBackup(before), isTrue);
  });
}
