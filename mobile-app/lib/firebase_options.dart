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
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDCZolgkxYj6fBvJ_OT1v6o5qVVmVKpuy8',
    appId: '1:126719829029:web:1314a91c649d4746f44bcc',
    messagingSenderId: '126719829029',
    projectId: 'project-3077643193540297838',
    storageBucket: 'project-3077643193540297838.firebasestorage.app',
    measurementId: 'G-M3RTF80GN1',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCkMPOu8OXeay131gO4HQ_eF7cTFQK25wY',
    appId: '1:126719829029:android:bb57d957740259c6f44bcc',
    messagingSenderId: '126719829029',
    projectId: 'project-3077643193540297838',
    storageBucket: 'project-3077643193540297838.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDCZolgkxYj6fBvJ_OT1v6o5qVVmVKpuy8',
    appId: '1:126719829029:ios:taxopark_driver',
    messagingSenderId: '126719829029',
    projectId: 'project-3077643193540297838',
    storageBucket: 'project-3077643193540297838.firebasestorage.app',
    iosBundleId: 'com.taxopark.driver',
  );
}
