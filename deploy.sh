

set -euo pipefail


readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' 


readonly LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


readonly EXIT_SUCCESS=0
readonly EXIT_INVALID_INPUT=1
readonly EXIT_CLONE_FAILED=2
readonly EXIT_SSH_FAILED=3
readonly EXIT_DOCKER_FAILED=4
readonly EXIT_NGINX_FAILED=5
readonly EXIT_VALIDATION_FAILED=6


GIT_REPO_URL=""
PAT=""
BRANCH="main"
SSH_USER=""
SERVER_IP=""
SSH_KEY_PATH=""
APP_PORT=""
PROJECT_NAME=""
CLEANUP_MODE=false



log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}


cleanup_on_error() {
    log_error "Script interrupted or failed at line $1"
    log_info "Check log file: $LOG_FILE"
    exit 1
}

trap 'cleanup_on_error $LINENO' ERR INT TERM



validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?:// ]]; then
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}



collect_user_input() {
    log_info "=== Step 1: Collecting User Input ==="
    
    
    while true; do
        read -rp "Enter Git Repository URL: " GIT_REPO_URL
        if validate_url "$GIT_REPO_URL"; then
            break
        else
            log_error "Invalid URL format. Please enter a valid HTTP/HTTPS URL."
        fi
    done
    
    
    read -rsp "Enter Personal Access Token (PAT): " PAT
    echo
    if [ -z "$PAT" ]; then
        error_exit "PAT cannot be empty" $EXIT_INVALID_INPUT
    fi
    
    
    read -rp "Enter branch name (default: main): " BRANCH
    BRANCH="${BRANCH:-main}"
    
   
    read -rp "Enter SSH username: " SSH_USER
    if [ -z "$SSH_USER" ]; then
        error_exit "SSH username cannot be empty" $EXIT_INVALID_INPUT
    fi
    
    
    while true; do
        read -rp "Enter server IP address: " SERVER_IP
        if validate_ip "$SERVER_IP"; then
            break
        else
            log_error "Invalid IP address format."
        fi
    done
    
   
    while true; do
        read -rp "Enter SSH key path: " SSH_KEY_PATH
        SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
        if [ -f "$SSH_KEY_PATH" ]; then
            chmod 600 "$SSH_KEY_PATH"
            break
        else
            log_error "SSH key file not found: $SSH_KEY_PATH"
        fi
    done
    
    
    while true; do
        read -rp "Enter application port: " APP_PORT
        if validate_port "$APP_PORT"; then
            break
        else
            log_error "Invalid port number (1-65535)."
        fi
    done
    
    
    PROJECT_NAME=$(basename "$GIT_REPO_URL" .git)
    
    log_success "Input collection completed"
    log_info "Project: $PROJECT_NAME | Branch: $BRANCH | Port: $APP_PORT"
}



