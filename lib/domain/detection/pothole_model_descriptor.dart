/// Fixed constants of the bundled pothole detection model (E5.4).
///
/// The asset is versioned unchanged; a test compares its size and SHA-256
/// with this descriptor so the model cannot be swapped silently.
final class PotholeModelDescriptor {
  const PotholeModelDescriptor._();

  static const String assetPath = 'assets/models/buraco.tflite';
  static const String sha256 =
      'f6a69aa9595d54006ca2ddb7b1ed316bdee1852b79c5f68651c1af5d96434463';
  static const int sizeInBytes = 10685246;
  static const String task = 'detect';

  /// Input tensor: batch 1, NCHW float32, 640×640.
  static const int inputSize = 640;

  static const int sourceClassIndex = 0;
  static const String sourceClassName = 'buraco';

  /// Defect class sent in the occurrence contract.
  static const String contractDefectClass = 'pothole';

  /// Maps a model class to the contract class, or `null` when the class is
  /// not the pothole class of this model.
  static String? contractClassFor({
    required int classIndex,
    required String className,
  }) {
    if (classIndex == sourceClassIndex && className == sourceClassName) {
      return contractDefectClass;
    }
    return null;
  }
}
