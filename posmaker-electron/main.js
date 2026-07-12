const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs   = require('fs');
const { execSync } = require('child_process');
const os   = require('os');

const LINE_WIDTH = 32;

// Config lives next to the exe (production) or in __dirname (dev)
const configPath = app.isPackaged
  ? path.join(path.dirname(process.execPath), 'posmaker-config.json')
  : path.join(__dirname, 'posmaker-config.json');

function loadConfig() {
  try {
    if (fs.existsSync(configPath)) return JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (_) {}
  return null;
}

// ── Raw ESC/POS thermal printing ───────────────────────────────────────────
// Ported from posmaker-print-server.js — printing lives inside the app now,
// so cashiers no longer need to install/run a separate helper program.
let _cachedPrinterName = null;
function getDefaultPrinter() {
  if (_cachedPrinterName) return _cachedPrinterName;
  try {
    var name = execSync(
      'powershell -NonInteractive -NoProfile -Command ' +
      '"(Get-WmiObject Win32_Printer | Where-Object { $_.Default -eq $true }).Name"',
      { encoding: 'utf8', timeout: 8000 }
    ).trim();
    _cachedPrinterName = name || null;
    return _cachedPrinterName;
  } catch (_) { return null; }
}

function buildEscPos(r) {
  var W = LINE_WIDTH;
  var chunks = [];

  function safe(s) {
    return String(s || '').replace(/₱/g, 'P').replace(/[^\x20-\x7E]/g, '?');
  }
  function enc(s)  { return Buffer.from(safe(s), 'latin1'); }
  function line(s) { return Buffer.concat([enc(s), Buffer.from([0x0A])]); }
  function div()   { return line('-'.repeat(W)); }
  function pad(l, r) {
    var g = W - l.length - r.length;
    return l + ' '.repeat(Math.max(1, g)) + r;
  }

  var store  = safe(r.store  || 'POSMaker').substring(0, W);
  var footer = safe(r.footer || 'Thank you!').substring(0, W);
  var time   = new Date().toLocaleTimeString('en-PH', { hour: '2-digit', minute: '2-digit', hour12: true });
  var date   = new Date().toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' });

  chunks.push(Buffer.from([0x1B, 0x40]));

  // Store logo, printed as an ESC/POS raster image (GS v 0) at the top of the
  // receipt. The cashier page pre-converts the logo to a packed 1bpp bitmap
  // (see _buildLogoRaster() in the cashier page) with the Canvas API.
  if (r.logo_raster_b64 && r.logo_w_bytes && r.logo_h_px) {
    try {
      var logoBuf = Buffer.from(r.logo_raster_b64, 'base64');
      var wBytes  = r.logo_w_bytes | 0;
      var hPx     = r.logo_h_px | 0;
      if (logoBuf.length === wBytes * hPx) {
        chunks.push(Buffer.from([0x1B, 0x61, 0x01]));
        chunks.push(Buffer.from([0x1D, 0x76, 0x30, 0x00, wBytes & 0xFF, (wBytes >> 8) & 0xFF, hPx & 0xFF, (hPx >> 8) & 0xFF]));
        chunks.push(logoBuf);
        chunks.push(Buffer.from([0x0A]));
      }
    } catch (_) { /* bad/corrupt logo data — skip it, still print the rest of the receipt */ }
  }

  chunks.push(Buffer.from([0x1B, 0x61, 0x01]));
  chunks.push(Buffer.from([0x1B, 0x21, 0x10]));
  chunks.push(line(store));
  chunks.push(Buffer.from([0x1B, 0x21, 0x00]));
  if (r.address) chunks.push(line(safe(r.address).substring(0, W)));
  if (r.phone)   chunks.push(line(safe(r.phone).substring(0, W)));
  chunks.push(Buffer.from([0x1B, 0x61, 0x00]));
  chunks.push(div());
  chunks.push(line(date + '  ' + time));
  chunks.push(line('Order #' + safe(r.order_id)));
  chunks.push(line('Cashier: ' + safe(r.cashier)));
  if (r.orderType) chunks.push(line('Type: ' + safe(r.orderType) + (r.tableNo ? ' | ' + safe(r.tableNo) : '')));
  chunks.push(div());

  for (var i = 0; i < (r.items || []).length; i++) {
    var item  = r.items[i];
    var qty   = parseFloat(item.qty   || 1);
    var price = parseFloat(item.price || 0);
    chunks.push(line(safe(item.name).substring(0, W)));
    chunks.push(line('  ' + qty + ' x P' + price.toFixed(2) + ' = P' + (qty * price).toFixed(2)));
  }

  chunks.push(div());
  chunks.push(line(pad('Subtotal:', 'P' + parseFloat(r.sub  || 0).toFixed(2))));
  if (parseFloat(r.disc || 0) > 0)
    chunks.push(line(pad('Discount:', '-P' + parseFloat(r.disc).toFixed(2))));
  chunks.push(line(pad('VAT (12%):', 'P' + parseFloat(r.tax  || 0).toFixed(2))));
  chunks.push(Buffer.from([0x1B, 0x45, 0x01]));
  chunks.push(line(pad('TOTAL:', 'P' + parseFloat(r.total || 0).toFixed(2))));
  chunks.push(Buffer.from([0x1B, 0x45, 0x00]));

  if (r.method === 'Cash') {
    chunks.push(line(pad('Cash:',   'P' + parseFloat(r.tender || 0).toFixed(2))));
    chunks.push(line(pad('Change:', 'P' + parseFloat(r.change || 0).toFixed(2))));
  } else {
    chunks.push(line(pad('Paid via:', safe(r.method || 'GCash'))));
  }

  chunks.push(div());
  chunks.push(Buffer.from([0x1B, 0x61, 0x01]));
  chunks.push(line(footer));
  chunks.push(Buffer.from([0x1B, 0x61, 0x00]));
  chunks.push(Buffer.from([0x0A, 0x0A, 0x0A]));
  chunks.push(Buffer.from([0x1D, 0x56, 0x41, 0x03]));

  return Buffer.concat(chunks);
}

function sendToPrinter(printerName, data) {
  var ts     = Date.now();
  var tmpPrn = path.join(os.tmpdir(), 'pm_' + ts + '.prn');
  var tmpPs1 = path.join(os.tmpdir(), 'pm_' + ts + '.ps1');

  fs.writeFileSync(tmpPrn, data);

  var prnPath = tmpPrn.replace(/\\/g, '/');
  var ps1 = [
    "$bytes = [System.IO.File]::ReadAllBytes('" + prnPath + "')",
    "Add-Type -TypeDefinition @'",
    "using System;using System.Runtime.InteropServices;",
    "public class PMPrint {",
    "  [DllImport(\"winspool.drv\",CharSet=CharSet.Unicode,SetLastError=true)]",
    "  public static extern bool OpenPrinter(string n,out IntPtr h,IntPtr d);",
    "  [DllImport(\"winspool.drv\",SetLastError=true)]",
    "  public static extern int StartDocPrinter(IntPtr h,int level,IntPtr pDocInfo);",
    "  [DllImport(\"winspool.drv\",SetLastError=true)]",
    "  public static extern bool StartPagePrinter(IntPtr h);",
    "  [DllImport(\"winspool.drv\",SetLastError=true)]",
    "  public static extern bool WritePrinter(IntPtr h,byte[] buf,int len,out int written);",
    "  [DllImport(\"winspool.drv\",SetLastError=true)]",
    "  public static extern bool EndPagePrinter(IntPtr h);",
    "  [DllImport(\"winspool.drv\",SetLastError=true)]",
    "  public static extern bool EndDocPrinter(IntPtr h);",
    "  [DllImport(\"winspool.drv\",SetLastError=true)]",
    "  public static extern bool ClosePrinter(IntPtr h);",
    "}",
    "'@",
    "$h = [IntPtr]::Zero",
    "[PMPrint]::OpenPrinter(\"" + printerName + "\", [ref]$h, [IntPtr]::Zero) | Out-Null",
    "if ($h -eq [IntPtr]::Zero) { Write-Host 'ERR:OpenPrinter'; exit 1 }",
    "$pDoc  = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(24)",
    "$pName = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni('Receipt')",
    "[System.Runtime.InteropServices.Marshal]::WriteIntPtr($pDoc,  0, $pName)",
    "[System.Runtime.InteropServices.Marshal]::WriteIntPtr($pDoc,  8, [IntPtr]::Zero)",
    "[System.Runtime.InteropServices.Marshal]::WriteIntPtr($pDoc, 16, [IntPtr]::Zero)",
    "$jobId   = [PMPrint]::StartDocPrinter($h, 1, $pDoc)",
    "$e1      = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()",
    "[PMPrint]::StartPagePrinter($h) | Out-Null",
    "$written = 0",
    "[PMPrint]::WritePrinter($h, $bytes, $bytes.Length, [ref]$written) | Out-Null",
    "[PMPrint]::EndPagePrinter($h)  | Out-Null",
    "[PMPrint]::EndDocPrinter($h)   | Out-Null",
    "[PMPrint]::ClosePrinter($h)    | Out-Null",
    "[System.Runtime.InteropServices.Marshal]::FreeHGlobal($pDoc)",
    "[System.Runtime.InteropServices.Marshal]::FreeHGlobal($pName)",
    "Write-Host \"job:$jobId e1:$e1 written:$written\""
  ].join('\r\n');

  fs.writeFileSync(tmpPs1, ps1, 'utf8');

  try {
    var result = execSync(
      'powershell -NonInteractive -NoProfile -File "' + tmpPs1 + '"',
      { timeout: 15000, encoding: 'utf8' }
    );
    try { fs.unlinkSync(tmpPrn); fs.unlinkSync(tmpPs1); } catch(_) {}
    return result.trim();
  } catch (e) {
    try { fs.unlinkSync(tmpPrn); fs.unlinkSync(tmpPs1); } catch(_) {}
    throw new Error(e.stderr || e.stdout || e.message);
  }
}

let mainWin;

// Tracks whether a cashier is currently logged in on the POS window, so the
// window can refuse to close until they log out (which requires entering
// Cash on Hand) — see the 'close' handler in createPosWindow() below.
let cashierLoggedIn = false;
ipcMain.on('cashier-logged-in',  () => { cashierLoggedIn = true; });
ipcMain.on('cashier-logged-out', () => { cashierLoggedIn = false; });

function createPosWindow(url) {
  mainWin = new BrowserWindow({
    width: 1280, height: 800,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    }
  });
  mainWin.maximize();
  mainWin.setMenuBarVisibility(false);
  mainWin.loadURL(url);
  mainWin.on('close', (e) => {
    if (cashierLoggedIn) {
      e.preventDefault();
      mainWin.webContents.send('force-logout-prompt');
    }
  });
}

