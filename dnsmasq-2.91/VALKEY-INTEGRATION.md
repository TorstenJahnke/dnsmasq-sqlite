# Valkey Integration - L1 Cache für dnsmasq + SQLite

## 🎯 Overview

**Valkey** = Open-Source Fork von Redis (BSD-lizenziert)
- In-Memory Key-Value Store
- **0.05 ms Lookups** (4x schneller als SQLite!)
- Perfekt als L1 Cache vor SQLite (L2)

## 🏗️ Architecture: Tiered Caching

```
┌─────────────────────────────────────────────────────────────┐
│                  DNS Query Performance                       │
└─────────────────────────────────────────────────────────────┘

Client Query: "ads.example.com"
    │
    ├──> [L0] dnsmasq Query Cache (0.01 ms)
    │    └─> HIT → Return cached answer ✅
    │
    ├──> [L1] Valkey Cache (0.05 ms)
    │    ├─> HIT → Return + Update dnsmasq cache ✅
    │    └─> MISS ↓
    │
    ├──> [L2] SQLite (0.2-2 ms)
    │    ├─> domain_dns_allow → Forward to DNS
    │    ├─> domain_dns_block → Forward to DNS
    │    ├─> domain_exact → Return 0.0.0.0
    │    ├─> domain → Return 0.0.0.0
    │    ├─> domain_regex → Return 0.0.0.0
    │    └─> MISS ↓
    │
    └──> [L3] Upstream DNS (50-200 ms)
         └─> Normal DNS resolution

Result: Cache in Valkey + SQLite + dnsmasq
```

## 📊 Performance Comparison

### Without Valkey (Current)

```
Query: "ads.example.com"

1st request:  SQLite lookup = 0.5 ms
2nd request:  dnsmasq cache = 0.01 ms (TTL cached)
...
After TTL:    SQLite lookup = 0.5 ms (again!)
```

### With Valkey (Proposed)

```
Query: "ads.example.com"

1st request:  SQLite = 0.5 ms → Cache in Valkey
2nd request:  dnsmasq cache = 0.01 ms
After TTL:    Valkey = 0.05 ms (10x faster than SQLite!)
```

**Improvement for hot data: 10x faster!** 🚀

## 🔧 Implementation Options

### Option 1: External Valkey Cache (Recommended)

**dnsmasq ruft Valkey API direkt:**

```c
// In db.c - Add Valkey lookup before SQLite

#include <hiredis/hiredis.h>

static redisContext *valkey = NULL;

void db_init(void)
{
    // Connect to Valkey
    valkey = redisConnect("127.0.0.1", 6379);
    if (valkey == NULL || valkey->err)
    {
        my_syslog(LOG_WARNING, _("Valkey connection failed, using SQLite only"));
        valkey = NULL;
    }

    // Initialize SQLite (existing code)
    // ...
}

int db_check_termination(const char *name)
{
    // Check L1: Valkey Cache
    if (valkey)
    {
        redisReply *reply = redisCommand(valkey, "GET block:%s", name);
        if (reply && reply->type == REDIS_REPLY_STRING)
        {
            int result = (strcmp(reply->str, "1") == 0) ? 1 : 0;
            freeReplyObject(reply);
            return result;  // HIT: Return from Valkey
        }
        if (reply) freeReplyObject(reply);
    }

    // Check L2: SQLite (existing code)
    int result = db_check_termination_sqlite(name);

    // Store in Valkey for next time
    if (valkey && result >= 0)
    {
        redisCommand(valkey, "SETEX block:%s 3600 %d", name, result);
    }

    return result;
}
```

**Vorteile:**
- ✅ Direkter Zugriff, keine zusätzliche Latenz
- ✅ Volle Kontrolle über Caching-Strategie
- ✅ Automatisches Fallback zu SQLite bei Valkey-Ausfall

