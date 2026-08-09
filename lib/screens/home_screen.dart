import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/pdf_file.dart';
import '../services/file_service.dart';
import '../services/pdf_service.dart';
import 'conversion_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FileService _fileService = FileService();
  final PdfService _pdfService = PdfService();
  List<PdfFile> _pdfFiles = [];
  bool _isLoading = true;
  String _version = '';
  late StreamSubscription _intentMediaStreamSubscription;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _initPackageInfo();

    // For sharing images coming from outside the app while the app is in the memory
    _intentMediaStreamSubscription = FlutterSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedFile> value) {
            if (value.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _handleSharedMedia(value);
              });
            }
          },
          onError: (err) {
            debugPrint("getMediaStream error: $err");
          },
        );

    // For sharing images coming from outside the app while the app is closed
    FlutterSharingIntent.instance.getInitialSharing().then((
      List<SharedFile> value,
    ) {
      if (value.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleSharedMedia(value);
        });
      }
    });
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
      });
    }
  }

  void _handleSharedMedia(List<SharedFile> sharedFiles) async {
    final imageFiles = sharedFiles
        .where((f) => f.type == SharedMediaType.IMAGE)
        .toList();
    if (imageFiles.isEmpty) return;

    final xFiles = imageFiles.map((f) => XFile(f.value!)).toList();
    FlutterSharingIntent.instance.reset();

    if (!mounted) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เลือกรูปแบบการสร้าง PDF'),
        content: const Text(
          'คุณได้รับรูปภาพที่แชร์มา คุณต้องการสร้าง PDF แบบใด?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'normal'),
            child: const Text('สร้างปกติ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'quick'),
            child: const Text('Quick PDF'),
          ),
        ],
      ),
    );

    if (choice == 'normal') {
      if (!mounted) return;
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConversionScreen(initialImages: xFiles),
        ),
      );
      if (result == true) {
        _loadFiles();
      }
    } else if (choice == 'quick') {
      await _processQuickExport(xFiles);
    }
  }

  @override
  void dispose() {
    _intentMediaStreamSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });
    final files = await _fileService.getPdfFiles();
    setState(() {
      _pdfFiles = files;
      _isLoading = false;
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _confirmDelete(PdfFile file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบ PDF'),
        content: Text('คุณแน่ใจหรือไม่ว่าต้องการลบ ${file.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _fileService.deletePdf(file.path);
              _loadFiles();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }

  void _showRetryShareDialog(Future<void> Function() onRetry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('การแชร์ไม่สำเร็จ'),
        content: const Text(
          'ดูเหมือนว่าการแชร์จะไม่สมบูรณ์ คุณต้องการลองอีกครั้งหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onRetry();
            },
            child: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }

  Future<void> _processQuickExport(List<XFile> images) async {
    try {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final paths = images.map((e) => e.path).toList();
      final pdfBytes = await _pdfService.createPdfFromImages(paths);
      final success = await _fileService.sharePdfBytes(pdfBytes, 'QuickPDF');
      if (mounted) Navigator.pop(context); // dismiss loading

      if (!success && mounted) {
        _showRetryShareDialog(() => _processQuickExport(images));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // dismiss loading if still showing
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  Future<void> _quickExport() async {
    final picker = ImagePicker();
    try {
      final List<XFile> images = await picker.pickMultiImage();
      if (images.isEmpty) return;
      await _processQuickExport(images);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('VibeQuickPDF'),
            if (_version.isNotEmpty)
              Text(
                'v$_version',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFiles),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pdfFiles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.picture_as_pdf,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ยังไม่มี PDF ที่สร้างขึ้น\nแตะที่ปุ่มด้านล่างเพื่อสร้างใหม่!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _pdfFiles.length,
              itemBuilder: (context, index) {
                final file = _pdfFiles[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  elevation: 2,
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.redAccent,
                      child: Icon(Icons.picture_as_pdf, color: Colors.white),
                    ),
                    title: Text(
                      file.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${DateFormat('MMM d, yyyy HH:mm').format(file.createdAt)} • ${_formatSize(file.size)}',
                    ),
                    onTap: () => _fileService.openPdf(file.path),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.blue),
                          onPressed: () async {
                            final success = await _fileService.sharePdf(
                              file.path,
                            );
                            if (!success && context.mounted) {
                              _showRetryShareDialog(
                                () => _fileService.sharePdf(file.path),
                              );
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _confirmDelete(file),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ConversionScreen(),
                        ),
                      );
                      if (result == true) {
                        _loadFiles();
                      }
                    },
                    icon: const Icon(Icons.add, size: 28),
                    label: const Text(
                      'สร้าง PDF',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 64,
                height: 64,
                child: ElevatedButton(
                  onPressed: _quickExport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Icon(Icons.bolt, size: 28),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
