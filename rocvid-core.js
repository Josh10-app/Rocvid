/* =====================================================================
   rocvid-core.js : kod dikongsi oleh index.html dan rocvid_music.html
   Muatkan SELEPAS config.js dan pustaka supabase-js.
   ===================================================================== */

/* ---------- Konfigurasi dan klien Supabase ---------- */
const CFG = Object.assign({ supabaseUrl:'', supabaseAnonKey:'', maxUploadMB:50, siteUrl:'index.html', studioUrl:'rocvid_music.html' }, window.ROCVID_CONFIG || {});
const CONFIGURED = /^https:\/\/\S+$/.test(CFG.supabaseUrl) && !/ISI|YOUR|EXAMPLE|xxxx/i.test(CFG.supabaseUrl + CFG.supabaseAnonKey) && CFG.supabaseAnonKey.length > 20;
let sb = null;
const LIB = { ok:false, tried:[] };
const LIB_SOURCES = ['https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2', 'https://unpkg.com/@supabase/supabase-js@2',
  'https://cdnjs.cloudflare.com/ajax/libs/supabase-js/2.45.4/supabase.min.js', 'supabase.js'];
const loadScript = src => new Promise((res, rej) => { const el = document.createElement('script'); el.src = src; el.onload = res; el.onerror = () => rej(new Error(src)); document.head.appendChild(el); });
/* Muat pustaka supabase-js (cuba beberapa sumber), kemudian cipta klien. Panggil sekali semasa mula. */
async function loadSupabase() {
  if (!window.supabase) for (const src of LIB_SOURCES) { LIB.tried.push(src); try { await loadScript(src); if (window.supabase) break; } catch (e) {} }
  LIB.ok = !!window.supabase;
  if (CONFIGURED && LIB.ok) sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey, { auth:{ flowType:'pkce', persistSession:true, autoRefreshToken:true, detectSessionInUrl:true } });
  return !!sb;
}

