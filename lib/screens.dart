import 'dart:async';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'domain.dart';
import 'native.dart';
import 'widgets.dart';

class SearchScreen extends StatefulWidget {
  final ReaderController controller;
  const SearchScreen({super.key, required this.controller});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final input = TextEditingController();
  final focus = FocusNode();
  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    focus.unfocus();
    await widget.controller.search(input.text);
  }

  Widget recommendationTile(
    BuildContext context,
    ReaderController controller,
    Book book,
    double width,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: InkWell(
      onTap: () => showBookDetails(context, controller, book),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(book, width: width, height: width * 1.42),
          const SizedBox(height: 7),
          Text(
            book.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 420 &&
            c.searchPage == null &&
            c.recommendationHasMore &&
            !c.recommendationsLoading) {
          unawaited(c.loadRecommendations());
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: c.probeRoutes,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今天读什么？',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 6),
                    const Text('从书海里找到下一本想读的书。'),
                    const SizedBox(height: 18),
                    TextField(
                      controller: input,
                      focusNode: focus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        hintText: '输入书名、作者或关键词',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: c.searching
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                onPressed: submit,
                                icon: const Icon(Icons.arrow_forward_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (c.recent.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          const Icon(Icons.history_rounded, size: 18),
                          ...c.recent
                              .take(5)
                              .map(
                                (q) => ActionChip(
                                  label: Text(q),
                                  onPressed: () {
                                    input.text = q;
                                    submit();
                                  },
                                ),
                              ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (c.searchError.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: ErrorPanel(
                    message: c.searchError,
                    onRetry: () => c.search(input.text),
                  ),
                ),
              ),
            if (c.searchPage == null && c.searchError.isEmpty) ...[
              if (!c.loggedIn)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: '登录后查看热门推荐',
                    message: '登录账户后可浏览推荐书籍、搜索并下载。',
                    action: '登录',
                    onAction: () => showLogin(context, c),
                  ),
                )
              else if (c.recommendationsLoading &&
                  c.recommendationBooks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (c.recommendationBooks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.auto_awesome_outlined,
                    title: '暂时没有推荐书籍',
                    message: '网络恢复后可以重新加载。',
                    action: '重新加载',
                    onAction: () => c.loadRecommendations(refresh: true),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '热门推荐',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: '换一批',
                          onPressed: c.recommendationsLoading
                              ? null
                              : () => c.loadRecommendations(refresh: true),
                          icon: c.recommendationsLoading
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: column == columnCount - 1 ? 0 : gap,
                                ),
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
            if (c.searchPage != null) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
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
                                input.text,
                                page: c.searchPage!.page + 1,
                              ),
                        icon: const Icon(Icons.arrow_downward_rounded),
                        label: Text('加载第 ${c.searchPage!.page + 1} 页'),
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

class BookAction extends StatelessWidget {
  final Book book;
  final ReaderController controller;
  const BookAction({super.key, required this.book, required this.controller});
  @override
  Widget build(BuildContext context) {
    final busy =
        controller.resolvingDownloads.contains(book.ref) ||
        controller.downloads.any((d) => d.active && d.book.ref == book.ref);
    return IconButton(
      tooltip: busy ? '下载中' : '下载',
      onPressed: busy
          ? null
          : () => guarded(context, () => controller.startDownload(book)),
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
class HistoryScreen extends StatelessWidget {
  final ReaderController controller;
  const HistoryScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.loggedIn) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 30),
        children: [
          Text('下载记录', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 6),
          const Text('登录后查看账户在云端的下载历史。'),
          const SizedBox(height: 26),
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
    final page = c.historyPage;
    return NotificationListener<ScrollNotification>(
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
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '下载记录',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: c.historyLoading ? null : c.loadHistory,
                      icon: c.historyLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
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
            else if (page.books.isEmpty)
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
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => BookTile(
                        page.books[i],
                        onTap: () => showBookDetails(context, c, page.books[i]),
                        trailing: BookAction(
                          book: page.books[i],
                          controller: c,
                        ),
                        showDownloadDate: true,
                      ),
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
                            label: Text(c.historyLoading ? '加载中…' : '加载更多历史记录'),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
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
              BookCover(item.book, width: 48, height: 70),
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
        Text('我的', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text('账户、历史和阅读设置', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: c.loggedIn
                ? Row(
                    children: [
                      Builder(
                        builder: (_) {
                          final avatar = avatarUrl(c);
                          return ClipOval(
                            child: SizedBox.square(
                              dimension: 44,
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
                        radius: 22,
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
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                minVerticalPadding: 2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: Badge(
                  isLabelVisible: c.activeDownloads > 0,
                  label: Text('${c.activeDownloads}'),
                  child: const Icon(Icons.download_rounded),
                ),
                title: const Text('下载任务'),
                subtitle: Text(
                  c.activeDownloads > 0
                      ? '${c.activeDownloads} 项正在下载'
                      : '查看本地下载进度与文件',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
              const Divider(indent: 56),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                minVerticalPadding: 2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
              const Divider(indent: 56),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                minVerticalPadding: 2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.palette_outlined),
                title: const Text('外观'),
                subtitle: Text(themeLabel(c.theme)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showTheme(context, c),
              ),
              const Divider(indent: 56),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                minVerticalPadding: 2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.lan_outlined),
                title: const Text('连接线路'),
                subtitle: Text(c.host),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showRoutes(context, c),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'z-lib 0.1.0 · 基于开源项目',
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

Future<void> showBookDetails(
  BuildContext context,
  ReaderController c,
  Book initial,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => BookDetailsSheet(controller: c, initial: initial),
);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(book, width: 112, height: 162),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: Theme.of(context).textTheme.headlineSmall,
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
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        IconButton(
                          tooltip: widget.controller.bookmarked(book)
                              ? '取消收藏'
                              : '收藏',
                          onPressed: () {
                            widget.controller.toggleBookmark(book);
                            setState(() {});
                          },
                          icon: Icon(
                            widget.controller.bookmarked(book)
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                          ),
                        ),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => guarded(context, () async {
                              await widget.controller.startDownload(book);
                              if (context.mounted) Navigator.pop(context);
                            }),
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('下载'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
          final page = c.historyPage;
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
