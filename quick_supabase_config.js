// ============================================================
//  Configuración de Supabase — Plataforma Quick Last Mile
//  Proyecto: lfssdwtbxadzkcccestq
//
//  La clave publicable está pensada para vivir en el navegador.
//  Por sí sola no da acceso a nada: cada tabla tiene seguridad a
//  nivel de fila (RLS) y sin sesión iniciada la base responde
//  "privilegio insuficiente". El acceso lo determina el perfil
//  del usuario que inicia sesión, no esta clave.
// ============================================================

window.QUICK_SUPABASE_CONFIG = {
  enabled: true,
  url: 'https://lfssdwtbxadzkcccestq.supabase.co',
  publishableKey: 'sb_publishable_VxnAg0AwxydxXu7xbOlzKw_PXPfo1xT',

  // Cubeta de Storage para fotos de marcación, documentos y evidencias
  bucket: 'evidencias',

  // Perfiles con acceso a la plataforma administrativa
  perfilesAdministrativos: ['Administrador', 'Gerencia', 'Jefe', 'Coordinador', 'HSQ'],

  // Perfil de la aplicación del mensajero
  perfilMensajero: 'Quicker'
};
