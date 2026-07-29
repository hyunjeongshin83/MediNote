/* MediNote 서비스워커 — 오프라인 캐시 + 알림(푸시) 표시 (원본 앱 UI 변경 없음) */
const CACHE="medinote-app-v2";
const ASSETS=["MediNote_app.html","manifest.webmanifest","icon-192.png","icon-512.png","icon-512-maskable.png","apple-touch-icon.png","favicon-32.png"];

self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting()));});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==CACHE).map(x=>caches.delete(x)))).then(()=>self.clients.claim()));});

self.addEventListener("fetch",e=>{
  const req=e.request; if(req.method!=="GET")return;
  const u=new URL(req.url);
  if(u.origin!==self.location.origin){ e.respondWith(fetch(req).catch(()=>caches.match(req))); return; } // Supabase 등: 네트워크 우선
  e.respondWith(caches.match(req).then(h=>h||fetch(req).then(r=>{const c=r.clone();caches.open(CACHE).then(x=>x.put(req,c)).catch(()=>{});return r;}).catch(()=>caches.match("MediNote_app.html"))));
});

/* 접종 시기 알림 등 — 푸시 수신 시 알림 표시 (백엔드 푸시 연결 시 동작) */
self.addEventListener("push",e=>{
  let data={title:"MediNote",body:"접종·복약 안내가 도착했어요."};
  try{ if(e.data) data=Object.assign(data,e.data.json()); }catch(_){ if(e.data) data.body=e.data.text(); }
  e.waitUntil(self.registration.showNotification(data.title,{body:data.body,icon:"icon-192.png",badge:"favicon-32.png",lang:"ko"}));
});
self.addEventListener("notificationclick",e=>{
  e.notification.close();
  e.waitUntil(self.clients.matchAll({type:"window"}).then(cl=>{ for(const c of cl){ if("focus" in c) return c.focus(); } if(self.clients.openWindow) return self.clients.openWindow("MediNote_app.html"); }));
});
