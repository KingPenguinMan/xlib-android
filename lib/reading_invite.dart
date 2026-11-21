import 'dart:math' as math;

import 'package:flutter/material.dart';

typedef InviteChoice = ({bool join, bool hide});

class ReadingInvite extends StatefulWidget {
  const ReadingInvite({super.key});

  @override
  State<ReadingInvite> createState() => _ReadingInviteState();
}

class _ReadingInviteState extends State<ReadingInvite> {
  bool hide = false;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = dark ? const Color(0xff222a20) : const Color(0xfffaf8f0);
    final ink = dark ? const Color(0xfff1efdb) : const Color(0xff25351e);
    final accent = dark ? const Color(0xffc1d5a7) : const Color(0xff344f29);
    void choose({required bool join}) =>
        Navigator.pop(context, (join: join, hide: hide));
    final illustration = Image.asset(
      'assets/reading_desk.jpg',
      fit: BoxFit.cover,
      alignment: Alignment.center,
      excludeFromSemantics: true,
    );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '一起读书，一起学习',
            style: TextStyle(
              fontSize: 25,
              fontFamily: 'serif',
              height: 1.28,
              fontWeight: FontWeight.bold,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '加入 Reading club，和书友一起学习、交流书单，获取应用更新。',
            style: TextStyle(color: ink, fontSize: 15, height: 1.55),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: hide,
            title: Text('不再弹出此邀请', style: TextStyle(color: ink, fontSize: 14)),
            onChanged: (value) => setState(() => hide = value ?? false),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: ink,
                    backgroundColor: ink.withValues(alpha: .08),
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () => choose(join: false),
                  child: const Text('暂不加入'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: paper,
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () => choose(join: true),
                  child: const Text('加入 QQ 群'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Dialog(
      backgroundColor: paper,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, limits) {
          final wide =
              MediaQuery.orientationOf(context) == Orientation.landscape &&
              limits.maxWidth >= 490;
          if (wide) {
            return SizedBox(
              width: 620,
              height: math.min(268.0, limits.maxHeight),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 2, child: illustration),
                  Expanded(
                    flex: 4,
                    child: Center(child: SingleChildScrollView(child: content)),
                  ),
                ],
              ),
            );
          }
          return SizedBox(
            width: 370,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: math.min(160.0, limits.maxHeight * .28),
                    child: illustration,
                  ),
                  content,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
