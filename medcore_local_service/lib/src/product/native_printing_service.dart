import 'dart:convert';
import 'package:decimal/decimal.dart';

/// Native Desktop Printing Abstraction (Batch 18).
/// Formats thermal receipts (ESC/POS 80mm), barcode labels (ZPL), and A4 financial documents.
/// Strictly separates Document Generation from Printer Transport.
class NativePrintingService {
  static const String hardwareVerificationPendingMarker = 'HARDWARE_VERIFICATION_PENDING';

  /// Generates ESC/POS byte sequence for standard 80mm thermal receipt printer.
  static List<int> generateEscPosThermalReceipt({
    required String facilityName,
    required String receiptNumber,
    required String dateString,
    required String cashierName,
    required String patientName,
    required String patientMrn,
    required List<Map<String, dynamic>> items,
    required Decimal grossAmount,
    required Decimal discountAmount,
    required Decimal netAmount,
    required Decimal paidAmount,
    required Decimal balanceAmount,
    required String currency,
  }) {
    final buffer = <int>[];

    void addStr(String s) => buffer.addAll(utf8.encode(s));
    void esc(List<int> bytes) => buffer.addAll(bytes);

    // Initialize printer: ESC @
    esc([0x1B, 0x40]);

    // Align center: ESC a 1
    esc([0x1B, 0x61, 0x01]);
    // Bold on: ESC E 1
    esc([0x1B, 0x45, 0x01]);
    addStr('$facilityName\n');
    addStr('OFFICIAL PAYMENT RECEIPT\n');
    // Bold off: ESC E 0
    esc([0x1B, 0x45, 0x00]);
    addStr('Receipt #: $receiptNumber\n');
    addStr('Date: $dateString\n');
    addStr('------------------------------------------------\n');

    // Align left: ESC a 0
    esc([0x1B, 0x61, 0x00]);
    addStr('Patient: $patientName (MRN: $patientMrn)\n');
    addStr('Cashier: $cashierName\n');
    addStr('------------------------------------------------\n');
    addStr('Item                              Qty    Total\n');
    addStr('------------------------------------------------\n');

    for (final item in items) {
      final name = (item['name'] ?? 'Service').toString().padRight(32).substring(0, 32);
      final qty = (item['qty'] ?? '1').toString().padLeft(4);
      final tot = (item['total'] ?? '0.00').toString().padLeft(10);
      addStr('$name $qty $tot\n');
    }

    addStr('------------------------------------------------\n');
    // Align right: ESC a 2
    esc([0x1B, 0x61, 0x02]);
    addStr('Gross Total: ${grossAmount.toStringAsFixed(4)} $currency\n');
    if (discountAmount > Decimal.zero) {
      addStr('Discount: -${discountAmount.toStringAsFixed(4)} $currency\n');
    }
    // Bold on
    esc([0x1B, 0x45, 0x01]);
    addStr('Net Amount: ${netAmount.toStringAsFixed(4)} $currency\n');
    addStr('Paid Amount: ${paidAmount.toStringAsFixed(4)} $currency\n');
    // Bold off
    esc([0x1B, 0x45, 0x00]);
    if (balanceAmount > Decimal.zero) {
      addStr('Remaining Balance: ${balanceAmount.toStringAsFixed(4)} $currency\n');
    } else {
      addStr('Balance: PAID IN FULL\n');
    }

    addStr('------------------------------------------------\n');
    // Align center
    esc([0x1B, 0x61, 0x01]);
    addStr('Thank you for choosing $facilityName\n');
    addStr('System: MedCore Platinum Desktop\n\n\n');

    // Feed and Partial Cut: GS V 1
    esc([0x1D, 0x56, 0x01]);

    return buffer;
  }

  /// Generates ZPL (Zebra Programming Language) string for specimen/tube/wristband labels.
  static String generateZplBarcodeLabel({
    required String facilityName,
    required String patientName,
    required String patientMrn,
    required String barcodeContent,
    required String labelTitle,
    required String timestampString,
  }) {
    return [
      '^XA',
      '^CF0,30',
      '^FO50,40^FD$facilityName^FS',
      '^CF0,24',
      '^FO50,80^FD$labelTitle^FS',
      '^FO50,115^FDPat: $patientName^FS',
      '^FO50,145^FDMRN: $patientMrn^FS',
      '^FO50,180^BY2,2,60',
      '^BCN,60,Y,N,N',
      '^FD$barcodeContent^FS',
      '^FO50,280^CF0,18^FD$timestampString^FS',
      '^XZ',
    ].join('\n');
  }

  /// Simulates/Dispatches print job to transport.
  /// If hardware printer is not connected, returns payload bytes and marks HARDWARE_VERIFICATION_PENDING.
  static Map<String, dynamic> dispatchPrintJob({
    required String format, // 'ESC_POS' | 'ZPL' | 'A4_HTML'
    required String documentType,
    required String documentId,
    required List<int> rawBytes,
    String? printerEndpoint,
  }) {
    return {
      'jobId': 'PRN-${DateTime.now().millisecondsSinceEpoch}',
      'format': format,
      'documentType': documentType,
      'documentId': documentId,
      'byteLength': rawBytes.length,
      'base64Payload': base64Encode(rawBytes),
      'targetPrinter': printerEndpoint ?? 'DEFAULT_USB_PRINTER',
      'hardwareStatus': hardwareVerificationPendingMarker,
      'message': 'Print formatting generated successfully. Hardware transport marked $hardwareVerificationPendingMarker pending physical device connection.',
    };
  }
}
