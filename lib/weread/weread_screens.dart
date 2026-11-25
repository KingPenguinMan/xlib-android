/// 微信读书界面：扫码连接、书城搜索、书架、书籍详情。
///
/// 视觉沿用本项目既有风格（阅读纸色背景、衬线标题、8/16 圆角），
/// 交互参考 olib-mobile 的 weread 页面，但按本项目的单控制器结构重写。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../webview_page.dart';

import 'package:qr_flutter/qr_flutter.dart';

import '../native.dart';
import '../widgets.dart';
import 'weread_controller.dart';
import 'weread_models.dart';

/// 微信读书 tab 的根组件。
class WereadScreen extends StatefulWidget {
  final WereadController controller;
  const WereadScreen({super.key, required this.controller});

  @override
  State<WereadScreen> createState() => _WereadScreenState();
}

class _WereadScreenState extends State<WereadScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.ensureStarted();
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (controller.checking) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!controller.connected) return _ConnectView(controller: controller);
      return _BrowseView(controller: controller);
    },
  );
}

// ═══════════════════════════ 扫码连接 ═══════════════════════════

class _ConnectView extends StatefulWidget {
  final WereadController controller;
  const _ConnectView({required this.controller});

  @override
  State<_ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<_ConnectView> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.qrPhase == QrPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.startQr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Text('连接微信读书', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
          '用微信扫码授权后，可以搜索微信读书书城、同步你的书架。'
          '登录凭据会加密保存在本机，不会上传到别处。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              SizedBox(height: 240, child: Center(child: _qrArea(c, colors))),
              const SizedBox(height: 16),
              Text(
                c.qrMessage.isEmpty ? '正在准备二维码…' : c.qrMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: c.qrPhase == QrPhase.error
                      ? colors.error
                      : colors.onSurfaceVariant,
                ),
              ),
              if (c.connectionError.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  c.connectionError,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (c.qrPhase == QrPhase.waiting ||
                      c.qrPhase == QrPhase.scanned)
                    TextButton.icon(
                      onPressed: c.cancelQr,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('取消'),
                    ),
                  if (c.qrPhase == QrPhase.error || c.qrPhase == QrPhase.idle)
                    FilledButton.tonalIcon(
                      onPressed: c.startQr,
                      icon: const Icon(Icons.qr_code_2, size: 18),
                      label: const Text('生成二维码'),
                    ),
                  if (c.qrPhase == QrPhase.waiting ||
                      c.qrPhase == QrPhase.scanned)
                    TextButton.icon(
                      onPressed: c.startQr,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('刷新'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '提示：在微信里点「确认登录」后，本页会自动完成连接。'
          '连上之后请立刻到右上角菜单「导出连接信息」保存好，'
          '以后重装或换机粘贴回来即可，不用再扫。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _showImportDialog(context, c),
          icon: const Icon(Icons.key_outlined, size: 18),
          label: const Text('用连接信息恢复登录'),
        ),
        const SizedBox(height: 6),
        Text(
          '换机或重装前，可在已连接状态的右上角菜单里「导出连接信息」；'
          '之后粘贴到这里即可恢复，不用再扫码。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Future<void> _showImportDialog(
    BuildContext context,
    WereadController c,
  ) async {
    final input = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('导入连接信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('把之前导出的连接信息粘贴到这里，验证通过后即可恢复登录，不用再扫码。'),
            const SizedBox(height: 12),
            TextField(
              controller: input,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '{"vid": "...", "accessToken": "...", ...}',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      input.dispose();
      return;
    }
    try {
      await c.importConnection(input.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('连接信息有效，已恢复登录')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      input.dispose();
    }
  }

  Widget _qrArea(WereadController c, ColorScheme colors) {
    if (c.qrPhase == QrPhase.loading) {
      return const CircularProgressIndicator();
    }
    final qr = c.qr;
    if (qr == null) {
      return Icon(
        Icons.qr_code_2,
        size: 96,
        color: colors.primary.withValues(alpha: .35),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: qr.imageBytes != null
              ? Image.memory(
                  qr.imageBytes!,
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                )
              : QrImageView(
                  data: qr.confirmUrl,
                  version: QrVersions.auto,
                  size: 200,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                ),
        ),
        if (c.qrPhase == QrPhase.scanned)
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 44),
                SizedBox(height: 10),
                Text(
                  '已扫码',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════ 书城 / 书架 ═══════════════════════════

class _BrowseView extends StatelessWidget {
  final WereadController controller;
  const _BrowseView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
          child: Row(
            children: [
              Text('我的书架', style: theme.textTheme.titleLarge),
              const SizedBox(width: 8),
              if (c.shelfBooks.isNotEmpty)
                Text(
                  '${c.shelfBooks.length} 本',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: '刷新书架',
                onPressed: c.shelfLoading ? null : c.loadShelf,
                icon: c.shelfLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: '连接选项',
                onSelected: (value) async {
                  if (value == 'export') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: const Text('导出连接信息？'),
                        content: const Text(
                          '这段内容等同于你的微信读书登录凭据，拿到它的人可以访问你的书架。'
                          '请只保存在自己能控制的地方。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialog, true),
                            child: const Text('复制'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    final raw = await c.exportConnection();
                    if (raw == null || raw.isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('当前没有可导出的连接信息')),
                        );
                      }
                      return;
                    }
                    await Clipboard.setData(ClipboardData(text: raw));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('连接信息已复制，请妥善保管')),
                      );
                    }
                  } else if (value == 'disconnect') {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: const Text('断开微信读书？'),
                        content: const Text('会清除本机保存的连接凭据。书架里的书不受影响。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialog, true),
                            child: const Text('断开'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) await c.disconnect();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'export', child: Text('导出连接信息')),
                  PopupMenuItem(value: 'disconnect', child: Text('断开连接')),
                ],
              ),
            ],
          ),
        ),
        if (c.importError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: colors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.importError,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: colors.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: c.dismissImportError,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: _ShelfView(controller: c)),
      ],
    );
  }
}

