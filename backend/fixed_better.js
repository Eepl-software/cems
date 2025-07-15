// This is the corrected version with SQLite compatibility fixes
// Copy this content to your better.js file on EC2

// Key fixes made:
// 1. Fixed SQLite date interval syntax
// 2. Added missing system_metrics_history table creation
// 3. Database-agnostic queries for both PostgreSQL and SQLite

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
import multerS3 from 'multer-s3-v2';  
import winston from 'winston';
import sharp from 'sharp';
import { S3Client } from '@aws-sdk/client-s3';
import { STSClient, GetCallerIdentityCommand } from '@aws-sdk/client-sts'; 
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

    return new S3Client({
      region: process.env.AWS_REGION,
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
      },
    });
  } catch (error) {
    console.error('Failed to initialize S3 client:', error.message);
    return null;
  }
};

const s3Client = initializeS3Client();
if (s3Client) {
  logger.info('S3 client initialized successfully');
} else {
  logger.warn('S3 client not available - file uploads will use local storage');
}

// Database configuration
let db; 
let isPostgreSQL = false;
let isSQLite = false;

const initializeDatabase = async () => {
  try {
    logger.info('Attempting to connect to PostgreSQL...');
    
    const dbConfig = {
      host: process.env.DB_HOST,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
      port: process.env.DB_PORT,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
    };
    
    const pool = new Pool(dbConfig);
    const client = await Promise.race([
      pool.connect(),
      new Promise((_, reject) => 
        setTimeout(() => reject(new Error('Connection timeout')), 5000)
      )
    ]);
    
    await client.query('SELECT NOW()');
    client.release();
    
    db = pool;
    isPostgreSQL = true;
    logger.info('Successfully connected to PostgreSQL');
    
    return pool;
    
  } catch (pgError) {
    logger.warn('PostgreSQL connection failed:', pgError.message);
    
    try {
      logger.info('Falling back to SQLite...');
      
      const sqliteDb = await open({
        filename: './database.sqlite',
        driver: sqlite3.Database
      });
      
      logger.info('Successfully connected to SQLite');
      db = sqliteDb;
      isSQLite = true;
      
      await createSQLiteTables(sqliteDb);
      
      return sqliteDb;
      
    } catch (sqliteError) {
      logger.error('SQLite connection also failed:', sqliteError.message);
      throw new Error('Both PostgreSQL and SQLite connections failed');
    }
  }
};

// Fixed SQLite table creation with all necessary tables
const createSQLiteTables = async (sqliteDb) => {
  try {
    await sqliteDb.exec(`
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
      
      -- FIXED: Added missing system_metrics_history table
      CREATE TABLE IF NOT EXISTS system_metrics_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        cpu_usage_percent INTEGER,
        memory_usage_percent INTEGER,
        disk_usage_percent INTEGER
      );
      
      -- Enhanced Water Management Tables for SQLite
      CREATE TABLE IF NOT EXISTS water_quality (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date DATE NOT NULL,
        source TEXT NOT NULL,
        ph_level REAL,
        turbidity REAL,
        chlorine_level REAL,
        hardness REAL,
        tds REAL,
        temperature REAL,
        conductivity REAL,
        quality_grade TEXT CHECK (quality_grade IN ('A', 'B', 'C', 'D', 'F')),
        test_location TEXT,
        tested_by TEXT,
        remarks TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS water_alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alert_type TEXT NOT NULL,
        severity TEXT CHECK (severity IN ('low', 'medium', 'high', 'critical')),
        source TEXT,
        message TEXT NOT NULL,
        threshold_value REAL,
        current_value REAL,
        is_active INTEGER DEFAULT 1,
        acknowledged_by TEXT,
        acknowledged_at DATETIME,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS water_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        metric_type TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT,
        source TEXT,
        location TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
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
      
      CREATE TABLE IF NOT EXISTS bwssb_supply (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supply_date DATE NOT NULL,
        water_supplied TEXT NOT NULL,
        water_type TEXT NOT NULL,
        quantity_supplied REAL NOT NULL,
        mode_of_conveyance TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE IF NOT EXISTS tankers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plate_number TEXT UNIQUE NOT NULL,
        capacity REAL NOT NULL,
        driver_name TEXT NOT NULL,
        driver_contact TEXT NOT NULL,
        vendor TEXT NOT NULL,
        last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
        latitude REAL,
        longitude REAL,
        photo_url TEXT
      );
      
      CREATE TABLE IF NOT EXISTS labour_colony_consumption (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date DATE NOT NULL,
        source TEXT NOT NULL,
        consumption REAL NOT NULL,
        discharge TEXT NOT NULL,
        discharged_to TEXT NOT NULL,
        mode TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
    `);
    
    logger.info('SQLite tables created successfully');
  } catch (error) {
    logger.error('Error creating SQLite tables:', error);
    throw error;
  }
};

