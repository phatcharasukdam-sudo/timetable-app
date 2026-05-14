// ============================================================
// ClassMeow — Month 1 Features Module
// วาง <script src="classmeow-features.js"></script>
// ก่อน </body> ใน index.html
// ============================================================

// ── 1. SERVICE WORKER REGISTRATION ──────────────────────────
async function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) {
    console.warn('[ClassMeow] Service Worker not supported');
    return null;
  }
  try {
    const reg = await navigator.serviceWorker.register('/classmeow-sw.js', {
      scope: '/',
      updateViaCache: 'none',
    });
    console.log('[ClassMeow] SW registered:', reg.scope);

    // Listen for SW messages
    navigator.serviceWorker.addEventListener('message', handleSWMessage);

    // Check for updates every 60s when page visible
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') reg.update();
    });

    return reg;
  } catch (err) {
    console.error('[ClassMeow] SW registration failed:', err);
    return null;
  }
}

function handleSWMessage(event) {
  const { type, url } = event.data || {};
  if (type === 'NOTIFICATION_CLICK' && url) {
    // Navigate to page from notification click
    const page = new URL(url, window.location).searchParams.get('page');
    if (page && typeof goPage === 'function') goPage(page);
  }
  if (type === 'SYNC_NOW') {
    console.log('[ClassMeow] Background sync triggered from SW');
    // Could trigger Supabase re-fetch here
  }
}

// ── 2. WEB PUSH NOTIFICATIONS ───────────────────────────────
const VAPID_PUBLIC_KEY = 'YOUR_VAPID_PUBLIC_KEY_HERE';
// Generate VAPID keys at: https://vapidkeys.com
// Or run: npx web-push generate-vapid-keys

function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) outputArray[i] = rawData.charCodeAt(i);
  return outputArray;
}

async function subscribeToPush() {
  if (!('PushManager' in window)) {
    showToast('เบราว์เซอร์นี้ไม่รองรับ Push Notification', 'warn');
    return null;
  }
  const reg = await navigator.serviceWorker.ready;
  try {
    const existing = await reg.pushManager.getSubscription();
    if (existing) return existing;

    const subscription = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
    });

    // Save subscription to Supabase (if connected)
    if (typeof supabase !== 'undefined' && window.CU) {
      await supabase.from('push_subscriptions').upsert({
        user_id: window.CU.id,
        subscription: JSON.stringify(subscription),
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' });
    }

    console.log('[ClassMeow] Push subscription saved');
    return subscription;
  } catch (err) {
    console.error('[ClassMeow] Push subscription failed:', err);
    return null;
  }
}

async function requestPushPermission() {
  const perm = await Notification.requestPermission();
  if (perm === 'granted') {
    await subscribeToPush();
    showToast('🔔 เปิดการแจ้งเตือนสำเร็จ!', 'success');
    return true;
  }
  showToast('ไม่ได้รับอนุญาต — กรุณาเปิดใน Settings ของเบราว์เซอร์', 'warn');
  return false;
}

// Schedule class reminder via Service Worker
async function scheduleClassNotification({ id, title, body, delayMs }) {
  if (Notification.permission !== 'granted') return;
  const reg = await navigator.serviceWorker.ready;
  // Send to SW to handle the timer (survives page close)
  reg.active?.postMessage({
    type: 'SCHEDULE_NOTIFICATION',
    payload: { id, title, body, delayMs, tag: `class-${id}` },
  });
}

// Cancel a scheduled reminder
async function cancelClassNotification(id) {
  const reg = await navigator.serviceWorker.ready;
  reg.active?.postMessage({ type: 'CANCEL_NOTIFICATION', id });
}

// ── 3. GOOGLE OAUTH ──────────────────────────────────────────
async function signInWithGoogle() {
  if (typeof supabase === 'undefined') {
    showToast('กรุณาเชื่อมต่อ Supabase ก่อน', 'warn');
    return;
  }
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: window.location.origin + window.location.pathname,
      queryParams: {
        access_type: 'offline',
        prompt: 'consent',
      },
    },
  });
  if (error) showToast('Login ด้วย Google ไม่สำเร็จ: ' + error.message, 'error');
}

