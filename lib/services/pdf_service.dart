import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfService {
  Future contract(String name, String mobile) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(17 * PdfPageFormat.cm, 14 * PdfPageFormat.cm),
        margin: pw.EdgeInsets.all(20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              /// 🔝 HEADER
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Taj Royal Glass Co.",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("LOGO"),
                  pw.Text("شركة تاج رويال الزجاج"),
                ],
              ),

              pw.SizedBox(height: 10),
              pw.Divider(),

              /// 🏷️ TITLE
              pw.Center(
                child: pw.Container(
                  padding: pw.EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(),
                  ),
                  child: pw.Text("CONTRACT PAPER",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ),
              ),

              pw.SizedBox(height: 20),

              /// 👤 CLIENT DETAILS
              pw.Text("Name: $name"),
              pw.Text("Mobile: $mobile"),
              pw.Text("Address: _______________________"),
              pw.Text("Date: _______________________"),

              pw.SizedBox(height: 20),

              /// 📋 WORK TABLE 🔥
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  /// Header row
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text("No"),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text("Description"),
                      ),
                    ],
                  ),

                  /// 10 rows
                  ...List.generate(10, (index) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: pw.EdgeInsets.all(5),
                          child: pw.Text("${index + 1}"),
                        ),
                        pw.Padding(
                          padding: pw.EdgeInsets.all(10),
                          child: pw.Text(""),
                        ),
                      ],
                    );
                  }),
                ],
              ),

              pw.Spacer(),

              /// 📍 FOOTER
              pw.Divider(),

              pw.Center(
                child: pw.Text(
                  "Kuwait - Al Rai | Mobile: 96952550",
                  style: pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }
}
