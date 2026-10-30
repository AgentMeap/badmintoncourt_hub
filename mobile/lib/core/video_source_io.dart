import 'dart:io' show File;
import 'package:video_player/video_player.dart';

/// Android / iOS: video chọn từ máy là đường dẫn file.
VideoPlayerController controllerFromLocalPath(String path) => VideoPlayerController.file(File(path));
