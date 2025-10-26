import 'dart:io';
import 'package:image/image.dart' as img;

class ImageProcessor {
  /// معالجة الصورة لتحسين دقة OCR
  static Future<File> processImageForOCR(String imagePath) async {
    // قراءة الصورة
    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      return File(imagePath);
    }

    // 1. تحويل الصورة إلى أبيض وأسود
    image = img.grayscale(image);

    // 2. زيادة التباين
    image = img.contrast(image, contrast: 150);

    // 3. تحسين الوضوح
    image = img.adjustColor(image, saturation: 0);

    // 4. تكبير الصورة لتحسين الدقة (إذا كانت صغيرة)
    if (image.width < 1000) {
      image = img.copyResize(
        image,
        width: image.width * 2,
        height: image.height * 2,
        interpolation: img.Interpolation.cubic,
      );
    }

    // حفظ الصورة المعالجة
    final processedPath = imagePath.replaceAll('.jpg', '_processed.jpg');
    final processedFile = File(processedPath);
    await processedFile.writeAsBytes(img.encodeJpg(image, quality: 100));

    return processedFile;
  }

  /// معالجة خفيفة للصورة
  static Future<File> lightProcessImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      return File(imagePath);
    }

    // تحسين بسيط للتباين
    image = img.contrast(image, contrast: 120);

    final processedPath = imagePath.replaceAll('.jpg', '_light_processed.jpg');
    final processedFile = File(processedPath);
    await processedFile.writeAsBytes(img.encodeJpg(image, quality: 100));

    return processedFile;
  }
}
