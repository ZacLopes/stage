import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PDFGeneratorService {
  static Future<Uint8List> generateResumePDF(String text) async {
    print('--- GENERATING PDF ---');
    print('Text length: ${text.length}');
    
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.interRegular();
    final fontBold = await PdfGoogleFonts.interBold();

    final displayContent = text.trim().isEmpty 
        ? "O conteúdo do currículo otimizado está sendo processado ou não foi retornado corretamente pela IA." 
        : text;

    print('First 100 chars of displayContent: ${displayContent.substring(0, displayContent.length > 100 ? 100 : displayContent.length)}');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('CURRÍCULO OTIMIZADO', 
                    style: pw.TextStyle(font: fontBold, fontSize: 20, color: PdfColors.blue900)),
                  pw.SizedBox(height: 4),
                  pw.Container(height: 2, color: PdfColors.blue900),
                  pw.SizedBox(height: 20),
                ],
              ),
            ),
            pw.Paragraph(
              text: displayContent,
              style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.black),
            ),
            pw.Footer(
              trailing: pw.Text('Gerado por Stage IA', 
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}
