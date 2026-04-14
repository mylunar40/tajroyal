import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/sidebar.dart';

import '../services/data_service.dart';
import '../services/browser_file_download.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class Receipt extends StatefulWidget {
  const Receipt({super.key, this.initialHistoryIndex});

  final int? initialHistoryIndex;

  @override
  State<Receipt> createState() => _ReceiptState();
}

enum PdfOutputMode { fastest, exact, smart }

class _ReceiptState extends State<Receipt> {
  // Force exact mode for pixel-perfect PDF output.
  static const PdfOutputMode _pdfMode = PdfOutputMode.exact;
  static final PdfPageFormat _receiptPageFormat = PdfPageFormat(
    17 * PdfPageFormat.cm,
    14 * PdfPageFormat.cm,
  );

  final GlobalKey _receiptBoundaryKey = GlobalKey();
  Uint8List? _cachedPdfBytes;
  String _cachedPdfKey = '';
  bool _isProcessing = false;
  bool _isWarmingUp = false;
  Timer? _warmupDebounce;
  static const Duration _warmupDebounceDelay = Duration(milliseconds: 1200);
  static const Duration _warmupRetryDelay = Duration(milliseconds: 700);
  final TransformationController _zoomController = TransformationController();
  double _zoomScale = 1.0;
  static const double _minZoom = 0.55;
  static const double _maxZoom = 2.2;
  static const double _zoomStep = 0.15;
  static const double _receiptCardWidth = 640;
  static const double _receiptCardHeight = 490;
  final GlobalKey _viewerAreaKey = GlobalKey();
  Size _lastViewerSize = Size.zero;
  double _inputFontSize = 10;
  bool _isInputBold = false;
  bool _isInputItalic = false;
  bool _isInputUnderline = false;
  String _inputFontStyle = 'Roboto';
  // Approx 4mm spacing in logical pixels for on-screen layout.
  static const double _twoMmGap = 11.4;

  static const List<String> _fontStyleOptions = <String>[
    'Roboto',
    'Poppins',
    'Lato',
    'Merriweather',
  ];

  TextStyle _arabicHeaderStyle({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    return GoogleFonts.notoNaskhArabic(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: const Color(0xFF0D47A1),
      height: 1.05,
    );
  }

  TextStyle _receiptInputTextStyle({Color color = const Color(0xFF0D47A1)}) {
    final effectiveWeight = _isInputBold ? FontWeight.w700 : FontWeight.w500;
    final effectiveStyle = _isInputItalic ? FontStyle.italic : FontStyle.normal;
    final effectiveDecoration =
        _isInputUnderline ? TextDecoration.underline : TextDecoration.none;

    switch (_inputFontStyle) {
      case 'Poppins':
        return GoogleFonts.poppins(
          fontSize: _inputFontSize,
          fontWeight: effectiveWeight,
          fontStyle: effectiveStyle,
          decoration: effectiveDecoration,
          color: color,
        );
      case 'Lato':
        return GoogleFonts.lato(
          fontSize: _inputFontSize,
          fontWeight: effectiveWeight,
          fontStyle: effectiveStyle,
          decoration: effectiveDecoration,
          color: color,
        );
      case 'Merriweather':
        return GoogleFonts.merriweather(
          fontSize: _inputFontSize,
          fontWeight: effectiveWeight,
          fontStyle: effectiveStyle,
          decoration: effectiveDecoration,
          color: color,
        );
      case 'Roboto':
      default:
        return GoogleFonts.roboto(
          fontSize: _inputFontSize,
          fontWeight: effectiveWeight,
          fontStyle: effectiveStyle,
          decoration: effectiveDecoration,
          color: color,
        );
    }
  }

  // --- Amount to English words helpers ---
  String _intToWords(int n) {
    if (n == 0) return 'Zero';
    const ones = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    const tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];
    String words = '';
    if (n >= 1000000) {
      words += '${_intToWords(n ~/ 1000000)} Million ';
      n %= 1000000;
    }
    if (n >= 1000) {
      words += '${_intToWords(n ~/ 1000)} Thousand ';
      n %= 1000;
    }
    if (n >= 100) {
      words += '${ones[n ~/ 100]} Hundred ';
      n %= 100;
      if (n > 0) words += 'and ';
    }
    if (n >= 20) {
      words += '${tens[n ~/ 10]} ';
      n %= 10;
    }
    if (n > 0) words += '${ones[n]} ';
    return words.trim();
  }

