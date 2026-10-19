/* =====================================================================
   config.js : tetapan Rocvid
   Isi dua nilai Supabase di bawah (Supabase Dashboard > Project Settings > API).
   Gunakan kunci "anon public" sahaja. JANGAN letak kunci "service_role" di sini.
   ===================================================================== */
window.ROCVID_CONFIG = {
  supabaseUrl: 'https://ajepmujsnfzzsgkqmrpy.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFqZXBtdWpzbmZ6enNna3FtcnB5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIzOTQyMDIsImV4cCI6MjEwNzk3MDIwMn0.MJtIVuuLFTv3JGysgxs9Yg6lu9-vEZVgF0dNcttYewI',

  // Had saiz muat naik (MB). Pelan percuma Supabase menghadkan 50 MB setiap fail.
  // Naikkan nilai ini hanya jika anda sudah menaikkan had storan dalam Supabase.
  maxUploadMB: 50,

  // Nama fail halaman (ubah jika anda menukar nama atau laluan)
  siteUrl: 'index.html',
  studioUrl: 'rocvid_music.html'
};