/// 微信读书的搜索结果条目，供全局搜索页复用。
class WereadResultTile extends StatelessWidget {
  final SearchResultBook book;
  final VoidCallback onTap;
  const WereadResultTile({super.key, required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = book.bookInfo;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WereadCover(url: info.cover, width: 56, height: 78),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title.isEmpty ? '未命名' : info.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if ((info.author ?? '').isNotEmpty)
                        GestureDetector(
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WebViewPage(
                                url:
                                    'https://weread.qq.com/web/search/books?keyword=${Uri.encodeComponent(info.author!)}',
                                title: info.author ?? '',
                              ),
                            ),
                          ),
                          child: Text(
                            info.author!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.primary,
                            ),
                          ),
                        ),
                      if ((info.category ?? '').isNotEmpty)
                        Text(
                          '${(info.author ?? '').isNotEmpty ? ' · ' : ''}${info.category}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (book.newRating != null && book.newRating! > 0)
                        Pill('${(book.newRating! / 10).toStringAsFixed(1)} 分'),
                      if (book.newRating != null && book.newRating! > 0)
                        const SizedBox(width: 6),
                      if (info.wordCount != null && info.wordCount! > 0)
                        Text(
                          '${(info.wordCount! / 10000).toStringAsFixed(1)} 万字',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ShelfView extends StatelessWidget {
  final WereadController controller;
  const _ShelfView({required this.controller});

  /// 长按书封直接给一个移出菜单，省得每次都点进详情页。
  Future<void> _quickRemove(BuildContext context, ShelfBook book) async {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    final author = book.author ?? '';
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: author.isEmpty ? null : Text(author),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colors.error),
              title: Text('移出微信读书书架', style: TextStyle(color: colors.error)),
              onTap: () => Navigator.pop(sheet, 'remove'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.pop(sheet),
            ),
          ],
        ),
      ),
    );
    if (action != 'remove' || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await c.removeFromShelf(book.bookId);
      messenger.showSnackBar(const SnackBar(content: Text('已移出微信读书书架')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('移出失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.shelfLoading && c.shelfBooks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c.shelfBooks.isEmpty) {
      return RefreshIndicator(
        onRefresh: c.loadShelf,
        child: ListView(
          children: [
            c.shelfError.isNotEmpty
                ? EmptyState(
                    icon: Icons.cloud_off,
                    title: '书架没有加载出来',
                    message: c.shelfError,
                    action: '重试',
                    onAction: c.loadShelf,
                  )
                : const EmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: '书架是空的',
                    message: '在微信读书里加入书架的书会显示在这里。下拉可以重新同步。',
                  ),
            const SizedBox(height: 6),
            Center(
              child: FilledButton.tonalIcon(
                onPressed: c.importing
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final bookId = await c.pickAndImport();
                          if (bookId == null) return;
                          messenger.showSnackBar(
                            const SnackBar(content: Text('已导入微信读书书架，稍等几秒即可看到')),
                          );
                        } catch (error) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('导入失败：$error')),
                          );
                        }
                      },
                icon: const Icon(Icons.add, size: 18),
                label: Text(c.importing ? '导入中…' : '从本地导入'),
              ),
            ),
          ],
        ),
      );
    }
    final sorted = [...c.shelfBooks]
      ..sort((a, b) => (b.readUpdateTime ?? 0) - (a.readUpdateTime ?? 0));
    return RefreshIndicator(
      onRefresh: c.loadShelf,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
          childAspectRatio: .52,
        ),
        // 第一格固定是「从本地导入」，书架再多也不用翻到底部。
        itemCount: sorted.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _ImportTile(controller: c);
          }
          final book = sorted[index - 1];
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onLongPress: () => _quickRemove(context, book),
            onTap: () => openWereadBook(
              context,
              c,
              book.bookId,
              initial: WereadBookInfo(
                bookId: book.bookId,
                title: book.title,
                author: book.author,
                cover: book.cover,
                category: book.category,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: WereadCover(
                          url: book.cover,
                          width: double.infinity,
                          height: double.infinity,
                          radius: 10,
                        ),
                      ),
                      if (book.isFinished)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .55),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '读完',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.3),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 书架末尾的导入位：平时是虚线和加号，上传时变成进度环。
