// ATTG HRSuccess API. Run: npm start (reads ../.env)
const http = require('node:http');
const crypto = require('node:crypto');
const sql = require('mssql');

const env = process.env;
if (!env.SESSION_SECRET) { console.error('SESSION_SECRET missing in .env (run db\\setup.ps1)'); process.exit(1); }

const pool = new sql.ConnectionPool({
  server: env.DB_SERVER,
  database: env.DB_NAME,
  user: env.DB_USER,
  password: env.DB_PASSWORD,
  options: { instanceName: env.DB_INSTANCE, encrypt: false, trustServerCertificate: true },
}).connect();

const M365 = env.M365_TENANT_ID && env.M365_CLIENT_ID ? { tenant: env.M365_TENANT_ID, client: env.M365_CLIENT_ID } : null;
// DEMO_LOGIN=on/off; empty -> on only until Microsoft 365 is configured
const DEMO = env.DEMO_LOGIN ? env.DEMO_LOGIN.toLowerCase() === 'on' : !M365;
const SESSION_HOURS = 12;
const NO_ACCESS = 'ยังไม่มีสิทธิ์ใช้งาน กรุณาติดต่อ Mr.Santi (santi.s@attg.co.th)';

// What each role may see. @EmpID is the viewer's EmpID: manager_1..7 hold EmpIDs, users log in by UserID.
const SCOPE = {
  superadmin: '1=1',
  admin: 'e.ComCode = @ComCode',
  manager: 'e.UserID = @UserID OR @EmpID IN (e.manager_1, e.manager_2, e.manager_3, e.manager_4, e.manager_5, e.manager_6, e.manager_7)',
  user: 'e.UserID = @UserID',
};

const fail = (status, message) => Object.assign(new Error(message), { status });

async function query(text, params = {}) {
  const req = (await pool).request();
  for (const [k, v] of Object.entries(params)) req.input(k, v);
  return (await req.query(text)).recordset;
}

const USER_SQL = `SELECT u.UserID, u.Role, u.ComCode, u.Email, u.IsActive, e.EmpID, e.Fname_TH, e.Lname_TH, e.Fname_EN, e.Lname_EN
  FROM Users u LEFT JOIN Employee e ON e.UserID = u.UserID`;

// ---- session token: base64url(json).HMAC-SHA256 ----
const b64 = (buf) => Buffer.from(buf).toString('base64url');
const hmac = (data) => crypto.createHmac('sha256', env.SESSION_SECRET).update(data).digest();

function signSession(userId) {
  const body = b64(JSON.stringify({ uid: userId, exp: Date.now() + SESSION_HOURS * 3600e3 }));
  return `${body}.${b64(hmac(body))}`;
}

function readSession(token) {
  const [body, sig] = (token || '').split('.');
  if (!body || !sig) return null;
  const want = hmac(body), got = Buffer.from(sig, 'base64url');
  if (got.length !== want.length || !crypto.timingSafeEqual(got, want)) return null;
  const { uid, exp } = JSON.parse(Buffer.from(body, 'base64url'));
  return exp > Date.now() ? uid : null;
}

// role + IsActive re-read from Users on every request
async function currentUser(req) {
  const uid = readSession((req.headers.authorization || '').replace(/^Bearer /, ''));
  if (!uid) throw fail(401, 'กรุณาเข้าสู่ระบบ');
  const [me] = await query(`${USER_SQL} WHERE u.UserID = @UserID`, { UserID: uid });
  if (!me || !me.IsActive) throw fail(403, NO_ACCESS);
  return me;
}

// ---- Microsoft ID token check (RS256 against tenant JWKS) ----
let jwks = { at: 0, keys: [] };
async function msKey(kid) {
  if (Date.now() - jwks.at > 3600e3 || !jwks.keys.some((k) => k.kid === kid)) {
    const res = await fetch(`https://login.microsoftonline.com/${M365.tenant}/discovery/v2.0/keys`);
    if (!res.ok) throw fail(502, 'ติดต่อ Microsoft ไม่ได้');
    jwks = { at: Date.now(), keys: (await res.json()).keys };
  }
  const jwk = jwks.keys.find((k) => k.kid === kid);
  if (!jwk) throw fail(401, 'ID token ไม่ถูกต้อง');
  return crypto.createPublicKey({ key: { kty: jwk.kty, n: jwk.n, e: jwk.e }, format: 'jwk' });
}

async function verifyIdToken(idToken, nonce) {
  const [h, p, s] = (idToken || '').split('.');
  if (!s) throw fail(401, 'ID token ไม่ถูกต้อง');
  const header = JSON.parse(Buffer.from(h, 'base64url'));
  if (header.alg !== 'RS256') throw fail(401, 'ID token ไม่ถูกต้อง');
  const ok = crypto.verify('RSA-SHA256', Buffer.from(`${h}.${p}`), await msKey(header.kid), Buffer.from(s, 'base64url'));
  if (!ok) throw fail(401, 'ID token ไม่ถูกต้อง');
  const c = JSON.parse(Buffer.from(p, 'base64url'));
  const now = Date.now() / 1000, skew = 300;
  if (c.aud !== M365.client || c.iss !== `https://login.microsoftonline.com/${M365.tenant}/v2.0`
    || c.exp < now - skew || (c.nbf && c.nbf > now + skew) || c.nonce !== nonce) throw fail(401, 'ID token ไม่ถูกต้องหรือหมดอายุ');
  return String(c.email || c.preferred_username || '').toLowerCase();
}

