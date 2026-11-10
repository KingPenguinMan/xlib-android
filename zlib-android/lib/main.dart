import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controller.dart';
import 'widgets.dart';
import 'screens.dart';
import 'reading_invite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ReaderApp(controller: ReaderController()));
}

ThemeData readerTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff435534),
    brightness: brightness,
    surface: dark ? const Color(0xff1e221b) : const Color(0xfffaf6ec),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    navigationBarTheme: const NavigationBarThemeData(
      iconTheme: WidgetStatePropertyAll(IconThemeData(size: 19)),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      shape: Border(
        bottom: BorderSide(color: scheme.outlineVariant, width: .6),
      ),
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .48),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xff272d23) : const Color(0xfff6f1e6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .5),
      space: 1,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'serif',
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.35,
        letterSpacing: -.8,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'serif',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      titleLarge: TextStyle(
        fontFamily: 'serif',
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        fontFamily: 'serif',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.5,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.6),
      bodySmall: TextStyle(fontSize: 12, height: 1.5),
    ),
  );
}

class ReaderApp extends StatefulWidget {
  final ReaderController controller;
  final bool autoStart;
  const ReaderApp({super.key, required this.controller, this.autoStart = true});
  @override
  State<ReaderApp> createState() => _ReaderAppState();
}

class _ReaderAppState extends State<ReaderApp> {
  @override
  void initState() {
    super.initState();
    if (widget.autoStart) unawaited(widget.controller.init());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => MaterialApp(
      title: 'z-lib',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: readerTheme(Brightness.light),
      darkTheme: readerTheme(Brightness.dark),
      themeMode: widget.controller.theme,
      home: AppShell(controller: widget.controller),
    ),
  );
}

class AppShell extends StatefulWidget {
  final ReaderController controller;
  const AppShell({super.key, required this.controller});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  bool _promptsStarted = false;
  Future<void> _startupPrompts() async {
    if (!mounted) return;
    if (!c.hideGroupInvite) {
      final choice = await showDialog<InviteChoice>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ReadingInvite(),
      );
      if (choice?.hide == true) {
        c.hideGroupInvite = true;
        try {
          await c.persist();
          if (mounted) c.say('以后可以从侧边栏「一起读书」加入群聊');
        } catch (_) {
          c.hideGroupInvite = false;
          if (mounted) c.say('未能保存邀请偏好，请稍后重试');
        }
      }
      if (choice?.join == true) await _open(kReadingClubUrl);
    }
  }

  Future<void> _open(String url) async {
    try {
      await c.native.openUrl(url);
    } catch (_) {
      c.say('无法打开链接，请检查设备是否已安装浏览器');
    }
  }

  int _noticeId = 0;
  ReaderController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_notice);
  }

  void _notice() {
    if (!mounted || c.noticeId == _noticeId) return;
    _noticeId = c.noticeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(c.notice),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(c.refreshDownloads());
  }

  @override
  void dispose() {
    c.removeListener(_notice);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!c.ready)
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(size: 64),
              SizedBox(height: 24),
              Text('z-lib · 把好书带在身边'),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    if (!_promptsStarted) {
      _promptsStarted = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_startupPrompts()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 0,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'z-lib',
              style: TextStyle(
                fontSize: 22,
                fontFamily: 'serif',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          if (c.selectedTab == 1 && c.loggedIn)
            IconButton(
              tooltip: '刷新历史',
              icon: const Icon(Icons.refresh),
              onPressed: c.historyLoading ? null : c.loadHistory,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () => showRoutes(context, c),
              icon: c.probing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.lan_outlined,
                      size: 18,
                      color: c.healthyCount > 0 ? colors.primary : colors.error,
                    ),
              label: Text(
                c.probing
                    ? '检测线路'
                    : c.healthyCount == 0
                    ? '选择线路'
                    : '${c.automatic ? '自动' : '手动'} · ${c.host}',
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(maximumSize: const Size(220, 48)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: c.selectedTab,
          children: [
            SearchScreen(controller: c),
            HistoryScreen(controller: c),
          ],
        ),
      ),
      drawer: Drawer(
        width: (MediaQuery.sizeOf(context).width * .82)
            .clamp(280.0, 320.0)
            .toDouble(),
        child: SafeArea(child: ProfileScreen(controller: c)),
      ),
      bottomNavigationBar: NavigationBar(
        height: 52,
        backgroundColor: colors.surface,
        indicatorColor: colors.primary.withValues(alpha: .10),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: c.selectedTab,
        onDestinationSelected: c.setTab,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: '首页',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: '历史',
          ),
        ],
      ),
    );
  }
}
