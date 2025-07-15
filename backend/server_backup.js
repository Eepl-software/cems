import express from 'express';
import bodyParser from 'body-parser';
import bcrypt from 'bcrypt';
import cors from 'cors';
import Joi from 'joi';
import pkg from 'pg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import multer from 'multer';
import multerS3 from 'multer-s3-v2';  
import winston from 'winston';
import sharp from 'sharp';
import AWS from 'aws-sdk'; 
import dotenv from 'dotenv';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import jwt from 'jsonwebtoken';
import os from 'os';
import si from 'systeminformation';
import { v4 as uuidv4 } from 'uuid';
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

    // Configure AWS SDK
    AWS.config.update({
      accessKeyId: process.env.AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
      region: process.env.AWS_REGION
    });

    return new AWS.S3();
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

// Configure multer for file uploads
const upload = multer({
  storage: multerS3({
    s3: s3Client,
    bucket: process.env.AWS_BUCKET_NAME,
    acl: 'public-read',
    contentType: multerS3.AUTO_CONTENT_TYPE,
    key: function (req, file, cb) {
      if (!s3Client) {
        return cb(new Error('S3 client not initialized - file uploads are disabled'));
      }
      const timestamp = Date.now();
      const key = `tanker-images/${req.body.plateNumber || 'unknown'}/${timestamp}_${file.originalname}`;
      logger.info('Generated S3 key:', key);
      cb(null, key);
    },
    metadata: function (req, file, cb) {
      cb(null, { fieldName: file.fieldname });
    }
  }),
  fileFilter: (req, file, cb) => {
    logger.info('Checking file:', {
      fieldname: file.fieldname,
      originalname: file.originalname,
      mimetype: file.mimetype
    });

    // Check if S3 is properly configured
    if (!s3Client) {
      logger.error('S3 client not initialized');
      cb(new Error('File uploads are currently disabled'), false);
      return;
    }

    // Check if file exists
    if (!file) {
      logger.warn('No file provided');
      cb(new Error('No file provided'), false);
      return;
    }

    // Check file type
    const validMimeTypes = ['image/jpeg', 'image/jpg', 'image/png'];
    if (!validMimeTypes.includes(file.mimetype)) {
      logger.warn('Invalid file type:', file.mimetype);
      cb(new Error(`Invalid file type. Allowed types are: ${validMimeTypes.join(', ')}`), false);
      return;
    }

    logger.info('File validation passed');
    cb(null, true);
  },
  limits: {
    fileSize: 5 * 1024 * 1024, // 5MB
    files: 1
  }
});

// Create separate upload middlewares for different routes
const uploadTankerImage = upload.single('image');
const uploadPhoto = upload.single('photo');

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
  lastUpdated: Joi.date().required(),
  latitude: Joi.number().optional(),
  longitude: Joi.number().optional(),
  photoUrl: Joi.string().optional(),
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

// Database configuration
const dbConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT,
  ssl: process.env.NODE_ENV === 'production' ? sslConfig : false,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000, 
};

// Create a connection pool instead of a single client
const pool = new Pool(dbConfig);

pool.on('error', (err) => {
  logger.error('Unexpected error on idle client', err);
  process.exit(-1);
});

// Test database connection
pool.connect()
  .then(client => {
    logger.info('Successfully connected to PostgreSQL');
    client.release();
  })
  .catch(err => {
    logger.error('Error connecting to PostgreSQL:', err);
    process.exit(1);
});

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

Promise.all([
  pool.query(createAdminLogsTable),
  pool.query(createSystemStatsTable),
  pool.query(createAdminSettingsTable)
]).then(() => {
  logger.info('Admin tables initialized successfully');
}).catch(err => {
  logger.error('Error creating admin tables:', err);
});

