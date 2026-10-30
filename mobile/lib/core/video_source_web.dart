import 'package:video_player/video_player.dart';

/// Web: video chọn từ máy là blob URL của trình duyệt.
VideoPlayerController controllerFromLocalPath(String path) =>
    VideoPlayerController.networkUrl(Uri.parse(path));
