import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

quill.Document loadRichNoteDocument(
  List<Map<String, dynamic>>? richContent,
  String plainText,
) {
  if (richContent != null && richContent.isNotEmpty) {
    try {
      // Notes only store text formatting; media remains in the attachment area.
      if (richContent.every((operation) => operation['insert'] is String)) {
        return quill.Document.fromJson(richContent);
      }
    } catch (_) {
      // Older notes and unsupported documents retain their readable text.
    }
  }
  return quill.Document.fromJson([
    {'insert': plainText.endsWith('\n') ? plainText : '$plainText\n'},
  ]);
}

String richNoteShareText(quill.Document document) {
  final text = document.toPlainText().trim();
  final links = document
      .toDelta()
      .toJson()
      .map((operation) => (operation['attributes'] as Map?)?['link'])
      .whereType<String>()
      .where((link) => !text.contains(link))
      .toSet();
  return [text, ...links].join('\n\n');
}

class RichNoteField extends StatelessWidget {
  final quill.QuillController controller;
  final FocusNode focusNode;
  const RichNoteField({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) => quill.QuillEditor.basic(
    controller: controller,
    focusNode: focusNode,
    config: quill.QuillEditorConfig(
      placeholder: 'Take a note...',
      scrollable: false,
      minHeight: 180,
      padding: const EdgeInsets.symmetric(vertical: 8),
      customStyles: quill.DefaultStyles(
        paragraph: quill.DefaultTextBlockStyle(
          TextStyle(
            fontSize: 16,
            height: 1.45,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          const quill.HorizontalSpacing(0, 0),
          const quill.VerticalSpacing(0, 0),
          const quill.VerticalSpacing(0, 0),
          null,
        ),
      ),
    ),
  );
}

class RichNoteToolbar extends StatelessWidget {
  final quill.QuillController controller;
  const RichNoteToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Note formatting toolbar. Scroll horizontally for more tools.',
    child: quill.QuillSimpleToolbar(
      controller: controller,
      config: const quill.QuillSimpleToolbarConfig(
        multiRowsDisplay: false,
        showUndo: false,
        showRedo: false,
        showAlignmentButtons: true,
        showDirection: true,
        showLineHeightButton: true,
        showSearchButton: false,
        buttonOptions: quill.QuillSimpleToolbarButtonOptions(
          fontFamily: quill.QuillToolbarFontFamilyButtonOptions(
            items: {
              'Sans serif': 'sans-serif',
              'Serif': 'serif',
              'Monospace': 'monospace',
            },
          ),
        ),
      ),
    ),
  );
}
