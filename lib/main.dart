import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'backup_exporter_stub.dart'
    if (dart.library.html) 'backup_exporter_web.dart'
    if (dart.library.io) 'backup_exporter_io.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NotesProvider()..bootstrap()),
      ],
      child: const NeoKeepApp(),
    ),
  );
}

class NeoKeepApp extends StatelessWidget {
  const NeoKeepApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotesProvider>();
    return MaterialApp(
      title: 'NeoNote Pro',
      debugShowCheckedModeBanner: false,
      themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const AppGate(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: const Color(0xFFFBC02D),
      fontFamily: 'Inter',
    );

    return base.copyWith(
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1F2937) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
}

// ================================================================
// MODELS
// ================================================================

enum NoteType { text, checklist, shopping, drawing, audio, image }

enum NoteStatus { active, archived, trashed }

enum NoteView { notes, reminders, archive, trash, locked }

String _newId(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

Color parseHexColor(String hex, {Color fallback = const Color(0xFFFFF8B8)}) {
  try {
    final cleaned = hex.replaceAll('#', '');
    final value = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
    return Color(int.parse(value, radix: 16));
  } catch (_) {
    return fallback;
  }
}

String hexFromColor(Color color) =>
    '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

class Folder {
  final String id;
  final String name;
  final IconData icon;
  final String iconKey;

  Folder({
    required this.id,
    required this.name,
    required this.icon,
    String? iconKey,
  }) : iconKey = iconKey ?? _keyFromIcon(icon);

  static const Map<String, IconData> _iconMap = {
    'folder_outlined': Icons.folder_outlined,
    'work_outline': Icons.work_outline,
    'shopping_basket_outlined': Icons.shopping_basket_outlined,
    'folder_open_outlined': Icons.folder_open_outlined,
    'home_outlined': Icons.home_outlined,
    'campaign_outlined': Icons.campaign_outlined,
    'lightbulb_outline': Icons.lightbulb_outline,
  };

  static String _keyFromIcon(IconData icon) {
    if (icon == Icons.work_outline) return 'work_outline';
    if (icon == Icons.shopping_basket_outlined) {
      return 'shopping_basket_outlined';
    }
    if (icon == Icons.folder_open_outlined) return 'folder_open_outlined';
    if (icon == Icons.home_outlined) return 'home_outlined';
    if (icon == Icons.campaign_outlined) return 'campaign_outlined';
    if (icon == Icons.lightbulb_outline) return 'lightbulb_outline';
    return 'folder_outlined';
  }

  static String _legacyKeyFromCodePoint(int? codePoint) {
    if (codePoint == Icons.work_outline.codePoint) return 'work_outline';
    if (codePoint == Icons.shopping_basket_outlined.codePoint) {
      return 'shopping_basket_outlined';
    }
    if (codePoint == Icons.folder_open_outlined.codePoint) {
      return 'folder_open_outlined';
    }
    if (codePoint == Icons.home_outlined.codePoint) return 'home_outlined';
    if (codePoint == Icons.campaign_outlined.codePoint) {
      return 'campaign_outlined';
    }
    if (codePoint == Icons.lightbulb_outline.codePoint) {
      return 'lightbulb_outline';
    }
    return 'folder_outlined';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconKey': iconKey,
      };

  factory Folder.fromJson(Map<String, dynamic> json) {
    final key =
        json['iconKey'] ?? _legacyKeyFromCodePoint(json['iconCode'] as int?);
    return Folder(
      id: json['id'] ?? _newId('folder'),
      name: json['name'] ?? 'Untitled Folder',
      icon: _iconMap[key] ?? Icons.folder_outlined,
      iconKey: key,
    );
  }
}

class NoteLabel {
  final String id;
  final String name;
  final Color color;

  NoteLabel({required this.id, required this.name, required this.color});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': color.value,
      };

  factory NoteLabel.fromJson(Map<String, dynamic> json) {
    return NoteLabel(
      id: json['id'] ?? _newId('label'),
      name: json['name'] ?? 'label',
      color: Color((json['colorValue'] as num?)?.toInt() ?? 0xFFF59E0B),
    );
  }
}

class ShoppingItem {
  String id;
  String name;
  bool isChecked;
  double unitPrice;

  ShoppingItem({
    required this.id,
    required this.name,
    this.isChecked = false,
    this.unitPrice = 0,
  });

  ShoppingItem copy() => ShoppingItem(
        id: id,
        name: name,
        isChecked: isChecked,
        unitPrice: unitPrice,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isChecked': isChecked,
        'unitPrice': unitPrice,
      };

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'] ?? _newId('item'),
      name: json['name'] ?? '',
      isChecked: json['isChecked'] ?? false,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ChecklistItem {
  String id;
  String text;
  bool isChecked;

  ChecklistItem({
    required this.id,
    required this.text,
    this.isChecked = false,
  });

  ChecklistItem copy() => ChecklistItem(
        id: id,
        text: text,
        isChecked: isChecked,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isChecked': isChecked,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] ?? _newId('check'),
      text: json['text'] ?? '',
      isChecked: json['isChecked'] ?? false,
    );
  }
}

class NoteAttachment {
  String id;
  String type; // image, audio, drawing
  String data; // image/drawing base64, audio path/blob path
  String? fileName;
  String? drawingJson;
  DateTime createdAt;

