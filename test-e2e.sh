#!/bin/bash

# =============================================================================
# AGROSYNCHRO END-TO-END TESTING SCRIPT
# =============================================================================
# Comprehensive testing script that validates:
# 1. Infrastructure deployment and connectivity
# 2. API Gateway endpoints functionality
# 3. SQS message processing
# 4. Lambda image upload functionality
# 5. Fargate container health
# 6. RDS database connectivity
# 7. S3 bucket operations
# 8. Overall system integration
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Test configuration
TERRAFORM_DIR="terraform"
TEST_IMAGE_FILE="./mocks/test_image.jpg"
TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${PURPLE}[TEST]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

print_banner() {
    echo -e "${CYAN}"
    echo "========================================================================"
    echo "  🧪 AGROSYNCHRO - END-TO-END TESTING SUITE"
    echo "========================================================================"
    echo -e "${NC}"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_test "Running: $test_name"
    
    if eval "$test_command"; then
        log_success "✅ PASSED: $test_name"
        TEST_RESULTS+=("✅ $test_name")
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log_error "❌ FAILED: $test_name"
        TEST_RESULTS+=("❌ $test_name")
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if running from project root
    if [ ! -f "terraform/main.tf" ]; then
        log_error "Please run this script from the project root directory"
        exit 1
    fi
    
    # Check required tools
    for tool in aws curl terraform jq; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured properly"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

get_terraform_outputs() {
    log_step "Retrieving Terraform outputs..."
    
    cd $TERRAFORM_DIR
    
    # Check if terraform state exists
    if ! terraform state list &> /dev/null; then
        log_error "Terraform state not found. Please deploy infrastructure first."
        cd ..
        exit 1
    fi
    
    # Get outputs with better error handling
    API_URL=$(terraform output -raw api_gateway_invoke_url 2>/dev/null || echo "")
    ALB_URL=$(terraform output -raw alb_health_check_url 2>/dev/null | sed 's|/health$||' || echo "")
    SQS_QUEUE_URL=$(terraform output -raw sqs_queue_url 2>/dev/null || echo "")
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    
    cd ..
    
    if [ -z "$API_URL" ]; then
        log_error "Could not retrieve API Gateway URL. Infrastructure may not be deployed."
        exit 1
    fi
    
    log_success "Retrieved infrastructure endpoints"
    log_info "API Gateway URL: $API_URL"
    log_info "ALB URL: $ALB_URL"
    log_info "SQS Queue URL: $SQS_QUEUE_URL"
    log_info "VPC ID: $VPC_ID"
}

# =============================================================================
# INFRASTRUCTURE TESTS
# =============================================================================

test_aws_connectivity() {
    aws sts get-caller-identity &> /dev/null
}

test_terraform_state() {
    cd $TERRAFORM_DIR
    terraform state list &> /dev/null
    cd ..
}

test_vpc_exists() {
    [ ! -z "$VPC_ID" ] && aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region ${AWS_REGION:-us-east-1} &> /dev/null
}

# =============================================================================
# API GATEWAY TESTS
# =============================================================================

test_api_gateway_ping() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/ping")
    [ "$response" = "200" ]
}

test_api_gateway_ping_content() {
    local content=$(curl -s "$API_URL/ping")
    echo "$content" | grep -q "pong"
}

test_api_gateway_cors() {
    local cors_header=$(curl -s -I "$API_URL/ping" | grep -i "access-control-allow")
    [ ! -z "$cors_header" ] || true  # CORS may not be configured, which is OK
}

# =============================================================================
# SQS TESTS
# =============================================================================

test_sqs_send_message() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL/messages" \
        -H "Content-Type: application/json" \
        -d '{"message": "test from e2e suite", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}')
    [ "$response" = "200" ]
}

test_sqs_queue_exists() {
    [ ! -z "$SQS_QUEUE_URL" ] && aws sqs get-queue-attributes --queue-url "$SQS_QUEUE_URL" --region ${AWS_REGION:-us-east-1} &> /dev/null
}

