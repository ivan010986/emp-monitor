// Idempotently ensures the application Mongo user exists with the current
// password. Runs inside the migrations job (before any app service starts),
// authenticating as root — which the mongo image entrypoint always creates —
// so it self-heals volumes that were initialized without the app user.
let MongoClient;
try {
  ({ MongoClient } = require('/app/migrations/node_modules/mongodb'));
} catch {
  MongoClient = require('/app/migrations/node_modules/mongoose').mongo.MongoClient;
}

(async () => {
  const dbName = process.env.MONGO_APP_DB || 'empmonitor';
  const user = process.env.MONGO_APP_USER;
  const pwd = process.env.MONGO_APP_PASSWORD;
  const roles = [{ role: 'readWrite', db: dbName }];

  const client = new MongoClient(process.env.MONGO_ROOT_URI);
  await client.connect();
  const db = client.db(dbName);
  try {
    await db.command({ createUser: user, pwd, roles });
    console.log('[mongo-user] created', user, 'on', dbName);
  } catch (e) {
    if (e.code === 51003 || /already exists/i.test(e.message)) {
      await db.command({ updateUser: user, pwd, roles });
      console.log('[mongo-user] updated', user, 'on', dbName);
    } else {
      throw e;
    }
  }
  await client.close();
})().catch((e) => {
  console.error('[mongo-user] FAILED:', e.message);
  process.exit(1);
});