  NoteAttachment({
    required this.id,
    required this.type,
    required this.data,
    this.fileName,
    this.drawingJson,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  NoteAttachment copy() => NoteAttachment(
        id: id,
        type: type,
        data: data,
        fileName: fileName,
        drawingJson: drawingJson,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'data': data,
        'fileName': fileName,
        'drawingJson': drawingJson,
        'createdAt': createdAt.toIso8601String(),
      };

  factory NoteAttachment.fromJson(Map<String, dynamic> json) {
    return NoteAttachment(
      id: json['id'] ?? _newId('attachment'),
      type: json['type'] ?? 'image',
      data: json['data'] ?? json['pathOrBase64'] ?? '',
      fileName: json['fileName'],
      drawingJson: json['drawingJson'],
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class Note {
  String id;
  String title;
  String content;
  NoteType type;
  NoteStatus status;
  String? folderId;
  List<String> labelIds;
  String colorHex;
  bool isPinned;
  bool isLocked;
  DateTime createdAt;
  DateTime updatedAt;
  DateTime? reminderAt;
  bool reminderFired;
  DateTime? trashedAt;
  List<ShoppingItem> shoppingItems;
  List<ChecklistItem> checklistItems;
  List<NoteAttachment> attachments;

  Note({
    required this.id,
    required this.title,
    required this.content,
    this.type = NoteType.text,
    this.status = NoteStatus.active,
    this.folderId,
    required this.labelIds,
    required this.colorHex,
    this.isPinned = false,
    this.isLocked = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.reminderAt,
    this.reminderFired = false,
    this.trashedAt,
    required this.shoppingItems,
    required this.checklistItems,
    required this.attachments,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get hasContent =>
      title.trim().isNotEmpty ||
      content.trim().isNotEmpty ||
      shoppingItems.isNotEmpty ||
      checklistItems.isNotEmpty ||
      attachments.isNotEmpty;

  Note copy() => Note(
        id: id,
        title: title,
        content: content,
        type: type,
        status: status,
        folderId: folderId,
        labelIds: List<String>.from(labelIds),
        colorHex: colorHex,
        isPinned: isPinned,
        isLocked: isLocked,
        createdAt: createdAt,
        updatedAt: updatedAt,
        reminderAt: reminderAt,
        reminderFired: reminderFired,
        trashedAt: trashedAt,
        shoppingItems: shoppingItems.map((e) => e.copy()).toList(),
        checklistItems: checklistItems.map((e) => e.copy()).toList(),
        attachments: attachments.map((e) => e.copy()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'type': type.name,
        'status': status.name,
        'folderId': folderId,
        'labelIds': labelIds,
        'colorHex': colorHex,
        'isPinned': isPinned,
        'isLocked': isLocked,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
        'reminderFired': reminderFired,
        'trashedAt': trashedAt?.toIso8601String(),
        'shoppingItems': shoppingItems.map((e) => e.toJson()).toList(),
        'checklistItems': checklistItems.map((e) => e.toJson()).toList(),
        'attachments': attachments.map((e) => e.toJson()).toList(),
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    final oldShoppingMode = json['isShoppingMode'] == true;
    final rawShoppingItems = json['shoppingItems'] as List? ?? [];
    final rawChecklistItems = json['checklistItems'] as List? ?? [];
    final rawAttachments = json['attachments'] as List? ?? [];

    return Note(
      id: json['id'] ?? _newId('note'),
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      type: NoteType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => oldShoppingMode ? NoteType.shopping : NoteType.text,
      ),
      status: NoteStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => NoteStatus.active,
      ),
      folderId: json['folderId'],
      labelIds: List<String>.from(json['labelIds'] ?? json['tags'] ?? []),
      colorHex: json['colorHex'] ?? '#FFF8B8',
      isPinned: json['isPinned'] ?? false,
      isLocked: json['isLocked'] ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ??
          DateTime.tryParse(json['updatedAt'] ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      reminderAt: json['reminderAt'] == null
          ? null
          : DateTime.tryParse(json['reminderAt']),
      reminderFired: json['reminderFired'] ?? false,
      trashedAt:
          json['trashedAt'] == null ? null : DateTime.tryParse(json['trashedAt']),
      shoppingItems:
          rawShoppingItems.map((e) => ShoppingItem.fromJson(e)).toList(),
      checklistItems:
          rawChecklistItems.map((e) => ChecklistItem.fromJson(e)).toList(),
      attachments:
          rawAttachments.map((e) => NoteAttachment.fromJson(e)).toList(),
    );
  }
}


// ================================================================
// PERMISSIONS + LOCAL NOTIFICATIONS
// ================================================================

class AppPermissionService {
  static const String _permissionAskedKey = 'NeoNote_permissions_requested_v5';

  static Future<void> requestFirstLaunchPermissions(SharedPreferences? prefs) async {
    if (kIsWeb) return;
    final alreadyAsked = prefs?.getBool(_permissionAskedKey) ?? false;
    if (alreadyAsked) return;

    await _requestCorePermissions();
    await NotificationService.requestPermissions();
    await prefs?.setBool(_permissionAskedKey, true);
  }

  static Future<void> _requestCorePermissions() async {
    try {
      await Permission.microphone.request();
      await Permission.notification.request();

      if (defaultTargetPlatform == TargetPlatform.android) {
        await Permission.photos.request();
        await Permission.storage.request();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await Permission.photos.request();
      }
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }
  }

  static Future<bool> ensureMicrophone(BuildContext context) async {
    if (kIsWeb) return true;
    final status = await Permission.microphone.request();
    if (status.isGranted || status.isLimited) return true;
    if (context.mounted) {
      _snack(
        context,
        'Microphone permission is required for audio notes. Enable it from App Info if denied.',
      );
    }
    return false;
  }

  static Future<bool> ensureGallery(BuildContext context) async {
    if (kIsWeb) return true;
    try {
      final photos = await Permission.photos.request();
      final storage = await Permission.storage.request();
      if (photos.isGranted || photos.isLimited || storage.isGranted) return true;
    } catch (_) {
      // image_picker can still open Android Photo Picker on modern Android.
      return true;
    }
    if (context.mounted) {
      _snack(
        context,
        'Photo/storage permission is required to attach images.',
      );
    }
    return false;
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  static Future<void> init() async {
    try {
      tz.initializeTimeZones();

      if (!kIsWeb) {
        try {
          final zoneInfo = await FlutterTimezone.getLocalTimezone();
          tz.setLocalLocation(tz.getLocation(zoneInfo.identifier));
        } catch (_) {
          tz.setLocalLocation(tz.local);
        }
      }

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');

      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );

      await _plugin.initialize(
        settings: initSettings,
      );

      _ready = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
      _ready = false;
    }
  }

  static Future<void> requestPermissions() async {
    if (!_ready || kIsWeb) return;

    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      // Safe for Android 13+ and avoids OS-level exact alarm panics
      await android?.requestNotificationsPermission();

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();

      await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      final macos = _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>();

      await macos?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
  }

  static int _idFor(String noteId) {
    return noteId.hashCode & 0x7fffffff;
  }

  static Future<void> cancelReminder(String noteId) async {
    if (!_ready) return;

    try {
      await _plugin.cancel(
        id: _idFor(noteId),
      );
    } catch (_) {}
  }

  static Future<void> scheduleNoteReminder(Note note) async {
    if (!_ready || note.reminderAt == null || note.status != NoteStatus.active) {
      await cancelReminder(note.id);
      return;
    }

    final due = note.reminderAt!;

    if (!due.isAfter(DateTime.now())) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'neonote_reminders',
      'NeoNote Reminders',
      channelDescription: 'Reminder notifications for saved notes',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    try {
      // Using inexact scheduling prevents modern OS execution crashes entirely 
      // while preserving dependable reminder behavior
      await _plugin.zonedSchedule(
        id: _idFor(note.id),
        title: note.title.trim().isEmpty ? 'NeoNote reminder' : note.title.trim(),
        body: note.content.trim().isEmpty ? 'Open your note' : note.content.trim(),
        scheduledDate: tz.TZDateTime.from(due, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: note.id,
      );
    } catch (e) {
      debugPrint('Reminder schedule failed: $e');
    }
  }

  static Future<void> showReminderNow(Note note) async {
    if (!_ready) return;

    const androidDetails = AndroidNotificationDetails(
      'neonote_reminders',
      'NeoNote Reminders',
      channelDescription: 'Reminder notifications for saved notes',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _plugin.show(
        id: _idFor('${note.id}_now'),
        title: note.title.trim().isEmpty ? 'NeoNote reminder' : note.title.trim(),
        body: note.content.trim().isEmpty ? 'Open your note' : note.content.trim(),
        notificationDetails: details,
        payload: note.id,
      );
    } catch (e) {
      debugPrint('Immediate reminder failed: $e');
    }
  }
}

// ================================================================
// PROVIDER
// ================================================================

class NotesProvider extends ChangeNotifier {
  static const String _storageKey = 'NeoNotepro_device_registry';

  List<Note> notes = [];
  List<Folder> folders = [];
  List<NoteLabel> labels = [];

  String searchQuery = '';
  String? selectedFolderId = 'all';
  String? selectedLabelId;
  NoteView currentView = NoteView.notes;
  bool isGridView = true;
  bool isDarkMode = false;

  String currentPin = '0000';
  bool isFingerprintActive = false;
  bool isVaultLocked = true;
  bool isLockEnabled = false;
  bool isBootstrapped = false;

  SharedPreferences? _prefs;

  Future<void> bootstrap() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _loadFromStorage();
      await AppPermissionService.requestFirstLaunchPermissions(_prefs);
      await NotificationService.requestPermissions();
      _refreshReminderStatesInternal(showImmediateNotifications: false);
      _rescheduleFutureReminders();
    } catch (e) {
      _loadSampleData();
      debugPrint('SharedPreferences load failed: $e');
    }
    isBootstrapped = true;
    notifyListeners();
  }

  void _loadFromStorage() {
    final raw = _prefs?.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      _loadSampleData();
      return;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      notes = (decoded['notes'] as List? ?? [])
          .map((e) => Note.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      folders = (decoded['folders'] as List? ?? [])
          .map((e) => Folder.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      labels = (decoded['labels'] as List? ?? decoded['tags'] as List? ?? [])
          .map((e) => NoteLabel.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      currentPin = decoded['currentPin'] ?? '0000';
      isLockEnabled = decoded['isLockEnabled'] ?? false;
      isFingerprintActive = decoded['isFingerprintActive'] ?? false;
      isVaultLocked = decoded['isVaultLocked'] ?? isLockEnabled;
      isGridView = decoded['isGridView'] ?? true;
      isDarkMode = decoded['isDarkMode'] ?? false;

      if (folders.isEmpty) _seedFolders();
      if (labels.isEmpty) _seedLabels();
    } catch (e) {
      debugPrint('State decode failed: $e');
      _loadSampleData();
    }
  }

  void _seedFolders() {
    folders = [
      Folder(id: 'folder_personal', name: 'Personal', icon: Icons.home_outlined),
      Folder(id: 'folder_work', name: 'Work', icon: Icons.work_outline),
      Folder(
        id: 'folder_shopping',
        name: 'Shopping',
        icon: Icons.shopping_basket_outlined,
      ),
    ];
  }

  void _seedLabels() {
    labels = [
      NoteLabel(id: 'label_urgent', name: 'urgent', color: const Color(0xFFEF4444)),
      NoteLabel(id: 'label_ideas', name: 'ideas', color: const Color(0xFF3B82F6)),
      NoteLabel(id: 'label_budget', name: 'budget', color: const Color(0xFFF59E0B)),
    ];
  }

  void _loadSampleData() {
    _seedFolders();
    _seedLabels();
    notes = [
      Note(
        id: 'note_welcome',
        title: 'Welcome to NeoNote Pro',
        content:
            'Quick notes, image attachments, audio recording, drawings, archive, trash, labels, folders and vault lock are ready.',
        type: NoteType.text,
        labelIds: ['label_ideas'],
        folderId: 'folder_personal',
        colorHex: '#FFF8B8',
        isPinned: true,
        shoppingItems: [],
        checklistItems: [],
        attachments: [],
      ),
      Note(
        id: 'note_shop',
        title: 'Market list',
        content: '',
        type: NoteType.shopping,
        labelIds: ['label_budget'],
        folderId: 'folder_shopping',
        colorHex: '#D7F5D1',
        shoppingItems: [
          ShoppingItem(id: 'item_1', name: 'Milk', unitPrice: 90),
          ShoppingItem(id: 'item_2', name: 'Bread', unitPrice: 60),
        ],
        checklistItems: [],
        attachments: [],
      ),
    ];
    save();
  }

  void save() {
    final map = {
      'notes': notes.map((n) => n.toJson()).toList(),
      'folders': folders.map((f) => f.toJson()).toList(),
      'labels': labels.map((l) => l.toJson()).toList(),
      'currentPin': currentPin,
      'isLockEnabled': isLockEnabled,
      'isFingerprintActive': isFingerprintActive,
      'isVaultLocked': isVaultLocked,
      'isGridView': isGridView,
      'isDarkMode': isDarkMode,
    };
    _prefs?.setString(_storageKey, jsonEncode(map));
  }

  List<Note> get visibleNotes {
    final query = searchQuery.trim().toLowerCase();
    final filtered = notes.where((note) {
      final viewMatch = switch (currentView) {
        NoteView.notes => note.status == NoteStatus.active,
        NoteView.reminders =>
          note.status == NoteStatus.active && note.reminderAt != null,
        NoteView.archive => note.status == NoteStatus.archived,
        NoteView.trash => note.status == NoteStatus.trashed,
        NoteView.locked => note.status != NoteStatus.trashed && note.isLocked,
      };
      if (!viewMatch) return false;

      if (selectedFolderId != null && selectedFolderId != 'all') {
        if (selectedFolderId == 'uncategorized') {
          if (note.folderId != null) return false;
        } else if (note.folderId != selectedFolderId) {
          return false;
        }
      }

      if (selectedLabelId != null && !note.labelIds.contains(selectedLabelId)) {
        return false;
      }

      if (query.isNotEmpty) {
        final labelNames = note.labelIds
            .map((id) => labels
                .where((label) => label.id == id)
                .map((label) => label.name)
                .join(' '))
            .join(' ');
        final haystack = [
          note.title,
          note.content,
          labelNames,
          note.type.name,
          ...note.shoppingItems.map((e) => e.name),
          ...note.checklistItems.map((e) => e.text),
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return filtered;
  }

  List<Note> get pinnedNotes => visibleNotes.where((n) => n.isPinned).toList();
  List<Note> get otherNotes => visibleNotes.where((n) => !n.isPinned).toList();

  void setSearch(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void selectView(NoteView view) {
    currentView = view;
    selectedFolderId = 'all';
    selectedLabelId = null;
    notifyListeners();
  }

  void selectFolder(String? id) {
    selectedFolderId = id;
    selectedLabelId = null;
    currentView = NoteView.notes;
    notifyListeners();
  }

  void selectLabel(String? id) {
    selectedLabelId = id;
    selectedFolderId = 'all';
    currentView = NoteView.notes;
    notifyListeners();
  }

  void toggleViewMode() {
    isGridView = !isGridView;
    save();
    notifyListeners();
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    save();
    notifyListeners();
  }

  void setLockState(bool value) {
    isVaultLocked = value;
    save();
    notifyListeners();
  }

  void updateSecurity({
    required bool lockEnabled,
    required bool fingerprintEnabled,
    required String pin,
  }) {
    isLockEnabled = lockEnabled;
    isFingerprintActive = fingerprintEnabled;
    if (pin.length == 4) currentPin = pin;
    isVaultLocked = lockEnabled;
    save();
    notifyListeners();
  }

  void createFolder(String name) {
    folders.add(Folder(
      id: _newId('folder'),
      name: name,
      icon: Icons.folder_open_outlined,
    ));
    save();
    notifyListeners();
  }

  void removeFolder(String id) {
    folders.removeWhere((f) => f.id == id);
    for (final note in notes) {
      if (note.folderId == id) note.folderId = null;
    }
    save();
    notifyListeners();
  }

  void renameFolder(String id, String newName) {
    final cleaned = newName.trim();
    if (cleaned.isEmpty) return;
    final index = folders.indexWhere((f) => f.id == id);
    if (index == -1) return;
    final old = folders[index];
    folders[index] = Folder(id: old.id, name: cleaned, icon: old.icon, iconKey: old.iconKey);
    save();
    notifyListeners();
  }

  Future<void> refreshNow() async {
    _refreshReminderStatesInternal(showImmediateNotifications: true);
    _rescheduleFutureReminders();
    save();
    notifyListeners();
  }

  void _refreshReminderStatesInternal({required bool showImmediateNotifications}) {
    final now = DateTime.now();
    for (final note in notes) {
      final due = note.reminderAt;
      if (due == null || note.status != NoteStatus.active) continue;
      if (!note.reminderFired && !due.isAfter(now)) {
        note.reminderFired = true;
        note.updatedAt = now;
        if (showImmediateNotifications) {
          unawaited(NotificationService.showReminderNow(note));
        }
      }
    }
  }

  void _rescheduleFutureReminders() {
    for (final note in notes) {
      if (note.reminderAt != null &&
          note.status == NoteStatus.active &&
          note.reminderAt!.isAfter(DateTime.now())) {
        unawaited(NotificationService.scheduleNoteReminder(note));
      }
    }
  }

  void createLabel(String name, Color color) {
    labels.add(NoteLabel(id: _newId('label'), name: name, color: color));
    save();
    notifyListeners();
  }

  void upsertNote(Note note) {
    note.updatedAt = DateTime.now();
    if (note.reminderAt != null && note.reminderAt!.isAfter(DateTime.now())) {
      note.reminderFired = false;
    }
    final index = notes.indexWhere((n) => n.id == note.id);
    if (index == -1) {
      notes.insert(0, note);
    } else {
      notes[index] = note;
    }
    save();
    unawaited(NotificationService.scheduleNoteReminder(note));
    notifyListeners();
  }

  void togglePin(String id) {
    final note = notes.firstWhere((n) => n.id == id);
    note.isPinned = !note.isPinned;
    note.updatedAt = DateTime.now();
    save();
    notifyListeners();
  }

  void archiveNote(String id) {
    final note = notes.firstWhere((n) => n.id == id);
    note.status = NoteStatus.archived;
    note.updatedAt = DateTime.now();
    save();
    unawaited(NotificationService.cancelReminder(id));
    notifyListeners();
  }

  void unarchiveNote(String id) {
    final note = notes.firstWhere((n) => n.id == id);
    note.status = NoteStatus.active;
    note.updatedAt = DateTime.now();
    save();
    unawaited(NotificationService.scheduleNoteReminder(note));
    notifyListeners();
  }

  void moveToTrash(String id) {
    final note = notes.firstWhere((n) => n.id == id);
    note.status = NoteStatus.trashed;
    note.trashedAt = DateTime.now();
    note.updatedAt = DateTime.now();
    save();
    unawaited(NotificationService.cancelReminder(id));
    notifyListeners();
  }

  void restoreNote(String id) {
    final index = notes.indexWhere((n) => n.id == id);
    if (index == -1) return;
    final note = notes[index];
    note.status = NoteStatus.active;
    note.trashedAt = null;
    note.updatedAt = DateTime.now();
    save();
    unawaited(NotificationService.scheduleNoteReminder(note));
    notifyListeners();
  }

  void deleteForever(String id) {
    notes.removeWhere((n) => n.id == id);
    save();
    unawaited(NotificationService.cancelReminder(id));
    notifyListeners();
  }

  String generateJsonBackup() {
    final map = {
      'notes': notes.map((n) => n.toJson()).toList(),
      'folders': folders.map((f) => f.toJson()).toList(),
      'labels': labels.map((l) => l.toJson()).toList(),
      'currentPin': currentPin,
      'isLockEnabled': isLockEnabled,
      'isFingerprintActive': isFingerprintActive,
      'isGridView': isGridView,
      'isDarkMode': isDarkMode,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  bool importJsonBackup(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      notes = (decoded['notes'] as List? ?? [])
          .map((e) => Note.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      folders = (decoded['folders'] as List? ?? [])
          .map((e) => Folder.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      labels = (decoded['labels'] as List? ?? decoded['tags'] as List? ?? [])
          .map((e) => NoteLabel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      currentPin = decoded['currentPin'] ?? currentPin;
      isLockEnabled = decoded['isLockEnabled'] ?? isLockEnabled;
      isFingerprintActive = decoded['isFingerprintActive'] ?? isFingerprintActive;
      isGridView = decoded['isGridView'] ?? isGridView;
      isDarkMode = decoded['isDarkMode'] ?? isDarkMode;
      isVaultLocked = false;
      if (folders.isEmpty) _seedFolders();
      if (labels.isEmpty) _seedLabels();
      save();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Restore failed: $e');
      return false;
    }
  }
}

// ================================================================
// APP GATE + LOCK
// ================================================================

class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotesProvider>();
    if (!state.isBootstrapped) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (state.isLockEnabled && state.isVaultLocked) {
      return const SecureLockScreen();
    }
    return const DashboardScreen();
  }
}

class SecureLockScreen extends StatefulWidget {
  const SecureLockScreen({super.key});

  @override
  State<SecureLockScreen> createState() => _SecureLockScreenState();
}

class _SecureLockScreenState extends State<SecureLockScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  String pin = '';
  String status = 'Enter your PIN';
  bool bioAvailable = false;
  bool bioBusy = false;

  @override
  void initState() {
    super.initState();
    _checkBio();
  }

  Future<void> _checkBio() async {
    final state = context.read<NotesProvider>();
    if (kIsWeb || !state.isFingerprintActive) {
      setState(() => bioAvailable = false);
      return;
    }
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      final available = await _auth.getAvailableBiometrics();
      if (!mounted) return;
      setState(() => bioAvailable = canCheck && supported && available.isNotEmpty);
    } catch (_) {
      if (mounted) setState(() => bioAvailable = false);
    }
  }

  Future<void> _unlockWithBio() async {
    if (!bioAvailable || bioBusy) return;
    setState(() => bioBusy = true);
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock NeoNote Pro',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) context.read<NotesProvider>().setLockState(false);
    } catch (e) {
      if (mounted) setState(() => status = 'Fingerprint failed. Use PIN.');
    } finally {
      if (mounted) setState(() => bioBusy = false);
    }
  }

  void _press(String value) {
    final state = context.read<NotesProvider>();
    if (value == 'back') {
      if (pin.isNotEmpty) setState(() => pin = pin.substring(0, pin.length - 1));
      return;
    }
    if (value == 'clear') {
      setState(() => pin = '');
      return;
    }
    if (pin.length >= 4) return;
    setState(() => pin += value);
    if (pin.length == 4) {
      if (pin == state.currentPin) {
        HapticFeedback.lightImpact();
        state.setLockState(false);
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          pin = '';
          status = 'Wrong PIN. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<NotesProvider>().isDarkMode;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBC02D).withOpacity(.18),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.lightbulb_rounded,
                      color: Color(0xFFFBC02D), size: 38),
                ),
                const SizedBox(height: 18),
                const Text('NeoNote Pro',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(status,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 13,
                    )),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    4,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < pin.length
                            ? const Color(0xFFFBC02D)
                            : (isDark ? Colors.white24 : Colors.black12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                if (bioAvailable)
                  IconButton.filledTonal(
                    onPressed: _unlockWithBio,
                    icon: bioBusy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fingerprint_rounded, size: 34),
                  ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 12,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.45,
                  ),
                  itemBuilder: (_, index) {
                    final values = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'clear', '0', 'back'];
                    final value = values[index];
                    final child = value == 'clear'
                        ? const Icon(Icons.refresh_rounded)
                        : value == 'back'
                            ? const Icon(Icons.backspace_outlined)
                            : Text(value,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold));
                    return InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _press(value),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1F2937) : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: isDark ? Colors.white10 : Colors.black12),
                        ),
                        child: Center(child: child),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// DASHBOARD
// ================================================================

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _search = TextEditingController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) context.read<NotesProvider>().refreshNow();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _openEditor({
    Note? note,
    NoteType type = NoteType.text,
    NoteAttachment? attachment,
    bool autoStartRecording = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          initialNote: note,
          initialType: type,
          initialAttachment: attachment,
          autoStartRecording: autoStartRecording,
        ),
      ),
    );
  }

  Future<void> _showCreateSheet() async {
    final isDark = context.read<NotesProvider>().isDarkMode;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add new',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _CreateTile(
                    icon: Icons.notes_rounded,
                    title: 'Note',
                    onTap: () {
                      Navigator.pop(context);
                      _openEditor(type: NoteType.text);
                    },
                  ),
                  _CreateTile(
                    icon: Icons.image_outlined,
                    title: 'Image',
                    onTap: () async {
                      Navigator.pop(context);
                      final attachment = await _pickImageAttachment(context);
                      if (attachment != null && mounted) {
                        _openEditor(type: NoteType.image, attachment: attachment);
                      }
                    },
                  ),
                  _CreateTile(
                    icon: Icons.mic_none_rounded,
                    title: 'Audio',
                    onTap: () {
                      Navigator.pop(context);
                      _openEditor(type: NoteType.audio, autoStartRecording: true);
                    },
                  ),
                  _CreateTile(
                    icon: Icons.draw_outlined,
                    title: 'Drawing',
                    onTap: () async {
                      Navigator.pop(context);
                      final attachment = await Navigator.of(context).push<NoteAttachment>(
                        MaterialPageRoute(builder: (_) => const DrawingCaptureScreen()),
                      );
                      if (attachment != null && mounted) {
                        _openEditor(type: NoteType.drawing, attachment: attachment);
                      }
                    },
                  ),
                  _CreateTile(
                    icon: Icons.shopping_basket_outlined,
                    title: 'Shopping',
                    onTap: () {
                      Navigator.pop(context);
                      _openEditor(type: NoteType.shopping);
                    },
                  ),
                  _CreateTile(
                    icon: Icons.check_box_outlined,
                    title: 'Checklist',
                    onTap: () {
                      Navigator.pop(context);
                      _openEditor(type: NoteType.checklist);
                    },
                  ),
                ],
              ),
              if (isDark) const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotesProvider>();
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 980;

    return Scaffold(
      key: _scaffoldKey,
      drawer: isWide ? null : Drawer(child: _Sidebar(onClose: () => Navigator.pop(context))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: SafeArea(
        child: Row(
          children: [
            if (isWide) const SizedBox(width: 288, child: _Sidebar()),
            Expanded(
              child: Column(
                children: [
                  _Header(
                    controller: _search,
                    onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                    showMenu: !isWide,
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        width < 640 ? 12 : 24,
                        12,
                        width < 640 ? 12 : 24,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _QuickComposer(),
                          const SizedBox(height: 14),
                          const _LabelsBar(),
                          const SizedBox(height: 12),
                          _NotesTitleRow(total: state.visibleNotes.length),
                          const SizedBox(height: 10),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: () => context.read<NotesProvider>().refreshNow(),
                              child: state.visibleNotes.isEmpty
                                  ? const _EmptyState(scrollable: true)
                                  : state.isGridView
                                      ? _NotesGrid(onOpen: _openEditor)
                                      : _NotesList(onOpen: _openEditor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _CreateTile({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<NotesProvider>().isDarkMode;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onMenu;
  final bool showMenu;

  const _Header({required this.controller, required this.onMenu, required this.showMenu});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotesProvider>();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: state.isDarkMode ? Colors.white10 : Colors.black12)),
      ),
      child: Row(
        children: [
          if (showMenu) IconButton(onPressed: onMenu, icon: const Icon(Icons.menu_rounded)),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: context.read<NotesProvider>().setSearch,
              decoration: InputDecoration(
                hintText: 'Search your notes',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: state.searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          controller.clear();
                          context.read<NotesProvider>().setSearch('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: context.read<NotesProvider>().refreshNow,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: state.isGridView ? 'List view' : 'Grid view',
            onPressed: context.read<NotesProvider>().toggleViewMode,
            icon: Icon(state.isGridView ? Icons.view_agenda_outlined : Icons.grid_view_rounded),
          ),
          IconButton(
            tooltip: 'Theme',
            onPressed: context.read<NotesProvider>().toggleTheme,
            icon: Icon(state.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
          ),
          IconButton(
            tooltip: 'Lock app',
            onPressed: state.isLockEnabled ? () => state.setLockState(true) : null,
            icon: const Icon(Icons.lock_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final VoidCallback? onClose;

  const _Sidebar({this.onClose});

@override
Widget build(BuildContext context) {
  final state = context.watch<NotesProvider>();
  final bg = state.isDarkMode ? const Color(0xFF1F2937) : Colors.white;
  
  return Container(
    color: bg,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // BRAND HEADER (Stays pinned to top)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBC02D),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.lightbulb_rounded, color: Colors.black87),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('NeoNote Pro',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          
          // SCROLLABLE NAV BODY (Prevents the overflow bug)
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NavItem(
                    icon: Icons.lightbulb_outline,
                    title: 'Notes',
                    selected: state.currentView == NoteView.notes && state.selectedFolderId == 'all' && state.selectedLabelId == null,
                    count: state.notes.where((n) => n.status == NoteStatus.active).length,
                    onTap: () {
                      context.read<NotesProvider>().selectView(NoteView.notes);
                      onClose?.call();
                    },
                  ),
                  _NavItem(
                    icon: Icons.notifications_none_rounded,
                    title: 'Reminders',
                    selected: state.currentView == NoteView.reminders,
                    count: state.notes.where((n) => n.reminderAt != null && n.status == NoteStatus.active).length,
                    onTap: () {
                      context.read<NotesProvider>().selectView(NoteView.reminders);
                      onClose?.call();
                    },
                  ),
                  _NavItem(
                    icon: Icons.lock_outline_rounded,
                    title: 'Locked',
                    selected: state.currentView == NoteView.locked,
                    count: state.notes.where((n) => n.isLocked && n.status != NoteStatus.trashed).length,
                    onTap: () {
                      context.read<NotesProvider>().selectView(NoteView.locked);
                      onClose?.call();
                    },
                  ),
                  _NavItem(
                    icon: Icons.archive_outlined,
                    title: 'Archive',
                    selected: state.currentView == NoteView.archive,
                    count: state.notes.where((n) => n.status == NoteStatus.archived).length,
                    onTap: () {
                      context.read<NotesProvider>().selectView(NoteView.archive);
                      onClose?.call();
                    },
                  ),
                  _NavItem(
                    icon: Icons.delete_outline_rounded,
                    title: 'Trash',
                    selected: state.currentView == NoteView.trash,
                    count: state.notes.where((n) => n.status == NoteStatus.trashed).length,
                    onTap: () {
                      context.read<NotesProvider>().selectView(NoteView.trash);
                      onClose?.call();
                    },
                  ),
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Folders', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold))),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          onPressed: () => _showFolderDialog(context),
                        ),
                      ],
                    ),
                  ),
                  _NavItem(
                    icon: Icons.layers_clear_outlined,
                    title: 'Uncategorized',
                    selected: state.selectedFolderId == 'uncategorized',
                    count: state.notes.where((n) => n.folderId == null && n.status == NoteStatus.active).length,
                    onTap: () {
                      context.read<NotesProvider>().selectFolder('uncategorized');
                      onClose?.call();
                    },
                  ),
                  ...state.folders.map((folder) => _NavItem(
                        icon: folder.icon,
                        title: folder.name,
                        selected: state.selectedFolderId == folder.id,
                        count: state.notes.where((n) => n.folderId == folder.id && n.status == NoteStatus.active).length,
                        onTap: () {
                          context.read<NotesProvider>().selectFolder(folder.id);
                          onClose?.call();
                        },
                        onLongPress: () => _showFolderActions(context, folder),
                      )),
                ],
              ),
            ),
          ),
          
          // BOTTOM BUTTONS PANEL (Stays pinned to bottom)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _BottomButton(
                  icon: Icons.security_rounded,
                  title: 'Security',
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => const SecuritySettingsDialog(),
                  ),
                ),
                _BottomButton(
                  icon: Icons.backup_outlined,
                  title: 'Backup & Restore',
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => const BackupDialog(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  void _showFolderActions(BuildContext context, Folder folder) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename folder'),
              onTap: () {
                Navigator.pop(context);
                _showFolderDialog(context, folder: folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Delete folder', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteFolder(context, folder);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteFolder(BuildContext context, Folder folder) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text('Notes inside "${folder.name}" will become uncategorized.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.tonal(
            onPressed: () {
              context.read<NotesProvider>().removeFolder(folder.id);
              Navigator.pop(context);
              _snack(context, 'Folder deleted.');
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showFolderDialog(BuildContext context, {Folder? folder}) {
    final ctrl = TextEditingController(text: folder?.name ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(folder == null ? 'New folder' : 'Rename folder'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Folder name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                if (folder == null) {
                  context.read<NotesProvider>().createFolder(name);
                } else {
                  context.read<NotesProvider>().renameFolder(folder.id, name);
                }
              }
              Navigator.pop(context);
            },
            child: Text(folder == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _NavItem({
    required this.icon,
    required this.title,
    required this.selected,
    required this.count,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        dense: true,
        onTap: onTap,
        onLongPress: onLongPress,
        leading: Icon(icon, size: 20, color: selected ? const Color(0xFFFBC02D) : null),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text('$count', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        selected: selected,
        selectedTileColor: const Color(0xFFFBC02D).withOpacity(.18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

class _BottomButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _BottomButton({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 19),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

class _QuickComposer extends StatefulWidget {
  const _QuickComposer();

  @override
  State<_QuickComposer> createState() => _QuickComposerState();
}

class _QuickComposerState extends State<_QuickComposer> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    context.read<NotesProvider>().upsertNote(
          Note(
            id: _newId('note'),
            title: '',
            content: text,
            type: NoteType.text,
            status: NoteStatus.active,
            folderId: null,
            labelIds: [],
            colorHex: '#FFFFFF',
            shoppingItems: [],
            checklistItems: [],
            attachments: [],
          ),
        );
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<NotesProvider>().isDarkMode;
    return Material(
      color: isDark ? const Color(0xFF1F2937) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.lightbulb_outline_rounded, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 3,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  hintText: 'Take a note...',
                  filled: false,
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(onPressed: _save, icon: const Icon(Icons.check_rounded)),
          ],
        ),
      ),
    );
  }
}

class _LabelsBar extends StatelessWidget {
  const _LabelsBar();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotesProvider>();
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Label'),
              onPressed: () => _showLabelDialog(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: state.selectedLabelId == null,
              label: const Text('All labels'),
              onSelected: (_) => context.read<NotesProvider>().selectLabel(null),
            ),
          ),
          ...state.labels.map(
            (label) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: state.selectedLabelId == label.id,
                avatar: CircleAvatar(backgroundColor: label.color, radius: 5),
                label: Text(label.name),
                onSelected: (_) => context.read<NotesProvider>().selectLabel(label.id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLabelDialog(BuildContext context) {
    final ctrl = TextEditingController();
    Color selected = const Color(0xFFF59E0B);
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          title: const Text('New label'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Label name')),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  const Color(0xFFF59E0B),
                  const Color(0xFF3B82F6),
                  const Color(0xFF10B981),
                  const Color(0xFFEF4444),
                  const Color(0xFFA855F7),
                ].map((c) {
                  return GestureDetector(
                    onTap: () => setState(() => selected = c),
                    child: CircleAvatar(
                      backgroundColor: c,
                      child: selected == c ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  context.read<NotesProvider>().createLabel(ctrl.text.trim(), selected);
                }
                Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        );
      }),
    );
  }
}

class _NotesTitleRow extends StatelessWidget {
  final int total;
  const _NotesTitleRow({required this.total});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotesProvider>();
    final label = switch (state.currentView) {
      NoteView.notes => 'Notes',
      NoteView.reminders => 'Reminders',
      NoteView.archive => 'Archive',
      NoteView.trash => 'Trash',
      NoteView.locked => 'Locked Notes',
    };
    return Row(
      children: [
        Expanded(
          child: Text('$label ($total)',
              style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w800)),
        ),
        Text(state.isGridView ? 'Grid' : 'List',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool scrollable;
  const _EmptyState({this.scrollable = false});

  @override
  Widget build(BuildContext context) {
    final child = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 72, color: Colors.grey.withOpacity(.5)),
          const SizedBox(height: 14),
          const Text('No notes here', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Tap Add or use quick note to create one.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
    if (!scrollable) return child;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [SizedBox(height: MediaQuery.of(context).size.height * .55, child: child)],
    );
  }
}

class _NotesGrid extends StatelessWidget {
  final void Function({Note? note, NoteType type, NoteAttachment? attachment}) onOpen;
  const _NotesGrid({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotesProvider>();
    final notes = state.visibleNotes;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      int count = 2;
      if (width > 700) count = 3;
      if (width > 1050) count = 4;
      if (width > 1400) count = 5;
      return GridView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: notes.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: width < 420 ? .78 : .86,
        ),
        itemBuilder: (_, index) => NoteCard(
          note: notes[index],
          onOpen: () => onOpen(note: notes[index], type: notes[index].type),
        ),
      );
    });
  }
}

class _NotesList extends StatelessWidget {
  final void Function({Note? note, NoteType type, NoteAttachment? attachment}) onOpen;
  const _NotesList({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<NotesProvider>().visibleNotes;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) => NoteCard(
        note: notes[index],
        listMode: true,
        onOpen: () => onOpen(note: notes[index], type: notes[index].type),
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  final Note note;
  final bool listMode;
  final VoidCallback onOpen;

  const NoteCard({super.key, required this.note, required this.onOpen, this.listMode = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotesProvider>();
    final baseColor = parseHexColor(note.colorHex, fallback: state.isDarkMode ? const Color(0xFF1F2937) : Colors.white);
    final cardColor = state.isDarkMode
        ? Color.lerp(baseColor, const Color(0xFF111827), .72)!
        : baseColor;
    final textColor = state.isDarkMode ? Colors.white.withOpacity(.92) : Colors.black87;
    final subText = state.isDarkMode ? Colors.white70 : Colors.black54;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _handleOpen(context),
        onLongPress: () => _showOptions(context),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: listMode ? const BoxConstraints(minHeight: 116) : null,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: state.isDarkMode ? Colors.white12 : Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: listMode ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      note.title.trim().isEmpty ? 'Untitled' : note.title.trim(),
                      maxLines: listMode ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (note.isPinned) Icon(Icons.push_pin_rounded, size: 16, color: subText),
                  if (note.isLocked) Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.lock_rounded, size: 16, color: subText),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (note.isLocked)
                Text('Locked note', style: TextStyle(color: subText, fontSize: 13))
              else ...[
                if (note.content.trim().isNotEmpty)
                  Padding(
                    padding: EdgeInsets.zero,
                    child: Text(
                      note.content.trim(),
                      maxLines: listMode ? 2 : 5,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subText, height: 1.35, fontSize: 13),
                    ),
                  ),
                if (note.type == NoteType.shopping && note.shoppingItems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${note.shoppingItems.where((e) => e.isChecked).length}/${note.shoppingItems.length} items • ৳${note.shoppingItems.fold<double>(0, (p, e) => p + e.unitPrice).toStringAsFixed(0)}',
                      style: TextStyle(color: subText, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                if (note.type == NoteType.checklist && note.checklistItems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: note.checklistItems.take(listMode ? 2 : 4).map((item) {
                        return Row(
                          children: [
                            Icon(item.isChecked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 15, color: subText),
                            const SizedBox(width: 5),
                            Expanded(child: Text(item.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: subText, fontSize: 12))),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
              ],
              if (!listMode) const Spacer(),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (note.reminderAt != null)
                    _MiniChip(
                      icon: note.reminderFired ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                      label: _reminderChipLabel(note),
                      color: subText,
                    ),
                  if (note.attachments.isNotEmpty)
                    _MiniChip(icon: Icons.attach_file_rounded, label: '${note.attachments.length} asset${note.attachments.length == 1 ? '' : 's'}', color: subText),
                  if (note.type != NoteType.text)
                    _MiniChip(icon: _typeIcon(note.type), label: note.type.name, color: subText),
                  ...note.labelIds.map((id) {
                    final label = state.labels.where((l) => l.id == id).firstOrNull;
                    if (label == null) return const SizedBox.shrink();
                    return _MiniChip(label: label.name, color: subText);
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleOpen(BuildContext context) {
    if (!note.isLocked) {
      onOpen();
      return;
    }
    _showUnlockNoteDialog(context);
  }

  void _showUnlockNoteDialog(BuildContext context) {
    final pinCtrl = TextEditingController();
    String error = '';
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          title: const Text('Unlock note'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinCtrl,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(counterText: '', hintText: 'PIN'),
              ),
              if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (pinCtrl.text == context.read<NotesProvider>().currentPin) {
                  Navigator.pop(context);
                  onOpen();
                } else {
                  setState(() => error = 'Wrong PIN');
                }
              },
              child: const Text('Unlock'),
            ),
          ],
        );
      }),
    );
  }

  void _showOptions(BuildContext context) {
    final state = context.read<NotesProvider>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(note.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
                title: Text(note.isPinned ? 'Unpin' : 'Pin'),
                onTap: () {
                  Navigator.pop(context);
                  state.togglePin(note.id);
                },
              ),
              if (note.status == NoteStatus.active)
                ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: const Text('Archive'),
                  onTap: () {
                    Navigator.pop(context);
                    state.archiveNote(note.id);
                    _snack(context, 'Note archived', actionLabel: 'Undo', action: () => state.unarchiveNote(note.id));
                  },
                ),
              if (note.status == NoteStatus.archived)
                ListTile(
                  leading: const Icon(Icons.unarchive_outlined),
                  title: const Text('Unarchive'),
                  onTap: () {
                    Navigator.pop(context);
                    state.unarchiveNote(note.id);
                  },
                ),
              if (note.status == NoteStatus.trashed) ...[
                ListTile(
                  leading: const Icon(Icons.restore_from_trash_outlined),
                  title: const Text('Restore'),
                  onTap: () {
                    Navigator.pop(context);
                    state.restoreNote(note.id);
                    _snack(context, 'Note restored');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                  title: const Text('Delete forever', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(context);
                    state.deleteForever(note.id);
                    _snack(context, 'Note permanently deleted');
                  },
                ),
              ] else
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  title: const Text('Move to trash', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(context);
                    state.moveToTrash(note.id);
                    _snack(context, 'Moved to trash', actionLabel: 'Undo', action: () => state.restoreNote(note.id));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateLabel(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  static String _reminderChipLabel(Note note) {
    final due = note.reminderAt;
    if (due == null) return '';
    if (note.reminderFired || !due.isAfter(DateTime.now())) return 'Reminder sent';
    return _dateLabel(due);
  }

  static IconData _typeIcon(NoteType type) => switch (type) {
        NoteType.text => Icons.notes_rounded,
        NoteType.checklist => Icons.check_box_outlined,
        NoteType.shopping => Icons.shopping_basket_outlined,
        NoteType.drawing => Icons.draw_outlined,
        NoteType.audio => Icons.mic_none_rounded,
        NoteType.image => Icons.image_outlined,
      };
}

// ignore: unused_element
class _AttachmentPreviewStrip extends StatelessWidget {
  final Note note;
  const _AttachmentPreviewStrip({required this.note});

  @override
  Widget build(BuildContext context) {
    final firstImage = note.attachments.where((a) => a.type == 'image' || a.type == 'drawing').firstOrNull;
    if (firstImage != null) {
      try {
        final bytes = base64Decode(firstImage.data);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, height: 86, width: double.infinity, fit: BoxFit.cover),
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    final audioCount = note.attachments.where((a) => a.type == 'audio').length;
    if (audioCount > 0) {
      return Row(
        children: [
          const Icon(Icons.mic_none_rounded, size: 18),
          const SizedBox(width: 6),
          Text('$audioCount audio recording${audioCount > 1 ? 's' : ''}', style: const TextStyle(fontSize: 12)),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _MiniChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color color;

  const _MiniChip({this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

void _snack(BuildContext context, String message, {String? actionLabel, VoidCallback? action}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: action ?? () {}),
    ),
  );
}

extension FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

// ================================================================
// EDITOR
// ================================================================

class NoteEditorScreen extends StatefulWidget {
  final Note? initialNote;
  final NoteType initialType;
  final NoteAttachment? initialAttachment;
  final bool autoStartRecording;

  const NoteEditorScreen({
    super.key,
    this.initialNote,
    this.initialType = NoteType.text,
    this.initialAttachment,
    this.autoStartRecording = false,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController titleCtrl;
  late final TextEditingController bodyCtrl;
  late NoteType type;
  late NoteStatus status;
  late String colorHex;
  late bool isPinned;
  late bool isLocked;
  late String? folderId;
  late List<String> labelIds;
  late List<ShoppingItem> shoppingItems;
  late List<ChecklistItem> checklistItems;
  late List<NoteAttachment> attachments;
  DateTime? reminderAt;
  bool reminderFired = false;
  String? activeNoteId;
  bool skipAutoSave = false;
  bool isRecording = false;
  String? recordingPath;
  final AudioRecorder _recorder = AudioRecorder();

  final keepColors = const <String>[
    '#FFFFFF',
    '#FFF8B8',
    '#FAD2CF',
    '#FADCB3',
    '#D7F5D1',
    '#C8F1EF',
    '#D7E8FF',
    '#E6D7FF',
    '#F4D7F4',
    '#E5E7EB',
  ];

  @override
  void initState() {
    super.initState();
    final note = widget.initialNote;
    activeNoteId = note?.id;
    titleCtrl = TextEditingController(text: note?.title ?? '');
    bodyCtrl = TextEditingController(text: note?.content ?? '');
    type = note?.type ?? widget.initialType;
    status = note?.status ?? NoteStatus.active;
    colorHex = note?.colorHex ?? '#FFFFFF';
    isPinned = note?.isPinned ?? false;
    isLocked = note?.isLocked ?? false;
    folderId = note?.folderId;
    labelIds = List<String>.from(note?.labelIds ?? []);
    shoppingItems = note?.shoppingItems.map((e) => e.copy()).toList() ?? [];
    checklistItems = note?.checklistItems.map((e) => e.copy()).toList() ?? [];
    attachments = note?.attachments.map((e) => e.copy()).toList() ?? [];
    reminderAt = note?.reminderAt;
    reminderFired = note?.reminderFired ?? false;
    if (widget.initialAttachment != null) attachments.add(widget.initialAttachment!);
    if (type == NoteType.shopping && shoppingItems.isEmpty) _addShoppingItem();
    if (type == NoteType.checklist && checklistItems.isEmpty) _addChecklistItem();
    if (widget.autoStartRecording) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !isRecording) _toggleRecording();
      });
    }
  }

  @override
  void dispose() {
    _autoSave();
    _recorder.dispose();
    titleCtrl.dispose();
    bodyCtrl.dispose();
    super.dispose();
  }

  Note _buildNote() {
    return Note(
      id: activeNoteId ?? _newId('note'),
      title: titleCtrl.text.trim(),
      content: bodyCtrl.text.trim(),
      type: type,
      status: status,
      folderId: folderId,
      labelIds: List<String>.from(labelIds),
      colorHex: colorHex,
      isPinned: isPinned,
      isLocked: isLocked,
      createdAt: widget.initialNote?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      reminderAt: reminderAt,
      reminderFired: reminderFired,
      trashedAt: widget.initialNote?.trashedAt,
      shoppingItems: type == NoteType.shopping ? shoppingItems : [],
      checklistItems: type == NoteType.checklist ? checklistItems : [],
      attachments: attachments,
    );
  }

  void _autoSave() {
    if (skipAutoSave) return;
    final note = _buildNote();
    if (note.hasContent) {
      activeNoteId = note.id;
      context.read<NotesProvider>().upsertNote(note);
    }
  }

  void _saveAndClose() {
    final note = _buildNote();
    if (note.hasContent) {
      activeNoteId = note.id;
      context.read<NotesProvider>().upsertNote(note);
    }
    skipAutoSave = true;
    Navigator.pop(context);
  }

  void _delete() {
    final id = activeNoteId ?? widget.initialNote?.id;
    if (id != null) context.read<NotesProvider>().moveToTrash(id);
    skipAutoSave = true;
    Navigator.pop(context);
  }

  Future<void> _pickReminder() async {
    final date = await showDatePicker(
      context: context,
      initialDate: reminderAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(reminderAt ?? DateTime.now()));
    if (time == null) return;
    setState(() {
      reminderAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      reminderFired = false;
    });
  }

  Future<void> _showAddModal() async {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add to this note', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _CreateTile(icon: Icons.notes_rounded, title: 'Note', onTap: () { Navigator.pop(context); setState(() => type = NoteType.text); }),
                  _CreateTile(icon: Icons.image_outlined, title: 'Image', onTap: () async { Navigator.pop(context); await _attachImage(); }),
                  _CreateTile(icon: Icons.mic_none_rounded, title: 'Audio', onTap: () { Navigator.pop(context); _toggleRecording(); }),
                  _CreateTile(icon: Icons.draw_outlined, title: 'Drawing', onTap: () async { Navigator.pop(context); await _attachDrawing(); }),
                  _CreateTile(icon: Icons.shopping_basket_outlined, title: 'Shopping', onTap: () { Navigator.pop(context); setState(() { type = NoteType.shopping; if (shoppingItems.isEmpty) _addShoppingItem(); }); }),
                  _CreateTile(icon: Icons.check_box_outlined, title: 'Checklist', onTap: () { Navigator.pop(context); setState(() { type = NoteType.checklist; if (checklistItems.isEmpty) _addChecklistItem(); }); }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _attachImage() async {
    final attachment = await _pickImageAttachment(context);
    if (attachment == null) return;
    setState(() {
      type = NoteType.image;
      attachments.add(attachment);
    });
  }

  Future<void> _attachDrawing() async {
    final attachment = await Navigator.of(context).push<NoteAttachment>(
      MaterialPageRoute(builder: (_) => const DrawingCaptureScreen()),
    );
    if (attachment == null) return;
    setState(() {
      type = NoteType.drawing;
      attachments.add(attachment);
    });
  }

  Future<void> _toggleRecording() async {
    if (isRecording) {
      final path = await _recorder.stop();
      setState(() {
        isRecording = false;
        recordingPath = null;
        if (path != null && path.trim().isNotEmpty) {
          type = NoteType.audio;
          attachments.add(NoteAttachment(
            id: _newId('audio'),
            type: 'audio',
            data: path,
            fileName: path.split('/').last,
          ));
        }
      });
      if (mounted) _snack(context, 'Audio recording attached.');
      return;
    }

    try {
      final micAllowed = await AppPermissionService.ensureMicrophone(context);
      if (!micAllowed) return;
      if (!await _recorder.hasPermission()) {
        if (mounted) _snack(context, 'Microphone permission is required.');
        return;
      }
      final extension = kIsWeb ? 'wav' : 'm4a';
      final encoder = kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc;
      final path = await createLocalAttachmentPath('neonote_audio_${DateTime.now().millisecondsSinceEpoch}.$extension');
      await _recorder.start(RecordConfig(encoder: encoder), path: path);
      setState(() {
        isRecording = true;
        recordingPath = path;
      });
      if (mounted) _snack(context, 'Recording started. Tap Stop to attach.');
    } catch (e) {
      if (mounted) _snack(context, 'Audio recording failed: $e');
    }
  }

  void _addShoppingItem() {
    shoppingItems.add(ShoppingItem(id: _newId('shop'), name: '', unitPrice: 0));
  }

  void _addChecklistItem() {
    checklistItems.add(ChecklistItem(id: _newId('check'), text: ''));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotesProvider>();
    final noteColor = parseHexColor(colorHex, fallback: state.isDarkMode ? const Color(0xFF1F2937) : Colors.white);
    final surface = state.isDarkMode ? Color.lerp(noteColor, const Color(0xFF111827), .72)! : noteColor;
    final textColor = state.isDarkMode ? Colors.white : Colors.black87;

    return WillPopScope(
      onWillPop: () async {
        _autoSave();
        return true;
      },
      child: Scaffold(
        backgroundColor: surface,
        appBar: AppBar(
          backgroundColor: surface,
          foregroundColor: textColor,
          title: Text(widget.initialNote == null ? 'New note' : 'Edit note'),
          actions: [
            IconButton(
              tooltip: isPinned ? 'Unpin' : 'Pin',
              onPressed: () => setState(() => isPinned = !isPinned),
              icon: Icon(isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
            ),
            IconButton(
              tooltip: isLocked ? 'Unlock note' : 'Lock note',
              onPressed: () => setState(() => isLocked = !isLocked),
              icon: Icon(isLocked ? Icons.lock_rounded : Icons.lock_open_outlined),
            ),
            IconButton(
              tooltip: 'Reminder',
              onPressed: _pickReminder,
              icon: Icon(reminderAt == null ? Icons.notifications_none_rounded : Icons.notifications_active_rounded),
            ),
            if (widget.initialNote != null)
              IconButton(
                tooltip: 'Move to trash',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            IconButton(onPressed: _saveAndClose, icon: const Icon(Icons.check_rounded)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 110),
          children: [
            _EditorMetaCard(
              folderId: folderId,
              labelIds: labelIds,
              colorHex: colorHex,
              colors: keepColors,
              onFolderChanged: (v) => setState(() => folderId = v),
              onLabelToggle: (id) => setState(() => labelIds.contains(id) ? labelIds.remove(id) : labelIds.add(id)),
              onColorChanged: (v) => setState(() => colorHex = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                hintText: 'Title',
                hintStyle: TextStyle(color: textColor.withOpacity(.45)),
              ),
            ),
            if (type != NoteType.shopping && type != NoteType.checklist)
              TextField(
                controller: bodyCtrl,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: TextStyle(color: textColor, fontSize: 16, height: 1.45),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  hintText: 'Take a note...',
                  hintStyle: TextStyle(color: textColor.withOpacity(.45)),
                ),
              ),
            if (type == NoteType.shopping) _ShoppingEditor(items: shoppingItems, onChanged: () => setState(() {}), onAdd: () => setState(_addShoppingItem)),
            if (type == NoteType.checklist) _ChecklistEditor(items: checklistItems, onChanged: () => setState(() {}), onAdd: () => setState(_addChecklistItem)),
            if (reminderAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  children: [
                    InputChip(
                      avatar: const Icon(Icons.notifications_none_rounded, size: 18),
                      label: Text('Reminder: ${reminderAt!.day}/${reminderAt!.month}/${reminderAt!.year} ${reminderAt!.hour.toString().padLeft(2, '0')}:${reminderAt!.minute.toString().padLeft(2, '0')}'),
                      onDeleted: () => setState(() { reminderAt = null; reminderFired = false; }),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            if (attachments.isNotEmpty) _AttachmentsEditor(attachments: attachments, onRemove: (id) => setState(() => attachments.removeWhere((a) => a.id == id))),
            if (isRecording)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: _toggleRecording,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text('Stop recording${recordingPath == null ? '' : ' and attach'}'),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: state.isDarkMode ? Colors.white10 : Colors.black12)),
            ),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _showAddModal,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add'),
                ),
                const SizedBox(width: 8),
                if (isRecording)
                  FilledButton.icon(
                    onPressed: _toggleRecording,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                  ),
                const Spacer(),
                Text(_typeLabel(type), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _typeLabel(NoteType value) => switch (value) {
        NoteType.text => 'Note',
        NoteType.checklist => 'Checklist',
        NoteType.shopping => 'Shopping',
        NoteType.drawing => 'Drawing',
        NoteType.audio => 'Audio',
        NoteType.image => 'Image',
      };
}

class _EditorMetaCard extends StatelessWidget {
  final String? folderId;
  final List<String> labelIds;
  final String colorHex;
  final List<String> colors;
  final ValueChanged<String?> onFolderChanged;
  final ValueChanged<String> onLabelToggle;
  final ValueChanged<String> onColorChanged;

  const _EditorMetaCard({
    required this.folderId,
    required this.labelIds,
    required this.colorHex,
    required this.colors,
    required this.onFolderChanged,
    required this.onLabelToggle,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotesProvider>();
    final cardColor = state.isDarkMode ? const Color(0xFF1F2937).withOpacity(.72) : Colors.white.withOpacity(.82);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: state.isDarkMode ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String?>(
            value: folderId,
            isExpanded: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.folder_open_outlined), labelText: 'Folder'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Uncategorized')),
              ...state.folders.map((f) => DropdownMenuItem<String?>(value: f.id, child: Text(f.name))),
            ],
            onChanged: onFolderChanged,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: state.labels.map((label) {
              final selected = labelIds.contains(label.id);
              return FilterChip(
                selected: selected,
                avatar: CircleAvatar(backgroundColor: label.color, radius: 5),
                label: Text(label.name),
                onSelected: (_) => onLabelToggle(label.id),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: colors.map((hex) {
              final selected = colorHex == hex;
              final color = parseHexColor(hex, fallback: Colors.white);
              return GestureDetector(
                onTap: () => onColorChanged(hex),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.black26, width: selected ? 3 : 1),
                  ),
                  child: selected ? const Icon(Icons.check_rounded, size: 18) : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ShoppingEditor extends StatelessWidget {
  final List<ShoppingItem> items;
  final VoidCallback onChanged;
  final VoidCallback onAdd;

  const _ShoppingEditor({required this.items, required this.onChanged, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (p, e) => p + e.unitPrice);
    final remaining = items.where((e) => !e.isChecked).fold<double>(0, (p, e) => p + e.unitPrice);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Checkbox(value: item.isChecked, onChanged: (v) { item.isChecked = v ?? false; onChanged(); }),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: item.name,
                      decoration: const InputDecoration(hintText: 'Item'),
                      onChanged: (v) => item.name = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: TextFormField(
                      initialValue: item.unitPrice == 0 ? '' : item.unitPrice.toStringAsFixed(0),
                      decoration: const InputDecoration(hintText: '৳'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) { item.unitPrice = double.tryParse(v) ?? 0; onChanged(); },
                    ),
                  ),
                  IconButton(onPressed: () { items.remove(item); onChanged(); }, icon: const Icon(Icons.close_rounded)),
                ],
              ),
            )),
        Align(alignment: Alignment.centerLeft, child: FilledButton.tonalIcon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Add item'))),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.black.withOpacity(.06), borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Remaining'), Text('৳${remaining.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))]),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total'), Text('৳${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))]),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChecklistEditor extends StatelessWidget {
  final List<ChecklistItem> items;
  final VoidCallback onChanged;
  final VoidCallback onAdd;

  const _ChecklistEditor({required this.items, required this.onChanged, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Checkbox(value: item.isChecked, onChanged: (v) { item.isChecked = v ?? false; onChanged(); }),
                  Expanded(
                    child: TextFormField(
                      initialValue: item.text,
                      decoration: const InputDecoration(hintText: 'List item'),
                      onChanged: (v) => item.text = v,
                    ),
                  ),
                  IconButton(onPressed: () { items.remove(item); onChanged(); }, icon: const Icon(Icons.close_rounded)),
                ],
              ),
            )),
        Align(alignment: Alignment.centerLeft, child: FilledButton.tonalIcon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Add item'))),
      ],
    );
  }
}

class _AttachmentsEditor extends StatelessWidget {
  final List<NoteAttachment> attachments;
  final ValueChanged<String> onRemove;

  const _AttachmentsEditor({required this.attachments, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final itemWidth = constraints.maxWidth < 420 ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: attachments.map((a) {
          return SizedBox(
            width: itemWidth,
            child: _AttachmentTile(attachment: a, onRemove: () => onRemove(a.id)),
          );
        }).toList(),
      );
    });
  }
}

class _AttachmentTile extends StatelessWidget {
  final NoteAttachment attachment;
  final VoidCallback onRemove;

  const _AttachmentTile({required this.attachment, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (attachment.type == 'image' || attachment.type == 'drawing') {
      try {
        body = Image.memory(base64Decode(attachment.data), height: 160, width: double.infinity, fit: BoxFit.cover);
      } catch (_) {
        body = const SizedBox(height: 120, child: Center(child: Text('Preview unavailable')));
      }
    } else {
      body = SizedBox(
        height: 120,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic_rounded, size: 36),
              const SizedBox(height: 8),
              Text(attachment.fileName ?? 'Audio recording', maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(18)),
            child: body,
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton.filledTonal(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
              style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(.35), foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

Future<NoteAttachment?> _pickImageAttachment(BuildContext context) async {
  try {
    final allowed = await AppPermissionService.ensureGallery(context);
    if (!allowed) return null;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 84,
      maxWidth: 1600,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return NoteAttachment(
      id: _newId('image'),
      type: 'image',
      data: base64Encode(bytes),
      fileName: picked.name,
    );
  } catch (e) {
    if (context.mounted) _snack(context, 'Image attach failed: $e');
    return null;
  }
}

// ================================================================
// DRAWING CAPTURE
// ================================================================

class DrawingCaptureScreen extends StatefulWidget {
  const DrawingCaptureScreen({super.key});

  @override
  State<DrawingCaptureScreen> createState() => _DrawingCaptureScreenState();
}

class _DrawingCaptureScreenState extends State<DrawingCaptureScreen> {
  final DrawingController _drawingController = DrawingController();
  final TransformationController _transformController = TransformationController();

  @override
  void dispose() {
    _drawingController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _saveDrawing() async {
    try {
      final byteData = await _drawingController.getImageData();
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) _snack(context, 'Draw something before saving.');
        return;
      }
      final jsonData = const JsonEncoder.withIndent('  ').convert(_drawingController.getJsonList());
      final attachment = NoteAttachment(
        id: _newId('drawing'),
        type: 'drawing',
        data: base64Encode(bytes),
        fileName: 'drawing_${DateTime.now().millisecondsSinceEpoch}.png',
        drawingJson: jsonData,
      );
      if (mounted) Navigator.pop(context, attachment);
    } catch (e) {
      if (mounted) _snack(context, 'Drawing save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drawing'),
        actions: [IconButton(onPressed: _saveDrawing, icon: const Icon(Icons.check_rounded))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                return DrawingBoard(
                  controller: _drawingController,
                  transformationController: _transformController,
                  background: Container(width: constraints.maxWidth, height: constraints.maxHeight, color: Colors.white),
                );
              }),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DrawingBar(
                controller: _drawingController,
                tools: [
                  DefaultActionItem.undo(),
                  DefaultActionItem.redo(),
                  DefaultActionItem.clear(),
                  DefaultActionItem.slider(),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DrawingBar(
                controller: _drawingController,
                tools: [
                  DefaultToolItem.pen(),
                  DefaultToolItem.brush(),
                  DefaultToolItem.rectangle(),
                  DefaultToolItem.circle(),
                  DefaultToolItem.straightLine(),
                  DefaultToolItem.eraser(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// SETTINGS + BACKUP
// ================================================================

class SecuritySettingsDialog extends StatefulWidget {
  const SecuritySettingsDialog({super.key});

  @override
  State<SecuritySettingsDialog> createState() => _SecuritySettingsDialogState();
}

class _SecuritySettingsDialogState extends State<SecuritySettingsDialog> {
  late final TextEditingController pinCtrl;
  late bool lockEnabled;
  late bool fingerprintEnabled;

  @override
  void initState() {
    super.initState();
    final state = context.read<NotesProvider>();
    pinCtrl = TextEditingController(text: state.currentPin);
    lockEnabled = state.isLockEnabled;
    fingerprintEnabled = !kIsWeb && state.isFingerprintActive;
  }

  @override
  void dispose() {
    pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Security'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require PIN on app open'),
              value: lockEnabled,
              onChanged: (v) => setState(() => lockEnabled = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fingerprint unlock'),
              subtitle: const Text(kIsWeb ? 'Not available on Web. Test on Android/iOS/macOS/Windows.' : 'Uses device biometric authentication.'),
              value: !kIsWeb && fingerprintEnabled,
              onChanged: !kIsWeb && lockEnabled ? (v) => setState(() => fingerprintEnabled = v) : null,
            ),
            if (lockEnabled)
              TextField(
                controller: pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(labelText: '4-digit PIN', counterText: ''),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (lockEnabled && pinCtrl.text.length != 4) {
              _snack(context, 'PIN must be exactly 4 digits.');
              return;
            }
            context.read<NotesProvider>().updateSecurity(
                  lockEnabled: lockEnabled,
                  fingerprintEnabled: !kIsWeb && fingerprintEnabled,
                  pin: pinCtrl.text,
                );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class BackupDialog extends StatefulWidget {
  const BackupDialog({super.key});

  @override
  State<BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<BackupDialog> {
  late final TextEditingController dataCtrl;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    dataCtrl = TextEditingController(text: context.read<NotesProvider>().generateJsonBackup());
  }

  @override
  void dispose() {
    dataCtrl.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => busy = true);
    try {
      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final result = await saveBackupFile('NeoNote_backup_$stamp.json', dataCtrl.text);
      if (mounted) _snack(context, result);
    } catch (e) {
      if (mounted) _snack(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

 Future<void> _pickBackupFile() async {
  try {
    // CORRECT: .platform is required to tap into the underlying instance wrapper
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true, 
    );

    final file = result?.files.singleOrNull; // Safely handles empty or single results
    final bytes = file?.bytes;
    
    if (bytes == null || bytes.isEmpty) return;
    
    dataCtrl.text = utf8.decode(bytes);
    
    if (mounted) _snack(context, 'Backup file loaded. Tap Restore to import.');
  } catch (e) {
    if (mounted) _snack(context, 'Backup file pick failed: $e');
  }
}

  void _restore() {
    final ok = context.read<NotesProvider>().importJsonBackup(dataCtrl.text);
    if (ok) {
      Navigator.pop(context);
      _snack(context, 'Backup restored successfully.');
    } else {
      _snack(context, 'Invalid backup JSON.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backup & Restore'),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: dataCtrl,
          minLines: 8,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(hintText: 'Paste backup JSON here'),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : _export, child: Text(busy ? 'Saving...' : 'Save file')),
        TextButton(onPressed: _pickBackupFile, child: const Text('Pick file')),
        TextButton(onPressed: () => Share.share(dataCtrl.text, subject: 'NeoNote backup'), child: const Text('Share')),
        TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: dataCtrl.text)); }, child: const Text('Copy')),
        FilledButton(onPressed: _restore, child: const Text('Restore')),
      ],
    );
  }
}