// ── 4. ICS EXPORT (Google Calendar / Apple Calendar) ─────────
function generateICS(events) {
  const now = formatICSDate(new Date());
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//ClassMeow//TH',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:ClassMeow — ตารางเรียน',
    'X-WR-CALDESC:ตารางเรียนจาก ClassMeow',
    'X-WR-TIMEZONE:Asia/Bangkok',
    'BEGIN:VTIMEZONE',
    'TZID:Asia/Bangkok',
    'BEGIN:STANDARD',
    'DTSTART:19700101T000000',
    'TZOFFSETFROM:+0700',
    'TZOFFSETTO:+0700',
    'TZNAME:ICT',
    'END:STANDARD',
    'END:VTIMEZONE',
  ];

  events.forEach(ev => {
    lines.push(
      'BEGIN:VEVENT',
      `UID:${ev.id || crypto.randomUUID()}@classmeow`,
      `DTSTAMP:${now}`,
      `DTSTART;TZID=Asia/Bangkok:${formatICSDate(ev.start)}`,
      `DTEND;TZID=Asia/Bangkok:${formatICSDate(ev.end)}`,
      `SUMMARY:${escapeICS(ev.title)}`,
      ev.location ? `LOCATION:${escapeICS(ev.location)}` : '',
      ev.description ? `DESCRIPTION:${escapeICS(ev.description)}` : '',
      ev.rrule ? `RRULE:${ev.rrule}` : '',
      `STATUS:CONFIRMED`,
      `SEQUENCE:0`,
      'END:VEVENT',
    ).filter(Boolean);
  });

  lines.push('END:VCALENDAR');
  return lines.join('\r\n');
}

