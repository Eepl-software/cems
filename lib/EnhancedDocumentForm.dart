import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EnhancedDocumentForm extends StatefulWidget {
  @override
  _EnhancedDocumentFormState createState() => _EnhancedDocumentFormState();
}

class _EnhancedDocumentFormState extends State<EnhancedDocumentForm> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController _nameController = TextEditingController();
  TextEditingController _categoryController = TextEditingController();
  TextEditingController _tagsController = TextEditingController();
  PlatformFile? _selectedFile;
  bool _isLoading = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _selectedFile = result.files.first;
      });
    }
  }

  Future<void> _uploadDocument() async {
    if (!_formKey.currentState!.validate() || _selectedFile == null) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    // Fix URL construction issue by using Uri.http directly
    final uri = Uri.http('54.146.215.18:3000', '/api/documents');
    print('Document upload URL: $uri'); // Debug log
    final request = http.MultipartRequest(
      'POST',
      uri,
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['name'] = _nameController.text;
    request.fields['category'] = _categoryController.text;
    // Add tags as multiple fields
    final tags = _tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty);
    for (final tag in tags) {
      request.fields.addAll({'tags': tag});
    }
    request.files.add(await http.MultipartFile.fromPath('file', _selectedFile!.path!));
    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    setState(() => _isLoading = false);
    if (response.statusCode == 201 || response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload successful!')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $responseBody')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(controller: _nameController, decoration: InputDecoration(labelText: 'Name'), validator: (v) => v!.isEmpty ? 'Required' : null),
          TextFormField(controller: _categoryController, decoration: InputDecoration(labelText: 'Category'), validator: (v) => v!.isEmpty ? 'Required' : null),
          TextFormField(controller: _tagsController, decoration: InputDecoration(labelText: 'Tags (comma separated)')),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _pickFile, child: Text(_selectedFile == null ? 'Pick File' : _selectedFile!.name)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isLoading ? null : _uploadDocument,
            child: _isLoading ? CircularProgressIndicator() : Text('Upload'),
          ),
        ],
      ),
    );
  }
}
