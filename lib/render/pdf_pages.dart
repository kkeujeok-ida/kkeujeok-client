import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdfium_dart/pdfium_dart.dart';

import '../model/image_rules.dart';
import '../model/pdf_rules.dart';
import '../storage/asset_store.dart';
import '../sync/asset_sync.dart';

/// The page rectangle a PDF page is stretched to: the stored size is the truth
/// (spec `pdf.pageDisplay`), PDFium's page area is CropBox ∩ MediaBox with
/// /Rotate applied, which is the visible area of `pdf.pageMatrix`.
///
/// Pixels to render for [rect] (page pt, null = the whole page) at [scale]
/// px/pt: `(bitmap w, bitmap h, start x, start y, full w, full h)`.
({int bw, int bh, int sx, int sy, int fw, int fh}) pdfRenderSize(
  double pageW,
  double pageH,
  Rect? rect,
  double scale,
) {
  final fw = math.max(1, (pageW * scale).round());
  final fh = math.max(1, (pageH * scale).round());
  if (rect == null) return (bw: fw, bh: fh, sx: 0, sy: 0, fw: fw, fh: fh);
  return (
    bw: math.max(1, (rect.width * scale).round()),
    bh: math.max(1, (rect.height * scale).round()),
    sx: -(rect.left * scale).round(),
    sy: -(rect.top * scale).round(),
    fw: fw,
    fh: fh,
  );
}

/// BGRA pixels of one PDF page (or a region of it) on white, or null when
/// PDFium cannot open or render it. Runs in its own isolate; the document,
/// page and bitmap are closed before it returns.
Uint8List? renderPdfPage(
  String path,
  int index,
  ({int bw, int bh, int sx, int sy, int fw, int fh}) s,
) {
  final p = getPdfium();
  p.FPDF_InitLibrary();
  final np = path.toNativeUtf8();
  final doc = p.FPDF_LoadDocument(np.cast(), nullptr);
  calloc.free(np);
  if (doc == nullptr) return null;
  try {
    final page = p.FPDF_LoadPage(doc, index);
    if (page == nullptr) return null;
    try {
      final bmp = p.FPDFBitmap_Create(s.bw, s.bh, 1);
      if (bmp == nullptr) return null;
      try {
        p.FPDFBitmap_FillRect(bmp, 0, 0, s.bw, s.bh, 0xFFFFFFFF);
        p.FPDF_RenderPageBitmap(bmp, page, s.sx, s.sy, s.fw, s.fh, 0, 1);
        final stride = p.FPDFBitmap_GetStride(bmp);
        final src = p.FPDFBitmap_GetBuffer(bmp)
            .cast<Uint8>()
            .asTypedList(stride * s.bh);
        final row = s.bw * 4, out = Uint8List(row * s.bh);
        for (var y = 0; y < s.bh; y++) {
          out.setRange(y * row, (y + 1) * row, src, y * stride);
        }
        return out;
      } finally {
        p.FPDFBitmap_Destroy(bmp);
      }
    } finally {
      p.FPDF_ClosePage(page);
    }
  } finally {
    p.FPDF_CloseDocument(doc);
  }
}

class _Entry {
  _Entry(this.image, this.rect, this.scale)
    : bytes = image.width * image.height * 4;
  final ui.Image image;
  DateTime touched = DateTime.now();

  /// Region of the page in pt; null for the whole page.
  final Rect? rect;
  final double scale; // px per pt
  final int bytes;
}

class _Job {
  _Job(
    this.key,
    this.hash,
    this.index,
    this.pageW,
    this.pageH,
    this.rect,
    this.scale,
  ) : at = DateTime.now();
  final String key, hash;
  final int index;
  final double pageW, pageH, scale;
  final Rect? rect;
  DateTime at;
}

/// Renders PDF pages with PDFium, one render at a time (PDFium is not
/// thread safe), and keeps the results in a byte-bounded LRU. Every page has a
/// low-resolution whole-page image; a zoomed view adds one sharp tile of the
/// visible part, asked for only after the zoom has been still for a moment.
/// The PDF is opened by path in the render isolate, never read into memory
/// here.
class PdfPages extends ChangeNotifier {
  PdfPages(
    this.store,
    this.sync, {
    this.downloadingLabel = '',
    this.failedLabel = '',
  }) {
    sync.addListener(notifyListeners);
  }

