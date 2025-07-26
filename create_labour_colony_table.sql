-- SQL script to create missing labour_colony table
-- Run this on your PostgreSQL database

CREATE TABLE IF NOT EXISTS labour_colony (
  id SERIAL PRIMARY KEY,
  date DATE NOT NULL,
  source VARCHAR(255) NOT NULL,
  consumption NUMERIC NOT NULL,
  discharge VARCHAR(255) NOT NULL,
  discharged_to VARCHAR(255) NOT NULL,
  mode VARCHAR(50) NOT NULL
);

-- Verify the table was created
SELECT table_name, column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'labour_colony' 
ORDER BY ordinal_position;