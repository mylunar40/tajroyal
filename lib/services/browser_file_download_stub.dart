import 'dart:typed_data';

Future<void> downloadPdfBytes(Uint8List bytes, String filename) async {
  throw UnsupportedError('Browser download is only available on web.');
}

Future<void> downloadPdfWeb(Uint8List bytes) async {
  await downloadPdfBytes(bytes, 'contract.pdf');
}

Future<void> sharePdfWeb(
  Uint8List bytes, {
  String filename = 'contract.pdf',
  String title = 'Contract PDF',
  String text = 'Check this contract',
}) async {
  throw UnsupportedError('Browser share is only available on web.');
}