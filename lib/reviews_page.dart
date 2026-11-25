import 'package:flutter/material.dart';

import 'controller.dart';
import 'domain.dart';
import 'webview_page.dart';

/// 书籍评论页：直接打开 zlib 官方详情页的评论区。
///
/// 评论正文由网页 JS 动态加载，App 内解析不到，
/// 所以这里不做原生列表，直接展示官方评论区（自动切到 Comments 标签），
/// 既能看全部评论，也能在网页上发表评论。
class ReviewsPage extends StatelessWidget {
  final ReaderController controller;
  final Book book;

  /// 官方评论条数（详情页已解析）。
  final int commentCount;

  const ReviewsPage({
    super.key,
    required this.controller,
    required this.book,
    this.commentCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final origin = controller.activeOrigin;
    final url = '$origin/book/${Uri.encodeComponent(book.hash)}';
    // 页面加载完后自动切到 COMMENTS 标签并滚到评论区。
    const js = r'''
      (function() {
        function go() {
          var tab = document.querySelector('[z-tab="comments"]') ||
                    document.querySelector('[to="comments"]') ||
                    document.querySelector('a[href="#comments"]');
          if (tab) { tab.click(); }
          var box = document.querySelector('.book-comments') ||
                    document.querySelector('[z-tab-content="comments"]');
          if (box) { box.scrollIntoView({block: 'start'}); }
        }
        setTimeout(go, 900);
        setTimeout(go, 2000);
        setTimeout(go, 3500);
      })();
    ''';
    final count = commentCount > 0 ? commentCount : book.commentCount;
    return WebViewPage(
      url: url,
      title: count > 0 ? '评论（共 $count 条）' : '评论',
      session: controller.session,
      onLoadJs: js,
    );
  }
}
