import 'package:qr/qr.dart';

/// [data] as QR modules, true for dark, with the 4-module quiet zone.
List<List<bool>> qrModules(String data) {
  final image = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  const quiet = 4;
  final size = image.moduleCount + 2 * quiet;
  return [
    for (var row = 0; row < size; row++)
      [
        for (var col = 0; col < size; col++)
          row >= quiet &&
              col >= quiet &&
              row < size - quiet &&
              col < size - quiet &&
              image.isDark(row - quiet, col - quiet),
      ],
  ];
}

/// [data] as a QR code for a terminal, two rows per line in half blocks.
/// With [ansi], it is drawn black on white whatever the terminal's colours,
/// as scanners expect; without, dark modules are the block characters.
String qrTerminal(String data, {required bool ansi}) {
  final modules = qrModules(data);
  final lines = <String>[];
  for (var row = 0; row < modules.length; row += 2) {
    final line = StringBuffer();
    if (ansi) line.write('\x1B[30;47m');
    for (var col = 0; col < modules.length; col++) {
      final top = modules[row][col];
      final bottom = row + 1 < modules.length && modules[row + 1][col];
      line.write(switch ((top, bottom)) {
        (true, true) => '█',
        (true, false) => '▀',
        (false, true) => '▄',
        (false, false) => ' ',
      });
    }
    if (ansi) line.write('\x1B[0m');
    lines.add('$line');
  }
  return lines.join('\n');
}

/// [data] as an SVG QR code, black on white, [pixels] wide.
String qrSvg(String data, {int pixels = 320}) {
  final modules = qrModules(data);
  final size = modules.length;
  final path = StringBuffer();
  for (var row = 0; row < size; row++) {
    for (var col = 0; col < size; col++) {
      if (modules[row][col]) path.write('M$col ${row}h1v1h-1z');
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" width="$pixels" '
      'height="$pixels" viewBox="0 0 $size $size" shape-rendering="crispEdges">'
      '<rect width="$size" height="$size" fill="#fff"/>'
      '<path d="$path" fill="#000"/></svg>';
}