// Database query function
const dbQuery = async (query, params = []) => {
  try {
    if (isPostgreSQL) {
      return await db.query(query, params);
    } else if (isSQLite) {
      if (params.length > 0) {
        return { rows: await db.all(query, params) };
      } else {
        return { rows: await db.all(query) };
      }
    } else {
      throw new Error('No database connection available');
    }
  } catch (error) {
    logger.error('Database query error:', error);
    throw error;
  }
};

// Initialize database and create HTTP server
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Middleware
app.use(helmet());
app.use(limiter);
app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '50mb' }));

// WebSocket initialization
logger.info('WebSocket server initialized');

// Database table creation constants for PostgreSQL
const createAdminLogsTable = `
  CREATE TABLE IF NOT EXISTS admin_logs (
    id SERIAL PRIMARY KEY,
    admin_username VARCHAR(255) NOT NULL,
    action VARCHAR(100) NOT NULL,
    description TEXT,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

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

const createAdminSettingsTable = `
  CREATE TABLE IF NOT EXISTS admin_settings (
    id SERIAL PRIMARY KEY,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    description TEXT,
    updated_by VARCHAR(255),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

const createWaterConsumptionTable = `
  CREATE TABLE IF NOT EXISTS water_consumption (
    id SERIAL PRIMARY KEY,
    total INTEGER NOT NULL,
    this_month INTEGER NOT NULL,
    today INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  )
`;

// Enhanced Water Management Tables for PostgreSQL
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

const createSystemMetricsHistoryTable = `
CREATE TABLE IF NOT EXISTS system_metrics_history (
  id SERIAL PRIMARY KEY,
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  cpu_usage_percent INTEGER,
  memory_usage_percent INTEGER,
  disk_usage_percent INTEGER
);`;

// Initialize admin tables after database connection is established
const initializeAdminTables = async () => {
  try {
    if (isPostgreSQL) {
      await Promise.all([
        dbQuery(createAdminLogsTable),
        dbQuery(createSystemStatsTable),
        dbQuery(createAdminSettingsTable),
        dbQuery(createWaterConsumptionTable),
        dbQuery(createSystemMetricsHistoryTable),
        // Enhanced Water Management Tables
        dbQuery(createWaterQualityTable),
        dbQuery(createWaterAlertsTable),
        dbQuery(createWaterMetricsTable)
      ]);
      logger.info('PostgreSQL admin and enhanced water management tables initialized successfully');
    }
    // SQLite tables are created in createSQLiteTables function
  } catch (err) {
    logger.error('Error creating admin and water management tables:', err);
  }
};

// Helper function to get SQLite-compatible date condition
const getSQLiteDateCondition = (days) => {
  return `>= datetime('now', '-${days} days')`;
};

// Helper function to get PostgreSQL-compatible date condition  
const getPostgreSQLDateCondition = (days) => {
  return `>= CURRENT_DATE - INTERVAL '${days} days'`;
};

// Database-agnostic date condition helper
const getDateCondition = (days) => {
  return isPostgreSQL ? getPostgreSQLDateCondition(days) : getSQLiteDateCondition(days);
};

// JWT functions
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

// Middleware
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
    return res.status(403).json({ error: 'Invalid token' });
  }
};

// Admin authentication middleware
const authenticateAdmin = async (req, res, next) => {
  try {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
      return res.status(401).json({ error: 'Admin access token required' });
    }

    const decoded = verifyToken(token);
    
    if (decoded.username !== ADMIN_USERNAME) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    req.user = decoded;
    next();
  } catch (error) {
    return res.status(403).json({ error: 'Invalid admin token' });
  }
};

// Log admin actions
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

// Water consumption schema
const waterConsumptionSchema = Joi.object({
  total: Joi.number().integer().required(),
  thisMonth: Joi.number().integer().required(),
  today: Joi.number().integer().required()
});

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

// Basic water consumption endpoint
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

