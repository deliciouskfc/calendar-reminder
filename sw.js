// Service Worker - 离线缓存
const CACHE = 'calendar-v51';
const ASSETS = ['./', './index.html', './mobile.html', './manifest.json', './icon-192.png', './icon-512.png', './crest.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  // 关键修复：只缓存本站静态资源。Supabase API（rest/auth/realtime）及一切跨域请求
  // 绝不经过 SW 缓存，否则留言轮询会永远读到旧数据（v2.7.3 之前的全部怪象皆由此引起）
  if (url.origin !== self.location.origin) return;
  // 页面导航请求：网络优先，离线才回退缓存（保证发版后一次刷新即见新版）
  const isNavigate = e.request.mode === 'navigate' ||
    (e.request.headers.get('accept') || '').includes('text/html');
  if (isNavigate) {
    e.respondWith(
      fetch(e.request).then((res) => {
        const clone = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, clone));
        return res;
      }).catch(() => caches.match(e.request).then((cached) => cached || caches.match('./')))
    );
    return;
  }
  // 本站静态资源：缓存优先，未命中走网络并回填
  e.respondWith(
    caches.match(e.request).then((cached) =>
      cached ||
      fetch(e.request).then((res) => {
        const clone = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, clone));
        return res;
      }).catch(() => cached)
    )
  );
});
