import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../core/widgets/pii_mask.dart';
import '../../core/theme/theme.dart';

class ResumePreviewScreen extends StatelessWidget {
  final String title;
  final Uint8List pdfBytes;

  const ResumePreviewScreen({
    super.key,
    required this.title,
    required this.pdfBytes,
  });

  @override
  Widget build(BuildContext context) {
    return PiiMask(child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          title,
          style: TextStyle(fontFamily: 'Outfit', 
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.share_rounded, size: 22),
              onPressed: () async {
                await Printing.sharePdf(
                  bytes: pdfBytes,
                  filename: '${title.replaceAll(' ', '_')}.pdf',
                );
              },
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate expected page height based on width (max 600) and A4 ratio (1.414)
          // ratio = h/w ~ 1.414. So h = w * 1.414
          // If width is constrained by screen width (minus padding), use that.
          final double horizontalPadding = 16;
          final double maxWidth = 600;
          final double screenWidth = constraints.maxWidth;
          
          final double actualWidth = (screenWidth > maxWidth ? maxWidth : screenWidth) - (horizontalPadding * 2);
          final double estimatedHeight = actualWidth * 1.414;
          
          final double availableHeight = constraints.maxHeight;
          
          // Calculate vertical padding to center the page
          // If estimated height is bigger than available, use minimal padding (24)
          double verticalPadding = 24.0;
          if (estimatedHeight < availableHeight) {
            verticalPadding = (availableHeight - estimatedHeight) / 2;
          }

          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: PdfPreview(
              build: (format) => pdfBytes,
              useActions: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              maxPageWidth: maxWidth,
              padding: EdgeInsets.symmetric(
                vertical: verticalPadding, 
                horizontal: horizontalPadding
              ),
              scrollViewDecoration: const BoxDecoration(
                color: AppColors.background,
              ),
              pdfPreviewPageDecoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              loadingWidget: const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          );
        },
      ),
    ));
  }
}