**Nachteile:**
- ❌ Erfordert Änderungen in dnsmasq Code
- ❌ Dependency auf hiredis library

### Option 2: Valkey als Proxy (No Code Changes)

**Valkey Proxy vor dnsmasq:**

```
Client → Valkey Proxy → dnsmasq + SQLite
            ↓
         Cache
```

**Proxy-Script:**
```python
#!/usr/bin/env python3
import socket
import valkey

# Valkey client
cache = valkey.Valkey(host='localhost', port=6379, decode_responses=True)

# DNS Proxy
server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
server.bind(('0.0.0.0', 5353))  # Listen on 5353

dnsmasq = ('127.0.0.1', 53)  # Forward to dnsmasq on 53

while True:
    data, addr = server.recvfrom(512)

    # Parse DNS query (simplified)
    domain = parse_dns_query(data)
    cache_key = f"dns:{domain}"

    # Check Valkey cache
    cached = cache.get(cache_key)
    if cached:
        # Return cached response
        server.sendto(cached.encode(), addr)
        continue

    # Cache miss: Forward to dnsmasq
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.sendto(data, dnsmasq)
    response, _ = sock.recvfrom(512)
    sock.close()

    # Cache response
    cache.setex(cache_key, 3600, response)

    # Return to client
    server.sendto(response, addr)
```

**Vorteile:**
- ✅ Keine Code-Änderungen in dnsmasq
- ✅ Einfach zu deployen
- ✅ Kann mit anderem DNS-Server kombiniert werden

**Nachteile:**
- ❌ Zusätzlicher Netzwerk-Hop (minimal, aber vorhanden)
- ❌ DNS-Parsing erforderlich
- ❌ Kein Fallback bei Proxy-Ausfall

### Option 3: Valkey + dnsmasq Cache Sync

**Valkey spiegelt dnsmasq internen Cache:**

```bash
# dnsmasq exportiert Cache-Statistiken
dnsmasq --log-queries --log-facility=/var/log/dnsmasq.log

# Script liest Log und füllt Valkey
tail -f /var/log/dnsmasq.log | while read line; do
    if [[ "$line" =~ "query\[A\] (.*) from" ]]; then
        domain="${BASH_REMATCH[1]}"
        # Check if blocked
        if [[ "$line" =~ "0.0.0.0" ]]; then
            redis-cli SETEX "block:$domain" 3600 1
        fi
    fi
done
```

**Vorteile:**
- ✅ Keine Code-Änderungen
- ✅ Nutzt bestehende dnsmasq Logs

**Nachteile:**
- ❌ Reaktiv statt proaktiv (lernt erst nach 1. Query)
- ❌ Logfile-Parsing ist ineffizient

## 🚀 Recommended Architecture

### Tier-1: Enterprise Setup (128 GB RAM)

```
┌──────────────────────────────────────────────────────────┐
│  Server: 8 Core Intel + 128 GB RAM + NVMe                │
└──────────────────────────────────────────────────────────┘

[Client Queries]
    ↓
[dnsmasq Query Cache] ←── 2M entries (~600 MB RAM)
    ↓ (miss)
[Valkey L1 Cache] ←────── 10M hot entries (~1-2 GB RAM)
    ↓ (miss)
[SQLite L2 Cache] ←────── 1B total entries (40-80 GB cache)
    ↓ (miss)
[Upstream DNS]

RAM Distribution:
- dnsmasq:  2 GB (query cache)
- Valkey:   10 GB (hot domains)
- SQLite:   80 GB (cold domains)
- BIND:     30 GB (zones, cache)
- OS:       6 GB (kernel, buffers)
Total:      128 GB
```

### Valkey Configuration

