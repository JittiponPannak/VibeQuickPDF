import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  
  final TextEditingController _fileNameController = TextEditingController(text: 'เอกสาร');

  @override
  void initState() {
    super.initState();
    if (widget.initialImages != null) {
      _selectedImages.addAll(widget.initialImages!);
    }
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
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
      _showError('ไม่สามารถเลือกรูปภาพได้: $e');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generatePdf() async {
    if (_selectedImages.isEmpty) {
      _showError('กรุณาเลือกรูปภาพอย่างน้อยหนึ่งรูป');
      return;
    }

    final fileName = _fileNameController.text.trim().isEmpty ? 'เอกสาร' : _fileNameController.text.trim();

    setState(() {
      _isGenerating = true;
    });

    try {
      if (_mergeIntoSingle) {
        // Generate single PDF with all images
        final paths = _selectedImages.map((e) => e.path).toList();
        final pdfBytes = await _pdfService.createPdfFromImages(paths);
        await _fileService.savePdf(fileName, pdfBytes);
      } else {
        // Generate one PDF per image
        for (int i = 0; i < _selectedImages.length; i++) {
          final pdfBytes = await _pdfService.createPdfFromImage(_selectedImages[i].path);
          final suffix = _selectedImages.length > 1 ? '_${i + 1}' : '';
          await _fileService.savePdf('$fileName$suffix', pdfBytes);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้าง PDF สำเร็จแล้ว!')));
        Navigator.pop(context, true); // Return true to indicate success and trigger reload
      }
    } catch (e) {
      if (mounted) {
        _showError('ไม่สามารถสร้าง PDF ได้: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สร้าง PDF'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate),
            onPressed: _pickImages,
            tooltip: 'เพิ่มรูปภาพ',
          )
        ],
      ),
      body: _isGenerating
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('กำลังสร้าง PDF กรุณารอสักครู่...'),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _fileNameController,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อไฟล์',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('รวมเป็น PDF ไฟล์เดียว'),
                  subtitle: Text(_mergeIntoSingle ? 'รูปภาพทั้งหมดจะอยู่ในเอกสาร PDF เดียว' : 'แต่ละรูปภาพจะถูกแยกเป็น PDF คนละไฟล์'),
                  value: _mergeIntoSingle,
                  onChanged: (value) {
                    setState(() {
                      _mergeIntoSingle = value;
                    });
                  },
                ),
                const Divider(),
                Expanded(
                  child: _selectedImages.isEmpty
                      ? const Center(child: Text('ยังไม่ได้เลือกรูปภาพ'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                          itemCount: _selectedImages.length,
                          itemBuilder: (context, index) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(_selectedImages[index].path),
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                                    onPressed: () => _removeImage(index),
                                  ),
                                ),
                                Positioned(
                                  bottom: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    color: Colors.black54,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: _selectedImages.isNotEmpty && !_isGenerating
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton.icon(
                    onPressed: _generatePdf,
                    icon: const Icon(Icons.picture_as_pdf, size: 28),
                    label: const Text('สร้าง PDF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
