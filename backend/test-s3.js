// test-s3-v3.js - AWS SDK v3 version
import { S3Client, ListBucketsCommand, HeadBucketCommand, ListObjectsV2Command } from '@aws-sdk/client-s3';
import { STSClient, GetCallerIdentityCommand } from '@aws-sdk/client-sts';
import dotenv from 'dotenv';

dotenv.config();

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

async function testS3V3() {
  try {
    console.log('🔐 Testing AWS credentials...');
    
    // Test credentials
    const identity = await stsClient.send(new GetCallerIdentityCommand({}));
    console.log('✅ AWS credentials valid!');
    console.log(`   Account: ${identity.Account}`);
    
    console.log('\n📦 Testing S3 access...');
    
    // List buckets
    const buckets = await s3Client.send(new ListBucketsCommand({}));
    console.log('✅ S3 accessible!');
    console.log(`   Buckets: ${buckets.Buckets.length}`);
    
    // Test specific bucket
    const bucketName = process.env.AWS_BUCKET_NAME;
    await s3Client.send(new HeadBucketCommand({ Bucket: bucketName }));
    console.log(`✅ Bucket "${bucketName}" accessible!`);
    
    console.log('\n🎉 All tests passed!');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  }
}

testS3V3();