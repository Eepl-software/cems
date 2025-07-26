-- Database schema updates for enhanced OCR fields
-- This script adds the enhanced OCR fields to all material submission tables

-- Add enhanced OCR fields to pipes_submissions table
ALTER TABLE pipes_submissions ADD COLUMN IF NOT EXISTS material_name VARCHAR(255);
ALTER TABLE pipes_submissions ADD COLUMN IF NOT EXISTS material_category VARCHAR(255);
ALTER TABLE pipes_submissions ADD COLUMN IF NOT EXISTS weighment_slip_no VARCHAR(255);
ALTER TABLE pipes_submissions ADD COLUMN IF NOT EXISTS driver_name VARCHAR(255);
ALTER TABLE pipes_submissions ADD COLUMN IF NOT EXISTS transporter VARCHAR(255);

-- Add enhanced OCR fields to tiles_submissions table  
ALTER TABLE tiles_submissions ADD COLUMN IF NOT EXISTS material_name VARCHAR(255);
ALTER TABLE tiles_submissions ADD COLUMN IF NOT EXISTS material_category VARCHAR(255);
ALTER TABLE tiles_submissions ADD COLUMN IF NOT EXISTS weighment_slip_no VARCHAR(255);
ALTER TABLE tiles_submissions ADD COLUMN IF NOT EXISTS driver_name VARCHAR(255);
ALTER TABLE tiles_submissions ADD COLUMN IF NOT EXISTS transporter VARCHAR(255);

-- Add enhanced OCR fields to wood_submissions table
ALTER TABLE wood_submissions ADD COLUMN IF NOT EXISTS material_name VARCHAR(255);
ALTER TABLE wood_submissions ADD COLUMN IF NOT EXISTS material_category VARCHAR(255);
ALTER TABLE wood_submissions ADD COLUMN IF NOT EXISTS weighment_slip_no VARCHAR(255);
ALTER TABLE wood_submissions ADD COLUMN IF NOT EXISTS driver_name VARCHAR(255);
ALTER TABLE wood_submissions ADD COLUMN IF NOT EXISTS transporter VARCHAR(255);

-- Add enhanced OCR fields to electricals_submissions table
ALTER TABLE electricals_submissions ADD COLUMN IF NOT EXISTS material_name VARCHAR(255);
ALTER TABLE electricals_submissions ADD COLUMN IF NOT EXISTS material_category VARCHAR(255);
ALTER TABLE electricals_submissions ADD COLUMN IF NOT EXISTS weighment_slip_no VARCHAR(255);
ALTER TABLE electricals_submissions ADD COLUMN IF NOT EXISTS driver_name VARCHAR(255);
ALTER TABLE electricals_submissions ADD COLUMN IF NOT EXISTS transporter VARCHAR(255);

-- Add enhanced OCR fields to plastic_submissions table
ALTER TABLE plastic_submissions ADD COLUMN IF NOT EXISTS material_name VARCHAR(255);
ALTER TABLE plastic_submissions ADD COLUMN IF NOT EXISTS material_category VARCHAR(255);
ALTER TABLE plastic_submissions ADD COLUMN IF NOT EXISTS weighment_slip_no VARCHAR(255);
ALTER TABLE plastic_submissions ADD COLUMN IF NOT EXISTS driver_name VARCHAR(255);
ALTER TABLE plastic_submissions ADD COLUMN IF NOT EXISTS transporter VARCHAR(255);

-- Add enhanced OCR fields to aggregates_submissions table
ALTER TABLE aggregates_submissions ADD COLUMN IF NOT EXISTS material_name VARCHAR(255);
ALTER TABLE aggregates_submissions ADD COLUMN IF NOT EXISTS material_category VARCHAR(255);
ALTER TABLE aggregates_submissions ADD COLUMN IF NOT EXISTS weighment_slip_no VARCHAR(255);
ALTER TABLE aggregates_submissions ADD COLUMN IF NOT EXISTS driver_name VARCHAR(255);
ALTER TABLE aggregates_submissions ADD COLUMN IF NOT EXISTS transporter VARCHAR(255);