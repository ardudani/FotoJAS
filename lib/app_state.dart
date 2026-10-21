import 'services/camera_service.dart';
import 'services/drive_service.dart';
import 'settings.dart';

/// Servicios compartidos por toda la app.
class App {
  static late AppSettings settings;
  static late CameraService camera;
  static late DriveService drive;
}
