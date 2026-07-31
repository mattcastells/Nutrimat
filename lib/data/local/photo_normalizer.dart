import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Deja toda foto en **JPEG opaco**, pase lo que pase.
///
/// `image_picker` comprime a JPEG solo cuando la imagen no tiene canal alfa; si
/// lo tiene la guarda en PNG y **descarta el `imageQuality`** —lo dice por log y
/// sigue de largo—. Desde la cámara no pasa nunca; desde la galería sí, porque
/// una captura de pantalla suele traer alfa.
///
/// El resultado es una foto de 1024×1024 sin comprimir: entre 1 y 3 MB en vez de
/// los ~200 kB de una normal, o sea entre 5 y 15 veces más, del lado del que
/// paga el almacenamiento. Y encima se subía con nombre `.jpg` y
/// `content-type: image/jpeg`, así que los bytes y lo que decían ser no
/// coincidían: se ve bien porque todo el mundo olfatea el contenido, pero es una
/// mentira esperando a que algo la crea.
///
/// **Se compone sobre blanco, no se descarta el alfa a secas.** Un JPEG no tiene
/// transparencia: tirar el canal deja los píxeles transparentes con el color que
/// tengan debajo, que en un PNG suele ser negro. Una captura con fondo
/// transparente terminaría con manchones negros.
abstract final class PhotoNormalizer {
  /// La firma de un PNG: `\x89PNG`. Se mira el contenido y no la extensión
  /// porque el archivo que devuelve `image_picker` conserva el nombre original,
  /// que puede decir cualquier cosa.
  static const List<int> _pngSignature = <int>[0x89, 0x50, 0x4E, 0x47];

  /// La misma calidad que se le pide a `image_picker`: acá se llega justamente
  /// porque ese pedido se ignoró.
  static const int jpegQuality = 80;

  static bool isPng(List<int> bytes) {
    if (bytes.length < _pngSignature.length) return false;
    for (var i = 0; i < _pngSignature.length; i++) {
      if (bytes[i] != _pngSignature[i]) return false;
    }
    return true;
  }

  /// Devuelve la ruta de la foto lista para subir.
  ///
  /// Si ya es JPEG —el 99 % de las veces— devuelve la misma ruta sin tocar nada:
  /// no se re-codifica lo que ya está bien, porque cada vuelta de JPEG pierde
  /// calidad. Si algo falla también devuelve la original: subir una foto pesada
  /// es un problema de plata, no poder registrar la comida es un problema de la
  /// persona.
  static Future<String> toJpeg(String path) async {
    final File file;
    final Uint8List bytes;
    try {
      file = File(path);
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return path;
    }

    if (!isPng(bytes)) return path;

    // Decodificar y volver a codificar un PNG de 1024² son unos cientos de
    // milisegundos: en el hilo de la interfaz eso es un tirón visible justo
    // después de elegir la foto.
    final Uint8List? jpeg;
    try {
      jpeg = await compute(_flattenToJpeg, bytes);
    } on Object {
      return path;
    }
    if (jpeg == null) return path;

    try {
      final target = File('$path.nm.jpg');
      await target.writeAsBytes(jpeg, flush: true);
      return target.path;
    } on FileSystemException {
      return path;
    }
  }
}

/// Corre en otro isolate ([compute]), así que tiene que ser de nivel superior.
Uint8List? _flattenToJpeg(Uint8List bytes) {
  final decoded = img.decodePng(bytes);
  if (decoded == null) return null;

  final flat = img.Image(width: decoded.width, height: decoded.height)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, decoded);

  return img.encodeJpg(flat, quality: PhotoNormalizer.jpegQuality);
}
