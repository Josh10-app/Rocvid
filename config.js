/* =====================================================================
   config.js : tetapan Rocvid
   Isi dua nilai Supabase di bawah (Supabase Dashboard > Project Settings > API).
   Gunakan kunci "anon public" sahaja. JANGAN letak kunci "service_role" di sini.
   ===================================================================== */
window.ROCVID_CONFIG = {
  supabaseUrl: 'https://ajepmujsnfzzsgkqmrpy.supabase.co',
  supabaseAnonKey: 'sb_publishable_4_Dnudnp2Cvkpfz2mLt4nQ_oVUQ6NNL',

  // Had saiz muat naik (MB). Pelan percuma Supabase menghadkan 50 MB setiap fail.
  // Naikkan nilai ini hanya jika anda sudah menaikkan had storan dalam Supabase.
  maxUploadMB: 50,

  // Nama fail halaman (ubah jika anda menukar nama atau laluan)
  siteUrl: 'index.html',
  studioUrl: 'rocvid_music.html'
};
