import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../services/unified_storage_service.dart';

class DocumentUploadTestWidget extends StatefulWidget {
  const DocumentUploadTestWidget({Key? key}) : super(key: key);

  @override
  State<DocumentUploadTestWidget> createState() => _DocumentUploadTestWidgetState();
}

class _DocumentUploadTestWidgetState extends State<DocumentUploadTestWidget> {
  PlatformFile? _selectedFile;
  Uint8List? _fileBytes;
  bool _isLoading = false;
  String _testResults = '';

  Future<void> _pickFile() async {
    setState(() => _isLoading = true);
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _selectedFile = file;
          _fileBytes = file.bytes;
          _testResults += '✅ File selected: ${file.name} (${file.size} bytes)\\n';
        });
        
        if (kIsWeb) {
          _testResults += '✅ Web platform: File loaded as bytes\\n';
        } else {
          _testResults += '✅ Mobile platform: File path available\\n';
        }
      } else {
        setState(() {
          _testResults += '⚠️ No file selected\\n';
        });
      }
    } catch (e) {
      setState(() {
        _testResults += '❌ File picker error: $e\\n';
      });
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _testFileHandling() async {
    if (_selectedFile == null) {
      setState(() {
        _testResults += '❌ No file to test\\n';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _testResults += '\\n🧪 Testing file handling...\\n';
    });

    try {
      // Test storage service
      await UnifiedStorageService.saveData('test_file_name', _selectedFile!.name);
      final savedName = await UnifiedStorageService.getData('test_file_name');
      
      if (savedName == _selectedFile!.name) {
        setState(() {
          _testResults += '✅ Storage service working\\n';
        });
      }

      // Test platform compatibility
      setState(() {
        _testResults += 'Platform: ${kIsWeb ? 'Web' : 'Mobile'}\\n';
        _testResults += 'File name: ${_selectedFile!.name}\\n';
        _testResults += 'File size: ${_selectedFile!.size} bytes\\n';
        _testResults += 'Has bytes: ${_fileBytes != null}\\n';
        if (!kIsWeb) {
          _testResults += 'File path: ${_selectedFile!.path ?? 'Not available'}\\n';
        }
      });

      // Simulate upload preparation
      if (_fileBytes != null || (!kIsWeb && _selectedFile!.path != null)) {
        setState(() {
          _testResults += '✅ File ready for upload\\n';
        });
      }

    } catch (e) {
      setState(() {
        _testResults += '❌ File handling error: $e\\n';
      });
    }

    setState(() => _isLoading = false);
  }

  void _clearResults() {
    setState(() {
      _selectedFile = null;
      _fileBytes = null;
      _testResults = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Upload Test'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document Upload Functionality Test',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Platform: ${kIsWeb ? 'Web Browser' : 'Mobile App'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _pickFile,
                          icon: const Icon(Icons.file_upload),
                          label: Text(_selectedFile == null ? 'Pick File' : 'Change File'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _selectedFile == null || _isLoading ? null : _testFileHandling,
                          icon: const Icon(Icons.science),
                          label: const Text('Test Handling'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _clearResults,
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_selectedFile != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected File:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Name: ${_selectedFile!.name}'),
                      Text('Size: ${_selectedFile!.size} bytes'),
                      Text('Extension: ${_selectedFile!.extension ?? 'Unknown'}'),
                      if (!kIsWeb) Text('Path: ${_selectedFile!.path ?? 'Not available'}'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.terminal, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Test Results:',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            _testResults.isEmpty ? 'No tests run yet. Click "Pick File" to start.' : _testResults,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}