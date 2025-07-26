-- SQL script to add last_login column to users table
-- Run this on your PostgreSQL database

ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login TIMESTAMP;

-- Verify the column was added
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'users' AND column_name = 'last_login';