```conf
# /usr/local/etc/valkey.conf

# Memory limit (10 GB for hot cache)
maxmemory 10gb
maxmemory-policy allkeys-lru  # Evict least recently used

# Persistence (optional - for cache it's not critical)
save ""  # Disable RDB snapshots (pure cache mode)
appendonly no  # Disable AOF (pure cache mode)

# Performance
tcp-backlog 511
timeout 0
tcp-keepalive 300

# Threading (for 8 cores)
io-threads 4
io-threads-do-reads yes

# Network
bind 127.0.0.1  # Only local access
port 6379
```

### dnsmasq Configuration

```conf
# /usr/local/etc/dnsmasq/dnsmasq.conf

# SQLite (L2 Cache)
db-file=/var/db/dnsmasq/blocklist.db
db-block-ipv4=0.0.0.0
db-block-ipv6=::

# dnsmasq Query Cache (L0)
cache-size=2000000  # 2M entries
min-cache-ttl=300   # 5 minutes minimum
max-cache-ttl=3600  # 1 hour maximum

# Valkey integration would go here (requires code changes)
# valkey-host=127.0.0.1
# valkey-port=6379
# valkey-ttl=3600
```

## 📈 Performance Estimates

### Scenario: 1 Billion Domains in SQLite

**Without Valkey:**
```
Hot domains (1% = 10M):    0.5 ms (SQLite every time)
Cold domains (99% = 990M): 0.5 ms (SQLite)

Average:  0.5 ms
QPS:      2,000 queries/sec
```

**With Valkey (10M hot entries):**
```
Hot domains (1% = 10M):    0.05 ms (Valkey cache)
Cold domains (99% = 990M): 0.5 ms (SQLite)

Average:  0.05 * 0.01 + 0.5 * 0.99 = 0.5 ms (first hit)
         0.05 ms (subsequent hits on hot data)

Sustained QPS: 20,000 queries/sec (10x improvement!)
```

### Real-World Hit Rates

**Typical DNS Query Distribution:**
- **Top 1% domains** = 80% of queries (Pareto principle!)
- **Top 10% domains** = 95% of queries
- **Remaining 90%** = 5% of queries

**With 10M Valkey cache:**
```
Cache Hit Rate: ~80% (top 1% domains)
Cache Miss Rate: ~20% (go to SQLite)

Average Latency: 0.05 * 0.8 + 0.5 * 0.2 = 0.14 ms

Improvement: 3.5x faster average response!
```

## 💡 Smart Caching Strategies

### Strategy 1: LRU (Least Recently Used)

```
Valkey evicts least recently used entries
→ Hot domains stay in cache
→ Cold domains evicted
```

**Best for:** General-purpose DNS blocking

### Strategy 2: Frequency-Based

```python
# Track query frequency
cache.zincrby("freq", 1, domain)

# Only cache domains with >10 queries/hour
if cache.zscore("freq", domain) > 10:
    cache.setex(f"block:{domain}", 3600, result)
```

**Best for:** High-traffic servers

### Strategy 3: Predictive Caching

```python
# Pre-populate Valkey with top domains from SQLite
top_domains = sqlite3.execute("""
    SELECT Domain FROM domain
    ORDER BY last_query_time DESC
    LIMIT 10000000
""")

for domain in top_domains:
    cache.setex(f"block:{domain}", 86400, 1)
```

**Best for:** Known hot domains

## 🔧 Implementation Roadmap

### Phase 1: Proof of Concept (1 Woche)

1. **Install Valkey**
   ```bash
   # FreeBSD
   pkg install valkey
   service valkey start
   ```

2. **Build Python Proxy** (Option 2)
   ```bash
   pip install valkey dnspython
   ./valkey-dns-proxy.py
   ```

3. **Test Performance**
   ```bash
   # Benchmark without Valkey
   dnsperf -d queries.txt -s 127.0.0.1 -p 53

   # Benchmark with Valkey
   dnsperf -d queries.txt -s 127.0.0.1 -p 5353
   ```

4. **Measure Hit Rates**
   ```bash
   valkey-cli INFO stats | grep keyspace_hits
   valkey-cli INFO stats | grep keyspace_misses
   ```

