import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/tanker_service.dart';

class TankerImageProcessor extends StatefulWidget {
  final Function(Map<String, dynamic>) onProcessingComplete;

  const TankerImageProcessor({
    Key? key,
    required this.onProcessingComplete,
  }) : super(key: key);

  @override
  State<TankerImageProcessor> createState() => _TankerImageProcessorState();
}

class _TankerImageProcessorState extends State<TankerImageProcessor> {
  final TankerService _tankerService = TankerService();
  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;
  String? _errorMessage;
  File? _imageFile;

  Future<void> _processImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _isProcessing = true;
        _errorMessage = null;
        _imageFile = File(pickedFile.path);
      });

      final result = await _tankerService.processTankerImage(_imageFile!);
      widget.onProcessingComplete(result);

      if (!result['success']) {
        setState(() {
          _errorMessage = result['message'];
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error processing image: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _processImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
            ),
            ElevatedButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _processImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose Photo'),
            ),
          ],
        ),
        if (_isProcessing)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        if (_imageFile != null && !_isProcessing)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Image.file(
              _imageFile!,
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
      ],
    );
  }
} 