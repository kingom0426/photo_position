import { pool } from '../src/config/database.js';

try {
  const [rows] = await pool.query(
    'SELECT DATABASE() AS databaseName, VERSION() AS serverVersion, UTC_TIMESTAMP() AS serverTime'
  );
  console.log(JSON.stringify(rows[0], null, 2));
} finally {
  await pool.end();
}