  final AssetStore store;
  final AssetSync sync;

  String downloadingLabel, failedLabel;
  double devicePixelRatio = 2;

  static const baseSide = 768; // px, long side of the whole-page image
  static const tileSide = 3072; // px, long side cap of a sharp tile
  static const budget = 160 * 1024 * 1024; // bytes of bitmaps kept
  static const _staleAfter = Duration(seconds: 3);

  final _lru = <String, _Entry>{};
  final _queue = <String, _Job>{};
  final _timers = <String, Timer>{};
  final _inflight = <String>{};
  final _broken = <String>{};
  var _bytes = 0;
  var _running = false;
  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    sync.removeListener(notifyListeners);
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _queue.clear();
    for (final e in _lru.values) {
      e.image.dispose();
    }
    _lru.clear();
    super.dispose();
  }

  /// `pdf.pageDisplay` of [page] for this device: the layer, state and the
  /// invert flags a renderer must obey (never set for a PDF page).
  Map<String, Object?> display(Map<String, dynamic> page) {
    final d = pdfPageDisplay({
      'page': page,
      'local': sync.local.toList(),
      'failed': sync.failed.toList(),
      'theme': 'light',
    });
    final bg = page['background'];
    if (d['state'] == 'ready' && bg is Map && _broken.contains(bg['asset'])) {
      return {...d, 'state': AssetState.failed.name};
    }
    return d;
  }

  /// [다시 시도]: forgets a render failure and fetches again if need be.
  void retry(String hash) {
    _broken.remove(hash);
    sync.retry(hash, 'pdf');
    notifyListeners();
  }

  static String _key(Map bg) => '${bg['asset']}:${bg['page']}';

  _Entry? _touch(String key) {
    final e = _lru.remove(key);
    if (e != null) {
      _lru[key] = e..touched = DateTime.now();
    }
    return e;
  }

  /// The whole-page image of [bg], or null while it is being made.
  ui.Image? base(Map bg, double pageW, double pageH) {
    final key = _key(bg);
    final e = _touch(key);
    if (e != null) return e.image;
    final s = baseSide / math.max(pageW, pageH);
    _enqueue(
      _Job(key, '${bg['asset']}', bg['page'] as int, pageW, pageH, null, s),
    );
    return null;
  }

  /// The sharp tile of [bg] when it covers [visible] (page pt) well enough
  /// for [target] px/pt, else null (and, once the zoom is still, one is made).
  ({ui.Image image, Rect rect})? tile(
    Map bg,
    double pageW,
    double pageH,
    Rect visible,
    double target,
  ) {
    if (target <= baseSide / math.max(pageW, pageH) * 1.1) return null;
    final key = '${_key(bg)}:t';
    final e = _touch(key);
    if (e != null) {
      final r = e.rect!;
      final want = math.min(target, tileSide / math.max(r.width, r.height));
      if (r.inflate(0.5).contains(visible.topLeft) &&
          r.inflate(0.5).contains(visible.bottomRight) &&
          e.scale >= want * 0.9) {
        _timers.remove(key)?.cancel();
        return (image: e.image, rect: r);
      }
    }
    final area = visible
        .inflate(math.max(visible.width, visible.height) * 0.25)
        .intersect(Rect.fromLTWH(0, 0, pageW, pageH));
    final scale = math.min(
      target,
      tileSide / math.max(area.width, area.height),
    );
    final job = _Job(
      key,
      '${bg['asset']}',
      bg['page'] as int,
      pageW,
      pageH,
      area,
      scale,
    );
    _timers[key]?.cancel();
    _timers[key] = Timer(const Duration(milliseconds: 200), () {
      _timers.remove(key);
      _enqueue(job);
    });
    return e == null ? null : (image: e.image, rect: e.rect!);
  }

  void _enqueue(_Job job) {
    if (_disposed || _broken.contains(job.hash)) return;
    if (!sync.local.contains(job.hash) || _inflight.contains(job.key)) return;
    // Newest request last: what is on screen now is rendered first.
    _queue.remove(job.key);
    _queue[job.key] = job;
    if (!_running) unawaited(_pump());
  }

  Future<void> _pump() async {
    _running = true;
    try {
      while (!_disposed && _queue.isNotEmpty) {
        final job = _queue.remove(_queue.keys.last)!;
        _inflight.add(job.key);
        try {
          await _run(job);
        } finally {
          _inflight.remove(job.key);
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(_Job job) async {
    {
      {
        // A page that left the screen long ago is asked for again when it returns.
        if (DateTime.now().difference(job.at) > _staleAfter) return;
        final path = await store.pdfPath(job.hash);
        if (path == null) return;
        final size = pdfRenderSize(job.pageW, job.pageH, job.rect, job.scale);
        ui.Image? img;
        try {
          final px = await Isolate.run(
            () => renderPdfPage(path, job.index, size),
          );
          if (px != null && !_disposed) {
            img = await _decode(px, size.bw, size.bh);
          }
        } catch (_) {
          img = null;
        }
        if (_disposed) {
          img?.dispose();
          return;
        }
        if (img == null) {
          // Only a failed whole-page render says the PDF is unreadable; a
          // failed sharp tile is dropped and the base stays.
          if (job.rect == null) {
            _broken.add(job.hash);
            notifyListeners();
          }
          return;
        }
        _put(job.key, _Entry(img, job.rect, job.scale));
        notifyListeners();
      }
    }
  }

  Future<ui.Image> _decode(Uint8List px, int w, int h) async {
    final buf = await ui.ImmutableBuffer.fromUint8List(px);
    final desc = ui.ImageDescriptor.raw(
      buf,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.bgra8888,
    );
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    desc.dispose();
    buf.dispose();
    return frame.image;
  }

  void _put(String key, _Entry e) {
    final old = _lru.remove(key);
    if (old != null) {
      _bytes -= old.bytes;
      old.image.dispose();
    }
    _lru[key] = e;
    _bytes += e.bytes;
    // Off-screen pages go first; the newest entry stays.
    // Entries drawn in the last moments are on screen: they stay.
    final recent = DateTime.now().subtract(const Duration(milliseconds: 500));
    while (_bytes > budget && _lru.length > 1) {
      final k = _lru.keys.firstWhere(
        (k) => _lru[k]!.touched.isBefore(recent),
        orElse: () => '',
      );
      if (k.isEmpty) break;
      final v = _lru.remove(k)!;
      _bytes -= v.bytes;
      v.image.dispose();
    }
  }
}

final _grey = Paint()..color = const Color(0xFFE0E0E0);

/// Draws the PDF ground of [page] over the paper, in page coordinates, under
/// all elements: the sharp tile over the whole-page image, or the placeholder
/// of the page's state. [visible] is the part of the page on screen (page pt)
/// and [scale] the screen scale (px/pt before the device ratio), or null for a
/// thumbnail.
void paintPdfBackground(
  Canvas canvas,
  Map<String, dynamic> page,
  PdfPages pdf,
  Rect? visible,
  double scale,
) {
  final bg = page['background'] as Map;
  final w = (page['width'] as num).toDouble();
  final h = (page['height'] as num).toDouble();
  final d = pdf.display(page);
  final full = Rect.fromLTWH(0, 0, w, h);
  if (d['state'] != 'ready') {
    canvas.drawRect(full, _grey);
    final text = d['state'] == 'failed'
        ? pdf.failedLabel
        : pdf.downloadingLabel;
    if (text.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: math.max(12, w / 25),
            color: const Color(0xFF555555),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: math.max(1, w - 8));
      tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));
    }
    return;
  }
  // shortcut: invertPdf is always false (spec: a PDF page is never inverted);
  // Epic 10 reads the flag here if that ever changes.
  final paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = d['invertPdf'] == true
        ? const ColorFilter.matrix([
            -1,
            0,
            0,
            0,
            255,
            0,
            -1,
            0,
            0,
            255,
            0,
            0,
            -1,
            0,
            255,
            0,
            0,
            0,
            1,
            0,
          ])
        : null;
  void draw(ui.Image img, Rect dst) => canvas.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    dst,
    paint,
  );
  final base = pdf.base(bg, w, h);
  if (base != null) draw(base, full);
  if (visible != null && base != null) {
    final t = pdf.tile(bg, w, h, visible, scale * pdf.devicePixelRatio);
    if (t != null) draw(t.image, t.rect);
  }
}
