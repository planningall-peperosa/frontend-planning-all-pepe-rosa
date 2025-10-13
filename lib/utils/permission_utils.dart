import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionUtils {
  /// Richiede i permessi necessari per accedere alla galleria e alla memoria
  static Future<void> richiediPermessiBase() async {
    // 📱 ANDROID
    if (Platform.isAndroid) {
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }

      // Android 13+ (permessi separati per foto/video/audio)
      if (await Permission.photos.isDenied) {
        await Permission.photos.request();
      }
      if (await Permission.videos.isDenied) {
        await Permission.videos.request();
      }
      if (await Permission.audio.isDenied) {
        await Permission.audio.request();
      }
    }

    // 🍏 iOS & macOS
    if (Platform.isIOS || Platform.isMacOS) {
      if (await Permission.photos.isDenied) {
        await Permission.photos.request();
      }

      // Se l'utente ha negato in modo permanente → apro impostazioni
      if (await Permission.photos.isPermanentlyDenied) {
        await openAppSettings();
      }
    }

    // 💻 Windows/Linux: nessun permesso richiesto, ma lasciamo il metodo
  }
}
