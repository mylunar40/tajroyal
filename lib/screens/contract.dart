import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui; // ← yeh zaroori hai
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // ← kIsWeb ke liye
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart'; // ← yeh add karo
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:translator/translator.dart';
import '../services/browser_file_download.dart';
import '../widgets/sidebar.dart';
import '../services/data_service.dart';

class Contract extends StatefulWidget {
  const Contract({super.key, this.initialHistoryIndex});

  final int? initialHistoryIndex;

  @override
  State<Contract> createState() => _ContractState();
}

class _NewContractIntent extends Intent {
  const _NewContractIntent();
}

class _SaveContractIntent extends Intent {
  const _SaveContractIntent();
}

class _ContractState extends State<Contract> {
  Future<void> _loadStampAndSignImages() async {
    try {
      final stampData = await rootBundle.load('assets/stamp.png');
      _stampImage = pw.MemoryImage(stampData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Failed to load stamp.png: $e');
      _stampImage = null;
    }

    try {
      final signData = await rootBundle.load('assets/sign.png');
      _signImage = pw.MemoryImage(signData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Failed to load sign.png: $e');
      _signImage = null;
    }
  }

  // Signature & Stamp Images
  pw.MemoryImage? _stampImage;
  pw.MemoryImage? _signImage;
  static const String _leftQrUrl =
      'https://www.instagram.com/royalglasscompany';
  static const String _rightQrUrl =
      'https://www.instagram.com/stainless_steelvip';
  static const List<String> _paymentPrefixesEn = [
    'Grand Total:',
    'First Payment:',
    'Second Payment:',
    'Third Payment:',
    'Last Payment:',
  ];
  static const List<String> _paymentPrefixesAr = [
    'إجمالي المبلغ:',
    'الدفعة الأولى:',
    'الدفعة الثانية:',
    'الدفعة الثالثة:',
    'الدفعة الأخيرة:',
  ];

  // ON/OFF switch for showing sign/stamp
  bool showSignStamp = false;

  TextEditingController content = TextEditingController();
  final TextEditingController _historySearchController =
      TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final List<TextEditingController> _paymentValueControllersEn =
      List.generate(5, (_) => TextEditingController());
  final List<FocusNode> _paymentFocusNodesEn =
      List.generate(5, (_) => FocusNode());
  final TextEditingController _nameArabicController = TextEditingController();
  final TextEditingController _mobileArabicController = TextEditingController();
  final TextEditingController _addressArabicController =
      TextEditingController();
  final TextEditingController _descriptionArabicController =
      TextEditingController();
  final List<TextEditingController> _paymentValueControllersAr =
      List.generate(5, (_) => TextEditingController());
  final List<FocusNode> _paymentFocusNodesAr =
      List.generate(5, (_) => FocusNode());

  final GoogleTranslator _translator = GoogleTranslator();
  final Map<TextEditingController, Timer> _translationDebouncers = {};
  final Map<TextEditingController, VoidCallback> _translationListeners = {};
  int? _editingContractIndex;
  final GlobalKey _contractBoundaryKey = GlobalKey();

  Uint8List? _cachedPdfBytes;
  String _cachedPdfKey = '';
  bool _isProcessing = false;
  bool _isWarmingUp = false;
  Timer? _warmupDebounce;
  static const Duration _warmupDebounceDelay = Duration(milliseconds: 1200);
  static const Duration _warmupRetryDelay = Duration(milliseconds: 700);
  bool _isSyncingPaymentValues = false;
  final List<VoidCallback> _paymentAutoFillListeners = [];
  final TransformationController _pageZoomController =
      TransformationController();
  static const double _a4PageWidth = 595;
  static const double _a4PageHeight = 841.89;
  static const double _minPageScale = 0.35;
  static const double _maxPageScale = 3.0;
  static const double _pageZoomStep = 0.2;
  double _pageScale = 1.0;
  Size? _zoomViewportSize;
  TextEditingController? _activeTextController;
  final Map<TextEditingController, double> _fieldFontSizes = {};
  final Map<TextEditingController, bool> _fieldBoldStates = {};
  final Map<TextEditingController, bool> _fieldItalicStates = {};
  final Map<TextEditingController, bool> _fieldUnderlineStates = {};
  final Map<TextEditingController, String> _fieldFontStyles = {};
  static const List<String> _fontStyleOptions = <String>[
    'Roboto',
    'Poppins',
    'Lato',
    'Merriweather',
  ];

  late String _contractDateTime;
  late String _contractNumber;
  pw.Font arabicFont =
      pw.Font.helvetica(); // Safe default for fallback PDF path.

  TextStyle _arabicTextStyle({
    double fontSize = 10,
    FontWeight fontWeight = FontWeight.w600,
    FontStyle fontStyle = FontStyle.normal,
    TextDecoration decoration = TextDecoration.none,
    Color color = Colors.black,
    double height = 1.1,
  }) {
    return GoogleFonts.notoNaskhArabic(
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      decoration: decoration,
      color: color,
      height: height,
    );
  }

  void _setActiveField(TextEditingController controller) {
    if (_activeTextController == controller) {
      return;
    }

    if (mounted) {
      setState(() {
        _activeTextController = controller;
      });
    } else {
      _activeTextController = controller;
    }
  }

  TextStyle _editableFieldStyle(
    TextEditingController controller, {
    required double fallbackSize,
    required FontWeight fallbackWeight,
    Color color = Colors.black,
  }) {
    final size = _fieldFontSizes[controller] ?? fallbackSize;
    final isBold = _fieldBoldStates[controller] ??
        (fallbackWeight.index >= FontWeight.w600.index);
    final isItalic = _fieldItalicStates[controller] ?? false;
    final isUnderline = _fieldUnderlineStates[controller] ?? false;
    final style = _fieldFontStyles[controller] ?? 'Roboto';
    final weight = isBold ? FontWeight.w700 : FontWeight.w500;

    switch (style) {
      case 'Poppins':
        return GoogleFonts.poppins(
          fontSize: size,
          fontWeight: weight,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          decoration:
              isUnderline ? TextDecoration.underline : TextDecoration.none,
          color: color,
        );
      case 'Lato':
        return GoogleFonts.lato(
          fontSize: size,
          fontWeight: weight,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          decoration:
              isUnderline ? TextDecoration.underline : TextDecoration.none,
          color: color,
        );
      case 'Merriweather':
        return GoogleFonts.merriweather(
          fontSize: size,
          fontWeight: weight,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          decoration:
              isUnderline ? TextDecoration.underline : TextDecoration.none,
          color: color,
        );
      case 'Roboto':
      default:
        return GoogleFonts.roboto(
          fontSize: size,
          fontWeight: weight,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          decoration:
              isUnderline ? TextDecoration.underline : TextDecoration.none,
          color: color,
        );
    }
  }

  TextStyle _editableArabicFieldStyle(
    TextEditingController controller, {
    required double fallbackSize,
    required FontWeight fallbackWeight,
    Color color = Colors.black,
  }) {
    final size = _fieldFontSizes[controller] ?? fallbackSize;
    final isBold = _fieldBoldStates[controller] ??
        (fallbackWeight.index >= FontWeight.w600.index);
    final isItalic = _fieldItalicStates[controller] ?? false;
    final isUnderline = _fieldUnderlineStates[controller] ?? false;

    return _arabicTextStyle(
      fontSize: size,
      fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
      fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
      color: color,
    );
  }

  void _changeSelectedFontSize(double delta) {
    final controller = _activeTextController;
    if (controller == null) {
      return;
    }

    setState(() {
      final current = _fieldFontSizes[controller] ?? 10;
      _fieldFontSizes[controller] = (current + delta).clamp(8, 24).toDouble();
    });
  }

  void _toggleSelectedBold() {
    final controller = _activeTextController;
    if (controller == null) {
      return;
    }

    setState(() {
      final current = _fieldBoldStates[controller] ?? false;
      _fieldBoldStates[controller] = !current;
    });
  }

  void _toggleSelectedItalic() {
    final controller = _activeTextController;
    if (controller == null) {
      return;
    }

    setState(() {
      final current = _fieldItalicStates[controller] ?? false;
      _fieldItalicStates[controller] = !current;
    });
  }

  void _toggleSelectedUnderline() {
    final controller = _activeTextController;
    if (controller == null) {
      return;
    }

    setState(() {
      final current = _fieldUnderlineStates[controller] ?? false;
      _fieldUnderlineStates[controller] = !current;
    });
  }

  void _setSelectedFontStyle(String style) {
    final controller = _activeTextController;
    if (controller == null) {
      return;
    }

    setState(() {
      _fieldFontStyles[controller] = style;
    });
  }

  void _resetSelectedTextStyle() {
    final controller = _activeTextController;
    if (controller == null) {
      return;
    }

    setState(() {
      _fieldFontSizes.remove(controller);
      _fieldBoldStates.remove(controller);
      _fieldItalicStates.remove(controller);
      _fieldUnderlineStates.remove(controller);
      _fieldFontStyles.remove(controller);
    });
  }

  Widget _buildTypographyRibbon({bool compact = false}) {
    final selected = _activeTextController;
    final hasSelection = selected != null;
    final currentSize =
        selected != null ? (_fieldFontSizes[selected] ?? 10) : 10;
    final currentBold =
        selected != null ? (_fieldBoldStates[selected] ?? false) : false;
    final currentItalic =
        selected != null ? (_fieldItalicStates[selected] ?? false) : false;
    final currentUnderline =
        selected != null ? (_fieldUnderlineStates[selected] ?? false) : false;
    final currentStyle =
        selected != null ? (_fieldFontStyles[selected] ?? 'Roboto') : 'Roboto';
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
            isEnabled: hasSelection,
            onTap: () => _changeSelectedFontSize(-1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              currentSize.toStringAsFixed(0),
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
            isEnabled: hasSelection,
            onTap: () => _changeSelectedFontSize(1),
          ),
          const SizedBox(height: 6),
          _ribbonControlButton(
            icon: Icons.format_bold,
            tooltip: currentBold ? 'Set normal' : 'Set bold',
            isActive: currentBold,
            isEnabled: hasSelection,
            padding: buttonPadding,
            onTap: _toggleSelectedBold,
          ),
          const SizedBox(height: 4),
          _ribbonControlButton(
            icon: Icons.format_italic,
            tooltip: currentItalic ? 'Set normal' : 'Set italic',
            isActive: currentItalic,
            isEnabled: hasSelection,
            padding: buttonPadding,
            onTap: _toggleSelectedItalic,
          ),
          const SizedBox(height: 4),
          _ribbonControlButton(
            icon: Icons.format_underline,
            tooltip: currentUnderline ? 'Remove underline' : 'Underline text',
            isActive: currentUnderline,
            isEnabled: hasSelection,
            padding: buttonPadding,
            onTap: _toggleSelectedUnderline,
          ),
          const SizedBox(height: 4),
          PopupMenuButton<String>(
            tooltip: hasSelection ? 'Font style' : 'Select a text field first',
            enabled: hasSelection,
            initialValue: currentStyle,
            icon: Icon(
              Icons.text_fields,
              size: 18,
              color:
                  hasSelection ? const Color(0xFF0D47A1) : Colors.grey.shade500,
            ),
            onSelected: _setSelectedFontStyle,
            itemBuilder: (context) => _fontStyleOptions
                .map((font) => PopupMenuItem<String>(
                      value: font,
                      child: Text(font),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          _ribbonControlButton(
            icon: Icons.refresh,
            tooltip: 'Reset selected text style',
            isEnabled: hasSelection,
            padding: buttonPadding,
            onTap: _resetSelectedTextStyle,
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
    bool isEnabled = true,
  }) {
    final activeColor = const Color(0xFF0D47A1);
    final inactiveColor = Colors.grey.shade500;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isEnabled ? onTap : null,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isActive
                ? activeColor
                : (isEnabled ? Colors.white : Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: activeColor.withValues(alpha: 0.28)),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive
                ? Colors.white
                : (isEnabled ? activeColor : inactiveColor),
          ),
        ),
      ),
    );
  }

  String _currentPdfDataKey() {
    return [
      content.text,
      _nameController.text,
      _nameArabicController.text,
      _mobileController.text,
      _mobileArabicController.text,
      _addressController.text,
      _addressArabicController.text,
      _descriptionController.text,
      _descriptionArabicController.text,
      _paymentDetailsValueKey(_paymentValueControllersEn),
      _paymentDetailsValueKey(_paymentValueControllersAr),
    ].join('|');
  }

  void _updateZoomViewport(Size nextSize) {
    if (_zoomViewportSize == nextSize) {
      return;
    }
    _zoomViewportSize = nextSize;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _setPageScale(_pageScale);
    });
  }

  void _setPageScale(double scale) {
    final viewport = _zoomViewportSize;
    if (viewport == null) {
      return;
    }

    final clamped = scale.clamp(_minPageScale, _maxPageScale).toDouble();
    final dx = (viewport.width - (_a4PageWidth * clamped)) / 2;
    final dy = (viewport.height - (_a4PageHeight * clamped)) / 2;

    _pageZoomController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(clamped, clamped, 1, 1);

    if ((_pageScale - clamped).abs() > 0.0001 && mounted) {
      setState(() {
        _pageScale = clamped;
      });
    } else {
      _pageScale = clamped;
    }
  }

  void _zoomInPage() {
    _setPageScale(_pageScale + _pageZoomStep);
  }

  void _zoomOutPage() {
    _setPageScale(_pageScale - _pageZoomStep);
  }

  void _resetPageZoom() {
    _setPageScale(1.0);
  }

  String _paymentDetailsValueKey(List<TextEditingController> controllers) {
    return controllers.map((controller) => controller.text.trim()).join('|');
  }

  static final TextInputFormatter _paymentAmountFormatter =
      TextInputFormatter.withFunction((oldValue, newValue) {
    final value = newValue.text;
    if (value.isEmpty) {
      return newValue;
    }

    final validAmount = RegExp(r'^\d*\.?\d{0,2}$');
    return validAmount.hasMatch(value) ? newValue : oldValue;
  });

  TextInputAction _paymentInputActionForIndex(int index) {
    return index == _paymentValueControllersEn.length - 1
        ? TextInputAction.done
        : TextInputAction.next;
  }

  void _handlePaymentSubmitted({
    required List<FocusNode> focusNodes,
    required int index,
  }) {
    if (index >= focusNodes.length - 1) {
      focusNodes[index].unfocus();
      return;
    }

    FocusScope.of(context).requestFocus(focusNodes[index + 1]);
  }

  void _resetPaymentDetailsValues() {
    for (final controller in _paymentValueControllersEn) {
      controller.clear();
    }
    for (final controller in _paymentValueControllersAr) {
      controller.clear();
    }
  }

  void _syncPaymentEnglishToArabic(int index) {
    if (_isSyncingPaymentValues) {
      return;
    }
    if (index < 0 || index >= _paymentValueControllersEn.length) {
      return;
    }

    _isSyncingPaymentValues = true;
    try {
      final value = _paymentValueControllersEn[index].text;
      if (_paymentValueControllersAr[index].text != value) {
        _paymentValueControllersAr[index].text = value;
      }
    } finally {
      _isSyncingPaymentValues = false;
    }
  }

  void _setupPaymentAutoFill() {
    for (var i = 0; i < _paymentValueControllersEn.length; i++) {
      final index = i;
      void listener() => _syncPaymentEnglishToArabic(index);
      _paymentAutoFillListeners.add(listener);
      _paymentValueControllersEn[index].addListener(listener);
      _syncPaymentEnglishToArabic(index);
    }
  }

  void _attachAutoTranslation(
    TextEditingController source,
    TextEditingController target,
  ) {
    void listener() {
      _translationDebouncers[source]?.cancel();
      _translationDebouncers[source] =
          Timer(const Duration(milliseconds: 350), () async {
        await _translateSourceToArabic(source: source, target: target);
      });
    }

    _translationListeners[source] = listener;
    source.addListener(listener);
  }

  Future<void> _translateSourceToArabic({
    required TextEditingController source,
    required TextEditingController target,
  }) async {
    final raw = source.text.trim();

    if (raw.isEmpty) {
      if (target.text.isNotEmpty) {
        target.text = '';
        _onContractChanged();
      }
      return;
    }

    try {
      final translated = await _translator.translate(raw, to: 'ar');
      if (!mounted) return;

      final nextValue = translated.text.trim();
      if (nextValue.isNotEmpty && target.text != nextValue) {
        target.text = nextValue;
        _onContractChanged();
      }
    } catch (_) {
      // Keep previous Arabic value if translation fails temporarily.
    }
  }

  void _invalidatePdfCache() {
    _cachedPdfBytes = null;
    _cachedPdfKey = '';
  }

  void _onContractChanged() {
    _invalidatePdfCache();
  }

  void _schedulePdfWarmup() {
    if (kIsWeb) {
      // Keep web editors smooth; build PDF only when user explicitly asks.
      return;
    }

    _warmupDebounce?.cancel();
    _warmupDebounce = Timer(_warmupDebounceDelay, () {
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

  Future<void> _warmupPdfCache() async {
    if (_isWarmingUp) return;
    _isWarmingUp = true;

    try {
      final currentKey = _currentPdfDataKey();
      if (_cachedPdfBytes != null && _cachedPdfKey == currentKey) {
        return;
      }

      final bytes = await _buildDirectPdfBytes();
      _cachedPdfBytes = bytes;
      _cachedPdfKey = currentKey;
    } catch (_) {
      // Keep UI responsive; runtime actions still have fallback path.
    } finally {
      _isWarmingUp = false;
    }
  }

  Future<void> _runButtonAction(
      String actionName, Future<void> Function() action) async {
    if (_isProcessing) {
      debugPrint('[$actionName] Already processing, ignoring request');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      debugPrint('[$actionName] Starting...');
      await action().timeout(const Duration(seconds: 20));
      debugPrint('[$actionName] Completed successfully');
    } on TimeoutException {
      debugPrint('[$actionName] Timeout after 20 seconds');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$actionName is taking too long. Try again.')),
        );
      }
    } catch (e) {
      debugPrint('[$actionName] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$actionName failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // ─── Web-safe direct PDF (no image capture needed) ──────────────────────────
  Future<Uint8List> generatePdf_OLD() async {
    final pdf = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      final logoData = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) {
          return pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Contract Paper',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (logoImage != null)
                      pw.Container(
                        width: 46,
                        height: 46,
                        child: pw.Image(logoImage),
                      ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Divider(),
                pw.Text('Name: ${_nameController.text}'),
                pw.Text('Mobile: ${_mobileController.text}'),
                pw.Text('Address: ${_addressController.text}'),
                pw.SizedBox(height: 10),
                pw.Text('Description:'),
                pw.Text(_descriptionController.text),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Grand Total: ${_paymentValueControllersEn[0].text.isEmpty ? '0' : _paymentValueControllersEn[0].text}',
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> _buildDirectPdfBytes() async {
    final pdf = pw.Document();
    final af = arabicFont;

    String v(TextEditingController c) => c.text.trim();

    pw.Widget infoRow(
        String enLabel, String arLabel, String enVal, String arVal) {
      return pw.Row(
        children: [
          pw.Expanded(
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(enLabel,
                      style: const pw.TextStyle(
                          fontSize: 7, color: PdfColors.grey700)),
                  pw.Text(enVal.isEmpty ? ' ' : enVal,
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(arLabel,
                      style: pw.TextStyle(
                          font: af, fontSize: 7, color: PdfColors.grey700),
                      textDirection: pw.TextDirection.rtl),
                  pw.Text(arVal.isEmpty ? ' ' : arVal,
                      style: pw.TextStyle(
                          font: af,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold),
                      textDirection: pw.TextDirection.rtl),
                ],
              ),
            ),
          ),
        ],
      );
    }

    pw.Widget descriptionRow(
        String enLabel, String arLabel, String enVal, String arVal) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              height: 120,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(enLabel,
                      style: const pw.TextStyle(
                          fontSize: 7, color: PdfColors.grey700)),
                  pw.SizedBox(height: 4),
                  pw.Text(enVal.isEmpty ? ' ' : enVal,
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              constraints: const pw.BoxConstraints(minHeight: 100),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(arLabel,
                      style: pw.TextStyle(
                          font: af, fontSize: 7, color: PdfColors.grey700),
                      textDirection: pw.TextDirection.rtl),
                  pw.SizedBox(height: 4),
                  pw.Text(arVal.isEmpty ? ' ' : arVal,
                      style: pw.TextStyle(
                          font: af,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold),
                      textDirection: pw.TextDirection.rtl),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final List<(String en, String ar, String val)> payments = [
      (
        'Grand Total',
        'إجمالي المبلغ',
        v(_paymentValueControllersEn[0]).isEmpty
            ? '0'
            : v(_paymentValueControllersEn[0])
      ),
      (
        'First Payment',
        'الدفعة الأولى',
        v(_paymentValueControllersEn[1]).isEmpty
            ? '0'
            : v(_paymentValueControllersEn[1])
      ),
      (
        'Second Payment',
        'الدفعة الثانية',
        v(_paymentValueControllersEn[2]).isEmpty
            ? '0'
            : v(_paymentValueControllersEn[2])
      ),
      (
        'Third Payment',
        'الدفعة الثالثة',
        v(_paymentValueControllersEn[3]).isEmpty
            ? '0'
            : v(_paymentValueControllersEn[3])
      ),
      (
        'Last Payment',
        'الدفعة الأخيرة',
        v(_paymentValueControllersEn[4]).isEmpty
            ? '0'
            : v(_paymentValueControllersEn[4])
      ),
    ];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (ctx) {
          return pw.Container(
            width: PdfPageFormat.a4.width,
            height: PdfPageFormat.a4.height,
            child: pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              child: pw.Column(
                children: [
                  // ── HEADER ──────────────────────────────────────────────────────
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Taj Royal Glass Co.',
                                style: pw.TextStyle(
                                    fontSize: 14,
                                    fontWeight: pw.FontWeight.bold)),
                            pw.Text('Mirror and Glass Manufacturing Factory',
                                style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 16),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('شركة تاج رويال الزجاج',
                                style: pw.TextStyle(
                                    font: af,
                                    fontSize: 14,
                                    fontWeight: pw.FontWeight.bold),
                                textDirection: pw.TextDirection.rtl),
                            pw.Text('لتركيب الزجاج والمرايا والبراويز',
                                style: pw.TextStyle(font: af, fontSize: 8),
                                textDirection: pw.TextDirection.rtl),
                          ],
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColors.black, thickness: 1),
                  pw.SizedBox(height: 4),

                  // ── DATE / TITLE / CONTRACT NO ──────────────────────────────────
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: pw.BoxDecoration(border: pw.Border.all()),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Date / التاريخ',
                                style: const pw.TextStyle(
                                    fontSize: 7, color: PdfColors.grey700)),
                            pw.Text(_contractDateTime.trim(),
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        decoration: pw.BoxDecoration(border: pw.Border.all()),
                        child: pw.Column(
                          children: [
                            pw.Text('عقد إتفاق',
                                style: pw.TextStyle(
                                    font: af,
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold),
                                textDirection: pw.TextDirection.rtl),
                            pw.Text('Contract Paper',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: pw.BoxDecoration(border: pw.Border.all()),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('Contract No. / رقم العقد',
                                style: const pw.TextStyle(
                                    fontSize: 7, color: PdfColors.grey700)),
                            pw.Text(_contractNumber.trim(),
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 8),

                  // ── INFO ROWS ────────────────────────────────────────────────────
                  infoRow('Name', 'الاسم', v(_nameController),
                      v(_nameArabicController)),
                  pw.SizedBox(height: 4),
                  infoRow('Mobile', 'الهاتف', v(_mobileController),
                      v(_mobileArabicController)),
                  pw.SizedBox(height: 4),
                  infoRow('Address', 'العنوان', v(_addressController),
                      v(_addressArabicController)),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    height: 140,
                    child: descriptionRow(
                        'Description',
                        'الوصف',
                        v(_descriptionController),
                        v(_descriptionArabicController)),
                  ),

                  pw.SizedBox(height: 10),

                  // ── PAYMENT TABLE ────────────────────────────────────────────────
                  pw.Container(
                    height: 140,
                    child: pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.black),
                      columnWidths: const {
                        0: pw.FlexColumnWidth(3),
                        1: pw.FlexColumnWidth(2),
                        2: pw.FlexColumnWidth(3),
                      },
                      children: [
                        pw.TableRow(
                          decoration:
                              const pw.BoxDecoration(color: PdfColors.grey300),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text('Payment',
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text('Amount',
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text('الدفعة',
                                  style: pw.TextStyle(
                                      font: af,
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold),
                                  textDirection: pw.TextDirection.rtl),
                            ),
                          ],
                        ),
                        for (final p in payments)
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(p.$1,
                                  style: const pw.TextStyle(fontSize: 9)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(p.$3,
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(p.$2,
                                  style: pw.TextStyle(font: af, fontSize: 9),
                                  textDirection: pw.TextDirection.rtl),
                            ),
                          ]),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 16),

                  // ── SIGNATURES ───────────────────────────────────────────────────
                  if (showSignStamp &&
                      (_signImage != null || _stampImage != null))
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('Authorized Signature / التوقيع المعتمد',
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold)),
                              pw.SizedBox(height: 4),
                              if (_signImage != null)
                                pw.Image(_signImage!, width: 80, height: 40),
                              pw.SizedBox(height: 4),
                              pw.Container(height: 1, color: PdfColors.black),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 30),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text('Stamp / الختم',
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold)),
                              pw.SizedBox(height: 4),
                              if (_stampImage != null)
                                pw.Image(_stampImage!, width: 50, height: 50),
                              pw.SizedBox(height: 4),
                              pw.Container(height: 1, color: PdfColors.black),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('Authorized Signature / التوقيع المعتمد',
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold)),
                              pw.SizedBox(height: 18),
                              pw.Container(height: 1, color: PdfColors.black),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 30),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text('Customer Signature / توقيع العميل',
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold)),
                              pw.SizedBox(height: 18),
                              pw.Container(height: 1, color: PdfColors.black),
                            ],
                          ),
                        ),
                      ],
                    ),

                  pw.SizedBox(height: 8),
                  pw.Divider(color: PdfColors.black, thickness: 1.5),
                  pw.SizedBox(height: 4),

                  // ── FOOTER ───────────────────────────────────────────────────────
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Text(
                            'الكويت - الراي - قطعة ١ - قسيمة ٢٦ - مبنى ١٤١٩',
                            style: pw.TextStyle(font: af, fontSize: 9),
                            textDirection: pw.TextDirection.rtl),
                        pw.Text(
                            'Kuwait - Al Rai Block 1 - Street 26 - Building 1419',
                            style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('96952550 - 98532064 - 56540521',
                            style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> _getContractPdfBytes() async {
    final currentKey = _currentPdfDataKey();
    if (_cachedPdfBytes != null && _cachedPdfKey == currentKey) {
      return _cachedPdfBytes!;
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await Future.delayed(const Duration(milliseconds: 300));
        await WidgetsBinding.instance.endOfFrame;

        final boundary = _contractBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;

        if (boundary == null) {
          continue;
        }

        if (boundary.debugNeedsPaint) {
          await Future.delayed(const Duration(milliseconds: 60));
          await WidgetsBinding.instance.endOfFrame;
        }

        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          throw Exception("Image conversion failed");
        }

        final pngBytes = byteData.buffer.asUint8List();
        final pdf = pw.Document();
        final imagePdf = pw.MemoryImage(pngBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(imagePdf, fit: pw.BoxFit.fill),
          ),
        );

        final bytes = await pdf.save();
        _cachedPdfBytes = bytes;
        _cachedPdfKey = currentKey;
        return bytes;
      } catch (_) {
        // Retry capture; if all attempts fail, use structured fallback below.
      }
    }

    final bytes = await _buildDirectPdfBytes();
    _cachedPdfBytes = bytes;
    _cachedPdfKey = currentKey;
    return bytes;
  }
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _printContract() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      await WidgetsBinding.instance.endOfFrame;

      final boundary = _contractBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception("UI not ready");
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception("Image conversion failed");
      }

      final pngBytes = byteData.buffer.asUint8List();

      final pdf = pw.Document();
      final imagePdf = pw.MemoryImage(pngBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(imagePdf, fit: pw.BoxFit.fill),
        ),
      );

      await Printing.layoutPdf(onLayout: (_) async => pdf.save());
    } catch (e) {
      debugPrint("PRINT ERROR: $e");
    }
  }

  Future<void> _saveContractOnly() async {
    final contractName = _buildContractName();
    final contractDate = _formatAutoDateTime(DateTime.now());

    _saveContractHistory(
      name: contractName,
      date: contractDate,
      body: content.text,
    );

    if (mounted) {
      setState(() {
        _editingContractIndex = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to history')),
      );
    }
  }

  Future<void> _downloadPdf() async {
    try {
      debugPrint('DOWNLOADING DIRECT PDF');
      final bytes = await _buildDirectPdfBytes();
      final now = DateTime.now();
      final name =
          'contract_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf';

      if (kIsWeb) {
        await downloadPdfBytes(bytes, name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF download started')),
          );
        }
        return;
      }

      final downloadDir = await getDownloadsDirectory();
      final fallbackDir = await getApplicationDocumentsDirectory();
      final targetDir = downloadDir ?? fallbackDir;
      final file = File('${targetDir.path}/$name');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded to: ${file.path}')),
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

  Future<void> downloadContractPDF({
    required BuildContext context,
    required GlobalKey repaintKey,
  }) async {
    try {
      final boundary = repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Contract preview is not ready yet');
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Could not render contract image');
      }

      final pngBytes = byteData.buffer.asUint8List();
      final pdf = pw.Document();
      final pdfImage = pw.MemoryImage(pngBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) {
            return pw.Center(
              child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
            );
          },
        ),
      );

      final bytes = await pdf.save();

      final now = DateTime.now();
      final name =
          'contract_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf';

      if (kIsWeb) {
        await downloadPdfBytes(bytes, name);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF download started')),
          );
        }
        return;
      }

      final downloadDir = await getDownloadsDirectory();
      final fallbackDir = await getApplicationDocumentsDirectory();
      final targetDir = downloadDir ?? fallbackDir;
      final file = File('${targetDir.path}/$name');
      await file.writeAsBytes(bytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded to: ${file.path}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> downloadContractFromServer() async {
    await downloadContractPDF(
      context: context,
      repaintKey: _contractBoundaryKey,
    );
  }

  // ...existing code...

  String _buildContractName() {
    final trimmed = content.text.trim();
    if (trimmed.isEmpty) {
      return 'Contract';
    }

    final firstLine = trimmed.split('\n').first.trim();
    if (firstLine.isEmpty) {
      return 'Contract';
    }

    return firstLine.length > 35
        ? '${firstLine.substring(0, 35)}...'
        : firstLine;
  }

  String _formatAutoDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  void _saveContractHistory({
    required String name,
    required String date,
    required String body,
  }) {
    final entry = <String, dynamic>{
      'name': name,
      'date': date,
      'content': body,
      'payment_en': _paymentValueControllersEn
          .map((controller) => controller.text)
          .toList(),
      'payment_ar': _paymentValueControllersAr
          .map((controller) => controller.text)
          .toList(),
    };

    final editingIndex = _editingContractIndex;
    if (editingIndex != null &&
        editingIndex >= 0 &&
        editingIndex < DataService.contracts.length) {
      DataService.contracts[editingIndex] = entry;
      return;
    }

    DataService.contracts.add(entry);
  }

  void _deleteContractHistoryEntry(int sourceIndex) {
    if (sourceIndex < 0 || sourceIndex >= DataService.contracts.length) {
      return;
    }

    DataService.contracts.removeAt(sourceIndex);
  }

  List<Map<String, dynamic>> _filteredContracts() {
    final query = _historySearchController.text.trim().toLowerCase();
    final source = DataService.contracts.reversed.toList();

    if (query.isEmpty) {
      return source;
    }
    return source.where((contract) {
      final name = (contract['name'] ?? '').toString().toLowerCase();
      final date = (contract['date'] ?? '').toString().toLowerCase();
      final body = (contract['content'] ?? '').toString().toLowerCase();
      return name.contains(query) ||
          date.contains(query) ||
          body.contains(query);
    }).toList();
  }

  void _loadContractFromHistory(Map<String, dynamic> contract, {int? index}) {
    final paymentEn = (contract['payment_en'] as List?)
            ?.map((value) => value?.toString() ?? '')
            .toList() ??
        const <String>[];
    final paymentAr = (contract['payment_ar'] as List?)
            ?.map((value) => value?.toString() ?? '')
            .toList() ??
        const <String>[];

    setState(() {
      _editingContractIndex = index;
      content.text = (contract['content'] ?? '').toString();
      for (var i = 0; i < _paymentValueControllersEn.length; i++) {
        _paymentValueControllersEn[i].text =
            i < paymentEn.length ? paymentEn[i] : '';
      }
      for (var i = 0; i < _paymentValueControllersAr.length; i++) {
        _paymentValueControllersAr[i].text =
            i < paymentAr.length ? paymentAr[i] : '';
      }
    });
  }

  void _startNewContract() {
    setState(() {
      _editingContractIndex = null;
      content.clear();
      _resetPaymentDetailsValues();
    });
  }

  Future<void> _deleteContractFromHistory(int sourceIndex) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Contract'),
            content:
                const Text('Are you sure you want to delete this contract?'),
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
      _deleteContractHistoryEntry(sourceIndex);
      if (_editingContractIndex == sourceIndex) {
        _editingContractIndex = null;
      } else if (_editingContractIndex != null &&
          _editingContractIndex! > sourceIndex) {
        _editingContractIndex = _editingContractIndex! - 1;
      }
    });
  }

  Widget _buildHistoryPanel({double width = 300}) {
    final contracts = _filteredContracts();

    return Container(
      width: width,
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contract History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 10),
          if (_editingContractIndex != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF0D47A1).withValues(alpha: 0.2)),
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
                    onPressed: _startNewContract,
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
                    hintText: 'Search by name or date/time',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildTypographyRibbon(),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: contracts.isEmpty
                ? const Center(
                    child: Text(
                      'No contracts found',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : ListView.separated(
                    itemCount: contracts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final contract = contracts[index];
                      final sourceIndex =
                          DataService.contracts.indexOf(contract);
                      final preview = (contract['content'] ?? '').toString();

                      return InkWell(
                        onTap: sourceIndex >= 0
                            ? () => _loadContractFromHistory(contract,
                                index: sourceIndex)
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
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
                                (contract['name'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0D47A1),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                  'Date: ${(contract['date'] ?? '-').toString()}'),
                              const SizedBox(height: 3),
                              Text(
                                preview.isEmpty ? 'No content' : preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black87),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: sourceIndex >= 0
                                        ? () => _loadContractFromHistory(
                                            contract,
                                            index: sourceIndex)
                                        : null,
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('Edit'),
                                  ),
                                  const SizedBox(width: 4),
                                  TextButton.icon(
                                    onPressed: sourceIndex >= 0
                                        ? () => _deleteContractFromHistory(
                                            sourceIndex)
                                        : null,
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 16,
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

  @override
  void initState() {
    super.initState();
    rootBundle
        .load("assets/fonts/NotoNaskhArabic-Regular.ttf")
        .then((fontData) {
      arabicFont = pw.Font.ttf(fontData);
    }).catchError((e) {
      debugPrint('Arabic font loading error: $e (using fallback)');
      arabicFont = pw.Font.helvetica();
    });
    _setupPaymentAutoFill();
    content.addListener(_onContractChanged);
    _nameController.addListener(_onContractChanged);
    _mobileController.addListener(_onContractChanged);
    _addressController.addListener(_onContractChanged);
    _descriptionController.addListener(_onContractChanged);
    for (final controller in _paymentValueControllersEn) {
      controller.addListener(_onContractChanged);
    }
    _nameArabicController.addListener(_onContractChanged);
    _mobileArabicController.addListener(_onContractChanged);
    _addressArabicController.addListener(_onContractChanged);
    _descriptionArabicController.addListener(_onContractChanged);
    for (final controller in _paymentValueControllersAr) {
      controller.addListener(_onContractChanged);
    }
    _attachAutoTranslation(
      _nameController,
      _nameArabicController,
    );
    _attachAutoTranslation(
      _mobileController,
      _mobileArabicController,
    );
    _attachAutoTranslation(
      _addressController,
      _addressArabicController,
    );
    _attachAutoTranslation(
      _descriptionController,
      _descriptionArabicController,
    );
    final now = DateTime.now();
    _contractDateTime =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}  '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    _contractNumber = 'CT-0001';
    // Load Stamp and Sign images for PDF
    // ignore: unused_local_variable
    var loadStampAndSignImages = _loadStampAndSignImages();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _schedulePdfWarmup();

      final initialIndex = widget.initialHistoryIndex;
      if (initialIndex != null &&
          initialIndex >= 0 &&
          initialIndex < DataService.contracts.length) {
        _loadContractFromHistory(
          DataService.contracts[initialIndex],
          index: initialIndex,
        );
      }
    });
  }

  @override
  void dispose() {
    _warmupDebounce?.cancel();
    content.removeListener(_onContractChanged);
    _nameController.removeListener(_onContractChanged);
    _mobileController.removeListener(_onContractChanged);
    _addressController.removeListener(_onContractChanged);
    _descriptionController.removeListener(_onContractChanged);
    for (final controller in _paymentValueControllersEn) {
      controller.removeListener(_onContractChanged);
    }
    _nameArabicController.removeListener(_onContractChanged);
    _mobileArabicController.removeListener(_onContractChanged);
    _addressArabicController.removeListener(_onContractChanged);
    _descriptionArabicController.removeListener(_onContractChanged);
    for (final controller in _paymentValueControllersAr) {
      controller.removeListener(_onContractChanged);
    }
    for (var i = 0; i < _paymentAutoFillListeners.length; i++) {
      if (i < _paymentValueControllersEn.length) {
        _paymentValueControllersEn[i]
            .removeListener(_paymentAutoFillListeners[i]);
      }
    }
    _paymentAutoFillListeners.clear();
    for (final entry in _translationListeners.entries) {
      entry.key.removeListener(entry.value);
    }
    for (final timer in _translationDebouncers.values) {
      timer.cancel();
    }
    _translationListeners.clear();
    _translationDebouncers.clear();
    content.dispose();
    _historySearchController.dispose();
    _nameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    for (final controller in _paymentValueControllersEn) {
      controller.dispose();
    }
    for (final focusNode in _paymentFocusNodesEn) {
      focusNode.dispose();
    }
    _nameArabicController.dispose();
    _mobileArabicController.dispose();
    _addressArabicController.dispose();
    _descriptionArabicController.dispose();
    for (final controller in _paymentValueControllersAr) {
      controller.dispose();
    }
    for (final focusNode in _paymentFocusNodesAr) {
      focusNode.dispose();
    }
    _pageZoomController.dispose();
    super.dispose();
  }

  Widget _buildSplitInfoBoxRow({
    required String englishLabel,
    required String arabicLabel,
    required TextEditingController controller,
    TextEditingController? mirrorController,
    TextInputType keyboardType = TextInputType.text,
    double rowHeight = 28.4,
    bool premiumStyle = false,
    bool centerTallLabel = false,
    double labelFontSize = 7,
    FontWeight labelFontWeight = FontWeight.w600,
    double valueFontSize = 9,
    FontWeight valueFontWeight = FontWeight.w500,
    bool readOnly = false,
  }) {
    const double centerGap = 5.7; // 2mm at 72dpi equivalent
    const BorderSide borderSide = BorderSide(color: Colors.black, width: 1.2);
    final bool isMultiline = rowHeight > 60;
    final BorderRadius boxRadius = BorderRadius.circular(8);
    final Color boxColor =
        premiumStyle ? const Color(0xFFF8FBFF) : Colors.white;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: rowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                height: double.infinity,
                clipBehavior: premiumStyle ? Clip.antiAlias : Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: boxColor,
                  border: const Border.fromBorderSide(borderSide),
                  borderRadius: boxRadius,
                ),
                child: (isMultiline && centerTallLabel)
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 1),
                          Text(
                            '$englishLabel:',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: labelFontSize,
                              fontWeight: labelFontWeight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              onTap: () => _setActiveField(controller),
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              enabled: true,
                              readOnly: readOnly,
                              maxLines: null,
                              expands: false,
                              textAlign: TextAlign.left,
                              textAlignVertical: TextAlignVertical.top,
                              style: _editableFieldStyle(
                                controller,
                                fallbackSize: valueFontSize,
                                fallbackWeight: valueFontWeight,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: isMultiline
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.center,
                        children: [
                          Text(
                            '$englishLabel: ',
                            style: TextStyle(
                              fontSize: labelFontSize,
                              fontWeight: labelFontWeight,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              onTap: () => _setActiveField(controller),
                              keyboardType: isMultiline
                                  ? TextInputType.multiline
                                  : keyboardType,
                              textInputAction: isMultiline
                                  ? TextInputAction.newline
                                  : TextInputAction.next,
                              enabled: true,
                              readOnly: readOnly,
                              maxLines: isMultiline ? null : 1,
                              expands: false,
                              textAlign: TextAlign.left,
                              textAlignVertical: isMultiline
                                  ? TextAlignVertical.top
                                  : TextAlignVertical.center,
                              style: _editableFieldStyle(
                                controller,
                                fallbackSize: valueFontSize,
                                fallbackWeight: valueFontWeight,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: centerGap),
            Container(
              width: 0,
              color: Colors.transparent,
            ),
            const SizedBox(width: centerGap),
            Expanded(
              child: Container(
                height: double.infinity,
                clipBehavior: premiumStyle ? Clip.antiAlias : Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: boxColor,
                  border: const Border.fromBorderSide(borderSide),
                  borderRadius: boxRadius,
                ),
                child: (isMultiline && centerTallLabel)
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 1),
                          Text(
                            arabicLabel,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: _arabicTextStyle(
                              fontSize: labelFontSize + 1,
                              fontWeight: labelFontWeight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Expanded(
                            child: TextField(
                              controller: mirrorController ?? controller,
                              onTap: () => _setActiveField(
                                mirrorController ?? controller,
                              ),
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              enabled: true,
                              readOnly: readOnly,
                              maxLines: null,
                              expands: false,
                              textAlign: TextAlign.right,
                              textDirection: TextDirection.rtl,
                              textAlignVertical: TextAlignVertical.top,
                              style: _editableArabicFieldStyle(
                                mirrorController ?? controller,
                                fallbackSize: valueFontSize,
                                fallbackWeight: valueFontWeight,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: isMultiline
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: mirrorController ?? controller,
                              onTap: () => _setActiveField(
                                mirrorController ?? controller,
                              ),
                              keyboardType: isMultiline
                                  ? TextInputType.multiline
                                  : keyboardType,
                              textInputAction: isMultiline
                                  ? TextInputAction.newline
                                  : TextInputAction.next,
                              enabled: true,
                              readOnly: readOnly,
                              maxLines: isMultiline ? null : 1,
                              expands: false,
                              textAlign: TextAlign.right,
                              textDirection: TextDirection.rtl,
                              textAlignVertical: isMultiline
                                  ? TextAlignVertical.top
                                  : TextAlignVertical.center,
                              style: _editableArabicFieldStyle(
                                mirrorController ?? controller,
                                fallbackSize: valueFontSize,
                                fallbackWeight: valueFontWeight,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            arabicLabel,
                            textDirection: TextDirection.rtl,
                            style: _arabicTextStyle(
                              fontSize: labelFontSize + 1,
                              fontWeight: labelFontWeight,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentDetailsSplitBox({
    double rowHeight = 136,
    bool premiumStyle = true,
    double titleFontSize = 8.5,
    double valueFontSize = 12.5,
    FontWeight valueFontWeight = FontWeight.w700,
  }) {
    const double centerGap = 6;
    const BorderSide borderSide = BorderSide(color: Colors.black, width: 1.2);
    final BorderRadius boxRadius = BorderRadius.circular(8);
    final Color boxColor =
        premiumStyle ? const Color(0xFFF8FBFF) : Colors.white;

    Widget buildSide({
      required List<String> labels,
      required List<TextEditingController> controllers,
      required bool isArabic,
    }) {
      return Container(
        height: double.infinity,
        clipBehavior: premiumStyle ? Clip.antiAlias : Clip.none,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
        decoration: BoxDecoration(
          color: boxColor,
          border: const Border.fromBorderSide(borderSide),
          borderRadius: boxRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 14,
              child: isArabic
                  ? Text(
                      "تفاصيل الدفع",
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    )
                  : Text(
                      "Payment Details:",
                      textAlign: TextAlign.left,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                children: List.generate(labels.length, (index) {
                  final labelWidget = Expanded(
                    flex: 2,
                    child: Text(
                      labels[index],
                      textAlign: isArabic ? TextAlign.right : TextAlign.left,
                      textDirection:
                          isArabic ? TextDirection.rtl : TextDirection.ltr,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: valueFontSize,
                        fontWeight: valueFontWeight,
                      ),
                    ),
                  );

                  final amountFieldWidget = Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: controllers[index],
                        onTap: () => _setActiveField(controllers[index]),
                        focusNode: isArabic
                            ? _paymentFocusNodesAr[index]
                            : _paymentFocusNodesEn[index],
                        enabled: true,
                        readOnly: false,
                        maxLines: 1,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: _paymentInputActionForIndex(index),
                        inputFormatters: [_paymentAmountFormatter],
                        onSubmitted: (_) => _handlePaymentSubmitted(
                          focusNodes: isArabic
                              ? _paymentFocusNodesAr
                              : _paymentFocusNodesEn,
                          index: index,
                        ),
                        textAlign: TextAlign.right,
                        textAlignVertical: TextAlignVertical.center,
                        style: _editableFieldStyle(
                          controllers[index],
                          fallbackSize: valueFontSize,
                          fallbackWeight: valueFontWeight,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter amount',
                          suffixText: 'KD',
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 0,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(6),
                            ),
                            borderSide: BorderSide(
                              width: 1.5,
                              color: Colors.black54,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(6),
                            ),
                            borderSide: BorderSide(
                              width: 1.5,
                              color: Colors.black,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(6),
                            ),
                            borderSide: BorderSide(width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  );

                  return Expanded(
                    child: Row(
                      textDirection:
                          isArabic ? TextDirection.rtl : TextDirection.ltr,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        labelWidget,
                        const SizedBox(width: 6),
                        amountFieldWidget,
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: rowHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sideWidth = (constraints.maxWidth - centerGap) / 2;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: sideWidth,
                  child: buildSide(
                    labels: _paymentPrefixesEn,
                    controllers: _paymentValueControllersEn,
                    isArabic: false,
                  ),
                ),
                const SizedBox(width: centerGap),
                SizedBox(
                  width: sideWidth,
                  child: buildSide(
                    labels: _paymentPrefixesAr,
                    controllers: _paymentValueControllersAr,
                    isArabic: true,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyP, control: true):
            ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.keyP, meta: true): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _NewContractIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            _NewContractIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _SaveContractIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            _SaveContractIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              _printContract();
              return null;
            },
          ),
          _NewContractIntent: CallbackAction<_NewContractIntent>(
            onInvoke: (intent) {
              _startNewContract();
              return null;
            },
          ),
          _SaveContractIntent: CallbackAction<_SaveContractIntent>(
            onInvoke: (intent) {
              _runButtonAction('Save PDF', _saveContractOnly);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            drawer: isMobile
                ? const Drawer(
                    child: SafeArea(
                      child: Sidebar(currentIndex: 1),
                    ),
                  )
                : null,
            floatingActionButton: isMobile
                ? FloatingActionButton.extended(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => SafeArea(
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.75,
                            child: _buildHistoryPanel(width: double.infinity),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('History'),
                  )
                : null,
            bottomNavigationBar: isMobile
                ? SafeArea(
                    top: false,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildMobileActionButton(
                              'New',
                              Colors.indigo,
                              _startNewContract,
                            ),
                            const SizedBox(width: 8),
                            _buildMobileActionButton(
                              'Print',
                              Colors.blue,
                              _printContract,
                            ),
                            const SizedBox(width: 8),
                            _buildMobileActionButton(
                              'Save PDF',
                              const Color(0xFF249B28),
                              () => _runButtonAction(
                                  'Save PDF', _saveContractOnly),
                            ),
                            const SizedBox(width: 8),
                            _buildMobileActionButton(
                              'Download',
                              Colors.blueAccent,
                              () => _runButtonAction(
                                  'Download PDF', downloadContractFromServer),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.share),
                              label: const Text('Share Contract'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                try {
                                  // 1. Widget capture
                                  final boundary = _contractBoundaryKey
                                          .currentContext!
                                          .findRenderObject()
                                      as RenderRepaintBoundary;
                                  final image =
                                      await boundary.toImage(pixelRatio: 3.0);
                                  final byteData = await image.toByteData(
                                      format: ui.ImageByteFormat.png);
                                  final pngBytes =
                                      byteData!.buffer.asUint8List();

                                  // 2. PDF banao (A4 perfect size)
                                  final pdf = pw.Document();
                                  final pdfImage = pw.MemoryImage(pngBytes);

                                  pdf.addPage(
                                    pw.Page(
                                      pageFormat: PdfPageFormat.a4,
                                      margin: pw.EdgeInsets.zero,
                                      build: (pw.Context context) => pw.Center(
                                          child: pw.Image(pdfImage,
                                              fit: pw.BoxFit.contain)),
                                    ),
                                  );

                                  final pdfBytes = await pdf.save();

                                  final now = DateTime.now();
                                  final fileName =
                                      'taj_royal_contract_ 2${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf';

                                  // 3. Smart logic → Web ya Mobile
                                  if (kIsWeb) {
                                    // Web pe download (tumhara existing function)
                                    await downloadPdfBytes(pdfBytes, fileName);

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              '✅ PDF downloaded! Downloads folder mein jaake share kar sakte ho'),
                                          duration: Duration(seconds: 4),
                                        ),
                                      );
                                    }
                                  } else {
                                    // Mobile pe asli Share Sheet
                                    final output =
                                        await getTemporaryDirectory();
                                    final file =
                                        File("${output.path}/$fileName");
                                    await file.writeAsBytes(pdfBytes);

                                    await Share.shareXFiles(
                                      [XFile(file.path)],
                                      text:
                                          'Taj Royal Glass Co. - Contract Paper',
                                    );

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Share sheet opened ✅')),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  print('Share Error: $e');
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildMobileActionButton(
                              'Zoom -',
                              Colors.teal,
                              _zoomOutPage,
                            ),
                            const SizedBox(width: 8),
                            _buildMobileActionButton(
                              'Zoom +',
                              Colors.teal,
                              _zoomInPage,
                            ),
                            if (_isProcessing) ...[
                              const SizedBox(width: 12),
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ],
                          ],
                        ),
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
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 4)
                      ],
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
                          'Contract',
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
                      /// 🔹 SIDEBAR
                      if (!isMobile) const Sidebar(currentIndex: 1),
                      if (!isMobile) _buildHistoryPanel(),

                      /// 📄 MAIN AREA
                      Expanded(
                        child: Container(
                          color: Colors.grey[300],
                          child: Center(
                            child: isMobile
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      /// 📄 A4 PAGE (Photo Design)
                                      _buildZoomablePage(
                                        child: RepaintBoundary(
                                          key: _contractBoundaryKey,
                                          child: Container(
                                            width: _a4PageWidth,
                                            height: _a4PageHeight,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Colors.black12,
                                                  blurRadius: 10,
                                                  offset: Offset(0, 5),
                                                )
                                              ],
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 30, vertical: 20),
                                            child: Column(
                                              children: [
                                                /// --- HEADER (Same as Photo) ---
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    // Left: English
                                                    const Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                              "Taj Royal Glass Co.",
                                                              style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize:
                                                                      18)),
                                                          Text(
                                                              "Mirror and Glass Manufacturing Factory",
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      10)),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Center: Logo Circle
                                                    Container(
                                                      width: 60,
                                                      height: 60,
                                                      decoration:
                                                          const BoxDecoration(
                                                        color: Colors
                                                            .white, // 🔥 FORCE WHITE
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: ClipOval(
                                                        child: Image.asset(
                                                          "assets/logo.png",
                                                          fit: BoxFit.cover,
                                                        ),
                                                      ),
                                                    ),

                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .end,
                                                        children: [
                                                          Text(
                                                              "شركة تـاج رويـال الزجاج",
                                                              textDirection:
                                                                  TextDirection
                                                                      .rtl,
                                                              textAlign:
                                                                  TextAlign
                                                                      .right,
                                                              style:
                                                                  _arabicTextStyle(
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              )),
                                                          Text(
                                                              "لتركيب الزجاج والمرايا والبراويز",
                                                              textDirection:
                                                                  TextDirection
                                                                      .rtl,
                                                              textAlign:
                                                                  TextAlign
                                                                      .right,
                                                              style:
                                                                  _arabicTextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              )),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),

                                                const SizedBox(height: 22.7),

                                                const Divider(
                                                  height: 1,
                                                  thickness: 1,
                                                  color: Colors.black,
                                                ),

                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Align(
                                                        alignment:
                                                            Alignment.topLeft,
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 3),
                                                          decoration:
                                                              BoxDecoration(
                                                            border: Border.all(
                                                                width: 1,
                                                                color: Colors
                                                                    .black),
                                                            borderRadius:
                                                                const BorderRadius
                                                                    .only(
                                                              bottomRight:
                                                                  Radius
                                                                      .circular(
                                                                          4),
                                                            ),
                                                          ),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              RichText(
                                                                text: TextSpan(
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize: 7,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                                  children: [
                                                                    const TextSpan(
                                                                        text:
                                                                            'Date / '),
                                                                    TextSpan(
                                                                      text:
                                                                          'التاريخ',
                                                                      style:
                                                                          _arabicTextStyle(
                                                                        fontSize:
                                                                            7,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                        color: Colors
                                                                            .grey,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              Text(
                                                                _contractDateTime,
                                                                style: const TextStyle(
                                                                    fontSize: 9,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Transform.translate(
                                                      offset:
                                                          const Offset(0, -1),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 12,
                                                                vertical: 4),
                                                        decoration:
                                                            const BoxDecoration(
                                                          border: Border(
                                                            left: BorderSide(
                                                                width: 1),
                                                            right: BorderSide(
                                                                width: 1),
                                                            bottom: BorderSide(
                                                                width: 1),
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.only(
                                                            bottomLeft:
                                                                Radius.circular(
                                                                    5),
                                                            bottomRight:
                                                                Radius.circular(
                                                                    5),
                                                          ),
                                                        ),
                                                        child: Column(
                                                          children: [
                                                            Text("عقد إتفاق",
                                                                style:
                                                                    _arabicTextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                )),
                                                            const Text(
                                                                "Contract Paper",
                                                                style:
                                                                    TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 10,
                                                                )),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Align(
                                                        alignment:
                                                            Alignment.topRight,
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 3),
                                                          decoration:
                                                              BoxDecoration(
                                                            border: Border.all(
                                                                width: 1,
                                                                color: Colors
                                                                    .black),
                                                            borderRadius:
                                                                const BorderRadius
                                                                    .only(
                                                              bottomLeft: Radius
                                                                  .circular(4),
                                                            ),
                                                          ),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .end,
                                                            children: [
                                                              RichText(
                                                                textAlign:
                                                                    TextAlign
                                                                        .right,
                                                                text: TextSpan(
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize: 7,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                                  children: [
                                                                    const TextSpan(
                                                                      text:
                                                                          'Contract No. / ',
                                                                    ),
                                                                    TextSpan(
                                                                      text:
                                                                          'رقم العقد',
                                                                      style:
                                                                          _arabicTextStyle(
                                                                        fontSize:
                                                                            7,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                        color: Colors
                                                                            .grey,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              Text(
                                                                _contractNumber,
                                                                style: const TextStyle(
                                                                    fontSize: 9,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),

                                                const SizedBox(height: 8.5),

                                                Column(
                                                  children: [
                                                    _buildSplitInfoBoxRow(
                                                      englishLabel: 'Name',
                                                      arabicLabel: 'الاسم',
                                                      controller:
                                                          _nameController,
                                                      mirrorController:
                                                          _nameArabicController,
                                                      premiumStyle: true,
                                                      labelFontSize: 8,
                                                      valueFontSize: 10,
                                                      valueFontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    _buildSplitInfoBoxRow(
                                                      englishLabel: 'Mobile',
                                                      arabicLabel: 'الهاتف',
                                                      controller:
                                                          _mobileController,
                                                      mirrorController:
                                                          _mobileArabicController,
                                                      keyboardType:
                                                          TextInputType.phone,
                                                      premiumStyle: true,
                                                      labelFontSize: 8,
                                                      valueFontSize: 10,
                                                      valueFontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    _buildSplitInfoBoxRow(
                                                      englishLabel: 'Address',
                                                      arabicLabel: 'العنوان',
                                                      controller:
                                                          _addressController,
                                                      mirrorController:
                                                          _addressArabicController,
                                                      premiumStyle: true,
                                                      labelFontSize: 8,
                                                      valueFontSize: 10,
                                                      valueFontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    _buildSplitInfoBoxRow(
                                                      englishLabel:
                                                          'Description',
                                                      arabicLabel: 'الوصف',
                                                      controller:
                                                          _descriptionController,
                                                      mirrorController:
                                                          _descriptionArabicController,
                                                      rowHeight: 248,
                                                      centerTallLabel: true,
                                                      labelFontSize: 9,
                                                      valueFontSize: 12,
                                                      valueFontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    const SizedBox(height: 18),
                                                    _buildPaymentDetailsSplitBox(
                                                      rowHeight: 136,
                                                      premiumStyle: true,
                                                      titleFontSize: 8.5,
                                                      valueFontSize: 12.5,
                                                      valueFontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ],
                                                ),

                                                const Expanded(
                                                  child: SizedBox.shrink(),
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Transform.translate(
                                                            offset:
                                                                const Offset(
                                                                    0, -16.3),
                                                            child: RichText(
                                                              text: TextSpan(
                                                                style:
                                                                    const TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .black,
                                                                ),
                                                                children: [
                                                                  const TextSpan(
                                                                    text:
                                                                        'Authorized Signature / ',
                                                                  ),
                                                                  TextSpan(
                                                                    text:
                                                                        'التوقيع المعتمد',
                                                                    style:
                                                                        _arabicTextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 4),
                                                          // Show sign image if enabled
                                                          if (showSignStamp) ...[
                                                            Text(
                                                                'SIGNATURE IMAGE YAHAN HAI',
                                                                style: TextStyle(
                                                                    color: Colors
                                                                        .red)),
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      bottom:
                                                                          4),
                                                              child:
                                                                  Image.asset(
                                                                'assets/sing.png',
                                                                width: 90,
                                                                height: 40,
                                                                fit: BoxFit
                                                                    .contain,
                                                                errorBuilder: (context,
                                                                        error,
                                                                        stackTrace) =>
                                                                    Text(
                                                                        'Image not found',
                                                                        style: TextStyle(
                                                                            color:
                                                                                Colors.red)),
                                                              ),
                                                            ),
                                                          ],
                                                          const SizedBox(
                                                              height: 8),
                                                          Transform.translate(
                                                            offset:
                                                                const Offset(
                                                                    0, -11.4),
                                                            child:
                                                                _buildDottedSignatureLine(),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 40),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .end,
                                                        children: [
                                                          Transform.translate(
                                                            offset:
                                                                const Offset(
                                                                    0, -16.3),
                                                            child: RichText(
                                                              textAlign:
                                                                  TextAlign
                                                                      .right,
                                                              text: TextSpan(
                                                                style:
                                                                    const TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .black,
                                                                ),
                                                                children: [
                                                                  const TextSpan(
                                                                    text:
                                                                        'Customer Signature / ',
                                                                  ),
                                                                  TextSpan(
                                                                    text:
                                                                        'توقيع العميل',
                                                                    style:
                                                                        _arabicTextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 4),
                                                          // Show stamp image if enabled
                                                          if (showSignStamp) ...[
                                                            Text(
                                                                'STAMP IMAGE YAHAN HAI',
                                                                style: TextStyle(
                                                                    color: Colors
                                                                        .red)),
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      bottom:
                                                                          4),
                                                              child:
                                                                  Image.asset(
                                                                'assets/stamp.png',
                                                                width: 60,
                                                                height: 60,
                                                                fit: BoxFit
                                                                    .contain,
                                                                errorBuilder: (context,
                                                                        error,
                                                                        stackTrace) =>
                                                                    Text(
                                                                        'Image not found',
                                                                        style: TextStyle(
                                                                            color:
                                                                                Colors.red)),
                                                              ),
                                                            ),
                                                          ],
                                                          const SizedBox(
                                                              height: 8),
                                                          Transform.translate(
                                                            offset:
                                                                const Offset(
                                                                    0, -11.4),
                                                            child:
                                                                _buildDottedSignatureLine(),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),

                                                /// --- FOOTER SECTION ---
                                                const Divider(
                                                  thickness: 1.5,
                                                  color: Colors.black,
                                                  height: 1,
                                                ),
                                                SizedBox(
                                                  height: 85,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      SizedBox(
                                                        width: 55,
                                                        height: 55,
                                                        child: FittedBox(
                                                          fit: BoxFit.contain,
                                                          child: _buildFooterQr(
                                                            _leftQrUrl,
                                                          ),
                                                        ),
                                                      ),
                                                      Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                              "الكويت - الراي - قطعة ١ - قسيمة ٢٦ - مبنى ١٤١٩",
                                                              textDirection:
                                                                  TextDirection
                                                                      .rtl,
                                                              style:
                                                                  _arabicTextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                height: 1.2,
                                                              )),
                                                          const Text(
                                                              "Kuwait - Al Rai Block 1 - Street 26 - Building 1419",
                                                              style: TextStyle(
                                                                  fontSize: 11,
                                                                  height: 1.2)),
                                                          const Text(
                                                              "96952550 - 98532064 - 56540521",
                                                              style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 12,
                                                                  height: 1.2)),
                                                        ],
                                                      ),
                                                      SizedBox(
                                                        width: 55,
                                                        height: 55,
                                                        child: FittedBox(
                                                          fit: BoxFit.contain,
                                                          child: _buildFooterQr(
                                                            _rightQrUrl,
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
                                      ),

                                      const SizedBox(width: 30),

                                      /// 🔘 RIGHT SIDE BUTTONS
                                      Padding(
                                        padding: const EdgeInsets.only(top: 80),
                                        child: Column(
                                          children: [
                                            _buildButton(
                                                "New Contract",
                                                Colors.indigo,
                                                _startNewContract),
                                            const SizedBox(height: 20),
                                            _buildButton("Print", Colors.blue,
                                                _printContract),
                                            const SizedBox(height: 20),
                                            _buildButton(
                                                "Save PDF",
                                                const Color(0xFF249B28),
                                                () => _runButtonAction(
                                                    'Save PDF',
                                                    _saveContractOnly)),
                                            const SizedBox(height: 20),
                                            _buildButton(
                                                "Download PDF",
                                                Colors.blueAccent,
                                                () => _runButtonAction(
                                                    'Download PDF',
                                                    downloadContractFromServer)),
                                            const SizedBox(height: 20),
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.share),
                                              label:
                                                  const Text('Share Contract'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                              ),
                                              onPressed: () async {
                                                try {
                                                  // 1. Widget capture (high quality)
                                                  final boundary =
                                                      _contractBoundaryKey
                                                              .currentContext!
                                                              .findRenderObject()
                                                          as RenderRepaintBoundary;
                                                  final image =
                                                      await boundary.toImage(
                                                          pixelRatio:
                                                              3.0); // 3.0 = sharp quality
                                                  final byteData =
                                                      await image.toByteData(
                                                          format: ui
                                                              .ImageByteFormat
                                                              .png);
                                                  final pngBytes = byteData!
                                                      .buffer
                                                      .asUint8List();

                                                  // 2. PDF banao (exact A4 size)
                                                  final pdf = pw.Document();
                                                  final pdfImage =
                                                      pw.MemoryImage(pngBytes);

                                                  pdf.addPage(
                                                    pw.Page(
                                                      pageFormat:
                                                          PdfPageFormat.a4,
                                                      margin:
                                                          pw.EdgeInsets.zero,
                                                      build:
                                                          (pw.Context context) {
                                                        return pw.Center(
                                                          child: pw.Image(
                                                              pdfImage,
                                                              fit: pw.BoxFit
                                                                  .contain),
                                                        );
                                                      },
                                                    ),
                                                  );

                                                  final pdfBytes =
                                                      await pdf.save();

                                                  // 3. File name
                                                  final now = DateTime.now();
                                                  final fileName =
                                                      'taj_royal_contract_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf';

                                                  // 4. Share (Web + Mobile dono ke liye perfect)
                                                  if (kIsWeb) {
                                                    // Web pe direct download + share
                                                    await Share.shareXFiles(
                                                      [
                                                        XFile.fromData(pdfBytes,
                                                            mimeType:
                                                                'application/pdf',
                                                            name: fileName)
                                                      ],
                                                      text:
                                                          'Taj Royal Glass Co. - Contract Paper',
                                                    );
                                                  } else {
                                                    // Mobile/Desktop
                                                    final output =
                                                        await getTemporaryDirectory();
                                                    final file = File(
                                                        "${output.path}/$fileName");
                                                    await file
                                                        .writeAsBytes(pdfBytes);

                                                    await Share.shareXFiles(
                                                      [XFile(file.path)],
                                                      text:
                                                          'Taj Royal Glass Co. - Contract Paper',
                                                    );
                                                  }

                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                          content: Text(
                                                              'Share sheet opened ✅')),
                                                    );
                                                  }
                                                } catch (e) {
                                                  print('Share Error: $e');
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                          content: Text(
                                                              'Share failed: $e')),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                            const SizedBox(height: 20),
                                            _buildButton(
                                              "Zoom In",
                                              Colors.teal,
                                              _zoomInPage,
                                            ),
                                            const SizedBox(height: 20),
                                            _buildButton(
                                              "Zoom Out",
                                              Colors.teal,
                                              _zoomOutPage,
                                            ),
                                            const SizedBox(height: 20),
                                            _buildButton(
                                              "Reset Zoom",
                                              Colors.teal.shade700,
                                              _resetPageZoom,
                                            ),
                                            const SizedBox(height: 20),

                                            // ==================== NAYA SIGNATURE & STAMP BUTTON ====================
                                            ElevatedButton.icon(
                                              onPressed: () {
                                                setState(() {
                                                  showSignStamp =
                                                      !showSignStamp;
                                                });
                                              },
                                              icon: Icon(
                                                showSignStamp
                                                    ? Icons.visibility
                                                    : Icons.visibility_off,
                                                color: Colors.white,
                                              ),
                                              label: Text(
                                                showSignStamp
                                                    ? "Signature & Stamp ON"
                                                    : "Signature & Stamp OFF",
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: showSignStamp
                                                    ? Colors.purple
                                                    : Colors.grey[700],
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 24,
                                                        vertical: 16),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                elevation: 5,
                                              ),
                                            ),
                                            if (_isProcessing) ...[
                                              const SizedBox(height: 20),
                                              const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      /// 📄 A4 PAGE (Photo Design)
                                      _buildZoomablePage(
                                        child: RepaintBoundary(
                                          key: _contractBoundaryKey,
                                          child: Container(
                                            width: _a4PageWidth,
                                            height: _a4PageHeight,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Colors.black12,
                                                  blurRadius: 10,
                                                  offset: Offset(0, 5),
                                                )
                                              ],
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 30, vertical: 20),
                                            child: Column(
                                              children: [
                                                /// --- HEADER (Same as Photo) ---
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    // Left: English
                                                    const Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                              "Taj Royal Glass Co.",
                                                              style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize:
                                                                      18)),
                                                          Text(
                                                              "Mirror and Glass Manufacturing Factory",
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      10)),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Center: Logo Circle
                                                    Container(
                                                      width: 60,
                                                      height: 60,
                                                      decoration:
                                                          const BoxDecoration(
                                                        color: Colors
                                                            .white, // 🔥 FORCE WHITE
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: ClipOval(
                                                        child: Image.asset(
                                                          "assets/logo.png",
                                                          fit: BoxFit.cover,
                                                        ),
                                                      ),
                                                    ),

                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .end,
                                                        children: [
                                                          Text(
                                                              "شركة تـاج رويـال الزجاج",
                                                              textDirection:
                                                                  TextDirection
                                                                      .rtl,
                                                              textAlign:
                                                                  TextAlign
                                                                      .right,
                                                              style:
                                                                  _arabicTextStyle(
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              )),
                                                          Text(
                                                              "لتركيب الزجاج والمرايا والبراويز",
                                                              textDirection:
                                                                  TextDirection
                                                                      .rtl,
                                                              textAlign:
                                                                  TextAlign
                                                                      .right,
                                                              style:
                                                                  _arabicTextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              )),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),

                                                const SizedBox(height: 22.7),

                                                const Divider(
                                                  height: 1,
                                                  thickness: 1,
                                                  color: Colors.black,
                                                ),

                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Align(
                                                        alignment:
                                                            Alignment.topLeft,
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 3),
                                                          decoration:
                                                              BoxDecoration(
                                                            border: Border.all(
                                                                width: 1,
                                                                color: Colors
                                                                    .black),
                                                            borderRadius:
                                                                const BorderRadius
                                                                    .only(
                                                              bottomRight:
                                                                  Radius
                                                                      .circular(
                                                                          4),
                                                            ),
                                                          ),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              RichText(
                                                                text: TextSpan(
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize: 7,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                                  children: [
                                                                    const TextSpan(
                                                                        text:
                                                                            'Date / '),
                                                                    TextSpan(
                                                                      text:
                                                                          'التاريخ',
                                                                      style:
                                                                          _arabicTextStyle(
                                                                        fontSize:
                                                                            7,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                        color: Colors
                                                                            .grey,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              Text(
                                                                _contractDateTime,
                                                                style: const TextStyle(
                                                                    fontSize: 9,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Transform.translate(
                                                      offset:
                                                          const Offset(0, -1),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 12,
                                                                vertical: 4),
                                                        decoration:
                                                            const BoxDecoration(
                                                          border: Border(
                                                            left: BorderSide(
                                                                width: 1),
                                                            right: BorderSide(
                                                                width: 1),
                                                            bottom: BorderSide(
                                                                width: 1),
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.only(
                                                            bottomLeft:
                                                                Radius.circular(
                                                                    5),
                                                            bottomRight:
                                                                Radius.circular(
                                                                    5),
                                                          ),
                                                        ),
                                                        child: Column(
                                                          children: [
                                                            Text("عقد إتفاق",
                                                                style:
                                                                    _arabicTextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                )),
                                                            const Text(
                                                                "Contract Paper",
                                                                style:
                                                                    TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 10,
                                                                )),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Align(
                                                        alignment:
                                                            Alignment.topRight,
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 3),
                                                          decoration:
                                                              BoxDecoration(
                                                            border: Border.all(
                                                                width: 1,
                                                                color: Colors
                                                                    .black),
                                                            borderRadius:
                                                                const BorderRadius
                                                                    .only(
                                                              bottomLeft: Radius
                                                                  .circular(4),
                                                            ),
                                                          ),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .end,
                                                            children: [
                                                              RichText(
                                                                textAlign:
                                                                    TextAlign
                                                                        .right,
                                                                text: TextSpan(
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize: 7,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                                  children: [
                                                                    const TextSpan(
                                                                      text:
                                                                          'Contract No. / ',
                                                                    ),
                                                                    TextSpan(
                                                                      text:
                                                                          'رقم العقد',
                                                                      style:
                                                                          _arabicTextStyle(
                                                                        fontSize:
                                                                            7,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                        color: Colors
                                                                            .grey,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              Text(
                                                                _contractNumber,
                                                                style: const TextStyle(
                                                                    fontSize: 9,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),

                                                const SizedBox(height: 8.5),

                                                Column(
                                                  children: [
                                                    _buildSplitInfoBoxRow(
                                                      englishLabel: 'Name',
                                                      arabicLabel: 'الاسم',
                                                      controller:
                                                          _nameController,
                                                      mirrorController:
                                                          _nameArabicController,
                                                      premiumStyle: true,
                                                      labelFontSize: 8,
                                                      valueFontSize: 10,
                                                      valueFontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    _buildSplitInfoBoxRow(
                                                      englishLabel: 'Mobile',
                                                      arabicLabel: 'الهاتف',
                                                      controller:
                                                          _mobileController,
                                                      mirrorController:
                                                          _mobileArabicController,
                                                      keyboardType:
                                                          TextInputType.phone,
                                                      premiumStyle: true,
                                                      labelFontSize: 8,
                                                      valueFontSize: 10,
                                                      valueFontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    _buildSplitInfoBoxRow(
                                                      englishLabel: 'Address',
                                                      arabicLabel: 'العنوان',
                                                      controller:
                                                          _addressController,
                                                      mirrorController:
                                                          _addressArabicController,
                                                      premiumStyle: true,
                                                      labelFontSize: 8,
                                                      valueFontSize: 10,
                                                      valueFontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    _buildSplitInfoBoxRow(
                                                      englishLabel:
                                                          'Description',
                                                      arabicLabel: 'الوصف',
                                                      controller:
                                                          _descriptionController,
                                                      mirrorController:
                                                          _descriptionArabicController,
                                                      rowHeight: 248,
                                                      centerTallLabel: true,
                                                      labelFontSize: 9,
                                                      valueFontSize: 12,
                                                      valueFontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    const SizedBox(height: 18),
                                                    _buildPaymentDetailsSplitBox(
                                                      rowHeight: 136,
                                                      premiumStyle: true,
                                                      titleFontSize: 8.5,
                                                      valueFontSize: 12.5,
                                                      valueFontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ],
                                                ),

                                                const Expanded(
                                                  child: SizedBox.shrink(),
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Transform.translate(
                                                            offset:
                                                                const Offset(
                                                                    0, -16.3),
                                                            child: RichText(
                                                              text: TextSpan(
                                                                style:
                                                                    const TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .black,
                                                                ),
                                                                children: [
                                                                  const TextSpan(
                                                                    text:
                                                                        'Authorized Signature / ',
                                                                  ),
                                                                  TextSpan(
                                                                    text:
                                                                        'التوقيع المعتمد',
                                                                    style:
                                                                        _arabicTextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 12),
                                                          Transform.translate(
                                                            offset:
                                                                const Offset(
                                                                    0, -11.4),
                                                            child:
                                                                _buildDottedSignatureLine(),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 40),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .end,
                                                        children: [
                                                          Transform.translate(
                                                            offset:
                                                                const Offset(
                                                                    0, -16.3),
                                                            child: RichText(
                                                              textAlign:
                                                                  TextAlign
                                                                      .right,
                                                              text: TextSpan(
                                                                style:
                                                                    const TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Colors
                                                                      .black,
                                                                ),
                                                                children: [
                                                                  const TextSpan(
                                                                    text:
                                                                        'Customer Signature / ',
                                                                  ),
                                                                  TextSpan(
                                                                    text:
                                                                        'توقيع العميل',
                                                                    style:
                                                                        _arabicTextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 12),
                                                          Transform.translate(
                                                            offset:
                                                                const Offset(
                                                                    0, -11.4),
                                                            child:
                                                                _buildDottedSignatureLine(),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),

                                                /// --- FOOTER SECTION ---
                                                const Divider(
                                                  thickness: 1.5,
                                                  color: Colors.black,
                                                  height: 1,
                                                ),
                                                SizedBox(
                                                  height: 85,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      SizedBox(
                                                        width: 55,
                                                        height: 55,
                                                        child: FittedBox(
                                                          fit: BoxFit.contain,
                                                          child: _buildFooterQr(
                                                              _leftQrUrl),
                                                        ),
                                                      ),
                                                      Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                              "الكويت - الراي - قطعة ١ - قسيمة ٢٦ - مبنى ١٤١٩",
                                                              textDirection:
                                                                  TextDirection
                                                                      .rtl,
                                                              style:
                                                                  _arabicTextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                height: 1.2,
                                                              )),
                                                          const Text(
                                                              "Kuwait - Al Rai Block 1 - Street 26 - Building 1419",
                                                              style: TextStyle(
                                                                  fontSize: 11,
                                                                  height: 1.2)),
                                                          const Text(
                                                              "96952550 - 98532064 - 56540521",
                                                              style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 12,
                                                                  height: 1.2)),
                                                        ],
                                                      ),
                                                      SizedBox(
                                                        width: 55,
                                                        height: 55,
                                                        child: FittedBox(
                                                          fit: BoxFit.contain,
                                                          child: _buildFooterQr(
                                                            _rightQrUrl,
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
                                      ),

                                      const SizedBox(width: 30),

                                      /// 🔘 RIGHT SIDE BUTTONS
                                      Padding(
                                        padding: const EdgeInsets.only(top: 80),
                                        child: Column(
                                          children: [
                                            // ==================== DESKTOP/WEB - SIGNATURE & STAMP BUTTON ====================
                                            ElevatedButton.icon(
                                              onPressed: () {
                                                setState(() {
                                                  showSignStamp =
                                                      !showSignStamp;
                                                });
                                              },
                                              icon: Icon(
                                                showSignStamp
                                                    ? Icons.visibility
                                                    : Icons.visibility_off,
                                                color: Colors.white,
                                              ),
                                              label: Text(
                                                showSignStamp
                                                    ? "Signature & Stamp ON"
                                                    : "Signature & Stamp OFF",
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: showSignStamp
                                                    ? Colors.purple
                                                    : Colors.grey[700],
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 24,
                                                        vertical: 16),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12)),
                                                elevation: 4,
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                            _buildButton("Print", Colors.blue,
                                                _printContract),
                                            const SizedBox(height: 20),
                                            _buildButton(
                                                "Save PDF",
                                                const Color(0xFF249B28),
                                                () => _runButtonAction(
                                                    'Save PDF',
                                                    _saveContractOnly)),
                                            const SizedBox(height: 20),
                                            _buildButton(
                                                "Download PDF",
                                                Colors.blueAccent,
                                                () => _runButtonAction(
                                                    'Download PDF',
                                                    downloadContractFromServer)),
                                            const SizedBox(height: 20),
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.share),
                                              label:
                                                  const Text('Share Contract'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                              ),
                                              onPressed: () async {
                                                try {
                                                  // 1. Widget capture (high quality)
                                                  final boundary =
                                                      _contractBoundaryKey
                                                              .currentContext!
                                                              .findRenderObject()
                                                          as RenderRepaintBoundary;
                                                  final image =
                                                      await boundary.toImage(
                                                          pixelRatio:
                                                              3.0); // 3.0 = sharp quality
                                                  final byteData =
                                                      await image.toByteData(
                                                          format: ui
                                                              .ImageByteFormat
                                                              .png);
                                                  final pngBytes = byteData!
                                                      .buffer
                                                      .asUint8List();

                                                  // 2. PDF banao (exact A4 size)
                                                  final pdf = pw.Document();
                                                  final pdfImage =
                                                      pw.MemoryImage(pngBytes);

                                                  pdf.addPage(
                                                    pw.Page(
                                                      pageFormat:
                                                          PdfPageFormat.a4,
                                                      margin:
                                                          pw.EdgeInsets.zero,
                                                      build:
                                                          (pw.Context context) {
                                                        return pw.Center(
                                                          child: pw.Image(
                                                              pdfImage,
                                                              fit: pw.BoxFit
                                                                  .contain),
                                                        );
                                                      },
                                                    ),
                                                  );

                                                  final pdfBytes =
                                                      await pdf.save();

                                                  // 3. File name
                                                  final now = DateTime.now();
                                                  final fileName =
                                                      'taj_royal_contract_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf';

                                                  // 4. Share (Web + Mobile dono ke liye perfect)
                                                  if (kIsWeb) {
                                                    // Web pe direct download + share
                                                    await Share.shareXFiles(
                                                      [
                                                        XFile.fromData(pdfBytes,
                                                            mimeType:
                                                                'application/pdf',
                                                            name: fileName)
                                                      ],
                                                      text:
                                                          'Taj Royal Glass Co. - Contract Paper',
                                                    );
                                                  } else {
                                                    // Mobile/Desktop
                                                    final output =
                                                        await getTemporaryDirectory();
                                                    final file = File(
                                                        "${output.path}/$fileName");
                                                    await file
                                                        .writeAsBytes(pdfBytes);

                                                    await Share.shareXFiles(
                                                      [XFile(file.path)],
                                                      text:
                                                          'Taj Royal Glass Co. - Contract Paper',
                                                    );
                                                  }

                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                          content: Text(
                                                              'Share sheet opened ✅')),
                                                    );
                                                  }
                                                } catch (e) {
                                                  print('Share Error: $e');
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                          content: Text(
                                                              'Share failed: $e')),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                            const SizedBox(height: 20),
                                            _buildButton(
                                              "Zoom In",
                                              Colors.teal,
                                              _zoomInPage,
                                            ),
                                            const SizedBox(height: 20),
                                            _buildButton(
                                              "Zoom Out",
                                              Colors.teal,
                                              _zoomOutPage,
                                            ),
                                            const SizedBox(height: 20),
                                            _buildButton(
                                              "Reset Zoom",
                                              Colors.teal.shade700,
                                              _resetPageZoom,
                                            ),
                                            if (_isProcessing) ...[
                                              const SizedBox(height: 20),
                                              const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              ),
                                            ],
                                          ],
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
        ),
      ),
    );
  }

  Widget _buildButton(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      width: 150,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 5,
        ),
        onPressed: _isProcessing ? null : onTap,
        child: Text(label,
            style: const TextStyle(fontSize: 16, color: Colors.white)),
      ),
    );
  }

  Widget _buildZoomablePage({required Widget child}) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    return SizedBox(
      width: _a4PageWidth,
      height: _a4PageHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(
            constraints.hasBoundedWidth ? constraints.maxWidth : _a4PageWidth,
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : _a4PageHeight,
          );
          _updateZoomViewport(viewport);

          return ClipRect(
            child: InteractiveViewer(
              transformationController: _pageZoomController,
              minScale: _minPageScale,
              maxScale: _maxPageScale,
              constrained: isMobile ? true : false,
              boundaryMargin:
                  isMobile ? EdgeInsets.zero : const EdgeInsets.all(250),
              onInteractionEnd: (_) {
                final current = _pageZoomController.value.getMaxScaleOnAxis();
                final clamped =
                    current.clamp(_minPageScale, _maxPageScale).toDouble();
                if ((_pageScale - clamped).abs() > 0.001 && mounted) {
                  setState(() {
                    _pageScale = clamped;
                  });
                } else {
                  _pageScale = clamped;
                }
              },
              child: child,
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooterQr(String data) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: 200,
      backgroundColor: Colors.white,
    );
  }

  Widget _buildMobileActionButton(
      String label, Color color, VoidCallback onTap) {
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
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget buildField(String label) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label),
    );
  }

  Widget buildPaymentDetailsColumn({
    required TextStyle titleStyle,
    required TextStyle contentStyle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Payment Details", style: titleStyle),
        const SizedBox(height: 8),
        Text("Grand Total:", style: contentStyle),
        const SizedBox(height: 6),
        Text("First Payment:", style: contentStyle),
        const SizedBox(height: 6),
        Text("Second Payment:", style: contentStyle),
        const SizedBox(height: 6),
        Text("Third Payment:", style: contentStyle),
        const SizedBox(height: 6),
        Text("Last Payment:", style: contentStyle),
      ],
    );
  }
}

/// Load signature and stamp images from assets for PDF
Future<void> _loadStampAndSignImages() async {
  try {
    final stampData = await rootBundle.load('assets/stamp.png');
    var _stampImage = pw.MemoryImage(stampData.buffer.asUint8List());
  } catch (e) {
    debugPrint('Failed to load stamp.png: $e');
    var _stampImage = null;
  }
  try {
    final signData = await rootBundle.load('assets/sign.png');
    var _signImage = pw.MemoryImage(signData.buffer.asUint8List());
  } catch (e) {
    debugPrint('Failed to load sign.png: $e');
    var _signImage = null;
  }
}

class PaymentSection extends StatefulWidget {
  const PaymentSection({super.key});

  @override
  State<PaymentSection> createState() => _PaymentSectionState();
}

class _PaymentSectionState extends State<PaymentSection> {
  final TextEditingController grandTotal = TextEditingController();
  final TextEditingController firstPayment = TextEditingController();
  final TextEditingController secondPayment = TextEditingController();
  final TextEditingController thirdPayment = TextEditingController();
  final TextEditingController lastPayment = TextEditingController();

  Widget buildGrandTotalField() {
    return TextField(
      controller: grandTotal,
      decoration: const InputDecoration(
        hintText: 'Enter amount',
        border: OutlineInputBorder(
          borderSide: BorderSide(width: 1.5),
        ),
      ),
    );
  }

  Widget buildRow(
    String labelEng,
    String labelAr,
    TextEditingController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    labelEng,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Enter amount',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(width: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: controller,
                    readOnly: false,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      hintText: 'المبلغ',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: Text(
                    labelAr,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    grandTotal.dispose();
    firstPayment.dispose();
    secondPayment.dispose();
    thirdPayment.dispose();
    lastPayment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(width: 1.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Payment Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          buildRow('Grand Total:', 'إجمالي المبلغ:', grandTotal),
          buildRow('First Payment:', 'الدفعة الأولى:', firstPayment),
          buildRow('Second Payment:', 'الدفعة الثانية:', secondPayment),
          buildRow('Third Payment:', 'الدفعة الثالثة:', thirdPayment),
          buildRow('Last Payment:', 'الدفعة الأخيرة:', lastPayment),
        ],
      ),
    );
  }
}
