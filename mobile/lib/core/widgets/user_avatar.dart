import 'package:flutter/material.dart';

/// Ảnh đại diện tròn: ảnh từ [url] (VD ảnh tài khoản Google), lỗi / trống thì hiện
/// chữ cái đầu của [name] trên nền màu Theme.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.url = '', this.radius = 26});

  final String name;
  final String url;
  final double radius;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final last = parts.length > 1 ? parts.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Text(
      _initials,
      style: TextStyle(
        color: cs.onPrimaryContainer,
        fontWeight: FontWeight.w800,
        fontSize: radius * 0.7,
      ),
    );
    return Semantics(
      label: 'Ảnh đại diện của $name',
      image: true,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: cs.primaryContainer,
        child: url.isEmpty
            ? fallback
            : ClipOval(
                child: Image.network(
                  url,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(child: fallback),
                ),
              ),
      ),
    );
  }
}
