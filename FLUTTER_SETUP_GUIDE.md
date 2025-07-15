# 🚀 Flutter OCR Integration Setup Guide

## ✅ **OCR URLs Updated for All Platforms**

The cement.dart file has been updated with **platform-aware URL detection** that automatically uses the correct endpoints for different platforms.

### 🔧 **Automatic Platform Detection**

The app now automatically detects your platform and uses:

#### **Android Emulator:**
- OCR: `http://10.0.2.2:8000/extract-weights`
- Backend: `http://10.0.2.2:3000/api`

#### **iOS Simulator:**
- OCR: `http://localhost:8000/extract-weights`
- Backend: `http://localhost:3000/api`

#### **Other Platforms (Desktop/Web):**
- OCR: `http://localhost:8000/extract-weights`
- Backend: `http://localhost:3000/api`

### 📱 **For Physical Devices**

If you're testing on a **physical Android/iOS device**, you need to:

1. **Find your computer's IP address:**
   ```bash
   # On macOS/Linux:
   ifconfig | grep inet
   
   # On Windows:
   ipconfig
   
   # Look for something like: 192.168.1.100
   ```

2. **Update the custom URLs** in `cement.dart`:
   ```dart
   // Replace these lines (around line 38-39):
   static const String? _customOcrUrl = null;
   static const String? _customBackendUrl = null;
   
   // With your computer's IP:
   static const String? _customOcrUrl = 'http://192.168.1.100:8000/extract-weights';
   static const String? _customBackendUrl = 'http://192.168.1.100:3000/api';
   ```

### 🔍 **Enhanced Debug Features**

The updated cement.dart now includes:

1. **Platform Detection Debug:**
   ```
   🔍 DEBUG: Platform: android
   🔍 DEBUG: OCR URL: http://10.0.2.2:8000/extract-weights
   ```

2. **Connection Testing:**
   - Automatically tests OCR service health before upload
   - Shows detailed error messages

3. **File Validation:**
   - Checks if image file exists before upload
   - Validates file path and permissions

### 🛠️ **Setup Instructions**

#### **Step 1: Start OCR Service**
```bash
cd ml/
python3 main.py
```
You should see:
```
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

#### **Step 2: Start Backend Service**
```bash
cd backend/
node server.js
```

#### **Step 3: Test OCR Service**
```bash
cd ml/
python3 test_upload.py test_weighbridge_slip.png
```
Should show: `✅ Upload successful!`

#### **Step 4: Run Flutter App**

##### **For Android Emulator:**
```bash
flutter run
```
- App will automatically use `http://10.0.2.2:8000`
- No additional configuration needed

##### **For iOS Simulator:**
```bash
flutter run
```
- App will automatically use `http://localhost:8000`
- No additional configuration needed

##### **For Physical Device:**
1. Update the custom URLs in cement.dart (see above)
2. Ensure your device is on the same WiFi network
3. Run: `flutter run`

### 🔧 **Troubleshooting**

#### **Issue: "Cannot connect to OCR service"**

**For Android Emulator:**
- Ensure OCR service is running on `http://0.0.0.0:8000`
- Check that emulator can reach host: `adb shell ping 10.0.2.2`

**For Physical Device:**
- Update custom URLs with your computer's IP
- Ensure firewall allows connections on port 8000
- Test manually: `curl http://YOUR_IP:8000/health`

#### **Issue: Still getting 400 errors**

Check Flutter console for debug output:
```
🔍 DEBUG: Platform: android
🔍 DEBUG: OCR URL: http://10.0.2.2:8000/extract-weights
🔍 DEBUG: Testing OCR service connection...
🔍 DEBUG: Health check status: 200
🔍 DEBUG: Image path: /data/user/0/.../image.jpg
🔍 DEBUG: File exists: true
```

### 📋 **Quick Test Checklist**

1. **✅ OCR Service Running:**
   ```bash
   curl http://localhost:8000/health
   # Should return: {"status":"healthy"...}
   ```

2. **✅ Platform Detection Working:**
   - Check Flutter console for debug messages
   - Verify correct URL is being used

3. **✅ Network Connectivity:**
   - Health check passes before upload
   - No connection errors in logs

4. **✅ File Upload Working:**
   - Image selection successful
   - File exists check passes
   - Weights extracted successfully

### 🎯 **Expected Success Flow**

When everything works correctly, you'll see:

1. **In Flutter Console:**
   ```
   🔍 DEBUG: Platform: android
   🔍 DEBUG: OCR URL: http://10.0.2.2:8000/extract-weights
   🔍 DEBUG: Testing OCR service connection...
   🔍 DEBUG: Health check status: 200
   🔍 DEBUG: Image path: /storage/emulated/0/...
   🔍 DEBUG: File exists: true
   OCR Response Status: 200
   OCR Response Body: {"success":true,"data":{"gross_weight":"28000 KG"...}}
   ```

2. **In App:**
   - Green success message: "Weights extracted successfully!"
   - Form fields auto-filled with extracted weights
   - Ready to submit to backend

3. **In OCR Service Logs:**
   ```
   INFO: Received file: image.jpg, content_type: image/jpeg
   INFO: Successfully processed image in 2.5s
   ```

### 🚨 **Common Issues & Solutions**

| Issue | Solution |
|-------|----------|
| "Cannot connect to OCR service" | Check if OCR service is running, verify URL |
| 400 Bad Request | Enable debug logs, check file format |
| Network timeout | For physical devices, use computer's IP |
| File not found | Check image picker permissions |

### 📞 **Next Steps**

1. **Run your Flutter app** with the updated cement.dart
2. **Check Flutter console** for debug output
3. **Test image upload** and verify weights extraction
4. **Report any remaining issues** with the debug logs

The OCR integration is now **fully configured** for all platforms! 🎉