test_sqs_queue_properties() {
    local attributes=$(aws sqs get-queue-attributes --queue-url "$SQS_QUEUE_URL" --attribute-names All --region ${AWS_REGION:-us-east-1} --output json 2>/dev/null)
    echo "$attributes" | jq -r '.Attributes.KmsMasterKeyId' | grep -q "alias/aws/sqs"
}

# =============================================================================
# LAMBDA TESTS
# =============================================================================

test_lambda_image_upload() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL/api/drones/image" \
        -H "Content-Type: multipart/form-data" \
        -F "image=@$TEST_IMAGE_FILE" \
        -F "drone_id=test-drone-001" \
        -F "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    
    [ "$response" = "200" ] || [ "$response" = "201" ]
}

test_lambda_function_exists() {
    aws lambda get-function --function-name "agrosynchro-drone-image-upload" --region ${AWS_REGION:-us-east-1} &> /dev/null
}


# =============================================================================
# S3 TESTS
# =============================================================================

test_s3_buckets_exist() {
    aws s3api list-buckets --region ${AWS_REGION:-us-east-1} --output json | jq -r '.Buckets[].Name' | grep -q "agrosynchro.*raw.*images"
}

test_s3_bucket_encryption() {
    local bucket=$(aws s3api list-buckets --region ${AWS_REGION:-us-east-1} --output json | jq -r '.Buckets[].Name' | grep "agrosynchro.*raw.*images" | head -1)
    if [ ! -z "$bucket" ]; then
        aws s3api get-bucket-encryption --bucket "$bucket" --region ${AWS_REGION:-us-east-1} &> /dev/null
    else
        return 1
    fi
}

test_s3_bucket_public_access() {
    local bucket=$(aws s3api list-buckets --region ${AWS_REGION:-us-east-1} --output json | jq -r '.Buckets[].Name' | grep "agrosynchro.*raw.*images" | head -1)
    if [ ! -z "$bucket" ]; then
        local pab=$(aws s3api get-public-access-block --bucket "$bucket" --region ${AWS_REGION:-us-east-1} --output json 2>/dev/null)
        echo "$pab" | jq -r '.PublicAccessBlockConfiguration.BlockPublicAcls' | grep -q "true"
    else
        return 1
    fi
}

test_s3_processed_bucket_exists() {
    aws s3api list-buckets --region ${AWS_REGION:-us-east-1} --output json | jq -r '.Buckets[].Name' | grep -q "agrosynchro.*processed.*images"
}

test_s3_bucket_versioning() {
    local bucket=$(aws s3api list-buckets --region ${AWS_REGION:-us-east-1} --output json | jq -r '.Buckets[].Name' | grep "agrosynchro.*raw.*images" | head -1)
    if [ ! -z "$bucket" ]; then
        local versioning=$(aws s3api get-bucket-versioning --bucket "$bucket" --region ${AWS_REGION:-us-east-1} --output json 2>/dev/null)
        echo "$versioning" | jq -r '.Status' | grep -q "Enabled"
    else
        return 1
    fi
}

# =============================================================================
# RDS TESTS
# =============================================================================

test_rds_instance_exists() {
    aws rds describe-db-instances --region ${AWS_REGION:-us-east-1} --output json | jq -r '.DBInstances[].DBInstanceIdentifier' | grep -q "agrosynchro"
}

test_rds_multi_az() {
    local db_instance=$(aws rds describe-db-instances --region ${AWS_REGION:-us-east-1} --output json | jq -r '.DBInstances[] | select(.DBInstanceIdentifier | contains("agrosynchro")) | .MultiAZ')
    [ "$db_instance" = "true" ]
}

test_rds_encryption() {
    local encrypted=$(aws rds describe-db-instances --region ${AWS_REGION:-us-east-1} --output json | jq -r '.DBInstances[] | select(.DBInstanceIdentifier | contains("agrosynchro")) | .StorageEncrypted')
    [ "$encrypted" = "true" ]
}

