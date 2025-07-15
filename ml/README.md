# Weighbridge OCR System

A machine learning pipeline that automatically extracts GROSS, TARE, and NET weights from weighbridge slip photos using OCR (Optical Character Recognition).

## Features

- **Advanced OCR Processing**: Uses Tesseract OCR with image preprocessing for accurate text extraction
- **Multiple Format Support**: Handles various weighbridge slip formats and layouts
- **Weight Validation**: Validates extracted weights for logical consistency (GROSS = TARE + NET)
- **REST API**: FastAPI-based server for easy integration with mobile apps
- **Comprehensive Testing**: Full test suite with performance benchmarks
- **Error Handling**: Robust error handling and validation

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Image Input   │───▶│  OCR Processor  │───▶│  JSON Output    │
│                 │    │                 │    │                 │
│ • Mobile Photo  │    │ • Preprocessing │    │ • GROSS Weight  │
│ • File Upload   │    │ • Text Extract  │    │ • TARE Weight   │
│ • Base64 Data   │    │ • Weight Parse  │    │ • NET Weight    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Quick Start

### 1. Installation

```bash
# Clone the repository
cd ml/

# Run setup script (installs dependencies)
python setup.py

# Or install manually
pip install -r requirements.txt
```

### 2. Start the API Server

```bash
python main.py
```

The API will be available at `http://localhost:8000`

### 3. Test the API

```bash
# Run comprehensive tests
python test_ocr.py

# Or test with curl
curl -X POST "http://localhost:8000/extract-weights" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@your_weighbridge_image.jpg"
```

## API Endpoints

### POST `/extract-weights`

Extract GROSS, TARE, and NET weights from weighbridge slip image.

**Request:**
- **Method**: POST
- **Content-Type**: multipart/form-data
- **Body**: Image file (jpg, png, etc.)

**Response:**
```json
{
  "success": true,
  "data": {
    "gross_weight": "28000 Kg",
    "tare_weight": "12000 Kg",
    "net_weight": "16000 Kg",
    "validation_passed": true
  },
  "message": "Weights extracted successfully"
}
```

### POST `/extract-weights-detailed`

Extract weights with detailed debugging information.

**Response:**
```json
{
  "success": true,
  "data": {
    "gross_weight": "28000 Kg",
    "tare_weight": "12000 Kg",
    "net_weight": "16000 Kg",
    "validation_passed": true,
    "extracted_text": "WEIGHBRIDGE SLIP\nGROSS : 28000 Kg\n..."
  },
  "message": "Detailed weight extraction completed"
}
```

### POST `/validate-image`

Validate if uploaded image is suitable for OCR processing.

**Response:**
```json
{
  "success": true,
  "data": {
    "width": 800,
    "height": 600,
    "file_size": 245760,
    "file_type": "image/png",
    "is_valid": true,
    "issues": []
  },
  "message": "Image validation completed"
}
```

### GET `/health`

Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "service": "weighbridge-ocr-api"
}
```

## Flutter Integration

### 1. Add Dependencies

```yaml
dependencies:
  http: ^0.13.5
  image_picker: ^0.8.6
```

### 2. Upload Image to API

```dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

Future<Map<String, dynamic>> extractWeights(File imageFile) async {
  var request = http.MultipartRequest(
    'POST',
    Uri.parse('http://your-server:8000/extract-weights'),
  );
  
  request.files.add(
    await http.MultipartFile.fromPath('file', imageFile.path),
  );
  
  var response = await request.send();
  var responseBody = await response.stream.bytesToString();
  
  return json.decode(responseBody);
}

// Usage
final picker = ImagePicker();
final image = await picker.pickImage(source: ImageSource.camera);

if (image != null) {
  final result = await extractWeights(File(image.path));
  print('Gross: ${result['data']['gross_weight']}');
  print('Tare: ${result['data']['tare_weight']}');
  print('Net: ${result['data']['net_weight']}');
}
```

## Supported Formats

The system supports various weighbridge slip formats:

### Format 1: Standard Layout
```
GROSS : 28000 Kg
TARE  : 12000 Kg
NET   : 16000 Kg
```

### Format 2: Extended Labels
```
GROSS WEIGHT: 25,000 KG
TARE WEIGHT: 10,000 KG
NET WEIGHT: 15,000 KG
```

### Format 3: Compact Format
```
Gross: 30000
Tare: 15000
Net: 15000
```

## Image Requirements

- **Format**: JPG, PNG, BMP, TIFF
- **Resolution**: Minimum 200x200 pixels
- **File Size**: Maximum 10MB
- **Quality**: Clear, readable text
- **Orientation**: Any (system handles rotation)

## Performance

- **Processing Time**: ~2-3 seconds per image
- **Accuracy**: 95%+ on clear images
- **Memory Usage**: ~100MB per concurrent request
- **Throughput**: 20-30 images per minute

## Error Handling

The system provides comprehensive error handling:

```python
# Example error response
{
  "success": false,
  "error": "OCR processing failed: Could not extract readable text",
  "details": {
    "error_code": "OCR_FAILED",
    "suggestions": [
      "Ensure image is clear and well-lit",
      "Check image orientation",
      "Verify text is readable"
    ]
  }
}
```

## Development

### Project Structure
```
ml/
├── main.py              # FastAPI server
├── ocr_processor.py     # Core OCR logic
├── test_ocr.py          # Test suite
├── setup.py             # Installation script
├── requirements.txt     # Dependencies
└── README.md           # This file
```

### Running Tests

```bash
# Run all tests
python test_ocr.py

# Run specific test
python -m unittest test_ocr.TestWeighbridgeOCR.test_weight_parsing

# Run performance tests
python test_ocr.py --performance
```

### Adding New Formats

To support new weighbridge slip formats:

1. Update regex patterns in `ocr_processor.py`:
```python
patterns = {
    'gross_weight': [
        r'GROSS\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?',
        r'YOUR_NEW_PATTERN_HERE'
    ],
    # ... other patterns
}
```

2. Add test cases in `test_ocr.py`
3. Run tests to verify

## Deployment

### Docker Deployment

```dockerfile
FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    tesseract-ocr \
    libgl1-mesa-glx \
    libglib2.0-0

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
EXPOSE 8000

CMD ["python", "main.py"]
```

### Production Considerations

1. **Scaling**: Use gunicorn with multiple workers
2. **Security**: Add authentication and rate limiting
3. **Monitoring**: Implement health checks and logging
4. **Storage**: Add image caching and result storage
5. **Performance**: Use async processing for batch operations

## Troubleshooting

### Common Issues

1. **Tesseract not found**
   ```bash
   # macOS
   brew install tesseract
   
   # Ubuntu/Debian
   sudo apt-get install tesseract-ocr
   ```

2. **Poor OCR accuracy**
   - Ensure good image quality
   - Check lighting conditions
   - Verify text is clear and readable

3. **Memory issues**
   - Reduce image size before processing
   - Implement image compression
   - Use batch processing for multiple images

### Debug Mode

Enable debug logging:
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Support

For issues and questions:
- Create an issue in the repository
- Check the troubleshooting section
- Review the test cases for examples