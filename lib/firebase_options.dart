// إعدادات Firebase لمشروع taawanu-4ca70.
// القيم دي مش أسرار: بتعرّف التطبيق بمشروع Firebase بس.
// الحماية الفعلية في قواعد أمان Firestore على السيرفر.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('نسخة الويب لسه مش متجهزة.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('المنصة دي مش مدعومة.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD2EZUmBhCsK-UwfQYaHorTbcKE5GZYKko',
    appId: '1:880661928235:android:d65c206996abb276208d6e',
    messagingSenderId: '880661928235',
    projectId: 'taawanu-4ca70',
    storageBucket: 'taawanu-4ca70.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCxH8fk1APQP8AWC1Bk5vHVrLKVeMKL6Tg',
    appId: '1:880661928235:ios:09faaabd236c3c34208d6e',
    messagingSenderId: '880661928235',
    projectId: 'taawanu-4ca70',
    storageBucket: 'taawanu-4ca70.firebasestorage.app',
    iosClientId: '880661928235-gotsckn46lhkd1uk3prlu5muqgat4qc5.apps.googleusercontent.com',
    iosBundleId: 'com.taawanu.taawanu',
  );
}
