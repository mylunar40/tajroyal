import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadPdfBytes(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);

  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();

  html.Url.revokeObjectUrl(url);
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
  // Fallback: trigger download since Web Share API requires js_interop
  await downloadPdfBytes(bytes, filename);
}
