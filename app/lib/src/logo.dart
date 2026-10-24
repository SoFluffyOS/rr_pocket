import 'package:flutter/material.dart';

import 'theme.dart';

/// The R² mark: a white R with an amber superscript 2, as in the icon.
class RrLogo extends StatelessWidget {
  const RrLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 1.6,
      height: size * 1.6,
      decoration: BoxDecoration(
        color: RrColors.slate,
        borderRadius: BorderRadius.circular(size * 0.36),
        // Keeps the tile's edge visible on a dark background.
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white24)
            : null,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'R',
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1,
            ),
          ),
          Text(
            '2',
            style: TextStyle(
              fontSize: size * 0.46,
              fontWeight: FontWeight.w800,
              color: RrColors.amber,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
