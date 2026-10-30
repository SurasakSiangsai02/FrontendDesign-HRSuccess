# Create DB + tables, import Employee from the sample xlsx, seed Users. Re-runnable.
# Usage (from project root):  powershell -ExecutionPolicy Bypass -File db\setup.ps1 [path\to\file.xlsx]
param([string]$Xlsx = "$PSScriptRoot\..\Employee Data_byInno.xlsx")
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\.."
$envFile = "$root\.env"

# 1) .env: add any missing line (secrets generated here, never printed)
function New-Secret($len) {
  do {
    $bytes = New-Object byte[] $len; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $s = -join ($bytes | ForEach-Object { 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'[$_ % 56] })
  } until ($s -cmatch '[A-Z]' -and $s -cmatch '[a-z]' -and $s -match '\d')
  $s
}
$defaults = [ordered]@{
  DB_SERVER = 'localhost'; DB_INSTANCE = 'SQLEXPRESS'; DB_NAME = 'HRSuccess'; DB_USER = 'hrsuccess_app'
  DB_PASSWORD = { New-Secret 24 }; API_PORT = '3001'; WEB_PORT = '5173'
  M365_TENANT_ID = ''; M365_CLIENT_ID = ''
  DEMO_LOGIN = ''          # on / off ; empty = on until M365 is configured
  SESSION_SECRET = { New-Secret 48 }
}
$cfg = @{}
if (Test-Path $envFile) { Get-Content $envFile | Where-Object { $_ -match '^\s*([^#=]+)=(.*)$' } | ForEach-Object { $cfg[$Matches[1].Trim()] = $Matches[2].Trim() } }
foreach ($k in $defaults.Keys) {
  if ($cfg.ContainsKey($k)) { continue }
  $v = $defaults[$k]; if ($v -is [scriptblock]) { $v = & $v }
  Add-Content -Encoding ASCII $envFile "$k=$v"; $cfg[$k] = $v
  Write-Host "Added $k to .env"
}
$server = "$($cfg.DB_SERVER)\$($cfg.DB_INSTANCE)"
$db = $cfg.DB_NAME

function Run-Sql($file) {
  sqlcmd -S $server -E -b -I -f 65001 -i $file -v DB_NAME="$db" DB_USER="$($cfg.DB_USER)" DB_PASSWORD="$($cfg.DB_PASSWORD)"
  if ($LASTEXITCODE) { throw "sqlcmd failed: $file" }
}

# 2) schema
Run-Sql "$PSScriptRoot\schema.sql"
Write-Host 'Schema OK'

# 3) read xlsx (first sheet; row 1 = title, row 2 = headers)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $Xlsx))
function Read-Entry($name) { $r = New-Object IO.StreamReader($zip.GetEntry($name).Open(), [Text.Encoding]::UTF8); try { $r.ReadToEnd() } finally { $r.Close() } }
[xml]$ss = Read-Entry 'xl/sharedStrings.xml'
$strings = @($ss.sst.si | ForEach-Object { $_.InnerText })
[xml]$sheet = Read-Entry 'xl/worksheets/sheet1.xml'
$zip.Dispose()
$ns = New-Object Xml.XmlNamespaceManager($sheet.NameTable); $ns.AddNamespace('m', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
$rows = $sheet.SelectNodes('//m:sheetData/m:row', $ns)
function Cells($row) {
  $h = @{}
  foreach ($c in $row.SelectNodes('m:c', $ns)) {
    $col = $c.r -replace '\d', ''
    if ($c.t -eq 's') { $h[$col] = $strings[[int]$c.SelectSingleNode('m:v', $ns).InnerText] }
    elseif ($c.t -eq 'inlineStr') { $h[$col] = $c.InnerText }
    else { $v = $c.SelectSingleNode('m:v', $ns); if ($v) { $h[$col] = $v.InnerText } }
  }
  $h
}

# header "EmpID<thai label>" -> column EmpID + description; Thai-only header -> used as-is (kept ASCII: PS 5.1 reads .ps1 as ANSI)
$cols = [ordered]@{}
$hdr = Cells $rows[1]
foreach ($k in $hdr.Keys) {
  $text = $hdr[$k].Trim()
  if ($text -match '^[A-Za-z0-9_]+') { $name = $Matches[0]; $desc = $text.Substring($name.Length).Trim() } else { $name = $text; $desc = $text }
  $cols[$k] = @{ Name = $name; Desc = $desc }
}

$conn = New-Object Data.SqlClient.SqlConnection("Server=$server;Database=$db;Integrated Security=True")
$conn.Open()
$types = @{}
$cmd = $conn.CreateCommand(); $cmd.CommandText = "SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='Employee'"
$rd = $cmd.ExecuteReader(); while ($rd.Read()) { $types[$rd.GetString(0)] = $rd.GetString(1) }; $rd.Close()
foreach ($c in $cols.Values) { if (-not $types.ContainsKey($c.Name)) { throw "Excel column not in Employee table: $($c.Name)" } }

$dt = New-Object Data.DataTable
foreach ($c in $cols.Values) { [void]$dt.Columns.Add($c.Name, [object]) }
for ($i = 2; $i -lt $rows.Count; $i++) {
  $cells = Cells $rows[$i]
  if (-not $cells.Count) { continue }
  $r = $dt.NewRow()
  foreach ($k in $cols.Keys) {
    $name = $cols[$k].Name; $v = $cells[$k]
    if ($null -eq $v -or "$v".Trim() -eq '') { $r[$name] = [DBNull]::Value; continue }
    $r[$name] = switch ($types[$name]) {
      'date'      { if ($v -match '^[\d.]+$') { [DateTime]::FromOADate([double]$v).Date } else { [DateTime]::Parse($v) } }
      'datetime2' { if ($v -match '^[\d.]+$') { [DateTime]::FromOADate([double]$v) } else { [DateTime]::Parse($v) } }
      'int'       { [int][double]$v }
      'decimal'   { [decimal][double]$v }
      default     { "$v".Trim() }
    }
  }
  $dt.Rows.Add($r)
}

$cmd.CommandText = 'TRUNCATE TABLE dbo.Employee'; [void]$cmd.ExecuteNonQuery()
$bulk = New-Object Data.SqlClient.SqlBulkCopy($conn)
$bulk.DestinationTableName = 'dbo.Employee'
foreach ($c in $dt.Columns) { [void]$bulk.ColumnMappings.Add($c.ColumnName, $c.ColumnName) }
$bulk.WriteToServer($dt)
Write-Host "Imported $($dt.Rows.Count) employees"

# 4) Thai labels from the Excel header -> MS_Description on each column
foreach ($c in $cols.Values) {
  if (-not $c.Desc) { continue }
  $cmd.CommandText = @"
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID('dbo.Employee') AND name = 'MS_Description' AND minor_id = COLUMNPROPERTY(OBJECT_ID('dbo.Employee'), @col, 'ColumnId'))
  EXEC sys.sp_updateextendedproperty 'MS_Description', @desc, 'SCHEMA', 'dbo', 'TABLE', 'Employee', 'COLUMN', @col
ELSE
  EXEC sys.sp_addextendedproperty 'MS_Description', @desc, 'SCHEMA', 'dbo', 'TABLE', 'Employee', 'COLUMN', @col
"@
  $cmd.Parameters.Clear()
  [void]$cmd.Parameters.AddWithValue('@col', $c.Name); [void]$cmd.Parameters.AddWithValue('@desc', $c.Desc)
  [void]$cmd.ExecuteNonQuery()
}
$conn.Close()

# 5) sample values for empty columns + Users
Run-Sql "$PSScriptRoot\seed.sql"
Write-Host 'Seed OK'
