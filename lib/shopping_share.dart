import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

class ShoppingShareRow {
  final String name;
  final double? price;
  const ShoppingShareRow(this.name, this.price);
}

Uint8List _encodeJpeg(Uint8List png) =>
    img.encodeJpg(img.decodePng(png)!, quality: 94);

/// Renders the entire draft, independently of which rows are on screen.
Future<List<Uint8List>> renderShoppingJpegs(
  String title,
  List<ShoppingShareRow> rows, {
  DateTime? date,
}) async {
  const ink = Color(0xFF162C2B);
  const muted = Color(0xFF647572);
  const green = Color(0xFFBDF3C6);
  const width = 1080.0;
  final now = date ?? DateTime.now();
  final priced = rows.where((r) => r.price != null).length;
  final total = rows.fold<double>(0, (sum, r) => sum + (r.price ?? 0));
  TextPainter text(
    String value,
    double size,
    Color color,
    double maxWidth, {
    FontWeight weight = FontWeight.w400,
  }) => TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: 1.3,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  final heading = text(
    title.trim().isEmpty ? 'Shopping list' : title.trim(),
    58,
    Colors.white,
    920,
    weight: FontWeight.w800,
  );
  final names = rows
      .map(
        (r) => text(
          r.name.trim().isEmpty ? 'Unnamed item' : r.name.trim(),
          30,
          ink,
          570,
          weight: FontWeight.w500,
        ),
      )
      .toList();
  // Height-based pagination preserves long names without clipping or shrinking text.
  final pages = <List<int>>[];
  var page = <int>[];
  var used = 0.0;
  for (var i = 0; i < rows.length; i++) {
    final height = math.max(88.0, names[i].height + 38);
    if (page.isNotEmpty && used + height > 1600) {
      pages.add(page);
      page = [];
      used = 0;
    }
    page.add(i);
    used += height;
  }
  if (page.isNotEmpty || pages.isEmpty) pages.add(page);
  final output = <Uint8List>[];
  for (var p = 0; p < pages.length; p++) {
    final headerHeight = heading.height + 210;
    final tableHeight = pages[p].isEmpty
        ? 120.0
        : pages[p].fold<double>(
            0,
            (sum, i) => sum + math.max(88.0, names[i].height + 38),
          );
    final height = (headerHeight + tableHeight + 430).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFFF5F3EC), BlendMode.src);
    final headerRect = Rect.fromLTWH(0, 0, width, headerHeight);
    canvas.drawRect(
      headerRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF102D2A), Color(0xFF285B4F)],
        ).createShader(headerRect),
    );
    canvas.save();
    canvas.clipRect(headerRect);
    canvas.drawCircle(
      Offset(1010, 30),
      220,
      Paint()..color = const Color(0x185EE5A2),
    );
    canvas.drawCircle(
      Offset(1020, 35),
      165,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x306EE5A2),
    );
    canvas.restore();
    void label(
      String value,
      double x,
      double y,
      double size,
      Color color,
      double maxWidth, {
      FontWeight weight = FontWeight.w400,
    }) {
      final painter = text(value, size, color, maxWidth, weight: weight);
      painter.paint(canvas, Offset(x, y));
      painter.dispose();
    }

    label(
      'NEONOTE  /  SHOPPING',
      64,
      45,
      23,
      green,
      800,
      weight: FontWeight.w700,
    );
    heading.paint(canvas, const Offset(64, 95));
    label(
      '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}   /   MADE TO SHARE',
      64,
      headerHeight - 57,
      20,
      const Color(0xFFD4E9DE),
      900,
    );
    var y = headerHeight + 32;
    label('ITEM', 140, y, 20, muted, 600, weight: FontWeight.w700);
    label('TAKA', 800, y, 20, muted, 200, weight: FontWeight.w700);
    y += 48;
    if (pages[p].isEmpty)
      label('Your shopping list is empty.', 64, y + 24, 30, muted, 900);
    for (final i in pages[p]) {
      final h = math.max(88.0, names[i].height + 38);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(48, y, 984, h - 8),
          const Radius.circular(16),
        ),
        Paint()..color = i.isEven ? Colors.white : const Color(0xFFEDEFE7),
      );
      label('${i + 1}'.padLeft(2, '0'), 68, y + 24, 22, muted, 60);
      names[i].paint(canvas, Offset(140, y + 18));
      final price = text(
        rows[i].price == null
            ? 'Not priced'
            : '\u09f3${rows[i].price!.toStringAsFixed(2)}',
        rows[i].price == null ? 24 : 29,
        rows[i].price == null ? muted : ink,
        215,
        weight: FontWeight.w600,
      );
      price.paint(canvas, Offset(1000 - price.width, y + 22));
      price.dispose();
      y += h;
    }
    y = headerHeight + tableHeight + 116;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(48, y, 984, 200),
        const Radius.circular(28),
      ),
      Paint()..color = ink,
    );
    label(
      '${rows.length} ITEMS LISTED   /   $priced SUMMED',
      80,
      y + 27,
      24,
      green,
      900,
      weight: FontWeight.w700,
    );
    label('TOTAL TAKA', 80, y + 89, 24, Colors.white70, 280);
    final amount = text(
      '\u09f3${total.toStringAsFixed(2)}',
      58,
      Colors.white,
      570,
      weight: FontWeight.w800,
    );
    amount.paint(canvas, Offset(995 - amount.width, y + 73));
    amount.dispose();
    label(
      '${rows.length - priced} unpriced  /  Total includes entered prices only',
      64,
      y + 221,
      21,
      muted,
      900,
    );
    label(
      'A LITTLE MORE ORGANIZED.',
      64,
      height - 45,
      18,
      muted,
      700,
      weight: FontWeight.w600,
    );
    label('${p + 1} / ${pages.length}', 910, height - 45, 18, muted, 100);
    final picture = recorder.endRecording();
    final raster = await picture.toImage(width.toInt(), height);
    try {
      final png = await raster.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('Could not render shopping image');
      output.add(await compute(_encodeJpeg, png.buffer.asUint8List()));
    } finally {
      raster.dispose();
      picture.dispose();
    }
  }
  heading.dispose();
  for (final name in names) {
    name.dispose();
  }
  return output;
}

