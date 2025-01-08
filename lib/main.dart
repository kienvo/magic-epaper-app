import 'dart:io';
import 'dart:math';

import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import "dart:convert";
import 'dart:typed_data';
import 'package:convert/convert.dart';

import 'imagehandler.dart';

import 'epdutils.dart';

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

ImageUtils imageUtils = ImageUtils();

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Namer App',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        ),
        home: MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  var current = WordPair.random();
}

class MyHomePage extends StatelessWidget {
  void nfc_write() async {
    // var pixels = await imageUtils.generateByteData('assets/images/FOSSASIA.svg');
    // var pixels = await imageUtils.generateByteData('assets/images/FOSSASIA-rotated.svg');
    // var pixels = await imageUtils.convertBitmapToByteData('assets/images/tux-fit.png');
    var (red, black) = await imageUtils.convertBitmapToByteDataBiColor('assets/images/black-red.png');

    int chunkSize = 220; // NFC tag can handle 255 bytes per chunk.
    List<Uint8List> redChunks = imageUtils.divideUint8List(red, chunkSize);
    List<Uint8List> blackChunks = imageUtils.divideUint8List(black, chunkSize);
    // debugPrint("chunks data  = $chunks", wrapWidth: 1024);
    // print("chunks length = ${chunks.length}");
    MagicEpd.writeChunk(blackChunks, redChunks);
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('A random idea:'),
            Text(appState.current.asLowerCase),
            ElevatedButton(
              onPressed: () {
                print('button pressed!');
                nfc_write();
              },
              child: Text('Start transfer'),
            ),
          ],
        ),
      ),
    );
  }
}
