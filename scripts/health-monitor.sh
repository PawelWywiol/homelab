#!/bin/bash
set -e

# =============================================================================
# Health Monitoring Script
# Generates system/Docker health reports for AI analysis
# Supports: Debian, Ubuntu, Raspberry Pi OS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Configuration (can be overridden via .env or CLI)
# =============================================================================

# Load config file if exists
if [[ -f "$SCRIPT_DIR/.env.health-monitor" ]]; then
    source "$SCRIPT_DIR/.env.health-monitor"
fi

# Thresholds
CPU_THRESHOLD=${CPU_THRESHOLD:-80}
MEMORY_THRESHOLD=${MEMORY_THRESHOLD:-80}
DISK_THRESHOLD=${DISK_THRESHOLD:-85}
CONTAINER_CPU_THRESHOLD=${CONTAINER_CPU_THRESHOLD:-80}
CONTAINER_MEMORY_THRESHOLD=${CONTAINER_MEMORY_THRESHOLD:-80}
CONTAINER_RESTART_THRESHOLD=${CONTAINER_RESTART_THRESHOLD:-3}
LOG_HOURS=${LOG_HOURS:-24}
LONG_RUNNING_DAYS=${LONG_RUNNING_DAYS:-30}
LOG_PATTERNS=${LOG_PATTERNS:-"ERROR|FATAL|CRITICAL|Exception|panic|failed"}

# Output settings
OUTPUT_FORMAT="json"
OUTPUT_FILE=""
QUIET=false

# Report data (accumulated during checks - using individual variables for bash 3.x compat)
RECOMMENDATIONS=""
RECOMMENDATIONS_COUNT=0
CHECKS_TOTAL=0
CHECKS_PASSED=0
CHECKS_WARNING=0
CHECKS_CRITICAL=0

# Report data variables (set by check functions)
REPORT_cpu_status=""
REPORT_cpu_value=""
REPORT_cpu_threshold=""
REPORT_memory_status=""
REPORT_memory_value=""
REPORT_memory_total_mb=""
REPORT_memory_available_mb=""
REPORT_memory_threshold=""
REPORT_disk_status=""
REPORT_disk_threshold=""
REPORT_disk_details=""
REPORT_network_status=""
REPORT_network_details=""
REPORT_system_logs_status=""
REPORT_system_logs_errors=""
REPORT_system_logs_warnings=""
REPORT_system_logs_sample=""
REPORT_docker_installed=""
REPORT_docker_daemon_status=""
REPORT_containers_total=""
REPORT_containers_running=""
REPORT_containers_stopped=""
REPORT_containers_exited=""
REPORT_containers_list=""
REPORT_exited_containers_status=""
REPORT_exited_containers_issues=""
REPORT_container_resources_status=""
REPORT_container_resources_details=""
REPORT_container_restarts_status=""
REPORT_container_restarts_details=""
REPORT_created_not_running_status=""
REPORT_created_not_running_count=""
REPORT_created_not_running_details=""
REPORT_stopped_not_removed_status=""
REPORT_stopped_not_removed_count=""
REPORT_stopped_not_removed_details=""
REPORT_container_disk_status=""
REPORT_container_disk_total=""
REPORT_container_disk_details=""
REPORT_long_running_status=""
REPORT_long_running_count=""
REPORT_long_running_threshold_days=""
REPORT_long_running_details=""
REPORT_outdated_images_status=""
REPORT_outdated_images_details=""
REPORT_container_logs_status=""
REPORT_container_logs_details=""
REPORT_security_status=""
REPORT_security_details=""
REPORT_resource_limits_status=""
REPORT_resource_limits_missing=""
REPORT_resource_limits_details=""
REPORT_network_config_status=""
REPORT_network_config_details=""
REPORT_volume_mounts_status=""
REPORT_volume_mounts_details=""

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    if [[ "$QUIET" != true ]]; then
        echo "==> $*" >&2
    fi
}

error() {
    echo "ERROR: $*" >&2
}

get_hostname() {
    hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "unknown"
}

get_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || ip addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1 || echo "unknown"
}

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

add_recommendation() {
    if [[ -z "$RECOMMENDATIONS" ]]; then
        RECOMMENDATIONS="$1"
    else
        RECOMMENDATIONS="$RECOMMENDATIONS|$1"
    fi
    ((RECOMMENDATIONS_COUNT++)) || true
}

record_check() {
    local status=$1
    ((CHECKS_TOTAL++)) || true
    case "$status" in
        OK|PASS) ((CHECKS_PASSED++)) || true ;;
        WARNING) ((CHECKS_WARNING++)) || true ;;
        CRITICAL|FAIL) ((CHECKS_CRITICAL++)) || true ;;
    esac
}

# JSON helpers
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

json_array_from_pipe() {
    local pipe_str="$1"
    local result="["
    local first=true

    if [[ -n "$pipe_str" ]]; then
        local IFS='|'
        for item in $pipe_str; do
            if [[ "$first" == true ]]; then
                first=false
            else
                result+=","
            fi
            result+="\"$(json_escape "$item")\""
        done
    fi
    result+="]"
    echo "$result"
}

json_array() {
    local arr=("$@")
    local result="["
    local first=true
    for item in "${arr[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            result+=","
        fi
        result+="\"$(json_escape "$item")\""
    done
    result+="]"
    echo "$result"
}

# =============================================================================
# System Checks
# =============================================================================