### Phase 2: Code Integration (2-3 Wochen)

1. **Add hiredis dependency** to dnsmasq build
2. **Implement valkey_check()** in db.c
3. **Add Valkey config options** to dnsmasq.conf
4. **Test fallback behavior** (Valkey down = use SQLite)
5. **Benchmark integrated solution**

### Phase 3: Production Deployment (1 Woche)

1. **Deploy Valkey in production**
2. **Configure monitoring** (hit rate, latency)
3. **Tune cache size** based on hot data
4. **Document operational procedures**

## 📊 Cost-Benefit Analysis

### Resources

**Memory:**
- **Valkey**: 10 GB (10M domains @ ~1KB each)
- **SQLite**: 80 GB (1B domains)
- **Total**: 90 GB / 128 GB = 70% RAM usage

**CPU:**
- **Valkey**: 1-2 cores (io-threads)
- **dnsmasq**: 2-4 cores (query processing)
- **SQLite**: 2-4 cores (disk I/O)
- **Total**: ~6 cores / 8 cores = 75% CPU

### Benefits

**Performance:**
- ✅ 3-10x faster queries for hot data
- ✅ 10x higher QPS (2,000 → 20,000 q/s)
- ✅ Reduced SQLite disk I/O
- ✅ Better cache hit rates

**Scalability:**
- ✅ Handles traffic spikes
- ✅ Reduces backend load
- ✅ Can scale Valkey horizontally (cluster mode)

**Reliability:**
- ✅ Graceful degradation (Valkey down = SQLite still works)
- ✅ No SPOF (Single Point of Failure)

### Costs

**Implementation:**
- ⚠️ Code changes in dnsmasq (if Option 1)
- ⚠️ Additional dependency (hiredis)
- ⚠️ Testing & validation

**Operations:**
- ⚠️ One more service to monitor
- ⚠️ 10 GB extra RAM
- ⚠️ Valkey maintenance

**Complexity:**
- ⚠️ More moving parts
- ⚠️ Cache invalidation logic
- ⚠️ Debugging is harder

## 🎯 Recommendation

### For Your Setup (128 GB RAM, 1B domains):

**Phase 1: Start with Proxy (Option 2)**
- ✅ No code changes
- ✅ Easy to test
- ✅ Reversible
- ✅ Immediate benefits

**Phase 2: If successful → Code Integration (Option 1)**
- ✅ Maximum performance
- ✅ Direct control
- ✅ Better error handling

**Configuration:**
```
Valkey Cache: 10 GB (10M hot domains)
SQLite Cache: 80 GB (1B total domains)
Hit Rate: ~80% (Valkey)
Latency: 0.14 ms average (vs 0.5 ms without)
Improvement: 3.5x faster!
```

## 📝 TL;DR

**Valkey Integration Benefits:**

| Metric | Without Valkey | With Valkey | Improvement |
|--------|----------------|-------------|-------------|
| **Hot Queries** | 0.5 ms | 0.05 ms | **10x faster** |
| **Avg Latency** | 0.5 ms | 0.14 ms | **3.5x faster** |
| **Max QPS** | 2,000 | 20,000 | **10x higher** |
| **Hit Rate** | N/A | ~80% | **Massive!** |
| **RAM Cost** | 80 GB | 90 GB | +10 GB |

**Recommendation: DO IT!** ✅

Especially für dein Setup (128 GB RAM) ist das ein No-Brainer:
- Du hast genug RAM (10 GB extra ist nichts bei 128 GB)
- 1B Domains = viel Cold Data, perfect für Tiered Cache
- 3-10x Performance-Boost für Hot Data
- Einfach zu testen mit Proxy (keine Code-Changes)

**Next Steps:**
1. Valkey installieren
2. Proxy-Script testen
3. Performance messen
4. Bei Erfolg: Code-Integration in dnsmasq

🚀 **LET'S GO!**
