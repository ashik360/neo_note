import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:neo_note_pro/main.dart';
import 'package:neo_note_pro/shopping_share.dart';
import 'package:provider/provider.dart';

class _SavePicker extends FilePicker {
  Uint8List? saved;
  String? filename;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saved = bytes;
    filename = fileName;
    return 'shopping.jpg';
  }
}

void main() {
  testWidgets('Shopping renderer makes real JPGs and paginates full lists', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final fontPath = Platform.environment['NEONOTE_TEST_FONT'];
      if (fontPath != null) {
        final loader = FontLoader('Roboto')
          ..addFont(
            File(
              fontPath,
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
      }
      final images = await renderShoppingJpegs('Weekend essentials', const [
        ShoppingShareRow('Fresh vegetables', 240),
        ShoppingShareRow('Milk & eggs', 180.5),
        ShoppingShareRow('Basmati rice', 320),
        ShoppingShareRow('Coffee for the week', null),
        ShoppingShareRow('Reusable shopping bag', 0),
      ], date: DateTime(2026, 9, 24));
      expect(images, hasLength(1));
      expect(images.first.take(3), [0xff, 0xd8, 0xff]);
      final decoded = img.decodeJpg(images.first)!;
      expect(decoded.width, 1080);
      expect(decoded.height, greaterThan(900));
      if (fontPath != null) {
        await Directory('build').create(recursive: true);
        await File(
          'build/shopping-share-preview.jpg',
        ).writeAsBytes(images.first);
      }
      final pages = await renderShoppingJpegs(
        'Long list',
        List.generate(25, (i) => ShoppingShareRow('Item $i', i.toDouble())),
      );
      expect(pages.length, greaterThan(1));
      for (final page in pages) {
        expect(img.decodeJpg(page)?.width, 1080);
      }
    });
  });

  testWidgets('Shopping preview saves the generated JPG with a jpg filename', (
    tester,
  ) async {
    final picker = _SavePicker();
    FilePicker.platform = picker;
    await tester.pumpWidget(
      const MaterialApp(
        home: ShoppingShareScreen(
          title: 'Groceries',
          rows: [ShoppingShareRow('Milk', 90)],
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
    expect(find.text('Share JPG'), findsOneWidget);
    await tester.tap(find.text('Save JPG'));
    await tester.pumpAndSettle();
    expect(picker.filename, endsWith('.jpg'));
    expect(picker.saved?.take(3), [0xff, 0xd8, 0xff]);
    expect(find.text('JPG saved to shopping.jpg'), findsOneWidget);
  });

  testWidgets('Note options shares current unsaved text', (tester) async {
    MethodCall? request;
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      request = call;
      return 'test';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: NotesProvider(),
        child: const MaterialApp(home: NoteEditorScreen()),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Share this draft');
    await tester.tap(find.byTooltip('Note options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(request?.method, 'share');
    expect(request?.arguments['text'], 'Share this draft');
  });
}
