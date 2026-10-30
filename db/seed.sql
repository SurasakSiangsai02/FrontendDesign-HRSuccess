-- Sample-only values. Run by db/setup.ps1 after the Excel import.
USE [$(DB_NAME)];
GO
-- The sample file leaves vacation columns empty: fill made-up numbers so the dashboard has data.
-- Only touches NULLs, so real values from the source View are never overwritten.
UPDATE dbo.Employee SET [สิทธิลาพักร้อน] =
  CASE WHEN DATEDIFF(year, HireDate, GETDATE()) >= 10 THEN 15
       WHEN DATEDIFF(year, HireDate, GETDATE()) >= 5  THEN 12
       WHEN DATEDIFF(year, HireDate, GETDATE()) >= 1  THEN 10
       ELSE 6 END
WHERE [สิทธิลาพักร้อน] IS NULL;
UPDATE dbo.Employee SET [ลาพักร้อนไปแล้ว/วัน] = ABS(CHECKSUM(UserID)) % (CAST([สิทธิลาพักร้อน] AS int) + 1)
WHERE [ลาพักร้อนไปแล้ว/วัน] IS NULL;
GO
-- Users: seeded once (later edits/passwords are kept on re-run).
IF NOT EXISTS (SELECT 1 FROM dbo.Users)
BEGIN
  -- manager = EmpID appears in anyone's manager_1..7 ; everyone else = user
  INSERT dbo.Users (UserID, Role, ComCode)
  SELECT e.UserID,
         CASE WHEN EXISTS (SELECT 1 FROM dbo.Employee s
                           WHERE e.EmpID IN (s.manager_1, s.manager_2, s.manager_3, s.manager_4, s.manager_5, s.manager_6, s.manager_7))
              THEN 'manager' ELSE 'user' END,
         e.ComCode
  FROM dbo.Employee e;

  -- test HR accounts: 1st HR person of ComCode 1290 (ATA) = superadmin (HRATA),
  -- 2nd of 1290 + 1st of every other company = admin (HR บริษัท)
  WITH pick AS (
    SELECT UserID, ComCode,
           ROW_NUMBER() OVER (PARTITION BY ComCode ORDER BY
             CASE WHEN CONCAT(Division_EN, Department_EN, Section_EN) LIKE '%Human%' THEN 0 ELSE 1 END, UserID) AS rn
    FROM dbo.Employee)
  UPDATE u SET Role = CASE WHEN p.ComCode = '1290' AND p.rn = 1 THEN 'superadmin' ELSE 'admin' END
  FROM dbo.Users u JOIN pick p ON p.UserID = u.UserID
  WHERE p.rn = 1 OR (p.ComCode = '1290' AND p.rn = 2);
END
GO
-- Users.Email = login key for M365. Sample file has one shared placeholder email, so give each
-- sample user a fake unique one (never matches a real M365 account). Real emails: set them in Users.
UPDATE u SET Email = CONCAT('user.', u.UserID, '@hrs-demo.local')
FROM dbo.Users u WHERE u.Email IS NULL;
GO