class _ImportTile extends StatelessWidget {
  final WereadController controller;
  const _ImportTile({required this.controller});

  Future<void> _pick(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bookId = await controller.pickAndImport();
      if (bookId == null) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('已导入微信读书书架，稍等几秒即可看到')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    if (c.importing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                value: c.importProgress <= 0 ? null : c.importProgress,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(c.importProgress * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              c.importName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
            ),
            TextButton(
              onPressed: c.cancelImport,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 26),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('取消', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _pick(context),
      child: CustomPaint(
        painter: _DashedBorder(colors.primary.withValues(alpha: .38), 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add,
              size: 30,
              color: colors.primary.withValues(alpha: .55),
            ),
            const SizedBox(height: 6),
            Text(
              '从本地导入',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 虚线圆角边框，用系统 Path 度量自己切段，不需要额外依赖。
class _DashedBorder extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBorder(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) =>
      old.color != color || old.radius != radius;
}

// ═══════════════════════════ 公共组件 ═══════════════════════════

/// 微信读书封面，失败时退回主色块。
class WereadCover extends StatelessWidget {
  final String? url;
  final double width, height, radius;
  const WereadCover({
    super.key,
    required this.url,
    this.width = 56,
    this.height = 78,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      color: colors.primary.withValues(alpha: .10),
      child: Icon(
        Icons.menu_book_outlined,
        size: (width.isFinite ? width : 40) * .40,
        color: colors.primary.withValues(alpha: .55),
      ),
    );
    final raw = url ?? '';
    if (raw.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: placeholder,
      );
    }
    // 微信读书部分封面走明文 HTTP，Android 9+ 默认拦截，统一升到 HTTPS。
    final source = raw.startsWith('http://')
        ? raw.replaceFirst('http://', 'https://')
        : raw;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        source,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}

/// 打开微信读书书籍详情。
Future<void> openWereadBook(
  BuildContext context,
  WereadController controller,
  String bookId, {
  WereadBookInfo? initial,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      _BookSheet(controller: controller, bookId: bookId, initial: initial),
);

class _BookSheet extends StatefulWidget {
  final WereadController controller;
  final String bookId;
  final WereadBookInfo? initial;
  const _BookSheet({
    required this.controller,
    required this.bookId,
    this.initial,
  });

  @override
  State<_BookSheet> createState() => _BookSheetState();
}

class _BookSheetState extends State<_BookSheet> {
  final ScrollController _scrollController = ScrollController();
  WereadBookInfo? _info;
  List<ChapterInfo> _chapters = [];
  List<BestBookmarkItem> _hotBookmarks = [];
  Map<int, String> _hotBookmarkChapterTitles = {};
  bool _loading = true;
  String _error = '';
  bool _showIntro = false;
  bool _showChapters = false;
  bool _showScrollTop = false;

  @override
  void initState() {
    super.initState();
    _info = widget.initial;
    _scrollController.addListener(_onScroll);
    _load();
  }

  void _onScroll() {
    final show = _scrollController.hasClients && _scrollController.offset > 400;
    if (show != _showScrollTop) {
      setState(() => _showScrollTop = show);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 目录和进度属于附加信息，单独失败不该让整个详情页报错。
  Future<T?> _optional<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      // 三个请求同时发出，再逐个取结果。
      final api = widget.controller.api;
      final infoFuture = api.bookInfo(widget.bookId);
      final chaptersFuture = _optional(api.chapters(widget.bookId));
      final bookmarksFuture = _optional(api.bestBookmarks(widget.bookId));
      final info = await infoFuture;
      final chapters = await chaptersFuture;
      final bookmarks = await bookmarksFuture;
      if (!mounted) return;
      setState(() {
        _info = info;
        _chapters = chapters?.chapters ?? const [];
        _hotBookmarks = bookmarks?.items ?? const [];
        _hotBookmarkChapterTitles = {
          for (final chapter
              in bookmarks?.chapters ?? const <BestBookmarkChapter>[])
            chapter.chapterUid: chapter.title ?? '',
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addToShelf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.addToShelf(widget.bookId);
      messenger.showSnackBar(const SnackBar(content: Text('已加入微信读书书架')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('加入失败：$error')));
    }
  }

  /// 直接唤起微信读书 App 打开这本书（上次阅读位置）。
  /// 指定包名、绕开浏览器；没装 App 才回退到网页版。
  Future<void> _openInWeread() async {
    final messenger = ScaffoldMessenger.of(context);
    final deepLink = _info?.deepLink;
    final appUrl = (deepLink != null && deepLink.isNotEmpty)
        ? deepLink
        : 'weread://reading?bId=${widget.bookId}';
    if (await NativeBridge().openWeread(appUrl)) return;
    final webUrl = 'https://weread.qq.com/web/bookDetail/${widget.bookId}';
    if (await NativeBridge().tryOpenUrl(webUrl)) return;
    messenger.showSnackBar(const SnackBar(content: Text('请先安装微信读书 App')));
  }

  Widget _hotBookmarkTile(
    ThemeData theme,
    ColorScheme colors,
    BestBookmarkItem mark, {
    int? markTextMaxLines,
  }) {
    final chapterTitle = _hotBookmarkChapterTitles[mark.chapterUid] ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chapterTitle.isNotEmpty) ...[
            Text(
              chapterTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: .4),
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                left: BorderSide(color: Color(0xffd9a05b), width: 3),
              ),
            ),
            child: Text(
              mark.markText,
              maxLines: markTextMaxLines,
              overflow: markTextMaxLines == null ? null : TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (mark.totalCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${mark.totalCount} 人划线',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 折叠标题：点标题展开 / 收起，右侧带箭头。
  Widget _collapsibleHeader({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _openAllBookmarks() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AllBookmarksPage(
          bookTitle: _info?.title ?? '',
          items: _hotBookmarks,
          chapterTitles: _hotBookmarkChapterTitles,
        ),
      ),
    );
  }

  /// 移出书架前先确认，这个操作会直接改用户账号。
  Future<void> _confirmRemove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('移出书架'),
        content: const Text('这本书会从你的微信读书书架上移除。阅读进度和笔记不会受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.removeFromShelf(widget.bookId);
      messenger.showSnackBar(const SnackBar(content: Text('已移出微信读书书架')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('移出失败：$error')));
    }
  }

  /// 加入书架按钮：已在书架时可以点一下移出，提交中显示进度。
  Widget _shelfAction() => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (c.shelfIds.contains(widget.bookId)) {
        final removing = c.removingBooks.contains(widget.bookId);
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: removing ? null : _confirmRemove,
            icon: removing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.library_add_check, size: 18),
            label: Text(removing ? '正在移出…' : '已在书架 · 点此移出'),
          ),
        );
      }
      final adding = c.addingBooks.contains(widget.bookId);
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: adding ? null : _addToShelf,
          icon: adding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.library_add_outlined, size: 18),
          label: Text(adding ? '正在加入…' : '加入微信读书书架'),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final info = _info;
    return FractionallySizedBox(
      heightFactor: .92,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('微信读书', style: theme.textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SelectionArea(
                  child: _loading && info == null
                      ? const Center(child: CircularProgressIndicator())
                      : _error.isNotEmpty && info == null
                      ? SingleChildScrollView(
                          child: EmptyState(
                            icon: Icons.error_outline,
                            title: '没能读取这本书',
                            message: _error,
                            action: '重试',
                            onAction: _load,
                          ),
                        )
                      : ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                WereadCover(
                                  url: info?.cover,
                                  width: 92,
                                  height: 128,
                                  radius: 8,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        info?.title.isNotEmpty == true
                                            ? info!.title
                                            : '未命名',
                                        style: theme.textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 6),
                                      if ((info?.author ?? '').isNotEmpty)
                                        Text(
                                          info!.author!,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          if ((info?.category ?? '').isNotEmpty)
                                            Pill(info!.category!),
                                          if (info?.newRating != null &&
                                              info!.newRating! > 0)
                                            Pill(
                                              '${(info.newRating! / 10).toStringAsFixed(1)} 分',
                                            ),
                                          if (info?.wordCount != null &&
                                              info!.wordCount! > 0)
                                            Pill(
                                              '${(info.wordCount! / 10000).toStringAsFixed(1)} 万字',
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _shelfAction(),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonalIcon(
                                onPressed: _openInWeread,
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: const Text('在微信读书中打开'),
                              ),
                            ),
                            if ((info?.intro ?? '').isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _collapsibleHeader(
                                title: '简介',
                                expanded: _showIntro,
                                onToggle: () =>
                                    setState(() => _showIntro = !_showIntro),
                              ),
                              if (_showIntro) ...[
                                const SizedBox(height: 8),
                                Text(
                                  info!.intro!.trim(),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                            if (_hotBookmarks.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '热门划线',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _openAllBookmarks,
                                    child: const Text('查看全部'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 170,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    for (final mark in _hotBookmarks)
                                      SizedBox(
                                        width: 280,
                                        child: _hotBookmarkTile(
                                          theme,
                                          colors,
                                          mark,
                                          markTextMaxLines: 3,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            if (_chapters.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _collapsibleHeader(
                                title: '目录 · ${_chapters.length} 章',
                                expanded: _showChapters,
                                onToggle: () => setState(
                                  () => _showChapters = !_showChapters,
                                ),
                              ),
                              if (_showChapters) ...[
                                const SizedBox(height: 6),
                                for (final chapter in _chapters)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 5,
                                    ),
                                    child: Text(
                                      chapter.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                              ],
                            ],
                            const SizedBox(height: 20),
                            Text(
                              '此处只展示微信读书的数据。要阅读正文，请在微信读书 App 中打开。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: .8,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: ScrollQuickActions(
              visible: _showScrollTop,
              tag: 'wereadBook',
              onTop: _scrollToTop,
            ),
          ),
        ],
      ),
    );
  }
}

/// 全部热门划线的瀑布流页，从书籍详情「查看全部」进入。
class _AllBookmarksPage extends StatelessWidget {
  final String bookTitle;
  final List<BestBookmarkItem> items;
  final Map<int, String> chapterTitles;

  const _AllBookmarksPage({
    required this.bookTitle,
    required this.items,
    required this.chapterTitles,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // 按文本长度贪心分到两列，做出接近瀑布流的效果。
    final left = <BestBookmarkItem>[];
    final right = <BestBookmarkItem>[];
    var leftLen = 0, rightLen = 0;
    for (final mark in items) {
      final len =
          mark.markText.length + (chapterTitles[mark.chapterUid]?.length ?? 0);
      if (leftLen <= rightLen) {
        left.add(mark);
        leftLen += len;
      } else {
        right.add(mark);
        rightLen += len;
      }
    }

    Widget tile(BestBookmarkItem mark) {
      final chapterTitle = chapterTitles[mark.chapterUid] ?? '';
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: .4),
          borderRadius: BorderRadius.circular(10),
          border: const Border(
            left: BorderSide(color: Color(0xffd9a05b), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chapterTitle.isNotEmpty) ...[
              Text(
                chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(mark.markText, style: theme.textTheme.bodyMedium),
            if (mark.totalCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${mark.totalCount} 人划线',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(bookTitle.isEmpty ? '热门划线' : '热门划线 · $bookTitle'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final mark in left) tile(mark)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final mark in right) tile(mark)],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
