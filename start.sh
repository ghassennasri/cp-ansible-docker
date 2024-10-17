#!/bin/bash

LOG_FILE="ansible_execution.log"

# Start with a clean log file
> "$LOG_FILE"

echo "Download the Confluent Platform collection from Ansible Galaxy..." | tee -a "$LOG_FILE"
ansible-galaxy collection install confluent.platform:7.6.0 >> "$LOG_FILE" 2>&1

# Step 1: Start Docker Compose services
echo "Starting Docker Compose..." | tee -a "$LOG_FILE"
docker-compose up -d >> "$LOG_FILE" 2>&1

# Step 2: Check Docker containers status
echo "Waiting for Docker containers to be ready..." | tee -a "$LOG_FILE"
sleep 20  

# Step 3: Run Ansible Playbook to install Confluent Platform
echo "Running Ansible Playbook to install Confluent Platform..." | tee -a "$LOG_FILE"
ansible-playbook -i hosts.yml confluent.platform.all >> "$LOG_FILE" 2>&1

# Sleep for 30 seconds to allow any pending actions to complete
sleep 30

# Step 4: Check if Playbook ran successfully and run Migration Playbook if it did
if [ $? -eq 0 ]; then
  echo "Initial Playbook to install Confluent Platform ran successfully. Running Migration Playbook..." | tee -a "$LOG_FILE"
  ansible-playbook -i hosts_migrated.yml controller3_migration.yaml -v >> "$LOG_FILE" 2>&1

  # Step 5: Check Migration Playbook status
  if [ $? -eq 0 ]; then
    echo "Migration Playbook ran successfully!" | tee -a "$LOG_FILE"
  else
    echo "Migration Playbook failed. Check the logs above for errors." | tee -a "$LOG_FILE"
  fi
else
  echo "Initial Playbook failed. Migration will not proceed. Check the logs above for errors." | tee -a "$LOG_FILE"
fi
