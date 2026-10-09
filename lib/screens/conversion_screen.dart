import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:open_filex/open_filex.dart';
import '../l10n/app_localizations.dart';
import '../services/pdf_service.dart';
import '../services/file_service.dart';
import '../services/archive_service.dart';
import '../widgets/shared_media_dialog.dart';

class ConversionScreen extends StatefulWidget {
  final List<XFile>? initialImages;
  static List<XFile> currentDraftImages = [];

  const ConversionScreen({super.key, this.initialImages});

  @override
  State<ConversionScreen> createState() => _ConversionScreenState();
}

class _ConversionScreenState extends State<ConversionScreen> {
  final ImagePicker _picker = ImagePicker();
  final PdfService _pdfService = PdfService();
  final FileService _fileService = FileService();
  final ArchiveService _archiveService = ArchiveService();

  final List<XFile> _selectedImages = [];
  bool _isGenerating = false;
  bool _isPreviewGenerating = false;
  File? _tempPreviewFile;
  String _exportType = 'PDF';
  bool _mergeIntoSingle = true;
  late StreamSubscription _intentMediaStreamSubscription;

  final TextEditingController _fileNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialImages != null) {
      _selectedImages.addAll(widget.initialImages!);
      ConversionScreen.currentDraftImages = List.from(_selectedImages);
    }

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
  }

  @override
  void dispose() {
    _cleanupTempPreviewFile();
    _intentMediaStreamSubscription.cancel();
    _fileNameController.dispose();
    super.dispose();
  }

  void _handleSharedMedia(List<SharedFile> sharedFiles) async {
    final validPaths = sharedFiles
        .map((f) => f.value)
        .where((val) => val != null && val.isNotEmpty)
        .cast<String>()
        .toList();
    if (validPaths.isEmpty) return;

    FlutterSharingIntent.instance.reset(); // clear it

    final xFiles =
        await _archiveService.resolveImagesFromSharedPaths(validPaths);

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
    final l10n = AppLocalizations.of(context);

    final action = await showSharedMediaApplicationDialog(
      context: context,
      count: xFiles.length,
    );

    if (!mounted || action == null) return;

    if (action == SharedMediaAction.append) {
      setState(() {
        _selectedImages.addAll(xFiles);
        ConversionScreen.currentDraftImages = List.from(_selectedImages);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.imagesAddedSuccess(xFiles.length)),
          ),
        );
      }
    } else if (action == SharedMediaAction.createNew) {
      setState(() {
        _selectedImages.clear();
        _selectedImages.addAll(xFiles);
        ConversionScreen.currentDraftImages = List.from(_selectedImages);
        _fileNameController.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.imagesReplacedSuccess(xFiles.length),
            ),
          ),
        );
      }
    } else if (action == SharedMediaAction.quickPdf) {
      await _processQuickExport(xFiles);
    }
  }

  Future<void> _processQuickExport(List<XFile> images) async {
    final l10n = AppLocalizations.of(context);
    bool dialogOpen = false;
    try {
      if (!mounted) return;

      dialogOpen = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    l10n.generatingPdfWait,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      ).then((_) => dialogOpen = false);

      final paths = images.map((e) => e.path).toList();
      final pdfBytes = await _pdfService.createPdfFromImages(paths);
      final success = await _fileService.sharePdfBytes(
        pdfBytes,
        'QuickPDF',
        shareText: l10n.shareWatermark,
      );

      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      if (!success && mounted) {
        _showRetryShareDialog(() => _processQuickExport(images));
      }
    } catch (e) {
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
      if (mounted) {
        _showError(l10n.cannotCreatePdf(e));
      }
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
        });
      }
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context).cannotPickImages(e));
      }
    }
  }

  Future<void> _captureFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        setState(() {
          _selectedImages.add(image);
        });
      }
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context).cannotOpenCamera(e));
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _reorderImages(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _selectedImages.length) return;
    if (newIndex < 0 || newIndex >= _selectedImages.length) return;

    setState(() {
      final item = _selectedImages.removeAt(oldIndex);
      _selectedImages.insert(newIndex, item);
    });
  }

  void _showReorderModal(int index) {
    final l10n = AppLocalizations.of(context);
    final image = _selectedImages[index];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(image.path),
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.pageNumber(index + 1),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.reorderHint,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: index > 0
                          ? () {
                              Navigator.pop(context);
                              _reorderImages(index, 0);
                            }
                          : null,
                      icon: const Icon(Icons.first_page, size: 20),
                      label: Text(l10n.moveToFirst),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: index > 0
                          ? () {
                              Navigator.pop(context);
                              _reorderImages(index, index - 1);
                            }
                          : null,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: Text(l10n.movePrevious),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: index < _selectedImages.length - 1
                          ? () {
                              Navigator.pop(context);
                              _reorderImages(index, index + 1);
                            }
                          : null,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: Text(l10n.moveNext),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: index < _selectedImages.length - 1
                          ? () {
                              Navigator.pop(context);
                              _reorderImages(index, _selectedImages.length - 1);
                            }
                          : null,
                      icon: const Icon(Icons.last_page, size: 20),
                      label: Text(l10n.moveToLast),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _removeImage(index);
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: Text(
                    l10n.delete,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _generatePdf({required bool share}) async {
    final l10n = AppLocalizations.of(context);
    if (_selectedImages.isEmpty) {
      _showError(l10n.selectAtLeastOneImage);
      return;
    }

    final fileName = _fileNameController.text.trim().isEmpty
        ? l10n.defaultFileName
        : _fileNameController.text.trim();

    setState(() {
      _isGenerating = true;
    });

    try {
      if (_exportType == 'PDF') {
        if (share) {
          bool success = false;
          if (_mergeIntoSingle) {
            final paths = _selectedImages.map((e) => e.path).toList();
            final pdfBytes = await _pdfService.createPdfFromImages(paths);
            success = await _fileService.sharePdfBytes(
              pdfBytes,
              fileName,
              shareText: l10n.shareWatermark,
            );
          } else {
            final files = <MapEntry<String, List<int>>>[];
            for (int i = 0; i < _selectedImages.length; i++) {
              final pdfBytes = await _pdfService.createPdfFromImage(
                _selectedImages[i].path,
              );
              final suffix = _selectedImages.length > 1 ? '_${i + 1}' : '';
              files.add(MapEntry('$fileName$suffix', pdfBytes));
            }
            success = await _fileService.shareMultiplePdfBytes(
              files,
              shareText: l10n.shareWatermark,
            );
          }

          if (mounted) {
            if (!success) {
              _showRetryShareDialog(() => _generatePdf(share: true));
            }
          }
        } else {
          if (_mergeIntoSingle) {
            // Generate single PDF with all images
            final paths = _selectedImages.map((e) => e.path).toList();
            final pdfBytes = await _pdfService.createPdfFromImages(paths);
            await _fileService.savePdf(fileName, pdfBytes);
          } else {
            // Generate one PDF per image
            for (int i = 0; i < _selectedImages.length; i++) {
              final pdfBytes = await _pdfService.createPdfFromImage(
                _selectedImages[i].path,
              );
              final suffix = _selectedImages.length > 1 ? '_${i + 1}' : '';
              await _fileService.savePdf('$fileName$suffix', pdfBytes);
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.pdfCreatedSuccess)));
            Navigator.pop(
              context,
              true,
            ); // Return true to indicate success and trigger reload
          }
        }
      } else {
        // Export as ZIP
        if (share) {
          bool success = false;
          if (_mergeIntoSingle) {
            final paths = _selectedImages.map((e) => e.path).toList();
            final zipBytes = await _archiveService.createZipFromImages(
              paths,
              baseFileName: fileName,
            );
            success = await _fileService.shareBytes(
              zipBytes,
              fileName,
              extension: 'zip',
              shareText: l10n.shareWatermark,
            );
          } else {
            final files = <MapEntry<String, List<int>>>[];
            for (int i = 0; i < _selectedImages.length; i++) {
              final suffix = _selectedImages.length > 1 ? '_${i + 1}' : '';
              final zipBytes = await _archiveService.createZipFromImage(
                _selectedImages[i].path,
                baseFileName: '$fileName$suffix',
              );
              files.add(MapEntry('$fileName$suffix', zipBytes));
            }
            success = await _fileService.shareMultipleBytes(
              files,
              extension: 'zip',
              shareText: l10n.shareWatermark,
            );
          }

          if (mounted) {
            if (!success) {
              _showRetryShareDialog(() => _generatePdf(share: true));
            }
          }
        } else {
          if (_mergeIntoSingle) {
            final paths = _selectedImages.map((e) => e.path).toList();
            final zipBytes = await _archiveService.createZipFromImages(
              paths,
              baseFileName: fileName,
            );
            await _fileService.saveZip(fileName, zipBytes);
          } else {
            for (int i = 0; i < _selectedImages.length; i++) {
              final suffix = _selectedImages.length > 1 ? '_${i + 1}' : '';
              final zipBytes = await _archiveService.createZipFromImage(
                _selectedImages[i].path,
                baseFileName: '$fileName$suffix',
              );
              await _fileService.saveZip('$fileName$suffix', zipBytes);
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.zipCreatedSuccess)));
            Navigator.pop(
              context,
              true,
            ); // Return true to indicate success and trigger reload
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showError(
          _exportType == 'PDF'
              ? l10n.cannotCreatePdf(e)
              : l10n.cannotCreateZip(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _cleanupTempPreviewFile() async {
    final file = _tempPreviewFile;
    _tempPreviewFile = null;
    if (file != null) {
      try {
        if (await file.exists()) {
          await file.delete();
          debugPrint("Temporary preview file deleted: ${file.path}");
        }
      } catch (e) {
        debugPrint("Error deleting temp preview file: $e");
      }
    }
  }

  Future<void> _previewPdf() async {
    final l10n = AppLocalizations.of(context);
    if (_selectedImages.isEmpty) {
      _showError(l10n.selectAtLeastOneImage);
      return;
    }

    final fileName = _fileNameController.text.trim().isEmpty
        ? l10n.defaultFileName
        : _fileNameController.text.trim();

    setState(() {
      _isGenerating = true;
      _isPreviewGenerating = true;
    });

    try {
      // Clean up previous temp preview file if any
      await _cleanupTempPreviewFile();

      final paths = _selectedImages.map((e) => e.path).toList();
      final pdfBytes = await _pdfService.createPdfFromImages(paths);
      final tempFile = await _fileService.createTempPdf(fileName, pdfBytes);
      _tempPreviewFile = tempFile;

      final openResult = await OpenFilex.open(tempFile.path);
      if (openResult.type != ResultType.done) {
        debugPrint("OpenFilex preview result: ${openResult.message}");
      }

      if (mounted) {
        _showPreviewModal(tempFile);
      }
    } catch (e) {
      if (mounted) {
        _showError(l10n.cannotCreatePdf(e));
      }
      await _cleanupTempPreviewFile();
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _isPreviewGenerating = false;
        });
      }
    }
  }

  void _showPreviewModal(File tempFile) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.picture_as_pdf,
                    color: Colors.redAccent,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.previewPdfTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.previewTempNotice,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (_tempPreviewFile != null) {
                          OpenFilex.open(_tempPreviewFile!.path);
                        }
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(l10n.reopenPreview),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(l10n.closePreview),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() async {
      await _cleanupTempPreviewFile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.previewClosedCleaned),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _showAddImageModal() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.addImagesTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade500,
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: Text(l10n.takePhotoOptionTitle),
                subtitle: Text(l10n.takePhotoOptionSubtitle),
                onTap: () {
                  Navigator.pop(context);
                  _captureFromCamera();
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.photo_library, color: Colors.white),
                ),
                title: Text(l10n.galleryOptionTitle),
                subtitle: Text(l10n.galleryOptionSubtitle),
                onTap: () {
                  Navigator.pop(context);
                  _pickImages();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearAll() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearAllConfirmTitle),
        content: Text(l10n.clearAllConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _selectedImages.clear();
              });
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.clearAll),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    final l10n = AppLocalizations.of(context);
    final isZip = _exportType == 'ZIP';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? Theme.of(context).colorScheme.outlineVariant
              : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _fileNameController,
              decoration: InputDecoration(
                labelText: isZip ? l10n.zipFileNameLabel : l10n.fileNameLabel,
                hintText: l10n.defaultFileName,
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: Icon(
                  isZip ? Icons.folder_zip_outlined : Icons.description,
                ),
                suffixIcon: _fileNameController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _fileNameController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _exportType,
              decoration: InputDecoration(
                labelText: l10n.exportFormatLabel,
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: Icon(
                  isZip ? Icons.folder_zip : Icons.picture_as_pdf,
                  color: isZip ? Colors.amber.shade800 : Colors.redAccent,
                ),
              ),
              items: const [
                DropdownMenuItem<String>(
                  value: 'PDF',
                  child: Text('PDF'),
                ),
                DropdownMenuItem<String>(
                  value: 'ZIP',
                  child: Text('ZIP'),
                ),
              ],
              onChanged: (String? value) {
                if (value != null && value != _exportType) {
                  setState(() {
                    _exportType = value;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                isZip ? l10n.mergeSingleZipTitle : l10n.mergeSingleTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                isZip
                    ? (_mergeIntoSingle
                        ? l10n.mergeSingleZipSubtitle(_selectedImages.length)
                        : l10n.splitZipSubtitle(_selectedImages.length))
                    : (_mergeIntoSingle
                        ? l10n.mergeSingleSubtitle(_selectedImages.length)
                        : l10n.splitSubtitle(_selectedImages.length)),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
              value: _mergeIntoSingle,
              onChanged: (value) {
                setState(() {
                  _mergeIntoSingle = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withAlpha(50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.emptyStateHubTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.emptyStateHubSubtitle,
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _captureFromCamera,
                      icon: const Icon(Icons.camera_alt),
                      label: Text(
                        l10n.takePhoto,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _pickImages,
                      icon: const Icon(Icons.photo_library),
                      label: Text(
                        l10n.chooseFromGallery,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagesGrid() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.selectedImagesCount(_selectedImages.length),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.reorderHint,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _showAddImageModal,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.addPhotoTile),
                  ),
                  TextButton(
                    onPressed: _confirmClearAll,
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text(l10n.clear),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount: _selectedImages.length + 1,
            itemBuilder: (context, index) {
              if (index == _selectedImages.length) {
                return DragTarget<int>(
                  onWillAcceptWithDetails: (details) =>
                      details.data != _selectedImages.length - 1,
                  onAcceptWithDetails: (details) {
                    _reorderImages(details.data, _selectedImages.length - 1);
                  },
                  builder: (context, candidateData, rejectedData) {
                    final isHovered = candidateData.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: isHovered
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2.5,
                              )
                            : null,
                      ),
                      child: InkWell(
                        onTap: _showAddImageModal,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Theme.of(context).colorScheme.outlineVariant
                                  : Colors.grey.shade400,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh
                                : Colors.grey.shade100,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: 32,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.addPhotoTile,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              }

              final image = _selectedImages[index];
              return DragTarget<int>(
                onWillAcceptWithDetails: (details) => details.data != index,
                onAcceptWithDetails: (details) {
                  _reorderImages(details.data, index);
                },
                builder: (context, candidateData, rejectedData) {
                  final isHovered = candidateData.isNotEmpty;
                  return LongPressDraggable<int>(
                    data: index,
                    delay: const Duration(milliseconds: 150),
                    feedback: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.transparent,
                      child: SizedBox(
                        width: 100,
                        height: 115,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(image.path),
                                fit: BoxFit.cover,
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2.5,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 4,
                              left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.25,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                              : Colors.grey.shade300,
                          child: const Center(
                            child: Icon(
                              Icons.swap_horiz,
                              color: Colors.grey,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: isHovered
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              )
                            : null,
                      ),
                      child: InkWell(
                        onTap: () => _showReorderModal(index),
                        borderRadius: BorderRadius.circular(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(image.path),
                                fit: BoxFit.cover,
                              ),
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                height: 36,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black54,
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black45,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.drag_indicator,
                                        color: Colors.white70,
                                        size: 12,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.createPdf),
        actions: [
          if (_selectedImages.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              onPressed: _isGenerating ? null : _previewPdf,
              tooltip: l10n.previewPdf,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _confirmClearAll,
              tooltip: l10n.clearAll,
            ),
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: _captureFromCamera,
              tooltip: l10n.takePhoto,
            ),
            IconButton(
              icon: const Icon(Icons.add_photo_alternate),
              onPressed: _pickImages,
              tooltip: l10n.chooseFromGallery,
            ),
          ],
        ],
      ),
      body: _isGenerating
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _isPreviewGenerating
                        ? l10n.preparingPreviewWait
                        : (_exportType == 'PDF'
                            ? l10n.generatingPdfWait
                            : l10n.generatingZipWait),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildSettingsSection(),
                const Divider(height: 1),
                Expanded(
                  child: _selectedImages.isEmpty
                       ? _buildEmptyState()
                      : _buildImagesGrid(),
                ),
              ],
            ),
      bottomNavigationBar: (!_isGenerating && _selectedImages.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _isGenerating ? null : _previewPdf,
                        icon: const Icon(Icons.visibility_outlined, size: 20),
                        label: Text(
                          l10n.previewPdf,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: () => _generatePdf(share: false),
                              icon: const Icon(Icons.save_alt, size: 22),
                              label: Text(
                                l10n.saveToDisk,
                                style: const TextStyle(
                                  fontSize: 15,
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
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: () => _generatePdf(share: true),
                              icon: const Icon(Icons.share, size: 22),
                              label: Text(
                                l10n.share,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
