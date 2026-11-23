#!/bin/bash
# Elasticsearch start script for the Tube Archivist Railway template.
set -e
ES_HOME=/usr/share/elasticsearch
DATA_DIR=/usr/share/elasticsearch/data
export PORT="${PORT:-9200}"
log() { echo "railway-template: $*"; }

if [ -z "$ELASTIC_PASSWORD" ]; then
  log "ELASTIC_PASSWORD is empty; refusing to start without a password" >&2
  exit 1
fi

# Heap: ES_JAVA_OPTS wins if set. Otherwise size it from the container's memory
# limit: 40% of it, at least 128 MB and at most 1 GB (Tube Archivist's indexes are
# small; the rest of the memory is left to the OS file cache).
if [ -z "$ES_JAVA_OPTS" ]; then
  LIMIT=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
  if [ "$LIMIT" = "max" ] || [ -z "$LIMIT" ]; then LIMIT=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) * 1024 )); fi
  HEAP_MB=$(( LIMIT / 1024 / 1024 * 40 / 100 ))
  [ "$HEAP_MB" -lt 128 ] && HEAP_MB=128
  [ "$HEAP_MB" -gt 1024 ] && HEAP_MB=1024
  export ES_JAVA_OPTS="-Xms${HEAP_MB}m -Xmx${HEAP_MB}m -XX:ActiveProcessorCount=${ES_CPUS:-2}"
fi

mkdir -p "$DATA_DIR/snapshot"
rm -rf "$DATA_DIR/lost+found"
if [ "$(id -u)" = "0" ] && [ "$(stat -c %u "$DATA_DIR")" != "1000" ]; then
  log "giving $DATA_DIR to uid 1000"
  chown -R 1000:0 "$DATA_DIR"
fi
chown 1000:0 "$DATA_DIR/snapshot" 2>/dev/null || true

# Railway hosts differ in vm.max_map_count and a container can't raise it.
MMAP=true
MAPS=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)
if [ "$MAPS" -lt 262144 ]; then MMAP=false; fi
log "Elasticsearch on port $PORT, heap '$ES_JAVA_OPTS', vm.max_map_count=$MAPS allow_mmap=$MMAP"

cat > "$ES_HOME/config/elasticsearch.yml" <<YML
cluster.name: tubearchivist
node.name: archivist-es
path.data: "$DATA_DIR"
path.repo: "$DATA_DIR/snapshot"
discovery.type: single-node
http.host: "::"
http.port: $PORT
transport.host: 127.0.0.1
node.store.allow_mmap: $MMAP
node.processors: ${ES_CPUS:-2}
xpack.ml.enabled: false
xpack.security.enabled: true
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
# Disk watermarks as absolute free space, so a small volume doesn't go read-only at 85-95% use.
cluster.routing.allocation.disk.watermark.low: 500mb
cluster.routing.allocation.disk.watermark.high: 300mb
cluster.routing.allocation.disk.watermark.flood_stage: 200mb
# Anonymous requests may read the cluster health (Railway's health check) and nothing else.
xpack.security.authc.anonymous.username: railway_healthcheck
xpack.security.authc.anonymous.roles: railway_healthcheck
xpack.security.authc.anonymous.authz_exception: false
YML
cat > "$ES_HOME/config/roles.yml" <<YML
railway_healthcheck:
  cluster: [ "cluster:monitor/health" ]
YML
chown 1000:0 "$ES_HOME/config/elasticsearch.yml" "$ES_HOME/config/roles.yml" 2>/dev/null || true

cd "$ES_HOME"
if [ "$(id -u)" = "0" ]; then
  # --skip-chdir keeps the working directory: the entrypoint needs it to add
  # ELASTIC_PASSWORD to the keystore on the first start.
  exec chroot --skip-chdir --userspec=1000:0 / env HOME="$ES_HOME" /usr/local/bin/docker-entrypoint.sh eswrapper
fi
exec /usr/local/bin/docker-entrypoint.sh eswrapper
