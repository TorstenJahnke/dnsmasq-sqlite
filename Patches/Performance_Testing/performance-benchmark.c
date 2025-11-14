/*
 * Performance Benchmark Tool for dnsmasq-sqlite
 *
 * Tests database performance with massive datasets (2+ billion entries)
 * Measures: query times, cache efficiency, memory usage, throughput
 *
 * Compile: gcc -O3 -o performance-benchmark performance-benchmark.c -lsqlite3 -lpthread -lm
 * Usage: ./performance-benchmark <db_file> <test_mode> [iterations]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sqlite3.h>
#include <pthread.h>
#include <math.h>
#include <unistd.h>

#define MAX_DOMAIN_LEN 256
#define DEFAULT_ITERATIONS 100000
#define WARMUP_QUERIES 1000

/* Test modes */
typedef enum {
    TEST_EXACT_MATCH,
    TEST_WILDCARD_MATCH,
    TEST_REGEX_MATCH,
    TEST_MIXED_WORKLOAD,
    TEST_CACHE_EFFICIENCY,
    TEST_CONCURRENT_ACCESS,
    TEST_COLD_START,
    TEST_ALL
} test_mode_t;

/* Statistics structure */
typedef struct {
    long long total_queries;
    double total_time_ms;
    double min_time_ms;
    double max_time_ms;
    double avg_time_ms;
    double median_time_ms;
    double p95_time_ms;
    double p99_time_ms;
    long long cache_hits;
    long long cache_misses;
    long long errors;
} stats_t;

/* Thread data for concurrent tests */
typedef struct {
    sqlite3 *db;
    int thread_id;
    int iterations;
    stats_t stats;
} thread_data_t;

/* Global variables */
static sqlite3 *g_db = NULL;
static double *g_query_times = NULL;
static int g_query_count = 0;

/* Utility functions */
static double get_time_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)(tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0);
}

static long long get_memory_usage_kb(void) {
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    return usage.ru_maxrss;
}

static int compare_double(const void *a, const void *b) {
    double diff = *(double*)a - *(double*)b;
    return (diff > 0) ? 1 : ((diff < 0) ? -1 : 0);
}

static void calculate_percentiles(double *times, int count, stats_t *stats) {
    if (count == 0) return;

    qsort(times, count, sizeof(double), compare_double);

    stats->min_time_ms = times[0];
    stats->max_time_ms = times[count - 1];
    stats->median_time_ms = times[count / 2];
    stats->p95_time_ms = times[(int)(count * 0.95)];
    stats->p99_time_ms = times[(int)(count * 0.99)];

    double sum = 0;
    for (int i = 0; i < count; i++) {
        sum += times[i];
    }
    stats->avg_time_ms = sum / count;
}

/* Database query functions */
static int query_exact_match(sqlite3 *db, const char *domain, double *query_time) {
    sqlite3_stmt *stmt;
    const char *sql = "SELECT IPv4, IPv6 FROM block_exact WHERE Domain = ? LIMIT 1";
    int rc;
    double start, end;

    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "SQL prepare error: %s\n", sqlite3_errmsg(db));
        return -1;
    }

    sqlite3_bind_text(stmt, 1, domain, -1, SQLITE_STATIC);

    start = get_time_ms();
    rc = sqlite3_step(stmt);
    end = get_time_ms();

    *query_time = end - start;

    sqlite3_finalize(stmt);
    return (rc == SQLITE_ROW) ? 1 : 0;
}

static int query_wildcard_match(sqlite3 *db, const char *domain, double *query_time) {
    sqlite3_stmt *stmt;
    const char *sql = "SELECT IPv4, IPv6 FROM block_wildcard WHERE Domain = ? OR ? LIKE '%.' || Domain LIMIT 1";
    int rc;
    double start, end;

    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "SQL prepare error: %s\n", sqlite3_errmsg(db));
        return -1;
    }

    sqlite3_bind_text(stmt, 1, domain, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, domain, -1, SQLITE_STATIC);

    start = get_time_ms();
    rc = sqlite3_step(stmt);
    end = get_time_ms();

    *query_time = end - start;

    sqlite3_finalize(stmt);
    return (rc == SQLITE_ROW) ? 1 : 0;
}

