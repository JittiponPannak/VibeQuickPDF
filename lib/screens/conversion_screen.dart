import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import '../l10n/app_localizations.dart';
import '../services/pdf_service.dart';
import '../services/file_service.dart';

class ConversionScreen extends StatefulWidget {
  final List<XFile>? initialImages;

  const ConversionScreen({super.key, this.initialImages});

  @override
  State<ConversionScreen> createState() => _ConversionScreenState();
}

class _ConversionScreenState extends State<ConversionScreen> {
  final ImagePicker _picker = ImagePicker();
  final PdfService _pdfService = PdfService();
  final FileService _fileService = FileService();

  final List<XFile> _selectedImages = [];
  bool _isGenerating = false;
  bool _mergeIntoSingle = true;
  bool _quickPdf = false;
  late StreamSubscription _intentMediaStreamSubscription;

  final TextEditingController _fileNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialImages != null) {
      _selectedImages.addAll(widget.initialImages!);
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
    _intentMediaStreamSubscription.cancel();
    _fileNameController.dispose();
    super.dispose();
  }

  void _handleSharedMedia(List<SharedFile> sharedFiles) async {
    final imageFiles = sharedFiles
        .where((f) => f.type == SharedMediaType.IMAGE)
        .toList();
    if (imageFiles.isEmpty) return;

    final xFiles = imageFiles.map((f) => XFile(f.value!)).toList();
    FlutterSharingIntent.instance.reset(); // clear it

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    if (_selectedImages.isEmpty) {
      setState(() {
        _selectedImages.addAll(xFiles);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.imagesAddedSuccess(xFiles.length)),
        ),
      );
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sharedMediaTitle),
        content: Text(
          l10n.sharedMediaQuestion(xFiles.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'replace'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.replaceExisting),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'append'),
            child: Text(l10n.appendToEnd),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );

    if (choice == 'append') {
      setState(() {
        _selectedImages.addAll(xFiles);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.imagesAddedSuccess(xFiles.length)),
          ),
        );
        if (_quickPdf) {
          _generatePdf(share: true);
        }
      }
    } else if (choice == 'replace') {
      setState(() {
        _selectedImages.clear();
        _selectedImages.addAll(xFiles);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.imagesReplacedSuccess(xFiles.length),
            ),
          ),
        );
        if (_quickPdf) {
          _generatePdf(share: true);
        }
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
        if (_quickPdf && mounted) {
          _generatePdf(share: true);
        }
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
        if (_quickPdf && mounted) {
          _generatePdf(share: true);
        }
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
    } catch (e) {
      if (mounted) {
        _showError(l10n.cannotCreatePdf(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
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
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _fileNameController,
              decoration: InputDecoration(
                labelText: l10n.fileNameLabel,
                hintText: l10n.defaultFileName,
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.description),
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
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.mergeSingleTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                _mergeIntoSingle
                    ? l10n.mergeSingleSubtitle(_selectedImages.length)
                    : l10n.splitSubtitle(_selectedImages.length),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              value: _mergeIntoSingle,
              onChanged: (value) {
                setState(() {
                  _mergeIntoSingle = value;
                });
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.amber, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    l10n.quickPdfTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                l10n.quickPdfSubtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              value: _quickPdf,
              onChanged: (value) {
                setState(() {
                  _quickPdf = value;
                });
                if (_quickPdf && _selectedImages.isNotEmpty) {
                  _generatePdf(share: true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
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
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
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
              Text(
                l10n.selectedImagesCount(_selectedImages.length),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
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
                return InkWell(
                  onTap: _showAddImageModal,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.grey.shade400,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey.shade100,
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
                );
              }

              final image = _selectedImages[index];
              return ClipRRect(
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
                            colors: [Colors.black54, Colors.transparent],
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
                  Text(l10n.generatingPdfWait),
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
                child: Row(
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
              ),
            )
          : null,
    );
  }
}
