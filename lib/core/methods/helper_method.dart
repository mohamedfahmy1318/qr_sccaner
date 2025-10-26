// لازم تكون top-level function علشان تشتغل مع compute
/*import 'dart:io';
import 'package:image/image.dart' as img;

class PreprocessResult {
  final String path;
  PreprocessResult(this.path);
}

// data object for compute
class CropAndEnhanceParams {
  final String inputPath;
  final int cropHeight; // pixels from bottom
  final String outPath;
  CropAndEnhanceParams(this.inputPath, this.cropHeight, this.outPath);
}

Future<String> saveUint8ListToFile(List<int> bytes, String outPath) async {
  final file = File(outPath);
  await file.writeAsBytes(bytes);
  return file.path;
}

PreprocessResult cropAndEnhance(CropAndEnhanceParams params) {
  final bytes = File(params.inputPath).readAsBytesSync();
  img.Image? image = img.decodeImage(bytes);
  if (image == null) throw Exception('Failed to decode image');

  // crop bottom area
  final cropH = params.cropHeight.clamp(50, image.height);
  final cropY = (image.height - cropH).clamp(0, image.height - 1);
  final cropped = img.copyCrop(image, x: 0, y: cropY, width: image.width, height: cropH);

  // enhance: increase contrast & sharpen a bit
  img.adjustColor(cropped, contrast: 1.2, saturation: 1.0, brightness: 0.0);
  // Use convolution for sharpening instead of deprecated sharpen function
  final sharpened = img.convolution(cropped, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);

  final outBytes = img.encodeJpg(sharpened, quality: 90);
  final outPath = params.outPath;
  File(outPath).writeAsBytesSync(outBytes);
  return PreprocessResult(outPath);
}
*/
