import 'package:flutter/material.dart';

/// Quy chuẩn Responsive & Adaptive UI cho toàn dự án Badminton V2.
/// Breakpoints:
/// - Mobile: < 600
/// - Tablet: 600 - 1023
/// - Desktop: >= 1024
class Responsive {
  static const double mobileMaxWidth = 600;
  static const double tabletMaxWidth = 1024;
  static const double defaultFormMaxWidth = 680;
  static const double defaultContentMaxWidth = 960;

  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static bool isMobile(BuildContext context) =>
      screenWidth(context) < mobileMaxWidth;

  static bool isTablet(BuildContext context) {
    final w = screenWidth(context);
    return w >= mobileMaxWidth && w < tabletMaxWidth;
  }

  static bool isDesktop(BuildContext context) =>
      screenWidth(context) >= tabletMaxWidth;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  static EdgeInsets screenPadding(BuildContext context) {
    if (isDesktop(context)) {
      return const EdgeInsets.symmetric(horizontal: 28, vertical: 20);
    }
    if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: 20, vertical: 16);
    }
    return const EdgeInsets.all(14);
  }
}

/// Widget phân nhánh bố cục dựa trên constraints thực tế của widget cha (LayoutBuilder).
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        if (maxW >= Responsive.tabletMaxWidth) {
          return desktop ?? tablet ?? mobile;
        }
        if (maxW >= Responsive.mobileMaxWidth) {
          return tablet ?? mobile;
        }
        return mobile;
      },
    );
  }
}

/// Giới hạn maxWidth và căn giữa nội dung trên màn hình lớn (Tablet/Desktop)
/// để tránh form/danh sách bị kéo giãn quá rộng.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = Responsive.defaultContentMaxWidth,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    );
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    return Align(
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}
