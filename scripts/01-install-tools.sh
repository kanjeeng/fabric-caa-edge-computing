#!/bin/bash
# scripts/01-install-tools.sh (FIXED VERSION)

set -e

echo "🔧 Installing Prerequisites for CANA Blockchain..."

# Check OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    ARCH="amd64"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="darwin"
    ARCH="amd64"
else
    echo "❌ Unsupported OS: $OSTYPE"
    exit 1
fi

echo "Detected OS: $OS ($ARCH)"
echo ""

# ============================================
# 1. INSTALL DOCKER
# ============================================
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    if [ "$OS" == "linux" ]; then
        # Install Docker using official script
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
        
        # Start Docker service
        sudo systemctl start docker
        sudo systemctl enable docker
        
        echo "⚠️  IMPORTANT: You need to log out and log back in for Docker group changes to take effect"
        echo "   Or run: newgrp docker"
    else
        echo "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
        exit 1
    fi
else
    echo "✅ Docker already installed: $(docker --version)"
fi

# ============================================
# 2. INSTALL KUBECTL (FIXED)
# ============================================
if ! command -v kubectl &> /dev/null; then
    echo "📦 Installing kubectl..."
    
    # Remove any corrupted kubectl
    sudo rm -f /usr/local/bin/kubectl
    
    # Get latest stable version
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    echo "   Downloading kubectl version: $KUBECTL_VERSION"
    
    # Download kubectl binary
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
    
    # Verify it's a valid binary (not XML error)
    if file kubectl | grep -q "ELF.*executable"; then
        echo "   ✅ Valid binary downloaded"
    else
        echo "   ❌ Downloaded file is not a valid binary!"
        echo "   File content:"
        head -n 5 kubectl
        exit 1
    fi
    
    # Make executable and move
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
    
    # Verify installation
    /usr/local/bin/kubectl version --client
    
else
    echo "✅ kubectl already installed"
    
    # Check if current kubectl is corrupted
    if ! kubectl version --client &> /dev/null; then
        echo "⚠️  Current kubectl seems corrupted, reinstalling..."
        sudo rm -f /usr/local/bin/kubectl
        
        # Reinstall
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/kubectl
    fi
    
    kubectl version --client
fi

# ============================================
# 3. INSTALL MINIKUBE
# ============================================
if ! command -v minikube &> /dev/null; then
    echo "📦 Installing Minikube..."
    if [ "$OS" == "linux" ]; then
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-${OS}-${ARCH}
        chmod +x minikube-${OS}-${ARCH}
        sudo install minikube-${OS}-${ARCH} /usr/local/bin/minikube
        rm minikube-${OS}-${ARCH}
    else
        brew install minikube
    fi
else
    echo "✅ Minikube already installed: $(minikube version --short)"
fi

# ============================================
# 4. INSTALL NODE.JS
# ============================================
if ! command -v node &> /dev/null; then
    echo "📦 Installing Node.js 18.x..."
    if [ "$OS" == "linux" ]; then
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    else
        brew install node@18
    fi
else
    echo "✅ Node.js already installed: $(node --version)"
fi

# ============================================
# 5. INSTALL PYTHON 3
# ============================================
if ! command -v python3 &> /dev/null; then
    echo "📦 Installing Python 3..."
    if [ "$OS" == "linux" ]; then
        sudo apt-get update
        sudo apt-get install -y python3 python3-pip python3-venv
    else
        brew install python@3.11
    fi
else
    echo "✅ Python already installed: $(python3 --version)"
fi

# ============================================
# 6. INSTALL ADDITIONAL TOOLS
# ============================================
echo ""
echo "📦 Installing additional tools..."

# Install git if not present
if ! command -v git &> /dev/null; then
    if [ "$OS" == "linux" ]; then
        sudo apt-get install -y git
    fi
fi

# Install curl if not present
if ! command -v curl &> /dev/null; then
    if [ "$OS" == "linux" ]; then
        sudo apt-get install -y curl
    fi
fi

# Install file utility for checking binary types
if ! command -v file &> /dev/null; then
    if [ "$OS" == "linux" ]; then
        sudo apt-get install -y file
    fi
fi

echo ""
echo "=" * 60
echo "✅ All prerequisites installed successfully!"
echo "=" * 60
echo ""
echo "Installed versions:"
echo "  Docker:    $(docker --version 2>/dev/null || echo 'Not in PATH yet')"
echo "  kubectl:   $(kubectl version --client --short 2>/dev/null || echo 'Not working')"
echo "  Minikube:  $(minikube version --short 2>/dev/null)"
echo "  Node.js:   $(node --version 2>/dev/null)"
echo "  Python:    $(python3 --version 2>/dev/null)"
echo ""
echo "⚠️  IMPORTANT NEXT STEPS:"
echo "  1. If Docker was just installed, run: newgrp docker"
echo "  2. Or logout and login again"
echo "  3. Then run: ./scripts/02-setup-minikube.sh"
echo ""