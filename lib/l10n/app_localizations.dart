import 'package:flutter/material.dart';

/// Global notifier for switching application language at runtime.
/// `null` represents system default locale.
final ValueNotifier<Locale?> appLocaleNotifier = ValueNotifier<Locale?>(null);

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static const LocalizationsDelegate<AppLocalizations> delegate =
      AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('th'),
    Locale('en'),
  ];

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('th'));
  }

  bool get isThai => locale.languageCode == 'th';

  // Common / App
  String get appTitle => 'VibeQuickPDF';
  String get refresh => isThai ? 'รีเฟรช' : 'Refresh';
  String get cancel => isThai ? 'ยกเลิก' : 'Cancel';
  String get delete => isThai ? 'ลบ' : 'Delete';
  String get clear => isThai ? 'ล้าง' : 'Clear';
  String get clearAll => isThai ? 'ล้างทั้งหมด' : 'Clear All';
  String get retry => isThai ? 'ลองใหม่' : 'Retry';
  String get share => isThai ? 'แชร์' : 'Share';
  String get shareWatermark =>
      isThai ? 'สร้างด้วย VibeQuickPDF' : 'Created with VibeQuickPDF';
  String get changeLanguage => isThai ? 'เปลี่ยนภาษา' : 'Change Language';
  String get languageThai => 'ภาษาไทย (Thai)';
  String get languageEnglish => 'English';
  String get languageSystem => isThai ? 'ตามระบบ' : 'System Default';

  // Home Screen
  String get emptyPdfListMessage => isThai
      ? 'ยังไม่มี PDF ที่สร้างขึ้น\nแตะที่ปุ่มด้านล่างเพื่อสร้างใหม่!'
      : 'No PDFs created yet\nTap the button below to create one!';
  String get createPdf => isThai ? 'สร้าง PDF' : 'Create PDF';
  String get deletePdfTitle => isThai ? 'ลบ PDF' : 'Delete PDF';
  String deletePdfConfirm(String name) => isThai
      ? 'คุณแน่ใจหรือไม่ว่าต้องการลบ $name?'
      : 'Are you sure you want to delete $name?';
  String get shareFailedTitle => isThai ? 'การแชร์ไม่สำเร็จ' : 'Share Failed';
  String get shareFailedMessage => isThai
      ? 'ดูเหมือนว่าการแชร์จะไม่สมบูรณ์ คุณต้องการลองอีกครั้งหรือไม่?'
      : 'The share appears to be incomplete. Would you like to try again?';

  // Conversion Screen - Source Selection
  String get takePhoto => isThai ? 'ถ่ายรูป' : 'Camera';
  String get chooseFromGallery => isThai ? 'เลือกจากคลัง' : 'Gallery';
  String get addImagesTitle => isThai ? 'เพิ่มรูปภาพ' : 'Add Images';
  String get takePhotoOptionTitle =>
      isThai ? 'ถ่ายรูปด้วยกล้อง' : 'Take Photo with Camera';
  String get takePhotoOptionSubtitle =>
      isThai ? 'ถ่ายภาพเอกสารใหม่' : 'Capture a new document photo';
  String get galleryOptionTitle =>
      isThai ? 'เลือกจากคลังรูปภาพ' : 'Select from Gallery';
  String get galleryOptionSubtitle =>
      isThai ? 'เลือกภาพถ่ายหลายภาพพร้อมกัน' : 'Pick multiple photos at once';
  String get addPhotoTile => isThai ? 'เพิ่มรูป' : 'Add Photo';

  // Conversion Screen - Empty State Hub
  String get emptyStateHubTitle => isThai
      ? 'เพิ่มรูปภาพเพื่อเริ่มต้นสร้าง PDF'
      : 'Add images to start creating PDF';
  String get emptyStateHubSubtitle => isThai
      ? 'ถ่ายภาพเอกสารใหม่ หรือเลือกรูปภาพจากคลังรูปภาพของคุณ'
      : 'Capture new document photos or select images from your gallery';

  // Conversion Screen - Image Grid Header & Confirmations
  String selectedImagesCount(int count) =>
      isThai ? 'รูปภาพที่เลือก ($count)' : 'Selected Images ($count)';
  String get reorderHint => isThai
      ? 'กดค้างแล้วลากเพื่อจัดลำดับหน้า'
      : 'Press & drag to reorder pages';
  String pageNumber(int index) =>
      isThai ? 'หน้า $index' : 'Page $index';
  String get movePrevious => isThai ? 'ย้ายไปก่อนหน้า' : 'Move Previous';
  String get moveNext => isThai ? 'ย้ายไปถัดไป' : 'Move Next';
  String get moveToFirst => isThai ? 'ย้ายไปหน้าแรกสุด' : 'Move to First';
  String get moveToLast => isThai ? 'ย้ายไปหน้าท้ายสุด' : 'Move to Last';
  String get reorderOptionsTitle =>
      isThai ? 'จัดลำดับหน้า' : 'Reorder Page';
  String get clearAllConfirmTitle =>
      isThai ? 'ล้างรูปภาพทั้งหมด' : 'Clear All Images';
  String get clearAllConfirmMessage => isThai
      ? 'คุณแน่ใจหรือไม่ว่าต้องการลบรูปภาพทั้งหมดที่เลือกไว้?'
      : 'Are you sure you want to remove all selected images?';

  // Conversion Screen - Settings
  String get fileNameLabel => isThai ? 'ชื่อไฟล์ PDF' : 'PDF File Name';
  String get defaultFileName => isThai ? 'เอกสาร' : 'Document';
  String get mergeSingleTitle =>
      isThai ? 'รวมเป็น PDF ไฟล์เดียว' : 'Merge into single PDF';
  String mergeSingleSubtitle(int count) => count > 0
      ? (isThai
          ? 'รวมรูปภาพ $count รูปไว้ใน 1 ไฟล์ PDF เดียว'
          : 'Combine $count images into 1 PDF document')
      : (isThai
          ? 'รูปภาพทั้งหมดจะรวมอยู่ในไฟล์ PDF เดียว'
          : 'All images will be merged into a single PDF');
  String splitSubtitle(int count) => count > 0
      ? (isThai
          ? 'แยกสร้าง $count ไฟล์ PDF (1 ไฟล์ต่อ 1 รูปภาพ)'
          : 'Create $count separate PDF files (1 file per image)')
      : (isThai
          ? 'แต่ละรูปภาพจะถูกแยกเป็น PDF คนละไฟล์'
          : 'Each image will be saved as an individual PDF');
  String get quickPdfTitle => 'Quick PDF';
  String get quickPdfSubtitle => isThai
      ? 'สร้างและแชร์ PDF ทันทีหลังจากเลือกรูปภาพ'
      : 'Automatically create and share PDF immediately after picking images';

  // Conversion Screen - Actions
  String get saveToDisk => isThai ? 'บันทึกในเครื่อง' : 'Save to Device';
  String get generatingPdfWait => isThai
      ? 'กำลังสร้าง PDF กรุณารอสักครู่...'
      : 'Generating PDF, please wait...';

  // Shared Media Application Dialog
  String get sharedMediaTitle =>
      isThai ? 'ได้รับรูปภาพที่แชร์มา' : 'Shared Images Received';
  String sharedMediaQuestion(int count) => isThai
      ? 'ต้องการจัดการรูปภาพ $count รูปที่ได้รับอย่างไร?'
      : 'How would you like to handle the $count shared images?';
  String get appendCurrentList =>
      isThai ? 'เพิ่มต่อท้ายรายการเดิม' : 'Append to current list';
  String get appendCurrentListSubtitle => isThai
      ? 'เพิ่มรูปภาพต่อท้ายรายการรูปภาพเดิมที่มีอยู่'
      : 'Add these images to the end of the current list';
  String get createNewListFirst => isThai
      ? 'สร้างรายการใหม่ (แทรกเป็นรูปแรก)'
      : 'Create new list (insert as first element)';
  String get createNewListFirstSubtitle => isThai
      ? 'เริ่มรายการใหม่โดยวางรูปภาพนี้เป็นลำดับแรก'
      : 'Start a fresh list with these images as the first elements';
  String get replaceExisting => isThai ? 'แทนที่รูปเดิม' : 'Replace existing';
  String get appendToEnd => isThai ? 'เพิ่มต่อท้าย' : 'Append to list';

  // Messages & Snackbars
  String imagesAddedSuccess(int count) => isThai
      ? 'เพิ่มรูปภาพ $count รูปเรียบร้อยแล้ว'
      : 'Added $count images successfully';
  String imagesReplacedSuccess(int count) => isThai
      ? 'สร้างรายการใหม่ด้วย $count รูปภาพแล้ว'
      : 'Created new list with $count images';
  String cannotPickImages(dynamic e) =>
      isThai ? 'ไม่สามารถเลือกรูปภาพได้: $e' : 'Unable to select images: $e';
  String cannotOpenCamera(dynamic e) =>
      isThai ? 'ไม่สามารถเปิดกล้องได้: $e' : 'Unable to open camera: $e';
  String get selectAtLeastOneImage => isThai
      ? 'กรุณาเลือกรูปภาพอย่างน้อยหนึ่งรูป'
      : 'Please select at least one image';
  String get pdfCreatedSuccess =>
      isThai ? 'สร้าง PDF สำเร็จแล้ว!' : 'PDF created successfully!';
  String get pdfSharedSuccess =>
      isThai ? 'แชร์ PDF สำเร็จแล้ว!' : 'PDF shared successfully!';
  String cannotCreatePdf(dynamic e) =>
      isThai ? 'ไม่สามารถสร้าง PDF ได้: $e' : 'Failed to create PDF: $e';
  String errorOccurred(dynamic e) =>
      isThai ? 'เกิดข้อผิดพลาด: $e' : 'An error occurred: $e';
}

class AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['th', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
