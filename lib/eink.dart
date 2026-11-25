/// 墨水屏构建开关。
///
/// 构建时加 `--dart-define=EINK=true` 得到墨水屏版：
/// 黑白灰阶配色、去掉页面过渡、动画时长归零。
/// 不加这个参数就是普通彩色版，两者代码同一份。
const bool einkMode = bool.fromEnvironment('EINK');

/// 根据是否墨水屏模式给动画定时长，墨水屏一律 0。
Duration uiDuration(int milliseconds) =>
    einkMode ? Duration.zero : Duration(milliseconds: milliseconds);
