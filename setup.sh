
#!/bin/bash
set -e

# ------------------------------
# Detect OS Type
# ------------------------------
source /etc/os-release
DISTRO=$ID
echo "Detected OS: $DISTRO"

# ------------------------------
# Install System Dependencies + Docker + Docker Compose
# ------------------------------
case "$DISTRO" in
    ubuntu|debian)
        echo "[+] Installing dependencies for Ubuntu/Debian"
        sudo apt-get update
        sudo apt-get install -y gnupg curl unzip software-properties-common git openjdk-17-jdk lsb-release

        echo "[+] Installing Docker and Docker Compose"
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo usermod -aG docker $USER
        ;;
    amzn|amazon)
        echo "[+] Installing dependencies for Amazon Linux"
        sudo yum update -y
        sudo yum install -y unzip curl git java-17-openjdk

        echo "[+] Installing Docker and Docker Compose"
        sudo yum install -y docker
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker $USER

        DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
        mkdir -p $DOCKER_CONFIG/cli-plugins
        curl -SL https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
        chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
        ;;
    centos|rhel)
        echo "[+] Installing dependencies for CentOS/RHEL"
        sudo yum update -y
        sudo yum install -y epel-release unzip curl git java-17-openjdk

        echo "[+] Installing Docker and Docker Compose"
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker $USER
        ;;
    *)
        echo "[-] Unsupported OS: $DISTRO"
        exit 1
        ;;
esac

# ------------------------------
# Install Terraform
# ------------------------------
echo "[+] Installing Terraform..."
if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
    sudo apt-get update && sudo apt-get install -y terraform
else
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
    sudo yum install -y terraform
fi

# ------------------------------
# Install Ansible
# ------------------------------
echo "[+] Installing Ansible..."
if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
    sudo add-apt-repository --yes --update ppa:ansible/ansible
    sudo apt-get install -y ansible
elif [[ "$DISTRO" == "amzn" ]]; then
    sudo amazon-linux-extras enable ansible2
    sudo yum install -y ansible
else
    sudo yum install -y ansible
fi

# ------------------------------
# Install Jenkins
# ------------------------------
echo "[+] Installing Jenkins..."
if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | \
        sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y jenkins
else
    sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
    sudo yum install -y jenkins
fi

# ------------------------------
# Enable and Start Jenkins
# ------------------------------
echo "[+] Starting Jenkins service..."
sudo systemctl enable jenkins
sudo systemctl start jenkins

# ------------------------------
# Jenkins Plugin Init Script
# ------------------------------
echo "[+] Creating Jenkins plugin init script..."
sudo mkdir -p /var/lib/jenkins/init.groovy.d

cat <<'EOF' | sudo tee /var/lib/jenkins/init.groovy.d/install-plugins.groovy
import jenkins.model.*
import hudson.model.*

def instance = Jenkins.getInstance()
def pluginManager = instance.pluginManager
def updateCenter = instance.updateCenter

updateCenter.updateAllSites()

def plugins = [
    "git",
    "workflow-aggregator",
    "pipeline-github-lib",
    "pipeline-stage-view",
    "parameterized-trigger",
    "ansicolor",
    "credentials-binding",
    "ssh-agent",
    "job-dsl",
    "workflow-job",
    "workflow-cps",
    "pipeline-model-definition",
    "scm-api",
    "branch-api",
    "credentials",
    "structs",
    "envinject"
]

def installed = false

plugins.each { pluginName ->
    if (!pluginManager.getPlugin(pluginName)) {
        def plugin = updateCenter.getPlugin(pluginName)
        if (plugin) {
            println("Installing plugin: ${pluginName}")
            plugin.deploy()
            installed = true
        } else {
            println("Plugin not found in Update Center: ${pluginName}")
        }
    }
}

if (installed) {
    instance.save()
}
EOF

sudo chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d

# ------------------------------
# Restart Jenkins to Trigger Plugins
# ------------------------------
echo "[+] Restarting Jenkins to trigger plugin installation..."
sudo systemctl restart jenkins

# ------------------------------
# Output Info
# ------------------------------
echo "Jenkins setup complete!"
echo "Access Jenkins at: http://<your-server-ip>:8080"
echo "Initial Admin Password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword

# ------------------------------
# Reload Docker Group for Current Session
# ------------------------------
#echo "Reloading docker group permissions..."
#newgrp docker
