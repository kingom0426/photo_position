import { pool } from '../src/config/database.js';
import { schemaStatements, seedStatements } from '../src/db/schema.js';

try {
  for (const [index, sql] of schemaStatements.entries()) {
    await pool.query(sql);
    console.log(`Schema ${index + 1}/${schemaStatements.length} ready`);
  }
  for (const seed of seedStatements) {
    await pool.execute(seed.sql, seed.values);
  }
  console.log('Database migration completed');
} finally {
  await pool.end();
}
