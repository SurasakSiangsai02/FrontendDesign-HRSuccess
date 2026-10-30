# ATTG HRSuccess [HRS]

ระบบแสดงข้อมูลการลา โอที และกำลังพลของหน่วยงาน
- พนักงานตรวจสอบวันลาและโอทีสะสมของตัวเองได้
- หัวหน้าดูและควบคุมการลาและโอทีของผู้ใต้บังคับบัญชาได้

| ส่วน | เทคโนโลยี | พอร์ต |
|---|---|---|
| หน้าเว็บ | HTML/JS ล้วน เสิร์ฟด้วย Node (`web/`) | 5173 |
| API | Node.js + `mssql` (`api/`) | 3001 (รับเฉพาะจากในเครื่อง) |
| ฐานข้อมูล | Microsoft SQL Server Express (`db/`) | `localhost\SQLEXPRESS` |

หน้าเว็บส่งต่อคำขอ `/api/*` ไปให้ API ผู้ใช้จึงเปิดแค่ http://localhost:5173

---

## 1. สิ่งที่ต้องมีในเครื่อง

| โปรแกรม | หมายเหตุ |
|---|---|
| Windows 10/11 | สคริปต์ติดตั้งเป็น PowerShell / .bat |
| [Node.js](https://nodejs.org) 20.6 ขึ้นไป | ต้องรองรับ `node --env-file` |
| Microsoft SQL Server Express | ชื่อ instance `SQLEXPRESS` |
| `sqlcmd` | มากับ SQL Server หรือติดตั้งแยกจาก Microsoft ODBC/SQL tools |
| Git | ใช้ clone โปรเจกต์ |

**ตั้งค่า SQL Server Express ให้ครบ 4 ข้อนี้ก่อน**
1. **เปิดการล็อกอินแบบ SQL Server**: ใน SSMS คลิกขวาที่เซิร์ฟเวอร์ → Properties → Security → เลือก *SQL Server and Windows Authentication mode* แล้วรีสตาร์ต service
2. **เปิด TCP/IP**: SQL Server Configuration Manager → SQL Server Network Configuration → Protocols for SQLEXPRESS → TCP/IP = Enabled
3. **เปิด service SQL Server Browser** และตั้งเป็น Automatic (API หา instance ชื่อ `SQLEXPRESS` ผ่าน service นี้)
4. **บัญชี Windows ที่ใช้ติดตั้งต้องเป็น sysadmin** ของ SQLEXPRESS เพราะสคริปต์ต้องสร้างฐานข้อมูลและ login

## 2. ดาวน์โหลดโปรเจกต์และติดตั้งแพ็กเกจ

```powershell
git clone https://github.com/SurasakSiangsai02/FrontendDesign-HRSuccess.git "ATTG HRSuccess"
cd "ATTG HRSuccess"
npm.cmd install
```

`npm install` จะติดตั้งแพ็กเกจของ API (`mssql`) ให้เองผ่าน `postinstall`

## 3. วางไฟล์ที่ไม่ได้อยู่ใน Git

ไฟล์เหล่านี้ไม่อยู่ใน repo ต้องขอจากผู้ดูแลแล้ววางเอง

| ไฟล์ | วางที่ | ใช้ทำอะไร |
|---|---|---|
| `Employee Data_byInno.xlsx` | โฟลเดอร์หลักของโปรเจกต์ | ข้อมูลพนักงานตัวอย่าง: แผ่นงานแรก, แถว 1 = หัวเรื่อง, แถว 2 = ชื่อคอลัมน์ |
| `login-globe-skyline.png` | `web/public/assets/` | รูปลูกโลกและตึก ฝั่งซ้ายของหน้าล็อกอิน |
| `login-right-wave.png` | `web/public/assets/` | รูปคลื่น ฝั่งขวาบน |
| `login-right-skyline.jpg` | `web/public/assets/` | รูปตึก ฝั่งขวาล่าง |

> ไม่มีรูป 3 ไฟล์นี้ หน้าล็อกอินก็ยังใช้งานได้ เพียงแต่ไม่มีภาพตกแต่ง
> **ห้าม commit ไฟล์ข้อมูลพนักงาน** `.gitignore` กันไฟล์ `*.xlsx`, `*.xls`, `*.csv` และโฟลเดอร์ `data/` ไว้แล้ว

## 4. สร้างฐานข้อมูล

```powershell
powershell -ExecutionPolicy Bypass -File db\setup.ps1
```

สคริปต์จะทำ 5 อย่าง:
1. **สร้างไฟล์ `.env`** และสุ่มรหัสผ่าน DB กับ `SESSION_SECRET` ให้ (ไม่แสดงค่าบนจอ) ถ้ามีไฟล์อยู่แล้ว จะเพิ่มเฉพาะบรรทัดที่ยังขาด
2. **สร้างฐานข้อมูล `HRSuccess`** และ SQL login `hrsuccess_app` ที่อ่านและเขียนข้อมูลได้เท่านั้น
3. **สร้างตาราง** `Employee`, `Users`, `LoginLog`, `ActivityLog` และ `AppSettings`
4. **นำเข้าพนักงานจากไฟล์ Excel** และใส่คำอธิบายภาษาไทยให้แต่ละคอลัมน์
5. **สร้างผู้ใช้ตัวอย่างในตาราง `Users`**:
   - superadmin 1 คน และ admin 1 คน
   - หัวหน้า = คนที่ชื่ออยู่ใน manager_1–7 ของคนอื่น
   - ที่เหลือเป็น user

ถ้าไฟล์ Excel อยู่ที่อื่น ให้ระบุ path เอง:
```powershell
powershell -ExecutionPolicy Bypass -File db\setup.ps1 -Xlsx "D:\path\to\file.xlsx"
```

**รันซ้ำได้:** ข้อมูล `Employee` จะถูกล้างแล้วนำเข้าใหม่ ส่วนตาราง `Users` ที่มีข้อมูลแล้วจะไม่ถูกแก้

## 5. เปิดแอป

ทำอย่างใดอย่างหนึ่ง:
- **ดับเบิลคลิก `start.bat`**: เปิด API และหน้าเว็บ แล้วเปิดเบราว์เซอร์ให้ ปิดหน้าต่างเมื่อต้องการหยุด
- หรือพิมพ์ใน Terminal: `npm.cmd run dev` แล้วกด <kbd>Ctrl</kbd>+<kbd>C</kbd> เมื่อต้องการหยุด

จากนั้นเปิด **http://localhost:5173**

## 6. ทดสอบ

ถ้ายังไม่ได้ต่อ Microsoft 365:
1. กดปุ่ม **"ลงชื่อเข้าใช้ด้วย Microsoft 365 ›"**
2. จะมีหน้าต่างพร้อมกล่องส้ม "⚠ ยังไม่ได้ต่อ Microsoft 365"
3. เลือกผู้ใช้ตัวอย่างจากรายชื่อด้านล่างกล่อง
4. ระบบพาไปหน้า Dashboard ซึ่งแสดงข้อมูลตามสิทธิ์:

| สิทธิ์ | เห็นข้อมูล |
|---|---|
| Super Admin (HRATA) | ทุกบริษัท |
| Admin (HR บริษัท) | เฉพาะบริษัทตัวเอง (`ComCode`) |
| Manager (หัวหน้า) | ตัวเองและลูกน้องทุกชั้น ตาม `manager_1`–`manager_7` |
| User | ตัวเองเท่านั้น |

## 7. ต่อ Microsoft 365 (ล็อกอินจริง)

1. **ให้ IT ลงทะเบียนแอปใน Microsoft Entra ID** หรือเพิ่มที่อยู่นี้ในทะเบียนที่ใช้ร่วมกับ DSR / A-SOP
   - Platform: **Single-page application**
   - Redirect URI: `http://localhost:5173/` หรือที่อยู่จริงของแอป
2. **ใส่ค่าใน `.env`**:
   ```
   M365_TENANT_ID=<Directory (tenant) ID>
   M365_CLIENT_ID=<Application (client) ID>
   ```
3. **ใส่อีเมลจริงของผู้ใช้ในคอลัมน์ `Users.Email`** ระบบหาสิทธิ์จากอีเมลนี้
   - อีเมลตัวอย่าง `user.<UserID>@hrs-demo.local` ใช้กับ M365 ไม่ได้
   - ถ้าอีเมลไม่มีในตาราง หรือ `IsActive = 0` ระบบจะแจ้งว่ายังไม่มีสิทธิ์ใช้งาน
4. **ปิดหน้าต่าง API แล้วเปิด `start.bat` ใหม่**

ล็อกอินทุกครั้ง ทั้งสำเร็จและไม่สำเร็จ ถูกบันทึกใน `LoginLog`

## ค่าในไฟล์ `.env`

| ตัวแปร | ความหมาย |
|---|---|
| `DB_SERVER`, `DB_INSTANCE`, `DB_NAME` | ที่อยู่ฐานข้อมูล (ค่าเริ่มต้น `localhost` / `SQLEXPRESS` / `HRSuccess`) |
| `DB_USER`, `DB_PASSWORD` | SQL login ของแอป สร้างโดย `setup.ps1` |
| `API_PORT`, `WEB_PORT` | พอร์ต API / หน้าเว็บ (3001 / 5173) |
| `M365_TENANT_ID`, `M365_CLIENT_ID` | ค่าจากการลงทะเบียนแอปใน Entra ID ปล่อยว่าง = ยังไม่ต่อ M365 |
| `DEMO_LOGIN` | `on` / `off` เปิดหรือปิดผู้ใช้ตัวอย่าง ปล่อยว่าง = เปิดเฉพาะตอนยังไม่ต่อ M365 |
| `SESSION_SECRET` | กุญแจเซ็น token หลังล็อกอิน (อายุ 12 ชั่วโมง) |

> **ห้าม commit หรือส่งไฟล์ `.env` ให้คนอื่น** ไฟล์นี้มีรหัสผ่านและกุญแจ ใช้ `.env.example` เป็นตัวอย่างโครงสร้างแทน
> บนเครื่องที่ใช้งานจริงให้ตั้ง `DEMO_LOGIN=off`

## โครงสร้างโปรเจกต์

```
.env.example      ตัวอย่างค่าตั้ง (ไฟล์จริง .env สร้างโดย setup.ps1)
start.bat         เปิดแอปด้วยการดับเบิลคลิก
dev.js            เปิด API + หน้าเว็บพร้อมกัน (npm run dev)
db/
  schema.sql      สร้างฐานข้อมูล ตาราง และค่าเริ่มต้น AppSettings
  seed.sql        ค่าตัวอย่าง (วันลาพักร้อน, ผู้ใช้ Users)
  setup.ps1       ตัวติดตั้งฐานข้อมูล + นำเข้า Excel
api/server.js     API: ล็อกอิน, ตรวจสิทธิ์, Dashboard
web/server.js     เสิร์ฟหน้าเว็บ + ส่งต่อ /api ไปที่ API
web/public/       index.html (ล็อกอิน), dashboard.html, assets/
```

## แก้ปัญหาที่พบบ่อย

| อาการ | วิธีแก้ |
|---|---|
| `npm.ps1 cannot be loaded because running scripts is disabled` | ใช้ `npm.cmd` แทน `npm` หรือรัน `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` ครั้งเดียว หรือใช้ `start.bat` |
| `EADDRINUSE ... 3001` หรือ `5173` | มีแอปเปิดค้างอยู่แล้ว ปิดหน้าต่างเดิมก่อน หรือเปลี่ยน `API_PORT` / `WEB_PORT` ใน `.env` |
| API ต่อฐานข้อมูลไม่ได้ / Login failed | ตรวจหัวข้อ 1 ให้ครบ (Mixed mode, TCP/IP, SQL Browser) แล้วรัน `db\setup.ps1` อีกครั้งเพื่อตั้งรหัสผ่าน login ให้ตรงกับ `.env` |
| `SESSION_SECRET missing in .env` | รัน `db\setup.ps1` สคริปต์จะเพิ่มบรรทัดที่ขาดให้ |
| ล็อกอิน M365 แล้วขึ้น "ยังไม่มีสิทธิ์ใช้งาน" | อีเมลนี้ยังไม่มีใน `Users.Email` หรือ `IsActive = 0` |
| ล็อกอิน M365 จากเครื่องอื่นในวงแลนไม่ได้ | การล็อกอิน M365 ต้องเปิดผ่าน `https://` หรือ `localhost` ถ้าจะให้เครื่องอื่นใช้ ต้องตั้ง HTTPS ก่อน |

ติดต่อผู้ดูแลระบบ: Mr.Santi (santi.s@attg.co.th)
