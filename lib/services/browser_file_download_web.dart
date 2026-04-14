import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

Future<void> downloadPdfBytes(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
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
  final blob = html.Blob([bytes], 'application/pdf');
  final file = html.File([blob], filename);
  final nav = html.window.navigator;

  try {
    final canSharePayload = js_util.jsify({
      'files': [file],
    });
    final sharePayload = js_util.jsify({
      'files': [file],
      'title': title,
      'text': text,
    });

    final canShareFiles = js_util.hasProperty(nav, 'canShare') &&
        js_util.callMethod<Object>(nav, 'canShare', [canSharePayload]) == true;

    if (canShareFiles && js_util.hasProperty(nav, 'share')) {
      await js_util.promiseToFuture<void>(
        js_util.callMethod<Object>(nav, 'share', [sharePayload]),
      );
    } else {
      throw Exception('Share not supported');
    }
  } catch (_) {
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
    Future<void>.delayed(const Duration(seconds: 30), () {
      html.Url.revokeObjectUrl(url);
    });
  }
}