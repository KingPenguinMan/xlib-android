import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'domain.dart';

/// App 内嵌网页视图：作者主页、书单作者、评论等。
///
/// 用 InAppWebView 而不是 webview_flutter：后者滚动时会出现
/// 「画面回到变化前」的残影（PlatformView 重绘问题）。
///
/// 另外把 App 的登录 Cookie 注入进来，网页里也能识别账号。
class WebViewPage extends StatefulWidget {
  final String url;
  final String title;
  final Session? session;

  /// 页面加载完成后注入的 JS（例如自动切到评论区）。
  final String? onLoadJs;

  /// 临时诊断：记录网页发出的所有 XHR/fetch 请求。
  final bool logRequests;
  const WebViewPage({
    super.key,
    required this.url,
    this.title = '',
    this.session,
    this.onLoadJs,
    this.logRequests = false,
  });

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  InAppWebViewController? _controller;
  bool _cookiesReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareCookies());
  }

  /// 把 App 的登录态写进 WebView 的 Cookie 仓库，再去加载页面。
  Future<void> _prepareCookies() async {
    final s = widget.session;
    try {
      if (s != null && s.valid) {
        final uri = Uri.parse(widget.url);
        final origin = 'https://${uri.host}';
        final manager = CookieManager.instance();
        await manager.setCookie(
          url: WebUri(origin),
          name: 'remix_userid',
          value: s.userId,
        );
        await manager.setCookie(
          url: WebUri(origin),
          name: 'remix_userkey',
          value: s.userKey,
        );
      }
    } catch (_) {
      // 注入失败也照常展示页面（只是显示未登录态）。
    } finally {
      if (mounted) setState(() => _cookiesReady = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? '网页' : widget.title),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
          ),
        ],
      ),
      body: !_cookiesReady
          ? const Center(child: CircularProgressIndicator())
          : InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: false,
                useShouldOverrideUrlLoading: false,
                supportZoom: false,
                useShouldInterceptRequest: widget.logRequests,
              ),
              shouldInterceptRequest: (controller, request) async {
                if (widget.logRequests) {
                  final u = request.url.toString();
                  if (!u.contains('.css') &&
                      !u.contains('.js') &&
                      !u.contains('.png') &&
                      !u.contains('.jpg') &&
                      !u.contains('.svg') &&
                      !u.contains('.woff')) {
                    print('[req] $u');
                  }
                }
                return null;
              },
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStop: (controller, url) async {
                final js = widget.onLoadJs;
                if (js != null && js.isNotEmpty) {
                  await controller.evaluateJavascript(source: js);
                }
              },
            ),
    );
  }
}
