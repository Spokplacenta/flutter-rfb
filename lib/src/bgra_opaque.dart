import 'dart:typed_data';

/// Le format négocié est du 24 bits dans un pixel 32 bits. L’octet de poids
/// fort n’est pas une transparence : beaucoup de serveurs (Istobal, RAW) le
/// laissent à 0. Flutter décode le BGRA en alpha prémultiplié, donc cet octet
/// à 0 lave l’image sur le fond clair.
void forceBgraOpaque(final Uint8List pixels) {
  for (int i = 3; i < pixels.length; i += 4) {
    pixels[i] = 0xFF;
  }
}
