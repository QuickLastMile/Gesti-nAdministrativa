const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { BigQuery } = require('@google-cloud/bigquery');

admin.initializeApp();

const PROJECT_ID = 'gestion-administrativa-60773';
const BQ_DATASET  = 'quick_lastmile';
const bigquery    = new BigQuery({ projectId: PROJECT_ID });

// Colecciones del estado que se replican a BigQuery.
// Cada entrada define el nombre en Firestore y las columnas clave para el schema.
const COLLECTIONS = [
  'availabilities',
  'novelties',
  'overtimeReports',
  'parkingReports',
  'quickers',
  'clients',
  'cases',
  'users',
  'tickets',
  'logs',
  'gestionRows',
  'evidences',
  'calendarEvents',
];

// Aplana un objeto anidado en un nivel (arrays se convierten a JSON string).
function flattenRow(obj, prefix = '') {
  const result = {};
  for (const [k, v] of Object.entries(obj || {})) {
    const key = (prefix ? `${prefix}_` : '') + k.replace(/[^a-zA-Z0-9_]/g, '_');
    if (v === null || v === undefined) {
      result[key] = null;
    } else if (Array.isArray(v)) {
      result[key] = JSON.stringify(v);
    } else if (typeof v === 'object' && !(v instanceof Date)) {
      // Un nivel de anidación — aplana
      Object.assign(result, flattenRow(v, key));
    } else {
      result[key] = v;
    }
  }
  return result;
}

// Asegura que la tabla exista en BigQuery. Si no existe la crea con autodetect.
async function ensureTable(dataset, tableName, rows) {
  const table = dataset.table(tableName);
  const [exists] = await table.exists();
  if (!exists) {
    await dataset.createTable(tableName, {
      schema: { fields: [] }, // BigQuery usará autodetect al insertar
      timePartitioning: { type: 'DAY', field: '_synced_at' },
    });
    functions.logger.info(`Tabla creada: ${tableName}`);
  }
  return table;
}

// Sincroniza una colección del estado a una tabla de BigQuery.
// Estrategia: MERGE por id — inserta o actualiza según _synced_at.
async function syncCollection(dataset, name, items, syncedAt) {
  if (!Array.isArray(items) || items.length === 0) return;

  const rows = items.map(item => ({
    ...flattenRow(item),
    _synced_at: syncedAt,
    _collection: name,
  }));

  const table = await ensureTable(dataset, name, rows);

  // Inserta con insertAll (streaming insert, disponible en todos los planes).
  // skipInvalidRows e ignoreUnknownValues evitan que un campo raro tire error.
  await table.insert(rows, {
    skipInvalidRows: true,
    ignoreUnknownValues: true,
  });

  functions.logger.info(`✔ ${name}: ${rows.length} filas sincronizadas`);
}

/**
 * Cloud Function: se dispara cada vez que el documento platform_state
 * cambia en Firestore (escritura, actualización o borrado).
 *
 * Documento: quick_lastmile/platform_state
 */
exports.syncToBigQuery = functions
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .firestore
  .document('quick_lastmile/platform_state')
  .onWrite(async (change, context) => {
    if (!change.after.exists) {
      functions.logger.warn('Documento eliminado — nada que sincronizar');
      return;
    }

    const data = change.after.data() || {};
    const syncedAt = new Date().toISOString();

    // Asegurar que el dataset existe
    const dataset = bigquery.dataset(BQ_DATASET);
    const [dsExists] = await dataset.exists();
    if (!dsExists) {
      await bigquery.createDataset(BQ_DATASET, { location: 'US' });
      functions.logger.info(`Dataset creado: ${BQ_DATASET}`);
    }

    // Sincronizar cada colección en paralelo
    await Promise.all(
      COLLECTIONS.map(col => syncCollection(dataset, col, data[col], syncedAt))
    );

    functions.logger.info(`Sincronización completa — ${syncedAt}`);
  });

/**
 * Cloud Function HTTP: permite disparar una sincronización manual
 * desde el navegador o Postman sin esperar un cambio en Firestore.
 *
 * GET/POST https://<region>-gestion-administrativa-60773.cloudfunctions.net/manualSync
 * (protege esta URL con un secreto si la expones públicamente)
 */
exports.manualSync = functions
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .https.onRequest(async (req, res) => {
    const secret = functions.config().sync?.secret || '';
    if (secret && req.query.secret !== secret) {
      res.status(403).send('Forbidden');
      return;
    }

    try {
      const doc = await admin
        .firestore()
        .collection('quick_lastmile')
        .doc('platform_state')
        .get();

      if (!doc.exists) {
        res.status(404).send('platform_state no encontrado en Firestore');
        return;
      }

      const data = doc.data() || {};
      const syncedAt = new Date().toISOString();

      const dataset = bigquery.dataset(BQ_DATASET);
      const [dsExists] = await dataset.exists();
      if (!dsExists) {
        await bigquery.createDataset(BQ_DATASET, { location: 'US' });
      }

      const results = await Promise.allSettled(
        COLLECTIONS.map(async col => {
          const items = data[col] || [];
          await syncCollection(dataset, col, items, syncedAt);
          return { col, count: items.length };
        })
      );

      const summary = results.map(r =>
        r.status === 'fulfilled'
          ? `${r.value.col}: ${r.value.count} filas`
          : `ERROR: ${r.reason}`
      );

      res.status(200).json({ ok: true, syncedAt, summary });
    } catch (err) {
      functions.logger.error('Error en manualSync:', err);
      res.status(500).json({ ok: false, error: err.message });
    }
  });
