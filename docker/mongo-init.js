// Creates the application user inside the `empmonitor` database so that
// mongodb://empmonitor:***@mongo:27017/empmonitor authenticates directly
// against this DB (no authSource query param needed — migrate-mongo's config
// builds the URI from parts and cannot carry query strings).
db = db.getSiblingDB('empmonitor');
db.createUser({
  user: 'empmonitor',
  pwd: process.env.MONGO_APP_PASSWORD || 'empmonitor',
  roles: [{ role: 'readWrite', db: 'empmonitor' }],
});
print('[mongo-init] created user empmonitor on db empmonitor');
