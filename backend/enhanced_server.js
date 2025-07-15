// enhanced_server.js
import express from 'express';
import bodyParser from 'body-parser';
import bcrypt from 'bcrypt';
import cors from 'cors';
import Joi from 'joi';
import pkg from 'pg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import jwt from 'jsonwebtoken';
import winston from 'winston';
import dotenv from 'dotenv';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';

dotenv.config();

const app = express();
const port = process.env.PORT || 3000;
const { Client, Pool } = pkg;

// Security configuration
const JWT_SECRET = process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-in-production';
const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'admin';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin123';
const SUPER_ADMIN_PASSWORD = process.env.SUPER_ADMIN_PASSWORD || 'superadmin@2024';

// Logger configuration
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

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: 'Too many requests from this IP, please try again later.'
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5, // limit each IP to 5 auth requests per windowMs
  message: 'Too many authentication attempts, please try again later.'
});

// Middleware
app.use(helmet());
app.use(limiter);
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10mb' }));
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Accept'],
  credentials: true,
}));

// Database configuration
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const sslConfig = {
  rejectUnauthorized: false,
  ca: fs.existsSync(path.join(__dirname, 'us-east-1-bundle.pem')) 
    ? fs.readFileSync(path.join(__dirname, 'us-east-1-bundle.pem')).toString()
    : undefined
};

const dbConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT || 5432,
  ssl: process.env.NODE_ENV === 'production' ? sslConfig : false,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,
};

const pool = new Pool(dbConfig);

pool.on('error', (err) => {
  logger.error('Unexpected error on idle client', err);
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

// Utility Functions
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

// Middleware for authentication
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

// Create admin logs table
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

// Initialize tables
Promise.all([
  pool.query(createAdminLogsTable),
  pool.query(createSystemStatsTable),
  pool.query(createAdminSettingsTable)
]).then(() => {
  logger.info('Admin tables initialized successfully');
}).catch(err => {
  logger.error('Error creating admin tables:', err);
});

// Helper function to log admin actions
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

// AUTHENTICATION ENDPOINTS

// Regular user login (existing)
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

// Admin login endpoint
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

// ADMIN DASHBOARD ENDPOINTS

// Get dashboard statistics
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

    // Calculate system health (mock calculation)
    const systemHealth = Math.floor(Math.random() * 10) + 90; // 90-99%

    // Calculate data usage (mock calculation)
    const dataUsage = Math.floor(Math.random() * 50) + 10; // 10-60 GB

    const stats = {
      totalUsers: parseInt(userStats.rows[0].total_users || 0),
      activeUsers: parseInt(userStats.rows[0].active_users || 0),
      activeTankers: parseInt(tankerStats.rows[0].active_tankers || 0),
      waterConsumption: parseInt(waterStats.rows[0].total_consumption || 0),
      alerts: parseInt(alertStats.rows[0].total_alerts || 0),
      systemHealth: systemHealth,
      dataUsage: dataUsage,
      activeSessions: Math.floor(Math.random() * 20) + 5,
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

// USER MANAGEMENT ENDPOINTS

// Get all users
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

// Create new user
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

// Update user
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

// Delete user
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

// SYSTEM MANAGEMENT ENDPOINTS

// System backup
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

// Get system logs
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

// REPORTS ENDPOINTS

// Generate reports
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

// Get reports list
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

// ALERTS MANAGEMENT

// Get system alerts
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

// Create system alert
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

// SETTINGS MANAGEMENT

// Get admin settings
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

// Update admin setting
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

// HEALTH CHECK AND STATUS

app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    version: process.env.npm_package_version || '1.0.0'
  });
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

// Error handling middleware
app.use((err, req, res, next) => {
  logger.error('Unhandled error:', err);
  res.status(500).json({ 
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

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

app.listen(port, () => {
  logger.info(`Enhanced server running on port ${port}`);
  logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
  logger.info(`Admin username: ${ADMIN_USERNAME}`);
});

export default app;