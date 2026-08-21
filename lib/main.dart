import 'package:flutter/material.dart';

import 'src/face_camera_view.dart';

void main() {
  runApp(const FaceCameraApp());
}

class FaceCameraApp extends StatelessWidget {
  const FaceCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceCamera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const FaceCameraView(),
    );
  }
}
