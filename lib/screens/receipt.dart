import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/sidebar.dart';
import 'dashboard.dart';

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
  static const double _receiptCardHeight = 527;
  final GlobalKey _viewerAreaKey = GlobalKey();
  Size _lastViewerSize = Size.zero;
  bool _initialZoomSet = false;
  double _inputFontSize = 10;
  bool _isInputBold = false;
  bool _isInputItalic = false;
  bool _isInputUnderline = false;
  String _inputFontStyle = 'Roboto';
  Color _receiptBgColor = Colors.white;
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
  final _receiptNoController = TextEditingController();
  final _historySearchController = TextEditingController();
  int? _editingReceiptIndex;
  int? _hoveredReceiptIndex;
  bool _showSignature = false;
  Timer? _mobileDebounce;

  final TextEditingController _dateController = TextEditingController(
    text:
        "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
  );

  final TextEditingController _receiverNameController = TextEditingController();

  // Firebase instance
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _noController.text = "0001"; // contract no auto later
    _receiptNoController.text = "1";
    _attachFieldListeners();
    _loadReceiptsFromFirebase();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _schedulePdfWarmup();
      _resetZoom(); // center receipt preview on first frame

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
    _mobileController.addListener(_onMobileFieldChanged);
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
    _mobileController.removeListener(_onMobileFieldChanged);
  }

  void _onFormChanged() {
    _invalidatePdfCache();
    _schedulePdfWarmup();
  }

  void _onMobileFieldChanged() {
    _mobileDebounce?.cancel();
    _mobileDebounce = Timer(const Duration(milliseconds: 900), () {
      _autoFillReceiptNumber();
    });
  }

  Future<void> _autoFillReceiptNumber() async {
    final mobile = _mobileController.text.trim();
    if (mobile.isEmpty) return;
    // Skip auto-fill when editing an existing receipt
    if (_editingReceiptIndex != null) return;
    try {
      final existingSnap = await _firestore
          .collection('receipts')
          .where('mobile', isEqualTo: mobile)
          .limit(1)
          .get();
      if (existingSnap.docs.isEmpty) return;
      final contractNo =
          (existingSnap.docs.first.data()['contractNo'] as String?) ?? '';
      if (contractNo.isEmpty) return;
      final countSnap = await _firestore
          .collection('receipts')
          .where('contractNo', isEqualTo: contractNo)
          .get();
      final nextReceiptNo = countSnap.docs.length + 1;
      if (mounted) {
        setState(() {
          _noController.text = contractNo.replaceAll('CT-', '');
          _receiptNoController.text = nextReceiptNo.toString();
        });
      }
    } catch (_) {
      // Non-critical � user can still save manually
    }
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

  /// Returns a safe PDF filename: CustomerName_Receipt_DD-MM-YYYY.pdf
  String _receiptPdfFileName() {
    final rawName = _receivedFromController.text.trim();
    final safeName = rawName.isEmpty
        ? 'Customer'
        : rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').replaceAll(' ', '_');
    final rawDate = _dateController.text.trim(); // DD/M/YYYY
    final parts = rawDate.split('/');
    final dateStr = parts.length == 3
        ? '${parts[0].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}-${parts[2]}'
        : rawDate.replaceAll('/', '-');
    return '${safeName}_Receipt_$dateStr.pdf';
  }

  Future<Uint8List> _captureReceiptAsPng() async {
    await Future.delayed(const Duration(milliseconds: 200));
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
    final currentKey = _currentPdfDataKey();
    if (_cachedPdfBytes != null && _cachedPdfKey == currentKey) {
      return _cachedPdfBytes!;
    }
    final pngBytes = await _captureReceiptAsPng();
    final pdf = _buildPdfFromImage(pngBytes);
    final bytes = await pdf.save();
    _cachedPdfBytes = bytes;
    _cachedPdfKey = currentKey;
    return bytes;
  }

  // ignore: unused_element
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
          return pw.FittedBox(
            fit: pw.BoxFit.fill,
            child: pw.Image(receiptImage),
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
                    'No: CT-${_noController.text}',
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
                style: pw.TextStyle(fontSize: 11),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      // ?? Editable field ka text PDF me show hoga
                      pw.Text(
                        _receiverNameController.text.isEmpty
                            ? ' '
                            : _receiverNameController.text,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),

                      pw.Text('__________________________'),

                      pw.Text(
                        "Receiver's Name / اسم المستلم",
                        style: pw.TextStyle(fontSize: 9),
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
    _mobileDebounce?.cancel();
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
    _receiptNoController.dispose();
    _dateController.dispose();
    _historySearchController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  void _setZoom(double nextScale, {Size? viewerSize}) {
    final clamped = nextScale.clamp(_minZoom, _maxZoom).toDouble();
    Size? size = viewerSize;
    if (size == null) {
      final renderObject = _viewerAreaKey.currentContext?.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        size = renderObject.size;
      }
    }
    if (size != null) {
      final dx = (size.width - (_receiptCardWidth * clamped)) / 2;
      final dy = (size.height - (_receiptCardHeight * clamped)) / 2;
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
    final renderObject = _viewerAreaKey.currentContext?.findRenderObject();
    Size? viewerSize;
    if (renderObject is RenderBox && renderObject.hasSize) {
      viewerSize = renderObject.size;
    }
    final effectiveWidth =
        viewerSize?.width ?? MediaQuery.of(context).size.width;
    if (effectiveWidth < 900) {
      final fitZoom = (effectiveWidth / _receiptCardWidth).clamp(_minZoom, 1.0);
      _setZoom(fitZoom, viewerSize: viewerSize);
    } else {
      _setZoom(1.0, viewerSize: viewerSize);
    }
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
    await saveReceiptToFirebase();

    try {
      final bytes = await _getPdfBytes();
      final name = 'receipt_${_dateController.text.replaceAll('/', '-')}.pdf';

      if (kIsWeb) {
        await downloadPdfBytes(bytes, name);
        _saveReceiptHistory();
        if (mounted) {
          setState(() {
            _editingReceiptIndex = null;
          });
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
      final pdfBytes = await _getPdfBytes();
      final name = _receiptPdfFileName();

      if (kIsWeb) {
        await downloadPdfBytes(pdfBytes, name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Receipt PDF downloaded')),
          );
        }
        return;
      }

      final downloadDir = await getDownloadsDirectory();
      final fallbackDir = await getApplicationDocumentsDirectory();
      final targetDir = downloadDir ?? fallbackDir;
      final file = File('${targetDir.path}/$name');
      await file.writeAsBytes(pdfBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt PDF saved: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  Future<void> _sharePdf() async {
    try {
      final bytes = await _getPdfBytes();
      final name = _receiptPdfFileName();

      if (kIsWeb) {
        // Try Web Share API via share_plus; fallback to download if unsupported
        try {
          await Share.shareXFiles(
            [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
            text: 'Receipt from Taj Royal Glass Co.',
          );
        } catch (_) {
          await downloadPdfBytes(bytes, name);
        }
      } else {
        // Mobile / Desktop: pehle file save, phir native share sheet
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Receipt from Taj Royal Glass Co.',
        );
      }
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

  Future<void> _loadReceiptsFromFirebase() async {
    try {
      final snapshot = await _firestore.collection('receipts').get();
      DataService.receipts.clear();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        DataService.receipts.add({
          'name': data['name'] ?? '',
          'mobile': data['mobile'] ?? '',
          'amount': data['amount'] ?? '',
          'date': data['date'] ?? '',
          'contractNo': data['contractNo'] ?? '',
          'receiptNo': data['receiptNo'] ?? '',
          'fullNo': data['fullNo'] ?? '',
          'bank': data['bank'] ?? '',
          'chequeNo': data['chequeNo'] ?? '',
          'beingFor': data['beingFor'] ?? '',
          'kd': data['amount'] ?? '',
          'fils': data.containsKey('fils') ? data['fils'] : '',
          'sum': data.containsKey('sum') ? data['sum'] : '',
          'no': data['contractNo']?.replaceAll('CT-', '') ?? '',
          'receiverName': data['receiverName'] ?? '',
        });
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading receipts: $e');
    }
  }

  Future<void> saveReceiptToFirebase() async {
    try {
      final name = _receivedFromController.text.trim();
      final mobile = _mobileController.text.trim();

      // Check if editing an existing receipt that has a Firestore doc
      final editingIndex = _editingReceiptIndex;
      final existingFirestoreId = (editingIndex != null &&
              editingIndex >= 0 &&
              editingIndex < DataService.receipts.length)
          ? DataService.receipts[editingIndex]['firestoreId']?.toString()
          : null;

      if (existingFirestoreId != null && existingFirestoreId.isNotEmpty) {
        // UPDATE existing Firestore document — no duplicate
        final updateData = {
          'name': name,
          'mobile': mobile,
          'amount': _kdController.text.trim(),
          'date': _dateController.text.trim(),
          'bank': _bankController.text.trim(),
          'chequeNo': _chequeController.text.trim(),
          'beingFor': _beingForController.text.trim(),
          'receiverName': _receiverNameController.text.trim(),
          'fils': _filsController.text.trim(),
          'sum': _sumController.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await _firestore
            .collection('receipts')
            .doc(existingFirestoreId)
            .update(updateData);

        // Update local DataService entry
        DataService.receipts[editingIndex!] = {
          ...DataService.receipts[editingIndex],
          'name': name,
          'mobile': mobile,
          'amount': _kdController.text.trim(),
          'date': _dateController.text.trim(),
          'bank': _bankController.text.trim(),
          'cheque': _chequeController.text.trim(),
          'beingFor': _beingForController.text.trim(),
          'receiverName': _receiverNameController.text.trim(),
          'fils': _filsController.text.trim(),
          'sum': _sumController.text.trim(),
          'kd': _kdController.text.trim(),
        };

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Receipt updated')),
          );
        }
        return;
      }

      // NEW receipt — create new Firestore document
      String contractNo = '';
      int receiptNo = 1;

      if (mobile.isNotEmpty) {
        // Look for any existing receipt from this mobile number
        final existingSnap = await _firestore
            .collection('receipts')
            .where('mobile', isEqualTo: mobile)
            .limit(1)
            .get();
        if (existingSnap.docs.isNotEmpty) {
          contractNo =
              (existingSnap.docs.first.data()['contractNo'] as String?) ?? '';
        }
      }

      if (contractNo.isEmpty) {
        // New customer — assign next CT-XXXX via Firestore counter
        final counterRef = _firestore.collection('counters').doc('mainCounter');
        final counterSnap = await counterRef.get();
        int lastNo = counterSnap.exists
            ? ((counterSnap['lastContractNo'] ?? 0) as int)
            : 0;
        lastNo++;
        await counterRef.set({'lastContractNo': lastNo});
        contractNo = 'CT-${lastNo.toString().padLeft(4, '0')}';
      }

      // Count existing receipts for this contractNo — receipt sequence number
      final countSnap = await _firestore
          .collection('receipts')
          .where('contractNo', isEqualTo: contractNo)
          .get();
      receiptNo = countSnap.docs.length + 1;

      final fullNo = '$contractNo / R$receiptNo';

      final docRef = await _firestore.collection('receipts').add({
        'contractNo': contractNo,
        'receiptNo': receiptNo.toString(),
        'fullNo': fullNo,
        'name': name,
        'mobile': mobile,
        'amount': _kdController.text.trim(),
        'date': _dateController.text.trim(),
        'bank': _bankController.text.trim(),
        'chequeNo': _chequeController.text.trim(),
        'beingFor': _beingForController.text.trim(),
        'receiverName': _receiverNameController.text.trim(),
        'fils': _filsController.text.trim(),
        'sum': _sumController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Keep DataService.receipts in sync so Dashboard shows fresh data
      final newEntry = {
        'firestoreId': docRef.id,
        'name': name,
        'mobile': mobile,
        'amount': _kdController.text.trim(),
        'date': _dateController.text.trim(),
        'contractNo': contractNo,
        'receiptNo': receiptNo.toString(),
        'fullNo': fullNo,
        'bank': _bankController.text.trim(),
        'cheque': _chequeController.text.trim(),
        'beingFor': _beingForController.text.trim(),
        'kd': _kdController.text.trim(),
        'fils': _filsController.text.trim(),
        'sum': _sumController.text.trim(),
        'no': contractNo.replaceAll('CT-', ''),
        'receiverName': _receiverNameController.text.trim(),
      };
      DataService.receipts.insert(0, newEntry);

      if (mounted) {
        setState(() {
          _noController.text = contractNo.replaceAll('CT-', '');
          _receiptNoController.text = receiptNo.toString();
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $fullNo')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
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
      final receiptNo = (receipt['no'] ?? '').toString().toLowerCase();
      final cheque = (receipt['cheque'] ?? '').toString().toLowerCase();
      final beingFor = (receipt['beingFor'] ?? '').toString().toLowerCase();
      return name.contains(query) ||
          mobile.contains(query) ||
          amount.contains(query) ||
          date.contains(query) ||
          receiptNo.contains(query) ||
          cheque.contains(query) ||
          beingFor.contains(query);
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

  String _nextReceiptNumber() {
    final count = DataService.receipts.length + 1;
    return count.toString().padLeft(4, '0');
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
      _noController.text = _nextReceiptNumber();
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

    try {
      final receipt = DataService.receipts[sourceIndex];
      final firestoreId = receipt['firestoreId']?.toString() ?? '';
      final fullNo = receipt['fullNo']?.toString() ?? '';

      // Delete from Firebase — prefer direct doc delete, fallback to fullNo query
      if (firestoreId.isNotEmpty) {
        await _firestore.collection('receipts').doc(firestoreId).delete();
      } else if (fullNo.isNotEmpty) {
        final snapshot = await _firestore
            .collection('receipts')
            .where('fullNo', isEqualTo: fullNo)
            .get();
        for (var doc in snapshot.docs) {
          await doc.reference.delete();
        }
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Widget _buildHistoryPanel({double width = 300, bool compact = false}) {
    final receipts = _filteredReceipts();

    // -- MOBILE / COMPACT branch (bottom-sheet) � unchanged ----------
    if (compact) {
      return Container(
        width: width,
        color: Colors.white,
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.receipt_long,
                            color: Color(0xFF0D47A1), size: 16),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Receipt History',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0D47A1),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF0D47A1).withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${receipts.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0D47A1),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_editingReceiptIndex != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                const Color(0xFF0D47A1).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Edit mode is active',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0D47A1))),
                          ),
                          TextButton(
                              onPressed: _startNewReceipt,
                              child: const Text('Cancel')),
                        ],
                      ),
                    ),
                  TextField(
                    controller: _historySearchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search receipts�',
                      hintStyle:
                          TextStyle(color: Colors.grey[400], fontSize: 12),
                      prefixIcon: const Icon(Icons.search,
                          size: 18, color: Color(0xFF0D47A1)),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF0F4FF),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 9),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFF0D47A1), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text('Name',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('Mobile',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('Date',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('Amount',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                        SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: receipts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.receipt_long_outlined,
                                    size: 40, color: Colors.grey[300]),
                                const SizedBox(height: 10),
                                Text('No receipts found',
                                    style: TextStyle(
                                        color: Colors.grey[400], fontSize: 13)),
                              ],
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ListView.separated(
                              itemCount: receipts.length,
                              separatorBuilder: (_, __) => Divider(
                                  height: 1, color: Colors.blue.shade50),
                              itemBuilder: (context, index) {
                                final receipt = receipts[index];
                                final sourceIndex =
                                    DataService.receipts.indexOf(receipt);
                                final isHov = _hoveredReceiptIndex == index;
                                return MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  onEnter: (_) => setState(
                                      () => _hoveredReceiptIndex = index),
                                  onExit: (_) => setState(
                                      () => _hoveredReceiptIndex = null),
                                  child: InkWell(
                                    onTap: sourceIndex >= 0
                                        ? () => _loadReceiptFromHistory(receipt,
                                            index: sourceIndex)
                                        : null,
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 7),
                                      color: isHov
                                          ? const Color(0xFFE8F0FF)
                                          : (index.isEven
                                              ? Colors.white
                                              : const Color(0xFFFAFBFF)),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  (receipt['name'] ?? '')
                                                          .toString()
                                                          .isEmpty
                                                      ? 'Unnamed'
                                                      : receipt['name']
                                                          .toString(),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF0D47A1)),
                                                ),
                                                Text(
                                                  '#${receipt['receiptNo'] ?? ''}',
                                                  style: TextStyle(
                                                      fontSize: 9,
                                                      color: Colors.grey[500]),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              (receipt['mobile'] ?? '-')
                                                  .toString(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey[700]),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              (receipt['date'] ?? '-')
                                                  .toString(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey[600]),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF00897B)
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                (receipt['amount'] ?? '-')
                                                    .toString(),
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF00695C)),
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 48,
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child: IconButton(
                                                    padding: EdgeInsets.zero,
                                                    icon: const Icon(
                                                        Icons.edit_outlined,
                                                        size: 13,
                                                        color:
                                                            Color(0xFF0D47A1)),
                                                    onPressed: sourceIndex >= 0
                                                        ? () =>
                                                            _loadReceiptFromHistory(
                                                                receipt,
                                                                index:
                                                                    sourceIndex)
                                                        : null,
                                                    tooltip: 'Edit',
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child: IconButton(
                                                    padding: EdgeInsets.zero,
                                                    icon: const Icon(
                                                        Icons.delete_outline,
                                                        size: 13,
                                                        color: Colors.red),
                                                    onPressed: sourceIndex >= 0
                                                        ? () =>
                                                            _deleteReceiptFromHistory(
                                                                sourceIndex)
                                                        : null,
                                                    tooltip: 'Delete',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 2,
              decoration: BoxDecoration(
                color: const Color(0xFF0D47A1).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 6),
            _buildTypographyRibbon(compact: true),
          ],
        ),
      );
    }

    // -- DESKTOP branch � premium admin dashboard style ---------------
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FF),
      ),
      child: Column(
        children: [
          // -- Top accent bar -----------------------------------------
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // -- Main panel ---------------------------------------
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // -- Header -------------------------------------
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0D47A1),
                                    Color(0xFF1976D2)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0D47A1)
                                        .withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.receipt_long,
                                  color: Colors.white, size: 17),
                            ),
                            const SizedBox(width: 10),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Receipt History',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0D47A1),
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                Text(
                                  'All saved receipts',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF90A4AE),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // Count badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0D47A1),
                                    Color(0xFF1565C0)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0D47A1)
                                        .withValues(alpha: 0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                '${receipts.length} records',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // -- Edit mode banner ----------------------------
                        if (_editingReceiptIndex != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F2FD),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFF1976D2)
                                      .withValues(alpha: 0.35),
                                  width: 1),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.edit_note,
                                    size: 16, color: Color(0xFF1565C0)),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Editing receipt � changes apply on Save',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1565C0)),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _startNewReceipt,
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF1565C0),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    textStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ),

                        // -- Search bar ----------------------------------
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _historySearchController,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Search by name, mobile, amount�',
                              hintStyle: TextStyle(
                                  color: Colors.grey[400], fontSize: 12.5),
                              prefixIcon: const Icon(Icons.search,
                                  size: 19, color: Color(0xFF0D47A1)),
                              suffixIcon:
                                  _historySearchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(Icons.close,
                                              size: 16,
                                              color: Colors.grey[400]),
                                          onPressed: () => setState(() =>
                                              _historySearchController.clear()),
                                        )
                                      : null,
                              isDense: false,
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 13),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                    color: Colors.grey.shade200, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: Color(0xFF0D47A1), width: 1.8),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // -- Table container -----------------------------
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Column(
                                children: [
                                  // -- Column header ---------------------
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 11),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFF0D47A1),
                                          Color(0xFF1565C0),
                                        ],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                    ),
                                    child: const Row(
                                      children: [
                                        Expanded(
                                          flex: 34,
                                          child: Text(
                                            'Name & Ref',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 24,
                                          child: Text(
                                            'Mobile',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 22,
                                          child: Text(
                                            'Date',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 20,
                                          child: Text(
                                            'Amount',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.3,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        SizedBox(width: 58),
                                      ],
                                    ),
                                  ),

                                  // -- Rows -----------------------------
                                  Expanded(
                                    child: receipts.isEmpty
                                        ? Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.all(18),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFFF0F4FF),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.receipt_long_outlined,
                                                    size: 36,
                                                    color: Color(0xFF90A4AE),
                                                  ),
                                                ),
                                                const SizedBox(height: 14),
                                                const Text(
                                                  'No receipts found',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF90A4AE),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Try adjusting your search',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[400],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : ListView.separated(
                                            itemCount: receipts.length,
                                            separatorBuilder: (_, __) =>
                                                Divider(
                                                    height: 1,
                                                    color:
                                                        Colors.grey.shade100),
                                            itemBuilder: (context, index) {
                                              final receipt = receipts[index];
                                              final sourceIndex = DataService
                                                  .receipts
                                                  .indexOf(receipt);
                                              final isHov =
                                                  _hoveredReceiptIndex == index;
                                              final isEditing =
                                                  _editingReceiptIndex !=
                                                          null &&
                                                      sourceIndex ==
                                                          _editingReceiptIndex;

                                              final fullNo =
                                                  (receipt['fullNo'] ?? '')
                                                      .toString();
                                              final contractNo =
                                                  (receipt['contractNo'] ?? '')
                                                      .toString();
                                              final receiptNo =
                                                  (receipt['receiptNo'] ?? '')
                                                      .toString();
                                              final displayRef = fullNo
                                                      .isNotEmpty
                                                  ? fullNo
                                                  : (contractNo.isNotEmpty
                                                      ? '$contractNo / $receiptNo'
                                                      : (receiptNo.isNotEmpty
                                                          ? '#$receiptNo'
                                                          : '�'));

                                              return MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.click,
                                                onEnter: (_) => setState(() =>
                                                    _hoveredReceiptIndex =
                                                        index),
                                                onExit: (_) => setState(() =>
                                                    _hoveredReceiptIndex =
                                                        null),
                                                child: InkWell(
                                                  onTap: sourceIndex >= 0
                                                      ? () =>
                                                          _loadReceiptFromHistory(
                                                            receipt,
                                                            index: sourceIndex,
                                                          )
                                                      : null,
                                                  child: AnimatedContainer(
                                                    duration: const Duration(
                                                        milliseconds: 150),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 16,
                                                        vertical: 12),
                                                    decoration: BoxDecoration(
                                                      color: isEditing
                                                          ? const Color(
                                                              0xFFE3F2FD)
                                                          : (isHov
                                                              ? const Color(
                                                                  0xFFEEF4FF)
                                                              : (index.isEven
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFFFAFCFF))),
                                                      border: isEditing
                                                          ? Border(
                                                              left: BorderSide(
                                                                  color: const Color(
                                                                      0xFF1976D2),
                                                                  width: 3))
                                                          : null,
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        // Name + ref
                                                        Expanded(
                                                          flex: 34,
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                (receipt['name'] ??
                                                                            '')
                                                                        .toString()
                                                                        .isEmpty
                                                                    ? 'Unnamed'
                                                                    : receipt[
                                                                            'name']
                                                                        .toString(),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  color: isEditing
                                                                      ? const Color(
                                                                          0xFF1565C0)
                                                                      : const Color(
                                                                          0xFF1A2340),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  height: 2),
                                                              Container(
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical:
                                                                        1),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: const Color(
                                                                          0xFF0D47A1)
                                                                      .withValues(
                                                                          alpha:
                                                                              0.08),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              5),
                                                                ),
                                                                child: Text(
                                                                  displayRef,
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize:
                                                                        9.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: Color(
                                                                        0xFF0D47A1),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        // Mobile
                                                        Expanded(
                                                          flex: 24,
                                                          child: Text(
                                                            (receipt['mobile'] ??
                                                                    '�')
                                                                .toString(),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 11.5,
                                                              color: Colors
                                                                  .grey[600],
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ),
                                                        // Date
                                                        Expanded(
                                                          flex: 22,
                                                          child: Text(
                                                            (receipt['date'] ??
                                                                    '�')
                                                                .toString(),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Colors
                                                                  .grey[500],
                                                            ),
                                                          ),
                                                        ),
                                                        // Amount badge
                                                        Expanded(
                                                          flex: 20,
                                                          child: Center(
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          9,
                                                                      vertical:
                                                                          4),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: const Color(
                                                                        0xFF00897B)
                                                                    .withValues(
                                                                        alpha:
                                                                            0.1),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            20),
                                                                border: Border.all(
                                                                    color: const Color(
                                                                            0xFF00897B)
                                                                        .withValues(
                                                                            alpha:
                                                                                0.25),
                                                                    width: 1),
                                                              ),
                                                              child: Text(
                                                                (receipt['amount'] ??
                                                                        '�')
                                                                    .toString(),
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style:
                                                                    const TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: Color(
                                                                      0xFF00695C),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        // Actions
                                                        SizedBox(
                                                          width: 58,
                                                          child: Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .end,
                                                            children: [
                                                              Tooltip(
                                                                message: 'Edit',
                                                                child: InkWell(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              7),
                                                                  onTap: sourceIndex >=
                                                                          0
                                                                      ? () =>
                                                                          _loadReceiptFromHistory(
                                                                            receipt,
                                                                            index:
                                                                                sourceIndex,
                                                                          )
                                                                      : null,
                                                                  child:
                                                                      Container(
                                                                    width: 26,
                                                                    height: 26,
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: const Color(
                                                                              0xFF0D47A1)
                                                                          .withValues(
                                                                              alpha: 0.08),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              7),
                                                                    ),
                                                                    child:
                                                                        const Icon(
                                                                      Icons
                                                                          .edit_outlined,
                                                                      size: 14,
                                                                      color: Color(
                                                                          0xFF0D47A1),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  width: 6),
                                                              Tooltip(
                                                                message:
                                                                    'Delete',
                                                                child: InkWell(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              7),
                                                                  onTap: sourceIndex >=
                                                                          0
                                                                      ? () => _deleteReceiptFromHistory(
                                                                          sourceIndex)
                                                                      : null,
                                                                  child:
                                                                      Container(
                                                                    width: 26,
                                                                    height: 26,
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: Colors
                                                                          .red
                                                                          .withValues(
                                                                              alpha: 0.08),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              7),
                                                                    ),
                                                                    child:
                                                                        const Icon(
                                                                      Icons
                                                                          .delete_outline,
                                                                      size: 14,
                                                                      color: Colors
                                                                          .red,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // -- Typography ribbon (right side) -------------------
                  const SizedBox(width: 8),
                  Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF0D47A1).withValues(alpha: 0.0),
                          const Color(0xFF0D47A1).withValues(alpha: 0.35),
                          const Color(0xFF0D47A1).withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildTypographyRibbon(compact: false),
                ],
              ),
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
          _buildBgColorButton(compact: compact),
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
                _receiptBgColor = Colors.white;
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

  static const List<Color> _bgColorOptions = [
    Colors.white,
    Color(0xFFFFFDE7), // light yellow
    Color(0xFFFFF9C4), // cream yellow
    Color(0xFFFFF3E0), // light orange cream
    Color(0xFFE8F5E9), // light green
    Color(0xFFE3F2FD), // light blue
  ];

  Widget _buildBgColorButton({bool compact = false}) {
    return PopupMenuButton<Color>(
      tooltip: 'Receipt background color',
      icon: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: _receiptBgColor,
          border: Border.all(
            color: const Color(0xFF0D47A1).withValues(alpha: 0.6),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      onSelected: (color) {
        setState(() {
          _receiptBgColor = color;
        });
      },
      itemBuilder: (context) => _bgColorOptions.map((color) {
        final labels = {
          Colors.white: 'White',
          const Color(0xFFFFFDE7): 'Light Yellow',
          const Color(0xFFFFF9C4): 'Cream Yellow',
          const Color(0xFFFFF3E0): 'Cream',
          const Color(0xFFE8F5E9): 'Light Green',
          const Color(0xFFE3F2FD): 'Light Blue',
        };
        return PopupMenuItem<Color>(
          value: color,
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(
                    color: const Color(0xFF0D47A1).withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Text(labels[color] ?? ''),
              if (_receiptBgColor == color)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.check, size: 14, color: Color(0xFF0D47A1)),
                ),
            ],
          ),
        );
      }).toList(),
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 180),
              pageBuilder: (_, __, ___) => const Dashboard(),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          );
        }
      },
      child: Scaffold(
        drawer: isMobile
            ? const Drawer(
                child: SafeArea(child: Sidebar(currentIndex: 2)),
              )
            : null,
        floatingActionButton: isMobile
            ? FloatingActionButton(
                onPressed: _openHistorySheet,
                backgroundColor: const Color(0xFF0D47A1),
                mini: true,
                tooltip: 'History',
                child: const Icon(Icons.history, size: 20, color: Colors.white),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        bottomNavigationBar: isMobile
            ? SafeArea(
                top: false,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isProcessing)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildMobileActionButton(
                            'New',
                            Colors.indigo,
                            _startNewReceipt,
                          ),
                          ElevatedButton.icon(
                            icon: Icon(
                              _showSignature
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.white,
                              size: 14,
                            ),
                            label: Text(
                              _showSignature ? 'Sign ON' : 'Sign OFF',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _showSignature
                                  ? Colors.purple
                                  : Colors.grey[700],
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 38),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => setState(
                                () => _showSignature = !_showSignature),
                          ),
                          _buildMobileActionButton(
                            'Print',
                            Colors.blue,
                            () => _runButtonAction('Print', _printReceipt),
                          ),
                          _buildMobileActionButton(
                            'Save',
                            Colors.green,
                            () => _runButtonAction('Save PDF', _savePdf),
                          ),
                          _buildMobileActionButton(
                            'Download',
                            Colors.blueAccent,
                            () =>
                                _runButtonAction('Download PDF', _downloadPdf),
                          ),
                          _buildMobileActionButton(
                            'Share',
                            Colors.orange,
                            () => _runButtonAction('Share', _sharePdf),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : null,
        body: Column(
          children: [
            if (isMobile)
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Receipt',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Row(
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
                                  final isFirstLayout =
                                      _lastViewerSize == Size.zero;
                                  if ((nextViewerSize.width -
                                                  _lastViewerSize.width)
                                              .abs() >
                                          0.5 ||
                                      (nextViewerSize.height -
                                                  _lastViewerSize.height)
                                              .abs() >
                                          0.5) {
                                    _lastViewerSize = nextViewerSize;
                                    if (isFirstLayout && !_initialZoomSet) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (mounted) {
                                          _initialZoomSet = true;
                                          final isMobileLayout =
                                              nextViewerSize.width < 900;
                                          final zoom = isMobileLayout
                                              ? (nextViewerSize.width /
                                                      _receiptCardWidth)
                                                  .clamp(_minZoom, 1.0)
                                              : 1.0;
                                          _setZoom(
                                            zoom,
                                            viewerSize: nextViewerSize,
                                          );
                                        }
                                      });
                                    }
                                  }

                                  return Center(
                                    child: SizedBox(
                                      key: _viewerAreaKey,
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                      child: InteractiveViewer(
                                        transformationController:
                                            _zoomController,
                                        alignment: Alignment.center,
                                        minScale: _minZoom,
                                        maxScale: _maxZoom,
                                        panEnabled: true,
                                        scaleEnabled: true,
                                        trackpadScrollCausesScale: true,
                                        constrained: false,
                                        clipBehavior: Clip.none,
                                        boundaryMargin:
                                            const EdgeInsets.all(420),
                                        interactionEndFrictionCoefficient:
                                            0.00006,
                                        onInteractionUpdate: (_) {
                                          final currentScale = _zoomController
                                              .value
                                              .getMaxScaleOnAxis();
                                          if ((currentScale - _zoomScale)
                                                      .abs() >
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
                                              color: _receiptBgColor,
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFF0D47A1),
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
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: const [
                                                          Text(
                                                              "Taj Royal Glass Co.",
                                                              style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 16,
                                                                  color: Color(
                                                                      0xFF0D47A1))),
                                                          Text(
                                                              "for Glass & Mirrors Production",
                                                              style: TextStyle(
                                                                  fontSize: 9,
                                                                  color: Color(
                                                                      0xFF0D47A1),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold)),
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
                                                            CrossAxisAlignment
                                                                .end,
                                                        children: const [
                                                          Text(
                                                              "شركة تـاج رويـال",
                                                              style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 18,
                                                                  color: Color(
                                                                      0xFF0D47A1))),
                                                          Text(
                                                              "لتركيب الزجاج والمرايا والبراويز",
                                                              style: TextStyle(
                                                                  fontSize: 9,
                                                                  color: Color(
                                                                      0xFF0D47A1),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold)),
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
                                                        controller:
                                                            _kdController),
                                                    _buildTopBox("Fils | فلس",
                                                        controller:
                                                            _filsController),
                                                    const Spacer(),
                                                    Column(
                                                      children: [
                                                        Container(
                                                          width: 100,
                                                          height: 20,
                                                          decoration: const BoxDecoration(
                                                              color: Color(
                                                                  0xFF0D47A1),
                                                              borderRadius: BorderRadius.only(
                                                                  topLeft: Radius
                                                                      .circular(
                                                                          4),
                                                                  topRight: Radius
                                                                      .circular(
                                                                          4))),
                                                          child: const Center(
                                                              child: Text(
                                                                  "Date / التاريخ",
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize:
                                                                          9,
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
                                                              borderRadius: const BorderRadius
                                                                  .only(
                                                                  bottomLeft: Radius
                                                                      .circular(
                                                                          4),
                                                                  bottomRight: Radius
                                                                      .circular(
                                                                          4))),
                                                          child: TextField(
                                                            controller:
                                                                _dateController,
                                                            textAlign: TextAlign
                                                                .center,
                                                            style: const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold),
                                                            decoration: const InputDecoration(
                                                                isDense: true,
                                                                border:
                                                                    InputBorder
                                                                        .none,
                                                                contentPadding:
                                                                    EdgeInsets.only(
                                                                        top:
                                                                            6)),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(width: 10),
                                                    _buildNoBox(
                                                        controller:
                                                            _noController),
                                                  ],
                                                ),

                                                /// --- CENTER VOUCHER TITLE ---
                                                Container(
                                                  margin: const EdgeInsets
                                                      .symmetric(vertical: 8),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 15,
                                                      vertical: 3),
                                                  decoration: BoxDecoration(
                                                      border: Border.all(
                                                          color: const Color(
                                                              0xFF0D47A1),
                                                          width: 1.5)),
                                                  child: Column(
                                                    children: const [
                                                      Text("سـند قـبـض",
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 12,
                                                              color: Color(
                                                                  0xFF0D47A1))),
                                                      Text("Receipt Voucher",
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 10,
                                                              color: Color(
                                                                  0xFF0D47A1))),
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
                                                    controller:
                                                        _mobileController),

                                                _buildLineField(
                                                    "The sum of K.D.:",
                                                    "مبلغ وقدرة د.ك.:",
                                                    controller: _sumController),

                                                Row(
                                                  children: [
                                                    Expanded(
                                                        child: _buildLineField(
                                                            "On Bank:",
                                                            "على بنك:",
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
                                                    controller:
                                                        _beingForController),

                                                const Spacer(),

                                                /// --- SIGNATURE AREA ---

                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    _buildSignArea(
                                                      "Receiver's Name / اسم المستلم",
                                                      middleChild: SizedBox(
                                                        width: 145,
                                                        height: 25,
                                                        child: TextField(
                                                          controller:
                                                              _receiverNameController,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 9,
                                                            color: Color(
                                                                0xFF0D47A1),
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
                                                          decoration:
                                                              InputDecoration(
                                                            isDense: true,
                                                            border: InputBorder
                                                                .none,
                                                            hintText:
                                                                'Enter name',
                                                            hintStyle: TextStyle(
                                                                fontSize: 8,
                                                                color: Colors
                                                                    .grey[400]),
                                                            contentPadding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    vertical:
                                                                        4),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    _buildSignArea(
                                                      "Signature / التوقيع",
                                                      middleChild: SizedBox(
                                                        height: 25,
                                                        child: _showSignature
                                                            ? Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                  left: 10,
                                                                  bottom: 5,
                                                                ),
                                                                child:
                                                                    Image.asset(
                                                                  'assets/sign.png',
                                                                  fit: BoxFit
                                                                      .contain,
                                                                  alignment:
                                                                      Alignment
                                                                          .centerLeft,
                                                                  errorBuilder: (_,
                                                                          __,
                                                                          ___) =>
                                                                      const SizedBox
                                                                          .shrink(),
                                                                ),
                                                              )
                                                            : const SizedBox
                                                                .shrink(),
                                                      ),
                                                    ),
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
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        const Icon(
                                                            Icons.location_on,
                                                            color: Color(
                                                                0xFF0D47A1),
                                                            size: 24),
                                                        const SizedBox(
                                                            width: 9),
                                                        Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: const [
                                                            Text(
                                                                "الراي - قطعة ١ - شارع ٢٦ - محل ١٣/١١",
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        9.5,
                                                                    color: Color(
                                                                        0xFF0D47A1),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800)),
                                                            Text(
                                                                "Al Rai Block 1 - St. 26 - Shop 11/13",
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        9.5,
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
                                                        FaIcon(
                                                            FontAwesomeIcons
                                                                .instagram,
                                                            color: Color(
                                                                0xFF0D47A1),
                                                            size: 20),
                                                        SizedBox(width: 5),
                                                        Text(
                                                            "stainless_steelvip",
                                                            style: TextStyle(
                                                                fontSize: 11,
                                                                color: Color(
                                                                    0xFF0D47A1),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold)),
                                                      ],
                                                    ),
                                                    Row(
                                                      children: [
                                                        const FaIcon(
                                                            FontAwesomeIcons
                                                                .whatsapp,
                                                            color: Color(
                                                                0xFF0D47A1),
                                                            size: 20),
                                                        const SizedBox(
                                                            width: 5),
                                                        Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: const [
                                                            Text("56540521",
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        13,
                                                                    color: Color(
                                                                        0xFF0D47A1),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold)),
                                                            Text("96952550",
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        13,
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

                            if (!isMobile) ...[
                              const SizedBox(height: 20),

                              /// --- BUTTONS ---

                              Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 15,
                                  runSpacing: 10,
                                  children: [
                                    _buildActionButton(
                                        "Print",
                                        Colors.blue,
                                        () => _runButtonAction(
                                            'Print', _printReceipt)),
                                    _buildActionButton(
                                        "Save PDF",
                                        Colors.green,
                                        () => _runButtonAction(
                                            'Save PDF', _savePdf)),
                                    _buildActionButton(
                                        "Download PDF",
                                        Colors.blueAccent,
                                        () => _runButtonAction(
                                            'Download PDF', _downloadPdf)),
                                    _buildActionButton(
                                        "Share",
                                        Colors.orange,
                                        () => _runButtonAction(
                                            'Share', _sharePdf)),
                                    ElevatedButton.icon(
                                      icon: Icon(
                                        _showSignature
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                        color: Colors.white,
                                      ),
                                      label: Text(
                                        _showSignature
                                            ? 'Signature ON'
                                            : 'Signature OFF',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _showSignature
                                            ? Colors.purple
                                            : Colors.grey[700],
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 28, vertical: 16),
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                      onPressed: () => setState(() =>
                                          _showSignature = !_showSignature),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (_isProcessing)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
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
                            if (!isMobile)
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
            ),
          ],
        ),
      ),
    );
  }

  // Helper Methods (Boxes, Lines, Buttons)

  Widget _buildNoBox({TextEditingController? controller}) {
    final contractCtrl = controller ?? _noController;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 20,
          decoration: const BoxDecoration(
            color: Color(0xFF0D47A1),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
          child: const Center(
            child: Text(
              'No. / رقم',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Container(
          width: 100,
          height: 30,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF0D47A1)),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Center(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _receiptNoController,
              builder: (context, receiptVal, _) {
                return ValueListenableBuilder<TextEditingValue>(
                  valueListenable: contractCtrl,
                  builder: (context, contractVal, _) {
                    final contractPart = contractVal.text.isEmpty
                        ? '----'
                        : 'CT-${contractVal.text}';
                    final receiptPart =
                        receiptVal.text.isEmpty ? '1' : receiptVal.text;
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$contractPart / R$receiptPart',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D47A1),
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

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
                  border: InputBorder.none,
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF0D47A1), width: 1),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: Color(0xFF0D47A1), width: 1.5),
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

  Widget _buildSignArea(String label, {Widget? middleChild}) {
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
        middleChild ?? const SizedBox(height: 25),
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
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        elevation: 2,
        shadowColor: color.withOpacity(0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.3,
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
