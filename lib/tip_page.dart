import 'package:flutter/material.dart';

/// 回血页：自愿赞赏，不强制、不打扰。
class TipPage extends StatelessWidget {
  const TipPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('回血')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          // 顶部：图标 + 标题
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.coffee_outlined,
                size: 30,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text('请我们喝杯咖啡', style: theme.textTheme.titleLarge)),
          const SizedBox(height: 22),

          // 二维码卡片
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/tip_qr.png',
                  width: 236,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(child: Text('微信扫码 · 金额随意', style: theme.textTheme.bodySmall)),
          const SizedBox(height: 26),

          // 说明
          _Paragraph(
            icon: Icons.auto_awesome_outlined,
            text: 'xlib 是我们一点点做出来的，一直免费、开源、没有广告。',
          ),
          const SizedBox(height: 14),
          _Paragraph(
            icon: Icons.handshake_outlined,
            text:
                '这一路投入了不少精力和 token，也收到了很多朋友的反馈和建议——'
                '这些都让 xlib 变得更好。',
          ),
          const SizedBox(height: 14),
          _Paragraph(
            icon: Icons.favorite_outline,
            text:
                '也欢迎扫码请我们回一点血。'
                '金额随意，一块钱也是心意；不赞赏也完全不影响使用，'
                '该有的功能一样不少。',
          ),
          const SizedBox(height: 14),
          _Paragraph(
            icon: Icons.chat_bubble_outline,
            text:
                '遇到问题或有建议，欢迎随时告诉我们。'
                '我们会尽力改进，让 xlib 越来越好用。',
          ),

          const SizedBox(height: 28),
          Center(
            child: Text(
              '赞赏完全自愿 · xlib 永久免费开源',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 带小图标的说明段落。
class _Paragraph extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Paragraph({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
          ),
        ),
      ],
    );
  }
}