async function logLogin(req, { userId = null, email = null, method, success, reason = null }) {
  await query(`INSERT LoginLog (UserID, Email, Method, Success, Reason, IPAddress) VALUES (@UserID, @Email, @Method, @Success, @Reason, @IP)`,
    { UserID: userId, Email: email, Method: method, Success: success, Reason: reason, IP: req.headers['x-forwarded-for'] || req.socket.remoteAddress });
}

// finish a login for a Users row (or reject + log)
async function login(req, method, me, email) {
  if (!me || !me.IsActive) {
    await logLogin(req, { userId: me?.UserID, email, method, success: false, reason: me ? 'inactive' : 'not in Users' });
    throw fail(403, NO_ACCESS);
  }
  await logLogin(req, { userId: me.UserID, email: me.Email, method, success: true });
  return { token: signSession(me.UserID), user: publicUser(me) };
}

const publicUser = (u) => ({ UserID: u.UserID, Role: u.Role, Email: u.Email, Fname_TH: u.Fname_TH, Lname_TH: u.Lname_TH, Fname_EN: u.Fname_EN, Lname_EN: u.Lname_EN });

const routes = {
  'GET /api/health': async () => ({ ok: true, settings: await query('SELECT SettingKey, SettingValue FROM AppSettings') }),

  // public: tells the login page what to show (tenant/client IDs are not secrets; they are needed in the browser)
  'GET /api/auth/config': async () => ({ m365: !!M365, tenantId: M365?.tenant, clientId: M365?.client, demo: DEMO }),

  'POST /api/auth/m365': async (req, body) => {
    if (!M365) throw fail(400, 'ยังไม่ได้ต่อ Microsoft 365');
    let email = null;
    try {
      email = await verifyIdToken(body.idToken, body.nonce);
    } catch (err) {
      if (!err.status) err = fail(401, 'ID token ไม่ถูกต้อง'); // malformed base64/JSON
      await logLogin(req, { method: 'm365', success: false, reason: err.message });
      throw err;
    }
    const [me] = await query(`${USER_SQL} WHERE u.Email = @Email`, { Email: email });
    return login(req, 'm365', me, email);
  },

  // ponytail: demo users list is capped per role; a training machine doesn't need all 246
  'GET /api/auth/demo-users': async () => {
    if (!DEMO) throw fail(404, 'ปิดผู้ใช้ตัวอย่างอยู่');
    return query(`SELECT UserID, Role, Email, Fname_TH, Lname_TH, Fname_EN, Lname_EN FROM (
        SELECT u.UserID, u.Role, u.Email, e.Fname_TH, e.Lname_TH, e.Fname_EN, e.Lname_EN,
               ROW_NUMBER() OVER (PARTITION BY u.Role ORDER BY u.UserID) rn
        FROM Users u JOIN Employee e ON e.UserID = u.UserID WHERE u.IsActive = 1) t
      WHERE rn <= 3 ORDER BY CASE Role WHEN 'superadmin' THEN 1 WHEN 'admin' THEN 2 WHEN 'manager' THEN 3 ELSE 4 END, UserID`);
  },

  'POST /api/auth/demo': async (req, body) => {
    if (!DEMO) throw fail(404, 'ปิดผู้ใช้ตัวอย่างอยู่');
    const [me] = await query(`${USER_SQL} WHERE u.UserID = @UserID`, { UserID: String(body.userId || '') });
    return login(req, 'demo', me, me?.Email);
  },

  'GET /api/me': async (req) => publicUser(await currentUser(req)),

  'GET /api/dashboard': async (req) => {
    const me = await currentUser(req);
    const where = SCOPE[me.Role];
    const p = { UserID: me.UserID, EmpID: me.EmpID, ComCode: me.ComCode };
    const [byDepartment, people] = await Promise.all([
      query(`SELECT COALESCE(e.Department_TH, e.Division_TH, N'(ไม่ระบุ)') AS Department, COUNT(*) AS Headcount,
                    SUM(e.[สิทธิลาพักร้อน]) AS Entitled, SUM(e.[ลาพักร้อนไปแล้ว/วัน]) AS Used
             FROM Employee e WHERE ${where} GROUP BY COALESCE(e.Department_TH, e.Division_TH, N'(ไม่ระบุ)')
             ORDER BY Headcount DESC`, p),
      query(`SELECT e.UserID, e.Fname_TH, e.Lname_TH, e.Position_TH, e.Department_TH,
                    e.[สิทธิลาพักร้อน] AS Entitled, e.[ลาพักร้อนไปแล้ว/วัน] AS Used
             FROM Employee e WHERE ${where} ORDER BY e.UserID`, p),
    ]);
    await query(`INSERT ActivityLog (UserID, Action) VALUES (@UserID, 'view_dashboard')`, { UserID: me.UserID });
    return { me: publicUser(me), byDepartment, people };
  },
};

async function readJson(req) {
  let raw = '';
  for await (const chunk of req) { raw += chunk; if (raw.length > 64e3) throw fail(413, 'too large'); }
  try { return raw ? JSON.parse(raw) : {}; } catch { throw fail(400, 'bad json'); }
}

http.createServer(async (req, res) => {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  const route = routes[`${req.method} ${new URL(req.url, 'http://x').pathname}`];
  try {
    if (!route) throw fail(404, 'not found');
    res.end(JSON.stringify(await route(req, req.method === 'POST' ? await readJson(req) : null)));
  } catch (err) {
    if (!err.status) console.error(err);
    res.statusCode = err.status || 500;
    res.end(JSON.stringify({ error: err.status ? err.message : 'server error' }));
  }
}).listen(env.API_PORT, '127.0.0.1', () => // local only: browsers reach it through the web server's /api proxy
   console.log(`API http://localhost:${env.API_PORT} · M365 ${M365 ? 'on' : 'off'} · demo ${DEMO ? 'on' : 'off'}`));
