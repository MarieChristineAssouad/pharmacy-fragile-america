-- =====================================================================
-- 01_create_database.sql
-- ---------------------------------------------------------------------
-- BIG PICTURE
-- ---------------------------------------------------------------------
-- Create a fresh workspace for your project
-- ---------------------------------------------------------------------
-- Project: Quantifying the Impact of Rural Pharmacy Closures on
--          Medicare Spending: A County-Level Analysis (2019-2024)
-- Step:    Create the project database
-- Author:  Marie Christine Assouad
-- =====================================================================

-- Create a dedicated database for this project.
-- Using a separate DB keeps our work isolated from the system databases.
USE master;
GO

-- Drop existing DB if we're rebuilding from scratch (safe to run repeatedly)
IF DB_ID('pharmacy_medicare_project') IS NOT NULL
BEGIN
    ALTER DATABASE pharmacy_medicare_project SET SINGLE_USER WITH ROLLBACK IMMEDIATE;-- Terminate all active connections and roll back ongoing transactions to enable database drop.
    DROP DATABASE pharmacy_medicare_project;--This deletes the old database completely.
END
GO

CREATE DATABASE pharmacy_medicare_project;
GO

USE pharmacy_medicare_project;--From now on, work inside my project database.
GO

-- Create two schemas to separate raw (as-loaded) from clean (transformed) data.
-- This is a standard data-engineering pattern: raw.* is immutable,
-- clean.* is where we build analysis-ready tables.
CREATE SCHEMA raw;--where original loaded data goes.
GO

CREATE SCHEMA clean;--This is where cleaned, typed, analysis-ready tables go
GO

PRINT 'Database pharmacy_medicare_project created successfully.';
PRINT 'Schemas created: raw, clean';
