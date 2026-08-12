# Despliegue de Supabase

La función `create-messenger` crea de forma segura la cuenta de Auth y enlaza
`perfiles` con `quickers`. La clave `service_role` nunca se expone en el navegador.

```bash
supabase login
supabase link --project-ref lfssdwtbxadzkcccestq
supabase functions deploy create-messenger
```

Supabase proporciona automáticamente `SUPABASE_URL` y
`SUPABASE_SERVICE_ROLE_KEY` dentro de la Edge Function.