check_cpu() {
    log "Checking CPU usage..."
    local cpu_usage=0
    local proc_stat="${PROC_STAT_PATH:-/proc/stat}"

    # Prefer /proc/stat on Linux (more reliable)
    if [[ -f "$proc_stat" ]]; then
        local cpu1 cpu2 idle1 idle2
        cpu1=$(grep '^cpu ' "$proc_stat" | awk '{print $2+$3+$4+$5+$6+$7+$8}')
        idle1=$(grep '^cpu ' "$proc_stat" | awk '{print $5}')
        sleep 1
        cpu2=$(grep '^cpu ' "$proc_stat" | awk '{print $2+$3+$4+$5+$6+$7+$8}')
        idle2=$(grep '^cpu ' "$proc_stat" | awk '{print $5}')
        local diff_total=$((cpu2 - cpu1))
        local diff_idle=$((idle2 - idle1))
        if [[ "$diff_total" -gt 0 ]]; then
            cpu_usage=$((100 * (diff_total - diff_idle) / diff_total))
        fi
    elif [[ "$(uname)" == "Linux" ]] && command -v top &>/dev/null; then
        # Fallback to top (Linux syntax only)
        cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print int($2 + $4)}' || echo "0")
    fi
    # macOS/other: cpu_usage stays at 0 (unsupported)

    local status="OK"
    if [[ "$cpu_usage" -ge "$CPU_THRESHOLD" ]]; then
        status="WARNING"
        add_recommendation "CPU usage ($cpu_usage%) exceeds threshold ($CPU_THRESHOLD%)"
    fi

    record_check "$status"
    REPORT_cpu_status="$status"
    REPORT_cpu_value="$cpu_usage"
    REPORT_cpu_threshold="$CPU_THRESHOLD"
}

check_memory() {
    log "Checking memory usage..."
    local mem_info mem_total mem_available mem_used_pct

    mem_info=$(free -m | grep Mem)
    mem_total=$(echo "$mem_info" | awk '{print $2}')
    mem_available=$(echo "$mem_info" | awk '{print $7}')

    if [[ -z "$mem_available" || "$mem_available" == "0" ]]; then
        # Older systems may not have available column
        local mem_free=$(echo "$mem_info" | awk '{print $4}')
        local mem_buffers=$(echo "$mem_info" | awk '{print $6}')
        local mem_cached=$(free -m | grep "buffers/cache" | awk '{print $4}' 2>/dev/null || echo "0")
        mem_available=$((mem_free + mem_buffers + mem_cached))
    fi

    mem_used_pct=$((100 - (mem_available * 100 / mem_total)))

    local status="OK"
    if [[ "$mem_used_pct" -ge "$MEMORY_THRESHOLD" ]]; then
        status="WARNING"
        add_recommendation "Memory usage ($mem_used_pct%) exceeds threshold ($MEMORY_THRESHOLD%)"
    fi

    record_check "$status"
    REPORT_memory_status="$status"
    REPORT_memory_value="$mem_used_pct"
    REPORT_memory_total_mb="$mem_total"
    REPORT_memory_available_mb="$mem_available"
    REPORT_memory_threshold="$MEMORY_THRESHOLD"
}

check_disk() {
    log "Checking disk usage..."
    local disks_json="["
    local first=true
    local any_warning=false

    while IFS= read -r line; do
        local filesystem=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local avail=$(echo "$line" | awk '{print $4}')
        local use_pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local mount=$(echo "$line" | awk '{print $6}')

        local status="OK"
        if [[ "$use_pct" -ge "$DISK_THRESHOLD" ]]; then
            status="WARNING"
            any_warning=true
            add_recommendation "Disk $mount ($use_pct% used) exceeds threshold ($DISK_THRESHOLD%)"
        fi

        if [[ "$first" == true ]]; then
            first=false
        else
            disks_json+=","
        fi

        disks_json+="{\"mount\":\"$mount\",\"filesystem\":\"$filesystem\",\"size\":\"$size\",\"used\":\"$used\",\"available\":\"$avail\",\"use_percent\":$use_pct,\"status\":\"$status\"}"
    done < <(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2)

    disks_json+="]"

    local overall_status="OK"
    if [[ "$any_warning" == true ]]; then
        overall_status="WARNING"
    fi

    record_check "$overall_status"
    REPORT_disk_status="$overall_status"
    REPORT_disk_threshold="$DISK_THRESHOLD"
    REPORT_disk_details="$disks_json"
}

check_network() {
    log "Checking network connectivity..."
    local endpoints=("8.8.8.8" "1.1.1.1")
    local results_json="["
    local first=true
    local any_fail=false

    for endpoint in "${endpoints[@]}"; do
        local status="OK"
        if ! ping -c 1 -W 3 "$endpoint" &>/dev/null; then
            status="FAIL"
            any_fail=true
        fi

        if [[ "$first" == true ]]; then
            first=false
        else
            results_json+=","
        fi
        results_json+="{\"endpoint\":\"$endpoint\",\"status\":\"$status\"}"
    done
    results_json+="]"

    local overall_status="OK"
    if [[ "$any_fail" == true ]]; then
        overall_status="WARNING"
        add_recommendation "Network connectivity issues detected"
    fi

    record_check "$overall_status"
    REPORT_network_status="$overall_status"
    REPORT_network_details="$results_json"
}

# =============================================================================
# System Log Checks
# =============================================================================