static void generate_random_domain(char *domain, int vary) {
    const char *tlds[] = {".com", ".net", ".org", ".de", ".uk", ".io"};
    int tld_count = sizeof(tlds) / sizeof(tlds[0]);

    if (vary) {
        /* Generate varied domains for cache testing */
        int prefix = rand() % 1000000;
        snprintf(domain, MAX_DOMAIN_LEN, "test%d%s", prefix, tlds[rand() % tld_count]);
    } else {
        /* Generate predictable domains for consistent testing */
        int prefix = rand() % 100;  /* Limited set for cache hits */
        snprintf(domain, MAX_DOMAIN_LEN, "popular%d.example.com", prefix);
    }
}

/* Test functions */
static void test_exact_match(sqlite3 *db, int iterations, stats_t *stats) {
    double *times = malloc(iterations * sizeof(double));
    char domain[MAX_DOMAIN_LEN];
    double query_time;
    int result;
    double start_total, end_total;

    printf("Testing exact match queries...\n");

    /* Warmup */
    for (int i = 0; i < WARMUP_QUERIES; i++) {
        generate_random_domain(domain, 1);
        query_exact_match(db, domain, &query_time);
    }

    start_total = get_time_ms();

    for (int i = 0; i < iterations; i++) {
        generate_random_domain(domain, 1);
        result = query_exact_match(db, domain, &query_time);
        times[i] = query_time;

        if (result < 0) {
            stats->errors++;
        }

        if (i % 10000 == 0 && i > 0) {
            printf("  Progress: %d/%d queries (%.1f%%)\r", i, iterations, (double)i/iterations*100);
            fflush(stdout);
        }
    }

    end_total = get_time_ms();
    printf("\n");

    stats->total_queries = iterations;
    stats->total_time_ms = end_total - start_total;
    calculate_percentiles(times, iterations, stats);

    free(times);
}

static void test_wildcard_match(sqlite3 *db, int iterations, stats_t *stats) {
    double *times = malloc(iterations * sizeof(double));
    char domain[MAX_DOMAIN_LEN];
    double query_time;
    int result;
    double start_total, end_total;

    printf("Testing wildcard match queries...\n");

    /* Warmup */
    for (int i = 0; i < WARMUP_QUERIES; i++) {
        generate_random_domain(domain, 1);
        query_wildcard_match(db, domain, &query_time);
    }

    start_total = get_time_ms();

    for (int i = 0; i < iterations; i++) {
        generate_random_domain(domain, 1);
        result = query_wildcard_match(db, domain, &query_time);
        times[i] = query_time;

        if (result < 0) {
            stats->errors++;
        }

        if (i % 10000 == 0 && i > 0) {
            printf("  Progress: %d/%d queries (%.1f%%)\r", i, iterations, (double)i/iterations*100);
            fflush(stdout);
        }
    }

    end_total = get_time_ms();
    printf("\n");

    stats->total_queries = iterations;
    stats->total_time_ms = end_total - start_total;
    calculate_percentiles(times, iterations, stats);

    free(times);
}

static void test_mixed_workload(sqlite3 *db, int iterations, stats_t *stats) {
    double *times = malloc(iterations * sizeof(double));
    char domain[MAX_DOMAIN_LEN];
    double query_time;
    int result;
    double start_total, end_total;

    printf("Testing mixed workload (60%% exact, 40%% wildcard)...\n");

    start_total = get_time_ms();

    for (int i = 0; i < iterations; i++) {
        generate_random_domain(domain, 1);

        /* 60% exact, 40% wildcard */
        if (rand() % 100 < 60) {
            result = query_exact_match(db, domain, &query_time);
        } else {
            result = query_wildcard_match(db, domain, &query_time);
        }

        times[i] = query_time;

        if (result < 0) {
            stats->errors++;
        }

        if (i % 10000 == 0 && i > 0) {
            printf("  Progress: %d/%d queries (%.1f%%)\r", i, iterations, (double)i/iterations*100);
            fflush(stdout);
        }
    }

    end_total = get_time_ms();
    printf("\n");

    stats->total_queries = iterations;
    stats->total_time_ms = end_total - start_total;
    calculate_percentiles(times, iterations, stats);

    free(times);
}