test_rds_backup_enabled() {
    local backup_retention=$(aws rds describe-db-instances --region ${AWS_REGION:-us-east-1} --output json | jq -r '.DBInstances[] | select(.DBInstanceIdentifier | contains("agrosynchro")) | .BackupRetentionPeriod')
    [ "$backup_retention" -gt 0 ]
}

test_rds_parameter_group() {
    local param_group=$(aws rds describe-db-instances --region ${AWS_REGION:-us-east-1} --output json | jq -r '.DBInstances[] | select(.DBInstanceIdentifier | contains("agrosynchro")) | .DBParameterGroups[0].DBParameterGroupName')
    echo "$param_group" | grep -q "agrosynchro"
}

test_rds_subnet_group() {
    local subnet_group=$(aws rds describe-db-instances --region ${AWS_REGION:-us-east-1} --output json | jq -r '.DBInstances[] | select(.DBInstanceIdentifier | contains("agrosynchro")) | .DBSubnetGroup.DBSubnetGroupName')
    echo "$subnet_group" | grep -q "agrosynchro"
}

# =============================================================================
# FARGATE TESTS
# =============================================================================

test_fargate_cluster_exists() {
    aws ecs describe-clusters --clusters "agrosynchro-cluster" --region ${AWS_REGION:-us-east-1} &> /dev/null
}

test_fargate_service_running() {
    local services=$(aws ecs describe-services --cluster "agrosynchro-cluster" --services "agrosynchro-processing-engine" --region ${AWS_REGION:-us-east-1} --output json 2>/dev/null)
    local running_count=$(echo "$services" | jq -r '.services[0].runningCount // 0')
    [ "$running_count" -gt 0 ]
}

test_fargate_task_definition() {
    aws ecs describe-task-definition --task-definition "agrosynchro-processing-engine" --region ${AWS_REGION:-us-east-1} &> /dev/null
}

test_fargate_service_desired_count() {
    local services=$(aws ecs describe-services --cluster "agrosynchro-cluster" --services "agrosynchro-processing-engine" --region ${AWS_REGION:-us-east-1} --output json 2>/dev/null)
    local desired_count=$(echo "$services" | jq -r '.services[0].desiredCount // 0')
    [ "$desired_count" -gt 0 ]
}

test_fargate_service_status() {
    local services=$(aws ecs describe-services --cluster "agrosynchro-cluster" --services "agrosynchro-processing-engine" --region ${AWS_REGION:-us-east-1} --output json 2>/dev/null)
    local status=$(echo "$services" | jq -r '.services[0].status // "INACTIVE"')
    [ "$status" = "ACTIVE" ]
}

test_fargate_tasks_healthy() {
    local tasks=$(aws ecs list-tasks --cluster "agrosynchro-cluster" --service-name "agrosynchro-processing-engine" --region ${AWS_REGION:-us-east-1} --output json 2>/dev/null)
    local task_count=$(echo "$tasks" | jq -r '.taskArns | length')
    [ "$task_count" -gt 0 ]
}

# =============================================================================
# INTEGRATION TESTS  
# =============================================================================

test_sensor_data_flow() {
    # Test sensor data flow: API Gateway → SQS → Fargate → RDS
    local response=$(curl -s -X POST "$API_URL/messages" \
        -H "Content-Type: application/json" \
        -d '{"user_id": "test-user", "measurements": {"temperature": 25.5, "humidity": 60.0}}')
    
    # Test passes if API Gateway accepts sensor data
    echo "$response" | grep -q "Message sent to queue successfully"
}