check_system_logs() {
    log "Checking system logs (last ${LOG_HOURS}h)..."
    local errors=0
    local warnings=0
    local sample_errors="["
    local first=true

    # Use journalctl if available, else fall back to syslog
    if command -v journalctl &>/dev/null; then
        local since="${LOG_HOURS} hours ago"

        # Count errors
        errors=$(journalctl --since "$since" -p err --no-pager -q 2>/dev/null | wc -l || echo "0")
        warnings=$(journalctl --since "$since" -p warning --no-pager -q 2>/dev/null | wc -l || echo "0")

        # Get sample errors (last 5)
        while IFS= read -r line; do
            if [[ "$first" == true ]]; then
                first=false
            else
                sample_errors+=","
            fi
            sample_errors+="\"$(json_escape "$line")\""
        done < <(journalctl --since "$since" -p err --no-pager -q 2>/dev/null | tail -5)
    elif [[ -f /var/log/syslog ]]; then
        local cutoff_time=$(date -d "${LOG_HOURS} hours ago" +%s 2>/dev/null || echo "0")
        errors=$(grep -ciE "$LOG_PATTERNS" /var/log/syslog 2>/dev/null || echo "0")
        warnings=$(grep -ci "warning" /var/log/syslog 2>/dev/null || echo "0")
    fi

    sample_errors+="]"

    local status="OK"
    if [[ "$errors" -gt 100 ]]; then
        status="CRITICAL"
        add_recommendation "High number of system errors ($errors) in last ${LOG_HOURS}h"
    elif [[ "$errors" -gt 10 ]]; then
        status="WARNING"
        add_recommendation "Elevated system errors ($errors) in last ${LOG_HOURS}h"
    fi

    record_check "$status"
    REPORT_system_logs_status="$status"
    REPORT_system_logs_errors="$errors"
    REPORT_system_logs_warnings="$warnings"
    REPORT_system_logs_sample="$sample_errors"
}

# =============================================================================
# Docker Checks
# =============================================================================

check_docker_daemon() {
    log "Checking Docker daemon..."

    if ! command -v docker &>/dev/null; then
        REPORT_docker_installed="false"
        REPORT_docker_daemon_status="NOT_INSTALLED"
        record_check "WARNING"
        add_recommendation "Docker is not installed"
        return 1
    fi

    REPORT_docker_installed="true"

    if ! docker info &>/dev/null; then
        REPORT_docker_daemon_status="NOT_RUNNING"
        record_check "CRITICAL"
        add_recommendation "Docker daemon is not running"
        return 1
    fi

    REPORT_docker_daemon_status="OK"
    record_check "OK"
    return 0
}

check_containers_status() {
    log "Checking container statuses..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local containers_json="["
    local first=true
    local total=0
    local running=0
    local stopped=0
    local exited=0

    while IFS=$'\t' read -r id name state status image; do
        ((total++))
        case "$state" in
            running) ((running++)) ;;
            exited) ((exited++)) ;;
            *) ((stopped++)) ;;
        esac

        if [[ "$first" == true ]]; then
            first=false
        else
            containers_json+=","
        fi
        containers_json+="{\"id\":\"$id\",\"name\":\"$name\",\"state\":\"$state\",\"status\":\"$(json_escape "$status")\",\"image\":\"$image\"}"
    done < <(docker ps -a --format '{{.ID}}\t{{.Names}}\t{{.State}}\t{{.Status}}\t{{.Image}}' 2>/dev/null)

    containers_json+="]"

    local status="OK"
    if [[ "$exited" -gt 0 ]]; then
        status="WARNING"
    fi

    record_check "$status"
    REPORT_containers_total="$total"
    REPORT_containers_running="$running"
    REPORT_containers_stopped="$stopped"
    REPORT_containers_exited="$exited"
    REPORT_containers_list="$containers_json"
}