static void test_cache_efficiency(sqlite3 *db, int iterations, stats_t *stats) {
    double *times = malloc(iterations * sizeof(double));
    char domain[MAX_DOMAIN_LEN];
    double query_time;
    int result;
    double start_total, end_total;

    printf("Testing cache efficiency (90%% popular domains, 10%% random)...\n");

    start_total = get_time_ms();

    for (int i = 0; i < iterations; i++) {
        /* 90% queries to popular domains (cache hits), 10% to random (cache misses) */
        if (rand() % 100 < 90) {
            generate_random_domain(domain, 0);  /* Popular domains */
        } else {
            generate_random_domain(domain, 1);  /* Random domains */
        }

        result = query_exact_match(db, domain, &query_time);
        times[i] = query_time;

        if (result < 0) {
            stats->errors++;
        }

        if (i % 10000 == 0 && i > 0) {
            printf("  Progress: %d/%d queries (%.1f%%)\r", i, iterations, (double)i/iterations*100);
            fflush(stdout);
        }
    }

    end_total = get_time_ms();
    printf("\n");

    stats->total_queries = iterations;
    stats->total_time_ms = end_total - start_total;
    calculate_percentiles(times, iterations, stats);

    free(times);
}

static void* thread_query_worker(void *arg) {
    thread_data_t *data = (thread_data_t*)arg;
    char domain[MAX_DOMAIN_LEN];
    double query_time;
    int result;

    for (int i = 0; i < data->iterations; i++) {
        generate_random_domain(domain, 1);
        result = query_exact_match(data->db, domain, &query_time);

        if (result >= 0) {
            data->stats.total_queries++;
            data->stats.total_time_ms += query_time;
        } else {
            data->stats.errors++;
        }
    }

    return NULL;
}

static void test_concurrent_access(sqlite3 *db, int iterations, stats_t *stats) {
    int num_threads = 10;
    pthread_t threads[num_threads];
    thread_data_t thread_data[num_threads];
    double start_total, end_total;

    printf("Testing concurrent access with %d threads...\n", num_threads);

    /* Initialize thread data */
    for (int i = 0; i < num_threads; i++) {
        thread_data[i].db = db;
        thread_data[i].thread_id = i;
        thread_data[i].iterations = iterations / num_threads;
        memset(&thread_data[i].stats, 0, sizeof(stats_t));
    }

    start_total = get_time_ms();

    /* Start threads */
    for (int i = 0; i < num_threads; i++) {
        pthread_create(&threads[i], NULL, thread_query_worker, &thread_data[i]);
    }

    /* Wait for threads */
    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }

    end_total = get_time_ms();

    /* Aggregate statistics */
    stats->total_queries = 0;
    stats->total_time_ms = end_total - start_total;
    stats->errors = 0;
    double avg_sum = 0;

    for (int i = 0; i < num_threads; i++) {
        stats->total_queries += thread_data[i].stats.total_queries;
        stats->errors += thread_data[i].stats.errors;
        avg_sum += thread_data[i].stats.total_time_ms;
    }

    stats->avg_time_ms = avg_sum / stats->total_queries;

    printf("  Completed %lld queries in %.2f ms\n", stats->total_queries, stats->total_time_ms);
}

static void print_stats(const char *test_name, stats_t *stats) {
    printf("\n=== %s Results ===\n", test_name);
    printf("Total Queries:    %lld\n", stats->total_queries);
    printf("Total Time:       %.2f ms\n", stats->total_time_ms);
    printf("Throughput:       %.0f queries/sec\n",
           (stats->total_queries / stats->total_time_ms) * 1000.0);
    printf("\nQuery Latency:\n");
    printf("  Average:        %.3f ms\n", stats->avg_time_ms);
    printf("  Median:         %.3f ms\n", stats->median_time_ms);
    printf("  Min:            %.3f ms\n", stats->min_time_ms);
    printf("  Max:            %.3f ms\n", stats->max_time_ms);
    printf("  95th percentile: %.3f ms\n", stats->p95_time_ms);
    printf("  99th percentile: %.3f ms\n", stats->p99_time_ms);

    if (stats->errors > 0) {
        printf("\nErrors:           %lld\n", stats->errors);
    }

    printf("Memory Usage:     %lld KB\n", get_memory_usage_kb());
    printf("=====================================\n\n");
}

static void get_database_stats(sqlite3 *db) {
    sqlite3_stmt *stmt;
    long long count;

    printf("\n=== Database Statistics ===\n");

    /* Get row counts for each table */
    const char *tables[] = {"block_exact", "block_wildcard", "block_regex",
                           "fqdn_dns_allow", "fqdn_dns_block"};

    for (int i = 0; i < 5; i++) {
        char sql[256];
        snprintf(sql, sizeof(sql), "SELECT COUNT(*) FROM %s", tables[i]);

        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                count = sqlite3_column_int64(stmt, 0);
                printf("  %-20s: %lld entries\n", tables[i], count);
            }
            sqlite3_finalize(stmt);
        }
    }

    /* Get database file size */
    const char *filename = sqlite3_db_filename(db, "main");
    FILE *fp = fopen(filename, "rb");
    if (fp) {
        fseek(fp, 0, SEEK_END);
        long long size = ftell(fp);
        fclose(fp);
        printf("  Database size:       %.2f GB\n", size / (1024.0 * 1024.0 * 1024.0));
    }

    /* Get SQLite cache stats */
    if (sqlite3_prepare_v2(db, "PRAGMA cache_size", -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            long long cache_size = sqlite3_column_int64(stmt, 0);
            printf("  Cache size:          %lld pages (%.2f MB)\n",
                   cache_size, (cache_size * 4096.0) / (1024.0 * 1024.0));
        }
        sqlite3_finalize(stmt);
    }

    printf("===========================\n\n");
}

