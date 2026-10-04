import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/pdf_file.dart';
import '../services/file_service.dart';
import '../services/archive_service.dart';
import '../widgets/shared_media_dialog.dart';

import 'conversion_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FileService _fileService = FileService();
  List<PdfFile> _pdfFiles = [];
  bool _isLoading = true;
  bool _isConversionScreenOpen = false;
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
    if (_isConversionScreenOpen) return;

    final validPaths = sharedFiles
        .map((f) => f.value)
        .where((val) => val != null && val.isNotEmpty)
        .cast<String>()
        .toList();
    if (validPaths.isEmpty) return;

    FlutterSharingIntent.instance.reset();

    final archiveService = ArchiveService();
    final xFiles = await archiveService.resolveImagesFromSharedPaths(validPaths);

    if (xFiles.isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.noImagesInArchive)),
        );
      }
      return;
    }

    if (!mounted) return;

    final action = await showSharedMediaApplicationDialog(
      context: context,
      count: xFiles.length,
    );

    if (!mounted || action == null) return;

    final List<XFile> imagesToOpen;
    if (action == SharedMediaAction.append) {
      imagesToOpen = [...ConversionScreen.currentDraftImages, ...xFiles];
    } else {
      ConversionScreen.currentDraftImages.clear();
      imagesToOpen = xFiles;
    }
    ConversionScreen.currentDraftImages = List.from(imagesToOpen);

    _isConversionScreenOpen = true;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversionScreen(initialImages: imagesToOpen),
      ),
    );
    _isConversionScreenOpen = false;
    if (result == true) {
      _loadFiles();
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
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePdfTitle),
        content: Text(l10n.deletePdfConfirm(file.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _fileService.deletePdf(file.path);
              _loadFiles();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _showRetryShareDialog(Future<void> Function() onRetry) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.shareFailedTitle),
        content: Text(l10n.shareFailedMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onRetry();
            },
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Image.asset('assets/icon.png'),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.appTitle),
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
          PopupMenuButton<Locale?>(
            icon: const Icon(Icons.language),
            tooltip: l10n.changeLanguage,
            onSelected: (Locale? locale) {
              appLocaleNotifier.value = locale;
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: null,
                child: Row(
                  children: [
                    if (appLocaleNotifier.value == null)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(l10n.languageSystem),
                  ],
                ),
              ),
              PopupMenuItem(
                value: const Locale('th'),
                child: Row(
                  children: [
                    if (appLocaleNotifier.value?.languageCode == 'th')
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(l10n.languageThai),
                  ],
                ),
              ),
              PopupMenuItem(
                value: const Locale('en'),
                child: Row(
                  children: [
                    if (appLocaleNotifier.value?.languageCode == 'en')
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(l10n.languageEnglish),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: _loadFiles,
          ),
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
                    l10n.emptyPdfListMessage,
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
                    leading: CircleAvatar(
                      backgroundColor: file.path.toLowerCase().endsWith('.zip')
                          ? Colors.amber.shade700
                          : Colors.redAccent,
                      child: Icon(
                        file.path.toLowerCase().endsWith('.zip')
                            ? Icons.folder_zip
                            : Icons.picture_as_pdf,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      file.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${DateFormat('MMM d, yyyy HH:mm', l10n.locale.toString()).format(file.createdAt)} • ${_formatSize(file.size)}',
                    ),
                    onTap: () => _fileService.openPdf(file.path),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.blue),
                          tooltip: l10n.share,
                          onPressed: () async {
                            final success = await _fileService.sharePdf(
                              file.path,
                              shareText: l10n.shareWatermark,
                            );
                            if (!success && context.mounted) {
                              _showRetryShareDialog(
                                () => _fileService.sharePdf(
                                  file.path,
                                  shareText: l10n.shareWatermark,
                                ),
                              );
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: l10n.delete,
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
          child: SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton.icon(
              onPressed: () async {
                _isConversionScreenOpen = true;
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ConversionScreen(),
                  ),
                );
                _isConversionScreenOpen = false;
                if (result == true) {
                  _loadFiles();
                }
              },
              icon: const Icon(Icons.add, size: 28),
              label: Text(
                l10n.createPdf,
                style: const TextStyle(
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
      ),
    );
  }
}