function formatICSDate(date) {
  const d = date instanceof Date ? date : new Date(date);
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth()+1)}${pad(d.getDate())}T${pad(d.getHours())}${pad(d.getMinutes())}00`;
}

function escapeICS(str) {
  return String(str || '').replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n');
}

function downloadICS(icsContent, filename = 'classmeow-timetable.ics') {
  const blob = new Blob([icsContent], { type: 'text/calendar;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// Convert ClassMeow timetable to ICS events (weekly recurring)
function timetableToICS(timetable, periods, days, subjects) {
  const dayOffsets = { // Days relative to Monday
    'วันจันทร์': 0, 'วันอังคาร': 1, 'วันพุธ': 2,
    'วันพฤหัสบดี': 3, 'วันศุกร์': 4, 'วันเสาร์': 5, 'วันอาทิตย์': 6,
  };
  const rruleDays = ['MO','TU','WE','TH','FR','SA','SU'];
  const today = new Date();
  // Find this week's Monday
  const monday = new Date(today);
  monday.setDate(today.getDate() - today.getDay() + 1);
  monday.setHours(0,0,0,0);

  const events = [];

  Object.entries(timetable).forEach(([key, subjId]) => {
    const [dayIdx, periodId] = key.split('_');
    const dayName = days[parseInt(dayIdx)];
    const period = periods.find(p => p.id === periodId);
    const subj = subjects.find(s => s.id === subjId);
    if (!dayName || !period || !subj || period.b) return;

    const offset = dayOffsets[dayName] ?? parseInt(dayIdx);
    const rruleDay = rruleDays[offset] || 'MO';
    const [sh, sm] = period.s.split(':').map(Number);
    const [eh, em] = period.e.split(':').map(Number);

    const startDate = new Date(monday);
    startDate.setDate(monday.getDate() + offset);
    startDate.setHours(sh, sm, 0, 0);

    const endDate = new Date(startDate);
    endDate.setHours(eh, em, 0, 0);

    events.push({
      id: `${key}-${subjId}`,
      title: `${subj.icon || '📚'} ${subj.name}`,
      start: startDate,
      end: endDate,
      location: subj.room ? `ห้อง ${subj.room}` : '',
      description: [
        subj.code ? `รหัสวิชา: ${subj.code}` : '',
        subj.teacher ? `ครูผู้สอน: ${subj.teacher}` : '',
        `เวลา: ${period.s}–${period.e} น.`,
      ].filter(Boolean).join('\\n'),
      rrule: `FREQ=WEEKLY;BYDAY=${rruleDay}`,
    });
  });

  return generateICS(events);
}

// Export button handler — called from UI
async function exportToCalendar() {
  // Works with both localStorage and Supabase versions
  let slots, periods, days, subjects;

  if (typeof activeTTId !== 'undefined' && typeof getSlots === 'function') {
    // localStorage version
    slots = getSlots(activeTTId);
    const cfg = getUserSettings();
    periods = cfg.periods;
    days = cfg.days;
    subjects = getUserSubjects();
  } else {
    showToast('กรุณาเปิดตารางก่อน export', 'warn');
    return;
  }

  if (!Object.keys(slots).length) {
    showToast('ตารางว่างเปล่า ยังไม่มีวิชาในตาราง', 'warn');
    return;
  }

  const icsContent = timetableToICS(slots, periods, days, subjects);
  const ttName = document.getElementById('tt-page-title')?.textContent?.replace('📅','').trim() || 'timetable';
  downloadICS(icsContent, `classmeow-${ttName}.ics`);
  showToast('📅 Export ไปยัง Calendar สำเร็จ! เปิดไฟล์ .ics เพื่อ import', 'success', 5000);
}

// ── 5. PWA INSTALL PROMPT ─────────────────────────────────────
let _deferredInstallPrompt = null;

window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  _deferredInstallPrompt = e;
  // Show install banner after 30s or when user has done something
  setTimeout(showInstallBanner, 30000);
});

function showInstallBanner() {
  if (!_deferredInstallPrompt) return;
  if (localStorage.getItem('cm_install_dismissed')) return;
  if (typeof showToast !== 'function') return;

  const toast = showToast(
    '📲 ติดตั้ง ClassMeow บนอุปกรณ์ของคุณ — ใช้ได้แบบแอปจริง!',
    'info', 0
  );
  if (toast) {
    const btn = document.createElement('button');
    btn.textContent = 'ติดตั้ง';
    btn.style.cssText = 'margin-left:8px;padding:4px 10px;border-radius:6px;border:none;background:rgba(255,255,255,.25);color:#fff;font-weight:700;cursor:pointer;font-family:Sarabun,sans-serif;';
    btn.onclick = async () => {
      _deferredInstallPrompt.prompt();
      const { outcome } = await _deferredInstallPrompt.userChoice;
      if (outcome === 'accepted') showToast('🎉 ติดตั้ง ClassMeow สำเร็จ!', 'success');
      _deferredInstallPrompt = null;
      toast.remove();
    };
    toast.appendChild(btn);
    // Dismiss button
    const dis = document.createElement('button');
    dis.textContent = '✕';
    dis.style.cssText = 'margin-left:4px;padding:4px 8px;border-radius:6px;border:none;background:rgba(255,255,255,.15);color:#fff;cursor:pointer;';
    dis.onclick = () => {
      localStorage.setItem('cm_install_dismissed', '1');
      toast.remove();
    };
    toast.appendChild(dis);
  }
}

window.addEventListener('appinstalled', () => {
  showToast('🎉 ClassMeow ติดตั้งสำเร็จ!', 'success');
  _deferredInstallPrompt = null;
});

// ── 6. AUTO-INIT on DOM ready ─────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  // Register SW
  registerServiceWorker();

  // Handle URL params (from notification click deep link)
  const urlPage = new URLSearchParams(window.location.search).get('page');
  if (urlPage) {
    // Wait for app to init then navigate
    const waitForApp = setInterval(() => {
      if (typeof goPage === 'function' && typeof CU !== 'undefined' && CU) {
        clearInterval(waitForApp);
        goPage(urlPage);
      }
    }, 200);
    setTimeout(() => clearInterval(waitForApp), 5000);
  }
});

// Export functions for use in main app
window.ClassMeowFeatures = {
  registerServiceWorker,
  requestPushPermission,
  scheduleClassNotification,
  cancelClassNotification,
  signInWithGoogle,
  exportToCalendar,
  generateICS,
  timetableToICS,
  downloadICS,
};

console.log('🐱 ClassMeow Features Module loaded (SW + Push + OAuth + ICS)');