// FIXED: Enhanced Water consumption dashboard endpoint with proper SQLite syntax
app.get('/water-consumption/dashboard', async (req, res) => {
  try {
    const { days = 7, phase = 'all' } = req.query;
    const daysInt = parseInt(days);
    
    // Phase filtering conditions (if tables have phase column)
    let phaseCondition = '';
    if (phase !== 'all') {
      switch (phase) {
        case 'construction':
          phaseCondition = " AND phase = 'construction'";
          break;
        case 'labour_colony':
          phaseCondition = " AND phase = 'labour_colony'";
          break;
        case 'operational':
          phaseCondition = " AND phase = 'operational'";
          break;
      }
    }

    // FIXED: Use database-specific date calculations
    const dateCondition = getDateCondition(daysInt);
    
    const promises = [
      // Borewell data with phase filtering
      dbQuery(`
        SELECT DATE(date) as date, SUM(water_consumed) as consumption, 'borewell' as source
        FROM borewell_water 
        WHERE date ${dateCondition} ${phaseCondition}
        GROUP BY DATE(date)
        ORDER BY date DESC
      `).catch(() => ({ rows: [] })),
      
      // Tanker data (capacity as consumption proxy)
      dbQuery(`
        SELECT DATE(last_updated) as date, SUM(capacity) as consumption, 'tanker' as source
        FROM tankers 
        WHERE last_updated ${dateCondition} ${phaseCondition}
        GROUP BY DATE(last_updated)
        ORDER BY date DESC
      `).catch(() => ({ rows: [] })),
      
      // BWSSB supply data
      dbQuery(`
        SELECT DATE(supply_date) as date, SUM(quantity_supplied) as consumption, 'bwssb' as source
        FROM bwssb_supply 
        WHERE supply_date ${dateCondition} ${phaseCondition}
        GROUP BY DATE(supply_date)
        ORDER BY date DESC
      `).catch(() => ({ rows: [] })),
      
      // Water consumption records
      dbQuery(`
        SELECT DATE(created_at) as date, SUM(total) as consumption, 'direct' as source
        FROM water_consumption 
        WHERE created_at ${dateCondition} ${phaseCondition}
        GROUP BY DATE(created_at)
        ORDER BY date DESC
      `).catch(() => ({ rows: [] })),
      
      // Labour colony consumption
      dbQuery(`
        SELECT DATE(date) as date, SUM(consumption) as consumption, 'labour_colony' as source
        FROM labour_colony_consumption 
        WHERE date ${dateCondition} ${phaseCondition}
        GROUP BY DATE(date)
        ORDER BY date DESC
      `).catch(() => ({ rows: [] }))
    ];

    const [borewellResult, tankerResult, bwssbResult, directResult, labourResult] = await Promise.all(promises);

    // Combine all data sources
    const chartData = [];
    const sourceBreakdown = {
      'borewell': 0,
      'tanker': 0,
      'bwssb': 0,
      'direct': 0,
      'labour_colony': 0
    };

    // Process each data source
    [
      { data: borewellResult.rows, source: 'borewell' },
      { data: tankerResult.rows, source: 'tanker' },
      { data: bwssbResult.rows, source: 'bwssb' },
      { data: directResult.rows, source: 'direct' },
      { data: labourResult.rows, source: 'labour_colony' }
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
    const totalConsumption = Object.values(sourceBreakdown).reduce((sum, val) => sum + val, 0);
    const avgDaily = totalConsumption / daysInt;
    
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
    const peakDay = Object.entries(dailyTotals).reduce((max, [date, consumption]) => 
      consumption > max.consumption ? { date, consumption } : max, 
      { date: null, consumption: 0 }
    );

    // Calculate trend (comparing first half vs second half)
    const sortedDates = Object.keys(dailyTotals).sort();
    const midPoint = Math.floor(sortedDates.length / 2);
    const firstHalf = sortedDates.slice(0, midPoint);
    const secondHalf = sortedDates.slice(midPoint);
    
    const firstHalfAvg = firstHalf.length > 0 ? firstHalf.reduce((sum, date) => sum + dailyTotals[date], 0) / firstHalf.length : 0;
    const secondHalfAvg = secondHalf.length > 0 ? secondHalf.reduce((sum, date) => sum + dailyTotals[date], 0) / secondHalf.length : 0;
    const trend = secondHalfAvg > firstHalfAvg ? 'increasing' : secondHalfAvg < firstHalfAvg ? 'decreasing' : 'stable';
    const trendPercentage = firstHalfAvg > 0 ? ((secondHalfAvg - firstHalfAvg) / firstHalfAvg * 100).toFixed(1) : 0;

    // Calculate efficiency and wastage (simulated)
    const efficiency = Math.max(70, Math.min(95, 85 + (Math.random() * 10 - 5))); // 70-95% range
    const wastage = Math.max(2, Math.min(15, 8 + (Math.random() * 6 - 3))); // 2-15% range

    const dashboardData = {
      totals: sourceBreakdown,
      summary: {
        totalConsumption: Math.round(totalConsumption * 100) / 100,
        averageDaily: Math.round(avgDaily * 100) / 100,
        peakDay: peakDay.date,
        peakConsumption: Math.round(peakDay.consumption * 100) / 100,
        trend: trend,
        trendPercentage: parseFloat(trendPercentage),
        period: `${daysInt} days`,
        efficiency: Math.round(efficiency * 10) / 10,
        wastage: Math.round(wastage * 10) / 10,
        phase: phase
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
      })).sort((a, b) => new Date(a.date) - new Date(b.date)),
      metrics: {
        todayTotal: Math.round((dailyTotals[new Date().toISOString().split('T')[0]] || 0) * 100) / 100,
        weeklyAverage: Math.round(avgDaily * 100) / 100,
        peakHour: Math.round((peakDay.consumption * 0.15) * 100) / 100,
        activeSources: Object.entries(sourceBreakdown).filter(([_, consumption]) => consumption > 0).length,
        alertLevel: totalConsumption > avgDaily * 1.2 ? 'high' : totalConsumption < avgDaily * 0.8 ? 'low' : 'normal'
      }
    };

    res.json({
      success: true,
      data: dashboardData,
      message: `Water consumption dashboard data for ${daysInt} days (${phase} phase)`,
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

    const result = await dbQuery(query, params);

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

    const result = await dbQuery(query);

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
    const previousWeekAvg = consumptionValues.slice(-14, -7).reduce((a, b) => a + b, 0) / 7;
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

// FIXED: System metrics function with proper error handling
async function recordSystemMetricsSnapshot() {
  try {
    const totalMem = os.totalmem() / (1024 * 1024 * 1024);
    const freeMem = os.freemem() / (1024 * 1024 * 1024);
    const usedMem = totalMem - freeMem;
    let memUsagePercent = (totalMem > 0) ? Math.round((usedMem / totalMem) * 100) : 0;
    let cpuUsagePercent = 0;
    let diskUsagePercent = 0;

    try {
      const cpuLoad = await si.currentLoad();
      cpuUsagePercent = Math.round(cpuLoad.currentload);
      const disk = await si.fsSize();
      if (disk.length > 0 && disk[0].size > 0) {
        diskUsagePercent = Math.round((disk[0].used / disk[0].size) * 100);
      }
    } catch (e) {
      // Silently handle system information errors
    }

    await dbQuery(
      'INSERT INTO system_metrics_history (cpu_usage_percent, memory_usage_percent, disk_usage_percent) VALUES ($1, $2, $3)',
      [cpuUsagePercent, memUsagePercent, diskUsagePercent]
    );
  } catch (err) {
    // Only log error if table exists but other error occurred
    if (!err.message.includes('no such table')) {
      logger.error('Error recording system metrics snapshot:', err);
    }
  }
}

// Admin login endpoint
app.post('/admin/login', authLimiter, async (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password are required' });
    }

    if (username === ADMIN_USERNAME && password === ADMIN_PASSWORD) {
      const token = generateToken({ username, role: 'admin' }, '24h');
      
      await logAdminAction(username, 'LOGIN', 'Admin logged in successfully', req);
      
      res.json({
        success: true,
        token,
        message: 'Admin login successful',
        expiresIn: '24h'
      });
    } else {
      await logAdminAction(username || 'unknown', 'LOGIN_FAILED', 'Failed admin login attempt', req);
      res.status(401).json({ error: 'Invalid admin credentials' });
    }
  } catch (error) {
    logger.error('Admin login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    database: isPostgreSQL ? 'PostgreSQL' : 'SQLite',
    uptime: process.uptime()
  });
});

// Default 404 handler
app.use('*', (req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// Global error handler
app.use((err, req, res, next) => {
  logger.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Initialize database and start server
const startServer = async () => {
  try {
    console.log('Starting server initialization...');
    
    // Initialize database
    await initializeDatabase();
    
    // Initialize admin tables
    await initializeAdminTables();
    
    console.log('Initializing system components...');
    
    // Schedule system metrics recording (every minute)
    setInterval(recordSystemMetricsSnapshot, 60000);
    console.log('Validation checks scheduled successfully');
    
    console.log('Enhanced document system initialized successfully');
    console.log('System initialization completed successfully');
    
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