import 'package:flutter/material.dart';

import 'api_exception.dart';

/// Hiện lỗi API dưới dạng SnackBar với câu tiếng Việt dễ hiểu.
void showApiError(BuildContext context, Object error, {String? fallback}) {
  if (!context.mounted) return;
  final message = fallback == null
      ? ApiException.messageOf(error)
      : ApiException.messageOf(error, fallback);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
