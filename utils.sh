#!/bin/bash

# ログレベルの定義
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# 現在のログレベル（デフォルトはINFO）
CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO

# ログ出力関数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    if [ $level -ge $CURRENT_LOG_LEVEL ]; then
        case $level in
            $LOG_LEVEL_DEBUG) echo "[$timestamp] DEBUG: $message" ;;
            $LOG_LEVEL_INFO)  echo "[$timestamp] INFO: $message" ;;
            $LOG_LEVEL_WARN)  echo "[$timestamp] WARN: $message" >&2 ;;
            $LOG_LEVEL_ERROR) echo "[$timestamp] ERROR: $message" >&2 ;;
        esac
    fi
}

# エラーハンドリング関数
handle_error() {
    local exit_code=$1
    local error_message=$2
    log $LOG_LEVEL_ERROR "$error_message"
    exit $exit_code
}

# API有効化関数
enable_api() {
    local api=$1
    local project_id=$2
    log $LOG_LEVEL_INFO "Enabling $api API for project $project_id"
    if ! gcloud services enable $api --project=$project_id; then
        handle_error 1 "Failed to enable $api API"
    fi
    log $LOG_LEVEL_DEBUG "$api API enabled successfully"
}

# リソース存在確認関数
check_resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local project_id=$3
    local extra_args=${4:-}
    
    log $LOG_LEVEL_DEBUG "Checking if $resource_type $resource_name exists in project $project_id"
    if gcloud $resource_type describe $resource_name --project=$project_id $extra_args &>/dev/null; then
        log $LOG_LEVEL_DEBUG "$resource_type $resource_name exists"
        return 0
    else
        log $LOG_LEVEL_DEBUG "$resource_type $resource_name does not exist"
        return 1
    fi
}

# タイムアウト付き待機関数
wait_for_operation() {
    local operation_type=$1
    local resource_name=$2
    local timeout=${3:-300}  # デフォルトタイムアウト: 5分
    local check_interval=${4:-10}  # デフォルト確認間隔: 10秒
    
    log $LOG_LEVEL_INFO "Waiting for $operation_type operation on $resource_name to complete"
    local start_time=$(date +%s)
    while true; do
        if check_resource_exists "$operation_type" "$resource_name" "$PROJECT_ID"; then
            log $LOG_LEVEL_INFO "$operation_type operation on $resource_name completed successfully"
            return 0
        fi
        
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -ge $timeout ]; then
            handle_error 1 "$operation_type operation on $resource_name timed out after $timeout seconds"
        fi
        
        log $LOG_LEVEL_DEBUG "Waiting for $check_interval seconds before next check"
        sleep $check_interval
    done
}

# 環境変数の検証関数
validate_env_vars() {
    local required_vars=("$@")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            handle_error 1 "Required environment variable $var is not set"
        fi
    done
    log $LOG_LEVEL_DEBUG "All required environment variables are set"
}
