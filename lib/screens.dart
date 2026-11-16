import 'dart:async';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'domain.dart';
import 'native.dart';
import 'preview_loader.dart';
import 'update.dart';
import 'weread/weread_controller.dart';
import 'weread/weread_screens.dart';
import 'widgets.dart';

const String kReadingClubUrl = 'https://qm.qq.com/q/lGu49c8YDY';

/// 搜索范围。
enum SearchScope { all, zlib, weread }

class SearchScreen extends StatefulWidget {
  final ReaderController controller;
  final WereadController weread;
  const SearchScreen({
    super.key,
    required this.controller,
    required this.weread,
  });
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin {
  final _scroll = ScrollController();
  final Map<String, ScrollController> _sectionScrolls = {};
  late TabController _tab;
  int _sectionCount = 0;
  bool _showActions = false;
  bool _recommendRefreshing = false;

  List<HomeSection> get _sections => widget.controller.sections;

  @override
  void initState() {
    super.initState();
    _sectionCount = _sections.length;
    _tab = TabController(length: _sectionCount, vsync: this)
      ..addListener(_onTabChanged);
    _scroll.addListener(_onScroll);
    widget.controller.addListener(_onSectionsChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSectionsChanged);
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    for (final controller in _sectionScrolls.values) {
      controller.removeListener(_onScroll);
      controller.dispose();
    }
    super.dispose();
  }

  /// 增删分区后 TabController 的 length 必须重建，否则下标会错位。
  void _onSectionsChanged() {
    final count = _sections.length;
    if (count == _sectionCount || count == 0) return;
    final index = _tab.index.clamp(0, count - 1);
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _sectionCount = count;
    _tab = TabController(length: count, vsync: this, initialIndex: index)
      ..addListener(_onTabChanged);
    if (mounted) setState(() {});
  }

  ScrollController _sectionScroll(String id) =>
      _sectionScrolls.putIfAbsent(id, () {
        return ScrollController()..addListener(_onScroll);
      });

  /// 当前页对应的滚动控制器，悬浮按钮跟着当前页走。
  ScrollController? get _activeScroll {
    final index = _tab.index;
    if (index < 0 || index >= _sections.length) return null;
    final spec = _sections[index];
    if (spec.id == 'popular') return _scroll;
    return _sectionScrolls[spec.id];
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    final controller = _activeScroll;
    final show =
        controller != null && controller.hasClients && controller.offset > 280;
    if (show != _showActions) setState(() => _showActions = show);
  }

  void _onScroll() {
    final controller = _activeScroll;
    if (controller == null || !controller.hasClients) return;
    final show = controller.offset > 280;
    if (show != _showActions) setState(() => _showActions = show);
  }

  void _toTop() {
    final controller = _activeScroll;
    if (controller == null || !controller.hasClients) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// 热门推荐的刷新：短暂停顿显示转圈，然后换成新顺序并回到顶部。
  Future<void> _refreshRecommendations() async {
    if (_recommendRefreshing) return;
    setState(() => _recommendRefreshing = true);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    widget.controller.shuffleRecommendations();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (mounted) setState(() => _recommendRefreshing = false);
  }

  Future<void> _openSearch() async {
    final c = widget.controller;
    c.returnToRecommendations();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SearchPage(controller: c, weread: widget.weread),
      ),
    );
    c.returnToRecommendations();
  }

  Widget recommendationTile(
    BuildContext context,
    ReaderController controller,
    Book book,
    double width,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: () => showBookDetails(context, controller, book),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(book, width: width, height: width * 1.42),
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Stack(
      children: [
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    // TabBar 不支持长按拖动，长按标签栏打开管理面板，
                    // 那里可以拖动排序、删除和新增分区。
                    onLongPress: _openManager,
                    child: TabBar(
                      controller: _tab,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                      tabs: [
                        for (final spec in c.sections)
                          Tab(height: 38, text: spec.title),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '管理分区',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: _openManager,
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  for (final spec in c.sections)
                    spec.id == 'popular'
                        ? _recommendationTab(c)
                        : SectionGridTab(
                            spec: spec,
                            controller: c,
                            scrollController: _sectionScroll(spec.id),
                            onSearch: _openSearch,
                          ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: ScrollQuickActions(
            visible: _showActions,
            tag: 'home',
            onTop: _toTop,
            onSearch: _openSearch,
          ),
        ),
      ],
    );
  }

  Future<void> _openManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // 与列表项同色，拖动让位时不会露出一块灰色空隙。
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => SectionManagerSheet(controller: widget.controller),
    );
    if (mounted) setState(() {});
  }

