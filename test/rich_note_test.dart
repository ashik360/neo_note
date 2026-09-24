import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:neo_note_pro/main.dart';
import 'package:neo_note_pro/rich_note_editor.dart';

void main() {
  testWidgets(
    'Formatting can be undone, saved, reopened and restored from backup',
    (tester) async {
      final state = NotesProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NoteEditorScreen(
                        initialNote: state.notes.firstOrNull,
                      ),
                    ),
                  ),
                  child: const Text('Open note'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open note'));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
          .controller;
      controller.replaceText(
        0,
        0,
        'Hello world',
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Bold'));
      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();
      expect(
        controller.document.toDelta().toJson().first['attributes']['bold'],
        true,
      );
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(
        controller.document.toDelta().toJson().first['attributes'],
        isNull,
      );
      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(
        controller.document.toDelta().toJson().first['attributes']['bold'],
        true,
      );
      controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
        quill.ChangeSource.local,
      );
      controller.formatSelection(quill.Attribute.italic);
      controller.formatSelection(quill.Attribute.underline);
      controller.formatSelection(const quill.ColorAttribute('#C62828'));
      controller.formatSelection(const quill.BackgroundAttribute('#FFF59D'));
      controller.formatSelection(
        const quill.LinkAttribute('https://example.com'),
      );
      await tester.pump();
      final expected = controller.document.toDelta().toJson();
      await tester.tap(find.byTooltip('Save note'));
      await tester.pumpAndSettle();
      expect(state.notes.single.content, 'Hello world');
      expect(state.notes.single.richContent, expected);
      final restored = NotesProvider();
      expect(restored.importJsonBackup(state.generateJsonBackup()), true);
      expect(restored.notes.single.richContent, expected);
      final copy = state.notes.single.copy();
      copy.richContent!.first['insert'] = 'Changed';
      expect(state.notes.single.richContent, expected);
      await tester.tap(find.text('Open note'));
      await tester.pumpAndSettle();
      final reopened = tester
          .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
          .controller;
      expect(reopened.document.toDelta().toJson(), expected);
      expect(
        richNoteShareText(reopened.document),
        contains('https://example.com'),
      );
    },
  );

  testWidgets('Formatting toolbar fits a narrow phone and can be hidden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: NotesProvider(),
        child: const MaterialApp(home: NoteEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RichNoteToolbar), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 290);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(
      tester.getBottomRight(find.byType(RichNoteToolbar)).dy,
      lessThan(450),
    );
    await tester.tap(find.byTooltip('Text formatting'));
    await tester.pump();
    expect(find.byType(RichNoteToolbar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'Plain notes migrate without losing text and invalid rich data falls back',
    () {
      final legacy = Note.fromJson({
        'id': 'old',
        'title': 'Legacy',
        'content': 'First line\nSecond line',
      });
      expect(legacy.richContent, isNull);
      final doc = loadRichNoteDocument(legacy.richContent, legacy.content);
      expect(doc.toPlainText(), 'First line\nSecond line\n');
      final invalid = loadRichNoteDocument([
        {
          'insert': {'unsupported': 'embed'},
        },
      ], legacy.content);
      expect(invalid.toPlainText(), doc.toPlainText());
      expect(jsonEncode(doc.toDelta().toJson()), contains('First line'));
      doc.close();
      invalid.close();
    },
  );
}
