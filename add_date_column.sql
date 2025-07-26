-- SQL script to add date column to existing tankers table
-- Run this on your EC2 PostgreSQL database


ALTER TABLE tankers ADD COLUMN IF NOT EXISTS date DATE;
UPDATE tankers SET date = CURRENT_DATE WHERE date IS NULL;
ALTER TABLE tankers ALTER COLUMN date SET NOT NULL;

-- Verify the column was added
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'tankers' AND column_name = 'date';