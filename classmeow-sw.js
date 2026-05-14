// ============================================================
// ClassMeow Service Worker v1.0
// วางไฟล์นี้ที่ root เดียวกับ index.html
// ============================================================

const CACHE_NAME = 'classmeow-v1';
const STATIC_ASSETS = [
  '/',
  '/index.html',
  'https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;500;600;700&display=swap',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
];

// ── Install: cache static assets ──
self.addEventListener('install', (event) => {
  console.log('[SW] Installing ClassMeow Service Worker...');
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS.filter(url => url.startsWith('/')));
    }).then(() => self.skipWaiting())
  );
});

// ── Activate: clean old caches ──
self.addEventListener('activate', (event) => {
  console.log('[SW] Activating...');
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// ── Fetch: Network First, fallback to cache ──
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Skip Supabase API calls — always network
  if (url.hostname.includes('supabase.co')) return;
  // Skip chrome-extension and non-http
  if (!event.request.url.startsWith('http')) return;

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // Cache successful GET requests
        if (event.request.method === 'GET' && response.status === 200) {
          const cloned = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, cloned));
        }
        return response;
      })
      .catch(() => {
        // Offline fallback
        return caches.match(event.request).then(cached => {
          if (cached) return cached;
          // Return offline page for navigation requests
          if (event.request.mode === 'navigate') {
            return caches.match('/index.html');
          }
        });
      })
  );
});

// ── Push Notification Handler ──
self.addEventListener('push', (event) => {
  if (!event.data) return;

  let data;
  try { data = event.data.json(); }
  catch { data = { title: 'ClassMeow', body: event.data.text(), icon: '/icon-192.png' }; }

  const options = {
    body: data.body || 'มีการแจ้งเตือนใหม่',
    icon: data.icon || '/icon-192.png',
    badge: '/badge-72.png',
    tag: data.tag || 'classmeow-notif',
    renotify: true,
    requireInteraction: data.requireInteraction || false,
    data: { url: data.url || '/', ts: Date.now() },
    actions: data.actions || [],
    vibrate: [200, 100, 200],
  };

  event.waitUntil(
    self.registration.showNotification(data.title || '🐱 ClassMeow', options)
  );
});

// ── Notification Click ──
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = event.notification.data?.url || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // Focus existing window if open
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.focus();
          client.postMessage({ type: 'NOTIFICATION_CLICK', url: targetUrl });
          return;
        }
      }
      // Open new window
      if (clients.openWindow) return clients.openWindow(targetUrl);
    })
  );
});

// ── Background Sync (for offline data) ──
self.addEventListener('sync', (event) => {
  if (event.tag === 'classmeow-sync') {
    console.log('[SW] Background sync triggered');
    event.waitUntil(syncOfflineData());
  }
});

async function syncOfflineData() {
  // Notify all clients to sync their pending data
  const clientList = await clients.matchAll();
  clientList.forEach(client => {
    client.postMessage({ type: 'SYNC_NOW' });
  });
}

// ── Message Handler (from main app) ──
self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  if (event.data?.type === 'SCHEDULE_NOTIFICATION') {
    scheduleClassReminder(event.data.payload);
  }
});

// ── Schedule class reminder ──
const scheduledReminders = new Map();

function scheduleClassReminder({ id, title, body, delayMs, tag }) {
  // Clear existing
  if (scheduledReminders.has(id)) {
    clearTimeout(scheduledReminders.get(id));
  }
  if (delayMs <= 0) return;

  const timer = setTimeout(() => {
    self.registration.showNotification(`🔔 ${title}`, {
      body,
      icon: '/icon-192.png',
      tag: tag || id,
      vibrate: [300, 100, 300],
      data: { url: '/?page=timetable' },
    });
    scheduledReminders.delete(id);
  }, delayMs);

  scheduledReminders.set(id, timer);
  console.log(`[SW] Reminder scheduled: "${title}" in ${Math.round(delayMs/60000)} min`);
}
