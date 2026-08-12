import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, 'Content-Type': 'application/json' },
})

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (request.method !== 'POST') return json({ ok: false, message: 'Método no permitido' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const authorization = request.headers.get('Authorization') || ''
  if (!authorization.startsWith('Bearer ')) return json({ ok: false, message: 'Sesión requerida' }, 401)

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const token = authorization.slice(7)
  const { data: caller, error: authError } = await admin.auth.getUser(token)
  if (authError || !caller.user) return json({ ok: false, message: 'Sesión inválida o vencida' }, 401)

  const { data: callerProfile } = await admin.from('perfiles').select('perfil,activo').eq('id', caller.user.id).maybeSingle()
  const allowed = ['Administrador', 'Gerencia', 'Jefe', 'Coordinador']
  if (!callerProfile?.activo || !allowed.includes(callerProfile.perfil)) {
    return json({ ok: false, message: 'No tienes permiso para crear usuarios mensajeros' }, 403)
  }

  try {
    const body = await request.json()
    const email = String(body.email || '').trim().toLowerCase()
    const password = String(body.password || '')
    const name = String(body.nombre || '').trim()
    const cedula = String(body.cedula || '').trim()
    if (!email || !name || !cedula) return json({ ok: false, message: 'Nombre, cédula y correo son obligatorios' }, 400)
    if (!body.quicker_id && password.length < 8) return json({ ok: false, message: 'La contraseña debe tener al menos 8 caracteres' }, 400)

    let authId: string | null = null
    let existingQuicker: Record<string, unknown> | null = null
    if (body.quicker_id) {
      const { data } = await admin.from('quickers').select('id,usuario_id').eq('id', body.quicker_id).maybeSingle()
      existingQuicker = data
      authId = (data?.usuario_id as string) || null
    }

    let createdAuth = false
    if (!authId) {
      const { data, error } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { nombre: name, perfil: 'Quicker' },
      })
      if (error) throw error
      authId = data.user.id
      createdAuth = true
    } else {
      const changes: Record<string, unknown> = { email, user_metadata: { nombre: name, perfil: 'Quicker' } }
      if (password) changes.password = password
      const { error } = await admin.auth.admin.updateUserById(authId, changes)
      if (error) throw error
    }

    const profile = {
      id: authId, nombre: name, usuario: email, telefono: body.telefono || null,
      cedula, perfil: 'Quicker', cliente: body.cliente || null,
      clientes: body.cliente ? [body.cliente] : [], activo: true,
    }
    const { error: profileError } = await admin.from('perfiles').upsert(profile, { onConflict: 'id' })
    if (profileError) {
      if (createdAuth) await admin.auth.admin.deleteUser(authId)
      throw profileError
    }

    const quicker = {
      usuario_id: authId, codigo: `Q-${cedula.replace(/\D/g, '').slice(-6).padStart(6, '0')}`, cedula, nombre: name,
      telefono: body.telefono || null, email, ciudad: body.ciudad || null,
      cliente: body.cliente || null, punto: body.punto || null, puntos: body.puntos || [],
      placa: body.placa || null, cargo: body.cargo || 'Quicker mensajero',
      fecha_ingreso: body.fecha_ingreso || null, estado: 'Activo',
      pagos_habilitados: Boolean(body.pagos_habilitados), tipos_pago: body.tipos_pago || [],
    }
    const query = existingQuicker
      ? admin.from('quickers').update(quicker).eq('id', body.quicker_id).select('id,usuario_id').single()
      : admin.from('quickers').insert(quicker).select('id,usuario_id').single()
    const { data: saved, error: quickerError } = await query
    if (quickerError) {
      if (createdAuth) {
        await admin.from('perfiles').delete().eq('id', authId)
        await admin.auth.admin.deleteUser(authId)
      }
      throw quickerError
    }

    return json({ ok: true, quicker_id: saved.id, usuario_id: authId, email })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Error inesperado'
    const friendly = /already.*registered|already been registered/i.test(message)
      ? 'Ya existe una cuenta con ese correo. Edita el mensajero existente o usa otro correo.'
      : message
    return json({ ok: false, message: friendly }, 400)
  }
})
