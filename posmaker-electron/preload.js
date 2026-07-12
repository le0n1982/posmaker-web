const { contextBridge, ipcRenderer } = require('electron');

// For setup.html
contextBridge.exposeInMainWorld('electronSetup', {
  saveConfig: (url) => ipcRenderer.send('save-config', url)
});

// For cashier pages — same window.posApp API the Flutter exe used
contextBridge.exposeInMainWorld('posApp', {
  // Raw ESC/POS print, straight to the printer — preferred when available,
  // since it bypasses the Windows print driver entirely (more reliable with
  // cheap thermal printers, and the only path that can print the logo).
  printRaw: (receiptData) => ipcRenderer.invoke('print-raw-receipt', receiptData),
  // Lets the main process refuse to close the app window while a cashier is
  // logged in, so the drawer's Cash on Hand always gets counted at shift end.
  notifyLoggedIn:  () => ipcRenderer.send('cashier-logged-in'),
  notifyLoggedOut: () => ipcRenderer.send('cashier-logged-out'),
  onForceLogoutPrompt: (cb) => ipcRenderer.on('force-logout-prompt', cb),
  printReceipt: () => {
    const el  = document.getElementById('receiptPrintArea');
    const txt = el ? (el.textContent || '') : '';
    const escaped = txt
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');

    const html = '<!DOCTYPE html><html><head><meta charset="UTF-8">'
      + '<style>'
      + '@page{size:58mm auto;margin:2mm}'
      + 'html,body{color-scheme:light;-webkit-print-color-adjust:exact;print-color-adjust:exact}'
      + 'body{font-family:"Courier New",Courier,monospace;font-size:10.5pt;'
      + 'width:54mm;margin:0;padding:0;color:#000!important;background:#fff!important}'
      + 'pre{white-space:pre-wrap;word-break:break-word;margin:0;'
      + 'color:#000!important;background:#fff!important}'
      + '</style></head><body>'
      + '<pre>' + escaped + '</pre>'
      + '</body></html>';

    ipcRenderer.send('print-receipt', html);
  }
});