// First run (no saved cashier URL yet) — show the local "paste your cashier
// URL" screen instead of jumping straight to the store owner's admin login.
function createSetupWindow() {
  mainWin = new BrowserWindow({
    width: 900, height: 650,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    }
  });
  mainWin.setMenuBarVisibility(false);
  mainWin.loadFile(path.join(__dirname, 'setup.html'));
}

// First-run: save URL from setup screen and reload as POS
ipcMain.on('save-config', (event, url) => {
  fs.writeFileSync(configPath, JSON.stringify({ url }), 'utf8');
  mainWin.close();
  createPosWindow(url);
});

// Raw ESC/POS print — talks straight to the printer, no OS print dialog/driver
ipcMain.handle('print-raw-receipt', (event, receipt) => {
  try {
    const printerName = getDefaultPrinter();
    if (!printerName) return { ok: false, error: 'No default printer found' };
    const escData = buildEscPos(receipt || {});
    const result  = sendToPrinter(printerName, escData);
    return { ok: true, result };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

// Silent print — hidden window, no dialog, no flash
ipcMain.on('print-receipt', (event, html) => {
  const pw = new BrowserWindow({
    show: false,
    webPreferences: { contextIsolation: true }
  });
  pw.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent(html));
  pw.webContents.once('did-finish-load', () => {
    pw.webContents.print({ silent: true, printBackground: true }, () => {
      pw.destroy();
    });
  });
});

app.whenReady().then(() => {
  const cfg = loadConfig();
  if (cfg && cfg.url) createPosWindow(cfg.url);
  else createSetupWindow();
});

app.on('window-all-closed', () => app.quit());
