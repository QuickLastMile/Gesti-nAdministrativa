# Sincronización Firebase → BigQuery

## Requisitos previos
- Node.js 20+ instalado
- Firebase CLI instalado: `npm install -g firebase-tools`
- Google Cloud SDK instalado (opcional, para configurar permisos)
- Acceso al proyecto Firebase: `gestion-administrativa-60773`

---

## Pasos para desplegar

### 1. Autenticarse en Firebase
```bash
firebase login
firebase use gestion-administrativa-60773
```

### 2. Habilitar BigQuery en Google Cloud
En la consola de Google Cloud (console.cloud.google.com), proyecto `gestion-administrativa-60773`:
- Ir a **APIs & Services → Enable APIs**
- Buscar y habilitar **BigQuery API**

### 3. Dar permisos a la Cloud Function para escribir en BigQuery
En Google Cloud Console → **IAM & Admin → IAM**:
- Buscar la cuenta de servicio: `gestion-administrativa-60773@appspot.gserviceaccount.com`
- Agregar rol: **BigQuery Data Editor**

### 4. Instalar dependencias e instalar
```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

### 5. Sincronización inicial (primer volcado de datos)
Después de desplegar, ejecuta la sincronización manual para cargar los datos existentes:

```
GET https://us-central1-gestion-administrativa-60773.cloudfunctions.net/manualSync
```

O desde el navegador, pegar esa URL directamente.

---

## Cómo funciona

| Evento | Acción |
|--------|--------|
| Cualquier cambio en la plataforma web | Firebase actualiza `platform_state` → Cloud Function se dispara → escribe en BigQuery |
| Sincronización manual | Llamar al endpoint `manualSync` |

### Tablas que se crean en BigQuery (dataset: `quick_lastmile`)
| Tabla | Contenido |
|-------|-----------|
| `availabilities` | Malla / turnos |
| `novelties` | Novedades e inasistencias |
| `overtimeReports` | Horas extras |
| `parkingReports` | Adicionales / parqueadero |
| `quickers` | Mensajeros |
| `clients` | Clientes y puntos |
| `cases` | Procesos administrativos |
| `users` | Usuarios de la plataforma |
| `tickets` | Tickets de soporte |
| `logs` | Historial de acciones |
| `gestionRows` | Gestión HSQ / motos |
| `evidences` | Evidencias |
| `calendarEvents` | Eventos de calendario |

Cada tabla tiene una columna `_synced_at` (timestamp de la sincronización) que permite ver el historial de cambios.

---

## Consultas de ejemplo en BigQuery

```sql
-- Malla del último mes
SELECT date, quicker, client, point, plannedStart, plannedEnd, status
FROM `gestion-administrativa-60773.quick_lastmile.availabilities`
WHERE DATE(_synced_at) = (SELECT MAX(DATE(_synced_at)) FROM `gestion-administrativa-60773.quick_lastmile.availabilities`)
  AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY date DESC;

-- Horas extras aprobadas por mensajero
SELECT quicker, cedula, COUNT(*) as registros, SUM(CAST(hours AS FLOAT64)) as total_horas
FROM `gestion-administrativa-60773.quick_lastmile.overtimeReports`
WHERE status = 'Aprobado'
  AND DATE(_synced_at) = (SELECT MAX(DATE(_synced_at)) FROM `gestion-administrativa-60773.quick_lastmile.overtimeReports`)
GROUP BY quicker, cedula
ORDER BY total_horas DESC;

-- Novedades por tipo
SELECT type, COUNT(*) as cantidad
FROM `gestion-administrativa-60773.quick_lastmile.novelties`
WHERE DATE(_synced_at) = (SELECT MAX(DATE(_synced_at)) FROM `gestion-administrativa-60773.quick_lastmile.novelties`)
GROUP BY type
ORDER BY cantidad DESC;
```
