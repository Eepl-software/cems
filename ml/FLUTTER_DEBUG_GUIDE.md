# 🔧 Flutter OCR Integration Debug Guide

## Issue: 400 Bad Request Error

### ✅ OCR Service Status: WORKING
The OCR service is functioning correctly and successfully extracting weights from test images.

### 🔍 Debugging Steps

#### 1. Check Flutter Console Output
After uploading an image in your Flutter app, check the console for:
```
OCR Response Status: [status_code]
OCR Response Body: [response_body]
```

#### 2. Common Issues & Solutions

##### Issue A: Network Connection
**Symptoms**: Network error in Flutter
**Solutions**:
```dart
// Make sure the OCR service URL is correct
static const String _ocrApiUrl = 'http://localhost:8000/extract-weights';

// For Android emulator, use:
static const String _ocrApiUrl = 'http://10.0.2.2:8000/extract-weights';

// For physical device, use your computer's IP:
static const String _ocrApiUrl = 'http://192.168.1.XXX:8000/extract-weights';
```

##### Issue B: File Path Issues
**Symptoms**: 400 error with file not found
**Solutions**:
```dart
// Add file existence check
if (!await File(_selectedImage!.path).exists()) {
  _showErrorSnackBar('Selected image file not found');
  return;
}
```

##### Issue C: CORS Issues (Web Flutter)
**Symptoms**: CORS policy errors
**Solutions**:
Add to your OCR service startup:
```python
# In main.py, update CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For development only
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)
```

#### 3. Test OCR Service Independently

##### Using curl:
```bash
curl -X POST "http://localhost:8000/extract-weights" \
  -F "file=@test_weighbridge_slip.png"
```

##### Using Python test script:
```bash
cd ml/
python3 test_upload.py test_weighbridge_slip.png
```

#### 4. Check Image Format

The OCR service accepts:
- PNG (.png)
- JPEG (.jpg, .jpeg) 
- BMP (.bmp)
- TIFF (.tiff)

#### 5. Flutter Debugging Code

Add this to your `_processImageWithOCR()` method:

```dart
Future<void> _processImageWithOCR() async {
  if (_selectedImage == null) return;

  print('🔍 DEBUG: Starting OCR processing...');
  print('🔍 DEBUG: Image path: ${_selectedImage!.path}');
  print('🔍 DEBUG: File exists: ${await File(_selectedImage!.path).exists()}');
  
  setState(() {
    _isProcessing = true;
    _errorMessage = null;
  });

  try {
    var request = http.MultipartRequest('POST', Uri.parse(_ocrApiUrl));
    
    print('🔍 DEBUG: OCR URL: $_ocrApiUrl');
    
    request.files.add(await http.MultipartFile.fromPath(
      'file', 
      _selectedImage!.path,
    ));
    
    print('🔍 DEBUG: Sending request...');
    var response = await request.send();
    var responseBody = await response.stream.bytesToString();

    print('🔍 DEBUG: Response Status: ${response.statusCode}');
    print('🔍 DEBUG: Response Body: $responseBody');

    if (response.statusCode == 200) {
      var data = json.decode(responseBody);
      
      if (data['success']) {
        var weights = data['data'];
        
        setState(() {
          _grossWeightController.text = weights['gross_weight'] ?? '';
          _tareWeightController.text = weights['tare_weight'] ?? '';
          _netWeightController.text = weights['net_weight'] ?? '';
        });
        
        _showSuccessSnackBar('Weights extracted successfully!');
      } else {
        _showErrorSnackBar('OCR processing failed: ${data['message']}');
      }
    } else {
      _showErrorSnackBar('Server error: ${response.statusCode} - $responseBody');
    }
  } catch (e) {
    print('🔍 DEBUG: Exception: $e');
    _showErrorSnackBar('Network error: $e');
  } finally {
    setState(() {
      _isProcessing = false;
    });
  }
}
```

### 🛠️ Quick Fixes

#### Fix 1: Update OCR URL for Your Platform

**For Android Emulator:**
```dart
static const String _ocrApiUrl = 'http://10.0.2.2:8000/extract-weights';
```

**For iOS Simulator:**
```dart
static const String _ocrApiUrl = 'http://localhost:8000/extract-weights';
```

**For Physical Device:**
Find your computer's IP address and use:
```dart
static const String _ocrApiUrl = 'http://192.168.1.XXX:8000/extract-weights';
```

#### Fix 2: Add Internet Permission (Android)

In `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

#### Fix 3: iOS Network Security (iOS)

In `ios/Runner/Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### 📊 Expected Successful Response

When working correctly, you should see:
```json
{
  "success": true,
  "data": {
    "gross_weight": "28000 KG",
    "tare_weight": "12000 KG", 
    "net_weight": "16000 KG",
    "validation_passed": true
  },
  "message": "Weights extracted successfully"
}
```

### 🚨 Common Error Messages

#### "Invalid file type"
- Check image format (PNG, JPEG, BMP, TIFF only)
- Ensure file has proper extension

#### "Network error: SocketException"
- Check OCR service is running (`python3 main.py`)
- Verify URL is correct for your platform
- Check firewall/network permissions

#### "Server error: 500"
- Check OCR service logs
- Verify Tesseract is installed in service
- Check image is not corrupted

### 🔄 Complete Test Procedure

1. **Start OCR Service:**
   ```bash
   cd ml/
   python3 main.py
   ```

2. **Test Service Health:**
   ```bash
   curl http://localhost:8000/health
   ```

3. **Test File Upload:**
   ```bash
   python3 test_upload.py test_weighbridge_slip.png
   ```

4. **Update Flutter URL:**
   ```dart
   // Use correct URL for your platform
   static const String _ocrApiUrl = 'http://10.0.2.2:8000/extract-weights';
   ```

5. **Run Flutter App:**
   ```bash
   flutter run
   ```

6. **Check Debug Output:**
   - Look for debug prints in Flutter console
   - Check for successful weight extraction

### 📞 Still Having Issues?

If the problem persists:

1. **Share the exact error message** from Flutter console
2. **Confirm OCR service is accessible** from your device/emulator
3. **Test with the debug code** above to get detailed logs
4. **Check network connectivity** between Flutter app and OCR service

---

**The OCR service is working perfectly - the issue is likely in the network connection or URL configuration between Flutter and the service.**