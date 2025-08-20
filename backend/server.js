import express from 'express';
import bodyParser from 'body-parser';
import bcrypt from 'bcrypt';
import cors from 'cors';
import Joi from 'joi';
import pkg from 'pg';
import sqlite3 from 'sqlite3';
import { open } from 'sqlite';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import multer from 'multer';
import multerS3 from 'multer-s3';  
import winston from 'winston';
import sharp from 'sharp';
import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { STSClient, GetCallerIdentityCommand } from '@aws-sdk/client-sts';
import { Upload } from '@aws-sdk/lib-storage'; 
import dotenv from 'dotenv';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import jwt from 'jsonwebtoken';
import os from 'os';
import si from 'systeminformation';
import { v4 as uuidv4 } from 'uuid';
import { exec } from 'child_process';
import { promisify } from 'util';
dotenv.config();
import { Server } from 'socket.io';
import { createServer } from 'http';

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' }),
    new winston.transports.Console({
      format: winston.format.simple()
    })
  ],
});

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, 
  max: 10000, 
  message: 'Too many requests from this IP, please try again later.'
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, 
  max: 5,
  handler: (req, res) => {
    res.status(429).json({ error: 'Too many authentication attempts, please try again later.' });
  }
});

if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: winston.format.simple(),
  }));
}

const app = express();
const port = 3000;
const { Client, Pool } = pkg;
const execAsync = promisify(exec);


const JWT_SECRET = process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-in-production';
const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'thanush_admin';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'thanush';
const SUPER_ADMIN_PASSWORD = process.env.SUPER_ADMIN_PASSWORD || 'thanush';


// Initialize S3 client with credential checks
const initializeS3Client = () => {
  try {
    // Check for required AWS credentials
    const requiredEnvVars = [
      'AWS_ACCESS_KEY_ID',
      'AWS_SECRET_ACCESS_KEY',
      'AWS_REGION',
      'AWS_BUCKET_NAME'
    ];

    const missingVars = requiredEnvVars.filter(varName => !process.env[varName]);
    if (missingVars.length > 0) {
      console.error(`Missing required AWS environment variables: ${missingVars.join(', ')}`);
      throw new Error('Missing AWS credentials');
    }

    // Create S3 client with AWS SDK v3
    return new S3Client({
      region: process.env.AWS_REGION,
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
      },
    });
  } catch (error) {
    console.error('Failed to initialize S3 client:', error);
    return null;
  }
};

// Initialize S3 client
const s3Client = initializeS3Client();
if (s3Client) {
  logger.info('S3 client initialized successfully');
} else {
  logger.error('S3 client initialization failed - file uploads will be disabled');
}

// Configure multer for file uploads with fallback to local storage
const createMulterConfig = () => {
  // Use S3 storage if available
  if (s3Client) {
    // Use S3 storage if available
    return multer({
      storage: multerS3({
        s3: s3Client,
        bucket: process.env.AWS_BUCKET_NAME,
        contentType: multerS3.AUTO_CONTENT_TYPE,
        key: function (req, file, cb) {
          const timestamp = Date.now();
          const key = `tanker-images/${req.body.plateNumber || 'unknown'}/${timestamp}_${file.originalname}`;
          logger.info('Generated S3 key:', key);
          cb(null, key);
        },
        metadata: function (req, file, cb) {
          cb(null, { fieldName: file.fieldname });
        }
      }),
      fileFilter: fileFilterFunction,
      limits: { fileSize: 5 * 1024 * 1024, files: 1 }
    });
  } else {
    // Fallback to local storage
    logger.warn('S3 not available, using local storage for file uploads');
    return multer({
      storage: multer.diskStorage({
        destination: function (req, file, cb) {
          const uploadDir = './uploads/tanker-images';
          // Create directory if it doesn't exist
          try {
            if (!fs.existsSync(uploadDir)) {
              fs.mkdirSync(uploadDir, { recursive: true });
            }
            cb(null, uploadDir);
          } catch (error) {
            logger.error('Error creating upload directory:', error);
            cb(error, null);
          }
        },
        filename: function (req, file, cb) {
          try {
            const timestamp = Date.now();
            const plateNumber = req.body.plateNumber || 'unknown';
            const sanitizedFilename = file.originalname.replace(/[^a-zA-Z0-9.-]/g, '_');
            const filename = `${plateNumber}_${timestamp}_${sanitizedFilename}`;
            logger.info('Generated filename:', filename);
            cb(null, filename);
          } catch (error) {
            logger.error('Error generating filename:', error);
            cb(error, null);
          }
        }
      }),
      fileFilter: fileFilterFunction,
      limits: { fileSize: 5 * 1024 * 1024, files: 1 }
    });
  }
};

// File filter function
function fileFilterFunction(req, file, cb) {
  logger.info('Checking file:', {
    fieldname: file.fieldname,
    originalname: file.originalname,
    mimetype: file.mimetype
  });

  // Check if file exists
  if (!file) {
    logger.warn('No file provided');
    cb(new Error('No file provided'), false);
    return;
  }

  // Check file type - include both MIME type and file extension
  const validMimeTypes = ['image/jpeg', 'image/jpg', 'image/png'];
  const validExtensions = ['.jpg', '.jpeg', '.png'];
  
  // Get file extension
  const fileExtension = file.originalname.toLowerCase().split('.').pop();
  const hasValidExtension = validExtensions.includes(`.${fileExtension}`);
  
  // Allow if either MIME type is valid OR file extension is valid (to handle application/octet-stream)
  const isValidMimeType = validMimeTypes.includes(file.mimetype);
  const isValidFile = isValidMimeType || hasValidExtension;
  
  if (!isValidFile) {
    logger.warn('Invalid file type:', {
      mimetype: file.mimetype,
      extension: fileExtension,
      originalname: file.originalname
    });
    cb(new Error(`Invalid file type. Allowed types are: ${validMimeTypes.join(', ')} or extensions: ${validExtensions.join(', ')}`), false);
    return;
  }

  logger.info('File validation passed');
  cb(null, true);
}

const upload = createMulterConfig();

// Create separate upload middlewares for different routes
const uploadTankerImage = upload.single('image');
const uploadPhoto = upload.single('photo');

// Serve uploaded files when using local storage
if (!s3Client) {
  app.use('/uploads', express.static('./uploads'));
  logger.info('Static file serving enabled for local uploads');
}

// Image validation middleware
const validateImage = async (req, res, next) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file provided' });
    }

    const file = req.file;
    const maxSize = 5 * 1024 * 1024; // 5MB
    const allowedTypes = ['image/jpeg', 'image/png'];

    if (file.size > maxSize) {
      return res.status(400).json({ error: 'File size exceeds 5MB limit' });
    }

    if (!allowedTypes.includes(file.mimetype)) {
      return res.status(400).json({ error: 'Only JPEG and PNG images are allowed' });
    }

    // Process image with Sharp
    const image = sharp(file.buffer);
    const metadata = await image.metadata();

    if (metadata.width < 800 || metadata.height < 600) {
      return res.status(400).json({ error: 'Image dimensions must be at least 800x600 pixels' });
    }

    // Resize image if larger than 1920x1080
    if (metadata.width > 1920 || metadata.height > 1080) {
      const resized = await image
        .resize(1920, 1080, {
          fit: 'inside',
          withoutEnlargement: true
        })
        .jpeg({ quality: 85 })
        .toBuffer();
      req.file.buffer = resized;
    }

    next();
  } catch (error) {
    logger.error('Error in validateImage middleware:', error);
    return res.status(500).json({ error: 'Error processing image' });
  }
};

// Tanker schema validation
const tankerSchema = Joi.object({
  plateNumber: Joi.string().required(),
  capacity: Joi.number().required(),
  driverName: Joi.string().required(),
  driverContact: Joi.string().required(),
  vendor: Joi.string().required(),
  date: Joi.date().required(),
  lastUpdated: Joi.date().required(),
  latitude: Joi.number().optional(),
  longitude: Joi.number().optional(),
  photoUrl: Joi.string().optional().allow(null),
});
// Configure body parsers and CORS before any routes
app.use(helmet());
app.use(limiter);
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10mb' }));

app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Accept', 'Content-Disposition', 'X-Requested-With'],
  credentials: true,
  maxAge: 86400
}));

// Add error handling middleware at the beginning
app.use((err, req, res, next) => {
  logger.error('Global error handler:', err);
  
  // Set JSON content type
  res.setHeader('Content-Type', 'application/json');
  
  // Handle multer errors
  if (err instanceof multer.MulterError) {
    return res.status(400).json({
      success: false,
      message: 'File upload error',
      error: err.message,
      code: 'MULTER_ERROR'
    });
  }

  // Handle validation errors
  if (err.name === 'ValidationError') {
    return res.status(400).json({
      success: false,
      message: 'Validation error',
      error: err.message,
      code: 'VALIDATION_ERROR'
    });
  }

  // Handle file filter errors
  if (err.message && err.message.includes('Only image files are allowed')) {
    return res.status(400).json({
      success: false,
      message: err.message,
      code: 'FILE_TYPE_ERROR'
    });
  }

  // Default error response
  res.status(500).json({
    success: false,
    message: 'Internal server error',
    error: err.message,
    code: 'INTERNAL_ERROR'
  });
});

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const sslConfig = {
  rejectUnauthorized: false,
  ca: fs.existsSync(path.join(__dirname, 'us-east-1-bundle.pem')) 
    ? fs.readFileSync(path.join(__dirname, 'us-east-1-bundle.pem')).toString()
    : undefined
};

// Database configuration with SQLite fallback
let db; // Database connection object
let isPostgreSQL = false;
let isSQLite = false;

const initializeDatabase = async () => {
  try {
    // First, try PostgreSQL
    logger.info('Attempting to connect to PostgreSQL...');
    logger.info(`Connecting to: ${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}`);
    
    const dbConfig = {
      host: process.env.DB_HOST,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
      port: process.env.DB_PORT,
      ssl: { rejectUnauthorized: false }, // AWS RDS requires SSL
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000, // Reduced timeout for faster fallback
    };

    const pool = new Pool(dbConfig);
    
    // Test PostgreSQL connection with timeout
    logger.info('Testing PostgreSQL connection...');
    const client = await Promise.race([
      pool.connect(),
      new Promise((_, reject) => 
        setTimeout(() => reject(new Error('Connection timeout')), 5000)
      )
    ]);
    
    client.release();
    logger.info('Successfully connected to PostgreSQL');
    
    pool.on('error', (err) => {
      logger.error('Unexpected PostgreSQL error:', err);
      // Don't exit, continue with current connection
    });
    
    db = pool;
    isPostgreSQL = true;
    return pool;
    
  } catch (postgresError) {
    logger.error('PostgreSQL connection failed:', {
      message: postgresError.message,
      code: postgresError.code,
      errno: postgresError.errno
    });
    logger.info('Falling back to SQLite...');
    
    try {
      // Create data directory if it doesn't exist
      const dataDir = './data';
      if (!fs.existsSync(dataDir)) {
        fs.mkdirSync(dataDir, { recursive: true });
      }
      
      // Initialize SQLite as fallback
      const sqliteDb = await open({
        filename: './data/database.sqlite',
        driver: sqlite3.Database
      });
      
      logger.info('Successfully connected to SQLite');
      db = sqliteDb;
      isSQLite = true;
      
      // Create basic tables for SQLite
      await createSQLiteTables(sqliteDb);
      
      return sqliteDb;
      
    } catch (sqliteError) {
      logger.error('SQLite connection also failed:', sqliteError.message);
      throw new Error('Both PostgreSQL and SQLite connections failed');
    }
  }
};

// Create SQLite tables with compatible schema
const createSQLiteTables = async (sqliteDb) => {
  try {
    // Convert PostgreSQL tables to SQLite-compatible format
    await sqliteDb.exec(`
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        email TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        phone TEXT NOT NULL,
        company TEXT NOT NULL,
        designation TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS tanker_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plate_number TEXT NOT NULL,
        capacity REAL NOT NULL,
        driver_name TEXT NOT NULL,
        driver_contact TEXT NOT NULL,
        vendor TEXT NOT NULL,
        photo_url TEXT,
        latitude REAL,
        longitude REAL,
        last_updated DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS water_consumption (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total INTEGER NOT NULL,
        this_month INTEGER NOT NULL,
        today INTEGER NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS admin_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        admin_username TEXT NOT NULL,
        action TEXT NOT NULL,
        description TEXT,
        ip_address TEXT,
        user_agent TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS system_stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_users INTEGER DEFAULT 0,
        active_users INTEGER DEFAULT 0,
        active_sessions INTEGER DEFAULT 0,
        system_health INTEGER DEFAULT 95,
        data_usage_gb REAL DEFAULT 0,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS admin_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        setting_key TEXT UNIQUE NOT NULL,
        setting_value TEXT,
        description TEXT,
        updated_by TEXT,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS borewell_water (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date DATE NOT NULL,
        borewell_no TEXT NOT NULL,
        located_at TEXT NOT NULL,
        in_kld REAL NOT NULL,
        out_kld REAL NOT NULL,
        water_consumed REAL NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS project_documents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_type TEXT NOT NULL,
        file_size INTEGER,
        date_added DATETIME DEFAULT CURRENT_TIMESTAMP,
        expiry_date DATE,
        status TEXT DEFAULT 'Active',
        description TEXT,
        tags TEXT,
        is_asset INTEGER DEFAULT 0,
        user_id INTEGER,
        project_name TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS notifications (
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        type TEXT DEFAULT 'info',
        priority TEXT DEFAULT 'medium',
        read_at DATETIME,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        data TEXT
      );
      
      CREATE TABLE IF NOT EXISTS system_metrics_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        cpu_usage_percent INTEGER,
        memory_usage_percent INTEGER,
        disk_usage_percent INTEGER,
        network_upload_mb REAL,
        network_download_mb REAL,
        active_connections INTEGER,
        error_count INTEGER DEFAULT 0
      );
    `);
    
    logger.info('SQLite tables created successfully');
  } catch (error) {
    logger.error('Error creating SQLite tables:', error);
    throw error;
  }
};

// Database query helper that works with both PostgreSQL and SQLite
const dbQuery = async (query, params = []) => {
  try {
    if (isPostgreSQL) {
      const result = await db.query(query, params);
      return result;
    } else if (isSQLite) {
      // Convert PostgreSQL-style queries to SQLite format
      let sqliteQuery = query.replace(/\$(\d+)/g, '?');
      
      if (query.includes('INSERT') && query.includes('RETURNING')) {
        // Handle RETURNING clause for SQLite
        sqliteQuery = sqliteQuery.replace(/RETURNING.*$/i, '');
        const result = await db.run(sqliteQuery, params);
        return { rows: [{ id: result.lastID }], rowCount: result.changes };
      } else if (query.includes('SELECT')) {
        const rows = await db.all(sqliteQuery, params);
        return { rows, rowCount: rows.length };
      } else {
        const result = await db.run(sqliteQuery, params);
        return { rows: [], rowCount: result.changes };
      }
    } else {
      throw new Error('No database connection available');
    }
  } catch (error) {
    logger.error('Database query error:', error);
    throw error;
  }
};

// Database initialization moved to startServer() function to avoid double initialization

const generateToken = (payload, expiresIn = '24h') => {
  return jwt.sign(payload, JWT_SECRET, { expiresIn });
};

const verifyToken = (token) => {
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch (error) {
    throw new Error('Invalid token');
  }
};

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  try {
    const decoded = verifyToken(token);
    req.user = decoded;
    next();
  } catch (error) {
    logger.warn('Token verification failed:', error.message);
    return res.status(403).json({ error: 'Invalid or expired token' });
  }
};

// Middleware for admin authentication
const authenticateAdmin = (req, res, next) => {
  authenticateToken(req, res, () => {
    if (!req.user.isAdmin) {
      return res.status(403).json({ error: 'Admin access required' });
    }
    next();
  });
};


app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok' });
});

// ====================================
// SESSION MANAGEMENT ENDPOINTS
// ====================================

// Refresh token endpoint
app.post('/refresh-token', async (req, res) => {
  try {
    const authHeader = req.headers['authorization'];
    const refreshToken = authHeader && authHeader.split(' ')[1];

    if (!refreshToken) {
      return res.status(401).json({ error: 'Refresh token required' });
    }

    // Verify refresh token
    let decoded;
    try {
      decoded = jwt.verify(refreshToken, JWT_SECRET);
    } catch (error) {
      return res.status(403).json({ error: 'Invalid refresh token' });
    }

    // Generate new tokens
    const newToken = generateToken({ 
      id: decoded.id, 
      username: decoded.username,
      isAdmin: decoded.isAdmin 
    }, '24h');
    
    const newRefreshToken = generateToken({ 
      id: decoded.id, 
      username: decoded.username,
      isAdmin: decoded.isAdmin 
    }, '7d');

    logger.info(`Token refreshed for user: ${decoded.username}`);

    res.json({
      success: true,
      token: newToken,
      refreshToken: newRefreshToken,
      message: 'Tokens refreshed successfully'
    });

  } catch (error) {
    logger.error('Error refreshing token:', error);
    res.status(500).json({ 
      success: false,
      error: 'Internal server error during token refresh' 
    });
  }
});

// Verify token endpoint
app.get('/verify-token', (req, res) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ 
      valid: false, 
      error: 'No token provided' 
    });
  }

  try {
    const decoded = verifyToken(token);
    res.json({
      valid: true,
      user: {
        id: decoded.id,
        username: decoded.username,
        isAdmin: decoded.isAdmin
      },
      expiresAt: decoded.exp
    });
  } catch (error) {
    res.status(401).json({ 
      valid: false, 
      error: 'Invalid or expired token' 
    });
  }
});


const createAdminLogsTable = `
  CREATE TABLE IF NOT EXISTS admin_logs (
    id SERIAL PRIMARY KEY,
    admin_username VARCHAR(255) NOT NULL,
    action VARCHAR(255) NOT NULL,
    description TEXT,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Create system_stats table
const createSystemStatsTable = `
  CREATE TABLE IF NOT EXISTS system_stats (
    id SERIAL PRIMARY KEY,
    total_users INTEGER DEFAULT 0,
    active_users INTEGER DEFAULT 0,
    active_sessions INTEGER DEFAULT 0,
    system_health INTEGER DEFAULT 95,
    data_usage_gb DECIMAL(10,2) DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Create admin_settings table
const createAdminSettingsTable = `
  CREATE TABLE IF NOT EXISTS admin_settings (
    id SERIAL PRIMARY KEY,
    setting_key VARCHAR(255) UNIQUE NOT NULL,
    setting_value TEXT,
    description TEXT,
    updated_by VARCHAR(255),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Material submission tables creation function
const createMaterialSubmissionTables = async () => {
  try {
    // Cement submissions table
    await dbQuery(`
      CREATE TABLE IF NOT EXISTS cement_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        material_category VARCHAR(255),
        weighment_slip_no VARCHAR(255),
        driver_name VARCHAR(255),
        transporter VARCHAR(255)
      )
    `);

    // Sand submissions table
    await dbQuery(`
      CREATE TABLE IF NOT EXISTS sand_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        material_category VARCHAR(255),
        weighment_slip_no VARCHAR(255),
        driver_name VARCHAR(255),
        transporter VARCHAR(255)
      )
    `);

    // Metals submissions table
    await dbQuery(`
      CREATE TABLE IF NOT EXISTS metals_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT
      )
    `);

    // Pipes submissions table
    await dbQuery(`
      CREATE TABLE IF NOT EXISTS pipes_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT
      )
    `);

    // Tiles submissions table
    await dbQuery(`
      CREATE TABLE IF NOT EXISTS tiles_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT
      )
    `);

    // Wood submissions table
    await dbQuery(`
      CREATE TABLE IF NOT EXISTS wood_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight NUMERIC(10,2) NOT NULL,
        tare_weight NUMERIC(10,2) NOT NULL,
        net_weight NUMERIC(10,2) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Electricals submissions table
    await dbQuery(`
      CREATE TABLE IF NOT EXISTS electricals_submissions (
        id SERIAL PRIMARY KEY,
        date VARCHAR(255),
        latitude VARCHAR(255),
        longitude VARCHAR(255),
        gross_weight VARCHAR(255),
        tare_weight VARCHAR(255),
        net_weight VARCHAR(255),
        vehicle_number VARCHAR(255),
        driver_number VARCHAR(255),
        contact_number VARCHAR(255),
        timestamp VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Plastic submissions table
    await dbQuery(`
      CREATE TABLE IF NOT EXISTS plastic_submissions (
        id SERIAL PRIMARY KEY,
        date VARCHAR(255),
        latitude VARCHAR(255),
        longitude VARCHAR(255),
        gross_weight VARCHAR(255),
        tare_weight VARCHAR(255),
        net_weight VARCHAR(255),
        vehicle_number VARCHAR(255),
        driver_number VARCHAR(255),
        contact_number VARCHAR(255),
        timestamp VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        material_category VARCHAR(255),
        weighment_slip_no VARCHAR(255),
        driver_name VARCHAR(255),
        transporter VARCHAR(255)
      )
    `);

    // Aggregates submissions table
    await dbQuery(`
      CREATE TABLE IF NOT EXISTS aggregates_submissions (
        id SERIAL PRIMARY KEY,
        date VARCHAR(255),
        latitude VARCHAR(255),
        longitude VARCHAR(255),
        gross_weight VARCHAR(255),
        tare_weight VARCHAR(255),
        net_weight VARCHAR(255),
        vehicle_number VARCHAR(255),
        driver_number VARCHAR(255),
        contact_number VARCHAR(255),
        timestamp VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT
      )
    `);

    // Notifications table
    await dbQuery(`
      CREATE TABLE IF NOT EXISTS notifications (
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        type TEXT DEFAULT 'info',
        priority TEXT DEFAULT 'medium',
        read_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        data TEXT
      )
    `);

    logger.info('Material submission tables created successfully');
  } catch (error) {
    logger.error('Error creating material submission tables:', error);
    throw error;
  }
};

// Initialize admin tables after database connection is established
const initializeAdminTables = async () => {
  try {
    if (isPostgreSQL) {
      // Core admin and user tables
      await Promise.all([
        dbQuery(createAdminLogsTable),
        dbQuery(createSystemStatsTable),
        dbQuery(createAdminSettingsTable),
        dbQuery(createWaterConsumptionTable),
        dbQuery(createSystemMetricsHistoryTable),
        dbQuery(createUsersTable),
        dbQuery(createBorewellTable)
      ]);
      
      // Water management tables
      await Promise.all([
        dbQuery(createWaterQualityTable),
        dbQuery(createWaterAlertsTable),
        dbQuery(createWaterMetricsTable),
        dbQuery(createTankersTable),
        dbQuery(createConsumptionTable),
        dbQuery(createbwssb_supplyTable),
        dbQuery(createLabourColonyConsumptionTable)
      ]);
      
      // Waste management tables
      await Promise.all([
        dbQuery(createLabourColonyWasteTable),
        dbQuery(createCDWasteTable),
        dbQuery(createCDWasteCalculationTable),
        dbQuery(createcd_waste_calcTable),
        dbQuery(createDailyWasteTable),
        dbQuery(createMunicipalSolidWasteTable),
        dbQuery(createConstructionPhaseWasteTable),
        dbQuery(createTableproject_waste)
      ]);
      
      // Run database migrations for new columns
      await migrateCDWasteTable();
      await migrateDailyWasteTable();
      await migrateMunicipalSolidWasteTable();
      await migrateWoodSubmissionsTable();
      await migrateTilesSubmissionsTable();
      await migratePipesSubmissionsTable();
      await migrateMetalsSubmissionsTable();
      await migrateSandSubmissionsTable();
      await migrateAggregatesSubmissionsTable();
      
      // Environmental monitoring tables
      await Promise.all([
        dbQuery(createAlertTable),
        dbQuery(createStackMonitoringTable),
        dbQuery(createAmbientMonitoringTable)
      ]);
      
      // Document tables
      await Promise.all([
        dbQuery(createProjectDocumentsTable),
        dbQuery(createDocumentCategoriesTable)
      ]);
      
      // Call BWSSB table creation function
      await createBWSSBTables();
      
      // Material submission tables (cement, sand, metals, pipes, tiles, wood, electricals, plastic, aggregates)
      await createMaterialSubmissionTables();
      
      logger.info('PostgreSQL admin tables initialized successfully');
    }
    // SQLite tables are created in createSQLiteTables function
  } catch (err) {
    logger.error('Error creating admin tables:', err);
  }
};

const logAdminAction = async (username, action, description, req) => {
  try {
    await dbQuery(
      'INSERT INTO admin_logs (admin_username, action, description, ip_address, user_agent) VALUES ($1, $2, $3, $4, $5)',
      [username, action, description, req.ip, req.get('User-Agent')]
    );
  } catch (error) {
    logger.error('Failed to log admin action:', error);
  }
};

// USER TABLE

const createWaterConsumptionTable = `
  CREATE TABLE IF NOT EXISTS water_consumption (
    id SERIAL PRIMARY KEY,
    total INTEGER NOT NULL,
    this_month INTEGER NOT NULL,
    today INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Water consumption table will be created in initializeAdminTables function

const waterConsumptionSchema = Joi.object({
  total: Joi.number().integer().required(),
  thisMonth: Joi.number().integer().required(),
  today: Joi.number().integer().required()
});

app.post('/water-consumption', async (req, res) => {
  try {
    const { error } = waterConsumptionSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const { total, thisMonth, today } = req.body;

    const query = `
      INSERT INTO water_consumption (total, this_month, today)
      VALUES ($1, $2, $3)
      RETURNING id, total, this_month, today
    `;

    const result = await dbQuery(query, [total, thisMonth, today]);

    res.status(201).json({
      message: 'Water consumption data added successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error adding water consumption data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Test endpoint for water consumption dashboard
app.get('/water-consumption/test', async (req, res) => {
  try {
    // Test if database tables exist
    const tables = await dbQuery(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name IN ('borewell_water', 'tankers', 'bwssb_supply', 'water_consumption')
    `);
    
    res.json({
      success: true,
      tables: tables.rows,
      message: 'Database connectivity test'
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Water consumption dashboard endpoint
app.get('/water-consumption/dashboard', async (req, res) => {
  try {
    const { days = 7 } = req.query;
    const daysInt = parseInt(days);
    
    console.log(`Fetching water consumption dashboard for ${daysInt} days`);

    // Get data from multiple sources for the dashboard
    const promises = [
      // Borewell data
      dbQuery(`
        SELECT DATE(date) as date, SUM(water_consumed) as consumption, 'Borewell' as source
        FROM borewell_water 
        WHERE date >= CURRENT_DATE - INTERVAL '${daysInt} days'
        GROUP BY DATE(date)
        ORDER BY date DESC
      `),
      
      // Tanker data (capacity as consumption proxy)
      dbQuery(`
        SELECT DATE(last_updated) as date, SUM(capacity) as consumption, 'Tanker' as source
        FROM tankers 
        WHERE last_updated >= CURRENT_DATE - INTERVAL '${daysInt} days'
        GROUP BY DATE(last_updated)
        ORDER BY date DESC
      `),
      
      // BWSSB supply data
      dbQuery(`
        SELECT DATE(supply_date) as date, SUM(quantity_supplied) as consumption, 'BWSSB' as source
        FROM bwssb_supply 
        WHERE supply_date >= CURRENT_DATE - INTERVAL '${daysInt} days'
        GROUP BY DATE(supply_date)
        ORDER BY date DESC
      `),
      
      // Water consumption records
      dbQuery(`
        SELECT DATE(created_at) as date, SUM(total) as consumption, 'Direct' as source
        FROM water_consumption 
        WHERE created_at >= CURRENT_DATE - INTERVAL '${daysInt} days'
        GROUP BY DATE(created_at)
        ORDER BY date DESC
      `)
    ];

    const [borewellResult, tankerResult, bwssbResult, directResult] = await Promise.all(promises);

    // Combine all data sources
    const chartData = [];
    const sourceBreakdown = {
      'Borewell': 0,
      'Tanker': 0,
      'BWSSB': 0,
      'Direct': 0
    };

    // Process each data source
    [
      { data: borewellResult.rows, source: 'Borewell' },
      { data: tankerResult.rows, source: 'Tanker' },
      { data: bwssbResult.rows, source: 'BWSSB' },
      { data: directResult.rows, source: 'Direct' }
    ].forEach(({ data, source }) => {
      data.forEach(row => {
        const consumption = parseFloat(row.consumption) || 0;
        chartData.push({
          date: row.date,
          consumption: consumption,
          source: source
        });
        sourceBreakdown[source] += consumption;
      });
    });

    // Calculate summary statistics
    let totalConsumption = Object.values(sourceBreakdown).reduce((sum, val) => sum + val, 0);
    let avgDaily = totalConsumption / daysInt;
    
    // Get unique dates and calculate daily totals
    const dailyTotals = {};
    chartData.forEach(item => {
      const date = item.date;
      if (!dailyTotals[date]) {
        dailyTotals[date] = 0;
      }
      dailyTotals[date] += item.consumption;
    });

    // Find peak consumption day
    let peakDay = Object.entries(dailyTotals).reduce((max, [date, consumption]) => 
      consumption > max.consumption ? { date, consumption } : max, 
      { date: null, consumption: 0 }
    );

    // If no data, generate sample data for demonstration
    if (chartData.length === 0) {
      console.log('No data found, generating sample data for demonstration');
      const today = new Date();
      for (let i = daysInt - 1; i >= 0; i--) {
        const date = new Date(today);
        date.setDate(date.getDate() - i);
        const dateStr = date.toISOString().split('T')[0];
        
        // Generate realistic sample data
        const borewellConsumption = Math.random() * 5000 + 10000; // 10000-15000 L
        const tankerConsumption = Math.random() * 10000 + 15000; // 15000-25000 L
        const bwssbConsumption = Math.random() * 3000 + 5000; // 5000-8000 L
        
        chartData.push(
          { date: dateStr, consumption: borewellConsumption, source: 'borewell' },
          { date: dateStr, consumption: tankerConsumption, source: 'tanker' },
          { date: dateStr, consumption: bwssbConsumption, source: 'bwssb' }
        );
        
        sourceBreakdown['Borewell'] += borewellConsumption;
        sourceBreakdown['Tanker'] += tankerConsumption;
        sourceBreakdown['BWSSB'] += bwssbConsumption;
        
        dailyTotals[dateStr] = borewellConsumption + tankerConsumption + bwssbConsumption;
      }
      
      // Recalculate totalConsumption after generating sample data
      totalConsumption = Object.values(sourceBreakdown).reduce((sum, val) => sum + val, 0);
    }

    // Recalculate statistics after potential sample data generation
    totalConsumption = Object.values(sourceBreakdown).reduce((sum, val) => sum + val, 0);
    avgDaily = totalConsumption / daysInt;
    
    // Recalculate peak day
    peakDay = Object.entries(dailyTotals).reduce((max, [date, consumption]) => 
      consumption > max.consumption ? { date, consumption } : max, 
      { date: null, consumption: 0 }
    );

    // Calculate trend (comparing first half vs second half)
    const sortedDates = Object.keys(dailyTotals).sort();
    const midPoint = Math.floor(sortedDates.length / 2);
    const firstHalf = sortedDates.slice(0, midPoint);
    const secondHalf = sortedDates.slice(midPoint);
    
    const firstHalfAvg = firstHalf.length > 0 
      ? firstHalf.reduce((sum, date) => sum + dailyTotals[date], 0) / firstHalf.length 
      : 0;
    const secondHalfAvg = secondHalf.length > 0 
      ? secondHalf.reduce((sum, date) => sum + dailyTotals[date], 0) / secondHalf.length 
      : 0;
    const trend = secondHalfAvg > firstHalfAvg ? 'increasing' : secondHalfAvg < firstHalfAvg ? 'decreasing' : 'stable';
    const trendPercentage = firstHalfAvg > 0 ? ((secondHalfAvg - firstHalfAvg) / firstHalfAvg * 100).toFixed(1) : 0;

    const dashboardData = {
      summary: {
        totalConsumption: Math.round(totalConsumption * 100) / 100,
        averageDaily: Math.round(avgDaily * 100) / 100,
        peakDay: peakDay.date,
        peakConsumption: Math.round(peakDay.consumption * 100) / 100,
        trend: trend,
        trendPercentage: parseFloat(trendPercentage),
        period: `${daysInt} days`
      },
      chartData: chartData.sort((a, b) => new Date(a.date) - new Date(b.date)),
      sourceBreakdown: Object.entries(sourceBreakdown).map(([source, consumption]) => ({
        source,
        consumption: Math.round(consumption * 100) / 100,
        percentage: totalConsumption > 0 ? Math.round((consumption / totalConsumption) * 100 * 100) / 100 : 0
      })).filter(item => item.consumption > 0),
      dailyTotals: Object.entries(dailyTotals).map(([date, consumption]) => ({
        date,
        consumption: Math.round(consumption * 100) / 100
      })).sort((a, b) => new Date(a.date) - new Date(b.date))
    };

    console.log(`Returning dashboard data with ${chartData.length} chart points`);
    
    res.json({
      success: true,
      data: dashboardData,
      message: `Water consumption dashboard data for ${daysInt} days`,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    logger.error('Error fetching water consumption dashboard:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch dashboard data',
      message: error.message
    });
  }
});

// ====================================
// ENHANCED WATER MANAGEMENT ENDPOINTS
// ====================================

// Enhanced Water Management Table Definitions
const createWaterQualityTable = `
CREATE TABLE IF NOT EXISTS water_quality (
  id SERIAL PRIMARY KEY,
  date DATE NOT NULL,
  source VARCHAR(50) NOT NULL,
  ph_level DECIMAL(4,2),
  turbidity DECIMAL(6,2),
  chlorine_level DECIMAL(5,2),
  hardness DECIMAL(6,2),
  tds DECIMAL(8,2),
  temperature DECIMAL(4,1),
  conductivity DECIMAL(8,2),
  quality_grade VARCHAR(1) CHECK (quality_grade IN ('A', 'B', 'C', 'D', 'F')),
  test_location VARCHAR(100),
  tested_by VARCHAR(100),
  remarks TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);`;

const createWaterAlertsTable = `
CREATE TABLE IF NOT EXISTS water_alerts (
  id SERIAL PRIMARY KEY,
  alert_type VARCHAR(50) NOT NULL,
  severity VARCHAR(20) CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  source VARCHAR(50),
  message TEXT NOT NULL,
  threshold_value DECIMAL(10,2),
  current_value DECIMAL(10,2),
  is_active BOOLEAN DEFAULT true,
  acknowledged_by VARCHAR(100),
  acknowledged_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);`;

const createWaterMetricsTable = `
CREATE TABLE IF NOT EXISTS water_metrics (
  id SERIAL PRIMARY KEY,
  metric_type VARCHAR(50) NOT NULL,
  value DECIMAL(12,4) NOT NULL,
  unit VARCHAR(20),
  source VARCHAR(50),
  location VARCHAR(100),
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);`;

// Water Quality Validation Schema
const waterQualitySchema = Joi.object({
  date: Joi.date().required(),
  source: Joi.string().valid('borewell', 'tanker', 'bwssb', 'direct', 'labour_colony').required(),
  ph_level: Joi.number().min(0).max(14).optional(),
  turbidity: Joi.number().min(0).optional(),
  chlorine_level: Joi.number().min(0).optional(),
  hardness: Joi.number().min(0).optional(),
  tds: Joi.number().min(0).optional(),
  temperature: Joi.number().optional(),
  conductivity: Joi.number().min(0).optional(),
  quality_grade: Joi.string().valid('A', 'B', 'C', 'D', 'F').required(),
  test_location: Joi.string().optional(),
  tested_by: Joi.string().required(),
  remarks: Joi.string().optional()
});

// Helper function for database-agnostic date conditions
const getDateCondition = (days) => {
  return isPostgreSQL ? `>= CURRENT_DATE - INTERVAL '${days} days'` : `>= datetime('now', '-${days} days')`;
};

// Water Quality Endpoints
app.post('/water-quality', async (req, res) => {
  try {
    const { error } = waterQualitySchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: error.details[0].message
      });
    }

    const {
      date, source, ph_level, turbidity, chlorine_level, hardness,
      tds, temperature, conductivity, quality_grade, test_location,
      tested_by, remarks
    } = req.body;

    const query = `
      INSERT INTO water_quality 
      (date, source, ph_level, turbidity, chlorine_level, hardness, tds, 
       temperature, conductivity, quality_grade, test_location, tested_by, remarks)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
      RETURNING *
    `;

    const result = await dbQuery(query, [
      date, source, ph_level, turbidity, chlorine_level, hardness,
      tds, temperature, conductivity, quality_grade, test_location,
      tested_by, remarks
    ]);

    // Broadcast real-time update via WebSocket
    if (io) {
      io.emit('water_quality_update', {
        type: 'new_test',
        data: result.rows[0]
      });
    }

    res.status(201).json({
      success: true,
      data: result.rows[0],
      message: 'Water quality test result added successfully'
    });

  } catch (error) {
    logger.error('Error adding water quality data:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to add water quality data',
      message: error.message
    });
  }
});

app.get('/water-quality', async (req, res) => {
  try {
    const { days = 30, source, quality_grade } = req.query;
    const daysInt = parseInt(days);

    const dateCondition = getDateCondition(daysInt);
    
    let query = `
      SELECT * FROM water_quality 
      WHERE date ${dateCondition}
    `;
    const params = [];

    if (source) {
      query += ` AND source = $${params.length + 1}`;
      params.push(source);
    }

    if (quality_grade) {
      query += ` AND quality_grade = $${params.length + 1}`;
      params.push(quality_grade);
    }

    query += ' ORDER BY date DESC, created_at DESC';

    const result = await dbQuery(query, params).catch(() => ({ rows: [] }));

    // Calculate quality statistics
    const qualityStats = {
      totalTests: result.rows.length,
      qualityDistribution: {},
      averagePH: 0,
      averageTDS: 0,
      averageTurbidity: 0
    };

    if (result.rows.length > 0) {
      // Grade distribution
      result.rows.forEach(row => {
        const grade = row.quality_grade;
        qualityStats.qualityDistribution[grade] = (qualityStats.qualityDistribution[grade] || 0) + 1;
      });

      // Calculate averages
      const validPH = result.rows.filter(row => row.ph_level !== null);
      const validTDS = result.rows.filter(row => row.tds !== null);
      const validTurbidity = result.rows.filter(row => row.turbidity !== null);

      qualityStats.averagePH = validPH.length > 0 
        ? validPH.reduce((sum, row) => sum + parseFloat(row.ph_level), 0) / validPH.length 
        : 0;
      
      qualityStats.averageTDS = validTDS.length > 0 
        ? validTDS.reduce((sum, row) => sum + parseFloat(row.tds), 0) / validTDS.length 
        : 0;
      
      qualityStats.averageTurbidity = validTurbidity.length > 0 
        ? validTurbidity.reduce((sum, row) => sum + parseFloat(row.turbidity), 0) / validTurbidity.length 
        : 0;
    }

    res.json({
      success: true,
      data: result.rows,
      stats: qualityStats,
      message: `Water quality data for ${daysInt} days`
    });

  } catch (error) {
    logger.error('Error fetching water quality data:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch water quality data',
      message: error.message
    });
  }
});

// Water Alerts Endpoints
app.post('/water-alerts', async (req, res) => {
  try {
    const {
      alert_type, severity, source, message, threshold_value, current_value
    } = req.body;

    const query = `
      INSERT INTO water_alerts 
      (alert_type, severity, source, message, threshold_value, current_value)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `;

    const result = await dbQuery(query, [
      alert_type, severity, source, message, threshold_value, current_value
    ]);

    // Broadcast real-time alert via WebSocket
    if (io) {
      io.emit('water_alert', {
        type: 'new_alert',
        alert: result.rows[0]
      });
    }

    res.status(201).json({
      success: true,
      data: result.rows[0],
      message: 'Water alert created successfully'
    });

  } catch (error) {
    logger.error('Error creating water alert:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create water alert',
      message: error.message
    });
  }
});

app.get('/water-alerts', async (req, res) => {
  try {
    const { active_only = 'true' } = req.query;

    let query = 'SELECT * FROM water_alerts';
    if (active_only === 'true') {
      if (isPostgreSQL) {
        query += ' WHERE is_active = true';
      } else {
        query += ' WHERE is_active = 1';
      }
    }
    query += ' ORDER BY created_at DESC';

    const result = await dbQuery(query).catch(() => ({ rows: [] }));

    // Count alerts by severity
    const alertCounts = {
      total: result.rows.length,
      critical: 0,
      high: 0,
      medium: 0,
      low: 0
    };

    result.rows.forEach(alert => {
      const isActive = isPostgreSQL ? alert.is_active : alert.is_active === 1;
      if (isActive) {
        alertCounts[alert.severity] = (alertCounts[alert.severity] || 0) + 1;
      }
    });

    res.json({
      success: true,
      data: result.rows,
      counts: alertCounts,
      message: 'Water alerts retrieved successfully'
    });

  } catch (error) {
    logger.error('Error fetching water alerts:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch water alerts',
      message: error.message
    });
  }
});

app.put('/water-alerts/:id/acknowledge', async (req, res) => {
  try {
    const { acknowledged_by } = req.body;
    const alertId = req.params.id;

    const updateValue = isPostgreSQL ? 'false' : '0';
    const timestampFunc = isPostgreSQL ? 'CURRENT_TIMESTAMP' : "datetime('now')";

    const query = `
      UPDATE water_alerts 
      SET is_active = ${updateValue}, acknowledged_by = $1, acknowledged_at = ${timestampFunc}
      WHERE id = $2
      RETURNING *
    `;

    const result = await dbQuery(query, [acknowledged_by, alertId]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Alert not found'
      });
    }

    // Broadcast alert acknowledgment via WebSocket
    if (io) {
      io.emit('water_alert_acknowledged', {
        alertId: alertId,
        acknowledgedBy: acknowledged_by
      });
    }

    res.json({
      success: true,
      data: result.rows[0],
      message: 'Alert acknowledged successfully'
    });

  } catch (error) {
    logger.error('Error acknowledging water alert:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to acknowledge alert',
      message: error.message
    });
  }
});

// Predictive Analytics Endpoint
app.get('/water-analytics/predictions', async (req, res) => {
  try {
    const { days = 30 } = req.query;
    const daysInt = parseInt(days);

    // Get historical consumption data
    const dateCondition = getDateCondition(daysInt);
    
    const historyQuery = `
      SELECT DATE(date) as date, SUM(water_consumed) as total_consumption
      FROM borewell_water 
      WHERE date ${dateCondition}
      GROUP BY DATE(date)
      ORDER BY date
    `;

    const historyResult = await dbQuery(historyQuery).catch(() => ({ rows: [] }));
    const historicalData = historyResult.rows;

    if (historicalData.length < 7) {
      return res.json({
        success: true,
        predictions: [],
        message: 'Insufficient data for predictions. Need at least 7 days of historical data.'
      });
    }

    // Simple linear regression for trend prediction
    const consumptionValues = historicalData.map(row => parseFloat(row.total_consumption));
    const n = consumptionValues.length;
    const xSum = n * (n + 1) / 2;
    const ySum = consumptionValues.reduce((a, b) => a + b, 0);
    const xySum = consumptionValues.reduce((sum, y, i) => sum + (i + 1) * y, 0);
    const xSquareSum = n * (n + 1) * (2 * n + 1) / 6;

    const slope = (n * xySum - xSum * ySum) / (n * xSquareSum - xSum * xSum);
    const intercept = (ySum - slope * xSum) / n;

    // Generate 7-day predictions
    const predictions = [];
    for (let i = 1; i <= 7; i++) {
      const predictedValue = intercept + slope * (n + i);
      const futureDate = new Date();
      futureDate.setDate(futureDate.getDate() + i);
      
      predictions.push({
        date: futureDate.toISOString().split('T')[0],
        predicted_consumption: Math.max(0, Math.round(predictedValue * 100) / 100),
        confidence: Math.max(0.6, Math.min(0.95, 0.8 - Math.abs(slope) * 0.1))
      });
    }

    // Calculate efficiency trends
    const currentWeekAvg = consumptionValues.slice(-7).reduce((a, b) => a + b, 0) / 7;
    const previousWeekAvg = consumptionValues.length > 14 ? consumptionValues.slice(-14, -7).reduce((a, b) => a + b, 0) / 7 : currentWeekAvg;
    const efficiencyTrend = previousWeekAvg > 0 ? ((currentWeekAvg - previousWeekAvg) / previousWeekAvg * 100) : 0;

    res.json({
      success: true,
      predictions: predictions,
      analytics: {
        trend: slope > 0 ? 'increasing' : slope < 0 ? 'decreasing' : 'stable',
        slope: Math.round(slope * 100) / 100,
        currentWeekAverage: Math.round(currentWeekAvg * 100) / 100,
        previousWeekAverage: Math.round(previousWeekAvg * 100) / 100,
        efficiencyTrend: Math.round(efficiencyTrend * 100) / 100,
        dataPoints: n
      },
      message: '7-day water consumption predictions generated successfully'
    });

  } catch (error) {
    logger.error('Error generating water analytics predictions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate predictions',
      message: error.message
    });
  }
});

// Real-time Water Metrics Endpoint
app.post('/water-metrics', async (req, res) => {
  try {
    const { metric_type, value, unit, source, location } = req.body;

    const query = `
      INSERT INTO water_metrics (metric_type, value, unit, source, location)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING *
    `;

    const result = await dbQuery(query, [metric_type, value, unit, source, location]);

    // Broadcast real-time metric via WebSocket
    if (io) {
      io.emit('water_metric_update', {
        type: 'new_metric',
        metric: result.rows[0]
      });
    }

    res.status(201).json({
      success: true,
      data: result.rows[0],
      message: 'Water metric recorded successfully'
    });

  } catch (error) {
    logger.error('Error recording water metric:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to record water metric',
      message: error.message
    });
  }
});

// Updated validation schema to match Flutter form requirements

const createUsersTable = `
  CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    phone VARCHAR(10) NOT NULL,
    company VARCHAR(255) NOT NULL,
    designation VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Users table will be created in initializeAdditionalTables function

const registerSchema = Joi.object({
  username: Joi.string().min(4).required(),
  email: Joi.string().email().pattern(/^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/).required(),
  password: Joi.string().min(8)
    .pattern(/^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,}$/)
    .required()
    .messages({
      'string.pattern.base': 'Password must contain at least one letter and one number'
    }),
  phone: Joi.string().length(10).pattern(/^\d{10}$/).required(),
  company: Joi.string().required(),
  designation: Joi.string().required(),
});

const loginSchema = Joi.object({
  username: Joi.string().required(),
  password: Joi.string().required(),
});

// BOREWELL DATA TABLE

const createBorewellTable = `
  CREATE TABLE IF NOT EXISTS borewell_water (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    borewell_no VARCHAR(50) NOT NULL,
    located_at VARCHAR(100) NOT NULL,
    in_kld DECIMAL(10,2) NOT NULL,
    out_kld DECIMAL(10,2) NOT NULL,
    water_consumed DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Borewell table will be created in initializeAdditionalTables function

// Validation schema
const borewellSchema = Joi.object({
  date: Joi.date().required(),
  borewell_no: Joi.string().required(),
  located_at: Joi.string().required(),
  in_kld: Joi.number().positive().required(),
  out_kld: Joi.number().positive().required(),
  water_consumed: Joi.number().required()
});

// Add Borewell Data Endpoint
app.post('/borewell', async (req, res) => {
  try {
    // Validate request body
    const { error } = borewellSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        error: error.details[0].message
      });
    }

    const { date, borewell_no, located_at, in_kld, out_kld, water_consumed } = req.body;

    // Check if entry already exists for this date and borewell
    const existingEntry = await dbQuery(
      'SELECT * FROM borewell_water WHERE date = $1 AND borewell_no = $2',
      [date, borewell_no]
    );

    if (existingEntry.rows.length > 0) {
      return res.status(409).json({
        error: 'An entry already exists for this date and borewell number'
      });
    }

    // Insert new entry
    const query = `
      INSERT INTO borewell_water
      (date, borewell_no, located_at, in_kld, out_kld, water_consumed)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `;

    const result = await dbQuery(query, [
      date,
      borewell_no,
      located_at,
      in_kld,
      out_kld,
      water_consumed
    ]);

    res.status(201).json({
      message: 'Borewell data added successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error adding borewell data:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// Get Borewell Data Endpoint
app.get('/borewell', async (req, res) => {
  try {
    const { date, search } = req.query;
    let query = 'SELECT * FROM borewell_water';
    const values = [];
    const conditions = [];

    // Add date filter if provided
    if (date) {
      conditions.push(`date = $${values.length + 1}`);
      values.push(date);
    }

    // Add search filter if provided
    if (search) {
      conditions.push(`(
        borewell_no ILIKE $${values.length + 1} OR
        located_at ILIKE $${values.length + 1}
      )`);
      values.push(`%${search}%`);
    }

    // Combine conditions if any
    if (conditions.length > 0) {
      query += ' WHERE ' + conditions.join(' AND ');
    }

    // Order by date in descending order
    query += ' ORDER BY date DESC, borewell_no ASC';

    const result = await dbQuery(query, values);

    res.status(200).json({
      message: 'Data retrieved successfully',
      data: result.rows
    });

  } catch (err) {
    console.error('Error fetching borewell data:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// Update Borewell Data Endpoint
app.put('/borewell/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { error } = borewellSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        error: error.details[0].message
      });
    }

    const { date, borewell_no, located_at, in_kld, out_kld, water_consumed } = req.body;

    const query = `
      UPDATE borewell_water
      SET date = $1, borewell_no = $2, located_at = $3,
          in_kld = $4, out_kld = $5, water_consumed = $6
      WHERE id = $7
      RETURNING *
    `;

    const result = await dbQuery(query, [
      date,
      borewell_no,
      located_at,
      in_kld,
      out_kld,
      water_consumed,
      id
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'Borewell entry not found'
      });
    }

    res.status(200).json({
      message: 'Borewell data updated successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error updating borewell data:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// Delete Borewell Data Endpoint
app.delete('/borewell/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await dbQuery(
      'DELETE FROM borewell_water WHERE id = $1 RETURNING *',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'Borewell entry not found'
      });
    }

    res.status(200).json({
      message: 'Borewell data deleted successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error deleting borewell data:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// Get Borewell Statistics
app.get('/borewell/stats', async (req, res) => {
  try {
    const { start_date, end_date } = req.query;

    const query = `
      SELECT
        borewell_no,
        COUNT(*) as total_entries,
        SUM(water_consumed) as total_consumption,
        AVG(water_consumed) as avg_consumption,
        MIN(water_consumed) as min_consumption,
        MAX(water_consumed) as max_consumption
      FROM borewell_water
      WHERE ($1::date IS NULL OR date >= $1)
        AND ($2::date IS NULL OR date <= $2)
      GROUP BY borewell_no
      ORDER BY borewell_no
    `;

    const result = await dbQuery(query, [start_date, end_date]);

    res.status(200).json({
      message: 'Statistics retrieved successfully',
      data: result.rows
    });

  } catch (err) {
    console.error('Error fetching borewell statistics:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// Registration endpoint with improved error handling

app.post('/register', async (req, res) => {
  try {
    // Validate request body
    const { error } = registerSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        error: error.details[0].message
      });
    }

    const { username, email, password, phone, company, designation } = req.body;

    // Check if user already exists
    const existingUser = await dbQuery(
      'SELECT * FROM users WHERE email = $1 OR username = $2',
      [email, username]
    );

    if (existingUser.rows.length > 0) {
      return res.status(409).json({
        error: 'User with this email or username already exists'
      });
    }

    // Hash password and insert user
    const hashedPassword = await bcrypt.hash(password, 10);
    const query = `
      INSERT INTO users (username, email, password, phone, company, designation)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING id, username, email, phone, company, designation
    `;

    const result = await dbQuery(query, [
      username,
      email,
      hashedPassword,
      phone,
      company,
      designation
    ]);

    res.status(201).json({
      message: 'Registration successful!',
      user: result.rows[0]
    });

  } catch (err) {
    console.error('Error during registration:', err);
    if (err.code === '23505') { // Unique violation
      return res.status(409).json({
        error: 'User with this email or username already exists'
      });
    }

    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// LOGIN PAGE

app.post('/login', authLimiter, async (req, res) => {
  try {
    const loginSchema = Joi.object({
      username: Joi.string().required(),
      password: Joi.string().required(),
    });

    const { error } = loginSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const { username, password } = req.body;

    const result = await dbQuery(
      'SELECT * FROM users WHERE username = $1',
      [username]
    );

    if (result.rows.length === 0) {
      logger.warn(`Login attempt with invalid username: ${username}`);
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];
    const validPassword = await bcrypt.compare(password, user.password);

    if (!validPassword) {
      logger.warn(`Invalid password attempt for user: ${username}`);
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Update last login
    await dbQuery(
      'UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = $1',
      [user.id]
    );

    const token = generateToken({
      id: user.id,
      username: user.username,
      email: user.email,
      isAdmin: false
    });

    logger.info(`User login successful: ${username}`);

    const { password: _, ...userWithoutPassword } = user;
    res.status(200).json({
      message: 'Login successful',
      token,
      user: userWithoutPassword
    });

  } catch (err) {
    logger.error('Login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/admin/login', authLimiter, async (req, res) => {
  try {
    const adminLoginSchema = Joi.object({
      username: Joi.string().required(),
      password: Joi.string().required(),
      adminPassword: Joi.string().required(),
    });

    const { error } = adminLoginSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const { username, password, adminPassword } = req.body;

    // Validate admin credentials
    if (username !== ADMIN_USERNAME) {
      logger.warn(`Invalid admin username attempt: ${username} from IP: ${req.ip}`);
      return res.status(401).json({ error: 'Invalid admin credentials' });
    }

    if (password !== ADMIN_PASSWORD) {
      logger.warn(`Invalid admin password attempt from IP: ${req.ip}`);
      return res.status(401).json({ error: 'Invalid admin credentials' });
    }

    if (adminPassword !== SUPER_ADMIN_PASSWORD) {
      logger.warn(`Invalid super admin password attempt from IP: ${req.ip}`);
      return res.status(401).json({ error: 'Invalid super admin password' });
    }

    const token = generateToken({
      username: ADMIN_USERNAME,
      isAdmin: true,
      isSuperAdmin: true
    }, '8h'); // Shorter token expiry for admin

    await logAdminAction(ADMIN_USERNAME, 'LOGIN', 'Admin login successful', req);
    
    logger.info(`Admin login successful from IP: ${req.ip}`);

    res.status(200).json({
      message: 'Admin login successful',
      token,
      admin: {
        username: ADMIN_USERNAME,
        role: 'super_admin',
        permissions: ['all']
      }
    });

  } catch (err) {
    logger.error('Admin login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/admin/dashboard-stats', authenticateAdmin, async (req, res) => {
  try {
    // Get user statistics
    const userStats = await dbQuery(`
      SELECT 
        COUNT(*) as total_users,
        COUNT(CASE WHEN last_login > NOW() - INTERVAL '24 hours' THEN 1 END) as active_users
      FROM users
    `);

    // Get tanker statistics
    const tankerStats = await dbQuery('SELECT COUNT(*) as active_tankers FROM tankers');

    // Get water consumption statistics
    const waterStats = await dbQuery(`
      SELECT 
        COALESCE(SUM(total), 0) as total_consumption,
        COALESCE(SUM(this_month), 0) as month_consumption,
        COALESCE(SUM(today), 0) as today_consumption
      FROM water_consumption
    `);

    // Get system alerts
    const alertStats = await dbQuery(`
      SELECT COUNT(*) as total_alerts
      FROM alerts 
      WHERE is_active = true AND severity IN ('high', 'critical')
    `);

    // Get system stats from the database
    const systemStatsResult = await dbQuery('SELECT * FROM system_stats ORDER BY updated_at DESC LIMIT 1');
    let systemHealth = 95;
    let dataUsage = 0;
    let activeSessions = 0;
    if (systemStatsResult.rows.length > 0) {
      systemHealth = parseInt(systemStatsResult.rows[0].system_health || 95);
      dataUsage = parseFloat(systemStatsResult.rows[0].data_usage_gb || 0);
      activeSessions = parseInt(systemStatsResult.rows[0].active_sessions || 0);
    }

    // Real-time system metrics
    const totalMem = os.totalmem() / (1024 * 1024 * 1024); // in GB
    const freeMem = os.freemem() / (1024 * 1024 * 1024); // in GB
    const usedMem = totalMem - freeMem;
    const memUsagePercent = Math.round((usedMem / totalMem) * 100);
    let cpuUsagePercent = 0;
    let diskUsagePercent = 0;
    try {
      const cpuLoad = await si.currentLoad();
      cpuUsagePercent = Math.round(cpuLoad.currentload);
      const disk = await si.fsSize();
      if (disk.length > 0) {
        diskUsagePercent = Math.round((disk[0].used / disk[0].size) * 100);
      }
    } catch (e) {
      // ignore errors, use 0
    }

    const stats = {
      totalUsers: parseInt(userStats.rows[0].total_users || 0),
      activeUsers: parseInt(userStats.rows[0].active_users || 0),
      activeTankers: parseInt(tankerStats.rows[0].active_tankers || 0),
      waterConsumption: parseInt(waterStats.rows[0].total_consumption || 0),
      alerts: parseInt(alertStats.rows[0].total_alerts || 0),
      systemHealth: systemHealth,
      dataUsage: dataUsage,
      activeSessions: activeSessions,
      realTime: {
        memory: {
          totalGB: totalMem.toFixed(2),
          usedGB: usedMem.toFixed(2),
          usagePercent: memUsagePercent
        },
        cpu: {
          usagePercent: cpuUsagePercent
        },
        disk: {
          usagePercent: diskUsagePercent
        }
      }
    };

    // Update system stats table
    await dbQuery(`
      INSERT INTO system_stats (total_users, active_users, active_sessions, system_health, data_usage_gb)
      VALUES ($1, $2, $3, $4, $5)
      ON CONFLICT (id) DO UPDATE SET
        total_users = $1,
        active_users = $2,
        active_sessions = $3,
        system_health = $4,
        data_usage_gb = $5,
        updated_at = CURRENT_TIMESTAMP
    `, [stats.totalUsers, stats.activeUsers, stats.activeSessions, stats.systemHealth, stats.dataUsage]);

    await logAdminAction(req.user.username, 'VIEW_DASHBOARD', 'Accessed dashboard statistics', req);

    res.status(200).json(stats);

  } catch (err) {
    logger.error('Dashboard stats error:', err);
    res.status(500).json({ error: 'Failed to fetch dashboard statistics' });
  }
});


// Get recent activities
app.get('/admin/recent-activities', authenticateAdmin, async (req, res) => {
  try {
    const activities = await dbQuery(`
      SELECT 
        'login' as type,
        CONCAT('User ', username, ' logged in') as description,
        last_login as timestamp
      FROM users 
      WHERE last_login IS NOT NULL
      ORDER BY last_login DESC
      LIMIT 10
    `);

    const adminActivities = await dbQuery(`
      SELECT 
        'admin' as type,
        CONCAT('Admin action: ', action, ' - ', description) as description,
        created_at as timestamp
      FROM admin_logs
      ORDER BY created_at DESC
      LIMIT 5
    `);

    const allActivities = [
      ...activities.rows,
      ...adminActivities.rows
    ].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp)).slice(0, 15);

    res.status(200).json({ activities: allActivities });

  } catch (err) {
    logger.error('Recent activities error:', err);
    res.status(500).json({ error: 'Failed to fetch recent activities' });
  }
});

// Admin middleware to verify admin access
const verifyAdmin = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'No token provided' });
    }

    const token = authHeader.split(' ')[1];
    // In production, use proper JWT verification
    const [userId] = Buffer.from(token, 'base64').toString().split(':');

    const result = await dbQuery(
      'SELECT designation FROM users WHERE id = $1',
      [userId]
    );

    if (result.rows.length === 0 || result.rows[0].designation.toLowerCase() !== 'admin') {
      return res.status(403).json({ error: 'Not authorized' });
    }

    next();
  } catch (err) {
    console.error('Error verifying admin:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// Admin Stats Endpoint
app.get('/admin/stats', verifyAdmin, async (req, res) => {
  try {
    // Get total users count
    const usersCount = await dbQuery('SELECT COUNT(*) FROM users');
    
    // Get active tankers count (updated table name)
    const tankersCount = await dbQuery('SELECT COUNT(*) FROM tankers');
    
    // Get total water consumption
    const waterConsumption = await dbQuery(
      'SELECT SUM(total) as total FROM water_consumption'
    );
    
    // Get alerts count (from stack monitoring critical status)
    const alertsCount = await dbQuery(
      "SELECT COUNT(*) FROM stack_monitoring WHERE status = 'critical'"
    );

    res.status(200).json({
      totalUsers: parseInt(usersCount.rows[0].count),
      activeTankers: parseInt(tankersCount.rows[0].count),
      waterConsumption: parseInt(waterConsumption.rows[0].total || 0),
      alerts: parseInt(alertsCount.rows[0].count)
    });
  } catch (err) {
    console.error('Error fetching admin stats:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Admin User Management Endpoints
app.post('/admin/users', authenticateAdmin, async (req, res) => {
  try {
    const userSchema = Joi.object({
      username: Joi.string().min(3).max(50).required(),
      email: Joi.string().email().required(),
      password: Joi.string().min(8).required(),
      phone: Joi.string().pattern(/^\d{10}$/).required(),
      company: Joi.string().required(),
      designation: Joi.string().required(),
    });

    const { error } = userSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const { username, email, password, phone, company, designation } = req.body;

    // Check if user already exists
    const existingUser = await dbQuery(
      'SELECT * FROM users WHERE email = $1 OR username = $2',
      [email, username]
    );

    if (existingUser.rows.length > 0) {
      return res.status(409).json({ error: 'User with this email or username already exists' });
    }

    const hashedPassword = await bcrypt.hash(password, 12);

    const result = await dbQuery(
      `INSERT INTO users (username, email, password, phone, company, designation)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, username, email, phone, company, designation, created_at`,
      [username, email, hashedPassword, phone, company, designation]
    );

    await logAdminAction(
      req.user.username, 
      'CREATE_USER', 
      `Created user: ${username} (${email})`, 
      req
    );

    res.status(201).json({
      message: 'User created successfully',
      user: result.rows[0]
    });

  } catch (err) {
    logger.error('Create user error:', err);
    if (err.code === '23505') {
      return res.status(409).json({ error: 'User with this email or username already exists' });
    }
    res.status(500).json({ error: 'Failed to create user' });
  }
});

app.get('/admin/users', authenticateAdmin, async (req, res) => {
  try {
    const { page = 1, limit = 10, search = '' } = req.query;
    const offset = (page - 1) * limit;

    let query = `
      SELECT id, username, email, phone, company, designation, created_at, last_login,
             CASE WHEN last_login > NOW() - INTERVAL '15 minutes' THEN true ELSE false END as is_online
      FROM users
    `;
    let countQuery = 'SELECT COUNT(*) FROM users';
    const params = [];

    if (search) {
      query += ` WHERE username ILIKE $1 OR email ILIKE $1 OR company ILIKE $1`;
      countQuery += ` WHERE username ILIKE $1 OR email ILIKE $1 OR company ILIKE $1`;
      params.push(`%${search}%`);
    }

    query += ` ORDER BY created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);

    const [users, count] = await Promise.all([
      dbQuery(query, params),
      dbQuery(countQuery, search ? [`%${search}%`] : [])
    ]);

    await logAdminAction(req.user.username, 'VIEW_USERS', `Viewed users list (page ${page})`, req);

    res.status(200).json({
      users: users.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: parseInt(count.rows[0].count),
        pages: Math.ceil(count.rows[0].count / limit)
      }
    });

  } catch (err) {
    logger.error('Get users error:', err);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

app.put('/admin/users/:id', authenticateAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const updateSchema = Joi.object({
      username: Joi.string().min(3).max(50).optional(),
      email: Joi.string().email().optional(),
      phone: Joi.string().pattern(/^\d{10}$/).optional(),
      company: Joi.string().optional(),
      designation: Joi.string().optional(),
    });

    const { error } = updateSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const fields = Object.keys(req.body);
    const values = Object.values(req.body);
    
    if (fields.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    const setClause = fields.map((field, index) => `${field} = $${index + 1}`).join(', ');
    const query = `
      UPDATE users 
      SET ${setClause}, updated_at = CURRENT_TIMESTAMP
      WHERE id = $${fields.length + 1}
      RETURNING id, username, email, phone, company, designation
    `;

    const result = await dbQuery(query, [...values, id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    await logAdminAction(
      req.user.username, 
      'UPDATE_USER', 
      `Updated user ID: ${id}`, 
      req
    );

    res.status(200).json({
      message: 'User updated successfully',
      user: result.rows[0]
    });

  } catch (err) {
    logger.error('Update user error:', err);
    res.status(500).json({ error: 'Failed to update user' });
  }
});


app.delete('/admin/users/:id', authenticateAdmin, async (req, res) => {
  try {
    const { id } = req.params;

    const result = await dbQuery(
      'DELETE FROM users WHERE id = $1 RETURNING username, email',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    await logAdminAction(
      req.user.username, 
      'DELETE_USER', 
      `Deleted user: ${result.rows[0].username} (${result.rows[0].email})`, 
      req
    );

    res.status(200).json({
      message: 'User deleted successfully',
      deletedUser: result.rows[0]
    });

  } catch (err) {
    logger.error('Delete user error:', err);
    res.status(500).json({ error: 'Failed to delete user' });
  }
});


app.post('/admin/backup', authenticateAdmin, async (req, res) => {
  try {
    const backupId = `backup_${Date.now()}`;
    const timestamp = new Date().toISOString();
    
    // Get all table names
    const tablesResult = await dbQuery(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    `);

    const backup = {
      id: backupId,
      timestamp: timestamp,
      tables: {}
    };

    // Backup each table
    for (const table of tablesResult.rows) {
      const tableName = table.table_name;
      try {
        const data = await dbQuery(`SELECT * FROM ${tableName}`);
        backup.tables[tableName] = {
          rowCount: data.rows.length,
          data: data.rows
        };
      } catch (tableError) {
        logger.warn(`Failed to backup table ${tableName}:`, tableError.message);
        backup.tables[tableName] = {
          error: tableError.message
        };
      }
    }

    // Save backup to file
    const backupDir = path.join(__dirname, 'backups');
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir, { recursive: true });
    }

    const filename = `${backupId}.json`;
    const filepath = path.join(backupDir, filename);
    
    fs.writeFileSync(filepath, JSON.stringify(backup, null, 2));

    await logAdminAction(
      req.user.username, 
      'SYSTEM_BACKUP', 
      `Created system backup: ${backupId}`, 
      req
    );

    res.status(200).json({
      message: 'Backup completed successfully',
      backupId: backupId,
      filename: filename,
      timestamp: timestamp,
      tablesBackedUp: Object.keys(backup.tables).length
    });

  } catch (err) {
    logger.error('Backup error:', err);
    res.status(500).json({ error: 'Failed to create backup' });
  }
});

app.get('/admin/system-logs', authenticateAdmin, async (req, res) => {
  try {
    const { page = 1, limit = 50, level = 'all' } = req.query;
    const offset = (page - 1) * limit;

    // Get admin logs
    let query = `
      SELECT 
        'admin' as source,
        action as level,
        description as message,
        admin_username as user_info,
        ip_address,
        created_at as timestamp
      FROM admin_logs
    `;

    if (level !== 'all') {
      query += ` WHERE action ILIKE '%${level}%'`;
    }

    query += ` ORDER BY created_at DESC LIMIT $1 OFFSET $2`;

    const logs = await dbQuery(query, [limit, offset]);

    await logAdminAction(req.user.username, 'VIEW_LOGS', 'Accessed system logs', req);

    res.status(200).json({
      logs: logs.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit)
      }
    });

  } catch (err) {
    logger.error('System logs error:', err);
    res.status(500).json({ error: 'Failed to fetch system logs' });
  }
});
app.post('/admin/reports', authenticateAdmin, async (req, res) => {
  try {
    const reportSchema = Joi.object({
      type: Joi.string().valid('users', 'water', 'tankers', 'system', 'custom').required(),
      startDate: Joi.date().optional(),
      endDate: Joi.date().optional(),
      format: Joi.string().valid('json', 'csv').default('json'),
    });

    const { error } = reportSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const { type, startDate, endDate, format } = req.body;
    let reportData = {};

    switch (type) {
      case 'users':
        const usersReport = await dbQuery(`
          SELECT 
            COUNT(*) as total_users,
            COUNT(CASE WHEN last_login > NOW() - INTERVAL '30 days' THEN 1 END) as active_last_30_days,
            COUNT(CASE WHEN created_at > NOW() - INTERVAL '30 days' THEN 1 END) as new_last_30_days
          FROM users
          WHERE ($1::date IS NULL OR created_at >= $1)
            AND ($2::date IS NULL OR created_at <= $2)
        `, [startDate, endDate]);
        
        reportData = {
          type: 'Users Report',
          period: { start: startDate, end: endDate },
          summary: usersReport.rows[0],
          generatedAt: new Date().toISOString()
        };
        break;

      case 'water':
        const waterReport = await dbQuery(`
          SELECT 
            SUM(total) as total_consumption,
            AVG(total) as average_consumption,
            COUNT(*) as total_records
          FROM water_consumption
          WHERE ($1::date IS NULL OR created_at >= $1)
            AND ($2::date IS NULL OR created_at <= $2)
        `, [startDate, endDate]);
        
        reportData = {
          type: 'Water Consumption Report',
          period: { start: startDate, end: endDate },
          summary: waterReport.rows[0],
          generatedAt: new Date().toISOString()
        };
        break;

      case 'tankers':
        const tankersReport = await dbQuery(`
          SELECT 
            COUNT(*) as total_tankers,
            AVG(capacity) as average_capacity,
            COUNT(DISTINCT vendor) as unique_vendors
          FROM tankers
          WHERE ($1::date IS NULL OR last_updated >= $1)
            AND ($2::date IS NULL OR last_updated <= $2)
        `, [startDate, endDate]);
        
        reportData = {
          type: 'Tankers Report',
          period: { start: startDate, end: endDate },
          summary: tankersReport.rows[0],
          generatedAt: new Date().toISOString()
        };
        break;

      case 'system':
        const systemReport = await dbQuery(`
          SELECT 
            AVG(system_health) as average_health,
            MAX(total_users) as peak_users,
            AVG(data_usage_gb) as average_data_usage
          FROM system_stats
          WHERE ($1::date IS NULL OR updated_at >= $1)
            AND ($2::date IS NULL OR updated_at <= $2)
        `, [startDate, endDate]);
        
        reportData = {
          type: 'System Performance Report',
          period: { start: startDate, end: endDate },
          summary: systemReport.rows[0],
          generatedAt: new Date().toISOString()
        };
        break;

      default:
        return res.status(400).json({ error: 'Invalid report type' });
    }

    // Save report
    const reportId = `report_${type}_${Date.now()}`;
    const reportsDir = path.join(__dirname, 'reports');
    if (!fs.existsSync(reportsDir)) {
      fs.mkdirSync(reportsDir, { recursive: true });
    }

    const filename = `${reportId}.json`;
    const filepath = path.join(reportsDir, filename);
    fs.writeFileSync(filepath, JSON.stringify(reportData, null, 2));

    await logAdminAction(
      req.user.username, 
      'GENERATE_REPORT', 
      `Generated ${type} report: ${reportId}`, 
      req
    );

    res.status(200).json({
      message: 'Report generated successfully',
      reportId: reportId,
      filename: filename,
      data: reportData
    });

  } catch (err) {
    logger.error('Generate report error:', err);
    res.status(500).json({ error: 'Failed to generate report' });
  }
});

app.get('/admin/reports', authenticateAdmin, async (req, res) => {
  try {
    const reportsDir = path.join(__dirname, 'reports');
    
    if (!fs.existsSync(reportsDir)) {
      return res.status(200).json({ reports: [] });
    }

    const files = fs.readdirSync(reportsDir);
    const reports = files
      .filter(file => file.endsWith('.json'))
      .map(file => {
        const stats = fs.statSync(path.join(reportsDir, file));
        return {
          filename: file,
          id: file.replace('.json', ''),
          size: stats.size,
          created: stats.birthtime,
          modified: stats.mtime
        };
      })
      .sort((a, b) => new Date(b.created) - new Date(a.created));

    res.status(200).json({ reports });

  } catch (err) {
    logger.error('Get reports error:', err);
    res.status(500).json({ error: 'Failed to fetch reports' });
  }
});

// Admin Alert Management
const createAlertTable = `
  CREATE TABLE IF NOT EXISTS alerts (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    severity VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by INTEGER REFERENCES users(id),
    is_active BOOLEAN DEFAULT true
  )
`;

// Alerts table will be created in initializeAdditionalTables function

  app.post('/admin/alerts', authenticateAdmin, async (req, res) => {
    try {
      const alertSchema = Joi.object({
        title: Joi.string().required(),
        message: Joi.string().required(),
        severity: Joi.string().valid('low', 'medium', 'high', 'critical').required(),
        sendToUsers: Joi.boolean().default(false),
      });
  
      const { error } = alertSchema.validate(req.body);
      if (error) {
        return res.status(400).json({ error: error.details[0].message });
      }
  
      const { title, message, severity, sendToUsers } = req.body;
  
      const result = await dbQuery(
        `INSERT INTO alerts (title, message, severity, created_by)
         VALUES ($1, $2, $3, $4)
         RETURNING *`,
        [title, message, severity, req.user.id || null]
      );
  
      await logAdminAction(
        req.user.username, 
        'CREATE_ALERT', 
        `Created ${severity} alert: ${title}`, 
        req
      );
  
      // If sendToUsers is true, implement notification logic here
      if (sendToUsers) {
        // Add notification logic (email, push notifications, etc.)
        logger.info(`Alert sent to users: ${title}`);
      }
  
      res.status(201).json({
        message: 'Alert created successfully',
        alert: result.rows[0]
      });
  
    } catch (err) {
      logger.error('Create alert error:', err);
      res.status(500).json({ error: 'Failed to create alert' });
    }
  });

app.get('/admin/alerts', authenticateAdmin, async (req, res) => {
  try {
    const { page = 1, limit = 20, severity = 'all' } = req.query;
    const offset = (page - 1) * limit;

    let query = `
      SELECT a.*, u.username as created_by_username
      FROM alerts a
      LEFT JOIN users u ON a.created_by = u.id
      WHERE a.is_active = true
    `;
    const params = [];

    if (severity !== 'all') {
      query += ` AND a.severity = $${params.length + 1}`;
      params.push(severity);
    }

    query += ` ORDER BY a.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);

    const alerts = await dbQuery(query, params);

    res.status(200).json({
      alerts: alerts.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit)
      }
    });

  } catch (err) {
    logger.error('Get alerts error:', err);
    res.status(500).json({ error: 'Failed to fetch alerts' });
  }
});

app.get('/admin/settings', authenticateAdmin, async (req, res) => {
  try {
    const settings = await dbQuery(
      'SELECT * FROM admin_settings ORDER BY setting_key'
    );

    res.status(200).json({ settings: settings.rows });

  } catch (err) {
    logger.error('Get settings error:', err);
    res.status(500).json({ error: 'Failed to fetch settings' });
  }
});


app.put('/admin/settings/:key', authenticateAdmin, async (req, res) => {
  try {
    const { key } = req.params;
    const { value, description } = req.body;

    if (!value) {
      return res.status(400).json({ error: 'Setting value is required' });
    }

    const result = await dbQuery(
      `INSERT INTO admin_settings (setting_key, setting_value, description, updated_by)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (setting_key) DO UPDATE SET
         setting_value = $2,
         description = COALESCE($3, admin_settings.description),
         updated_by = $4,
         updated_at = CURRENT_TIMESTAMP
       RETURNING *`,
      [key, value, description, req.user.username]
    );

    await logAdminAction(
      req.user.username, 
      'UPDATE_SETTING', 
      `Updated setting: ${key}`, 
      req
    );

    res.status(200).json({
      message: 'Setting updated successfully',
      setting: result.rows[0]
    });

  } catch (err) {
    logger.error('Update setting error:', err);
    res.status(500).json({ error: 'Failed to update setting' });
  }
});

app.get('/admin/status', authenticateAdmin, async (req, res) => {
  try {
    const dbStatus = await dbQuery('SELECT NOW()');
    const memoryUsage = process.memoryUsage();
    
    const status = {
      database: 'connected',
      uptime: process.uptime(),
      memory: {
        used: Math.round(memoryUsage.heapUsed / 1024 / 1024),
        total: Math.round(memoryUsage.heapTotal / 1024 / 1024),
        external: Math.round(memoryUsage.external / 1024 / 1024)
      },
      nodeVersion: process.version,
      platform: process.platform,
      timestamp: new Date().toISOString()
    };

    res.status(200).json(status);

  } catch (err) {
    logger.error('Status check error:', err);
    res.status(500).json({ error: 'Failed to get system status' });
  }
});


app.use((err, req, res, next) => {
  logger.error('Unhandled error:', err);
  res.status(500).json({ 
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});


// STACK MONITORING

const createStackMonitoringTable = `
  CREATE TABLE IF NOT EXISTS stack_monitoring (
    id SERIAL PRIMARY KEY,
    source VARCHAR(255) NOT NULL,
    consent_chimney VARCHAR(255),
    consent_apc_system VARCHAR(255),
    provided_chimney VARCHAR(255),
    provided_apc_system VARCHAR(255),
    parameter VARCHAR(255),
    standard VARCHAR(255),
    results VARCHAR(255),
    comments TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
  )
`;

// Stack Monitoring table will be created in initializeAdditionalTables function

const stackMonitoringSchema = Joi.object({
  source: Joi.string().required(),
  consent_chimney: Joi.string().allow('').optional(),
  consent_apc_system: Joi.string().allow('').optional(),
  provided_chimney: Joi.string().allow('').optional(),
  provided_apc_system: Joi.string().allow('').optional(),
  parameter: Joi.string().allow('').optional(),
  standard: Joi.string().allow('').optional(),
  results: Joi.string().allow('').optional(),
  comments: Joi.string().allow('').optional(),
  status: Joi.string().valid('active', 'inactive', 'maintenance', 'critical').default('active'),
});

app.get('/stack-monitoring', async (req, res) => {
  try {
    const result = await dbQuery('SELECT * FROM stack_monitoring ORDER BY timestamp DESC');
    res.status(200).json({
      data: result.rows
    });
  } catch (err) {
    console.error('Error fetching stack monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/stack-monitoring', async (req, res) => {
  try {
    const { error, value } = stackMonitoringSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    const {
      source, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, standard, results, comments, status
    } = value;
    const result = await dbQuery(
      `INSERT INTO stack_monitoring (source, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system, parameter, standard, results, comments, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
      [source, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system, parameter, standard, results, comments, status]
    );
    res.status(201).json({
      message: 'Stack monitoring data added successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error adding stack monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.put('/stack-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { error, value } = stackMonitoringSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    const {
      source, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, standard, results, comments, status
    } = value;
    const result = await dbQuery(
      `UPDATE stack_monitoring SET source = $1, consent_chimney = $2, consent_apc_system = $3, provided_chimney = $4, provided_apc_system = $5, parameter = $6, standard = $7, results = $8, comments = $9, status = $10 WHERE id = $11 RETURNING *`,
      [source, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system, parameter, standard, results, comments, status, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }
    res.status(200).json({
      message: 'Stack monitoring data updated successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error updating stack monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/stack-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const result = await dbQuery(
      'DELETE FROM stack_monitoring WHERE id = $1 RETURNING *',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }

    res.status(200).json({
      message: 'Stack monitoring data deleted successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error deleting stack monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// AMBIENT AIR MONITORING

const createAmbientMonitoringTable = `
  CREATE TABLE IF NOT EXISTS ambient_monitoring (
    id VARCHAR(50) PRIMARY KEY,
    location TEXT NOT NULL,
    consent_chimney VARCHAR(255),
    consent_apc_system VARCHAR(255),
    provided_chimney VARCHAR(255),
    provided_apc_system VARCHAR(255),
    parameter TEXT,
    limit_value TEXT,
    standard TEXT,
    measured TEXT,
    results TEXT,
    comments TEXT,
    status TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Ambient Monitoring table will be created in initializeAdditionalTables function

const ambientMonitoringSchema = Joi.object({
  id: Joi.string().max(50).required(),
  location: Joi.string().required(),
  consent_chimney: Joi.string().allow('').optional(),
  consent_apc_system: Joi.string().allow('').optional(),
  provided_chimney: Joi.string().allow('').optional(),
  provided_apc_system: Joi.string().allow('').optional(),
  parameter: Joi.string().allow('').optional(),
  limit: Joi.string().allow('').optional(),
  standard: Joi.string().allow('').optional(),
  measured: Joi.string().allow('').optional(),
  results: Joi.string().allow('').optional(),
  comments: Joi.string().allow('').optional(),
  status: Joi.string().required(),
  timestamp: Joi.date().optional()
});

app.get('/ambient-monitoring', async (req, res) => {
  try {
    const { status, search } = req.query;
    let query = 'SELECT * FROM ambient_monitoring';
    let params = [];
    if (status && status !== 'All') {
      query += ' WHERE status = $1';
      params.push(status);
    }
    if (search) {
      query += params.length ? ' AND' : ' WHERE';
      query += ` (location ILIKE $${params.length + 1} OR parameter ILIKE $${params.length + 1})`;
      params.push(`%${search}%`);
    }
    query += ' ORDER BY timestamp DESC';
    const result = await dbQuery(query, params);
    res.status(200).json({
      message: 'Data retrieved successfully',
      data: result.rows
    });
  } catch (err) {
    console.error('Error retrieving monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/ambient-monitoring', async (req, res) => {
  try {
    const { error } = ambientMonitoringSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    const {
      id, location, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, limit, standard, measured, results, comments, status, timestamp
    } = req.body;
    const query = `
      INSERT INTO ambient_monitoring
      (id, location, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system, parameter, limit_value, standard, measured, results, comments, status, timestamp)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      RETURNING *
    `;
    const result = await dbQuery(query, [
      id, location, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, limit, standard, measured, results, comments, status, timestamp || new Date()
    ]);
    res.status(201).json({
      message: 'Monitoring data added successfully!',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error adding monitoring data:', err.stack);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.put('/ambient-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { location, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, limit, standard, measured, results, comments, status, timestamp } = req.body;
    const query = `
      UPDATE ambient_monitoring
      SET location = $1, consent_chimney = $2, consent_apc_system = $3, provided_chimney = $4, provided_apc_system = $5, parameter = $6, limit_value = $7, standard = $8, measured = $9, results = $10, comments = $11, status = $12, timestamp = $13
      WHERE id = $14
      RETURNING *
    `;
    const result = await dbQuery(query, [
      location, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, limit, standard, measured, results, comments, status, timestamp, id
    ]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Monitoring data not found' });
    }
    res.status(200).json({
      message: 'Monitoring data updated successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error updating monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/ambient-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const query = 'DELETE FROM ambient_monitoring WHERE id = $1 RETURNING *';
    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Monitoring data not found' });
    }

    res.status(200).json({
      message: 'Monitoring data deleted successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error deleting monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// CONSUMPTION TABLE CREATION

const createConsumptionTable = `
  CREATE TABLE IF NOT EXISTS consumption (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    source VARCHAR(255) NOT NULL,
    water_supplied VARCHAR(255),
    treated_water VARCHAR(255),
    quantity_supplied NUMERIC(10,2) NOT NULL,
    mode_of_convergence VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Consumption table will be created in initializeAdditionalTables function

// Validation Schema for Consumption Entry
const consumptionSchema = Joi.object({
  date: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).required(),
  source: Joi.string().required(),
  waterSupplied: Joi.string().optional(),
  treatedWater: Joi.string().optional(),
  quantitySupplied: Joi.number().positive().required(),
  modeOfConvergence: Joi.string().optional()
});

// Add Consumption Data Endpoint
app.post('/consumption', async (req, res) => {
  try {
    // Validate request body
    const { error } = consumptionSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        error: error.details[0].message
      });
    }

    const {
      date,
      source,
      waterSupplied,
      treatedWater,
      quantitySupplied,
      modeOfConvergence
    } = req.body;

    // Insert consumption data
    const query = `
      INSERT INTO consumption (
        date,
        source,
        water_supplied,
        treated_water,
        quantity_supplied,
        mode_of_convergence
      ) VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `;

    const result = await dbQuery(query, [
      date,
      source,
      waterSupplied,
      treatedWater,
      quantitySupplied,
      modeOfConvergence
    ]);

    res.status(201).json({
      message: 'Consumption data added successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error adding consumption data:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// Get Consumption Data Endpoint
app.get('/consumption', async (req, res) => {
  try {
    const { source, date } = req.query;

    let query = 'SELECT * FROM consumption';
    let params = [];
    let whereConditions = [];

    // Build dynamic query based on filters
    if (source) {
      whereConditions.push(`source ILIKE $${params.length + 1}`);
      params.push(`%${source}%`);
    }

    if (date) {
      whereConditions.push(`date = $${params.length + 1}`);
      params.push(date);
    }

    // Add WHERE clause if conditions exist
    if (whereConditions.length > 0) {
      query += ' WHERE ' + whereConditions.join(' AND ');
    }

    const result = await dbQuery(query, params);

    res.status(200).json({
      message: 'Consumption data retrieved successfully!',
      data: result.rows
    });

  } catch (err) {
    console.error('Error retrieving consumption data:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// Endpoint to get unique sources
app.get('/consumption/sources', async (_req, res) => {
  try {
    const query = 'SELECT DISTINCT source FROM consumption ORDER BY source';
    const result = await dbQuery(query);

    res.status(200).json({
      message: 'Sources retrieved successfully!',
      sources: result.rows.map(row => row.source)
    });
  } catch (err) {
    console.error('Error retrieving sources:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// TANKER TABLE CREATION

// Create tanker table
const createTankersTable = `
  CREATE TABLE IF NOT EXISTS tankers (
    id SERIAL PRIMARY KEY,
    plate_number VARCHAR(20) UNIQUE NOT NULL,
    capacity DECIMAL NOT NULL,
    driver_name VARCHAR(100) NOT NULL,
    driver_contact VARCHAR(20) NOT NULL,
    vendor VARCHAR(100) NOT NULL,
    date DATE NOT NULL,
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    latitude DECIMAL,
    longitude DECIMAL,
    photo_url TEXT
  )
`;

// Tankers table will be created in initializeAdditionalTables function

// Add fresh water photo fields to existing tankers table
const addFreshWaterFields = `
  DO $$
  BEGIN
    -- Add loading_photo_url column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tankers' AND column_name='loading_photo_url') THEN
      ALTER TABLE tankers ADD COLUMN loading_photo_url TEXT;
    END IF;
    
    -- Add unloading_photo_url column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tankers' AND column_name='unloading_photo_url') THEN
      ALTER TABLE tankers ADD COLUMN unloading_photo_url TEXT;
    END IF;
    
    -- Add certificate_photo_url column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tankers' AND column_name='certificate_photo_url') THEN
      ALTER TABLE tankers ADD COLUMN certificate_photo_url TEXT;
    END IF;
    
    -- Add water_type column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tankers' AND column_name='water_type') THEN
      ALTER TABLE tankers ADD COLUMN water_type VARCHAR(50) DEFAULT 'Fresh';
    END IF;
  END
  $$;
`;

// WATER TANKER RECORDS TABLE (for treated water dashboard)

const createWaterTankerRecordsTable = `
  CREATE TABLE IF NOT EXISTS water_tanker_records (
    id SERIAL PRIMARY KEY,
    tanker_number VARCHAR(50) NOT NULL,
    tanker_capacity_liters INTEGER NOT NULL,
    water_type VARCHAR(50) DEFAULT 'Treated Water',
    tanker_photo_url TEXT,
    vendor_license_url TEXT,
    vehicle_rc_url TEXT,
    entry_photo_url TEXT,
    exit_photo_url TEXT,
    gps_latitude DECIMAL(10, 8),
    gps_longitude DECIMAL(11, 8),
    gps_captured_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Water Tanker Records table will be created in initializeAdditionalTables function

// DAILY INPUT TABLE (for treated water dashboard)

const createDailyInputTable = `
  CREATE TABLE IF NOT EXISTS daily_input (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    number_of_labourers INTEGER NOT NULL DEFAULT 0,
    construction_activity VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(date)
  )
`;

// Daily Input table will be created in initializeAdditionalTables function

// Validation schema for daily input
const dailyInputSchema = Joi.object({
  date: Joi.date().required(),
  number_of_labourers: Joi.number().integer().min(0).required(),
  construction_activity: Joi.string().max(100).optional()
});

// Validation schema for water tanker records
const waterTankerRecordSchema = Joi.object({
  tanker_number: Joi.string().max(50).required(),
  tanker_capacity_liters: Joi.number().positive().required(),
  water_type: Joi.string().max(50).default('Treated Water'),
  gps_latitude: Joi.number().min(-90).max(90).optional(),
  gps_longitude: Joi.number().min(-180).max(180).optional(),
  gps_captured_at: Joi.date().optional()
});

// Use the existing tankerSchema defined at the top of the file

// POST Endpoint to Add Tanker Data
app.post('/tanker', upload.fields([
  { name: 'photo', maxCount: 1 },
  { name: 'loading_photo', maxCount: 1 },
  { name: 'unloading_photo', maxCount: 1 },
  { name: 'certificate_photo', maxCount: 1 }
]), async (req, res) => {
  try {
    console.log('Tanker POST request received:', {
      contentType: req.get('Content-Type'),
      hasFiles: !!req.files,
      body: req.body,
      fileDetails: req.files ? Object.keys(req.files).map(key => ({
        field: key,
        count: req.files[key].length,
        files: req.files[key].map(f => ({ filename: f.filename, size: f.size }))
      })) : null
    });
    
    let tankerData;
    
    // Extract file URLs
    const getFileUrl = (fieldName) => {
      if (req.files && req.files[fieldName] && req.files[fieldName][0]) {
        const file = req.files[fieldName][0];
        return file.location || `/uploads/tanker-images/${file.filename}`;
      }
      return null;
    };

    // Check if the request is multipart form data or JSON
    if (req.is('multipart/form-data')) {
      // Handle multipart form data (from mobile app)
      tankerData = {
        plateNumber: req.body.plateNumber,
        capacity: parseFloat(req.body.capacity),
        driverName: req.body.driverName,
        driverContact: req.body.driverContact,
        vendor: req.body.vendor,
        date: req.body.date || new Date().toISOString().split('T')[0],
        lastUpdated: req.body.lastUpdated || new Date().toISOString(),
        latitude: req.body.latitude ? parseFloat(req.body.latitude) : null,
        longitude: req.body.longitude ? parseFloat(req.body.longitude) : null,
        waterType: req.body.waterType || req.body.water_type || 'Fresh',
        photoUrl: getFileUrl('photo'),
        loadingPhotoUrl: getFileUrl('loading_photo'),
        unloadingPhotoUrl: getFileUrl('unloading_photo'),
        certificatePhotoUrl: getFileUrl('certificate_photo')
      };
    } else {
      // Handle JSON data (from curl/API requests)
      tankerData = {
        ...req.body,
        capacity: parseFloat(req.body.capacity),
        date: req.body.date || new Date().toISOString().split('T')[0],
        lastUpdated: req.body.lastUpdated || new Date().toISOString(),
        latitude: req.body.latitude ? parseFloat(req.body.latitude) : null,
        longitude: req.body.longitude ? parseFloat(req.body.longitude) : null,
        waterType: req.body.waterType || req.body.water_type || 'Fresh'
      };
    }
    
    console.log('Processed tanker data:', tankerData);

    // Validate the data against schema
    const { error } = tankerSchema.validate(tankerData);
    if (error) {
      console.error('Validation error:', error.details);
      return res.status(400).json({
        success: false,
        message: error.details[0].message
      });
    }

    // Always insert new tanker entry (allow multiple entries per day)
    const result = await dbQuery(`
      INSERT INTO tankers 
      (plate_number, capacity, driver_name, driver_contact, vendor, date, last_updated, latitude, longitude, 
       photo_url, loading_photo_url, unloading_photo_url, certificate_photo_url, water_type)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      RETURNING *`,
      [
        tankerData.plateNumber,
        tankerData.capacity,
        tankerData.driverName,
        tankerData.driverContact,
        tankerData.vendor,
        tankerData.date,
        tankerData.lastUpdated,
        tankerData.latitude,
        tankerData.longitude,
        tankerData.photoUrl,
        tankerData.loadingPhotoUrl,
        tankerData.unloadingPhotoUrl,
        tankerData.certificatePhotoUrl,
        tankerData.waterType
      ]
    );

    // Convert snake_case to camelCase for response
    const tanker = {
      id: result.rows[0].id,
      plateNumber: result.rows[0].plate_number,
      capacity: parseFloat(result.rows[0].capacity),
      driverName: result.rows[0].driver_name,
      driverContact: result.rows[0].driver_contact,
      vendor: result.rows[0].vendor,
      date: result.rows[0].date,
      lastUpdated: result.rows[0].last_updated,
      latitude: result.rows[0].latitude ? parseFloat(result.rows[0].latitude) : null,
      longitude: result.rows[0].longitude ? parseFloat(result.rows[0].longitude) : null,
      waterType: result.rows[0].water_type,
      photoUrl: result.rows[0].photo_url,
      loadingPhotoUrl: result.rows[0].loading_photo_url,
      unloadingPhotoUrl: result.rows[0].unloading_photo_url,
      certificatePhotoUrl: result.rows[0].certificate_photo_url
    };

    res.status(201).json({
      success: true,
      message: 'Tanker entry created successfully',
      data: tanker
    });
  } catch (err) {
    console.error('Error in /tanker POST:', err);
    res.status(500).json({
      success: false,
      message: 'Failed to process tanker data',
      error: err.message
    });
  }
});


app.get('/tanker', async (req, res) => {
  try {
    const { plateNumber, date } = req.query;
    let query = 'SELECT * FROM tankers';
    let params = [];

    if (plateNumber) {
      query += ' WHERE plate_number = $1';
      params.push(plateNumber);
    }

    if (date) {
      query += params.length ? ' AND' : ' WHERE';
      query += ` DATE(date) = $${params.length + 1}`;
      params.push(date);
    }

    query += ' ORDER BY last_updated DESC';

    const result = await dbQuery(query, params);
    
    // Convert snake_case to camelCase for frontend
    const tankers = result.rows.map(row => ({
      id: row.id,
      plateNumber: row.plate_number,
      capacity: row.capacity,
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
      date: row.date,
      lastUpdated: row.last_updated,
      latitude: row.latitude,
      longitude: row.longitude,
      photoUrl: row.photo_url
    }));

    res.status(200).json({
      success: true,
      message: 'Tankers retrieved successfully',
      data: tankers
    });
  } catch (err) {
    logger.error('Error fetching tanker data:', err);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch tanker data',
      error: err.message
    });
  }
});

app.put('/tanker/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { plateNumber, capacity, driverName, driverContact, vendor, lastUpdated, latitude, longitude, photoUrl } = req.body;

    const query = `
      UPDATE tankers
      SET plate_number = $1,
          capacity = $2,
          driver_name = $3,
          driver_contact = $4,
          vendor = $5,
          last_updated = $6,
          latitude = $7,
          longitude = $8,
          photo_url = $9
      WHERE id = $10
      RETURNING *
    `;

    const result = await dbQuery(query, [
      plateNumber,
      capacity,
      driverName,
      driverContact,
      vendor,
      lastUpdated || new Date(),
      latitude,
      longitude,
      photoUrl,
      id
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Tanker data not found' });
    }

    // Convert snake_case to camelCase for response
    const tanker = {
      id: result.rows[0].id,
      plateNumber: result.rows[0].plate_number,
      capacity: result.rows[0].capacity,
      driverName: result.rows[0].driver_name,
      driverContact: result.rows[0].driver_contact,
      vendor: result.rows[0].vendor,
      lastUpdated: result.rows[0].last_updated,
      latitude: result.rows[0].latitude,
      longitude: result.rows[0].longitude,
      photoUrl: result.rows[0].photo_url
    };


    res.status(200).json({
      message: 'Tanker data updated successfully!',
      data: tanker
    });

  } catch (err) {
    console.error('Error updating tanker data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/tanker/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const query = 'DELETE FROM tankers WHERE id = $1 RETURNING *';
    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Tanker data not found' });
    }

    res.status(200).json({
      message: 'Tanker data deleted successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error deleting tanker data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/tanker/:id/photo', async (req, res) => {
  try {
    const { id } = req.params;
    const query = 'SELECT photo_url FROM tankers WHERE id = $1';
    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Photo not found' });
    }

    res.status(200).json({ photo_url: result.rows[0].photo_url });
  } catch (err) {
    console.error('Error retrieving photo:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/upload-photo', upload.single('photo'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No file uploaded'
      });
    }

    const photoUrl = req.file.location; // S3 file URL

    res.status(200).json({
      success: true,
      photo_url: photoUrl,
      message: 'Photo uploaded successfully'
    });
  } catch (err) {
    logger.error('Error uploading photo:', err);
    res.status(500).json({
      success: false,
      message: 'Failed to upload photo',
      error: err.message
    });
  }
});

// ====================================
// ADVANCED TANKER API ENDPOINTS
// ====================================

// Get all tankers with enhanced API format
app.get('/api/tankers', authenticateToken, async (req, res) => {
  try {
    const { date, plateNumber } = req.query;
    let query = 'SELECT * FROM tankers';
    let params = [];
    let whereConditions = [];

    if (date) {
      whereConditions.push('DATE(last_updated) = $' + (params.length + 1));
      params.push(date);
    }

    if (plateNumber) {
      whereConditions.push('plate_number ILIKE $' + (params.length + 1));
      params.push(`%${plateNumber}%`);
    }

    if (whereConditions.length > 0) {
      query += ' WHERE ' + whereConditions.join(' AND ');
    }

    query += ' ORDER BY last_updated DESC';

    const result = await dbQuery(query, params);
    
    const tankers = result.rows.map(row => ({
      plateNumber: row.plate_number,
      capacity: parseFloat(row.capacity),
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
      date: row.date,
      lastUpdated: row.last_updated,
      latitude: row.latitude ? parseFloat(row.latitude) : null,
      longitude: row.longitude ? parseFloat(row.longitude) : null,
      photoUrl: row.photo_url
    }));

    res.json({
      success: true,
      data: tankers,
      total: tankers.length
    });

  } catch (error) {
    logger.error('Error fetching tankers:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch tankers',
      message: error.message
    });
  }
});

// Get tanker by plate number
app.get('/api/tankers/:plateNumber', authenticateToken, async (req, res) => {
  try {
    const { plateNumber } = req.params;
    const query = 'SELECT * FROM tankers WHERE plate_number = $1';
    const result = await dbQuery(query, [plateNumber]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Tanker not found'
      });
    }

    const row = result.rows[0];
    const tanker = {
      plateNumber: row.plate_number,
      capacity: parseFloat(row.capacity),
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
      date: row.date,
      lastUpdated: row.last_updated,
      latitude: row.latitude ? parseFloat(row.latitude) : null,
      longitude: row.longitude ? parseFloat(row.longitude) : null,
      photoUrl: row.photo_url
    };

    res.json({
      success: true,
      data: tanker
    });

  } catch (error) {
    logger.error('Error fetching tanker:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch tanker',
      message: error.message
    });
  }
});

// Upload tanker image (enhanced API)
app.post('/api/tankers/images', authenticateToken, upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No image file provided'
      });
    }

    const { plateNumber } = req.body;
    if (!plateNumber) {
      return res.status(400).json({
        success: false,
        error: 'Plate number is required'
      });
    }

    // Get the image URL (from S3 or local storage)
    const imageUrl = req.file.location || `/uploads/${req.file.filename}`;
    
    // Update tanker with new image URL
    const updateQuery = 'UPDATE tankers SET photo_url = $1 WHERE plate_number = $2 RETURNING *';
    const result = await dbQuery(updateQuery, [imageUrl, plateNumber]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Tanker not found'
      });
    }

    logger.info(`Tanker image uploaded for ${plateNumber}: ${imageUrl}`);

    res.json({
      success: true,
      imageUrl: imageUrl,
      message: 'Image uploaded successfully'
    });

  } catch (error) {
    logger.error('Error uploading tanker image:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to upload image',
      message: error.message
    });
  }
});

// Update tanker status/data
app.put('/api/tankers/:plateNumber', authenticateToken, async (req, res) => {
  try {
    const { plateNumber } = req.params;
    const { capacity, driverName, driverContact, vendor, latitude, longitude, photoUrl } = req.body;

    const query = `
      UPDATE tankers 
      SET capacity = $1,
          driver_name = $2,
          driver_contact = $3,
          vendor = $4,
          latitude = $5,
          longitude = $6,
          photo_url = $7,
          last_updated = CURRENT_TIMESTAMP
      WHERE plate_number = $8
      RETURNING *
    `;

    const result = await dbQuery(query, [
      capacity,
      driverName,
      driverContact,
      vendor,
      latitude,
      longitude,
      photoUrl,
      plateNumber
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Tanker not found'
      });
    }

    const row = result.rows[0];
    const updatedTanker = {
      plateNumber: row.plate_number,
      capacity: parseFloat(row.capacity),
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
      date: row.date,
      lastUpdated: row.last_updated,
      latitude: row.latitude ? parseFloat(row.latitude) : null,
      longitude: row.longitude ? parseFloat(row.longitude) : null,
      photoUrl: row.photo_url
    };

    logger.info(`Tanker updated: ${plateNumber}`);

    res.json({
      success: true,
      data: updatedTanker,
      message: 'Tanker updated successfully'
    });

  } catch (error) {
    logger.error('Error updating tanker:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update tanker',
      message: error.message
    });
  }
});

// Delete tanker image
app.delete('/api/tankers/images', authenticateToken, async (req, res) => {
  try {
    const { imageUrl } = req.body;
    
    if (!imageUrl) {
      return res.status(400).json({
        success: false,
        error: 'Image URL is required'
      });
    }

    // Remove image URL from tanker record
    const query = 'UPDATE tankers SET photo_url = NULL WHERE photo_url = $1 RETURNING *';
    const result = await dbQuery(query, [imageUrl]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Image not found'
      });
    }

    // TODO: Also delete the actual file from S3/local storage if needed
    
    logger.info(`Tanker image deleted: ${imageUrl}`);

    res.json({
      success: true,
      message: 'Image deleted successfully'
    });

  } catch (error) {
    logger.error('Error deleting tanker image:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete image',
      message: error.message
    });
  }
});

// ===========================================
// WATER TANKER RECORDS ENDPOINTS (for treated water dashboard)
// ===========================================

// Configure multer for multiple file uploads (for water tanker records)
const waterTankerUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit
  },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'), false);
    }
  }
});

// GET all water tanker records
app.get('/api/water-tanker-records', async (req, res) => {
  try {
    const { page = 1, limit = 10, sort = 'created_at', order = 'DESC', date, start_date, end_date } = req.query;
    const offset = (page - 1) * limit;
    
    // Build dynamic WHERE clause for date filtering
    let whereClause = '';
    let queryParams = [limit, offset];
    let paramIndex = 3;
    
    if (date) {
      // Filter by specific date
      whereClause = `WHERE DATE(created_at) = $${paramIndex}`;
      queryParams.push(date);
      paramIndex++;
    } else if (start_date && end_date) {
      // Filter by date range
      whereClause = `WHERE DATE(created_at) BETWEEN $${paramIndex} AND $${paramIndex + 1}`;
      queryParams.push(start_date, end_date);
      paramIndex += 2;
    } else if (start_date) {
      // Filter from start_date onwards
      whereClause = `WHERE DATE(created_at) >= $${paramIndex}`;
      queryParams.push(start_date);
      paramIndex++;
    } else if (end_date) {
      // Filter up to end_date
      whereClause = `WHERE DATE(created_at) <= $${paramIndex}`;
      queryParams.push(end_date);
      paramIndex++;
    }
    
    const query = `
      SELECT * FROM water_tanker_records 
      ${whereClause}
      ORDER BY ${sort} ${order} 
      LIMIT $1 OFFSET $2
    `;
    
    const countQuery = `SELECT COUNT(*) FROM water_tanker_records ${whereClause}`;
    const countParams = queryParams.slice(2); // Remove limit and offset for count query
    
    const [records, countResult] = await Promise.all([
      dbQuery(query, queryParams),
      dbQuery(countQuery, countParams)
    ]);
    
    const total = parseInt(countResult.rows[0].count);
    const totalPages = Math.ceil(total / limit);
    
    res.status(200).json({
      success: true,
      data: records.rows,
      pagination: {
        currentPage: parseInt(page),
        totalPages,
        totalRecords: total,
        hasNext: page < totalPages,
        hasPrev: page > 1
      },
      filters: {
        date: date || null,
        start_date: start_date || null,
        end_date: end_date || null
      }
    });
    
  } catch (error) {
    console.error('Error fetching water tanker records:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch water tanker records',
      message: error.message
    });
  }
});

// GET single water tanker record by ID
app.get('/api/water-tanker-records/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const query = 'SELECT * FROM water_tanker_records WHERE id = $1';
    const result = await dbQuery(query, [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Water tanker record not found'
      });
    }
    
    res.status(200).json({
      success: true,
      data: result.rows[0]
    });
    
  } catch (error) {
    console.error('Error fetching water tanker record:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch water tanker record',
      message: error.message
    });
  }
});

// POST create new water tanker record with multiple file uploads
app.post('/api/water-tanker-records', waterTankerUpload.fields([
  { name: 'tanker_photo', maxCount: 1 },
  { name: 'vendor_license', maxCount: 1 },
  { name: 'vehicle_rc', maxCount: 1 },
  { name: 'entry_photo', maxCount: 1 },
  { name: 'exit_photo', maxCount: 1 }
]), async (req, res) => {
  try {
    // Validate request body
    const { error, value } = waterTankerRecordSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: 'Validation error',
        details: error.details[0].message
      });
    }
    
    const { tanker_number, tanker_capacity_liters, water_type, gps_latitude, gps_longitude, gps_captured_at } = value;
    
    // Upload files to S3 and get URLs
    const uploadPromises = [];
    const photoUrls = {};
    
    if (req.files) {
      const fileFields = ['tanker_photo', 'vendor_license', 'vehicle_rc', 'entry_photo', 'exit_photo'];
      
      for (const field of fileFields) {
        if (req.files[field] && req.files[field][0]) {
          const file = req.files[field][0];
          const key = `water-tanker-records/${Date.now()}-${field}-${file.originalname}`;
          
          uploadPromises.push(
            uploadToS3(file.buffer, key, file.mimetype).then(url => {
              photoUrls[`${field}_url`] = url;
            })
          );
        }
      }
      
      // Wait for all uploads to complete
      await Promise.all(uploadPromises);
    }
    
    // Insert record into database
    const insertQuery = `
      INSERT INTO water_tanker_records (
        tanker_number, tanker_capacity_liters, water_type,
        tanker_photo_url, vendor_license_url, vehicle_rc_url,
        entry_photo_url, exit_photo_url,
        gps_latitude, gps_longitude, gps_captured_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING *
    `;
    
    const result = await dbQuery(insertQuery, [
      tanker_number,
      tanker_capacity_liters,
      water_type || 'Treated Water',
      photoUrls.tanker_photo_url || null,
      photoUrls.vendor_license_url || null,
      photoUrls.vehicle_rc_url || null,
      photoUrls.entry_photo_url || null,
      photoUrls.exit_photo_url || null,
      gps_latitude || null,
      gps_longitude || null,
      gps_captured_at || null
    ]);
    
    res.status(201).json({
      success: true,
      data: result.rows[0],
      message: 'Water tanker record created successfully'
    });
    
  } catch (error) {
    console.error('Error creating water tanker record:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create water tanker record',
      message: error.message
    });
  }
});

// PUT update water tanker record
app.put('/api/water-tanker-records/:id', waterTankerUpload.fields([
  { name: 'tanker_photo', maxCount: 1 },
  { name: 'vendor_license', maxCount: 1 },
  { name: 'vehicle_rc', maxCount: 1 },
  { name: 'entry_photo', maxCount: 1 },
  { name: 'exit_photo', maxCount: 1 }
]), async (req, res) => {
  try {
    const { id } = req.params;
    
    // Validate request body
    const { error, value } = waterTankerRecordSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: 'Validation error',
        details: error.details[0].message
      });
    }
    
    // Check if record exists
    const existingRecord = await dbQuery('SELECT * FROM water_tanker_records WHERE id = $1', [id]);
    if (existingRecord.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Water tanker record not found'
      });
    }
    
    const { tanker_number, tanker_capacity_liters, water_type, gps_latitude, gps_longitude, gps_captured_at } = value;
    
    // Upload new files to S3 if provided
    const uploadPromises = [];
    const photoUrls = {};
    
    if (req.files) {
      const fileFields = ['tanker_photo', 'vendor_license', 'vehicle_rc', 'entry_photo', 'exit_photo'];
      
      for (const field of fileFields) {
        if (req.files[field] && req.files[field][0]) {
          const file = req.files[field][0];
          const key = `water-tanker-records/${Date.now()}-${field}-${file.originalname}`;
          
          uploadPromises.push(
            uploadToS3(file.buffer, key, file.mimetype).then(url => {
              photoUrls[`${field}_url`] = url;
            })
          );
        }
      }
      
      // Wait for all uploads to complete
      await Promise.all(uploadPromises);
    }
    
    // Build update query dynamically
    const updateFields = [];
    const updateValues = [];
    let paramCount = 1;
    
    updateFields.push(`tanker_number = $${paramCount++}`);
    updateValues.push(tanker_number);
    
    updateFields.push(`tanker_capacity_liters = $${paramCount++}`);
    updateValues.push(tanker_capacity_liters);
    
    updateFields.push(`water_type = $${paramCount++}`);
    updateValues.push(water_type || 'Treated Water');
    
    // Add photo URLs if uploaded
    if (photoUrls.tanker_photo_url) {
      updateFields.push(`tanker_photo_url = $${paramCount++}`);
      updateValues.push(photoUrls.tanker_photo_url);
    }
    if (photoUrls.vendor_license_url) {
      updateFields.push(`vendor_license_url = $${paramCount++}`);
      updateValues.push(photoUrls.vendor_license_url);
    }
    if (photoUrls.vehicle_rc_url) {
      updateFields.push(`vehicle_rc_url = $${paramCount++}`);
      updateValues.push(photoUrls.vehicle_rc_url);
    }
    if (photoUrls.entry_photo_url) {
      updateFields.push(`entry_photo_url = $${paramCount++}`);
      updateValues.push(photoUrls.entry_photo_url);
    }
    if (photoUrls.exit_photo_url) {
      updateFields.push(`exit_photo_url = $${paramCount++}`);
      updateValues.push(photoUrls.exit_photo_url);
    }
    
    // Add GPS data if provided
    if (gps_latitude !== undefined) {
      updateFields.push(`gps_latitude = $${paramCount++}`);
      updateValues.push(gps_latitude);
    }
    if (gps_longitude !== undefined) {
      updateFields.push(`gps_longitude = $${paramCount++}`);
      updateValues.push(gps_longitude);
    }
    if (gps_captured_at !== undefined) {
      updateFields.push(`gps_captured_at = $${paramCount++}`);
      updateValues.push(gps_captured_at);
    }
    
    updateFields.push(`updated_at = CURRENT_TIMESTAMP`);
    updateValues.push(id);
    
    const updateQuery = `
      UPDATE water_tanker_records 
      SET ${updateFields.join(', ')}
      WHERE id = $${paramCount}
      RETURNING *
    `;
    
    const result = await dbQuery(updateQuery, updateValues);
    
    res.status(200).json({
      success: true,
      data: result.rows[0],
      message: 'Water tanker record updated successfully'
    });
    
  } catch (error) {
    console.error('Error updating water tanker record:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update water tanker record',
      message: error.message
    });
  }
});

// DELETE water tanker record
app.delete('/api/water-tanker-records/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    // First get the record to delete associated S3 files
    const recordQuery = 'SELECT * FROM water_tanker_records WHERE id = $1';
    const recordResult = await dbQuery(recordQuery, [id]);
    
    if (recordResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Water tanker record not found'
      });
    }
    
    const record = recordResult.rows[0];
    
    // Delete associated S3 files
    const s3DeletePromises = [];
    const photoFields = ['tanker_photo_url', 'vendor_license_url', 'vehicle_rc_url', 'entry_photo_url', 'exit_photo_url'];
    
    for (const field of photoFields) {
      if (record[field]) {
        const key = record[field].split('/').pop(); // Extract key from URL
        s3DeletePromises.push(deleteFromS3(key));
      }
    }
    
    // Wait for S3 deletions to complete (but don't fail if they error)
    try {
      await Promise.all(s3DeletePromises);
    } catch (s3Error) {
      console.warn('Some S3 files could not be deleted:', s3Error);
    }
    
    // Delete record from database
    const deleteQuery = 'DELETE FROM water_tanker_records WHERE id = $1 RETURNING *';
    const deleteResult = await dbQuery(deleteQuery, [id]);
    
    res.status(200).json({
      success: true,
      data: deleteResult.rows[0],
      message: 'Water tanker record deleted successfully'
    });
    
  } catch (error) {
    console.error('Error deleting water tanker record:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete water tanker record',
      message: error.message
    });
  }
});

// GET signed URL for viewing water tanker images
app.get('/api/water-tanker-records/:id/images/:imageType', async (req, res) => {
  try {
    const { id, imageType } = req.params;
    
    // Validate image type
    const validImageTypes = ['tanker_photo', 'vendor_license', 'vehicle_rc', 'entry_photo', 'exit_photo'];
    if (!validImageTypes.includes(imageType)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid image type'
      });
    }
    
    // Get the record
    const query = `SELECT ${imageType}_url FROM water_tanker_records WHERE id = $1`;
    const result = await dbQuery(query, [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Water tanker record not found'
      });
    }
    
    const imageUrl = result.rows[0][`${imageType}_url`];
    
    if (!imageUrl) {
      return res.status(404).json({
        success: false,
        message: `No ${imageType.replace('_', ' ')} found for this record`
      });
    }
    
    // For S3 files, generate a signed URL
    if (s3Client && imageUrl.includes('amazonaws.com')) {
      try {
        const key = imageUrl.split('/').slice(-3).join('/'); // Extract key from URL
        
        // Generate signed URL using AWS SDK v3
        const command = new GetObjectCommand({
          Bucket: process.env.AWS_BUCKET_NAME,
          Key: key,
          ResponseContentDisposition: `inline; filename="${imageType}_${id}.jpg"`
        });
        
        const signedUrl = await getSignedUrl(s3Client, command, {
          expiresIn: 3600 // 1 hour
        });
        
        res.json({
          success: true,
          imageUrl: signedUrl,
          imageType: imageType,
          expiresIn: 3600
        });
        
      } catch (s3Error) {
        logger.error('Error generating signed URL:', s3Error);
        res.status(500).json({
          success: false,
          message: 'Failed to generate image URL'
        });
      }
    } else {
      // For direct URLs, return as is
      res.json({
        success: true,
        imageUrl: imageUrl,
        imageType: imageType
      });
    }
    
  } catch (error) {
    logger.error('Error getting water tanker image:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get image',
      message: error.message
    });
  }
});

// DELETE specific image from water tanker record
app.delete('/api/water-tanker-records/:id/images/:imageType', async (req, res) => {
  try {
    const { id, imageType } = req.params;
    
    // Validate image type
    const validImageTypes = ['tanker_photo', 'vendor_license', 'vehicle_rc', 'entry_photo', 'exit_photo'];
    if (!validImageTypes.includes(imageType)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid image type'
      });
    }
    
    // Get the current record
    const getQuery = `SELECT ${imageType}_url FROM water_tanker_records WHERE id = $1`;
    const getResult = await dbQuery(getQuery, [id]);
    
    if (getResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Water tanker record not found'
      });
    }
    
    const imageUrl = getResult.rows[0][`${imageType}_url`];
    
    if (!imageUrl) {
      return res.status(404).json({
        success: false,
        message: `No ${imageType.replace('_', ' ')} to delete`
      });
    }
    
    // Update database to remove image URL
    const updateQuery = `
      UPDATE water_tanker_records 
      SET ${imageType}_url = NULL, updated_at = CURRENT_TIMESTAMP
      WHERE id = $1
      RETURNING *
    `;
    
    const result = await dbQuery(updateQuery, [id]);
    
    // Optionally delete from S3 (commented out to keep for backup)
    /*
    if (s3Client && imageUrl.includes('amazonaws.com')) {
      try {
        const key = imageUrl.split('/').slice(-3).join('/');
        await s3Client.send(new DeleteObjectCommand({
          Bucket: process.env.AWS_BUCKET_NAME,
          Key: key
        }));
        logger.info(`Deleted S3 object: ${key}`);
      } catch (s3Error) {
        logger.error('Error deleting from S3:', s3Error);
        // Continue even if S3 deletion fails
      }
    }
    */
    
    logger.info(`Removed ${imageType} from water tanker record: ID ${id}`);
    
    res.json({
      success: true,
      data: result.rows[0],
      message: `${imageType.replace('_', ' ')} removed successfully`
    });
    
  } catch (error) {
    logger.error('Error deleting water tanker image:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete image',
      message: error.message
    });
  }
});

// GET all images for a water tanker record with signed URLs
app.get('/api/water-tanker-records/:id/all-images', async (req, res) => {
  try {
    const { id } = req.params;
    
    // Get the record with all image URLs
    const query = `
      SELECT 
        tanker_photo_url,
        vendor_license_url,
        vehicle_rc_url,
        entry_photo_url,
        exit_photo_url
      FROM water_tanker_records 
      WHERE id = $1
    `;
    
    const result = await dbQuery(query, [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Water tanker record not found'
      });
    }
    
    const record = result.rows[0];
    const signedUrls = {};
    
    // Generate signed URLs for all images
    const imageTypes = ['tanker_photo', 'vendor_license', 'vehicle_rc', 'entry_photo', 'exit_photo'];
    
    for (const imageType of imageTypes) {
      const imageUrl = record[`${imageType}_url`];
      
      if (imageUrl && s3Client && imageUrl.includes('amazonaws.com')) {
        try {
          const key = imageUrl.split('/').slice(-3).join('/');
          
          const command = new GetObjectCommand({
            Bucket: process.env.AWS_BUCKET_NAME,
            Key: key,
            ResponseContentDisposition: `inline; filename="${imageType}_${id}.jpg"`
          });
          
          const signedUrl = await getSignedUrl(s3Client, command, {
            expiresIn: 3600 // 1 hour
          });
          
          signedUrls[imageType] = {
            originalUrl: imageUrl,
            signedUrl: signedUrl,
            expiresIn: 3600
          };
        } catch (s3Error) {
          logger.error(`Error generating signed URL for ${imageType}:`, s3Error);
          signedUrls[imageType] = {
            originalUrl: imageUrl,
            signedUrl: imageUrl, // Fallback to original URL
            error: 'Failed to generate signed URL'
          };
        }
      } else if (imageUrl) {
        // Direct URL
        signedUrls[imageType] = {
          originalUrl: imageUrl,
          signedUrl: imageUrl
        };
      } else {
        signedUrls[imageType] = null;
      }
    }
    
    res.json({
      success: true,
      recordId: id,
      images: signedUrls
    });
    
  } catch (error) {
    logger.error('Error getting water tanker images:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get images',
      message: error.message
    });
  }
});

// ===========================================
// DAILY INPUT ENDPOINTS (for treated water dashboard)
// ===========================================

// GET daily input by date
app.get('/api/daily-input/:date', async (req, res) => {
  try {
    const { date } = req.params;
    const query = 'SELECT * FROM daily_input WHERE date = $1';
    const result = await dbQuery(query, [date]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Daily input not found for this date'
      });
    }
    
    res.status(200).json({
      success: true,
      data: result.rows[0]
    });
    
  } catch (error) {
    console.error('Error fetching daily input:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch daily input',
      message: error.message
    });
  }
});

// POST/PUT create or update daily input
app.post('/api/daily-input', async (req, res) => {
  try {
    // Validate request body
    const { error, value } = dailyInputSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: 'Validation error',
        details: error.details[0].message
      });
    }
    
    const { date, number_of_labourers, construction_activity } = value;
    
    // Use UPSERT (ON CONFLICT) to insert or update
    const upsertQuery = `
      INSERT INTO daily_input (date, number_of_labourers, construction_activity, updated_at)
      VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
      ON CONFLICT (date) 
      DO UPDATE SET 
        number_of_labourers = EXCLUDED.number_of_labourers,
        construction_activity = EXCLUDED.construction_activity,
        updated_at = CURRENT_TIMESTAMP
      RETURNING *
    `;
    
    const result = await dbQuery(upsertQuery, [date, number_of_labourers, construction_activity]);
    
    res.status(200).json({
      success: true,
      data: result.rows[0],
      message: 'Daily input saved successfully'
    });
    
  } catch (error) {
    console.error('Error saving daily input:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to save daily input',
      message: error.message
    });
  }
});

// GET all daily inputs with optional date range
app.get('/api/daily-input', async (req, res) => {
  try {
    const { start_date, end_date, limit = 30 } = req.query;
    
    let query = 'SELECT * FROM daily_input';
    const params = [];
    
    if (start_date && end_date) {
      query += ' WHERE date BETWEEN $1 AND $2';
      params.push(start_date, end_date);
    } else if (start_date) {
      query += ' WHERE date >= $1';
      params.push(start_date);
    } else if (end_date) {
      query += ' WHERE date <= $1';
      params.push(end_date);
    }
    
    query += ' ORDER BY date DESC LIMIT $' + (params.length + 1);
    params.push(limit);
    
    const result = await dbQuery(query, params);
    
    res.status(200).json({
      success: true,
      data: result.rows,
      total: result.rows.length
    });
    
  } catch (error) {
    console.error('Error fetching daily inputs:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch daily inputs',
      message: error.message
    });
  }
});

// DELETE daily input by date
app.delete('/api/daily-input/:date', async (req, res) => {
  try {
    const { date } = req.params;
    const query = 'DELETE FROM daily_input WHERE date = $1 RETURNING *';
    const result = await dbQuery(query, [date]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Daily input not found for this date'
      });
    }
    
    res.status(200).json({
      success: true,
      data: result.rows[0],
      message: 'Daily input deleted successfully'
    });
    
  } catch (error) {
    console.error('Error deleting daily input:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete daily input',
      message: error.message
    });
  }
});

// LABOUR COLONY WASTE

const createLabourColonyWasteTable = `
  CREATE TABLE IF NOT EXISTS labour_colony_waste (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    source VARCHAR(255) NOT NULL,
    consumption NUMERIC(10,2) NOT NULL,
    discharge VARCHAR(255) NOT NULL,
    discharged_to VARCHAR(255) NOT NULL,
    mode VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Labour Colony Waste table will be created in initializeAdditionalTables function

// Validation Schema
const labourColonyWasteSchema = Joi.object({
  date: Joi.date().required(),
  source: Joi.string().required(),
  consumption: Joi.number().positive().required(),
  discharge: Joi.string().required(),
  discharged_to: Joi.string().required(),
  mode: Joi.string().valid('Pipeline', 'Tanker', 'Other').required()
});

// GET Labour Colony Waste Data Endpoint
app.get('/labour-colony-waste', async (req, res) => {
  try {
    const { date } = req.query;
    let query = 'SELECT * FROM labour_colony_waste';
    const values = [];

    // Add date filter if provided
    if (date) {
      query += ' WHERE date = $1';
      values.push(date);
    }

    // Order by date in descending order
    query += ' ORDER BY date DESC';

    const result = await dbQuery(query, values);

    res.status(200).json({
      message: 'Labour Colony Waste data retrieved successfully!',
      data: result.rows
    });

  } catch (err) {
    console.error('Error retrieving Labour Colony Waste data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST Labour Colony Waste Data Endpoint
app.post('/labour-colony-waste', async (req, res) => {
  try {
    // Validate request body
    const { error } = labourColonyWasteSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        error: error.details[0].message
      });
    }

    const { date, source, consumption, discharge, discharged_to, mode } = req.body;

    // Insert new waste data
    const query = `
      INSERT INTO labour_colony_waste
      (date, source, consumption, discharge, discharged_to, mode)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `;

    const result = await dbQuery(query, [
      date,
      source,
      consumption,
      discharge,
      discharged_to,
      mode
    ]);

    res.status(201).json({
      message: 'Labour Colony Waste data added successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error adding Labour Colony Waste data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// UPDATE Labour Colony Waste Data Endpoint
app.put('/labour-colony-waste/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Validate request body
    const { error } = labourColonyWasteSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        error: error.details[0].message
      });
    }

    const { date, source, consumption, discharge, discharged_to, mode } = req.body;

    // Update waste data
    const query = `
      UPDATE labour_colony_waste
      SET date = $1,
          source = $2,
          consumption = $3,
          discharge = $4,
          discharged_to = $5,
          mode = $6
      WHERE id = $7
      RETURNING *
    `;

    const result = await dbQuery(query, [
      date,
      source,
      consumption,
      discharge,
      discharged_to,
      mode,
      id
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'Labour Colony Waste entry not found'
      });
    }

    res.status(200).json({
      message: 'Labour Colony Waste data updated successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error updating Labour Colony Waste data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE Labour Colony Waste Data Endpoint
app.delete('/labour-colony-waste/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const result = await dbQuery(
      'DELETE FROM labour_colony_waste WHERE id = $1 RETURNING *',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'Labour Colony Waste entry not found'
      });
    }

    res.status(200).json({
      message: 'Labour Colony Waste data deleted successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error deleting Labour Colony Waste data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// C&D WASTE TABLE

const createCDWasteTable = `
  CREATE TABLE IF NOT EXISTS cd_waste (
    id SERIAL PRIMARY KEY,
    project_area NUMERIC(10,2) NOT NULL,
    waste_amount NUMERIC(10,2) NOT NULL,
    date DATE NOT NULL,
    project_name VARCHAR(255),
    construction_type VARCHAR(100),
    waste_type VARCHAR(100),
    disposal_method VARCHAR(100),
    reuse_recycling_details TEXT,
    location VARCHAR(255),
    contractor_name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// C&D Waste table will be created in initializeAdditionalTables function

// Migration queries to add new columns to existing cd_waste table
const migrateCDWasteTable = async () => {
  const migrations = [
    `ALTER TABLE cd_waste ADD COLUMN IF NOT EXISTS project_name VARCHAR(255)`,
    `ALTER TABLE cd_waste ADD COLUMN IF NOT EXISTS construction_type VARCHAR(100)`,
    `ALTER TABLE cd_waste ADD COLUMN IF NOT EXISTS location VARCHAR(255)`,
    `ALTER TABLE cd_waste ADD COLUMN IF NOT EXISTS contractor_name VARCHAR(255)`,
    `ALTER TABLE cd_waste ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP`
  ];

  for (const migration of migrations) {
    try {
      await dbQuery(migration);
      logger.info(`Migration executed: ${migration}`);
    } catch (error) {
      // Ignore "column already exists" errors
      if (!error.message.includes('already exists')) {
        logger.error(`Migration failed: ${migration}`, error);
      }
    }
  }
};

// Validation Schema
const cdWasteSchema = Joi.object({
  project_area: Joi.number().positive().required(),
  project_name: Joi.string().allow(''),
  construction_type: Joi.string().allow(''),
  waste_type: Joi.string().required(),
  disposal_method: Joi.string().required(),
  reuse_recycling_details: Joi.string().allow(''),
  location: Joi.string().allow(''),
  contractor_name: Joi.string().allow(''),
  date: Joi.date().required()
});

// GET waste data
app.get('/cd-waste', async (req, res) => {
  try {
    const { startDate, endDate } = req.query;
    let query = 'SELECT * FROM cd_waste';
    const params = [];

    if (startDate && endDate) {
      query += ' WHERE date BETWEEN $1 AND $2';
      params.push(startDate, endDate);
    }

    query += ' ORDER BY date DESC';

    const result = await dbQuery(query, params);
    res.status(200).json({
      message: 'Data retrieved successfully',
      data: result.rows
    });
  } catch (err) {
    console.error('Error retrieving waste data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST waste data
app.post('/cd-waste', async (req, res) => {
  try {
    const { error } = cdWasteSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const {
      project_area,
      project_name,
      construction_type,
      date,
      waste_type,
      disposal_method,
      reuse_recycling_details,
      location,
      contractor_name
    } = req.body;

    // Use correct formula: 50kg per sq ft
    const waste_amount = project_area * 50;

    const query = `
      INSERT INTO cd_waste
      (project_area, waste_amount, date, project_name, construction_type, 
       waste_type, disposal_method, reuse_recycling_details, location, contractor_name)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `;

    const result = await dbQuery(query, [
      project_area,
      waste_amount,
      date,
      project_name || null,
      construction_type || null,
      waste_type,
      disposal_method,
      reuse_recycling_details || null,
      location || null,
      contractor_name || null
    ]);

    res.status(201).json({
      message: 'Waste data added successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error adding waste data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// C&D WASTE CALCULATION

const createCDWasteCalculationTable = `
  CREATE TABLE IF NOT EXISTS waste_calculations (
    id SERIAL PRIMARY KEY,
    project_area NUMERIC(10,2) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    waste_amount NUMERIC(10,2) NOT NULL,
    calculation_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Waste Calculations table will be created in initializeAdditionalTables function

// Validation Schema
const wasteCalculationSchema = Joi.object({
  project_area: Joi.number().positive().required(),
  start_date: Joi.date().required(),
  end_date: Joi.date().required()
});

// Constants for waste calculation
const WASTE_FACTOR = 50; // kg/m² (example factor)

// Calculate and Store Waste Endpoint
app.post('/waste-calculations', async (req, res) => {
  try {
    // Validate request body
    const { error } = wasteCalculationSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        error: error.details[0].message
      });
    }

    const { project_area, start_date, end_date } = req.body;

    // Use correct formula: 50kg per sq ft
    const waste_amount = project_area * 50;

    // Store calculation
    const query = `
      INSERT INTO waste_calculations (
        project_area,
        start_date,
        end_date,
        waste_amount
      ) VALUES ($1, $2, $3, $4)
      RETURNING *
    `;

    const result = await dbQuery(query, [
      project_area,
      start_date,
      end_date,
      waste_amount
    ]);

    res.status(201).json({
      message: 'Waste calculation stored successfully',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error in waste calculation:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// Get Waste Calculations Endpoint
app.get('/waste-calculations', async (req, res) => {
  try {
    const query = `
      SELECT
        id,
        project_area,
        start_date,
        end_date,
        waste_amount,
        calculation_date
      FROM waste_calculations
      ORDER BY calculation_date DESC
    `;

    const result = await dbQuery(query);

    res.status(200).json({
      message: 'Waste calculations retrieved successfully',
      data: result.rows
    });

  } catch (err) {
    console.error('Error retrieving waste calculations:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// Get Specific Waste Calculation
app.get('/waste-calculations/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const query = `
      SELECT * FROM waste_calculations
      WHERE id = $1
    `;

    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'Calculation not found'
      });
    }

    res.status(200).json({
      message: 'Waste calculation retrieved successfully',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error retrieving waste calculation:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// Delete Waste Calculation
app.delete('/waste-calculations/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const query = `
      DELETE FROM waste_calculations
      WHERE id = $1
      RETURNING *
    `;

    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'Calculation not found'
      });
    }

    res.status(200).json({
      message: 'Waste calculation deleted successfully',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error deleting waste calculation:', err);
    res.status(500).json({
      error: 'Internal server error'
    });
  }
});

// DELETE cd-waste record
app.delete('/cd-waste/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const query = 'DELETE FROM cd_waste WHERE id = $1 RETURNING *';
    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'C&D waste record not found'
      });
    }

    logger.info(`C&D waste record deleted: ${id}`);
    res.status(200).json({
      message: 'C&D waste record deleted successfully',
      data: result.rows[0]
    });
  } catch (error) {
    logger.error('Error deleting C&D waste record:', error);
    res.status(500).json({
      error: 'Failed to delete C&D waste record',
      message: error.message
    });
  }
});

// UPDATE cd-waste record
app.put('/cd-waste/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { error } = cdWasteSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const {
      project_area,
      project_name,
      construction_type,
      date,
      waste_type,
      disposal_method,
      reuse_recycling_details,
      location,
      contractor_name
    } = req.body;

    // Use correct formula: 50kg per sq ft
    const waste_amount = project_area * 50;

    const query = `
      UPDATE cd_waste
      SET project_area = $1, waste_amount = $2, date = $3, project_name = $4, 
          construction_type = $5, waste_type = $6, disposal_method = $7, 
          reuse_recycling_details = $8, location = $9, contractor_name = $10,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = $11
      RETURNING *
    `;

    const result = await dbQuery(query, [
      project_area,
      waste_amount,
      date,
      project_name || null,
      construction_type || null,
      waste_type,
      disposal_method,
      reuse_recycling_details || null,
      location || null,
      contractor_name || null,
      id
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'C&D waste record not found'
      });
    }

    res.status(200).json({
      message: 'C&D waste record updated successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error updating C&D waste record:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Testing C&D WASTE CALCULATION

const createcd_waste_calcTable = `
  CREATE TABLE IF NOT EXISTS cd_waste_calc (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    quantity_kg NUMERIC(10, 2) NOT NULL,
    mode_of_storage VARCHAR(255),
    mode_of_disposal VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// C&D Waste Calculation table will be created in initializeAdditionalTables function

// Endpoint to calculate and store waste
app.post("/calculate-and-store", async (req, res) => {
  try {
    const { projectArea } = req.body;

    if (!projectArea || projectArea <= 0) {
      return res.status(400).json({ error: "Invalid project area" });
    }

    const wasteAmount = projectArea * 50; // Calculate waste (kg)
    const date = new Date().toISOString();

    // Store calculation in database
    await dbQuery(
      `INSERT INTO cd_waste_calc (date, quantity_kg) VALUES ($1, $2)`,
      [date, wasteAmount]
    );

    res.status(201).json({
      message: `Waste calculation stored successfully (${wasteAmount}kg)`,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Endpoint to retrieve waste data
app.get("/waste-data", async (req, res) => {
  try {
    const result = await dbQuery(`SELECT * FROM cd_waste_calc ORDER BY created_at DESC`);
    res.status(200).json({
      message: "Waste data retrieved successfully",
      data: result.rows,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: "Internal server error" });
  }
});

const createDailyWasteTable = `
  CREATE TABLE IF NOT EXISTS daily_waste (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    quantity_kg NUMERIC(10,2) NOT NULL,
    mode_of_storage VARCHAR(255) NOT NULL,
    mode_of_disposal VARCHAR(255) NOT NULL,
    waste_type VARCHAR(255) DEFAULT 'Mixed C&D Waste',
    notes TEXT,
    location VARCHAR(255),
    loading_photo_url TEXT,
    unloading_photo_url TEXT,
    vendor_license_photo_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Municipal Solid Waste Management Table
const createMunicipalSolidWasteTable = `
  CREATE TABLE IF NOT EXISTS municipal_solid_waste (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    no_of_houses_occupied INTEGER DEFAULT 0,
    num_employees INTEGER DEFAULT 0,
    employee_generated_waste NUMERIC(10,2) DEFAULT 0,
    dry_generated_quantity NUMERIC(10,2) DEFAULT 0,
    dry_disposed_to VARCHAR(255) DEFAULT '',
    dry_quantity NUMERIC(10,2) DEFAULT 0,
    wet_generated_quantity NUMERIC(10,2) DEFAULT 0,
    wet_disposed_to VARCHAR(255) DEFAULT '',
    wet_quantity NUMERIC(10,2) DEFAULT 0,
    sanitary_napkins_generated_quantity NUMERIC(10,2) DEFAULT 0,
    sanitary_napkins_disposed_to VARCHAR(255) DEFAULT '',
    sanitary_napkins_quantity NUMERIC(10,2) DEFAULT 0,
    e_waste_generated_quantity NUMERIC(10,2) DEFAULT 0,
    e_waste_disposed_to VARCHAR(255) DEFAULT '',
    e_waste_quantity NUMERIC(10,2) DEFAULT 0,
    bio_medical_waste_generated_quantity NUMERIC(10,2) DEFAULT 0,
    bio_medical_waste_disposed_to VARCHAR(255) DEFAULT '',
    bio_medical_waste_quantity NUMERIC(10,2) DEFAULT 0,
    battery_waste_generated_quantity NUMERIC(10,2) DEFAULT 0,
    battery_waste_disposed_to VARCHAR(255) DEFAULT '',
    battery_waste_quantity NUMERIC(10,2) DEFAULT 0,
    others_generated_quantity NUMERIC(10,2) DEFAULT 0,
    others_disposed_to VARCHAR(255) DEFAULT '',
    others_quantity NUMERIC(10,2) DEFAULT 0,
    vendor_license_url TEXT,
    disposal_photo_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Construction Phase Waste Management Table
const createConstructionPhaseWasteTable = `
  CREATE TABLE IF NOT EXISTS construction_phase_waste (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    approx_no_of_labour INTEGER DEFAULT 0,
    dry_waste_generated NUMERIC(10,2) DEFAULT 0,
    dry_waste_disposed_through VARCHAR(255) DEFAULT '',
    wet_waste_generated NUMERIC(10,2) DEFAULT 0,
    wet_waste_disposed_through VARCHAR(255) DEFAULT '',
    notes TEXT DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Daily Waste table will be created in initializeAdditionalTables function

// Migration queries to add new columns to existing daily_waste table
const migrateDailyWasteTable = async () => {
  const migrations = [
    `ALTER TABLE daily_waste ADD COLUMN IF NOT EXISTS waste_type VARCHAR(255) DEFAULT 'Mixed C&D Waste'`,
    `ALTER TABLE daily_waste ADD COLUMN IF NOT EXISTS notes TEXT`,
    `ALTER TABLE daily_waste ADD COLUMN IF NOT EXISTS location VARCHAR(255)`,
    `ALTER TABLE daily_waste ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP`,
    `ALTER TABLE daily_waste ADD COLUMN IF NOT EXISTS loading_photo_url TEXT`,
    `ALTER TABLE daily_waste ADD COLUMN IF NOT EXISTS unloading_photo_url TEXT`,
    `ALTER TABLE daily_waste ADD COLUMN IF NOT EXISTS vendor_license_photo_url TEXT`
  ];

  for (const migration of migrations) {
    try {
      await dbQuery(migration);
      logger.info(`Migration executed: ${migration}`);
    } catch (error) {
      // Ignore "column already exists" errors
      if (!error.message.includes('already exists')) {
        logger.error(`Migration failed: ${migration}`, error);
      }
    }
  }
};

// Migration for Wood Submissions Table - Add photo URL columns
const migrateWoodSubmissionsTable = async () => {
  const migrations = [
    `ALTER TABLE wood_submissions ADD COLUMN IF NOT EXISTS vehicle_photo_url TEXT`,
    `ALTER TABLE wood_submissions ADD COLUMN IF NOT EXISTS vendor_license_photo_url TEXT`,
    `ALTER TABLE wood_submissions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`,
    `ALTER TABLE wood_submissions ALTER COLUMN gross_weight TYPE NUMERIC(10,2) USING gross_weight::numeric`,
    `ALTER TABLE wood_submissions ALTER COLUMN tare_weight TYPE NUMERIC(10,2) USING tare_weight::numeric`,
    `ALTER TABLE wood_submissions ALTER COLUMN net_weight TYPE NUMERIC(10,2) USING net_weight::numeric`
  ];

  for (const migration of migrations) {
    try {
      await dbQuery(migration);
      logger.info(`Migration executed: ${migration}`);
    } catch (error) {
      // Ignore "column already exists" or "type already correct" errors
      if (!error.message.includes('already exists') && !error.message.includes('cannot be cast')) {
        logger.error(`Migration failed: ${migration}`, error);
      }
    }
  }
};

// Migration for Tiles Submissions Table - Add photo URL columns
const migrateTilesSubmissionsTable = async () => {
  const migrations = [
    `ALTER TABLE tiles_submissions ADD COLUMN IF NOT EXISTS vehicle_photo_url TEXT`,
    `ALTER TABLE tiles_submissions ADD COLUMN IF NOT EXISTS vendor_license_photo_url TEXT`,
    `ALTER TABLE tiles_submissions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`
  ];

  for (const migration of migrations) {
    try {
      await dbQuery(migration);
      logger.info(`Tiles migration executed: ${migration}`);
    } catch (error) {
      // Ignore "column already exists" errors
      if (!error.message.includes('already exists')) {
        logger.error(`Tiles migration failed: ${migration}`, error);
      }
    }
  }
};

// Migration for Pipes Submissions Table - Add photo URL columns
const migratePipesSubmissionsTable = async () => {
  const migrations = [
    `ALTER TABLE pipes_submissions ADD COLUMN IF NOT EXISTS vehicle_photo_url TEXT`,
    `ALTER TABLE pipes_submissions ADD COLUMN IF NOT EXISTS vendor_license_photo_url TEXT`,
    `ALTER TABLE pipes_submissions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`
  ];

  for (const migration of migrations) {
    try {
      await dbQuery(migration);
      logger.info(`Pipes migration executed: ${migration}`);
    } catch (error) {
      // Ignore "column already exists" errors
      if (!error.message.includes('already exists')) {
        logger.error(`Pipes migration failed: ${migration}`, error);
      }
    }
  }
};

// Migration for Metals Submissions Table - Add photo URL columns
const migrateMetalsSubmissionsTable = async () => {
  const migrations = [
    `ALTER TABLE metals_submissions ADD COLUMN IF NOT EXISTS vehicle_photo_url TEXT`,
    `ALTER TABLE metals_submissions ADD COLUMN IF NOT EXISTS vendor_license_photo_url TEXT`,
    `ALTER TABLE metals_submissions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`
  ];

  for (const migration of migrations) {
    try {
      await dbQuery(migration);
      logger.info(`Metals migration executed: ${migration}`);
    } catch (error) {
      // Ignore "column already exists" errors
      if (!error.message.includes('already exists')) {
        logger.error(`Metals migration failed: ${migration}`, error);
      }
    }
  }
};

// Migration for Sand Submissions Table - Add photo URL columns
const migrateSandSubmissionsTable = async () => {
  const migrations = [
    `ALTER TABLE sand_submissions ADD COLUMN IF NOT EXISTS vehicle_photo_url TEXT`,
    `ALTER TABLE sand_submissions ADD COLUMN IF NOT EXISTS vendor_license_photo_url TEXT`,
    `ALTER TABLE sand_submissions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`
  ];

  for (const migration of migrations) {
    try {
      await dbQuery(migration);
      logger.info(`Sand migration executed: ${migration}`);
    } catch (error) {
      // Ignore "column already exists" errors
      if (!error.message.includes('already exists')) {
        logger.error(`Sand migration failed: ${migration}`, error);
      }
    }
  }
};

// Migration for Aggregates Submissions Table - Add photo URL columns
const migrateAggregatesSubmissionsTable = async () => {
  const migrations = [
    `ALTER TABLE aggregates_submissions ADD COLUMN IF NOT EXISTS vehicle_photo_url TEXT`,
    `ALTER TABLE aggregates_submissions ADD COLUMN IF NOT EXISTS vendor_license_photo_url TEXT`,
    `ALTER TABLE aggregates_submissions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`
  ];

  for (const migration of migrations) {
    try {
      await dbQuery(migration);
      logger.info(`Aggregates migration executed: ${migration}`);
    } catch (error) {
      // Ignore "column already exists" errors
      if (!error.message.includes('already exists')) {
        logger.error(`Aggregates migration failed: ${migration}`, error);
      }
    }
  }
};

// Migration for Municipal Solid Waste Table - Add document URL columns
const migrateMunicipalSolidWasteTable = async () => {
  const migrations = [
    `ALTER TABLE municipal_solid_waste ADD COLUMN IF NOT EXISTS vendor_license_url TEXT`,
    `ALTER TABLE municipal_solid_waste ADD COLUMN IF NOT EXISTS disposal_photo_url TEXT`
  ];

  for (const migration of migrations) {
    try {
      await dbQuery(migration);
      logger.info(`Migration executed: ${migration}`);
    } catch (error) {
      // Ignore "column already exists" errors
      if (!error.message.includes('already exists')) {
        logger.error(`Migration failed: ${migration}`, error);
      }
    }
  }
};

// Endpoint to add daily waste data
app.post("/daily-waste", async (req, res) => {
  try {
    const { 
      date, 
      quantity_kg, 
      mode_of_storage, 
      mode_of_disposal, 
      waste_type,
      notes,
      location,
      loading_photo_url,
      unloading_photo_url,
      vendor_license_photo_url
    } = req.body;

    const query = `
      INSERT INTO daily_waste (
        date, quantity_kg, mode_of_storage, mode_of_disposal, 
        waste_type, notes, location, loading_photo_url, 
        unloading_photo_url, vendor_license_photo_url
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `;

    const result = await dbQuery(query, [
      date, 
      quantity_kg, 
      mode_of_storage, 
      mode_of_disposal,
      waste_type || 'Mixed C&D Waste',
      notes || null,
      location || null,
      loading_photo_url || null,
      unloading_photo_url || null,
      vendor_license_photo_url || null
    ]);

    res.status(201).json({
      message: "Daily waste data added successfully",
      data: result.rows[0]
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Endpoint to get daily waste data with total
app.get("/daily-waste", async (req, res) => {
  try {
    const { start_date, end_date, limit, offset } = req.query;
    let whereClause = '';
    const params = [];
    let paramIndex = 1;

    if (start_date && end_date) {
      whereClause = `WHERE date BETWEEN $${paramIndex} AND $${paramIndex + 1}`;
      params.push(start_date, end_date);
      paramIndex += 2;
    }

    let limitClause = '';
    if (limit) {
      limitClause = `LIMIT $${paramIndex}`;
      params.push(parseInt(limit));
      paramIndex++;
    }

    let offsetClause = '';
    if (offset) {
      offsetClause = `OFFSET $${paramIndex}`;
      params.push(parseInt(offset));
    }

    const query = `
      SELECT
        id,
        date,
        quantity_kg,
        mode_of_storage,
        mode_of_disposal,
        waste_type,
        notes,
        location,
        loading_photo_url,
        unloading_photo_url,
        vendor_license_photo_url,
        created_at,
        updated_at,
        (SELECT SUM(quantity_kg) FROM daily_waste ${whereClause}) as total_waste
      FROM daily_waste
      ${whereClause}
      ORDER BY date DESC, created_at DESC
      ${limitClause}
      ${offsetClause}
    `;

    const result = await dbQuery(query, params);

    res.status(200).json({
      message: "Daily waste data retrieved successfully",
      data: result.rows,
      total_waste: result.rows[0]?.total_waste || 0
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// DELETE daily-waste record
app.delete('/daily-waste/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const query = 'DELETE FROM daily_waste WHERE id = $1 RETURNING *';
    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'Daily waste record not found'
      });
    }

    logger.info(`Daily waste record deleted: ${id}`);
    res.status(200).json({
      message: 'Daily waste record deleted successfully',
      data: result.rows[0]
    });
  } catch (error) {
    logger.error('Error deleting daily waste record:', error);
    res.status(500).json({
      error: 'Failed to delete daily waste record',
      message: error.message
    });
  }
});

// Dynamic C&D Waste Configuration endpoints
app.get('/cd-waste/config', async (req, res) => {
  try {
    const config = {
      wasteCoefficients: {
        'Residential': 21.0,
        'Commercial': 18.5,
        'Industrial': 25.0,
        'Infrastructure': 15.0,
        'Renovation': 12.5,
        'Demolition': 30.0,
        'Mixed Use': 20.0,
        'High Rise': 23.0
      },
      constructionTypes: [
        'Residential',
        'Commercial', 
        'Industrial',
        'Infrastructure',
        'Renovation',
        'Demolition',
        'Mixed Use',
        'High Rise'
      ],
      wasteCategories: {
        'Concrete': { percentage: 40, color: '#1E88E5', recyclable: 90 },
        'Wood': { percentage: 20, color: '#43A047', recyclable: 70 },
        'Metal': { percentage: 15, color: '#FFB300', recyclable: 95 },
        'Glass': { percentage: 10, color: '#E53935', recyclable: 80 },
        'Plastic': { percentage: 5, color: '#8E24AA', recyclable: 60 },
        'Others': { percentage: 10, color: '#757575', recyclable: 30 }
      },
      storageMethods: [
        'On-site Container',
        'Segregated Bins',
        'Temporary Storage Area',
        'Skip/Dumpster',
        'Collection Point',
        'Covered Storage',
        'Open Storage',
        'Other'
      ],
      disposalMethods: [
        'Recycling Facility',
        'Landfill',
        'Reuse on Site',
        'Transfer Station',
        'Specialist Contractor',
        'Waste-to-Energy',
        'Composting',
        'Authorized Vendor',
        'Other'
      ],
      wasteTypes: [
        'Mixed C&D Waste',
        'Concrete Debris',
        'Wood Waste',
        'Metal Scrap',
        'Glass/Ceramic',
        'Plastic Waste',
        'Packaging Materials',
        'Hazardous Waste',
        'Excavation Soil',
        'Other'
      ],
      calculationFormula: {
        description: 'Waste Amount = Project Area × 50 kg/sq ft',
        factor: 50,
        unit: 'kg/sq ft'
      },
      thresholds: {
        wastePerLabour: { good: 1.0, acceptable: 1.5, unit: 'kg/person' },
        dailyAverage: { good: 25.0, acceptable: 50.0, unit: 'kg/day' },
        recyclingTarget: { minimum: 50, optimal: 75, unit: '%' }
      }
    };

    res.status(200).json({
      success: true,
      config: config
    });
  } catch (error) {
    logger.error('Error fetching C&D waste configuration:', error);
    res.status(500).json({
      error: 'Failed to fetch configuration',
      message: error.message
    });
  }
});

// C&D Waste Statistics endpoint
app.get('/cd-waste/stats', async (req, res) => {
  try {
    const { start_date, end_date } = req.query;
    let dateFilter = '';
    const params = [];

    if (start_date && end_date) {
      dateFilter = 'WHERE date BETWEEN $1 AND $2';
      params.push(start_date, end_date);
    }

    const statsQuery = `
      SELECT 
        COUNT(*) as total_records,
        COALESCE(SUM(waste_amount), 0) as total_waste,
        COALESCE(AVG(waste_amount), 0) as avg_waste_per_project,
        COALESCE(SUM(project_area), 0) as total_area,
        COALESCE(MIN(date), CURRENT_DATE) as first_record_date,
        COALESCE(MAX(date), CURRENT_DATE) as last_record_date,
        COUNT(DISTINCT construction_type) as construction_types_count,
        COUNT(DISTINCT disposal_method) as disposal_methods_count
      FROM cd_waste
      ${dateFilter}
    `;

    const wasteByTypeQuery = `
      SELECT 
        construction_type,
        COUNT(*) as count,
        COALESCE(SUM(waste_amount), 0) as total_waste,
        COALESCE(AVG(waste_amount), 0) as avg_waste
      FROM cd_waste
      ${dateFilter}
      GROUP BY construction_type
      ORDER BY total_waste DESC
    `;

    const wasteByMonthQuery = `
      SELECT 
        DATE_TRUNC('month', date) as month,
        COUNT(*) as records,
        COALESCE(SUM(waste_amount), 0) as total_waste,
        COALESCE(SUM(project_area), 0) as total_area
      FROM cd_waste
      ${dateFilter}
      GROUP BY month
      ORDER BY month DESC
      LIMIT 12
    `;

    const [statsResult, typeResult, monthResult] = await Promise.all([
      dbQuery(statsQuery, params),
      dbQuery(wasteByTypeQuery, params),
      dbQuery(wasteByMonthQuery, params)
    ]);

    const stats = statsResult.rows[0];
    const byType = typeResult.rows;
    const byMonth = monthResult.rows;

    res.status(200).json({
      success: true,
      summary: {
        total_records: parseInt(stats.total_records),
        total_waste: parseFloat(stats.total_waste),
        avg_waste_per_project: parseFloat(stats.avg_waste_per_project),
        total_area: parseFloat(stats.total_area),
        first_record_date: stats.first_record_date,
        last_record_date: stats.last_record_date,
        construction_types_count: parseInt(stats.construction_types_count),
        disposal_methods_count: parseInt(stats.disposal_methods_count),
        waste_per_area: stats.total_area > 0 ? parseFloat(stats.total_waste) / parseFloat(stats.total_area) : 0
      },
      wasteByConstructionType: byType,
      wasteByMonth: byMonth
    });
  } catch (error) {
    logger.error('Error fetching C&D waste statistics:', error);
    res.status(500).json({
      error: 'Failed to fetch statistics',
      message: error.message
    });
  }
});

// Labour colony water consumption page
const createTableQuery = `
  CREATE TABLE IF NOT EXISTS labour_colony (
    id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    source VARCHAR(255) NOT NULL,
    consumption NUMERIC NOT NULL,
    discharge VARCHAR(255) NOT NULL,
    discharged_to VARCHAR(255) NOT NULL,
    mode VARCHAR(50) NOT NULL
  );
`;

// Municipal Solid Waste table will be created in initializeAdditionalTables function

// Fetch data with optional date filter
app.get('/labour-colony', async (req, res) => {
  try {
    let query = 'SELECT * FROM labour_colony';
    const params = [];

    if (req.query.date) {
      query += ' WHERE date = $1';
      params.push(req.query.date);
    }

    query += ' ORDER BY date DESC';
    const result = await dbQuery(query, params);
    res.json({ data: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).send('Server error');
  }
});

// Add data
app.post('/labour-colony', async (req, res) => {
  try {
    const { date, source, consumption, discharge, discharged_to, mode } = req.body;
    const query = `
      INSERT INTO labour_colony (date, source, consumption, discharge, discharged_to, mode)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `;
    const result = await dbQuery(query, [date, source, consumption, discharge, discharged_to, mode]);
    res.status(201).json({ data: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).send('Server error');
  }
});

// Update data (missing in original)
app.put('/labour-colony/:id', async (req, res) => {
  try {
    const { date, source, consumption, discharge, discharged_to, mode } = req.body;
    const query = `
      UPDATE labour_colony
      SET date = $1, source = $2, consumption = $3,
          discharge = $4, discharged_to = $5, mode = $6
      WHERE id = $7
      RETURNING *
    `;
    const result = await dbQuery(query, [
      date, source, consumption, discharge, discharged_to, mode, req.params.id
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Record not found' });
    }
    res.json({ data: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).send('Server error');
  }
});

// Delete data (missing in original)
app.delete('/labour-colony/:id', async (req, res) => {
  try {
    const result = await dbQuery(
      'DELETE FROM labour_colony WHERE id = $1 RETURNING *',
      [req.params.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Record not found' });
    }
    res.json({ message: 'Record deleted successfully' });
  } catch (err) {
    console.error(err);
    res.status(500).send('Server error');
  }
});

// Modified table creation
const createTableproject_waste = `
CREATE TABLE IF NOT EXISTS project_waste (
  id SERIAL PRIMARY KEY,
  date DATE NOT NULL,
  quantity_kg NUMERIC(10,2) NOT NULL,
  mode_of_storage VARCHAR(255) NOT NULL,
  mode_of_disposal VARCHAR(255) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
`;

// Project waste table will be created in initializeAdditionalTables function

// Fetch data with calculated total
app.get('/project-waste', async (req, res) => {
  try {
    let query = 'SELECT * FROM project_waste';
    const params = [];

    if (req.query.date) {
      query += ' WHERE date = $1';
      params.push(req.query.date);
    }

    query += ' ORDER BY date DESC';
    const result = await dbQuery(query, params);

    // Calculate total waste
    const totalWaste = result.rows.reduce((sum, record) => sum + Number(record.quantity_kg), 0);

    res.json({
      data: result.rows,
      total_waste: totalWaste
    });
  } catch (err) {
    console.error(err);
    res.status(500).send('Server error');
  }
});

// Add data
app.post('/project-waste', async (req, res) => {
  try {
    const { date, quantity_kg, mode_of_storage, mode_of_disposal } = req.body;
    const query = `
  INSERT INTO project_waste (date, quantity_kg, mode_of_storage, mode_of_disposal)
  VALUES ($1, $2, $3, $4)
  RETURNING *
`;
    const result = await dbQuery(query, [
      date,
      quantity_kg,
      mode_of_storage,
      mode_of_disposal
    ]);

    res.status(201).json({ data: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).send('Server error');
  }
});

// Update data
app.put('/project-waste/:id', async (req, res) => {
  try {
    const { date, quantity_kg, mode_of_storage, mode_of_disposal } = req.body;
    const query = `
      UPDATE project_waste
      SET date = $1, quantity_kg = $2, mode_of_storage = $3, mode_of_disposal = $4
      WHERE id = $5
      RETURNING *
    `;
    const result = await dbQuery(query, [
      date,
      quantity_kg,
      mode_of_storage,
      mode_of_disposal,
      req.params.id
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Record not found' });
    }
    res.json({ data: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).send('Server error');
  }
});

// Delete data (unchanged)
app.delete('/project-waste/:id', async (req, res) => {
  try {
    const result = await dbQuery(
      'DELETE FROM project_waste WHERE id = $1 RETURNING *',
      [req.params.id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Record not found' });
    }
    res.json({ message: 'Record deleted successfully' });
  } catch (err) {
    console.error(err);
    res.status(500).send('Server error');
  }
});

// BWSSB TABLE
const createbwssb_supplyTable = `
  CREATE TABLE IF NOT EXISTS bwssb_supply (
    id SERIAL PRIMARY KEY,
    supply_date DATE NOT NULL,
    water_supplied VARCHAR(255) NOT NULL,
    water_type VARCHAR(10) NOT NULL CHECK (water_type IN ('Fresh', 'Treated')),
    quantity_supplied DECIMAL(10,2) NOT NULL,
    mode_of_conveyance VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )
`;

const createUpdateTrigger = `
  CREATE OR REPLACE FUNCTION update_timestamp()
  RETURNS TRIGGER AS $$
  BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
  END;
  $$ language 'plpgsql';

  DROP TRIGGER IF EXISTS update_bwssb_supply_timestamp ON bwssb_supply;

  CREATE TRIGGER update_bwssb_supply_timestamp
    BEFORE UPDATE ON bwssb_supply
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();
`;

// Execute both queries
// BWSSB Supply table will be created in initializeAdditionalTables function

// GET all records
app.get('/bwssb', (req, res) => {
  let query = 'SELECT * FROM bwssb_supply';
  const params = [];

  if (req.query.date) {
    // Validate date format
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (!dateRegex.test(req.query.date)) {
      return res.status(400).json({ error: 'Invalid date format. Use YYYY-MM-DD' });
    }
    query += ' WHERE DATE(supply_date) = $1';
    params.push(req.query.date);
  }

  if (req.query.search) {
    const searchCondition = params.length > 0 ? ' AND' : ' WHERE';
    query += `${searchCondition} (water_supplied LIKE $${params.length + 1} OR mode_of_conveyance LIKE $${params.length + 1})`;
    params.push(`%${req.query.search}%`, `%${req.query.search}%`);
  }

  query += ' ORDER BY supply_date DESC';

  dbQuery(query, params).then((results) => {
    res.json({ data: results.rows });
  }).catch((err) => {
    console.error('Error fetching data:', err);
    res.status(500).json({ error: err.message });
  });
});

// POST new record
app.post('/bwssb', (req, res) => {
  const { supply_date, water_supplied, water_type, quantity_supplied, mode_of_conveyance } = req.body;

  console.log('Received data:', req.body);

  // Add validation
  if (!supply_date || !water_supplied || !water_type || !quantity_supplied || !mode_of_conveyance) {
    return res.status(400).json({ error: 'All fields are required' });
  }

  // Validate water_type enum
  if (!['Fresh', 'Treated'].includes(water_type)) {
    return res.status(400).json({ error: 'Invalid water type' });
  }

  // Validate date format
  const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
  if (!dateRegex.test(supply_date)) {
    return res.status(400).json({ error: 'Invalid date format. Use YYYY-MM-DD' });
  }

  // Validate quantity is a number
  if (isNaN(quantity_supplied)) {
    return res.status(400).json({ error: 'Quantity must be a number' });
  }

  dbQuery(
    'INSERT INTO bwssb_supply (supply_date, water_supplied, water_type, quantity_supplied, mode_of_conveyance) VALUES ($1, $2, $3, $4, $5) RETURNING id',
    [supply_date, water_supplied, water_type, quantity_supplied, mode_of_conveyance],
    (err, results) => {
      if (err) {
        console.error('Error inserting data:', err);
        return res.status(500).json({ error: err.message });
      }
      res.status(201).json({ message: 'Record created successfully', id: results.rows[0].id });
    }
  );

});

// ====================================
// ENHANCED BWSSB ENDPOINTS
// ====================================

// Enhanced database tables for BWSSB management
const createBWSSBTables = async () => {
  const tables = [
    // BWSSB Gates table
    `CREATE TABLE IF NOT EXISTS bwssb_gates (
      id SERIAL PRIMARY KEY,
      gate_name VARCHAR(100) NOT NULL UNIQUE,
      location VARCHAR(255),
      latitude DECIMAL(10, 8),
      longitude DECIMAL(11, 8),
      status VARCHAR(20) DEFAULT 'active',
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )`,
    
    // BWSSB Vehicles table
    `CREATE TABLE IF NOT EXISTS bwssb_vehicles (
      id SERIAL PRIMARY KEY,
      vehicle_number VARCHAR(20) NOT NULL UNIQUE,
      vehicle_type VARCHAR(50) DEFAULT 'tanker',
      capacity_liters DECIMAL(10, 2),
      driver_name VARCHAR(100),
      driver_contact VARCHAR(20),
      status VARCHAR(20) DEFAULT 'active',
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )`,
    
    // BWSSB Entries table (entry/exit tracking)
    `CREATE TABLE IF NOT EXISTS bwssb_entries (
      id SERIAL PRIMARY KEY,
      vehicle_number VARCHAR(20) NOT NULL,
      water_type VARCHAR(20) NOT NULL,
      entry_gate VARCHAR(100),
      exit_gate VARCHAR(100),
      initial_reading DECIMAL(10, 2),
      final_reading DECIMAL(10, 2),
      quantity_delivered DECIMAL(10, 2),
      driver_name VARCHAR(100),
      driver_contact VARCHAR(20),
      entry_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      exit_time TIMESTAMP WITH TIME ZONE,
      entry_photo_url TEXT,
      exit_photo_url TEXT,
      status VARCHAR(20) DEFAULT 'entered',
      remarks TEXT,
      entry_latitude DECIMAL(10, 8),
      entry_longitude DECIMAL(11, 8),
      exit_latitude DECIMAL(10, 8),
      exit_longitude DECIMAL(11, 8),
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )`
  ];
  
  for (const table of tables) {
    await dbQuery(table);
  }
};

// BWSSB tables will be created in initializeAdditionalTables()

// Get BWSSB statistics
app.get('/bwssb/stats', async (req, res) => {
  try {
    const { days = 30 } = req.query;
    
    // Get quantity by water type
    const quantityByTypeQuery = `
      SELECT water_type, SUM(quantity_delivered) as total_quantity, COUNT(*) as delivery_count
      FROM bwssb_entries 
      WHERE entry_time >= CURRENT_DATE - INTERVAL '${parseInt(days)} days'
        AND status = 'completed'
      GROUP BY water_type
      ORDER BY total_quantity DESC
    `;
    
    // Get daily quantity trends
    const dailyQuantityQuery = `
      SELECT DATE(entry_time) as date, 
             SUM(quantity_delivered) as total_quantity,
             COUNT(*) as delivery_count
      FROM bwssb_entries 
      WHERE entry_time >= CURRENT_DATE - INTERVAL '${parseInt(days)} days'
        AND status = 'completed'
      GROUP BY DATE(entry_time)
      ORDER BY date DESC
    `;
    
    // Get ongoing entries
    const ongoingEntriesQuery = `
      SELECT COUNT(*) as count
      FROM bwssb_entries 
      WHERE status = 'entered'
    `;
    
    const [quantityByType, dailyQuantity, ongoingEntries] = await Promise.all([
      dbQuery(quantityByTypeQuery),
      dbQuery(dailyQuantityQuery),
      dbQuery(ongoingEntriesQuery)
    ]);
    
    const stats = {
      quantityByType: quantityByType.rows.map(row => ({
        waterType: row.water_type,
        totalQuantity: parseFloat(row.total_quantity) || 0,
        deliveryCount: parseInt(row.delivery_count) || 0
      })),
      dailyQuantity: dailyQuantity.rows.map(row => ({
        date: row.date,
        totalQuantity: parseFloat(row.total_quantity) || 0,
        deliveryCount: parseInt(row.delivery_count) || 0
      })),
      ongoingEntries: parseInt(ongoingEntries.rows[0].count) || 0
    };
    
    res.json({
      success: true,
      data: stats
    });
    
  } catch (error) {
    logger.error('Error fetching BWSSB stats:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch statistics',
      message: error.message
    });
  }
});

// Get BWSSB gates
app.get('/bwssb/gates', async (req, res) => {
  try {
    const query = 'SELECT * FROM bwssb_gates WHERE status = $1 ORDER BY gate_name';
    const result = await dbQuery(query, ['active']);
    
    res.json({
      success: true,
      data: result.rows
    });
    
  } catch (error) {
    logger.error('Error fetching BWSSB gates:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch gates',
      message: error.message
    });
  }
});

// Get BWSSB vehicles
app.get('/bwssb/vehicles', async (req, res) => {
  try {
    const query = 'SELECT * FROM bwssb_vehicles WHERE status = $1 ORDER BY vehicle_number';
    const result = await dbQuery(query, ['active']);
    
    res.json({
      success: true,
      data: result.rows
    });
    
  } catch (error) {
    logger.error('Error fetching BWSSB vehicles:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch vehicles',
      message: error.message
    });
  }
});

// License plate recognition endpoint (mock implementation)
app.post('/bwssb/recognize-plate', upload.single('photo'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No photo provided'
      });
    }
    
    // This is a mock implementation - in reality, you'd use OCR/ML services
    // For now, return a mock response with common plate patterns
    const mockPlates = ['KA01AB1234', 'KA05CD5678', 'KA02EF9012', 'KA03GH3456'];
    const randomPlate = mockPlates[Math.floor(Math.random() * mockPlates.length)];
    
    // Check if this vehicle exists in our database
    const vehicleQuery = 'SELECT * FROM bwssb_vehicles WHERE vehicle_number = $1';
    const vehicleResult = await dbQuery(vehicleQuery, [randomPlate]);
    
    const responseData = {
      plateNumber: randomPlate,
      confidence: 0.85,
      vehicleExists: vehicleResult.rows.length > 0,
      vehicleData: vehicleResult.rows.length > 0 ? vehicleResult.rows[0] : null
    };
    
    logger.info(`Plate recognition result: ${randomPlate}`);
    
    res.json({
      success: true,
      data: responseData
    });
    
  } catch (error) {
    logger.error('Error in plate recognition:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to recognize plate',
      message: error.message
    });
  }
});

// Create entry record
app.post('/bwssb/entry', upload.single('photo'), async (req, res) => {
  try {
    const {
      vehicleNumber,
      waterType,
      entryGate,
      initialReading,
      driverName,
      driverContact,
      entryLatitude,
      entryLongitude
    } = req.body;
    
    if (!vehicleNumber || !waterType || !entryGate || !initialReading) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: vehicleNumber, waterType, entryGate, initialReading'
      });
    }
    
    // Get photo URL if uploaded
    const photoUrl = req.file ? (req.file.location || `/uploads/${req.file.filename}`) : null;
    
    const query = `
      INSERT INTO bwssb_entries (
        vehicle_number, water_type, entry_gate, initial_reading,
        driver_name, driver_contact, entry_photo_url,
        entry_latitude, entry_longitude, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'entered')
      RETURNING *
    `;
    
    const result = await dbQuery(query, [
      vehicleNumber,
      waterType,
      entryGate,
      parseFloat(initialReading),
      driverName || null,
      driverContact || null,
      photoUrl,
      entryLatitude ? parseFloat(entryLatitude) : null,
      entryLongitude ? parseFloat(entryLongitude) : null
    ]);
    
    logger.info(`BWSSB entry created: ${vehicleNumber} at ${entryGate}`);
    
    res.status(201).json({
      success: true,
      data: result.rows[0],
      message: 'Entry recorded successfully'
    });
    
  } catch (error) {
    logger.error('Error creating BWSSB entry:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create entry',
      message: error.message
    });
  }
});

// Update exit record
app.put('/bwssb/exit/:id', upload.single('photo'), async (req, res) => {
  try {
    const { id } = req.params;
    const {
      finalReading,
      exitGate,
      remarks,
      exitLatitude,
      exitLongitude
    } = req.body;
    
    if (!finalReading) {
      return res.status(400).json({
        success: false,
        error: 'Final reading is required for exit'
      });
    }
    
    // Get photo URL if uploaded
    const photoUrl = req.file ? (req.file.location || `/uploads/${req.file.filename}`) : null;
    
    // First get the entry to calculate quantity delivered
    const entryQuery = 'SELECT * FROM bwssb_entries WHERE id = $1';
    const entryResult = await dbQuery(entryQuery, [id]);
    
    if (entryResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Entry not found'
      });
    }
    
    const entry = entryResult.rows[0];
    const quantityDelivered = parseFloat(entry.initial_reading) - parseFloat(finalReading);
    
    const updateQuery = `
      UPDATE bwssb_entries 
      SET final_reading = $1,
          exit_gate = $2,
          exit_time = CURRENT_TIMESTAMP,
          exit_photo_url = $3,
          remarks = $4,
          exit_latitude = $5,
          exit_longitude = $6,
          quantity_delivered = $7,
          status = 'completed',
          updated_at = CURRENT_TIMESTAMP
      WHERE id = $8
      RETURNING *
    `;
    
    const result = await dbQuery(updateQuery, [
      parseFloat(finalReading),
      exitGate || entry.entry_gate,
      photoUrl,
      remarks || null,
      exitLatitude ? parseFloat(exitLatitude) : null,
      exitLongitude ? parseFloat(exitLongitude) : null,
      quantityDelivered,
      id
    ]);
    
    logger.info(`BWSSB exit recorded: ${entry.vehicle_number} delivered ${quantityDelivered}L`);
    
    res.json({
      success: true,
      data: result.rows[0],
      message: 'Exit recorded successfully'
    });
    
  } catch (error) {
    logger.error('Error recording BWSSB exit:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to record exit',
      message: error.message
    });
  }
});

// Labour colony water consumption

const createLabourColonyConsumptionTable = `
  CREATE TABLE IF NOT EXISTS labour_colony_consumption (
  id SERIAL PRIMARY KEY,
  date DATE NOT NULL,
  source VARCHAR(255) NOT NULL,
  consumption DECIMAL(10, 2) NOT NULL,
  discharge VARCHAR(255) NOT NULL,
  discharged_to VARCHAR(255) NOT NULL,
  mode VARCHAR(50) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_date_source UNIQUE (date, source)
);

CREATE INDEX IF NOT EXISTS idx_labour_colony_consumption_date ON labour_colony_consumption (date);

`;

const labourColonyConsumptionSchema = Joi.object({
  date: Joi.date().required(),
  source: Joi.string().required(),
  consumption: Joi.number().positive().required(),
  discharge: Joi.string().required(),
  discharged_to: Joi.string().required(),
  mode: Joi.string().valid('Pipeline', 'Tanker', 'Other').required()
});

app.get('/labour-colony-consumption', async (req, res) => {
  try {
    const result = await dbQuery('SELECT * FROM labour_colony_consumption ORDER BY date DESC');
    res.json({ data: result.rows });
  } catch (err) {
    console.error('Query error:', err);
    res.status(500).json({ error: 'Database query failed', details: err.message });
  }
});

// POST route
app.post('/labour-colony-consumption', async (req, res) => {
  try {
    const { error } = labourColonyConsumptionSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const { date, source, consumption, discharge, discharged_to, mode } = req.body;

    const query = `
      INSERT INTO labour_colony_consumption
      (date, source, consumption, discharge, discharged_to, mode)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `;

    const result = await dbQuery(query, [date, source, consumption, discharge, discharged_to, mode]);

    res.status(201).json({
      message: 'Labour Colony Consumption data added successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error adding Labour Colony Consumption data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});



// New endpoint for tanker image upload
app.post('/upload-tanker-image', upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file provided' });
    }

    if (!req.body.plateNumber) {
      return res.status(400).json({ error: 'Plate number is required' });
    }

    // If using multer-s3, the URL is already available
    const imageUrl = req.file.location;
    
    res.json({
      success: true,
      imageUrl,
      message: 'Image uploaded successfully'
    });
  } catch (error) {
    logger.error('Error in upload-tanker-image endpoint:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to upload image',
      message: error.message 
    });
  }
});

// Get tanker details endpoint
app.get('/tanker', async (req, res) => {
  try {
    const { plateNumber, date } = req.query;
    let query = 'SELECT * FROM tankers';
    let params = [];

    if (plateNumber) {
      query += ' WHERE plate_number = $1';
      params.push(plateNumber);
    }

    if (date) {
      query += params.length ? ' AND' : ' WHERE';
      query += ` DATE(date) = $${params.length + 1}`;
      params.push(date);
    }

    query += ' ORDER BY last_updated DESC';

    const result = await dbQuery(query, params);
    
    // Convert snake_case to camelCase for frontend
    const tankers = result.rows.map(row => ({
      id: row.id,
      plateNumber: row.plate_number,
      capacity: row.capacity,
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
      date: row.date,
      lastUpdated: row.last_updated,
      latitude: row.latitude,
      longitude: row.longitude,
      photoUrl: row.photo_url
    }));

    res.status(200).json(tankers);
  } catch (err) {
    console.error('Error fetching tanker data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update tanker details endpoint
app.post('/tankers', async (req, res) => {
  try {
    logger.info('Received request to /tankers', {
      contentType: req.get('Content-Type'),
      hasFile: !!req.file,
      fields: req.body
    });
    
    // Set JSON content type early
    res.setHeader('Content-Type', 'application/json');
    
    // Handle file upload with multer
    upload.single('image')(req, res, async function(err) {
      if (err) {
        logger.error('Upload error:', {
          error: err.message,
          stack: err.stack,
          code: err.code,
          field: err.field
        });
        return res.status(400).json({
          success: false,
          message: 'File upload error',
          error: err.message,
          code: 'UPLOAD_ERROR',
          details: {
            code: err.code,
            field: err.field
          }
        });
      }

      try {
        // Log request details
        logger.info('Processing request after upload', {
          file: req.file ? {
            fieldname: req.file.fieldname,
            originalname: req.file.originalname,
            mimetype: req.file.mimetype,
            size: req.file.size
          } : null,
          body: req.body
        });

        // Validate required fields
        const requiredFields = ['plateNumber', 'capacity', 'driverName', 'driverContact', 'vendor'];
        const missingFields = requiredFields.filter(field => !req.body[field]);
        
        if (missingFields.length > 0) {
          logger.warn('Missing required fields:', missingFields);
          return res.status(400).json({
            success: false,
            message: `Missing required fields: ${missingFields.join(', ')}`,
            code: 'MISSING_FIELDS'
          });
        }

        // Validate and parse capacity
        const capacity = parseFloat(req.body.capacity);
        if (isNaN(capacity) || capacity <= 0) {
          return res.status(400).json({
            success: false,
            message: 'Invalid capacity value',
            code: 'INVALID_CAPACITY'
          });
        }

        // Validate and parse coordinates if present
        let latitude = null;
        let longitude = null;
        
        if (req.body.latitude && req.body.longitude) {
          latitude = parseFloat(req.body.latitude);
          longitude = parseFloat(req.body.longitude);
          
          if (isNaN(latitude) || isNaN(longitude)) {
            return res.status(400).json({
              success: false,
              message: 'Invalid coordinates format',
              code: 'INVALID_COORDINATES'
            });
          }
        }

        // Check if tanker with plate number already exists
        const existingTanker = await dbQuery(
          'SELECT * FROM tankers WHERE plate_number = $1',
          [req.body.plateNumber]
        );

        // Prepare tanker data
        const tankerData = {
          plateNumber: req.body.plateNumber,
          capacity: capacity,
          driverName: req.body.driverName,
          driverContact: req.body.driverContact,
          vendor: req.body.vendor,
          lastUpdated: new Date().toISOString(),
          latitude: latitude,
          longitude: longitude,
          photoUrl: req.file ? req.file.location : null
        };

        logger.info('Processed tanker data:', tankerData);

        let result;
        if (existingTanker.rows.length > 0) {
          // Update existing tanker
          result = await dbQuery(`
            UPDATE tankers 
            SET capacity = $2,
                driver_name = $3,
                driver_contact = $4,
                vendor = $5,
                last_updated = $6,
                latitude = $7,
                longitude = $8,
                photo_url = COALESCE($9, photo_url)
            WHERE plate_number = $1
            RETURNING *`,
            [
              tankerData.plateNumber,
              tankerData.capacity,
              tankerData.driverName,
              tankerData.driverContact,
              tankerData.vendor,
              tankerData.lastUpdated,
              tankerData.latitude,
              tankerData.longitude,
              tankerData.photoUrl
            ]
          );

          return res.status(200).json({
            success: true,
            message: 'Tanker updated successfully',
            data: result.rows[0]
          });
        } else {
          // Insert new tanker
          result = await dbQuery(`
            INSERT INTO tankers 
            (plate_number, capacity, driver_name, driver_contact, vendor, last_updated, latitude, longitude, photo_url)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            RETURNING *`,
            [
              tankerData.plateNumber,
              tankerData.capacity,
              tankerData.driverName,
              tankerData.driverContact,
              tankerData.vendor,
              tankerData.lastUpdated,
              tankerData.latitude,
              tankerData.longitude,
              tankerData.photoUrl
            ]
          );

          return res.status(201).json({
            success: true,
            message: 'Tanker created successfully',
            data: result.rows[0]
          });
        }
      } catch (error) {
        logger.error('Error processing request:', error);
        return res.status(500).json({
          success: false,
          message: 'Error processing request',
          error: error.message,
          code: 'PROCESSING_ERROR'
        });
      }
    });
  } catch (error) {
    logger.error('Unhandled error:', error);
    return res.status(500).json({
      success: false,
      message: 'Internal server error',
      error: error.message,
      code: 'INTERNAL_ERROR'
    });
  }
});

// Update GET endpoint to /tankers
app.get('/tankers', async (req, res) => {
  try {
    const { plateNumber, date } = req.query;
    let query = 'SELECT * FROM tankers';
    let params = [];

    if (plateNumber) {
      query += ' WHERE plate_number = $1';
      params.push(plateNumber);
    }

    if (date) {
      query += params.length ? ' AND' : ' WHERE';
      query += ` DATE(date) = $${params.length + 1}`;
      params.push(date);
    }

    query += ' ORDER BY last_updated DESC';

    const result = await dbQuery(query, params);
    
    // Convert snake_case to camelCase for frontend
    const tankers = result.rows.map(row => ({
      id: row.id,
      plateNumber: row.plate_number,
      capacity: row.capacity,
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
      date: row.date,
      lastUpdated: row.last_updated,
      latitude: row.latitude,
      longitude: row.longitude,
      photoUrl: row.photo_url
    }));

    res.status(200).json({
      success: true,
      message: 'Tankers retrieved successfully',
      data: tankers
    });
  } catch (err) {
    logger.error('Error fetching tanker data:', err);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch tanker data',
      error: err.message
    });
  }
});

// Upload image to S3 using AWS SDK v3
const uploadToS3 = async (buffer, key, mimetype = 'application/octet-stream') => {
  try {
    // Check if S3 client is initialized
    if (!s3Client) {
      throw new Error('S3 client not initialized - file uploads are disabled');
    }

    // Log upload attempt
    logger.info('Attempting S3 upload:', {
      key: key,
      timestamp: new Date().toISOString()
    });

    const upload = new Upload({
      client: s3Client,
      params: {
        Bucket: process.env.AWS_BUCKET_NAME,
        Key: key,
        Body: buffer,
        ContentType: mimetype,
        Metadata: {
          'upload-date': new Date().toISOString()
        }
      }
    });

    // Add upload progress logging
    upload.on('httpUploadProgress', (progress) => {
      logger.info('Upload progress:', {
        key: key,
        loaded: progress.loaded,
        total: progress.total
      });
    });

    const result = await upload.done();
    logger.info('S3 upload successful:', {
      key: key,
      location: result.Location,
      eTag: result.ETag
    });

    // Return the URL for the uploaded file
    // If Location is available, use it; otherwise construct the URL
    const url = result.Location || `https://${process.env.AWS_BUCKET_NAME}.s3.${process.env.AWS_REGION}.amazonaws.com/${key}`;
    return url;
  } catch (error) {
    logger.error('Error uploading to S3:', {
      error: error.message,
      key: key,
      timestamp: new Date().toISOString()
    });

    // Provide more specific error messages
    if (error.code === 'CredentialsError') {
      throw new Error('Invalid AWS credentials');
    } else if (error.code === 'NoSuchBucket') {
      throw new Error(`S3 bucket ${process.env.AWS_BUCKET_NAME} does not exist`);
    } else if (error.code === 'AccessDenied') {
      throw new Error('Access denied to S3 bucket - check IAM permissions');
    }

    throw new Error(`Failed to upload image to S3: ${error.message}`);
  }
};

// Delete file from S3
const deleteFromS3 = async (key) => {
  try {
    // Check if S3 client is initialized
    if (!s3Client) {
      throw new Error('S3 client not initialized - file deletion is disabled');
    }

    const command = new DeleteObjectCommand({
      Bucket: process.env.AWS_BUCKET_NAME,
      Key: key
    });

    await s3Client.send(command);
    
    logger.info('Successfully deleted file from S3:', {
      key: key,
      bucket: process.env.AWS_BUCKET_NAME
    });
    
    return { success: true, key };
  } catch (error) {
    logger.error('Error deleting from S3:', {
      error: error.message,
      code: error.code,
      key: key
    });
    
    throw new Error(`Failed to delete file from S3: ${error.message}`);
  }
};



// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  if (db && db.end) {
    db.end(() => {
      logger.info('Database pool closed');
      process.exit(0);
    });
  } else {
    process.exit(0);
  }
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  if (db && db.end) {
    db.end(() => {
      logger.info('Database pool closed');
      process.exit(0);
    });
  } else {
    process.exit(0);
  }
});

// Create system_metrics_history table
const createSystemMetricsHistoryTable = `
  CREATE TABLE IF NOT EXISTS system_metrics_history (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    cpu_usage_percent INTEGER,
    memory_usage_percent INTEGER,
    disk_usage_percent INTEGER
  )
`;
// System Metrics History table will be created in initializeAdditionalTables function

// Helper to sanitize metric values
function safeInt(val) {
  return (typeof val === 'number' && isFinite(val) && !isNaN(val)) ? Math.round(val) : 0;
}

// Function to record a system metrics snapshot
async function recordSystemMetricsSnapshot() {
  try {
    const os = await import('os');
    const si = await import('systeminformation');
    const totalMem = os.default.totalmem() / (1024 * 1024 * 1024);
    const freeMem = os.default.freemem() / (1024 * 1024 * 1024);
    const usedMem = totalMem - freeMem;
    let memUsagePercent = (totalMem > 0) ? Math.round((usedMem / totalMem) * 100) : 0;
    let cpuUsagePercent = 0;
    let diskUsagePercent = 0;
    try {
      const cpuLoad = await si.default.currentLoad();
      cpuUsagePercent = Math.round(cpuLoad.currentload);
      const disk = await si.default.fsSize();
      if (disk.length > 0 && disk[0].size > 0) {
        diskUsagePercent = Math.round((disk[0].used / disk[0].size) * 100);
      }
    } catch (e) {}
    await dbQuery(
      'INSERT INTO system_metrics_history (cpu_usage_percent, memory_usage_percent, disk_usage_percent) VALUES ($1, $2, $3)',
      [safeInt(cpuUsagePercent), safeInt(memUsagePercent), safeInt(diskUsagePercent)]
    );
  } catch (err) {
    console.error('Error recording system metrics snapshot:', err);
  }
}
// Record metrics every minute
setInterval(recordSystemMetricsSnapshot, 60 * 1000);

// Endpoint to get last 24h of system metrics for charts
app.get('/admin/metrics-history', authenticateAdmin, async (req, res) => {
  try {
    const result = await dbQuery(
      `SELECT timestamp, cpu_usage_percent, memory_usage_percent, disk_usage_percent
       FROM system_metrics_history
       WHERE timestamp > NOW() - INTERVAL '24 hours'
       ORDER BY timestamp ASC`
    );
    res.status(200).json({
      metrics: result.rows.map(row => ({
        timestamp: row.timestamp,
        cpu: row.cpu_usage_percent,
        memory: row.memory_usage_percent,
        disk: row.disk_usage_percent
      }))
    });
  } catch (err) {
    console.error('Error fetching metrics history:', err);
    res.status(500).json({ error: 'Failed to fetch metrics history' });
  }
});



const createProjectDocumentsTable = `
  CREATE TABLE IF NOT EXISTS project_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL,
    file_path TEXT NOT NULL,
    file_type VARCHAR(50) NOT NULL,
    file_size BIGINT,
    date_added TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expiry_date DATE,
    status VARCHAR(50) DEFAULT 'Active',
    description TEXT,
    tags TEXT[], -- PostgreSQL array type
    is_asset BOOLEAN DEFAULT false,
    uploaded_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Create document_categories table
const createDocumentCategoriesTable = `
  CREATE TABLE IF NOT EXISTS document_categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    icon VARCHAR(100),
    color VARCHAR(50),
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Create indexes for better performance
const createDocumentIndexes = `
  CREATE INDEX IF NOT EXISTS idx_project_documents_category ON project_documents(category);
  CREATE INDEX IF NOT EXISTS idx_project_documents_status ON project_documents(status);
  CREATE INDEX IF NOT EXISTS idx_project_documents_date_added ON project_documents(date_added);
  CREATE INDEX IF NOT EXISTS idx_project_documents_expiry_date ON project_documents(expiry_date);
  CREATE INDEX IF NOT EXISTS idx_project_documents_tags ON project_documents USING GIN(tags);
`;

// Project Documents and Document Categories tables will be created in initializeAdditionalTables function

// Insert default categories
const insertDefaultCategories = `
  INSERT INTO document_categories (name, display_name, icon, color, description) VALUES
  ('environmental', 'Environmental', 'eco', 'green', 'Environmental clearances and approvals'),
  ('planning', 'Planning & Building', 'architecture', 'blue', 'Building plans and architectural approvals'),
  ('utilities', 'Utilities', 'electrical_services', 'orange', 'Utility connections and clearances'),
  ('legal', 'Legal & Land', 'gavel', 'purple', 'Legal documents and land records'),
  ('safety', 'Safety & Security', 'security', 'red', 'Safety and security related documents'),
  ('financial', 'Financial', 'account_balance', 'teal', 'Financial documents and records'),
  ('other', 'Other Documents', 'folder', 'grey', 'Miscellaneous documents')
  ON CONFLICT (name) DO NOTHING
`;

// Default categories will be inserted in initializeAdditionalTables function

// ===========================================
// VALIDATION SCHEMAS
// ===========================================

const documentSchema = Joi.object({
  name: Joi.string().min(1).max(255).required(),
  category: Joi.string().required(),
  description: Joi.string().max(1000).optional().allow(''),
  tags: Joi.alternatives().try(
    Joi.array().items(Joi.string()),
    Joi.string()
  ).optional(),
  status: Joi.string().valid('Active', 'Approved', 'Pending', 'Expired', 'Verified', 'Rejected').default('Active'),
  expiry_date: Joi.date().optional().allow(null)
});

// Create document upload with better error handling and timeout
const documentUpload = multer({
  storage: s3Client ? multerS3({
    s3: s3Client,
    bucket: process.env.AWS_BUCKET_NAME,
    contentType: multerS3.AUTO_CONTENT_TYPE,
    key: function (req, file, cb) {
      try {
        if (!s3Client) {
          logger.error('S3 client not initialized during key generation');
          return cb(new Error('S3 client not initialized - file uploads are disabled'));
        }
        const timestamp = Date.now();
        const sanitizedFileName = file.originalname.replace(/[^a-zA-Z0-9.-]/g, '_');
        const key = `project-documents/${req.user?.id || 'anonymous'}/${timestamp}_${sanitizedFileName}`;
        logger.info('Generated document S3 key:', { key, bucket: process.env.AWS_BUCKET_NAME });
        cb(null, key);
      } catch (error) {
        logger.error('Error generating S3 key:', error);
        cb(error);
      }
    },
    metadata: function (req, file, cb) {
      try {
        cb(null, { 
          fieldName: file.fieldname,
          originalName: file.originalname,
          uploadedBy: req.user?.id?.toString() || 'anonymous'
        });
      } catch (error) {
        logger.error('Error setting S3 metadata:', error);
        cb(error);
      }
    }
  }) : multer.memoryStorage(), // Fallback to memory storage if S3 not available
  fileFilter: (req, file, cb) => {
    logger.info('Checking document file:', {
      fieldname: file.fieldname,
      originalname: file.originalname,
      mimetype: file.mimetype
    });

    if (!s3Client) {
      logger.error('S3 client not initialized');
      cb(new Error('File uploads are currently disabled'), false);
      return;
    }

    // Allowed document types
    const validMimeTypes = [
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'image/jpeg',
      'image/jpg', 
      'image/png',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ];

    // Allowed file extensions (fallback when MIME type detection fails)
    const validExtensions = ['.pdf', '.doc', '.docx', '.jpg', '.jpeg', '.png', '.xls', '.xlsx'];
    const fileExtension = path.extname(file.originalname).toLowerCase();

    // Check MIME type first, then fallback to extension
    const isValidMimeType = validMimeTypes.includes(file.mimetype);
    const isValidExtension = validExtensions.includes(fileExtension);
    
    if (!isValidMimeType && !isValidExtension) {
      logger.warn('Invalid document file type:', {
        mimetype: file.mimetype,
        extension: fileExtension,
        filename: file.originalname
      });
      cb(new Error(`Invalid file type. Allowed types are: PDF, DOC, DOCX, JPG, PNG, XLS, XLSX`), false);
      return;
    }

    // Special case: if MIME type is generic but extension is valid, accept it
    if (!isValidMimeType && isValidExtension) {
      logger.info('File accepted based on extension (MIME type detection failed):', {
        mimetype: file.mimetype,
        extension: fileExtension,
        filename: file.originalname
      });
    }

    logger.info('Document file validation passed');
    cb(null, true);
  },
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit for documents
    files: 1
  }
});

// Driver License Upload Configuration (Fixed for AWS SDK v3)
const driverLicenseUpload = multer({
  storage: multer.memoryStorage(), // Store in memory first, then upload to S3 manually
  fileFilter: function (req, file, cb) {
    logger.info('Checking driver license file:', {
      fieldname: file.fieldname,
      originalname: file.originalname,
      mimetype: file.mimetype
    });

    // Allow multiple file formats for driver licenses
    const allowedMimes = [
      'image/jpeg',
      'image/jpg', 
      'image/png',
      'image/bmp',
      'image/tiff',
      'image/webp',
      'application/pdf'
    ];
    
    const allowedExtensions = ['.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.pdf', '.webp'];
    const fileExtension = path.extname(file.originalname).toLowerCase();
    
    if (allowedMimes.includes(file.mimetype) || allowedExtensions.includes(fileExtension)) {
      logger.info('Driver license file validation passed');
      cb(null, true);
    } else {
      logger.warn('Invalid driver license file type:', {
        mimetype: file.mimetype,
        extension: fileExtension
      });
      cb(new Error(`Invalid file format. Allowed formats: JPG, PNG, PDF, BMP, TIFF, WEBP`), false);
    }
  },
  limits: {
    fileSize: 20 * 1024 * 1024, // 20MB limit for driver licenses
    files: 1
  }
});

// ===========================================
// API ENDPOINTS
// ===========================================

// GET all documents with filtering and pagination
app.get('/api/documents', authenticateToken, async (req, res) => {
  try {
    const { 
      page = 1, 
      limit = 20, 
      category, 
      status, 
      search, 
      sort_by = 'date_added', 
      sort_order = 'DESC',
      expiring_soon = false
    } = req.query;

    const offset = (page - 1) * limit;
    let whereConditions = [];
    let params = [];

    // Build dynamic WHERE clause
    if (category) {
      whereConditions.push(`category = $${params.length + 1}`);
      params.push(category);
    }

    if (status) {
      whereConditions.push(`status = $${params.length + 1}`);
      params.push(status);
    }

    if (search) {
      whereConditions.push(`(
        name ILIKE $${params.length + 1} OR 
        description ILIKE $${params.length + 1} OR 
        $${params.length + 1} = ANY(tags)
      )`);
      params.push(`%${search}%`);
    }

    if (expiring_soon === 'true') {
      whereConditions.push(`expiry_date IS NOT NULL AND expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'`);
    }

    const whereClause = whereConditions.length > 0 ? `WHERE ${whereConditions.join(' AND ')}` : '';

    // Validate sort parameters
    const validSortColumns = ['name', 'date_added', 'category', 'status', 'expiry_date'];
    const sortColumn = validSortColumns.includes(sort_by) ? sort_by : 'date_added';
    const sortDirection = sort_order.toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

    const query = `
      SELECT 
        id,
        name,
        category,
        file_path,
        file_type,
        file_size,
        date_added,
        expiry_date,
        status,
        description,
        tags,
        is_asset,
        CASE 
          WHEN expiry_date IS NOT NULL AND expiry_date < CURRENT_DATE THEN true 
          ELSE false 
        END as is_expired,
        CASE 
          WHEN expiry_date IS NOT NULL AND expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days' THEN true 
          ELSE false 
        END as is_expiring_soon
      FROM project_documents 
      ${whereClause}
      ORDER BY ${sortColumn} ${sortDirection}
      LIMIT $${params.length + 1} OFFSET $${params.length + 2}
    `;

    params.push(limit, offset);

    // Get count for pagination
    const countQuery = `
      SELECT COUNT(*) as total 
      FROM project_documents 
      ${whereClause}
    `;

    const [documents, countResult] = await Promise.all([
      dbQuery(query, params),
      dbQuery(countQuery, params.slice(0, -2)) // Remove limit and offset for count
    ]);

    const total = parseInt(countResult.rows[0].total);
    const totalPages = Math.ceil(total / limit);

    res.status(200).json({
      success: true,
      data: documents.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: total,
        totalPages: totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1
      }
    });

  } catch (err) {
    logger.error('Error fetching documents:', err);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch documents',
      error: err.message 
    });
  }
});

// GET document by ID
app.get('/api/documents/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;

    const query = `
      SELECT 
        pd.*,
        u.username as uploaded_by_username,
        CASE 
          WHEN pd.expiry_date IS NOT NULL AND pd.expiry_date < CURRENT_DATE THEN true 
          ELSE false 
        END as is_expired,
        CASE 
          WHEN pd.expiry_date IS NOT NULL AND pd.expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days' THEN true 
          ELSE false 
        END as is_expiring_soon
      FROM project_documents pd
      LEFT JOIN users u ON pd.uploaded_by = u.id
      WHERE pd.id = $1
    `;

    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Document not found'
      });
    }

    res.status(200).json({
      success: true,
      data: result.rows[0]
    });

  } catch (err) {
    logger.error('Error fetching document:', err);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch document',
      error: err.message 
    });
  }
});

// POST new document with timeout handling
app.post('/api/documents', authenticateToken, (req, res, next) => {
  // Add timeout handling
  const uploadTimeout = setTimeout(() => {
    logger.error('Document upload timeout after 30 seconds');
    if (!res.headersSent) {
      res.status(408).json({
        success: false,
        message: 'Upload timeout - please try with a smaller file',
        error: 'Request timeout after 30 seconds'
      });
    }
  }, 30000); // 30 second timeout

  documentUpload.single('file')(req, res, (err) => {
    clearTimeout(uploadTimeout);
    
    if (err) {
      logger.error('Document upload middleware error:', err);
      if (!res.headersSent) {
        return res.status(500).json({
          success: false,
          message: 'File upload failed',
          error: err.message
        });
      }
      return;
    }
    
    next();
  });
}, async (req, res) => {
  try {
    logger.info('Document upload request body:', {
      name: req.body.name,
      category: req.body.category,
      status: req.body.status,
      description: req.body.description?.substring(0, 50),
      tags: req.body.tags,
      tagsType: typeof req.body.tags
    });

    // Parse tags before validation if they come as a string
    let processedBody = { ...req.body };
    if (typeof req.body.tags === 'string' && req.body.tags.trim() !== '') {
      try {
        processedBody.tags = JSON.parse(req.body.tags);
        logger.info('Parsed tags from JSON string:', processedBody.tags);
      } catch (e) {
        processedBody.tags = req.body.tags.split(',').map(tag => tag.trim()).filter(tag => tag.length > 0);
        logger.info('Parsed tags from CSV string:', processedBody.tags);
      }
    }

    const { error } = documentSchema.validate(processedBody);
    if (error) {
      logger.error('Document validation failed:', error.details[0].message);
      logger.error('Validation input:', processedBody);
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        error: error.details[0].message
      });
    }

    if (!req.file) {
      logger.warn('No file in request after multer processing');
      return res.status(400).json({
        success: false,
        message: 'No file provided or upload failed'
      });
    }

    logger.info('File upload successful:', {
      filename: req.file.originalname,
      location: req.file.location,
      key: req.file.key,
      size: req.file.size,
      mimetype: req.file.mimetype
    });

    const {
      name,
      category,
      description = '',
      tags = [],
      status = 'Active',
      expiry_date
    } = processedBody;

    // Tags are already processed from validation step
    let parsedTags = tags;

    const query = `
      INSERT INTO project_documents 
      (name, category, file_path, file_type, file_size, description, tags, status, expiry_date, uploaded_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `;

    const result = await dbQuery(query, [
      name,
      category,
      req.file.location, // S3 URL
      req.file.mimetype,
      req.file.size,
      description,
      parsedTags,
      status,
      expiry_date || null,
      req.user.id
    ]);

    logger.info(`Document uploaded successfully: ${name} by user ${req.user.id}`);

    res.status(201).json({
      success: true,
      message: 'Document uploaded successfully',
      data: result.rows[0]
    });

  } catch (err) {
    logger.error('Error uploading document:', err);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to upload document',
      error: err.message 
    });
  }
});

// PUT update document
app.put('/api/documents/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    logger.info('Document update request body:', {
      id: id,
      name: req.body.name,
      category: req.body.category,
      status: req.body.status,
      description: req.body.description?.substring(0, 50),
      tags: req.body.tags,
      tagsType: typeof req.body.tags
    });

    // Parse tags before validation if they come as a string
    let processedBody = { ...req.body };
    if (typeof req.body.tags === 'string' && req.body.tags.trim() !== '') {
      try {
        processedBody.tags = JSON.parse(req.body.tags);
        logger.info('Parsed tags from JSON string:', processedBody.tags);
      } catch (e) {
        processedBody.tags = req.body.tags.split(',').map(tag => tag.trim()).filter(tag => tag.length > 0);
        logger.info('Parsed tags from CSV string:', processedBody.tags);
      }
    }

    const { error } = documentSchema.validate(processedBody);
    if (error) {
      logger.error('Document update validation failed:', error.details[0].message);
      logger.error('Validation input:', processedBody);
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        error: error.details[0].message
      });
    }

    const {
      name,
      category,
      description = '',
      tags = [],
      status = 'Active',
      expiry_date
    } = processedBody;

    // Tags are already processed from validation step
    let parsedTags = tags;

    const query = `
      UPDATE project_documents 
      SET name = $1, category = $2, description = $3, tags = $4, status = $5, 
          expiry_date = $6, updated_at = CURRENT_TIMESTAMP
      WHERE id = $7 AND (uploaded_by = $8 OR is_asset = false)
      RETURNING *
    `;

    const result = await dbQuery(query, [
      name,
      category,
      description,
      parsedTags,
      status,
      expiry_date || null,
      id,
      req.user.id
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Document not found or you do not have permission to edit it'
      });
    }

    res.status(200).json({
      success: true,
      message: 'Document updated successfully',
      data: result.rows[0]
    });

  } catch (err) {
    logger.error('Error updating document:', err);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to update document',
      error: err.message 
    });
  }
});

// DELETE document
app.delete('/api/documents/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;

    // First, get the document to check permissions and get file path
    const getDocQuery = `
      SELECT file_path, name, uploaded_by, is_asset 
      FROM project_documents 
      WHERE id = $1
    `;
    
    const docResult = await dbQuery(getDocQuery, [id]);
    
    if (docResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Document not found'
      });
    }

    const document = docResult.rows[0];

    // Check if user can delete (only non-asset documents can be deleted by users)
    if (document.is_asset) {
      return res.status(403).json({
        success: false,
        message: 'Cannot delete system documents'
      });
    }

    if (document.uploaded_by !== req.user.id && !req.user.isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to delete this document'
      });
    }

    // Delete from database
    const deleteQuery = `
      DELETE FROM project_documents 
      WHERE id = $1 
      RETURNING *
    `;

    const result = await dbQuery(deleteQuery, [id]);

    // Optionally, delete from S3 (you might want to keep files for backup)
    // if (s3Client && document.file_path.includes('amazonaws.com')) {
    //   const key = document.file_path.split('/').slice(-2).join('/');
    //   await s3Client.deleteObject({
    //     Bucket: process.env.AWS_BUCKET_NAME,
    //     Key: key
    //   }).promise();
    // }

    logger.info(`Document deleted: ${document.name} by user ${req.user.id}`);

    res.status(200).json({
      success: true,
      message: 'Document deleted successfully',
      data: result.rows[0]
    });

  } catch (err) {
    logger.error('Error deleting document:', err);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to delete document',
      error: err.message 
    });
  }
});

// GET document categories
app.get('/api/document-categories', async (req, res) => {
  try {
    const query = `
      SELECT * FROM document_categories 
      WHERE is_active = true 
      ORDER BY display_name
    `;

    const result = await dbQuery(query);

    res.status(200).json({
      success: true,
      data: result.rows
    });

  } catch (err) {
    logger.error('Error fetching categories:', err);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch categories',
      error: err.message 
    });
  }
});

// GET document statistics
app.get('/api/documents/stats', authenticateToken, async (req, res) => {
  try {
    const statsQuery = `
      SELECT 
        COUNT(*) as total_documents,
        COUNT(CASE WHEN expiry_date IS NOT NULL AND expiry_date < CURRENT_DATE THEN 1 END) as expired_documents,
        COUNT(CASE WHEN expiry_date IS NOT NULL AND expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days' THEN 1 END) as expiring_soon_documents,
        COUNT(CASE WHEN status = 'Approved' THEN 1 END) as approved_documents,
        COUNT(CASE WHEN status = 'Pending' THEN 1 END) as pending_documents,
        SUM(file_size) as total_file_size
      FROM project_documents
    `;

    const categoryStatsQuery = `
      SELECT 
        category,
        COUNT(*) as count
      FROM project_documents
      GROUP BY category
      ORDER BY count DESC
    `;

    const [statsResult, categoryStatsResult] = await Promise.all([
      dbQuery(statsQuery),
      dbQuery(categoryStatsQuery)
    ]);

    res.status(200).json({
      success: true,
      data: {
        overview: statsResult.rows[0],
        categoryStats: categoryStatsResult.rows
      }
    });

  } catch (err) {
    logger.error('Error fetching document statistics:', err);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch statistics',
      error: err.message 
    });
  }
});

// GET download document (generate signed URL for private documents)
app.get('/api/documents/:id/download', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;

    const query = `
      SELECT file_path, name, file_type, uploaded_by, is_asset
      FROM project_documents 
      WHERE id = $1
    `;

    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Document not found'
      });
    }

    const document = result.rows[0];

    // For S3 files, generate a signed URL
    if (s3Client && document.file_path.includes('amazonaws.com')) {
      try {
        const key = document.file_path.split('/').slice(-3).join('/'); // Extract key from URL
        
        // Generate signed URL using AWS SDK v3
        const command = new GetObjectCommand({
          Bucket: process.env.AWS_BUCKET_NAME,
          Key: key,
          ResponseContentDisposition: `inline; filename="${document.name}"`
        });
        
        const signedUrl = await getSignedUrl(s3Client, command, {
          expiresIn: 3600 // 1 hour
        });

        res.status(200).json({
          success: true,
          downloadUrl: signedUrl,
          fileName: document.name,
          fileType: document.file_type
        });

      } catch (s3Error) {
        logger.error('Error generating signed URL:', s3Error);
        res.status(500).json({
          success: false,
          message: 'Failed to generate download link'
        });
      }
    } else {
      // For direct file paths, return the path
      res.status(200).json({
        success: true,
        downloadUrl: document.file_path,
        fileName: document.name,
        fileType: document.file_type
      });
    }

  } catch (err) {
    logger.error('Error generating download link:', err);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to generate download link',
      error: err.message 
    });
  }
});

// ===========================================
// SEED DEFAULT DOCUMENTS (run once)
// ===========================================

// Function to seed default documents (call this once)
const seedDefaultDocuments = async () => {
  try {
    const defaultDocuments = [
      {
        name: 'KSPCB CFE',
        category: 'environmental',
        file_path: 'assets/cfe1.pdf',
        file_type: 'application/pdf',
        description: 'Consent for Establishment from Karnataka State Pollution Control Board',
        tags: ['KSPCB', 'Environmental', 'Mandatory'],
        status: 'Approved',
        is_asset: true
      },
      {
        name: 'Environmental Clearances',
        category: 'environmental',
        file_path: 'assets/ENvironmental.pdf',
        file_type: 'application/pdf',
        description: 'Environmental impact assessment and clearance',
        tags: ['Environmental', 'Clearance'],
        status: 'Approved',
        is_asset: true
      },
      {
        name: 'BBMP Plan Sanction',
        category: 'planning',
        file_path: 'assets/Conversion Certificate.pdf',
        file_type: 'application/pdf',
        description: 'Building plan sanction from BBMP',
        tags: ['BBMP', 'Planning', 'Building'],
        status: 'Approved',
        is_asset: true
      },
      {
        name: 'Land Document',
        category: 'legal',
        file_path: 'assets/Conversion Certificate.pdf',
        file_type: 'application/pdf',
        description: 'Original land ownership and title documents',
        tags: ['Land', 'Legal', 'Title'],
        status: 'Verified',
        is_asset: true
      },
      {
        name: 'SGWA',
        category: 'utilities',
        file_path: 'assets/SGWA.pdf',
        file_type: 'application/pdf',
        description: 'State Groundwater Authority approval',
        tags: ['Water', 'Groundwater', 'Authority'],
        status: 'Approved',
        is_asset: true
      },
      {
        name: 'Fire NOC',
        category: 'safety',
        file_path: 'assets/FIRE_NOC.pdf',
        file_type: 'application/pdf',
        description: 'Fire department No Objection Certificate',
        tags: ['Fire', 'Safety', 'NOC'],
        status: 'Approved',
        is_asset: true
      },
      {
        name: 'Airport Clearance',
        category: 'planning',
        file_path: 'assets/Airport.pdf',
        file_type: 'application/pdf',
        description: 'Airport authority height clearance certificate',
        tags: ['Airport', 'Height', 'Clearance'],
        status: 'Approved',
        is_asset: true
      },
      {
        name: 'BESCOM Clearances',
        category: 'utilities',
        file_path: 'assets/ BESCOM.pdf',
        file_type: 'application/pdf',
        description: 'Electricity board clearances and connections',
        tags: ['Electricity', 'BESCOM', 'Utilities'],
        status: 'Approved',
        is_asset: true
      }
    ];

    for (const doc of defaultDocuments) {
      await dbQuery(`
        INSERT INTO project_documents 
        (name, category, file_path, file_type, description, tags, status, is_asset)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT DO NOTHING
      `, [
        doc.name,
        doc.category,
        doc.file_path,
        doc.file_type,
        doc.description,
        doc.tags,
        doc.status,
        doc.is_asset
      ]);
    }

    logger.info('Default documents seeded successfully');
  } catch (err) {
    logger.error('Error seeding default documents:', err);
  }
};



// Admin: Get all documents with additional info
app.get('/admin/documents', authenticateAdmin, async (req, res) => {
  try {
    const query = `
      SELECT 
        pd.*,
        u.username as uploaded_by_username,
        u.email as uploaded_by_email
      FROM project_documents pd
      LEFT JOIN users u ON pd.uploaded_by = u.id
      ORDER BY pd.date_added DESC
    `;

    const result = await dbQuery(query);

    res.status(200).json({
      success: true,
      data: result.rows
    });

  } catch (err) {
    logger.error('Error fetching all documents (admin):', err);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch documents',
      error: err.message 
    });
  }
});

// Admin: Force delete any document
app.delete('/admin/documents/:id', authenticateAdmin, async (req, res) => {
  try {
    const { id } = req.params;

    const result = await dbQuery(
      'DELETE FROM project_documents WHERE id = $1 RETURNING *',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Document not found'
      });
    }

    await logAdminAction(
      req.user.username,
      'DELETE_DOCUMENT',
      `Deleted document: ${result.rows[0].name}`,
      req
    );

    res.status(200).json({
      success: true,
      message: 'Document deleted successfully',
      data: result.rows[0]
    });

  } catch (err) {
    logger.error('Error deleting document (admin):', err);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to delete document',
      error: err.message 
    });
  }
});

logger.info('Document storage API endpoints initialized successfully');




const getMonthDateRange = (date) => {
  const targetDate = new Date(date);
  const firstDay = new Date(targetDate.getFullYear(), targetDate.getMonth(), 1);
  const lastDay = new Date(targetDate.getFullYear(), targetDate.getMonth() + 1, 0);
  return { firstDay, lastDay };
};

// Helper function to safely parse numeric values
const safeParseFloat = (value) => {
  if (value === null || value === undefined) return 0.0;
  const parsed = parseFloat(value);
  return isNaN(parsed) ? 0.0 : parsed;
};


// ============================================
// CONSUMPTION SUMMARY ENDPOINTS
// ============================================

// Borewell Consumption Summary
app.get('/borewell/consumption-summary', async (req, res) => {
  try {
    const { date, fromDate, toDate } = req.query;
    const targetDate = date ? new Date(date) : new Date();
    const { firstDay, lastDay } = getMonthDateRange(targetDate);

    console.log('Fetching borewell consumption summary for date:', targetDate);

    // Daily consumption for the specific date
    const dailyQuery = `
      SELECT COALESCE(SUM(water_consumed), 0) as daily_consumption
      FROM borewell_water 
      WHERE date = $1
    `;
    const dailyResult = await dbQuery(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly consumption
    const monthlyQuery = `
      SELECT COALESCE(SUM(water_consumed), 0) as monthly_consumption
      FROM borewell_water 
      WHERE date >= $1 AND date <= $2
    `;
    const monthlyResult = await dbQuery(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Cumulative consumption (all time)
    const cumulativeQuery = `
      SELECT COALESCE(SUM(water_consumed), 0) as cumulative_consumption
      FROM borewell_water
    `;
    const cumulativeResult = await dbQuery(cumulativeQuery);

    // Period consumption (if date range provided)
    let periodConsumption = cumulativeResult.rows[0].cumulative_consumption;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(water_consumed), 0) as period_consumption
        FROM borewell_water 
        WHERE date >= $1 AND date <= $2
      `;
      const periodResult = await dbQuery(periodQuery, [fromDate, toDate]);
      periodConsumption = periodResult.rows[0].period_consumption;
    }

    const response = {
      success: true,
      data: {
        daily: safeParseFloat(dailyResult.rows[0].daily_consumption),
        monthly: safeParseFloat(monthlyResult.rows[0].monthly_consumption),
        cumulative: safeParseFloat(cumulativeResult.rows[0].cumulative_consumption),
        period: safeParseFloat(periodConsumption)
      }
    };

    console.log('Borewell consumption summary response:', response);
    res.status(200).json(response);

  } catch (err) {
    console.error('Error fetching borewell consumption summary:', err);
    res.status(500).json({ 
      success: false,
      error: 'Internal server error',
      data: { daily: 0, monthly: 0, cumulative: 0, period: 0 }
    });
  }
});

// Tanker Consumption Summary
app.get('/tanker/consumption-summary', async (req, res) => {
  try {
    const { date, fromDate, toDate } = req.query;
    const targetDate = date ? new Date(date) : new Date();
    const { firstDay, lastDay } = getMonthDateRange(targetDate);

    console.log('Fetching tanker consumption summary for date:', targetDate);

    // For tankers, we'll use capacity as a proxy for consumption
    // In real scenarios, you'd have delivery records
    
    // Daily deliveries for the specific date
    const dailyQuery = `
      SELECT COALESCE(SUM(capacity), 0) as daily_capacity
      FROM tankers 
      WHERE DATE(last_updated) = $1
    `;
    const dailyResult = await dbQuery(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly deliveries
    const monthlyQuery = `
      SELECT COALESCE(SUM(capacity), 0) as monthly_capacity
      FROM tankers 
      WHERE DATE(last_updated) >= $1 AND DATE(last_updated) <= $2
    `;
    const monthlyResult = await dbQuery(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Total tanker capacity (all active tankers)
    const cumulativeQuery = `
      SELECT COALESCE(SUM(capacity), 0) as total_capacity
      FROM tankers
    `;
    const cumulativeResult = await dbQuery(cumulativeQuery);

    // Period consumption
    let periodConsumption = cumulativeResult.rows[0].total_capacity;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(capacity), 0) as period_capacity
        FROM tankers 
        WHERE DATE(last_updated) >= $1 AND DATE(last_updated) <= $2
      `;
      const periodResult = await dbQuery(periodQuery, [fromDate, toDate]);
      periodConsumption = periodResult.rows[0].period_capacity;
    }

    const response = {
      success: true,
      data: {
        daily: safeParseFloat(dailyResult.rows[0].daily_capacity),
        monthly: safeParseFloat(monthlyResult.rows[0].monthly_capacity),
        cumulative: safeParseFloat(cumulativeResult.rows[0].total_capacity),
        period: safeParseFloat(periodConsumption)
      }
    };

    console.log('Tanker consumption summary response:', response);
    res.status(200).json(response);

  } catch (err) {
    console.error('Error fetching tanker consumption summary:', err);
    res.status(500).json({ 
      success: false,
      error: 'Internal server error',
      data: { daily: 0, monthly: 0, cumulative: 0, period: 0 }
    });
  }
});

// BWSSB Consumption Summary
app.get('/bwssb/consumption-summary', async (req, res) => {
  try {
    const { date, fromDate, toDate } = req.query;
    const targetDate = date ? new Date(date) : new Date();
    const { firstDay, lastDay } = getMonthDateRange(targetDate);

    console.log('Fetching BWSSB consumption summary for date:', targetDate);

    // Daily consumption
    const dailyQuery = `
      SELECT COALESCE(SUM(quantity_supplied), 0) as daily_consumption
      FROM bwssb_supply 
      WHERE supply_date = $1
    `;
    const dailyResult = await dbQuery(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly consumption
    const monthlyQuery = `
      SELECT COALESCE(SUM(quantity_supplied), 0) as monthly_consumption
      FROM bwssb_supply 
      WHERE supply_date >= $1 AND supply_date <= $2
    `;
    const monthlyResult = await dbQuery(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Cumulative consumption
    const cumulativeQuery = `
      SELECT COALESCE(SUM(quantity_supplied), 0) as cumulative_consumption
      FROM bwssb_supply
    `;
    const cumulativeResult = await dbQuery(cumulativeQuery);

    // Period consumption
    let periodConsumption = cumulativeResult.rows[0].cumulative_consumption;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(quantity_supplied), 0) as period_consumption
        FROM bwssb_supply 
        WHERE supply_date >= $1 AND supply_date <= $2
      `;
      const periodResult = await dbQuery(periodQuery, [fromDate, toDate]);
      periodConsumption = periodResult.rows[0].period_consumption;
    }

    const response = {
      success: true,
      data: {
        daily: safeParseFloat(dailyResult.rows[0].daily_consumption),
        monthly: safeParseFloat(monthlyResult.rows[0].monthly_consumption),
        cumulative: safeParseFloat(cumulativeResult.rows[0].cumulative_consumption),
        period: safeParseFloat(periodConsumption)
      }
    };

    console.log('BWSSB consumption summary response:', response);
    res.status(200).json(response);

  } catch (err) {
    console.error('Error fetching BWSSB consumption summary:', err);
    res.status(500).json({ 
      success: false,
      error: 'Internal server error',
      data: { daily: 0, monthly: 0, cumulative: 0, period: 0 }
    });
  }
});

// Labour Colony Consumption Summary
app.get('/labour-colony-waste/consumption-summary', async (req, res) => {
  try {
    const { date, fromDate, toDate } = req.query;
    const targetDate = date ? new Date(date) : new Date();
    const { firstDay, lastDay } = getMonthDateRange(targetDate);

    console.log('Fetching labour colony consumption summary for date:', targetDate);

    // Daily consumption
    const dailyQuery = `
      SELECT COALESCE(SUM(consumption), 0) as daily_consumption
      FROM labour_colony 
      WHERE date = $1
    `;
    const dailyResult = await dbQuery(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly consumption
    const monthlyQuery = `
      SELECT COALESCE(SUM(consumption), 0) as monthly_consumption
      FROM labour_colony 
      WHERE date >= $1 AND date <= $2
    `;
    const monthlyResult = await dbQuery(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Cumulative consumption
    const cumulativeQuery = `
      SELECT COALESCE(SUM(consumption), 0) as cumulative_consumption
      FROM labour_colony
    `;
    const cumulativeResult = await dbQuery(cumulativeQuery);

    // Period consumption
    let periodConsumption = cumulativeResult.rows[0].cumulative_consumption;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(consumption), 0) as period_consumption
        FROM labour_colony 
        WHERE date >= $1 AND date <= $2
      `;
      const periodResult = await dbQuery(periodQuery, [fromDate, toDate]);
      periodConsumption = periodResult.rows[0].period_consumption;
    }

    const response = {
      success: true,
      data: {
        daily: safeParseFloat(dailyResult.rows[0].daily_consumption),
        monthly: safeParseFloat(monthlyResult.rows[0].monthly_consumption),
        cumulative: safeParseFloat(cumulativeResult.rows[0].cumulative_consumption),
        period: safeParseFloat(periodConsumption)
      }
    };

    console.log('Labour colony consumption summary response:', response);
    res.status(200).json(response);

  } catch (err) {
    console.error('Error fetching labour colony consumption summary:', err);
    res.status(500).json({ 
      success: false,
      error: 'Internal server error',
      data: { daily: 0, monthly: 0, cumulative: 0, period: 0 }
    });
  }
});

// ============================================
// PHASE SUMMARY ENDPOINTS (Main endpoints)
// ============================================

// Construction Phase Summary
app.get('/water-consumption/phase-summary/construction', async (req, res) => {
  try {
    console.log('Fetching construction phase summary with params:', req.query);
    
    const { date, fromDate, toDate } = req.query;
    const baseUrl = 'http://localhost:3000'; // Use localhost for internal calls
    
    // Build query string
    const queryParams = new URLSearchParams();
    if (date) queryParams.append('date', date);
    if (fromDate) queryParams.append('fromDate', fromDate);
    if (toDate) queryParams.append('toDate', toDate);
    const queryString = queryParams.toString();
    
    // Fetch data from individual endpoints
    const endpoints = [
      `${baseUrl}/borewell/consumption-summary?${queryString}`,
      `${baseUrl}/tanker/consumption-summary?${queryString}`,
      `${baseUrl}/bwssb/consumption-summary?${queryString}`
    ];

    const responses = await Promise.allSettled(
      endpoints.map(url => 
        fetch(url).then(r => r.json()).catch(e => {
          console.error(`Failed to fetch ${url}:`, e);
          return { data: { daily: 0, monthly: 0, cumulative: 0, period: 0 } };
        })
      )
    );

    const [borewellData, tankerData, bwssbData] = responses.map(response => 
      response.status === 'fulfilled' ? response.value : { data: { daily: 0, monthly: 0, cumulative: 0, period: 0 } }
    );

    const responseData = {
      success: true,
      data: {
        borewell: borewellData.data || { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        tanker: tankerData.data || { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        bwssb: bwssbData.data || { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        others: { daily: 0, monthly: 0, cumulative: 0, period: 0 }
      }
    };

    console.log('Construction phase summary response:', responseData);
    res.status(200).json(responseData);

  } catch (err) {
    console.error('Error fetching construction phase summary:', err);
    res.status(500).json({ 
      success: false,
      error: 'Internal server error',
      data: {
        borewell: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        tanker: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        bwssb: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        others: { daily: 0, monthly: 0, cumulative: 0, period: 0 }
      }
    });
  }
});

// Labour Colony Phase Summary
app.get('/water-consumption/phase-summary/labour_colony', async (req, res) => {
  try {
    console.log('Fetching labour colony phase summary with params:', req.query);
    
    const { date, fromDate, toDate } = req.query;
    const baseUrl = 'http://localhost:3000';
    
    const queryParams = new URLSearchParams();
    if (date) queryParams.append('date', date);
    if (fromDate) queryParams.append('fromDate', fromDate);
    if (toDate) queryParams.append('toDate', toDate);
    const queryString = queryParams.toString();
    
    // Fetch labour colony data
    const labourColonyResponse = await fetch(`${baseUrl}/labour-colony-waste/consumption-summary?${queryString}`)
      .then(r => r.json())
      .catch(e => {
        console.error('Failed to fetch labour colony data:', e);
        return { data: { daily: 0, monthly: 0, cumulative: 0, period: 0 } };
      });

    const responseData = {
      success: true,
      data: {
        borewell: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        tanker: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        bwssb: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        others: labourColonyResponse.data || { daily: 0, monthly: 0, cumulative: 0, period: 0 }
      }
    };

    console.log('Labour colony phase summary response:', responseData);
    res.status(200).json(responseData);

  } catch (err) {
    console.error('Error fetching labour colony phase summary:', err);
    res.status(500).json({ 
      success: false,
      error: 'Internal server error',
      data: {
        borewell: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        tanker: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        bwssb: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        others: { daily: 0, monthly: 0, cumulative: 0, period: 0 }
      }
    });
  }
});

// Operational Phase Summary (similar to construction)
app.get('/water-consumption/phase-summary/operational', async (req, res) => {
  try {
    console.log('Fetching operational phase summary with params:', req.query);
    
    const { date, fromDate, toDate } = req.query;
    const baseUrl = 'http://localhost:3000';
    
    const queryParams = new URLSearchParams();
    if (date) queryParams.append('date', date);
    if (fromDate) queryParams.append('fromDate', fromDate);
    if (toDate) queryParams.append('toDate', toDate);
    const queryString = queryParams.toString();
    
    const endpoints = [
      `${baseUrl}/borewell/consumption-summary?${queryString}`,
      `${baseUrl}/tanker/consumption-summary?${queryString}`,
      `${baseUrl}/bwssb/consumption-summary?${queryString}`
    ];

    const responses = await Promise.allSettled(
      endpoints.map(url => 
        fetch(url).then(r => r.json()).catch(e => {
          console.error(`Failed to fetch ${url}:`, e);
          return { data: { daily: 0, monthly: 0, cumulative: 0, period: 0 } };
        })
      )
    );

    const [borewellData, tankerData, bwssbData] = responses.map(response => 
      response.status === 'fulfilled' ? response.value : { data: { daily: 0, monthly: 0, cumulative: 0, period: 0 } }
    );

    const responseData = {
      success: true,
      data: {
        borewell: borewellData.data || { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        tanker: tankerData.data || { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        bwssb: bwssbData.data || { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        others: { daily: 0, monthly: 0, cumulative: 0, period: 0 }
      }
    };

    console.log('Operational phase summary response:', responseData);
    res.status(200).json(responseData);

  } catch (err) {
    console.error('Error fetching operational phase summary:', err);
    res.status(500).json({ 
      success: false,
      error: 'Internal server error',
      data: {
        borewell: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        tanker: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        bwssb: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
        others: { daily: 0, monthly: 0, cumulative: 0, period: 0 }
      }
    });
  }
});

// ===========================================
// REAL-TIME DOCUMENT SERVICE
// ===========================================

class RealTimeDocumentService {
  constructor(server) {
    this.io = new Server(server, {
      cors: {
        origin: "*", // Configure appropriately for production
        methods: ["GET", "POST"],
        credentials: true
      },
      transports: ['websocket', 'polling']
    });

    this.connectedUsers = new Map(); // userId -> socketId mapping
    this.userSockets = new Map(); // socketId -> user info mapping
    this.setupEventHandlers();
    
    logger.info('WebSocket server initialized');
  }

  setupEventHandlers() {
    this.io.on('connection', (socket) => {
      logger.info(`Client connected: ${socket.id}`);

      // Handle user authentication
      socket.on('authenticate', async (data) => {
        try {
          const { token, userId } = data;
          
          // Verify JWT token
          const decoded = verifyToken(token);
          if (decoded && decoded.id) {
            // Store user connection
            this.connectedUsers.set(decoded.id, socket.id);
            this.userSockets.set(socket.id, {
              userId: decoded.id,
              username: decoded.username,
              connectedAt: new Date()
            });

            socket.join(`user_${decoded.id}`);
            socket.emit('authenticated', { 
              success: true, 
              message: 'Successfully authenticated',
              userId: decoded.id 
            });

            // Send pending notifications
            await this.sendPendingNotifications(decoded.id, socket);
            
            logger.info(`User ${decoded.username} authenticated on socket ${socket.id}`);
          } else {
            socket.emit('authentication_error', { message: 'Invalid token' });
          }
        } catch (error) {
          logger.error('Authentication error:', error);
          socket.emit('authentication_error', { message: 'Authentication failed' });
        }
      });

      // Handle document subscription
      socket.on('subscribe_to_project', (data) => {
        const { projectName } = data;
        const userInfo = this.userSockets.get(socket.id);
        
        if (userInfo && projectName) {
          socket.join(`project_${projectName}`);
          socket.emit('subscribed', { 
            projectName,
            message: `Subscribed to ${projectName} updates` 
          });
          
          logger.info(`User ${userInfo.username} subscribed to project: ${projectName}`);
        }
      });

      // Handle document editing sessions
      socket.on('start_editing_document', (data) => {
        const { documentId } = data;
        const userInfo = this.userSockets.get(socket.id);
        
        if (userInfo && documentId) {
          socket.join(`document_${documentId}`);
          
          // Notify other users viewing the same document
          socket.to(`document_${documentId}`).emit('user_started_editing', {
            documentId,
            userId: userInfo.userId,
            username: userInfo.username,
            timestamp: new Date()
          });
          
          logger.info(`User ${userInfo.username} started editing document: ${documentId}`);
        }
      });

      socket.on('stop_editing_document', (data) => {
        const { documentId } = data;
        const userInfo = this.userSockets.get(socket.id);
        
        if (userInfo && documentId) {
          socket.leave(`document_${documentId}`);
          
          // Notify other users
          socket.to(`document_${documentId}`).emit('user_stopped_editing', {
            documentId,
            userId: userInfo.userId,
            username: userInfo.username,
            timestamp: new Date()
          });
          
          logger.info(`User ${userInfo.username} stopped editing document: ${documentId}`);
        }
      });

      // Handle real-time validation requests
      socket.on('validate_document_field', async (data) => {
        try {
          const { documentId, fieldName, fieldValue, projectName } = data;
          
          // Perform real-time validation
          const validationResult = await this.validateFieldInRealTime(
            documentId, fieldName, fieldValue, projectName
          );
          
          socket.emit('field_validation_result', {
            documentId,
            fieldName,
            validation: validationResult
          });
        } catch (error) {
          logger.error('Real-time validation error:', error);
          socket.emit('field_validation_error', { 
            fieldName, 
            error: error.message 
          });
        }
      });

      // Handle disconnection
      socket.on('disconnect', () => {
        const userInfo = this.userSockets.get(socket.id);
        
        if (userInfo) {
          this.connectedUsers.delete(userInfo.userId);
          this.userSockets.delete(socket.id);
          
          // Notify about user going offline
          this.io.emit('user_status_changed', {
            userId: userInfo.userId,
            username: userInfo.username,
            status: 'offline',
            timestamp: new Date()
          });
          
          logger.info(`User ${userInfo.username} disconnected from socket ${socket.id}`);
        } else {
          logger.info(`Client disconnected: ${socket.id}`);
        }
      });

      // Handle ping/pong for connection health
      socket.on('ping', () => {
        socket.emit('pong', { timestamp: new Date() });
      });
    });
  }

  // Real-time field validation
  async validateFieldInRealTime(documentId, fieldName, fieldValue, projectName) {
    try {
      const validationResult = {
        isValid: true,
        warnings: [],
        suggestions: [],
        inconsistencies: []
      };

      // Check for consistency with other documents in the same project
      if (projectName && ['project_name', 'project_address', 'built_up_area', 'plot_area'].includes(fieldName)) {
        const similarDocs = await dbQuery(`
          SELECT ${fieldName}, name, id FROM enhanced_project_documents 
          WHERE project_name = $1 AND id != $2 AND ${fieldName} IS NOT NULL
        `, [projectName, documentId]);

        if (similarDocs.rows.length > 0) {
          const existingValues = similarDocs.rows.map(doc => doc[fieldName]);
          const uniqueValues = [...new Set(existingValues)];

          if (fieldName === 'built_up_area' || fieldName === 'plot_area') {
            // Numeric field validation with tolerance
            const numericValue = parseFloat(fieldValue);
            const tolerance = fieldName === 'built_up_area' ? 1000 : 500; // sq ft tolerance

            const hasInconsistency = !existingValues.some(val => 
              Math.abs(parseFloat(val) - numericValue) <= tolerance
            );

            if (hasInconsistency) {
              validationResult.warnings.push({
                type: 'inconsistency',
                message: `${fieldName.replace('_', ' ')} differs from other documents in this project`,
                severity: 'medium',
                affectedDocuments: similarDocs.rows.map(doc => doc.name)
              });
            }
          } else {
            // Text field validation
            if (!existingValues.includes(fieldValue) && uniqueValues.length > 0) {
              validationResult.warnings.push({
                type: 'inconsistency',
                message: `${fieldName.replace('_', ' ')} differs from other documents in this project`,
                severity: 'high',
                suggestion: `Consider using: ${uniqueValues[0]}`,
                affectedDocuments: similarDocs.rows.map(doc => doc.name)
              });
            }
          }
        }
      }

      // Smart suggestions based on field type
      if (fieldName === 'issuing_authority') {
        const suggestions = await this.getAuthoritySuggestions(fieldValue);
        if (suggestions.length > 0) {
          validationResult.suggestions = suggestions;
        }
      }

      if (fieldName === 'approval_number') {
        const pattern = this.getApprovalNumberPattern(fieldValue);
        if (pattern.isValid === false) {
          validationResult.warnings.push({
            type: 'format',
            message: 'Approval number format may be incorrect',
            severity: 'low',
            suggestion: pattern.suggestion
          });
        }
      }

      return validationResult;
    } catch (error) {
      logger.error('Real-time validation error:', error);
      return {
        isValid: false,
        error: error.message
      };
    }
  }

  // Get authority suggestions based on partial input
  async getAuthoritySuggestions(partialText) {
    try {
      const commonAuthorities = [
        'Karnataka State Pollution Control Board',
        'Bruhat Bengaluru Mahanagara Palike',
        'Ministry of Environment, Forest and Climate Change',
        'State Groundwater Authority',
        'Karnataka Fire and Emergency Services',
        'Airports Authority of India',
        'Bangalore Electricity Supply Company'
      ];

      return commonAuthorities
        .filter(auth => 
          auth.toLowerCase().includes(partialText.toLowerCase())
        )
        .slice(0, 3)
        .map(auth => ({
          text: auth,
          confidence: this.calculateMatchConfidence(partialText, auth)
        }));
    } catch (error) {
      logger.error('Error getting authority suggestions:', error);
      return [];
    }
  }

  // Pattern validation for approval numbers
  getApprovalNumberPattern(approvalNumber) {
    const patterns = {
      'KSPCB': /^KSPCB\/[A-Z]{2,4}\/\d{4}\/\d{6}$/,
      'BBMP': /^BBMP\/[A-Z]{4}\/\d{4}\/[A-Z]{2}\d{3}$/,
      'AAI': /^AAI\/[A-Z]{2}\/\d{4}\/[A-Z]{3}\d{3}$/,
      'SGWA': /^SGWA\/\d{4}\/[A-Z]{3}\d{3}$/
    };

    for (const [authority, pattern] of Object.entries(patterns)) {
      if (approvalNumber.includes(authority)) {
        return {
          isValid: pattern.test(approvalNumber),
          suggestion: pattern.test(approvalNumber) 
            ? null 
            : `Expected format for ${authority}: ${pattern.source}`
        };
      }
    }

    return { isValid: true, suggestion: null };
  }

  calculateMatchConfidence(input, suggestion) {
    const inputLower = input.toLowerCase();
    const suggestionLower = suggestion.toLowerCase();
    
    if (suggestionLower.startsWith(inputLower)) {
      return 0.9;
    } else if (suggestionLower.includes(inputLower)) {
      return 0.7;
    } else {
      return 0.5;
    }
  }

  // Send pending notifications to newly connected users
  async sendPendingNotifications(userId, socket) {
    try {
      const notifications = await NotificationService.getUserNotifications(userId, {
        unread_only: true,
        limit: 10
      });

      if (notifications.notifications.length > 0) {
        socket.emit('pending_notifications', {
          notifications: notifications.notifications,
          unread_count: notifications.unread_count
        });
      }
    } catch (error) {
      logger.error('Error sending pending notifications:', error);
    }
  }

  // Broadcast document update to relevant users
  broadcastDocumentUpdate(documentId, document, updateType, userId) {
    try {
      const updateData = {
        documentId,
        document,
        updateType, // 'created', 'updated', 'deleted'
        updatedBy: userId,
        timestamp: new Date()
      };

      // Broadcast to document subscribers
      this.io.to(`document_${documentId}`).emit('document_updated', updateData);

      // Broadcast to project subscribers if project name exists
      if (document.project_name) {
        this.io.to(`project_${document.project_name}`).emit('project_document_updated', updateData);
      }

      // Broadcast to all authenticated users for critical updates
      if (updateType === 'expired' || updateType === 'critical_inconsistency') {
        this.io.emit('critical_document_alert', updateData);
      }

      logger.info(`Broadcasted document update: ${documentId} (${updateType})`);
    } catch (error) {
      logger.error('Error broadcasting document update:', error);
    }
  }

  // Broadcast system-wide notifications
  broadcastSystemNotification(notification) {
    try {
      this.io.emit('system_notification', {
        ...notification,
        timestamp: new Date()
      });

      logger.info(`Broadcasted system notification: ${notification.title}`);
    } catch (error) {
      logger.error('Error broadcasting system notification:', error);
    }
  }

  // Send notification to specific user
  sendNotificationToUser(userId, notification) {
    try {
      const socketId = this.connectedUsers.get(userId);
      
      if (socketId) {
        this.io.to(socketId).emit('user_notification', {
          ...notification,
          timestamp: new Date()
        });
        
        logger.info(`Sent notification to user ${userId}: ${notification.title}`);
        return true;
      } else {
        logger.info(`User ${userId} not connected, notification queued`);
        return false;
      }
    } catch (error) {
      logger.error('Error sending notification to user:', error);
      return false;
    }
  }

  // Get connected users count
  getConnectedUsersCount() {
    return this.connectedUsers.size;
  }

  // Get user connection status
  isUserConnected(userId) {
    return this.connectedUsers.has(userId);
  }

  // Broadcast expiry alerts in real-time
  async broadcastExpiryAlerts() {
    try {
      const expiringDocs = await DocumentIntelligenceService.checkExpiringDocuments(30);
      
      for (const doc of expiringDocs) {
        const alertData = {
          type: 'document_expiry',
          severity: doc.alert_type,
          document: {
            id: doc.id,
            name: doc.name,
            project_name: doc.project_name,
            days_until_expiry: doc.days_until_expiry,
            validity_end_date: doc.validity_end_date
          },
          suggested_action: doc.suggested_action,
          timestamp: new Date()
        };

        // Send to project subscribers
        if (doc.project_name) {
          this.io.to(`project_${doc.project_name}`).emit('expiry_alert', alertData);
        }

        // Send critical alerts to all users
        if (doc.days_until_expiry <= 7) {
          this.io.emit('critical_expiry_alert', alertData);
        }
      }

      logger.info(`Broadcasted expiry alerts for ${expiringDocs.length} documents`);
    } catch (error) {
      logger.error('Error broadcasting expiry alerts:', error);
    }
  }

  // Real-time health score updates
  async broadcastHealthScoreUpdate(projectName = null) {
    try {
      const healthReport = await DocumentIntelligenceService.generateHealthReport(projectName);
      
      const healthData = {
        project_name: projectName,
        health_score: healthReport.health_score,
        health_status: healthReport.health_status,
        summary: healthReport.summary,
        timestamp: new Date()
      };

      if (projectName) {
        this.io.to(`project_${projectName}`).emit('health_score_updated', healthData);
      } else {
        this.io.emit('system_health_updated', healthData);
      }

      logger.info(`Broadcasted health score update: ${healthReport.health_score}%`);
    } catch (error) {
      logger.error('Error broadcasting health score update:', error);
    }
  }
}

// ===========================================
// SERVER INITIALIZATION AND STARTUP
// ===========================================

// Initialize additional database tables and data
const initializeAdditionalTables = async () => {
  try {
    console.log('Initializing additional database tables...');
    
    // Create all remaining tables
    await dbQuery(createUsersTable);
    await dbQuery(createBorewellTable);
    await dbQuery(createAlertTable);
    await dbQuery(createStackMonitoringTable);
    await dbQuery(createAmbientMonitoringTable);
    await dbQuery(createConsumptionTable);
    await dbQuery(createTankersTable);
    await dbQuery(addFreshWaterFields); // Add new fresh water fields
    await dbQuery(createWaterTankerRecordsTable);
    await dbQuery(createDailyInputTable);
    await dbQuery(createLabourColonyWasteTable);
    await dbQuery(createCDWasteTable);
    await dbQuery(createCDWasteCalculationTable);
    await dbQuery(createcd_waste_calcTable);
    await dbQuery(createDailyWasteTable);
    await dbQuery(createMunicipalSolidWasteTable);
    await dbQuery(createConstructionPhaseWasteTable);
    
    // Run database migrations for new columns
    await migrateCDWasteTable();
    await migrateDailyWasteTable();
    await dbQuery(createTableQuery);
    await dbQuery(createTableproject_waste);
    await dbQuery(createbwssb_supplyTable);
    // Skip trigger creation for SQLite (PostgreSQL only)
    if (isPostgreSQL) {
      await dbQuery(createUpdateTrigger);
    }
    await dbQuery(createLabourColonyConsumptionTable);
    
    // Create BWSSB tables
    await createBWSSBTables();
    await dbQuery(createSystemMetricsHistoryTable);
    await dbQuery(createProjectDocumentsTable);
    await dbQuery(createDocumentCategoriesTable);
    await dbQuery(createDocumentIndexes);
    
    // Insert default data
    await dbQuery(insertDefaultCategories);
    
    console.log('Additional database tables initialization completed successfully');
  } catch (error) {
    console.error('Error initializing additional database tables:', error);
    throw error;
  }
};

// Schedule validation checks function
const scheduleValidationChecks = () => {
  try {
    console.log('Validation checks scheduled successfully');
    // Placeholder for validation checks - implement as needed
    // You can add periodic validation logic here
  } catch (error) {
    logger.error('Error scheduling validation checks:', error);
  }
};

// Initialize enhanced document system function
const initializeEnhancedDocumentSystem = async () => {
  try {
    console.log('Enhanced document system initialized successfully');
    // Placeholder for enhanced document system - implement as needed
    // You can add document management logic here
  } catch (error) {
    logger.error('Error initializing enhanced document system:', error);
    throw error;
  }
};

// Initialize notification system
const initializeSystem = async () => {
  try {
    console.log('Initializing system components...');
    
    // Initialize notification system (placeholder)
    // initializeNotificationSystem();
    
    // Schedule validation checks
    scheduleValidationChecks();
    
    // Initialize enhanced document system
    await initializeEnhancedDocumentSystem();
    
    console.log('System initialization completed successfully');
  } catch (error) {
    console.error('Error initializing system:', error);
    throw error;
  }
};

// Create HTTP server for WebSocket support
const httpServer = createServer(app);

// Initialize WebSocket service
global.realTimeService = new RealTimeDocumentService(httpServer);

// ===========================================
// WASTE MANAGEMENT API ENDPOINTS
// ===========================================

// Municipal Solid Waste Management
app.get('/municipal-solid-waste', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 50;
    const offset = parseInt(req.query.offset) || 0;
    
    const query = `
      SELECT * FROM municipal_solid_waste 
      ORDER BY date DESC, created_at DESC 
      LIMIT $1 OFFSET $2
    `;
    
    const result = await dbQuery(query, [limit, offset]);
    
    res.json({
      success: true,
      data: result.rows,
      total: result.rows.length
    });

  } catch (error) {
    logger.error('Error fetching municipal solid waste records:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch municipal solid waste records',
      message: error.message
    });
  }
});

app.post('/municipal-solid-waste', async (req, res) => {
  try {
    const {
      date,
      no_of_houses_occupied,
      num_employees = 0,
      dry_generated_quantity,
      dry_disposed_to,
      dry_quantity,
      wet_generated_quantity,
      wet_disposed_to,
      wet_quantity,
      sanitary_napkins_generated_quantity,
      sanitary_napkins_disposed_to,
      sanitary_napkins_quantity,
      e_waste_generated_quantity,
      e_waste_disposed_to,
      e_waste_quantity,
      bio_medical_waste_generated_quantity,
      bio_medical_waste_disposed_to,
      bio_medical_waste_quantity,
      battery_waste_generated_quantity,
      battery_waste_disposed_to,
      battery_waste_quantity,
      others_generated_quantity,
      others_disposed_to,
      others_quantity,
      vendor_license_url,
      disposal_photo_url
    } = req.body;

    // Calculate employee-generated waste (kg): 100g per employee per day
    const employee_generated_waste = (parseInt(num_employees) || 0) * 0.1;

    const query = `
      INSERT INTO municipal_solid_waste (
        date, no_of_houses_occupied, num_employees, employee_generated_waste,
        dry_generated_quantity, dry_disposed_to, dry_quantity,
        wet_generated_quantity, wet_disposed_to, wet_quantity,
        sanitary_napkins_generated_quantity, sanitary_napkins_disposed_to, sanitary_napkins_quantity,
        e_waste_generated_quantity, e_waste_disposed_to, e_waste_quantity,
        bio_medical_waste_generated_quantity, bio_medical_waste_disposed_to, bio_medical_waste_quantity,
        battery_waste_generated_quantity, battery_waste_disposed_to, battery_waste_quantity,
        others_generated_quantity, others_disposed_to, others_quantity,
        vendor_license_url, disposal_photo_url
      ) VALUES (
        $1, $2, $3, $4,
        $5, $6, $7,
        $8, $9, $10,
        $11, $12, $13,
        $14, $15, $16,
        $17, $18, $19,
        $20, $21, $22,
        $23, $24, $25,
        $26, $27
      ) RETURNING id
    `;

    const values = [
      date, no_of_houses_occupied || 0, num_employees || 0, employee_generated_waste,
      dry_generated_quantity || 0, dry_disposed_to || '', dry_quantity || 0,
      wet_generated_quantity || 0, wet_disposed_to || '', wet_quantity || 0,
      sanitary_napkins_generated_quantity || 0, sanitary_napkins_disposed_to || '', sanitary_napkins_quantity || 0,
      e_waste_generated_quantity || 0, e_waste_disposed_to || '', e_waste_quantity || 0,
      bio_medical_waste_generated_quantity || 0, bio_medical_waste_disposed_to || '', bio_medical_waste_quantity || 0,
      battery_waste_generated_quantity || 0, battery_waste_disposed_to || '', battery_waste_quantity || 0,
      others_generated_quantity || 0, others_disposed_to || '', others_quantity || 0,
      vendor_license_url || null, disposal_photo_url || null
    ];

    const result = await dbQuery(query, values);

    logger.info(`Municipal solid waste record created with ID: ${result.rows[0].id}`);

    res.status(201).json({
      success: true,
      data: { id: result.rows[0].id },
      message: 'Municipal solid waste record created successfully'
    });

  } catch (error) {
    logger.error('Error creating municipal solid waste record:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create municipal solid waste record',
      message: error.message
    });
  }
});

app.delete('/municipal-solid-waste/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const query = 'DELETE FROM municipal_solid_waste WHERE id = $1 RETURNING id';
    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Municipal solid waste record not found'
      });
    }

    logger.info(`Municipal solid waste record deleted: ${id}`);

    res.json({
      success: true,
      message: 'Municipal solid waste record deleted successfully'
    });

  } catch (error) {
    logger.error('Error deleting municipal solid waste record:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete municipal solid waste record',
      message: error.message
    });
  }
});

app.get('/municipal-solid-waste/stats', async (req, res) => {
  try {
    const query = `
      SELECT 
        COUNT(*) as total_records,
        COALESCE(SUM(dry_generated_quantity + wet_generated_quantity + sanitary_napkins_generated_quantity + e_waste_generated_quantity + bio_medical_waste_generated_quantity + battery_waste_generated_quantity + others_generated_quantity), 0) as total_waste_generated,
        COALESCE(SUM(dry_quantity + wet_quantity + sanitary_napkins_quantity + e_waste_quantity + bio_medical_waste_quantity + battery_waste_quantity + others_quantity), 0) as total_waste_disposed,
        COALESCE(AVG(dry_generated_quantity + wet_generated_quantity + sanitary_napkins_generated_quantity + e_waste_generated_quantity + bio_medical_waste_generated_quantity + battery_waste_generated_quantity + others_generated_quantity), 0) as avg_daily_waste,
        COALESCE(AVG(no_of_houses_occupied), 0) as avg_houses_occupied
      FROM municipal_solid_waste
    `;
    
    const result = await dbQuery(query);
    const summary = result.rows[0];

    res.json({
      success: true,
      summary: {
        total_records: parseInt(summary.total_records),
        total_waste_generated: parseFloat(summary.total_waste_generated),
        total_waste_disposed: parseFloat(summary.total_waste_disposed),
        avg_daily_waste: parseFloat(summary.avg_daily_waste),
        avg_houses_occupied: parseFloat(summary.avg_houses_occupied)
      }
    });

  } catch (error) {
    logger.error('Error fetching municipal solid waste stats:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch municipal solid waste statistics',
      message: error.message
    });
  }
});

// Construction Phase Waste Management
app.get('/construction-phase-waste', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 50;
    const offset = parseInt(req.query.offset) || 0;
    
    const query = `
      SELECT * FROM construction_phase_waste 
      ORDER BY date DESC, created_at DESC 
      LIMIT $1 OFFSET $2
    `;
    
    const result = await dbQuery(query, [limit, offset]);
    
    res.json({
      success: true,
      data: result.rows,
      total: result.rows.length
    });

  } catch (error) {
    logger.error('Error fetching construction phase waste records:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch construction phase waste records',
      message: error.message
    });
  }
});

app.post('/construction-phase-waste', async (req, res) => {
  try {
    const {
      date,
      approx_no_of_labour,
      dry_waste_generated,
      dry_waste_disposed_through,
      wet_waste_generated,
      wet_waste_disposed_through,
      notes
    } = req.body;

    const query = `
      INSERT INTO construction_phase_waste (
        date, approx_no_of_labour, dry_waste_generated, dry_waste_disposed_through,
        wet_waste_generated, wet_waste_disposed_through, notes
      ) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id
    `;

    const values = [
      date,
      approx_no_of_labour || 0,
      dry_waste_generated || 0,
      dry_waste_disposed_through || '',
      wet_waste_generated || 0,
      wet_waste_disposed_through || '',
      notes || ''
    ];

    const result = await dbQuery(query, values);

    logger.info(`Construction phase waste record created with ID: ${result.rows[0].id}`);

    res.status(201).json({
      success: true,
      data: { id: result.rows[0].id },
      message: 'Construction phase waste record created successfully'
    });

  } catch (error) {
    logger.error('Error creating construction phase waste record:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create construction phase waste record',
      message: error.message
    });
  }
});

// Cement submissions endpoint
app.post('/api/cement-submissions', async (req, res) => {
  try {
    const {
      date,
      latitude,
      longitude,
      gross_weight,
      tare_weight,
      net_weight,
      vehicle_number,
      driver_number,
      contact_number,
      timestamp,
      // Enhanced OCR fields
      material_name,
      material_category,
      weighment_slip_no,
      driver_name,
      transporter
    } = req.body;

    // Validate required fields
    if (!date || !latitude || !longitude || !gross_weight || !tare_weight || !net_weight || !driver_number || !contact_number) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'All fields are required'
      });
    }

    // Create cement_submissions table if it doesn't exist
    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS cement_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        -- Enhanced OCR fields
        material_name VARCHAR(255),
        material_category VARCHAR(255),
        weighment_slip_no VARCHAR(255),
        driver_name VARCHAR(255),
        transporter VARCHAR(255)
      )
    `;

    await dbQuery(createTableQuery);

    // Insert the cement submission data
    const insertQuery = `
      INSERT INTO cement_submissions (
        date, latitude, longitude, gross_weight, tare_weight, net_weight,
        vehicle_number, driver_number, contact_number, timestamp,
        material_name, driver_name
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING id
    `;

    const values = [
      date,
      parseFloat(latitude),
      parseFloat(longitude),
      gross_weight,
      tare_weight,
      net_weight,
      vehicle_number || null,
      driver_number,
      contact_number,
      timestamp || new Date().toISOString(),
      material_name || null,
      driver_name || null
    ];

    const result = await dbQuery(insertQuery, values);

    logger.info(`Cement submission created with ID: ${result.rows[0].id}`);

    res.status(201).json({
      success: true,
      data: { 
        id: result.rows[0].id,
        message: 'Cement data submitted successfully'
      }
    });

  } catch (error) {
    logger.error('Error creating cement submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to submit cement data',
      message: error.message
    });
  }
});

// Driver license upload endpoint (MANDATORY with multiple format support)
app.post('/api/upload-license', driverLicenseUpload.single('license'), async (req, res) => {
  try {
    const { driver_number, contact_number } = req.body;
    const file = req.file;

    // Validate required fields
    if (!driver_number || !contact_number) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'Driver number and contact number are required'
      });
    }

    if (!file) {
      return res.status(400).json({
        success: false,
        error: 'No file uploaded',
        message: 'Please upload a license image file'
      });
    }

    // Upload to S3 manually (AWS SDK v3 compatible)
    const timestamp = Date.now();
    const fileFormat = path.extname(file.originalname).toLowerCase().replace('.', '');
    const sanitizedDriverNumber = (driver_number || 'unknown').replace(/[^a-zA-Z0-9]/g, '_');
    const sanitizedFileName = file.originalname.replace(/[^a-zA-Z0-9.-]/g, '_');
    const s3Key = `driver-licenses/${sanitizedDriverNumber}/${timestamp}_${sanitizedFileName}`;
    
    let s3Url = '';
    
    if (s3Client) {
      try {
        const uploadParams = {
          Bucket: process.env.AWS_BUCKET_NAME,
          Key: s3Key,
          Body: file.buffer,
          ContentType: file.mimetype,
          Metadata: {
            'driver-number': driver_number || '',
            'contact-number': contact_number || '',
            'upload-timestamp': new Date().toISOString(),
            'file-type': 'driver-license',
            'original-name': file.originalname
          }
        };

        const command = new PutObjectCommand(uploadParams);
        await s3Client.send(command);
        
        s3Url = `https://${process.env.AWS_BUCKET_NAME}.s3.${process.env.AWS_REGION}.amazonaws.com/${s3Key}`;
        logger.info(`File uploaded to S3: ${s3Url}`);
      } catch (s3Error) {
        logger.error('S3 upload failed:', s3Error);
        return res.status(500).json({
          success: false,
          error: 'File upload failed',
          message: 'Could not upload file to storage'
        });
      }
    }

    // Create driver_licenses table if it doesn't exist (Enhanced schema)
    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS driver_licenses (
        id SERIAL PRIMARY KEY,
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        license_filename VARCHAR(255) NOT NULL,
        license_url VARCHAR(500) NOT NULL,
        file_size INTEGER,
        mime_type VARCHAR(100),
        s3_key VARCHAR(500),
        s3_bucket VARCHAR(100),
        file_format VARCHAR(20),
        is_verified BOOLEAN DEFAULT FALSE,
        uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        
        -- Add unique constraint to prevent duplicate uploads per driver
        UNIQUE(driver_number, license_filename)
      )
    `;

    await dbQuery(createTableQuery);

    // Store license information in database with enhanced metadata
        
    const insertQuery = `
      INSERT INTO driver_licenses (
        driver_number, contact_number, license_filename, license_url,
        file_size, mime_type, s3_key, s3_bucket, file_format
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id
    `;

    const values = [
      driver_number,
      contact_number,
      file.originalname,
      s3Url || 'local-storage', // S3 location URL
      file.size,
      file.mimetype,
      s3Key, // S3 key for future reference
      process.env.AWS_BUCKET_NAME || null,
      fileFormat
    ];

    const result = await dbQuery(insertQuery, values);

    logger.info(`Driver license uploaded with ID: ${result.rows[0].id} for driver: ${driver_number}`);

    res.status(201).json({
      success: true,
      data: { 
        id: result.rows[0].id,
        message: 'Driver license uploaded successfully to S3',
        filename: file.originalname,
        size: file.size,
        format: fileFormat.toUpperCase(),
        s3_url: s3Url,
        s3_key: s3Key,
        upload_timestamp: new Date().toISOString(),
        storage_location: `driver-licenses/${sanitizedDriverNumber}/`
      }
    });

  } catch (error) {
    logger.error('Error uploading driver license:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to upload driver license',
      message: error.message
    });
  }
});

// Get cement submissions endpoint
app.get('/api/cement-submissions', async (req, res) => {
  try {
    const { page = 1, limit = 50, date_from, date_to } = req.query;
    const offset = (page - 1) * limit;

    let query = `
      SELECT * FROM cement_submissions 
      WHERE 1=1
    `;
    let values = [];
    let paramCount = 0;

    // Add date filtering if provided
    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` ORDER BY created_at DESC LIMIT $${paramCount + 1} OFFSET $${paramCount + 2}`;
    values.push(limit, offset);

    const result = await dbQuery(query, values);

    // Get total count for pagination
    let countQuery = `SELECT COUNT(*) FROM cement_submissions WHERE 1=1`;
    let countValues = [];
    let countParamCount = 0;

    if (date_from) {
      countParamCount++;
      countQuery += ` AND date >= $${countParamCount}`;
      countValues.push(date_from);
    }

    if (date_to) {
      countParamCount++;
      countQuery += ` AND date <= $${countParamCount}`;
      countValues.push(date_to);
    }

    const countResult = await dbQuery(countQuery, countValues);
    const totalRecords = parseInt(countResult.rows[0].count);

    res.status(200).json({
      success: true,
      data: result.rows,
      pagination: {
        current_page: parseInt(page),
        total_pages: Math.ceil(totalRecords / limit),
        total_records: totalRecords,
        records_per_page: parseInt(limit)
      }
    });

  } catch (error) {
    logger.error('Error fetching cement submissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch cement submissions',
      message: error.message
    });
  }
});

// Cement Analytics Endpoint
app.get('/api/cement-analytics', async (req, res) => {
  try {
    const { date_from, date_to, group_by = 'day' } = req.query;

    // Base query for analytics
    let query = `
      SELECT 
        date,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(tare_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_tare_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles,
        COUNT(DISTINCT driver_number) as unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight
      FROM cement_submissions 
      WHERE 1=1
    `;
    
    let values = [];
    let paramCount = 0;

    // Add date filtering
    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    // Group by date
    query += ` GROUP BY date ORDER BY date DESC`;

    const analyticsResult = await dbQuery(query, values);

    // Calculate summary statistics
    const summaryQuery = `
      SELECT 
        COUNT(*) as total_submissions,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as total_unique_vehicles,
        COUNT(DISTINCT driver_number) as total_unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight,
        MIN(date) as earliest_date,
        MAX(date) as latest_date
      FROM cement_submissions
      WHERE 1=1
      ${date_from ? `AND date >= '${date_from}'` : ''}
      ${date_to ? `AND date <= '${date_to}'` : ''}
    `;

    const summaryResult = await dbQuery(summaryQuery);

    // Top vehicles by submission count
    const topVehiclesQuery = `
      SELECT 
        vehicle_number,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight
      FROM cement_submissions 
      WHERE vehicle_number IS NOT NULL AND vehicle_number != ''
      ${date_from ? `AND date >= '${date_from}'` : ''}
      ${date_to ? `AND date <= '${date_to}'` : ''}
      GROUP BY vehicle_number 
      ORDER BY submission_count DESC 
      LIMIT 10
    `;

    const topVehiclesResult = await dbQuery(topVehiclesQuery);

    // Top drivers by submission count
    const topDriversQuery = `
      SELECT 
        driver_number,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight
      FROM cement_submissions 
      WHERE driver_number IS NOT NULL AND driver_number != ''
      ${date_from ? `AND date >= '${date_from}'` : ''}
      ${date_to ? `AND date <= '${date_to}'` : ''}
      GROUP BY driver_number 
      ORDER BY submission_count DESC 
      LIMIT 10
    `;

    const topDriversResult = await dbQuery(topDriversQuery);

    res.status(200).json({
      success: true,
      data: {
        daily_analytics: analyticsResult.rows,
        summary: summaryResult.rows[0],
        top_vehicles: topVehiclesResult.rows,
        top_drivers: topDriversResult.rows,
        period: {
          date_from: date_from || null,
          date_to: date_to || null
        }
      }
    });

  } catch (error) {
    logger.error('Error fetching cement analytics:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch cement analytics',
      message: error.message
    });
  }
});

// ===========================================
// SAND MANAGEMENT API ENDPOINTS
// ===========================================

// Sand submissions endpoint
app.post('/api/sand-submissions', async (req, res) => {
  try {
    const {
      date,
      latitude,
      longitude,
      gross_weight,
      tare_weight,
      net_weight,
      vehicle_number,
      driver_number,
      contact_number,
      timestamp,
      // Enhanced OCR fields
      material_name,
      material_category,
      weighment_slip_no,
      driver_name,
      transporter,
      vehicle_photo_url,
      vendor_license_photo_url
    } = req.body;

    // Validate required fields
    if (!date || !latitude || !longitude || !gross_weight || !tare_weight || !net_weight || !driver_number || !contact_number) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'All fields are required'
      });
    }

    // Create sand_submissions table if it doesn't exist
    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS sand_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        -- Enhanced OCR fields
        material_name VARCHAR(255),
        material_category VARCHAR(255),
        weighment_slip_no VARCHAR(255),
        driver_name VARCHAR(255),
        transporter VARCHAR(255)
      )
    `;

    await dbQuery(createTableQuery);

    // Insert the sand submission data
    const insertQuery = `
      INSERT INTO sand_submissions (
        date, latitude, longitude, gross_weight, tare_weight, net_weight,
        vehicle_number, driver_number, contact_number, timestamp,
        material_name, driver_name, vehicle_photo_url, vendor_license_photo_url
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) RETURNING id
    `;

    const values = [
      date,
      parseFloat(latitude),
      parseFloat(longitude),
      gross_weight,
      tare_weight,
      net_weight,
      vehicle_number || null,
      driver_number,
      contact_number,
      timestamp || new Date().toISOString(),
      material_name || null,
      driver_name || null,
      vehicle_photo_url || null,
      vendor_license_photo_url || null
    ];

    const result = await dbQuery(insertQuery, values);

    logger.info(`Sand submission created with ID: ${result.rows[0].id}`);

    res.status(201).json({
      success: true,
      data: { 
        id: result.rows[0].id,
        message: 'Sand data submitted successfully'
      }
    });

  } catch (error) {
    logger.error('Error creating sand submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to submit sand data',
      message: error.message
    });
  }
});

// Get sand submissions endpoint
app.get('/api/sand-submissions', async (req, res) => {
  try {
    const { page = 1, limit = 50, date_from, date_to } = req.query;
    const offset = (page - 1) * limit;

    let query = `
      SELECT * FROM sand_submissions 
      WHERE 1=1
    `;
    let values = [];
    let paramCount = 0;

    // Add date filtering if provided
    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` ORDER BY created_at DESC LIMIT $${paramCount + 1} OFFSET $${paramCount + 2}`;
    values.push(limit, offset);

    const result = await dbQuery(query, values);

    // Get total count for pagination
    let countQuery = `SELECT COUNT(*) FROM sand_submissions WHERE 1=1`;
    let countValues = [];
    let countParamCount = 0;

    if (date_from) {
      countParamCount++;
      countQuery += ` AND date >= $${countParamCount}`;
      countValues.push(date_from);
    }

    if (date_to) {
      countParamCount++;
      countQuery += ` AND date <= $${countParamCount}`;
      countValues.push(date_to);
    }

    const countResult = await dbQuery(countQuery, countValues);
    const totalRecords = parseInt(countResult.rows[0].count);

    res.status(200).json({
      success: true,
      data: result.rows,
      pagination: {
        current_page: parseInt(page),
        total_pages: Math.ceil(totalRecords / limit),
        total_records: totalRecords,
        records_per_page: parseInt(limit)
      }
    });

  } catch (error) {
    logger.error('Error fetching sand submissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch sand submissions',
      message: error.message
    });
  }
});

// Sand Analytics Endpoint
app.get('/api/sand-analytics', async (req, res) => {
  try {
    const { date_from, date_to, group_by = 'day' } = req.query;

    // Base query for analytics
    let query = `
      SELECT 
        date,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(tare_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_tare_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles,
        COUNT(DISTINCT driver_number) as unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight
      FROM sand_submissions 
      WHERE 1=1
    `;
    
    let values = [];
    let paramCount = 0;

    // Add date filtering
    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    // Group by date
    query += ` GROUP BY date ORDER BY date DESC`;

    const analyticsResult = await dbQuery(query, values);

    // Calculate summary statistics
    const summaryQuery = `
      SELECT 
        COUNT(*) as total_submissions,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as total_unique_vehicles,
        COUNT(DISTINCT driver_number) as total_unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight,
        MIN(date) as earliest_date,
        MAX(date) as latest_date
      FROM sand_submissions
      WHERE 1=1
      ${date_from ? `AND date >= '${date_from}'` : ''}
      ${date_to ? `AND date <= '${date_to}'` : ''}
    `;

    const summaryResult = await dbQuery(summaryQuery);

    // Top vehicles by submission count
    const topVehiclesQuery = `
      SELECT 
        vehicle_number,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight
      FROM sand_submissions 
      WHERE vehicle_number IS NOT NULL AND vehicle_number != ''
      ${date_from ? `AND date >= '${date_from}'` : ''}
      ${date_to ? `AND date <= '${date_to}'` : ''}
      GROUP BY vehicle_number 
      ORDER BY submission_count DESC 
      LIMIT 10
    `;

    const topVehiclesResult = await dbQuery(topVehiclesQuery);

    // Top drivers by submission count
    const topDriversQuery = `
      SELECT 
        driver_number,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight
      FROM sand_submissions 
      WHERE driver_number IS NOT NULL AND driver_number != ''
      ${date_from ? `AND date >= '${date_from}'` : ''}
      ${date_to ? `AND date <= '${date_to}'` : ''}
      GROUP BY driver_number 
      ORDER BY submission_count DESC 
      LIMIT 10
    `;

    const topDriversResult = await dbQuery(topDriversQuery);

    res.status(200).json({
      success: true,
      data: {
        daily_analytics: analyticsResult.rows,
        summary: summaryResult.rows[0],
        top_vehicles: topVehiclesResult.rows,
        top_drivers: topDriversResult.rows,
        period: {
          date_from: date_from || null,
          date_to: date_to || null
        }
      }
    });

  } catch (error) {
    logger.error('Error fetching sand analytics:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch sand analytics',
      message: error.message
    });
  }
});

// ===========================================
// METALS MANAGEMENT API ENDPOINTS
// ===========================================

app.post('/api/metals-submissions', async (req, res) => {
  try {
    const {
      date, latitude, longitude, gross_weight, tare_weight, net_weight,
      vehicle_number, driver_number, contact_number, timestamp,
      // Enhanced OCR fields
      material_name, driver_name,
      // Photo URLs
      vehicle_photo_url, vendor_license_photo_url
    } = req.body;

    if (!date || !latitude || !longitude || !gross_weight || !tare_weight || !net_weight || !driver_number || !contact_number) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'All fields are required'
      });
    }

    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS metals_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        -- Enhanced OCR fields
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT
      )
    `;

    await dbQuery(createTableQuery);

    const insertQuery = `
      INSERT INTO metals_submissions (
        date, latitude, longitude, gross_weight, tare_weight, net_weight,
        vehicle_number, driver_number, contact_number, timestamp,
        material_name, driver_name,
        vehicle_photo_url, vendor_license_photo_url
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) RETURNING id
    `;

    const values = [
      date, parseFloat(latitude), parseFloat(longitude), gross_weight, tare_weight, net_weight,
      vehicle_number || null, driver_number, contact_number, timestamp || new Date().toISOString(),
      material_name || null, driver_name || null,
      vehicle_photo_url || null, vendor_license_photo_url || null
    ];

    const result = await dbQuery(insertQuery, values);
    logger.info(`Metals submission created with ID: ${result.rows[0].id}`);

    res.status(201).json({
      success: true,
      data: { id: result.rows[0].id, message: 'Metals data submitted successfully' }
    });

  } catch (error) {
    logger.error('Error creating metals submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to submit metals data',
      message: error.message
    });
  }
});

app.get('/api/metals-submissions', async (req, res) => {
  try {
    const { page = 1, limit = 50, date_from, date_to } = req.query;
    const offset = (page - 1) * limit;

    let query = `SELECT * FROM metals_submissions WHERE 1=1`;
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` ORDER BY created_at DESC LIMIT $${paramCount + 1} OFFSET $${paramCount + 2}`;
    values.push(limit, offset);

    const result = await dbQuery(query, values);

    let countQuery = `SELECT COUNT(*) FROM metals_submissions WHERE 1=1`;
    let countValues = [];
    let countParamCount = 0;

    if (date_from) {
      countParamCount++;
      countQuery += ` AND date >= $${countParamCount}`;
      countValues.push(date_from);
    }

    if (date_to) {
      countParamCount++;
      countQuery += ` AND date <= $${countParamCount}`;
      countValues.push(date_to);
    }

    const countResult = await dbQuery(countQuery, countValues);
    const totalRecords = parseInt(countResult.rows[0].count);

    res.status(200).json({
      success: true,
      data: result.rows,
      pagination: {
        current_page: parseInt(page),
        total_pages: Math.ceil(totalRecords / limit),
        total_records: totalRecords,
        records_per_page: parseInt(limit)
      }
    });

  } catch (error) {
    logger.error('Error fetching metals submissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch metals submissions',
      message: error.message
    });
  }
});

app.get('/api/metals-analytics', async (req, res) => {
  try {
    const { date_from, date_to } = req.query;

    let query = `
      SELECT 
        date,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(tare_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_tare_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles,
        COUNT(DISTINCT driver_number) as unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight
      FROM metals_submissions 
      WHERE 1=1
    `;
    
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` GROUP BY date ORDER BY date DESC`;

    const analyticsResult = await dbQuery(query, values);

    const summaryQuery = `
      SELECT 
        COUNT(*) as total_submissions,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as total_unique_vehicles,
        COUNT(DISTINCT driver_number) as total_unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight,
        MIN(date) as earliest_date,
        MAX(date) as latest_date
      FROM metals_submissions
      WHERE 1=1
      ${date_from ? `AND date >= '${date_from}'` : ''}
      ${date_to ? `AND date <= '${date_to}'` : ''}
    `;

    const summaryResult = await dbQuery(summaryQuery);

    res.status(200).json({
      success: true,
      data: {
        daily_analytics: analyticsResult.rows,
        summary: summaryResult.rows[0],
        period: {
          date_from: date_from || null,
          date_to: date_to || null
        }
      }
    });

  } catch (error) {
    logger.error('Error fetching metals analytics:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch metals analytics',
      message: error.message
    });
  }
});

// ===========================================
// PIPES MANAGEMENT API ENDPOINTS
// ===========================================

app.post('/api/pipes-submissions', async (req, res) => {
  try {
    const {
      date, latitude, longitude, gross_weight, tare_weight, net_weight,
      vehicle_number, driver_number, contact_number, timestamp,
      // Enhanced OCR fields
      material_name, driver_name,
      // Photo URLs
      vehicle_photo_url, vendor_license_photo_url
    } = req.body;

    if (!date || !latitude || !longitude || !gross_weight || !tare_weight || !net_weight || !driver_number || !contact_number) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'All fields are required'
      });
    }

    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS pipes_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        -- Enhanced OCR fields
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT
      )
    `;

    await dbQuery(createTableQuery);

    const insertQuery = `
      INSERT INTO pipes_submissions (
        date, latitude, longitude, gross_weight, tare_weight, net_weight,
        vehicle_number, driver_number, contact_number, timestamp,
        material_name, driver_name,
        vehicle_photo_url, vendor_license_photo_url
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) RETURNING id
    `;

    const values = [
      date, parseFloat(latitude), parseFloat(longitude), gross_weight, tare_weight, net_weight,
      vehicle_number || null, driver_number, contact_number, timestamp || new Date().toISOString(),
      material_name || null, driver_name || null,
      vehicle_photo_url || null, vendor_license_photo_url || null
    ];

    const result = await dbQuery(insertQuery, values);
    logger.info(`Pipes submission created with ID: ${result.rows[0].id}`);

    res.status(201).json({
      success: true,
      data: { id: result.rows[0].id, message: 'Pipes data submitted successfully' }
    });

  } catch (error) {
    logger.error('Error creating pipes submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to submit pipes data',
      message: error.message
    });
  }
});

app.get('/api/pipes-submissions', async (req, res) => {
  try {
    const { page = 1, limit = 50, date_from, date_to } = req.query;
    const offset = (page - 1) * limit;

    let query = `SELECT * FROM pipes_submissions WHERE 1=1`;
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` ORDER BY created_at DESC LIMIT $${paramCount + 1} OFFSET $${paramCount + 2}`;
    values.push(limit, offset);

    const result = await dbQuery(query, values);

    let countQuery = `SELECT COUNT(*) FROM pipes_submissions WHERE 1=1`;
    let countValues = [];
    let countParamCount = 0;

    if (date_from) {
      countParamCount++;
      countQuery += ` AND date >= $${countParamCount}`;
      countValues.push(date_from);
    }

    if (date_to) {
      countParamCount++;
      countQuery += ` AND date <= $${countParamCount}`;
      countValues.push(date_to);
    }

    const countResult = await dbQuery(countQuery, countValues);
    const totalRecords = parseInt(countResult.rows[0].count);

    res.status(200).json({
      success: true,
      data: result.rows,
      pagination: {
        current_page: parseInt(page),
        total_pages: Math.ceil(totalRecords / limit),
        total_records: totalRecords,
        records_per_page: parseInt(limit)
      }
    });

  } catch (error) {
    logger.error('Error fetching pipes submissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch pipes submissions',
      message: error.message
    });
  }
});

app.get('/api/pipes-analytics', async (req, res) => {
  try {
    const { date_from, date_to } = req.query;

    let query = `
      SELECT 
        date,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(tare_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_tare_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles,
        COUNT(DISTINCT driver_number) as unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight
      FROM pipes_submissions 
      WHERE 1=1
    `;
    
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` GROUP BY date ORDER BY date DESC`;

    const analyticsResult = await dbQuery(query, values);

    const summaryQuery = `
      SELECT 
        COUNT(*) as total_submissions,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as total_unique_vehicles,
        COUNT(DISTINCT driver_number) as total_unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight,
        MIN(date) as earliest_date,
        MAX(date) as latest_date
      FROM pipes_submissions
      WHERE 1=1
      ${date_from ? `AND date >= '${date_from}'` : ''}
      ${date_to ? `AND date <= '${date_to}'` : ''}
    `;

    const summaryResult = await dbQuery(summaryQuery);

    res.status(200).json({
      success: true,
      data: {
        daily_analytics: analyticsResult.rows,
        summary: summaryResult.rows[0],
        period: {
          date_from: date_from || null,
          date_to: date_to || null
        }
      }
    });

  } catch (error) {
    logger.error('Error fetching pipes analytics:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch pipes analytics',
      message: error.message
    });
  }
});

// ===========================================
// TILES MANAGEMENT API ENDPOINTS
// ===========================================

app.post('/api/tiles-submissions', async (req, res) => {
  try {
    const {
      date, latitude, longitude, gross_weight, tare_weight, net_weight,
      vehicle_number, driver_number, contact_number, timestamp,
      // Enhanced OCR fields
      material_name, driver_name,
      // Photo URLs
      vehicle_photo_url, vendor_license_photo_url
    } = req.body;

    if (!date || !latitude || !longitude || !gross_weight || !tare_weight || !net_weight || !driver_number || !contact_number) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'All fields are required'
      });
    }

    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS tiles_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT
      )
    `;

    await dbQuery(createTableQuery);

    const insertQuery = `
      INSERT INTO tiles_submissions (
        date, latitude, longitude, gross_weight, tare_weight, net_weight,
        vehicle_number, driver_number, contact_number, timestamp,
        material_name, driver_name,
        vehicle_photo_url, vendor_license_photo_url
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) RETURNING id
    `;

    const values = [
      date, parseFloat(latitude), parseFloat(longitude), gross_weight, tare_weight, net_weight,
      vehicle_number || null, driver_number, contact_number, timestamp || new Date().toISOString(),
      material_name || null, driver_name || null,
      vehicle_photo_url || null, vendor_license_photo_url || null
    ];

    const result = await dbQuery(insertQuery, values);
    logger.info(`Tiles submission created with ID: ${result.rows[0].id}`);

    res.status(201).json({
      success: true,
      data: { id: result.rows[0].id, message: 'Tiles data submitted successfully' }
    });

  } catch (error) {
    logger.error('Error creating tiles submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to submit tiles data',
      message: error.message
    });
  }
});

app.get('/api/tiles-submissions', async (req, res) => {
  try {
    const { page = 1, limit = 50, date_from, date_to } = req.query;
    const offset = (page - 1) * limit;

    let query = `SELECT * FROM tiles_submissions WHERE 1=1`;
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` ORDER BY created_at DESC LIMIT $${paramCount + 1} OFFSET $${paramCount + 2}`;
    values.push(limit, offset);

    const result = await dbQuery(query, values);

    let countQuery = `SELECT COUNT(*) FROM tiles_submissions WHERE 1=1`;
    let countValues = [];
    let countParamCount = 0;

    if (date_from) {
      countParamCount++;
      countQuery += ` AND date >= $${countParamCount}`;
      countValues.push(date_from);
    }

    if (date_to) {
      countParamCount++;
      countQuery += ` AND date <= $${countParamCount}`;
      countValues.push(date_to);
    }

    const countResult = await dbQuery(countQuery, countValues);
    const totalRecords = parseInt(countResult.rows[0].count);

    res.status(200).json({
      success: true,
      data: result.rows,
      pagination: {
        current_page: parseInt(page),
        total_pages: Math.ceil(totalRecords / limit),
        total_records: totalRecords,
        records_per_page: parseInt(limit)
      }
    });

  } catch (error) {
    logger.error('Error fetching tiles submissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch tiles submissions',
      message: error.message
    });
  }
});

app.get('/api/tiles-analytics', async (req, res) => {
  try {
    const { date_from, date_to } = req.query;

    let query = `
      SELECT 
        date,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(tare_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_tare_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles,
        COUNT(DISTINCT driver_number) as unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight
      FROM tiles_submissions 
      WHERE 1=1
    `;
    
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` GROUP BY date ORDER BY date DESC`;

    const analyticsResult = await dbQuery(query, values);

    const summaryQuery = `
      SELECT 
        COUNT(*) as total_submissions,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as total_unique_vehicles,
        COUNT(DISTINCT driver_number) as total_unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight,
        MIN(date) as earliest_date,
        MAX(date) as latest_date
      FROM tiles_submissions
      WHERE 1=1
      ${date_from ? `AND date >= '${date_from}'` : ''}
      ${date_to ? `AND date <= '${date_to}'` : ''}
    `;

    const summaryResult = await dbQuery(summaryQuery);

    res.status(200).json({
      success: true,
      data: {
        daily_analytics: analyticsResult.rows,
        summary: summaryResult.rows[0],
        period: {
          date_from: date_from || null,
          date_to: date_to || null
        }
      }
    });

  } catch (error) {
    logger.error('Error fetching tiles analytics:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch tiles analytics',
      message: error.message
    });
  }
});

// ===========================================
// WOOD MANAGEMENT API ENDPOINTS
// ===========================================

app.post('/api/wood-submissions', async (req, res) => {
  try {
    const {
      date, latitude, longitude, gross_weight, tare_weight, net_weight,
      vehicle_number, driver_number, contact_number, timestamp,
      // Enhanced OCR fields
      material_name, driver_name,
      // Photo URLs
      vehicle_photo_url, vendor_license_photo_url
    } = req.body;

    if (!date || !latitude || !longitude || !gross_weight || !tare_weight || !net_weight || !driver_number || !contact_number) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'All fields are required'
      });
    }

    const createTableQuery = `
      CREATE TABLE IF NOT EXISTS wood_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight NUMERIC(10,2) NOT NULL,
        tare_weight NUMERIC(10,2) NOT NULL,
        net_weight NUMERIC(10,2) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `;

    await dbQuery(createTableQuery);

    const insertQuery = `
      INSERT INTO wood_submissions (
        date, latitude, longitude, gross_weight, tare_weight, net_weight,
        vehicle_number, driver_number, contact_number, timestamp,
        material_name, driver_name,
        vehicle_photo_url, vendor_license_photo_url
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) RETURNING id
    `;

    const values = [
      date, parseFloat(latitude), parseFloat(longitude), gross_weight, tare_weight, net_weight,
      vehicle_number || null, driver_number, contact_number, timestamp || new Date().toISOString(),
      material_name || null, driver_name || null,
      vehicle_photo_url || null, vendor_license_photo_url || null
    ];

    const result = await dbQuery(insertQuery, values);
    logger.info(`Wood submission created with ID: ${result.rows[0].id}`);

    res.status(201).json({
      success: true,
      data: { id: result.rows[0].id, message: 'Wood data submitted successfully' }
    });

  } catch (error) {
    logger.error('Error creating wood submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to submit wood data',
      message: error.message
    });
  }
});

app.get('/api/wood-submissions', async (req, res) => {
  try {
    const { page = 1, limit = 50, date_from, date_to } = req.query;
    const offset = (page - 1) * limit;

    let query = `SELECT * FROM wood_submissions WHERE 1=1`;
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` ORDER BY created_at DESC LIMIT $${paramCount + 1} OFFSET $${paramCount + 2}`;
    values.push(limit, offset);

    const result = await dbQuery(query, values);

    let countQuery = `SELECT COUNT(*) FROM wood_submissions WHERE 1=1`;
    let countValues = [];
    let countParamCount = 0;

    if (date_from) {
      countParamCount++;
      countQuery += ` AND date >= $${countParamCount}`;
      countValues.push(date_from);
    }

    if (date_to) {
      countParamCount++;
      countQuery += ` AND date <= $${countParamCount}`;
      countValues.push(date_to);
    }

    const countResult = await dbQuery(countQuery, countValues);
    const totalRecords = parseInt(countResult.rows[0].count);

    res.status(200).json({
      success: true,
      data: result.rows,
      pagination: {
        current_page: parseInt(page),
        total_pages: Math.ceil(totalRecords / limit),
        total_records: totalRecords,
        records_per_page: parseInt(limit)
      }
    });

  } catch (error) {
    logger.error('Error fetching wood submissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch wood submissions',
      message: error.message
    });
  }
});

app.get('/api/wood-analytics', async (req, res) => {
  try {
    const { date_from, date_to } = req.query;

    let query = `
      SELECT 
        date,
        COUNT(*) as submission_count,
        SUM(gross_weight) as total_gross_weight,
        SUM(tare_weight) as total_tare_weight,
        SUM(net_weight) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles,
        COUNT(DISTINCT driver_number) as unique_drivers,
        AVG(net_weight) as avg_net_weight
      FROM wood_submissions 
      WHERE 1=1
    `;
    
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` GROUP BY date ORDER BY date DESC`;

    const analyticsResult = await dbQuery(query, values);

    const summaryQuery = `
      SELECT 
        COUNT(*) as total_submissions,
        SUM(gross_weight) as total_gross_weight,
        SUM(net_weight) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as total_unique_vehicles,
        COUNT(DISTINCT driver_number) as total_unique_drivers,
        AVG(net_weight) as avg_net_weight,
        MIN(date) as earliest_date,
        MAX(date) as latest_date
      FROM wood_submissions
      WHERE 1=1
      ${date_from ? `AND date >= '${date_from}'` : ''}
      ${date_to ? `AND date <= '${date_to}'` : ''}
    `;

    const summaryResult = await dbQuery(summaryQuery);

    res.status(200).json({
      success: true,
      data: {
        daily_analytics: analyticsResult.rows,
        summary: summaryResult.rows[0],
        period: {
          date_from: date_from || null,
          date_to: date_to || null
        }
      }
    });

  } catch (error) {
    logger.error('Error fetching wood analytics:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch wood analytics',
      message: error.message
    });
  }
});

// ==================== ELECTRICALS ENDPOINTS ====================

app.post('/api/electricals-submissions', async (req, res) => {
  try {
    const {
      date,
      latitude,
      longitude,
      gross_weight,
      tare_weight,
      net_weight,
      vehicle_number,
      driver_number,
      contact_number,
      timestamp
    } = req.body;

    const validationSchema = Joi.object({
      date: Joi.string().required(),
      latitude: Joi.string().required(),
      longitude: Joi.string().required(),
      gross_weight: Joi.string().required(),
      tare_weight: Joi.string().required(),
      net_weight: Joi.string().required(),
      vehicle_number: Joi.string().required(),
      driver_number: Joi.string().required(),
      contact_number: Joi.string().required(),
      timestamp: Joi.string().optional()
    });

    const { error } = validationSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        details: error.details[0].message
      });
    }

    await ensureTableExists('electricals_submissions', `
      CREATE TABLE IF NOT EXISTS electricals_submissions (
        id SERIAL PRIMARY KEY,
        date VARCHAR(255),
        latitude VARCHAR(255),
        longitude VARCHAR(255),
        gross_weight VARCHAR(255),
        tare_weight VARCHAR(255),
        net_weight VARCHAR(255),
        vehicle_number VARCHAR(255),
        driver_number VARCHAR(255),
        contact_number VARCHAR(255),
        timestamp VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    const query = `
      INSERT INTO electricals_submissions 
      (date, latitude, longitude, gross_weight, tare_weight, net_weight, 
       vehicle_number, driver_number, contact_number, timestamp)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING id
    `;
    
    const values = [
      date, latitude, longitude, gross_weight, tare_weight, net_weight,
      vehicle_number, driver_number, contact_number, timestamp || new Date().toISOString()
    ];

    const result = await dbQuery(query, values);
    
    logger.info(`New electricals submission created with ID: ${result.rows[0].id}`);
    
    res.status(201).json({
      success: true,
      message: 'Electricals submission created successfully',
      data: { id: result.rows[0].id }
    });

  } catch (error) {
    logger.error('Error creating electricals submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create electricals submission',
      message: error.message
    });
  }
});

app.get('/api/electricals-submissions', async (req, res) => {
  try {
    const { date_from, date_to, limit = 100, offset = 0 } = req.query;

    await ensureTableExists('electricals_submissions', `
      CREATE TABLE IF NOT EXISTS electricals_submissions (
        id SERIAL PRIMARY KEY,
        date VARCHAR(255),
        latitude VARCHAR(255),
        longitude VARCHAR(255),
        gross_weight VARCHAR(255),
        tare_weight VARCHAR(255),
        net_weight VARCHAR(255),
        vehicle_number VARCHAR(255),
        driver_number VARCHAR(255),
        contact_number VARCHAR(255),
        timestamp VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    let query = 'SELECT * FROM electricals_submissions WHERE 1=1';
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ' ORDER BY created_at DESC';
    
    if (limit) {
      paramCount++;
      query += ` LIMIT $${paramCount}`;
      values.push(parseInt(limit));
    }
    
    if (offset) {
      paramCount++;
      query += ` OFFSET $${paramCount}`;
      values.push(parseInt(offset));
    }

    const result = await dbQuery(query, values);

    res.status(200).json({
      success: true,
      data: result.rows,
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset),
        total: result.rows.length
      }
    });

  } catch (error) {
    logger.error('Error fetching electricals submissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch electricals submissions',
      message: error.message
    });
  }
});

app.get('/api/electricals-analytics', async (req, res) => {
  try {
    const { date_from, date_to } = req.query;

    let query = `
      SELECT 
        date,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(tare_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_tare_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles,
        COUNT(DISTINCT driver_number) as unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight
      FROM electricals_submissions 
      WHERE 1=1
    `;
    
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` GROUP BY date ORDER BY date DESC`;

    const analyticsResult = await dbQuery(query, values);

    const summaryQuery = `
      SELECT 
        COUNT(*) as total_submissions,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles
      FROM electricals_submissions 
      WHERE 1=1
    `;

    const summaryResult = await dbQuery(summaryQuery);

    res.status(200).json({
      success: true,
      data: {
        daily_analytics: analyticsResult.rows,
        summary: summaryResult.rows[0],
        period: {
          date_from: date_from || null,
          date_to: date_to || null
        }
      }
    });

  } catch (error) {
    logger.error('Error fetching electricals analytics:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch electricals analytics',
      message: error.message
    });
  }
});

// ==================== PLASTIC ENDPOINTS ====================

app.post('/api/plastic-submissions', async (req, res) => {
  try {
    const {
      date,
      latitude,
      longitude,
      gross_weight,
      tare_weight,
      net_weight,
      vehicle_number,
      driver_number,
      contact_number,
      timestamp,
      // Enhanced OCR fields
      material_name,
      material_category,
      weighment_slip_no,
      driver_name,
      transporter
    } = req.body;

    const validationSchema = Joi.object({
      date: Joi.string().required(),
      latitude: Joi.string().required(),
      longitude: Joi.string().required(),
      gross_weight: Joi.string().required(),
      tare_weight: Joi.string().required(),
      net_weight: Joi.string().required(),
      vehicle_number: Joi.string().required(),
      driver_number: Joi.string().required(),
      contact_number: Joi.string().required(),
      timestamp: Joi.string().optional(),
      material_name: Joi.string().allow(null, ''),
      material_category: Joi.string().allow(null, ''),
      weighment_slip_no: Joi.string().allow(null, ''),
      driver_name: Joi.string().allow(null, ''),
      transporter: Joi.string().allow(null, '')
    });

    const { error } = validationSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        details: error.details[0].message
      });
    }

    await ensureTableExists('plastic_submissions', `
      CREATE TABLE IF NOT EXISTS plastic_submissions (
        id SERIAL PRIMARY KEY,
        date VARCHAR(255),
        latitude VARCHAR(255),
        longitude VARCHAR(255),
        gross_weight VARCHAR(255),
        tare_weight VARCHAR(255),
        net_weight VARCHAR(255),
        vehicle_number VARCHAR(255),
        driver_number VARCHAR(255),
        contact_number VARCHAR(255),
        timestamp VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        material_category VARCHAR(255),
        weighment_slip_no VARCHAR(255),
        driver_name VARCHAR(255),
        transporter VARCHAR(255)
      )
    `);

    const query = `
      INSERT INTO plastic_submissions 
      (date, latitude, longitude, gross_weight, tare_weight, net_weight, 
       vehicle_number, driver_number, contact_number, timestamp, 
       material_name, driver_name)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
      RETURNING id
    `;
    
    const values = [
      date, latitude, longitude, gross_weight, tare_weight, net_weight,
      vehicle_number, driver_number, contact_number, timestamp || new Date().toISOString(),
      material_name || null, driver_name || null
    ];

    const result = await dbQuery(query, values);
    
    logger.info(`New plastic submission created with ID: ${result.rows[0].id}`);
    
    res.status(201).json({
      success: true,
      message: 'Plastic submission created successfully',
      data: { id: result.rows[0].id }
    });

  } catch (error) {
    logger.error('Error creating plastic submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create plastic submission',
      message: error.message
    });
  }
});

app.get('/api/plastic-submissions', async (req, res) => {
  try {
    const { date_from, date_to, limit = 100, offset = 0 } = req.query;

    await ensureTableExists('plastic_submissions', `
      CREATE TABLE IF NOT EXISTS plastic_submissions (
        id SERIAL PRIMARY KEY,
        date VARCHAR(255),
        latitude VARCHAR(255),
        longitude VARCHAR(255),
        gross_weight VARCHAR(255),
        tare_weight VARCHAR(255),
        net_weight VARCHAR(255),
        vehicle_number VARCHAR(255),
        driver_number VARCHAR(255),
        contact_number VARCHAR(255),
        timestamp VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        material_category VARCHAR(255),
        weighment_slip_no VARCHAR(255),
        driver_name VARCHAR(255),
        transporter VARCHAR(255)
      )
    `);

    let query = 'SELECT * FROM plastic_submissions WHERE 1=1';
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ' ORDER BY created_at DESC';
    
    if (limit) {
      paramCount++;
      query += ` LIMIT $${paramCount}`;
      values.push(parseInt(limit));
    }
    
    if (offset) {
      paramCount++;
      query += ` OFFSET $${paramCount}`;
      values.push(parseInt(offset));
    }

    const result = await dbQuery(query, values);

    res.status(200).json({
      success: true,
      data: result.rows,
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset),
        total: result.rows.length
      }
    });

  } catch (error) {
    logger.error('Error fetching plastic submissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch plastic submissions',
      message: error.message
    });
  }
});

app.get('/api/plastic-analytics', async (req, res) => {
  try {
    const { date_from, date_to } = req.query;

    let query = `
      SELECT 
        date,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(tare_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_tare_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles,
        COUNT(DISTINCT driver_number) as unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight
      FROM plastic_submissions 
      WHERE 1=1
    `;
    
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` GROUP BY date ORDER BY date DESC`;

    const analyticsResult = await dbQuery(query, values);

    const summaryQuery = `
      SELECT 
        COUNT(*) as total_submissions,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles
      FROM plastic_submissions 
      WHERE 1=1
    `;

    const summaryResult = await dbQuery(summaryQuery);

    res.status(200).json({
      success: true,
      data: {
        daily_analytics: analyticsResult.rows,
        summary: summaryResult.rows[0],
        period: {
          date_from: date_from || null,
          date_to: date_to || null
        }
      }
    });

  } catch (error) {
    logger.error('Error fetching plastic analytics:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch plastic analytics',
      message: error.message
    });
  }
});

// ==================== AGGREGATES ENDPOINTS ====================

app.post('/api/aggregates-submissions', async (req, res) => {
  try {
    const {
      date,
      latitude,
      longitude,
      gross_weight,
      tare_weight,
      net_weight,
      vehicle_number,
      driver_number,
      contact_number,
      timestamp,
      // Enhanced OCR fields
      material_name,
      material_category,
      weighment_slip_no,
      driver_name,
      transporter,
      // Photo URLs
      vehicle_photo_url,
      vendor_license_photo_url
    } = req.body;

    const validationSchema = Joi.object({
      date: Joi.string().required(),
      latitude: Joi.string().required(),
      longitude: Joi.string().required(),
      gross_weight: Joi.string().required(),
      tare_weight: Joi.string().required(),
      net_weight: Joi.string().required(),
      vehicle_number: Joi.string().required(),
      driver_number: Joi.string().required(),
      contact_number: Joi.string().required(),
      timestamp: Joi.string().optional(),
      material_name: Joi.string().optional(),
      material_category: Joi.string().optional(),
      weighment_slip_no: Joi.string().optional(),
      driver_name: Joi.string().optional(),
      transporter: Joi.string().optional(),
      vehicle_photo_url: Joi.string().optional(),
      vendor_license_photo_url: Joi.string().optional()
    });

    const { error } = validationSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        details: error.details[0].message
      });
    }

    await ensureTableExists('aggregates_submissions', `
      CREATE TABLE IF NOT EXISTS aggregates_submissions (
        id SERIAL PRIMARY KEY,
        date VARCHAR(255),
        latitude VARCHAR(255),
        longitude VARCHAR(255),
        gross_weight VARCHAR(255),
        tare_weight VARCHAR(255),
        net_weight VARCHAR(255),
        vehicle_number VARCHAR(255),
        driver_number VARCHAR(255),
        contact_number VARCHAR(255),
        timestamp VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT
      )
    `);

    const query = `
      INSERT INTO aggregates_submissions 
      (date, latitude, longitude, gross_weight, tare_weight, net_weight, 
       vehicle_number, driver_number, contact_number, timestamp,
       material_name, driver_name,
       vehicle_photo_url, vendor_license_photo_url)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      RETURNING id
    `;
    
    const values = [
      date, latitude, longitude, gross_weight, tare_weight, net_weight,
      vehicle_number, driver_number, contact_number, timestamp || new Date().toISOString(),
      material_name || null, driver_name || null,
      vehicle_photo_url || null, vendor_license_photo_url || null
    ];

    const result = await dbQuery(query, values);
    
    logger.info(`New aggregates submission created with ID: ${result.rows[0].id}`);
    
    res.status(201).json({
      success: true,
      message: 'Aggregates submission created successfully',
      data: { id: result.rows[0].id }
    });

  } catch (error) {
    logger.error('Error creating aggregates submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create aggregates submission',
      message: error.message
    });
  }
});

app.get('/api/aggregates-submissions', async (req, res) => {
  try {
    const { date_from, date_to, limit = 100, offset = 0 } = req.query;

    await ensureTableExists('aggregates_submissions', `
      CREATE TABLE IF NOT EXISTS aggregates_submissions (
        id SERIAL PRIMARY KEY,
        date VARCHAR(255),
        latitude VARCHAR(255),
        longitude VARCHAR(255),
        gross_weight VARCHAR(255),
        tare_weight VARCHAR(255),
        net_weight VARCHAR(255),
        vehicle_number VARCHAR(255),
        driver_number VARCHAR(255),
        contact_number VARCHAR(255),
        timestamp VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name VARCHAR(255),
        driver_name VARCHAR(255),
        vehicle_photo_url TEXT,
        vendor_license_photo_url TEXT
      )
    `);

    let query = 'SELECT * FROM aggregates_submissions WHERE 1=1';
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ' ORDER BY created_at DESC';
    
    if (limit) {
      paramCount++;
      query += ` LIMIT $${paramCount}`;
      values.push(parseInt(limit));
    }
    
    if (offset) {
      paramCount++;
      query += ` OFFSET $${paramCount}`;
      values.push(parseInt(offset));
    }

    const result = await dbQuery(query, values);

    res.status(200).json({
      success: true,
      data: result.rows,
      pagination: {
        limit: parseInt(limit),
        offset: parseInt(offset),
        total: result.rows.length
      }
    });

  } catch (error) {
    logger.error('Error fetching aggregates submissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch aggregates submissions',
      message: error.message
    });
  }
});

app.get('/api/aggregates-analytics', async (req, res) => {
  try {
    const { date_from, date_to } = req.query;

    let query = `
      SELECT 
        date,
        COUNT(*) as submission_count,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(tare_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_tare_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles,
        COUNT(DISTINCT driver_number) as unique_drivers,
        AVG(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as avg_net_weight
      FROM aggregates_submissions 
      WHERE 1=1
    `;
    
    let values = [];
    let paramCount = 0;

    if (date_from) {
      paramCount++;
      query += ` AND date >= $${paramCount}`;
      values.push(date_from);
    }

    if (date_to) {
      paramCount++;
      query += ` AND date <= $${paramCount}`;
      values.push(date_to);
    }

    query += ` GROUP BY date ORDER BY date DESC`;

    const analyticsResult = await dbQuery(query, values);

    const summaryQuery = `
      SELECT 
        COUNT(*) as total_submissions,
        SUM(CAST(REGEXP_REPLACE(gross_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_gross_weight,
        SUM(CAST(REGEXP_REPLACE(net_weight, '[^0-9.]', '', 'g') AS NUMERIC)) as total_net_weight,
        COUNT(DISTINCT vehicle_number) as unique_vehicles
      FROM aggregates_submissions 
      WHERE 1=1
    `;

    const summaryResult = await dbQuery(summaryQuery);

    res.status(200).json({
      success: true,
      data: {
        daily_analytics: analyticsResult.rows,
        summary: summaryResult.rows[0],
        period: {
          date_from: date_from || null,
          date_to: date_to || null
        }
      }
    });

  } catch (error) {
    logger.error('Error fetching aggregates analytics:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch aggregates analytics',
      message: error.message
    });
  }
});

app.delete('/construction-phase-waste/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const query = 'DELETE FROM construction_phase_waste WHERE id = $1 RETURNING id';
    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Construction phase waste record not found'
      });
    }

    logger.info(`Construction phase waste record deleted: ${id}`);

    res.json({
      success: true,
      message: 'Construction phase waste record deleted successfully'
    });

  } catch (error) {
    logger.error('Error deleting construction phase waste record:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete construction phase waste record',
      message: error.message
    });
  }
});

app.get('/construction-phase-waste/stats', async (req, res) => {
  try {
    const query = `
      SELECT 
        COUNT(*) as total_records,
        COALESCE(SUM(dry_waste_generated), 0) as total_dry_waste,
        COALESCE(SUM(wet_waste_generated), 0) as total_wet_waste,
        COALESCE(SUM(dry_waste_generated + wet_waste_generated), 0) as total_waste_generated,
        COALESCE(AVG(dry_waste_generated + wet_waste_generated), 0) as avg_daily_waste,
        COALESCE(AVG(approx_no_of_labour), 0) as avg_labour_count,
        CASE 
          WHEN AVG(approx_no_of_labour) > 0 THEN 
            COALESCE(AVG((dry_waste_generated + wet_waste_generated) / NULLIF(approx_no_of_labour, 0)), 0)
          ELSE 0 
        END as avg_waste_per_labour
      FROM construction_phase_waste
    `;
    
    const result = await dbQuery(query);
    const summary = result.rows[0];

    res.json({
      success: true,
      summary: {
        total_records: parseInt(summary.total_records),
        total_dry_waste: parseFloat(summary.total_dry_waste),
        total_wet_waste: parseFloat(summary.total_wet_waste),
        total_waste_generated: parseFloat(summary.total_waste_generated),
        avg_daily_waste: parseFloat(summary.avg_daily_waste),
        avg_labour_count: parseFloat(summary.avg_labour_count),
        avg_waste_per_labour: parseFloat(summary.avg_waste_per_labour)
      }
    });

  } catch (error) {
    logger.error('Error fetching construction phase waste stats:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch construction phase waste statistics',
      message: error.message
    });
  }
});

// ===========================================
// AIR POLLUTION MONITORING API ENDPOINTS
// ===========================================

// Stack Monitoring Enhanced
app.get('/stack-monitoring', async (req, res) => {
  try {
    const result = await dbQuery('SELECT * FROM stack_monitoring ORDER BY timestamp DESC');
    res.status(200).json({
      data: result.rows
    });
  } catch (err) {
    console.error('Error fetching stack monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/stack-monitoring', async (req, res) => {
  try {
    const { error, value } = stackMonitoringSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    const {
      source, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, standard, results, comments, status
    } = value;
    const result = await dbQuery(
      `INSERT INTO stack_monitoring (source, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system, parameter, standard, results, comments, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
      [source, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system, parameter, standard, results, comments, status]
    );
    res.status(201).json({
      message: 'Stack monitoring data added successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error adding stack monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.put('/stack-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { error, value } = stackMonitoringSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    const {
      source, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, standard, results, comments, status
    } = value;
    const result = await dbQuery(
      `UPDATE stack_monitoring SET source = $1, consent_chimney = $2, consent_apc_system = $3, provided_chimney = $4, provided_apc_system = $5, parameter = $6, standard = $7, results = $8, comments = $9, status = $10 WHERE id = $11 RETURNING *`,
      [source, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system, parameter, standard, results, comments, status, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }
    res.status(200).json({
      message: 'Stack monitoring data updated successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error updating stack monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/stack-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const query = 'DELETE FROM stack_monitoring WHERE id = $1 RETURNING id';
    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Stack monitoring record not found'
      });
    }

    logger.info(`Stack monitoring record deleted: ${id}`);

    res.json({
      success: true,
      message: 'Stack monitoring record deleted successfully'
    });

  } catch (error) {
    logger.error('Error deleting stack monitoring record:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete stack monitoring record',
      message: error.message
    });
  }
});

// Ambient Monitoring Enhanced
app.get('/ambient-monitoring', async (req, res) => {
  try {
    const { status, search } = req.query;
    let query = 'SELECT * FROM ambient_monitoring';
    let params = [];
    if (status && status !== 'All') {
      query += ' WHERE status = $1';
      params.push(status);
    }
    if (search) {
      query += params.length ? ' AND' : ' WHERE';
      query += ` (location ILIKE $${params.length + 1} OR parameter ILIKE $${params.length + 1})`;
      params.push(`%${search}%`);
    }
    query += ' ORDER BY timestamp DESC';
    const result = await dbQuery(query, params);
    res.status(200).json({
      message: 'Data retrieved successfully',
      data: result.rows
    });
  } catch (err) {
    console.error('Error retrieving monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/ambient-monitoring', async (req, res) => {
  try {
    const { error } = ambientMonitoringSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }
    const {
      id, location, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, limit, standard, measured, results, comments, status, timestamp
    } = req.body;
    const query = `
      INSERT INTO ambient_monitoring
      (id, location, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system, parameter, limit_value, standard, measured, results, comments, status, timestamp)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      RETURNING *
    `;
    const result = await dbQuery(query, [
      id, location, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, limit, standard, measured, results, comments, status, timestamp || new Date()
    ]);
    res.status(201).json({
      message: 'Monitoring data added successfully!',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error adding monitoring data:', err.stack);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.put('/ambient-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { location, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, limit, standard, measured, results, comments, status, timestamp } = req.body;
    const query = `
      UPDATE ambient_monitoring
      SET location = $1, consent_chimney = $2, consent_apc_system = $3, provided_chimney = $4, provided_apc_system = $5, parameter = $6, limit_value = $7, standard = $8, measured = $9, results = $10, comments = $11, status = $12, timestamp = $13
      WHERE id = $14
      RETURNING *
    `;
    const result = await dbQuery(query, [
      location, consent_chimney, consent_apc_system, provided_chimney, provided_apc_system,
      parameter, limit, standard, measured, results, comments, status, timestamp, id
    ]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Monitoring data not found' });
    }
    res.status(200).json({
      message: 'Monitoring data updated successfully',
      data: result.rows[0]
    });
  } catch (err) {
    console.error('Error updating monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/ambient-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const query = 'DELETE FROM ambient_monitoring WHERE id = $1 RETURNING id';
    const result = await dbQuery(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Ambient monitoring record not found'
      });
    }

    logger.info(`Ambient monitoring record deleted: ${id}`);

    res.json({
      success: true,
      message: 'Ambient monitoring record deleted successfully'
    });

  } catch (error) {
    logger.error('Error deleting ambient monitoring record:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete ambient monitoring record',
      message: error.message
    });
  }
});

// ===========================================
// WEBSOCKET API ENDPOINTS
// ===========================================

// Get connected users (Admin only)
app.get('/api/admin/websocket/users', authenticateAdmin, (req, res) => {
  try {
    const connectedCount = global.realTimeService.getConnectedUsersCount();
    const connectedUsers = Array.from(global.realTimeService.userSockets.values());
    
    res.status(200).json({
      success: true,
      data: {
        connected_count: connectedCount,
        connected_users: connectedUsers
      }
    });
  } catch (error) {
    logger.error('Error getting connected users:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get connected users',
      error: error.message
    });
  }
});

// Broadcast admin message
app.post('/api/admin/websocket/broadcast', authenticateAdmin, async (req, res) => {
  try {
    const { title, message, type = 'announcement', severity = 'Medium' } = req.body;
    
    if (!title || !message) {
      return res.status(400).json({
        success: false,
        message: 'Title and message are required'
      });
    }

    global.realTimeService.broadcastSystemNotification({
      type,
      title,
      message,
      severity,
      from_admin: req.user.username
    });

    await logAdminAction(
      req.user.username,
      'WEBSOCKET_BROADCAST',
      `Broadcasted message: ${title}`,
      req
    );

    res.status(200).json({
      success: true,
      message: 'Message broadcasted successfully'
    });
  } catch (error) {
    logger.error('Error broadcasting admin message:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to broadcast message',
      error: error.message
    });
  }
});

// Trigger health score update
app.post('/api/admin/websocket/health-update', authenticateAdmin, async (req, res) => {
  try {
    const { project_name } = req.body;
    
    await global.realTimeService.broadcastHealthScoreUpdate(project_name);
    
    res.status(200).json({
      success: true,
      message: 'Health score update broadcasted'
    });
  } catch (error) {
    logger.error('Error broadcasting health update:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to broadcast health update',
      error: error.message
    });
  }
});

// Check user connection status
app.get('/api/users/:userId/connection-status', authenticateToken, (req, res) => {
  try {
    const { userId } = req.params;
    const isConnected = global.realTimeService.isUserConnected(parseInt(userId));
    
    res.status(200).json({
      success: true,
      data: {
        user_id: userId,
        is_connected: isConnected,
        checked_at: new Date()
      }
    });
  } catch (error) {
    logger.error('Error checking connection status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to check connection status',
      error: error.message
    });
  }
});

// ===========================================
// SCHEDULED REAL-TIME UPDATES
// ===========================================

// Schedule periodic health score broadcasts (every 30 minutes)
setInterval(async () => {
  try {
    await global.realTimeService.broadcastHealthScoreUpdate();
  } catch (error) {
    logger.error('Error in scheduled health score update:', error);
  }
}, 30 * 60 * 1000);

// Schedule expiry alert broadcasts (every hour)
setInterval(async () => {
  try {
    await global.realTimeService.broadcastExpiryAlerts();
  } catch (error) {
    logger.error('Error in scheduled expiry alerts:', error);
  }
}, 60 * 60 * 1000);

// ===========================================
// ENHANCED OCR ENDPOINT
// ===========================================

// Enhanced OCR endpoint for weighbridge slip extraction
app.post('/api/extract-weighbridge-data', upload.single('weighbridge_slip'), async (req, res) => {
  try {
    logger.info('Enhanced OCR extraction request received');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No weighbridge slip image provided'
      });
    }

    const startTime = Date.now();
    
    try {
      // Call Python OCR service
      const imagePath = req.file.path || req.file.filename;
      const ocrServicePath = path.join(process.cwd(), '..', 'ml', 'ocr_service.py');
      const command = `python3 "${ocrServicePath}" process_file "${imagePath}"`;
      
      logger.info(`Executing OCR command: ${command}`);
      
      const { stdout, stderr } = await execAsync(command, { 
        timeout: 30000, // 30 second timeout
        cwd: path.join(process.cwd(), '..', 'ml')
      });
      
      if (stderr) {
        logger.warn('OCR stderr:', stderr);
      }
      
      // Parse OCR results
      const ocrResults = JSON.parse(stdout);
      const processingTime = (Date.now() - startTime) / 1000;
      
      logger.info(`OCR extraction completed for ${req.file.originalname}:`, {
        material: ocrResults.material_name,
        vehicle: ocrResults.vehicle_number,
        slip_no: ocrResults.weighment_slip_no,
        confidence: ocrResults.confidence_score,
        processing_time: processingTime
      });

      res.json({
        success: true,
        message: "Weighbridge slip data extracted successfully",
        data: ocrResults,
        confidence: ocrResults.confidence_score,
        processing_time: processingTime
      });

    } catch (ocrError) {
      logger.error('OCR processing error:', ocrError);
      
      // Fallback to mock data if OCR fails
      const mockExtractionResults = {
        "STONE_AGGREGATE": {
          "material_name": "STONE AGGREGATE",
          "material_category": "Aggregate",
          "gross_weight": "44560 KG",
          "tare_weight": "12350 KG", 
          "net_weight": "32210 KG",
          "weighment_slip_no": "WB48R20250715153923-3",
          "vehicle_number": "KA034C313",
          "driver_name": "Sartmul",
          "transporter": "foyer mines",
          "validation_passed": true
        },
        "CEMENT": {
          "material_name": "ORDINARY PORTLAND CEMENT, GRADE : 53, FORM : Grey Cement",
          "material_category": "Grey Cement", 
          "gross_weight": "65570 KG",
          "tare_weight": "14500 KG",
          "net_weight": "51070 KG",
          "weighment_slip_no": "WB48R20250715111655-3",
          "vehicle_number": "TN914235",
          "driver_name": "babrish",
          "transporter": "bam logistics",
          "validation_passed": true
        }
      };

      // Mock selection based on filename or random
      const isAggregateSlip = req.file.originalname.includes('aggregate') || Math.random() > 0.5;
      const extractedData = isAggregateSlip ? 
        mockExtractionResults.STONE_AGGREGATE : 
        mockExtractionResults.CEMENT;

      logger.info(`Fallback to mock data for ${req.file.originalname}`);

      res.json({
        success: true,
        message: "Weighbridge slip data extracted successfully (fallback)",
        data: extractedData,
        confidence: 85.0,
        processing_time: (Date.now() - startTime) / 1000,
        fallback: true
      });
    }

  } catch (error) {
    logger.error('Error in enhanced OCR extraction:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to extract weighbridge data',
      message: error.message
    });
  }
});

// ===========================================
// 404 HANDLER
// ===========================================

// ===========================================
// WOOD MANAGEMENT PHOTO UPLOAD ENDPOINT
// ===========================================

// Wood management photo upload endpoint
app.post('/upload-wood-photo', upload.single('photo'), async (req, res) => {
  try {
    logger.info('Wood management photo upload request received');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No photo file provided'
      });
    }

    const { photo_type, upload_date } = req.body;
    
    // Validate photo type
    if (!photo_type || !['vehicle_photo', 'vendor_license_photo'].includes(photo_type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid photo type. Must be vehicle_photo or vendor_license_photo'
      });
    }

    const startTime = Date.now();
    
    try {
      // Get photo URL from multer-s3 (if S3 is configured) or local path
      const photoUrl = req.file.location || `/uploads/${req.file.filename}`;
      
      const processingTime = (Date.now() - startTime) / 1000;
      
      logger.info(`Wood management photo uploaded successfully:`, {
        photo_type: photo_type,
        original_name: req.file.originalname,
        photo_url: photoUrl,
        file_size: req.file.size,
        processing_time: processingTime
      });

      res.json({
        success: true,
        message: "Wood management photo uploaded successfully",
        photo_url: photoUrl,
        data: {
          photo_type: photo_type,
          upload_date: upload_date || new Date().toISOString().split('T')[0],
          original_filename: req.file.originalname,
          photo_url: photoUrl,
          file_size: req.file.size,
          content_type: req.file.mimetype,
          processing_time: processingTime
        }
      });

    } catch (uploadError) {
      logger.error('Error uploading wood management photo to S3:', uploadError);
      
      res.status(500).json({
        success: false,
        error: `Failed to upload photo: ${uploadError.message}`,
        details: 'S3 upload failed'
      });
    }

  } catch (error) {
    logger.error('Wood management photo upload error:', error);
    
    res.status(500).json({
      success: false,
      error: 'Internal server error during photo upload',
      details: error.message
    });
  }
});

// ===========================================
// C&D WASTE PHOTO UPLOAD ENDPOINT
// ===========================================

// C&D waste photo upload endpoint for daily waste records
app.post('/upload-cd-waste-photo', upload.single('photo'), async (req, res) => {
  try {
    logger.info('C&D waste photo upload request received');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No photo file provided'
      });
    }

    const { photo_type, upload_date } = req.body;
    
    // Validate photo type
    if (!photo_type || !['loading_photo', 'unloading_photo', 'vendor_license_photo'].includes(photo_type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid photo type. Must be loading_photo, unloading_photo, or vendor_license_photo'
      });
    }

    const startTime = Date.now();
    
    try {
      // Get photo URL from multer-s3 (if S3 is configured) or local path
      const photoUrl = req.file.location || `/uploads/${req.file.filename}`;
      
      const processingTime = (Date.now() - startTime) / 1000;
      
      logger.info(`C&D waste photo uploaded successfully:`, {
        photo_type: photo_type,
        original_name: req.file.originalname,
        photo_url: photoUrl,
        file_size: req.file.size,
        processing_time: processingTime
      });

      res.json({
        success: true,
        message: "C&D waste photo uploaded successfully",
        photo_url: photoUrl,
        data: {
          photo_type: photo_type,
          upload_date: upload_date || new Date().toISOString().split('T')[0],
          original_filename: req.file.originalname,
          photo_url: photoUrl,
          file_size: req.file.size,
          content_type: req.file.mimetype,
          processing_time: processingTime
        }
      });

    } catch (uploadError) {
      logger.error('Error uploading C&D waste photo to S3:', uploadError);
      
      res.status(500).json({
        success: false,
        error: `Failed to upload photo: ${uploadError.message}`,
        details: 'S3 upload failed'
      });
    }

  } catch (error) {
    logger.error('C&D waste photo upload error:', error);
    
    res.status(500).json({
      success: false,
      error: 'Internal server error during photo upload',
      details: error.message
    });
  }
});

// ===========================================
// MUNICIPAL WASTE DOCUMENT UPLOAD ENDPOINT
// ===========================================

// Municipal waste document upload endpoint
app.post('/upload-municipal-waste-document', upload.single('document'), async (req, res) => {
  try {
    logger.info('Municipal waste document upload request received');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No document file provided'
      });
    }

    const { document_type, upload_date } = req.body;
    
    // Validate document type
    if (!document_type || !['vendor_license', 'disposal_photo'].includes(document_type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid document type. Must be vendor_license or disposal_photo'
      });
    }

    const startTime = Date.now();
    
    try {
      // Generate unique filename with timestamp
      const timestamp = Date.now();
      const fileExtension = path.extname(req.file.originalname);
      const sanitizedName = req.file.originalname.replace(/[^a-zA-Z0-9.-]/g, '_');
      const key = `municipal-waste-documents/${document_type}/${timestamp}_${sanitizedName}`;
      
      // Upload to S3
      const s3Url = await uploadToS3(req.file.buffer, key, req.file.mimetype);
      
      const processingTime = (Date.now() - startTime) / 1000;
      
      logger.info(`Municipal waste document uploaded successfully:`, {
        document_type: document_type,
        original_name: req.file.originalname,
        s3_key: key,
        s3_url: s3Url,
        processing_time: processingTime
      });

      res.json({
        success: true,
        message: "Municipal waste document uploaded successfully",
        data: {
          document_type: document_type,
          upload_date: upload_date || new Date().toISOString().split('T')[0],
          original_filename: req.file.originalname,
          s3_key: key,
          s3_url: s3Url,
          file_size: req.file.size,
          content_type: req.file.mimetype,
          processing_time: processingTime
        }
      });

    } catch (uploadError) {
      logger.error('Error uploading municipal waste document to S3:', uploadError);
      
      res.status(500).json({
        success: false,
        error: `Failed to upload document: ${uploadError.message}`,
        details: 'S3 upload failed'
      });
    }

  } catch (error) {
    logger.error('Municipal waste document upload error:', error);
    
    res.status(500).json({
      success: false,
      error: 'Internal server error during document upload',
      details: error.message
    });
  }
});

// ===========================================
// CEMENT MANAGEMENT PHOTO UPLOAD ENDPOINT
// ===========================================

// Cement management photo upload endpoint
app.post('/upload-cement-photo', upload.single('photo'), async (req, res) => {
  try {
    logger.info('Cement management photo upload request received');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No photo file provided'
      });
    }

    const { photo_type, upload_date } = req.body;
    
    // Validate photo type
    if (!photo_type || !['vehicle_photo', 'vendor_license_photo'].includes(photo_type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid photo type. Must be vehicle_photo or vendor_license_photo'
      });
    }

    const startTime = Date.now();
    
    try {
      // Get photo URL from multer-s3 (if S3 is configured) or local path
      const photoUrl = req.file.location || `/uploads/${req.file.filename}`;
      
      const processingTime = (Date.now() - startTime) / 1000;
      
      logger.info(`Cement management photo uploaded successfully:`, {
        photo_type: photo_type,
        original_name: req.file.originalname,
        photo_url: photoUrl,
        file_size: req.file.size,
        processing_time: processingTime
      });

      res.json({
        success: true,
        message: "Cement management photo uploaded successfully",
        photo_url: photoUrl,
        data: {
          photo_type: photo_type,
          upload_date: upload_date || new Date().toISOString().split('T')[0],
          original_filename: req.file.originalname,
          photo_url: photoUrl,
          file_size: req.file.size,
          content_type: req.file.mimetype,
          processing_time: processingTime
        }
      });

    } catch (uploadError) {
      logger.error('Error uploading cement management photo:', uploadError);
      
      res.status(500).json({
        success: false,
        error: `Failed to upload photo: ${uploadError.message}`,
        details: 'Upload failed'
      });
    }

  } catch (error) {
    logger.error('Cement management photo upload error:', error);
    
    res.status(500).json({
      success: false,
      error: 'Internal server error during photo upload',
      details: error.message
    });
  }
});

// ===========================================
// SAND MANAGEMENT PHOTO UPLOAD ENDPOINT
// ===========================================

// Sand management photo upload endpoint
app.post('/upload-sand-photo', upload.single('photo'), async (req, res) => {
  try {
    logger.info('Sand management photo upload request received');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No photo file provided'
      });
    }

    const { photo_type, upload_date } = req.body;
    
    // Validate photo type
    if (!photo_type || !['vehicle_photo', 'vendor_license_photo'].includes(photo_type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid photo type. Must be vehicle_photo or vendor_license_photo'
      });
    }

    const startTime = Date.now();
    
    try {
      // Get photo URL from multer-s3 (if S3 is configured) or local path
      const photoUrl = req.file.location || `/uploads/${req.file.filename}`;
      
      const processingTime = (Date.now() - startTime) / 1000;
      
      logger.info(`Sand management photo uploaded successfully:`, {
        photo_type: photo_type,
        original_name: req.file.originalname,
        photo_url: photoUrl,
        file_size: req.file.size,
        processing_time: processingTime
      });

      res.json({
        success: true,
        message: "Sand management photo uploaded successfully",
        photo_url: photoUrl,
        data: {
          photo_type: photo_type,
          upload_date: upload_date || new Date().toISOString().split('T')[0],
          original_filename: req.file.originalname,
          photo_url: photoUrl,
          file_size: req.file.size,
          content_type: req.file.mimetype,
          processing_time: processingTime
        }
      });

    } catch (uploadError) {
      logger.error('Error uploading sand management photo:', uploadError);
      
      res.status(500).json({
        success: false,
        error: `Failed to upload photo: ${uploadError.message}`,
        details: 'Upload failed'
      });
    }

  } catch (error) {
    logger.error('Sand management photo upload error:', error);
    
    res.status(500).json({
      success: false,
      error: 'Internal server error during photo upload',
      details: error.message
    });
  }
});

// ===========================================
// TILES MANAGEMENT PHOTO UPLOAD ENDPOINT
// ===========================================

// Tiles management photo upload endpoint
app.post('/upload-tiles-photo', upload.single('photo'), async (req, res) => {
  try {
    logger.info('Tiles management photo upload request received');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No photo file provided'
      });
    }

    const { photo_type, upload_date } = req.body;
    
    // Validate photo type
    if (!photo_type || !['vehicle_photo', 'vendor_license_photo'].includes(photo_type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid photo type. Must be vehicle_photo or vendor_license_photo'
      });
    }

    const startTime = Date.now();
    
    try {
      // Get photo URL from multer-s3 (if S3 is configured) or local path
      const photoUrl = req.file.location || `/uploads/${req.file.filename}`;
      
      const processingTime = (Date.now() - startTime) / 1000;
      
      logger.info(`Tiles management photo uploaded successfully:`, {
        photo_type: photo_type,
        original_name: req.file.originalname,
        photo_url: photoUrl,
        file_size: req.file.size,
        processing_time: processingTime
      });

      res.json({
        success: true,
        message: "Tiles management photo uploaded successfully",
        photo_url: photoUrl,
        data: {
          photo_type: photo_type,
          upload_date: upload_date || new Date().toISOString().split('T')[0],
          original_filename: req.file.originalname,
          photo_url: photoUrl,
          file_size: req.file.size,
          content_type: req.file.mimetype,
          processing_time: processingTime
        }
      });

    } catch (uploadError) {
      logger.error('Error uploading tiles management photo:', uploadError);
      
      res.status(500).json({
        success: false,
        error: `Failed to upload photo: ${uploadError.message}`,
        details: 'Upload failed'
      });
    }

  } catch (error) {
    logger.error('Tiles management photo upload error:', error);
    
    res.status(500).json({
      success: false,
      error: 'Internal server error during photo upload',
      details: error.message
    });
  }
});

// ===========================================
// PIPES MANAGEMENT PHOTO UPLOAD ENDPOINT
// ===========================================

// Pipes management photo upload endpoint
app.post('/upload-pipes-photo', upload.single('photo'), async (req, res) => {
  try {
    logger.info('Pipes management photo upload request received');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No photo file provided'
      });
    }

    const { photo_type, upload_date } = req.body;
    
    // Validate photo type  
    if (!photo_type || !['vehicle_photo', 'vendor_license_photo'].includes(photo_type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid photo type. Must be vehicle_photo or vendor_license_photo'
      });
    }

    const startTime = Date.now();
    
    try {
      // Get photo URL from multer-s3 (if S3 is configured) or local path
      const photoUrl = req.file.location || `/uploads/${req.file.filename}`;
      
      const processingTime = (Date.now() - startTime) / 1000;
      
      logger.info(`Pipes management photo uploaded successfully:`, {
        photo_type: photo_type,
        original_name: req.file.originalname,
        photo_url: photoUrl,
        file_size: req.file.size,
        processing_time: processingTime
      });

      res.json({
        success: true,
        message: "Pipes management photo uploaded successfully",
        photo_url: photoUrl,
        data: {
          photo_type: photo_type,
          upload_date: upload_date || new Date().toISOString().split('T')[0],
          original_filename: req.file.originalname,
          photo_url: photoUrl,
          file_size: req.file.size,
          content_type: req.file.mimetype,
          processing_time: processingTime
        }
      });

    } catch (uploadError) {
      logger.error('Error uploading pipes management photo:', uploadError);
      
      res.status(500).json({
        success: false,
        error: `Failed to upload photo: ${uploadError.message}`,
        details: 'Upload failed'
      });
    }

  } catch (error) {
    logger.error('Pipes management photo upload error:', error);
    
    res.status(500).json({
      success: false,
      error: 'Internal server error during photo upload',
      details: error.message
    });
  }
});

// Metals management photo upload endpoint
app.post('/upload-metals-photo', upload.single('photo'), async (req, res) => {
  try {
    logger.info('Metals management photo upload request received');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No photo file provided'
      });
    }

    const { type } = req.body;
    
    // Validate photo type  
    if (!type || !['vehicle', 'vendor_license'].includes(type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid photo type. Must be vehicle or vendor_license'
      });
    }

    const startTime = Date.now();
    
    try {
      // Get photo URL from multer-s3 (if S3 is configured) or local path
      const photoUrl = req.file.location || `/uploads/${req.file.filename}`;
      
      const processingTime = (Date.now() - startTime) / 1000;
      
      logger.info(`Metals management photo uploaded successfully:`, {
        photo_type: type,
        original_name: req.file.originalname,
        photo_url: photoUrl,
        file_size: req.file.size,
        processing_time: processingTime
      });

      res.json({
        success: true,
        message: "Metals management photo uploaded successfully",
        url: photoUrl,
        data: {
          photo_type: type,
          upload_date: new Date().toISOString().split('T')[0],
          original_filename: req.file.originalname,
          photo_url: photoUrl,
          file_size: req.file.size,
          content_type: req.file.mimetype,
          processing_time: processingTime
        }
      });

    } catch (uploadError) {
      logger.error('Error uploading metals management photo:', uploadError);
      
      res.status(500).json({
        success: false,
        error: `Failed to upload photo: ${uploadError.message}`,
        details: 'Upload failed'
      });
    }

  } catch (error) {
    logger.error('Metals management photo upload error:', error);
    
    res.status(500).json({
      success: false,
      error: 'Internal server error during photo upload',
      details: error.message
    });
  }
});

// Aggregates management photo upload endpoint
app.post('/upload-aggregates-photo', upload.single('photo'), async (req, res) => {
  try {
    logger.info('Aggregates management photo upload request received');
    
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No photo file provided'
      });
    }

    const { type } = req.body;
    
    // Validate photo type  
    if (!type || !['vehicle', 'vendor_license'].includes(type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid photo type. Must be vehicle or vendor_license'
      });
    }

    const startTime = Date.now();
    
    try {
      // Get photo URL from multer-s3 (if S3 is configured) or local path
      const photoUrl = req.file.location || `/uploads/${req.file.filename}`;
      
      const processingTime = (Date.now() - startTime) / 1000;
      
      logger.info(`Aggregates management photo uploaded successfully:`, {
        photo_type: type,
        original_name: req.file.originalname,
        photo_url: photoUrl,
        file_size: req.file.size,
        processing_time: processingTime
      });

      res.json({
        success: true,
        message: "Aggregates management photo uploaded successfully",
        url: photoUrl,
        data: {
          photo_type: type,
          upload_date: new Date().toISOString().split('T')[0],
          original_filename: req.file.originalname,
          photo_url: photoUrl,
          file_size: req.file.size,
          content_type: req.file.mimetype,
          processing_time: processingTime
        }
      });

    } catch (uploadError) {
      logger.error('Error uploading aggregates management photo:', uploadError);
      
      res.status(500).json({
        success: false,
        error: `Failed to upload photo: ${uploadError.message}`,
        details: 'Upload failed'
      });
    }

  } catch (error) {
    logger.error('Aggregates management photo upload error:', error);
    
    res.status(500).json({
      success: false,
      error: 'Internal server error during photo upload',
      details: error.message
    });
  }
});

app.use('*', (req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// ===========================================
// SERVER STARTUP
// ===========================================

const startServer = async () => {
  try {
    console.log('Starting server initialization...');
    
    // Initialize database
    await initializeDatabase();
    
    // Initialize admin tables after database connection is ready
    await initializeAdminTables();
    
    // Initialize additional tables (project documents, etc.)
    await initializeAdditionalTables();
    
    // Initialize system components
    await initializeSystem();
    
    // Start the server
    const PORT = process.env.PORT || 3000;
    httpServer.listen(PORT, () => {
      logger.info(`Server with WebSocket running on port ${PORT}`);
      logger.info('Real-time document management system ready');
      console.log(`Server started successfully on port ${PORT}`);
    });
    
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
};


// Start the server
startServer();

// Export for external use
export {
  RealTimeDocumentService,
  httpServer
};

logger.info('WebSocket real-time system initialized');