class ShoppingShareScreen extends StatefulWidget {
  final String title;
  final List<ShoppingShareRow> rows;
  const ShoppingShareScreen({
    super.key,
    required this.title,
    required this.rows,
  });
  @override
  State<ShoppingShareScreen> createState() => _ShoppingShareScreenState();
}

class _ShoppingShareScreenState extends State<ShoppingShareScreen> {
  late Future<List<Uint8List>> _images;
  final _stamp = DateTime.now().millisecondsSinceEpoch;
  int _page = 0;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _images = renderShoppingJpegs(widget.title, widget.rows);
  }

  String _filename(int page) => 'NeoNote_shopping_${_stamp}_${page + 1}.jpg';
  Future<void> _send(List<Uint8List> images, bool save) async {
    final box = context.findRenderObject() as RenderBox?;
    setState(() => _busy = true);
    try {
      if (save) {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save shopping JPG',
          fileName: _filename(_page),
          type: FileType.custom,
          allowedExtensions: ['jpg'],
          bytes: images[_page],
        );
        if (mounted && (path != null || kIsWeb))
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                kIsWeb ? 'JPG download started.' : 'JPG saved to $path',
              ),
            ),
          );
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: images
                .map((bytes) => XFile.fromData(bytes, mimeType: 'image/jpeg'))
                .toList(),
            fileNameOverrides: List.generate(images.length, _filename),
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              save
                  ? 'Could not save JPG. Please try again.'
                  : 'Sharing is unavailable. You can save the JPG instead.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Share shopping list')),
    backgroundColor: const Color(0xFFDFE5DF),
    body: FutureBuilder<List<Uint8List>>(
      future: _images,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not create your JPG.'),
                TextButton(
                  onPressed: () => setState(() {
                    _images = renderShoppingJpegs(widget.title, widget.rows);
                  }),
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        if (!snapshot.hasData)
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Creating your shopping JPG...'),
              ],
            ),
          );
        final images = snapshot.data!;
        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                itemCount: images.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.memory(images[index], fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        images.length == 1
                            ? 'JPG preview / Ready to send'
                            : 'Page ${_page + 1} of ${images.length} / Swipe to preview',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _send(images, true),
                              icon: const Icon(Icons.download_outlined),
                              label: Text(
                                images.length == 1
                                    ? 'Save JPG'
                                    : 'Save page ${_page + 1}',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _send(images, false),
                              icon: const Icon(Icons.share_outlined),
                              label: Text(
                                images.length == 1
                                    ? 'Share JPG'
                                    : 'Share all JPGs',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_busy) const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