const logAdminAction = async (username, action, description, req) => {
  try {
    await pool.query(
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

pool.query(createWaterConsumptionTable)
  .then(() => console.log('Water Consumption table created or already exists.'))
  .catch(err => console.error('Error creating water consumption table:', err));

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

    const result = await pool.query(query, [total, thisMonth, today]);

    res.status(201).json({
      message: 'Water consumption data added successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error adding water consumption data:', err);
    res.status(500).json({ error: 'Internal server error' });
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

pool.query(createUsersTable)
  .then(() => console.log('Users table created or already exists.'))
  .catch(err => console.error('Error creating users table:', err));

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

// Initialize table
pool.query(createBorewellTable)
  .then(() => console.log('Borewell Water table created or already exists.'))
  .catch(err => console.error('Error creating borewell water table:', err));

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
    const existingEntry = await pool.query(
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

    const result = await pool.query(query, [
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

    const result = await pool.query(query, values);

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

    const result = await pool.query(query, [
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
    const result = await pool.query(
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

    const result = await pool.query(query, [start_date, end_date]);

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
    const existingUser = await pool.query(
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

    const result = await pool.query(query, [
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

    const result = await pool.query(
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
    await pool.query(
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
    const userStats = await pool.query(`
      SELECT 
        COUNT(*) as total_users,
        COUNT(CASE WHEN last_login > NOW() - INTERVAL '24 hours' THEN 1 END) as active_users
      FROM users
    `);

    // Get tanker statistics
    const tankerStats = await pool.query('SELECT COUNT(*) as active_tankers FROM tankers');

    // Get water consumption statistics
    const waterStats = await pool.query(`
      SELECT 
        COALESCE(SUM(total), 0) as total_consumption,
        COALESCE(SUM(this_month), 0) as month_consumption,
        COALESCE(SUM(today), 0) as today_consumption
      FROM water_consumption
    `);

    // Get system alerts
    const alertStats = await pool.query(`
      SELECT COUNT(*) as total_alerts
      FROM alerts 
      WHERE is_active = true AND severity IN ('high', 'critical')
    `);

    // Get system stats from the database
    const systemStatsResult = await pool.query('SELECT * FROM system_stats ORDER BY updated_at DESC LIMIT 1');
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
    await pool.query(`
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
    const activities = await pool.query(`
      SELECT 
        'login' as type,
        CONCAT('User ', username, ' logged in') as description,
        last_login as timestamp
      FROM users 
      WHERE last_login IS NOT NULL
      ORDER BY last_login DESC
      LIMIT 10
    `);

    const adminActivities = await pool.query(`
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

    const result = await pool.query(
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
    const usersCount = await pool.query('SELECT COUNT(*) FROM users');
    
    // Get active tankers count (updated table name)
    const tankersCount = await pool.query('SELECT COUNT(*) FROM tankers');
    
    // Get total water consumption
    const waterConsumption = await pool.query(
      'SELECT SUM(total) as total FROM water_consumption'
    );
    
    // Get alerts count (from stack monitoring critical status)
    const alertsCount = await pool.query(
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
    const existingUser = await pool.query(
      'SELECT * FROM users WHERE email = $1 OR username = $2',
      [email, username]
    );

    if (existingUser.rows.length > 0) {
      return res.status(409).json({ error: 'User with this email or username already exists' });
    }

    const hashedPassword = await bcrypt.hash(password, 12);

    const result = await pool.query(
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
      pool.query(query, params),
      pool.query(countQuery, search ? [`%${search}%`] : [])
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

    const result = await pool.query(query, [...values, id]);

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

    const result = await pool.query(
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
    const tablesResult = await pool.query(`
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
        const data = await pool.query(`SELECT * FROM ${tableName}`);
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

    const logs = await pool.query(query, [limit, offset]);

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
        const usersReport = await pool.query(`
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
        const waterReport = await pool.query(`
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
        const tankersReport = await pool.query(`
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
        const systemReport = await pool.query(`
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

pool.query(createAlertTable)
  .then(() => console.log('Alerts table created or already exists.'))
  .catch(err => console.error('Error creating alerts table:', err));

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
  
      const result = await pool.query(
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

    const alerts = await pool.query(query, params);

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
    const settings = await pool.query(
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

    const result = await pool.query(
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
    const dbStatus = await pool.query('SELECT NOW()');
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
    as_per_consent VARCHAR(255) NOT NULL,
    provided VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'Active',
    timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
  )
`;

pool.query(createStackMonitoringTable)
  .then(() => console.log('Stack Monitoring table created or already exists.'))
  .catch(err => console.error('Error creating stack monitoring table:', err));

const stackMonitoringSchema = Joi.object({
  source: Joi.string().required(),
  as_per_consent: Joi.string().required(),
  provided: Joi.string().required(),
  status: Joi.string().valid('active', 'inactive', 'maintenance', 'critical').default('active'),
});

app.get('/stack-monitoring', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM stack_monitoring ORDER BY timestamp DESC');
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

    const { source, as_per_consent, provided, status } = value;

    const result = await pool.query(
      'INSERT INTO stack_monitoring (source, as_per_consent, provided, status) VALUES ($1, $2, $3, $4) RETURNING *',
      [source, as_per_consent, provided, status.toLowerCase()]
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

    const { source, as_per_consent, provided, status } = value;

    const result = await pool.query(
      'UPDATE stack_monitoring SET source = $1, as_per_consent = $2, provided = $3, status = $4 WHERE id = $5 RETURNING *',
      [source, as_per_consent, provided, status.toLowerCase(), id]
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

    const result = await pool.query(
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
    parameter TEXT NOT NULL,
    limit_value TEXT NOT NULL,
    measured TEXT NOT NULL,
    status TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

pool.query(createAmbientMonitoringTable)
  .then(() => console.log('Ambient monitoring table created or already exists.'))
  .catch(err => console.error('Error creating ambient monitoring table:', err));

// Add monitoring data endpoint
app.post('/ambient-monitoring', async (req, res) => {
  try {
    const monitoringSchema = Joi.object({
      id: Joi.string().max(50).required(),
      location: Joi.string().required(),
      parameter: Joi.string().required(),
      limit: Joi.string().required(),
      measured: Joi.string().required(),
      status: Joi.string().required(),
      timestamp: Joi.date().optional() // Allow default timestamp
    });

    const { error } = monitoringSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const { id, location, parameter, limit, measured, status, timestamp } = req.body;

    const query = `
      INSERT INTO ambient_monitoring
      (id, location, parameter, limit_value, measured, status, timestamp)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING *
    `;

    const result = await pool.query(query, [
      id, location, parameter, limit, measured, status, timestamp || new Date()
    ]);

    res.status(201).json({
      message: 'Monitoring data added successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error adding monitoring data:', err.stack); // Detailed error logging
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get monitoring data endpoint
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

    const result = await pool.query(query, params);
    res.status(200).json({
      message: 'Data retrieved successfully',
      data: result.rows
    });

  } catch (err) {
    console.error('Error retrieving monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update monitoring data endpoint
app.put('/ambient-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { location, parameter, limit, measured, status, timestamp } = req.body;

    const query = `
      UPDATE ambient_monitoring
      SET location = $1, parameter = $2, limit_value = $3, measured = $4, status = $5, timestamp = $6
      WHERE id = $7
      RETURNING *
    `;

    const result = await pool.query(query, [
      location, parameter, limit, measured, status, timestamp, id
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Monitoring data not found' });
    }

    res.status(200).json({
      message: 'Monitoring data updated successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error updating monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete monitoring data endpoint
app.delete('/ambient-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const query = 'DELETE FROM ambient_monitoring WHERE id = $1 RETURNING *';
    const result = await pool.query(query, [id]);

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

pool.query(createConsumptionTable)
  .then(() => console.log('Consumption table created or already exists.'))
  .catch(err => console.error('Error creating consumption table:', err));

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

    const result = await pool.query(query, [
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

    const result = await pool.query(query, params);

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
    const result = await pool.query(query);

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
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    latitude DECIMAL,
    longitude DECIMAL,
    photo_url TEXT
  )
`;

pool.query(createTankersTable)
  .then(() => console.log('Tankers table created successfully'))
  .catch(err => console.error('Error creating tankers table:', err));

// Use the existing tankerSchema defined at the top of the file

// POST Endpoint to Add Tanker Data
app.post('/tanker', upload.single('photo'), async (req, res) => {
  try {
    let tankerData;
    
    // Check if the request is multipart form data or JSON
    if (req.is('multipart/form-data')) {
      // Handle multipart form data (from mobile app)
      tankerData = {
        plateNumber: req.body.plateNumber,
        capacity: parseFloat(req.body.capacity),
        driverName: req.body.driverName,
        driverContact: req.body.driverContact,
        vendor: req.body.vendor,
        lastUpdated: req.body.lastUpdated || new Date().toISOString(),
        latitude: req.body.latitude ? parseFloat(req.body.latitude) : null,
        longitude: req.body.longitude ? parseFloat(req.body.longitude) : null,
        photoUrl: req.file ? req.file.location : null
      };
    } else {
      // Handle JSON data (from curl/API requests)
      tankerData = {
        ...req.body,
        capacity: parseFloat(req.body.capacity),
        lastUpdated: req.body.lastUpdated || new Date().toISOString(),
        latitude: req.body.latitude ? parseFloat(req.body.latitude) : null,
        longitude: req.body.longitude ? parseFloat(req.body.longitude) : null
      };
    }

    // Validate the data against schema
    const { error } = tankerSchema.validate(tankerData);
    if (error) {
      console.error('Validation error:', error.details);
      return res.status(400).json({
        success: false,
        message: error.details[0].message
      });
    }

    // Check if tanker exists
    const existingTanker = await pool.query(
      'SELECT * FROM tankers WHERE plate_number = $1',
      [tankerData.plateNumber]
    );

    let result;
    if (existingTanker.rows.length > 0) {
      // Update existing tanker
      result = await pool.query(`
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
    } else {
      // Insert new tanker
      result = await pool.query(`
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
    }

    // Convert snake_case to camelCase for response
    const tanker = {
      id: result.rows[0].id,
      plateNumber: result.rows[0].plate_number,
      capacity: parseFloat(result.rows[0].capacity),
      driverName: result.rows[0].driver_name,
      driverContact: result.rows[0].driver_contact,
      vendor: result.rows[0].vendor,
      lastUpdated: result.rows[0].last_updated,
      latitude: result.rows[0].latitude ? parseFloat(result.rows[0].latitude) : null,
      longitude: result.rows[0].longitude ? parseFloat(result.rows[0].longitude) : null,
      photoUrl: result.rows[0].photo_url
    };

    res.status(existingTanker.rows.length > 0 ? 200 : 201).json({
      success: true,
      message: existingTanker.rows.length > 0 ? 'Tanker updated successfully' : 'Tanker created successfully',
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
      query += ` DATE(last_updated) = $${params.length + 1}`;
      params.push(date);
    }

    query += ' ORDER BY last_updated DESC';

    const result = await pool.query(query, params);
    
    // Convert snake_case to camelCase for frontend
    const tankers = result.rows.map(row => ({
      id: row.id,
      plateNumber: row.plate_number,
      capacity: row.capacity,
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
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

    const result = await pool.query(query, [
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
    const result = await pool.query(query, [id]);

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
    const result = await pool.query(query, [id]);

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

pool.query(createLabourColonyWasteTable)
  .then(() => console.log('Labour Colony Waste table created or already exists.'))
  .catch(err => console.error('Error creating labour colony waste table:', err));

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

    const result = await pool.query(query, values);

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

    const result = await pool.query(query, [
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

    const result = await pool.query(query, [
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

    const result = await pool.query(
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
    waste_type VARCHAR(100),
    disposal_method VARCHAR(100),
    reuse_recycling_details TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

pool.query(createCDWasteTable)
  .then(() => console.log('C&D Waste table created or already exists.'))
  .catch(err => console.error('Error creating C&D waste table:', err));

// Validation Schema
const cdWasteSchema = Joi.object({
  project_area: Joi.number().positive().required(),
  waste_type: Joi.string().required(),
  disposal_method: Joi.string().required(),
  reuse_recycling_details: Joi.string(),
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

    const result = await pool.query(query, params);
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
      date,
      waste_type,
      disposal_method,
      reuse_recycling_details
    } = req.body;

    const waste_amount = project_area * 0.15;

    const query = `
      INSERT INTO cd_waste
      (project_area, waste_amount, date, waste_type, disposal_method, reuse_recycling_details)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `;

    const result = await pool.query(query, [
      project_area,
      waste_amount,
      date,
      waste_type,
      disposal_method,
      reuse_recycling_details
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

pool.query(createCDWasteCalculationTable)
  .then(() => console.log('Waste Calculations table created or already exists.'))
  .catch(err => console.error('Error creating Waste Calculations table:', err));

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

    // Calculate waste amount
    const waste_amount = project_area * WASTE_FACTOR;

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

    const result = await pool.query(query, [
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

    const result = await pool.query(query);

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

    const result = await pool.query(query, [id]);

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

    const result = await pool.query(query, [id]);

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

pool.query(createcd_waste_calcTable)
  .then(() => console.log('C&D Waste Calculation table created or already exists.'))
  .catch(err => console.error('Error creating C&D waste calculation table:', err));

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
    await pool.query(
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
    const result = await pool.query(`SELECT * FROM cd_waste_calc ORDER BY created_at DESC`);
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
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

pool.query(createDailyWasteTable)
  .then(() => console.log('Daily Waste table created or already exists.'))
  .catch(err => console.error('Error creating Daily Waste table:', err));

// Endpoint to add daily waste data
app.post("/daily-waste", async (req, res) => {
  try {
    const { date, quantity_kg, mode_of_storage, mode_of_disposal } = req.body;

    const query = `
      INSERT INTO daily_waste (date, quantity_kg, mode_of_storage, mode_of_disposal)
      VALUES ($1, $2, $3, $4)
      RETURNING *
    `;

    const result = await pool.query(query, [date, quantity_kg, mode_of_storage, mode_of_disposal]);

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
    const query = `
      SELECT
        id,
        date,
        quantity_kg,
        mode_of_storage,
        mode_of_disposal,
        (SELECT SUM(quantity_kg) FROM daily_waste) as total_waste
      FROM daily_waste
      ORDER BY date DESC
    `;

    const result = await pool.query(query);

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

pool.query(createTableQuery)
  .then(() => console.log('Table ready'))
  .catch(err => console.error('Error creating table:', err));

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
    const result = await pool.query(query, params);
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
    const result = await pool.query(query, [date, source, consumption, discharge, discharged_to, mode]);
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
    const result = await pool.query(query, [
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
    const result = await pool.query(
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

(async () => {
  try {
    await pool.query(createTableproject_waste);
    console.log('Table "project_waste" created or already exists.');
  } catch (err) {
    console.error('Error creating table:', err.message);
  }
})();

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
    const result = await pool.query(query, params);

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
    const result = await pool.query(query, [
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
    const result = await pool.query(query, [
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
    const result = await pool.query(
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
pool.query(createbwssb_supplyTable)
  .then(() => pool.query(createUpdateTrigger))
  .then(() => console.log('BWSSB table and trigger created or already exists'))
  .catch(err => console.error('Error creating table:', err));

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

  pool.query(query, params, (err, results) => {
    if (err) {
      console.error('Error fetching data:', err);
      return res.status(500).json({ error: err.message });
    }
    res.json({ data: results.rows });
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

  pool.query(
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

CREATE INDEX idx_labour_colony_consumption_date ON labour_colony_consumption (date);

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
    const result = await pool.query('SELECT * FROM labour_colony_consumption ORDER BY date DESC');
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

    const result = await pool.query(query, [date, source, consumption, discharge, discharged_to, mode]);

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
      query += ` DATE(last_updated) = $${params.length + 1}`;
      params.push(date);
    }

    query += ' ORDER BY last_updated DESC';

    const result = await pool.query(query, params);
    
    // Convert snake_case to camelCase for frontend
    const tankers = result.rows.map(row => ({
      id: row.id,
      plateNumber: row.plate_number,
      capacity: row.capacity,
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
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
        const existingTanker = await pool.query(
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
          result = await pool.query(`
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
          result = await pool.query(`
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
      query += ` DATE(last_updated) = $${params.length + 1}`;
      params.push(date);
    }

    query += ' ORDER BY last_updated DESC';

    const result = await pool.query(query, params);
    
    // Convert snake_case to camelCase for frontend
    const tankers = result.rows.map(row => ({
      id: row.id,
      plateNumber: row.plate_number,
      capacity: row.capacity,
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
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
const uploadToS3 = async (fileData, key) => {
  try {
    // Check if S3 client is initialized
    if (!s3Client) {
      throw new Error('S3 client not initialized - file uploads are disabled');
    }

    // Log upload attempt
    logger.info('Attempting S3 upload:', {
      key: key,
      contentType: fileData.mimetype,
      size: fileData.buffer.length
    });

    const upload = new Upload({
      client: s3Client,
      params: {
        Bucket: process.env.AWS_BUCKET_NAME,
        Key: key,
        Body: fileData.buffer,
        ContentType: fileData.mimetype,
        ACL: 'public-read',
        Metadata: {
          'original-filename': fileData.originalname || 'unknown',
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

    return {
      Location: result.Location,
      Key: key,
      ETag: result.ETag
    };
  } catch (error) {
    logger.error('Error uploading to S3:', {
      error: error.message,
      code: error.code,
      key: key,
      requestId: error.$metadata?.requestId
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



// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  pool.end(() => {
    logger.info('Database pool closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  pool.end(() => {
    logger.info('Database pool closed');
    process.exit(0);
  });
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
pool.query(createSystemMetricsHistoryTable)
  .then(() => console.log('system_metrics_history table created or already exists.'))
  .catch(err => console.error('Error creating system_metrics_history table:', err));

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
    await pool.query(
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
    const result = await pool.query(
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

// Execute table creation
Promise.all([
  pool.query(createProjectDocumentsTable),
  pool.query(createDocumentCategoriesTable),
  pool.query(createDocumentIndexes)
]).then(() => {
  logger.info('Document storage tables initialized successfully');
}).catch(err => {
  logger.error('Error creating document storage tables:', err);
});

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

pool.query(insertDefaultCategories)
  .then(() => logger.info('Default document categories inserted'))
  .catch(err => logger.error('Error inserting default categories:', err));

// ===========================================
// VALIDATION SCHEMAS
// ===========================================

const documentSchema = Joi.object({
  name: Joi.string().min(1).max(255).required(),
  category: Joi.string().required(),
  description: Joi.string().max(1000).optional().allow(''),
  tags: Joi.array().items(Joi.string()).optional(),
  status: Joi.string().valid('Active', 'Approved', 'Pending', 'Expired', 'Verified', 'Rejected').default('Active'),
  expiry_date: Joi.date().optional().allow(null)
});

const documentUpload = multer({
  storage: multerS3({
    s3: s3Client,
    bucket: process.env.AWS_BUCKET_NAME,
    acl: 'private', // Documents should be private
    contentType: multerS3.AUTO_CONTENT_TYPE,
    key: function (req, file, cb) {
      if (!s3Client) {
        return cb(new Error('S3 client not initialized - file uploads are disabled'));
      }
      const timestamp = Date.now();
      const sanitizedFileName = file.originalname.replace(/[^a-zA-Z0-9.-]/g, '_');
      const key = `project-documents/${req.user?.id || 'anonymous'}/${timestamp}_${sanitizedFileName}`;
      logger.info('Generated document S3 key:', key);
      cb(null, key);
    },
    metadata: function (req, file, cb) {
      cb(null, { 
        fieldName: file.fieldname,
        originalName: file.originalname,
        uploadedBy: req.user?.id?.toString() || 'anonymous'
      });
    }
  }),
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

    if (!validMimeTypes.includes(file.mimetype)) {
      logger.warn('Invalid document file type:', file.mimetype);
      cb(new Error(`Invalid file type. Allowed types are: PDF, DOC, DOCX, JPG, PNG, XLS, XLSX`), false);
      return;
    }

    logger.info('Document file validation passed');
    cb(null, true);
  },
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit for documents
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
      pool.query(query, params),
      pool.query(countQuery, params.slice(0, -2)) // Remove limit and offset for count
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

    const result = await pool.query(query, [id]);

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

// POST new document
app.post('/api/documents', authenticateToken, documentUpload.single('file'), async (req, res) => {
  try {
    const { error } = documentSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        error: error.details[0].message
      });
    }

    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No file provided'
      });
    }

    const {
      name,
      category,
      description = '',
      tags = [],
      status = 'Active',
      expiry_date
    } = req.body;

    // Parse tags if they come as a string
    let parsedTags = tags;
    if (typeof tags === 'string') {
      parsedTags = tags.split(',').map(tag => tag.trim()).filter(tag => tag.length > 0);
    }

    const query = `
      INSERT INTO project_documents 
      (name, category, file_path, file_type, file_size, description, tags, status, expiry_date, uploaded_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `;

    const result = await pool.query(query, [
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
    const { error } = documentSchema.validate(req.body);
    if (error) {
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
    } = req.body;

    // Parse tags if they come as a string
    let parsedTags = tags;
    if (typeof tags === 'string') {
      parsedTags = tags.split(',').map(tag => tag.trim()).filter(tag => tag.length > 0);
    }

    const query = `
      UPDATE project_documents 
      SET name = $1, category = $2, description = $3, tags = $4, status = $5, 
          expiry_date = $6, updated_at = CURRENT_TIMESTAMP
      WHERE id = $7 AND (uploaded_by = $8 OR is_asset = false)
      RETURNING *
    `;

    const result = await pool.query(query, [
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
    
    const docResult = await pool.query(getDocQuery, [id]);
    
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

    const result = await pool.query(deleteQuery, [id]);

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

    const result = await pool.query(query);

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
      pool.query(statsQuery),
      pool.query(categoryStatsQuery)
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

    const result = await pool.query(query, [id]);

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
        
        const signedUrl = await s3Client.getSignedUrlPromise('getObject', {
          Bucket: process.env.AWS_BUCKET_NAME,
          Key: key,
          Expires: 3600, // 1 hour
          ResponseContentDisposition: `attachment; filename="${document.name}"`
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
      await pool.query(`
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

    const result = await pool.query(query);

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

    const result = await pool.query(
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
    const dailyResult = await pool.query(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly consumption
    const monthlyQuery = `
      SELECT COALESCE(SUM(water_consumed), 0) as monthly_consumption
      FROM borewell_water 
      WHERE date >= $1 AND date <= $2
    `;
    const monthlyResult = await pool.query(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Cumulative consumption (all time)
    const cumulativeQuery = `
      SELECT COALESCE(SUM(water_consumed), 0) as cumulative_consumption
      FROM borewell_water
    `;
    const cumulativeResult = await pool.query(cumulativeQuery);

    // Period consumption (if date range provided)
    let periodConsumption = cumulativeResult.rows[0].cumulative_consumption;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(water_consumed), 0) as period_consumption
        FROM borewell_water 
        WHERE date >= $1 AND date <= $2
      `;
      const periodResult = await pool.query(periodQuery, [fromDate, toDate]);
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
    const dailyResult = await pool.query(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly deliveries
    const monthlyQuery = `
      SELECT COALESCE(SUM(capacity), 0) as monthly_capacity
      FROM tankers 
      WHERE DATE(last_updated) >= $1 AND DATE(last_updated) <= $2
    `;
    const monthlyResult = await pool.query(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Total tanker capacity (all active tankers)
    const cumulativeQuery = `
      SELECT COALESCE(SUM(capacity), 0) as total_capacity
      FROM tankers
    `;
    const cumulativeResult = await pool.query(cumulativeQuery);

    // Period consumption
    let periodConsumption = cumulativeResult.rows[0].total_capacity;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(capacity), 0) as period_capacity
        FROM tankers 
        WHERE DATE(last_updated) >= $1 AND DATE(last_updated) <= $2
      `;
      const periodResult = await pool.query(periodQuery, [fromDate, toDate]);
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
    const dailyResult = await pool.query(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly consumption
    const monthlyQuery = `
      SELECT COALESCE(SUM(quantity_supplied), 0) as monthly_consumption
      FROM bwssb_supply 
      WHERE supply_date >= $1 AND supply_date <= $2
    `;
    const monthlyResult = await pool.query(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Cumulative consumption
    const cumulativeQuery = `
      SELECT COALESCE(SUM(quantity_supplied), 0) as cumulative_consumption
      FROM bwssb_supply
    `;
    const cumulativeResult = await pool.query(cumulativeQuery);

    // Period consumption
    let periodConsumption = cumulativeResult.rows[0].cumulative_consumption;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(quantity_supplied), 0) as period_consumption
        FROM bwssb_supply 
        WHERE supply_date >= $1 AND supply_date <= $2
      `;
      const periodResult = await pool.query(periodQuery, [fromDate, toDate]);
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
    const dailyResult = await pool.query(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly consumption
    const monthlyQuery = `
      SELECT COALESCE(SUM(consumption), 0) as monthly_consumption
      FROM labour_colony 
      WHERE date >= $1 AND date <= $2
    `;
    const monthlyResult = await pool.query(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Cumulative consumption
    const cumulativeQuery = `
      SELECT COALESCE(SUM(consumption), 0) as cumulative_consumption
      FROM labour_colony
    `;
    const cumulativeResult = await pool.query(cumulativeQuery);

    // Period consumption
    let periodConsumption = cumulativeResult.rows[0].cumulative_consumption;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(consumption), 0) as period_consumption
        FROM labour_colony 
        WHERE date >= $1 AND date <= $2
      `;
      const periodResult = await pool.query(periodQuery, [fromDate, toDate]);
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

// Dashboard endpoint for charts and real-time data
import express from 'express';
import bodyParser from 'body-parser';
import bcrypt from 'bcrypt';
import cors from 'cors';
import Joi from 'joi';
import pkg from 'pg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import multer from 'multer';
import multerS3 from 'multer-s3-v2';  
import winston from 'winston';
import sharp from 'sharp';
import AWS from 'aws-sdk'; 
import dotenv from 'dotenv';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import jwt from 'jsonwebtoken';
import os from 'os';
import si from 'systeminformation';
import { v4 as uuidv4 } from 'uuid';
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

    // Configure AWS SDK
    AWS.config.update({
      accessKeyId: process.env.AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
      region: process.env.AWS_REGION
    });

    return new AWS.S3();
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

// Configure multer for file uploads
const upload = multer({
  storage: multerS3({
    s3: s3Client,
    bucket: process.env.AWS_BUCKET_NAME,
    acl: 'public-read',
    contentType: multerS3.AUTO_CONTENT_TYPE,
    key: function (req, file, cb) {
      if (!s3Client) {
        return cb(new Error('S3 client not initialized - file uploads are disabled'));
      }
      const timestamp = Date.now();
      const key = `tanker-images/${req.body.plateNumber || 'unknown'}/${timestamp}_${file.originalname}`;
      logger.info('Generated S3 key:', key);
      cb(null, key);
    },
    metadata: function (req, file, cb) {
      cb(null, { fieldName: file.fieldname });
    }
  }),
  fileFilter: (req, file, cb) => {
    logger.info('Checking file:', {
      fieldname: file.fieldname,
      originalname: file.originalname,
      mimetype: file.mimetype
    });

    // Check if S3 is properly configured
    if (!s3Client) {
      logger.error('S3 client not initialized');
      cb(new Error('File uploads are currently disabled'), false);
      return;
    }

    // Check if file exists
    if (!file) {
      logger.warn('No file provided');
      cb(new Error('No file provided'), false);
      return;
    }

    // Check file type
    const validMimeTypes = ['image/jpeg', 'image/jpg', 'image/png'];
    if (!validMimeTypes.includes(file.mimetype)) {
      logger.warn('Invalid file type:', file.mimetype);
      cb(new Error(`Invalid file type. Allowed types are: ${validMimeTypes.join(', ')}`), false);
      return;
    }

    logger.info('File validation passed');
    cb(null, true);
  },
  limits: {
    fileSize: 5 * 1024 * 1024, // 5MB
    files: 1
  }
});

// Create separate upload middlewares for different routes
const uploadTankerImage = upload.single('image');
const uploadPhoto = upload.single('photo');

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
  lastUpdated: Joi.date().required(),
  latitude: Joi.number().optional(),
  longitude: Joi.number().optional(),
  photoUrl: Joi.string().optional(),
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

// Database configuration
const dbConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT,
  ssl: process.env.NODE_ENV === 'production' ? sslConfig : false,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000, 
};

// Create a connection pool instead of a single client
const pool = new Pool(dbConfig);

pool.on('error', (err) => {
  logger.error('Unexpected error on idle client', err);
  process.exit(-1);
});

// Test database connection
pool.connect()
  .then(client => {
    logger.info('Successfully connected to PostgreSQL');
    client.release();
  })
  .catch(err => {
    logger.error('Error connecting to PostgreSQL:', err);
    process.exit(1);
});

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

Promise.all([
  pool.query(createAdminLogsTable),
  pool.query(createSystemStatsTable),
  pool.query(createAdminSettingsTable)
]).then(() => {
  logger.info('Admin tables initialized successfully');
}).catch(err => {
  logger.error('Error creating admin tables:', err);
});

const logAdminAction = async (username, action, description, req) => {
  try {
    await pool.query(
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

pool.query(createWaterConsumptionTable)
  .then(() => console.log('Water Consumption table created or already exists.'))
  .catch(err => console.error('Error creating water consumption table:', err));

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

    const result = await pool.query(query, [total, thisMonth, today]);

    res.status(201).json({
      message: 'Water consumption data added successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error adding water consumption data:', err);
    res.status(500).json({ error: 'Internal server error' });
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

pool.query(createUsersTable)
  .then(() => console.log('Users table created or already exists.'))
  .catch(err => console.error('Error creating users table:', err));

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

// Initialize table
pool.query(createBorewellTable)
  .then(() => console.log('Borewell Water table created or already exists.'))
  .catch(err => console.error('Error creating borewell water table:', err));

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
    const existingEntry = await pool.query(
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

    const result = await pool.query(query, [
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

    const result = await pool.query(query, values);

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

    const result = await pool.query(query, [
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
    const result = await pool.query(
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

    const result = await pool.query(query, [start_date, end_date]);

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
    const existingUser = await pool.query(
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

    const result = await pool.query(query, [
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

    const result = await pool.query(
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
    await pool.query(
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
    const userStats = await pool.query(`
      SELECT 
        COUNT(*) as total_users,
        COUNT(CASE WHEN last_login > NOW() - INTERVAL '24 hours' THEN 1 END) as active_users
      FROM users
    `);

    // Get tanker statistics
    const tankerStats = await pool.query('SELECT COUNT(*) as active_tankers FROM tankers');

    // Get water consumption statistics
    const waterStats = await pool.query(`
      SELECT 
        COALESCE(SUM(total), 0) as total_consumption,
        COALESCE(SUM(this_month), 0) as month_consumption,
        COALESCE(SUM(today), 0) as today_consumption
      FROM water_consumption
    `);

    // Get system alerts
    const alertStats = await pool.query(`
      SELECT COUNT(*) as total_alerts
      FROM alerts 
      WHERE is_active = true AND severity IN ('high', 'critical')
    `);

    // Get system stats from the database
    const systemStatsResult = await pool.query('SELECT * FROM system_stats ORDER BY updated_at DESC LIMIT 1');
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
    await pool.query(`
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
    const activities = await pool.query(`
      SELECT 
        'login' as type,
        CONCAT('User ', username, ' logged in') as description,
        last_login as timestamp
      FROM users 
      WHERE last_login IS NOT NULL
      ORDER BY last_login DESC
      LIMIT 10
    `);

    const adminActivities = await pool.query(`
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

    const result = await pool.query(
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
    const usersCount = await pool.query('SELECT COUNT(*) FROM users');
    
    // Get active tankers count (updated table name)
    const tankersCount = await pool.query('SELECT COUNT(*) FROM tankers');
    
    // Get total water consumption
    const waterConsumption = await pool.query(
      'SELECT SUM(total) as total FROM water_consumption'
    );
    
    // Get alerts count (from stack monitoring critical status)
    const alertsCount = await pool.query(
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
    const existingUser = await pool.query(
      'SELECT * FROM users WHERE email = $1 OR username = $2',
      [email, username]
    );

    if (existingUser.rows.length > 0) {
      return res.status(409).json({ error: 'User with this email or username already exists' });
    }

    const hashedPassword = await bcrypt.hash(password, 12);

    const result = await pool.query(
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
      pool.query(query, params),
      pool.query(countQuery, search ? [`%${search}%`] : [])
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

    const result = await pool.query(query, [...values, id]);

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

    const result = await pool.query(
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
    const tablesResult = await pool.query(`
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
        const data = await pool.query(`SELECT * FROM ${tableName}`);
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

    const logs = await pool.query(query, [limit, offset]);

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
        const usersReport = await pool.query(`
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
        const waterReport = await pool.query(`
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
        const tankersReport = await pool.query(`
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
        const systemReport = await pool.query(`
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

pool.query(createAlertTable)
  .then(() => console.log('Alerts table created or already exists.'))
  .catch(err => console.error('Error creating alerts table:', err));

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
  
      const result = await pool.query(
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

    const alerts = await pool.query(query, params);

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
    const settings = await pool.query(
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

    const result = await pool.query(
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
    const dbStatus = await pool.query('SELECT NOW()');
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
    as_per_consent VARCHAR(255) NOT NULL,
    provided VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'Active',
    timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
  )
`;

pool.query(createStackMonitoringTable)
  .then(() => console.log('Stack Monitoring table created or already exists.'))
  .catch(err => console.error('Error creating stack monitoring table:', err));

const stackMonitoringSchema = Joi.object({
  source: Joi.string().required(),
  as_per_consent: Joi.string().required(),
  provided: Joi.string().required(),
  status: Joi.string().valid('active', 'inactive', 'maintenance', 'critical').default('active'),
});

app.get('/stack-monitoring', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM stack_monitoring ORDER BY timestamp DESC');
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

    const { source, as_per_consent, provided, status } = value;

    const result = await pool.query(
      'INSERT INTO stack_monitoring (source, as_per_consent, provided, status) VALUES ($1, $2, $3, $4) RETURNING *',
      [source, as_per_consent, provided, status.toLowerCase()]
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

    const { source, as_per_consent, provided, status } = value;

    const result = await pool.query(
      'UPDATE stack_monitoring SET source = $1, as_per_consent = $2, provided = $3, status = $4 WHERE id = $5 RETURNING *',
      [source, as_per_consent, provided, status.toLowerCase(), id]
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

    const result = await pool.query(
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
    parameter TEXT NOT NULL,
    limit_value TEXT NOT NULL,
    measured TEXT NOT NULL,
    status TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

pool.query(createAmbientMonitoringTable)
  .then(() => console.log('Ambient monitoring table created or already exists.'))
  .catch(err => console.error('Error creating ambient monitoring table:', err));

// Add monitoring data endpoint
app.post('/ambient-monitoring', async (req, res) => {
  try {
    const monitoringSchema = Joi.object({
      id: Joi.string().max(50).required(),
      location: Joi.string().required(),
      parameter: Joi.string().required(),
      limit: Joi.string().required(),
      measured: Joi.string().required(),
      status: Joi.string().required(),
      timestamp: Joi.date().optional() // Allow default timestamp
    });

    const { error } = monitoringSchema.validate(req.body);
    if (error) {
      return res.status(400).json({ error: error.details[0].message });
    }

    const { id, location, parameter, limit, measured, status, timestamp } = req.body;

    const query = `
      INSERT INTO ambient_monitoring
      (id, location, parameter, limit_value, measured, status, timestamp)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING *
    `;

    const result = await pool.query(query, [
      id, location, parameter, limit, measured, status, timestamp || new Date()
    ]);

    res.status(201).json({
      message: 'Monitoring data added successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error adding monitoring data:', err.stack); // Detailed error logging
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get monitoring data endpoint
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

    const result = await pool.query(query, params);
    res.status(200).json({
      message: 'Data retrieved successfully',
      data: result.rows
    });

  } catch (err) {
    console.error('Error retrieving monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update monitoring data endpoint
app.put('/ambient-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { location, parameter, limit, measured, status, timestamp } = req.body;

    const query = `
      UPDATE ambient_monitoring
      SET location = $1, parameter = $2, limit_value = $3, measured = $4, status = $5, timestamp = $6
      WHERE id = $7
      RETURNING *
    `;

    const result = await pool.query(query, [
      location, parameter, limit, measured, status, timestamp, id
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Monitoring data not found' });
    }

    res.status(200).json({
      message: 'Monitoring data updated successfully!',
      data: result.rows[0]
    });

  } catch (err) {
    console.error('Error updating monitoring data:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete monitoring data endpoint
app.delete('/ambient-monitoring/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const query = 'DELETE FROM ambient_monitoring WHERE id = $1 RETURNING *';
    const result = await pool.query(query, [id]);

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

pool.query(createConsumptionTable)
  .then(() => console.log('Consumption table created or already exists.'))
  .catch(err => console.error('Error creating consumption table:', err));

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

    const result = await pool.query(query, [
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

    const result = await pool.query(query, params);

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
    const result = await pool.query(query);

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
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    latitude DECIMAL,
    longitude DECIMAL,
    photo_url TEXT
  )
`;

pool.query(createTankersTable)
  .then(() => console.log('Tankers table created successfully'))
  .catch(err => console.error('Error creating tankers table:', err));

// Use the existing tankerSchema defined at the top of the file

// POST Endpoint to Add Tanker Data
app.post('/tanker', upload.single('photo'), async (req, res) => {
  try {
    let tankerData;
    
    // Check if the request is multipart form data or JSON
    if (req.is('multipart/form-data')) {
      // Handle multipart form data (from mobile app)
      tankerData = {
        plateNumber: req.body.plateNumber,
        capacity: parseFloat(req.body.capacity),
        driverName: req.body.driverName,
        driverContact: req.body.driverContact,
        vendor: req.body.vendor,
        lastUpdated: req.body.lastUpdated || new Date().toISOString(),
        latitude: req.body.latitude ? parseFloat(req.body.latitude) : null,
        longitude: req.body.longitude ? parseFloat(req.body.longitude) : null,
        photoUrl: req.file ? req.file.location : null
      };
    } else {
      // Handle JSON data (from curl/API requests)
      tankerData = {
        ...req.body,
        capacity: parseFloat(req.body.capacity),
        lastUpdated: req.body.lastUpdated || new Date().toISOString(),
        latitude: req.body.latitude ? parseFloat(req.body.latitude) : null,
        longitude: req.body.longitude ? parseFloat(req.body.longitude) : null
      };
    }

    // Validate the data against schema
    const { error } = tankerSchema.validate(tankerData);
    if (error) {
      console.error('Validation error:', error.details);
      return res.status(400).json({
        success: false,
        message: error.details[0].message
      });
    }

    // Check if tanker exists
    const existingTanker = await pool.query(
      'SELECT * FROM tankers WHERE plate_number = $1',
      [tankerData.plateNumber]
    );

    let result;
    if (existingTanker.rows.length > 0) {
      // Update existing tanker
      result = await pool.query(`
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
    } else {
      // Insert new tanker
      result = await pool.query(`
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
    }

    // Convert snake_case to camelCase for response
    const tanker = {
      id: result.rows[0].id,
      plateNumber: result.rows[0].plate_number,
      capacity: parseFloat(result.rows[0].capacity),
      driverName: result.rows[0].driver_name,
      driverContact: result.rows[0].driver_contact,
      vendor: result.rows[0].vendor,
      lastUpdated: result.rows[0].last_updated,
      latitude: result.rows[0].latitude ? parseFloat(result.rows[0].latitude) : null,
      longitude: result.rows[0].longitude ? parseFloat(result.rows[0].longitude) : null,
      photoUrl: result.rows[0].photo_url
    };

    res.status(existingTanker.rows.length > 0 ? 200 : 201).json({
      success: true,
      message: existingTanker.rows.length > 0 ? 'Tanker updated successfully' : 'Tanker created successfully',
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
      query += ` DATE(last_updated) = $${params.length + 1}`;
      params.push(date);
    }

    query += ' ORDER BY last_updated DESC';

    const result = await pool.query(query, params);
    
    // Convert snake_case to camelCase for frontend
    const tankers = result.rows.map(row => ({
      id: row.id,
      plateNumber: row.plate_number,
      capacity: row.capacity,
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
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

    const result = await pool.query(query, [
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
    const result = await pool.query(query, [id]);

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
    const result = await pool.query(query, [id]);

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

pool.query(createLabourColonyWasteTable)
  .then(() => console.log('Labour Colony Waste table created or already exists.'))
  .catch(err => console.error('Error creating labour colony waste table:', err));

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

    const result = await pool.query(query, values);

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

    const result = await pool.query(query, [
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

    const result = await pool.query(query, [
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

    const result = await pool.query(
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
    waste_type VARCHAR(100),
    disposal_method VARCHAR(100),
    reuse_recycling_details TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

pool.query(createCDWasteTable)
  .then(() => console.log('C&D Waste table created or already exists.'))
  .catch(err => console.error('Error creating C&D waste table:', err));

// Validation Schema
const cdWasteSchema = Joi.object({
  project_area: Joi.number().positive().required(),
  waste_type: Joi.string().required(),
  disposal_method: Joi.string().required(),
  reuse_recycling_details: Joi.string(),
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

    const result = await pool.query(query, params);
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
      date,
      waste_type,
      disposal_method,
      reuse_recycling_details
    } = req.body;

    const waste_amount = project_area * 0.15;

    const query = `
      INSERT INTO cd_waste
      (project_area, waste_amount, date, waste_type, disposal_method, reuse_recycling_details)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `;

    const result = await pool.query(query, [
      project_area,
      waste_amount,
      date,
      waste_type,
      disposal_method,
      reuse_recycling_details
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

pool.query(createCDWasteCalculationTable)
  .then(() => console.log('Waste Calculations table created or already exists.'))
  .catch(err => console.error('Error creating Waste Calculations table:', err));

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

    // Calculate waste amount
    const waste_amount = project_area * WASTE_FACTOR;

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

    const result = await pool.query(query, [
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

    const result = await pool.query(query);

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

    const result = await pool.query(query, [id]);

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

    const result = await pool.query(query, [id]);

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

pool.query(createcd_waste_calcTable)
  .then(() => console.log('C&D Waste Calculation table created or already exists.'))
  .catch(err => console.error('Error creating C&D waste calculation table:', err));

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
    await pool.query(
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
    const result = await pool.query(`SELECT * FROM cd_waste_calc ORDER BY created_at DESC`);
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
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

pool.query(createDailyWasteTable)
  .then(() => console.log('Daily Waste table created or already exists.'))
  .catch(err => console.error('Error creating Daily Waste table:', err));

// Endpoint to add daily waste data
app.post("/daily-waste", async (req, res) => {
  try {
    const { date, quantity_kg, mode_of_storage, mode_of_disposal } = req.body;

    const query = `
      INSERT INTO daily_waste (date, quantity_kg, mode_of_storage, mode_of_disposal)
      VALUES ($1, $2, $3, $4)
      RETURNING *
    `;

    const result = await pool.query(query, [date, quantity_kg, mode_of_storage, mode_of_disposal]);

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
    const query = `
      SELECT
        id,
        date,
        quantity_kg,
        mode_of_storage,
        mode_of_disposal,
        (SELECT SUM(quantity_kg) FROM daily_waste) as total_waste
      FROM daily_waste
      ORDER BY date DESC
    `;

    const result = await pool.query(query);

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

pool.query(createTableQuery)
  .then(() => console.log('Table ready'))
  .catch(err => console.error('Error creating table:', err));

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
    const result = await pool.query(query, params);
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
    const result = await pool.query(query, [date, source, consumption, discharge, discharged_to, mode]);
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
    const result = await pool.query(query, [
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
    const result = await pool.query(
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

(async () => {
  try {
    await pool.query(createTableproject_waste);
    console.log('Table "project_waste" created or already exists.');
  } catch (err) {
    console.error('Error creating table:', err.message);
  }
})();

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
    const result = await pool.query(query, params);

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
    const result = await pool.query(query, [
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
    const result = await pool.query(query, [
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
    const result = await pool.query(
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
pool.query(createbwssb_supplyTable)
  .then(() => pool.query(createUpdateTrigger))
  .then(() => console.log('BWSSB table and trigger created or already exists'))
  .catch(err => console.error('Error creating table:', err));

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

  pool.query(query, params, (err, results) => {
    if (err) {
      console.error('Error fetching data:', err);
      return res.status(500).json({ error: err.message });
    }
    res.json({ data: results.rows });
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

  pool.query(
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

CREATE INDEX idx_labour_colony_consumption_date ON labour_colony_consumption (date);

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
    const result = await pool.query('SELECT * FROM labour_colony_consumption ORDER BY date DESC');
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

    const result = await pool.query(query, [date, source, consumption, discharge, discharged_to, mode]);

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
      query += ` DATE(last_updated) = $${params.length + 1}`;
      params.push(date);
    }

    query += ' ORDER BY last_updated DESC';

    const result = await pool.query(query, params);
    
    // Convert snake_case to camelCase for frontend
    const tankers = result.rows.map(row => ({
      id: row.id,
      plateNumber: row.plate_number,
      capacity: row.capacity,
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
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
        const existingTanker = await pool.query(
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
          result = await pool.query(`
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
          result = await pool.query(`
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
      query += ` DATE(last_updated) = $${params.length + 1}`;
      params.push(date);
    }

    query += ' ORDER BY last_updated DESC';

    const result = await pool.query(query, params);
    
    // Convert snake_case to camelCase for frontend
    const tankers = result.rows.map(row => ({
      id: row.id,
      plateNumber: row.plate_number,
      capacity: row.capacity,
      driverName: row.driver_name,
      driverContact: row.driver_contact,
      vendor: row.vendor,
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
const uploadToS3 = async (fileData, key) => {
  try {
    // Check if S3 client is initialized
    if (!s3Client) {
      throw new Error('S3 client not initialized - file uploads are disabled');
    }

    // Log upload attempt
    logger.info('Attempting S3 upload:', {
      key: key,
      contentType: fileData.mimetype,
      size: fileData.buffer.length
    });

    const upload = new Upload({
      client: s3Client,
      params: {
        Bucket: process.env.AWS_BUCKET_NAME,
        Key: key,
        Body: fileData.buffer,
        ContentType: fileData.mimetype,
        ACL: 'public-read',
        Metadata: {
          'original-filename': fileData.originalname || 'unknown',
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

    return {
      Location: result.Location,
      Key: key,
      ETag: result.ETag
    };
  } catch (error) {
    logger.error('Error uploading to S3:', {
      error: error.message,
      code: error.code,
      key: key,
      requestId: error.$metadata?.requestId
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



// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  pool.end(() => {
    logger.info('Database pool closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  pool.end(() => {
    logger.info('Database pool closed');
    process.exit(0);
  });
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
pool.query(createSystemMetricsHistoryTable)
  .then(() => console.log('system_metrics_history table created or already exists.'))
  .catch(err => console.error('Error creating system_metrics_history table:', err));

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
    await pool.query(
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
    const result = await pool.query(
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

// Execute table creation
Promise.all([
  pool.query(createProjectDocumentsTable),
  pool.query(createDocumentCategoriesTable),
  pool.query(createDocumentIndexes)
]).then(() => {
  logger.info('Document storage tables initialized successfully');
}).catch(err => {
  logger.error('Error creating document storage tables:', err);
});

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

pool.query(insertDefaultCategories)
  .then(() => logger.info('Default document categories inserted'))
  .catch(err => logger.error('Error inserting default categories:', err));

// ===========================================
// VALIDATION SCHEMAS
// ===========================================

const documentSchema = Joi.object({
  name: Joi.string().min(1).max(255).required(),
  category: Joi.string().required(),
  description: Joi.string().max(1000).optional().allow(''),
  tags: Joi.array().items(Joi.string()).optional(),
  status: Joi.string().valid('Active', 'Approved', 'Pending', 'Expired', 'Verified', 'Rejected').default('Active'),
  expiry_date: Joi.date().optional().allow(null)
});

const documentUpload = multer({
  storage: multerS3({
    s3: s3Client,
    bucket: process.env.AWS_BUCKET_NAME,
    acl: 'private', // Documents should be private
    contentType: multerS3.AUTO_CONTENT_TYPE,
    key: function (req, file, cb) {
      if (!s3Client) {
        return cb(new Error('S3 client not initialized - file uploads are disabled'));
      }
      const timestamp = Date.now();
      const sanitizedFileName = file.originalname.replace(/[^a-zA-Z0-9.-]/g, '_');
      const key = `project-documents/${req.user?.id || 'anonymous'}/${timestamp}_${sanitizedFileName}`;
      logger.info('Generated document S3 key:', key);
      cb(null, key);
    },
    metadata: function (req, file, cb) {
      cb(null, { 
        fieldName: file.fieldname,
        originalName: file.originalname,
        uploadedBy: req.user?.id?.toString() || 'anonymous'
      });
    }
  }),
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

    if (!validMimeTypes.includes(file.mimetype)) {
      logger.warn('Invalid document file type:', file.mimetype);
      cb(new Error(`Invalid file type. Allowed types are: PDF, DOC, DOCX, JPG, PNG, XLS, XLSX`), false);
      return;
    }

    logger.info('Document file validation passed');
    cb(null, true);
  },
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit for documents
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
      pool.query(query, params),
      pool.query(countQuery, params.slice(0, -2)) // Remove limit and offset for count
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

    const result = await pool.query(query, [id]);

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

// POST new document
app.post('/api/documents', authenticateToken, documentUpload.single('file'), async (req, res) => {
  try {
    const { error } = documentSchema.validate(req.body);
    if (error) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        error: error.details[0].message
      });
    }

    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No file provided'
      });
    }

    const {
      name,
      category,
      description = '',
      tags = [],
      status = 'Active',
      expiry_date
    } = req.body;

    // Parse tags if they come as a string
    let parsedTags = tags;
    if (typeof tags === 'string') {
      parsedTags = tags.split(',').map(tag => tag.trim()).filter(tag => tag.length > 0);
    }

    const query = `
      INSERT INTO project_documents 
      (name, category, file_path, file_type, file_size, description, tags, status, expiry_date, uploaded_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `;

    const result = await pool.query(query, [
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
    const { error } = documentSchema.validate(req.body);
    if (error) {
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
    } = req.body;

    // Parse tags if they come as a string
    let parsedTags = tags;
    if (typeof tags === 'string') {
      parsedTags = tags.split(',').map(tag => tag.trim()).filter(tag => tag.length > 0);
    }

    const query = `
      UPDATE project_documents 
      SET name = $1, category = $2, description = $3, tags = $4, status = $5, 
          expiry_date = $6, updated_at = CURRENT_TIMESTAMP
      WHERE id = $7 AND (uploaded_by = $8 OR is_asset = false)
      RETURNING *
    `;

    const result = await pool.query(query, [
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
    
    const docResult = await pool.query(getDocQuery, [id]);
    
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

    const result = await pool.query(deleteQuery, [id]);

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

    const result = await pool.query(query);

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
      pool.query(statsQuery),
      pool.query(categoryStatsQuery)
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

    const result = await pool.query(query, [id]);

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
        
        const signedUrl = await s3Client.getSignedUrlPromise('getObject', {
          Bucket: process.env.AWS_BUCKET_NAME,
          Key: key,
          Expires: 3600, // 1 hour
          ResponseContentDisposition: `attachment; filename="${document.name}"`
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
      await pool.query(`
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

    const result = await pool.query(query);

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

    const result = await pool.query(
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
    const dailyResult = await pool.query(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly consumption
    const monthlyQuery = `
      SELECT COALESCE(SUM(water_consumed), 0) as monthly_consumption
      FROM borewell_water 
      WHERE date >= $1 AND date <= $2
    `;
    const monthlyResult = await pool.query(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Cumulative consumption (all time)
    const cumulativeQuery = `
      SELECT COALESCE(SUM(water_consumed), 0) as cumulative_consumption
      FROM borewell_water
    `;
    const cumulativeResult = await pool.query(cumulativeQuery);

    // Period consumption (if date range provided)
    let periodConsumption = cumulativeResult.rows[0].cumulative_consumption;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(water_consumed), 0) as period_consumption
        FROM borewell_water 
        WHERE date >= $1 AND date <= $2
      `;
      const periodResult = await pool.query(periodQuery, [fromDate, toDate]);
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
    const dailyResult = await pool.query(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly deliveries
    const monthlyQuery = `
      SELECT COALESCE(SUM(capacity), 0) as monthly_capacity
      FROM tankers 
      WHERE DATE(last_updated) >= $1 AND DATE(last_updated) <= $2
    `;
    const monthlyResult = await pool.query(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Total tanker capacity (all active tankers)
    const cumulativeQuery = `
      SELECT COALESCE(SUM(capacity), 0) as total_capacity
      FROM tankers
    `;
    const cumulativeResult = await pool.query(cumulativeQuery);

    // Period consumption
    let periodConsumption = cumulativeResult.rows[0].total_capacity;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(capacity), 0) as period_capacity
        FROM tankers 
        WHERE DATE(last_updated) >= $1 AND DATE(last_updated) <= $2
      `;
      const periodResult = await pool.query(periodQuery, [fromDate, toDate]);
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
    const dailyResult = await pool.query(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly consumption
    const monthlyQuery = `
      SELECT COALESCE(SUM(quantity_supplied), 0) as monthly_consumption
      FROM bwssb_supply 
      WHERE supply_date >= $1 AND supply_date <= $2
    `;
    const monthlyResult = await pool.query(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Cumulative consumption
    const cumulativeQuery = `
      SELECT COALESCE(SUM(quantity_supplied), 0) as cumulative_consumption
      FROM bwssb_supply
    `;
    const cumulativeResult = await pool.query(cumulativeQuery);

    // Period consumption
    let periodConsumption = cumulativeResult.rows[0].cumulative_consumption;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(quantity_supplied), 0) as period_consumption
        FROM bwssb_supply 
        WHERE supply_date >= $1 AND supply_date <= $2
      `;
      const periodResult = await pool.query(periodQuery, [fromDate, toDate]);
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
    const dailyResult = await pool.query(dailyQuery, [targetDate.toISOString().split('T')[0]]);

    // Monthly consumption
    const monthlyQuery = `
      SELECT COALESCE(SUM(consumption), 0) as monthly_consumption
      FROM labour_colony 
      WHERE date >= $1 AND date <= $2
    `;
    const monthlyResult = await pool.query(monthlyQuery, [
      firstDay.toISOString().split('T')[0],
      lastDay.toISOString().split('T')[0]
    ]);

    // Cumulative consumption
    const cumulativeQuery = `
      SELECT COALESCE(SUM(consumption), 0) as cumulative_consumption
      FROM labour_colony
    `;
    const cumulativeResult = await pool.query(cumulativeQuery);

    // Period consumption
    let periodConsumption = cumulativeResult.rows[0].cumulative_consumption;
    if (fromDate && toDate) {
      const periodQuery = `
        SELECT COALESCE(SUM(consumption), 0) as period_consumption
        FROM labour_colony 
        WHERE date >= $1 AND date <= $2
      `;
      const periodResult = await pool.query(periodQuery, [fromDate, toDate]);
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

// Dashboard endpoint for charts and real-time data
app.get('/water-consumption/dashboard', async (req, res) => {
  try {
    const { days = 7 } = req.query;
    
    console.log(`Fetching dashboard data for last ${days} days`);
    
    // Get consumption data for the last N days for charts
    const chartQuery = `
      SELECT 
        date,
        'borewell' as source,
        SUM(water_consumed) as consumption
      FROM borewell_water 
      WHERE date >= CURRENT_DATE - INTERVAL '${days} days'
      GROUP BY date
      
      UNION ALL
      
      SELECT 
        supply_date as date,
        'bwssb' as source,
        SUM(quantity_supplied) as consumption
      FROM bwssb_supply
      WHERE supply_date >= CURRENT_DATE - INTERVAL '${days} days'
      GROUP BY supply_date
      
      UNION ALL
      
      SELECT 
        date,
        'labour_colony' as source,
        SUM(consumption) as consumption
      FROM labour_colony
      WHERE date >= CURRENT_DATE - INTERVAL '${days} days'
      GROUP BY date
      
      ORDER BY date DESC
    `;

    const chartData = await pool.query(chartQuery);

    // Get current totals
    const totalsQuery = `
      SELECT 
        (SELECT COALESCE(SUM(water_consumed), 0) FROM borewell_water) as total_borewell,
        (SELECT COALESCE(SUM(quantity_supplied), 0) FROM bwssb_supply) as total_bwssb,
        (SELECT COALESCE(SUM(consumption), 0) FROM labour_colony) as total_labour_colony,
        (SELECT COALESCE(SUM(capacity), 0) FROM tankers) as total_tanker_capacity
    `;

    const totals = await pool.query(totalsQuery);

    const responseData = {
      success: true,
      data: {
        chartData: chartData.rows,
        totals: totals.rows[0],
        lastUpdated: new Date().toISOString()
      }
    };

    console.log('Dashboard data response:', responseData);
    res.status(200).json(responseData);

  } catch (err) {
    console.error('Error fetching dashboard data:', err);
    res.status(500).json({ 
      success: false,
      error: 'Internal server error'
    });
  }
});

console.log('Water consumption summary endpoints added successfully');


app.get('/water-consumption/phase-summary/:phase', async (req, res) => {
  const { phase } = req.params;
  const { date, fromDate, toDate } = req.query;

  try {
    const targetDate = date ? new Date(date) : new Date();
    if (isNaN(targetDate)) {
      return res.status(400).json({ error: 'Invalid date format' });
    }

    const { firstDay, lastDay } = getMonthDateRange(targetDate);

    const periodFrom = fromDate ? new Date(fromDate) : null;
    const periodTo = toDate ? new Date(toDate) : null;

    if ((periodFrom && isNaN(periodFrom)) || (periodTo && isNaN(periodTo))) {
        return res.status(400).json({ error: 'Invalid period date format' });
    }

    const query = `
      SELECT
        source,
        COALESCE(SUM(CASE WHEN "createdAt"::date = $1 THEN "quantityInKLD" ELSE 0 END), 0) AS daily,
        COALESCE(SUM(CASE WHEN "createdAt" >= $2 AND "createdAt" <= $3 THEN "quantityInKLD" ELSE 0 END), 0) AS monthly,
        COALESCE(SUM("quantityInKLD"), 0) AS cumulative,
        COALESCE(SUM(CASE WHEN $4::date IS NOT NULL AND $5::date IS NOT NULL AND "createdAt"::date >= $4 AND "createdAt"::date <= $5 THEN "quantityInKLD" ELSE 0 END), 0) AS period
      FROM water_consumption
      WHERE phase = $6
      GROUP BY source;
    `;

    const result = await pool.query(query, [
        targetDate.toISOString().split('T')[0],
        firstDay.toISOString().split('T')[0],
        lastDay.toISOString().split('T')[0],
        periodFrom ? periodFrom.toISOString().split('T')[0] : null,
        periodTo ? periodTo.toISOString().split('T')[0] : null,
        phase
    ]);

    const summary = {
      borewell: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
      tanker: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
      bwssb: { daily: 0, monthly: 0, cumulative: 0, period: 0 },
      others: { daily: 0, monthly: 0, cumulative: 0, period: 0 }
    };

    result.rows.forEach(row => {
      const source = row.source.toLowerCase();
      if (summary[source]) {
        summary[source] = {
          daily: safeParseFloat(row.daily),
          monthly: safeParseFloat(row.monthly),
          cumulative: safeParseFloat(row.cumulative),
          period: safeParseFloat(row.period)
        };
      }
    });

    res.json({ data: summary });
  } catch (error) {
    logger.error(`Error fetching water consumption for phase ${phase}:`, error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});



// Enhanced Document Management System with Intelligence
// Add this to your existing Node.js server

// ===========================================
// ENHANCED DATABASE SCHEMA
// ===========================================

const createEnhancedProjectDocumentsTable = `
  CREATE TABLE IF NOT EXISTS enhanced_project_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL,
    file_path TEXT NOT NULL,
    file_type VARCHAR(50) NOT NULL,
    file_size BIGINT,
    
    -- Common Project Information
    project_name VARCHAR(255),
    project_address TEXT,
    built_up_area DECIMAL(10,2), -- in sq ft
    plot_area DECIMAL(10,2), -- in sq ft
    floor_area_ratio DECIMAL(5,2),
    
    -- Authority and Approval Information
    issuing_authority VARCHAR(255),
    approval_number VARCHAR(255),
    application_number VARCHAR(255),
    contact_person VARCHAR(255),
    contact_phone VARCHAR(20),
    contact_email VARCHAR(255),
    
    -- Validity and Timeline Information
    date_added TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    application_date DATE,
    approval_date DATE,
    validity_start_date DATE,
    validity_end_date DATE,
    renewal_due_date DATE,
    
    -- Status and Classification
    status VARCHAR(50) DEFAULT 'Active',
    priority_level VARCHAR(20) DEFAULT 'Medium', -- Low, Medium, High, Critical
    compliance_status VARCHAR(50) DEFAULT 'Compliant', -- Compliant, Non-Compliant, Under Review, Expired
    
    -- Document Relationships
    depends_on_documents UUID[], -- Array of document IDs this document depends on
    prerequisite_for UUID[], -- Array of document IDs that depend on this document
    
    -- Additional Metadata
    description TEXT,
    tags TEXT[],
    conditions_attached TEXT,
    renewal_process TEXT,
    fees_paid DECIMAL(10,2),
    
    -- System Fields
    is_asset BOOLEAN DEFAULT false,
    uploaded_by INTEGER REFERENCES users(id),
    last_validated_at TIMESTAMP WITH TIME ZONE,
    validation_status VARCHAR(50) DEFAULT 'Pending', -- Pending, Valid, Invalid, Needs_Review
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

const createDocumentValidationRulesTable = `
  CREATE TABLE IF NOT EXISTS document_validation_rules (
    id SERIAL PRIMARY KEY,
    rule_name VARCHAR(255) NOT NULL,
    rule_type VARCHAR(100) NOT NULL, -- consistency, expiry, dependency, completeness
    source_category VARCHAR(100),
    target_category VARCHAR(100),
    field_name VARCHAR(100),
    validation_logic JSONB, -- Store complex validation rules
    severity VARCHAR(20) DEFAULT 'Medium', -- Low, Medium, High, Critical
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

const createDocumentAlertsTable = `
  CREATE TABLE IF NOT EXISTS document_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID REFERENCES enhanced_project_documents(id),
    alert_type VARCHAR(100) NOT NULL, -- expiry, inconsistency, missing, renewal
    severity VARCHAR(20) NOT NULL, -- Low, Medium, High, Critical
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    suggested_action TEXT,
    due_date DATE,
    is_resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolved_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

const createDocumentComplianceHistoryTable = `
  CREATE TABLE IF NOT EXISTS document_compliance_history (
    id SERIAL PRIMARY KEY,
    document_id UUID REFERENCES enhanced_project_documents(id),
    compliance_check_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    compliance_status VARCHAR(50),
    issues_found JSONB,
    actions_taken TEXT,
    checked_by INTEGER REFERENCES users(id)
  )
`;

// Execute enhanced table creation
Promise.all([
  pool.query(createEnhancedProjectDocumentsTable),
  pool.query(createDocumentValidationRulesTable),
  pool.query(createDocumentAlertsTable),
  pool.query(createDocumentComplianceHistoryTable)
]).then(() => {
  logger.info('Enhanced document management tables created successfully');
}).catch(err => {
  logger.error('Error creating enhanced document management tables:', err);
});

// ===========================================
// DOCUMENT INTELLIGENCE SERVICE
// ===========================================

class DocumentIntelligenceService {
  
  // Validate document consistency
  static async validateDocumentConsistency(documentId = null) {
    try {
      let documents;
      
      if (documentId) {
        const result = await pool.query(
          'SELECT * FROM enhanced_project_documents WHERE id = $1',
          [documentId]
        );
        documents = result.rows;
      } else {
        const result = await pool.query(
          'SELECT * FROM enhanced_project_documents WHERE is_asset = false'
        );
        documents = result.rows;
      }

      const inconsistencies = [];
      
      // Group documents by project_name
      const projectGroups = {};
      documents.forEach(doc => {
        const projectName = doc.project_name || 'Unknown Project';
        if (!projectGroups[projectName]) {
          projectGroups[projectName] = [];
        }
        projectGroups[projectName].push(doc);
      });

      // Check consistency within each project
      for (const [projectName, projectDocs] of Object.entries(projectGroups)) {
        if (projectDocs.length < 2) continue;

        const baseDoc = projectDocs[0];
        const fieldsToCheck = [
          'project_address',
          'built_up_area', 
          'plot_area',
          'contact_person',
          'contact_email'
        ];

        for (let i = 1; i < projectDocs.length; i++) {
          const currentDoc = projectDocs[i];
          
          for (const field of fieldsToCheck) {
            if (baseDoc[field] && currentDoc[field] && 
                baseDoc[field] !== currentDoc[field]) {
              
              inconsistencies.push({
                type: 'field_mismatch',
                severity: 'Medium',
                project_name: projectName,
                field: field,
                document1: {
                  id: baseDoc.id,
                  name: baseDoc.name,
                  value: baseDoc[field]
                },
                document2: {
                  id: currentDoc.id,
                  name: currentDoc.name,
                  value: currentDoc[field]
                },
                suggestion: `Review ${field} consistency between ${baseDoc.name} and ${currentDoc.name}`
              });
            }
          }
        }
      }

      return inconsistencies;
    } catch (error) {
      logger.error('Error validating document consistency:', error);
      throw error;
    }
  }

  // Check for expiring documents
  static async checkExpiringDocuments(daysAhead = 30) {
    try {
      const query = `
        SELECT 
          id, name, category, validity_end_date, renewal_due_date,
          project_name, issuing_authority,
          CASE 
            WHEN validity_end_date IS NOT NULL THEN 
              EXTRACT(DAYS FROM validity_end_date - CURRENT_DATE)
            WHEN renewal_due_date IS NOT NULL THEN 
              EXTRACT(DAYS FROM renewal_due_date - CURRENT_DATE)
            ELSE NULL
          END as days_until_expiry
        FROM enhanced_project_documents
        WHERE 
          (validity_end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '${daysAhead} days'
           OR renewal_due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '${daysAhead} days')
          AND compliance_status != 'Expired'
        ORDER BY 
          LEAST(
            COALESCE(validity_end_date, '2099-12-31'::date),
            COALESCE(renewal_due_date, '2099-12-31'::date)
          ) ASC
      `;

      const result = await pool.query(query);
      return result.rows.map(doc => ({
        ...doc,
        alert_type: doc.days_until_expiry <= 7 ? 'Critical' : 
                   doc.days_until_expiry <= 15 ? 'High' : 'Medium',
        suggested_action: this.getExpiryAction(doc)
      }));
    } catch (error) {
      logger.error('Error checking expiring documents:', error);
      throw error;
    }
  }

  // Get suggested action for expiring documents
  static getExpiryAction(document) {
    const days = document.days_until_expiry;
    const category = document.category;
    
    if (days <= 7) {
      return `URGENT: ${document.name} expires in ${days} days. Contact ${document.issuing_authority} immediately for renewal.`;
    } else if (days <= 15) {
      return `${document.name} expires in ${days} days. Start renewal process with ${document.issuing_authority}.`;
    } else {
      return `${document.name} expires in ${days} days. Prepare renewal documents.`;
    }
  }

  // Check for missing required documents
  static async checkMissingDocuments(projectName) {
    try {
      const requiredDocuments = {
        'environmental': ['KSPCB CFE', 'Environmental Clearances'],
        'planning': ['BBMP Plan Sanction', 'Airport Clearance'],
        'utilities': ['SGWA', 'BESCOM Clearances'],
        'legal': ['Land Document'],
        'safety': ['Fire NOC']
      };

      const existingDocsResult = await pool.query(
        'SELECT category, name FROM enhanced_project_documents WHERE project_name = $1',
        [projectName]
      );

      const existingDocs = {};
      existingDocsResult.rows.forEach(doc => {
        if (!existingDocs[doc.category]) {
          existingDocs[doc.category] = [];
        }
        existingDocs[doc.category].push(doc.name);
      });

      const missingDocs = [];
      for (const [category, required] of Object.entries(requiredDocuments)) {
        const existing = existingDocs[category] || [];
        for (const reqDoc of required) {
          if (!existing.some(ex => ex.includes(reqDoc))) {
            missingDocs.push({
              category,
              document_name: reqDoc,
              severity: 'High',
              suggestion: `Upload ${reqDoc} for ${category} compliance`
            });
          }
        }
      }

      return missingDocs;
    } catch (error) {
      logger.error('Error checking missing documents:', error);
      throw error;
    }
  }

  // Analyze document dependencies
  static async analyzeDependencies(documentId) {
    try {
      const dependencyRules = {
        'BBMP Plan Sanction': ['Land Document'],
        'KSPCB CFE': ['BBMP Plan Sanction', 'Environmental Clearances'],
        'Fire NOC': ['BBMP Plan Sanction'],
        'BESCOM Clearances': ['BBMP Plan Sanction'],
        'SGWA': ['Environmental Clearances']
      };

      const docResult = await pool.query(
        'SELECT * FROM enhanced_project_documents WHERE id = $1',
        [documentId]
      );

      if (docResult.rows.length === 0) {
        throw new Error('Document not found');
      }

      const document = docResult.rows[0];
      const requiredDocs = dependencyRules[document.name] || [];
      
      if (requiredDocs.length === 0) {
        return { satisfied: true, missing: [] };
      }

      const projectDocsResult = await pool.query(
        'SELECT name, status FROM enhanced_project_documents WHERE project_name = $1',
        [document.project_name]
      );

      const projectDocs = projectDocsResult.rows;
      const missing = [];

      for (const reqDoc of requiredDocs) {
        const exists = projectDocs.some(pd => 
          pd.name.includes(reqDoc) && pd.status === 'Approved'
        );
        
        if (!exists) {
          missing.push({
            document_name: reqDoc,
            status: 'Missing or not approved',
            impact: `${document.name} may not be valid without ${reqDoc}`
          });
        }
      }

      return {
        satisfied: missing.length === 0,
        missing: missing
      };
    } catch (error) {
      logger.error('Error analyzing dependencies:', error);
      throw error;
    }
  }

  // Generate comprehensive document health report
  static async generateHealthReport(projectName = null) {
    try {
      const [
        inconsistencies,
        expiringDocs,
        missingDocs
      ] = await Promise.all([
        this.validateDocumentConsistency(),
        this.checkExpiringDocuments(60),
        projectName ? this.checkMissingDocuments(projectName) : []
      ]);

      // Calculate health score
      const totalIssues = inconsistencies.length + expiringDocs.length + missingDocs.length;
      const criticalIssues = [
        ...inconsistencies.filter(i => i.severity === 'Critical'),
        ...expiringDocs.filter(e => e.alert_type === 'Critical'),
        ...missingDocs.filter(m => m.severity === 'Critical')
      ].length;

      let healthScore = 100;
      healthScore -= (criticalIssues * 20);
      healthScore -= ((totalIssues - criticalIssues) * 5);
      healthScore = Math.max(0, healthScore);

      let healthStatus = 'Excellent';
      if (healthScore < 60) healthStatus = 'Poor';
      else if (healthScore < 80) healthStatus = 'Fair';
      else if (healthScore < 95) healthStatus = 'Good';

      return {
        health_score: healthScore,
        health_status: healthStatus,
        summary: {
          total_issues: totalIssues,
          critical_issues: criticalIssues,
          expiring_documents: expiringDocs.length,
          inconsistencies: inconsistencies.length,
          missing_documents: missingDocs.length
        },
        details: {
          inconsistencies,
          expiring_documents: expiringDocs,
          missing_documents: missingDocs
        },
        recommendations: this.generateRecommendations(inconsistencies, expiringDocs, missingDocs)
      };
    } catch (error) {
      logger.error('Error generating health report:', error);
      throw error;
    }
  }

  // Generate action recommendations
  static generateRecommendations(inconsistencies, expiringDocs, missingDocs) {
    const recommendations = [];

    // Priority actions for expiring documents
    const criticalExpiring = expiringDocs.filter(d => d.alert_type === 'Critical');
    if (criticalExpiring.length > 0) {
      recommendations.push({
        priority: 'Critical',
        action: 'Immediate Renewal Required',
        description: `${criticalExpiring.length} documents expire within 7 days`,
        items: criticalExpiring.map(d => d.name)
      });
    }

    // Address inconsistencies
    if (inconsistencies.length > 0) {
      const projectsWithIssues = [...new Set(inconsistencies.map(i => i.project_name))];
      recommendations.push({
        priority: 'High',
        action: 'Resolve Data Inconsistencies',
        description: `Found ${inconsistencies.length} inconsistencies across ${projectsWithIssues.length} projects`,
        items: inconsistencies.slice(0, 3).map(i => i.suggestion)
      });
    }

    // Upload missing documents
    if (missingDocs.length > 0) {
      recommendations.push({
        priority: 'Medium',
        action: 'Complete Document Collection',
        description: `${missingDocs.length} required documents are missing`,
        items: missingDocs.slice(0, 3).map(m => m.document_name)
      });
    }

    return recommendations;
  }
}

// ===========================================
// ENHANCED API ENDPOINTS
// ===========================================

// Get document health dashboard
app.get('/api/documents/health-dashboard', authenticateToken, async (req, res) => {
  try {
    const { project_name } = req.query;
    
    const healthReport = await DocumentIntelligenceService.generateHealthReport(project_name);
    
    res.status(200).json({
      success: true,
      data: healthReport
    });
  } catch (error) {
    logger.error('Error fetching document health dashboard:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch health dashboard',
      error: error.message
    });
  }
});

// Get document inconsistencies
app.get('/api/documents/inconsistencies', authenticateToken, async (req, res) => {
  try {
    const { document_id } = req.query;
    
    const inconsistencies = await DocumentIntelligenceService.validateDocumentConsistency(document_id);
    
    res.status(200).json({
      success: true,
      data: inconsistencies
    });
  } catch (error) {
    logger.error('Error fetching document inconsistencies:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch inconsistencies',
      error: error.message
    });
  }
});

// Get expiring documents
app.get('/api/documents/expiring', authenticateToken, async (req, res) => {
  try {
    const { days_ahead = 30 } = req.query;
    
    const expiringDocs = await DocumentIntelligenceService.checkExpiringDocuments(parseInt(days_ahead));
    
    res.status(200).json({
      success: true,
      data: expiringDocs
    });
  } catch (error) {
    logger.error('Error fetching expiring documents:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch expiring documents',
      error: error.message
    });
  }
});

// Analyze document dependencies
app.get('/api/documents/:id/dependencies', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    const dependencies = await DocumentIntelligenceService.analyzeDependencies(id);
    
    res.status(200).json({
      success: true,
      data: dependencies
    });
  } catch (error) {
    logger.error('Error analyzing document dependencies:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to analyze dependencies',
      error: error.message
    });
  }
});

// Create or update enhanced document
app.post('/api/enhanced-documents', authenticateToken, documentUpload.single('file'), async (req, res) => {
  try {
    const {
      name, category, project_name, project_address, built_up_area, plot_area,
      issuing_authority, approval_number, application_number,
      contact_person, contact_phone, contact_email,
      application_date, approval_date, validity_start_date, validity_end_date,
      renewal_due_date, status, priority_level, description, tags,
      conditions_attached, renewal_process, fees_paid
    } = req.body;

    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No file provided'
      });
    }

    // Parse tags if they come as a string
    let parsedTags = tags;
    if (typeof tags === 'string') {
      parsedTags = tags.split(',').map(tag => tag.trim()).filter(tag => tag.length > 0);
    }

    const query = `
      INSERT INTO enhanced_project_documents 
      (name, category, file_path, file_type, file_size,
       project_name, project_address, built_up_area, plot_area,
       issuing_authority, approval_number, application_number,
       contact_person, contact_phone, contact_email,
       application_date, approval_date, validity_start_date, validity_end_date,
       renewal_due_date, status, priority_level, description, tags,
       conditions_attached, renewal_process, fees_paid, uploaded_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
              $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28)
      RETURNING *
    `;

    const result = await pool.query(query, [
      name, category, req.file.location, req.file.mimetype, req.file.size,
      project_name, project_address, built_up_area ? parseFloat(built_up_area) : null, 
      plot_area ? parseFloat(plot_area) : null,
      issuing_authority, approval_number, application_number,
      contact_person, contact_phone, contact_email,
      application_date || null, approval_date || null, 
      validity_start_date || null, validity_end_date || null,
      renewal_due_date || null, status || 'Active', priority_level || 'Medium',
      description, parsedTags, conditions_attached, renewal_process,
      fees_paid ? parseFloat(fees_paid) : null, req.user.id
    ]);

    // Trigger validation after document creation
    setTimeout(async () => {
      try {
        await DocumentIntelligenceService.validateDocumentConsistency(result.rows[0].id);
      } catch (error) {
        logger.error('Error in post-creation validation:', error);
      }
    }, 1000);

    logger.info(`Enhanced document uploaded successfully: ${name} by user ${req.user.id}`);

    res.status(201).json({
      success: true,
      message: 'Enhanced document uploaded successfully',
      data: result.rows[0]
    });

  } catch (error) {
    logger.error('Error uploading enhanced document:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to upload enhanced document',
      error: error.message
    });
  }
});

// Get enhanced documents with intelligence
app.get('/api/enhanced-documents', authenticateToken, async (req, res) => {
  try {
    const { 
      page = 1, limit = 20, category, status, project_name, 
      search, sort_by = 'created_at', sort_order = 'DESC',
      include_health = false
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

    if (project_name) {
      whereConditions.push(`project_name = $${params.length + 1}`);
      params.push(project_name);
    }

    if (search) {
      whereConditions.push(`(
        name ILIKE $${params.length + 1} OR 
        description ILIKE $${params.length + 1} OR 
        project_name ILIKE $${params.length + 1} OR
        approval_number ILIKE $${params.length + 1}
      )`);
      params.push(`%${search}%`);
    }

    const whereClause = whereConditions.length > 0 ? `WHERE ${whereConditions.join(' AND ')}` : '';

    const validSortColumns = ['name', 'created_at', 'category', 'status', 'validity_end_date', 'priority_level'];
    const sortColumn = validSortColumns.includes(sort_by) ? sort_by : 'created_at';
    const sortDirection = sort_order.toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

    const query = `
      SELECT 
        *,
        CASE 
          WHEN validity_end_date IS NOT NULL AND validity_end_date < CURRENT_DATE THEN true 
          ELSE false 
        END as is_expired,
        CASE 
          WHEN validity_end_date IS NOT NULL AND validity_end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days' THEN true 
          WHEN renewal_due_date IS NOT NULL AND renewal_due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days' THEN true
          ELSE false 
        END as is_expiring_soon,
        CASE 
          WHEN validity_end_date IS NOT NULL THEN 
            EXTRACT(DAYS FROM validity_end_date - CURRENT_DATE)
          WHEN renewal_due_date IS NOT NULL THEN 
            EXTRACT(DAYS FROM renewal_due_date - CURRENT_DATE)
          ELSE NULL
        END as days_until_expiry
      FROM enhanced_project_documents 
      ${whereClause}
      ORDER BY ${sortColumn} ${sortDirection}
      LIMIT $${params.length + 1} OFFSET $${params.length + 2}
    `;

    params.push(limit, offset);

    const countQuery = `
      SELECT COUNT(*) as total 
      FROM enhanced_project_documents 
      ${whereClause}
    `;

    const [documents, countResult] = await Promise.all([
      pool.query(query, params),
      pool.query(countQuery, params.slice(0, -2))
    ]);

    let healthData = null;
    if (include_health === 'true') {
      healthData = await DocumentIntelligenceService.generateHealthReport(project_name);
    }

    const total = parseInt(countResult.rows[0].total);
    const totalPages = Math.ceil(total / limit);

    res.status(200).json({
      success: true,
      data: documents.rows,
      health: healthData,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: total,
        totalPages: totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1
      }
    });

  } catch (error) {
    logger.error('Error fetching enhanced documents:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch enhanced documents',
      error: error.message
    });
  }
});

// Run validation check manually
app.post('/api/documents/validate', authenticateToken, async (req, res) => {
  try {
    const { document_id, project_name } = req.body;
    
    const [inconsistencies, dependencies] = await Promise.all([
      DocumentIntelligenceService.validateDocumentConsistency(document_id),
      document_id ? DocumentIntelligenceService.analyzeDependencies(document_id) : null
    ]);

    res.status(200).json({
      success: true,
      data: {
        inconsistencies,
        dependencies,
        validation_timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Error running validation:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to run validation',
      error: error.message
    });
  }
});

logger.info('Enhanced document intelligence system initialized successfully');




const seedValidationRules = async () => {
  try {
    const validationRules = [
      {
        rule_name: 'Project Name Consistency',
        rule_type: 'consistency',
        source_category: 'environmental',
        target_category: 'planning',
        field_name: 'project_name',
        validation_logic: {
          type: 'field_match',
          description: 'Project name should be consistent across all documents'
        },
        severity: 'High'
      },
      {
        rule_name: 'Project Address Consistency',
        rule_type: 'consistency',
        source_category: 'legal',
        target_category: 'planning',
        field_name: 'project_address',
        validation_logic: {
          type: 'field_match',
          description: 'Project address should match between land documents and planning approvals'
        },
        severity: 'High'
      },
      {
        rule_name: 'Built-up Area Consistency',
        rule_type: 'consistency',
        source_category: 'planning',
        target_category: 'environmental',
        field_name: 'built_up_area',
        validation_logic: {
          type: 'field_match',
          tolerance: 50,
          description: 'Built-up area should be consistent within tolerance limits'
        },
        severity: 'Medium'
      },
      {
        rule_name: 'Contact Person Consistency',
        rule_type: 'consistency',
        source_category: null,
        target_category: null,
        field_name: 'contact_person',
        validation_logic: {
          type: 'field_match',
          description: 'Contact person should be consistent across project documents'
        },
        severity: 'Low'
      },
      {
        rule_name: 'Environmental Clearance Expiry',
        rule_type: 'expiry',
        source_category: 'environmental',
        target_category: null,
        field_name: 'validity_end_date',
        validation_logic: {
          type: 'expiry_check',
          warning_days: 60,
          critical_days: 30,
          description: 'Environmental clearances require 60-day advance renewal notice'
        },
        severity: 'Critical'
      },
      {
        rule_name: 'Fire NOC Expiry',
        rule_type: 'expiry',
        source_category: 'safety',
        target_category: null,
        field_name: 'validity_end_date',
        validation_logic: {
          type: 'expiry_check',
          warning_days: 45,
          critical_days: 15,
          description: 'Fire NOC requires advance renewal for continuous compliance'
        },
        severity: 'High'
      },
      {
        rule_name: 'KSPCB CFE Dependency',
        rule_type: 'dependency',
        source_category: 'environmental',
        target_category: 'planning',
        field_name: null,
        validation_logic: {
          type: 'prerequisite_check',
          required_documents: ['Land Document', 'BBMP Plan Sanction'],
          description: 'KSPCB CFE requires valid land documents and building plan sanction'
        },
        severity: 'Critical'
      },
      {
        rule_name: 'Fire NOC Dependency',
        rule_type: 'dependency',
        source_category: 'safety',
        target_category: 'planning',
        field_name: null,
        validation_logic: {
          type: 'prerequisite_check',
          required_documents: ['BBMP Plan Sanction'],
          description: 'Fire NOC requires approved building plans'
        },
        severity: 'High'
      },
      {
        rule_name: 'Complete Environmental Package',
        rule_type: 'completeness',
        source_category: 'environmental',
        target_category: null,
        field_name: null,
        validation_logic: {
          type: 'document_set_check',
          required_documents: ['KSPCB CFE', 'Environmental Clearances', 'SGWA'],
          description: 'Complete environmental compliance requires all clearances'
        },
        severity: 'High'
      },
      {
        rule_name: 'Complete Planning Package',
        rule_type: 'completeness',
        source_category: 'planning',
        target_category: null,
        field_name: null,
        validation_logic: {
          type: 'document_set_check',
          required_documents: ['BBMP Plan Sanction', 'Airport Clearance'],
          description: 'Complete planning approval requires all planning documents'
        },
        severity: 'Medium'
      }
    ];

    for (const rule of validationRules) {
      await pool.query(`
        INSERT INTO document_validation_rules 
        (rule_name, rule_type, source_category, target_category, field_name, validation_logic, severity)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (rule_name) DO UPDATE SET
          rule_type = $2,
          source_category = $3,
          target_category = $4,
          field_name = $5,
          validation_logic = $6,
          severity = $7,
          is_active = true
      `, [
        rule.rule_name,
        rule.rule_type,
        rule.source_category,
        rule.target_category,
        rule.field_name,
        JSON.stringify(rule.validation_logic),
        rule.severity
      ]);
    }

    logger.info('Validation rules seeded successfully');
  } catch (error) {
    logger.error('Error seeding validation rules:', error);
  }
};

// ===========================================
// SEED ENHANCED DEFAULT DOCUMENTS
// ===========================================

const seedEnhancedDefaultDocuments = async () => {
  try {
    const defaultDocuments = [
      {
        name: 'KSPCB CFE',
        category: 'environmental',
        file_path: 'assets/cfe1.pdf',
        file_type: 'application/pdf',
        project_name: 'Prestige Park Groove',
        project_address: 'Whitefield, Bangalore, Karnataka 560066',
        built_up_area: 2500000.00, // 25 lakh sq ft
        plot_area: 5000000.00, // 50 lakh sq ft
        floor_area_ratio: 0.50,
        issuing_authority: 'Karnataka State Pollution Control Board',
        approval_number: 'KSPCB/CFE/2023/001234',
        application_number: 'APP/ENV/2023/5678',
        contact_person: 'Dr. Rajesh Kumar',
        contact_phone: '+91-80-12345678',
        contact_email: 'rajesh.kumar@kspcb.gov.in',
        application_date: new Date('2023-01-15'),
        approval_date: new Date('2023-03-20'),
        validity_start_date: new Date('2023-03-20'),
        validity_end_date: new Date('2028-03-19'),
        renewal_due_date: new Date('2027-12-20'),
        status: 'Approved',
        priority_level: 'Critical',
        compliance_status: 'Compliant',
        description: 'Consent for Establishment from Karnataka State Pollution Control Board for construction activities',
        tags: ['KSPCB', 'Environmental', 'Mandatory', 'Construction'],
        conditions_attached: 'Regular monitoring of air and water quality required. Monthly compliance reports to be submitted.',
        renewal_process: 'Apply for renewal 90 days before expiry with updated environmental impact assessment.',
        fees_paid: 150000.00,
        is_asset: true
      },
      {
        name: 'Environmental Clearances',
        category: 'environmental',
        file_path: 'assets/ENvironmental.pdf',
        file_type: 'application/pdf',
        project_name: 'Prestige Park Groove',
        project_address: 'Whitefield, Bangalore, Karnataka 560066',
        built_up_area: 2500000.00,
        plot_area: 5000000.00,
        issuing_authority: 'Ministry of Environment, Forest and Climate Change',
        approval_number: 'MoEF/EC/2023/7890',
        application_number: 'ENV/CLEAR/2023/1122',
        contact_person: 'Smt. Priya Sharma',
        contact_phone: '+91-11-87654321',
        contact_email: 'priya.sharma@moef.gov.in',
        application_date: new Date('2022-10-01'),
        approval_date: new Date('2023-02-15'),
        validity_start_date: new Date('2023-02-15'),
        validity_end_date: new Date('2033-02-14'),
        status: 'Approved',
        priority_level: 'Critical',
        compliance_status: 'Compliant',
        description: 'Environmental impact assessment and clearance for large-scale construction project',
        tags: ['Environmental', 'Clearance', 'MoEF', 'Impact Assessment'],
        conditions_attached: 'Implementation of environmental management plan. Quarterly biodiversity monitoring required.',
        renewal_process: 'Submit comprehensive environmental compliance report before expiry.',
        fees_paid: 500000.00,
        is_asset: true
      },
      {
        name: 'BBMP Plan Sanction',
        category: 'planning',
        file_path: 'assets/Conversion Certificate.pdf',
        file_type: 'application/pdf',
        project_name: 'Prestige Park Groove',
        project_address: 'Whitefield, Bangalore, Karnataka 560066',
        built_up_area: 2500000.00,
        plot_area: 5000000.00,
        floor_area_ratio: 0.50,
        issuing_authority: 'Bruhat Bengaluru Mahanagara Palike',
        approval_number: 'BBMP/PLAN/2023/WF456',
        application_number: 'PLAN/APP/2023/789',
        contact_person: 'Sri. Manjunath Reddy',
        contact_phone: '+91-80-22334455',
        contact_email: 'manjunath.reddy@bbmp.gov.in',
        application_date: new Date('2022-08-15'),
        approval_date: new Date('2023-01-10'),
        validity_start_date: new Date('2023-01-10'),
        validity_end_date: new Date('2026-01-09'),
        status: 'Approved',
        priority_level: 'Critical',
        compliance_status: 'Compliant',
        description: 'Building plan sanction from BBMP for residential township development',
        tags: ['BBMP', 'Planning', 'Building', 'Sanction'],
        conditions_attached: 'Compliance with building bylaws. Regular inspection during construction phases.',
        renewal_process: 'Apply for extension if construction not completed within validity period.',
        fees_paid: 1200000.00,
        is_asset: true
      },
      {
        name: 'Land Document',
        category: 'legal',
        file_path: 'assets/Conversion Certificate.pdf',
        file_type: 'application/pdf',
        project_name: 'Prestige Park Groove',
        project_address: 'Whitefield, Bangalore, Karnataka 560066',
        plot_area: 5000000.00,
        issuing_authority: 'Sub-Registrar Office, Whitefield',
        approval_number: 'REG/2022/WF123',
        application_number: 'LAND/REG/2022/456',
        contact_person: 'Sri. Venkatesh Rao',
        contact_phone: '+91-80-33445566',
        contact_email: 'venkatesh.rao@subregistrar.kar.gov.in',
        application_date: new Date('2022-05-01'),
        approval_date: new Date('2022-06-15'),
        validity_start_date: new Date('2022-06-15'),
        status: 'Verified',
        priority_level: 'Critical',
        compliance_status: 'Compliant',
        description: 'Original land ownership and title documents with clear title verification',
        tags: ['Land', 'Legal', 'Title', 'Ownership'],
        conditions_attached: 'No encumbrances. Clear title with marketable rights.',
        fees_paid: 800000.00,
        is_asset: true
      },
      {
        name: 'SGWA',
        category: 'utilities',
        file_path: 'assets/SGWA.pdf',
        file_type: 'application/pdf',
        project_name: 'Prestige Park Groove',
        project_address: 'Whitefield, Bangalore, Karnataka 560066',
        issuing_authority: 'State Groundwater Authority',
        approval_number: 'SGWA/2023/BLR789',
        application_number: 'GW/APP/2023/321',
        contact_person: 'Dr. Suresh Babu',
        contact_phone: '+91-80-44556677',
        contact_email: 'suresh.babu@sgwa.kar.gov.in',
        application_date: new Date('2023-02-01'),
        approval_date: new Date('2023-04-15'),
        validity_start_date: new Date('2023-04-15'),
        validity_end_date: new Date('2028-04-14'),
        status: 'Approved',
        priority_level: 'High',
        compliance_status: 'Compliant',
        description: 'State Groundwater Authority approval for bore well construction and water extraction',
        tags: ['Water', 'Groundwater', 'Authority', 'Bore Wells'],
        conditions_attached: 'Maximum extraction limit: 500 KLD. Monthly water usage reporting required.',
        renewal_process: 'Submit water usage reports and apply for renewal 60 days before expiry.',
        fees_paid: 75000.00,
        is_asset: true
      },
      {
        name: 'Fire NOC',
        category: 'safety',
        file_path: 'assets/FIRE_NOC.pdf',
        file_type: 'application/pdf',
        project_name: 'Prestige Park Groove',
        project_address: 'Whitefield, Bangalore, Karnataka 560066',
        built_up_area: 2500000.00,
        issuing_authority: 'Karnataka Fire and Emergency Services',
        approval_number: 'FIRE/NOC/2023/WF567',
        application_number: 'FIRE/APP/2023/890',
        contact_person: 'Sri. Ravi Kumar',
        contact_phone: '+91-80-55667788',
        contact_email: 'ravi.kumar@fireservices.kar.gov.in',
        application_date: new Date('2023-05-01'),
        approval_date: new Date('2023-06-20'),
        validity_start_date: new Date('2023-06-20'),
        validity_end_date: new Date('2025-06-19'),
        renewal_due_date: new Date('2025-05-01'),
        status: 'Approved',
        priority_level: 'High',
        compliance_status: 'Compliant',
        description: 'Fire department No Objection Certificate for fire safety compliance',
        tags: ['Fire', 'Safety', 'NOC', 'Emergency'],
        conditions_attached: 'Installation of fire safety equipment as per approved plans. Regular fire safety audits.',
        renewal_process: 'Submit fire safety compliance certificate and apply 45 days before expiry.',
        fees_paid: 100000.00,
        is_asset: true
      },
      {
        name: 'Airport Clearance',
        category: 'planning',
        file_path: 'assets/Airport.pdf',
        file_type: 'application/pdf',
        project_name: 'Prestige Park Groove',
        project_address: 'Whitefield, Bangalore, Karnataka 560066',
        built_up_area: 2500000.00,
        issuing_authority: 'Airports Authority of India',
        approval_number: 'AAI/HT/2023/BLR234',
        application_number: 'AIRPORT/CLR/2023/567',
        contact_person: 'Wing Commander S. Prasad',
        contact_phone: '+91-80-66778899',
        contact_email: 's.prasad@aai.aero',
        application_date: new Date('2023-03-01'),
        approval_date: new Date('2023-04-10'),
        validity_start_date: new Date('2023-04-10'),
        status: 'Approved',
        priority_level: 'Medium',
        compliance_status: 'Compliant',
        description: 'Airport authority height clearance certificate for high-rise construction',
        tags: ['Airport', 'Height', 'Clearance', 'Aviation'],
        conditions_attached: 'Maximum building height: 150 meters above ground level. Aviation warning lights required.',
        renewal_process: 'No renewal required unless height specifications change.',
        fees_paid: 25000.00,
        is_asset: true
      },
      {
        name: 'BESCOM Clearances',
        category: 'utilities',
        file_path: 'assets/ BESCOM.pdf',
        file_type: 'application/pdf',
        project_name: 'Prestige Park Groove',
        project_address: 'Whitefield, Bangalore, Karnataka 560066',
        issuing_authority: 'Bangalore Electricity Supply Company',
        approval_number: 'BESCOM/2023/WF890',
        application_number: 'ELEC/CONN/2023/234',
        contact_person: 'Sri. Govind Prasad',
        contact_phone: '+91-80-77889900',
        contact_email: 'govind.prasad@bescom.org',
        application_date: new Date('2023-04-01'),
        approval_date: new Date('2023-05-15'),
        validity_start_date: new Date('2023-05-15'),
        status: 'Approved',
        priority_level: 'High',
        compliance_status: 'Compliant',
        description: 'Electricity board clearances and connections for township power supply',
        tags: ['Electricity', 'BESCOM', 'Utilities', 'Power Supply'],
        conditions_attached: 'Installation of dedicated transformer. Compliance with electrical safety norms.',
        renewal_process: 'Connection agreement valid for project duration. Upgrade as per load requirements.',
        fees_paid: 350000.00,
        is_asset: true
      }
    ];

    for (const doc of defaultDocuments) {
      await pool.query(`
        INSERT INTO enhanced_project_documents 
        (name, category, file_path, file_type, project_name, project_address,
         built_up_area, plot_area, floor_area_ratio, issuing_authority, approval_number,
         application_number, contact_person, contact_phone, contact_email,
         application_date, approval_date, validity_start_date, validity_end_date,
         renewal_due_date, status, priority_level, compliance_status, description,
         tags, conditions_attached, renewal_process, fees_paid, is_asset)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
                $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, $29)
        ON CONFLICT (name, project_name) DO UPDATE SET
          category = $2,
          file_path = $3,
          issuing_authority = $10,
          approval_number = $11,
          contact_person = $13,
          contact_phone = $14,
          contact_email = $15,
          validity_end_date = $19,
          renewal_due_date = $20,
          status = $21,
          updated_at = CURRENT_TIMESTAMP
      `, [
        doc.name, doc.category, doc.file_path, doc.file_type, doc.project_name,
        doc.project_address, doc.built_up_area, doc.plot_area, doc.floor_area_ratio,
        doc.issuing_authority, doc.approval_number, doc.application_number,
        doc.contact_person, doc.contact_phone, doc.contact_email,
        doc.application_date, doc.approval_date, doc.validity_start_date,
        doc.validity_end_date, doc.renewal_due_date, doc.status, doc.priority_level,
        doc.compliance_status, doc.description, doc.tags, doc.conditions_attached,
        doc.renewal_process, doc.fees_paid, doc.is_asset
      ]);
    }

    logger.info('Enhanced default documents seeded successfully');
  } catch (error) {
    logger.error('Error seeding enhanced default documents:', error);
  }
};

// ===========================================
// SEED SAMPLE ALERTS
// ===========================================

const seedSampleAlerts = async () => {
  try {
    // Get document IDs for creating sample alerts
    const docsResult = await pool.query(
      'SELECT id, name, validity_end_date FROM enhanced_project_documents WHERE name IN ($1, $2, $3)',
      ['Fire NOC', 'KSPCB CFE', 'BBMP Plan Sanction']
    );

    const sampleAlerts = [
      {
        document_id: docsResult.rows.find(d => d.name === 'Fire NOC')?.id,
        alert_type: 'expiry_warning',
        severity: 'Medium',
        title: 'Fire NOC Renewal Due Soon',
        message: 'Fire NOC will expire in approximately 18 months. Consider starting renewal process.',
        suggested_action: 'Contact Karnataka Fire and Emergency Services to understand renewal requirements.',
        due_date: new Date('2025-05-01')
      },
      {
        document_id: docsResult.rows.find(d => d.name === 'KSPCB CFE')?.id,
        alert_type: 'compliance_check',
        severity: 'Low',
        title: 'Monthly Compliance Report Due',
        message: 'KSPCB requires monthly environmental compliance reports.',
        suggested_action: 'Submit water and air quality monitoring data to KSPCB portal.',
        due_date: new Date(new Date().getFullYear(), new Date().getMonth() + 1, 15)
      }
    ];

    for (const alert of sampleAlerts) {
      if (alert.document_id) {
        await pool.query(`
          INSERT INTO document_alerts 
          (document_id, alert_type, severity, title, message, suggested_action, due_date)
          VALUES ($1, $2, $3, $4, $5, $6, $7)
          ON CONFLICT DO NOTHING
        `, [
          alert.document_id, alert.alert_type, alert.severity, alert.title,
          alert.message, alert.suggested_action, alert.due_date
        ]);
      }
    }

    logger.info('Sample alerts seeded successfully');
  } catch (error) {
    logger.error('Error seeding sample alerts:', error);
  }
};

// ===========================================
// COMPREHENSIVE SEED FUNCTION
// ===========================================

const seedDatabase = async () => {
  try {
    logger.info('Starting comprehensive database seeding...');
    
    await seedValidationRules();
    await seedEnhancedDefaultDocuments();
    await seedSampleAlerts();
    
    logger.info('Database seeding completed successfully!');
  } catch (error) {
    logger.error('Error during database seeding:', error);
  }
};

// ===========================================
// AUTO-VALIDATION SCHEDULER
// ===========================================

const scheduleValidationChecks = () => {
  // Run validation checks every 6 hours
  setInterval(async () => {
    try {
      logger.info('Running scheduled document validation...');
      
      const healthReport = await DocumentIntelligenceService.generateHealthReport();
      
      // Create alerts for critical issues
      if (healthReport.summary.critical_issues > 0) {
        logger.warn(`Found ${healthReport.summary.critical_issues} critical document issues`);
        
        // Here you could send notifications, emails, etc.
        // For example: await sendNotificationToAdmins(healthReport);
      }
      
      logger.info('Scheduled validation completed');
    } catch (error) {
      logger.error('Error in scheduled validation:', error);
    }
  }, 6 * 60 * 60 * 1000); // 6 hours

  logger.info('Document validation scheduler started');
};

// ===========================================
// INITIALIZATION AND EXPORT
// ===========================================

// Initialize enhanced document system
const initializeEnhancedDocumentSystem = async () => {
  try {
    await seedDatabase();
    scheduleValidationChecks();
    
    logger.info('Enhanced Document Management System initialized successfully');
  } catch (error) {
    logger.error('Error initializing enhanced document system:', error);
  }
};

// Export functions for use
export {
  seedDatabase,
  seedValidationRules,
  seedEnhancedDefaultDocuments,
  seedSampleAlerts,
  scheduleValidationChecks,
  initializeEnhancedDocumentSystem
};

// Auto-run if this script is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  initializeEnhancedDocumentSystem();
}

// ===========================================
// ADDITIONAL ENDPOINT FOR MANUAL SEEDING
// ===========================================

// Admin endpoint to manually trigger seeding
app.post('/admin/seed-database', authenticateAdmin, async (req, res) => {
  try {
    await seedDatabase();
    
    await logAdminAction(
      req.user.username,
      'SEED_DATABASE',
      'Manually triggered database seeding',
      req
    );
    
    res.status(200).json({
      success: true,
      message: 'Database seeded successfully'
    });
  } catch (error) {
    logger.error('Error in manual database seeding:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to seed database',
      error: error.message
    });
  }
});

logger.info('Enhanced document seeding system ready');

class DocumentComparisonEngine {
  
  // Compare multiple documents for consistency
  static async compareDocuments(documentIds, comparisonType = 'full') {
    try {
      const documents = await this.getDocumentsForComparison(documentIds);
      
      if (documents.length < 2) {
        throw new Error('At least 2 documents required for comparison');
      }

      const comparison = {
        documents: documents.map(doc => ({
          id: doc.id,
          name: doc.name,
          category: doc.category,
          project_name: doc.project_name
        })),
        comparison_type: comparisonType,
        timestamp: new Date().toISOString(),
        fields_compared: [],
        inconsistencies: [],
        similarities: [],
        recommendations: []
      };

      // Define fields to compare based on type
      const fieldsToCompare = this.getComparisonFields(comparisonType);
      comparison.fields_compared = fieldsToCompare;

      // Perform field-by-field comparison
      for (const field of fieldsToCompare) {
        const fieldComparison = await this.compareField(documents, field);
        
        if (fieldComparison.inconsistent) {
          comparison.inconsistencies.push(fieldComparison);
        } else if (fieldComparison.similar) {
          comparison.similarities.push(fieldComparison);
        }
      }

      // Generate recommendations
      comparison.recommendations = this.generateComparisonRecommendations(comparison);

      // Save comparison result
      await this.saveComparisonResult(comparison);

      return comparison;
    } catch (error) {
      logger.error('Error in document comparison:', error);
      throw error;
    }
  }

  static async getDocumentsForComparison(documentIds) {
    const query = `
      SELECT * FROM enhanced_project_documents 
      WHERE id = ANY($1::uuid[])
      ORDER BY name
    `;
    
    const result = await pool.query(query, [documentIds]);
    return result.rows;
  }

  static getComparisonFields(comparisonType) {
    const fieldGroups = {
      basic: [
        'project_name', 'project_address', 'contact_person', 'contact_email'
      ],
      technical: [
        'built_up_area', 'plot_area', 'floor_area_ratio', 'issuing_authority'
      ],
      compliance: [
        'approval_number', 'validity_end_date', 'status', 'compliance_status'
      ],
      full: [
        'project_name', 'project_address', 'built_up_area', 'plot_area',
        'floor_area_ratio', 'issuing_authority', 'contact_person', 
        'contact_email', 'contact_phone', 'approval_number', 'status'
      ]
    };

    return fieldGroups[comparisonType] || fieldGroups.basic;
  }

  static async compareField(documents, fieldName) {
    const values = documents.map(doc => ({
      document_id: doc.id,
      document_name: doc.name,
      value: doc[fieldName],
      category: doc.category
    }));

    // Check for numeric field tolerance
    const numericFields = ['built_up_area', 'plot_area', 'floor_area_ratio'];
    const isNumeric = numericFields.includes(fieldName);
    
    let inconsistent = false;
    let toleranceExceeded = false;
    const uniqueValues = new Set();
    const nonNullValues = values.filter(v => v.value !== null && v.value !== undefined);

    if (nonNullValues.length < 2) {
      return {
        field: fieldName,
        inconsistent: false,
        similar: false,
        reason: 'Insufficient data for comparison',
        values: values
      };
    }

    for (const item of nonNullValues) {
      if (isNumeric && typeof item.value === 'number') {
        // For numeric fields, check tolerance
        const baseValue = nonNullValues[0].value;
        const tolerance = this.getFieldTolerance(fieldName);
        const difference = Math.abs(item.value - baseValue);
        const percentageDiff = (difference / baseValue) * 100;
        
        if (percentageDiff > tolerance) {
          inconsistent = true;
          toleranceExceeded = true;
        }
        
        uniqueValues.add(Math.round(item.value));
      } else {
        // For text fields, exact match
        uniqueValues.add(String(item.value).toLowerCase().trim());
      }
    }

    // For non-numeric fields, check if all values are the same
    if (!isNumeric && uniqueValues.size > 1) {
      inconsistent = true;
    }

    const result = {
      field: fieldName,
      inconsistent: inconsistent,
      similar: !inconsistent && nonNullValues.length > 1,
      values: values,
      unique_values: Array.from(uniqueValues),
      analysis: {
        is_numeric: isNumeric,
        tolerance_exceeded: toleranceExceeded,
        variance_count: uniqueValues.size
      }
    };

    if (inconsistent) {
      result.severity = this.getInconsistencySeverity(fieldName, uniqueValues.size);
      result.recommendation = this.getFieldRecommendation(fieldName, values);
    }

    return result;
  }

  static getFieldTolerance(fieldName) {
    const tolerances = {
      built_up_area: 2.0, // 2% tolerance
      plot_area: 1.0,     // 1% tolerance
      floor_area_ratio: 5.0 // 5% tolerance
    };
    
    return tolerances[fieldName] || 0;
  }

  static getInconsistencySeverity(fieldName, varianceCount) {
    const criticalFields = ['project_name', 'project_address', 'built_up_area', 'plot_area'];
    const highFields = ['contact_person', 'contact_email', 'issuing_authority'];
    
    if (criticalFields.includes(fieldName)) {
      return varianceCount > 2 ? 'Critical' : 'High';
    } else if (highFields.includes(fieldName)) {
      return 'Medium';
    }
    
    return 'Low';
  }

  static getFieldRecommendation(fieldName, values) {
    const recommendations = {
      project_name: 'Standardize project name across all documents',
      project_address: 'Verify and update address to match official records',
      built_up_area: 'Review area calculations and ensure consistency with approved plans',
      plot_area: 'Cross-check with survey documents and land records',
      contact_person: 'Update contact information to reflect current project manager',
      contact_email: 'Ensure all documents have current contact details',
      issuing_authority: 'Verify correct authority names and update if needed'
    };
    
    return recommendations[fieldName] || `Review and standardize ${fieldName} across documents`;
  }

  static generateComparisonRecommendations(comparison) {
    const recommendations = [];
    
    // Critical inconsistencies
    const critical = comparison.inconsistencies.filter(inc => inc.severity === 'Critical');
    if (critical.length > 0) {
      recommendations.push({
        priority: 'Critical',
        title: 'Critical Data Inconsistencies Found',
        description: `Found ${critical.length} critical inconsistencies that must be resolved immediately`,
        actions: critical.map(inc => `Resolve ${inc.field} mismatch: ${inc.recommendation}`)
      });
    }

    // High priority inconsistencies
    const high = comparison.inconsistencies.filter(inc => inc.severity === 'High');
    if (high.length > 0) {
      recommendations.push({
        priority: 'High',
        title: 'High Priority Inconsistencies',
        description: `${high.length} high priority inconsistencies need attention`,
        actions: high.map(inc => inc.recommendation)
      });
    }

    // Document standardization
    if (comparison.inconsistencies.length > 3) {
      recommendations.push({
        priority: 'Medium',
        title: 'Document Standardization Needed',
        description: 'Multiple inconsistencies suggest need for document standardization',
        actions: [
          'Create document templates with standard fields',
          'Implement data validation rules',
          'Regular consistency audits'
        ]
      });
    }

    return recommendations;
  }

  static async saveComparisonResult(comparison) {
    try {
      const query = `
        INSERT INTO document_comparisons 
        (document_ids, comparison_type, inconsistencies_found, similarities_found, 
         comparison_data, created_at)
        VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)
        RETURNING id
      `;

      const documentIds = comparison.documents.map(doc => doc.id);
      const result = await pool.query(query, [
        documentIds,
        comparison.comparison_type,
        comparison.inconsistencies.length,
        comparison.similarities.length,
        JSON.stringify(comparison)
      ]);

      comparison.comparison_id = result.rows[0].id;
      return comparison;
    } catch (error) {
      logger.error('Error saving comparison result:', error);
      // Continue without saving if there's an error
      return comparison;
    }
  }

  // Smart document matching for finding related documents
  static async findRelatedDocuments(documentId, threshold = 0.7) {
    try {
      const targetDoc = await pool.query(
        'SELECT * FROM enhanced_project_documents WHERE id = $1',
        [documentId]
      );

      if (targetDoc.rows.length === 0) {
        throw new Error('Document not found');
      }

      const target = targetDoc.rows[0];
      
      // Find documents with similar project details
      const query = `
        SELECT *, 
          CASE 
            WHEN project_name = $1 THEN 0.4
            ELSE 0.0
          END +
          CASE 
            WHEN project_address = $2 THEN 0.3
            ELSE 0.0
          END +
          CASE 
            WHEN ABS(COALESCE(built_up_area, 0) - COALESCE($3, 0)) < 1000 THEN 0.2
            ELSE 0.0
          END +
          CASE 
            WHEN contact_person = $4 THEN 0.1
            ELSE 0.0
          END as similarity_score
        FROM enhanced_project_documents 
        WHERE id != $5
        HAVING similarity_score >= $6
        ORDER BY similarity_score DESC
        LIMIT 10
      `;

      const relatedDocs = await pool.query(query, [
        target.project_name,
        target.project_address,
        target.built_up_area,
        target.contact_person,
        documentId,
        threshold
      ]);

      return {
        target_document: target,
        related_documents: relatedDocs.rows,
        similarity_threshold: threshold
      };
    } catch (error) {
      logger.error('Error finding related documents:', error);
      throw error;
    }
  }

  // Analyze document completeness for a project
  static async analyzeProjectCompleteness(projectName) {
    try {
      const requiredDocumentTypes = {
        environmental: {
          required: ['KSPCB CFE', 'Environmental Clearances', 'SGWA'],
          optional: ['Tree Cutting Permission', 'Waste Management Plan']
        },
        planning: {
          required: ['BBMP Plan Sanction', 'Airport Clearance'],
          optional: ['Traffic Impact Assessment', 'Parking Plan']
        },
        legal: {
          required: ['Land Document'],
          optional: ['Power of Attorney', 'Partnership Deed']
        },
        safety: {
          required: ['Fire NOC'],
          optional: ['Structural Safety Certificate', 'Electrical Safety Certificate']
        },
        utilities: {
          required: ['BESCOM Clearances'],
          optional: ['Telecom Clearances', 'Gas Connection Approval']
        }
      };

      // Get existing documents for the project
      const existingDocs = await pool.query(
        'SELECT name, category, status FROM enhanced_project_documents WHERE project_name = $1',
        [projectName]
      );

      const analysis = {
        project_name: projectName,
        completeness_score: 0,
        total_required: 0,
        total_available: 0,
        categories: {},
        missing_documents: [],
        recommendations: []
      };

      for (const [category, docs] of Object.entries(requiredDocumentTypes)) {
        const categoryAnalysis = {
          required_count: docs.required.length,
          available_count: 0,
          missing_required: [],
          available_optional: []
        };

        // Check required documents
        for (const reqDoc of docs.required) {
          const exists = existingDocs.rows.some(doc => 
            doc.name.includes(reqDoc) && doc.status === 'Approved'
          );
          
          if (exists) {
            categoryAnalysis.available_count++;
          } else {
            categoryAnalysis.missing_required.push(reqDoc);
            analysis.missing_documents.push({
              category: category,
              document: reqDoc,
              priority: 'Required',
              impact: 'Project compliance may be affected'
            });
          }
        }

        // Check optional documents
        for (const optDoc of docs.optional) {
          const exists = existingDocs.rows.some(doc => 
            doc.name.includes(optDoc) && doc.status === 'Approved'
          );
          
          if (exists) {
            categoryAnalysis.available_optional.push(optDoc);
          }
        }

        categoryAnalysis.completeness = categoryAnalysis.available_count / categoryAnalysis.required_count;
        analysis.categories[category] = categoryAnalysis;
        analysis.total_required += categoryAnalysis.required_count;
        analysis.total_available += categoryAnalysis.available_count;
      }

      // Calculate overall completeness score
      analysis.completeness_score = Math.round((analysis.total_available / analysis.total_required) * 100);

      // Generate recommendations
      if (analysis.completeness_score < 70) {
        analysis.recommendations.push({
          priority: 'Critical',
          action: 'Complete Required Documents',
          description: `Only ${analysis.completeness_score}% of required documents are available`
        });
      }

      // Category-specific recommendations
      for (const [category, catAnalysis] of Object.entries(analysis.categories)) {
        if (catAnalysis.completeness < 1.0) {
          analysis.recommendations.push({
            priority: 'High',
            action: `Complete ${category} documentation`,
            description: `Missing: ${catAnalysis.missing_required.join(', ')}`
          });
        }
      }

      return analysis;
    } catch (error) {
      logger.error('Error analyzing project completeness:', error);
      throw error;
    }
  }
}

// ===========================================
// ENHANCED API ENDPOINTS
// ===========================================

// Create document comparisons table
const createDocumentComparisonsTable = `
  CREATE TABLE IF NOT EXISTS document_comparisons (
    id SERIAL PRIMARY KEY,
    document_ids UUID[],
    comparison_type VARCHAR(50),
    inconsistencies_found INTEGER DEFAULT 0,
    similarities_found INTEGER DEFAULT 0,
    comparison_data JSONB,
    created_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

pool.query(createDocumentComparisonsTable)
  .then(() => logger.info('Document comparisons table created'))
  .catch(err => logger.error('Error creating document comparisons table:', err));

// Compare multiple documents
app.post('/api/documents/compare', authenticateToken, async (req, res) => {
  try {
    const { document_ids, comparison_type = 'full' } = req.body;

    if (!document_ids || document_ids.length < 2) {
      return res.status(400).json({
        success: false,
        message: 'At least 2 document IDs are required for comparison'
      });
    }

    const comparison = await DocumentComparisonEngine.compareDocuments(document_ids, comparison_type);

    res.status(200).json({
      success: true,
      data: comparison
    });
  } catch (error) {
    logger.error('Error in document comparison:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to compare documents',
      error: error.message
    });
  }
});

// Find related documents
app.get('/api/documents/:id/related', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    const { threshold = 0.7 } = req.query;

    const relatedDocs = await DocumentComparisonEngine.findRelatedDocuments(id, parseFloat(threshold));

    res.status(200).json({
      success: true,
      data: relatedDocs
    });
  } catch (error) {
    logger.error('Error finding related documents:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to find related documents',
      error: error.message
    });
  }
});

// Analyze project completeness
app.get('/api/projects/:projectName/completeness', authenticateToken, async (req, res) => {
  try {
    const { projectName } = req.params;

    const analysis = await DocumentComparisonEngine.analyzeProjectCompleteness(projectName);

    res.status(200).json({
      success: true,
      data: analysis
    });
  } catch (error) {
    logger.error('Error analyzing project completeness:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to analyze project completeness',
      error: error.message
    });
  }
});

// Get comparison history
app.get('/api/documents/comparisons', authenticateToken, async (req, res) => {
  try {
    const { page = 1, limit = 10 } = req.query;
    const offset = (page - 1) * limit;

    const query = `
      SELECT 
        dc.*,
        u.username as created_by_username
      FROM document_comparisons dc
      LEFT JOIN users u ON dc.created_by = u.id
      ORDER BY dc.created_at DESC
      LIMIT $1 OFFSET $2
    `;

    const result = await pool.query(query, [limit, offset]);

    res.status(200).json({
      success: true,
      data: result.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit)
      }
    });
  } catch (error) {
    logger.error('Error fetching comparison history:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch comparison history',
      error: error.message
    });
  }
});

// Bulk document analysis for inconsistencies
app.post('/api/documents/bulk-analyze', authenticateToken, async (req, res) => {
  try {
    const { project_name, analysis_types = ['consistency', 'completeness', 'dependencies'] } = req.body;

    const results = {};

    // Consistency analysis
    if (analysis_types.includes('consistency')) {
      results.consistency = await DocumentIntelligenceService.validateDocumentConsistency();
    }

    // Completeness analysis
    if (analysis_types.includes('completeness') && project_name) {
      results.completeness = await DocumentComparisonEngine.analyzeProjectCompleteness(project_name);
    }

    // Dependency analysis
    if (analysis_types.includes('dependencies') && project_name) {
      const projectDocs = await pool.query(
        'SELECT id FROM enhanced_project_documents WHERE project_name = $1',
        [project_name]
      );

      results.dependencies = {};
      for (const doc of projectDocs.rows) {
        results.dependencies[doc.id] = await DocumentIntelligenceService.analyzeDependencies(doc.id);
      }
    }

    // Expiry analysis
    if (analysis_types.includes('expiry')) {
      results.expiry = await DocumentIntelligenceService.checkExpiringDocuments(90);
    }

    res.status(200).json({
      success: true,
      data: {
        project_name: project_name,
        analysis_types: analysis_types,
        results: results,
        analyzed_at: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Error in bulk document analysis:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to perform bulk analysis',
      error: error.message
    });
  }
});

// Advanced search with intelligent filtering
app.get('/api/documents/intelligent-search', authenticateToken, async (req, res) => {
  try {
    const { 
      query: searchQuery, 
      project_name, 
      category,
      status,
      expiry_within_days,
      has_issues = false,
      sort_by = 'relevance'
    } = req.query;

    let whereConditions = [];
    let params = [];
    let orderBy = 'ed.created_at DESC';

    // Base query with scoring
    let query = `
      SELECT ed.*,
        CASE 
          WHEN ed.name ILIKE $${params.length + 1} THEN 10
          WHEN ed.description ILIKE $${params.length + 1} THEN 5
          WHEN ed.project_name ILIKE $${params.length + 1} THEN 8
          WHEN ed.approval_number ILIKE $${params.length + 1} THEN 7
          ELSE 0
        END as relevance_score,
        CASE 
          WHEN ed.validity_end_date IS NOT NULL AND ed.validity_end_date < CURRENT_DATE THEN true 
          ELSE false 
        END as is_expired,
        CASE 
          WHEN ed.validity_end_date IS NOT NULL AND ed.validity_end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days' THEN true 
          WHEN ed.renewal_due_date IS NOT NULL AND ed.renewal_due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days' THEN true
          ELSE false 
        END as is_expiring_soon
      FROM enhanced_project_documents ed
    `;

    if (searchQuery) {
      params.push(`%${searchQuery}%`);
    } else {
      params.push('%%'); // Match all if no search query
    }

    // Add filters
    if (project_name) {
      whereConditions.push(`ed.project_name = $${params.length + 1}`);
      params.push(project_name);
    }

    if (category) {
      whereConditions.push(`ed.category = $${params.length + 1}`);
      params.push(category);
    }

    if (status) {
      whereConditions.push(`ed.status = $${params.length + 1}`);
      params.push(status);
    }

    if (expiry_within_days) {
      whereConditions.push(`ed.validity_end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '${parseInt(expiry_within_days)} days'`);
    }

    if (has_issues === 'true') {
      whereConditions.push(`(
        ed.validity_end_date < CURRENT_DATE OR 
        ed.validity_end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days' OR
        ed.status IN ('Expired', 'Pending')
      )`);
    }

    // Add WHERE clause
    if (whereConditions.length > 0) {
      query += ' WHERE ' + whereConditions.join(' AND ');
    }

    // Add sorting
    switch (sort_by) {
      case 'relevance':
        orderBy = 'relevance_score DESC, ed.created_at DESC';
        break;
      case 'expiry':
        orderBy = 'ed.validity_end_date ASC NULLS LAST';
        break;
      case 'priority':
        orderBy = `CASE ed.priority_level 
          WHEN 'Critical' THEN 1 
          WHEN 'High' THEN 2 
          WHEN 'Medium' THEN 3 
          ELSE 4 END ASC`;
        break;
      default:
        orderBy = 'ed.created_at DESC';
    }

    query += ` ORDER BY ${orderBy} LIMIT 50`;

    const result = await pool.query(query, params);

    res.status(200).json({
      success: true,
      data: result.rows,
      search_metadata: {
        query: searchQuery,
        filters_applied: {
          project_name, category, status, expiry_within_days, has_issues
        },
        results_count: result.rows.length,
        sort_by: sort_by
      }
    });
  } catch (error) {
    logger.error('Error in intelligent search:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to perform intelligent search',
      error: error.message
    });
  }
});

logger.info('Advanced document comparison and analysis system initialized');


class NotificationService {
  
  // Create notification
  static async createNotification(userId, type, title, message, data = {}) {
    try {
      const query = `
        INSERT INTO notifications 
        (user_id, type, title, message, data, created_at)
        VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)
        RETURNING *
      `;

      const result = await pool.query(query, [
        userId, type, title, message, JSON.stringify(data)
      ]);

      const notification = result.rows[0];

      // Emit real-time notification if WebSocket is available
      this.emitNotification(userId, notification);

      return notification;
    } catch (error) {
      logger.error('Error creating notification:', error);
      throw error;
    }
  }

  // Create system-wide alert
  static async createSystemAlert(type, title, message, severity = 'Medium', data = {}) {
    try {
      // Get all active users
      const users = await pool.query('SELECT id FROM users WHERE last_login > NOW() - INTERVAL \'30 days\'');
      
      const notifications = [];
      for (const user of users.rows) {
        const notification = await this.createNotification(
          user.id, type, title, message, { ...data, severity }
        );
        notifications.push(notification);
      }

      logger.info(`Created ${notifications.length} system notifications for ${type}`);
      return notifications;
    } catch (error) {
      logger.error('Error creating system alert:', error);
      throw error;
    }
  }

  // Document expiry notifications
  static async createExpiryNotifications() {
    try {
      const expiringDocs = await DocumentIntelligenceService.checkExpiringDocuments(30);
      
      for (const doc of expiringDocs) {
        const title = doc.days_until_expiry <= 7 
          ? `URGENT: ${doc.name} expires in ${doc.days_until_expiry} days`
          : `${doc.name} expires in ${doc.days_until_expiry} days`;

        const message = doc.suggested_action;

        // Create notification for document owner and admins
        await this.createNotificationForDocument(
          doc.id, 
          'document_expiry', 
          title, 
          message,
          {
            document_id: doc.id,
            days_until_expiry: doc.days_until_expiry,
            severity: doc.alert_type,
            authority: doc.issuing_authority
          }
        );
      }

      logger.info(`Created expiry notifications for ${expiringDocs.length} documents`);
    } catch (error) {
      logger.error('Error creating expiry notifications:', error);
    }
  }

  // Inconsistency notifications
  static async createInconsistencyNotifications() {
    try {
      const inconsistencies = await DocumentIntelligenceService.validateDocumentConsistency();
      
      if (inconsistencies.length === 0) return;

      // Group by project
      const projectInconsistencies = {};
      for (const inc of inconsistencies) {
        if (!projectInconsistencies[inc.project_name]) {
          projectInconsistencies[inc.project_name] = [];
        }
        projectInconsistencies[inc.project_name].push(inc);
      }

      for (const [projectName, projectIncs] of Object.entries(projectInconsistencies)) {
        const title = `Data Inconsistencies Detected in ${projectName}`;
        const message = `Found ${projectIncs.length} inconsistencies that need review.`;

        await this.createSystemAlert(
          'data_inconsistency',
          title,
          message,
          'High',
          {
            project_name: projectName,
            inconsistency_count: projectIncs.length,
            inconsistencies: projectIncs
          }
        );
      }

      logger.info(`Created inconsistency notifications for ${Object.keys(projectInconsistencies).length} projects`);
    } catch (error) {
      logger.error('Error creating inconsistency notifications:', error);
    }
  }

  // Document-specific notifications
  static async createNotificationForDocument(documentId, type, title, message, data = {}) {
    try {
      // Get document details
      const docResult = await pool.query(
        'SELECT * FROM enhanced_project_documents WHERE id = $1',
        [documentId]
      );

      if (docResult.rows.length === 0) return;

      const document = docResult.rows[0];

      // Get users who should receive this notification
      const recipients = await this.getDocumentNotificationRecipients(document);

      for (const userId of recipients) {
        await this.createNotification(userId, type, title, message, {
          ...data,
          document_id: documentId,
          document_name: document.name,
          project_name: document.project_name
        });
      }
    } catch (error) {
      logger.error('Error creating document notification:', error);
    }
  }

  // Get users who should receive document notifications
  static async getDocumentNotificationRecipients(document) {
    try {
      const recipients = new Set();

      // Add document owner
      if (document.uploaded_by) {
        recipients.add(document.uploaded_by);
      }

      // Add project managers (users who have uploaded documents for this project)
      if (document.project_name) {
        const projectUsers = await pool.query(
          'SELECT DISTINCT uploaded_by FROM enhanced_project_documents WHERE project_name = $1 AND uploaded_by IS NOT NULL',
          [document.project_name]
        );
        
        for (const user of projectUsers.rows) {
          recipients.add(user.uploaded_by);
        }
      }

      // Add admins
      const admins = await pool.query(
        'SELECT id FROM users WHERE designation ILIKE \'%admin%\''
      );
      
      for (const admin of admins.rows) {
        recipients.add(admin.id);
      }

      return Array.from(recipients);
    } catch (error) {
      logger.error('Error getting notification recipients:', error);
      return [];
    }
  }

  // Emit real-time notification (WebSocket)
  static emitNotification(userId, notification) {
    try {
      // If you have WebSocket setup, emit here
      // io.to(`user_${userId}`).emit('notification', notification);
      
      // For now, we'll just log
      logger.info(`Notification emitted to user ${userId}: ${notification.title}`);
    } catch (error) {
      logger.error('Error emitting notification:', error);
    }
  }

  // Mark notification as read
  static async markAsRead(notificationId, userId) {
    try {
      const query = `
        UPDATE notifications 
        SET is_read = true, read_at = CURRENT_TIMESTAMP
        WHERE id = $1 AND user_id = $2
        RETURNING *
      `;

      const result = await pool.query(query, [notificationId, userId]);
      return result.rows[0];
    } catch (error) {
      logger.error('Error marking notification as read:', error);
      throw error;
    }
  }

  // Get user notifications
  static async getUserNotifications(userId, options = {}) {
    try {
      const { 
        page = 1, 
        limit = 20, 
        unread_only = false,
        type = null
      } = options;

      const offset = (page - 1) * limit;
      let whereConditions = ['user_id = $1'];
      let params = [userId];

      if (unread_only) {
        whereConditions.push('is_read = false');
      }

      if (type) {
        whereConditions.push(`type = $${params.length + 1}`);
        params.push(type);
      }

      const query = `
        SELECT * FROM notifications
        WHERE ${whereConditions.join(' AND ')}
        ORDER BY created_at DESC
        LIMIT $${params.length + 1} OFFSET $${params.length + 2}
      `;

      params.push(limit, offset);

      const result = await pool.query(query, params);

      // Get unread count
      const countQuery = `
        SELECT COUNT(*) as unread_count
        FROM notifications
        WHERE user_id = $1 AND is_read = false
      `;

      const countResult = await pool.query(countQuery, [userId]);

      return {
        notifications: result.rows,
        unread_count: parseInt(countResult.rows[0].unread_count),
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total: result.rows.length
        }
      };
    } catch (error) {
      logger.error('Error getting user notifications:', error);
      throw error;
    }
  }

  // Smart notification scheduling
  static scheduleSmartNotifications() {
    // Daily health check at 9 AM
    setInterval(async () => {
      const now = new Date();
      if (now.getHours() === 9 && now.getMinutes() === 0) {
        await this.createExpiryNotifications();
        await this.createInconsistencyNotifications();
      }
    }, 60000); // Check every minute

    // Weekly comprehensive report on Mondays at 10 AM
    setInterval(async () => {
      const now = new Date();
      if (now.getDay() === 1 && now.getHours() === 10 && now.getMinutes() === 0) {
        await this.createWeeklyReport();
      }
    }, 60000);

    logger.info('Smart notification scheduling initialized');
  }

  // Weekly report notification
  static async createWeeklyReport() {
    try {
      const healthReport = await DocumentIntelligenceService.generateHealthReport();
      
      const title = `Weekly Document Health Report - Score: ${healthReport.health_score}%`;
      const message = `System health: ${healthReport.health_status}. ${healthReport.summary.total_issues} issues found.`;

      await this.createSystemAlert(
        'weekly_report',
        title,
        message,
        healthReport.health_score < 70 ? 'High' : 'Medium',
        {
          health_report: healthReport,
          report_type: 'weekly'
        }
      );

      logger.info('Weekly report notification created');
    } catch (error) {
      logger.error('Error creating weekly report:', error);
    }
  }
}

// ===========================================
// EMAIL NOTIFICATION SERVICE
// ===========================================

class EmailNotificationService {
  
  static async sendExpiryAlert(userEmail, documentName, daysUntilExpiry, contactInfo) {
    try {
      const subject = daysUntilExpiry <= 7 
        ? `URGENT: ${documentName} expires in ${daysUntilExpiry} days`
        : `REMINDER: ${documentName} expires in ${daysUntilExpiry} days`;

      const htmlBody = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <div style="background: ${daysUntilExpiry <= 7 ? '#dc3545' : '#ff9500'}; color: white; padding: 20px; text-align: center;">
            <h1>${daysUntilExpiry <= 7 ? '🚨 URGENT ALERT' : '⚠️ EXPIRY REMINDER'}</h1>
          </div>
          
          <div style="padding: 20px; background: #f8f9fa;">
            <h2>Document Expiry Alert</h2>
            <p><strong>Document:</strong> ${documentName}</p>
            <p><strong>Days until expiry:</strong> ${daysUntilExpiry}</p>
            
            ${contactInfo ? `
              <h3>Contact Information for Renewal:</h3>
              <p><strong>Authority:</strong> ${contactInfo.authority}</p>
              <p><strong>Contact Person:</strong> ${contactInfo.person}</p>
              <p><strong>Phone:</strong> ${contactInfo.phone}</p>
              <p><strong>Email:</strong> ${contactInfo.email}</p>
            ` : ''}
            
            <div style="margin: 20px 0; padding: 15px; background: white; border-left: 4px solid #007bff;">
              <h4>Recommended Actions:</h4>
              <ul>
                <li>Contact the issuing authority immediately</li>
                <li>Prepare required documents for renewal</li>
                <li>Schedule appointment if necessary</li>
                <li>Update project team about renewal status</li>
              </ul>
            </div>
            
            <p style="color: #666; font-size: 12px; margin-top: 30px;">
              This is an automated alert from the Document Management System.
              Please do not reply to this email.
            </p>
          </div>
        </div>
      `;

      // Here you would integrate with your email service (SendGrid, AWS SES, etc.)
      // For now, we'll just log
      logger.info(`Email alert would be sent to ${userEmail}: ${subject}`);
      
      return { success: true, message: 'Email alert logged' };
    } catch (error) {
      logger.error('Error sending email alert:', error);
      return { success: false, error: error.message };
    }
  }

  static async sendInconsistencyReport(userEmail, projectName, inconsistencies) {
    try {
      const subject = `Data Inconsistencies Detected in ${projectName}`;
      
      const inconsistencyList = inconsistencies.map(inc => `
        <li>
          <strong>${inc.field}:</strong> ${inc.suggestion}
          <br><small>Severity: ${inc.severity}</small>
        </li>
      `).join('');

      const htmlBody = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <div style="background: #ff9500; color: white; padding: 20px; text-align: center;">
            <h1>📊 Data Inconsistency Alert</h1>
          </div>
          
          <div style="padding: 20px; background: #f8f9fa;">
            <h2>Inconsistencies Detected</h2>
            <p><strong>Project:</strong> ${projectName}</p>
            <p><strong>Issues Found:</strong> ${inconsistencies.length}</p>
            
            <h3>Details:</h3>
            <ul style="line-height: 1.6;">
              ${inconsistencyList}
            </ul>
            
            <div style="margin: 20px 0; padding: 15px; background: white; border-left: 4px solid #dc3545;">
              <h4>Immediate Actions Required:</h4>
              <ul>
                <li>Review and verify the flagged data fields</li>
                <li>Update documents with correct information</li>
                <li>Ensure consistency across all project documents</li>
                <li>Contact relevant authorities if needed</li>
              </ul>
            </div>
          </div>
        </div>
      `;

      logger.info(`Inconsistency report would be sent to ${userEmail}: ${subject}`);
      
      return { success: true, message: 'Inconsistency report logged' };
    } catch (error) {
      logger.error('Error sending inconsistency report:', error);
      return { success: false, error: error.message };
    }
  }
}

// ===========================================
// DATABASE TABLES
// ===========================================

const createNotificationsTable = `
  CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    data JSONB DEFAULT '{}',
    is_read BOOLEAN DEFAULT false,
    read_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE
  )
`;

const createNotificationPreferencesTable = `
  CREATE TABLE IF NOT EXISTS notification_preferences (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    email_notifications BOOLEAN DEFAULT true,
    push_notifications BOOLEAN DEFAULT true,
    expiry_alerts BOOLEAN DEFAULT true,
    inconsistency_alerts BOOLEAN DEFAULT true,
    weekly_reports BOOLEAN DEFAULT true,
    critical_only BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

const createNotificationIndexes = `
  CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
  CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
  CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read);
  CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at);
`;

Promise.all([
  pool.query(createNotificationsTable),
  pool.query(createNotificationPreferencesTable),
  pool.query(createNotificationIndexes)
]).then(() => {
  logger.info('Notification system tables created successfully');
}).catch(err => {
  logger.error('Error creating notification tables:', err);
});

// ===========================================
// API ENDPOINTS
// ===========================================

// Get user notifications
app.get('/api/notifications', authenticateToken, async (req, res) => {
  try {
    const { page, limit, unread_only, type } = req.query;
    
    const notifications = await NotificationService.getUserNotifications(
      req.user.id, 
      { page, limit, unread_only: unread_only === 'true', type }
    );

    res.status(200).json({
      success: true,
      data: notifications
    });
  } catch (error) {
    logger.error('Error fetching notifications:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch notifications',
      error: error.message
    });
  }
});

// Mark notification as read
app.put('/api/notifications/:id/read', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    const notification = await NotificationService.markAsRead(id, req.user.id);
    
    if (!notification) {
      return res.status(404).json({
        success: false,
        message: 'Notification not found'
      });
    }

    res.status(200).json({
      success: true,
      data: notification
    });
  } catch (error) {
    logger.error('Error marking notification as read:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to mark notification as read',
      error: error.message
    });
  }
});

// Mark all notifications as read
app.put('/api/notifications/read-all', authenticateToken, async (req, res) => {
  try {
    const query = `
      UPDATE notifications 
      SET is_read = true, read_at = CURRENT_TIMESTAMP
      WHERE user_id = $1 AND is_read = false
      RETURNING COUNT(*) as updated_count
    `;

    const result = await pool.query(query, [req.user.id]);

    res.status(200).json({
      success: true,
      message: `Marked ${result.rows[0].updated_count} notifications as read`
    });
  } catch (error) {
    logger.error('Error marking all notifications as read:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to mark all notifications as read',
      error: error.message
    });
  }
});

// Get notification preferences
app.get('/api/notifications/preferences', authenticateToken, async (req, res) => {
  try {
    const query = `
      SELECT * FROM notification_preferences 
      WHERE user_id = $1
    `;

    const result = await pool.query(query, [req.user.id]);

    if (result.rows.length === 0) {
      // Create default preferences
      const defaultPrefs = await pool.query(`
        INSERT INTO notification_preferences (user_id)
        VALUES ($1)
        RETURNING *
      `, [req.user.id]);

      return res.status(200).json({
        success: true,
        data: defaultPrefs.rows[0]
      });
    }

    res.status(200).json({
      success: true,
      data: result.rows[0]
    });
  } catch (error) {
    logger.error('Error fetching notification preferences:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch notification preferences',
      error: error.message
    });
  }
});

// Update notification preferences
app.put('/api/notifications/preferences', authenticateToken, async (req, res) => {
  try {
    const {
      email_notifications,
      push_notifications,
      expiry_alerts,
      inconsistency_alerts,
      weekly_reports,
      critical_only
    } = req.body;

    const query = `
      INSERT INTO notification_preferences 
      (user_id, email_notifications, push_notifications, expiry_alerts, 
       inconsistency_alerts, weekly_reports, critical_only)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      ON CONFLICT (user_id) DO UPDATE SET
        email_notifications = $2,
        push_notifications = $3,
        expiry_alerts = $4,
        inconsistency_alerts = $5,
        weekly_reports = $6,
        critical_only = $7,
        updated_at = CURRENT_TIMESTAMP
      RETURNING *
    `;

    const result = await pool.query(query, [
      req.user.id, email_notifications, push_notifications,
      expiry_alerts, inconsistency_alerts, weekly_reports, critical_only
    ]);

    res.status(200).json({
      success: true,
      data: result.rows[0]
    });
  } catch (error) {
    logger.error('Error updating notification preferences:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update notification preferences',
      error: error.message
    });
  }
});

// Admin: Create system notification
app.post('/api/admin/notifications/system', authenticateAdmin, async (req, res) => {
  try {
    const { type, title, message, severity = 'Medium', data = {} } = req.body;

    const notifications = await NotificationService.createSystemAlert(
      type, title, message, severity, data
    );

    await logAdminAction(
      req.user.username,
      'CREATE_SYSTEM_NOTIFICATION',
      `Created system notification: ${title}`,
      req
    );

    res.status(201).json({
      success: true,
      message: `Created ${notifications.length} system notifications`,
      data: notifications
    });
  } catch (error) {
    logger.error('Error creating system notification:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create system notification',
      error: error.message
    });
  }
});

// Manual trigger for expiry notifications
app.post('/api/admin/notifications/check-expiry', authenticateAdmin, async (req, res) => {
  try {
    await NotificationService.createExpiryNotifications();
    
    res.status(200).json({
      success: true,
      message: 'Expiry notifications check completed'
    });
  } catch (error) {
    logger.error('Error in manual expiry check:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to check expiry notifications',
      error: error.message
    });
  }
});

// Manual trigger for inconsistency notifications
app.post('/api/admin/notifications/check-inconsistencies', authenticateAdmin, async (req, res) => {
  try {
    await NotificationService.createInconsistencyNotifications();
    
    res.status(200).json({
      success: true,
      message: 'Inconsistency notifications check completed'
    });
  } catch (error) {
    logger.error('Error in manual inconsistency check:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to check inconsistency notifications',
      error: error.message
    });
  }
});

// ===========================================
// INITIALIZATION
// ===========================================

// Initialize notification system
const initializeNotificationSystem = () => {
  // Start smart notification scheduling
  NotificationService.scheduleSmartNotifications();
  
  logger.info('Real-time notification system initialized');
};

// Auto-initialize
initializeNotificationSystem();

// Export for external use
export {
  NotificationService,
  EmailNotificationService,
  initializeNotificationSystem
};

logger.info('Notification and alert system ready');





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
        const similarDocs = await pool.query(`
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
// INTEGRATION WITH EXISTING SERVICES
// ===========================================

// Extend NotificationService to use WebSocket
const originalCreateNotification = NotificationService.createNotification;
NotificationService.createNotification = async function(userId, type, title, message, data = {}) {
  // Create notification in database
  const notification = await originalCreateNotification.call(this, userId, type, title, message, data);
  
  // Send real-time notification if WebSocket is available
  if (global.realTimeService) {
    const sent = global.realTimeService.sendNotificationToUser(userId, notification);
    if (sent) {
      // Mark as delivered in real-time
      await pool.query(
        'UPDATE notifications SET delivered_at = CURRENT_TIMESTAMP WHERE id = $1',
        [notification.id]
      );
    }
  }
  
  return notification;
};

// Extend DocumentIntelligenceService to broadcast updates
const originalValidateDocumentConsistency = DocumentIntelligenceService.validateDocumentConsistency;
DocumentIntelligenceService.validateDocumentConsistency = async function(documentId = null) {
  const inconsistencies = await originalValidateDocumentConsistency.call(this, documentId);
  
  // Broadcast inconsistency alerts if WebSocket is available
  if (global.realTimeService && inconsistencies.length > 0) {
    const criticalInconsistencies = inconsistencies.filter(inc => inc.severity === 'Critical');
    
    if (criticalInconsistencies.length > 0) {
      global.realTimeService.broadcastSystemNotification({
        type: 'critical_inconsistency',
        title: 'Critical Data Inconsistencies Detected',
        message: `Found ${criticalInconsistencies.length} critical inconsistencies requiring immediate attention`,
        data: { inconsistencies: criticalInconsistencies }
      });
    }
  }
  
  return inconsistencies;
};

// ===========================================
// SERVER SETUP AND INITIALIZATION
// ===========================================

// Create HTTP server for WebSocket
const httpServer = createServer(app);

// Initialize WebSocket service
global.realTimeService = new RealTimeDocumentService(httpServer);

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

// Update server to use HTTP server with WebSocket
const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  logger.info(`Server with WebSocket running on port ${PORT}`);
  logger.info('Real-time document management system ready');
});

// Export for external use
export {
  RealTimeDocumentService,
  httpServer
};

logger.info('WebSocket real-time system initialized');




app.use('*', (req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});