check_exited_containers() {
    log "Checking for unexpectedly exited containers..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local issues_json="["
    local first=true
    local issue_count=0

    while IFS=$'\t' read -r id name exit_code; do
        if [[ "$exit_code" != "0" && -n "$exit_code" ]]; then
            ((issue_count++))
            if [[ "$first" == true ]]; then
                first=false
            else
                issues_json+=","
            fi
            issues_json+="{\"id\":\"$id\",\"name\":\"$name\",\"exit_code\":$exit_code}"
            add_recommendation "Container '$name' exited with code $exit_code"
        fi
    done < <(docker ps -a --filter "status=exited" --format '{{.ID}}\t{{.Names}}\t{{.Label "exitCode"}}' 2>/dev/null)

    # Also check via inspect for exit codes
    while IFS=$'\t' read -r id name; do
        local exit_code=$(docker inspect --format '{{.State.ExitCode}}' "$id" 2>/dev/null)
        if [[ "$exit_code" != "0" && -n "$exit_code" ]]; then
            if [[ "$issues_json" != *"$id"* ]]; then
                ((issue_count++))
                if [[ "$first" == true ]]; then
                    first=false
                else
                    issues_json+=","
                fi
                issues_json+="{\"id\":\"$id\",\"name\":\"$name\",\"exit_code\":$exit_code}"
                add_recommendation "Container '$name' exited with code $exit_code"
            fi
        fi
    done < <(docker ps -a --filter "status=exited" --format '{{.ID}}\t{{.Names}}' 2>/dev/null)

    issues_json+="]"

    local status="OK"
    if [[ "$issue_count" -gt 0 ]]; then
        status="WARNING"
    fi

    record_check "$status"
    REPORT_exited_containers_status="$status"
    REPORT_exited_containers_issues="$issues_json"
}

check_container_resources() {
    log "Checking container resource usage..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local resources_json="["
    local first=true
    local any_warning=false

    while IFS=$'\t' read -r id name cpu_pct mem_pct mem_usage; do
        # Remove % signs and parse
        cpu_pct="${cpu_pct//%/}"
        mem_pct="${mem_pct//%/}"

        # Handle floating point
        local cpu_int=${cpu_pct%.*}
        local mem_int=${mem_pct%.*}

        local status="OK"
        if [[ "$cpu_int" -ge "$CONTAINER_CPU_THRESHOLD" ]]; then
            status="WARNING"
            any_warning=true
            add_recommendation "Container '$name' CPU usage ($cpu_pct%) exceeds threshold ($CONTAINER_CPU_THRESHOLD%)"
        fi
        if [[ "$mem_int" -ge "$CONTAINER_MEMORY_THRESHOLD" ]]; then
            status="WARNING"
            any_warning=true
            add_recommendation "Container '$name' memory usage ($mem_pct%) exceeds threshold ($CONTAINER_MEMORY_THRESHOLD%)"
        fi

        if [[ "$first" == true ]]; then
            first=false
        else
            resources_json+=","
        fi
        resources_json+="{\"id\":\"$id\",\"name\":\"$name\",\"cpu_percent\":\"$cpu_pct\",\"memory_percent\":\"$mem_pct\",\"memory_usage\":\"$(json_escape "$mem_usage")\",\"status\":\"$status\"}"
    done < <(docker stats --no-stream --format '{{.ID}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}' 2>/dev/null)

    resources_json+="]"

    local overall_status="OK"
    if [[ "$any_warning" == true ]]; then
        overall_status="WARNING"
    fi

    record_check "$overall_status"
    REPORT_container_resources_status="$overall_status"
    REPORT_container_resources_details="$resources_json"
}

check_container_restarts() {
    log "Checking container restart counts..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local restarts_json="["
    local first=true
    local any_warning=false

    while IFS=$'\t' read -r id name; do
        local restart_count=$(docker inspect --format '{{.RestartCount}}' "$id" 2>/dev/null || echo "0")

        local status="OK"
        if [[ "$restart_count" -ge "$CONTAINER_RESTART_THRESHOLD" ]]; then
            status="WARNING"
            any_warning=true
            add_recommendation "Container '$name' has restarted $restart_count times"
        fi

        if [[ "$restart_count" -gt 0 ]]; then
            if [[ "$first" == true ]]; then
                first=false
            else
                restarts_json+=","
            fi
            restarts_json+="{\"id\":\"$id\",\"name\":\"$name\",\"restart_count\":$restart_count,\"status\":\"$status\"}"
        fi
    done < <(docker ps -a --format '{{.ID}}\t{{.Names}}' 2>/dev/null)

    restarts_json+="]"

    local overall_status="OK"
    if [[ "$any_warning" == true ]]; then
        overall_status="WARNING"
    fi

    record_check "$overall_status"
    REPORT_container_restarts_status="$overall_status"
    REPORT_container_restarts_details="$restarts_json"
}

check_created_not_running() {
    log "Checking containers created but not running..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local containers_json="["
    local first=true
    local count=0

    while IFS=$'\t' read -r id name status; do
        ((count++))
        if [[ "$first" == true ]]; then
            first=false
        else
            containers_json+=","
        fi
        containers_json+="{\"id\":\"$id\",\"name\":\"$name\",\"status\":\"$(json_escape "$status")\"}"
        add_recommendation "Container '$name' is created but not running"
    done < <(docker ps -a --filter "status=created" --format '{{.ID}}\t{{.Names}}\t{{.Status}}' 2>/dev/null)

    containers_json+="]"

    local status="OK"
    if [[ "$count" -gt 0 ]]; then
        status="WARNING"
    fi

    record_check "$status"
    REPORT_created_not_running_status="$status"
    REPORT_created_not_running_count="$count"
    REPORT_created_not_running_details="$containers_json"
}

check_stopped_not_removed() {
    log "Checking stopped containers not removed..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local containers_json="["
    local first=true
    local count=0

    while IFS=$'\t' read -r id name status; do
        ((count++))
        if [[ "$first" == true ]]; then
            first=false
        else
            containers_json+=","
        fi
        containers_json+="{\"id\":\"$id\",\"name\":\"$name\",\"status\":\"$(json_escape "$status")\"}"
    done < <(docker ps -a --filter "status=exited" --format '{{.ID}}\t{{.Names}}\t{{.Status}}' 2>/dev/null)

    containers_json+="]"

    local status="OK"
    if [[ "$count" -gt 5 ]]; then
        status="WARNING"
        add_recommendation "$count stopped containers not removed - consider cleanup"
    fi

    record_check "$status"
    REPORT_stopped_not_removed_status="$status"
    REPORT_stopped_not_removed_count="$count"
    REPORT_stopped_not_removed_details="$containers_json"
}

check_container_disk_usage() {
    log "Checking container disk usage..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local disk_json="["
    local first=true
    local any_warning=false

    while IFS=$'\t' read -r id name size; do
        if [[ "$first" == true ]]; then
            first=false
        else
            disk_json+=","
        fi
        disk_json+="{\"id\":\"$id\",\"name\":\"$name\",\"size\":\"$(json_escape "$size")\"}"
    done < <(docker ps -a --format '{{.ID}}\t{{.Names}}\t{{.Size}}' 2>/dev/null)

    disk_json+="]"

    # Check total Docker disk usage
    local docker_disk_usage=$(docker system df --format '{{.Size}}' 2>/dev/null | head -1 || echo "unknown")

    record_check "OK"
    REPORT_container_disk_status="OK"
    REPORT_container_disk_total="$docker_disk_usage"
    REPORT_container_disk_details="$disk_json"
}

check_long_running_containers() {
    log "Checking long-running containers..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local threshold_seconds=$((LONG_RUNNING_DAYS * 24 * 60 * 60))
    local now=$(date +%s)
    local long_running_json="["
    local first=true
    local count=0

    while IFS=$'\t' read -r id name; do
        local started_at=$(docker inspect --format '{{.State.StartedAt}}' "$id" 2>/dev/null)
        if [[ -n "$started_at" && "$started_at" != "0001-01-01T00:00:00Z" ]]; then
            local started_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo "0")
            local running_seconds=$((now - started_epoch))
            local running_days=$((running_seconds / 86400))

            if [[ "$running_seconds" -gt "$threshold_seconds" ]]; then
                ((count++))
                if [[ "$first" == true ]]; then
                    first=false
                else
                    long_running_json+=","
                fi
                long_running_json+="{\"id\":\"$id\",\"name\":\"$name\",\"running_days\":$running_days}"
            fi
        fi
    done < <(docker ps --format '{{.ID}}\t{{.Names}}' 2>/dev/null)

    long_running_json+="]"

    local status="OK"
    # Long running is informational, not a warning

    record_check "$status"
    REPORT_long_running_status="$status"
    REPORT_long_running_count="$count"
    REPORT_long_running_threshold_days="$LONG_RUNNING_DAYS"
    REPORT_long_running_details="$long_running_json"
}

check_outdated_images() {
    log "Checking for outdated images..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local outdated_json="["
    local first=true
    local count=0

    while IFS=$'\t' read -r id name image; do
        # Parse registry from image name
        local registry="docker.io"
        local image_path="$image"

        if [[ "$image" == *"/"* ]]; then
            local first_part="${image%%/*}"
            if [[ "$first_part" == *"."* || "$first_part" == *":"* ]]; then
                registry="$first_part"
                image_path="${image#*/}"
            fi
        fi

        # Get local image digest
        local local_digest=$(docker inspect --format '{{.Image}}' "$id" 2>/dev/null | cut -c8-19)

        # Get image creation date
        local created=$(docker inspect --format '{{.Created}}' "$id" 2>/dev/null | cut -d'T' -f1)

        if [[ "$first" == true ]]; then
            first=false
        else
            outdated_json+=","
        fi
        outdated_json+="{\"id\":\"$id\",\"name\":\"$name\",\"image\":\"$image\",\"registry\":\"$registry\",\"local_digest\":\"$local_digest\",\"created\":\"$created\"}"
    done < <(docker ps --format '{{.ID}}\t{{.Names}}\t{{.Image}}' 2>/dev/null)

    outdated_json+="]"

    record_check "OK"
    REPORT_outdated_images_status="OK"
    REPORT_outdated_images_details="$outdated_json"
}

check_container_logs() {
    log "Checking container logs for errors..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local logs_json="["
    local first=true
    local any_errors=false
    local since="${LOG_HOURS}h"

    while IFS=$'\t' read -r id name; do
        local error_count=$(docker logs --since "$since" "$id" 2>&1 | grep -ciE "$LOG_PATTERNS" || echo "0")

        if [[ "$error_count" -gt 0 ]]; then
            any_errors=true
            if [[ "$first" == true ]]; then
                first=false
            else
                logs_json+=","
            fi

            # Get sample errors
            local sample_errors=$(docker logs --since "$since" "$id" 2>&1 | grep -iE "$LOG_PATTERNS" | tail -3 | while read -r line; do
                echo "$(json_escape "$line")"
            done | paste -sd',' -)

            logs_json+="{\"id\":\"$id\",\"name\":\"$name\",\"error_count\":$error_count,\"samples\":[$sample_errors]}"

            if [[ "$error_count" -gt 50 ]]; then
                add_recommendation "Container '$name' has $error_count log errors in last ${LOG_HOURS}h"
            fi
        fi
    done < <(docker ps --format '{{.ID}}\t{{.Names}}' 2>/dev/null)

    logs_json+="]"

    local status="OK"
    if [[ "$any_errors" == true ]]; then
        status="WARNING"
    fi

    record_check "$status"
    REPORT_container_logs_status="$status"
    REPORT_container_logs_details="$logs_json"
}

check_security_issues() {
    log "Checking container security configurations..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local security_json="["
    local first=true
    local any_issues=false

    while IFS=$'\t' read -r id name; do
        local issues=()

        # Check privileged mode
        local privileged=$(docker inspect --format '{{.HostConfig.Privileged}}' "$id" 2>/dev/null)
        if [[ "$privileged" == "true" ]]; then
            issues+=("privileged_mode")
        fi

        # Check capabilities
        local cap_add=$(docker inspect --format '{{.HostConfig.CapAdd}}' "$id" 2>/dev/null)
        if [[ "$cap_add" != "[]" && "$cap_add" != "<nil>" && -n "$cap_add" ]]; then
            issues+=("extra_capabilities")
        fi

        # Check PID mode
        local pid_mode=$(docker inspect --format '{{.HostConfig.PidMode}}' "$id" 2>/dev/null)
        if [[ "$pid_mode" == "host" ]]; then
            issues+=("host_pid")
        fi

        # Check network mode
        local network_mode=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$id" 2>/dev/null)
        if [[ "$network_mode" == "host" ]]; then
            issues+=("host_network")
        fi

        # Check for sensitive mounts
        local mounts=$(docker inspect --format '{{range .Mounts}}{{.Source}}:{{end}}' "$id" 2>/dev/null)
        if [[ "$mounts" == *"/var/run/docker.sock"* ]]; then
            issues+=("docker_socket_mounted")
        fi
        if [[ "$mounts" == *"/etc:"* || "$mounts" == *"/etc/"* ]]; then
            issues+=("etc_mounted")
        fi

        if [[ ${#issues[@]} -gt 0 ]]; then
            any_issues=true
            if [[ "$first" == true ]]; then
                first=false
            else
                security_json+=","
            fi
            local issues_array=$(json_array "${issues[@]}")
            security_json+="{\"id\":\"$id\",\"name\":\"$name\",\"issues\":$issues_array}"

            for issue in "${issues[@]}"; do
                add_recommendation "Container '$name' has security concern: $issue"
            done
        fi
    done < <(docker ps --format '{{.ID}}\t{{.Names}}' 2>/dev/null)

    security_json+="]"

    local status="OK"
    if [[ "$any_issues" == true ]]; then
        status="WARNING"
    fi

    record_check "$status"
    REPORT_security_status="$status"
    REPORT_security_details="$security_json"
}

check_resource_limits() {
    log "Checking container resource limits..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local limits_json="["
    local first=true
    local missing_limits=0

    while IFS=$'\t' read -r id name; do
        local memory_limit=$(docker inspect --format '{{.HostConfig.Memory}}' "$id" 2>/dev/null)
        local cpu_limit=$(docker inspect --format '{{.HostConfig.NanoCpus}}' "$id" 2>/dev/null)

        local has_memory_limit="true"
        local has_cpu_limit="true"

        if [[ "$memory_limit" == "0" || -z "$memory_limit" ]]; then
            has_memory_limit="false"
            ((missing_limits++))
            add_recommendation "Container '$name' has no memory limit"
        fi

        if [[ "$cpu_limit" == "0" || -z "$cpu_limit" ]]; then
            has_cpu_limit="false"
        fi

        if [[ "$first" == true ]]; then
            first=false
        else
            limits_json+=","
        fi
        limits_json+="{\"id\":\"$id\",\"name\":\"$name\",\"memory_limit\":$memory_limit,\"cpu_limit\":$cpu_limit,\"has_memory_limit\":$has_memory_limit,\"has_cpu_limit\":$has_cpu_limit}"
    done < <(docker ps --format '{{.ID}}\t{{.Names}}' 2>/dev/null)

    limits_json+="]"

    local status="OK"
    if [[ "$missing_limits" -gt 0 ]]; then
        status="WARNING"
    fi

    record_check "$status"
    REPORT_resource_limits_status="$status"
    REPORT_resource_limits_missing="$missing_limits"
    REPORT_resource_limits_details="$limits_json"
}

check_network_config() {
    log "Checking container network configurations..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local network_json="["
    local first=true

    while IFS=$'\t' read -r id name; do
        local network_mode=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$id" 2>/dev/null)
        local ports=$(docker inspect --format '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}}:{{range $conf}}{{.HostPort}}{{end}} {{end}}' "$id" 2>/dev/null)

        if [[ "$first" == true ]]; then
            first=false
        else
            network_json+=","
        fi
        network_json+="{\"id\":\"$id\",\"name\":\"$name\",\"network_mode\":\"$network_mode\",\"published_ports\":\"$(json_escape "$ports")\"}"
    done < <(docker ps --format '{{.ID}}\t{{.Names}}' 2>/dev/null)

    network_json+="]"

    record_check "OK"
    REPORT_network_config_status="OK"
    REPORT_network_config_details="$network_json"
}

check_volume_mounts() {
    log "Checking container volume mounts..."

    if [[ "${REPORT_docker_installed}" != "true" ]]; then
        return
    fi

    local volumes_json="["
    local first=true

    while IFS=$'\t' read -r id name; do
        local mounts=$(docker inspect --format '{{range .Mounts}}{{.Type}}:{{.Source}}:{{.Destination}}:{{.RW}},{{end}}' "$id" 2>/dev/null)

        if [[ "$first" == true ]]; then
            first=false
        else
            volumes_json+=","
        fi
        volumes_json+="{\"id\":\"$id\",\"name\":\"$name\",\"mounts\":\"$(json_escape "$mounts")\"}"
    done < <(docker ps --format '{{.ID}}\t{{.Names}}' 2>/dev/null)

    volumes_json+="]"

    record_check "OK"
    REPORT_volume_mounts_status="OK"
    REPORT_volume_mounts_details="$volumes_json"
}

# =============================================================================
# Report Generation
# =============================================================================

generate_json_report() {
    local recommendations_array=$(json_array_from_pipe "$RECOMMENDATIONS")

    cat <<EOF
{
  "report_metadata": {
    "generated_at": "$(timestamp)",
    "reporting_period_hours": $LOG_HOURS,
    "server_name": "$(get_hostname)",
    "server_ip": "$(get_ip)",
    "script_version": "1.0.0"
  },
  "overall_status": "$(get_overall_status)",
  "summary": {
    "total_checks": $CHECKS_TOTAL,
    "passed": $CHECKS_PASSED,
    "warnings": $CHECKS_WARNING,
    "critical": $CHECKS_CRITICAL
  },
  "checks": {
    "system": {
      "cpu": {
        "status": "${REPORT_cpu_status:-SKIPPED}",
        "value": ${REPORT_cpu_value:-0},
        "threshold": ${REPORT_cpu_threshold:-$CPU_THRESHOLD}
      },
      "memory": {
        "status": "${REPORT_memory_status:-SKIPPED}",
        "value": ${REPORT_memory_value:-0},
        "total_mb": ${REPORT_memory_total_mb:-0},
        "available_mb": ${REPORT_memory_available_mb:-0},
        "threshold": ${REPORT_memory_threshold:-$MEMORY_THRESHOLD}
      },
      "disk": {
        "status": "${REPORT_disk_status:-SKIPPED}",
        "threshold": ${REPORT_disk_threshold:-$DISK_THRESHOLD},
        "details": ${REPORT_disk_details:-[]}
      },
      "network": {
        "status": "${REPORT_network_status:-SKIPPED}",
        "details": ${REPORT_network_details:-[]}
      },
      "logs": {
        "status": "${REPORT_system_logs_status:-SKIPPED}",
        "errors": ${REPORT_system_logs_errors:-0},
        "warnings": ${REPORT_system_logs_warnings:-0},
        "sample": ${REPORT_system_logs_sample:-[]}
      }
    },
    "docker": {
      "installed": ${REPORT_docker_installed:-false},
      "daemon": {
        "status": "${REPORT_docker_daemon_status:-SKIPPED}"
      },
      "containers": {
        "total": ${REPORT_containers_total:-0},
        "running": ${REPORT_containers_running:-0},
        "stopped": ${REPORT_containers_stopped:-0},
        "exited": ${REPORT_containers_exited:-0},
        "list": ${REPORT_containers_list:-[]}
      },
      "exited_issues": {
        "status": "${REPORT_exited_containers_status:-SKIPPED}",
        "issues": ${REPORT_exited_containers_issues:-[]}
      },
      "resources": {
        "status": "${REPORT_container_resources_status:-SKIPPED}",
        "details": ${REPORT_container_resources_details:-[]}
      },
      "restarts": {
        "status": "${REPORT_container_restarts_status:-SKIPPED}",
        "details": ${REPORT_container_restarts_details:-[]}
      },
      "created_not_running": {
        "status": "${REPORT_created_not_running_status:-SKIPPED}",
        "count": ${REPORT_created_not_running_count:-0},
        "details": ${REPORT_created_not_running_details:-[]}
      },
      "stopped_not_removed": {
        "status": "${REPORT_stopped_not_removed_status:-SKIPPED}",
        "count": ${REPORT_stopped_not_removed_count:-0},
        "details": ${REPORT_stopped_not_removed_details:-[]}
      },
      "disk_usage": {
        "status": "${REPORT_container_disk_status:-SKIPPED}",
        "total": "${REPORT_container_disk_total:-unknown}",
        "details": ${REPORT_container_disk_details:-[]}
      },
      "long_running": {
        "status": "${REPORT_long_running_status:-SKIPPED}",
        "count": ${REPORT_long_running_count:-0},
        "threshold_days": ${REPORT_long_running_threshold_days:-$LONG_RUNNING_DAYS},
        "details": ${REPORT_long_running_details:-[]}
      },
      "images": {
        "status": "${REPORT_outdated_images_status:-SKIPPED}",
        "details": ${REPORT_outdated_images_details:-[]}
      },
      "logs": {
        "status": "${REPORT_container_logs_status:-SKIPPED}",
        "details": ${REPORT_container_logs_details:-[]}
      },
      "security": {
        "status": "${REPORT_security_status:-SKIPPED}",
        "details": ${REPORT_security_details:-[]}
      },
      "resource_limits": {
        "status": "${REPORT_resource_limits_status:-SKIPPED}",
        "missing": ${REPORT_resource_limits_missing:-0},
        "details": ${REPORT_resource_limits_details:-[]}
      },
      "network_config": {
        "status": "${REPORT_network_config_status:-SKIPPED}",
        "details": ${REPORT_network_config_details:-[]}
      },
      "volume_mounts": {
        "status": "${REPORT_volume_mounts_status:-SKIPPED}",
        "details": ${REPORT_volume_mounts_details:-[]}
      }
    }
  },
  "recommendations": $recommendations_array
}
EOF
}

generate_yaml_report() {
    # Convert JSON to YAML-like format using simple transformation
    generate_json_report | sed \
        -e 's/^{$/---/' \
        -e 's/^}$//' \
        -e 's/":\s*{$/:/g' \
        -e 's/":\s*\[$/:/g' \
        -e 's/^\s*},*$//' \
        -e 's/^\s*],*$//' \
        -e 's/"//g' \
        -e 's/,$//' \
        -e 's/: /: /g' | grep -v '^$'
}

generate_markdown_report() {
    local status=$(get_overall_status)
    local status_emoji="✅"
    [[ "$status" == "WARNING" ]] && status_emoji="⚠️"
    [[ "$status" == "CRITICAL" ]] && status_emoji="❌"

    cat <<EOF
# Health Report

## Metadata
- **Generated:** $(timestamp)
- **Server:** $(get_hostname) ($(get_ip))
- **Period:** Last ${LOG_HOURS} hours

## Overall Status: $status_emoji $status

### Summary
| Metric | Value |
|--------|-------|
| Total Checks | $CHECKS_TOTAL |
| Passed | $CHECKS_PASSED |
| Warnings | $CHECKS_WARNING |
| Critical | $CHECKS_CRITICAL |

## System Checks

### CPU
- **Status:** ${REPORT_cpu_status:-SKIPPED}
- **Usage:** ${REPORT_cpu_value:-0}%
- **Threshold:** ${REPORT_cpu_threshold:-$CPU_THRESHOLD}%

### Memory
- **Status:** ${REPORT_memory_status:-SKIPPED}
- **Usage:** ${REPORT_memory_value:-0}%
- **Total:** ${REPORT_memory_total_mb:-0} MB
- **Available:** ${REPORT_memory_available_mb:-0} MB

### Network
- **Status:** ${REPORT_network_status:-SKIPPED}

### System Logs
- **Status:** ${REPORT_system_logs_status:-SKIPPED}
- **Errors:** ${REPORT_system_logs_errors:-0}
- **Warnings:** ${REPORT_system_logs_warnings:-0}

## Docker

### Daemon
- **Installed:** ${REPORT_docker_installed:-false}
- **Status:** ${REPORT_docker_daemon_status:-SKIPPED}

### Containers
- **Total:** ${REPORT_containers_total:-0}
- **Running:** ${REPORT_containers_running:-0}
- **Stopped:** ${REPORT_containers_stopped:-0}
- **Exited:** ${REPORT_containers_exited:-0}

### Security
- **Status:** ${REPORT_security_status:-SKIPPED}

### Resource Limits
- **Status:** ${REPORT_resource_limits_status:-SKIPPED}
- **Missing Limits:** ${REPORT_resource_limits_missing:-0}

## Recommendations
EOF

    if [[ -z "$RECOMMENDATIONS" ]]; then
        echo "No recommendations - all checks passed."
    else
        local IFS='|'
        for rec in $RECOMMENDATIONS; do
            echo "- $rec"
        done
    fi
}

get_overall_status() {
    if [[ "$CHECKS_CRITICAL" -gt 0 ]]; then
        echo "CRITICAL"
    elif [[ "$CHECKS_WARNING" -gt 0 ]]; then
        echo "WARNING"
    else
        echo "OK"
    fi
}

# =============================================================================
# CLI
# =============================================================================

show_help() {
    cat <<EOF
Health Monitoring Script - Generate system/Docker health reports for AI analysis

USAGE:
    $(basename "$0") [OPTIONS]

OPTIONS:
    --format FORMAT     Output format: json, yaml, markdown (default: json)
    --output FILE       Write report to file (default: stdout)
    --config FILE       Load configuration from file
    --quiet             Suppress progress output
    --help              Show this help message

CONFIGURATION:
    Environment variables or .env.health-monitor file:
    - CPU_THRESHOLD (default: 80)
    - MEMORY_THRESHOLD (default: 80)
    - DISK_THRESHOLD (default: 85)
    - CONTAINER_CPU_THRESHOLD (default: 80)
    - CONTAINER_MEMORY_THRESHOLD (default: 80)
    - CONTAINER_RESTART_THRESHOLD (default: 3)
    - LOG_HOURS (default: 24)
    - LONG_RUNNING_DAYS (default: 30)
    - LOG_PATTERNS (default: ERROR|FATAL|CRITICAL|Exception|panic|failed)

EXAMPLES:
    $(basename "$0")                           # JSON to stdout
    $(basename "$0") --format markdown         # Markdown to stdout
    $(basename "$0") --format yaml --output /tmp/report.yaml
    $(basename "$0") --quiet --output /tmp/report.json

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                OUTPUT_FORMAT="$2"
                if [[ ! "$OUTPUT_FORMAT" =~ ^(json|yaml|markdown)$ ]]; then
                    error "Invalid format: $OUTPUT_FORMAT. Use json, yaml, or markdown."
                    exit 1
                fi
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --config)
                if [[ -f "$2" ]]; then
                    source "$2"
                else
                    error "Config file not found: $2"
                    exit 1
                fi
                shift 2
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    log "Starting health check..."

    # System checks
    check_cpu
    check_memory
    check_disk
    check_network
    check_system_logs

    # Docker checks
    if check_docker_daemon; then
        check_containers_status
        check_exited_containers
        check_container_resources
        check_container_restarts
        check_created_not_running
        check_stopped_not_removed
        check_container_disk_usage
        check_long_running_containers
        check_outdated_images
        check_container_logs
        check_security_issues
        check_resource_limits
        check_network_config
        check_volume_mounts
    fi

    log "Generating report..."

    # Generate report
    local report
    case "$OUTPUT_FORMAT" in
        json) report=$(generate_json_report) ;;
        yaml) report=$(generate_yaml_report) ;;
        markdown) report=$(generate_markdown_report) ;;
    esac

    # Output report
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$report" > "$OUTPUT_FILE"
        log "Report written to $OUTPUT_FILE"
    else
        echo "$report"
    fi

    log "Done. Status: $(get_overall_status)"
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