clone_repository() {
    log_info "=== Step 2: Cloning Repository ==="
    
    
    local auth_url
    if [[ "$GIT_REPO_URL" =~ ^https://github.com/ ]]; then
        auth_url="${GIT_REPO_URL/https:\/\//https://${PAT}@}"
    elif [[ "$GIT_REPO_URL" =~ ^https://gitlab.com/ ]]; then
        auth_url="${GIT_REPO_URL/https:\/\//https://oauth2:${PAT}@}"
    else
        auth_url="${GIT_REPO_URL/https:\/\//https://${PAT}@}"
    fi
    
    if [ -d "$PROJECT_NAME" ]; then
        log_warning "Directory $PROJECT_NAME already exists. Pulling latest changes..."
        cd "$PROJECT_NAME" || error_exit "Failed to navigate to $PROJECT_NAME" $EXIT_CLONE_FAILED
        
        git fetch origin || error_exit "Failed to fetch from origin" $EXIT_CLONE_FAILED
        git checkout "$BRANCH" || error_exit "Failed to checkout branch $BRANCH" $EXIT_CLONE_FAILED
        git pull origin "$BRANCH" || error_exit "Failed to pull latest changes" $EXIT_CLONE_FAILED
        
        cd "$SCRIPT_DIR" || exit
    else
        log_info "Cloning repository..."
        git clone -b "$BRANCH" "$auth_url" "$PROJECT_NAME" || error_exit "Failed to clone repository" $EXIT_CLONE_FAILED
    fi
    
    log_success "Repository cloned/updated successfully"
}



verify_project_structure() {
    log_info "=== Step 3: Verifying Project Structure ==="
    
    cd "$PROJECT_NAME" || error_exit "Failed to navigate to project directory" $EXIT_CLONE_FAILED
    
    if [ -f "Dockerfile" ]; then
        log_success "Dockerfile found"
    elif [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        log_success "docker-compose.yml found"
    else
        error_exit "Neither Dockerfile nor docker-compose.yml found in project" $EXIT_VALIDATION_FAILED
    fi
    
    cd "$SCRIPT_DIR" || exit
}



test_ssh_connection() {
    log_info "=== Step 4: Testing SSH Connection ==="
    
    log_info "Testing SSH connectivity to $SSH_USER@$SERVER_IP..."
    
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful'" >> "$LOG_FILE" 2>&1; then
        log_success "SSH connection established"
    else
        error_exit "Failed to establish SSH connection" $EXIT_SSH_FAILED
    fi
}



prepare_remote_environment() {
    log_info "=== Step 5: Preparing Remote Environment ==="
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" bash <<'ENDSSH' || error_exit "Remote environment setup failed" $EXIT_DOCKER_FAILED
        set -e
        
        echo "[INFO] Updating system packages..."
        sudo apt-get update -qq
        
        # Install Docker if not present
        if ! command -v docker &> /dev/null; then
            echo "[INFO] Installing Docker..."
            sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update -qq
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        else
            echo "[INFO] Docker already installed"
        fi
        
        # Install Docker Compose if not present
        if ! command -v docker-compose &> /dev/null; then
            echo "[INFO] Installing Docker Compose..."
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        else
            echo "[INFO] Docker Compose already installed"
        fi
        
        # Install Nginx if not present
        if ! command -v nginx &> /dev/null; then
            echo "[INFO] Installing Nginx..."
            sudo apt-get install -y nginx
        else
            echo "[INFO] Nginx already installed"
        fi
        
        # Add user to docker group
        sudo usermod -aG docker $USER || true
        
        # Enable and start services
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo systemctl enable nginx
        sudo systemctl start nginx
        
        # Display versions
        echo "[INFO] Docker version: $(docker --version)"
        echo "[INFO] Docker Compose version: $(docker-compose --version)"
        echo "[INFO] Nginx version: $(nginx -v 2>&1)"
ENDSSH
    
    log_success "Remote environment prepared successfully"
}



deploy_application() {
    log_info "=== Step 6: Deploying Dockerized Application ==="
    
   
    log_info "Transferring project files to remote server..."
    rsync -avz --progress -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" \
        "$PROJECT_NAME/" "$SSH_USER@$SERVER_IP:~/$PROJECT_NAME/" >> "$LOG_FILE" 2>&1 || \
        error_exit "Failed to transfer project files" $EXIT_DOCKER_FAILED
    
    log_success "Files transferred successfully"
    
    
    log_info "Building and running Docker containers..."
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" \
        "PROJECT_NAME=$PROJECT_NAME APP_PORT=$APP_PORT" bash <<'ENDSSH' || error_exit "Docker deployment failed" $EXIT_DOCKER_FAILED
        set -e
        
        cd "$PROJECT_NAME"
        
        # Stop and remove old containers (idempotency)
        echo "[INFO] Stopping existing containers..."
        docker-compose down 2>/dev/null || true
        docker stop $(docker ps -q --filter "name=$PROJECT_NAME") 2>/dev/null || true
        docker rm $(docker ps -aq --filter "name=$PROJECT_NAME") 2>/dev/null || true
        
        # Build and run
        if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
            echo "[INFO] Using Docker Compose..."
            docker-compose up -d --build
        elif [ -f "Dockerfile" ]; then
            echo "[INFO] Using Dockerfile..."
            docker build -t "$PROJECT_NAME:latest" .
            docker run -d --name "$PROJECT_NAME" -p "$APP_PORT:$APP_PORT" "$PROJECT_NAME:latest"
        fi
        
        # Wait for container to be healthy
        echo "[INFO] Waiting for container to be ready..."
        sleep 10
        
        # Validate container
        if docker ps | grep -q "$PROJECT_NAME"; then
            echo "[SUCCESS] Container is running"
            docker ps --filter "name=$PROJECT_NAME"
        else
            echo "[ERROR] Container failed to start"
            docker logs $(docker ps -aq --filter "name=$PROJECT_NAME" | head -1) || true
            exit 1
        fi
ENDSSH
    
    log_success "Application deployed successfully"
}



configure_nginx() {
    log_info "=== Step 7: Configuring Nginx Reverse Proxy ==="
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" \
        "PROJECT_NAME=$PROJECT_NAME APP_PORT=$APP_PORT SERVER_IP=$SERVER_IP" bash <<'ENDSSH' || error_exit "Nginx configuration failed" $EXIT_NGINX_FAILED
        set -e
        
        CONFIG_FILE="/etc/nginx/sites-available/$PROJECT_NAME"
        
        echo "[INFO] Creating Nginx configuration..."
        sudo tee "$CONFIG_FILE" > /dev/null <<EOF
server {
    listen 80;
    server_name $SERVER_IP _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
        
        # Enable site
        sudo ln -sf "$CONFIG_FILE" "/etc/nginx/sites-enabled/$PROJECT_NAME"
        
        # Remove default if exists
        sudo rm -f /etc/nginx/sites-enabled/default
        
        # Test configuration
        echo "[INFO] Testing Nginx configuration..."
        sudo nginx -t
        
        # Reload Nginx
        echo "[INFO] Reloading Nginx..."
        sudo systemctl reload nginx
        
        echo "[SUCCESS] Nginx configured successfully"
ENDSSH
    
    log_success "Nginx reverse proxy configured"
}



validate_deployment() {
    log_info "=== Step 8: Validating Deployment ==="
    
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" \
        "PROJECT_NAME=$PROJECT_NAME APP_PORT=$APP_PORT" bash <<'ENDSSH' || error_exit "Deployment validation failed" $EXIT_VALIDATION_FAILED
        set -e
        
        # Check Docker service
        if sudo systemctl is-active --quiet docker; then
            echo "[SUCCESS] Docker service is running"
        else
            echo "[ERROR] Docker service is not running"
            exit 1
        fi
        
        # Check container health
        if docker ps | grep -q "$PROJECT_NAME"; then
            echo "[SUCCESS] Container is active and healthy"
        else
            echo "[ERROR] Container is not running"
            exit 1
        fi
        
        # Check Nginx
        if sudo systemctl is-active --quiet nginx; then
            echo "[SUCCESS] Nginx is running"
        else
            echo "[ERROR] Nginx is not running"
            exit 1
        fi
        
        # Test local endpoint
        echo "[INFO] Testing local endpoint..."
        sleep 5
        if curl -sf "http://localhost:$APP_PORT" > /dev/null 2>&1 || \
           curl -sf "http://localhost:80" > /dev/null 2>&1; then
            echo "[SUCCESS] Application is responding"
        else
            echo "[WARNING] Application may not be responding on expected ports"
        fi
ENDSSH
    
    # Test from local machine
    log_info "Testing remote endpoint from local machine..."
    sleep 3
    if curl -sf "http://$SERVER_IP" > /dev/null 2>&1; then
        log_success "Remote endpoint is accessible"
    else
        log_warning "Remote endpoint test failed - check firewall rules"
    fi
    
    log_success "Deployment validation completed"
}



cleanup_deployment() {
    log_info "=== Cleanup Mode: Removing Deployed Resources ==="
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" \
        "PROJECT_NAME=$PROJECT_NAME" bash <<'ENDSSH' || error_exit "Cleanup failed" 1
        set -e
        
        echo "[INFO] Stopping and removing containers..."
        docker-compose -f "$PROJECT_NAME/docker-compose.yml" down 2>/dev/null || true
        docker stop $(docker ps -q --filter "name=$PROJECT_NAME") 2>/dev/null || true
        docker rm $(docker ps -aq --filter "name=$PROJECT_NAME") 2>/dev/null || true
        docker rmi $(docker images -q "$PROJECT_NAME") 2>/dev/null || true
        
        echo "[INFO] Removing Nginx configuration..."
        sudo rm -f "/etc/nginx/sites-enabled/$PROJECT_NAME"
        sudo rm -f "/etc/nginx/sites-available/$PROJECT_NAME"
        sudo systemctl reload nginx
        
        echo "[INFO] Removing project directory..."
        rm -rf "$PROJECT_NAME"
        
        echo "[SUCCESS] Cleanup completed"
ENDSSH
    
    log_success "All resources cleaned up successfully"
}



main() {
    log_info "=========================================="
    log_info "  Automated Deployment Script Started"
    log_info "=========================================="
    log_info "Log file: $LOG_FILE"
    echo
    
    
    if [ "${1:-}" = "--cleanup" ]; then
        CLEANUP_MODE=true
        collect_user_input
        test_ssh_connection
        cleanup_deployment
        log_success "Cleanup completed successfully!"
        exit $EXIT_SUCCESS
    fi
    
   
    collect_user_input
    clone_repository
    verify_project_structure
    test_ssh_connection
    prepare_remote_environment
    deploy_application
    configure_nginx
    validate_deployment
    
    echo
    log_success "=========================================="
    log_success "  Deployment Completed Successfully!"
    log_success "=========================================="
    log_info "Application URL: http://$SERVER_IP"
    log_info "Container Port: $APP_PORT"
    log_info "Log file: $LOG_FILE"
    echo
    log_info "To cleanup all resources, run: ./deploy.sh --cleanup"
    
    exit $EXIT_SUCCESS
}


main "$@"