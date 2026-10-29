/// A palette cell: the `#rrggbb` it stores and the key of its ko/en name.
class PaletteColor {
  const PaletteColor(this.hex, this.nameKey);

  final String hex;
  final String nameKey;
}

/// Spec `pen.palette`, grid order: 6 columns by 2 rows.
const penPalette = <PaletteColor>[
  PaletteColor('#000000', 'black'),
  PaletteColor('#2f9e44', 'green'),
  PaletteColor('#1971c2', 'blue'),
  PaletteColor('#e03131', 'red'),
  PaletteColor('#f59f00', 'yellow'),
  PaletteColor('#495057', 'darkGray'),
  PaletteColor('#f76707', 'orange'),
  PaletteColor('#0c8599', 'teal'),
  PaletteColor('#3b5bdb', 'indigo'),
  PaletteColor('#9c36b5', 'purple'),
  PaletteColor('#d6336c', 'pink'),
  PaletteColor('#7f5539', 'brown'),
];

/// Spec `pen.palette`, highlighter: 6 columns by 1 row.
const highlighterPalette = <PaletteColor>[
  PaletteColor('#ffe066', 'yellow'),
  PaletteColor('#8ce99a', 'green'),
  PaletteColor('#74c0fc', 'sky'),
  PaletteColor('#faa2c1', 'pink'),
  PaletteColor('#ffc078', 'orange'),
  PaletteColor('#d0bfff', 'lavender'),
];

List<PaletteColor> paletteFor(String tool) =>
    tool == 'highlighter' ? highlighterPalette : penPalette;
