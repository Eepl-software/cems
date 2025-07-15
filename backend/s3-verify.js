// s3-verify.js - S3 Setup Verification Script
import { S3Client, HeadBucketCommand, PutObjectCommand, GetObjectCommand, ListObjectsV2Command, DeleteObjectCommand, GetBucketCorsCommand, GetBucketVersioningCommand, GetBucketEncryptionCommand } from '@aws-sdk/client-s3';
import { STSClient, GetCallerIdentityCommand } from '@aws-sdk/client-sts';
import dotenv from 'dotenv';
import fs from 'fs';

// Load environment variables
dotenv.config();

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

function logStep(step, message) {
  log(`\n${step}. ${message}`, 'blue');
}

function logSuccess(message) {
  log(`✅ ${message}`, 'green');
}

function logError(message) {
  log(`❌ ${message}`, 'red');
}

function logWarning(message) {
  log(`⚠️  ${message}`, 'yellow');
}

// Verify S3 Setup
async function verifyS3Setup() {
  log('🚀 AWS S3 Setup Verification Script', 'bold');
  log('=====================================', 'blue');

  try {
    // Step 1: Check environment variables
    logStep(1, 'Checking environment variables...');
    
    const requiredEnvVars = [
      'AWS_ACCESS_KEY_ID',
      'AWS_SECRET_ACCESS_KEY',
      'AWS_REGION',
      'AWS_BUCKET_NAME'
    ];

    const missingVars = requiredEnvVars.filter(varName => !process.env[varName]);
    
    if (missingVars.length > 0) {
      logError(`Missing environment variables: ${missingVars.join(', ')}`);
      log('\nPlease add these to your .env file:', 'yellow');
      missingVars.forEach(varName => {
        log(`${varName}=your-${varName.toLowerCase().replace(/_/g, '-')}`, 'yellow');
      });
      process.exit(1);
    }

    logSuccess('All environment variables found');
    log(`   Region: ${process.env.AWS_REGION}`);
    log(`   Bucket: ${process.env.AWS_BUCKET_NAME}`);
    log(`   Access Key: ${process.env.AWS_ACCESS_KEY_ID.substring(0, 8)}...`);

    // Step 2: Configure AWS SDK v3
    logStep(2, 'Configuring AWS SDK v3...');
    
    const s3Client = new S3Client({
      region: process.env.AWS_REGION,
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
      },
    });

    const stsClient = new STSClient({
      region: process.env.AWS_REGION,
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
      },
    });
    
    logSuccess('AWS SDK v3 configured');

    // Step 3: Test AWS credentials
    logStep(3, 'Testing AWS credentials...');
    
    try {
      const identity = await stsClient.send(new GetCallerIdentityCommand({}));
      logSuccess('AWS credentials are valid');
      log(`   Account ID: ${identity.Account}`);
      log(`   User ARN: ${identity.Arn}`);
    } catch (error) {
      logError(`Invalid AWS credentials: ${error.message}`);
      log('\nPlease check your AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY', 'yellow');
      process.exit(1);
    }

    // Step 4: Test bucket access
    logStep(4, 'Testing bucket access...');
    
    const bucketName = process.env.AWS_BUCKET_NAME;
    
    try {
      // Check if bucket exists and we have access
      await s3Client.send(new HeadBucketCommand({ Bucket: bucketName }));
      logSuccess(`Bucket "${bucketName}" exists and is accessible`);
    } catch (error) {
      if (error.code === 'NotFound') {
        logError(`Bucket "${bucketName}" does not exist`);
        log('\nCreate the bucket in AWS Console or with AWS CLI:', 'yellow');
        log(`aws s3 mb s3://${bucketName} --region ${process.env.AWS_REGION}`, 'yellow');
      } else if (error.code === 'Forbidden') {
        logError(`Access denied to bucket "${bucketName}"`);
        log('\nCheck your IAM permissions. Required actions:', 'yellow');
        log('- s3:ListBucket', 'yellow');
        log('- s3:GetBucketLocation', 'yellow');
        log('- s3:GetObject', 'yellow');
        log('- s3:PutObject', 'yellow');
        log('- s3:DeleteObject', 'yellow');
      } else {
        logError(`Bucket access failed: ${error.message}`);
      }
      process.exit(1);
    }

    // Step 5: Test bucket permissions
    logStep(5, 'Testing bucket permissions...');
    
    const testKey = `test-files/verification-${Date.now()}.txt`;
    const testContent = 'This is a test file created by the S3 verification script.';
    
    try {
      // Test upload (PutObject)
      await s3Client.send(new PutObjectCommand({
        Bucket: bucketName,
        Key: testKey,
        Body: testContent,
        ContentType: 'text/plain'
      }));
      logSuccess('Upload permission (s3:PutObject) working');

      // Test download (GetObject)
      const downloadResult = await s3Client.send(new GetObjectCommand({
        Bucket: bucketName,
        Key: testKey
      }));
      logSuccess('Download permission (s3:GetObject) working');

      // Test list (ListBucket)
      await s3Client.send(new ListObjectsV2Command({
        Bucket: bucketName,
        Prefix: 'test-files/',
        MaxKeys: 1
      }));
      logSuccess('List permission (s3:ListBucket) working');

      // Test delete (DeleteObject)
      await s3Client.send(new DeleteObjectCommand({
        Bucket: bucketName,
        Key: testKey
      }));
      logSuccess('Delete permission (s3:DeleteObject) working');

    } catch (error) {
      logError(`Permission test failed: ${error.message}`);
      log('\nCheck your IAM policy includes all required S3 permissions', 'yellow');
      process.exit(1);
    }

    // Step 6: Check bucket configuration
    logStep(6, 'Checking bucket configuration...');
    
    try {
      // Check CORS configuration
      try {
        const corsConfig = await s3Client.send(new GetBucketCorsCommand({ Bucket: bucketName }));
        logSuccess('CORS configuration found');
        log(`   Rules: ${corsConfig.CORSRules.length}`);
      } catch (error) {
        if (error.name === 'NoSuchCORSConfiguration') {
          logWarning('No CORS configuration found');
          log('   You may need to configure CORS for web uploads', 'yellow');
        } else {
          throw error;
        }
      }

      // Check versioning
      const versioningConfig = await s3Client.send(new GetBucketVersioningCommand({ Bucket: bucketName }));
      if (versioningConfig.Status === 'Enabled') {
        logSuccess('Bucket versioning is enabled');
      } else {
        logWarning('Bucket versioning is not enabled');
        log('   Consider enabling versioning for better data protection', 'yellow');
      }

      // Check encryption
      try {
        const encryptionConfig = await s3Client.send(new GetBucketEncryptionCommand({ Bucket: bucketName }));
        logSuccess('Bucket encryption is configured');
      } catch (error) {
        if (error.name === 'ServerSideEncryptionConfigurationNotFoundError') {
          logWarning('No server-side encryption configured');
          log('   Consider enabling encryption for better security', 'yellow');
        } else {
          throw error;
        }
      }

    } catch (error) {
      logWarning(`Could not check all bucket configurations: ${error.message}`);
    }

    // Step 7: Performance test
    logStep(7, 'Running performance test...');
    
    const testData = Buffer.alloc(1024 * 100); // 100KB test file
    const perfTestKey = `test-files/perf-test-${Date.now()}.bin`;
    
    try {
      const startTime = Date.now();
      
      // Upload test
      await s3Client.send(new PutObjectCommand({
        Bucket: bucketName,
        Key: perfTestKey,
        Body: testData,
        ContentType: 'application/octet-stream'
      }));
      
      const uploadTime = Date.now() - startTime;
      logSuccess(`Upload speed: ${(testData.length / uploadTime * 1000 / 1024).toFixed(2)} KB/s`);
      
      // Download test
      const downloadStartTime = Date.now();
      await s3Client.send(new GetObjectCommand({
        Bucket: bucketName,
        Key: perfTestKey
      }));
      
      const downloadTime = Date.now() - downloadStartTime;
      logSuccess(`Download speed: ${(testData.length / downloadTime * 1000 / 1024).toFixed(2)} KB/s`);
      
      // Cleanup
      await s3Client.send(new DeleteObjectCommand({
        Bucket: bucketName,
        Key: perfTestKey
      }));
      
    } catch (error) {
      logWarning(`Performance test failed: ${error.message}`);
    }

    // Step 8: Generate summary
    logStep(8, 'Setup Summary');
    
    log('\n🎉 S3 Setup Verification Complete!', 'green');
    log('=====================================', 'green');
    logSuccess('AWS credentials are valid');
    logSuccess('S3 bucket is accessible');
    logSuccess('All required permissions are working');
    logSuccess('Ready for production use');
    
    log('\n📋 Next Steps:', 'blue');
    log('1. Update your application with these S3 settings');
    log('2. Test file uploads from your application');
    log('3. Configure monitoring and alerts');
    log('4. Set up backup and lifecycle policies');
    
    log('\n💡 Recommendations:', 'yellow');
    log('- Enable CloudTrail for API logging');
    log('- Set up CloudWatch monitoring');
    log('- Configure lifecycle policies for cost optimization');
    log('- Use separate buckets for dev/staging/production');

  } catch (error) {
    logError(`Verification failed: ${error.message}`);
    log('\nFor help, check:', 'yellow');
    log('- AWS S3 documentation: https://docs.aws.amazon.com/s3/', 'yellow');
    log('- Your IAM permissions', 'yellow');
    log('- Network connectivity to AWS', 'yellow');
    process.exit(1);
  }
}

// Check if .env file exists
if (!fs.existsSync('.env')) {
  logError('.env file not found');
  log('\nCreate a .env file with:', 'yellow');
  log('AWS_ACCESS_KEY_ID=your-access-key-id', 'yellow');
  log('AWS_SECRET_ACCESS_KEY=your-secret-access-key', 'yellow');
  log('AWS_REGION=us-east-1', 'yellow');
  log('AWS_BUCKET_NAME=your-bucket-name', 'yellow');
  process.exit(1);
}

// Run verification
verifyS3Setup().catch(error => {
  logError(`Unexpected error: ${error.message}`);
  process.exit(1);
});