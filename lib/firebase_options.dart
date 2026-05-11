import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA2Xjq6x50oejIMDu-j1G5FP_L5klcDcng',
    appId: '1:205018856680:android:7d54aacf59a34ad58cdd5d',
    messagingSenderId: '205018856680',
    projectId: 'patitas-dd0bb',
    storageBucket: 'patitas-dd0bb.firebasestorage.app',
  );
}