  String _amountToWords(String kdStr, String filsStr) {
    final kd = int.tryParse(kdStr.trim()) ?? 0;
    final fils = int.tryParse(filsStr.trim()) ?? 0;
    if (kd == 0 && fils == 0) return '';
    String result = '';
    if (kd > 0) {
      result = '${_intToWords(kd)} Kuwaiti Dinar${kd == 1 ? '' : 's'}';
    }
    if (fils > 0) {
      if (result.isNotEmpty) result += ' and ';
      result += '${_intToWords(fils)} Fils';
    }
    return '$result Only';
  }

  void _onAmountChanged() {
    final words = _amountToWords(_kdController.text, _filsController.text);
    if (_sumController.text != words) {
      _sumController.removeListener(_onFormChanged);
      _sumController.text = words;
      _sumController.addListener(_onFormChanged);
      _invalidatePdfCache();
      _schedulePdfWarmup();
    }
  }

  // --- Form field controllers ---
  final _receivedFromController = TextEditingController();
  final _mobileController = TextEditingController();
  final _sumController = TextEditingController();
  final _bankController = TextEditingController();
  final _chequeController = TextEditingController();
  final _beingForController = TextEditingController();
  final _kdController = TextEditingController();
  final _filsController = TextEditingController();
  final _noController = TextEditingController();
  final _historySearchController = TextEditingController();
  int? _editingReceiptIndex;

  final TextEditingController _dateController = TextEditingController(
    text:
        "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
  );