static void print_usage(const char *prog) {
    printf("Usage: %s <db_file> <test_mode> [iterations]\n\n", prog);
    printf("Test modes:\n");
    printf("  exact       - Test exact match queries\n");
    printf("  wildcard    - Test wildcard match queries\n");
    printf("  mixed       - Test mixed workload (60%% exact, 40%% wildcard)\n");
    printf("  cache       - Test cache efficiency\n");
    printf("  concurrent  - Test concurrent access (10 threads)\n");
    printf("  all         - Run all tests\n\n");
    printf("Default iterations: %d\n", DEFAULT_ITERATIONS);
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        print_usage(argv[0]);
        return 1;
    }

    const char *db_file = argv[1];
    const char *test_mode_str = argv[2];
    int iterations = (argc > 3) ? atoi(argv[3]) : DEFAULT_ITERATIONS;

    /* Open database */
    int rc = sqlite3_open(db_file, &g_db);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Cannot open database: %s\n", sqlite3_errmsg(g_db));
        return 1;
    }

    /* Set optimizations */
    sqlite3_exec(g_db, "PRAGMA cache_size = -100000", NULL, NULL, NULL);  /* 400 MB */
    sqlite3_exec(g_db, "PRAGMA mmap_size = 268435456", NULL, NULL, NULL);  /* 256 MB */
    sqlite3_exec(g_db, "PRAGMA journal_mode = WAL", NULL, NULL, NULL);

    printf("Performance Benchmark for dnsmasq-sqlite\n");
    printf("========================================\n");
    printf("Database: %s\n", db_file);
    printf("Iterations: %d\n", iterations);

    get_database_stats(g_db);

    srand(time(NULL));

    stats_t stats;
    memset(&stats, 0, sizeof(stats_t));

    /* Run requested test */
    if (strcmp(test_mode_str, "exact") == 0) {
        test_exact_match(g_db, iterations, &stats);
        print_stats("Exact Match", &stats);
    }
    else if (strcmp(test_mode_str, "wildcard") == 0) {
        test_wildcard_match(g_db, iterations, &stats);
        print_stats("Wildcard Match", &stats);
    }
    else if (strcmp(test_mode_str, "mixed") == 0) {
        test_mixed_workload(g_db, iterations, &stats);
        print_stats("Mixed Workload", &stats);
    }
    else if (strcmp(test_mode_str, "cache") == 0) {
        test_cache_efficiency(g_db, iterations, &stats);
        print_stats("Cache Efficiency", &stats);
    }
    else if (strcmp(test_mode_str, "concurrent") == 0) {
        test_concurrent_access(g_db, iterations, &stats);
        print_stats("Concurrent Access", &stats);
    }
    else if (strcmp(test_mode_str, "all") == 0) {
        printf("\n*** Running ALL tests ***\n\n");

        test_exact_match(g_db, iterations, &stats);
        print_stats("Exact Match", &stats);

        memset(&stats, 0, sizeof(stats_t));
        test_wildcard_match(g_db, iterations, &stats);
        print_stats("Wildcard Match", &stats);

        memset(&stats, 0, sizeof(stats_t));
        test_mixed_workload(g_db, iterations, &stats);
        print_stats("Mixed Workload", &stats);

        memset(&stats, 0, sizeof(stats_t));
        test_cache_efficiency(g_db, iterations, &stats);
        print_stats("Cache Efficiency", &stats);

        memset(&stats, 0, sizeof(stats_t));
        test_concurrent_access(g_db, iterations, &stats);
        print_stats("Concurrent Access", &stats);
    }
    else {
        fprintf(stderr, "Unknown test mode: %s\n", test_mode_str);
        print_usage(argv[0]);
        sqlite3_close(g_db);
        return 1;
    }

    sqlite3_close(g_db);
    return 0;
}
