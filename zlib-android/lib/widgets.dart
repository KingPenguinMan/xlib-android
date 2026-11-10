import 'package:flutter/material.dart';

import 'api.dart';
import 'controller.dart';
import 'domain.dart';

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Image.asset('assets/zlib_logo.png', fit: BoxFit.contain),
  );
}

class Pill extends StatelessWidget {
  final String text;
  final Color? color;
  const Pill(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

class BookCover extends StatelessWidget {
  final Book book;
  final double width, height;
  const BookCover(this.book, {super.key, this.width = 58, this.height = 84});
  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xffd9e3d5),
      const Color(0xffeadaca),
      const Color(0xffd9dfec),
      const Color(0xffe4d9e8),
    ];
    final bg =
        colors[book.title.runes.fold<int>(0, (a, b) => a + b) % colors.length];
    Widget placeholder() => Container(
      color: bg,
      padding: EdgeInsets.all(width * .12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: width * .29,
            color: const Color(0xff536359),
          ),
          SizedBox(height: height * .08),
          Text(
            book.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xff32483c),
              fontSize: width * .14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    final isbn = book.isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    final fallbackCover = isbn.isEmpty
        ? ''
        : 'https://covers.openlibrary.org/isbn/$isbn-M.jpg';
    Widget remoteCover(String url, {bool allowFallback = true}) =>
        Image.network(
          url,
          fit: BoxFit.cover,
          headers: const {'User-Agent': 'Mozilla/5.0 z-lib-android'},
          errorBuilder: (_, e, s) =>
              allowFallback && fallbackCover.isNotEmpty && url != fallbackCover
              ? remoteCover(fallbackCover, allowFallback: false)
              : placeholder(),
          loadingBuilder: (context, child, event) =>
              event == null ? child : placeholder(),
        );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: book.cover.isNotEmpty
            ? remoteCover(book.cover)
            : fallbackCover.isNotEmpty
            ? remoteCover(fallbackCover, allowFallback: false)
            : placeholder(),
      ),
    );
  }
}

class BookTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showDownloadDate;
  const BookTile(
    this.book, {
    super.key,
    required this.onTap,
    this.trailing,
    this.showDownloadDate = false,
  });

  String _downloadTimeLabel() {
    final raw = book.downloadedAt.trim();
    if (raw.isEmpty) return '下载时间未知';
    final time = book.localDownloadTime;
    if (time == null) return raw;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(book),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 5),
                  Text(
                    book.author.isEmpty ? '作者信息暂缺' : book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (book.extension.isNotEmpty) Pill(book.extension),
                      if (book.size.isNotEmpty && book.size != '0 B')
                        Pill(book.size),
                      if (book.year.isNotEmpty) Pill(book.year),
                    ],
                  ),
                  if (showDownloadDate)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '下载于 ${_downloadTimeLabel()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  if (book.date.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        book.date,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 36),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(23),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 36,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 9),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.7,
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 22),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

Future<void> guarded(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : '操作未完成：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

Future<bool> showLogin(
  BuildContext context,
  ReaderController controller,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LoginSheet(controller: controller),
    ) ??
    false;

class LoginSheet extends StatefulWidget {
  final ReaderController controller;
  const LoginSheet({super.key, required this.controller});
  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false, obscure = true;
  String error = '';
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.controller.login(email.text, password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        4,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandMark(),
            const SizedBox(height: 18),
            Text(
              '欢迎来到 z-lib',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '使用你的 Z-Library 账户登录',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () => showRoutes(context, widget.controller),
              icon: const Icon(Icons.lan_outlined, size: 17),
              label: Text('当前线路：${widget.controller.host}'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: '邮箱',
                prefixIcon: Icon(Icons.alternate_email),
              ),
              validator: (v) => (v ?? '').contains('@') ? null : '请输入有效邮箱',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: password,
              enabled: !busy,
              obscureText: obscure,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: obscure ? '显示密码' : '隐藏密码',
                  onPressed: () => setState(() => obscure = !obscure),
                  icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (v) => (v ?? '').isEmpty ? '请输入密码' : null,
            ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录并开始找书'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '密码不会保存；登录凭据保存在本机应用数据中。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        try {
                          await widget.controller.ensureRoute();
                          await widget.controller.native.openUrl(
                            '${widget.controller.activeOrigin}/register',
                          );
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        }
                      },
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('没有账户？前往注册'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showRoutes(BuildContext context, ReaderController c) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .9,
        child: AnimatedBuilder(
          animation: c,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '选择连接线路',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.probing
                                ? '正在逐条检查可用性…'
                                : '${c.healthyCount} 条可用 · 以当前网络实测为准',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '重新检测',
                      onPressed: c.probing ? null : () => c.probeRoutes(),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SegmentedButton<bool>(
                  expandedInsets: EdgeInsets.zero,
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('自动选择'),
                      icon: Icon(Icons.auto_awesome_outlined),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('手动选择'),
                      icon: Icon(Icons.touch_app_outlined),
                    ),
                  ],
                  selected: {c.automatic},
                  onSelectionChanged: (value) =>
                      guarded(context, () => c.setAutomatic(value.first)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  c.automatic
                      ? '优先选择响应较快的可用线路，读取失败时自动尝试其他可用线路。'
                      : '点击下方线路固定使用。手动模式不会自行切换线路。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (c.probing) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: c.routes.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final r = c.routes[index];
                    final chosen = c.activeOrigin == r.effectiveOrigin;
                    final color = r.usable
                        ? Theme.of(context).colorScheme.primary
                        : r.status == RouteStatus.failed ||
                              r.status == RouteStatus.blocked ||
                              r.status == RouteStatus.timeout
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.outline;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        leading: r.status == RouteStatus.testing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                r.usable
                                    ? Icons.check_circle_outline
                                    : Icons.language_rounded,
                                color: color,
                              ),
                        title: Text(
                          r.usable ? Uri.parse(r.effectiveOrigin).host : r.host,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          r.detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: color),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (chosen) Icon(Icons.check_rounded, color: color),
                            if (r.usable)
                              Text(
                                '${r.milliseconds} ms',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        onTap: r.status == RouteStatus.testing
                            ? null
                            : () => guarded(context, () async {
                                await c.selectRoute(r);
                                if (context.mounted) Navigator.pop(context);
                              }),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