  @override
  void initState() {
    super.initState();
    _attachFieldListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setZoom(1.0);
      _schedulePdfWarmup();

      final initialIndex = widget.initialHistoryIndex;
      if (initialIndex != null &&
          initialIndex >= 0 &&
          initialIndex < DataService.receipts.length) {
        _loadReceiptFromHistory(
          DataService.receipts[initialIndex],
          index: initialIndex,
        );
      }
    });
  }

  void _attachFieldListeners() {
    final controllers = [
      _receivedFromController,
      _mobileController,
      _sumController,
      _bankController,
      _chequeController,
      _beingForController,
      _kdController,
      _filsController,
      _noController,
      _dateController,
    ];
    for (final controller in controllers) {
      controller.addListener(_onFormChanged);
    }
    _kdController.addListener(_onAmountChanged);
    _filsController.addListener(_onAmountChanged);
  }

  void _detachFieldListeners() {
    final controllers = [
      _receivedFromController,
      _mobileController,
      _sumController,
      _bankController,
      _chequeController,
      _beingForController,
      _kdController,
      _filsController,
      _noController,
      _dateController,
    ];
    for (final controller in controllers) {
      controller.removeListener(_onFormChanged);
    }
    _kdController.removeListener(_onAmountChanged);
    _filsController.removeListener(_onAmountChanged);
  }

  void _onFormChanged() {
    _invalidatePdfCache();
    _schedulePdfWarmup();
  }

  void _invalidatePdfCache() {
    _cachedPdfBytes = null;
    _cachedPdfKey = '';
  }

  void _schedulePdfWarmup() {
    if (kIsWeb) {
      // Keep web typing/rendering smooth; generate PDF only on explicit actions.
      return;
    }

    _warmupDebounce?.cancel();
    _warmupDebounce = Timer(_warmupDebounceDelay, () {
      // Do not run heavy image/PDF warmup while user is actively typing.
      if (_isEditingTextField()) {
        _warmupDebounce = Timer(_warmupRetryDelay, () {
          if (!_isEditingTextField()) {
            _warmupPdfCache();
          }
        });
        return;
      }
      _warmupPdfCache();
    });
  }

  bool _isEditingTextField() {
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    return focusedWidget is EditableText;
  }

  bool _isPdfReadyForCurrentData() {
    return _cachedPdfBytes != null && _cachedPdfKey == _currentPdfDataKey();
  }

  Future<void> _warmupPdfCache() async {
    if (_isWarmingUp) return;
    if (mounted) {
      setState(() {
        _isWarmingUp = true;
      });
    } else {
      _isWarmingUp = true;
    }

    try {
      final currentKey = _currentPdfDataKey();
      if (_cachedPdfBytes != null && _cachedPdfKey == currentKey) {
        return;
      }

      final pdf = await buildPdf();
      final bytes = await pdf.save();

      _cachedPdfBytes = bytes;
      _cachedPdfKey = currentKey;
    } catch (_) {
      // Keep UI responsive; fallback happens in _getPdfBytes if needed.
    } finally {
      if (mounted) {
        setState(() {
          _isWarmingUp = false;
        });
      } else {
        _isWarmingUp = false;
      }
    }
  }

  Future<void> _runButtonAction(
    String actionName,
    Future<void> Function() action,
  ) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await action().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$actionName is taking too long. Try again.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  String _currentPdfDataKey() {
    return [
      _receivedFromController.text,
      _mobileController.text,
      _sumController.text,
      _bankController.text,
      _chequeController.text,
      _beingForController.text,
      _kdController.text,
      _filsController.text,
      _noController.text,
      _dateController.text,
    ].join('|');
  }

  Future<Uint8List> _captureReceiptAsPng() async {
    await Future.delayed(const Duration(milliseconds: 300));
    await WidgetsBinding.instance.endOfFrame;

    final boundary = _receiptBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;

    if (boundary == null) {
      throw Exception("Boundary not found");
    }

    final image = await boundary.toImage(pixelRatio: 3.0);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception("Image capture failed");
    }

    debugPrint("IMAGE CAPTURE SUCCESS");

    return byteData.buffer.asUint8List();
  }

  Future<pw.Document> buildPdf() async {
    if (_pdfMode == PdfOutputMode.fastest) {
      return _buildPdfFromFields();
    }

    if (_pdfMode == PdfOutputMode.exact) {
      final pngBytes = await _captureReceiptAsPng().timeout(
        const Duration(seconds: 2),
      );
      return _buildPdfFromImage(pngBytes);
    }

    // Smart mode
    try {
      final pngBytes = await _captureReceiptAsPng().timeout(
        const Duration(seconds: 2),
      );
      return _buildPdfFromImage(pngBytes);
    } catch (_) {
      return _buildPdfFromFields();
    }
  }

  Future<Uint8List> _getPdfBytes() async {
    final pngBytes = await _captureReceiptAsPng();
    final pdf = _buildPdfFromImage(pngBytes);
    return await pdf.save();
  }

  Future<Uint8List> _buildDirectPdfBytes() async {
    return _getPdfBytes();
  }

  pw.Document _buildPdfFromImage(Uint8List pngBytes) {
    final pdf = pw.Document();
    final receiptImage = pw.MemoryImage(pngBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: _receiptPageFormat,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Image(receiptImage, fit: pw.BoxFit.contain),
          );
        },
      ),
    );

    return pdf;
  }

  pw.Document _buildPdfFromFields() {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: _receiptPageFormat,
        margin: const pw.EdgeInsets.all(16),
        build: (context) => pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.blue900, width: 2),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Taj Royal Glass Co.',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'for Glass & Mirrors Production',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Receipt Voucher',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'سـند قـبـض',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'K.D: ${_kdController.text}    Fils: ${_filsController.text}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Text(
                    'Date: ${_dateController.text}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Text(
                    'No: ${_noController.text}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(color: PdfColors.blue900, thickness: 1.5),
              pw.SizedBox(height: 8),
              pw.Text(
                'Received from Mr./Messrs: ${_receivedFromController.text}',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Mobile No: ${_mobileController.text}',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'The sum of K.D.: ${_sumController.text}',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'On Bank: ${_bankController.text}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Text(
                      'Cash/Cheque No: ${_chequeController.text}',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Being For: ${_beingForController.text}',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('__________________________'),
                      pw.Text(
                        "Receiver's Name / اسم المستلم",
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('__________________________'),
                      pw.Text(
                        'Signature / التوقيع',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Divider(color: PdfColors.blue900, thickness: 1.2),
              pw.SizedBox(height: 6),
              pw.Text(
                'Al Rai Block 1 - St. 26 - Shop 11/13',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Tel: 56540521 / 96952550    Instagram: stainless_steelvip',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );

    return pdf;
  }

  @override
  void dispose() {
    _warmupDebounce?.cancel();
    _detachFieldListeners();
    _receivedFromController.dispose();
    _mobileController.dispose();
    _sumController.dispose();
    _bankController.dispose();
    _chequeController.dispose();
    _beingForController.dispose();
    _kdController.dispose();
    _filsController.dispose();
    _noController.dispose();
    _dateController.dispose();
    _historySearchController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  void _setZoom(double nextScale) {
    final clamped = nextScale.clamp(_minZoom, _maxZoom).toDouble();
    final renderObject = _viewerAreaKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final viewerSize = renderObject.size;
      final dx = (viewerSize.width - (_receiptCardWidth * clamped)) / 2;
      final dy = (viewerSize.height - (_receiptCardHeight * clamped)) / 2;
      _zoomController.value = Matrix4.identity()
        ..translate(dx, dy)
        ..scaleByDouble(clamped, clamped, 1, 1);
    } else {
      _zoomController.value = Matrix4.identity()
        ..scaleByDouble(clamped, clamped, 1, 1);
    }
    if (mounted) {
      setState(() {
        _zoomScale = clamped;
      });
    } else {
      _zoomScale = clamped;
    }
  }

  void _zoomIn() {
    _setZoom(_zoomScale + _zoomStep);
  }

  void _zoomOut() {
    _setZoom(_zoomScale - _zoomStep);
  }

  void _resetZoom() {
    _setZoom(1.0);
  }

  Future<void> _printReceipt() async {
    try {
      final bytes = await _getPdfBytes();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  Future<void> _savePdf() async {
    try {
      final bytes = await _getPdfBytes();
      final name = 'receipt_${_dateController.text.replaceAll('/', '-')}.pdf';

      if (kIsWeb) {
        _saveReceiptHistory();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Saved successfully')));
        }
        return;
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('PDF saved: ${file.path}')));
        }
      }

      _saveReceiptHistory();
      if (mounted) {
        setState(() {
          _editingReceiptIndex = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _downloadPdf() async {
    try {
      // Capture receipt widget as high-res PNG image
      final boundary = _receiptBoundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final base64Image = base64Encode(pngBytes);

      // Send to Firebase Cloud Function and get PDF back
      const functionUrl =
          'https://us-central1-taj-royal-c25cb.cloudfunctions.net/generateReceiptPdf';
      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      );

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      final pdfBytes = response.bodyBytes;
      final dateStr = _dateController.text.replaceAll('/', '-');
      final name = 'receipt$dateStr.pdf';

      if (kIsWeb) {
        await downloadPdfBytes(pdfBytes, name);
        return;
      }

      final downloadDir = await getDownloadsDirectory();
      final fallbackDir = await getApplicationDocumentsDirectory();
      final targetDir = downloadDir ?? fallbackDir;
      final file = File('${targetDir.path}/$name');
      await file.writeAsBytes(pdfBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF saved: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  Future<void> _sharePdf() async {
    try {
      final bytes = await _getPdfBytes();
      final name = 'receipt_${_dateController.text.replaceAll('/', '-')}.pdf';

      if (kIsWeb) {
        await sharePdfWeb(bytes);
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Receipt from Taj Royal Glass',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
      }
    }
  }

  String _formattedReceiptAmount() {
    final kd =
        _kdController.text.trim().isEmpty ? '0' : _kdController.text.trim();
    final filsRaw = _filsController.text.trim();
    final fils = filsRaw.isEmpty ? '000' : filsRaw.padLeft(3, '0');
    return 'KD $kd.$fils';
  }

  void _saveReceiptHistory() {
    final entry = <String, dynamic>{
      'name': _receivedFromController.text.trim(),
      'mobile': _mobileController.text.trim(),
      'amount': _formattedReceiptAmount(),
      'date': _dateController.text.trim(),
      'sum': _sumController.text.trim(),
      'bank': _bankController.text.trim(),
      'cheque': _chequeController.text.trim(),
      'beingFor': _beingForController.text.trim(),
      'kd': _kdController.text.trim(),
      'fils': _filsController.text.trim(),
      'no': _noController.text.trim(),
    };

    final editingIndex = _editingReceiptIndex;
    if (editingIndex != null &&
        editingIndex >= 0 &&
        editingIndex < DataService.receipts.length) {
      DataService.receipts[editingIndex] = entry;
      return;
    }

    DataService.receipts.add(entry);
  }

  List<Map<String, dynamic>> _filteredReceipts() {
    final query = _historySearchController.text.trim().toLowerCase();
    final source = DataService.receipts.reversed.toList();

    if (query.isEmpty) {
      return source;
    }

    return source.where((receipt) {
      final name = (receipt['name'] ?? '').toString().toLowerCase();
      final mobile = (receipt['mobile'] ?? '').toString().toLowerCase();
      final amount = (receipt['amount'] ?? '').toString().toLowerCase();
      final date = (receipt['date'] ?? '').toString().toLowerCase();
      return name.contains(query) ||
          mobile.contains(query) ||
          amount.contains(query) ||
          date.contains(query);
    }).toList();
  }

  void _loadReceiptFromHistory(Map<String, dynamic> receipt, {int? index}) {
    setState(() {
      _editingReceiptIndex = index;
      _receivedFromController.text = (receipt['name'] ?? '').toString();
      _mobileController.text = (receipt['mobile'] ?? '').toString();
      _sumController.text = (receipt['sum'] ?? '').toString();
      _bankController.text = (receipt['bank'] ?? '').toString();
      _chequeController.text = (receipt['cheque'] ?? '').toString();
      _beingForController.text = (receipt['beingFor'] ?? '').toString();
      _kdController.text = (receipt['kd'] ?? '').toString();
      _filsController.text = (receipt['fils'] ?? '').toString();
      _noController.text = (receipt['no'] ?? '').toString();
      _dateController.text = (receipt['date'] ?? '').toString();
    });
  }

  void _startNewReceipt() {
    setState(() {
      _editingReceiptIndex = null;
      _receivedFromController.clear();
      _mobileController.clear();
      _sumController.clear();
      _bankController.clear();
      _chequeController.clear();
      _beingForController.clear();
      _kdController.clear();
      _filsController.clear();
      _noController.clear();
      final now = DateTime.now();
      _dateController.text = '${now.day}/${now.month}/${now.year}';
    });
  }

  Future<void> _deleteReceiptFromHistory(int sourceIndex) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Receipt'),
            content: const Text(
              'Are you sure you want to delete this receipt?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    setState(() {
      DataService.receipts.removeAt(sourceIndex);
      if (_editingReceiptIndex == sourceIndex) {
        _editingReceiptIndex = null;
      } else if (_editingReceiptIndex != null &&
          _editingReceiptIndex! > sourceIndex) {
        _editingReceiptIndex = _editingReceiptIndex! - 1;
      }
    });
  }

  Widget _buildHistoryPanel({double width = 300, bool compact = false}) {
    final receipts = _filteredReceipts();

    return Container(
      width: width,
      color: Colors.white,
      padding: EdgeInsets.all(compact ? 10 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Receipt History',
            style: TextStyle(
              fontSize: compact ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0D47A1),
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          if (_editingReceiptIndex != null)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: compact ? 8 : 10),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 6 : 8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF0D47A1).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Edit mode is active',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _startNewReceipt,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _historySearchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search by name/mobile/date',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: compact ? 10 : 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SizedBox(width: compact ? 6 : 8),
              _buildTypographyRibbon(compact: compact),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          Expanded(
            child: receipts.isEmpty
                ? const Center(
                    child: Text(
                      'No receipts found',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : ListView.separated(
                    itemCount: receipts.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: compact ? 6 : 8),
                    itemBuilder: (context, index) {
                      final receipt = receipts[index];
                      final sourceIndex = DataService.receipts.indexOf(receipt);

                      return InkWell(
                        onTap: sourceIndex >= 0
                            ? () => _loadReceiptFromHistory(
                                  receipt,
                                  index: sourceIndex,
                                )
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: EdgeInsets.all(compact ? 8 : 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F8FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF0D47A1)
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (receipt['name'] ?? '').toString().isEmpty
                                    ? 'Unnamed Receipt'
                                    : (receipt['name'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: compact ? 13 : 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0D47A1),
                                ),
                              ),
                              SizedBox(height: compact ? 3 : 4),
                              Text(
                                'Mobile: ${(receipt['mobile'] ?? '-').toString()}',
                                style: TextStyle(fontSize: compact ? 12 : 13),
                              ),
                              Text(
                                'Amount: ${(receipt['amount'] ?? '-').toString()}',
                                style: TextStyle(fontSize: compact ? 12 : 13),
                              ),
                              Text(
                                'Date: ${(receipt['date'] ?? '-').toString()}',
                                style: TextStyle(fontSize: compact ? 12 : 13),
                              ),
                              SizedBox(height: compact ? 4 : 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: sourceIndex >= 0
                                        ? () => _loadReceiptFromHistory(
                                              receipt,
                                              index: sourceIndex,
                                            )
                                        : null,
                                    style: TextButton.styleFrom(
                                      visualDensity: compact
                                          ? const VisualDensity(
                                              horizontal: -2,
                                              vertical: -2,
                                            )
                                          : VisualDensity.standard,
                                      padding: compact
                                          ? const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 4,
                                            )
                                          : null,
                                    ),
                                    icon: const Icon(Icons.edit, size: 15),
                                    label: const Text('Edit'),
                                  ),
                                  SizedBox(width: compact ? 2 : 4),
                                  TextButton.icon(
                                    onPressed: sourceIndex >= 0
                                        ? () => _deleteReceiptFromHistory(
                                              sourceIndex,
                                            )
                                        : null,
                                    style: TextButton.styleFrom(
                                      visualDensity: compact
                                          ? const VisualDensity(
                                              horizontal: -2,
                                              vertical: -2,
                                            )
                                          : VisualDensity.standard,
                                      padding: compact
                                          ? const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 4,
                                            )
                                          : null,
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 15,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: PrimaryScrollController(
                      controller: scrollController,
                      child: _buildHistoryPanel(
                        width: double.infinity,
                        compact: true,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTypographyRibbon({bool compact = false}) {
    final buttonPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 7, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 7);

    return Container(
      width: compact ? 50 : 58,
      padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(9),
        border:
            Border.all(color: const Color(0xFF0D47A1).withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ribbonControlButton(
            icon: Icons.remove,
            tooltip: 'Font size down',
            padding: buttonPadding,
            onTap: () {
              setState(() {
                _inputFontSize = (_inputFontSize - 1).clamp(8, 24).toDouble();
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _inputFontSize.toStringAsFixed(0),
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0D47A1),
              ),
            ),
          ),
          _ribbonControlButton(
            icon: Icons.add,
            tooltip: 'Font size up',
            padding: buttonPadding,
            onTap: () {
              setState(() {
                _inputFontSize = (_inputFontSize + 1).clamp(8, 24).toDouble();
              });
            },
          ),
          const SizedBox(height: 6),
          _ribbonControlButton(
            icon: Icons.format_bold,
            tooltip: _isInputBold ? 'Set normal' : 'Set bold',
            isActive: _isInputBold,
            padding: buttonPadding,
            onTap: () {
              setState(() {
                _isInputBold = !_isInputBold;
              });
            },
          ),
          const SizedBox(height: 4),
          _ribbonControlButton(
            icon: Icons.format_italic,
            tooltip: _isInputItalic ? 'Set normal' : 'Set italic',
            isActive: _isInputItalic,
            padding: buttonPadding,
            onTap: () {
              setState(() {
                _isInputItalic = !_isInputItalic;
              });
            },
          ),
          const SizedBox(height: 4),
          _ribbonControlButton(
            icon: Icons.format_underline,
            tooltip: _isInputUnderline ? 'Remove underline' : 'Underline text',
            isActive: _isInputUnderline,
            padding: buttonPadding,
            onTap: () {
              setState(() {
                _isInputUnderline = !_isInputUnderline;
              });
            },
          ),
          const SizedBox(height: 4),
          PopupMenuButton<String>(
            tooltip: 'Font style',
            initialValue: _inputFontStyle,
            icon: const Icon(Icons.text_fields, size: 18),
            onSelected: (value) {
              setState(() {
                _inputFontStyle = value;
              });
            },
            itemBuilder: (context) => _fontStyleOptions
                .map(
                  (font) =>
                      PopupMenuItem<String>(value: font, child: Text(font)),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          _ribbonControlButton(
            icon: Icons.refresh,
            tooltip: 'Reset text style',
            padding: buttonPadding,
            onTap: () {
              setState(() {
                _inputFontSize = 10;
                _isInputBold = false;
                _isInputItalic = false;
                _isInputUnderline = false;
                _inputFontStyle = 'Roboto';
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _ribbonControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    required EdgeInsets padding,
    bool isActive = false,
  }) {
    final activeColor = const Color(0xFF0D47A1);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: activeColor.withValues(alpha: 0.28)),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? Colors.white : activeColor,
          ),
        ),
      ),
    );
  }

  Widget _buildZoomToolbar() {
    final canZoomOut = _zoomScale > _minZoom + 0.001;
    final canZoomIn = _zoomScale < _maxZoom - 0.001;

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFF0D47A1).withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: canZoomOut ? _zoomOut : null,
            tooltip: 'Zoom out',
            icon: const Icon(Icons.remove, color: Color(0xFF0D47A1)),
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${(_zoomScale * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF0D47A1),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            onPressed: canZoomIn ? _zoomIn : null,
            tooltip: 'Zoom in',
            icon: const Icon(Icons.add, color: Color(0xFF0D47A1)),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _resetZoom,
            tooltip: 'Reset zoom',
            icon: const Icon(Icons.refresh, color: Color(0xFF0D47A1)),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              onPressed: _openHistorySheet,
              icon: const Icon(Icons.history),
              label: const Text('History'),
            )
          : null,
      body: Row(
        children: [
          if (!isMobile) const Sidebar(currentIndex: 2),
          if (!isMobile) _buildHistoryPanel(width: 320),
          Expanded(
            child: Container(
              color: Colors.grey[300],
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- ZOOM FUNCTIONALITY --

                    _buildZoomToolbar(),

                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final nextViewerSize = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          if ((nextViewerSize.width - _lastViewerSize.width)
                                      .abs() >
                                  0.5 ||
                              (nextViewerSize.height - _lastViewerSize.height)
                                      .abs() >
                                  0.5) {
                            _lastViewerSize = nextViewerSize;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _setZoom(_zoomScale);
                              }
                            });
                          }

                          return Center(
                            child: SizedBox(
                              key: _viewerAreaKey,
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: InteractiveViewer(
                                transformationController: _zoomController,
                                alignment: Alignment.center,
                                minScale: _minZoom,
                                maxScale: _maxZoom,
                                panEnabled: true,
                                scaleEnabled: true,
                                trackpadScrollCausesScale: true,
                                constrained: false,
                                clipBehavior: Clip.none,
                                boundaryMargin: const EdgeInsets.all(420),
                                interactionEndFrictionCoefficient: 0.00006,
                                onInteractionUpdate: (_) {
                                  final currentScale =
                                      _zoomController.value.getMaxScaleOnAxis();
                                  if ((currentScale - _zoomScale).abs() >
                                          0.01 &&
                                      mounted) {
                                    setState(() {
                                      _zoomScale = currentScale.clamp(
                                          _minZoom, _maxZoom);
                                    });
                                  }
                                },
                                child: RepaintBoundary(
                                  key: _receiptBoundaryKey,
                                  child: Container(
                                    width: _receiptCardWidth,
                                    height: _receiptCardHeight,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                          color: const Color(0xFF0D47A1),
                                          width: 3),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x550D47A1),
                                          blurRadius: 18,
                                          spreadRadius: 3,
                                          offset: Offset(0, 4),
                                        ),
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 6,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 15, vertical: 10),
                                    child: Column(
                                      children: [
                                        /// --- HEADER ---
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: const [
                                                  Text("Taj Royal Glass Co.",
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                          color: Color(
                                                              0xFF0D47A1))),
                                                  Text(
                                                      "for Glass & Mirrors Production",
                                                      style: TextStyle(
                                                          fontSize: 9,
                                                          color:
                                                              Color(0xFF0D47A1),
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              width: 60,
                                              height: 60,
                                              color: Colors.white,
                                              child: Image.asset(
                                                "assets/logo.png",
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: const [
                                                  Text("شركة تـاج رويـال",
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 18,
                                                          color: Color(
                                                              0xFF0D47A1))),
                                                  Text(
                                                      "لتركيب الزجاج والمرايا والبراويز",
                                                      style: TextStyle(
                                                          fontSize: 9,
                                                          color:
                                                              Color(0xFF0D47A1),
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 8),

                                        /// --- TOP BOXES ---
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildTopBox("K.D | دينار",
                                                controller: _kdController),
                                            _buildTopBox("Fils | فلس",
                                                controller: _filsController),
                                            const Spacer(),
                                            Column(
                                              children: [
                                                Container(
                                                  width: 100,
                                                  height: 20,
                                                  decoration: const BoxDecoration(
                                                      color: Color(0xFF0D47A1),
                                                      borderRadius:
                                                          BorderRadius.only(
                                                              topLeft: Radius
                                                                  .circular(4),
                                                              topRight: Radius
                                                                  .circular(
                                                                      4))),
                                                  child: const Center(
                                                      child: Text(
                                                          "Date / التاريخ",
                                                          style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold))),
                                                ),
                                                Container(
                                                  width: 100,
                                                  height: 30,
                                                  decoration: BoxDecoration(
                                                      border: Border.all(
                                                          color: const Color(
                                                              0xFF0D47A1)),
                                                      borderRadius:
                                                          const BorderRadius
                                                              .only(
                                                              bottomLeft: Radius
                                                                  .circular(4),
                                                              bottomRight:
                                                                  Radius
                                                                      .circular(
                                                                          4))),
                                                  child: TextField(
                                                    controller: _dateController,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                    decoration:
                                                        const InputDecoration(
                                                            isDense: true,
                                                            border: InputBorder
                                                                .none,
                                                            contentPadding:
                                                                EdgeInsets.only(
                                                                    top: 6)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 10),
                                            _buildTopBox("No. / رقم",
                                                width: 80,
                                                controller: _noController),
                                          ],
                                        ),

                                        /// --- CENTER VOUCHER TITLE ---
                                        Container(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 8),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 15, vertical: 3),
                                          decoration: BoxDecoration(
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFF0D47A1),
                                                  width: 1.5)),
                                          child: Column(
                                            children: const [
                                              Text("سـند قـبـض",
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color:
                                                          Color(0xFF0D47A1))),
                                              Text("Receipt Voucher",
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 10,
                                                      color:
                                                          Color(0xFF0D47A1))),
                                            ],
                                          ),
                                        ),

                                        /// --- FORM FIELDS ---

                                        _buildLineField(
                                            "Received from Mr./Messrs:",
                                            "استلمنا من السيد / السادة:",
                                            controller:
                                                _receivedFromController),

                                        _buildLineField(
                                            "Mobile No:", "رقم الهاتف:",
                                            controller: _mobileController),

                                        _buildLineField("The sum of K.D.:",
                                            "مبلغ وقدرة د.ك.:",
                                            controller: _sumController),

                                        Row(
                                          children: [
                                            Expanded(
                                                child: _buildLineField(
                                                    "On Bank:", "على بنك:",
                                                    controller:
                                                        _bankController)),
                                            const SizedBox(width: 15),
                                            Expanded(
                                                child: _buildLineField(
                                                    "Cash/Cheque No:",
                                                    "نقداً/شيك رقم:",
                                                    controller:
                                                        _chequeController)),
                                          ],
                                        ),

                                        _buildLineField(
                                            "Being For:", "وذلك عن:",
                                            controller: _beingForController),

                                        const Spacer(),

                                        /// --- SIGNATURE AREA ---

                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            _buildSignArea(
                                                "Receiver's Name / اسم المستلم"),
                                            _buildSignArea(
                                                "Signature / التوقيع"),
                                          ],
                                        ),

                                        /// --- FOOTER (EXACT IMAGE 2 MATCH) ---

                                        const SizedBox(height: 20),

                                        const Divider(
                                            color: Color(0xFF0D47A1),
                                            thickness: 2.0),

                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.location_on,
                                                    color: Color(0xFF0D47A1),
                                                    size: 24),
                                                const SizedBox(width: 9),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: const [
                                                    Text(
                                                        "الراي - قطعة ١ - شارع ٢٦ - محل ١٣/١١",
                                                        style: TextStyle(
                                                            fontSize: 9.5,
                                                            color: Color(
                                                                0xFF0D47A1),
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800)),
                                                    Text(
                                                        "Al Rai Block 1 - St. 26 - Shop 11/13",
                                                        style: TextStyle(
                                                            fontSize: 9.5,
                                                            color: Color(
                                                                0xFF0D47A1),
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: const [
                                                Icon(Icons.camera_alt_outlined,
                                                    color: Color(0xFF0D47A1),
                                                    size: 20),
                                                SizedBox(width: 5),
                                                Text("stainless_steelvip",
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            Color(0xFF0D47A1),
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                const Icon(Icons.phone_android,
                                                    color: Color(0xFF0D47A1),
                                                    size: 20),
                                                const SizedBox(width: 5),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: const [
                                                    Text("56540521",
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color: Color(
                                                                0xFF0D47A1),
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                    Text("96952550",
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color: Color(
                                                                0xFF0D47A1),
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    /// --- BUTTONS ---

                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 15,
                        runSpacing: 10,
                        children: [
                          _buildActionButton("Print", Colors.blue,
                              () => _runButtonAction('Print', _printReceipt)),
                          _buildActionButton("Save PDF", Colors.green,
                              () => _runButtonAction('Save PDF', _savePdf)),
                          _buildActionButton(
                              "Download PDF",
                              Colors.blueAccent,
                              () => _runButtonAction(
                                  'Download PDF', _downloadPdf)),
                          _buildActionButton("Share", Colors.orange,
                              () => _runButtonAction('Share', _sharePdf)),
                        ],
                      ),
                    ),
                    if (_isProcessing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Please wait... Processing PDF',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0D47A1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _isWarmingUp
                            ? 'PDF status: Updating full receipt...'
                            : (_isPdfReadyForCurrentData()
                                ? 'PDF status: Ready (full receipt)'
                                : 'PDF status: Not ready yet'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF0D47A1),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper Methods (Boxes, Lines, Buttons)

  Widget _buildTopBox(
    String label, {
    double width = 65,
    TextEditingController? controller,
  }) {
    return Column(
      children: [
        Container(
          width: width,
          height: 20,
          decoration: const BoxDecoration(
            color: Color(0xFF0D47A1),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Container(
          width: width,
          height: 30,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF0D47A1)),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            style: _receiptInputTextStyle(),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.only(top: 6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLineField(
    String en,
    String ar, {
    TextEditingController? controller,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _twoMmGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            en,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF0D47A1),
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: TextField(
                controller: controller,
                style: _receiptInputTextStyle(color: Colors.black87),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.only(bottom: 2),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF0D47A1), width: 1),
                  ),
                ),
              ),
            ),
          ),
          Text(
            ar,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF0D47A1),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignArea(String label) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: Color(0xFF0D47A1),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 25),
        SizedBox(width: 150, child: _buildDottedSignatureLine()),
      ],
    );
  }

  Widget _buildDottedSignatureLine() {
    return SizedBox(
      height: 2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double dotWidth = 2.2;
          const double dotHeight = 2.2;
          const double gapWidth = 2.8;
          final dotCount =
              (constraints.maxWidth / (dotWidth + gapWidth)).floor();

          return Row(
            children: List.generate(
              dotCount,
              (_) => Container(
                width: dotWidth,
                height: dotHeight,
                margin: const EdgeInsets.only(right: gapWidth),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D47A1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMobileActionButton(
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: _isProcessing ? null : onTap,
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}