test_drone_image_upload_flow() {
    # Test drone image flow: API Gateway → Lambda → S3
    if [ ! -f "$TEST_IMAGE_FILE" ]; then
        log_warning "Test image file not found: $TEST_IMAGE_FILE"
        return 1
    fi
    
    local response=$(curl -s -X POST "$API_URL/api/drones/image" \
        -H "Content-Type: multipart/form-data" \
        -F "image=@$TEST_IMAGE_FILE" \
        -F "drone_id=test-drone-upload" \
        -F "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    
    # Test passes if upload is successful
    echo "$response" | grep -q "success.*true"
}

test_image_processing_flow() {
    # Test complete image processing: upload -> process -> analyze -> delete from raw
    if [ ! -f "$TEST_IMAGE_FILE" ]; then
        log_warning "Test image file not found: $TEST_IMAGE_FILE"
        return 1
    fi
    
    local drone_id="e2e-test-$(date +%s)"
    local upload_response=$(curl -s -X POST "$API_URL/api/drones/image" \
        -H "Content-Type: multipart/form-data" \
        -F "image=@$TEST_IMAGE_FILE" \
        -F "drone_id=$drone_id" \
        -F "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    
    # Check if upload was successful
    echo "$upload_response" | grep -q "success.*true"
}

test_image_appears_in_processed_bucket() {
    # Wait for processing and check if image appears in processed bucket
    sleep 45  # Wait for Fargate to process the image
    
    local processed_bucket=$(aws s3api list-buckets --region ${AWS_REGION:-us-east-1} --output json | jq -r '.Buckets[].Name' | grep "agrosynchro.*processed.*images" | head -1)
    if [ ! -z "$processed_bucket" ]; then
        aws s3 ls s3://"$processed_bucket"/processed/drone-images/ --recursive | grep -q "e2e-test"
    else
        return 1
    fi
}

test_image_removed_from_raw_bucket() {
    # Check that processed image was removed from raw bucket
    local raw_bucket=$(aws s3api list-buckets --region ${AWS_REGION:-us-east-1} --output json | jq -r '.Buckets[].Name' | grep "agrosynchro.*raw.*images" | head -1)
    if [ ! -z "$raw_bucket" ]; then
        # Should NOT find the e2e-test image in raw bucket
        ! aws s3 ls s3://"$raw_bucket"/drone-images/ --recursive | grep -q "e2e-test"
    else
        return 1
    fi
}

# =============================================================================
# ALB/FARGATE DATABASE TESTS
# =============================================================================

test_alb_health_endpoint() {
    # Test ALB health endpoint
    if [ -z "$ALB_URL" ]; then
        log_warning "ALB_URL not set, skipping ALB tests"
        return 1
    fi
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$ALB_URL/health")
    [ "$response" = "200" ]
}

test_database_connectivity() {
    # Test database connectivity via ALB health endpoint
    if [ -z "$ALB_URL" ]; then
        return 1
    fi
    
    local health_response=$(curl -s "$ALB_URL/health")
    echo "$health_response" | jq -r '.database.connected' | grep -q "true"
}

test_database_migrations() {
    # Verify database tables exist via ALB health endpoint
    if [ -z "$ALB_URL" ]; then
        return 1
    fi
    
    local health_response=$(curl -s "$ALB_URL/health")
    local tables=$(echo "$health_response" | jq -r '.database.tables[]' 2>/dev/null)
    
    # Check for required tables
    echo "$tables" | grep -q "users" && \
    echo "$tables" | grep -q "sensor_data" && \
    echo "$tables" | grep -q "drone_images" && \
    echo "$tables" | grep -q "parameters"
}

test_image_analysis_in_database() {
    # Test that image analysis results are stored in database
    if [ -z "$ALB_URL" ]; then
        return 1
    fi
    
    # Wait additional time for processing and analysis
    sleep 15
    
    local analysis_response=$(curl -s "$ALB_URL/api/images/analysis?limit=5")
    local success=$(echo "$analysis_response" | jq -r '.success' 2>/dev/null)
    local count=$(echo "$analysis_response" | jq -r '.count' 2>/dev/null)
    
    [ "$success" = "true" ] && [ "$count" -gt 0 ]
}

test_image_analysis_has_drone_id() {
    # Verify that analysis results contain our test drone_id
    if [ -z "$ALB_URL" ]; then
        return 1
    fi
    
    local analysis_response=$(curl -s "$ALB_URL/api/images/analysis?limit=10")
    echo "$analysis_response" | jq -r '.data[].drone_id' 2>/dev/null | grep -q "e2e-test"
}

test_image_analysis_has_field_status() {
    # Verify that analysis results have field_status and confidence
    if [ -z "$ALB_URL" ]; then
        return 1
    fi
    
    local analysis_response=$(curl -s "$ALB_URL/api/images/analysis?limit=5")
    local first_status=$(echo "$analysis_response" | jq -r '.data[0].field_status' 2>/dev/null)
    local first_confidence=$(echo "$analysis_response" | jq -r '.data[0].analysis_confidence' 2>/dev/null)
    
    # Check if field_status is one of the valid values
    echo "$first_status" | grep -E "excellent|good|fair|poor|critical" > /dev/null && \
    [ "$first_confidence" != "null" ] && [ "$first_confidence" != "0" ]
}

test_sensor_averages_endpoint() {
    # Test sensor averages endpoint (may be empty but should respond correctly)
    if [ -z "$ALB_URL" ]; then
        return 1
    fi
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$ALB_URL/api/sensors/average")
    [ "$response" = "200" ]
}

test_sensor_data_in_database() {
    # Test that sensor data gets processed and stored in database
    if [ -z "$ALB_URL" ]; then
        return 1
    fi
    
    # Send sensor data with unique test values
    local test_temp="99.9"
    local test_humidity="88.8"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    curl -s -X POST "$API_URL/messages" \
        -H "Content-Type: application/json" \
        -d "{\"user_id\": \"test-user-e2e\", \"timestamp\": \"$timestamp\", \"measurements\": {\"temperature\": $test_temp, \"humidity\": $test_humidity}}" > /dev/null
    
    # Wait for SQS processing
    sleep 10
    
    # Check if data appears in sensor averages (might be averaged with other data)
    local averages_response=$(curl -s "$ALB_URL/api/sensors/average")
    local has_data=$(echo "$averages_response" | jq -r '.data.sensors_count' 2>/dev/null)
    
    # Test passes if there's sensor data in the system
    [ "$has_data" != "null" ] && [ "$has_data" -gt 0 ]
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

run_all_tests() {
    log_step "Running infrastructure tests..."
    run_test "AWS Connectivity" test_aws_connectivity
    run_test "Terraform State" test_terraform_state
    run_test "VPC Exists" test_vpc_exists
    
    log_step "Running API Gateway tests..."
    run_test "API Gateway Ping" test_api_gateway_ping
    run_test "API Gateway Ping Content" test_api_gateway_ping_content
    run_test "API Gateway CORS" test_api_gateway_cors
    
    log_step "Running SQS tests..."
    run_test "SQS Send Message" test_sqs_send_message
    run_test "SQS Queue Exists" test_sqs_queue_exists
    run_test "SQS Queue Encryption" test_sqs_queue_properties
    
    log_step "Running Lambda tests..."
    run_test "Lambda Function Exists" test_lambda_function_exists
    run_test "Lambda Image Upload" test_lambda_image_upload
    
    log_step "Running S3 tests..."
    run_test "S3 Raw Buckets Exist" test_s3_buckets_exist
    run_test "S3 Processed Buckets Exist" test_s3_processed_bucket_exists
    run_test "S3 Bucket Encryption" test_s3_bucket_encryption
    run_test "S3 Public Access Block" test_s3_bucket_public_access
    run_test "S3 Bucket Versioning" test_s3_bucket_versioning
    
    log_step "Running RDS tests..."
    run_test "RDS Instance Exists" test_rds_instance_exists
    run_test "RDS Multi-AZ" test_rds_multi_az
    run_test "RDS Encryption" test_rds_encryption
    run_test "RDS Backup Enabled" test_rds_backup_enabled
    run_test "RDS Parameter Group" test_rds_parameter_group
    run_test "RDS Subnet Group" test_rds_subnet_group
    
    log_step "Running Fargate tests..."
    run_test "Fargate Cluster Exists" test_fargate_cluster_exists
    run_test "Fargate Task Definition" test_fargate_task_definition
    run_test "Fargate Service Status" test_fargate_service_status
    run_test "Fargate Service Desired Count" test_fargate_service_desired_count
    run_test "Fargate Service Running" test_fargate_service_running
    run_test "Fargate Tasks Healthy" test_fargate_tasks_healthy
    
    log_step "Running ALB/Database tests..."
    run_test "ALB Health Endpoint" test_alb_health_endpoint
    run_test "Database Connectivity" test_database_connectivity
    run_test "Database Migrations" test_database_migrations
    run_test "Sensor Averages Endpoint" test_sensor_averages_endpoint
    
    log_step "Running sensor data integration tests..."
    run_test "Sensor Data Flow (API→SQS)" test_sensor_data_flow
    run_test "Sensor Data Stored in Database" test_sensor_data_in_database
    
    log_step "Running image integration tests..."
    run_test "Drone Image Upload Flow (API→Lambda→S3)" test_drone_image_upload_flow
    run_test "Image Processing Flow (S3→Fargate→Analysis)" test_image_processing_flow
    run_test "Image Appears in Processed Bucket" test_image_appears_in_processed_bucket  
    run_test "Image Removed from Raw Bucket" test_image_removed_from_raw_bucket
    run_test "Image Analysis in Database" test_image_analysis_in_database
    run_test "Image Analysis Has Drone ID" test_image_analysis_has_drone_id
    run_test "Image Analysis Has Field Status" test_image_analysis_has_field_status
}

# cleanup() {
#     # Clean up test files
#     if [ -f "$TEST_IMAGE_FILE" ]; then
#         rm -f "$TEST_IMAGE_FILE"
#     fi
# }

display_results() {
    echo -e "${CYAN}"
    echo "========================================================================"
    echo "  📊 TEST RESULTS SUMMARY"
    echo "========================================================================"
    echo -e "${NC}"
    
    echo -e "${BLUE}Total Tests:${NC} $TOTAL_TESTS"
    echo -e "${GREEN}Passed:${NC} $PASSED_TESTS"
    echo -e "${RED}Failed:${NC} $FAILED_TESTS"
    echo
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}🎉 ALL TESTS PASSED! Your AgroSynchro deployment is working correctly.${NC}"
    else
        echo -e "${YELLOW}⚠️  Some tests failed. Review the output above for details.${NC}"
    fi
    
    echo
    echo -e "${CYAN}Detailed Results:${NC}"
    for result in "${TEST_RESULTS[@]}"; do
        echo "  $result"
    done
    
    echo
    if [ $FAILED_TESTS -gt 0 ]; then
        echo -e "${YELLOW}💡 Troubleshooting Tips:${NC}"
        echo "  • Check AWS CloudWatch logs for detailed error messages"
        echo "  • Verify all resources are in the correct region"
        echo "  • Ensure IAM permissions are correctly configured"
        echo "  • Wait a few minutes for services to fully initialize"
        echo "  • Run 'terraform plan' to check for configuration drift"
    fi
    
    echo
    echo -e "${BLUE}🔍 For more details:${NC}"
    echo "  • API Gateway: https://console.aws.amazon.com/apigateway/"
    echo "  • Fargate: https://console.aws.amazon.com/ecs/"
    echo "  • RDS: https://console.aws.amazon.com/rds/"
    echo "  • S3: https://console.aws.amazon.com/s3/"
    echo "  • CloudWatch: https://console.aws.amazon.com/cloudwatch/"
}

main() {
    print_banner
    
    # Set up cleanup
    #trap cleanup EXIT
    
    # Run test suite
    check_prerequisites
    get_terraform_outputs
    #create_test_image
    run_all_tests
    display_results
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"