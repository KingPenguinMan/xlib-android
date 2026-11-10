import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controller.dart';
import 'widgets.dart';
import 'screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ReaderApp(controller: ReaderController()));
}

ThemeData readerTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff286b5b),
    brightness: brightness,
    surface: dark ? const Color(0xff111b18) : const Color(0xfff7f7f2),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .48),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
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
      color: dark ? const Color(0xff1b2823) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.35,
        letterSpacing: -.8,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(
        fontSize: 16,
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
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 54,
        titleSpacing: 14,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 26),
            SizedBox(width: 8),
            Text('z-lib', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
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
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: c.selectedTab,
        onDestinationSelected: c.setTab,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.travel_explore_rounded),
            label: '找书',
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