/* ---------- Helper umum ---------- */
const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const slugify = t => (t || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
const num = n => n < 1e3 ? String(n) : n < 1e6 ? (n / 1e3).toFixed(n < 1e4 ? 1 : 0).replace('.0', '') + ' rb' : (n / 1e6).toFixed(1).replace('.0', '') + ' j';
const fmt = s => {
  if (!isFinite(s) || s < 0) s = 0; s = Math.round(s);
  const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
  return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(x).padStart(2, '0');
};
const ago = t => {
  const s = (Date.now() - t) / 1000;
  if (!isFinite(s)) return '';
  if (s < 60) return 'baru sahaja';
  if (s < 3600) return Math.floor(s / 60) + ' minit lalu';
  if (s < 86400) return Math.floor(s / 3600) + ' jam lalu';
  if (s < 2592000) return Math.floor(s / 86400) + ' hari lalu';
  if (s < 31536000) return Math.floor(s / 2592000) + ' bulan lalu';
  return Math.floor(s / 31536000) + ' tahun lalu';
};
const hue = seed => { let h = 0; for (const c of String(seed)) h = (h * 31 + c.charCodeAt(0)) % 360; return h; };
const grad = seed => { const h = hue(seed); return `linear-gradient(135deg,hsl(${h} 58% 40%),hsl(${(h + 50) % 360} 62% 26%))`; };
const safeUrl = u => (typeof u === 'string' && /^https:\/\//i.test(u)) ? u : '';
const urlOf = path => path ? `${CFG.supabaseUrl.replace(/\/$/, '')}/storage/v1/object/public/media/${String(path).split('/').map(encodeURIComponent).join('/')}` : '';

let toastTimer;
function toast(msg) {
  let t = $('#toast');
  if (!t) { t = document.createElement('div'); t.id = 'toast'; t.setAttribute('role', 'status'); t.setAttribute('aria-live', 'polite'); document.body.appendChild(t); }
  t.textContent = msg; t.classList.add('on');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('on'), 3200);
}

/* ---------- Ikon dan lencana ---------- */
const ICONS = {
  home:'<path d="M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
  flame:'<path d="M12 3c.5 4 5 6 5 11a5 5 0 0 1-10 0c0-2 1-3.5 2-4.5.2 1.5 1 2.5 2 2.5C11 8 10.5 5.5 12 3z"/>',
  music:'<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
  users:'<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5"/><path d="M16 5a3 3 0 0 1 0 6M18 15c2 .6 3 2.2 3 5"/>',
  bookmark:'<path d="M6 3h12v18l-6-4.5L6 21z"/>',
  thumb:'<path d="M7 11v9H4v-9zM7 11l4-8c1.8 0 3 1.2 3 3l-.8 4H19a2 2 0 0 1 2 2.3l-1 6A2 2 0 0 1 18 20H7"/>',
  clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  film:'<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M8 4v16M16 4v16M3 12h18"/>',
  disc:'<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2.5"/><path d="M12 3a9 9 0 0 1 9 9"/>',
  share:'<path d="M4 12v7h16v-7M12 15V3M8 7l4-4 4 4"/>',
  flag:'<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
  sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  moon:'<path d="M21 13A9 9 0 1 1 11 3a7 7 0 0 0 10 10z"/>',
  check:'<path d="M5 12l5 5 9-10"/>', x:'<path d="M6 6l12 12M18 6L6 18"/>', plus:'<path d="M12 5v14M5 12h14"/>',
  trash:'<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>', back:'<path d="M15 5l-7 7 7 7"/>',
  edit:'<path d="M4 20h4L19 9l-4-4L4 16z"/>',
  building:'<path d="M4 21V5l8-2v18M12 9h8v12M7 9h2M7 13h2M7 17h2M15 13h2M15 17h2"/>',
  link:'<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
  play:'<path d="M8 5l11 7-11 7z" fill="currentColor" stroke="none"/>',
  pause:'<rect x="6" y="5" width="4" height="14" rx="1.2" fill="currentColor" stroke="none"/><rect x="14" y="5" width="4" height="14" rx="1.2" fill="currentColor" stroke="none"/>',
  next:'<path d="M6 5l9 7-9 7z" fill="currentColor" stroke="none"/><path d="M18 5v14"/>',
  vol:'<path d="M4 9v6h4l5 4V5L8 9z" fill="currentColor" stroke="none"/><path d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"/>',
  vollow:'<path d="M4 9v6h4l5 4V5L8 9z" fill="currentColor" stroke="none"/><path d="M16.5 8.5a5 5 0 0 1 0 7"/>',
  mute:'<path d="M4 9v6h4l5 4V5L8 9z" fill="currentColor" stroke="none"/><path d="M17 9l5 6M22 9l-5 6"/>',
  gear:'<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>',
  theater:'<rect x="2.5" y="7" width="19" height="10" rx="2"/>',
  pip:'<rect x="3" y="5" width="18" height="14" rx="2"/><rect x="12" y="11" width="7" height="5" rx="1" fill="currentColor" stroke="none"/>',
  fs:'<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>',
  fsx:'<path d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5"/>',
  replay:'<path d="M4 12a8 8 0 1 0 3-6.2M4 4v5h5"/>'
};
const ic = (n, cls = '') => `<svg class="ic ${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[n]}</svg>`;

/* Lencana Artis Rocvid: meterai bergerigi dengan not muzik berganda */
const BADGE = (() => {
  let lobes = '';
  for (let i = 0; i < 10; i++) { const a = i * Math.PI / 5; lobes += `<circle cx="${(12 + 7.6 * Math.cos(a)).toFixed(2)}" cy="${(12 + 7.6 * Math.sin(a)).toFixed(2)}" r="3.5"/>`; }
  return `<svg class="ab" viewBox="0 0 24 24" role="img" aria-label="Artis rasmi Rocvid"><title>Artis rasmi Rocvid</title>
    <g fill="url(#abGrad)">${lobes}<circle cx="12" cy="12" r="8.4"/></g>
    <g fill="none" stroke="#15132B" stroke-linecap="round" stroke-linejoin="round"><path d="M10.4 8.6v6.8M15.6 7.6v6.8" stroke-width="1.5"/><path d="M10.4 8.6l5.2-1" stroke-width="2.2"/></g>
    <g fill="#15132B"><ellipse cx="8.9" cy="15.7" rx="1.9" ry="1.4" transform="rotate(-18 8.9 15.7)"/><ellipse cx="14.1" cy="14.7" rx="1.9" ry="1.4" transform="rotate(-18 14.1 14.7)"/></g></svg>`;
})();
/* Tick emas berkilau untuk saluran rasmi Rocvid (cth. CEO). Gradien dan klip ditakrif sekali dalam <defs> global. */
const GOLD = (() => {
  let lobes = '';
  for (let i = 0; i < 12; i++) { const a = i * Math.PI / 6; lobes += `<circle cx="${(12 + 7.7 * Math.cos(a)).toFixed(2)}" cy="${(12 + 7.7 * Math.sin(a)).toFixed(2)}" r="3.3"/>`; }
  return `<svg class="ab gold" viewBox="0 0 24 24" role="img" aria-label="Akaun rasmi Rocvid"><title>Akaun rasmi Rocvid</title>
    <g fill="url(#goldGrad)">${lobes}<circle cx="12" cy="12" r="8.6"/></g>
    <g clip-path="url(#goldClip)"><rect class="shine" x="-10" y="-2" width="7" height="28" fill="#fff" opacity=".7"/></g>
    <path d="M7.4 12.4l3.1 3.1 6.1-6.6" fill="none" stroke="#5B3A00" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
})();
const chBadge = ch => ch && ch.official ? GOLD : (ch && ch.badge ? BADGE : '');
const GOOGLE = `<svg viewBox="0 0 48 48" width="20" height="20" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>`;

/* ---------- Pangkalan data ---------- */
async function must(q) { const { data, error } = await q; if (error) throw error; return data; }
function friendly(e) {
  const m = (e && e.message) || String(e), c = e && e.code;
  if (c === '23505') return /isrc/i.test(m) ? 'ISRC ini sudah digunakan' : /upc/i.test(m) ? 'UPC ini sudah digunakan' : /handle/i.test(m) ? 'Nama pengguna saluran ini sudah digunakan' : /artists_name/i.test(m) ? 'Artis dengan nama ini sudah wujud' : 'Data ini sudah wujud';
  if (c === '42501' || /row-level security/i.test(m)) return 'Anda tidak mempunyai kebenaran untuk tindakan ini';
  if (c === '28000' || /JWT|not authenticated/i.test(m)) return 'Sila log masuk semula';
  return m;
}
const mapChannel = r => ({ id:r.id, handle:r.handle, name:r.name, bio:r.bio || '', avatar:urlOf(r.avatar_path), banner:urlOf(r.banner_path), avatarPath:r.avatar_path || null, bannerPath:r.banner_path || null,
  owner:r.owner_id, kind:r.kind, badge:!!r.is_artist, official:!!r.official, title:r.official_title || '', subs:+r.subscriber_count || 0, managedBy:r.managed_by });
const mapVideo = r => ({ id:r.id, chId:r.channel_id, uploader:r.uploader_id, type:r.type, title:r.title, desc:r.description || '', cat:r.category || '', privacy:r.privacy, status:r.status,
  src:safeUrl(r.src_url) || urlOf(r.src_path), thumb:safeUrl(r.thumb_url) || urlOf(r.thumb_path), srcPath:r.src_path, thumbPath:r.thumb_path, dur:+r.duration_s || 0,
  views:+r.view_count || 0, likes:+r.like_count || 0, dislikes:+r.dislike_count || 0, t:Date.parse(r.created_at), releaseId:r.release_id, trackId:r.track_id, isrc:r.isrc });

async function uploadFile(file, folder) {
  if (!RV.user) throw new Error('Sila log masuk dahulu');
  if (file.size > CFG.maxUploadMB * 1048576) throw new Error(`Fail melebihi had ${CFG.maxUploadMB} MB (ubah maxUploadMB dalam config.js jika had storan sudah dinaikkan)`);
  const ext = ((file.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '') || 'bin').slice(0, 5);
  const path = `${RV.user.id}/${folder}/${uuid()}.${ext}`;
  const { error } = await sb.storage.from('media').upload(path, file, { contentType:file.type || undefined, cacheControl:'31536000', upsert:false });
  if (error) throw error;
  return path;
}
const imageSize = file => new Promise((res, rej) => {
  const u = URL.createObjectURL(file), im = new Image();
  im.onload = () => { res({ w:im.naturalWidth, h:im.naturalHeight }); URL.revokeObjectURL(u); };
  im.onerror = () => { rej(new Error('Imej tidak dapat dibaca')); URL.revokeObjectURL(u); };
  im.src = u;
});
const mediaDuration = (file, tag = 'video') => new Promise(res => {
  const el = document.createElement(tag), u = URL.createObjectURL(file); el.preload = 'metadata';
  el.onloadedmetadata = () => { res(isFinite(el.duration) ? el.duration : 0); URL.revokeObjectURL(u); };
  el.onerror = () => { res(0); URL.revokeObjectURL(u); };
  el.src = u;
});

/* ---------- Tema dan keutamaan setempat (jatuh balik ke memori jika storan disekat) ---------- */
const LS = {
  mem:{},
  get(k, d) { try { const v = localStorage.getItem(k); return v === null ? (k in this.mem ? this.mem[k] : d) : JSON.parse(v); } catch (e) { return k in this.mem ? this.mem[k] : d; } },
  set(k, v) { this.mem[k] = v; try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
};
function setTheme(t) {
  document.documentElement.dataset.theme = t; LS.set('rv_theme', t);
  const b = $('#themeBtn'); if (b) b.innerHTML = ic(t === 'dark' ? 'sun' : 'moon');
}
function initTheme() { setTheme(LS.get('rv_theme', null) || (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark')); }

/* ---------- Pengesahan (Google) ---------- */
const RV = {
  user:null, profile:null, onChange:null,

  async initAuth(onChange) {
    this.onChange = onChange;
    if (!sb) return;
    try { const { data } = await sb.auth.getSession(); await this._set(data.session); } catch (e) { this.user = null; }
    const sp = new URLSearchParams(location.search);
    if (sp.get('error_description')) toast(sp.get('error_description'));
    if (sp.has('code') || sp.has('error')) { try { history.replaceState(null, '', location.pathname + location.hash); } catch (e) {} }
    this._restoreNext();
    sb.auth.onAuthStateChange((ev, session) => {
      if (ev === 'INITIAL_SESSION' || ev === 'TOKEN_REFRESHED') return;
      setTimeout(async () => {                       // elak kunci mati: jangan panggil Supabase terus dalam callback
        const prev = this.user && this.user.id;
        await this._set(session);
        if ((session && session.user && session.user.id) !== prev && this.onChange) this.onChange(ev);
      }, 0);
    });
  },
  async _set(session) {
    this.user = (session && session.user) || null; this.profile = null;
    if (this.user) {
      try { this.profile = await must(sb.from('profiles').select('*').eq('id', this.user.id).maybeSingle()); } catch (e) {}
      if (!this.profile) this.profile = { id:this.user.id, display_name:this.user.email, avatar_url:null, is_admin:false };
    }
  },
  _restoreNext() {
    try {
      const n = sessionStorage.getItem('rv_next');
      if (n !== null) { sessionStorage.removeItem('rv_next'); if (n && !location.hash) history.replaceState(null, '', location.pathname + n); }
    } catch (e) {}
  },
  async signIn() {
    if (!sb) return toast('Isi config.js dahulu');
    try { sessionStorage.setItem('rv_next', location.hash); } catch (e) {}
    const { error } = await sb.auth.signInWithOAuth({ provider:'google', options:{ redirectTo:location.origin + location.pathname } });
    if (error) toast(friendly(error));
  },
  async claim() {                                   // tuntut saluran yang ditempah untuk emel akaun ini (cth. Joshwilent Roy)
    if (!sb || !this.user) return 0;
    try { return (await must(sb.rpc('claim_reserved_channels'))) || 0; } catch (e) { return 0; }
  },
  async signOut() { if (sb) await sb.auth.signOut(); },
  get name() { return (this.profile && this.profile.display_name) || (this.user && this.user.email) || ''; },

  /* Paparkan dialog log masuk jika belum log masuk. Pulang benar jika sudah log masuk. */
  need(reason) {
    if (this.user) return true;
    let d = $('#loginDlg');
    if (!d) {
      d = document.createElement('dialog'); d.id = 'loginDlg';
      d.innerHTML = `<div class="dlg"><header><h2>Log masuk ke Rocvid</h2><button type="button" class="x" data-close aria-label="Tutup">${ic('x')}</button></header>
        <p id="loginWhy" class="muted"></p>
        <button class="btn gbtn wide" data-auth="login">${GOOGLE}<span>Teruskan dengan Google</span></button>
        <p class="muted">Tidak perlu akaun untuk menonton. Akaun diperlukan untuk muat naik, komen dan langganan.</p></div>`;
      document.body.appendChild(d);
    }
    $('#loginWhy').textContent = reason ? `Log masuk untuk ${reason}.` : 'Log masuk untuk meneruskan.';
    d.showModal();
    return false;
  },

  /* Butang log masuk atau menu akaun. `extra` ialah HTML item menu tambahan. */
  authHTML(extra = '') {
    if (!this.user) return `<button class="btn gbtn" data-auth="login">${GOOGLE}<span>Log masuk</span></button>`;
    const av = safeUrl(this.profile && this.profile.avatar_url), nm = this.name;
    return `<div class="umenu"><button class="avbtn" data-auth="menu" aria-haspopup="menu" aria-expanded="false" aria-label="Akaun ${esc(nm)}">${av ? `<img src="${esc(av)}" alt="" referrerpolicy="no-referrer">` : esc((nm[0] || '?').toUpperCase())}</button>
      <div class="upop" hidden role="menu"><div class="uhead"><strong>${esc(nm)}</strong><span>${esc(this.user.email || '')}</span></div>${extra}
      <div class="sep"></div><button role="menuitem" data-auth="logout">Log keluar</button></div></div>`;
  },
  mountAuth(extra) { const el = $('#auth'); if (el) el.innerHTML = this.authHTML(extra); },

  setupHTML() {
    const row = (ok, t) => `<li class="${ok ? 'ok' : 'bad'}">${ok ? '✓' : '✗'} ${t}</li>`;
    const hasCfg = !!window.ROCVID_CONFIG;
    const title = !hasCfg ? 'config.js tidak dimuatkan' : !CONFIGURED ? 'config.js belum diisi' : 'Pustaka Supabase gagal dimuatkan';
    const help = !hasCfg ? 'Letakkan config.js dalam folder yang sama dengan halaman ini, kemudian muat semula (Ctrl+Shift+R).'
      : !CONFIGURED ? 'Isi supabaseUrl dan supabaseAnonKey dalam config.js.'
      : 'Nilai config.js sudah betul. Yang gagal ialah memuatkan pustaka supabase-js daripada CDN (sambungan internet, penyekat iklan atau pratonton yang menyekat skrip luar). Cuba buka melalui http://localhost atau domain anda, atau muat turun supabase.js dan letak dalam folder yang sama.';
    return `<div class="setup"><h1>${title}</h1><p class="muted">${help}</p>
      <ul class="diag">${row(hasCfg, 'config.js dimuatkan')}${row(CONFIGURED, 'URL dan kunci anon diisi')}${row(LIB.ok, 'Pustaka supabase-js dimuatkan')}</ul>
      ${LIB.tried.length && !LIB.ok ? `<p class="muted" style="margin-top:10px">Sumber dicuba: ${LIB.tried.map(esc).join(', ')}</p>` : ''}</div>`;
  }
};

/* ---------- Tetapan global: menu akaun, penutup dialog ---------- */
document.addEventListener('click', e => {
  const t = e.target; let el;
  if ((el = t.closest('[data-auth]'))) {
    const a = el.dataset.auth;
    if (a === 'login') RV.signIn();
    else if (a === 'logout') RV.signOut();
    else if (a === 'menu') { const p = el.parentElement.querySelector('.upop'); p.hidden = !p.hidden; el.setAttribute('aria-expanded', !p.hidden); }
    return;
  }
  if (!t.closest('.umenu')) $$('.upop').forEach(p => { p.hidden = true; });
  if ((el = t.closest('[data-close]'))) { el.closest('dialog').close(); return; }
  if (t.tagName === 'DIALOG') t.close();
});

/* Definisi SVG global untuk tick emas */
(() => {
  const d = document.createElement('div'); d.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
  let lobes = '';
  for (let i = 0; i < 12; i++) { const a = i * Math.PI / 6; lobes += `<circle cx="${(12 + 7.7 * Math.cos(a)).toFixed(2)}" cy="${(12 + 7.7 * Math.sin(a)).toFixed(2)}" r="3.3"/>`; }
  d.innerHTML = `<svg width="0" height="0" aria-hidden="true"><defs>
    <linearGradient id="goldGrad" gradientUnits="userSpaceOnUse" x1="3" y1="2" x2="21" y2="22"><stop offset="0" stop-color="#FFF3B0"/><stop offset=".35" stop-color="#FFD23F"/><stop offset=".7" stop-color="#E8A100"/><stop offset="1" stop-color="#B87A00"/></linearGradient>
    <clipPath id="goldClip">${lobes}<circle cx="12" cy="12" r="8.6"/></clipPath></defs></svg>`;
  document.body ? document.body.prepend(d) : document.addEventListener('DOMContentLoaded', () => document.body.prepend(d));
})();

/* CSS komponen kongsi (menu akaun, dialog, panel persediaan, toast) */
(() => {
  const st = document.createElement('style'); st.id = 'rv-core-css';
  st.textContent = `
.umenu{position:relative}
.avbtn{width:42px;height:42px;border-radius:50%;border:2px solid var(--line);background:var(--accent);color:var(--accent-ink);font-weight:800;cursor:pointer;overflow:hidden;padding:0;display:grid;place-items:center;font-size:16px}
.avbtn img{width:100%;height:100%;object-fit:cover}
.upop{position:absolute;right:0;top:52px;width:280px;background:var(--surface);border:1px solid var(--line);border-radius:18px;box-shadow:var(--shadow);padding:8px;z-index:60;max-height:70vh;overflow:auto}
.upop[hidden]{display:none}
.uhead{padding:10px 12px 12px;border-bottom:1px solid var(--line);margin-bottom:6px;display:grid;gap:2px}
.uhead span{color:var(--muted);font-size:13px;overflow-wrap:anywhere}
.upop button,.upop a{display:flex;width:100%;align-items:center;gap:10px;background:none;border:0;padding:9px 12px;border-radius:10px;text-align:left;cursor:pointer;color:inherit;text-decoration:none;font-weight:560;font:inherit}
.upop button:hover,.upop a:hover{background:var(--surface2)}
.upop .sep{border-top:1px solid var(--line);margin:6px 0}
.upop small{padding:6px 12px 2px;color:var(--muted);display:block;font-weight:700;font-size:12px}
.upop .ic{width:18px;height:18px}
.gbtn svg{width:20px;height:20px}
.setup{max-width:640px;margin:60px auto;padding:28px;border:1px solid var(--line);border-radius:24px;background:var(--surface)}
.setup h1{font-size:24px;margin-bottom:8px}
.diag{list-style:none;padding:0;margin:14px 0 0;display:grid;gap:6px;font-weight:650}
.diag .ok{color:var(--ok)}.diag .bad{color:var(--danger)}
.setup code{background:var(--surface2);padding:2px 6px;border-radius:6px;font-size:13px}
dialog{border:1px solid var(--line);border-radius:22px;background:var(--surface);color:var(--ink);padding:0;width:min(520px,calc(100vw - 24px));max-height:calc(100vh - 24px)}
dialog::backdrop{background:rgba(6,5,20,.66)}
dialog form,dialog .dlg{padding:22px;display:grid;gap:14px}
dialog header{display:flex;justify-content:space-between;align-items:center}
dialog h2{font-size:20px}
dialog .x{border:0;background:none;cursor:pointer;color:var(--muted);padding:4px}
dialog footer{display:flex;justify-content:flex-end;gap:8px}
dialog .wide{width:100%;justify-content:center}
#toast{position:fixed;left:50%;bottom:28px;transform:translateX(-50%) translateY(20px);background:var(--ink);color:var(--bg);padding:11px 20px;border-radius:14px;font-weight:650;opacity:0;pointer-events:none;transition:opacity .2s,transform .2s;z-index:200;max-width:calc(100vw - 32px)}
#toast.on{opacity:1;transform:translateX(-50%)}
svg.gold{filter:drop-shadow(0 0 3px rgba(255,200,61,.75))}
svg.gold .shine{animation:goldshine 2.6s ease-in-out infinite;transform-box:view-box}
@keyframes goldshine{0%{transform:translateX(0) skewX(-20deg)}55%,100%{transform:translateX(36px) skewX(-20deg)}}
.otitle{display:inline-flex;align-items:center;gap:6px;font-size:13px;font-weight:800;padding:3px 12px 3px 8px;border-radius:999px;color:#5B3A00;background:linear-gradient(135deg,#FFF3B0,#FFD23F 45%,#E8A100);box-shadow:0 0 14px rgba(255,200,61,.45)}
.otitle .ab{width:18px;height:18px;margin:0;filter:none}
@media (prefers-reduced-motion:reduce){#toast{transition:none}svg.gold .shine{animation:none}}`;
  document.head.appendChild(st);
})();