  /// 热门推荐这一页：搜索框 + 瀑布流。
  Widget _recommendationTab(ReaderController c) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 420 &&
            c.recommendationHasMore &&
            !c.recommendationsLoading) {
          unawaited(c.loadRecommendations());
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async {
          await c.probeRoutes();
          await c.loadRecommendations(refresh: true);
          await c.refreshLoadedSections();
        },
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            // 搜索框放在滚动内容里，往下滑会跟着滚走，和历史页一致。
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
              sliver: SliverToBoxAdapter(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                  ),
                  icon: const Icon(Icons.search),
                  label: const Text('搜书名、作者或关键词'),
                  onPressed: _openSearch,
                ),
              ),
            ),
            ...[
              if (c.recommendationsLoading && c.recommendationBooks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (c.recommendationBooks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.auto_awesome_outlined,
                    title: c.loggedIn ? '暂时没有推荐书籍' : '暂时没有热门书籍',
                    message: c.loggedIn
                        ? '网络恢复后可以重新加载。'
                        : '网络恢复后可以重新加载，也可以直接搜索或浏览分类。',
                    action: '重新加载',
                    onAction: () => c.loadRecommendations(refresh: true),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 8, 2),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bookmark,
                          color: Color(0xffaa4934),
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '热门推荐',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: Divider()),
                        IconButton(
                          tooltip: '刷新',
                          onPressed: _refreshRecommendations,
                          icon: _recommendRefreshing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                  sliver: SliverToBoxAdapter(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 10.0;
                        final columnCount = (constraints.maxWidth / 96)
                            .floor()
                            .clamp(2, 8)
                            .toInt();
                        final coverWidth =
                            (constraints.maxWidth - gap * (columnCount - 1)) /
                            columnCount;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(columnCount, (column) {
                            return Padding(
                              padding: EdgeInsets.only(
                                right: column == columnCount - 1 ? 0 : gap,
                              ),
                              child: SizedBox(
                                width: coverWidth,
                                child: Column(
                                  children: [
                                    for (
                                      var i = column;
                                      i < c.recommendationBooks.length;
                                      i += columnCount
                                    )
                                      recommendationTile(
                                        context,
                                        c,
                                        c.recommendationBooks[i],
                                        coverWidth,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  final ReaderController controller;
  final WereadController weread;
  const SearchPage({super.key, required this.controller, required this.weread});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final input = TextEditingController();
  final focus = FocusNode();
  final _scroll = ScrollController();
  bool _showActions = false;
  SearchScope scope = SearchScope.all;
  WereadController get weread => widget.weread;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 280;
    if (show != _showActions) setState(() => _showActions = show);
  }

  void _toTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// 按选中的来源发起搜索。选「全部」时两个源并行，互不阻塞。
  Future<void> submit() async {
    focus.unfocus();
    final text = input.text.trim();
    if (text.isEmpty) return;
    if (scope == SearchScope.weread && !weread.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('微信读书还没有登录，暂时不可用。请先到「微信读书」页扫码连接。')),
      );
      return;
    }
    final tasks = <Future<void>>[];
    if (scope != SearchScope.weread) tasks.add(widget.controller.search(text));
    // 「全部」但微信读书未连接时静默跳过，顶部已有说明，不再报错。
    if (scope != SearchScope.zlib && weread.connected) {
      tasks.add(weread.search(text));
    }
    await Future.wait(tasks);
  }

  /// 搜索来源选择栏。微信读书未连接时给出明确提示，不让人白点。
  Widget _scopeBar() {
    final connected = weread.connected;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: scope == SearchScope.all,
                onSelected: (_) => setState(() => scope = SearchScope.all),
              ),
              ChoiceChip(
                label: const Text('z-lib'),
                selected: scope == SearchScope.zlib,
                onSelected: (_) => setState(() => scope = SearchScope.zlib),
              ),
              ChoiceChip(
                label: Text(connected ? '微信读书' : '微信读书 · 未登录'),
                selected: scope == SearchScope.weread,
                onSelected: (_) {
                  if (!connected) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('微信读书还没有登录，暂时不可用。请先到「微信读书」页扫码连接。'),
                      ),
                    );
                    return;
                  }
                  setState(() => scope = SearchScope.weread);
                },
              ),
            ],
          ),
        ),
        if (scope != SearchScope.zlib && !connected)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 0),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '微信读书未登录，本次只在 z-lib 中搜索',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(onPressed: _goWeread, child: const Text('去连接')),
              ],
            ),
          ),
      ],
    );
  }

  void _goWeread() {
    Navigator.of(context).pop();
    widget.controller.setTab(2);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AnimatedBuilder(
      animation: Listenable.merge([c, weread]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: TextField(
            controller: input,
            focusNode: focus,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => submit(),
            decoration: const InputDecoration(
              hintText: '搜书名、作者或关键词',
              isDense: true,
            ),
          ),
          actions: [
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: submit,
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(child: _scopeBar()),
                  if (c.recent.isNotEmpty && c.searchPage == null)
                    SliverPadding(
                      padding: const EdgeInsets.all(14),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(child: Text('搜索历史')),
                                TextButton(
                                  onPressed: c.clearRecent,
                                  child: const Text('清空'),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final q in c.recent)
                                  InputChip(
                                    label: Text(q),
                                    deleteButtonTooltipMessage: '删除搜索记录',
                                    onDeleted: () => c.removeRecent(q),
                                    onPressed: () {
                                      input.text = q;
                                      submit();
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (scope != SearchScope.weread && c.searching)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  if (scope != SearchScope.weread && c.searchError.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: ErrorPanel(
                          message: c.searchError,
                          onRetry: () => c.search(input.text),
                        ),
                      ),
                    ),
                  if (scope != SearchScope.weread && c.searchPage != null) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 10, 0),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '搜索结果',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            Text(
                              '${c.searchPage!.books.length} 本',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (c.searchPage!.books.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.search_off_rounded,
                          title: '没有找到相关图书',
                          message: '换个关键词再试试。',
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: c.searchPage!.books.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final book = c.searchPage!.books[index];
                          return BookTile(
                            book,
                            onTap: () => showBookDetails(context, c, book),
                            trailing: BookAction(book: book, controller: c),
                          );
                        },
                      ),
                    ),
                    if (c.searchPage!.totalPages > c.searchPage!.page)
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: 28),
                        sliver: SliverToBoxAdapter(
                          child: Center(
                            child: OutlinedButton.icon(
                              onPressed: c.searching
                                  ? null
                                  : () => c.search(
                                      c.query,
                                      page: c.searchPage!.page + 1,
                                    ),
                              icon: const Icon(Icons.arrow_downward_rounded),
                              label: Text('加载第 ${c.searchPage!.page + 1} 页'),
                            ),
                          ),
                        ),
                      ),
                  ],
                  if (scope != SearchScope.zlib &&
                      (weread.searchBooks.isNotEmpty ||
                          weread.searching ||
                          weread.searchError.isNotEmpty)) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 20, 10, 0),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.auto_stories_outlined,
                              size: 17,
                              color: Color(0xff2f7d4f),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '微信读书',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (weread.searching)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else
                              Text(
                                '${weread.searchBooks.length} 本',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (weread.searchError.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: ErrorPanel(
                            message: weread.searchError,
                            onRetry: () => weread.search(input.text),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        sliver: SliverList.separated(
                          itemCount:
                              weread.searchBooks.length +
                              (weread.searchHasMore ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(height: 2),
                          itemBuilder: (context, index) {
                            if (index >= weread.searchBooks.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Center(
                                  child: OutlinedButton.icon(
                                    onPressed: weread.loadMoreSearch,
                                    icon: const Icon(
                                      Icons.arrow_downward_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('加载更多'),
                                  ),
                                ),
                              );
                            }
                            final book = weread.searchBooks[index];
                            return WereadResultTile(
                              book: book,
                              onTap: () => openWereadBook(
                                context,
                                weread,
                                book.bookInfo.bookId,
                                initial: book.bookInfo,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ],
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: ScrollQuickActions(
                  visible: _showActions,
                  tag: 'search',
                  onTop: _toTop,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> requestBookDownload(
  BuildContext context,
  ReaderController c,
  Book book, {
  bool refreshLink = false,
}) => c.startDownload(
  book,
  refreshLink: refreshLink,
  onExistingFile: (file) async {
    if (!context.mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('这本书已下载'),
        content: Text(file.fileName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, 'open'),
            child: const Text('打开已有文件'),
          ),
        ],
      ),
    );
    if (result == 'open') await c.native.openFile(file);
  },
);

class BookAction extends StatelessWidget {
  final Book book;
  final ReaderController controller;
  const BookAction({super.key, required this.book, required this.controller});
  @override
  Widget build(BuildContext context) {
    final busy =
        controller.resolvingDownloads.contains(book.id) ||
        controller.downloads.any((d) => d.active && d.book.id == book.id);
    return IconButton(
      tooltip: busy ? '下载中' : '下载',
      onPressed: busy
          ? null
          : () => guarded(context, () async {
              await requestBookDownload(context, controller, book);
            }),
      icon: Icon(
        busy ? Icons.downloading_rounded : Icons.download_for_offline_outlined,
      ),
    );
  }
}

class DownloadsScreen extends StatelessWidget {
  final ReaderController controller;
  const DownloadsScreen({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final selecting = controller.selectingDownloads;
      final list = controller.downloads.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.download_outlined,
                  title: '还没有下载',
                  message: '搜索图书后点击下载，文件会保存到你设置的目录。',
                  action: '去找书',
                  onAction: () => controller.setTab(0),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              itemCount: controller.downloads.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = controller.downloads[index];
                return DownloadTile(
                  item: item,
                  controller: controller,
                  selected: controller.selectedDownloadIds.contains(item.id),
                  onTap: controller.selectingDownloads
                      ? () => controller.toggleDownloadSelection(item.id)
                      : null,
                  onLongPress: () =>
                      controller.toggleDownloadSelection(item.id),
                );
              },
            );
      return Column(
        children: [
          if (selecting)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: SizedBox(
                height: 46,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: controller.clearDownloadSelection,
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Text('已选 ${controller.selectedDownloadIds.length} 项'),
                    const Spacer(),
                    TextButton(
                      onPressed: controller.selectAllDownloads,
                      child: const Text('全选'),
                    ),
                    IconButton(
                      tooltip: '删除所选',
                      onPressed: () =>
                          confirmDeleteDownloads(context, controller),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refreshDownloads,
              child: list,
            ),
          ),
        ],
      );
    },
  );
}

Future<void> confirmDeleteDownloads(
  BuildContext context,
  ReaderController c,
) async {
  var deleteFiles = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('删除 ${c.selectedDownloadIds.length} 条记录？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('默认只删除应用中的下载记录。'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: deleteFiles,
              onChanged: (value) =>
                  setState(() => deleteFiles = value ?? false),
              title: const Text('同时删除本地文件'),
              subtitle: const Text('勾选后无法恢复已下载的文件'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ),
  );
  if (confirmed == true && context.mounted) {
    await guarded(
      context,
      () => c.deleteSelectedDownloads(deleteFiles: deleteFiles),
    );
  }
}

/// 云端账户下载记录，作为独立主页面展示。
class HistoryScreen extends StatefulWidget {
  final ReaderController controller;
  const HistoryScreen({super.key, required this.controller});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _scroll = ScrollController();
  final Set<String> _selected = {};
  bool _showActions = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 280;
    if (show != _showActions) setState(() => _showActions = show);
  }

  void _toTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openSearch() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => HistorySearchPage(controller: widget.controller),
    ),
  );

  /// 批量删除选中的历史记录：可选只删本地，或同时删云端。
  Future<void> _deleteSelected(ReaderController c) async {
    final books = (c.visibleHistoryPage?.books ?? const <Book>[])
        .where((b) => _selected.contains(b.ref))
        .toList();
    if (books.isEmpty) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('删除 ${books.length} 条历史记录？'),
        content: const Text(
          '本地删除：只在本机隐藏，账户里的下载历史仍保留。\n'
          '云端删除：同时从账户的下载历史中移除（已下载的文件不受影响）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, 'local'),
            child: const Text('本地删除'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, 'cloud'),
            child: const Text('云端删除'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await guarded(
      context,
      () => c.deleteHistoryBatch(books, cloud: choice == 'cloud'),
    );
    if (mounted) setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!c.loggedIn) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        children: [
          EmptyState(
            icon: Icons.lock_outline_rounded,
            title: '请先登录',
            message: '登录后即可同步并查看历史记录。',
            action: '去登录',
            onAction: () => showLogin(context, c),
          ),
        ],
      );
    }
    final page = c.visibleHistoryPage;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final current = c.historyPage;
            if (notification.metrics.axis == Axis.vertical &&
                notification.metrics.extentAfter < 350 &&
                current != null &&
                current.page < current.totalPages &&
                !c.historyLoading) {
              unawaited(c.loadHistory(page: current.page + 1));
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: () => c.loadHistory(page: 1),
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                if (page != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                    sliver: SliverToBoxAdapter(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                        ),
                        icon: const Icon(Icons.search),
                        label: const Text('在历史记录中搜索'),
                        onPressed: _openSearch,
                      ),
                    ),
                  ),
                if (c.historyError.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: ErrorPanel(
                        message: c.historyError,
                        onRetry: c.loadHistory,
                      ),
                    ),
                  ),
                if (page == null && c.historyLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (page == null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.history_rounded,
                      title: '加载历史记录',
                      message: '从账户中同步已经下载过的图书。',
                      action: '加载',
                      onAction: c.loadHistory,
                    ),
                  )
                else if (page.books.isEmpty && page.page >= page.totalPages)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.history_rounded,
                      title: '暂无下载记录',
                      message: '完成下载后，账户历史会在这里显示。',
                    ),
                  )
                else
                  SliverMainAxisGroup(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        sliver: SliverList.separated(
                          itemCount: page.books.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, i) {
                            final book = page.books[i];
                            final date = book.localDownloadTime;
                            final day = date == null
                                ? null
                                : DateUtils.dateOnly(date);
                            final previous = i == 0
                                ? null
                                : page.books[i - 1].localDownloadTime;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (i == 0 ||
                                    !DateUtils.isSameDay(day, previous))
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 10,
                                      bottom: 4,
                                    ),
                                    child: Text(
                                      day == null
                                          ? '日期未知'
                                          : '${day.year}年${day.month}月${day.day}日',
                                      style: TextStyle(
                                        fontFamily: 'serif',
                                        fontSize: 13,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                  ),
                                InkWell(
                                  onLongPress: () =>
                                      setState(() => _selected.add(book.ref)),
                                  onTap: () {
                                    if (_selected.isNotEmpty) {
                                      setState(() {
                                        if (!_selected.remove(book.ref)) {
                                          _selected.add(book.ref);
                                        }
                                      });
                                      return;
                                    }
                                    showBookDetails(context, c, book);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        if (_selected.contains(book.ref)) ...[
                                          Icon(
                                            Icons.check_circle,
                                            size: 20,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        BookCover(book, width: 40, height: 56),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                book.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                              if (book.author.isNotEmpty)
                                                Text(
                                                  book.author,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              Text(
                                                [
                                                      book.extension,
                                                      book.size,
                                                      if (date != null)
                                                        TimeOfDay.fromDateTime(
                                                          date,
                                                        ).format(context)
                                                      else
                                                        book.downloadedAt,
                                                    ]
                                                    .where((v) => v.isNotEmpty)
                                                    .join(' · '),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        BookAction(book: book, controller: c),
                                        IconButton(
                                          tooltip: '删除历史记录',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 19,
                                          ),
                                          onPressed: () => confirmDeleteHistory(
                                            context,
                                            c,
                                            book,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      if (page.page < page.totalPages)
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: 28),
                          sliver: SliverToBoxAdapter(
                            child: Center(
                              child: OutlinedButton.icon(
                                onPressed: c.historyLoading
                                    ? null
                                    : () => c.loadHistory(page: page.page + 1),
                                icon: const Icon(Icons.expand_more_rounded),
                                label: Text(
                                  c.historyLoading ? '加载中…' : '加载更多历史记录',
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: ScrollQuickActions(
            visible: _showActions,
            tag: 'history',
            onTop: _toTop,
            onSearch: _openSearch,
          ),
        ),
        if (_selected.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              elevation: 4,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Text('已选 ${_selected.length} 条'),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _selected.clear()),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => _deleteSelected(c),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class DownloadTile extends StatelessWidget {
  final DownloadRecord item;
  final ReaderController controller;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const DownloadTile({
    super.key,
    required this.item,
    required this.controller,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });
  @override
  Widget build(BuildContext context) {
    final progress = item.progress;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (selected) const Icon(Icons.check_circle_rounded, size: 22),
              if (selected) const SizedBox(width: 8),
              InkWell(
                onTap: controller.selectingDownloads
                    ? onTap
                    : () => showBookDetails(context, controller, item.book),
                child: BookCover(item.book, width: 48, height: 70),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.status == 'complete'
                          ? item.fileName
                          : item.error.isNotEmpty
                          ? item.error
                          : progress == null
                          ? '正在准备下载…'
                          : '正在下载 ${(progress * 100).round()}%',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (progress != null && !item.complete)
                      Padding(
                        padding: const EdgeInsets.only(top: 9),
                        child: LinearProgressIndicator(value: progress),
                      ),
                    if (item.complete)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => guarded(
                                context,
                                () => NativeBridge().openFile(item),
                              ),
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                              ),
                              label: const Text('打开'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => guarded(
                                context,
                                () => NativeBridge().shareFile(item),
                              ),
                              icon: const Icon(Icons.share_outlined, size: 16),
                              label: const Text('分享'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (item.status == 'failed' && !controller.selectingDownloads)
                IconButton(
                  tooltip: '重新获取链接并下载',
                  onPressed: () => guarded(context, () async {
                    await requestBookDownload(
                      context,
                      controller,
                      item.book,
                      refreshLink: true,
                    );
                  }),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              if ((item.active || item.status == 'paused') && !selected)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: item.status == 'paused' ? '继续下载' : '暂停下载',
                      onPressed: () => guarded(
                        context,
                        () => item.status == 'paused'
                            ? controller.resumeDownload(item.id)
                            : controller.pauseDownload(item.id),
                      ),
                      icon: Icon(
                        item.status == 'paused'
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: '取消下载',
                      onPressed: () => guarded(
                        context,
                        () => controller.cancelDownload(item.id),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  final ReaderController controller;
  const ProfileScreen({super.key, required this.controller});
  String quota(Map<String, dynamic> p) {
    final used = intValue(p['downloads_today'] ?? p['dailyDownloadsCount']);
    final limit = intValue(p['downloads_limit'] ?? p['dailyDownloadLimit']);
    return limit > 0 ? '今日已用 $used / $limit 次下载' : '账户信息已同步';
  }

  String themeLabel(ThemeMode mode) => mode == ThemeMode.dark
      ? '深色模式'
      : mode == ThemeMode.light
      ? '浅色模式'
      : '跟随系统';

  String avatarUrl(ReaderController c) {
    final p = c.profileData ?? const <String, dynamic>{};
    final nested = p['avatar'] is Map ? p['avatar'] as Map : const {};
    final raw = textValue(
      p['avatar_url'] ??
          p['avatarUrl'] ??
          (p['avatar'] is String ? p['avatar'] : null) ??
          p['photo'] ??
          p['image'] ??
          nested['url'] ??
          nested['src'],
    );
    if (raw.isEmpty) return '';
    try {
      var uri = Uri.parse(c.activeOrigin).resolve(raw);
      if (uri.scheme == 'http') uri = uri.replace(scheme: 'https');
      return uri.toString();
    } catch (_) {
      return '';
    }
  }

  Map<String, String> _avatarHeaders(ReaderController c, String url) {
    final headers = <String, String>{'User-Agent': 'Mozilla/5.0 z-lib-android'};
    final session = c.session;
    if (session == null) return headers;
    try {
      final image = Uri.parse(url);
      if (image.host == Uri.parse(c.activeOrigin).host) {
        headers['remix-userid'] = session.userId;
        headers['remix-userkey'] = session.userKey;
      }
    } catch (_) {}
    return headers;
  }

  Widget _avatarFallback(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Icon(
      Icons.person_rounded,
      color: Theme.of(context).colorScheme.primary,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      children: [
        Text(
          '我的账户',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontSize: 22),
        ),
        const Divider(),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.all(12),
          child: c.loggedIn
              ? Row(
                  children: [
                    Builder(
                      builder: (_) {
                        final avatar = avatarUrl(c);
                        return ClipOval(
                          child: SizedBox.square(
                            dimension: 50,
                            child: avatar.isEmpty
                                ? _avatarFallback(context)
                                : Image.network(
                                    avatar,
                                    fit: BoxFit.cover,
                                    headers: _avatarHeaders(c, avatar),
                                    errorBuilder: (_, __, ___) =>
                                        _avatarFallback(context),
                                  ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.session!.email.isEmpty
                                ? '已登录账户'
                                : c.session!.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.profileData == null
                                ? '正在获取账户信息…'
                                : quota(c.profileData!),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '退出登录',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('退出登录？'),
                            content: const Text('退出后仍可保留本地下载文件。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  c.logout();
                                },
                                child: const Text('退出'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.logout_rounded),
                    ),
                  ],
                )
              : Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      child: Icon(
                        Icons.person_outline_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(child: Text('登录后搜索、下载并同步账户历史记录')),
                    FilledButton(
                      onPressed: () => showLogin(context, c),
                      child: const Text('登录'),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        ListTileTheme(
          data: ListTileThemeData(
            titleTextStyle: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontSize: 17),
            subtitleTextStyle: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 13),
          ),
          child: Column(
            children: [
              ListTile(
                minTileHeight: 56,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.bookmarks_outlined),
                title: const Text('我的收藏'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => BookmarksPage(controller: c),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                dense: false,
                minTileHeight: 56,
                minVerticalPadding: 2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Badge(
                  isLabelVisible: c.activeDownloads > 0,
                  label: Text('${c.activeDownloads}'),
                  child: const Icon(Icons.download_rounded),
                ),
                title: const Text('下载任务'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => FractionallySizedBox(
                      heightFactor: .92,
                      child: DownloadsScreen(controller: c),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                dense: false,
                minTileHeight: 56,
                minVerticalPadding: 2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.folder_open_rounded),
                title: const Text('下载目录'),
                subtitle: Text(
                  c.directory,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showDirectory(context, c),
              ),
              const Divider(),
              ListTile(
                dense: false,
                minTileHeight: 56,
                minVerticalPadding: 2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.palette_outlined),
                title: const Text('外观'),
                subtitle: Text(themeLabel(c.theme)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showTheme(context, c),
              ),
              const Divider(),
              ListTile(
                dense: false,
                minTileHeight: 56,
                minVerticalPadding: 2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.lan_outlined),
                title: const Text('连接线路'),
                subtitle: Text(c.host),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showRoutes(context, c),
              ),
              const Divider(),
              ListTile(
                minTileHeight: 56,
                dense: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.history_rounded),
                title: const Text('历史版本'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReleasesPage(controller: c),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                minTileHeight: 56,
                dense: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('一起读书'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    guarded(context, () => c.native.openUrl(kReadingClubUrl)),
              ),
            ],
          ),
        ),
        Center(
          child: Text(
            'z-lib ${c.version}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorPanel({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    ),
  );
}

class BookmarksPage extends StatelessWidget {
  final ReaderController controller;
  const BookmarksPage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的收藏')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final books = controller.bookmarks;
          if (controller.bookmarksLoading && books.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: controller.loadBookmarks,
            child: books.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 140),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            controller.loggedIn
                                ? (controller.bookmarksError.isNotEmpty
                                      ? '收藏同步失败：${controller.bookmarksError}\n下拉可重试'
                                      : '还没有收藏，可在书籍详情页点「收藏」添加')
                                : '还没有收藏。登录后收藏会同步到你的 zlib 账号，换设备登录也能看到。',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return BookTile(
                        book,
                        key: ValueKey(book.ref),
                        onTap: () => showBookDetails(context, controller, book),
                        trailing: IconButton(
                          tooltip: '取消收藏',
                          icon: const Icon(Icons.bookmark_rounded),
                          onPressed: () => guarded(context, () async {
                            await controller.toggleBookmark(book);
                          }),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    ),
  );
}

Future<void> showBookDetails(
  BuildContext context,
  ReaderController c,
  Book initial,
) async {
  // 未登录时看不了详情（服务端要求登录），先引导登录。
  if (!c.loggedIn) {
    await showLogin(context, c);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BookDetailsSheet(controller: c, initial: initial),
  );
}

class BookDetailsSheet extends StatefulWidget {
  final ReaderController controller;
  final Book initial;
  const BookDetailsSheet({
    super.key,
    required this.controller,
    required this.initial,
  });
  @override
  State<BookDetailsSheet> createState() => _BookDetailsSheetState();
}

class _BookDetailsSheetState extends State<BookDetailsSheet> {
  late Book book;
  bool titleExpanded = false;
  bool loading = true;
  String error = '';
  @override
  void initState() {
    super.initState();
    book = widget.initial;
    unawaited(load());
  }

  Future<void> load() async {
    try {
      book = await widget.controller.details(widget.initial);
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .92,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, _) {
                    final width = MediaQuery.sizeOf(context).width < 500
                        ? 78.0
                        : 100.0;
                    return BookCover(book, width: width, height: width * 1.45);
                  },
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final style = DefaultTextStyle.of(context).style
                              .merge(
                                Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontSize: 20, height: 1.25),
                              );
                          final measure = TextPainter(
                            text: TextSpan(text: book.title, style: style),
                            maxLines: 2,
                            ellipsis: '…',
                            textDirection: Directionality.of(context),
                            textScaler: MediaQuery.textScalerOf(context),
                            locale: Localizations.maybeLocaleOf(context),
                          )..layout(maxWidth: constraints.maxWidth);
                          final overflows = measure.didExceedMaxLines;
                          measure.dispose();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.title,
                                style: style,
                                maxLines: titleExpanded ? null : 2,
                                overflow: titleExpanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                              ),
                              if (overflows)
                                TextButton(
                                  onPressed: () => setState(
                                    () => titleExpanded = !titleExpanded,
                                  ),
                                  child: Text(
                                    titleExpanded ? '收起书名' : '展开完整书名',
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        book.author.isEmpty ? '作者信息暂缺' : book.author,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (book.extension.isNotEmpty) Pill(book.extension),
                          if (book.size.isNotEmpty) Pill(book.size),
                          if (book.year.isNotEmpty) Pill(book.year),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final saved = widget.controller.bookmarked(book);
                final actions = <Widget>[
                  IconButton.outlined(
                    tooltip: saved ? '取消收藏' : '收藏',
                    onPressed: () => guarded(context, () async {
                      await widget.controller.toggleBookmark(book);
                      if (mounted) setState(() {});
                    }),
                    icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                  ),
                  if (book.downloadable &&
                      {'EPUB', 'PDF'}.contains(book.extension))
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PreviewLoader(
                            controller: widget.controller,
                            book: book,
                          ),
                        ),
                      ),
                      icon: const Icon(
                        Icons.chrome_reader_mode_outlined,
                        size: 18,
                      ),
                      label: const Text('在线预览'),
                    ),
                  FilledButton.icon(
                    onPressed: () => guarded(context, () async {
                      final queued = await requestBookDownload(
                        context,
                        widget.controller,
                        book,
                      );
                      if (queued && context.mounted) Navigator.pop(context);
                    }),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('下载'),
                  ),
                ];
                if (constraints.maxWidth <
                    300 * MediaQuery.textScalerOf(context).scale(1)) {
                  return Wrap(spacing: 8, runSpacing: 8, children: actions);
                }
                return Row(
                  children: [
                    actions.first,
                    for (final action in actions.skip(1)) ...[
                      const SizedBox(width: 8),
                      Expanded(child: SizedBox(height: 46, child: action)),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (loading) const LinearProgressIndicator(),
            if (error.isNotEmpty) ErrorPanel(message: error, onRetry: load),
            if (book.description.isNotEmpty) ...[
              Text('内容简介', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(book.description),
            ],
            if (book.publisher.isNotEmpty ||
                book.isbn.isNotEmpty ||
                book.language.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('图书信息', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (book.publisher.isNotEmpty) InfoRow('出版社', book.publisher),
              if (book.isbn.isNotEmpty) InfoRow('ISBN', book.isbn),
              if (book.language.isNotEmpty) InfoRow('语言', book.language),
            ],
          ],
        ),
      ),
    ),
  );
}

class InfoRow extends StatelessWidget {
  final String label, value;
  const InfoRow(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        SizedBox(width: 70, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

/// 删除历史记录：让用户选择只删本地，还是同时删云端。
Future<void> confirmDeleteHistory(
  BuildContext context,
  ReaderController c,
  Book book,
) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('删除这条历史记录？'),
      content: Text(
        '《${book.title}》\n\n'
        '本地删除：只在本机隐藏，账户里的下载历史仍保留。\n'
        '云端删除：同时从账户的下载历史中移除（已下载的文件不受影响）。',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.pop(d, 'local'),
          child: const Text('本地删除'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(d, 'cloud'),
          child: const Text('云端删除'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'local') {
    await guarded(context, () => c.hideHistory(book));
  } else {
    await guarded(context, () => c.deleteHistoryRemote(book));
  }
}

Future<void> showHistory(BuildContext context, ReaderController c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .92,
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final page = c.visibleHistoryPage;
          late final Widget content;
          if (c.historyLoading && page == null) {
            content = const Center(child: CircularProgressIndicator());
          } else if (page == null) {
            content = Center(
              child: FilledButton(
                onPressed: c.loadHistory,
                child: const Text('加载历史记录'),
              ),
            );
          } else if (page.books.isEmpty) {
            content = const EmptyState(
              icon: Icons.history_rounded,
              title: '暂无云端历史',
              message: '完成下载后，账户历史会在这里显示。',
            );
          } else {
            content = ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
              itemCount: page.books.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => BookTile(
                page.books[i],
                onTap: () => showBookDetails(context, c, page.books[i]),
                showDownloadDate: true,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  '账户下载历史',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (c.historyError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorPanel(
                    message: c.historyError,
                    onRetry: c.loadHistory,
                  ),
                ),
              Expanded(child: content),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> showDirectory(BuildContext context, ReaderController c) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('下载目录', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('下载完成后，文件会出现在这个目录中。Android 会记住你授予的目录权限。'),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(c.directory),
              subtitle: const Text('当前目录'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(context);
                guarded(context, c.chooseDirectory);
              },
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              guarded(context, c.resetDirectory);
            },
            icon: const Icon(Icons.restore_rounded),
            label: const Text('恢复应用默认目录'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showTheme(BuildContext context, ReaderController c) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => AnimatedBuilder(
      animation: c,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('外观', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            RadioListTile<ThemeMode>(
              value: ThemeMode.system,
              groupValue: c.theme,
              onChanged: (v) {
                if (v != null) c.setTheme(v);
                Navigator.pop(context);
              },
              title: const Text('跟随系统'),
              secondary: const Icon(Icons.brightness_auto_rounded),
            ),
            RadioListTile<ThemeMode>(
              value: ThemeMode.light,
              groupValue: c.theme,
              onChanged: (v) {
                if (v != null) c.setTheme(v);
                Navigator.pop(context);
              },
              title: const Text('浅色模式'),
              secondary: const Icon(Icons.light_mode_rounded),
            ),
            RadioListTile<ThemeMode>(
              value: ThemeMode.dark,
              groupValue: c.theme,
              onChanged: (v) {
                if (v != null) c.setTheme(v);
                Navigator.pop(context);
              },
              title: const Text('深色模式'),
              secondary: const Icon(Icons.dark_mode_rounded),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 历史记录条目：可选的日期头 + 封面 + 书名作者 + 格式/大小/时间 + 下载与删除操作。
///
/// 历史列表和「历史搜索」页共用，保证两边展示的字段完全一致。
/// [dateHeader] 为空时不显示日期头，此时时间会显示成完整的年月日时分。
class HistoryTile extends StatelessWidget {
  final Book book;
  final ReaderController controller;
  final String? dateHeader;
  const HistoryTile({
    super.key,
    required this.book,
    required this.controller,
    this.dateHeader,
  });

  static String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final date = book.localDownloadTime;
    final time = date == null
        ? book.downloadedAt
        : dateHeader == null
        ? '${date.year}-${_two(date.month)}-${_two(date.day)} '
              '${_two(date.hour)}:${_two(date.minute)}'
        : TimeOfDay.fromDateTime(date).format(context);
    final meta = [
      book.extension,
      book.size,
      time,
    ].where((v) => v.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dateHeader != null)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              dateHeader!,
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        InkWell(
          onTap: () => showBookDetails(context, c, book),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                BookCover(book, width: 40, height: 56),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (book.author.isNotEmpty)
                        Text(
                          book.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      Text(meta, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                BookAction(book: book, controller: c),
                IconButton(
                  tooltip: '删除历史记录',
                  icon: const Icon(Icons.delete_outline, size: 19),
                  onPressed: () => confirmDeleteHistory(context, c, book),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 下载历史的独立搜索页：按书名、作者、格式过滤已加载的历史记录。
class HistorySearchPage extends StatefulWidget {
  final ReaderController controller;
  const HistorySearchPage({super.key, required this.controller});

  @override
  State<HistorySearchPage> createState() => _HistorySearchPageState();
}

class _HistorySearchPageState extends State<HistorySearchPage> {
  final input = TextEditingController();
  final _scroll = ScrollController();
  bool _showActions = false;
  String query = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    input.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 280;
    if (show != _showActions) setState(() => _showActions = show);
  }

  void _toTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  List<Book> _results(ReaderController c) {
    final all = c.visibleHistoryPage?.books ?? const <Book>[];
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return all;
    return all.where((book) {
      return book.title.toLowerCase().contains(text) ||
          book.author.toLowerCase().contains(text) ||
          book.extension.toLowerCase().contains(text);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final all = c.visibleHistoryPage?.books ?? const <Book>[];
        final results = _results(c);
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: TextField(
              controller: input,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                hintText: '搜书名、作者或格式',
                isDense: true,
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          input.clear();
                          setState(() => query = '');
                        },
                      ),
              ),
            ),
          ),
          body: SafeArea(
            child: Stack(
              children: [
                results.isEmpty
                    ? ListView(
                        children: [
                          EmptyState(
                            icon: Icons.search_off_rounded,
                            title: query.isEmpty ? '还没有历史记录' : '没有匹配的记录',
                            message: query.isEmpty
                                ? '先到首页下载几本书，这里就会出现下载历史。'
                                : '「$query」在已加载的 ${all.length} 条记录里没有找到。'
                                      '可以回到列表，待加载更多后再搜。',
                          ),
                        ],
                      )
                    : ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            HistoryTile(book: results[index], controller: c),
                      ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: ScrollQuickActions(
                    visible: _showActions,
                    tag: 'history-search',
                    onTop: _toTop,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 首页的一个分类页：标题 + 纵向瀑布流 + 换一批。
///
/// 和「热门推荐」平级，用 TabBarView 左右滑动切换，内部照常上下滚动。
class SectionGridTab extends StatefulWidget {
  final HomeSection spec;
  final ReaderController controller;
  final ScrollController scrollController;
  final VoidCallback onSearch;
  const SectionGridTab({
    super.key,
    required this.spec,
    required this.controller,
    required this.scrollController,
    required this.onSearch,
  });

  @override
  State<SectionGridTab> createState() => _SectionGridTabState();
}

class _SectionGridTabState extends State<SectionGridTab> {
  bool _refreshing = false;

  /// 刷新：短暂停顿显示转圈，然后换成新顺序并回到顶部。
  /// 纯本地操作，不受正在进行的分页加载影响。
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    widget.controller.shuffleSection(widget.spec);
    if (widget.scrollController.hasClients) {
      widget.scrollController.jumpTo(0);
    }
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  void initState() {
    super.initState();
    // TabBarView 是懒构建的，第一次切到这个分类时才发请求，
    // 避免启动瞬间连打五个检索把线路打到限流。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = widget.controller;
      if (!c.sectionBooks.containsKey(widget.spec.id) &&
          !c.sectionLoading.contains(widget.spec.id)) {
        unawaited(c.loadSection(widget.spec));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final spec = widget.spec;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final books = c.sectionBooks[spec.id] ?? const <Book>[];
    final loading = c.sectionLoading.contains(spec.id);
    final error = c.sectionErrors[spec.id] ?? '';
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 滑到接近底部就追加下一页，书单可以一直往下延伸。
        if (notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 500 &&
            c.sectionHasMore[spec.id] == true &&
            !c.sectionLoading.contains(spec.id)) {
          unawaited(c.loadMoreSection(spec));
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => c.loadSection(spec),
        child: CustomScrollView(
          controller: widget.scrollController,
          slivers: [
            // 每个分区顶部都有搜索框，且会随内容一起滚走。
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
              sliver: SliverToBoxAdapter(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                  ),
                  icon: const Icon(Icons.search),
                  label: const Text('搜书名、作者或关键词'),
                  onPressed: widget.onSearch,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    // 分类名可能很长，用 Expanded 收紧并省略，
                    // 否则会把右边的刷新按钮挤出屏幕。
                    Expanded(
                      child: Text(
                        spec.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    if (books.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '已加载 ${books.length} 本',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: _refresh,
                      icon: _refreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            ),
            if (error.isNotEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.cloud_off,
                  title: '这个分类没加载出来',
                  message: error,
                  action: '重试',
                  onAction: () => c.loadSection(spec),
                ),
              )
            else if (books.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: loading
                      ? const CircularProgressIndicator()
                      : EmptyState(
                          icon: Icons.search_off_rounded,
                          title: '暂无内容',
                          message: '换个分类看看，或者下拉重新加载。',
                        ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 14,
                    childAspectRatio: .56,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final book = books[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => showBookDetails(context, c, book),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) => BookCover(
                                book,
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'serif',
                              fontSize: 12,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }, childCount: books.length),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                  child: Center(
                    child: loading
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(),
                          )
                        : c.sectionHasMore[spec.id] == true
                        ? OutlinedButton.icon(
                            onPressed: () => c.loadMoreSection(spec),
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('加载更多'),
                          )
                        : Text(
                            '已经到底了 · 共 ${books.length} 本',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分区管理：拖动排序、删除、从线路官方分类里添加。
///
/// 整个面板是一个 CustomScrollView：分区用 SliverReorderableList（能跟着滚），
/// 802 个官方分类用 SliverList 懒构建，不会一次全渲染。
class SectionManagerSheet extends StatefulWidget {
  final ReaderController controller;
  const SectionManagerSheet({super.key, required this.controller});

  @override
  State<SectionManagerSheet> createState() => _SectionManagerSheetState();
}

class _SectionManagerSheetState extends State<SectionManagerSheet> {
  final _search = TextEditingController();
  String _filter = '';

  /// 官方分类的中文名，只覆盖常用的那批，其余直接显示原名。
  static const _zhNames = <int, String>{
    40: '建筑',
    42: '音乐',
    43: '摄影',
    44: '电影',
    45: '雕塑',
    55: '素描',
    56: '绘画',
    70: '商业金融',
    84: '参考工具',
    91: '真实犯罪',
    92: '战争与间谍',
    94: '生物学',
    95: '人类学',
    101: '遗传学',
    107: '动物学',
    111: '会计',
    113: '管理与领导力',
    114: '销售与营销',
    118: '个人理财',
    122: '投资',
    126: '分析化学',
    133: '生物化学',
    140: '漫画',
    141: '计算机与技术',
    144: '童话神话',
    149: '幽默',
    150: '文学与小说',
    151: '悬疑推理',
    153: '科幻奇幻',
    157: '动漫',
    159: '儿童读物',
    163: 'DC 漫画',
    164: '漫威',
    168: '算法与数据结构',
    169: '人工智能',
    172: '计算机图形',
    173: '计算机科学',
    175: '密码学',
    177: '数据库',
    186: 'Web 开发',
    187: '互联网',
    190: '媒体',
    192: '网络',
    194: '操作系统',
    198: '编程',
    199: '网络安全',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadCategories();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _titleOf(ZlibCategory cat) => _zhNames[cat.id] ?? cat.name;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FractionallySizedBox(
      heightFactor: .92,
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final existing = c.sections.map((s) => s.categoryId).toSet();
          final filter = _filter.toLowerCase();
          final categories = c.zlibCategories.where((cat) {
            if (filter.isEmpty) return true;
            return _titleOf(cat).toLowerCase().contains(filter) ||
                cat.name.toLowerCase().contains(filter);
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('管理分区', style: theme.textTheme.titleLarge),
                    ),
                    TextButton(
                      onPressed: c.resetSections,
                      child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                    ),
                    IconButton(
                      tooltip: '完成',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          '全部拖左侧手柄排序，垃圾桶删除；下面的官方分类点一下就能加进来。'
                          '「恢复默认」可一键回到首次安装时的顺序。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    SliverReorderableList(
                      itemCount: c.sections.length,
                      onReorder: c.reorderSections,
                      // 默认拖动代理会带一层 elevation 阴影，看起来像一整块
                      // 灰色遮挡从下方浮起。这里改成不透明、无阴影的卡片。
                      proxyDecorator: (child, index, animation) => Material(
                        color: colors.surface,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: child,
                      ),
                      itemBuilder: (context, index) {
                        final spec = c.sections[index];
                        // 不透明底色，避免拖动代理和下面的内容叠出灰影。
                        return Material(
                          key: ValueKey(spec.id),
                          color: colors.surface,
                          child: ListTile(
                            dense: true,
                            leading: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle, size: 20),
                            ),
                            title: Text(
                              spec.title,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              spec.builtin
                                  ? '内置分区'
                                  : spec.isCategory
                                  ? '官方分类 #${spec.categoryId}'
                                  : '关键词：${spec.query}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            trailing: spec.builtin
                                ? null
                                : IconButton(
                                    tooltip: '删除',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 19,
                                    ),
                                    onPressed: () => c.removeSection(spec.id),
                                  ),
                          ),
                        );
                      },
                    ),
                    const SliverToBoxAdapter(child: Divider(height: 20)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Text('添加官方分类', style: theme.textTheme.titleMedium),
                            const SizedBox(width: 8),
                            if (c.categoriesLoading)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            const Spacer(),
                            Text(
                              '${c.zlibCategories.length} 个',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      sliver: SliverToBoxAdapter(
                        child: TextField(
                          controller: _search,
                          onChanged: (value) =>
                              setState(() => _filter = value.trim()),
                          decoration: const InputDecoration(
                            hintText: '搜分类，例如 小说 / 计算机 / Computer',
                            isDense: true,
                            prefixIcon: Icon(Icons.search, size: 18),
                          ),
                        ),
                      ),
                    ),
                    if (c.categoriesError.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.all(20),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            c.categoriesError,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.error, fontSize: 12),
                          ),
                        ),
                      )
                    else if (categories.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: c.categoriesLoading
                              ? const CircularProgressIndicator()
                              : Text(
                                  '没有匹配的分类',
                                  style: theme.textTheme.bodySmall,
                                ),
                        ),
                      )
                    else
                      SliverList.builder(
                        itemCount: categories.length,
                        itemBuilder: (context, index) {
                          final cat = categories[index];
                          final added = existing.contains(cat.id);
                          return ListTile(
                            dense: true,
                            title: Text(
                              _titleOf(cat),
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              cat.name,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            trailing: added
                                ? Text(
                                    '已添加',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  )
                                : IconButton(
                                    tooltip: '添加',
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      size: 20,
                                    ),
                                    onPressed: () => c.addSection(
                                      HomeSection(
                                        'cat-${cat.id}',
                                        _titleOf(cat),
                                        '',
                                        categoryId: cat.id,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 版本历史页：列出 Gitee 上的发行版，含版本号、时间、更新说明、下载入口。
class ReleasesPage extends StatefulWidget {
  final ReaderController controller;
  const ReleasesPage({super.key, required this.controller});

  @override
  State<ReleasesPage> createState() => _ReleasesPageState();
}

class _ReleasesPageState extends State<ReleasesPage> {
  final ScrollController _scroll = ScrollController();
  bool _showActions = false;
  String _query = '';
  int _matchIndex = 0;
  final Map<String, GlobalKey> _cardKeys = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (widget.controller.releases.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.loadReleases();
      });
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 80;
    if (show != _showActions) setState(() => _showActions = show);
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openSearch() async {
    final input = TextEditingController(text: _query);
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('搜索版本'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: '版本号或更新内容关键词'),
          onSubmitted: (value) => Navigator.pop(d, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, ''),
            child: const Text('清除'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, input.text),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _query = result.trim();
      _matchIndex = 0;
    });
  }

  List<AppRelease> _filtered() {
    if (_query.isEmpty) return widget.controller.releases;
    final q = _query.toLowerCase();
    return widget.controller.releases
        .where(
          (r) =>
              r.version.toLowerCase().contains(q) ||
              r.name.toLowerCase().contains(q) ||
              r.body.toLowerCase().contains(q),
        )
        .toList();
  }

  void _jumpTo(int index, List<AppRelease> releases) {
    if (index < 0 || index >= releases.length) return;
    setState(() => _matchIndex = index);
    final target = _cardKeys[releases[index].tag]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: .08,
    );
  }

  /// 把搜索词命中的片段高亮显示。
  Widget _highlighted(String text, TextStyle? style) {
    if (_query.isEmpty) return Text(text, style: style);
    final lower = text.toLowerCase();
    final q = _query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lower.indexOf(q, start);
      if (index < 0) break;
      if (index > start)
        spans.add(TextSpan(text: text.substring(start, index)));
      spans.add(
        TextSpan(
          text: text.substring(index, index + q.length),
          style: TextStyle(
            backgroundColor: const Color(0xffffd54f).withValues(alpha: .75),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = index + q.length;
    }
    if (spans.isEmpty) return Text(text, style: style);
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return Text.rich(TextSpan(style: style, children: spans));
  }

  String _date(String iso) {
    if (iso.isEmpty) return '';
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
    return match == null ? iso : '${match[1]}-${match[2]}-${match[3]}';
  }

  /// 固定在顶部的下载入口：所有版本共用这一组按钮。
  Widget _downloadCard(ThemeData theme, ReaderController c) => Card(
    color: theme.colorScheme.primaryContainer.withValues(alpha: .35),
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '下载全部版本',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      guarded(context, () => c.native.openUrl(netdiskUrl)),
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('网盘下载'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => guarded(
                    context,
                    () => c.native.openUrl(giteeReleasesPage),
                  ),
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('Gitee 下载'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '网盘密码：$netdiskPassword',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _releaseCard(
    ThemeData theme,
    ReaderController c,
    AppRelease release, {
    bool current = false,
  }) {
    final isCurrent = release.version == c.version;
    final text = markdownToPlain(release.body);
    final date = _date(release.publishedAt);
    return Card(
      key: _cardKeys.putIfAbsent(release.tag, () => GlobalKey()),
      shape: current
          ? RoundedRectangleBorder(
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _highlighted(
                    release.name.isNotEmpty
                        ? release.name
                        : 'v${release.version}',
                    theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '当前版本',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            if (date.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '发布于 $date',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (text.isNotEmpty) ...[
              const SizedBox(height: 10),
              _highlighted(
                text,
                theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('历史版本')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            if (c.releasesLoading && c.releases.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final releases = _filtered();
            return Stack(
              children: [
                RefreshIndicator(
                  onRefresh: c.loadReleases,
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    children: [
                      _downloadCard(theme, c),
                      if (_query.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '搜索：$_query',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _query = '';
                                  _matchIndex = 0;
                                }),
                                child: const Text('清除'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      if (releases.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Center(
                            child: Text(
                              _query.isEmpty
                                  ? '还没有版本记录，或暂时连不上更新源'
                                  : '没有匹配「$_query」的版本',
                            ),
                          ),
                        )
                      else
                        for (var i = 0; i < releases.length; i++)
                          _releaseCard(
                            theme,
                            c,
                            releases[i],
                            current:
                                _query.isNotEmpty &&
                                i == _matchIndex.clamp(0, releases.length - 1),
                          ),
                    ],
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: AnimatedSlide(
                    offset: _showActions ? Offset.zero : const Offset(0, .35),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: AnimatedOpacity(
                      opacity: _showActions ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: IgnorePointer(
                        ignoring: !_showActions,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_query.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${releases.isEmpty ? 0 : _matchIndex.clamp(0, releases.length - 1) + 1}/${releases.length}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              FloatingActionButton.small(
                                heroTag: 'releases-prev',
                                tooltip: '上一个匹配',
                                onPressed: _matchIndex > 0
                                    ? () => _jumpTo(_matchIndex - 1, releases)
                                    : null,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                                foregroundColor:
                                    theme.colorScheme.onSurfaceVariant,
                                child: const Icon(
                                  Icons.keyboard_arrow_up,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 8),
                              FloatingActionButton.small(
                                heroTag: 'releases-next',
                                tooltip: '下一个匹配',
                                onPressed: _matchIndex < releases.length - 1
                                    ? () => _jumpTo(_matchIndex + 1, releases)
                                    : null,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                                foregroundColor:
                                    theme.colorScheme.onSurfaceVariant,
                                child: const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            FloatingActionButton.small(
                              heroTag: 'releases-search',
                              tooltip: '搜索',
                              onPressed: _openSearch,
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              child: const Icon(Icons.search, size: 20),
                            ),
                            const SizedBox(height: 10),
                            FloatingActionButton.small(
                              heroTag: 'releases-top',
                              tooltip: '回到顶部',
                              onPressed: _scrollToTop,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              foregroundColor:
                                  theme.colorScheme.onSurfaceVariant,
                              child: const Icon(Icons.arrow_upward, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 新版本更新弹窗，带两个下载入口和「以后不再弹出」勾选。
class UpdatePrompt extends StatefulWidget {
  final AppRelease release;
  const UpdatePrompt({super.key, required this.release});

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  bool hide = false;

  void _open(String url) {
    final shouldHide = hide;
    Navigator.pop(context, shouldHide);
    unawaited(NativeBridge().openUrl(url));
  }

  @override
  Widget build(BuildContext context) {
    final text = markdownToPlain(widget.release.body);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('发现新版本 ${widget.release.version}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (text.isNotEmpty) Text(text),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _open(netdiskUrl),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('网盘下载'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _open(widget.release.giteeUrl),
                    icon: const Icon(Icons.code, size: 18),
                    label: const Text('Gitee 下载'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '网盘密码：$netdiskPassword',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: hide,
              title: const Text('以后不再弹出更新提醒'),
              onChanged: (value) => setState(() => hide = value ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, hide),
          child: const Text('以后再说'),
        ),
      ],
    );
  }
}
