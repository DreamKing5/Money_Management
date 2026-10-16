import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'このプラットフォームのFirebase設定はありません。',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDVYnPwp-wddKKYZwWUaE-PuTQr51E0a_8',
    appId: '1:760600053077:web:2b3355a2f5e667f4e79bdc',
    messagingSenderId: '760600053077',
    projectId: 'moneymanagement-tm',
    authDomain: 'moneymanagement-tm.firebaseapp.com',
    storageBucket: 'moneymanagement-tm.firebasestorage.app',
    measurementId: 'G-GD7ZP83JGV',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
  );
}
