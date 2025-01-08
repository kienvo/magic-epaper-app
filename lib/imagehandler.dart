import 'dart:ffi';
import 'dart:ui' as ui;
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:magic_epaper_app/epdutils.dart';
import 'package:matrix2d/matrix2d.dart';
import 'package:image/image.dart' as img;

class ImageUtils {
  late double originalHeight;
  late double originalWidth;

  late ui.Picture picture;

  //convert the 2D list to Uint8List
  //this funcction will be ustilised to convert the user drawn badge to Uint8List
  //and thus will be able to display with other vectors in the badge
  Future<Uint8List> convert2DListToUint8List(List<List<int>> twoDList) async {
    int height = twoDList.length;
    int width = twoDList[0].length;

    // Create a buffer to hold the pixel data
    Uint8List pixels =
        Uint8List(width * height * 4); // 4 bytes per pixel (RGBA)

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int value = twoDList[y][x] == 1 ? 0 : 255;
        int offset = (y * width + x) * 4;
        pixels[offset] = value; // Red
        pixels[offset + 1] = value; // Green
        pixels[offset + 2] = value; // Blue
        pixels[offset + 3] = 255; // Alpha
      }
    }

    // Create an ImmutableBuffer from the pixel data
    ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(pixels);

    // Create an ImageDescriptor from the buffer
    ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );

    // Instantiate a codec
    ui.Codec codec = await descriptor.instantiateCodec();

    // Get the first frame from the codec
    ui.FrameInfo frameInfo = await codec.getNextFrame();

    // Get the image from the frame
    ui.Image image = frameInfo.image;

    // Convert the image to PNG format
    ByteData? pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return pngBytes!.buffer.asUint8List();
  }

  //function that generates the Picture from the given asset
  Future<void> _loadSVG(String asset) async {
    //loading the Svg from the assets
    String svgString = await rootBundle.loadString(asset);

    // Load SVG picture and information
    final SvgStringLoader svgStringLoader = SvgStringLoader(svgString);
    final PictureInfo pictureInfo = await vg.loadPicture(svgStringLoader, null);
    picture = pictureInfo.picture;

    //setting the origin heigh and width of the svg
    originalHeight = pictureInfo.size.height;
    originalWidth = pictureInfo.size.width;
  }

  //function to load and scale the svg according to the badge size
  Future<ui.Image> _scaleSVG(
      ui.Image inputImage, double targetHeight, double targetWidth) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = Canvas(recorder,
        Rect.fromPoints(Offset.zero, Offset(targetWidth, targetHeight)));

    double scaleX = targetWidth / inputImage.width;
    double scaleY = targetHeight / inputImage.height;

    // double scale = scaleX < scaleY ? scaleX : scaleY; // Lock width and height ratio of the original image?

    double dx = (targetWidth - (inputImage.width * scaleX)) / 2;
    double dy = (targetHeight - (inputImage.height * scaleY)) / 2;
    canvas.translate(dx, dy);
    canvas.scale(scaleX, scaleY);

    canvas.drawImage(inputImage, Offset.zero, Paint());

    final ui.Image imgByteData = await recorder
        .endRecording()
        .toImage(targetWidth.ceil(), targetHeight.ceil());

    return imgByteData;
  }

  //function to convert the ui.Image to byte array
  Future<Uint8List?> _convertImageToByteArray(ui.Image image) async {
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData?.buffer.asUint8List();
  }

  //function to convert the byte array to 2D list of pixels
  List<List<int>> _convertUint8ListTo2DList(
      Uint8List byteArray, int width, int height) {
    //initialize the 2D list of pixels
    List<List<int>> pixelArray =
        List.generate(height, (i) => List<int>.filled(width, 0));
    int bytesPerPixel = 4; // RGBA format (4 bytes per pixel)
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int index = (y * width + x) * bytesPerPixel;
        if (index + bytesPerPixel <= byteArray.length) {
          int a = byteArray[index + 3];
          int color = (a << 24);
          pixelArray[y][x] = color;
        } else {
          // Handle out-of-bounds case gracefully, e.g., fill with a default color
          pixelArray[y][x] = Colors.transparent.value;
        }
      }
    }
    return pixelArray;
  }

  /**
   * Convert pixels to 8 pixels/byte in row-major order.
   *  */
  Uint8List _convertPixelsToEpdBytes(List<List<int>> pixels)
  {
    var flatPixels = (pixels).expand((i) => i).toList();
    List<int> bytes = List.empty(growable: true);
    int j=0;
    int byte = 0;
    for (int i=0; i<flatPixels.length; i++) {
      if (flatPixels[i] == Colors.transparent.value) {
        byte |= 0x80 >> j;
      }
      j++;
      if (j >= 8) {
        bytes.add(byte);
        byte = 0;
        j = 0;
      }
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List _convertImageArrayToEpdBytes(Uint8List imgArray)
  {
    List<int> bytes = List.empty(growable: true);
    int j=0;
    int byte = 0;
    for (int i=3; i<imgArray.length; i+=4) {
      double gray = (0.299*imgArray[i-3] 
                    + 0.587*imgArray[i-2] 
                    + 0.114*imgArray[i-1]);
                    // * imgArray[i] / 255;
      if (gray >= 127) {
        byte |= 0x80 >> j;
      }

      j++;
      if (j >= 8) {
        bytes.add(byte);
        byte = 0;
        j = 0;
      }
    }
    return Uint8List.fromList(bytes);
  }

  //function to generate the LED hex from the given asset
  Future<Uint8List> generateByteData(String asset) async {
    await _loadSVG(asset);
    ui.Image image = await picture.toImage(originalWidth.toInt(), originalHeight.toInt());
    ui.Image scaledImage = await _scaleSVG(image, 416, 240);
    final Uint8List? byteArray = await _convertImageToByteArray(scaledImage);
    final List<List<int>> pixelArray = _convertUint8ListTo2DList(byteArray!, 240, 416);
    final epdBytes = _convertPixelsToEpdBytes(pixelArray);
    // final epdBytes = _convertImageArrayToEpdBytes(byteArray!);
    return epdBytes!;
  }

  Future<Uint8List> convertBitmapToByteData(String asset) async {
    // Image image = Image(image: AssetImage(asset, bundle: rootBundle));
    final imgBin = await rootBundle.load(asset);
    // final Uint8List byteArray = png!.buffer.asUint8List();
    final Uint8List byteArray = imgBin.buffer.asUint8List();
    final decodedImg = img.decodeImage(byteArray);
    // decodedImg!.remapChannels(img.ChannelOrder.rgba);
    final epdBytes = _convertImageArrayToEpdBytes(decodedImg!.buffer.asUint8List());
    return epdBytes;
  }

  Future<(Uint8List, Uint8List)> convertBitmapToByteDataBiColor(String asset) async {
    final imgBin = await rootBundle.load(asset);
    final Uint8List byteArray = imgBin.buffer.asUint8List();
    final decodedImg = img.decodeImage(byteArray);
    final epdBytes = getBiColor(decodedImg!.buffer.asUint8List());
    return epdBytes;
  }

  (Uint8List, Uint8List) getBiColor(Uint8List imgArray)
  {
    List<int> red = List.empty(growable: true);
    List<int> black = List.empty(growable: true);
    int j=0;
    int rbyte = 0xff;
    int bbyte = 0;
    for (int i=3; i<imgArray.length; i+=4) {
      double gray = (0.299*imgArray[i-3] 
                    + 0.587*imgArray[i-2] 
                    + 0.114*imgArray[i-1]);
      int excess_red = ((imgArray[i-3] * 2) - imgArray[i-2]) - imgArray[i-1];
      if (excess_red >= 128+64) { // red
        rbyte &= ~(0x80 >> j);
        // bbyte |= 0x80 >> j; // make this b-pixel white
      } else if (gray >= 128+64) { // black
        bbyte |= 0x80 >> j;
      }

      j++;
      if (j >= 8) {
        red.add(rbyte);
        black.add(bbyte);
        rbyte = 0xff;
        bbyte = 0;
        j = 0;
      }
    }
    return (Uint8List.fromList(red), Uint8List.fromList(black));
  }

  List<Uint8List> divideUint8List(Uint8List data, int chunkSize) {
    List<Uint8List> chunks = [];
    print(data);
    for (int i = 0; i < data.length; i += chunkSize) {
      int end = (i + chunkSize > data.length) ? data.length : i + chunkSize;
      Uint8List chunk = Uint8List.fromList([MagicEpd.epd_send, ...data.sublist(i, end)]);
      chunks.add(chunk);
    }
    return chunks;
  }
}
