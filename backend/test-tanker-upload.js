// test-tanker-upload.js - Test tanker photo upload functionality
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Colors for console output
const colors = {
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  reset: '\x1b[0m',
  bold: '\x1b[1m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function logSuccess(message) {
  log(`✅ ${message}`, 'green');
}

function logError(message) {
  log(`❌ ${message}`, 'red');
}

function logInfo(message) {
  log(`ℹ️  ${message}`, 'blue');
}

// Test tanker upload functionality
async function testTankerUpload() {
  log('🚀 Testing Tanker Photo Upload Functionality', 'bold');
  log('=============================================', 'blue');

  try {
    // Create test image if it doesn't exist
    const testImagePath = path.join(__dirname, 'test-tanker.jpg');
    if (!fs.existsSync(testImagePath)) {
      logInfo('Creating test image...');
      // Create a simple test image (1x1 pixel JPEG)
      const testImageData = Buffer.from([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
        0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
        0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
        0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
        0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
        0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x01,
        0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
        0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0xFF, 0xC4,
        0x00, 0x14, 0x10, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xDA, 0x00, 0x0C,
        0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00, 0x55, 0xFF, 0xD9
      ]);
      fs.writeFileSync(testImagePath, testImageData);
      logSuccess('Test image created');
    }

    // Import form-data for multipart requests
    const FormData = (await import('form-data')).default;
    const fetch = (await import('node-fetch')).default;

    // Test data
    const testTankerData = {
      plateNumber: 'TEST123',
      capacity: '15000',
      driverName: 'Test Driver',
      driverContact: '1234567890',
      vendor: 'Test Vendor',
      latitude: '12.9716',
      longitude: '77.5946'
    };

    logInfo('Preparing test request...');
    
    // Create form data
    const formData = new FormData();
    Object.keys(testTankerData).forEach(key => {
      formData.append(key, testTankerData[key]);
    });
    formData.append('photo', fs.createReadStream(testImagePath));

    // Test upload
    logInfo('Sending test upload request...');
    const response = await fetch('http://localhost:3000/tanker', {
      method: 'POST',
      body: formData
    });

    const responseText = await response.text();
    let responseData;
    try {
      responseData = JSON.parse(responseText);
    } catch (e) {
      responseData = { message: responseText };
    }

    if (response.ok) {
      logSuccess('Upload test successful!');
      log(`Response: ${JSON.stringify(responseData, null, 2)}`, 'green');
      
      // Test GET endpoint
      logInfo('Testing data retrieval...');
      const getResponse = await fetch('http://localhost:3000/tanker');
      const getData = await getResponse.json();
      
      if (getResponse.ok) {
        logSuccess('Data retrieval successful!');
        log(`Found ${getData.data?.length || 0} tankers`, 'green');
      } else {
        logError('Data retrieval failed');
      }
    } else {
      logError(`Upload test failed: ${response.status} ${response.statusText}`);
      log(`Response: ${responseText}`, 'red');
    }

    // Cleanup
    if (fs.existsSync(testImagePath)) {
      fs.unlinkSync(testImagePath);
      logInfo('Test image cleaned up');
    }

  } catch (error) {
    logError(`Test failed: ${error.message}`);
    log(error.stack, 'red');
  }
}

// Check if server is running
async function checkServer() {
  try {
    const fetch = (await import('node-fetch')).default;
    const response = await fetch('http://localhost:3000/health');
    if (response.ok) {
      logSuccess('Server is running');
      return true;
    } else {
      logError('Server health check failed');
      return false;
    }
  } catch (error) {
    logError('Server is not running. Please start the server first:');
    log('npm start', 'yellow');
    return false;
  }
}

// Run test
async function runTest() {
  if (await checkServer()) {
    await testTankerUpload();
  }
}

runTest().catch(error => {
  logError(`Test runner failed: ${error.message}`);
  process.exit(1);
});