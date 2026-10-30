-- ATTG HRSuccess : run via db/setup.ps1 (passes $(DB_NAME), $(DB_USER), $(DB_PASSWORD) from .env)
IF DB_ID('$(DB_NAME)') IS NULL CREATE DATABASE [$(DB_NAME)];
GO
IF SUSER_ID('$(DB_USER)') IS NULL
  CREATE LOGIN [$(DB_USER)] WITH PASSWORD = '$(DB_PASSWORD)', DEFAULT_DATABASE = [$(DB_NAME)];
ELSE
  ALTER LOGIN [$(DB_USER)] WITH PASSWORD = '$(DB_PASSWORD)';
GO
USE [$(DB_NAME)];
GO
IF USER_ID('$(DB_USER)') IS NULL CREATE USER [$(DB_USER)] FOR LOGIN [$(DB_USER)];
ALTER ROLE db_datareader ADD MEMBER [$(DB_USER)];
ALTER ROLE db_datawriter ADD MEMBER [$(DB_USER)];
GO

-- ตารางข้อมูลหลัก: ตารางเดียว คอลัมน์ตาม Excel / View ต้นทาง (คำอธิบายภาษาไทยใส่เป็น MS_Description ตอน setup)
IF OBJECT_ID('dbo.Employee') IS NULL
CREATE TABLE dbo.Employee (
  EmpID nvarchar(20) NOT NULL UNIQUE,
  UserID nvarchar(20) NOT NULL PRIMARY KEY,
  Title_TH nvarchar(50), Fname_TH nvarchar(100), Lname_TH nvarchar(100),
  Position_TH nvarchar(255), Division_TH nvarchar(255), Department_TH nvarchar(255),
  Section_TH nvarchar(255), SubSection_TH nvarchar(255), Plant_TH nvarchar(255),
  Title_EN nvarchar(50), Fname_EN nvarchar(100), Lname_EN nvarchar(100),
  Position_EN nvarchar(255), Division_EN nvarchar(255), Department_EN nvarchar(255),
  Section_EN nvarchar(255), SubSection_EN nvarchar(255), Plant_EN nvarchar(255),
  Email nvarchar(255), EmpStatus nvarchar(50), WorkLocation nvarchar(255),
  NumberOfChild int, PerSubarea nvarchar(10), MobilePhone nvarchar(50),
  DOB date, HireDate date, PLDate date, Street nvarchar(255), ID_TAX nvarchar(20),
  PositionLevel nvarchar(100), ComCode nvarchar(10), Province nvarchar(100),
  MaritalStatus nvarchar(50), SubDistrict nvarchar(100), EmpSubgroup nvarchar(50),
  EducationGroup nvarchar(20), PostCode nvarchar(10), District nvarchar(100),
  ID_CARD nvarchar(20), ExperienceYear nvarchar(50), EmpGroup nvarchar(100),
  BankKey nvarchar(20), HouseNumber nvarchar(50), Bank nvarchar(255),
  BloodGroup nvarchar(10), CostCenter nvarchar(50), ComName nvarchar(255),
  manager_1 nvarchar(20), manager_2 nvarchar(20), manager_3 nvarchar(20), manager_4 nvarchar(20),
  manager_5 nvarchar(20), manager_6 nvarchar(20), manager_7 nvarchar(20),
  PositionEntryDate date, Religion nvarchar(50), Moo nvarchar(20),
  AccountNumber nvarchar(50), BenefitType nvarchar(100), BankBranch nvarchar(255),
  created_at datetime2, updated_at datetime2,
  SeniorityStartDate date, ExpDate date, RetirementDate date, PFStartDate date,
  EducationEndDate date, LevelOfEducation nvarchar(100), Certificate nvarchar(50),
  Institution nvarchar(255), Major nvarchar(255), GPA decimal(4,2),
  [สิทธิลาพักร้อน] decimal(5,1),
  [ลาพักร้อนไปแล้ว/วัน] decimal(5,1)
);
GO

-- ตารางมาตรฐาน
IF OBJECT_ID('dbo.Users') IS NULL
CREATE TABLE dbo.Users (
  UserID nvarchar(20) NOT NULL PRIMARY KEY,           -- = Employee.UserID
  Role nvarchar(20) NOT NULL CHECK (Role IN ('superadmin','admin','manager','user')),
  ComCode nvarchar(10) NULL,                           -- ใช้กับ admin: ดูเฉพาะบริษัทนี้
  PasswordHash nvarchar(200) NULL,
  IsActive bit NOT NULL DEFAULT 1,
  created_at datetime2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at datetime2 NOT NULL DEFAULT SYSDATETIME()
);
IF OBJECT_ID('dbo.LoginLog') IS NULL
CREATE TABLE dbo.LoginLog (
  LogID bigint IDENTITY PRIMARY KEY,
  UserID nvarchar(20) NOT NULL,
  Success bit NOT NULL,
  IPAddress nvarchar(50) NULL,
  created_at datetime2 NOT NULL DEFAULT SYSDATETIME()
);
IF OBJECT_ID('dbo.ActivityLog') IS NULL
CREATE TABLE dbo.ActivityLog (
  LogID bigint IDENTITY PRIMARY KEY,
  UserID nvarchar(20) NOT NULL,
  Action nvarchar(100) NOT NULL,
  Detail nvarchar(max) NULL,
  created_at datetime2 NOT NULL DEFAULT SYSDATETIME()
);
GO
-- login: Users found by M365 email; LoginLog also records failed attempts (no UserID yet)
IF COL_LENGTH('dbo.Users', 'Email') IS NULL ALTER TABLE dbo.Users ADD Email nvarchar(255) NULL;
IF COL_LENGTH('dbo.LoginLog', 'Email') IS NULL ALTER TABLE dbo.LoginLog ADD Email nvarchar(255) NULL, Method nvarchar(20) NULL, Reason nvarchar(255) NULL;
ALTER TABLE dbo.LoginLog ALTER COLUMN UserID nvarchar(20) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Users_Email')
  CREATE UNIQUE INDEX UX_Users_Email ON dbo.Users (Email) WHERE Email IS NOT NULL;
IF OBJECT_ID('dbo.AppSettings') IS NULL
CREATE TABLE dbo.AppSettings (
  SettingKey nvarchar(100) NOT NULL PRIMARY KEY,
  SettingValue nvarchar(max) NULL,
  updated_at datetime2 NOT NULL DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.AppSettings WHERE SettingKey = N'ชื่อหน่วยงาน')
  INSERT dbo.AppSettings (SettingKey, SettingValue) VALUES (N'ชื่อหน่วยงาน', N'ATTG HRSuccess');
IF NOT EXISTS (SELECT 1 FROM dbo.AppSettings WHERE SettingKey = N'อีเมลผู้ดูแล')
  INSERT dbo.AppSettings (SettingKey, SettingValue) VALUES (N'อีเมลผู้ดูแล', N'admin@attg.co.th');
GO
