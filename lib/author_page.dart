import 'package:flutter/material.dart';

import 'controller.dart';
import 'domain.dart';
import 'screens.dart';

/// 作者页：列出这位作者在库里的书（App 原生列表，不跳网页）。
class AuthorPage extends StatefulWidget {
  final ReaderController controller;
  final String author;
  final String authorProfile;
  const AuthorPage({
    super.key,
    required this.controller,
    required this.author,
    required this.authorProfile,
  });

  @override
  State<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends State<AuthorPage> {
  List<Book> _books = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final result = await widget.controller.authorBooks(widget.authorProfile);
      if (mounted) setState(() => _books = result);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.author.isEmpty ? '作者' : widget.author),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              ),
            )
          : _books.isEmpty
          ? const Center(child: Text('这位作者暂时没有可显示的书'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: _books.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '共 ${_books.length} 本',
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  }
                  final book = _books[index - 1];
                  return InkWell(
                    onTap: () =>
                        showBookDetails(context, widget.controller, book),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Cover(book: book, controller: widget.controller),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                              if (book.author.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  book.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 6,
                                children: [
                                  if (book.extension.isNotEmpty)
                                    Text(
                                      book.extension,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  if (book.size.isNotEmpty)
                                    Text(
                                      book.size,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  if (book.year.isNotEmpty)
                                    Text(
                                      book.year,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// 小封面：有图用图，没图用书脊占位。
class _Cover extends StatelessWidget {
  final Book book;
  final ReaderController controller;
  const _Cover({required this.book, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const w = 58.0, h = 84.0;
    if (book.cover.isEmpty) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.menu_book_outlined, size: 22),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: w,
        height: h,
        child: Image.network(
          book.cover,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: colors.surfaceContainerHighest,
            child: const Icon(Icons.menu_book_outlined, size: 22),
          ),
        ),
      ),
    );
  }
}
