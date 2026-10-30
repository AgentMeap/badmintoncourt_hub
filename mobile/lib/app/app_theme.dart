import 'package:flutter/material.dart';

/// Theme chung của app (design system theo skill ui-ux-pro-max):
/// màu sinh từ seed xanh thương hiệu, font Barlow cho nội dung,
/// Barlow Condensed cho số lớn (nhóm display), có cả giao diện sáng và tối.
class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF059669);

  static ThemeData build([Brightness brightness = Brightness.light]) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: seed,
      brightness: brightness,
      // Nền sáng hơi xám để thẻ trắng nổi lên; nền tối dùng mặc định của ColorScheme
      scaffoldBackgroundColor: isDark ? null : const Color(0xFFF8FAFC),
      fontFamily: 'Barlow',
    );
    // Theo skill (cặp Barlow / Barlow Condensed): Condensed chỉ dành cho "impact headline"
    // -> dùng cho nhóm display (số lớn: số dư ví, tiền giải ngân), độ đậm tối đa 700.
    TextStyle? condensed(TextStyle? s) =>
        s?.copyWith(fontFamily: 'BarlowCondensed', fontWeight: FontWeight.w700);
    // Tiêu đề màn hình (headline) dùng Barlow thường cùng độ rộng với nội dung,
    // đậm 700, cao dòng 1.3 để dấu tiếng Việt (ở, đâu, đánh) không bị chật.
    TextStyle? heading(TextStyle? s) => s?.copyWith(fontWeight: FontWeight.w700, height: 1.3);
    final t = base.textTheme;
    return base.copyWith(
      textTheme: t.copyWith(
        displayLarge: condensed(t.displayLarge),
        displayMedium: condensed(t.displayMedium),
        displaySmall: condensed(t.displaySmall),
        headlineLarge: heading(t.headlineLarge),
        headlineMedium: heading(t.headlineMedium),
        headlineSmall: heading(t.headlineSmall),
      ),
    );
  }

  static ThemeData get light => build(Brightness.light);
  static ThemeData get dark => build(Brightness.dark);
}
