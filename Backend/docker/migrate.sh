#!/bin/sh
# Guarded migration runner for EmpMonitor.
#
# 1) Runs Backend/migrations (emp-monitor.sql dump + mongo seed) ONLY when the
#    MySQL schema looks empty (or FRESH_DB=true is forced). The dump is NOT
#    idempotent: it drops/re-adds primary keys, so it must not run on every boot.
# 2) Always runs store-logs-api migrations (migrate-mongo + sequelize), which
#    are idempotent.
set -e

echo "[migrate] waiting for mysql..."
until node -e "const m=require('/app/migrations/node_modules/mysql2');const c=m.createConnection({host:process.env.MYSQL_HOST,user:process.env.MYSQL_USERNAME,password:process.env.MYSQL_PASSWORD,port:3306});c.query('SELECT 1',e=>{process.exit(e?1:0)});" 2>/dev/null; do
  sleep 3
done
echo "[migrate] mysql is up"

TABLES=$(node -e "const m=require('/app/migrations/node_modules/mysql2');const c=m.createConnection({host:process.env.MYSQL_HOST,user:process.env.MYSQL_USERNAME,password:process.env.MYSQL_PASSWORD});c.query(\"SELECT COUNT(*) AS c FROM information_schema.tables WHERE table_schema='\"+process.env.MYSQL_DATABASE_NAME+\"'\",(e,r)=>{if(e){console.log(0);c.end();return}console.log(r[0].c);c.end()});" | tail -1)
echo "[migrate] tables in ${MYSQL_DATABASE_NAME}: ${TABLES}"

if [ "${TABLES:-0}" -lt 10 ] || [ "${FRESH_DB}" = "true" ]; then
  echo "[migrate] empty schema or FRESH_DB=true -> running full SQL dump"
  cd /app/migrations && node index.js
else
  echo "[migrate] existing schema -> skipping destructive dump"
fi

echo "[migrate] running store-logs-api mongo migrations..."
cd /app/store-logs-api && npm run migrate-mongo:up || echo "[migrate] migrate-mongo failed (non-fatal)"

echo "[migrate] running store-logs-api mysql migrations..."
cd /app/store-logs-api && npm run migrate-mysql:up || echo "[migrate] sequelize failed (non-fatal)"

echo "[migrate] DONE"
