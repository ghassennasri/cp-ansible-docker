# Single Kafka Controller Migration Test (CP-7.6.0)

## Overview
This repository contains playbooks and scripts to migrate a Kafka controller (`kafka-controller-3`) to a new node (`kafka-controller-3-migrated`). The migration ensures the ClusterID, controller.quorum.voters are consistent across nodes and the migrated node keeps the same nodeID, and metadata synchronization is verified before and after the migration.

## Files Overview
- **`controller3_migration.yml`**: Ansible playbook to handle Kafka controller migration.
- **`start.sh`**: Script to start Docker services, run playbooks, and handle migration.
- **`hosts.yml`**: Inventory file with hosts and connection details.
- **`hosts_migrated.yml`**: Inventory file used for migration.

## Prerequisite: 

### Software Requirements

* Confluent Ansible Collection: Version 7.6.0

* Ansible Versions:

  * Ansible 7.x [ansible-core 2.14] & Python 3.6 - 3.11

  * Ansible 6.x [ansible-core 2.13] & Python 3.6 - 3.10

  * Ansible 5.x [ansible-core 2.12] & Python 3.6 - 3.10

  * Ansible 4.x [ansible-core 2.11] & Python 3.6 - 3.9

* Docker

* Docker Compose 

### Replacing id_rsa.pub file
- Generate ssh rsa key pair in the project directory with the name **`id_rsa`** 
```bash
ssh-keygen -t rsa -b 2048 -f ./id_rsa
```

### Patching the Role File
Before running the migration, you need to patch the Confluent Platform role file to ensure correct behavior during the migration process.

### File to Patch
- **`get_meta_properties.yml`** within the Confluent Platform role (`kafka_controller`). The path to this file is typically located in:
  `~/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_controller/tasks/get_meta_properties.yml`

### Patching Instructions
Replace the content of the file with the following:

```yaml
- name: Check if Data Directories are Formatted
  shell: "{{ binary_base_path }}/bin/kafka-storage info -c {{ kafka_controller.config_file }}"
  ignore_errors: true
  failed_when: false
  register: formatted

- name: Generate Cluster ID for New Clusters
  shell: "{{ binary_base_path }}/bin/kafka-storage random-uuid"
  environment:
    KAFKA_OPTS: "-Xlog:all=error -XX:+IgnoreUnrecognizedVMOptions"
  register: uuid_key
  run_once: true
  when: not kraft_migration | bool and formatted.rc == 1

- name: Output Debug Message - Overridden Cluster ID Task
  debug:
    msg: "Using overridden kafka_cluster_id: {{ kafka_cluster_id }}"
  when: kafka_cluster_id is defined and formatted.rc == 1

- name: Extract ClusterId from meta.properties on ZK Broker
  slurp:
    src: "{{ kafka_broker_final_properties['log.dirs'].split(',')[0] }}/meta.properties"
  delegate_to: "{{ groups.kafka_broker[0] }}"
  register: zoo_cluster
  when: kraft_migration | bool and formatted.rc == 1

- name: Set ClusterId Variable (for use in Formatting)
  set_fact:
    clusterid: >-
      {{ 
        kafka_cluster_id if kafka_cluster_id is defined else
        (zoo_cluster['content'] | b64decode).partition('cluster.id=')[2].partition('\n')[0]
        if kraft_migration | bool else uuid_key.stdout 
      }}
  when: formatted.rc == 1

- name: Format Data Directory
  shell: "{{ binary_base_path }}/bin/kafka-storage format -t={{ clusterid }} -c {{ kafka_controller.config_file }} --ignore-formatted"
  register: format_meta
  when: formatted.rc == 1  # Only format if the directories are not already formatted

```

Alternatively, you can use the provided script (`find_and_patch.sh`) to automate this process. (----under construction----)

## Usage
### Step 1: Start Docker Services
Run the `start.sh` script:

```bash
./start.sh
```

This script will:
1. Start Docker services.
2. Wait for services to be ready.
3. Run the initial playbook to install the Confluent Platform.
4. If successful, proceed to run the migration playbook (`controller3_migration.yml`).

### Step 2: Migration Playbook Steps
The `controller3_migration.yml` playbook performs the following:
- Logs quorum status and replica information before migration.
- Extracts the existing Cluster ID from `meta.properties` of an existing controller.
- Installs the Kafka controller on `kafka-controller-3-migrated`.
- Verifies the Cluster ID matches across controllers.
- Stops `kafka-controller-3` and updates quorum voter settings.
- Restarts controllers and brokers to apply the new configuration.
- Logs the quorum status and replica information after migration.

### Logs
- **`quorum_status_before_migration.log`**: Quorum status before migration.
- **`quorum_status_after_migration.log`**: Quorum status after migration.

**`quorum_status_before_migration.log`**
```text
ClusterId:              gKP1yNTvTvqf4ICEYzpYsg
LeaderId:               9991
LeaderEpoch:            1
HighWatermark:          3145
MaxFollowerLag:         0
MaxFollowerLagTimeMs:   0
CurrentVoters:          [9991,9992,9993]
CurrentObservers:       [1]
NodeId	LogEndOffset	Lag	LastFetchTimestamp	LastCaughtUpTimestamp	Status  	
9991  	3148        	0  	1729175321104     	1729175321104        	Leader  	
9992  	3148        	0  	1729175320937     	1729175320937        	Follower	
9993  	3148        	0  	1729175320937     	1729175320937        	Follower	
1     	3148        	0  	1729175320936     	1729175320936        	Observer	
```
**`quorum_status_after_migration.log`**
```text
ClusterId:              gKP1yNTvTvqf4ICEYzpYsg
LeaderId:               9991
LeaderEpoch:            5
HighWatermark:          5346
MaxFollowerLag:         0
MaxFollowerLagTimeMs:   0
CurrentVoters:          [9991,9992,9993]
CurrentObservers:       [1]
NodeId  LogEndOffset    Lag     LastFetchTimestamp      LastCaughtUpTimestamp   Status  
9991    9140            0       1729177586946           1729177586946           Leader  
9992    9140            0       1729177586699           1729177586699           Follower
9993    9140            0       1729177586698           1729177586698           Follower
1       9140            0       1729177586698           1729177586698           Observer
```

### 

<details>
  <summary>
    <b>Output example (Click to unfold)</b>
  </summary>
  <pre>
Download the Confluent Platform collection from Ansible Galaxy...
Starting galaxy collection install process
Nothing to do. All requested collections are already installed. If you want to reinstall them, consider using `--force`.
Starting Docker Compose...
Creating network "cp-ansible-docker_kafka_network" with driver "bridge"
Creating ksql-1 ... 
Creating kafka-broker-1 ... 
Creating kafka-controller-3-migrated ... 
Creating kafka-controller-3          ... 
Creating kafka-rest                  ... 
Creating kafka-connect               ... 
Creating schema-registry             ... 
Creating control-center              ... 
Creating kafka-controller-2          ... 
Creating kafka-controller-1          ... 
Creating ksql-1                      ... done
Creating kafka-controller-3-migrated ... done
Creating kafka-broker-1              ... done
Creating kafka-rest                  ... done
Creating kafka-connect               ... done
Creating kafka-controller-3          ... done
Creating schema-registry             ... done
Creating control-center              ... done
Creating kafka-controller-2          ... done
Creating kafka-controller-1          ... done
Waiting for Docker containers to be ready...
Running Ansible Playbook to install Confluent Platform...
[WARNING]: Could not match supplied host pattern, ignoring: zookeeper
[WARNING]: Could not match supplied host pattern, ignoring:
kafka_connect_replicator

PLAY [Host Prerequisites] ******************************************************

TASK [Create Certificate Authority and Copy to Ansible Host] *******************
skipping: [kafka-controller-1]

TASK [confluent.platform.common : Confirm Hash Merging Enabled] ****************
ok: [kafka-controller-1] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-controller-2] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-controller-3] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-broker-1] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [schema-registry] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-connect] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [ksql-1] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [control-center] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-rest] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [confluent.platform.common : Verify Ansible version] **********************
ok: [kafka-controller-1] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-controller-2] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-controller-3] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-broker-1] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [schema-registry] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-connect] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [ksql-1] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [control-center] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-rest] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [confluent.platform.common : Check the presence of Controller and Zookeeper] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Gather OS Facts] *****************************
[WARNING]: Platform linux on host kafka-broker-1 is using the discovered Python
interpreter at /usr/bin/python3.8, but future installation of another Python
interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
ok: [kafka-broker-1]
[WARNING]: Platform linux on host kafka-controller-2 is using the discovered
Python interpreter at /usr/bin/python3.8, but future installation of another
Python interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
ok: [kafka-controller-2]
[WARNING]: Platform linux on host kafka-controller-1 is using the discovered
Python interpreter at /usr/bin/python3.8, but future installation of another
Python interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
ok: [kafka-controller-1]
[WARNING]: Platform linux on host kafka-controller-3 is using the discovered
Python interpreter at /usr/bin/python3.8, but future installation of another
Python interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
[WARNING]: Platform linux on host schema-registry is using the discovered
Python interpreter at /usr/bin/python3.8, but future installation of another
Python interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
[WARNING]: Platform linux on host control-center is using the discovered Python
interpreter at /usr/bin/python3.8, but future installation of another Python
interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
[WARNING]: Platform linux on host kafka-connect is using the discovered Python
interpreter at /usr/bin/python3.8, but future installation of another Python
interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
[WARNING]: Platform linux on host ksql-1 is using the discovered Python
interpreter at /usr/bin/python3.8, but future installation of another Python
interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
[WARNING]: Platform linux on host kafka-rest is using the discovered Python
interpreter at /usr/bin/python3.8, but future installation of another Python
interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
ok: [kafka-controller-3]
ok: [schema-registry]
ok: [control-center]
ok: [kafka-connect]
ok: [ksql-1]
ok: [kafka-rest]

TASK [confluent.platform.common : Verify Python version] ***********************
ok: [kafka-controller-1] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-controller-2] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-controller-3] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-broker-1] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [schema-registry] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-connect] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [ksql-1] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [control-center] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-rest] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [confluent.platform.common : Red Hat Repo Setup and Java Installation] ****
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Ubuntu Repo Setup and Java Installation] *****
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/common/tasks/ubuntu.yml for kafka-controller-1, kafka-controller-2, kafka-controller-3, kafka-broker-1, schema-registry, kafka-connect, ksql-1, control-center, kafka-rest

TASK [confluent.platform.common : Install apt-transport-https] *****************
changed: [schema-registry]
changed: [kafka-controller-2]
changed: [kafka-controller-1]
changed: [kafka-broker-1]
changed: [kafka-controller-3]
changed: [kafka-connect]
changed: [ksql-1]
changed: [control-center]
changed: [kafka-rest]

TASK [confluent.platform.common : Install gnupg for gpg-keys] ******************
changed: [schema-registry]
changed: [kafka-broker-1]
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]
changed: [kafka-rest]
changed: [control-center]
changed: [kafka-connect]
changed: [ksql-1]

TASK [confluent.platform.common : Add Confluent Apt Key] ***********************
changed: [kafka-controller-3]
changed: [kafka-controller-2]
changed: [kafka-broker-1]
changed: [schema-registry]
changed: [kafka-controller-1]
changed: [kafka-connect]
changed: [ksql-1]
changed: [control-center]
changed: [kafka-rest]

TASK [confluent.platform.common : Ensure Custom Apt Repo does not Exists when repository_configuration is Confluent] ***
ok: [kafka-controller-3]
ok: [kafka-broker-1]
ok: [kafka-controller-2]
ok: [kafka-controller-1]
ok: [schema-registry]
ok: [kafka-connect]
ok: [ksql-1]
ok: [control-center]
ok: [kafka-rest]

TASK [confluent.platform.common : Add Confluent Apt Repo] **********************
changed: [kafka-controller-3]
changed: [kafka-controller-2]
changed: [kafka-controller-1]
changed: [kafka-broker-1]
changed: [schema-registry]
changed: [kafka-connect]
changed: [ksql-1]
changed: [control-center]
changed: [kafka-rest]

TASK [confluent.platform.common : Add Confluent Clients Apt Key] ***************
ok: [kafka-controller-2]
ok: [kafka-controller-1]
ok: [kafka-controller-3]
ok: [kafka-broker-1]
ok: [schema-registry]
ok: [kafka-connect]
ok: [ksql-1]
ok: [control-center]
ok: [kafka-rest]

TASK [confluent.platform.common : Add Confluent Clients Apt Repo] **************
changed: [kafka-controller-1]
changed: [schema-registry]
changed: [kafka-controller-2]
changed: [kafka-broker-1]
changed: [kafka-controller-3]
changed: [kafka-connect]
changed: [ksql-1]
changed: [control-center]
changed: [kafka-rest]

TASK [confluent.platform.common : Ensure Confluent Apt Repo does not Exists when repository_configuration is Custom] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Ensure Confluent Clients Apt Repo does not Exists when repository_configuration is Custom] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Add Custom Apt Repo] *************************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : meta] ****************************************

TASK [confluent.platform.common : meta] ****************************************

TASK [confluent.platform.common : meta] ****************************************

TASK [confluent.platform.common : meta] ****************************************

TASK [confluent.platform.common : meta] ****************************************

TASK [confluent.platform.common : meta] ****************************************

TASK [confluent.platform.common : meta] ****************************************

TASK [confluent.platform.common : meta] ****************************************

TASK [confluent.platform.common : meta] ****************************************

TASK [confluent.platform.common : Make Sure man pages Directory Exists] ********
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]
ok: [kafka-broker-1]
ok: [schema-registry]
ok: [kafka-connect]
ok: [ksql-1]
ok: [control-center]
ok: [kafka-rest]

TASK [confluent.platform.common : Custom Java Install] *************************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/common/tasks/custom_java_install.yml for kafka-controller-1, kafka-controller-2, kafka-controller-3, kafka-broker-1, schema-registry, kafka-connect, ksql-1, control-center, kafka-rest

TASK [confluent.platform.common : Check custom_java_path in Centos7] ***********
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Check custom_java_path in Debian] ************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Java Update Alternatives] ********************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Keytool Update Alternatives] *****************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Add open JDK repo] ***************************
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]
changed: [kafka-broker-1]
changed: [schema-registry]
changed: [kafka-connect]
changed: [ksql-1]
changed: [control-center]
changed: [kafka-rest]

TASK [confluent.platform.common : Install Java] ********************************
changed: [kafka-controller-1]
changed: [schema-registry]
changed: [kafka-controller-3]
changed: [kafka-controller-2]
changed: [kafka-broker-1]
changed: [control-center]
changed: [kafka-rest]
changed: [kafka-connect]
changed: [ksql-1]

TASK [confluent.platform.common : Install OpenSSL] *****************************
ok: [schema-registry]
ok: [kafka-broker-1]
ok: [kafka-controller-1]
ok: [kafka-controller-3]
ok: [kafka-controller-2]
ok: [kafka-connect]
ok: [ksql-1]
ok: [control-center]
ok: [kafka-rest]

TASK [confluent.platform.common : Get Java Version] ****************************
ok: [schema-registry]
ok: [kafka-controller-2]
ok: [kafka-broker-1]
ok: [kafka-controller-3]
ok: [kafka-controller-1]
ok: [kafka-connect]
ok: [ksql-1]
ok: [control-center]
ok: [kafka-rest]

TASK [confluent.platform.common : Print Java Version] **************************
ok: [kafka-controller-1] => {
    "msg": "Current Java Version is: openjdk version \"17.0.12\" 2024-07-16"
}
ok: [kafka-controller-2] => {
    "msg": "Current Java Version is: openjdk version \"17.0.12\" 2024-07-16"
}
ok: [kafka-controller-3] => {
    "msg": "Current Java Version is: openjdk version \"17.0.12\" 2024-07-16"
}
ok: [kafka-broker-1] => {
    "msg": "Current Java Version is: openjdk version \"17.0.12\" 2024-07-16"
}
ok: [schema-registry] => {
    "msg": "Current Java Version is: openjdk version \"17.0.12\" 2024-07-16"
}
ok: [kafka-connect] => {
    "msg": "Current Java Version is: openjdk version \"17.0.12\" 2024-07-16"
}
ok: [ksql-1] => {
    "msg": "Current Java Version is: openjdk version \"17.0.12\" 2024-07-16"
}
ok: [control-center] => {
    "msg": "Current Java Version is: openjdk version \"17.0.12\" 2024-07-16"
}
ok: [kafka-rest] => {
    "msg": "Current Java Version is: openjdk version \"17.0.12\" 2024-07-16"
}

TASK [confluent.platform.common : Install pip] *********************************
changed: [kafka-controller-1]
changed: [schema-registry]
changed: [kafka-controller-2]
changed: [kafka-controller-3]
changed: [kafka-broker-1]
changed: [kafka-connect]
changed: [ksql-1]
changed: [kafka-rest]
changed: [control-center]

TASK [confluent.platform.common : Upgrade pip] *********************************
changed: [kafka-controller-2]
changed: [kafka-controller-3]
changed: [kafka-controller-1]
changed: [schema-registry]
changed: [kafka-broker-1]
changed: [ksql-1]
changed: [kafka-connect]
changed: [control-center]
changed: [kafka-rest]

TASK [confluent.platform.common : Install pip packages] ************************
changed: [kafka-controller-2]
changed: [schema-registry]
changed: [kafka-controller-1]
changed: [kafka-controller-3]
changed: [kafka-broker-1]
changed: [kafka-connect]
changed: [ksql-1]
changed: [kafka-rest]
changed: [control-center]

TASK [confluent.platform.common : Debian Repo Setup and Java Installation] *****
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Config Validations] **************************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/common/tasks/config_validations.yml for kafka-controller-1, kafka-controller-2, kafka-controller-3, kafka-broker-1, schema-registry, kafka-connect, ksql-1, control-center, kafka-rest

TASK [confluent.platform.common : Retrieve SSL public key hash from private key on Local Host] ***
skipping: [kafka-controller-1] => (item=kafka_controller) 
skipping: [kafka-controller-2] => (item=kafka_controller) 
skipping: [kafka-controller-3] => (item=kafka_controller) 
skipping: [kafka-controller-1]
skipping: [kafka-broker-1] => (item=kafka_broker) 
skipping: [kafka-controller-2]
skipping: [schema-registry] => (item=schema_registry) 
skipping: [kafka-controller-3]
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [kafka-broker-1]
skipping: [ksql-1] => (item=ksql) 
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center] => (item=control_center) 
skipping: [control-center]
skipping: [kafka-rest] => (item=kafka_rest) 
skipping: [kafka-rest]

TASK [confluent.platform.common : Register content of key file] ****************
skipping: [kafka-controller-1] => (item=kafka_controller) 
skipping: [kafka-controller-2] => (item=kafka_controller) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-3] => (item=kafka_controller) 
skipping: [kafka-broker-1] => (item=kafka_broker) 
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [schema-registry] => (item=schema_registry) 
skipping: [kafka-broker-1]
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [ksql-1] => (item=ksql) 
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center] => (item=control_center) 
skipping: [control-center]
skipping: [kafka-rest] => (item=kafka_rest) 
skipping: [kafka-rest]

TASK [confluent.platform.common : Retrieve SSL public key Hash from private key on Remote Host] ***
skipping: [kafka-controller-1] => (item=kafka_controller) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-2] => (item=kafka_controller) 
skipping: [kafka-controller-2]
skipping: [kafka-controller-3] => (item=kafka_controller) 
skipping: [kafka-controller-3]
skipping: [kafka-broker-1] => (item=kafka_broker) 
skipping: [kafka-broker-1]
skipping: [schema-registry] => (item=schema_registry) 
skipping: [schema-registry]
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [kafka-connect]
skipping: [ksql-1] => (item=ksql) 
skipping: [control-center] => (item=control_center) 
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest] => (item=kafka_rest) 
skipping: [kafka-rest]

TASK [confluent.platform.common : Retrieve SSL public key hash from X509 certificate on Local Host] ***
skipping: [kafka-controller-1] => (item=kafka_controller) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-2] => (item=kafka_controller) 
skipping: [kafka-controller-2]
skipping: [kafka-controller-3] => (item=kafka_controller) 
skipping: [kafka-controller-3]
skipping: [kafka-broker-1] => (item=kafka_broker) 
skipping: [kafka-broker-1]
skipping: [schema-registry] => (item=schema_registry) 
skipping: [schema-registry]
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [kafka-connect]
skipping: [ksql-1] => (item=ksql) 
skipping: [ksql-1]
skipping: [control-center] => (item=control_center) 
skipping: [control-center]
skipping: [kafka-rest] => (item=kafka_rest) 
skipping: [kafka-rest]

TASK [confluent.platform.common : Register content of cert file] ***************
skipping: [kafka-controller-1] => (item=kafka_controller) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-2] => (item=kafka_controller) 
skipping: [kafka-controller-2]
skipping: [kafka-controller-3] => (item=kafka_controller) 
skipping: [kafka-controller-3]
skipping: [kafka-broker-1] => (item=kafka_broker) 
skipping: [kafka-broker-1]
skipping: [schema-registry] => (item=schema_registry) 
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [schema-registry]
skipping: [ksql-1] => (item=ksql) 
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center] => (item=control_center) 
skipping: [control-center]
skipping: [kafka-rest] => (item=kafka_rest) 
skipping: [kafka-rest]

TASK [confluent.platform.common : Retrieve SSL public key hash from X509 certificate on Remote Host] ***
skipping: [kafka-controller-1] => (item=kafka_controller) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-2] => (item=kafka_controller) 
skipping: [kafka-controller-3] => (item=kafka_controller) 
skipping: [kafka-controller-2]
skipping: [kafka-broker-1] => (item=kafka_broker) 
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry] => (item=schema_registry) 
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [schema-registry]
skipping: [ksql-1] => (item=ksql) 
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center] => (item=control_center) 
skipping: [control-center]
skipping: [kafka-rest] => (item=kafka_rest) 
skipping: [kafka-rest]

TASK [confluent.platform.common : get public key hash from private key] ********
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]
ok: [kafka-broker-1]
ok: [schema-registry]
ok: [kafka-connect]
ok: [ksql-1]
ok: [control-center]
ok: [kafka-rest]

TASK [confluent.platform.common : get public key hash from X509 cert] **********
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]
ok: [kafka-broker-1]
ok: [schema-registry]
ok: [kafka-connect]
ok: [ksql-1]
ok: [control-center]
ok: [kafka-rest]

TASK [confluent.platform.common : Assert SSL public key hash from private key matches public key hash from Cert] ***
skipping: [kafka-controller-1] => (item=kafka_controller) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-2] => (item=kafka_controller) 
skipping: [kafka-controller-2]
skipping: [kafka-controller-3] => (item=kafka_controller) 
skipping: [kafka-controller-3]
skipping: [kafka-broker-1] => (item=kafka_broker) 
skipping: [kafka-broker-1]
skipping: [schema-registry] => (item=schema_registry) 
skipping: [schema-registry]
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [ksql-1] => (item=ksql) 
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center] => (item=control_center) 
skipping: [control-center]
skipping: [kafka-rest] => (item=kafka_rest) 
skipping: [kafka-rest]

TASK [confluent.platform.common : Check the OS when using FIPS mode] ***********
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Check if FIPS is enabled on Local Host] ******
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : assert] **************************************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Check if FIPS is enabled on Remote Host] *****
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : assert] **************************************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Create Confluent Platform install directory] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Expand remote Confluent Platform archive] ****
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Create Jolokia directory] ********************
skipping: [kafka-controller-1] => (item=kafka_controller) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-2] => (item=kafka_controller) 
skipping: [kafka-controller-2]
skipping: [kafka-controller-3] => (item=kafka_controller) 
skipping: [kafka-controller-3]
skipping: [kafka-broker-1] => (item=kafka_broker) 
skipping: [kafka-broker-1]
skipping: [schema-registry] => (item=schema_registry) 
skipping: [schema-registry]
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [kafka-connect]
skipping: [ksql-1] => (item=ksql) 
skipping: [ksql-1]
skipping: [control-center] => (item=control_center) 
skipping: [control-center]
skipping: [kafka-rest] => (item=kafka_rest) 
skipping: [kafka-rest]

TASK [confluent.platform.common : Copy Jolokia Jar] ****************************
skipping: [kafka-controller-1] => (item=kafka_controller) 
skipping: [kafka-controller-2] => (item=kafka_controller) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-3] => (item=kafka_controller) 
skipping: [kafka-controller-2]
skipping: [kafka-broker-1] => (item=kafka_broker) 
skipping: [kafka-controller-3]
skipping: [schema-registry] => (item=schema_registry) 
skipping: [kafka-broker-1]
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [schema-registry]
skipping: [ksql-1] => (item=ksql) 
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center] => (item=control_center) 
skipping: [control-center]
skipping: [kafka-rest] => (item=kafka_rest) 
skipping: [kafka-rest]

TASK [confluent.platform.common : Download Jolokia Jar] ************************
skipping: [kafka-controller-1] => (item=kafka_controller) 
skipping: [kafka-controller-2] => (item=kafka_controller) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-3] => (item=kafka_controller) 
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1] => (item=kafka_broker) 
skipping: [schema-registry] => (item=schema_registry) 
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [ksql-1] => (item=ksql) 
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center] => (item=control_center) 
skipping: [control-center]
skipping: [kafka-rest] => (item=kafka_rest) 
skipping: [kafka-rest]

TASK [confluent.platform.common : Create Prometheus install directory] *********
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Copy Prometheus Jar] *************************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Download Prometheus JMX Exporter Jar] ********
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : Install Confluent CLI] ***********************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]
skipping: [kafka-broker-1]
skipping: [schema-registry]
skipping: [kafka-connect]
skipping: [ksql-1]
skipping: [control-center]
skipping: [kafka-rest]

TASK [confluent.platform.common : set_fact] ************************************
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]
ok: [kafka-broker-1]
ok: [schema-registry]
[WARNING]: Could not match supplied host pattern, ignoring: zookeeper_parallel
[WARNING]: Could not match supplied host pattern, ignoring: zookeeper_serial
[WARNING]: Could not match supplied host pattern, ignoring: zookeeper_follower
[WARNING]: Could not match supplied host pattern, ignoring: zookeeper_leader
ok: [kafka-connect]
ok: [ksql-1]
ok: [control-center]
ok: [kafka-rest]

PLAY [Zookeeper Status Finding] ************************************************
skipping: no hosts matched

PLAY [Zookeeper Parallel Provisioning] *****************************************
skipping: no hosts matched

PLAY [Zookeeper Serial Ordering] ***********************************************
skipping: no hosts matched

PLAY [Zookeeper Followers Provisioning] ****************************************
skipping: no hosts matched

PLAY [Zookeeper Leader Provisioning] *******************************************
skipping: no hosts matched

PLAY [Kafka Controller Status Finding] *****************************************

TASK [Populate service facts] **************************************************
ok: [kafka-controller-1]
ok: [kafka-controller-3]
ok: [kafka-controller-2]

TASK [Determine Installation Pattern - Parallel or Serial] *********************
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]

TASK [Group Hosts by Installation Pattern] *************************************
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]

PLAY [Kafka Controller Parallel Provisioning] **********************************

TASK [include_role : common] ***************************************************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Gather OS Facts] *******************
ok: [kafka-controller-1] => (item=ansible_os_family)
ok: [kafka-controller-2] => (item=ansible_os_family)
ok: [kafka-controller-3] => (item=ansible_os_family)
ok: [kafka-controller-1] => (item=ansible_fqdn)
ok: [kafka-controller-2] => (item=ansible_fqdn)
ok: [kafka-controller-3] => (item=ansible_fqdn)
ok: [kafka-controller-2] => (item=ansible_distribution)
ok: [kafka-controller-1] => (item=ansible_distribution)
ok: [kafka-controller-3] => (item=ansible_distribution)

TASK [confluent.platform.kafka_controller : Assert that datadir is not present in the inventory] ***
ok: [kafka-controller-1] => (item=kafka-controller-1) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-1",
    "msg": "All assertions passed"
}
ok: [kafka-controller-1] => (item=kafka-controller-2) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-2",
    "msg": "All assertions passed"
}
ok: [kafka-controller-2] => (item=kafka-controller-1) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-1",
    "msg": "All assertions passed"
}
ok: [kafka-controller-1] => (item=kafka-controller-3) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-3",
    "msg": "All assertions passed"
}
ok: [kafka-controller-2] => (item=kafka-controller-2) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-2",
    "msg": "All assertions passed"
}
ok: [kafka-controller-3] => (item=kafka-controller-1) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-1",
    "msg": "All assertions passed"
}
ok: [kafka-controller-2] => (item=kafka-controller-3) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-3",
    "msg": "All assertions passed"
}
ok: [kafka-controller-3] => (item=kafka-controller-2) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-2",
    "msg": "All assertions passed"
}
ok: [kafka-controller-3] => (item=kafka-controller-3) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-3",
    "msg": "All assertions passed"
}

TASK [confluent.platform.kafka_controller : Assert log.dirs Property not Misconfigured] ***
ok: [kafka-controller-1] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-controller-2] => {
    "changed": false,
    "msg": "All assertions passed"
}
ok: [kafka-controller-3] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [Stop Service and Remove Packages on Version Change] **********************
included: common for kafka-controller-1, kafka-controller-2, kafka-controller-3

TASK [confluent.platform.common : Get Package Facts] ***************************
ok: [kafka-controller-3]
ok: [kafka-controller-1]
ok: [kafka-controller-2]

TASK [confluent.platform.common : Determine if Confluent Platform Package Version Will Change] ***
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]

TASK [confluent.platform.common : Get installed Confluent Packages] ************
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]

TASK [confluent.platform.common : Determine Confluent Packages to Remove] ******
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]

TASK [confluent.platform.common : Debug Confluent Packages to Remove] **********
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.common : Get Service Facts] ***************************
ok: [kafka-controller-3]
ok: [kafka-controller-1]
ok: [kafka-controller-2]

TASK [confluent.platform.common : Stop Service before Removing Confluent Packages] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.common : Remove Confluent Packages - Red Hat] *********
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.common : Remove Confluent Packages - Debian] **********
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Install the Kafka Controller Packages] ***
skipping: [kafka-controller-1] => (item=confluent-common) 
skipping: [kafka-controller-1] => (item=confluent-ce-kafka-http-server) 
skipping: [kafka-controller-1] => (item=confluent-server-rest) 
skipping: [kafka-controller-1] => (item=confluent-telemetry) 
skipping: [kafka-controller-1] => (item=confluent-server) 
skipping: [kafka-controller-1] => (item=confluent-rebalancer) 
skipping: [kafka-controller-1] => (item=confluent-security) 
skipping: [kafka-controller-2] => (item=confluent-common) 
skipping: [kafka-controller-2] => (item=confluent-ce-kafka-http-server) 
skipping: [kafka-controller-2] => (item=confluent-server-rest) 
skipping: [kafka-controller-2] => (item=confluent-telemetry) 
skipping: [kafka-controller-2] => (item=confluent-server) 
skipping: [kafka-controller-2] => (item=confluent-rebalancer) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-2] => (item=confluent-security) 
skipping: [kafka-controller-2]
skipping: [kafka-controller-3] => (item=confluent-common) 
skipping: [kafka-controller-3] => (item=confluent-ce-kafka-http-server) 
skipping: [kafka-controller-3] => (item=confluent-server-rest) 
skipping: [kafka-controller-3] => (item=confluent-telemetry) 
skipping: [kafka-controller-3] => (item=confluent-server) 
skipping: [kafka-controller-3] => (item=confluent-rebalancer) 
skipping: [kafka-controller-3] => (item=confluent-security) 
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Install the Kafka Controller Packages] ***
changed: [kafka-controller-2] => (item=confluent-common)
changed: [kafka-controller-1] => (item=confluent-common)
ok: [kafka-controller-2] => (item=confluent-ce-kafka-http-server)
changed: [kafka-controller-3] => (item=confluent-common)
ok: [kafka-controller-1] => (item=confluent-ce-kafka-http-server)
ok: [kafka-controller-3] => (item=confluent-ce-kafka-http-server)
ok: [kafka-controller-2] => (item=confluent-server-rest)
ok: [kafka-controller-1] => (item=confluent-server-rest)
ok: [kafka-controller-3] => (item=confluent-server-rest)
ok: [kafka-controller-2] => (item=confluent-telemetry)
ok: [kafka-controller-1] => (item=confluent-telemetry)
ok: [kafka-controller-3] => (item=confluent-telemetry)
ok: [kafka-controller-2] => (item=confluent-server)
ok: [kafka-controller-1] => (item=confluent-server)
ok: [kafka-controller-3] => (item=confluent-server)
ok: [kafka-controller-2] => (item=confluent-rebalancer)
ok: [kafka-controller-1] => (item=confluent-rebalancer)
ok: [kafka-controller-3] => (item=confluent-rebalancer)
ok: [kafka-controller-2] => (item=confluent-security)
ok: [kafka-controller-1] => (item=confluent-security)
ok: [kafka-controller-3] => (item=confluent-security)

TASK [confluent.platform.kafka_controller : Kafka Controller group] ************
ok: [kafka-controller-2]
ok: [kafka-controller-1]
ok: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Check if Kafka Controller User Exists] ***
ok: [kafka-controller-3]
ok: [kafka-controller-2]
ok: [kafka-controller-1]

TASK [confluent.platform.kafka_controller : Create Kafka Controller user] ******
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Copy Kafka broker's Service to Create kafka Controller's service] ***
changed: [kafka-controller-2]
changed: [kafka-controller-3]
changed: [kafka-controller-1]

TASK [include_role : ssl] ******************************************************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : include_tasks] *********************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [Configure Kerberos] ******************************************************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [Copy Custom Kafka Files] *************************************************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Set Permissions on /var/lib/controller] ***
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Set Permissions on Data Dirs] ******
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Set Permissions on Data Dir files] ***
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Create Kafka Controller Config directory] ***
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Create Kafka Controller Config] ****
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Create Kafka Controller Client Config] ***
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Include Kraft Cluster Data] ********
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_controller/tasks/get_meta_properties.yml for kafka-controller-1, kafka-controller-2, kafka-controller-3

TASK [confluent.platform.kafka_controller : Check if Data Directories are Formatted] ***
changed: [kafka-controller-1]
changed: [kafka-controller-3]
changed: [kafka-controller-2]

TASK [confluent.platform.kafka_controller : Generate Cluster ID for New Clusters] ***
changed: [kafka-controller-1]

TASK [confluent.platform.kafka_controller : Output Debug Message - Overridden Cluster ID Task] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Extract ClusterId from meta.properties on ZK Broker] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Set ClusterId Variable (for use in Formatting)] ***
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Format Data Directory] *************
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Create Logs Directory] *************
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [Update Kafka log4j Config for Log Cleanup] *******************************
included: common for kafka-controller-1, kafka-controller-2, kafka-controller-3

TASK [confluent.platform.common : Replace rootLogger] **************************
ok: [kafka-controller-2]
ok: [kafka-controller-1]
ok: [kafka-controller-3]

TASK [confluent.platform.common : Replace DailyRollingFileAppender with RollingFileAppender] ***
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.common : Remove Key log4j.appender.X.DatePattern] *****
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.common : Register Appenders] **************************
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]

TASK [confluent.platform.common : Add Max Size Properties] *********************
changed: [kafka-controller-1] => (item=['kafkaAppender', 'Append=true'])
changed: [kafka-controller-2] => (item=['kafkaAppender', 'Append=true'])
changed: [kafka-controller-3] => (item=['kafkaAppender', 'Append=true'])
changed: [kafka-controller-1] => (item=['kafkaAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['kafkaAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-3] => (item=['kafkaAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-1] => (item=['kafkaAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-2] => (item=['kafkaAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-3] => (item=['kafkaAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-1] => (item=['stateChangeAppender', 'Append=true'])
changed: [kafka-controller-2] => (item=['stateChangeAppender', 'Append=true'])
changed: [kafka-controller-3] => (item=['stateChangeAppender', 'Append=true'])
changed: [kafka-controller-1] => (item=['stateChangeAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['stateChangeAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-3] => (item=['stateChangeAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-1] => (item=['stateChangeAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-2] => (item=['stateChangeAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-3] => (item=['stateChangeAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-1] => (item=['requestAppender', 'Append=true'])
changed: [kafka-controller-2] => (item=['requestAppender', 'Append=true'])
changed: [kafka-controller-3] => (item=['requestAppender', 'Append=true'])
changed: [kafka-controller-1] => (item=['requestAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-3] => (item=['requestAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['requestAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-1] => (item=['requestAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-2] => (item=['requestAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-3] => (item=['requestAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-1] => (item=['cleanerAppender', 'Append=true'])
changed: [kafka-controller-2] => (item=['cleanerAppender', 'Append=true'])
changed: [kafka-controller-3] => (item=['cleanerAppender', 'Append=true'])
changed: [kafka-controller-1] => (item=['cleanerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['cleanerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-3] => (item=['cleanerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-1] => (item=['cleanerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-2] => (item=['cleanerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-3] => (item=['cleanerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-1] => (item=['controllerAppender', 'Append=true'])
changed: [kafka-controller-2] => (item=['controllerAppender', 'Append=true'])
changed: [kafka-controller-3] => (item=['controllerAppender', 'Append=true'])
changed: [kafka-controller-1] => (item=['controllerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['controllerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-3] => (item=['controllerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-1] => (item=['controllerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-2] => (item=['controllerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-3] => (item=['controllerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-1] => (item=['authorizerAppender', 'Append=true'])
changed: [kafka-controller-2] => (item=['authorizerAppender', 'Append=true'])
changed: [kafka-controller-3] => (item=['authorizerAppender', 'Append=true'])
changed: [kafka-controller-1] => (item=['authorizerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['authorizerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-3] => (item=['authorizerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-1] => (item=['authorizerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-2] => (item=['authorizerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-3] => (item=['authorizerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-1] => (item=['metadataServiceAppender', 'Append=true'])
changed: [kafka-controller-2] => (item=['metadataServiceAppender', 'Append=true'])
changed: [kafka-controller-3] => (item=['metadataServiceAppender', 'Append=true'])
changed: [kafka-controller-1] => (item=['metadataServiceAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['metadataServiceAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-3] => (item=['metadataServiceAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-1] => (item=['metadataServiceAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-2] => (item=['metadataServiceAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-3] => (item=['metadataServiceAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-1] => (item=['auditLogAppender', 'Append=true'])
changed: [kafka-controller-2] => (item=['auditLogAppender', 'Append=true'])
changed: [kafka-controller-3] => (item=['auditLogAppender', 'Append=true'])
changed: [kafka-controller-1] => (item=['auditLogAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['auditLogAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-3] => (item=['auditLogAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-1] => (item=['auditLogAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-2] => (item=['auditLogAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-3] => (item=['auditLogAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-1] => (item=['dataBalancerAppender', 'Append=true'])
changed: [kafka-controller-2] => (item=['dataBalancerAppender', 'Append=true'])
changed: [kafka-controller-3] => (item=['dataBalancerAppender', 'Append=true'])
changed: [kafka-controller-1] => (item=['dataBalancerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['dataBalancerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-3] => (item=['dataBalancerAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['dataBalancerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-1] => (item=['dataBalancerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-3] => (item=['dataBalancerAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-1] => (item=['zkAuditAppender', 'Append=true'])
changed: [kafka-controller-2] => (item=['zkAuditAppender', 'Append=true'])
changed: [kafka-controller-3] => (item=['zkAuditAppender', 'Append=true'])
changed: [kafka-controller-1] => (item=['zkAuditAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-2] => (item=['zkAuditAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-3] => (item=['zkAuditAppender', 'MaxBackupIndex=10'])
changed: [kafka-controller-1] => (item=['zkAuditAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-2] => (item=['zkAuditAppender', 'MaxFileSize=100MB'])
changed: [kafka-controller-3] => (item=['zkAuditAppender', 'MaxFileSize=100MB'])

TASK [confluent.platform.kafka_controller : Set Permissions on Log4j Conf] *****
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Create logredactor rule file directory] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Copy logredactor rule file from control node to component node] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [Configure logredactor] ***************************************************
skipping: [kafka-controller-1] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'kafkaAppender'}) 
skipping: [kafka-controller-1]
skipping: [kafka-controller-2] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'kafkaAppender'}) 
skipping: [kafka-controller-2]
skipping: [kafka-controller-3] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'kafkaAppender'}) 
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Restart kafka Controller] **********
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Create Kafka Controller Jolokia Config] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Create Kafka Controller Jaas Config] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Deploy JMX Exporter Config File] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Create Service Override Directory] ***
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Write Service Overrides] ***********
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Create sysctl directory on Debian distributions] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Tune virtual memory settings] ******
changed: [kafka-controller-2] => (item={'key': 'vm.swappiness', 'value': 1})
changed: [kafka-controller-3] => (item={'key': 'vm.swappiness', 'value': 1})
changed: [kafka-controller-1] => (item={'key': 'vm.swappiness', 'value': 1})
changed: [kafka-controller-3] => (item={'key': 'vm.dirty_background_ratio', 'value': 5})
changed: [kafka-controller-2] => (item={'key': 'vm.dirty_background_ratio', 'value': 5})
changed: [kafka-controller-1] => (item={'key': 'vm.dirty_background_ratio', 'value': 5})
changed: [kafka-controller-3] => (item={'key': 'vm.dirty_ratio', 'value': 80})
changed: [kafka-controller-2] => (item={'key': 'vm.dirty_ratio', 'value': 80})
changed: [kafka-controller-1] => (item={'key': 'vm.dirty_ratio', 'value': 80})
changed: [kafka-controller-3] => (item={'key': 'vm.max_map_count', 'value': 262144})
changed: [kafka-controller-2] => (item={'key': 'vm.max_map_count', 'value': 262144})
changed: [kafka-controller-1] => (item={'key': 'vm.max_map_count', 'value': 262144})

TASK [confluent.platform.kafka_controller : Certs were Updated - Trigger Restart] ***
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : meta] ******************************

TASK [confluent.platform.kafka_controller : meta] ******************************

TASK [confluent.platform.kafka_controller : meta] ******************************

RUNNING HANDLER [confluent.platform.kafka_controller : restart Kafka Controller] ***
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_controller/tasks/restart_and_wait.yml for kafka-controller-1, kafka-controller-2, kafka-controller-3

RUNNING HANDLER [confluent.platform.kafka_controller : Restart Kafka] **********
changed: [kafka-controller-3]
changed: [kafka-controller-2]
changed: [kafka-controller-1]

RUNNING HANDLER [confluent.platform.kafka_controller : Startup Delay] **********
ok: [kafka-controller-3]
ok: [kafka-controller-1]
ok: [kafka-controller-2]

TASK [confluent.platform.kafka_controller : Encrypt secrets] *******************
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : meta] ******************************

TASK [confluent.platform.kafka_controller : meta] ******************************

TASK [confluent.platform.kafka_controller : meta] ******************************

TASK [confluent.platform.kafka_controller : Kafka Started] *********************
changed: [kafka-controller-1]
changed: [kafka-controller-2]
changed: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Wait for Controller health checks to complete] ***
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_controller/tasks/health_check.yml for kafka-controller-1, kafka-controller-2, kafka-controller-3

TASK [confluent.platform.kafka_controller : Check Kafka Metadata Quorum] *******
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Register LogEndOffset] *************
ok: [kafka-controller-1]
ok: [kafka-controller-3]
ok: [kafka-controller-2]

TASK [confluent.platform.kafka_controller : Check LogEndOffset values] *********
[WARNING]: conditional statements should not include jinja2 templating
delimiters such as {{ }} or {% %}. Found: {{ item|int > 0 and
LEO.stdout_lines[1:]|max|int - item|int < 1000 }}
ok: [kafka-controller-1] => (item=47) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "47",
    "msg": "All assertions passed"
}
ok: [kafka-controller-1] => (item=47) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "47",
    "msg": "All assertions passed"
}
ok: [kafka-controller-1] => (item=47) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "47",
    "msg": "All assertions passed"
}
ok: [kafka-controller-2] => (item=47) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "47",
    "msg": "All assertions passed"
}
ok: [kafka-controller-2] => (item=47) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "47",
    "msg": "All assertions passed"
}
ok: [kafka-controller-2] => (item=47) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "47",
    "msg": "All assertions passed"
}
ok: [kafka-controller-3] => (item=47) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "47",
    "msg": "All assertions passed"
}
ok: [kafka-controller-3] => (item=47) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "47",
    "msg": "All assertions passed"
}
ok: [kafka-controller-3] => (item=47) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "47",
    "msg": "All assertions passed"
}

TASK [confluent.platform.kafka_controller : Remove confluent.use.controller.listener config from Client Properties] ***
ok: [kafka-controller-1]
ok: [kafka-controller-2]
ok: [kafka-controller-3]

TASK [confluent.platform.kafka_controller : Delete temporary keys/certs when keystore and trustore is provided] ***
skipping: [kafka-controller-1] => (item=/var/ssl/private/ca.crt) 
skipping: [kafka-controller-1] => (item=/var/ssl/private/kafka_controller.crt) 
skipping: [kafka-controller-1] => (item=/var/ssl/private/kafka_controller.key) 
skipping: [kafka-controller-2] => (item=/var/ssl/private/ca.crt) 
skipping: [kafka-controller-2] => (item=/var/ssl/private/kafka_controller.crt) 
skipping: [kafka-controller-2] => (item=/var/ssl/private/kafka_controller.key) 
[WARNING]: Could not match supplied host pattern, ignoring:
kafka_controller_serial
skipping: [kafka-controller-1]
skipping: [kafka-controller-2]
skipping: [kafka-controller-3] => (item=/var/ssl/private/ca.crt) 
skipping: [kafka-controller-3] => (item=/var/ssl/private/kafka_controller.crt) 
skipping: [kafka-controller-3] => (item=/var/ssl/private/kafka_controller.key) 
skipping: [kafka-controller-3]

PLAY [Kafka Controller Serial Provisioning] ************************************
skipping: no hosts matched

PLAY [Kafka Broker Status Finding] *********************************************

TASK [Populate service facts] **************************************************
ok: [kafka-broker-1]

TASK [Determine Installation Pattern - Parallel or Serial] *********************
ok: [kafka-broker-1]

TASK [Group Hosts by Installation Pattern] *************************************
ok: [kafka-broker-1]

PLAY [Kafka Broker Parallel Provisioning] **************************************

TASK [include_role : common] ***************************************************
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Gather OS Facts] ***********************
ok: [kafka-broker-1] => (item=ansible_os_family)
ok: [kafka-broker-1] => (item=ansible_fqdn)
ok: [kafka-broker-1] => (item=ansible_distribution)

TASK [confluent.platform.kafka_broker : Assert that datadir is not present in the inventory] ***
ok: [kafka-broker-1] => (item=kafka-broker-1) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-broker-1",
    "msg": "All assertions passed"
}

TASK [confluent.platform.kafka_broker : Assert log.dirs Property not Misconfigured] ***
ok: [kafka-broker-1] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [Stop Service and Remove Packages on Version Change] **********************
included: common for kafka-broker-1

TASK [confluent.platform.common : Get Package Facts] ***************************
ok: [kafka-broker-1]

TASK [confluent.platform.common : Determine if Confluent Platform Package Version Will Change] ***
ok: [kafka-broker-1]

TASK [confluent.platform.common : Get installed Confluent Packages] ************
ok: [kafka-broker-1]

TASK [confluent.platform.common : Determine Confluent Packages to Remove] ******
ok: [kafka-broker-1]

TASK [confluent.platform.common : Debug Confluent Packages to Remove] **********
skipping: [kafka-broker-1]

TASK [confluent.platform.common : Get Service Facts] ***************************
ok: [kafka-broker-1]

TASK [confluent.platform.common : Stop Service before Removing Confluent Packages] ***
skipping: [kafka-broker-1]

TASK [confluent.platform.common : Remove Confluent Packages - Red Hat] *********
skipping: [kafka-broker-1]

TASK [confluent.platform.common : Remove Confluent Packages - Debian] **********
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Install the Kafka Broker Packages] *****
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Install the Kafka Broker Packages] *****
changed: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Kafka Broker group] ********************
ok: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Check if Kafka Broker User Exists] *****
ok: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create Kafka Broker user] **************
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Copy Kafka Broker Service from archive file to system] ***
skipping: [kafka-broker-1]

TASK [include_role : ssl] ******************************************************
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : include_tasks] *************************
skipping: [kafka-broker-1]

TASK [Configure Kerberos] ******************************************************
skipping: [kafka-broker-1]

TASK [Copy Custom Kafka Files] *************************************************
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Set Permissions on /var/lib/kafka] *****
ok: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Set Permissions on Data Dirs] **********
changed: [kafka-broker-1] => (item=/var/lib/kafka/data)

TASK [confluent.platform.kafka_broker : Set Permissions on Data Dir files] *****
ok: [kafka-broker-1] => (item=/var/lib/kafka/data)

TASK [confluent.platform.kafka_broker : Create Kafka Broker Config directory] ***
changed: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create Kafka Broker Config] ************
changed: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create Kafka Broker Client Config] *****
changed: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Include Kraft Cluster Data] ************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_broker/tasks/get_meta_properties.yml for kafka-broker-1

TASK [confluent.platform.kafka_broker : Extract ClusterId from meta.properties on KRaft Controller] ***
ok: [kafka-broker-1 -> kafka-controller-1(localhost)]

TASK [confluent.platform.kafka_broker : Format Storage Directory] **************
changed: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create Zookeeper TLS Client Config] ****
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create Logs Directory] *****************
changed: [kafka-broker-1]

TASK [Update Kafka log4j Config for Log Cleanup] *******************************
included: common for kafka-broker-1

TASK [confluent.platform.common : Replace rootLogger] **************************
ok: [kafka-broker-1]

TASK [confluent.platform.common : Replace DailyRollingFileAppender with RollingFileAppender] ***
changed: [kafka-broker-1]

TASK [confluent.platform.common : Remove Key log4j.appender.X.DatePattern] *****
changed: [kafka-broker-1]

TASK [confluent.platform.common : Register Appenders] **************************
ok: [kafka-broker-1]

TASK [confluent.platform.common : Add Max Size Properties] *********************
changed: [kafka-broker-1] => (item=['kafkaAppender', 'Append=true'])
changed: [kafka-broker-1] => (item=['kafkaAppender', 'MaxBackupIndex=10'])
changed: [kafka-broker-1] => (item=['kafkaAppender', 'MaxFileSize=100MB'])
changed: [kafka-broker-1] => (item=['stateChangeAppender', 'Append=true'])
changed: [kafka-broker-1] => (item=['stateChangeAppender', 'MaxBackupIndex=10'])
changed: [kafka-broker-1] => (item=['stateChangeAppender', 'MaxFileSize=100MB'])
changed: [kafka-broker-1] => (item=['requestAppender', 'Append=true'])
changed: [kafka-broker-1] => (item=['requestAppender', 'MaxBackupIndex=10'])
changed: [kafka-broker-1] => (item=['requestAppender', 'MaxFileSize=100MB'])
changed: [kafka-broker-1] => (item=['cleanerAppender', 'Append=true'])
changed: [kafka-broker-1] => (item=['cleanerAppender', 'MaxBackupIndex=10'])
changed: [kafka-broker-1] => (item=['cleanerAppender', 'MaxFileSize=100MB'])
changed: [kafka-broker-1] => (item=['controllerAppender', 'Append=true'])
changed: [kafka-broker-1] => (item=['controllerAppender', 'MaxBackupIndex=10'])
changed: [kafka-broker-1] => (item=['controllerAppender', 'MaxFileSize=100MB'])
changed: [kafka-broker-1] => (item=['authorizerAppender', 'Append=true'])
changed: [kafka-broker-1] => (item=['authorizerAppender', 'MaxBackupIndex=10'])
changed: [kafka-broker-1] => (item=['authorizerAppender', 'MaxFileSize=100MB'])
changed: [kafka-broker-1] => (item=['metadataServiceAppender', 'Append=true'])
changed: [kafka-broker-1] => (item=['metadataServiceAppender', 'MaxBackupIndex=10'])
changed: [kafka-broker-1] => (item=['metadataServiceAppender', 'MaxFileSize=100MB'])
changed: [kafka-broker-1] => (item=['auditLogAppender', 'Append=true'])
changed: [kafka-broker-1] => (item=['auditLogAppender', 'MaxBackupIndex=10'])
changed: [kafka-broker-1] => (item=['auditLogAppender', 'MaxFileSize=100MB'])
changed: [kafka-broker-1] => (item=['dataBalancerAppender', 'Append=true'])
changed: [kafka-broker-1] => (item=['dataBalancerAppender', 'MaxBackupIndex=10'])
changed: [kafka-broker-1] => (item=['dataBalancerAppender', 'MaxFileSize=100MB'])
changed: [kafka-broker-1] => (item=['zkAuditAppender', 'Append=true'])
changed: [kafka-broker-1] => (item=['zkAuditAppender', 'MaxBackupIndex=10'])
changed: [kafka-broker-1] => (item=['zkAuditAppender', 'MaxFileSize=100MB'])

TASK [confluent.platform.kafka_broker : Set Permissions on Log4j Conf] *********
changed: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create logredactor rule file directory] ***
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Copy logredactor rule file from control node to component node] ***
skipping: [kafka-broker-1]

TASK [Configure logredactor] ***************************************************
skipping: [kafka-broker-1] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'kafkaAppender'}) 
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Restart kafka broker] ******************
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create Kafka Broker Jolokia Config] ****
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create Kafka Broker Jaas Config] *******
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create Kafka Broker Password File] *****
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create Zookeeper chroot] ***************
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create SCRAM Users] ********************
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create SCRAM 256 Users] ****************
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1] => (item=None) 
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Deploy JMX Exporter Config File] *******
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create Service Override Directory] *****
changed: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Write Service Overrides] ***************
changed: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create sysctl directory on Debian distributions] ***
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Tune virtual memory settings] **********
changed: [kafka-broker-1] => (item={'key': 'vm.swappiness', 'value': 1})
changed: [kafka-broker-1] => (item={'key': 'vm.dirty_background_ratio', 'value': 5})
changed: [kafka-broker-1] => (item={'key': 'vm.dirty_ratio', 'value': 80})
changed: [kafka-broker-1] => (item={'key': 'vm.max_map_count', 'value': 262144})

TASK [confluent.platform.kafka_broker : Certs were Updated - Trigger Restart] ***
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : meta] **********************************

RUNNING HANDLER [confluent.platform.kafka_broker : restart kafka] **************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_broker/tasks/restart_and_wait.yml for kafka-broker-1

RUNNING HANDLER [confluent.platform.kafka_broker : Restart Kafka] **************
changed: [kafka-broker-1]

RUNNING HANDLER [confluent.platform.kafka_broker : Startup Delay] **************
ok: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Encrypt secrets] ***********************
skipping: [kafka-broker-1]

TASK [Encrypt Controller secrets] **********************************************
skipping: [kafka-broker-1] => (item=kafka-controller-1) 
skipping: [kafka-broker-1] => (item=kafka-controller-2) 
skipping: [kafka-broker-1] => (item=kafka-controller-3) 
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : meta] **********************************

TASK [confluent.platform.kafka_broker : Kafka Started] *************************
changed: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Wait for Broker health checks to complete] ***
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_broker/tasks/health_check.yml for kafka-broker-1

TASK [confluent.platform.kafka_broker : Get Topics with UnderReplicatedPartitions] ***
ok: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Get Topics with UnderReplicatedPartitions with Secrets Protection enabled] ***
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Wait for Metadata Service to start] ****
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Wait for Embedded Rest Proxy to start] ***
ok: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Fetch Files for Debugging Failure] *****
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Fail Provisioning] *********************
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Register Cluster] **********************
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Create RBAC Rolebindings] **************
skipping: [kafka-broker-1]

TASK [confluent.platform.kafka_broker : Delete temporary keys/certs when keystore and trustore is provided] ***
[WARNING]: Could not match supplied host pattern, ignoring: kafka_broker_serial
[WARNING]: Could not match supplied host pattern, ignoring:
kafka_broker_non_controller
[WARNING]: Could not match supplied host pattern, ignoring:
kafka_broker_controller
skipping: [kafka-broker-1] => (item=/var/ssl/private/ca.crt) 
skipping: [kafka-broker-1] => (item=/var/ssl/private/kafka_broker.crt) 
skipping: [kafka-broker-1] => (item=/var/ssl/private/kafka_broker.key) 
skipping: [kafka-broker-1]

PLAY [Kafka Broker Serial Provisioning] ****************************************
skipping: no hosts matched

PLAY [Kafka Broker Serial Ordering] ********************************************
skipping: no hosts matched

PLAY [Kafka Broker Non Controllers Provisioning] *******************************
skipping: no hosts matched

PLAY [Kafka Broker Controller Provisioning] ************************************
skipping: no hosts matched

PLAY [Schema Registry Provisioning] ********************************************

TASK [include_role : common] ***************************************************
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Gather OS Facts] ********************
ok: [schema-registry] => (item=ansible_os_family)
ok: [schema-registry] => (item=ansible_fqdn)

TASK [Stop Service and Remove Packages on Version Change] **********************
included: common for schema-registry

TASK [confluent.platform.common : Get Package Facts] ***************************
ok: [schema-registry]

TASK [confluent.platform.common : Determine if Confluent Platform Package Version Will Change] ***
ok: [schema-registry]

TASK [confluent.platform.common : Get installed Confluent Packages] ************
ok: [schema-registry]

TASK [confluent.platform.common : Determine Confluent Packages to Remove] ******
ok: [schema-registry]

TASK [confluent.platform.common : Debug Confluent Packages to Remove] **********
skipping: [schema-registry]

TASK [confluent.platform.common : Get Service Facts] ***************************
ok: [schema-registry]

TASK [confluent.platform.common : Stop Service before Removing Confluent Packages] ***
skipping: [schema-registry]

TASK [confluent.platform.common : Remove Confluent Packages - Red Hat] *********
skipping: [schema-registry]

TASK [confluent.platform.common : Remove Confluent Packages - Debian] **********
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Install the Schema Registry Packages] ***
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Install the Schema Registry Packages] ***
changed: [schema-registry]

TASK [confluent.platform.schema_registry : Schema Registry Group] **************
ok: [schema-registry]

TASK [confluent.platform.schema_registry : Check if Schema Registry User Exists] ***
ok: [schema-registry]

TASK [confluent.platform.schema_registry : Create Schema Registry User] ********
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Copy Schema Registry Service from archive file to system] ***
skipping: [schema-registry]

TASK [include_role : ssl] ******************************************************
skipping: [schema-registry]

TASK [Configure Kerberos] ******************************************************
skipping: [schema-registry]

TASK [Copy Custom Schema Registry Files] ***************************************
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Configure RBAC] *********************
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Create Schema Registry Config directory] ***
changed: [schema-registry]

TASK [confluent.platform.schema_registry : Create Schema Registry Config] ******
changed: [schema-registry]

TASK [Create Schema Registry Config with Secrets Protection] *******************
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Create Logs Directory] **************
changed: [schema-registry]

TASK [Update log4j Config for Log Cleanup] *************************************
included: common for schema-registry

TASK [confluent.platform.common : Replace rootLogger] **************************
ok: [schema-registry]

TASK [confluent.platform.common : Replace DailyRollingFileAppender with RollingFileAppender] ***
ok: [schema-registry]

TASK [confluent.platform.common : Remove Key log4j.appender.X.DatePattern] *****
ok: [schema-registry]

TASK [confluent.platform.common : Register Appenders] **************************
ok: [schema-registry]

TASK [confluent.platform.common : Add Max Size Properties] *********************
changed: [schema-registry] => (item=['file', 'Append=true'])
changed: [schema-registry] => (item=['file', 'MaxBackupIndex=10'])
changed: [schema-registry] => (item=['file', 'MaxFileSize=100MB'])

TASK [confluent.platform.schema_registry : Set Permissions on Log4j Conf] ******
changed: [schema-registry]

TASK [confluent.platform.schema_registry : Create logredactor rule file directory] ***
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Copy logredactor rule file from control node to component node] ***
skipping: [schema-registry]

TASK [Configure logredactor] ***************************************************
skipping: [schema-registry] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'file'}) 
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Restart schema registry] ************
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Create Schema Registry Jolokia Config] ***
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Deploy JMX Exporter Config File] ****
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Create Basic Auth Jaas File] ********
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Create Basic Auth Password File] ****
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Create Service Override Directory] ***
changed: [schema-registry]

TASK [confluent.platform.schema_registry : Write Service Overrides] ************
changed: [schema-registry]

TASK [confluent.platform.schema_registry : Certs were Updated - Trigger Restart] ***
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : meta] *******************************

RUNNING HANDLER [confluent.platform.schema_registry : restart schema-registry] ***
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/schema_registry/tasks/restart_and_wait.yml for schema-registry

RUNNING HANDLER [confluent.platform.schema_registry : Restart Schema Registry] ***
changed: [schema-registry]

RUNNING HANDLER [confluent.platform.schema_registry : Startup Delay] ***********
ok: [schema-registry]

TASK [confluent.platform.schema_registry : Start Schema Registry Service] ******
changed: [schema-registry]

TASK [confluent.platform.schema_registry : Health Check] ***********************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/schema_registry/tasks/health_check.yml for schema-registry

TASK [confluent.platform.schema_registry : Wait for API to return 200] *********
ok: [schema-registry]

TASK [confluent.platform.schema_registry : set_fact] ***************************
ok: [schema-registry]

TASK [confluent.platform.schema_registry : Wait for API to return 200 - mTLS] ***
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Fetch Files for Debugging Failure] ***
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Fail Provisioning] ******************
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Register Cluster] *******************
skipping: [schema-registry]

TASK [confluent.platform.schema_registry : Delete temporary keys/certs when keystore and trustore is provided] ***
skipping: [schema-registry] => (item=/var/ssl/private/ca.crt) 
skipping: [schema-registry] => (item=/var/ssl/private/schema_registry.crt) 
skipping: [schema-registry] => (item=/var/ssl/private/schema_registry.key) 
skipping: [schema-registry]

TASK [Proceed Prompt] **********************************************************
skipping: [schema-registry]

PLAY [Kafka Connect Status Finding] ********************************************

TASK [Populate service facts] **************************************************
ok: [kafka-connect]

TASK [Determine Installation Pattern - Parallel or Serial] *********************
ok: [kafka-connect]

TASK [Group Hosts by Installation Pattern] *************************************
ok: [kafka-connect]

PLAY [Kafka Connect Parallel Provisioning] *************************************

TASK [include_role : common] ***************************************************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Gather OS Facts] **********************
ok: [kafka-connect] => (item=ansible_os_family)
ok: [kafka-connect] => (item=ansible_fqdn)

TASK [Stop Service and Remove Packages on Version Change] **********************
included: common for kafka-connect

TASK [confluent.platform.common : Get Package Facts] ***************************
ok: [kafka-connect]

TASK [confluent.platform.common : Determine if Confluent Platform Package Version Will Change] ***
ok: [kafka-connect]

TASK [confluent.platform.common : Get installed Confluent Packages] ************
ok: [kafka-connect]

TASK [confluent.platform.common : Determine Confluent Packages to Remove] ******
ok: [kafka-connect]

TASK [confluent.platform.common : Debug Confluent Packages to Remove] **********
skipping: [kafka-connect]

TASK [confluent.platform.common : Get Service Facts] ***************************
ok: [kafka-connect]

TASK [confluent.platform.common : Stop Service before Removing Confluent Packages] ***
skipping: [kafka-connect]

TASK [confluent.platform.common : Remove Confluent Packages - Red Hat] *********
skipping: [kafka-connect]

TASK [confluent.platform.common : Remove Confluent Packages - Debian] **********
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Install the Kafka Connect Packages] ***
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Install the Kafka Connect Packages] ***
changed: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create Kafka Connect Group] ***********
ok: [kafka-connect]

TASK [confluent.platform.kafka_connect : Check if Kafka Connect User Exists] ***
ok: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create Kafka Connect User] ************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Copy Kafka Connect Service from archive file to system] ***
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Copy Kafka Connect Service from default install to system] ***
skipping: [kafka-connect]

TASK [include_role : ssl] ******************************************************
skipping: [kafka-connect]

TASK [Configure Kerberos] ******************************************************
skipping: [kafka-connect]

TASK [Copy Kafka Connect Files] ************************************************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Configure RBAC] ***********************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create Kafka Connect Config directory] ***
changed: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create Kafka Connect Config] **********
changed: [kafka-connect]

TASK [Create Kafka Connect Config with Secrets Protection] *********************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Install Connect Plugins] **************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_connect/tasks/connect_plugins.yml for kafka-connect

TASK [confluent.platform.kafka_connect : Ensure Plugin Dirs] *******************
changed: [kafka-connect] => (item=/usr/share/java/connect_plugins)

TASK [confluent.platform.kafka_connect : set_fact] *****************************
skipping: [kafka-connect]

TASK [Copy Kafka Connect Local Plugins from Controller to Host] ****************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Installing Local Plugins] *************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create tmp directory for downloading remote plugins] ***
changed: [kafka-connect]

TASK [confluent.platform.kafka_connect : Download Remote Plugins] **************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Installing Remote Plugins] ************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Set Permissions on all Plugin Files] ***
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Confluent Hub] ************************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create Logs Directory] ****************
changed: [kafka-connect]

TASK [Update Connect log4j Config for Log Cleanup] *****************************
included: common for kafka-connect

TASK [confluent.platform.common : Replace rootLogger] **************************
ok: [kafka-connect]

TASK [confluent.platform.common : Replace DailyRollingFileAppender with RollingFileAppender] ***
changed: [kafka-connect]

TASK [confluent.platform.common : Remove Key log4j.appender.X.DatePattern] *****
changed: [kafka-connect]

TASK [confluent.platform.common : Register Appenders] **************************
ok: [kafka-connect]

TASK [confluent.platform.common : Add Max Size Properties] *********************
changed: [kafka-connect] => (item=['connectAppender', 'Append=true'])
changed: [kafka-connect] => (item=['connectAppender', 'MaxBackupIndex=10'])
changed: [kafka-connect] => (item=['connectAppender', 'MaxFileSize=100MB'])

TASK [confluent.platform.kafka_connect : Set Permissions on Log4j Conf] ********
changed: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create logredactor rule file directory] ***
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Copy logredactor rule file from control node to component node] ***
skipping: [kafka-connect]

TASK [Configure logredactor] ***************************************************
skipping: [kafka-connect] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'connectAppender'}) 
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Restart kafka connect] ****************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create Kafka Connect Jolokia Config] ***
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Deploy JMX Exporter Config File] ******
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create Basic Auth Jaas File] **********
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create Basic Auth Password File] ******
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Create Service Override Directory] ****
changed: [kafka-connect]

TASK [confluent.platform.kafka_connect : Write Service Overrides] **************
changed: [kafka-connect]

TASK [confluent.platform.kafka_connect : Certs were Updated - Trigger Restart] ***
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : meta] *********************************

RUNNING HANDLER [confluent.platform.kafka_connect : restart connect distributed] ***
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_connect/tasks/restart_and_wait.yml for kafka-connect

RUNNING HANDLER [confluent.platform.kafka_connect : Restart Kafka Connect] *****
changed: [kafka-connect]

RUNNING HANDLER [confluent.platform.kafka_connect : Startup Delay] *************
ok: [kafka-connect]

TASK [confluent.platform.kafka_connect : Start Connect Service] ****************
changed: [kafka-connect]

TASK [confluent.platform.kafka_connect : Health Check] *************************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_connect/tasks/health_check.yml for kafka-connect

TASK [confluent.platform.kafka_connect : Wait for API to return 200] ***********
ok: [kafka-connect]

TASK [confluent.platform.kafka_connect : set_fact] *****************************
ok: [kafka-connect]

TASK [confluent.platform.kafka_connect : Wait for API to return 200 - mTLS] ****
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Fetch Files for Debugging Failure] ****
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Fail Provisioning] ********************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Set parent Cluster] *******************
ok: [kafka-connect]

TASK [confluent.platform.kafka_connect : Register Cluster] *********************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_connect/tasks/register_cluster.yml for kafka-connect

TASK [confluent.platform.common : Get Kafka Cluster ID from Embedded Rest Proxy] ***
skipping: [kafka-connect]

TASK [confluent.platform.common : Parse Kafka Cluster ID from json query] ******
skipping: [kafka-connect]

TASK [confluent.platform.common : Get Kafka Cluster ID from Zookeeper] *********
skipping: [kafka-connect]

TASK [confluent.platform.common : set_fact] ************************************
skipping: [kafka-connect]

TASK [confluent.platform.common : Set kafka_cluster_id Variable] ***************
skipping: [kafka-connect]

TASK [confluent.platform.common : Create SSL Certificate Directory] ************
skipping: [kafka-connect]

TASK [confluent.platform.common : Check if MDS public pem file exists on Ansible Controller] ***
skipping: [kafka-connect]

TASK [confluent.platform.common : Debug] ***************************************
skipping: [kafka-connect]

TASK [confluent.platform.common : Copy in MDS Public Pem File] *****************
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Fetch Kafka Connect Cluster Groups] ***
ok: [kafka-connect] => (item=kafka-connect)

TASK [confluent.platform.kafka_connect : Register Kafka Connect Cluster] *******
skipping: [kafka-connect] => (item=kafka-connect) 
skipping: [kafka-connect] => (item=kafka-connect) 
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Deploy Connectors] ********************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_connect/tasks/deploy_connectors.yml for kafka-connect

TASK [confluent.platform.kafka_connect : Register Kafka Connect Subgroups] *****
ok: [kafka-connect] => (item=kafka-connect)

TASK [confluent.platform.kafka_connect : Add Role Bindings for Connect] ********
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : set_fact] *****************************
ok: [kafka-connect]

TASK [confluent.platform.kafka_connect : Register connector configs and remove deleted connectors for single cluster] ***
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Register connector configs and remove deleted connectors for Multiple Clusters] ***
skipping: [kafka-connect] => (item=kafka_connect_parallel) 
skipping: [kafka-connect] => (item=kafka_connect) 
skipping: [kafka-connect]

TASK [confluent.platform.kafka_connect : Delete temporary keys/certs when keystore and trustore is provided] ***
[WARNING]: Could not match supplied host pattern, ignoring:
kafka_connect_serial
skipping: [kafka-connect] => (item=/var/ssl/private/ca.crt) 
skipping: [kafka-connect] => (item=/var/ssl/private/kafka_connect.crt) 
skipping: [kafka-connect] => (item=/var/ssl/private/kafka_connect.key) 
skipping: [kafka-connect]

PLAY [Kafka Connect Serial Provisioning] ***************************************
skipping: no hosts matched

PLAY [KSQL Status Finding] *****************************************************

TASK [Populate service facts] **************************************************
ok: [ksql-1]

TASK [Determine Installation Pattern - Parallel or Serial] *********************
ok: [ksql-1]

TASK [Group Hosts by Installation Pattern] *************************************
ok: [ksql-1]

PLAY [KSQL Parallel Provisioning] **********************************************

TASK [include_role : common] ***************************************************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Gather OS Facts] *******************************
ok: [ksql-1] => (item=ansible_os_family)
ok: [ksql-1] => (item=ansible_fqdn)

TASK [Stop Service and Remove Packages on Version Change] **********************
included: common for ksql-1

TASK [confluent.platform.common : Get Package Facts] ***************************
ok: [ksql-1]

TASK [confluent.platform.common : Determine if Confluent Platform Package Version Will Change] ***
ok: [ksql-1]

TASK [confluent.platform.common : Get installed Confluent Packages] ************
ok: [ksql-1]

TASK [confluent.platform.common : Determine Confluent Packages to Remove] ******
ok: [ksql-1]

TASK [confluent.platform.common : Debug Confluent Packages to Remove] **********
skipping: [ksql-1]

TASK [confluent.platform.common : Get Service Facts] ***************************
ok: [ksql-1]

TASK [confluent.platform.common : Stop Service before Removing Confluent Packages] ***
skipping: [ksql-1]

TASK [confluent.platform.common : Remove Confluent Packages - Red Hat] *********
skipping: [ksql-1]

TASK [confluent.platform.common : Remove Confluent Packages - Debian] **********
skipping: [ksql-1]

TASK [confluent.platform.ksql : Install the Ksql Packages] *********************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Install the Ksql Packages] *********************
changed: [ksql-1]

TASK [confluent.platform.ksql : Create Ksql Group] *****************************
ok: [ksql-1]

TASK [confluent.platform.ksql : Check if Ksql User Exists] *********************
ok: [ksql-1]

TASK [confluent.platform.ksql : Create Ksql User] ******************************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Set Ksql streams dir permissions] **************
changed: [ksql-1]

TASK [confluent.platform.ksql : Copy Ksql Service from archive file to system] ***
skipping: [ksql-1]

TASK [include_role : ssl] ******************************************************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Import Public Confluent Cloud Certificates Authority Certs into Truststore] ***
skipping: [ksql-1]

TASK [Configure Kerberos] ******************************************************
skipping: [ksql-1]

TASK [Copy Custom KSQL Files] **************************************************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Configure RBAC] ********************************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Create Ksql Config directory] ******************
changed: [ksql-1]

TASK [confluent.platform.ksql : Create Ksql Config] ****************************
changed: [ksql-1]

TASK [Create Ksql Config with Secrets Protection] ******************************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Create Logs Directory] *************************
changed: [ksql-1]

TASK [confluent.platform.ksql : Create log4j Directory] ************************
ok: [ksql-1]

TASK [confluent.platform.ksql : Create Ksql log4j Config] **********************
changed: [ksql-1]

TASK [confluent.platform.ksql : Create logredactor rule file directory] ********
skipping: [ksql-1]

TASK [confluent.platform.ksql : Copy logredactor rule file from control node to component node] ***
skipping: [ksql-1]

TASK [Configure logredactor] ***************************************************
skipping: [ksql-1] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'main'}) 
skipping: [ksql-1]

TASK [confluent.platform.ksql : Restart ksql] **********************************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Create Ksql Jolokia Config] ********************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Create RocksDB Directory] **********************
changed: [ksql-1]

TASK [confluent.platform.ksql : Set Permission to RocksDB Files] ***************
ok: [ksql-1]

TASK [confluent.platform.ksql : Deploy JMX Exporter Config File] ***************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Create Basic Auth Jaas File] *******************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Create Basic Auth Password File] ***************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Create Service Override Directory] *************
changed: [ksql-1]

TASK [confluent.platform.ksql : Write Service Overrides] ***********************
changed: [ksql-1]

TASK [confluent.platform.ksql : Certs were Updated - Trigger Restart] **********
skipping: [ksql-1]

TASK [confluent.platform.ksql : meta] ******************************************

RUNNING HANDLER [confluent.platform.ksql : restart ksql] ***********************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/ksql/tasks/restart_and_wait.yml for ksql-1

RUNNING HANDLER [confluent.platform.ksql : Restart KSQL] ***********************
changed: [ksql-1]

RUNNING HANDLER [confluent.platform.ksql : Startup Delay] **********************
ok: [ksql-1]

TASK [confluent.platform.ksql : Start Ksql Service] ****************************
changed: [ksql-1]

TASK [confluent.platform.ksql : Health Check] **********************************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/ksql/tasks/health_check.yml for ksql-1

TASK [confluent.platform.ksql : Wait for API to return 200] ********************
ok: [ksql-1]

TASK [confluent.platform.ksql : set_fact] **************************************
ok: [ksql-1]

TASK [confluent.platform.ksql : Wait for API to return 200 - mTLS] *************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Fetch Files for Debugging Failure] *************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Fail Provisioning] *****************************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Set parent Cluster] ****************************
ok: [ksql-1]

TASK [confluent.platform.ksql : Register Cluster] ******************************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/ksql/tasks/register_cluster.yml for ksql-1

TASK [confluent.platform.common : Get Kafka Cluster ID from Embedded Rest Proxy] ***
skipping: [ksql-1]

TASK [confluent.platform.common : Parse Kafka Cluster ID from json query] ******
skipping: [ksql-1]

TASK [confluent.platform.common : Get Kafka Cluster ID from Zookeeper] *********
skipping: [ksql-1]

TASK [confluent.platform.common : set_fact] ************************************
skipping: [ksql-1]

TASK [confluent.platform.common : Set kafka_cluster_id Variable] ***************
skipping: [ksql-1]

TASK [confluent.platform.common : Create SSL Certificate Directory] ************
skipping: [ksql-1]

TASK [confluent.platform.common : Check if MDS public pem file exists on Ansible Controller] ***
skipping: [ksql-1]

TASK [confluent.platform.common : Debug] ***************************************
skipping: [ksql-1]

TASK [confluent.platform.common : Copy in MDS Public Pem File] *****************
skipping: [ksql-1]

TASK [confluent.platform.ksql : Fetch KSQL Cluster Groups] *********************
ok: [ksql-1] => (item=ksql-1)

TASK [confluent.platform.ksql : Register KSQL Cluster] *************************
skipping: [ksql-1] => (item=ksql-1) 
skipping: [ksql-1] => (item=ksql-1) 
skipping: [ksql-1]

TASK [confluent.platform.ksql : Delete temporary keys/certs when keystore and trustore is provided] ***
[WARNING]: Could not match supplied host pattern, ignoring: ksql_serial
skipping: [ksql-1] => (item=/var/ssl/private/ca.crt) 
skipping: [ksql-1] => (item=/var/ssl/private/ksql.crt) 
skipping: [ksql-1] => (item=/var/ssl/private/ksql.key) 
skipping: [ksql-1]

PLAY [KSQL Serial Provisioning] ************************************************
skipping: no hosts matched

PLAY [Kafka Rest Status Finding] ***********************************************

TASK [Populate service facts] **************************************************
ok: [kafka-rest]

TASK [Determine Installation Pattern - Parallel or Serial] *********************
ok: [kafka-rest]

TASK [Group Hosts by Installation Pattern] *************************************
ok: [kafka-rest]

PLAY [Kafka Rest Parallel Provisioning] ****************************************

TASK [include_role : common] ***************************************************
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Gather OS Facts] *************************
ok: [kafka-rest] => (item=ansible_os_family)
ok: [kafka-rest] => (item=ansible_fqdn)

TASK [Stop Service and Remove Packages on Version Change] **********************
included: common for kafka-rest

TASK [confluent.platform.common : Get Package Facts] ***************************
ok: [kafka-rest]

TASK [confluent.platform.common : Determine if Confluent Platform Package Version Will Change] ***
ok: [kafka-rest]

TASK [confluent.platform.common : Get installed Confluent Packages] ************
ok: [kafka-rest]

TASK [confluent.platform.common : Determine Confluent Packages to Remove] ******
ok: [kafka-rest]

TASK [confluent.platform.common : Debug Confluent Packages to Remove] **********
skipping: [kafka-rest]

TASK [confluent.platform.common : Get Service Facts] ***************************
ok: [kafka-rest]

TASK [confluent.platform.common : Stop Service before Removing Confluent Packages] ***
skipping: [kafka-rest]

TASK [confluent.platform.common : Remove Confluent Packages - Red Hat] *********
skipping: [kafka-rest]

TASK [confluent.platform.common : Remove Confluent Packages - Debian] **********
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Install the Kafka Rest Packages] *********
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Install the Kafka Rest Packages] *********
changed: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create Kafka Rest Group] *****************
ok: [kafka-rest]

TASK [confluent.platform.kafka_rest : Check if Kafka Rest User Exists] *********
ok: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create Kafka Rest User] ******************
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Copy Kafka Rest Service from archive file to system] ***
skipping: [kafka-rest]

TASK [include_role : ssl] ******************************************************
skipping: [kafka-rest]

TASK [Configure Kerberos] ******************************************************
skipping: [kafka-rest]

TASK [Copy Custom Kafka Rest Files] ********************************************
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Configure RBAC] **************************
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create SSL Certificate Directory] ********
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Check if MDS public pem file exists on Ansible Controller] ***
ok: [kafka-rest -> localhost]

TASK [confluent.platform.kafka_rest : Debug] ***********************************
ok: [kafka-rest] => {
    "msg": "WARNING - The file generated_ssl_files/public.pem doesn't exist on the control node"
}

TASK [confluent.platform.kafka_rest : Copy in MDS Public Pem File] *************
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create Kafka Rest Config directory] ******
changed: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create Kafka Rest Config] ****************
changed: [kafka-rest]

TASK [Create Kafka Rest Config with Secrets Protection] ************************
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create Logs Directory] *******************
changed: [kafka-rest]

TASK [Update log4j Config for Log Cleanup] *************************************
included: common for kafka-rest

TASK [confluent.platform.common : Replace rootLogger] **************************
ok: [kafka-rest]

TASK [confluent.platform.common : Replace DailyRollingFileAppender with RollingFileAppender] ***
ok: [kafka-rest]

TASK [confluent.platform.common : Remove Key log4j.appender.X.DatePattern] *****
ok: [kafka-rest]

TASK [confluent.platform.common : Register Appenders] **************************
ok: [kafka-rest]

TASK [confluent.platform.common : Add Max Size Properties] *********************
changed: [kafka-rest] => (item=['file', 'Append=true'])
changed: [kafka-rest] => (item=['file', 'MaxBackupIndex=10'])
changed: [kafka-rest] => (item=['file', 'MaxFileSize=100MB'])

TASK [confluent.platform.kafka_rest : Set Permissions on Log4j Conf] ***********
changed: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create logredactor rule file directory] ***
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Copy logredactor rule file from control node to component node] ***
skipping: [kafka-rest]

TASK [Configure logredactor] ***************************************************
skipping: [kafka-rest] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'file'}) 
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Restart kafka rest] **********************
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create Kafka Rest Jolokia Config] ********
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Deploy JMX Exporter Config File] *********
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create Basic Auth Jaas File] *************
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create Basic Auth Password File] *********
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Create Service Override Directory] *******
changed: [kafka-rest]

TASK [confluent.platform.kafka_rest : Write Service Overrides] *****************
changed: [kafka-rest]

TASK [confluent.platform.kafka_rest : Certs were Updated - Trigger Restart] ****
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : meta] ************************************

RUNNING HANDLER [confluent.platform.kafka_rest : restart kafka-rest] ***********
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_rest/tasks/restart_and_wait.yml for kafka-rest

RUNNING HANDLER [confluent.platform.kafka_rest : Restart Kafka Rest] ***********
changed: [kafka-rest]

RUNNING HANDLER [confluent.platform.kafka_rest : Startup Delay] ****************
ok: [kafka-rest]

TASK [confluent.platform.kafka_rest : Start Kafka Rest Service] ****************
changed: [kafka-rest]

TASK [confluent.platform.kafka_rest : Health Check] ****************************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_rest/tasks/health_check.yml for kafka-rest

TASK [confluent.platform.kafka_rest : Wait for API to return 200] **************
ok: [kafka-rest]

TASK [confluent.platform.kafka_rest : set_fact] ********************************
ok: [kafka-rest]

TASK [confluent.platform.kafka_rest : Wait for API to return 200 - mTLS] *******
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Fetch Files for Debugging Failure] *******
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Fail Provisioning] ***********************
skipping: [kafka-rest]

TASK [confluent.platform.kafka_rest : Delete temporary keys/certs when keystore and trustore is provided] ***
[WARNING]: Could not match supplied host pattern, ignoring: kafka_rest_serial
skipping: [kafka-rest] => (item=/var/ssl/private/ca.crt) 
skipping: [kafka-rest] => (item=/var/ssl/private/kafka_rest.crt) 
skipping: [kafka-rest] => (item=/var/ssl/private/kafka_rest.key) 
skipping: [kafka-rest]

PLAY [Kafka Rest Serial Provisioning] ******************************************
skipping: no hosts matched

PLAY [Control Center Status Finding] *******************************************

TASK [Populate service facts] **************************************************
ok: [control-center]

TASK [Determine Installation Pattern - Parallel or Serial] *********************
ok: [control-center]

TASK [Group Hosts by Installation Pattern] *************************************
ok: [control-center]

PLAY [Control Center Parallel Provisioning] ************************************

TASK [include_role : common] ***************************************************
skipping: [control-center]

TASK [confluent.platform.control_center : Gather OS Facts] *********************
ok: [control-center] => (item=ansible_os_family)
ok: [control-center] => (item=ansible_fqdn)

TASK [Stop Service and Remove Packages on Version Change] **********************
included: common for control-center

TASK [confluent.platform.common : Get Package Facts] ***************************
ok: [control-center]

TASK [confluent.platform.common : Determine if Confluent Platform Package Version Will Change] ***
ok: [control-center]

TASK [confluent.platform.common : Get installed Confluent Packages] ************
ok: [control-center]

TASK [confluent.platform.common : Determine Confluent Packages to Remove] ******
ok: [control-center]

TASK [confluent.platform.common : Debug Confluent Packages to Remove] **********
skipping: [control-center]

TASK [confluent.platform.common : Get Service Facts] ***************************
ok: [control-center]

TASK [confluent.platform.common : Stop Service before Removing Confluent Packages] ***
skipping: [control-center]

TASK [confluent.platform.common : Remove Confluent Packages - Red Hat] *********
skipping: [control-center]

TASK [confluent.platform.common : Remove Confluent Packages - Debian] **********
skipping: [control-center]

TASK [confluent.platform.control_center : Install the Control Center Packages] ***
skipping: [control-center]

TASK [confluent.platform.control_center : Install the Control Center Packages] ***
changed: [control-center]

TASK [confluent.platform.control_center : Create Control Center Group] *********
ok: [control-center]

TASK [confluent.platform.control_center : Check if Control Center User Exists] ***
ok: [control-center]

TASK [confluent.platform.control_center : Create Control Center User] **********
skipping: [control-center]

TASK [confluent.platform.control_center : Set Control Center Data Dir permissions] ***
ok: [control-center]

TASK [confluent.platform.control_center : Set Control Center Data Dir file permissions] ***
ok: [control-center]

TASK [confluent.platform.control_center : Copy Control Center Service from archive file to system] ***
skipping: [control-center]

TASK [include_role : ssl] ******************************************************
skipping: [control-center]

TASK [Configure Kerberos] ******************************************************
skipping: [control-center]

TASK [Copy Custom Control Center Files] ****************************************
skipping: [control-center]

TASK [confluent.platform.control_center : Configure RBAC] **********************
skipping: [control-center]

TASK [confluent.platform.control_center : Create Control Center Config directory] ***
changed: [control-center]

TASK [confluent.platform.control_center : Create Control Center Config] ********
changed: [control-center]

TASK [Create Control Center Config with Secrets Protection] ********************
skipping: [control-center]

TASK [confluent.platform.control_center : Create Logs Directory] ***************
changed: [control-center]

TASK [Update log4j Config for Log Cleanup] *************************************
included: common for control-center

TASK [confluent.platform.common : Replace rootLogger] **************************
ok: [control-center]

TASK [confluent.platform.common : Replace DailyRollingFileAppender with RollingFileAppender] ***
ok: [control-center]

TASK [confluent.platform.common : Remove Key log4j.appender.X.DatePattern] *****
ok: [control-center]

TASK [confluent.platform.common : Register Appenders] **************************
ok: [control-center]

TASK [confluent.platform.common : Add Max Size Properties] *********************
changed: [control-center] => (item=['main', 'Append=true'])
changed: [control-center] => (item=['main', 'MaxBackupIndex=10'])
changed: [control-center] => (item=['main', 'MaxFileSize=100MB'])
changed: [control-center] => (item=['streams', 'Append=true'])
changed: [control-center] => (item=['streams', 'MaxBackupIndex=10'])
changed: [control-center] => (item=['streams', 'MaxFileSize=100MB'])
changed: [control-center] => (item=['kafka', 'Append=true'])
changed: [control-center] => (item=['kafka', 'MaxBackupIndex=10'])
changed: [control-center] => (item=['kafka', 'MaxFileSize=100MB'])

TASK [confluent.platform.control_center : Set Permissions on Log4j Conf] *******
changed: [control-center]

TASK [confluent.platform.control_center : Create logredactor rule file directory] ***
skipping: [control-center]

TASK [confluent.platform.control_center : Copy logredactor rule file from control node to component node] ***
skipping: [control-center]

TASK [Configure logredactor] ***************************************************
skipping: [control-center] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'main'}) 
skipping: [control-center]

TASK [confluent.platform.control_center : Restart control center] **************
skipping: [control-center]

TASK [confluent.platform.control_center : Create RocksDB Directory] ************
skipping: [control-center]

TASK [confluent.platform.control_center : Set Permission to RocksDB Files] *****
skipping: [control-center]

TASK [confluent.platform.control_center : Create Basic Auth Jaas File] *********
skipping: [control-center]

TASK [confluent.platform.control_center : Create Basic Auth Password File] *****
skipping: [control-center]

TASK [confluent.platform.control_center : Create Service Override Directory] ***
changed: [control-center]

TASK [confluent.platform.control_center : Write Service Overrides] *************
changed: [control-center]

TASK [confluent.platform.control_center : Certs were Updated - Trigger Restart] ***
skipping: [control-center]

TASK [confluent.platform.control_center : meta] ********************************

RUNNING HANDLER [confluent.platform.control_center : restart control center] ***
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/control_center/tasks/restart_and_wait.yml for control-center

RUNNING HANDLER [confluent.platform.control_center : Restart Control Center] ***
changed: [control-center]

RUNNING HANDLER [confluent.platform.control_center : Startup Delay] ************
ok: [control-center]

TASK [confluent.platform.control_center : Start Control Center Service] ********
changed: [control-center]

TASK [confluent.platform.control_center : Health Check] ************************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/control_center/tasks/health_check.yml for control-center

TASK [confluent.platform.control_center : Wait for webpage to serve content] ***
FAILED - RETRYING: [control-center]: Wait for webpage to serve content (40 retries left).
ok: [control-center]

TASK [confluent.platform.control_center : Fetch Files for Debugging Failure] ***
skipping: [control-center]

TASK [confluent.platform.control_center : Fail Provisioning] *******************
skipping: [control-center]

TASK [confluent.platform.control_center : Delete temporary keys/certs when keystore and trustore is provided] ***
[WARNING]: Could not match supplied host pattern, ignoring:
control_center_serial
[WARNING]: Could not match supplied host pattern, ignoring:
kafka_connect_replicator_parallel
[WARNING]: Could not match supplied host pattern, ignoring:
kafka_connect_replicator_serial
skipping: [control-center] => (item=/var/ssl/private/ca.crt) 
skipping: [control-center] => (item=/var/ssl/private/control_center.crt) 
skipping: [control-center] => (item=/var/ssl/private/control_center.key) 
skipping: [control-center]

PLAY [Control Center Serial Provisioning] **************************************
skipping: no hosts matched

PLAY [Kafka Connect Replicator Status Finding] *********************************
skipping: no hosts matched

PLAY [Kafka Connect Replicator Parallel Provisioning] **************************
skipping: no hosts matched

PLAY [Kafka Connect Replicator Serial Provisioning] ****************************
skipping: no hosts matched

PLAY RECAP *********************************************************************
control-center             : ok=59   changed=20   unreachable=0    failed=0    skipped=56   rescued=0    ignored=0   
kafka-broker-1             : ok=68   changed=26   unreachable=0    failed=0    skipped=66   rescued=0    ignored=0   
kafka-connect              : ok=67   changed=24   unreachable=0    failed=0    skipped=78   rescued=0    ignored=0   
kafka-controller-1         : ok=73   changed=30   unreachable=0    failed=0    skipped=56   rescued=0    ignored=0   
kafka-controller-2         : ok=72   changed=29   unreachable=0    failed=0    skipped=55   rescued=0    ignored=0   
kafka-controller-3         : ok=72   changed=29   unreachable=0    failed=0    skipped=55   rescued=0    ignored=0   
kafka-rest                 : ok=60   changed=20   unreachable=0    failed=0    skipped=59   rescued=0    ignored=0   
ksql-1                     : ok=59   changed=21   unreachable=0    failed=0    skipped=68   rescued=0    ignored=0   
schema-registry            : ok=55   changed=20   unreachable=0    failed=0    skipped=59   rescued=0    ignored=0   

Initial Playbook to install Confluent Platform ran successfully. Running Migration Playbook...
Using /home/ubuntu/projects/cp-ansible-docker/ansible.cfg as config file

PLAY [Kafka Controller Migration] **********************************************

TASK [Gathering Facts] *********************************************************
[WARNING]: Platform linux on host kafka-controller-3 is using the discovered
Python interpreter at /usr/bin/python3.8, but future installation of another
Python interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
[WARNING]: Platform linux on host kafka-controller-1 is using the discovered
Python interpreter at /usr/bin/python3.8, but future installation of another
Python interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
[WARNING]: Platform linux on host kafka-broker-1 is using the discovered Python
interpreter at /usr/bin/python3.8, but future installation of another Python
interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
[WARNING]: Platform linux on host kafka-controller-3-migrated is using the
discovered Python interpreter at /usr/bin/python3.8, but future installation of
another Python interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
[WARNING]: Platform linux on host kafka-controller-2 is using the discovered
Python interpreter at /usr/bin/python3.8, but future installation of another
Python interpreter could change the meaning of that path. See
https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
ok: [kafka-controller-3]
ok: [kafka-controller-1]
ok: [kafka-broker-1]
ok: [kafka-controller-3-migrated]
ok: [kafka-controller-2]

TASK [Log Quorum Status and Replica (Before Migration)] ************************
changed: [kafka-controller-1 -> kafka-broker-1(localhost)] => {"changed": true, "cmd": "kafka-metadata-quorum --bootstrap-server kafka-controller-1:9093 describe --status \nkafka-metadata-quorum --bootstrap-server kafka-controller-1:9093 describe --replica \n", "delta": "0:00:03.093764", "end": "2024-10-17 16:28:41.457000", "msg": "", "rc": 0, "start": "2024-10-17 16:28:38.363236", "stderr": "", "stderr_lines": [], "stdout": "ClusterId:              gKP1yNTvTvqf4ICEYzpYsg\nLeaderId:               9991\nLeaderEpoch:            1\nHighWatermark:          3145\nMaxFollowerLag:         0\nMaxFollowerLagTimeMs:   0\nCurrentVoters:          [9991,9992,9993]\nCurrentObservers:       [1]\nNodeId\tLogEndOffset\tLag\tLastFetchTimestamp\tLastCaughtUpTimestamp\tStatus  \t\n9991  \t3148        \t0  \t1729175321104     \t1729175321104        \tLeader  \t\n9992  \t3148        \t0  \t1729175320937     \t1729175320937        \tFollower\t\n9993  \t3148        \t0  \t1729175320937     \t1729175320937        \tFollower\t\n1     \t3148        \t0  \t1729175320936     \t1729175320936        \tObserver\t", "stdout_lines": ["ClusterId:              gKP1yNTvTvqf4ICEYzpYsg", "LeaderId:               9991", "LeaderEpoch:            1", "HighWatermark:          3145", "MaxFollowerLag:         0", "MaxFollowerLagTimeMs:   0", "CurrentVoters:          [9991,9992,9993]", "CurrentObservers:       [1]", "NodeId\tLogEndOffset\tLag\tLastFetchTimestamp\tLastCaughtUpTimestamp\tStatus  \t", "9991  \t3148        \t0  \t1729175321104     \t1729175321104        \tLeader  \t", "9992  \t3148        \t0  \t1729175320937     \t1729175320937        \tFollower\t", "9993  \t3148        \t0  \t1729175320937     \t1729175320937        \tFollower\t", "1     \t3148        \t0  \t1729175320936     \t1729175320936        \tObserver\t"]}

TASK [Save Quorum Status and Replica Before Migration to Localhost in One Task] ***
ok: [kafka-controller-1 -> localhost] => {"changed": false, "checksum": "2d6202089a50f16690cc33273d15c36627d997ee", "dest": "./quorum_status_before_migration.log", "gid": 0, "group": "root", "md5sum": "3766665acb65849ac4f4d7dc9fca31e4", "mode": "0644", "owner": "root", "size": 626, "src": "/home/ubuntu/.ansible/tmp/ansible-tmp-1729175321.515125-427599-20764390217932/.source.log", "state": "file", "uid": 0}
changed: [kafka-controller-3-migrated -> localhost] => {"changed": true, "checksum": "2d6202089a50f16690cc33273d15c36627d997ee", "dest": "./quorum_status_before_migration.log", "gid": 0, "group": "root", "md5sum": "3766665acb65849ac4f4d7dc9fca31e4", "mode": "0644", "owner": "root", "size": 626, "src": "/home/ubuntu/.ansible/tmp/ansible-tmp-1729175321.5508487-427625-164872171186122/.source.log", "state": "file", "uid": 0}
changed: [kafka-controller-2 -> localhost] => {"changed": true, "checksum": "2d6202089a50f16690cc33273d15c36627d997ee", "dest": "./quorum_status_before_migration.log", "gid": 0, "group": "root", "md5sum": "3766665acb65849ac4f4d7dc9fca31e4", "mode": "0644", "owner": "root", "size": 626, "src": "/home/ubuntu/.ansible/tmp/ansible-tmp-1729175321.526543-427600-123892647927359/.source.log", "state": "file", "uid": 0}
ok: [kafka-controller-3 -> localhost] => {"changed": false, "checksum": "2d6202089a50f16690cc33273d15c36627d997ee", "dest": "./quorum_status_before_migration.log", "gid": 0, "group": "root", "md5sum": "3766665acb65849ac4f4d7dc9fca31e4", "mode": "0644", "owner": "root", "size": 626, "src": "/home/ubuntu/.ansible/tmp/ansible-tmp-1729175321.5396357-427611-83298058173772/.source.log", "state": "file", "uid": 0}
ok: [kafka-broker-1 -> localhost] => {"changed": false, "checksum": "2d6202089a50f16690cc33273d15c36627d997ee", "dest": "./quorum_status_before_migration.log", "gid": 0, "group": "root", "md5sum": "3766665acb65849ac4f4d7dc9fca31e4", "mode": "0644", "owner": "root", "size": 626, "src": "/home/ubuntu/.ansible/tmp/ansible-tmp-1729175321.5634086-427635-93820045245909/.source.log", "state": "file", "uid": 0}

TASK [Extract ClusterId from meta.properties on Existing Controller] ***********
ok: [kafka-controller-1] => {"changed": false, "content": "IwojVGh1IE9jdCAxNyAxNjoxMjowMCBDRVNUIDIwMjQKbm9kZS5pZD05OTkxCnZlcnNpb249MQpjbHVzdGVyLmlkPWdLUDF5TlR2VHZxZjRJQ0VZenBZc2cK", "encoding": "base64", "source": "/var/lib/controller/data/meta.properties"}

TASK [Set ClusterId Fact] ******************************************************
ok: [kafka-controller-1] => {"ansible_facts": {"kafka_cluster_id": "gKP1yNTvTvqf4ICEYzpYsg"}, "changed": false}
ok: [kafka-controller-2] => {"ansible_facts": {"kafka_cluster_id": "gKP1yNTvTvqf4ICEYzpYsg"}, "changed": false}
ok: [kafka-controller-3] => {"ansible_facts": {"kafka_cluster_id": "gKP1yNTvTvqf4ICEYzpYsg"}, "changed": false}
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"kafka_cluster_id": "gKP1yNTvTvqf4ICEYzpYsg"}, "changed": false}
ok: [kafka-broker-1] => {"ansible_facts": {"kafka_cluster_id": "gKP1yNTvTvqf4ICEYzpYsg"}, "changed": false}

TASK [Stop Old Controller] *****************************************************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3] => {"changed": true, "name": "confluent-kcontroller", "state": "stopped", "status": {"ActiveEnterTimestamp": "Thu 2024-10-17 16:12:16 CEST", "ActiveEnterTimestampMonotonic": "27305074708", "ActiveExitTimestampMonotonic": "0", "ActiveState": "active", "After": "system.slice basic.target confluent-zookeeper.target network.target systemd-journald.socket sysinit.target", "AllowIsolate": "no", "AllowedCPUs": "", "AllowedMemoryNodes": "", "AmbientCapabilities": "", "AssertResult": "yes", "AssertTimestamp": "Thu 2024-10-17 16:12:16 CEST", "AssertTimestampMonotonic": "27305062583", "Before": "multi-user.target shutdown.target", "BlockIOAccounting": "no", "BlockIOWeight": "[not set]", "CPUAccounting": "no", "CPUAffinity": "", "CPUAffinityFromNUMA": "no", "CPUQuotaPerSecUSec": "infinity", "CPUQuotaPeriodUSec": "infinity", "CPUSchedulingPolicy": "0", "CPUSchedulingPriority": "0", "CPUSchedulingResetOnFork": "no", "CPUShares": "[not set]", "CPUUsageNSec": "[not set]", "CPUWeight": "[not set]", "CacheDirectoryMode": "0755", "CanIsolate": "no", "CanReload": "no", "CanStart": "yes", "CanStop": "yes", "CapabilityBoundingSet": "cap_chown cap_dac_override cap_dac_read_search cap_fowner cap_fsetid cap_kill cap_setgid cap_setuid cap_setpcap cap_linux_immutable cap_net_bind_service cap_net_broadcast cap_net_admin cap_net_raw cap_ipc_lock cap_ipc_owner cap_sys_module cap_sys_rawio cap_sys_chroot cap_sys_ptrace cap_sys_pacct cap_sys_admin cap_sys_boot cap_sys_nice cap_sys_resource cap_sys_time cap_sys_tty_config cap_mknod cap_lease cap_audit_write cap_audit_control cap_setfcap cap_mac_override cap_mac_admin cap_syslog cap_wake_alarm cap_block_suspend cap_audit_read 0x26 0x27 0x28", "CleanResult": "success", "CollectMode": "inactive", "ConditionResult": "yes", "ConditionTimestamp": "Thu 2024-10-17 16:12:16 CEST", "ConditionTimestampMonotonic": "27305062582", "ConfigurationDirectoryMode": "0755", "Conflicts": "shutdown.target", "ControlGroup": "/docker/6c92f17ea009b589e0e1dd61fa43c7e812caa58f6debe94f00a10ce957ebd270/system.slice/confluent-kcontroller.service", "ControlPID": "0", "DefaultDependencies": "yes", "DefaultMemoryLow": "0", "DefaultMemoryMin": "0", "Delegate": "no", "Description": "Apache Kafka - broker", "DevicePolicy": "auto", "Documentation": "http://docs.confluent.io/", "DropInPaths": "/etc/systemd/system/confluent-kcontroller.service.d/override.conf", "DynamicUser": "no", "EffectiveCPUs": "", "EffectiveMemoryNodes": "", "Environment": "[unprintable] KAFKA_LOG4J_OPTS=-Dlog4j.configuration=file:/etc/kafka/log4j.properties LOG_DIR=/var/log/controller", "ExecMainCode": "0", "ExecMainExitTimestampMonotonic": "0", "ExecMainPID": "6587", "ExecMainStartTimestamp": "Thu 2024-10-17 16:12:16 CEST", "ExecMainStartTimestampMonotonic": "27305073634", "ExecMainStatus": "0", "ExecStart": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "ExecStartEx": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; flags= ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "FailureAction": "none", "FileDescriptorStoreMax": "0", "FinalKillSignal": "9", "FragmentPath": "/lib/systemd/system/confluent-kcontroller.service", "GID": "107", "Group": "confluent", "GuessMainPID": "yes", "IOAccounting": "no", "IOReadBytes": "18446744073709551615", "IOReadOperations": "18446744073709551615", "IOSchedulingClass": "0", "IOSchedulingPriority": "0", "IOWeight": "[not set]", "IOWriteBytes": "18446744073709551615", "IOWriteOperations": "18446744073709551615", "IPAccounting": "no", "IPEgressBytes": "[no data]", "IPEgressPackets": "[no data]", "IPIngressBytes": "[no data]", "IPIngressPackets": "[no data]", "Id": "confluent-kcontroller.service", "IgnoreOnIsolate": "no", "IgnoreSIGPIPE": "yes", "InactiveEnterTimestampMonotonic": "0", "InactiveExitTimestamp": "Thu 2024-10-17 16:12:16 CEST", "InactiveExitTimestampMonotonic": "27305074708", "InvocationID": "d883cd98e6214fb989b2c7f68f707673", "JobRunningTimeoutUSec": "infinity", "JobTimeoutAction": "none", "JobTimeoutUSec": "infinity", "KeyringMode": "private", "KillMode": "control-group", "KillSignal": "15", "LimitAS": "infinity", "LimitASSoft": "infinity", "LimitCORE": "infinity", "LimitCORESoft": "infinity", "LimitCPU": "infinity", "LimitCPUSoft": "infinity", "LimitDATA": "infinity", "LimitDATASoft": "infinity", "LimitFSIZE": "infinity", "LimitFSIZESoft": "infinity", "LimitLOCKS": "infinity", "LimitLOCKSSoft": "infinity", "LimitMEMLOCK": "8388608", "LimitMEMLOCKSoft": "8388608", "LimitMSGQUEUE": "819200", "LimitMSGQUEUESoft": "819200", "LimitNICE": "0", "LimitNICESoft": "0", "LimitNOFILE": "1000000", "LimitNOFILESoft": "1000000", "LimitNPROC": "infinity", "LimitNPROCSoft": "infinity", "LimitRSS": "infinity", "LimitRSSSoft": "infinity", "LimitRTPRIO": "0", "LimitRTPRIOSoft": "0", "LimitRTTIME": "infinity", "LimitRTTIMESoft": "infinity", "LimitSIGPENDING": "128316", "LimitSIGPENDINGSoft": "128316", "LimitSTACK": "infinity", "LimitSTACKSoft": "8388608", "LoadState": "loaded", "LockPersonality": "no", "LogLevelMax": "-1", "LogRateLimitBurst": "0", "LogRateLimitIntervalUSec": "0", "LogsDirectoryMode": "0755", "MainPID": "6587", "MemoryAccounting": "yes", "MemoryCurrent": "368009216", "MemoryDenyWriteExecute": "no", "MemoryHigh": "infinity", "MemoryLimit": "infinity", "MemoryLow": "0", "MemoryMax": "infinity", "MemoryMin": "0", "MemorySwapMax": "infinity", "MountAPIVFS": "no", "MountFlags": "", "NFileDescriptorStore": "0", "NRestarts": "0", "NUMAMask": "", "NUMAPolicy": "n/a", "Names": "confluent-kcontroller.service", "NeedDaemonReload": "no", "Nice": "0", "NoNewPrivileges": "no", "NonBlocking": "no", "NotifyAccess": "none", "OOMPolicy": "stop", "OOMScoreAdjust": "0", "OnFailureJobMode": "replace", "Perpetual": "no", "PrivateDevices": "no", "PrivateMounts": "no", "PrivateNetwork": "no", "PrivateTmp": "no", "PrivateUsers": "no", "ProtectControlGroups": "no", "ProtectHome": "no", "ProtectHostname": "no", "ProtectKernelLogs": "no", "ProtectKernelModules": "no", "ProtectKernelTunables": "no", "ProtectSystem": "no", "RefuseManualStart": "no", "RefuseManualStop": "no", "ReloadResult": "success", "RemainAfterExit": "no", "RemoveIPC": "no", "Requires": "system.slice sysinit.target", "Restart": "no", "RestartKillSignal": "15", "RestartUSec": "100ms", "RestrictNamespaces": "no", "RestrictRealtime": "no", "RestrictSUIDSGID": "no", "Result": "success", "RootDirectoryStartOnly": "no", "RuntimeDirectoryMode": "0755", "RuntimeDirectoryPreserve": "no", "RuntimeMaxUSec": "infinity", "SameProcessGroup": "no", "SecureBits": "0", "SendSIGHUP": "no", "SendSIGKILL": "yes", "Slice": "system.slice", "StandardError": "inherit", "StandardInput": "null", "StandardInputData": "", "StandardOutput": "journal", "StartLimitAction": "none", "StartLimitBurst": "5", "StartLimitIntervalUSec": "10s", "StartupBlockIOWeight": "[not set]", "StartupCPUShares": "[not set]", "StartupCPUWeight": "[not set]", "StartupIOWeight": "[not set]", "StateChangeTimestamp": "Thu 2024-10-17 16:12:16 CEST", "StateChangeTimestampMonotonic": "27305074708", "StateDirectoryMode": "0755", "StatusErrno": "0", "StopWhenUnneeded": "no", "SubState": "running", "SuccessAction": "none", "SyslogFacility": "3", "SyslogLevel": "6", "SyslogLevelPrefix": "yes", "SyslogPriority": "30", "SystemCallErrorNumber": "0", "TTYReset": "no", "TTYVHangup": "no", "TTYVTDisallocate": "no", "TasksAccounting": "yes", "TasksCurrent": "82", "TasksMax": "38494", "TimeoutAbortUSec": "3min", "TimeoutCleanUSec": "infinity", "TimeoutStartUSec": "1min 30s", "TimeoutStopUSec": "3min", "TimerSlackNSec": "50000", "Transient": "no", "Type": "simple", "UID": "110", "UMask": "0022", "UnitFilePreset": "enabled", "UnitFileState": "enabled", "User": "cp-kafka", "UtmpMode": "init", "WantedBy": "multi-user.target", "WatchdogSignal": "6", "WatchdogTimestampMonotonic": "0", "WatchdogUSec": "0"}}

TASK [include_role : common] ***************************************************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
included: common for kafka-controller-3-migrated

TASK [confluent.platform.common : Confirm Hash Merging Enabled] ****************
ok: [kafka-controller-3-migrated] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [confluent.platform.common : Verify Ansible version] **********************
ok: [kafka-controller-3-migrated] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [confluent.platform.common : Check the presence of Controller and Zookeeper] ***
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "('zookeeper' in groups.keys() and groups['zookeeper'] | length > 0) | bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Gather OS Facts] *****************************
ok: [kafka-controller-3-migrated]

TASK [confluent.platform.common : Verify Python version] ***********************
ok: [kafka-controller-3-migrated] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [confluent.platform.common : Red Hat Repo Setup and Java Installation] ****
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "ansible_os_family == \"RedHat\"", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Ubuntu Repo Setup and Java Installation] *****
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/common/tasks/ubuntu.yml for kafka-controller-3-migrated

TASK [confluent.platform.common : Install apt-transport-https] *****************
changed: [kafka-controller-3-migrated] => {"attempts": 1, "cache_update_time": 1729175327, "cache_updated": false, "changed": true, "stderr": "debconf: delaying package configuration, since apt-utils is not installed\n", "stderr_lines": ["debconf: delaying package configuration, since apt-utils is not installed"], "stdout": "Reading package lists...\nBuilding dependency tree...\nReading state information...\nThe following NEW packages will be installed:\n  apt-transport-https\n0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.\nNeed to get 1704 B of archives.\nAfter this operation, 162 kB of additional disk space will be used.\nGet:1 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 apt-transport-https all 2.0.10 [1704 B]\nFetched 1704 B in 0s (54.9 kB/s)\nSelecting previously unselected package apt-transport-https.\r\n(Reading database ... \r(Reading database ... 5%\r(Reading database ... 10%\r(Reading database ... 15%\r(Reading database ... 20%\r(Reading database ... 25%\r(Reading database ... 30%\r(Reading database ... 35%\r(Reading database ... 40%\r(Reading database ... 45%\r(Reading database ... 50%\r(Reading database ... 55%\r(Reading database ... 60%\r(Reading database ... 65%\r(Reading database ... 70%\r(Reading database ... 75%\r(Reading database ... 80%\r(Reading database ... 85%\r(Reading database ... 90%\r(Reading database ... 95%\r(Reading database ... 100%\r(Reading database ... 15577 files and directories currently installed.)\r\nPreparing to unpack .../apt-transport-https_2.0.10_all.deb ...\r\nUnpacking apt-transport-https (2.0.10) ...\r\nSetting up apt-transport-https (2.0.10) ...\r\n", "stdout_lines": ["Reading package lists...", "Building dependency tree...", "Reading state information...", "The following NEW packages will be installed:", "  apt-transport-https", "0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.", "Need to get 1704 B of archives.", "After this operation, 162 kB of additional disk space will be used.", "Get:1 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 apt-transport-https all 2.0.10 [1704 B]", "Fetched 1704 B in 0s (54.9 kB/s)", "Selecting previously unselected package apt-transport-https.", "(Reading database ... ", "(Reading database ... 5%", "(Reading database ... 10%", "(Reading database ... 15%", "(Reading database ... 20%", "(Reading database ... 25%", "(Reading database ... 30%", "(Reading database ... 35%", "(Reading database ... 40%", "(Reading database ... 45%", "(Reading database ... 50%", "(Reading database ... 55%", "(Reading database ... 60%", "(Reading database ... 65%", "(Reading database ... 70%", "(Reading database ... 75%", "(Reading database ... 80%", "(Reading database ... 85%", "(Reading database ... 90%", "(Reading database ... 95%", "(Reading database ... 100%", "(Reading database ... 15577 files and directories currently installed.)", "Preparing to unpack .../apt-transport-https_2.0.10_all.deb ...", "Unpacking apt-transport-https (2.0.10) ...", "Setting up apt-transport-https (2.0.10) ..."]}

TASK [confluent.platform.common : Install gnupg for gpg-keys] ******************
changed: [kafka-controller-3-migrated] => {"attempts": 1, "cache_update_time": 1729175327, "cache_updated": false, "changed": true, "stderr": "debconf: delaying package configuration, since apt-utils is not installed\n", "stderr_lines": ["debconf: delaying package configuration, since apt-utils is not installed"], "stdout": "Reading package lists...\nBuilding dependency tree...\nReading state information...\nThe following additional packages will be installed:\n  dirmngr gnupg gnupg-l10n gnupg-utils gpg gpg-agent gpg-wks-client\n  gpg-wks-server gpgconf gpgsm libasn1-8-heimdal libassuan0 libgssapi3-heimdal\n  libhcrypto4-heimdal libheimbase1-heimdal libheimntlm0-heimdal\n  libhx509-5-heimdal libkrb5-26-heimdal libksba8 libldap-2.4-2 libldap-common\n  libnpth0 libroken18-heimdal libsasl2-2 libsasl2-modules libsasl2-modules-db\n  libwind0-heimdal pinentry-curses\nSuggested packages:\n  dbus-user-session pinentry-gnome3 tor parcimonie xloadimage scdaemon\n  libsasl2-modules-gssapi-mit | libsasl2-modules-gssapi-heimdal\n  libsasl2-modules-ldap libsasl2-modules-otp libsasl2-modules-sql pinentry-doc\nThe following NEW packages will be installed:\n  dirmngr gnupg gnupg-l10n gnupg-utils gnupg2 gpg gpg-agent gpg-wks-client\n  gpg-wks-server gpgconf gpgsm libasn1-8-heimdal libassuan0 libgssapi3-heimdal\n  libhcrypto4-heimdal libheimbase1-heimdal libheimntlm0-heimdal\n  libhx509-5-heimdal libkrb5-26-heimdal libksba8 libldap-2.4-2 libldap-common\n  libnpth0 libroken18-heimdal libsasl2-2 libsasl2-modules libsasl2-modules-db\n  libwind0-heimdal pinentry-curses\n0 upgraded, 29 newly installed, 0 to remove and 0 not upgraded.\nNeed to get 3642 kB of archives.\nAfter this operation, 11.7 MB of additional disk space will be used.\nGet:1 http://archive.ubuntu.com/ubuntu focal/main amd64 libassuan0 amd64 2.5.3-7ubuntu2 [35.7 kB]\nGet:2 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpgconf amd64 2.2.19-3ubuntu2.2 [124 kB]\nGet:3 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libksba8 amd64 1.3.5-2ubuntu0.20.04.2 [95.2 kB]\nGet:4 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libroken18-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [42.5 kB]\nGet:5 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libasn1-8-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [181 kB]\nGet:6 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libheimbase1-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [30.4 kB]\nGet:7 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libhcrypto4-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [88.1 kB]\nGet:8 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libwind0-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [47.7 kB]\nGet:9 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libhx509-5-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [107 kB]\nGet:10 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libkrb5-26-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [207 kB]\nGet:11 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libheimntlm0-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [15.1 kB]\nGet:12 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgssapi3-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [96.5 kB]\nGet:13 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libsasl2-modules-db amd64 2.1.27+dfsg-2ubuntu0.1 [14.7 kB]\nGet:14 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libsasl2-2 amd64 2.1.27+dfsg-2ubuntu0.1 [49.3 kB]\nGet:15 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libldap-common all 2.4.49+dfsg-2ubuntu1.10 [16.5 kB]\nGet:16 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libldap-2.4-2 amd64 2.4.49+dfsg-2ubuntu1.10 [155 kB]\nGet:17 http://archive.ubuntu.com/ubuntu focal/main amd64 libnpth0 amd64 1.6-1 [7736 B]\nGet:18 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 dirmngr amd64 2.2.19-3ubuntu2.2 [330 kB]\nGet:19 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gnupg-l10n all 2.2.19-3ubuntu2.2 [51.7 kB]\nGet:20 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gnupg-utils amd64 2.2.19-3ubuntu2.2 [481 kB]\nGet:21 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpg amd64 2.2.19-3ubuntu2.2 [482 kB]\nGet:22 http://archive.ubuntu.com/ubuntu focal/main amd64 pinentry-curses amd64 1.1.0-3build1 [36.3 kB]\nGet:23 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpg-agent amd64 2.2.19-3ubuntu2.2 [232 kB]\nGet:24 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpg-wks-client amd64 2.2.19-3ubuntu2.2 [97.4 kB]\nGet:25 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpg-wks-server amd64 2.2.19-3ubuntu2.2 [90.2 kB]\nGet:26 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpgsm amd64 2.2.19-3ubuntu2.2 [217 kB]\nGet:27 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gnupg all 2.2.19-3ubuntu2.2 [259 kB]\nGet:28 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libsasl2-modules amd64 2.1.27+dfsg-2ubuntu0.1 [48.8 kB]\nGet:29 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 gnupg2 all 2.2.19-3ubuntu2.2 [5316 B]\nFetched 3642 kB in 1s (3531 kB/s)\nSelecting previously unselected package libassuan0:amd64.\r\n(Reading database ... \r(Reading database ... 5%\r(Reading database ... 10%\r(Reading database ... 15%\r(Reading database ... 20%\r(Reading database ... 25%\r(Reading database ... 30%\r(Reading database ... 35%\r(Reading database ... 40%\r(Reading database ... 45%\r(Reading database ... 50%\r(Reading database ... 55%\r(Reading database ... 60%\r(Reading database ... 65%\r(Reading database ... 70%\r(Reading database ... 75%\r(Reading database ... 80%\r(Reading database ... 85%\r(Reading database ... 90%\r(Reading database ... 95%\r(Reading database ... 100%\r(Reading database ... 15581 files and directories currently installed.)\r\nPreparing to unpack .../00-libassuan0_2.5.3-7ubuntu2_amd64.deb ...\r\nUnpacking libassuan0:amd64 (2.5.3-7ubuntu2) ...\r\nSelecting previously unselected package gpgconf.\r\nPreparing to unpack .../01-gpgconf_2.2.19-3ubuntu2.2_amd64.deb ...\r\nUnpacking gpgconf (2.2.19-3ubuntu2.2) ...\r\nSelecting previously unselected package libksba8:amd64.\r\nPreparing to unpack .../02-libksba8_1.3.5-2ubuntu0.20.04.2_amd64.deb ...\r\nUnpacking libksba8:amd64 (1.3.5-2ubuntu0.20.04.2) ...\r\nSelecting previously unselected package libroken18-heimdal:amd64.\r\nPreparing to unpack .../03-libroken18-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...\r\nUnpacking libroken18-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSelecting previously unselected package libasn1-8-heimdal:amd64.\r\nPreparing to unpack .../04-libasn1-8-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...\r\nUnpacking libasn1-8-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSelecting previously unselected package libheimbase1-heimdal:amd64.\r\nPreparing to unpack .../05-libheimbase1-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...\r\nUnpacking libheimbase1-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSelecting previously unselected package libhcrypto4-heimdal:amd64.\r\nPreparing to unpack .../06-libhcrypto4-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...\r\nUnpacking libhcrypto4-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSelecting previously unselected package libwind0-heimdal:amd64.\r\nPreparing to unpack .../07-libwind0-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...\r\nUnpacking libwind0-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSelecting previously unselected package libhx509-5-heimdal:amd64.\r\nPreparing to unpack .../08-libhx509-5-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...\r\nUnpacking libhx509-5-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSelecting previously unselected package libkrb5-26-heimdal:amd64.\r\nPreparing to unpack .../09-libkrb5-26-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...\r\nUnpacking libkrb5-26-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSelecting previously unselected package libheimntlm0-heimdal:amd64.\r\nPreparing to unpack .../10-libheimntlm0-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...\r\nUnpacking libheimntlm0-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSelecting previously unselected package libgssapi3-heimdal:amd64.\r\nPreparing to unpack .../11-libgssapi3-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...\r\nUnpacking libgssapi3-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSelecting previously unselected package libsasl2-modules-db:amd64.\r\nPreparing to unpack .../12-libsasl2-modules-db_2.1.27+dfsg-2ubuntu0.1_amd64.deb ...\r\nUnpacking libsasl2-modules-db:amd64 (2.1.27+dfsg-2ubuntu0.1) ...\r\nSelecting previously unselected package libsasl2-2:amd64.\r\nPreparing to unpack .../13-libsasl2-2_2.1.27+dfsg-2ubuntu0.1_amd64.deb ...\r\nUnpacking libsasl2-2:amd64 (2.1.27+dfsg-2ubuntu0.1) ...\r\nSelecting previously unselected package libldap-common.\r\nPreparing to unpack .../14-libldap-common_2.4.49+dfsg-2ubuntu1.10_all.deb ...\r\nUnpacking libldap-common (2.4.49+dfsg-2ubuntu1.10) ...\r\nSelecting previously unselected package libldap-2.4-2:amd64.\r\nPreparing to unpack .../15-libldap-2.4-2_2.4.49+dfsg-2ubuntu1.10_amd64.deb ...\r\nUnpacking libldap-2.4-2:amd64 (2.4.49+dfsg-2ubuntu1.10) ...\r\nSelecting previously unselected package libnpth0:amd64.\r\nPreparing to unpack .../16-libnpth0_1.6-1_amd64.deb ...\r\nUnpacking libnpth0:amd64 (1.6-1) ...\r\nSelecting previously unselected package dirmngr.\r\nPreparing to unpack .../17-dirmngr_2.2.19-3ubuntu2.2_amd64.deb ...\r\nUnpacking dirmngr (2.2.19-3ubuntu2.2) ...\r\nSelecting previously unselected package gnupg-l10n.\r\nPreparing to unpack .../18-gnupg-l10n_2.2.19-3ubuntu2.2_all.deb ...\r\nUnpacking gnupg-l10n (2.2.19-3ubuntu2.2) ...\r\nSelecting previously unselected package gnupg-utils.\r\nPreparing to unpack .../19-gnupg-utils_2.2.19-3ubuntu2.2_amd64.deb ...\r\nUnpacking gnupg-utils (2.2.19-3ubuntu2.2) ...\r\nSelecting previously unselected package gpg.\r\nPreparing to unpack .../20-gpg_2.2.19-3ubuntu2.2_amd64.deb ...\r\nUnpacking gpg (2.2.19-3ubuntu2.2) ...\r\nSelecting previously unselected package pinentry-curses.\r\nPreparing to unpack .../21-pinentry-curses_1.1.0-3build1_amd64.deb ...\r\nUnpacking pinentry-curses (1.1.0-3build1) ...\r\nSelecting previously unselected package gpg-agent.\r\nPreparing to unpack .../22-gpg-agent_2.2.19-3ubuntu2.2_amd64.deb ...\r\nUnpacking gpg-agent (2.2.19-3ubuntu2.2) ...\r\nSelecting previously unselected package gpg-wks-client.\r\nPreparing to unpack .../23-gpg-wks-client_2.2.19-3ubuntu2.2_amd64.deb ...\r\nUnpacking gpg-wks-client (2.2.19-3ubuntu2.2) ...\r\nSelecting previously unselected package gpg-wks-server.\r\nPreparing to unpack .../24-gpg-wks-server_2.2.19-3ubuntu2.2_amd64.deb ...\r\nUnpacking gpg-wks-server (2.2.19-3ubuntu2.2) ...\r\nSelecting previously unselected package gpgsm.\r\nPreparing to unpack .../25-gpgsm_2.2.19-3ubuntu2.2_amd64.deb ...\r\nUnpacking gpgsm (2.2.19-3ubuntu2.2) ...\r\nSelecting previously unselected package gnupg.\r\nPreparing to unpack .../26-gnupg_2.2.19-3ubuntu2.2_all.deb ...\r\nUnpacking gnupg (2.2.19-3ubuntu2.2) ...\r\nSelecting previously unselected package libsasl2-modules:amd64.\r\nPreparing to unpack .../27-libsasl2-modules_2.1.27+dfsg-2ubuntu0.1_amd64.deb ...\r\nUnpacking libsasl2-modules:amd64 (2.1.27+dfsg-2ubuntu0.1) ...\r\nSelecting previously unselected package gnupg2.\r\nPreparing to unpack .../28-gnupg2_2.2.19-3ubuntu2.2_all.deb ...\r\nUnpacking gnupg2 (2.2.19-3ubuntu2.2) ...\r\nSetting up libksba8:amd64 (1.3.5-2ubuntu0.20.04.2) ...\r\nSetting up libsasl2-modules:amd64 (2.1.27+dfsg-2ubuntu0.1) ...\r\nSetting up libnpth0:amd64 (1.6-1) ...\r\nSetting up libassuan0:amd64 (2.5.3-7ubuntu2) ...\r\nSetting up libldap-common (2.4.49+dfsg-2ubuntu1.10) ...\r\nSetting up libsasl2-modules-db:amd64 (2.1.27+dfsg-2ubuntu0.1) ...\r\nSetting up gnupg-l10n (2.2.19-3ubuntu2.2) ...\r\nSetting up libsasl2-2:amd64 (2.1.27+dfsg-2ubuntu0.1) ...\r\nSetting up libroken18-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSetting up gpgconf (2.2.19-3ubuntu2.2) ...\r\nSetting up gpg (2.2.19-3ubuntu2.2) ...\r\nSetting up libheimbase1-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSetting up gnupg-utils (2.2.19-3ubuntu2.2) ...\r\nSetting up pinentry-curses (1.1.0-3build1) ...\r\nSetting up gpg-agent (2.2.19-3ubuntu2.2) ...\r\nCreated symlink /etc/systemd/user/sockets.target.wants/gpg-agent-browser.socket → /usr/lib/systemd/user/gpg-agent-browser.socket.\r\nCreated symlink /etc/systemd/user/sockets.target.wants/gpg-agent-extra.socket → /usr/lib/systemd/user/gpg-agent-extra.socket.\r\nCreated symlink /etc/systemd/user/sockets.target.wants/gpg-agent-ssh.socket → /usr/lib/systemd/user/gpg-agent-ssh.socket.\r\nCreated symlink /etc/systemd/user/sockets.target.wants/gpg-agent.socket → /usr/lib/systemd/user/gpg-agent.socket.\r\nSetting up libasn1-8-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSetting up gpgsm (2.2.19-3ubuntu2.2) ...\r\nSetting up libhcrypto4-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSetting up libwind0-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSetting up gpg-wks-server (2.2.19-3ubuntu2.2) ...\r\nSetting up libhx509-5-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSetting up libkrb5-26-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSetting up libheimntlm0-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSetting up libgssapi3-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...\r\nSetting up libldap-2.4-2:amd64 (2.4.49+dfsg-2ubuntu1.10) ...\r\nSetting up dirmngr (2.2.19-3ubuntu2.2) ...\r\nCreated symlink /etc/systemd/user/sockets.target.wants/dirmngr.socket → /usr/lib/systemd/user/dirmngr.socket.\r\nSetting up gpg-wks-client (2.2.19-3ubuntu2.2) ...\r\nSetting up gnupg (2.2.19-3ubuntu2.2) ...\r\nSetting up gnupg2 (2.2.19-3ubuntu2.2) ...\r\nProcessing triggers for libc-bin (2.31-0ubuntu9.16) ...\r\n", "stdout_lines": ["Reading package lists...", "Building dependency tree...", "Reading state information...", "The following additional packages will be installed:", "  dirmngr gnupg gnupg-l10n gnupg-utils gpg gpg-agent gpg-wks-client", "  gpg-wks-server gpgconf gpgsm libasn1-8-heimdal libassuan0 libgssapi3-heimdal", "  libhcrypto4-heimdal libheimbase1-heimdal libheimntlm0-heimdal", "  libhx509-5-heimdal libkrb5-26-heimdal libksba8 libldap-2.4-2 libldap-common", "  libnpth0 libroken18-heimdal libsasl2-2 libsasl2-modules libsasl2-modules-db", "  libwind0-heimdal pinentry-curses", "Suggested packages:", "  dbus-user-session pinentry-gnome3 tor parcimonie xloadimage scdaemon", "  libsasl2-modules-gssapi-mit | libsasl2-modules-gssapi-heimdal", "  libsasl2-modules-ldap libsasl2-modules-otp libsasl2-modules-sql pinentry-doc", "The following NEW packages will be installed:", "  dirmngr gnupg gnupg-l10n gnupg-utils gnupg2 gpg gpg-agent gpg-wks-client", "  gpg-wks-server gpgconf gpgsm libasn1-8-heimdal libassuan0 libgssapi3-heimdal", "  libhcrypto4-heimdal libheimbase1-heimdal libheimntlm0-heimdal", "  libhx509-5-heimdal libkrb5-26-heimdal libksba8 libldap-2.4-2 libldap-common", "  libnpth0 libroken18-heimdal libsasl2-2 libsasl2-modules libsasl2-modules-db", "  libwind0-heimdal pinentry-curses", "0 upgraded, 29 newly installed, 0 to remove and 0 not upgraded.", "Need to get 3642 kB of archives.", "After this operation, 11.7 MB of additional disk space will be used.", "Get:1 http://archive.ubuntu.com/ubuntu focal/main amd64 libassuan0 amd64 2.5.3-7ubuntu2 [35.7 kB]", "Get:2 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpgconf amd64 2.2.19-3ubuntu2.2 [124 kB]", "Get:3 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libksba8 amd64 1.3.5-2ubuntu0.20.04.2 [95.2 kB]", "Get:4 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libroken18-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [42.5 kB]", "Get:5 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libasn1-8-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [181 kB]", "Get:6 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libheimbase1-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [30.4 kB]", "Get:7 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libhcrypto4-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [88.1 kB]", "Get:8 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libwind0-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [47.7 kB]", "Get:9 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libhx509-5-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [107 kB]", "Get:10 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libkrb5-26-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [207 kB]", "Get:11 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libheimntlm0-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [15.1 kB]", "Get:12 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgssapi3-heimdal amd64 7.7.0+dfsg-1ubuntu1.4 [96.5 kB]", "Get:13 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libsasl2-modules-db amd64 2.1.27+dfsg-2ubuntu0.1 [14.7 kB]", "Get:14 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libsasl2-2 amd64 2.1.27+dfsg-2ubuntu0.1 [49.3 kB]", "Get:15 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libldap-common all 2.4.49+dfsg-2ubuntu1.10 [16.5 kB]", "Get:16 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libldap-2.4-2 amd64 2.4.49+dfsg-2ubuntu1.10 [155 kB]", "Get:17 http://archive.ubuntu.com/ubuntu focal/main amd64 libnpth0 amd64 1.6-1 [7736 B]", "Get:18 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 dirmngr amd64 2.2.19-3ubuntu2.2 [330 kB]", "Get:19 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gnupg-l10n all 2.2.19-3ubuntu2.2 [51.7 kB]", "Get:20 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gnupg-utils amd64 2.2.19-3ubuntu2.2 [481 kB]", "Get:21 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpg amd64 2.2.19-3ubuntu2.2 [482 kB]", "Get:22 http://archive.ubuntu.com/ubuntu focal/main amd64 pinentry-curses amd64 1.1.0-3build1 [36.3 kB]", "Get:23 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpg-agent amd64 2.2.19-3ubuntu2.2 [232 kB]", "Get:24 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpg-wks-client amd64 2.2.19-3ubuntu2.2 [97.4 kB]", "Get:25 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpg-wks-server amd64 2.2.19-3ubuntu2.2 [90.2 kB]", "Get:26 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gpgsm amd64 2.2.19-3ubuntu2.2 [217 kB]", "Get:27 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gnupg all 2.2.19-3ubuntu2.2 [259 kB]", "Get:28 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libsasl2-modules amd64 2.1.27+dfsg-2ubuntu0.1 [48.8 kB]", "Get:29 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 gnupg2 all 2.2.19-3ubuntu2.2 [5316 B]", "Fetched 3642 kB in 1s (3531 kB/s)", "Selecting previously unselected package libassuan0:amd64.", "(Reading database ... ", "(Reading database ... 5%", "(Reading database ... 10%", "(Reading database ... 15%", "(Reading database ... 20%", "(Reading database ... 25%", "(Reading database ... 30%", "(Reading database ... 35%", "(Reading database ... 40%", "(Reading database ... 45%", "(Reading database ... 50%", "(Reading database ... 55%", "(Reading database ... 60%", "(Reading database ... 65%", "(Reading database ... 70%", "(Reading database ... 75%", "(Reading database ... 80%", "(Reading database ... 85%", "(Reading database ... 90%", "(Reading database ... 95%", "(Reading database ... 100%", "(Reading database ... 15581 files and directories currently installed.)", "Preparing to unpack .../00-libassuan0_2.5.3-7ubuntu2_amd64.deb ...", "Unpacking libassuan0:amd64 (2.5.3-7ubuntu2) ...", "Selecting previously unselected package gpgconf.", "Preparing to unpack .../01-gpgconf_2.2.19-3ubuntu2.2_amd64.deb ...", "Unpacking gpgconf (2.2.19-3ubuntu2.2) ...", "Selecting previously unselected package libksba8:amd64.", "Preparing to unpack .../02-libksba8_1.3.5-2ubuntu0.20.04.2_amd64.deb ...", "Unpacking libksba8:amd64 (1.3.5-2ubuntu0.20.04.2) ...", "Selecting previously unselected package libroken18-heimdal:amd64.", "Preparing to unpack .../03-libroken18-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...", "Unpacking libroken18-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Selecting previously unselected package libasn1-8-heimdal:amd64.", "Preparing to unpack .../04-libasn1-8-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...", "Unpacking libasn1-8-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Selecting previously unselected package libheimbase1-heimdal:amd64.", "Preparing to unpack .../05-libheimbase1-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...", "Unpacking libheimbase1-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Selecting previously unselected package libhcrypto4-heimdal:amd64.", "Preparing to unpack .../06-libhcrypto4-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...", "Unpacking libhcrypto4-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Selecting previously unselected package libwind0-heimdal:amd64.", "Preparing to unpack .../07-libwind0-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...", "Unpacking libwind0-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Selecting previously unselected package libhx509-5-heimdal:amd64.", "Preparing to unpack .../08-libhx509-5-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...", "Unpacking libhx509-5-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Selecting previously unselected package libkrb5-26-heimdal:amd64.", "Preparing to unpack .../09-libkrb5-26-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...", "Unpacking libkrb5-26-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Selecting previously unselected package libheimntlm0-heimdal:amd64.", "Preparing to unpack .../10-libheimntlm0-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...", "Unpacking libheimntlm0-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Selecting previously unselected package libgssapi3-heimdal:amd64.", "Preparing to unpack .../11-libgssapi3-heimdal_7.7.0+dfsg-1ubuntu1.4_amd64.deb ...", "Unpacking libgssapi3-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Selecting previously unselected package libsasl2-modules-db:amd64.", "Preparing to unpack .../12-libsasl2-modules-db_2.1.27+dfsg-2ubuntu0.1_amd64.deb ...", "Unpacking libsasl2-modules-db:amd64 (2.1.27+dfsg-2ubuntu0.1) ...", "Selecting previously unselected package libsasl2-2:amd64.", "Preparing to unpack .../13-libsasl2-2_2.1.27+dfsg-2ubuntu0.1_amd64.deb ...", "Unpacking libsasl2-2:amd64 (2.1.27+dfsg-2ubuntu0.1) ...", "Selecting previously unselected package libldap-common.", "Preparing to unpack .../14-libldap-common_2.4.49+dfsg-2ubuntu1.10_all.deb ...", "Unpacking libldap-common (2.4.49+dfsg-2ubuntu1.10) ...", "Selecting previously unselected package libldap-2.4-2:amd64.", "Preparing to unpack .../15-libldap-2.4-2_2.4.49+dfsg-2ubuntu1.10_amd64.deb ...", "Unpacking libldap-2.4-2:amd64 (2.4.49+dfsg-2ubuntu1.10) ...", "Selecting previously unselected package libnpth0:amd64.", "Preparing to unpack .../16-libnpth0_1.6-1_amd64.deb ...", "Unpacking libnpth0:amd64 (1.6-1) ...", "Selecting previously unselected package dirmngr.", "Preparing to unpack .../17-dirmngr_2.2.19-3ubuntu2.2_amd64.deb ...", "Unpacking dirmngr (2.2.19-3ubuntu2.2) ...", "Selecting previously unselected package gnupg-l10n.", "Preparing to unpack .../18-gnupg-l10n_2.2.19-3ubuntu2.2_all.deb ...", "Unpacking gnupg-l10n (2.2.19-3ubuntu2.2) ...", "Selecting previously unselected package gnupg-utils.", "Preparing to unpack .../19-gnupg-utils_2.2.19-3ubuntu2.2_amd64.deb ...", "Unpacking gnupg-utils (2.2.19-3ubuntu2.2) ...", "Selecting previously unselected package gpg.", "Preparing to unpack .../20-gpg_2.2.19-3ubuntu2.2_amd64.deb ...", "Unpacking gpg (2.2.19-3ubuntu2.2) ...", "Selecting previously unselected package pinentry-curses.", "Preparing to unpack .../21-pinentry-curses_1.1.0-3build1_amd64.deb ...", "Unpacking pinentry-curses (1.1.0-3build1) ...", "Selecting previously unselected package gpg-agent.", "Preparing to unpack .../22-gpg-agent_2.2.19-3ubuntu2.2_amd64.deb ...", "Unpacking gpg-agent (2.2.19-3ubuntu2.2) ...", "Selecting previously unselected package gpg-wks-client.", "Preparing to unpack .../23-gpg-wks-client_2.2.19-3ubuntu2.2_amd64.deb ...", "Unpacking gpg-wks-client (2.2.19-3ubuntu2.2) ...", "Selecting previously unselected package gpg-wks-server.", "Preparing to unpack .../24-gpg-wks-server_2.2.19-3ubuntu2.2_amd64.deb ...", "Unpacking gpg-wks-server (2.2.19-3ubuntu2.2) ...", "Selecting previously unselected package gpgsm.", "Preparing to unpack .../25-gpgsm_2.2.19-3ubuntu2.2_amd64.deb ...", "Unpacking gpgsm (2.2.19-3ubuntu2.2) ...", "Selecting previously unselected package gnupg.", "Preparing to unpack .../26-gnupg_2.2.19-3ubuntu2.2_all.deb ...", "Unpacking gnupg (2.2.19-3ubuntu2.2) ...", "Selecting previously unselected package libsasl2-modules:amd64.", "Preparing to unpack .../27-libsasl2-modules_2.1.27+dfsg-2ubuntu0.1_amd64.deb ...", "Unpacking libsasl2-modules:amd64 (2.1.27+dfsg-2ubuntu0.1) ...", "Selecting previously unselected package gnupg2.", "Preparing to unpack .../28-gnupg2_2.2.19-3ubuntu2.2_all.deb ...", "Unpacking gnupg2 (2.2.19-3ubuntu2.2) ...", "Setting up libksba8:amd64 (1.3.5-2ubuntu0.20.04.2) ...", "Setting up libsasl2-modules:amd64 (2.1.27+dfsg-2ubuntu0.1) ...", "Setting up libnpth0:amd64 (1.6-1) ...", "Setting up libassuan0:amd64 (2.5.3-7ubuntu2) ...", "Setting up libldap-common (2.4.49+dfsg-2ubuntu1.10) ...", "Setting up libsasl2-modules-db:amd64 (2.1.27+dfsg-2ubuntu0.1) ...", "Setting up gnupg-l10n (2.2.19-3ubuntu2.2) ...", "Setting up libsasl2-2:amd64 (2.1.27+dfsg-2ubuntu0.1) ...", "Setting up libroken18-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Setting up gpgconf (2.2.19-3ubuntu2.2) ...", "Setting up gpg (2.2.19-3ubuntu2.2) ...", "Setting up libheimbase1-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Setting up gnupg-utils (2.2.19-3ubuntu2.2) ...", "Setting up pinentry-curses (1.1.0-3build1) ...", "Setting up gpg-agent (2.2.19-3ubuntu2.2) ...", "Created symlink /etc/systemd/user/sockets.target.wants/gpg-agent-browser.socket → /usr/lib/systemd/user/gpg-agent-browser.socket.", "Created symlink /etc/systemd/user/sockets.target.wants/gpg-agent-extra.socket → /usr/lib/systemd/user/gpg-agent-extra.socket.", "Created symlink /etc/systemd/user/sockets.target.wants/gpg-agent-ssh.socket → /usr/lib/systemd/user/gpg-agent-ssh.socket.", "Created symlink /etc/systemd/user/sockets.target.wants/gpg-agent.socket → /usr/lib/systemd/user/gpg-agent.socket.", "Setting up libasn1-8-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Setting up gpgsm (2.2.19-3ubuntu2.2) ...", "Setting up libhcrypto4-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Setting up libwind0-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Setting up gpg-wks-server (2.2.19-3ubuntu2.2) ...", "Setting up libhx509-5-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Setting up libkrb5-26-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Setting up libheimntlm0-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Setting up libgssapi3-heimdal:amd64 (7.7.0+dfsg-1ubuntu1.4) ...", "Setting up libldap-2.4-2:amd64 (2.4.49+dfsg-2ubuntu1.10) ...", "Setting up dirmngr (2.2.19-3ubuntu2.2) ...", "Created symlink /etc/systemd/user/sockets.target.wants/dirmngr.socket → /usr/lib/systemd/user/dirmngr.socket.", "Setting up gpg-wks-client (2.2.19-3ubuntu2.2) ...", "Setting up gnupg (2.2.19-3ubuntu2.2) ...", "Setting up gnupg2 (2.2.19-3ubuntu2.2) ...", "Processing triggers for libc-bin (2.31-0ubuntu9.16) ..."]}

TASK [confluent.platform.common : Add Confluent Apt Key] ***********************
changed: [kafka-controller-3-migrated] => {"after": ["8B1DA6120C2BF624", "DA3A94F6B33723BC", "3B4FE6ACC0B21F32", "D94AA3F0EFE21092", "871920D1991BC93C"], "attempts": 1, "before": ["3B4FE6ACC0B21F32", "D94AA3F0EFE21092", "871920D1991BC93C"], "changed": true, "fp": "8B1DA6120C2BF624", "id": "8B1DA6120C2BF624", "key_id": "8B1DA6120C2BF624", "short_id": "0C2BF624"}

TASK [confluent.platform.common : Ensure Custom Apt Repo does not Exists when repository_configuration is Confluent] ***
ok: [kafka-controller-3-migrated] => {"changed": false, "path": "/etc/apt/sources.list.d/custom_confluent.list", "state": "absent"}

TASK [confluent.platform.common : Add Confluent Apt Repo] **********************
changed: [kafka-controller-3-migrated] => {"attempts": 1, "changed": true, "repo": "deb https://packages.confluent.io/deb/7.6 stable main", "sources_added": ["/etc/apt/sources.list.d/packages_confluent_io_deb_7_6.list"], "sources_removed": [], "state": "present"}

TASK [confluent.platform.common : Add Confluent Clients Apt Key] ***************
ok: [kafka-controller-3-migrated] => {"before": ["8B1DA6120C2BF624", "DA3A94F6B33723BC", "3B4FE6ACC0B21F32", "D94AA3F0EFE21092", "871920D1991BC93C"], "changed": false, "fp": "8B1DA6120C2BF624", "id": "8B1DA6120C2BF624", "key_id": "8B1DA6120C2BF624", "short_id": "0C2BF624"}

TASK [confluent.platform.common : Add Confluent Clients Apt Repo] **************
changed: [kafka-controller-3-migrated] => {"attempts": 1, "changed": true, "repo": "deb https://packages.confluent.io/clients/deb/ focal main", "sources_added": ["/etc/apt/sources.list.d/packages_confluent_io_clients_deb.list"], "sources_removed": [], "state": "present"}

TASK [confluent.platform.common : Ensure Confluent Apt Repo does not Exists when repository_configuration is Custom] ***
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "repository_configuration == 'custom'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Ensure Confluent Clients Apt Repo does not Exists when repository_configuration is Custom] ***
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "repository_configuration == 'custom'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Add Custom Apt Repo] *************************
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "repository_configuration == 'custom'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : meta] ****************************************

TASK [confluent.platform.common : Make Sure man pages Directory Exists] ********
ok: [kafka-controller-3-migrated] => {"changed": false, "gid": 0, "group": "root", "mode": "0755", "owner": "root", "path": "/usr/share/man/man1", "size": 4096, "state": "directory", "uid": 0}

TASK [confluent.platform.common : Custom Java Install] *************************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/common/tasks/custom_java_install.yml for kafka-controller-3-migrated

TASK [confluent.platform.common : Check custom_java_path in Centos7] ***********
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "ansible_os_family == \"RedHat\" and ansible_distribution_major_version == '7'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Check custom_java_path in Debian] ************
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "ansible_os_family == \"Debian\" and ansible_distribution_major_version in ['9', '10']", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Java Update Alternatives] ********************
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "not install_java|bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Keytool Update Alternatives] *****************
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "not install_java|bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Add open JDK repo] ***************************
changed: [kafka-controller-3-migrated] => {"attempts": 1, "changed": true, "repo": "ppa:openjdk-r/ppa", "sources_added": ["/etc/apt/sources.list.d/ppa_openjdk_r_ppa_focal.list"], "sources_removed": [], "state": "present"}

TASK [confluent.platform.common : Install Java] ********************************
changed: [kafka-controller-3-migrated] => {"attempts": 1, "cache_update_time": 1729175360, "cache_updated": false, "changed": true, "stderr": "debconf: delaying package configuration, since apt-utils is not installed\n", "stderr_lines": ["debconf: delaying package configuration, since apt-utils is not installed"], "stdout": "Reading package lists...\nBuilding dependency tree...\nReading state information...\nThe following additional packages will be installed:\n  adwaita-icon-theme fontconfig gtk-update-icon-cache hicolor-icon-theme\n  humanity-icon-theme libcairo-gobject2 libcairo2 libdatrie1 libfribidi0\n  libgail-common libgail18 libgdk-pixbuf2.0-0 libgdk-pixbuf2.0-bin\n  libgdk-pixbuf2.0-common libgtk2.0-0 libgtk2.0-bin libgtk2.0-common libjbig0\n  libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 libpixman-1-0\n  librsvg2-2 librsvg2-common libthai-data libthai0 libtiff5 libwebp6\n  libxcb-render0 libxcursor1 libxdamage1 openjdk-17-jdk-headless\n  openjdk-17-jre openjdk-17-jre-headless ubuntu-mono\nSuggested packages:\n  gvfs librsvg2-bin openjdk-17-demo openjdk-17-source visualvm libnss-mdns\n  fonts-ipafont-gothic fonts-ipafont-mincho fonts-wqy-microhei\n  | fonts-wqy-zenhei fonts-indic\nThe following NEW packages will be installed:\n  adwaita-icon-theme fontconfig gtk-update-icon-cache hicolor-icon-theme\n  humanity-icon-theme libcairo-gobject2 libcairo2 libdatrie1 libfribidi0\n  libgail-common libgail18 libgdk-pixbuf2.0-0 libgdk-pixbuf2.0-bin\n  libgdk-pixbuf2.0-common libgtk2.0-0 libgtk2.0-bin libgtk2.0-common libjbig0\n  libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 libpixman-1-0\n  librsvg2-2 librsvg2-common libthai-data libthai0 libtiff5 libwebp6\n  libxcb-render0 libxcursor1 libxdamage1 openjdk-17-jdk\n  openjdk-17-jdk-headless openjdk-17-jre openjdk-17-jre-headless ubuntu-mono\n0 upgraded, 36 newly installed, 0 to remove and 0 not upgraded.\nNeed to get 128 MB of archives.\nAfter this operation, 329 MB of additional disk space will be used.\nGet:1 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libfribidi0 amd64 1.0.8-2ubuntu0.1 [24.2 kB]\nGet:2 http://archive.ubuntu.com/ubuntu focal/main amd64 hicolor-icon-theme all 0.17-2 [9976 B]\nGet:3 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libjbig0 amd64 2.1-3.1ubuntu0.20.04.1 [27.3 kB]\nGet:4 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libwebp6 amd64 0.6.1-2ubuntu0.20.04.3 [185 kB]\nGet:5 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libtiff5 amd64 4.1.0+git191117-2ubuntu0.20.04.14 [164 kB]\nGet:6 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgdk-pixbuf2.0-common all 2.40.0+dfsg-3ubuntu0.5 [4628 B]\nGet:7 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgdk-pixbuf2.0-0 amd64 2.40.0+dfsg-3ubuntu0.5 [169 kB]\nGet:8 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gtk-update-icon-cache amd64 3.24.20-0ubuntu1.2 [28.3 kB]\nGet:9 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libpixman-1-0 amd64 0.38.4-0ubuntu2.1 [227 kB]\nGet:10 http://archive.ubuntu.com/ubuntu focal/main amd64 libxcb-render0 amd64 1.14-2 [14.8 kB]\nGet:11 http://archive.ubuntu.com/ubuntu focal/main amd64 libcairo2 amd64 1.16.0-4ubuntu1 [583 kB]\nGet:12 http://archive.ubuntu.com/ubuntu focal/main amd64 libcairo-gobject2 amd64 1.16.0-4ubuntu1 [17.2 kB]\nGet:13 http://archive.ubuntu.com/ubuntu focal/main amd64 fontconfig amd64 2.13.1-2ubuntu3 [171 kB]\nGet:14 http://archive.ubuntu.com/ubuntu focal/main amd64 libthai-data all 0.1.28-3 [134 kB]\nGet:15 http://archive.ubuntu.com/ubuntu focal/main amd64 libdatrie1 amd64 0.2.12-3 [18.7 kB]\nGet:16 http://archive.ubuntu.com/ubuntu focal/main amd64 libthai0 amd64 0.1.28-3 [18.1 kB]\nGet:17 http://archive.ubuntu.com/ubuntu focal/main amd64 libpango-1.0-0 amd64 1.44.7-2ubuntu4 [162 kB]\nGet:18 http://archive.ubuntu.com/ubuntu focal/main amd64 libpangoft2-1.0-0 amd64 1.44.7-2ubuntu4 [34.9 kB]\nGet:19 http://archive.ubuntu.com/ubuntu focal/main amd64 libpangocairo-1.0-0 amd64 1.44.7-2ubuntu4 [24.8 kB]\nGet:20 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 librsvg2-2 amd64 2.48.9-1ubuntu0.20.04.4 [2313 kB]\nGet:21 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 librsvg2-common amd64 2.48.9-1ubuntu0.20.04.4 [9224 B]\nGet:22 http://archive.ubuntu.com/ubuntu focal/main amd64 humanity-icon-theme all 0.6.15 [1250 kB]\nGet:23 http://archive.ubuntu.com/ubuntu focal/main amd64 ubuntu-mono all 19.04-0ubuntu3 [147 kB]\nGet:24 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 adwaita-icon-theme all 3.36.1-2ubuntu0.20.04.2 [3441 kB]\nGet:25 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgtk2.0-common all 2.24.32-4ubuntu4.1 [126 kB]\nGet:26 http://archive.ubuntu.com/ubuntu focal/main amd64 libxcursor1 amd64 1:1.2.0-2 [20.1 kB]\nGet:27 http://archive.ubuntu.com/ubuntu focal/main amd64 libxdamage1 amd64 1:1.1.5-2 [6996 B]\nGet:28 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgtk2.0-0 amd64 2.24.32-4ubuntu4.1 [1789 kB]\nGet:29 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgail18 amd64 2.24.32-4ubuntu4.1 [14.8 kB]\nGet:30 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgail-common amd64 2.24.32-4ubuntu4.1 [115 kB]\nGet:31 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgdk-pixbuf2.0-bin amd64 2.40.0+dfsg-3ubuntu0.5 [14.1 kB]\nGet:32 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgtk2.0-bin amd64 2.24.32-4ubuntu4.1 [7728 B]\nGet:33 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 openjdk-17-jre-headless amd64 17.0.12+7-1ubuntu2~20.04 [43.7 MB]\nGet:34 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 openjdk-17-jre amd64 17.0.12+7-1ubuntu2~20.04 [185 kB]\nGet:35 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 openjdk-17-jdk-headless amd64 17.0.12+7-1ubuntu2~20.04 [71.3 MB]\nGet:36 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 openjdk-17-jdk amd64 17.0.12+7-1ubuntu2~20.04 [1510 kB]\nFetched 128 MB in 6s (19.8 MB/s)\nSelecting previously unselected package libfribidi0:amd64.\r\n(Reading database ... \r(Reading database ... 5%\r(Reading database ... 10%\r(Reading database ... 15%\r(Reading database ... 20%\r(Reading database ... 25%\r(Reading database ... 30%\r(Reading database ... 35%\r(Reading database ... 40%\r(Reading database ... 45%\r(Reading database ... 50%\r(Reading database ... 55%\r(Reading database ... 60%\r(Reading database ... 65%\r(Reading database ... 70%\r(Reading database ... 75%\r(Reading database ... 80%\r(Reading database ... 85%\r(Reading database ... 90%\r(Reading database ... 95%\r(Reading database ... 100%\r(Reading database ... 15908 files and directories currently installed.)\r\nPreparing to unpack .../00-libfribidi0_1.0.8-2ubuntu0.1_amd64.deb ...\r\nUnpacking libfribidi0:amd64 (1.0.8-2ubuntu0.1) ...\r\nSelecting previously unselected package hicolor-icon-theme.\r\nPreparing to unpack .../01-hicolor-icon-theme_0.17-2_all.deb ...\r\nUnpacking hicolor-icon-theme (0.17-2) ...\r\nSelecting previously unselected package libjbig0:amd64.\r\nPreparing to unpack .../02-libjbig0_2.1-3.1ubuntu0.20.04.1_amd64.deb ...\r\nUnpacking libjbig0:amd64 (2.1-3.1ubuntu0.20.04.1) ...\r\nSelecting previously unselected package libwebp6:amd64.\r\nPreparing to unpack .../03-libwebp6_0.6.1-2ubuntu0.20.04.3_amd64.deb ...\r\nUnpacking libwebp6:amd64 (0.6.1-2ubuntu0.20.04.3) ...\r\nSelecting previously unselected package libtiff5:amd64.\r\nPreparing to unpack .../04-libtiff5_4.1.0+git191117-2ubuntu0.20.04.14_amd64.deb ...\r\nUnpacking libtiff5:amd64 (4.1.0+git191117-2ubuntu0.20.04.14) ...\r\nSelecting previously unselected package libgdk-pixbuf2.0-common.\r\nPreparing to unpack .../05-libgdk-pixbuf2.0-common_2.40.0+dfsg-3ubuntu0.5_all.deb ...\r\nUnpacking libgdk-pixbuf2.0-common (2.40.0+dfsg-3ubuntu0.5) ...\r\nSelecting previously unselected package libgdk-pixbuf2.0-0:amd64.\r\nPreparing to unpack .../06-libgdk-pixbuf2.0-0_2.40.0+dfsg-3ubuntu0.5_amd64.deb ...\r\nUnpacking libgdk-pixbuf2.0-0:amd64 (2.40.0+dfsg-3ubuntu0.5) ...\r\nSelecting previously unselected package gtk-update-icon-cache.\r\nPreparing to unpack .../07-gtk-update-icon-cache_3.24.20-0ubuntu1.2_amd64.deb ...\r\nNo diversion 'diversion of /usr/sbin/update-icon-caches to /usr/sbin/update-icon-caches.gtk2 by libgtk-3-bin', none removed.\r\nNo diversion 'diversion of /usr/share/man/man8/update-icon-caches.8.gz to /usr/share/man/man8/update-icon-caches.gtk2.8.gz by libgtk-3-bin', none removed.\r\nUnpacking gtk-update-icon-cache (3.24.20-0ubuntu1.2) ...\r\nSelecting previously unselected package libpixman-1-0:amd64.\r\nPreparing to unpack .../08-libpixman-1-0_0.38.4-0ubuntu2.1_amd64.deb ...\r\nUnpacking libpixman-1-0:amd64 (0.38.4-0ubuntu2.1) ...\r\nSelecting previously unselected package libxcb-render0:amd64.\r\nPreparing to unpack .../09-libxcb-render0_1.14-2_amd64.deb ...\r\nUnpacking libxcb-render0:amd64 (1.14-2) ...\r\nSelecting previously unselected package libcairo2:amd64.\r\nPreparing to unpack .../10-libcairo2_1.16.0-4ubuntu1_amd64.deb ...\r\nUnpacking libcairo2:amd64 (1.16.0-4ubuntu1) ...\r\nSelecting previously unselected package libcairo-gobject2:amd64.\r\nPreparing to unpack .../11-libcairo-gobject2_1.16.0-4ubuntu1_amd64.deb ...\r\nUnpacking libcairo-gobject2:amd64 (1.16.0-4ubuntu1) ...\r\nSelecting previously unselected package fontconfig.\r\nPreparing to unpack .../12-fontconfig_2.13.1-2ubuntu3_amd64.deb ...\r\nUnpacking fontconfig (2.13.1-2ubuntu3) ...\r\nSelecting previously unselected package libthai-data.\r\nPreparing to unpack .../13-libthai-data_0.1.28-3_all.deb ...\r\nUnpacking libthai-data (0.1.28-3) ...\r\nSelecting previously unselected package libdatrie1:amd64.\r\nPreparing to unpack .../14-libdatrie1_0.2.12-3_amd64.deb ...\r\nUnpacking libdatrie1:amd64 (0.2.12-3) ...\r\nSelecting previously unselected package libthai0:amd64.\r\nPreparing to unpack .../15-libthai0_0.1.28-3_amd64.deb ...\r\nUnpacking libthai0:amd64 (0.1.28-3) ...\r\nSelecting previously unselected package libpango-1.0-0:amd64.\r\nPreparing to unpack .../16-libpango-1.0-0_1.44.7-2ubuntu4_amd64.deb ...\r\nUnpacking libpango-1.0-0:amd64 (1.44.7-2ubuntu4) ...\r\nSelecting previously unselected package libpangoft2-1.0-0:amd64.\r\nPreparing to unpack .../17-libpangoft2-1.0-0_1.44.7-2ubuntu4_amd64.deb ...\r\nUnpacking libpangoft2-1.0-0:amd64 (1.44.7-2ubuntu4) ...\r\nSelecting previously unselected package libpangocairo-1.0-0:amd64.\r\nPreparing to unpack .../18-libpangocairo-1.0-0_1.44.7-2ubuntu4_amd64.deb ...\r\nUnpacking libpangocairo-1.0-0:amd64 (1.44.7-2ubuntu4) ...\r\nSelecting previously unselected package librsvg2-2:amd64.\r\nPreparing to unpack .../19-librsvg2-2_2.48.9-1ubuntu0.20.04.4_amd64.deb ...\r\nUnpacking librsvg2-2:amd64 (2.48.9-1ubuntu0.20.04.4) ...\r\nSelecting previously unselected package librsvg2-common:amd64.\r\nPreparing to unpack .../20-librsvg2-common_2.48.9-1ubuntu0.20.04.4_amd64.deb ...\r\nUnpacking librsvg2-common:amd64 (2.48.9-1ubuntu0.20.04.4) ...\r\nSelecting previously unselected package humanity-icon-theme.\r\nPreparing to unpack .../21-humanity-icon-theme_0.6.15_all.deb ...\r\nUnpacking humanity-icon-theme (0.6.15) ...\r\nSelecting previously unselected package ubuntu-mono.\r\nPreparing to unpack .../22-ubuntu-mono_19.04-0ubuntu3_all.deb ...\r\nUnpacking ubuntu-mono (19.04-0ubuntu3) ...\r\nSelecting previously unselected package adwaita-icon-theme.\r\nPreparing to unpack .../23-adwaita-icon-theme_3.36.1-2ubuntu0.20.04.2_all.deb ...\r\nUnpacking adwaita-icon-theme (3.36.1-2ubuntu0.20.04.2) ...\r\nSelecting previously unselected package libgtk2.0-common.\r\nPreparing to unpack .../24-libgtk2.0-common_2.24.32-4ubuntu4.1_all.deb ...\r\nUnpacking libgtk2.0-common (2.24.32-4ubuntu4.1) ...\r\nSelecting previously unselected package libxcursor1:amd64.\r\nPreparing to unpack .../25-libxcursor1_1%3a1.2.0-2_amd64.deb ...\r\nUnpacking libxcursor1:amd64 (1:1.2.0-2) ...\r\nSelecting previously unselected package libxdamage1:amd64.\r\nPreparing to unpack .../26-libxdamage1_1%3a1.1.5-2_amd64.deb ...\r\nUnpacking libxdamage1:amd64 (1:1.1.5-2) ...\r\nSelecting previously unselected package libgtk2.0-0:amd64.\r\nPreparing to unpack .../27-libgtk2.0-0_2.24.32-4ubuntu4.1_amd64.deb ...\r\nUnpacking libgtk2.0-0:amd64 (2.24.32-4ubuntu4.1) ...\r\nSelecting previously unselected package libgail18:amd64.\r\nPreparing to unpack .../28-libgail18_2.24.32-4ubuntu4.1_amd64.deb ...\r\nUnpacking libgail18:amd64 (2.24.32-4ubuntu4.1) ...\r\nSelecting previously unselected package libgail-common:amd64.\r\nPreparing to unpack .../29-libgail-common_2.24.32-4ubuntu4.1_amd64.deb ...\r\nUnpacking libgail-common:amd64 (2.24.32-4ubuntu4.1) ...\r\nSelecting previously unselected package libgdk-pixbuf2.0-bin.\r\nPreparing to unpack .../30-libgdk-pixbuf2.0-bin_2.40.0+dfsg-3ubuntu0.5_amd64.deb ...\r\nUnpacking libgdk-pixbuf2.0-bin (2.40.0+dfsg-3ubuntu0.5) ...\r\nSelecting previously unselected package libgtk2.0-bin.\r\nPreparing to unpack .../31-libgtk2.0-bin_2.24.32-4ubuntu4.1_amd64.deb ...\r\nUnpacking libgtk2.0-bin (2.24.32-4ubuntu4.1) ...\r\nSelecting previously unselected package openjdk-17-jre-headless:amd64.\r\nPreparing to unpack .../32-openjdk-17-jre-headless_17.0.12+7-1ubuntu2~20.04_amd64.deb ...\r\nUnpacking openjdk-17-jre-headless:amd64 (17.0.12+7-1ubuntu2~20.04) ...\r\nSelecting previously unselected package openjdk-17-jre:amd64.\r\nPreparing to unpack .../33-openjdk-17-jre_17.0.12+7-1ubuntu2~20.04_amd64.deb ...\r\nUnpacking openjdk-17-jre:amd64 (17.0.12+7-1ubuntu2~20.04) ...\r\nSelecting previously unselected package openjdk-17-jdk-headless:amd64.\r\nPreparing to unpack .../34-openjdk-17-jdk-headless_17.0.12+7-1ubuntu2~20.04_amd64.deb ...\r\nUnpacking openjdk-17-jdk-headless:amd64 (17.0.12+7-1ubuntu2~20.04) ...\r\nSelecting previously unselected package openjdk-17-jdk:amd64.\r\nPreparing to unpack .../35-openjdk-17-jdk_17.0.12+7-1ubuntu2~20.04_amd64.deb ...\r\nUnpacking openjdk-17-jdk:amd64 (17.0.12+7-1ubuntu2~20.04) ...\r\nSetting up libpixman-1-0:amd64 (0.38.4-0ubuntu2.1) ...\r\nSetting up fontconfig (2.13.1-2ubuntu3) ...\r\nRegenerating fonts cache... done.\r\nSetting up libxdamage1:amd64 (1:1.1.5-2) ...\r\nSetting up hicolor-icon-theme (0.17-2) ...\r\nSetting up libdatrie1:amd64 (0.2.12-3) ...\r\nSetting up libxcb-render0:amd64 (1.14-2) ...\r\nSetting up libxcursor1:amd64 (1:1.2.0-2) ...\r\nSetting up libgdk-pixbuf2.0-common (2.40.0+dfsg-3ubuntu0.5) ...\r\nSetting up libjbig0:amd64 (2.1-3.1ubuntu0.20.04.1) ...\r\nSetting up libcairo2:amd64 (1.16.0-4ubuntu1) ...\r\nSetting up libfribidi0:amd64 (1.0.8-2ubuntu0.1) ...\r\nSetting up libwebp6:amd64 (0.6.1-2ubuntu0.20.04.3) ...\r\nSetting up openjdk-17-jre-headless:amd64 (17.0.12+7-1ubuntu2~20.04) ...\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/java to provide /usr/bin/java (java) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jpackage to provide /usr/bin/jpackage (jpackage) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/keytool to provide /usr/bin/keytool (keytool) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/rmiregistry to provide /usr/bin/rmiregistry (rmiregistry) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/lib/jexec to provide /usr/bin/jexec (jexec) in auto mode\r\nSetting up libthai-data (0.1.28-3) ...\r\nSetting up libcairo-gobject2:amd64 (1.16.0-4ubuntu1) ...\r\nSetting up libgtk2.0-common (2.24.32-4ubuntu4.1) ...\r\nSetting up libtiff5:amd64 (4.1.0+git191117-2ubuntu0.20.04.14) ...\r\nSetting up libthai0:amd64 (0.1.28-3) ...\r\nSetting up libgdk-pixbuf2.0-0:amd64 (2.40.0+dfsg-3ubuntu0.5) ...\r\nSetting up openjdk-17-jdk-headless:amd64 (17.0.12+7-1ubuntu2~20.04) ...\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jar to provide /usr/bin/jar (jar) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jarsigner to provide /usr/bin/jarsigner (jarsigner) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/javac to provide /usr/bin/javac (javac) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/javadoc to provide /usr/bin/javadoc (javadoc) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/javap to provide /usr/bin/javap (javap) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jcmd to provide /usr/bin/jcmd (jcmd) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jdb to provide /usr/bin/jdb (jdb) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jdeprscan to provide /usr/bin/jdeprscan (jdeprscan) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jdeps to provide /usr/bin/jdeps (jdeps) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jfr to provide /usr/bin/jfr (jfr) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jimage to provide /usr/bin/jimage (jimage) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jinfo to provide /usr/bin/jinfo (jinfo) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jlink to provide /usr/bin/jlink (jlink) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jmap to provide /usr/bin/jmap (jmap) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jmod to provide /usr/bin/jmod (jmod) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jps to provide /usr/bin/jps (jps) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jrunscript to provide /usr/bin/jrunscript (jrunscript) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jshell to provide /usr/bin/jshell (jshell) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jstack to provide /usr/bin/jstack (jstack) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jstat to provide /usr/bin/jstat (jstat) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jstatd to provide /usr/bin/jstatd (jstatd) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/serialver to provide /usr/bin/serialver (serialver) in auto mode\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jhsdb to provide /usr/bin/jhsdb (jhsdb) in auto mode\r\nSetting up libgdk-pixbuf2.0-bin (2.40.0+dfsg-3ubuntu0.5) ...\r\nSetting up gtk-update-icon-cache (3.24.20-0ubuntu1.2) ...\r\nSetting up libpango-1.0-0:amd64 (1.44.7-2ubuntu4) ...\r\nSetting up libpangoft2-1.0-0:amd64 (1.44.7-2ubuntu4) ...\r\nSetting up libpangocairo-1.0-0:amd64 (1.44.7-2ubuntu4) ...\r\nSetting up librsvg2-2:amd64 (2.48.9-1ubuntu0.20.04.4) ...\r\nSetting up librsvg2-common:amd64 (2.48.9-1ubuntu0.20.04.4) ...\r\nSetting up adwaita-icon-theme (3.36.1-2ubuntu0.20.04.2) ...\r\nupdate-alternatives: using /usr/share/icons/Adwaita/cursor.theme to provide /usr/share/icons/default/index.theme (x-cursor-theme) in auto mode\r\nSetting up libgtk2.0-0:amd64 (2.24.32-4ubuntu4.1) ...\r\nSetting up humanity-icon-theme (0.6.15) ...\r\nSetting up libgail18:amd64 (2.24.32-4ubuntu4.1) ...\r\nSetting up libgtk2.0-bin (2.24.32-4ubuntu4.1) ...\r\nSetting up libgail-common:amd64 (2.24.32-4ubuntu4.1) ...\r\nSetting up openjdk-17-jre:amd64 (17.0.12+7-1ubuntu2~20.04) ...\r\nSetting up ubuntu-mono (19.04-0ubuntu3) ...\r\nSetting up openjdk-17-jdk:amd64 (17.0.12+7-1ubuntu2~20.04) ...\r\nupdate-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jconsole to provide /usr/bin/jconsole (jconsole) in auto mode\r\nProcessing triggers for mime-support (3.64ubuntu1) ...\r\nProcessing triggers for libc-bin (2.31-0ubuntu9.16) ...\r\nProcessing triggers for libgdk-pixbuf2.0-0:amd64 (2.40.0+dfsg-3ubuntu0.5) ...\r\n", "stdout_lines": ["Reading package lists...", "Building dependency tree...", "Reading state information...", "The following additional packages will be installed:", "  adwaita-icon-theme fontconfig gtk-update-icon-cache hicolor-icon-theme", "  humanity-icon-theme libcairo-gobject2 libcairo2 libdatrie1 libfribidi0", "  libgail-common libgail18 libgdk-pixbuf2.0-0 libgdk-pixbuf2.0-bin", "  libgdk-pixbuf2.0-common libgtk2.0-0 libgtk2.0-bin libgtk2.0-common libjbig0", "  libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 libpixman-1-0", "  librsvg2-2 librsvg2-common libthai-data libthai0 libtiff5 libwebp6", "  libxcb-render0 libxcursor1 libxdamage1 openjdk-17-jdk-headless", "  openjdk-17-jre openjdk-17-jre-headless ubuntu-mono", "Suggested packages:", "  gvfs librsvg2-bin openjdk-17-demo openjdk-17-source visualvm libnss-mdns", "  fonts-ipafont-gothic fonts-ipafont-mincho fonts-wqy-microhei", "  | fonts-wqy-zenhei fonts-indic", "The following NEW packages will be installed:", "  adwaita-icon-theme fontconfig gtk-update-icon-cache hicolor-icon-theme", "  humanity-icon-theme libcairo-gobject2 libcairo2 libdatrie1 libfribidi0", "  libgail-common libgail18 libgdk-pixbuf2.0-0 libgdk-pixbuf2.0-bin", "  libgdk-pixbuf2.0-common libgtk2.0-0 libgtk2.0-bin libgtk2.0-common libjbig0", "  libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 libpixman-1-0", "  librsvg2-2 librsvg2-common libthai-data libthai0 libtiff5 libwebp6", "  libxcb-render0 libxcursor1 libxdamage1 openjdk-17-jdk", "  openjdk-17-jdk-headless openjdk-17-jre openjdk-17-jre-headless ubuntu-mono", "0 upgraded, 36 newly installed, 0 to remove and 0 not upgraded.", "Need to get 128 MB of archives.", "After this operation, 329 MB of additional disk space will be used.", "Get:1 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libfribidi0 amd64 1.0.8-2ubuntu0.1 [24.2 kB]", "Get:2 http://archive.ubuntu.com/ubuntu focal/main amd64 hicolor-icon-theme all 0.17-2 [9976 B]", "Get:3 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libjbig0 amd64 2.1-3.1ubuntu0.20.04.1 [27.3 kB]", "Get:4 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libwebp6 amd64 0.6.1-2ubuntu0.20.04.3 [185 kB]", "Get:5 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libtiff5 amd64 4.1.0+git191117-2ubuntu0.20.04.14 [164 kB]", "Get:6 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgdk-pixbuf2.0-common all 2.40.0+dfsg-3ubuntu0.5 [4628 B]", "Get:7 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgdk-pixbuf2.0-0 amd64 2.40.0+dfsg-3ubuntu0.5 [169 kB]", "Get:8 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gtk-update-icon-cache amd64 3.24.20-0ubuntu1.2 [28.3 kB]", "Get:9 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libpixman-1-0 amd64 0.38.4-0ubuntu2.1 [227 kB]", "Get:10 http://archive.ubuntu.com/ubuntu focal/main amd64 libxcb-render0 amd64 1.14-2 [14.8 kB]", "Get:11 http://archive.ubuntu.com/ubuntu focal/main amd64 libcairo2 amd64 1.16.0-4ubuntu1 [583 kB]", "Get:12 http://archive.ubuntu.com/ubuntu focal/main amd64 libcairo-gobject2 amd64 1.16.0-4ubuntu1 [17.2 kB]", "Get:13 http://archive.ubuntu.com/ubuntu focal/main amd64 fontconfig amd64 2.13.1-2ubuntu3 [171 kB]", "Get:14 http://archive.ubuntu.com/ubuntu focal/main amd64 libthai-data all 0.1.28-3 [134 kB]", "Get:15 http://archive.ubuntu.com/ubuntu focal/main amd64 libdatrie1 amd64 0.2.12-3 [18.7 kB]", "Get:16 http://archive.ubuntu.com/ubuntu focal/main amd64 libthai0 amd64 0.1.28-3 [18.1 kB]", "Get:17 http://archive.ubuntu.com/ubuntu focal/main amd64 libpango-1.0-0 amd64 1.44.7-2ubuntu4 [162 kB]", "Get:18 http://archive.ubuntu.com/ubuntu focal/main amd64 libpangoft2-1.0-0 amd64 1.44.7-2ubuntu4 [34.9 kB]", "Get:19 http://archive.ubuntu.com/ubuntu focal/main amd64 libpangocairo-1.0-0 amd64 1.44.7-2ubuntu4 [24.8 kB]", "Get:20 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 librsvg2-2 amd64 2.48.9-1ubuntu0.20.04.4 [2313 kB]", "Get:21 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 librsvg2-common amd64 2.48.9-1ubuntu0.20.04.4 [9224 B]", "Get:22 http://archive.ubuntu.com/ubuntu focal/main amd64 humanity-icon-theme all 0.6.15 [1250 kB]", "Get:23 http://archive.ubuntu.com/ubuntu focal/main amd64 ubuntu-mono all 19.04-0ubuntu3 [147 kB]", "Get:24 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 adwaita-icon-theme all 3.36.1-2ubuntu0.20.04.2 [3441 kB]", "Get:25 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgtk2.0-common all 2.24.32-4ubuntu4.1 [126 kB]", "Get:26 http://archive.ubuntu.com/ubuntu focal/main amd64 libxcursor1 amd64 1:1.2.0-2 [20.1 kB]", "Get:27 http://archive.ubuntu.com/ubuntu focal/main amd64 libxdamage1 amd64 1:1.1.5-2 [6996 B]", "Get:28 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgtk2.0-0 amd64 2.24.32-4ubuntu4.1 [1789 kB]", "Get:29 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgail18 amd64 2.24.32-4ubuntu4.1 [14.8 kB]", "Get:30 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgail-common amd64 2.24.32-4ubuntu4.1 [115 kB]", "Get:31 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgdk-pixbuf2.0-bin amd64 2.40.0+dfsg-3ubuntu0.5 [14.1 kB]", "Get:32 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgtk2.0-bin amd64 2.24.32-4ubuntu4.1 [7728 B]", "Get:33 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 openjdk-17-jre-headless amd64 17.0.12+7-1ubuntu2~20.04 [43.7 MB]", "Get:34 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 openjdk-17-jre amd64 17.0.12+7-1ubuntu2~20.04 [185 kB]", "Get:35 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 openjdk-17-jdk-headless amd64 17.0.12+7-1ubuntu2~20.04 [71.3 MB]", "Get:36 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 openjdk-17-jdk amd64 17.0.12+7-1ubuntu2~20.04 [1510 kB]", "Fetched 128 MB in 6s (19.8 MB/s)", "Selecting previously unselected package libfribidi0:amd64.", "(Reading database ... ", "(Reading database ... 5%", "(Reading database ... 10%", "(Reading database ... 15%", "(Reading database ... 20%", "(Reading database ... 25%", "(Reading database ... 30%", "(Reading database ... 35%", "(Reading database ... 40%", "(Reading database ... 45%", "(Reading database ... 50%", "(Reading database ... 55%", "(Reading database ... 60%", "(Reading database ... 65%", "(Reading database ... 70%", "(Reading database ... 75%", "(Reading database ... 80%", "(Reading database ... 85%", "(Reading database ... 90%", "(Reading database ... 95%", "(Reading database ... 100%", "(Reading database ... 15908 files and directories currently installed.)", "Preparing to unpack .../00-libfribidi0_1.0.8-2ubuntu0.1_amd64.deb ...", "Unpacking libfribidi0:amd64 (1.0.8-2ubuntu0.1) ...", "Selecting previously unselected package hicolor-icon-theme.", "Preparing to unpack .../01-hicolor-icon-theme_0.17-2_all.deb ...", "Unpacking hicolor-icon-theme (0.17-2) ...", "Selecting previously unselected package libjbig0:amd64.", "Preparing to unpack .../02-libjbig0_2.1-3.1ubuntu0.20.04.1_amd64.deb ...", "Unpacking libjbig0:amd64 (2.1-3.1ubuntu0.20.04.1) ...", "Selecting previously unselected package libwebp6:amd64.", "Preparing to unpack .../03-libwebp6_0.6.1-2ubuntu0.20.04.3_amd64.deb ...", "Unpacking libwebp6:amd64 (0.6.1-2ubuntu0.20.04.3) ...", "Selecting previously unselected package libtiff5:amd64.", "Preparing to unpack .../04-libtiff5_4.1.0+git191117-2ubuntu0.20.04.14_amd64.deb ...", "Unpacking libtiff5:amd64 (4.1.0+git191117-2ubuntu0.20.04.14) ...", "Selecting previously unselected package libgdk-pixbuf2.0-common.", "Preparing to unpack .../05-libgdk-pixbuf2.0-common_2.40.0+dfsg-3ubuntu0.5_all.deb ...", "Unpacking libgdk-pixbuf2.0-common (2.40.0+dfsg-3ubuntu0.5) ...", "Selecting previously unselected package libgdk-pixbuf2.0-0:amd64.", "Preparing to unpack .../06-libgdk-pixbuf2.0-0_2.40.0+dfsg-3ubuntu0.5_amd64.deb ...", "Unpacking libgdk-pixbuf2.0-0:amd64 (2.40.0+dfsg-3ubuntu0.5) ...", "Selecting previously unselected package gtk-update-icon-cache.", "Preparing to unpack .../07-gtk-update-icon-cache_3.24.20-0ubuntu1.2_amd64.deb ...", "No diversion 'diversion of /usr/sbin/update-icon-caches to /usr/sbin/update-icon-caches.gtk2 by libgtk-3-bin', none removed.", "No diversion 'diversion of /usr/share/man/man8/update-icon-caches.8.gz to /usr/share/man/man8/update-icon-caches.gtk2.8.gz by libgtk-3-bin', none removed.", "Unpacking gtk-update-icon-cache (3.24.20-0ubuntu1.2) ...", "Selecting previously unselected package libpixman-1-0:amd64.", "Preparing to unpack .../08-libpixman-1-0_0.38.4-0ubuntu2.1_amd64.deb ...", "Unpacking libpixman-1-0:amd64 (0.38.4-0ubuntu2.1) ...", "Selecting previously unselected package libxcb-render0:amd64.", "Preparing to unpack .../09-libxcb-render0_1.14-2_amd64.deb ...", "Unpacking libxcb-render0:amd64 (1.14-2) ...", "Selecting previously unselected package libcairo2:amd64.", "Preparing to unpack .../10-libcairo2_1.16.0-4ubuntu1_amd64.deb ...", "Unpacking libcairo2:amd64 (1.16.0-4ubuntu1) ...", "Selecting previously unselected package libcairo-gobject2:amd64.", "Preparing to unpack .../11-libcairo-gobject2_1.16.0-4ubuntu1_amd64.deb ...", "Unpacking libcairo-gobject2:amd64 (1.16.0-4ubuntu1) ...", "Selecting previously unselected package fontconfig.", "Preparing to unpack .../12-fontconfig_2.13.1-2ubuntu3_amd64.deb ...", "Unpacking fontconfig (2.13.1-2ubuntu3) ...", "Selecting previously unselected package libthai-data.", "Preparing to unpack .../13-libthai-data_0.1.28-3_all.deb ...", "Unpacking libthai-data (0.1.28-3) ...", "Selecting previously unselected package libdatrie1:amd64.", "Preparing to unpack .../14-libdatrie1_0.2.12-3_amd64.deb ...", "Unpacking libdatrie1:amd64 (0.2.12-3) ...", "Selecting previously unselected package libthai0:amd64.", "Preparing to unpack .../15-libthai0_0.1.28-3_amd64.deb ...", "Unpacking libthai0:amd64 (0.1.28-3) ...", "Selecting previously unselected package libpango-1.0-0:amd64.", "Preparing to unpack .../16-libpango-1.0-0_1.44.7-2ubuntu4_amd64.deb ...", "Unpacking libpango-1.0-0:amd64 (1.44.7-2ubuntu4) ...", "Selecting previously unselected package libpangoft2-1.0-0:amd64.", "Preparing to unpack .../17-libpangoft2-1.0-0_1.44.7-2ubuntu4_amd64.deb ...", "Unpacking libpangoft2-1.0-0:amd64 (1.44.7-2ubuntu4) ...", "Selecting previously unselected package libpangocairo-1.0-0:amd64.", "Preparing to unpack .../18-libpangocairo-1.0-0_1.44.7-2ubuntu4_amd64.deb ...", "Unpacking libpangocairo-1.0-0:amd64 (1.44.7-2ubuntu4) ...", "Selecting previously unselected package librsvg2-2:amd64.", "Preparing to unpack .../19-librsvg2-2_2.48.9-1ubuntu0.20.04.4_amd64.deb ...", "Unpacking librsvg2-2:amd64 (2.48.9-1ubuntu0.20.04.4) ...", "Selecting previously unselected package librsvg2-common:amd64.", "Preparing to unpack .../20-librsvg2-common_2.48.9-1ubuntu0.20.04.4_amd64.deb ...", "Unpacking librsvg2-common:amd64 (2.48.9-1ubuntu0.20.04.4) ...", "Selecting previously unselected package humanity-icon-theme.", "Preparing to unpack .../21-humanity-icon-theme_0.6.15_all.deb ...", "Unpacking humanity-icon-theme (0.6.15) ...", "Selecting previously unselected package ubuntu-mono.", "Preparing to unpack .../22-ubuntu-mono_19.04-0ubuntu3_all.deb ...", "Unpacking ubuntu-mono (19.04-0ubuntu3) ...", "Selecting previously unselected package adwaita-icon-theme.", "Preparing to unpack .../23-adwaita-icon-theme_3.36.1-2ubuntu0.20.04.2_all.deb ...", "Unpacking adwaita-icon-theme (3.36.1-2ubuntu0.20.04.2) ...", "Selecting previously unselected package libgtk2.0-common.", "Preparing to unpack .../24-libgtk2.0-common_2.24.32-4ubuntu4.1_all.deb ...", "Unpacking libgtk2.0-common (2.24.32-4ubuntu4.1) ...", "Selecting previously unselected package libxcursor1:amd64.", "Preparing to unpack .../25-libxcursor1_1%3a1.2.0-2_amd64.deb ...", "Unpacking libxcursor1:amd64 (1:1.2.0-2) ...", "Selecting previously unselected package libxdamage1:amd64.", "Preparing to unpack .../26-libxdamage1_1%3a1.1.5-2_amd64.deb ...", "Unpacking libxdamage1:amd64 (1:1.1.5-2) ...", "Selecting previously unselected package libgtk2.0-0:amd64.", "Preparing to unpack .../27-libgtk2.0-0_2.24.32-4ubuntu4.1_amd64.deb ...", "Unpacking libgtk2.0-0:amd64 (2.24.32-4ubuntu4.1) ...", "Selecting previously unselected package libgail18:amd64.", "Preparing to unpack .../28-libgail18_2.24.32-4ubuntu4.1_amd64.deb ...", "Unpacking libgail18:amd64 (2.24.32-4ubuntu4.1) ...", "Selecting previously unselected package libgail-common:amd64.", "Preparing to unpack .../29-libgail-common_2.24.32-4ubuntu4.1_amd64.deb ...", "Unpacking libgail-common:amd64 (2.24.32-4ubuntu4.1) ...", "Selecting previously unselected package libgdk-pixbuf2.0-bin.", "Preparing to unpack .../30-libgdk-pixbuf2.0-bin_2.40.0+dfsg-3ubuntu0.5_amd64.deb ...", "Unpacking libgdk-pixbuf2.0-bin (2.40.0+dfsg-3ubuntu0.5) ...", "Selecting previously unselected package libgtk2.0-bin.", "Preparing to unpack .../31-libgtk2.0-bin_2.24.32-4ubuntu4.1_amd64.deb ...", "Unpacking libgtk2.0-bin (2.24.32-4ubuntu4.1) ...", "Selecting previously unselected package openjdk-17-jre-headless:amd64.", "Preparing to unpack .../32-openjdk-17-jre-headless_17.0.12+7-1ubuntu2~20.04_amd64.deb ...", "Unpacking openjdk-17-jre-headless:amd64 (17.0.12+7-1ubuntu2~20.04) ...", "Selecting previously unselected package openjdk-17-jre:amd64.", "Preparing to unpack .../33-openjdk-17-jre_17.0.12+7-1ubuntu2~20.04_amd64.deb ...", "Unpacking openjdk-17-jre:amd64 (17.0.12+7-1ubuntu2~20.04) ...", "Selecting previously unselected package openjdk-17-jdk-headless:amd64.", "Preparing to unpack .../34-openjdk-17-jdk-headless_17.0.12+7-1ubuntu2~20.04_amd64.deb ...", "Unpacking openjdk-17-jdk-headless:amd64 (17.0.12+7-1ubuntu2~20.04) ...", "Selecting previously unselected package openjdk-17-jdk:amd64.", "Preparing to unpack .../35-openjdk-17-jdk_17.0.12+7-1ubuntu2~20.04_amd64.deb ...", "Unpacking openjdk-17-jdk:amd64 (17.0.12+7-1ubuntu2~20.04) ...", "Setting up libpixman-1-0:amd64 (0.38.4-0ubuntu2.1) ...", "Setting up fontconfig (2.13.1-2ubuntu3) ...", "Regenerating fonts cache... done.", "Setting up libxdamage1:amd64 (1:1.1.5-2) ...", "Setting up hicolor-icon-theme (0.17-2) ...", "Setting up libdatrie1:amd64 (0.2.12-3) ...", "Setting up libxcb-render0:amd64 (1.14-2) ...", "Setting up libxcursor1:amd64 (1:1.2.0-2) ...", "Setting up libgdk-pixbuf2.0-common (2.40.0+dfsg-3ubuntu0.5) ...", "Setting up libjbig0:amd64 (2.1-3.1ubuntu0.20.04.1) ...", "Setting up libcairo2:amd64 (1.16.0-4ubuntu1) ...", "Setting up libfribidi0:amd64 (1.0.8-2ubuntu0.1) ...", "Setting up libwebp6:amd64 (0.6.1-2ubuntu0.20.04.3) ...", "Setting up openjdk-17-jre-headless:amd64 (17.0.12+7-1ubuntu2~20.04) ...", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/java to provide /usr/bin/java (java) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jpackage to provide /usr/bin/jpackage (jpackage) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/keytool to provide /usr/bin/keytool (keytool) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/rmiregistry to provide /usr/bin/rmiregistry (rmiregistry) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/lib/jexec to provide /usr/bin/jexec (jexec) in auto mode", "Setting up libthai-data (0.1.28-3) ...", "Setting up libcairo-gobject2:amd64 (1.16.0-4ubuntu1) ...", "Setting up libgtk2.0-common (2.24.32-4ubuntu4.1) ...", "Setting up libtiff5:amd64 (4.1.0+git191117-2ubuntu0.20.04.14) ...", "Setting up libthai0:amd64 (0.1.28-3) ...", "Setting up libgdk-pixbuf2.0-0:amd64 (2.40.0+dfsg-3ubuntu0.5) ...", "Setting up openjdk-17-jdk-headless:amd64 (17.0.12+7-1ubuntu2~20.04) ...", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jar to provide /usr/bin/jar (jar) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jarsigner to provide /usr/bin/jarsigner (jarsigner) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/javac to provide /usr/bin/javac (javac) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/javadoc to provide /usr/bin/javadoc (javadoc) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/javap to provide /usr/bin/javap (javap) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jcmd to provide /usr/bin/jcmd (jcmd) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jdb to provide /usr/bin/jdb (jdb) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jdeprscan to provide /usr/bin/jdeprscan (jdeprscan) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jdeps to provide /usr/bin/jdeps (jdeps) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jfr to provide /usr/bin/jfr (jfr) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jimage to provide /usr/bin/jimage (jimage) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jinfo to provide /usr/bin/jinfo (jinfo) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jlink to provide /usr/bin/jlink (jlink) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jmap to provide /usr/bin/jmap (jmap) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jmod to provide /usr/bin/jmod (jmod) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jps to provide /usr/bin/jps (jps) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jrunscript to provide /usr/bin/jrunscript (jrunscript) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jshell to provide /usr/bin/jshell (jshell) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jstack to provide /usr/bin/jstack (jstack) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jstat to provide /usr/bin/jstat (jstat) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jstatd to provide /usr/bin/jstatd (jstatd) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/serialver to provide /usr/bin/serialver (serialver) in auto mode", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jhsdb to provide /usr/bin/jhsdb (jhsdb) in auto mode", "Setting up libgdk-pixbuf2.0-bin (2.40.0+dfsg-3ubuntu0.5) ...", "Setting up gtk-update-icon-cache (3.24.20-0ubuntu1.2) ...", "Setting up libpango-1.0-0:amd64 (1.44.7-2ubuntu4) ...", "Setting up libpangoft2-1.0-0:amd64 (1.44.7-2ubuntu4) ...", "Setting up libpangocairo-1.0-0:amd64 (1.44.7-2ubuntu4) ...", "Setting up librsvg2-2:amd64 (2.48.9-1ubuntu0.20.04.4) ...", "Setting up librsvg2-common:amd64 (2.48.9-1ubuntu0.20.04.4) ...", "Setting up adwaita-icon-theme (3.36.1-2ubuntu0.20.04.2) ...", "update-alternatives: using /usr/share/icons/Adwaita/cursor.theme to provide /usr/share/icons/default/index.theme (x-cursor-theme) in auto mode", "Setting up libgtk2.0-0:amd64 (2.24.32-4ubuntu4.1) ...", "Setting up humanity-icon-theme (0.6.15) ...", "Setting up libgail18:amd64 (2.24.32-4ubuntu4.1) ...", "Setting up libgtk2.0-bin (2.24.32-4ubuntu4.1) ...", "Setting up libgail-common:amd64 (2.24.32-4ubuntu4.1) ...", "Setting up openjdk-17-jre:amd64 (17.0.12+7-1ubuntu2~20.04) ...", "Setting up ubuntu-mono (19.04-0ubuntu3) ...", "Setting up openjdk-17-jdk:amd64 (17.0.12+7-1ubuntu2~20.04) ...", "update-alternatives: using /usr/lib/jvm/java-17-openjdk-amd64/bin/jconsole to provide /usr/bin/jconsole (jconsole) in auto mode", "Processing triggers for mime-support (3.64ubuntu1) ...", "Processing triggers for libc-bin (2.31-0ubuntu9.16) ...", "Processing triggers for libgdk-pixbuf2.0-0:amd64 (2.40.0+dfsg-3ubuntu0.5) ..."]}

TASK [confluent.platform.common : Install OpenSSL] *****************************
ok: [kafka-controller-3-migrated] => {"cache_update_time": 1729175360, "cache_updated": false, "changed": false}

TASK [confluent.platform.common : Get Java Version] ****************************
ok: [kafka-controller-3-migrated] => {"changed": false, "cmd": "java -version", "delta": "0:00:00.053551", "end": "2024-10-17 16:29:53.101626", "msg": "", "rc": 0, "start": "2024-10-17 16:29:53.048075", "stderr": "openjdk version \"17.0.12\" 2024-07-16\nOpenJDK Runtime Environment (build 17.0.12+7-Ubuntu-1ubuntu220.04)\nOpenJDK 64-Bit Server VM (build 17.0.12+7-Ubuntu-1ubuntu220.04, mixed mode, sharing)", "stderr_lines": ["openjdk version \"17.0.12\" 2024-07-16", "OpenJDK Runtime Environment (build 17.0.12+7-Ubuntu-1ubuntu220.04)", "OpenJDK 64-Bit Server VM (build 17.0.12+7-Ubuntu-1ubuntu220.04, mixed mode, sharing)"], "stdout": "", "stdout_lines": []}

TASK [confluent.platform.common : Print Java Version] **************************
ok: [kafka-controller-3-migrated] => {
    "msg": "Current Java Version is: openjdk version \"17.0.12\" 2024-07-16"
}

TASK [confluent.platform.common : Install pip] *********************************
changed: [kafka-controller-3-migrated] => {"cache_update_time": 1729175360, "cache_updated": false, "changed": true, "stderr": "debconf: delaying package configuration, since apt-utils is not installed\n", "stderr_lines": ["debconf: delaying package configuration, since apt-utils is not installed"], "stdout": "Reading package lists...\nBuilding dependency tree...\nReading state information...\nThe following additional packages will be installed:\n  binutils binutils-common binutils-x86-64-linux-gnu build-essential cpp cpp-9\n  dpkg-dev fakeroot g++ g++-9 gcc gcc-9 gcc-9-base libalgorithm-diff-perl\n  libalgorithm-diff-xs-perl libalgorithm-merge-perl libasan5 libatomic1\n  libbinutils libc-dev-bin libc6-dev libcc1-0 libcrypt-dev libctf-nobfd0\n  libctf0 libdpkg-perl libexpat1-dev libfakeroot libfile-fcntllock-perl\n  libgcc-9-dev libgdbm-compat4 libgdbm6 libgomp1 libisl22 libitm1\n  liblocale-gettext-perl liblsan0 libmpc3 libmpfr6 libperl5.30 libpython3-dev\n  libpython3.8 libpython3.8-dev libquadmath0 libstdc++-9-dev libtsan0\n  libubsan1 linux-libc-dev make manpages manpages-dev netbase patch perl\n  perl-modules-5.30 python-pip-whl python3-dev python3-distutils\n  python3-lib2to3 python3-setuptools python3-wheel python3.8-dev zlib1g-dev\nSuggested packages:\n  binutils-doc cpp-doc gcc-9-locales debian-keyring g++-multilib\n  g++-9-multilib gcc-9-doc gcc-multilib autoconf automake libtool flex bison\n  gdb gcc-doc gcc-9-multilib glibc-doc git bzr gdbm-l10n libstdc++-9-doc\n  make-doc man-browser ed diffutils-doc perl-doc libterm-readline-gnu-perl\n  | libterm-readline-perl-perl libb-debug-perl liblocale-codes-perl\n  python-setuptools-doc\nThe following NEW packages will be installed:\n  binutils binutils-common binutils-x86-64-linux-gnu build-essential cpp cpp-9\n  dpkg-dev fakeroot g++ g++-9 gcc gcc-9 gcc-9-base libalgorithm-diff-perl\n  libalgorithm-diff-xs-perl libalgorithm-merge-perl libasan5 libatomic1\n  libbinutils libc-dev-bin libc6-dev libcc1-0 libcrypt-dev libctf-nobfd0\n  libctf0 libdpkg-perl libexpat1-dev libfakeroot libfile-fcntllock-perl\n  libgcc-9-dev libgdbm-compat4 libgdbm6 libgomp1 libisl22 libitm1\n  liblocale-gettext-perl liblsan0 libmpc3 libmpfr6 libperl5.30 libpython3-dev\n  libpython3.8 libpython3.8-dev libquadmath0 libstdc++-9-dev libtsan0\n  libubsan1 linux-libc-dev make manpages manpages-dev netbase patch perl\n  perl-modules-5.30 python-pip-whl python3-dev python3-distutils\n  python3-lib2to3 python3-pip python3-setuptools python3-wheel python3.8-dev\n  zlib1g-dev\n0 upgraded, 64 newly installed, 0 to remove and 0 not upgraded.\nNeed to get 63.0 MB of archives.\nAfter this operation, 287 MB of additional disk space will be used.\nGet:1 http://archive.ubuntu.com/ubuntu focal/main amd64 liblocale-gettext-perl amd64 1.07-4 [17.1 kB]\nGet:2 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 perl-modules-5.30 all 5.30.0-9ubuntu0.5 [2739 kB]\nGet:3 http://archive.ubuntu.com/ubuntu focal/main amd64 libgdbm6 amd64 1.18.1-5 [27.4 kB]\nGet:4 http://archive.ubuntu.com/ubuntu focal/main amd64 libgdbm-compat4 amd64 1.18.1-5 [6244 B]\nGet:5 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libperl5.30 amd64 5.30.0-9ubuntu0.5 [3941 kB]\nGet:6 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 perl amd64 5.30.0-9ubuntu0.5 [224 kB]\nGet:7 http://archive.ubuntu.com/ubuntu focal/main amd64 netbase all 6.1 [13.1 kB]\nGet:8 http://archive.ubuntu.com/ubuntu focal/main amd64 manpages all 5.05-1 [1314 kB]\nGet:9 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 binutils-common amd64 2.34-6ubuntu1.9 [208 kB]\nGet:10 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libbinutils amd64 2.34-6ubuntu1.9 [475 kB]\nGet:11 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libctf-nobfd0 amd64 2.34-6ubuntu1.9 [48.2 kB]\nGet:12 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libctf0 amd64 2.34-6ubuntu1.9 [46.6 kB]\nGet:13 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 binutils-x86-64-linux-gnu amd64 2.34-6ubuntu1.9 [1614 kB]\nGet:14 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 binutils amd64 2.34-6ubuntu1.9 [3380 B]\nGet:15 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libc-dev-bin amd64 2.31-0ubuntu9.16 [71.6 kB]\nGet:16 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 linux-libc-dev amd64 5.4.0-198.218 [1130 kB]\nGet:17 http://archive.ubuntu.com/ubuntu focal/main amd64 libcrypt-dev amd64 1:4.4.10-10ubuntu4 [104 kB]\nGet:18 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libc6-dev amd64 2.31-0ubuntu9.16 [2520 kB]\nGet:19 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gcc-9-base amd64 9.4.0-1ubuntu1~20.04.2 [18.9 kB]\nGet:20 http://archive.ubuntu.com/ubuntu focal/main amd64 libisl22 amd64 0.22.1-1 [592 kB]\nGet:21 http://archive.ubuntu.com/ubuntu focal/main amd64 libmpfr6 amd64 4.0.2-1 [240 kB]\nGet:22 http://archive.ubuntu.com/ubuntu focal/main amd64 libmpc3 amd64 1.1.0-1 [40.8 kB]\nGet:23 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 cpp-9 amd64 9.4.0-1ubuntu1~20.04.2 [7502 kB]\nGet:24 http://archive.ubuntu.com/ubuntu focal/main amd64 cpp amd64 4:9.3.0-1ubuntu2 [27.6 kB]\nGet:25 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libcc1-0 amd64 10.5.0-1ubuntu1~20.04 [48.8 kB]\nGet:26 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgomp1 amd64 10.5.0-1ubuntu1~20.04 [102 kB]\nGet:27 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libitm1 amd64 10.5.0-1ubuntu1~20.04 [26.2 kB]\nGet:28 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libatomic1 amd64 10.5.0-1ubuntu1~20.04 [9284 B]\nGet:29 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libasan5 amd64 9.4.0-1ubuntu1~20.04.2 [2752 kB]\nGet:30 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 liblsan0 amd64 10.5.0-1ubuntu1~20.04 [835 kB]\nGet:31 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libtsan0 amd64 10.5.0-1ubuntu1~20.04 [2016 kB]\nGet:32 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libubsan1 amd64 10.5.0-1ubuntu1~20.04 [785 kB]\nGet:33 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libquadmath0 amd64 10.5.0-1ubuntu1~20.04 [146 kB]\nGet:34 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgcc-9-dev amd64 9.4.0-1ubuntu1~20.04.2 [2359 kB]\nGet:35 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gcc-9 amd64 9.4.0-1ubuntu1~20.04.2 [8276 kB]\nGet:36 http://archive.ubuntu.com/ubuntu focal/main amd64 gcc amd64 4:9.3.0-1ubuntu2 [5208 B]\nGet:37 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libstdc++-9-dev amd64 9.4.0-1ubuntu1~20.04.2 [1722 kB]\nGet:38 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 g++-9 amd64 9.4.0-1ubuntu1~20.04.2 [8421 kB]\nGet:39 http://archive.ubuntu.com/ubuntu focal/main amd64 g++ amd64 4:9.3.0-1ubuntu2 [1604 B]\nGet:40 http://archive.ubuntu.com/ubuntu focal/main amd64 make amd64 4.2.1-1.2 [162 kB]\nGet:41 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libdpkg-perl all 1.19.7ubuntu3.2 [231 kB]\nGet:42 http://archive.ubuntu.com/ubuntu focal/main amd64 patch amd64 2.7.6-6 [105 kB]\nGet:43 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 dpkg-dev all 1.19.7ubuntu3.2 [679 kB]\nGet:44 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 build-essential amd64 12.8ubuntu1.1 [4664 B]\nGet:45 http://archive.ubuntu.com/ubuntu focal/main amd64 libfakeroot amd64 1.24-1 [25.7 kB]\nGet:46 http://archive.ubuntu.com/ubuntu focal/main amd64 fakeroot amd64 1.24-1 [62.6 kB]\nGet:47 http://archive.ubuntu.com/ubuntu focal/main amd64 libalgorithm-diff-perl all 1.19.03-2 [46.6 kB]\nGet:48 http://archive.ubuntu.com/ubuntu focal/main amd64 libalgorithm-diff-xs-perl amd64 0.04-6 [11.3 kB]\nGet:49 http://archive.ubuntu.com/ubuntu focal/main amd64 libalgorithm-merge-perl all 0.08-3 [12.0 kB]\nGet:50 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libexpat1-dev amd64 2.2.9-1ubuntu0.7 [117 kB]\nGet:51 http://archive.ubuntu.com/ubuntu focal/main amd64 libfile-fcntllock-perl amd64 0.22-3build4 [33.1 kB]\nGet:52 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libpython3.8 amd64 3.8.10-0ubuntu1~20.04.12 [1626 kB]\nGet:53 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libpython3.8-dev amd64 3.8.10-0ubuntu1~20.04.12 [3947 kB]\nGet:54 http://archive.ubuntu.com/ubuntu focal/main amd64 libpython3-dev amd64 3.8.2-0ubuntu2 [7236 B]\nGet:55 http://archive.ubuntu.com/ubuntu focal/main amd64 manpages-dev all 5.05-1 [2266 kB]\nGet:56 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 python-pip-whl all 20.0.2-5ubuntu1.10 [1805 kB]\nGet:57 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 zlib1g-dev amd64 1:1.2.11.dfsg-2ubuntu1.5 [155 kB]\nGet:58 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 python3.8-dev amd64 3.8.10-0ubuntu1~20.04.12 [514 kB]\nGet:59 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 python3-lib2to3 all 3.8.10-0ubuntu1~20.04 [76.3 kB]\nGet:60 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 python3-distutils all 3.8.10-0ubuntu1~20.04 [141 kB]\nGet:61 http://archive.ubuntu.com/ubuntu focal/main amd64 python3-dev amd64 3.8.2-0ubuntu2 [1212 B]\nGet:62 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 python3-setuptools all 45.2.0-1ubuntu0.2 [330 kB]\nGet:63 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 python3-wheel all 0.34.2-1ubuntu0.1 [23.9 kB]\nGet:64 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 python3-pip all 20.0.2-5ubuntu1.10 [231 kB]\nFetched 63.0 MB in 3s (18.6 MB/s)\nSelecting previously unselected package liblocale-gettext-perl.\r\n(Reading database ... \r(Reading database ... 5%\r(Reading database ... 10%\r(Reading database ... 15%\r(Reading database ... 20%\r(Reading database ... 25%\r(Reading database ... 30%\r(Reading database ... 35%\r(Reading database ... 40%\r(Reading database ... 45%\r(Reading database ... 50%\r(Reading database ... 55%\r(Reading database ... 60%\r(Reading database ... 65%\r(Reading database ... 70%\r(Reading database ... 75%\r(Reading database ... 80%\r(Reading database ... 85%\r(Reading database ... 90%\r(Reading database ... 95%\r(Reading database ... 100%\r(Reading database ... 30315 files and directories currently installed.)\r\nPreparing to unpack .../00-liblocale-gettext-perl_1.07-4_amd64.deb ...\r\nUnpacking liblocale-gettext-perl (1.07-4) ...\r\nSelecting previously unselected package perl-modules-5.30.\r\nPreparing to unpack .../01-perl-modules-5.30_5.30.0-9ubuntu0.5_all.deb ...\r\nUnpacking perl-modules-5.30 (5.30.0-9ubuntu0.5) ...\r\nSelecting previously unselected package libgdbm6:amd64.\r\nPreparing to unpack .../02-libgdbm6_1.18.1-5_amd64.deb ...\r\nUnpacking libgdbm6:amd64 (1.18.1-5) ...\r\nSelecting previously unselected package libgdbm-compat4:amd64.\r\nPreparing to unpack .../03-libgdbm-compat4_1.18.1-5_amd64.deb ...\r\nUnpacking libgdbm-compat4:amd64 (1.18.1-5) ...\r\nSelecting previously unselected package libperl5.30:amd64.\r\nPreparing to unpack .../04-libperl5.30_5.30.0-9ubuntu0.5_amd64.deb ...\r\nUnpacking libperl5.30:amd64 (5.30.0-9ubuntu0.5) ...\r\nSelecting previously unselected package perl.\r\nPreparing to unpack .../05-perl_5.30.0-9ubuntu0.5_amd64.deb ...\r\nUnpacking perl (5.30.0-9ubuntu0.5) ...\r\nSelecting previously unselected package netbase.\r\nPreparing to unpack .../06-netbase_6.1_all.deb ...\r\nUnpacking netbase (6.1) ...\r\nSelecting previously unselected package manpages.\r\nPreparing to unpack .../07-manpages_5.05-1_all.deb ...\r\nUnpacking manpages (5.05-1) ...\r\nSelecting previously unselected package binutils-common:amd64.\r\nPreparing to unpack .../08-binutils-common_2.34-6ubuntu1.9_amd64.deb ...\r\nUnpacking binutils-common:amd64 (2.34-6ubuntu1.9) ...\r\nSelecting previously unselected package libbinutils:amd64.\r\nPreparing to unpack .../09-libbinutils_2.34-6ubuntu1.9_amd64.deb ...\r\nUnpacking libbinutils:amd64 (2.34-6ubuntu1.9) ...\r\nSelecting previously unselected package libctf-nobfd0:amd64.\r\nPreparing to unpack .../10-libctf-nobfd0_2.34-6ubuntu1.9_amd64.deb ...\r\nUnpacking libctf-nobfd0:amd64 (2.34-6ubuntu1.9) ...\r\nSelecting previously unselected package libctf0:amd64.\r\nPreparing to unpack .../11-libctf0_2.34-6ubuntu1.9_amd64.deb ...\r\nUnpacking libctf0:amd64 (2.34-6ubuntu1.9) ...\r\nSelecting previously unselected package binutils-x86-64-linux-gnu.\r\nPreparing to unpack .../12-binutils-x86-64-linux-gnu_2.34-6ubuntu1.9_amd64.deb ...\r\nUnpacking binutils-x86-64-linux-gnu (2.34-6ubuntu1.9) ...\r\nSelecting previously unselected package binutils.\r\nPreparing to unpack .../13-binutils_2.34-6ubuntu1.9_amd64.deb ...\r\nUnpacking binutils (2.34-6ubuntu1.9) ...\r\nSelecting previously unselected package libc-dev-bin.\r\nPreparing to unpack .../14-libc-dev-bin_2.31-0ubuntu9.16_amd64.deb ...\r\nUnpacking libc-dev-bin (2.31-0ubuntu9.16) ...\r\nSelecting previously unselected package linux-libc-dev:amd64.\r\nPreparing to unpack .../15-linux-libc-dev_5.4.0-198.218_amd64.deb ...\r\nUnpacking linux-libc-dev:amd64 (5.4.0-198.218) ...\r\nSelecting previously unselected package libcrypt-dev:amd64.\r\nPreparing to unpack .../16-libcrypt-dev_1%3a4.4.10-10ubuntu4_amd64.deb ...\r\nUnpacking libcrypt-dev:amd64 (1:4.4.10-10ubuntu4) ...\r\nSelecting previously unselected package libc6-dev:amd64.\r\nPreparing to unpack .../17-libc6-dev_2.31-0ubuntu9.16_amd64.deb ...\r\nUnpacking libc6-dev:amd64 (2.31-0ubuntu9.16) ...\r\nSelecting previously unselected package gcc-9-base:amd64.\r\nPreparing to unpack .../18-gcc-9-base_9.4.0-1ubuntu1~20.04.2_amd64.deb ...\r\nUnpacking gcc-9-base:amd64 (9.4.0-1ubuntu1~20.04.2) ...\r\nSelecting previously unselected package libisl22:amd64.\r\nPreparing to unpack .../19-libisl22_0.22.1-1_amd64.deb ...\r\nUnpacking libisl22:amd64 (0.22.1-1) ...\r\nSelecting previously unselected package libmpfr6:amd64.\r\nPreparing to unpack .../20-libmpfr6_4.0.2-1_amd64.deb ...\r\nUnpacking libmpfr6:amd64 (4.0.2-1) ...\r\nSelecting previously unselected package libmpc3:amd64.\r\nPreparing to unpack .../21-libmpc3_1.1.0-1_amd64.deb ...\r\nUnpacking libmpc3:amd64 (1.1.0-1) ...\r\nSelecting previously unselected package cpp-9.\r\nPreparing to unpack .../22-cpp-9_9.4.0-1ubuntu1~20.04.2_amd64.deb ...\r\nUnpacking cpp-9 (9.4.0-1ubuntu1~20.04.2) ...\r\nSelecting previously unselected package cpp.\r\nPreparing to unpack .../23-cpp_4%3a9.3.0-1ubuntu2_amd64.deb ...\r\nUnpacking cpp (4:9.3.0-1ubuntu2) ...\r\nSelecting previously unselected package libcc1-0:amd64.\r\nPreparing to unpack .../24-libcc1-0_10.5.0-1ubuntu1~20.04_amd64.deb ...\r\nUnpacking libcc1-0:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSelecting previously unselected package libgomp1:amd64.\r\nPreparing to unpack .../25-libgomp1_10.5.0-1ubuntu1~20.04_amd64.deb ...\r\nUnpacking libgomp1:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSelecting previously unselected package libitm1:amd64.\r\nPreparing to unpack .../26-libitm1_10.5.0-1ubuntu1~20.04_amd64.deb ...\r\nUnpacking libitm1:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSelecting previously unselected package libatomic1:amd64.\r\nPreparing to unpack .../27-libatomic1_10.5.0-1ubuntu1~20.04_amd64.deb ...\r\nUnpacking libatomic1:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSelecting previously unselected package libasan5:amd64.\r\nPreparing to unpack .../28-libasan5_9.4.0-1ubuntu1~20.04.2_amd64.deb ...\r\nUnpacking libasan5:amd64 (9.4.0-1ubuntu1~20.04.2) ...\r\nSelecting previously unselected package liblsan0:amd64.\r\nPreparing to unpack .../29-liblsan0_10.5.0-1ubuntu1~20.04_amd64.deb ...\r\nUnpacking liblsan0:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSelecting previously unselected package libtsan0:amd64.\r\nPreparing to unpack .../30-libtsan0_10.5.0-1ubuntu1~20.04_amd64.deb ...\r\nUnpacking libtsan0:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSelecting previously unselected package libubsan1:amd64.\r\nPreparing to unpack .../31-libubsan1_10.5.0-1ubuntu1~20.04_amd64.deb ...\r\nUnpacking libubsan1:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSelecting previously unselected package libquadmath0:amd64.\r\nPreparing to unpack .../32-libquadmath0_10.5.0-1ubuntu1~20.04_amd64.deb ...\r\nUnpacking libquadmath0:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSelecting previously unselected package libgcc-9-dev:amd64.\r\nPreparing to unpack .../33-libgcc-9-dev_9.4.0-1ubuntu1~20.04.2_amd64.deb ...\r\nUnpacking libgcc-9-dev:amd64 (9.4.0-1ubuntu1~20.04.2) ...\r\nSelecting previously unselected package gcc-9.\r\nPreparing to unpack .../34-gcc-9_9.4.0-1ubuntu1~20.04.2_amd64.deb ...\r\nUnpacking gcc-9 (9.4.0-1ubuntu1~20.04.2) ...\r\nSelecting previously unselected package gcc.\r\nPreparing to unpack .../35-gcc_4%3a9.3.0-1ubuntu2_amd64.deb ...\r\nUnpacking gcc (4:9.3.0-1ubuntu2) ...\r\nSelecting previously unselected package libstdc++-9-dev:amd64.\r\nPreparing to unpack .../36-libstdc++-9-dev_9.4.0-1ubuntu1~20.04.2_amd64.deb ...\r\nUnpacking libstdc++-9-dev:amd64 (9.4.0-1ubuntu1~20.04.2) ...\r\nSelecting previously unselected package g++-9.\r\nPreparing to unpack .../37-g++-9_9.4.0-1ubuntu1~20.04.2_amd64.deb ...\r\nUnpacking g++-9 (9.4.0-1ubuntu1~20.04.2) ...\r\nSelecting previously unselected package g++.\r\nPreparing to unpack .../38-g++_4%3a9.3.0-1ubuntu2_amd64.deb ...\r\nUnpacking g++ (4:9.3.0-1ubuntu2) ...\r\nSelecting previously unselected package make.\r\nPreparing to unpack .../39-make_4.2.1-1.2_amd64.deb ...\r\nUnpacking make (4.2.1-1.2) ...\r\nSelecting previously unselected package libdpkg-perl.\r\nPreparing to unpack .../40-libdpkg-perl_1.19.7ubuntu3.2_all.deb ...\r\nUnpacking libdpkg-perl (1.19.7ubuntu3.2) ...\r\nSelecting previously unselected package patch.\r\nPreparing to unpack .../41-patch_2.7.6-6_amd64.deb ...\r\nUnpacking patch (2.7.6-6) ...\r\nSelecting previously unselected package dpkg-dev.\r\nPreparing to unpack .../42-dpkg-dev_1.19.7ubuntu3.2_all.deb ...\r\nUnpacking dpkg-dev (1.19.7ubuntu3.2) ...\r\nSelecting previously unselected package build-essential.\r\nPreparing to unpack .../43-build-essential_12.8ubuntu1.1_amd64.deb ...\r\nUnpacking build-essential (12.8ubuntu1.1) ...\r\nSelecting previously unselected package libfakeroot:amd64.\r\nPreparing to unpack .../44-libfakeroot_1.24-1_amd64.deb ...\r\nUnpacking libfakeroot:amd64 (1.24-1) ...\r\nSelecting previously unselected package fakeroot.\r\nPreparing to unpack .../45-fakeroot_1.24-1_amd64.deb ...\r\nUnpacking fakeroot (1.24-1) ...\r\nSelecting previously unselected package libalgorithm-diff-perl.\r\nPreparing to unpack .../46-libalgorithm-diff-perl_1.19.03-2_all.deb ...\r\nUnpacking libalgorithm-diff-perl (1.19.03-2) ...\r\nSelecting previously unselected package libalgorithm-diff-xs-perl.\r\nPreparing to unpack .../47-libalgorithm-diff-xs-perl_0.04-6_amd64.deb ...\r\nUnpacking libalgorithm-diff-xs-perl (0.04-6) ...\r\nSelecting previously unselected package libalgorithm-merge-perl.\r\nPreparing to unpack .../48-libalgorithm-merge-perl_0.08-3_all.deb ...\r\nUnpacking libalgorithm-merge-perl (0.08-3) ...\r\nSelecting previously unselected package libexpat1-dev:amd64.\r\nPreparing to unpack .../49-libexpat1-dev_2.2.9-1ubuntu0.7_amd64.deb ...\r\nUnpacking libexpat1-dev:amd64 (2.2.9-1ubuntu0.7) ...\r\nSelecting previously unselected package libfile-fcntllock-perl.\r\nPreparing to unpack .../50-libfile-fcntllock-perl_0.22-3build4_amd64.deb ...\r\nUnpacking libfile-fcntllock-perl (0.22-3build4) ...\r\nSelecting previously unselected package libpython3.8:amd64.\r\nPreparing to unpack .../51-libpython3.8_3.8.10-0ubuntu1~20.04.12_amd64.deb ...\r\nUnpacking libpython3.8:amd64 (3.8.10-0ubuntu1~20.04.12) ...\r\nSelecting previously unselected package libpython3.8-dev:amd64.\r\nPreparing to unpack .../52-libpython3.8-dev_3.8.10-0ubuntu1~20.04.12_amd64.deb ...\r\nUnpacking libpython3.8-dev:amd64 (3.8.10-0ubuntu1~20.04.12) ...\r\nSelecting previously unselected package libpython3-dev:amd64.\r\nPreparing to unpack .../53-libpython3-dev_3.8.2-0ubuntu2_amd64.deb ...\r\nUnpacking libpython3-dev:amd64 (3.8.2-0ubuntu2) ...\r\nSelecting previously unselected package manpages-dev.\r\nPreparing to unpack .../54-manpages-dev_5.05-1_all.deb ...\r\nUnpacking manpages-dev (5.05-1) ...\r\nSelecting previously unselected package python-pip-whl.\r\nPreparing to unpack .../55-python-pip-whl_20.0.2-5ubuntu1.10_all.deb ...\r\nUnpacking python-pip-whl (20.0.2-5ubuntu1.10) ...\r\nSelecting previously unselected package zlib1g-dev:amd64.\r\nPreparing to unpack .../56-zlib1g-dev_1%3a1.2.11.dfsg-2ubuntu1.5_amd64.deb ...\r\nUnpacking zlib1g-dev:amd64 (1:1.2.11.dfsg-2ubuntu1.5) ...\r\nSelecting previously unselected package python3.8-dev.\r\nPreparing to unpack .../57-python3.8-dev_3.8.10-0ubuntu1~20.04.12_amd64.deb ...\r\nUnpacking python3.8-dev (3.8.10-0ubuntu1~20.04.12) ...\r\nSelecting previously unselected package python3-lib2to3.\r\nPreparing to unpack .../58-python3-lib2to3_3.8.10-0ubuntu1~20.04_all.deb ...\r\nUnpacking python3-lib2to3 (3.8.10-0ubuntu1~20.04) ...\r\nSelecting previously unselected package python3-distutils.\r\nPreparing to unpack .../59-python3-distutils_3.8.10-0ubuntu1~20.04_all.deb ...\r\nUnpacking python3-distutils (3.8.10-0ubuntu1~20.04) ...\r\nSelecting previously unselected package python3-dev.\r\nPreparing to unpack .../60-python3-dev_3.8.2-0ubuntu2_amd64.deb ...\r\nUnpacking python3-dev (3.8.2-0ubuntu2) ...\r\nSelecting previously unselected package python3-setuptools.\r\nPreparing to unpack .../61-python3-setuptools_45.2.0-1ubuntu0.2_all.deb ...\r\nUnpacking python3-setuptools (45.2.0-1ubuntu0.2) ...\r\nSelecting previously unselected package python3-wheel.\r\nPreparing to unpack .../62-python3-wheel_0.34.2-1ubuntu0.1_all.deb ...\r\nUnpacking python3-wheel (0.34.2-1ubuntu0.1) ...\r\nSelecting previously unselected package python3-pip.\r\nPreparing to unpack .../63-python3-pip_20.0.2-5ubuntu1.10_all.deb ...\r\nUnpacking python3-pip (20.0.2-5ubuntu1.10) ...\r\nSetting up perl-modules-5.30 (5.30.0-9ubuntu0.5) ...\r\nSetting up manpages (5.05-1) ...\r\nSetting up binutils-common:amd64 (2.34-6ubuntu1.9) ...\r\nSetting up linux-libc-dev:amd64 (5.4.0-198.218) ...\r\nSetting up libctf-nobfd0:amd64 (2.34-6ubuntu1.9) ...\r\nSetting up libgomp1:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSetting up python3-wheel (0.34.2-1ubuntu0.1) ...\r\nSetting up libfakeroot:amd64 (1.24-1) ...\r\nSetting up fakeroot (1.24-1) ...\r\nupdate-alternatives: using /usr/bin/fakeroot-sysv to provide /usr/bin/fakeroot (fakeroot) in auto mode\r\nupdate-alternatives: warning: skip creation of /usr/share/man/man1/fakeroot.1.gz because associated file /usr/share/man/man1/fakeroot-sysv.1.gz (of link group fakeroot) doesn't exist\r\nupdate-alternatives: warning: skip creation of /usr/share/man/man1/faked.1.gz because associated file /usr/share/man/man1/faked-sysv.1.gz (of link group fakeroot) doesn't exist\r\nupdate-alternatives: warning: skip creation of /usr/share/man/es/man1/fakeroot.1.gz because associated file /usr/share/man/es/man1/fakeroot-sysv.1.gz (of link group fakeroot) doesn't exist\r\nupdate-alternatives: warning: skip creation of /usr/share/man/es/man1/faked.1.gz because associated file /usr/share/man/es/man1/faked-sysv.1.gz (of link group fakeroot) doesn't exist\r\nupdate-alternatives: warning: skip creation of /usr/share/man/fr/man1/fakeroot.1.gz because associated file /usr/share/man/fr/man1/fakeroot-sysv.1.gz (of link group fakeroot) doesn't exist\r\nupdate-alternatives: warning: skip creation of /usr/share/man/fr/man1/faked.1.gz because associated file /usr/share/man/fr/man1/faked-sysv.1.gz (of link group fakeroot) doesn't exist\r\nupdate-alternatives: warning: skip creation of /usr/share/man/sv/man1/fakeroot.1.gz because associated file /usr/share/man/sv/man1/fakeroot-sysv.1.gz (of link group fakeroot) doesn't exist\r\nupdate-alternatives: warning: skip creation of /usr/share/man/sv/man1/faked.1.gz because associated file /usr/share/man/sv/man1/faked-sysv.1.gz (of link group fakeroot) doesn't exist\r\nSetting up make (4.2.1-1.2) ...\r\nSetting up libmpfr6:amd64 (4.0.2-1) ...\r\nSetting up libpython3.8:amd64 (3.8.10-0ubuntu1~20.04.12) ...\r\nSetting up libquadmath0:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSetting up libmpc3:amd64 (1.1.0-1) ...\r\nSetting up libatomic1:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSetting up patch (2.7.6-6) ...\r\nSetting up libubsan1:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSetting up libcrypt-dev:amd64 (1:4.4.10-10ubuntu4) ...\r\nSetting up libisl22:amd64 (0.22.1-1) ...\r\nSetting up netbase (6.1) ...\r\nSetting up python-pip-whl (20.0.2-5ubuntu1.10) ...\r\nSetting up libbinutils:amd64 (2.34-6ubuntu1.9) ...\r\nSetting up libc-dev-bin (2.31-0ubuntu9.16) ...\r\nSetting up python3-lib2to3 (3.8.10-0ubuntu1~20.04) ...\r\nSetting up libcc1-0:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSetting up liblocale-gettext-perl (1.07-4) ...\r\nSetting up liblsan0:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSetting up libitm1:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSetting up libgdbm6:amd64 (1.18.1-5) ...\r\nSetting up gcc-9-base:amd64 (9.4.0-1ubuntu1~20.04.2) ...\r\nSetting up libtsan0:amd64 (10.5.0-1ubuntu1~20.04) ...\r\nSetting up libctf0:amd64 (2.34-6ubuntu1.9) ...\r\nSetting up python3-distutils (3.8.10-0ubuntu1~20.04) ...\r\nSetting up manpages-dev (5.05-1) ...\r\nSetting up python3-setuptools (45.2.0-1ubuntu0.2) ...\r\nSetting up libasan5:amd64 (9.4.0-1ubuntu1~20.04.2) ...\r\nSetting up libgdbm-compat4:amd64 (1.18.1-5) ...\r\nSetting up python3-pip (20.0.2-5ubuntu1.10) ...\r\nSetting up cpp-9 (9.4.0-1ubuntu1~20.04.2) ...\r\nSetting up libperl5.30:amd64 (5.30.0-9ubuntu0.5) ...\r\nSetting up libc6-dev:amd64 (2.31-0ubuntu9.16) ...\r\nSetting up binutils-x86-64-linux-gnu (2.34-6ubuntu1.9) ...\r\nSetting up binutils (2.34-6ubuntu1.9) ...\r\nSetting up libgcc-9-dev:amd64 (9.4.0-1ubuntu1~20.04.2) ...\r\nSetting up perl (5.30.0-9ubuntu0.5) ...\r\nSetting up libexpat1-dev:amd64 (2.2.9-1ubuntu0.7) ...\r\nSetting up libpython3.8-dev:amd64 (3.8.10-0ubuntu1~20.04.12) ...\r\nSetting up libdpkg-perl (1.19.7ubuntu3.2) ...\r\nSetting up zlib1g-dev:amd64 (1:1.2.11.dfsg-2ubuntu1.5) ...\r\nSetting up cpp (4:9.3.0-1ubuntu2) ...\r\nSetting up gcc-9 (9.4.0-1ubuntu1~20.04.2) ...\r\nSetting up libpython3-dev:amd64 (3.8.2-0ubuntu2) ...\r\nSetting up libstdc++-9-dev:amd64 (9.4.0-1ubuntu1~20.04.2) ...\r\nSetting up libfile-fcntllock-perl (0.22-3build4) ...\r\nSetting up libalgorithm-diff-perl (1.19.03-2) ...\r\nSetting up gcc (4:9.3.0-1ubuntu2) ...\r\nSetting up dpkg-dev (1.19.7ubuntu3.2) ...\r\nSetting up g++-9 (9.4.0-1ubuntu1~20.04.2) ...\r\nSetting up python3.8-dev (3.8.10-0ubuntu1~20.04.12) ...\r\nSetting up g++ (4:9.3.0-1ubuntu2) ...\r\nupdate-alternatives: using /usr/bin/g++ to provide /usr/bin/c++ (c++) in auto mode\r\nupdate-alternatives: warning: skip creation of /usr/share/man/man1/c++.1.gz because associated file /usr/share/man/man1/g++.1.gz (of link group c++) doesn't exist\r\nSetting up build-essential (12.8ubuntu1.1) ...\r\nSetting up libalgorithm-diff-xs-perl (0.04-6) ...\r\nSetting up libalgorithm-merge-perl (0.08-3) ...\r\nSetting up python3-dev (3.8.2-0ubuntu2) ...\r\nProcessing triggers for libc-bin (2.31-0ubuntu9.16) ...\r\n", "stdout_lines": ["Reading package lists...", "Building dependency tree...", "Reading state information...", "The following additional packages will be installed:", "  binutils binutils-common binutils-x86-64-linux-gnu build-essential cpp cpp-9", "  dpkg-dev fakeroot g++ g++-9 gcc gcc-9 gcc-9-base libalgorithm-diff-perl", "  libalgorithm-diff-xs-perl libalgorithm-merge-perl libasan5 libatomic1", "  libbinutils libc-dev-bin libc6-dev libcc1-0 libcrypt-dev libctf-nobfd0", "  libctf0 libdpkg-perl libexpat1-dev libfakeroot libfile-fcntllock-perl", "  libgcc-9-dev libgdbm-compat4 libgdbm6 libgomp1 libisl22 libitm1", "  liblocale-gettext-perl liblsan0 libmpc3 libmpfr6 libperl5.30 libpython3-dev", "  libpython3.8 libpython3.8-dev libquadmath0 libstdc++-9-dev libtsan0", "  libubsan1 linux-libc-dev make manpages manpages-dev netbase patch perl", "  perl-modules-5.30 python-pip-whl python3-dev python3-distutils", "  python3-lib2to3 python3-setuptools python3-wheel python3.8-dev zlib1g-dev", "Suggested packages:", "  binutils-doc cpp-doc gcc-9-locales debian-keyring g++-multilib", "  g++-9-multilib gcc-9-doc gcc-multilib autoconf automake libtool flex bison", "  gdb gcc-doc gcc-9-multilib glibc-doc git bzr gdbm-l10n libstdc++-9-doc", "  make-doc man-browser ed diffutils-doc perl-doc libterm-readline-gnu-perl", "  | libterm-readline-perl-perl libb-debug-perl liblocale-codes-perl", "  python-setuptools-doc", "The following NEW packages will be installed:", "  binutils binutils-common binutils-x86-64-linux-gnu build-essential cpp cpp-9", "  dpkg-dev fakeroot g++ g++-9 gcc gcc-9 gcc-9-base libalgorithm-diff-perl", "  libalgorithm-diff-xs-perl libalgorithm-merge-perl libasan5 libatomic1", "  libbinutils libc-dev-bin libc6-dev libcc1-0 libcrypt-dev libctf-nobfd0", "  libctf0 libdpkg-perl libexpat1-dev libfakeroot libfile-fcntllock-perl", "  libgcc-9-dev libgdbm-compat4 libgdbm6 libgomp1 libisl22 libitm1", "  liblocale-gettext-perl liblsan0 libmpc3 libmpfr6 libperl5.30 libpython3-dev", "  libpython3.8 libpython3.8-dev libquadmath0 libstdc++-9-dev libtsan0", "  libubsan1 linux-libc-dev make manpages manpages-dev netbase patch perl", "  perl-modules-5.30 python-pip-whl python3-dev python3-distutils", "  python3-lib2to3 python3-pip python3-setuptools python3-wheel python3.8-dev", "  zlib1g-dev", "0 upgraded, 64 newly installed, 0 to remove and 0 not upgraded.", "Need to get 63.0 MB of archives.", "After this operation, 287 MB of additional disk space will be used.", "Get:1 http://archive.ubuntu.com/ubuntu focal/main amd64 liblocale-gettext-perl amd64 1.07-4 [17.1 kB]", "Get:2 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 perl-modules-5.30 all 5.30.0-9ubuntu0.5 [2739 kB]", "Get:3 http://archive.ubuntu.com/ubuntu focal/main amd64 libgdbm6 amd64 1.18.1-5 [27.4 kB]", "Get:4 http://archive.ubuntu.com/ubuntu focal/main amd64 libgdbm-compat4 amd64 1.18.1-5 [6244 B]", "Get:5 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libperl5.30 amd64 5.30.0-9ubuntu0.5 [3941 kB]", "Get:6 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 perl amd64 5.30.0-9ubuntu0.5 [224 kB]", "Get:7 http://archive.ubuntu.com/ubuntu focal/main amd64 netbase all 6.1 [13.1 kB]", "Get:8 http://archive.ubuntu.com/ubuntu focal/main amd64 manpages all 5.05-1 [1314 kB]", "Get:9 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 binutils-common amd64 2.34-6ubuntu1.9 [208 kB]", "Get:10 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libbinutils amd64 2.34-6ubuntu1.9 [475 kB]", "Get:11 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libctf-nobfd0 amd64 2.34-6ubuntu1.9 [48.2 kB]", "Get:12 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libctf0 amd64 2.34-6ubuntu1.9 [46.6 kB]", "Get:13 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 binutils-x86-64-linux-gnu amd64 2.34-6ubuntu1.9 [1614 kB]", "Get:14 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 binutils amd64 2.34-6ubuntu1.9 [3380 B]", "Get:15 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libc-dev-bin amd64 2.31-0ubuntu9.16 [71.6 kB]", "Get:16 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 linux-libc-dev amd64 5.4.0-198.218 [1130 kB]", "Get:17 http://archive.ubuntu.com/ubuntu focal/main amd64 libcrypt-dev amd64 1:4.4.10-10ubuntu4 [104 kB]", "Get:18 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libc6-dev amd64 2.31-0ubuntu9.16 [2520 kB]", "Get:19 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gcc-9-base amd64 9.4.0-1ubuntu1~20.04.2 [18.9 kB]", "Get:20 http://archive.ubuntu.com/ubuntu focal/main amd64 libisl22 amd64 0.22.1-1 [592 kB]", "Get:21 http://archive.ubuntu.com/ubuntu focal/main amd64 libmpfr6 amd64 4.0.2-1 [240 kB]", "Get:22 http://archive.ubuntu.com/ubuntu focal/main amd64 libmpc3 amd64 1.1.0-1 [40.8 kB]", "Get:23 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 cpp-9 amd64 9.4.0-1ubuntu1~20.04.2 [7502 kB]", "Get:24 http://archive.ubuntu.com/ubuntu focal/main amd64 cpp amd64 4:9.3.0-1ubuntu2 [27.6 kB]", "Get:25 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libcc1-0 amd64 10.5.0-1ubuntu1~20.04 [48.8 kB]", "Get:26 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgomp1 amd64 10.5.0-1ubuntu1~20.04 [102 kB]", "Get:27 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libitm1 amd64 10.5.0-1ubuntu1~20.04 [26.2 kB]", "Get:28 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libatomic1 amd64 10.5.0-1ubuntu1~20.04 [9284 B]", "Get:29 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libasan5 amd64 9.4.0-1ubuntu1~20.04.2 [2752 kB]", "Get:30 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 liblsan0 amd64 10.5.0-1ubuntu1~20.04 [835 kB]", "Get:31 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libtsan0 amd64 10.5.0-1ubuntu1~20.04 [2016 kB]", "Get:32 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libubsan1 amd64 10.5.0-1ubuntu1~20.04 [785 kB]", "Get:33 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libquadmath0 amd64 10.5.0-1ubuntu1~20.04 [146 kB]", "Get:34 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libgcc-9-dev amd64 9.4.0-1ubuntu1~20.04.2 [2359 kB]", "Get:35 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 gcc-9 amd64 9.4.0-1ubuntu1~20.04.2 [8276 kB]", "Get:36 http://archive.ubuntu.com/ubuntu focal/main amd64 gcc amd64 4:9.3.0-1ubuntu2 [5208 B]", "Get:37 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libstdc++-9-dev amd64 9.4.0-1ubuntu1~20.04.2 [1722 kB]", "Get:38 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 g++-9 amd64 9.4.0-1ubuntu1~20.04.2 [8421 kB]", "Get:39 http://archive.ubuntu.com/ubuntu focal/main amd64 g++ amd64 4:9.3.0-1ubuntu2 [1604 B]", "Get:40 http://archive.ubuntu.com/ubuntu focal/main amd64 make amd64 4.2.1-1.2 [162 kB]", "Get:41 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libdpkg-perl all 1.19.7ubuntu3.2 [231 kB]", "Get:42 http://archive.ubuntu.com/ubuntu focal/main amd64 patch amd64 2.7.6-6 [105 kB]", "Get:43 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 dpkg-dev all 1.19.7ubuntu3.2 [679 kB]", "Get:44 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 build-essential amd64 12.8ubuntu1.1 [4664 B]", "Get:45 http://archive.ubuntu.com/ubuntu focal/main amd64 libfakeroot amd64 1.24-1 [25.7 kB]", "Get:46 http://archive.ubuntu.com/ubuntu focal/main amd64 fakeroot amd64 1.24-1 [62.6 kB]", "Get:47 http://archive.ubuntu.com/ubuntu focal/main amd64 libalgorithm-diff-perl all 1.19.03-2 [46.6 kB]", "Get:48 http://archive.ubuntu.com/ubuntu focal/main amd64 libalgorithm-diff-xs-perl amd64 0.04-6 [11.3 kB]", "Get:49 http://archive.ubuntu.com/ubuntu focal/main amd64 libalgorithm-merge-perl all 0.08-3 [12.0 kB]", "Get:50 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libexpat1-dev amd64 2.2.9-1ubuntu0.7 [117 kB]", "Get:51 http://archive.ubuntu.com/ubuntu focal/main amd64 libfile-fcntllock-perl amd64 0.22-3build4 [33.1 kB]", "Get:52 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libpython3.8 amd64 3.8.10-0ubuntu1~20.04.12 [1626 kB]", "Get:53 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 libpython3.8-dev amd64 3.8.10-0ubuntu1~20.04.12 [3947 kB]", "Get:54 http://archive.ubuntu.com/ubuntu focal/main amd64 libpython3-dev amd64 3.8.2-0ubuntu2 [7236 B]", "Get:55 http://archive.ubuntu.com/ubuntu focal/main amd64 manpages-dev all 5.05-1 [2266 kB]", "Get:56 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 python-pip-whl all 20.0.2-5ubuntu1.10 [1805 kB]", "Get:57 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 zlib1g-dev amd64 1:1.2.11.dfsg-2ubuntu1.5 [155 kB]", "Get:58 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 python3.8-dev amd64 3.8.10-0ubuntu1~20.04.12 [514 kB]", "Get:59 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 python3-lib2to3 all 3.8.10-0ubuntu1~20.04 [76.3 kB]", "Get:60 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 python3-distutils all 3.8.10-0ubuntu1~20.04 [141 kB]", "Get:61 http://archive.ubuntu.com/ubuntu focal/main amd64 python3-dev amd64 3.8.2-0ubuntu2 [1212 B]", "Get:62 http://archive.ubuntu.com/ubuntu focal-updates/main amd64 python3-setuptools all 45.2.0-1ubuntu0.2 [330 kB]", "Get:63 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 python3-wheel all 0.34.2-1ubuntu0.1 [23.9 kB]", "Get:64 http://archive.ubuntu.com/ubuntu focal-updates/universe amd64 python3-pip all 20.0.2-5ubuntu1.10 [231 kB]", "Fetched 63.0 MB in 3s (18.6 MB/s)", "Selecting previously unselected package liblocale-gettext-perl.", "(Reading database ... ", "(Reading database ... 5%", "(Reading database ... 10%", "(Reading database ... 15%", "(Reading database ... 20%", "(Reading database ... 25%", "(Reading database ... 30%", "(Reading database ... 35%", "(Reading database ... 40%", "(Reading database ... 45%", "(Reading database ... 50%", "(Reading database ... 55%", "(Reading database ... 60%", "(Reading database ... 65%", "(Reading database ... 70%", "(Reading database ... 75%", "(Reading database ... 80%", "(Reading database ... 85%", "(Reading database ... 90%", "(Reading database ... 95%", "(Reading database ... 100%", "(Reading database ... 30315 files and directories currently installed.)", "Preparing to unpack .../00-liblocale-gettext-perl_1.07-4_amd64.deb ...", "Unpacking liblocale-gettext-perl (1.07-4) ...", "Selecting previously unselected package perl-modules-5.30.", "Preparing to unpack .../01-perl-modules-5.30_5.30.0-9ubuntu0.5_all.deb ...", "Unpacking perl-modules-5.30 (5.30.0-9ubuntu0.5) ...", "Selecting previously unselected package libgdbm6:amd64.", "Preparing to unpack .../02-libgdbm6_1.18.1-5_amd64.deb ...", "Unpacking libgdbm6:amd64 (1.18.1-5) ...", "Selecting previously unselected package libgdbm-compat4:amd64.", "Preparing to unpack .../03-libgdbm-compat4_1.18.1-5_amd64.deb ...", "Unpacking libgdbm-compat4:amd64 (1.18.1-5) ...", "Selecting previously unselected package libperl5.30:amd64.", "Preparing to unpack .../04-libperl5.30_5.30.0-9ubuntu0.5_amd64.deb ...", "Unpacking libperl5.30:amd64 (5.30.0-9ubuntu0.5) ...", "Selecting previously unselected package perl.", "Preparing to unpack .../05-perl_5.30.0-9ubuntu0.5_amd64.deb ...", "Unpacking perl (5.30.0-9ubuntu0.5) ...", "Selecting previously unselected package netbase.", "Preparing to unpack .../06-netbase_6.1_all.deb ...", "Unpacking netbase (6.1) ...", "Selecting previously unselected package manpages.", "Preparing to unpack .../07-manpages_5.05-1_all.deb ...", "Unpacking manpages (5.05-1) ...", "Selecting previously unselected package binutils-common:amd64.", "Preparing to unpack .../08-binutils-common_2.34-6ubuntu1.9_amd64.deb ...", "Unpacking binutils-common:amd64 (2.34-6ubuntu1.9) ...", "Selecting previously unselected package libbinutils:amd64.", "Preparing to unpack .../09-libbinutils_2.34-6ubuntu1.9_amd64.deb ...", "Unpacking libbinutils:amd64 (2.34-6ubuntu1.9) ...", "Selecting previously unselected package libctf-nobfd0:amd64.", "Preparing to unpack .../10-libctf-nobfd0_2.34-6ubuntu1.9_amd64.deb ...", "Unpacking libctf-nobfd0:amd64 (2.34-6ubuntu1.9) ...", "Selecting previously unselected package libctf0:amd64.", "Preparing to unpack .../11-libctf0_2.34-6ubuntu1.9_amd64.deb ...", "Unpacking libctf0:amd64 (2.34-6ubuntu1.9) ...", "Selecting previously unselected package binutils-x86-64-linux-gnu.", "Preparing to unpack .../12-binutils-x86-64-linux-gnu_2.34-6ubuntu1.9_amd64.deb ...", "Unpacking binutils-x86-64-linux-gnu (2.34-6ubuntu1.9) ...", "Selecting previously unselected package binutils.", "Preparing to unpack .../13-binutils_2.34-6ubuntu1.9_amd64.deb ...", "Unpacking binutils (2.34-6ubuntu1.9) ...", "Selecting previously unselected package libc-dev-bin.", "Preparing to unpack .../14-libc-dev-bin_2.31-0ubuntu9.16_amd64.deb ...", "Unpacking libc-dev-bin (2.31-0ubuntu9.16) ...", "Selecting previously unselected package linux-libc-dev:amd64.", "Preparing to unpack .../15-linux-libc-dev_5.4.0-198.218_amd64.deb ...", "Unpacking linux-libc-dev:amd64 (5.4.0-198.218) ...", "Selecting previously unselected package libcrypt-dev:amd64.", "Preparing to unpack .../16-libcrypt-dev_1%3a4.4.10-10ubuntu4_amd64.deb ...", "Unpacking libcrypt-dev:amd64 (1:4.4.10-10ubuntu4) ...", "Selecting previously unselected package libc6-dev:amd64.", "Preparing to unpack .../17-libc6-dev_2.31-0ubuntu9.16_amd64.deb ...", "Unpacking libc6-dev:amd64 (2.31-0ubuntu9.16) ...", "Selecting previously unselected package gcc-9-base:amd64.", "Preparing to unpack .../18-gcc-9-base_9.4.0-1ubuntu1~20.04.2_amd64.deb ...", "Unpacking gcc-9-base:amd64 (9.4.0-1ubuntu1~20.04.2) ...", "Selecting previously unselected package libisl22:amd64.", "Preparing to unpack .../19-libisl22_0.22.1-1_amd64.deb ...", "Unpacking libisl22:amd64 (0.22.1-1) ...", "Selecting previously unselected package libmpfr6:amd64.", "Preparing to unpack .../20-libmpfr6_4.0.2-1_amd64.deb ...", "Unpacking libmpfr6:amd64 (4.0.2-1) ...", "Selecting previously unselected package libmpc3:amd64.", "Preparing to unpack .../21-libmpc3_1.1.0-1_amd64.deb ...", "Unpacking libmpc3:amd64 (1.1.0-1) ...", "Selecting previously unselected package cpp-9.", "Preparing to unpack .../22-cpp-9_9.4.0-1ubuntu1~20.04.2_amd64.deb ...", "Unpacking cpp-9 (9.4.0-1ubuntu1~20.04.2) ...", "Selecting previously unselected package cpp.", "Preparing to unpack .../23-cpp_4%3a9.3.0-1ubuntu2_amd64.deb ...", "Unpacking cpp (4:9.3.0-1ubuntu2) ...", "Selecting previously unselected package libcc1-0:amd64.", "Preparing to unpack .../24-libcc1-0_10.5.0-1ubuntu1~20.04_amd64.deb ...", "Unpacking libcc1-0:amd64 (10.5.0-1ubuntu1~20.04) ...", "Selecting previously unselected package libgomp1:amd64.", "Preparing to unpack .../25-libgomp1_10.5.0-1ubuntu1~20.04_amd64.deb ...", "Unpacking libgomp1:amd64 (10.5.0-1ubuntu1~20.04) ...", "Selecting previously unselected package libitm1:amd64.", "Preparing to unpack .../26-libitm1_10.5.0-1ubuntu1~20.04_amd64.deb ...", "Unpacking libitm1:amd64 (10.5.0-1ubuntu1~20.04) ...", "Selecting previously unselected package libatomic1:amd64.", "Preparing to unpack .../27-libatomic1_10.5.0-1ubuntu1~20.04_amd64.deb ...", "Unpacking libatomic1:amd64 (10.5.0-1ubuntu1~20.04) ...", "Selecting previously unselected package libasan5:amd64.", "Preparing to unpack .../28-libasan5_9.4.0-1ubuntu1~20.04.2_amd64.deb ...", "Unpacking libasan5:amd64 (9.4.0-1ubuntu1~20.04.2) ...", "Selecting previously unselected package liblsan0:amd64.", "Preparing to unpack .../29-liblsan0_10.5.0-1ubuntu1~20.04_amd64.deb ...", "Unpacking liblsan0:amd64 (10.5.0-1ubuntu1~20.04) ...", "Selecting previously unselected package libtsan0:amd64.", "Preparing to unpack .../30-libtsan0_10.5.0-1ubuntu1~20.04_amd64.deb ...", "Unpacking libtsan0:amd64 (10.5.0-1ubuntu1~20.04) ...", "Selecting previously unselected package libubsan1:amd64.", "Preparing to unpack .../31-libubsan1_10.5.0-1ubuntu1~20.04_amd64.deb ...", "Unpacking libubsan1:amd64 (10.5.0-1ubuntu1~20.04) ...", "Selecting previously unselected package libquadmath0:amd64.", "Preparing to unpack .../32-libquadmath0_10.5.0-1ubuntu1~20.04_amd64.deb ...", "Unpacking libquadmath0:amd64 (10.5.0-1ubuntu1~20.04) ...", "Selecting previously unselected package libgcc-9-dev:amd64.", "Preparing to unpack .../33-libgcc-9-dev_9.4.0-1ubuntu1~20.04.2_amd64.deb ...", "Unpacking libgcc-9-dev:amd64 (9.4.0-1ubuntu1~20.04.2) ...", "Selecting previously unselected package gcc-9.", "Preparing to unpack .../34-gcc-9_9.4.0-1ubuntu1~20.04.2_amd64.deb ...", "Unpacking gcc-9 (9.4.0-1ubuntu1~20.04.2) ...", "Selecting previously unselected package gcc.", "Preparing to unpack .../35-gcc_4%3a9.3.0-1ubuntu2_amd64.deb ...", "Unpacking gcc (4:9.3.0-1ubuntu2) ...", "Selecting previously unselected package libstdc++-9-dev:amd64.", "Preparing to unpack .../36-libstdc++-9-dev_9.4.0-1ubuntu1~20.04.2_amd64.deb ...", "Unpacking libstdc++-9-dev:amd64 (9.4.0-1ubuntu1~20.04.2) ...", "Selecting previously unselected package g++-9.", "Preparing to unpack .../37-g++-9_9.4.0-1ubuntu1~20.04.2_amd64.deb ...", "Unpacking g++-9 (9.4.0-1ubuntu1~20.04.2) ...", "Selecting previously unselected package g++.", "Preparing to unpack .../38-g++_4%3a9.3.0-1ubuntu2_amd64.deb ...", "Unpacking g++ (4:9.3.0-1ubuntu2) ...", "Selecting previously unselected package make.", "Preparing to unpack .../39-make_4.2.1-1.2_amd64.deb ...", "Unpacking make (4.2.1-1.2) ...", "Selecting previously unselected package libdpkg-perl.", "Preparing to unpack .../40-libdpkg-perl_1.19.7ubuntu3.2_all.deb ...", "Unpacking libdpkg-perl (1.19.7ubuntu3.2) ...", "Selecting previously unselected package patch.", "Preparing to unpack .../41-patch_2.7.6-6_amd64.deb ...", "Unpacking patch (2.7.6-6) ...", "Selecting previously unselected package dpkg-dev.", "Preparing to unpack .../42-dpkg-dev_1.19.7ubuntu3.2_all.deb ...", "Unpacking dpkg-dev (1.19.7ubuntu3.2) ...", "Selecting previously unselected package build-essential.", "Preparing to unpack .../43-build-essential_12.8ubuntu1.1_amd64.deb ...", "Unpacking build-essential (12.8ubuntu1.1) ...", "Selecting previously unselected package libfakeroot:amd64.", "Preparing to unpack .../44-libfakeroot_1.24-1_amd64.deb ...", "Unpacking libfakeroot:amd64 (1.24-1) ...", "Selecting previously unselected package fakeroot.", "Preparing to unpack .../45-fakeroot_1.24-1_amd64.deb ...", "Unpacking fakeroot (1.24-1) ...", "Selecting previously unselected package libalgorithm-diff-perl.", "Preparing to unpack .../46-libalgorithm-diff-perl_1.19.03-2_all.deb ...", "Unpacking libalgorithm-diff-perl (1.19.03-2) ...", "Selecting previously unselected package libalgorithm-diff-xs-perl.", "Preparing to unpack .../47-libalgorithm-diff-xs-perl_0.04-6_amd64.deb ...", "Unpacking libalgorithm-diff-xs-perl (0.04-6) ...", "Selecting previously unselected package libalgorithm-merge-perl.", "Preparing to unpack .../48-libalgorithm-merge-perl_0.08-3_all.deb ...", "Unpacking libalgorithm-merge-perl (0.08-3) ...", "Selecting previously unselected package libexpat1-dev:amd64.", "Preparing to unpack .../49-libexpat1-dev_2.2.9-1ubuntu0.7_amd64.deb ...", "Unpacking libexpat1-dev:amd64 (2.2.9-1ubuntu0.7) ...", "Selecting previously unselected package libfile-fcntllock-perl.", "Preparing to unpack .../50-libfile-fcntllock-perl_0.22-3build4_amd64.deb ...", "Unpacking libfile-fcntllock-perl (0.22-3build4) ...", "Selecting previously unselected package libpython3.8:amd64.", "Preparing to unpack .../51-libpython3.8_3.8.10-0ubuntu1~20.04.12_amd64.deb ...", "Unpacking libpython3.8:amd64 (3.8.10-0ubuntu1~20.04.12) ...", "Selecting previously unselected package libpython3.8-dev:amd64.", "Preparing to unpack .../52-libpython3.8-dev_3.8.10-0ubuntu1~20.04.12_amd64.deb ...", "Unpacking libpython3.8-dev:amd64 (3.8.10-0ubuntu1~20.04.12) ...", "Selecting previously unselected package libpython3-dev:amd64.", "Preparing to unpack .../53-libpython3-dev_3.8.2-0ubuntu2_amd64.deb ...", "Unpacking libpython3-dev:amd64 (3.8.2-0ubuntu2) ...", "Selecting previously unselected package manpages-dev.", "Preparing to unpack .../54-manpages-dev_5.05-1_all.deb ...", "Unpacking manpages-dev (5.05-1) ...", "Selecting previously unselected package python-pip-whl.", "Preparing to unpack .../55-python-pip-whl_20.0.2-5ubuntu1.10_all.deb ...", "Unpacking python-pip-whl (20.0.2-5ubuntu1.10) ...", "Selecting previously unselected package zlib1g-dev:amd64.", "Preparing to unpack .../56-zlib1g-dev_1%3a1.2.11.dfsg-2ubuntu1.5_amd64.deb ...", "Unpacking zlib1g-dev:amd64 (1:1.2.11.dfsg-2ubuntu1.5) ...", "Selecting previously unselected package python3.8-dev.", "Preparing to unpack .../57-python3.8-dev_3.8.10-0ubuntu1~20.04.12_amd64.deb ...", "Unpacking python3.8-dev (3.8.10-0ubuntu1~20.04.12) ...", "Selecting previously unselected package python3-lib2to3.", "Preparing to unpack .../58-python3-lib2to3_3.8.10-0ubuntu1~20.04_all.deb ...", "Unpacking python3-lib2to3 (3.8.10-0ubuntu1~20.04) ...", "Selecting previously unselected package python3-distutils.", "Preparing to unpack .../59-python3-distutils_3.8.10-0ubuntu1~20.04_all.deb ...", "Unpacking python3-distutils (3.8.10-0ubuntu1~20.04) ...", "Selecting previously unselected package python3-dev.", "Preparing to unpack .../60-python3-dev_3.8.2-0ubuntu2_amd64.deb ...", "Unpacking python3-dev (3.8.2-0ubuntu2) ...", "Selecting previously unselected package python3-setuptools.", "Preparing to unpack .../61-python3-setuptools_45.2.0-1ubuntu0.2_all.deb ...", "Unpacking python3-setuptools (45.2.0-1ubuntu0.2) ...", "Selecting previously unselected package python3-wheel.", "Preparing to unpack .../62-python3-wheel_0.34.2-1ubuntu0.1_all.deb ...", "Unpacking python3-wheel (0.34.2-1ubuntu0.1) ...", "Selecting previously unselected package python3-pip.", "Preparing to unpack .../63-python3-pip_20.0.2-5ubuntu1.10_all.deb ...", "Unpacking python3-pip (20.0.2-5ubuntu1.10) ...", "Setting up perl-modules-5.30 (5.30.0-9ubuntu0.5) ...", "Setting up manpages (5.05-1) ...", "Setting up binutils-common:amd64 (2.34-6ubuntu1.9) ...", "Setting up linux-libc-dev:amd64 (5.4.0-198.218) ...", "Setting up libctf-nobfd0:amd64 (2.34-6ubuntu1.9) ...", "Setting up libgomp1:amd64 (10.5.0-1ubuntu1~20.04) ...", "Setting up python3-wheel (0.34.2-1ubuntu0.1) ...", "Setting up libfakeroot:amd64 (1.24-1) ...", "Setting up fakeroot (1.24-1) ...", "update-alternatives: using /usr/bin/fakeroot-sysv to provide /usr/bin/fakeroot (fakeroot) in auto mode", "update-alternatives: warning: skip creation of /usr/share/man/man1/fakeroot.1.gz because associated file /usr/share/man/man1/fakeroot-sysv.1.gz (of link group fakeroot) doesn't exist", "update-alternatives: warning: skip creation of /usr/share/man/man1/faked.1.gz because associated file /usr/share/man/man1/faked-sysv.1.gz (of link group fakeroot) doesn't exist", "update-alternatives: warning: skip creation of /usr/share/man/es/man1/fakeroot.1.gz because associated file /usr/share/man/es/man1/fakeroot-sysv.1.gz (of link group fakeroot) doesn't exist", "update-alternatives: warning: skip creation of /usr/share/man/es/man1/faked.1.gz because associated file /usr/share/man/es/man1/faked-sysv.1.gz (of link group fakeroot) doesn't exist", "update-alternatives: warning: skip creation of /usr/share/man/fr/man1/fakeroot.1.gz because associated file /usr/share/man/fr/man1/fakeroot-sysv.1.gz (of link group fakeroot) doesn't exist", "update-alternatives: warning: skip creation of /usr/share/man/fr/man1/faked.1.gz because associated file /usr/share/man/fr/man1/faked-sysv.1.gz (of link group fakeroot) doesn't exist", "update-alternatives: warning: skip creation of /usr/share/man/sv/man1/fakeroot.1.gz because associated file /usr/share/man/sv/man1/fakeroot-sysv.1.gz (of link group fakeroot) doesn't exist", "update-alternatives: warning: skip creation of /usr/share/man/sv/man1/faked.1.gz because associated file /usr/share/man/sv/man1/faked-sysv.1.gz (of link group fakeroot) doesn't exist", "Setting up make (4.2.1-1.2) ...", "Setting up libmpfr6:amd64 (4.0.2-1) ...", "Setting up libpython3.8:amd64 (3.8.10-0ubuntu1~20.04.12) ...", "Setting up libquadmath0:amd64 (10.5.0-1ubuntu1~20.04) ...", "Setting up libmpc3:amd64 (1.1.0-1) ...", "Setting up libatomic1:amd64 (10.5.0-1ubuntu1~20.04) ...", "Setting up patch (2.7.6-6) ...", "Setting up libubsan1:amd64 (10.5.0-1ubuntu1~20.04) ...", "Setting up libcrypt-dev:amd64 (1:4.4.10-10ubuntu4) ...", "Setting up libisl22:amd64 (0.22.1-1) ...", "Setting up netbase (6.1) ...", "Setting up python-pip-whl (20.0.2-5ubuntu1.10) ...", "Setting up libbinutils:amd64 (2.34-6ubuntu1.9) ...", "Setting up libc-dev-bin (2.31-0ubuntu9.16) ...", "Setting up python3-lib2to3 (3.8.10-0ubuntu1~20.04) ...", "Setting up libcc1-0:amd64 (10.5.0-1ubuntu1~20.04) ...", "Setting up liblocale-gettext-perl (1.07-4) ...", "Setting up liblsan0:amd64 (10.5.0-1ubuntu1~20.04) ...", "Setting up libitm1:amd64 (10.5.0-1ubuntu1~20.04) ...", "Setting up libgdbm6:amd64 (1.18.1-5) ...", "Setting up gcc-9-base:amd64 (9.4.0-1ubuntu1~20.04.2) ...", "Setting up libtsan0:amd64 (10.5.0-1ubuntu1~20.04) ...", "Setting up libctf0:amd64 (2.34-6ubuntu1.9) ...", "Setting up python3-distutils (3.8.10-0ubuntu1~20.04) ...", "Setting up manpages-dev (5.05-1) ...", "Setting up python3-setuptools (45.2.0-1ubuntu0.2) ...", "Setting up libasan5:amd64 (9.4.0-1ubuntu1~20.04.2) ...", "Setting up libgdbm-compat4:amd64 (1.18.1-5) ...", "Setting up python3-pip (20.0.2-5ubuntu1.10) ...", "Setting up cpp-9 (9.4.0-1ubuntu1~20.04.2) ...", "Setting up libperl5.30:amd64 (5.30.0-9ubuntu0.5) ...", "Setting up libc6-dev:amd64 (2.31-0ubuntu9.16) ...", "Setting up binutils-x86-64-linux-gnu (2.34-6ubuntu1.9) ...", "Setting up binutils (2.34-6ubuntu1.9) ...", "Setting up libgcc-9-dev:amd64 (9.4.0-1ubuntu1~20.04.2) ...", "Setting up perl (5.30.0-9ubuntu0.5) ...", "Setting up libexpat1-dev:amd64 (2.2.9-1ubuntu0.7) ...", "Setting up libpython3.8-dev:amd64 (3.8.10-0ubuntu1~20.04.12) ...", "Setting up libdpkg-perl (1.19.7ubuntu3.2) ...", "Setting up zlib1g-dev:amd64 (1:1.2.11.dfsg-2ubuntu1.5) ...", "Setting up cpp (4:9.3.0-1ubuntu2) ...", "Setting up gcc-9 (9.4.0-1ubuntu1~20.04.2) ...", "Setting up libpython3-dev:amd64 (3.8.2-0ubuntu2) ...", "Setting up libstdc++-9-dev:amd64 (9.4.0-1ubuntu1~20.04.2) ...", "Setting up libfile-fcntllock-perl (0.22-3build4) ...", "Setting up libalgorithm-diff-perl (1.19.03-2) ...", "Setting up gcc (4:9.3.0-1ubuntu2) ...", "Setting up dpkg-dev (1.19.7ubuntu3.2) ...", "Setting up g++-9 (9.4.0-1ubuntu1~20.04.2) ...", "Setting up python3.8-dev (3.8.10-0ubuntu1~20.04.12) ...", "Setting up g++ (4:9.3.0-1ubuntu2) ...", "update-alternatives: using /usr/bin/g++ to provide /usr/bin/c++ (c++) in auto mode", "update-alternatives: warning: skip creation of /usr/share/man/man1/c++.1.gz because associated file /usr/share/man/man1/g++.1.gz (of link group c++) doesn't exist", "Setting up build-essential (12.8ubuntu1.1) ...", "Setting up libalgorithm-diff-xs-perl (0.04-6) ...", "Setting up libalgorithm-merge-perl (0.08-3) ...", "Setting up python3-dev (3.8.2-0ubuntu2) ...", "Processing triggers for libc-bin (2.31-0ubuntu9.16) ..."]}

TASK [confluent.platform.common : Upgrade pip] *********************************
changed: [kafka-controller-3-migrated] => {"changed": true, "cmd": ["/usr/bin/python3.8", "-m", "pip.__main__", "install", "--upgrade", "pip"], "name": ["pip"], "requirements": null, "state": "present", "stderr": "", "stderr_lines": [], "stdout": "Collecting pip\n  Downloading pip-24.2-py3-none-any.whl (1.8 MB)\nInstalling collected packages: pip\n  Attempting uninstall: pip\n    Found existing installation: pip 20.0.2\n    Not uninstalling pip at /usr/lib/python3/dist-packages, outside environment /usr\n    Can't uninstall 'pip'. No files were found to uninstall.\nSuccessfully installed pip-24.2\n", "stdout_lines": ["Collecting pip", "  Downloading pip-24.2-py3-none-any.whl (1.8 MB)", "Installing collected packages: pip", "  Attempting uninstall: pip", "    Found existing installation: pip 20.0.2", "    Not uninstalling pip at /usr/lib/python3/dist-packages, outside environment /usr", "    Can't uninstall 'pip'. No files were found to uninstall.", "Successfully installed pip-24.2"], "version": null, "virtualenv": null}

TASK [confluent.platform.common : Install pip packages] ************************
changed: [kafka-controller-3-migrated] => {"changed": true, "cmd": ["/usr/bin/python3.8", "-m", "pip.__main__", "install", "cryptography"], "name": ["cryptography"], "requirements": null, "state": "present", "stderr": "WARNING: Running pip as the 'root' user can result in broken permissions and conflicting behaviour with the system package manager, possibly rendering your system unusable.It is recommended to use a virtual environment instead: https://pip.pypa.io/warnings/venv. Use the --root-user-action option if you know what you are doing and want to suppress this warning.\n", "stderr_lines": ["WARNING: Running pip as the 'root' user can result in broken permissions and conflicting behaviour with the system package manager, possibly rendering your system unusable.It is recommended to use a virtual environment instead: https://pip.pypa.io/warnings/venv. Use the --root-user-action option if you know what you are doing and want to suppress this warning."], "stdout": "Collecting cryptography\n  Downloading cryptography-43.0.1-cp37-abi3-manylinux_2_28_x86_64.whl.metadata (5.4 kB)\nCollecting cffi>=1.12 (from cryptography)\n  Downloading cffi-1.17.1-cp38-cp38-manylinux_2_17_x86_64.manylinux2014_x86_64.whl.metadata (1.5 kB)\nCollecting pycparser (from cffi>=1.12->cryptography)\n  Downloading pycparser-2.22-py3-none-any.whl.metadata (943 bytes)\nDownloading cryptography-43.0.1-cp37-abi3-manylinux_2_28_x86_64.whl (4.0 MB)\n   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 4.0/4.0 MB 88.0 MB/s eta 0:00:00\nDownloading cffi-1.17.1-cp38-cp38-manylinux_2_17_x86_64.manylinux2014_x86_64.whl (446 kB)\nDownloading pycparser-2.22-py3-none-any.whl (117 kB)\nInstalling collected packages: pycparser, cffi, cryptography\nSuccessfully installed cffi-1.17.1 cryptography-43.0.1 pycparser-2.22\n", "stdout_lines": ["Collecting cryptography", "  Downloading cryptography-43.0.1-cp37-abi3-manylinux_2_28_x86_64.whl.metadata (5.4 kB)", "Collecting cffi>=1.12 (from cryptography)", "  Downloading cffi-1.17.1-cp38-cp38-manylinux_2_17_x86_64.manylinux2014_x86_64.whl.metadata (1.5 kB)", "Collecting pycparser (from cffi>=1.12->cryptography)", "  Downloading pycparser-2.22-py3-none-any.whl.metadata (943 bytes)", "Downloading cryptography-43.0.1-cp37-abi3-manylinux_2_28_x86_64.whl (4.0 MB)", "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 4.0/4.0 MB 88.0 MB/s eta 0:00:00", "Downloading cffi-1.17.1-cp38-cp38-manylinux_2_17_x86_64.manylinux2014_x86_64.whl (446 kB)", "Downloading pycparser-2.22-py3-none-any.whl (117 kB)", "Installing collected packages: pycparser, cffi, cryptography", "Successfully installed cffi-1.17.1 cryptography-43.0.1 pycparser-2.22"], "version": null, "virtualenv": null}

TASK [confluent.platform.common : Debian Repo Setup and Java Installation] *****
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "ansible_distribution == \"Debian\"", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Config Validations] **************************
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/common/tasks/config_validations.yml for kafka-controller-3-migrated

TASK [confluent.platform.common : Retrieve SSL public key hash from private key on Local Host] ***
skipping: [kafka-controller-3-migrated] => (item=kafka_controller)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ssl_custom_certs|bool and not ssl_custom_certs_remote_src|bool", "item": "kafka_controller", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.common : Register content of key file] ****************
skipping: [kafka-controller-3-migrated] => (item=kafka_controller)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ssl_custom_certs|bool and ssl_custom_certs_remote_src|bool", "item": "kafka_controller", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.common : Retrieve SSL public key Hash from private key on Remote Host] ***
skipping: [kafka-controller-3-migrated] => (item=kafka_controller)  => {"ansible_index_var": "group_idx", "ansible_loop_var": "item", "changed": false, "false_condition": "ssl_custom_certs|bool and ssl_custom_certs_remote_src|bool", "group_idx": 0, "item": "kafka_controller", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.common : Retrieve SSL public key hash from X509 certificate on Local Host] ***
skipping: [kafka-controller-3-migrated] => (item=kafka_controller)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ssl_custom_certs|bool and not ssl_custom_certs_remote_src|bool", "item": "kafka_controller", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.common : Register content of cert file] ***************
skipping: [kafka-controller-3-migrated] => (item=kafka_controller)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ssl_custom_certs|bool and ssl_custom_certs_remote_src|bool", "item": "kafka_controller", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.common : Retrieve SSL public key hash from X509 certificate on Remote Host] ***
skipping: [kafka-controller-3-migrated] => (item=kafka_controller)  => {"ansible_index_var": "group_idx", "ansible_loop_var": "item", "changed": false, "false_condition": "ssl_custom_certs|bool and ssl_custom_certs_remote_src|bool", "group_idx": 0, "item": "kafka_controller", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.common : get public key hash from private key] ********
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"key_hash": {"changed": false, "msg": "All items skipped", "results": [{"ansible_loop_var": "item", "changed": false, "false_condition": "ssl_custom_certs|bool and not ssl_custom_certs_remote_src|bool", "item": "kafka_controller", "skip_reason": "Conditional result was False", "skipped": true}], "skipped": true}}, "changed": false}

TASK [confluent.platform.common : get public key hash from X509 cert] **********
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"cert_hash": {"changed": false, "msg": "All items skipped", "results": [{"ansible_loop_var": "item", "changed": false, "false_condition": "ssl_custom_certs|bool and not ssl_custom_certs_remote_src|bool", "item": "kafka_controller", "skip_reason": "Conditional result was False", "skipped": true}], "skipped": true}}, "changed": false}

TASK [confluent.platform.common : Assert SSL public key hash from private key matches public key hash from Cert] ***
skipping: [kafka-controller-3-migrated] => (item=kafka_controller)  => {"ansible_index_var": "group_idx", "ansible_loop_var": "item", "changed": false, "false_condition": "ssl_custom_certs|bool", "group_idx": 0, "item": "kafka_controller", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.common : Check the OS when using FIPS mode] ***********
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "fips_enabled | bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Check if FIPS is enabled on Local Host] ******
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "fips_enabled | bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : assert] **************************************
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "fips_enabled | bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Check if FIPS is enabled on Remote Host] *****
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "fips_enabled | bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : assert] **************************************
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "fips_enabled | bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Create Confluent Platform install directory] ***
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "installation_method == \"archive\"", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Expand remote Confluent Platform archive] ****
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "installation_method == \"archive\"", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Create Jolokia directory] ********************
skipping: [kafka-controller-3-migrated] => (item=kafka_controller)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "lookup('vars', item + '_jolokia_enabled', default=jolokia_enabled)|bool", "item": "kafka_controller", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.common : Copy Jolokia Jar] ****************************
skipping: [kafka-controller-3-migrated] => (item=kafka_controller)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "lookup('vars', item + '_jolokia_enabled', default=jolokia_enabled)|bool", "item": "kafka_controller", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.common : Download Jolokia Jar] ************************
skipping: [kafka-controller-3-migrated] => (item=kafka_controller)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "lookup('vars', item + '_jolokia_enabled', default=jolokia_enabled)|bool", "item": "kafka_controller", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.common : Create Prometheus install directory] *********
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "jmxexporter_enabled|bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Copy Prometheus Jar] *************************
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "jmxexporter_enabled|bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Download Prometheus JMX Exporter Jar] ********
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "jmxexporter_enabled|bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Install Confluent CLI] ***********************
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "confluent_cli_download_enabled|bool", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : set_fact] ************************************
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"common_role_completed": true}, "changed": false}

TASK [confluent.platform.kafka_controller : Gather OS Facts] *******************
skipping: [kafka-controller-1] => (item=ansible_os_family)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_os_family", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=ansible_fqdn)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_fqdn", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=ansible_distribution)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_distribution", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=ansible_os_family)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_os_family", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=ansible_fqdn)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_fqdn", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=ansible_distribution)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_distribution", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=ansible_os_family)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_os_family", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3] => (item=ansible_fqdn)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_fqdn", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=ansible_distribution)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_distribution", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-broker-1] => (item=ansible_os_family)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_os_family", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=ansible_fqdn)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_fqdn", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=ansible_distribution)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "ansible_distribution", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "msg": "All items skipped"}
ok: [kafka-controller-3-migrated] => (item=ansible_os_family)
ok: [kafka-controller-3-migrated] => (item=ansible_fqdn)
ok: [kafka-controller-3-migrated] => (item=ansible_distribution)

TASK [confluent.platform.kafka_controller : Assert that datadir is not present in the inventory] ***
skipping: [kafka-controller-1] => (item=kafka-controller-1)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-1", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=kafka-controller-2)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-2", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=kafka-controller-3)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-3", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=kafka-controller-3-migrated)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-3-migrated", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=kafka-controller-1)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-1", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=kafka-controller-2)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-2", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-2] => (item=kafka-controller-3)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-3", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=kafka-controller-3-migrated)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-3-migrated", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=kafka-controller-1)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-1", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3] => (item=kafka-controller-2)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-2", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=kafka-controller-3)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-3", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=kafka-controller-3-migrated)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-3-migrated", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "msg": "All items skipped"}
ok: [kafka-controller-3-migrated] => (item=kafka-controller-1) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-1",
    "msg": "All assertions passed"
}
skipping: [kafka-broker-1] => (item=kafka-controller-1)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-1", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=kafka-controller-2)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-2", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=kafka-controller-3)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-3", "skip_reason": "Conditional result was False"}
ok: [kafka-controller-3-migrated] => (item=kafka-controller-2) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-2",
    "msg": "All assertions passed"
}
skipping: [kafka-broker-1] => (item=kafka-controller-3-migrated)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "kafka-controller-3-migrated", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "msg": "All items skipped"}
ok: [kafka-controller-3-migrated] => (item=kafka-controller-3) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-3",
    "msg": "All assertions passed"
}
ok: [kafka-controller-3-migrated] => (item=kafka-controller-3-migrated) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "kafka-controller-3-migrated",
    "msg": "All assertions passed"
}

TASK [confluent.platform.kafka_controller : Assert log.dirs Property not Misconfigured] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
ok: [kafka-controller-3-migrated] => {
    "changed": false,
    "msg": "All assertions passed"
}

TASK [Stop Service and Remove Packages on Version Change] **********************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
included: common for kafka-controller-3-migrated

TASK [confluent.platform.common : Get Package Facts] ***************************
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"packages": {"adduser": [{"arch": "all", "category": "admin", "name": "adduser", "origin": "Ubuntu", "source": "apt", "version": "3.118ubuntu2"}], "adwaita-icon-theme": [{"arch": "all", "category": "gnome", "name": "adwaita-icon-theme", "origin": "Ubuntu", "source": "apt", "version": "3.36.1-2ubuntu0.20.04.2"}], "alsa-topology-conf": [{"arch": "all", "category": "libs", "name": "alsa-topology-conf", "origin": "Ubuntu", "source": "apt", "version": "1.2.2-1"}], "alsa-ucm-conf": [{"arch": "all", "category": "libs", "name": "alsa-ucm-conf", "origin": "Ubuntu", "source": "apt", "version": "1.2.2-1ubuntu0.13"}], "apt": [{"arch": "amd64", "category": "admin", "name": "apt", "origin": "Ubuntu", "source": "apt", "version": "2.0.10"}], "apt-transport-https": [{"arch": "all", "category": "universe/admin", "name": "apt-transport-https", "origin": "Ubuntu", "source": "apt", "version": "2.0.10"}], "at-spi2-core": [{"arch": "amd64", "category": "misc", "name": "at-spi2-core", "origin": "Ubuntu", "source": "apt", "version": "2.36.0-2"}], "base-files": [{"arch": "amd64", "category": "admin", "name": "base-files", "origin": "Ubuntu", "source": "apt", "version": "11ubuntu5.8"}], "base-passwd": [{"arch": "amd64", "category": "admin", "name": "base-passwd", "origin": "Ubuntu", "source": "apt", "version": "3.5.47"}], "bash": [{"arch": "amd64", "category": "shells", "name": "bash", "origin": "Ubuntu", "source": "apt", "version": "5.0-6ubuntu1.2"}], "binutils": [{"arch": "amd64", "category": "devel", "name": "binutils", "origin": "Ubuntu", "source": "apt", "version": "2.34-6ubuntu1.9"}], "binutils-common": [{"arch": "amd64", "category": "devel", "name": "binutils-common", "origin": "Ubuntu", "source": "apt", "version": "2.34-6ubuntu1.9"}], "binutils-x86-64-linux-gnu": [{"arch": "amd64", "category": "devel", "name": "binutils-x86-64-linux-gnu", "origin": "Ubuntu", "source": "apt", "version": "2.34-6ubuntu1.9"}], "bsdutils": [{"arch": "amd64", "category": "utils", "name": "bsdutils", "origin": "Ubuntu", "source": "apt", "version": "1:2.34-0.1ubuntu9.6"}], "build-essential": [{"arch": "amd64", "category": "devel", "name": "build-essential", "origin": "Ubuntu", "source": "apt", "version": "12.8ubuntu1.1"}], "bzip2": [{"arch": "amd64", "category": "utils", "name": "bzip2", "origin": "Ubuntu", "source": "apt", "version": "1.0.8-2"}], "ca-certificates": [{"arch": "all", "category": "misc", "name": "ca-certificates", "origin": "Ubuntu", "source": "apt", "version": "20240203~20.04.1"}], "ca-certificates-java": [{"arch": "all", "category": "misc", "name": "ca-certificates-java", "origin": "Ubuntu", "source": "apt", "version": "20190405ubuntu1.1"}], "coreutils": [{"arch": "amd64", "category": "utils", "name": "coreutils", "origin": "Ubuntu", "source": "apt", "version": "8.30-3ubuntu2"}], "cpp": [{"arch": "amd64", "category": "interpreters", "name": "cpp", "origin": "Ubuntu", "source": "apt", "version": "4:9.3.0-1ubuntu2"}], "cpp-9": [{"arch": "amd64", "category": "interpreters", "name": "cpp-9", "origin": "Ubuntu", "source": "apt", "version": "9.4.0-1ubuntu1~20.04.2"}], "dash": [{"arch": "amd64", "category": "shells", "name": "dash", "origin": "Ubuntu", "source": "apt", "version": "0.5.10.2-6"}], "dbus": [{"arch": "amd64", "category": "devel", "name": "dbus", "origin": "Ubuntu", "source": "apt", "version": "1.12.16-2ubuntu2.3"}], "debconf": [{"arch": "all", "category": "admin", "name": "debconf", "origin": "Ubuntu", "source": "apt", "version": "1.5.73"}], "debianutils": [{"arch": "amd64", "category": "utils", "name": "debianutils", "origin": "Ubuntu", "source": "apt", "version": "4.9.1"}], "diffutils": [{"arch": "amd64", "category": "utils", "name": "diffutils", "origin": "Ubuntu", "source": "apt", "version": "1:3.7-3"}], "dirmngr": [{"arch": "amd64", "category": "utils", "name": "dirmngr", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "distro-info-data": [{"arch": "all", "category": "devel", "name": "distro-info-data", "origin": "Ubuntu", "source": "apt", "version": "0.43ubuntu1.16"}], "dmsetup": [{"arch": "amd64", "category": "admin", "name": "dmsetup", "origin": "Ubuntu", "source": "apt", "version": "2:1.02.167-1ubuntu1"}], "dpkg": [{"arch": "amd64", "category": "admin", "name": "dpkg", "origin": "Ubuntu", "source": "apt", "version": "1.19.7ubuntu3.2"}], "dpkg-dev": [{"arch": "all", "category": "utils", "name": "dpkg-dev", "origin": "Ubuntu", "source": "apt", "version": "1.19.7ubuntu3.2"}], "e2fsprogs": [{"arch": "amd64", "category": "admin", "name": "e2fsprogs", "origin": "Ubuntu", "source": "apt", "version": "1.45.5-2ubuntu1.2"}], "fakeroot": [{"arch": "amd64", "category": "utils", "name": "fakeroot", "origin": "Ubuntu", "source": "apt", "version": "1.24-1"}], "fdisk": [{"arch": "amd64", "category": "utils", "name": "fdisk", "origin": "Ubuntu", "source": "apt", "version": "2.34-0.1ubuntu9.6"}], "file": [{"arch": "amd64", "category": "utils", "name": "file", "origin": "Ubuntu", "source": "apt", "version": "1:5.38-4"}], "findutils": [{"arch": "amd64", "category": "utils", "name": "findutils", "origin": "Ubuntu", "source": "apt", "version": "4.7.0-1ubuntu1"}], "fontconfig": [{"arch": "amd64", "category": "utils", "name": "fontconfig", "origin": "Ubuntu", "source": "apt", "version": "2.13.1-2ubuntu3"}], "fontconfig-config": [{"arch": "all", "category": "libs", "name": "fontconfig-config", "origin": "Ubuntu", "source": "apt", "version": "2.13.1-2ubuntu3"}], "fonts-dejavu-core": [{"arch": "all", "category": "fonts", "name": "fonts-dejavu-core", "origin": "Ubuntu", "source": "apt", "version": "2.37-1"}], "fonts-dejavu-extra": [{"arch": "all", "category": "fonts", "name": "fonts-dejavu-extra", "origin": "Ubuntu", "source": "apt", "version": "2.37-1"}], "g++": [{"arch": "amd64", "category": "devel", "name": "g++", "origin": "Ubuntu", "source": "apt", "version": "4:9.3.0-1ubuntu2"}], "g++-9": [{"arch": "amd64", "category": "devel", "name": "g++-9", "origin": "Ubuntu", "source": "apt", "version": "9.4.0-1ubuntu1~20.04.2"}], "gcc": [{"arch": "amd64", "category": "devel", "name": "gcc", "origin": "Ubuntu", "source": "apt", "version": "4:9.3.0-1ubuntu2"}], "gcc-10-base": [{"arch": "amd64", "category": "libs", "name": "gcc-10-base", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "gcc-9": [{"arch": "amd64", "category": "devel", "name": "gcc-9", "origin": "Ubuntu", "source": "apt", "version": "9.4.0-1ubuntu1~20.04.2"}], "gcc-9-base": [{"arch": "amd64", "category": "libs", "name": "gcc-9-base", "origin": "Ubuntu", "source": "apt", "version": "9.4.0-1ubuntu1~20.04.2"}], "gir1.2-glib-2.0": [{"arch": "amd64", "category": "introspection", "name": "gir1.2-glib-2.0", "origin": "Ubuntu", "source": "apt", "version": "1.64.1-1~ubuntu20.04.1"}], "gnupg": [{"arch": "all", "category": "utils", "name": "gnupg", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "gnupg-l10n": [{"arch": "all", "category": "utils", "name": "gnupg-l10n", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "gnupg-utils": [{"arch": "amd64", "category": "utils", "name": "gnupg-utils", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "gnupg2": [{"arch": "all", "category": "universe/utils", "name": "gnupg2", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "gpg": [{"arch": "amd64", "category": "utils", "name": "gpg", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "gpg-agent": [{"arch": "amd64", "category": "utils", "name": "gpg-agent", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "gpg-wks-client": [{"arch": "amd64", "category": "utils", "name": "gpg-wks-client", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "gpg-wks-server": [{"arch": "amd64", "category": "utils", "name": "gpg-wks-server", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "gpgconf": [{"arch": "amd64", "category": "utils", "name": "gpgconf", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "gpgsm": [{"arch": "amd64", "category": "utils", "name": "gpgsm", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "gpgv": [{"arch": "amd64", "category": "utils", "name": "gpgv", "origin": "Ubuntu", "source": "apt", "version": "2.2.19-3ubuntu2.2"}], "grep": [{"arch": "amd64", "category": "utils", "name": "grep", "origin": "Ubuntu", "source": "apt", "version": "3.4-1"}], "gtk-update-icon-cache": [{"arch": "amd64", "category": "misc", "name": "gtk-update-icon-cache", "origin": "Ubuntu", "source": "apt", "version": "3.24.20-0ubuntu1.2"}], "gzip": [{"arch": "amd64", "category": "utils", "name": "gzip", "origin": "Ubuntu", "source": "apt", "version": "1.10-0ubuntu4.1"}], "hicolor-icon-theme": [{"arch": "all", "category": "misc", "name": "hicolor-icon-theme", "origin": "Ubuntu", "source": "apt", "version": "0.17-2"}], "hostname": [{"arch": "amd64", "category": "admin", "name": "hostname", "origin": "Ubuntu", "source": "apt", "version": "3.23"}], "humanity-icon-theme": [{"arch": "all", "category": "gnome", "name": "humanity-icon-theme", "origin": "Ubuntu", "source": "apt", "version": "0.6.15"}], "init-system-helpers": [{"arch": "all", "category": "admin", "name": "init-system-helpers", "origin": "Ubuntu", "source": "apt", "version": "1.57"}], "iso-codes": [{"arch": "all", "category": "libs", "name": "iso-codes", "origin": "Ubuntu", "source": "apt", "version": "4.4-1"}], "java-common": [{"arch": "all", "category": "misc", "name": "java-common", "origin": "Ubuntu", "source": "apt", "version": "0.72"}], "krb5-locales": [{"arch": "all", "category": "localization", "name": "krb5-locales", "origin": "Ubuntu", "source": "apt", "version": "1.17-6ubuntu4.7"}], "libacl1": [{"arch": "amd64", "category": "libs", "name": "libacl1", "origin": "Ubuntu", "source": "apt", "version": "2.2.53-6"}], "libalgorithm-diff-perl": [{"arch": "all", "category": "perl", "name": "libalgorithm-diff-perl", "origin": "Ubuntu", "source": "apt", "version": "1.19.03-2"}], "libalgorithm-diff-xs-perl": [{"arch": "amd64", "category": "perl", "name": "libalgorithm-diff-xs-perl", "origin": "Ubuntu", "source": "apt", "version": "0.04-6"}], "libalgorithm-merge-perl": [{"arch": "all", "category": "perl", "name": "libalgorithm-merge-perl", "origin": "Ubuntu", "source": "apt", "version": "0.08-3"}], "libapparmor1": [{"arch": "amd64", "category": "libs", "name": "libapparmor1", "origin": "Ubuntu", "source": "apt", "version": "2.13.3-7ubuntu5.4"}], "libapt-pkg6.0": [{"arch": "amd64", "category": "libs", "name": "libapt-pkg6.0", "origin": "Ubuntu", "source": "apt", "version": "2.0.10"}], "libargon2-1": [{"arch": "amd64", "category": "libs", "name": "libargon2-1", "origin": "Ubuntu", "source": "apt", "version": "0~20171227-0.2"}], "libasan5": [{"arch": "amd64", "category": "libs", "name": "libasan5", "origin": "Ubuntu", "source": "apt", "version": "9.4.0-1ubuntu1~20.04.2"}], "libasn1-8-heimdal": [{"arch": "amd64", "category": "libs", "name": "libasn1-8-heimdal", "origin": "Ubuntu", "source": "apt", "version": "7.7.0+dfsg-1ubuntu1.4"}], "libasound2": [{"arch": "amd64", "category": "libs", "name": "libasound2", "origin": "Ubuntu", "source": "apt", "version": "1.2.2-2.1ubuntu2.5"}], "libasound2-data": [{"arch": "all", "category": "libs", "name": "libasound2-data", "origin": "Ubuntu", "source": "apt", "version": "1.2.2-2.1ubuntu2.5"}], "libassuan0": [{"arch": "amd64", "category": "libs", "name": "libassuan0", "origin": "Ubuntu", "source": "apt", "version": "2.5.3-7ubuntu2"}], "libatk-bridge2.0-0": [{"arch": "amd64", "category": "libs", "name": "libatk-bridge2.0-0", "origin": "Ubuntu", "source": "apt", "version": "2.34.2-0ubuntu2~20.04.1"}], "libatk-wrapper-java": [{"arch": "all", "category": "java", "name": "libatk-wrapper-java", "origin": "Ubuntu", "source": "apt", "version": "0.37.1-1"}], "libatk-wrapper-java-jni": [{"arch": "amd64", "category": "java", "name": "libatk-wrapper-java-jni", "origin": "Ubuntu", "source": "apt", "version": "0.37.1-1"}], "libatk1.0-0": [{"arch": "amd64", "category": "libs", "name": "libatk1.0-0", "origin": "Ubuntu", "source": "apt", "version": "2.35.1-1ubuntu2"}], "libatk1.0-data": [{"arch": "all", "category": "misc", "name": "libatk1.0-data", "origin": "Ubuntu", "source": "apt", "version": "2.35.1-1ubuntu2"}], "libatomic1": [{"arch": "amd64", "category": "libs", "name": "libatomic1", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "libatspi2.0-0": [{"arch": "amd64", "category": "misc", "name": "libatspi2.0-0", "origin": "Ubuntu", "source": "apt", "version": "2.36.0-2"}], "libattr1": [{"arch": "amd64", "category": "libs", "name": "libattr1", "origin": "Ubuntu", "source": "apt", "version": "1:2.4.48-5"}], "libaudit-common": [{"arch": "all", "category": "libs", "name": "libaudit-common", "origin": "Ubuntu", "source": "apt", "version": "1:2.8.5-2ubuntu6"}], "libaudit1": [{"arch": "amd64", "category": "libs", "name": "libaudit1", "origin": "Ubuntu", "source": "apt", "version": "1:2.8.5-2ubuntu6"}], "libavahi-client3": [{"arch": "amd64", "category": "libs", "name": "libavahi-client3", "origin": "Ubuntu", "source": "apt", "version": "0.7-4ubuntu7.3"}], "libavahi-common-data": [{"arch": "amd64", "category": "libs", "name": "libavahi-common-data", "origin": "Ubuntu", "source": "apt", "version": "0.7-4ubuntu7.3"}], "libavahi-common3": [{"arch": "amd64", "category": "libs", "name": "libavahi-common3", "origin": "Ubuntu", "source": "apt", "version": "0.7-4ubuntu7.3"}], "libbinutils": [{"arch": "amd64", "category": "devel", "name": "libbinutils", "origin": "Ubuntu", "source": "apt", "version": "2.34-6ubuntu1.9"}], "libblkid1": [{"arch": "amd64", "category": "libs", "name": "libblkid1", "origin": "Ubuntu", "source": "apt", "version": "2.34-0.1ubuntu9.6"}], "libbsd0": [{"arch": "amd64", "category": "libs", "name": "libbsd0", "origin": "Ubuntu", "source": "apt", "version": "0.10.0-1"}], "libbz2-1.0": [{"arch": "amd64", "category": "libs", "name": "libbz2-1.0", "origin": "Ubuntu", "source": "apt", "version": "1.0.8-2"}], "libc-bin": [{"arch": "amd64", "category": "libs", "name": "libc-bin", "origin": "Ubuntu", "source": "apt", "version": "2.31-0ubuntu9.16"}], "libc-dev-bin": [{"arch": "amd64", "category": "libdevel", "name": "libc-dev-bin", "origin": "Ubuntu", "source": "apt", "version": "2.31-0ubuntu9.16"}], "libc6": [{"arch": "amd64", "category": "libs", "name": "libc6", "origin": "Ubuntu", "source": "apt", "version": "2.31-0ubuntu9.16"}], "libc6-dev": [{"arch": "amd64", "category": "libdevel", "name": "libc6-dev", "origin": "Ubuntu", "source": "apt", "version": "2.31-0ubuntu9.16"}], "libcairo-gobject2": [{"arch": "amd64", "category": "libs", "name": "libcairo-gobject2", "origin": "Ubuntu", "source": "apt", "version": "1.16.0-4ubuntu1"}], "libcairo2": [{"arch": "amd64", "category": "libs", "name": "libcairo2", "origin": "Ubuntu", "source": "apt", "version": "1.16.0-4ubuntu1"}], "libcap-ng0": [{"arch": "amd64", "category": "libs", "name": "libcap-ng0", "origin": "Ubuntu", "source": "apt", "version": "0.7.9-2.1build1"}], "libcap2": [{"arch": "amd64", "category": "libs", "name": "libcap2", "origin": "Ubuntu", "source": "apt", "version": "1:2.32-1ubuntu0.1"}], "libcbor0.6": [{"arch": "amd64", "category": "libs", "name": "libcbor0.6", "origin": "Ubuntu", "source": "apt", "version": "0.6.0-0ubuntu1"}], "libcc1-0": [{"arch": "amd64", "category": "libs", "name": "libcc1-0", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "libcom-err2": [{"arch": "amd64", "category": "libs", "name": "libcom-err2", "origin": "Ubuntu", "source": "apt", "version": "1.45.5-2ubuntu1.2"}], "libcrypt-dev": [{"arch": "amd64", "category": "libdevel", "name": "libcrypt-dev", "origin": "Ubuntu", "source": "apt", "version": "1:4.4.10-10ubuntu4"}], "libcrypt1": [{"arch": "amd64", "category": "libs", "name": "libcrypt1", "origin": "Ubuntu", "source": "apt", "version": "1:4.4.10-10ubuntu4"}], "libcryptsetup12": [{"arch": "amd64", "category": "libs", "name": "libcryptsetup12", "origin": "Ubuntu", "source": "apt", "version": "2:2.2.2-3ubuntu2.4"}], "libctf-nobfd0": [{"arch": "amd64", "category": "devel", "name": "libctf-nobfd0", "origin": "Ubuntu", "source": "apt", "version": "2.34-6ubuntu1.9"}], "libctf0": [{"arch": "amd64", "category": "devel", "name": "libctf0", "origin": "Ubuntu", "source": "apt", "version": "2.34-6ubuntu1.9"}], "libcups2": [{"arch": "amd64", "category": "libs", "name": "libcups2", "origin": "Ubuntu", "source": "apt", "version": "2.3.1-9ubuntu1.9"}], "libdatrie1": [{"arch": "amd64", "category": "libs", "name": "libdatrie1", "origin": "Ubuntu", "source": "apt", "version": "0.2.12-3"}], "libdb5.3": [{"arch": "amd64", "category": "libs", "name": "libdb5.3", "origin": "Ubuntu", "source": "apt", "version": "5.3.28+dfsg1-0.6ubuntu2"}], "libdbus-1-3": [{"arch": "amd64", "category": "libs", "name": "libdbus-1-3", "origin": "Ubuntu", "source": "apt", "version": "1.12.16-2ubuntu2.3"}], "libdebconfclient0": [{"arch": "amd64", "category": "libs", "name": "libdebconfclient0", "origin": "Ubuntu", "source": "apt", "version": "0.251ubuntu1"}], "libdevmapper1.02.1": [{"arch": "amd64", "category": "libs", "name": "libdevmapper1.02.1", "origin": "Ubuntu", "source": "apt", "version": "2:1.02.167-1ubuntu1"}], "libdpkg-perl": [{"arch": "all", "category": "perl", "name": "libdpkg-perl", "origin": "Ubuntu", "source": "apt", "version": "1.19.7ubuntu3.2"}], "libdrm-amdgpu1": [{"arch": "amd64", "category": "libs", "name": "libdrm-amdgpu1", "origin": "Ubuntu", "source": "apt", "version": "2.4.107-8ubuntu1~20.04.2"}], "libdrm-common": [{"arch": "all", "category": "libs", "name": "libdrm-common", "origin": "Ubuntu", "source": "apt", "version": "2.4.107-8ubuntu1~20.04.2"}], "libdrm-intel1": [{"arch": "amd64", "category": "libs", "name": "libdrm-intel1", "origin": "Ubuntu", "source": "apt", "version": "2.4.107-8ubuntu1~20.04.2"}], "libdrm-nouveau2": [{"arch": "amd64", "category": "libs", "name": "libdrm-nouveau2", "origin": "Ubuntu", "source": "apt", "version": "2.4.107-8ubuntu1~20.04.2"}], "libdrm-radeon1": [{"arch": "amd64", "category": "libs", "name": "libdrm-radeon1", "origin": "Ubuntu", "source": "apt", "version": "2.4.107-8ubuntu1~20.04.2"}], "libdrm2": [{"arch": "amd64", "category": "libs", "name": "libdrm2", "origin": "Ubuntu", "source": "apt", "version": "2.4.107-8ubuntu1~20.04.2"}], "libedit2": [{"arch": "amd64", "category": "libs", "name": "libedit2", "origin": "Ubuntu", "source": "apt", "version": "3.1-20191231-1"}], "libelf1": [{"arch": "amd64", "category": "libs", "name": "libelf1", "origin": "Ubuntu", "source": "apt", "version": "0.176-1.1ubuntu0.1"}], "libexpat1": [{"arch": "amd64", "category": "libs", "name": "libexpat1", "origin": "Ubuntu", "source": "apt", "version": "2.2.9-1ubuntu0.7"}], "libexpat1-dev": [{"arch": "amd64", "category": "libdevel", "name": "libexpat1-dev", "origin": "Ubuntu", "source": "apt", "version": "2.2.9-1ubuntu0.7"}], "libext2fs2": [{"arch": "amd64", "category": "libs", "name": "libext2fs2", "origin": "Ubuntu", "source": "apt", "version": "1.45.5-2ubuntu1.2"}], "libfakeroot": [{"arch": "amd64", "category": "utils", "name": "libfakeroot", "origin": "Ubuntu", "source": "apt", "version": "1.24-1"}], "libfdisk1": [{"arch": "amd64", "category": "libs", "name": "libfdisk1", "origin": "Ubuntu", "source": "apt", "version": "2.34-0.1ubuntu9.6"}], "libffi7": [{"arch": "amd64", "category": "libs", "name": "libffi7", "origin": "Ubuntu", "source": "apt", "version": "3.3-4"}], "libfido2-1": [{"arch": "amd64", "category": "libs", "name": "libfido2-1", "origin": "Ubuntu", "source": "apt", "version": "1.3.1-1ubuntu2"}], "libfile-fcntllock-perl": [{"arch": "amd64", "category": "perl", "name": "libfile-fcntllock-perl", "origin": "Ubuntu", "source": "apt", "version": "0.22-3build4"}], "libfontconfig1": [{"arch": "amd64", "category": "libs", "name": "libfontconfig1", "origin": "Ubuntu", "source": "apt", "version": "2.13.1-2ubuntu3"}], "libfontenc1": [{"arch": "amd64", "category": "x11", "name": "libfontenc1", "origin": "Ubuntu", "source": "apt", "version": "1:1.1.4-0ubuntu1"}], "libfreetype6": [{"arch": "amd64", "category": "libs", "name": "libfreetype6", "origin": "Ubuntu", "source": "apt", "version": "2.10.1-2ubuntu0.3"}], "libfribidi0": [{"arch": "amd64", "category": "libs", "name": "libfribidi0", "origin": "Ubuntu", "source": "apt", "version": "1.0.8-2ubuntu0.1"}], "libgail-common": [{"arch": "amd64", "category": "libs", "name": "libgail-common", "origin": "Ubuntu", "source": "apt", "version": "2.24.32-4ubuntu4.1"}], "libgail18": [{"arch": "amd64", "category": "libs", "name": "libgail18", "origin": "Ubuntu", "source": "apt", "version": "2.24.32-4ubuntu4.1"}], "libgcc-9-dev": [{"arch": "amd64", "category": "libdevel", "name": "libgcc-9-dev", "origin": "Ubuntu", "source": "apt", "version": "9.4.0-1ubuntu1~20.04.2"}], "libgcc-s1": [{"arch": "amd64", "category": "libs", "name": "libgcc-s1", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "libgcrypt20": [{"arch": "amd64", "category": "libs", "name": "libgcrypt20", "origin": "Ubuntu", "source": "apt", "version": "1.8.5-5ubuntu1.1"}], "libgdbm-compat4": [{"arch": "amd64", "category": "libs", "name": "libgdbm-compat4", "origin": "Ubuntu", "source": "apt", "version": "1.18.1-5"}], "libgdbm6": [{"arch": "amd64", "category": "libs", "name": "libgdbm6", "origin": "Ubuntu", "source": "apt", "version": "1.18.1-5"}], "libgdk-pixbuf2.0-0": [{"arch": "amd64", "category": "libs", "name": "libgdk-pixbuf2.0-0", "origin": "Ubuntu", "source": "apt", "version": "2.40.0+dfsg-3ubuntu0.5"}], "libgdk-pixbuf2.0-bin": [{"arch": "amd64", "category": "libs", "name": "libgdk-pixbuf2.0-bin", "origin": "Ubuntu", "source": "apt", "version": "2.40.0+dfsg-3ubuntu0.5"}], "libgdk-pixbuf2.0-common": [{"arch": "all", "category": "libs", "name": "libgdk-pixbuf2.0-common", "origin": "Ubuntu", "source": "apt", "version": "2.40.0+dfsg-3ubuntu0.5"}], "libgif7": [{"arch": "amd64", "category": "libs", "name": "libgif7", "origin": "Ubuntu", "source": "apt", "version": "5.1.9-1ubuntu0.1"}], "libgirepository-1.0-1": [{"arch": "amd64", "category": "libs", "name": "libgirepository-1.0-1", "origin": "Ubuntu", "source": "apt", "version": "1.64.1-1~ubuntu20.04.1"}], "libgl1": [{"arch": "amd64", "category": "libs", "name": "libgl1", "origin": "Ubuntu", "source": "apt", "version": "1.3.2-1~ubuntu0.20.04.2"}], "libgl1-mesa-dri": [{"arch": "amd64", "category": "libs", "name": "libgl1-mesa-dri", "origin": "Ubuntu", "source": "apt", "version": "21.2.6-0ubuntu0.1~20.04.2"}], "libglapi-mesa": [{"arch": "amd64", "category": "libs", "name": "libglapi-mesa", "origin": "Ubuntu", "source": "apt", "version": "21.2.6-0ubuntu0.1~20.04.2"}], "libglib2.0-0": [{"arch": "amd64", "category": "libs", "name": "libglib2.0-0", "origin": "Ubuntu", "source": "apt", "version": "2.64.6-1~ubuntu20.04.7"}], "libglib2.0-data": [{"arch": "all", "category": "misc", "name": "libglib2.0-data", "origin": "Ubuntu", "source": "apt", "version": "2.64.6-1~ubuntu20.04.7"}], "libglvnd0": [{"arch": "amd64", "category": "libs", "name": "libglvnd0", "origin": "Ubuntu", "source": "apt", "version": "1.3.2-1~ubuntu0.20.04.2"}], "libglx-mesa0": [{"arch": "amd64", "category": "libs", "name": "libglx-mesa0", "origin": "Ubuntu", "source": "apt", "version": "21.2.6-0ubuntu0.1~20.04.2"}], "libglx0": [{"arch": "amd64", "category": "libs", "name": "libglx0", "origin": "Ubuntu", "source": "apt", "version": "1.3.2-1~ubuntu0.20.04.2"}], "libgmp10": [{"arch": "amd64", "category": "libs", "name": "libgmp10", "origin": "Ubuntu", "source": "apt", "version": "2:6.2.0+dfsg-4ubuntu0.1"}], "libgnutls30": [{"arch": "amd64", "category": "libs", "name": "libgnutls30", "origin": "Ubuntu", "source": "apt", "version": "3.6.13-2ubuntu1.11"}], "libgomp1": [{"arch": "amd64", "category": "libs", "name": "libgomp1", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "libgpg-error0": [{"arch": "amd64", "category": "libs", "name": "libgpg-error0", "origin": "Ubuntu", "source": "apt", "version": "1.37-1"}], "libgraphite2-3": [{"arch": "amd64", "category": "libs", "name": "libgraphite2-3", "origin": "Ubuntu", "source": "apt", "version": "1.3.13-11build1"}], "libgssapi-krb5-2": [{"arch": "amd64", "category": "libs", "name": "libgssapi-krb5-2", "origin": "Ubuntu", "source": "apt", "version": "1.17-6ubuntu4.7"}], "libgssapi3-heimdal": [{"arch": "amd64", "category": "libs", "name": "libgssapi3-heimdal", "origin": "Ubuntu", "source": "apt", "version": "7.7.0+dfsg-1ubuntu1.4"}], "libgtk2.0-0": [{"arch": "amd64", "category": "libs", "name": "libgtk2.0-0", "origin": "Ubuntu", "source": "apt", "version": "2.24.32-4ubuntu4.1"}], "libgtk2.0-bin": [{"arch": "amd64", "category": "misc", "name": "libgtk2.0-bin", "origin": "Ubuntu", "source": "apt", "version": "2.24.32-4ubuntu4.1"}], "libgtk2.0-common": [{"arch": "all", "category": "misc", "name": "libgtk2.0-common", "origin": "Ubuntu", "source": "apt", "version": "2.24.32-4ubuntu4.1"}], "libharfbuzz0b": [{"arch": "amd64", "category": "libs", "name": "libharfbuzz0b", "origin": "Ubuntu", "source": "apt", "version": "2.6.4-1ubuntu4.2"}], "libhcrypto4-heimdal": [{"arch": "amd64", "category": "libs", "name": "libhcrypto4-heimdal", "origin": "Ubuntu", "source": "apt", "version": "7.7.0+dfsg-1ubuntu1.4"}], "libheimbase1-heimdal": [{"arch": "amd64", "category": "libs", "name": "libheimbase1-heimdal", "origin": "Ubuntu", "source": "apt", "version": "7.7.0+dfsg-1ubuntu1.4"}], "libheimntlm0-heimdal": [{"arch": "amd64", "category": "libs", "name": "libheimntlm0-heimdal", "origin": "Ubuntu", "source": "apt", "version": "7.7.0+dfsg-1ubuntu1.4"}], "libhogweed5": [{"arch": "amd64", "category": "libs", "name": "libhogweed5", "origin": "Ubuntu", "source": "apt", "version": "3.5.1+really3.5.1-2ubuntu0.2"}], "libhx509-5-heimdal": [{"arch": "amd64", "category": "libs", "name": "libhx509-5-heimdal", "origin": "Ubuntu", "source": "apt", "version": "7.7.0+dfsg-1ubuntu1.4"}], "libice-dev": [{"arch": "amd64", "category": "libdevel", "name": "libice-dev", "origin": "Ubuntu", "source": "apt", "version": "2:1.0.10-0ubuntu1"}], "libice6": [{"arch": "amd64", "category": "libs", "name": "libice6", "origin": "Ubuntu", "source": "apt", "version": "2:1.0.10-0ubuntu1"}], "libicu66": [{"arch": "amd64", "category": "libs", "name": "libicu66", "origin": "Ubuntu", "source": "apt", "version": "66.1-2ubuntu2.1"}], "libidn2-0": [{"arch": "amd64", "category": "libs", "name": "libidn2-0", "origin": "Ubuntu", "source": "apt", "version": "2.2.0-2"}], "libip4tc2": [{"arch": "amd64", "category": "libs", "name": "libip4tc2", "origin": "Ubuntu", "source": "apt", "version": "1.8.4-3ubuntu2.1"}], "libisl22": [{"arch": "amd64", "category": "libs", "name": "libisl22", "origin": "Ubuntu", "source": "apt", "version": "0.22.1-1"}], "libitm1": [{"arch": "amd64", "category": "libs", "name": "libitm1", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "libjbig0": [{"arch": "amd64", "category": "libs", "name": "libjbig0", "origin": "Ubuntu", "source": "apt", "version": "2.1-3.1ubuntu0.20.04.1"}], "libjpeg-turbo8": [{"arch": "amd64", "category": "libs", "name": "libjpeg-turbo8", "origin": "Ubuntu", "source": "apt", "version": "2.0.3-0ubuntu1.20.04.3"}], "libjpeg8": [{"arch": "amd64", "category": "libs", "name": "libjpeg8", "origin": "Ubuntu", "source": "apt", "version": "8c-2ubuntu8"}], "libjson-c4": [{"arch": "amd64", "category": "libs", "name": "libjson-c4", "origin": "Ubuntu", "source": "apt", "version": "0.13.1+dfsg-7ubuntu0.3"}], "libk5crypto3": [{"arch": "amd64", "category": "libs", "name": "libk5crypto3", "origin": "Ubuntu", "source": "apt", "version": "1.17-6ubuntu4.7"}], "libkeyutils1": [{"arch": "amd64", "category": "misc", "name": "libkeyutils1", "origin": "Ubuntu", "source": "apt", "version": "1.6-6ubuntu1.1"}], "libkmod2": [{"arch": "amd64", "category": "libs", "name": "libkmod2", "origin": "Ubuntu", "source": "apt", "version": "27-1ubuntu2.1"}], "libkrb5-26-heimdal": [{"arch": "amd64", "category": "libs", "name": "libkrb5-26-heimdal", "origin": "Ubuntu", "source": "apt", "version": "7.7.0+dfsg-1ubuntu1.4"}], "libkrb5-3": [{"arch": "amd64", "category": "libs", "name": "libkrb5-3", "origin": "Ubuntu", "source": "apt", "version": "1.17-6ubuntu4.7"}], "libkrb5support0": [{"arch": "amd64", "category": "libs", "name": "libkrb5support0", "origin": "Ubuntu", "source": "apt", "version": "1.17-6ubuntu4.7"}], "libksba8": [{"arch": "amd64", "category": "libs", "name": "libksba8", "origin": "Ubuntu", "source": "apt", "version": "1.3.5-2ubuntu0.20.04.2"}], "liblcms2-2": [{"arch": "amd64", "category": "libs", "name": "liblcms2-2", "origin": "Ubuntu", "source": "apt", "version": "2.9-4"}], "libldap-2.4-2": [{"arch": "amd64", "category": "libs", "name": "libldap-2.4-2", "origin": "Ubuntu", "source": "apt", "version": "2.4.49+dfsg-2ubuntu1.10"}], "libldap-common": [{"arch": "all", "category": "libs", "name": "libldap-common", "origin": "Ubuntu", "source": "apt", "version": "2.4.49+dfsg-2ubuntu1.10"}], "libllvm12": [{"arch": "amd64", "category": "libs", "name": "libllvm12", "origin": "Ubuntu", "source": "apt", "version": "1:12.0.0-3ubuntu1~20.04.5"}], "liblocale-gettext-perl": [{"arch": "amd64", "category": "perl", "name": "liblocale-gettext-perl", "origin": "Ubuntu", "source": "apt", "version": "1.07-4"}], "liblsan0": [{"arch": "amd64", "category": "libs", "name": "liblsan0", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "liblz4-1": [{"arch": "amd64", "category": "libs", "name": "liblz4-1", "origin": "Ubuntu", "source": "apt", "version": "1.9.2-2ubuntu0.20.04.1"}], "liblzma5": [{"arch": "amd64", "category": "libs", "name": "liblzma5", "origin": "Ubuntu", "source": "apt", "version": "5.2.4-1ubuntu1.1"}], "libmagic-mgc": [{"arch": "amd64", "category": "libs", "name": "libmagic-mgc", "origin": "Ubuntu", "source": "apt", "version": "1:5.38-4"}], "libmagic1": [{"arch": "amd64", "category": "libs", "name": "libmagic1", "origin": "Ubuntu", "source": "apt", "version": "1:5.38-4"}], "libmount1": [{"arch": "amd64", "category": "libs", "name": "libmount1", "origin": "Ubuntu", "source": "apt", "version": "2.34-0.1ubuntu9.6"}], "libmpc3": [{"arch": "amd64", "category": "libs", "name": "libmpc3", "origin": "Ubuntu", "source": "apt", "version": "1.1.0-1"}], "libmpdec2": [{"arch": "amd64", "category": "libs", "name": "libmpdec2", "origin": "Ubuntu", "source": "apt", "version": "2.4.2-3"}], "libmpfr6": [{"arch": "amd64", "category": "libs", "name": "libmpfr6", "origin": "Ubuntu", "source": "apt", "version": "4.0.2-1"}], "libncurses6": [{"arch": "amd64", "category": "libs", "name": "libncurses6", "origin": "Ubuntu", "source": "apt", "version": "6.2-0ubuntu2.1"}], "libncursesw6": [{"arch": "amd64", "category": "libs", "name": "libncursesw6", "origin": "Ubuntu", "source": "apt", "version": "6.2-0ubuntu2.1"}], "libnettle7": [{"arch": "amd64", "category": "libs", "name": "libnettle7", "origin": "Ubuntu", "source": "apt", "version": "3.5.1+really3.5.1-2ubuntu0.2"}], "libnpth0": [{"arch": "amd64", "category": "libs", "name": "libnpth0", "origin": "Ubuntu", "source": "apt", "version": "1.6-1"}], "libnspr4": [{"arch": "amd64", "category": "libs", "name": "libnspr4", "origin": "Ubuntu", "source": "apt", "version": "2:4.35-0ubuntu0.20.04.1"}], "libnss-systemd": [{"arch": "amd64", "category": "admin", "name": "libnss-systemd", "origin": "Ubuntu", "source": "apt", "version": "245.4-4ubuntu3.24"}], "libnss3": [{"arch": "amd64", "category": "libs", "name": "libnss3", "origin": "Ubuntu", "source": "apt", "version": "2:3.98-0ubuntu0.20.04.2"}], "libp11-kit0": [{"arch": "amd64", "category": "libs", "name": "libp11-kit0", "origin": "Ubuntu", "source": "apt", "version": "0.23.20-1ubuntu0.1"}], "libpam-modules": [{"arch": "amd64", "category": "admin", "name": "libpam-modules", "origin": "Ubuntu", "source": "apt", "version": "1.3.1-5ubuntu4.7"}], "libpam-modules-bin": [{"arch": "amd64", "category": "admin", "name": "libpam-modules-bin", "origin": "Ubuntu", "source": "apt", "version": "1.3.1-5ubuntu4.7"}], "libpam-runtime": [{"arch": "all", "category": "admin", "name": "libpam-runtime", "origin": "Ubuntu", "source": "apt", "version": "1.3.1-5ubuntu4.7"}], "libpam-systemd": [{"arch": "amd64", "category": "admin", "name": "libpam-systemd", "origin": "Ubuntu", "source": "apt", "version": "245.4-4ubuntu3.24"}], "libpam0g": [{"arch": "amd64", "category": "libs", "name": "libpam0g", "origin": "Ubuntu", "source": "apt", "version": "1.3.1-5ubuntu4.7"}], "libpango-1.0-0": [{"arch": "amd64", "category": "libs", "name": "libpango-1.0-0", "origin": "Ubuntu", "source": "apt", "version": "1.44.7-2ubuntu4"}], "libpangocairo-1.0-0": [{"arch": "amd64", "category": "libs", "name": "libpangocairo-1.0-0", "origin": "Ubuntu", "source": "apt", "version": "1.44.7-2ubuntu4"}], "libpangoft2-1.0-0": [{"arch": "amd64", "category": "libs", "name": "libpangoft2-1.0-0", "origin": "Ubuntu", "source": "apt", "version": "1.44.7-2ubuntu4"}], "libpciaccess0": [{"arch": "amd64", "category": "libs", "name": "libpciaccess0", "origin": "Ubuntu", "source": "apt", "version": "0.16-0ubuntu1"}], "libpcre2-8-0": [{"arch": "amd64", "category": "libs", "name": "libpcre2-8-0", "origin": "Ubuntu", "source": "apt", "version": "10.34-7ubuntu0.1"}], "libpcre3": [{"arch": "amd64", "category": "libs", "name": "libpcre3", "origin": "Ubuntu", "source": "apt", "version": "2:8.39-12ubuntu0.1"}], "libpcsclite1": [{"arch": "amd64", "category": "libs", "name": "libpcsclite1", "origin": "Ubuntu", "source": "apt", "version": "1.8.26-3"}], "libperl5.30": [{"arch": "amd64", "category": "libs", "name": "libperl5.30", "origin": "Ubuntu", "source": "apt", "version": "5.30.0-9ubuntu0.5"}], "libpixman-1-0": [{"arch": "amd64", "category": "libs", "name": "libpixman-1-0", "origin": "Ubuntu", "source": "apt", "version": "0.38.4-0ubuntu2.1"}], "libpng16-16": [{"arch": "amd64", "category": "libs", "name": "libpng16-16", "origin": "Ubuntu", "source": "apt", "version": "1.6.37-2"}], "libprocps8": [{"arch": "amd64", "category": "libs", "name": "libprocps8", "origin": "Ubuntu", "source": "apt", "version": "2:3.3.16-1ubuntu2.4"}], "libpsl5": [{"arch": "amd64", "category": "libs", "name": "libpsl5", "origin": "Ubuntu", "source": "apt", "version": "0.21.0-1ubuntu1"}], "libpthread-stubs0-dev": [{"arch": "amd64", "category": "libdevel", "name": "libpthread-stubs0-dev", "origin": "Ubuntu", "source": "apt", "version": "0.4-1"}], "libpython3-dev": [{"arch": "amd64", "category": "python", "name": "libpython3-dev", "origin": "Ubuntu", "source": "apt", "version": "3.8.2-0ubuntu2"}], "libpython3-stdlib": [{"arch": "amd64", "category": "python", "name": "libpython3-stdlib", "origin": "Ubuntu", "source": "apt", "version": "3.8.2-0ubuntu2"}], "libpython3.8": [{"arch": "amd64", "category": "libs", "name": "libpython3.8", "origin": "Ubuntu", "source": "apt", "version": "3.8.10-0ubuntu1~20.04.12"}], "libpython3.8-dev": [{"arch": "amd64", "category": "libdevel", "name": "libpython3.8-dev", "origin": "Ubuntu", "source": "apt", "version": "3.8.10-0ubuntu1~20.04.12"}], "libpython3.8-minimal": [{"arch": "amd64", "category": "python", "name": "libpython3.8-minimal", "origin": "Ubuntu", "source": "apt", "version": "3.8.10-0ubuntu1~20.04.12"}], "libpython3.8-stdlib": [{"arch": "amd64", "category": "python", "name": "libpython3.8-stdlib", "origin": "Ubuntu", "source": "apt", "version": "3.8.10-0ubuntu1~20.04.12"}], "libquadmath0": [{"arch": "amd64", "category": "libs", "name": "libquadmath0", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "libreadline8": [{"arch": "amd64", "category": "libs", "name": "libreadline8", "origin": "Ubuntu", "source": "apt", "version": "8.0-4"}], "libroken18-heimdal": [{"arch": "amd64", "category": "libs", "name": "libroken18-heimdal", "origin": "Ubuntu", "source": "apt", "version": "7.7.0+dfsg-1ubuntu1.4"}], "librsvg2-2": [{"arch": "amd64", "category": "libs", "name": "librsvg2-2", "origin": "Ubuntu", "source": "apt", "version": "2.48.9-1ubuntu0.20.04.4"}], "librsvg2-common": [{"arch": "amd64", "category": "libs", "name": "librsvg2-common", "origin": "Ubuntu", "source": "apt", "version": "2.48.9-1ubuntu0.20.04.4"}], "libsasl2-2": [{"arch": "amd64", "category": "libs", "name": "libsasl2-2", "origin": "Ubuntu", "source": "apt", "version": "2.1.27+dfsg-2ubuntu0.1"}], "libsasl2-modules": [{"arch": "amd64", "category": "devel", "name": "libsasl2-modules", "origin": "Ubuntu", "source": "apt", "version": "2.1.27+dfsg-2ubuntu0.1"}], "libsasl2-modules-db": [{"arch": "amd64", "category": "libs", "name": "libsasl2-modules-db", "origin": "Ubuntu", "source": "apt", "version": "2.1.27+dfsg-2ubuntu0.1"}], "libseccomp2": [{"arch": "amd64", "category": "libs", "name": "libseccomp2", "origin": "Ubuntu", "source": "apt", "version": "2.5.1-1ubuntu1~20.04.2"}], "libselinux1": [{"arch": "amd64", "category": "libs", "name": "libselinux1", "origin": "Ubuntu", "source": "apt", "version": "3.0-1build2"}], "libsemanage-common": [{"arch": "all", "category": "libs", "name": "libsemanage-common", "origin": "Ubuntu", "source": "apt", "version": "3.0-1build2"}], "libsemanage1": [{"arch": "amd64", "category": "libs", "name": "libsemanage1", "origin": "Ubuntu", "source": "apt", "version": "3.0-1build2"}], "libsensors-config": [{"arch": "all", "category": "utils", "name": "libsensors-config", "origin": "Ubuntu", "source": "apt", "version": "1:3.6.0-2ubuntu1.1"}], "libsensors5": [{"arch": "amd64", "category": "libs", "name": "libsensors5", "origin": "Ubuntu", "source": "apt", "version": "1:3.6.0-2ubuntu1.1"}], "libsepol1": [{"arch": "amd64", "category": "libs", "name": "libsepol1", "origin": "Ubuntu", "source": "apt", "version": "3.0-1ubuntu0.1"}], "libsm-dev": [{"arch": "amd64", "category": "libdevel", "name": "libsm-dev", "origin": "Ubuntu", "source": "apt", "version": "2:1.2.3-1"}], "libsm6": [{"arch": "amd64", "category": "libs", "name": "libsm6", "origin": "Ubuntu", "source": "apt", "version": "2:1.2.3-1"}], "libsmartcols1": [{"arch": "amd64", "category": "libs", "name": "libsmartcols1", "origin": "Ubuntu", "source": "apt", "version": "2.34-0.1ubuntu9.6"}], "libsqlite3-0": [{"arch": "amd64", "category": "libs", "name": "libsqlite3-0", "origin": "Ubuntu", "source": "apt", "version": "3.31.1-4ubuntu0.6"}], "libss2": [{"arch": "amd64", "category": "libs", "name": "libss2", "origin": "Ubuntu", "source": "apt", "version": "1.45.5-2ubuntu1.2"}], "libssl1.1": [{"arch": "amd64", "category": "libs", "name": "libssl1.1", "origin": "Ubuntu", "source": "apt", "version": "1.1.1f-1ubuntu2.23"}], "libstdc++-9-dev": [{"arch": "amd64", "category": "libdevel", "name": "libstdc++-9-dev", "origin": "Ubuntu", "source": "apt", "version": "9.4.0-1ubuntu1~20.04.2"}], "libstdc++6": [{"arch": "amd64", "category": "libs", "name": "libstdc++6", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "libsystemd0": [{"arch": "amd64", "category": "libs", "name": "libsystemd0", "origin": "Ubuntu", "source": "apt", "version": "245.4-4ubuntu3.24"}], "libtasn1-6": [{"arch": "amd64", "category": "libs", "name": "libtasn1-6", "origin": "Ubuntu", "source": "apt", "version": "4.16.0-2"}], "libthai-data": [{"arch": "all", "category": "libs", "name": "libthai-data", "origin": "Ubuntu", "source": "apt", "version": "0.1.28-3"}], "libthai0": [{"arch": "amd64", "category": "libs", "name": "libthai0", "origin": "Ubuntu", "source": "apt", "version": "0.1.28-3"}], "libtiff5": [{"arch": "amd64", "category": "libs", "name": "libtiff5", "origin": "Ubuntu", "source": "apt", "version": "4.1.0+git191117-2ubuntu0.20.04.14"}], "libtinfo6": [{"arch": "amd64", "category": "libs", "name": "libtinfo6", "origin": "Ubuntu", "source": "apt", "version": "6.2-0ubuntu2.1"}], "libtsan0": [{"arch": "amd64", "category": "libs", "name": "libtsan0", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "libubsan1": [{"arch": "amd64", "category": "libs", "name": "libubsan1", "origin": "Ubuntu", "source": "apt", "version": "10.5.0-1ubuntu1~20.04"}], "libudev1": [{"arch": "amd64", "category": "libs", "name": "libudev1", "origin": "Ubuntu", "source": "apt", "version": "245.4-4ubuntu3.24"}], "libunistring2": [{"arch": "amd64", "category": "libs", "name": "libunistring2", "origin": "Ubuntu", "source": "apt", "version": "0.9.10-2"}], "libuuid1": [{"arch": "amd64", "category": "libs", "name": "libuuid1", "origin": "Ubuntu", "source": "apt", "version": "2.34-0.1ubuntu9.6"}], "libvulkan1": [{"arch": "amd64", "category": "libs", "name": "libvulkan1", "origin": "Ubuntu", "source": "apt", "version": "1.2.131.2-1"}], "libwayland-client0": [{"arch": "amd64", "category": "libs", "name": "libwayland-client0", "origin": "Ubuntu", "source": "apt", "version": "1.18.0-1ubuntu0.1"}], "libwebp6": [{"arch": "amd64", "category": "libs", "name": "libwebp6", "origin": "Ubuntu", "source": "apt", "version": "0.6.1-2ubuntu0.20.04.3"}], "libwind0-heimdal": [{"arch": "amd64", "category": "libs", "name": "libwind0-heimdal", "origin": "Ubuntu", "source": "apt", "version": "7.7.0+dfsg-1ubuntu1.4"}], "libwrap0": [{"arch": "amd64", "category": "libs", "name": "libwrap0", "origin": "Ubuntu", "source": "apt", "version": "7.6.q-30"}], "libx11-6": [{"arch": "amd64", "category": "libs", "name": "libx11-6", "origin": "Ubuntu", "source": "apt", "version": "2:1.6.9-2ubuntu1.6"}], "libx11-data": [{"arch": "all", "category": "x11", "name": "libx11-data", "origin": "Ubuntu", "source": "apt", "version": "2:1.6.9-2ubuntu1.6"}], "libx11-dev": [{"arch": "amd64", "category": "libdevel", "name": "libx11-dev", "origin": "Ubuntu", "source": "apt", "version": "2:1.6.9-2ubuntu1.6"}], "libx11-xcb1": [{"arch": "amd64", "category": "libs", "name": "libx11-xcb1", "origin": "Ubuntu", "source": "apt", "version": "2:1.6.9-2ubuntu1.6"}], "libxau-dev": [{"arch": "amd64", "category": "libdevel", "name": "libxau-dev", "origin": "Ubuntu", "source": "apt", "version": "1:1.0.9-0ubuntu1"}], "libxau6": [{"arch": "amd64", "category": "libs", "name": "libxau6", "origin": "Ubuntu", "source": "apt", "version": "1:1.0.9-0ubuntu1"}], "libxaw7": [{"arch": "amd64", "category": "libs", "name": "libxaw7", "origin": "Ubuntu", "source": "apt", "version": "2:1.0.13-1"}], "libxcb-dri2-0": [{"arch": "amd64", "category": "libs", "name": "libxcb-dri2-0", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb-dri3-0": [{"arch": "amd64", "category": "libs", "name": "libxcb-dri3-0", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb-glx0": [{"arch": "amd64", "category": "libs", "name": "libxcb-glx0", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb-present0": [{"arch": "amd64", "category": "libs", "name": "libxcb-present0", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb-randr0": [{"arch": "amd64", "category": "libs", "name": "libxcb-randr0", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb-render0": [{"arch": "amd64", "category": "libs", "name": "libxcb-render0", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb-shape0": [{"arch": "amd64", "category": "libs", "name": "libxcb-shape0", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb-shm0": [{"arch": "amd64", "category": "libs", "name": "libxcb-shm0", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb-sync1": [{"arch": "amd64", "category": "libs", "name": "libxcb-sync1", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb-xfixes0": [{"arch": "amd64", "category": "libs", "name": "libxcb-xfixes0", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb1": [{"arch": "amd64", "category": "libs", "name": "libxcb1", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcb1-dev": [{"arch": "amd64", "category": "libdevel", "name": "libxcb1-dev", "origin": "Ubuntu", "source": "apt", "version": "1.14-2"}], "libxcomposite1": [{"arch": "amd64", "category": "libs", "name": "libxcomposite1", "origin": "Ubuntu", "source": "apt", "version": "1:0.4.5-1"}], "libxcursor1": [{"arch": "amd64", "category": "libs", "name": "libxcursor1", "origin": "Ubuntu", "source": "apt", "version": "1:1.2.0-2"}], "libxdamage1": [{"arch": "amd64", "category": "libs", "name": "libxdamage1", "origin": "Ubuntu", "source": "apt", "version": "1:1.1.5-2"}], "libxdmcp-dev": [{"arch": "amd64", "category": "libdevel", "name": "libxdmcp-dev", "origin": "Ubuntu", "source": "apt", "version": "1:1.1.3-0ubuntu1"}], "libxdmcp6": [{"arch": "amd64", "category": "libs", "name": "libxdmcp6", "origin": "Ubuntu", "source": "apt", "version": "1:1.1.3-0ubuntu1"}], "libxext6": [{"arch": "amd64", "category": "libs", "name": "libxext6", "origin": "Ubuntu", "source": "apt", "version": "2:1.3.4-0ubuntu1"}], "libxfixes3": [{"arch": "amd64", "category": "libs", "name": "libxfixes3", "origin": "Ubuntu", "source": "apt", "version": "1:5.0.3-2"}], "libxft2": [{"arch": "amd64", "category": "libs", "name": "libxft2", "origin": "Ubuntu", "source": "apt", "version": "2.3.3-0ubuntu1"}], "libxi6": [{"arch": "amd64", "category": "libs", "name": "libxi6", "origin": "Ubuntu", "source": "apt", "version": "2:1.7.10-0ubuntu1"}], "libxinerama1": [{"arch": "amd64", "category": "libs", "name": "libxinerama1", "origin": "Ubuntu", "source": "apt", "version": "2:1.1.4-2"}], "libxkbfile1": [{"arch": "amd64", "category": "libs", "name": "libxkbfile1", "origin": "Ubuntu", "source": "apt", "version": "1:1.1.0-1"}], "libxml2": [{"arch": "amd64", "category": "libs", "name": "libxml2", "origin": "Ubuntu", "source": "apt", "version": "2.9.10+dfsg-5ubuntu0.20.04.7"}], "libxmu6": [{"arch": "amd64", "category": "libs", "name": "libxmu6", "origin": "Ubuntu", "source": "apt", "version": "2:1.1.3-0ubuntu1"}], "libxmuu1": [{"arch": "amd64", "category": "libs", "name": "libxmuu1", "origin": "Ubuntu", "source": "apt", "version": "2:1.1.3-0ubuntu1"}], "libxpm4": [{"arch": "amd64", "category": "libs", "name": "libxpm4", "origin": "Ubuntu", "source": "apt", "version": "1:3.5.12-1ubuntu0.20.04.2"}], "libxrandr2": [{"arch": "amd64", "category": "libs", "name": "libxrandr2", "origin": "Ubuntu", "source": "apt", "version": "2:1.5.2-0ubuntu1"}], "libxrender1": [{"arch": "amd64", "category": "libs", "name": "libxrender1", "origin": "Ubuntu", "source": "apt", "version": "1:0.9.10-1"}], "libxshmfence1": [{"arch": "amd64", "category": "libs", "name": "libxshmfence1", "origin": "Ubuntu", "source": "apt", "version": "1.3-1"}], "libxt-dev": [{"arch": "amd64", "category": "libdevel", "name": "libxt-dev", "origin": "Ubuntu", "source": "apt", "version": "1:1.1.5-1"}], "libxt6": [{"arch": "amd64", "category": "libs", "name": "libxt6", "origin": "Ubuntu", "source": "apt", "version": "1:1.1.5-1"}], "libxtst6": [{"arch": "amd64", "category": "libs", "name": "libxtst6", "origin": "Ubuntu", "source": "apt", "version": "2:1.2.3-1"}], "libxv1": [{"arch": "amd64", "category": "libs", "name": "libxv1", "origin": "Ubuntu", "source": "apt", "version": "2:1.0.11-1"}], "libxxf86dga1": [{"arch": "amd64", "category": "libs", "name": "libxxf86dga1", "origin": "Ubuntu", "source": "apt", "version": "2:1.1.5-0ubuntu1"}], "libxxf86vm1": [{"arch": "amd64", "category": "libs", "name": "libxxf86vm1", "origin": "Ubuntu", "source": "apt", "version": "1:1.1.4-1build1"}], "libzstd1": [{"arch": "amd64", "category": "libs", "name": "libzstd1", "origin": "Ubuntu", "source": "apt", "version": "1.4.4+dfsg-3ubuntu0.1"}], "linux-libc-dev": [{"arch": "amd64", "category": "devel", "name": "linux-libc-dev", "origin": "Ubuntu", "source": "apt", "version": "5.4.0-198.218"}], "login": [{"arch": "amd64", "category": "admin", "name": "login", "origin": "Ubuntu", "source": "apt", "version": "1:4.8.1-1ubuntu5.20.04.5"}], "logsave": [{"arch": "amd64", "category": "admin", "name": "logsave", "origin": "Ubuntu", "source": "apt", "version": "1.45.5-2ubuntu1.2"}], "lsb-base": [{"arch": "all", "category": "misc", "name": "lsb-base", "origin": "Ubuntu", "source": "apt", "version": "11.1.0ubuntu2"}], "lsb-release": [{"arch": "all", "category": "misc", "name": "lsb-release", "origin": "Ubuntu", "source": "apt", "version": "11.1.0ubuntu2"}], "make": [{"arch": "amd64", "category": "devel", "name": "make", "origin": "Ubuntu", "source": "apt", "version": "4.2.1-1.2"}], "manpages": [{"arch": "all", "category": "doc", "name": "manpages", "origin": "Ubuntu", "source": "apt", "version": "5.05-1"}], "manpages-dev": [{"arch": "all", "category": "doc", "name": "manpages-dev", "origin": "Ubuntu", "source": "apt", "version": "5.05-1"}], "mawk": [{"arch": "amd64", "category": "utils", "name": "mawk", "origin": "Ubuntu", "source": "apt", "version": "1.3.4.20200120-2"}], "mesa-vulkan-drivers": [{"arch": "amd64", "category": "libs", "name": "mesa-vulkan-drivers", "origin": "Ubuntu", "source": "apt", "version": "21.2.6-0ubuntu0.1~20.04.2"}], "mime-support": [{"arch": "all", "category": "net", "name": "mime-support", "origin": "Ubuntu", "source": "apt", "version": "3.64ubuntu1"}], "mount": [{"arch": "amd64", "category": "admin", "name": "mount", "origin": "Ubuntu", "source": "apt", "version": "2.34-0.1ubuntu9.6"}], "ncurses-base": [{"arch": "all", "category": "utils", "name": "ncurses-base", "origin": "Ubuntu", "source": "apt", "version": "6.2-0ubuntu2.1"}], "ncurses-bin": [{"arch": "amd64", "category": "utils", "name": "ncurses-bin", "origin": "Ubuntu", "source": "apt", "version": "6.2-0ubuntu2.1"}], "ncurses-term": [{"arch": "all", "category": "admin", "name": "ncurses-term", "origin": "Ubuntu", "source": "apt", "version": "6.2-0ubuntu2.1"}], "netbase": [{"arch": "all", "category": "admin", "name": "netbase", "origin": "Ubuntu", "source": "apt", "version": "6.1"}], "networkd-dispatcher": [{"arch": "all", "category": "utils", "name": "networkd-dispatcher", "origin": "Ubuntu", "source": "apt", "version": "2.1-2~ubuntu20.04.3"}], "openjdk-11-jdk": [{"arch": "amd64", "category": "java", "name": "openjdk-11-jdk", "origin": "Ubuntu", "source": "apt", "version": "11.0.24+8-1ubuntu3~20.04"}], "openjdk-11-jdk-headless": [{"arch": "amd64", "category": "java", "name": "openjdk-11-jdk-headless", "origin": "Ubuntu", "source": "apt", "version": "11.0.24+8-1ubuntu3~20.04"}], "openjdk-11-jre": [{"arch": "amd64", "category": "java", "name": "openjdk-11-jre", "origin": "Ubuntu", "source": "apt", "version": "11.0.24+8-1ubuntu3~20.04"}], "openjdk-11-jre-headless": [{"arch": "amd64", "category": "java", "name": "openjdk-11-jre-headless", "origin": "Ubuntu", "source": "apt", "version": "11.0.24+8-1ubuntu3~20.04"}], "openjdk-17-jdk": [{"arch": "amd64", "category": "universe/java", "name": "openjdk-17-jdk", "origin": "Ubuntu", "source": "apt", "version": "17.0.12+7-1ubuntu2~20.04"}], "openjdk-17-jdk-headless": [{"arch": "amd64", "category": "universe/java", "name": "openjdk-17-jdk-headless", "origin": "Ubuntu", "source": "apt", "version": "17.0.12+7-1ubuntu2~20.04"}], "openjdk-17-jre": [{"arch": "amd64", "category": "universe/java", "name": "openjdk-17-jre", "origin": "Ubuntu", "source": "apt", "version": "17.0.12+7-1ubuntu2~20.04"}], "openjdk-17-jre-headless": [{"arch": "amd64", "category": "universe/java", "name": "openjdk-17-jre-headless", "origin": "Ubuntu", "source": "apt", "version": "17.0.12+7-1ubuntu2~20.04"}], "openssh-client": [{"arch": "amd64", "category": "net", "name": "openssh-client", "origin": "Ubuntu", "source": "apt", "version": "1:8.2p1-4ubuntu0.11"}], "openssh-server": [{"arch": "amd64", "category": "net", "name": "openssh-server", "origin": "Ubuntu", "source": "apt", "version": "1:8.2p1-4ubuntu0.11"}], "openssh-sftp-server": [{"arch": "amd64", "category": "net", "name": "openssh-sftp-server", "origin": "Ubuntu", "source": "apt", "version": "1:8.2p1-4ubuntu0.11"}], "openssl": [{"arch": "amd64", "category": "utils", "name": "openssl", "origin": "Ubuntu", "source": "apt", "version": "1.1.1f-1ubuntu2.23"}], "passwd": [{"arch": "amd64", "category": "admin", "name": "passwd", "origin": "Ubuntu", "source": "apt", "version": "1:4.8.1-1ubuntu5.20.04.5"}], "patch": [{"arch": "amd64", "category": "utils", "name": "patch", "origin": "Ubuntu", "source": "apt", "version": "2.7.6-6"}], "perl": [{"arch": "amd64", "category": "perl", "name": "perl", "origin": "Ubuntu", "source": "apt", "version": "5.30.0-9ubuntu0.5"}], "perl-base": [{"arch": "amd64", "category": "perl", "name": "perl-base", "origin": "Ubuntu", "source": "apt", "version": "5.30.0-9ubuntu0.5"}], "perl-modules-5.30": [{"arch": "all", "category": "libs", "name": "perl-modules-5.30", "origin": "Ubuntu", "source": "apt", "version": "5.30.0-9ubuntu0.5"}], "pinentry-curses": [{"arch": "amd64", "category": "utils", "name": "pinentry-curses", "origin": "Ubuntu", "source": "apt", "version": "1.1.0-3build1"}], "procps": [{"arch": "amd64", "category": "admin", "name": "procps", "origin": "Ubuntu", "source": "apt", "version": "2:3.3.16-1ubuntu2.4"}], "publicsuffix": [{"arch": "all", "category": "net", "name": "publicsuffix", "origin": "Ubuntu", "source": "apt", "version": "20200303.0012-1"}], "python-apt-common": [{"arch": "all", "category": "python", "name": "python-apt-common", "origin": "Ubuntu", "source": "apt", "version": "2.0.1ubuntu0.20.04.1"}], "python-pip-whl": [{"arch": "all", "category": "universe/python", "name": "python-pip-whl", "origin": "Ubuntu", "source": "apt", "version": "20.0.2-5ubuntu1.10"}], "python3": [{"arch": "amd64", "category": "python", "name": "python3", "origin": "Ubuntu", "source": "apt", "version": "3.8.2-0ubuntu2"}], "python3-apt": [{"arch": "amd64", "category": "python", "name": "python3-apt", "origin": "Ubuntu", "source": "apt", "version": "2.0.1ubuntu0.20.04.1"}], "python3-certifi": [{"arch": "all", "category": "python", "name": "python3-certifi", "origin": "Ubuntu", "source": "apt", "version": "2019.11.28-1"}], "python3-chardet": [{"arch": "all", "category": "python", "name": "python3-chardet", "origin": "Ubuntu", "source": "apt", "version": "3.0.4-4build1"}], "python3-dbus": [{"arch": "amd64", "category": "python", "name": "python3-dbus", "origin": "Ubuntu", "source": "apt", "version": "1.2.16-1build1"}], "python3-dev": [{"arch": "amd64", "category": "python", "name": "python3-dev", "origin": "Ubuntu", "source": "apt", "version": "3.8.2-0ubuntu2"}], "python3-distro": [{"arch": "all", "category": "python", "name": "python3-distro", "origin": "Ubuntu", "source": "apt", "version": "1.4.0-1"}], "python3-distutils": [{"arch": "all", "category": "python", "name": "python3-distutils", "origin": "Ubuntu", "source": "apt", "version": "3.8.10-0ubuntu1~20.04"}], "python3-gi": [{"arch": "amd64", "category": "python", "name": "python3-gi", "origin": "Ubuntu", "source": "apt", "version": "3.36.0-1"}], "python3-idna": [{"arch": "all", "category": "python", "name": "python3-idna", "origin": "Ubuntu", "source": "apt", "version": "2.8-1ubuntu0.1"}], "python3-lib2to3": [{"arch": "all", "category": "python", "name": "python3-lib2to3", "origin": "Ubuntu", "source": "apt", "version": "3.8.10-0ubuntu1~20.04"}], "python3-minimal": [{"arch": "amd64", "category": "python", "name": "python3-minimal", "origin": "Ubuntu", "source": "apt", "version": "3.8.2-0ubuntu2"}], "python3-pip": [{"arch": "all", "category": "universe/python", "name": "python3-pip", "origin": "Ubuntu", "source": "apt", "version": "20.0.2-5ubuntu1.10"}], "python3-pkg-resources": [{"arch": "all", "category": "python", "name": "python3-pkg-resources", "origin": "Ubuntu", "source": "apt", "version": "45.2.0-1ubuntu0.2"}], "python3-requests": [{"arch": "all", "category": "python", "name": "python3-requests", "origin": "Ubuntu", "source": "apt", "version": "2.22.0-2ubuntu1.1"}], "python3-setuptools": [{"arch": "all", "category": "python", "name": "python3-setuptools", "origin": "Ubuntu", "source": "apt", "version": "45.2.0-1ubuntu0.2"}], "python3-six": [{"arch": "all", "category": "python", "name": "python3-six", "origin": "Ubuntu", "source": "apt", "version": "1.14.0-2"}], "python3-urllib3": [{"arch": "all", "category": "python", "name": "python3-urllib3", "origin": "Ubuntu", "source": "apt", "version": "1.25.8-2ubuntu0.3"}], "python3-wheel": [{"arch": "all", "category": "universe/python", "name": "python3-wheel", "origin": "Ubuntu", "source": "apt", "version": "0.34.2-1ubuntu0.1"}], "python3.8": [{"arch": "amd64", "category": "python", "name": "python3.8", "origin": "Ubuntu", "source": "apt", "version": "3.8.10-0ubuntu1~20.04.12"}], "python3.8-dev": [{"arch": "amd64", "category": "python", "name": "python3.8-dev", "origin": "Ubuntu", "source": "apt", "version": "3.8.10-0ubuntu1~20.04.12"}], "python3.8-minimal": [{"arch": "amd64", "category": "python", "name": "python3.8-minimal", "origin": "Ubuntu", "source": "apt", "version": "3.8.10-0ubuntu1~20.04.12"}], "readline-common": [{"arch": "all", "category": "utils", "name": "readline-common", "origin": "Ubuntu", "source": "apt", "version": "8.0-4"}], "sed": [{"arch": "amd64", "category": "utils", "name": "sed", "origin": "Ubuntu", "source": "apt", "version": "4.7-1"}], "sensible-utils": [{"arch": "all", "category": "utils", "name": "sensible-utils", "origin": "Ubuntu", "source": "apt", "version": "0.0.12+nmu1"}], "shared-mime-info": [{"arch": "amd64", "category": "misc", "name": "shared-mime-info", "origin": "Ubuntu", "source": "apt", "version": "1.15-1"}], "ssh-import-id": [{"arch": "all", "category": "misc", "name": "ssh-import-id", "origin": "Ubuntu", "source": "apt", "version": "5.10-0ubuntu1"}], "sudo": [{"arch": "amd64", "category": "admin", "name": "sudo", "origin": "Ubuntu", "source": "apt", "version": "1.8.31-1ubuntu1.5"}], "systemd": [{"arch": "amd64", "category": "admin", "name": "systemd", "origin": "Ubuntu", "source": "apt", "version": "245.4-4ubuntu3.24"}], "systemd-sysv": [{"arch": "amd64", "category": "admin", "name": "systemd-sysv", "origin": "Ubuntu", "source": "apt", "version": "245.4-4ubuntu3.24"}], "systemd-timesyncd": [{"arch": "amd64", "category": "admin", "name": "systemd-timesyncd", "origin": "Ubuntu", "source": "apt", "version": "245.4-4ubuntu3.24"}], "sysvinit-utils": [{"arch": "amd64", "category": "admin", "name": "sysvinit-utils", "origin": "Ubuntu", "source": "apt", "version": "2.96-2.1ubuntu1"}], "tar": [{"arch": "amd64", "category": "utils", "name": "tar", "origin": "Ubuntu", "source": "apt", "version": "1.30+dfsg-7ubuntu0.20.04.4"}], "tzdata": [{"arch": "all", "category": "libs", "name": "tzdata", "origin": "Ubuntu", "source": "apt", "version": "2024a-0ubuntu0.20.04.1"}], "ubuntu-keyring": [{"arch": "all", "category": "misc", "name": "ubuntu-keyring", "origin": "Ubuntu", "source": "apt", "version": "2020.02.11.4"}], "ubuntu-mono": [{"arch": "all", "category": "gnome", "name": "ubuntu-mono", "origin": "Ubuntu", "source": "apt", "version": "19.04-0ubuntu3"}], "ucf": [{"arch": "all", "category": "utils", "name": "ucf", "origin": "Ubuntu", "source": "apt", "version": "3.0038+nmu1"}], "util-linux": [{"arch": "amd64", "category": "utils", "name": "util-linux", "origin": "Ubuntu", "source": "apt", "version": "2.34-0.1ubuntu9.6"}], "wget": [{"arch": "amd64", "category": "web", "name": "wget", "origin": "Ubuntu", "source": "apt", "version": "1.20.3-1ubuntu2.1"}], "x11-common": [{"arch": "all", "category": "x11", "name": "x11-common", "origin": "Ubuntu", "source": "apt", "version": "1:7.7+19ubuntu14"}], "x11-utils": [{"arch": "amd64", "category": "x11", "name": "x11-utils", "origin": "Ubuntu", "source": "apt", "version": "7.7+5"}], "x11proto-core-dev": [{"arch": "all", "category": "x11", "name": "x11proto-core-dev", "origin": "Ubuntu", "source": "apt", "version": "2019.2-1ubuntu1"}], "x11proto-dev": [{"arch": "all", "category": "x11", "name": "x11proto-dev", "origin": "Ubuntu", "source": "apt", "version": "2019.2-1ubuntu1"}], "xauth": [{"arch": "amd64", "category": "x11", "name": "xauth", "origin": "Ubuntu", "source": "apt", "version": "1:1.1-0ubuntu1"}], "xdg-user-dirs": [{"arch": "amd64", "category": "utils", "name": "xdg-user-dirs", "origin": "Ubuntu", "source": "apt", "version": "0.17-2ubuntu1"}], "xorg-sgml-doctools": [{"arch": "all", "category": "x11", "name": "xorg-sgml-doctools", "origin": "Ubuntu", "source": "apt", "version": "1:1.11-1"}], "xtrans-dev": [{"arch": "all", "category": "x11", "name": "xtrans-dev", "origin": "Ubuntu", "source": "apt", "version": "1.4.0-1"}], "xz-utils": [{"arch": "amd64", "category": "utils", "name": "xz-utils", "origin": "Ubuntu", "source": "apt", "version": "5.2.4-1ubuntu1.1"}], "zlib1g": [{"arch": "amd64", "category": "libs", "name": "zlib1g", "origin": "Ubuntu", "source": "apt", "version": "1:1.2.11.dfsg-2ubuntu1.5"}], "zlib1g-dev": [{"arch": "amd64", "category": "libdevel", "name": "zlib1g-dev", "origin": "Ubuntu", "source": "apt", "version": "1:1.2.11.dfsg-2ubuntu1.5"}]}}, "changed": false}

TASK [confluent.platform.common : Determine if Confluent Platform Package Version Will Change] ***
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"confluent_package_version_changed": false}, "changed": false}

TASK [confluent.platform.common : Get installed Confluent Packages] ************
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"confluent_packages_actual": []}, "changed": false}

TASK [confluent.platform.common : Determine Confluent Packages to Remove] ******
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"confluent_packages_removed": []}, "changed": false}

TASK [confluent.platform.common : Debug Confluent Packages to Remove] **********
skipping: [kafka-controller-3-migrated] => {"false_condition": "confluent_packages_removed|length > 0"}

TASK [confluent.platform.common : Get Service Facts] ***************************
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"services": {"NetworkManager.service": {"name": "NetworkManager.service", "source": "systemd", "state": "stopped", "status": "not-found"}, "apt-daily-upgrade.service": {"name": "apt-daily-upgrade.service", "source": "systemd", "state": "stopped", "status": "static"}, "apt-daily.service": {"name": "apt-daily.service", "source": "systemd", "state": "stopped", "status": "static"}, "auditd.service": {"name": "auditd.service", "source": "systemd", "state": "stopped", "status": "not-found"}, "autovt@.service": {"name": "autovt@.service", "source": "systemd", "state": "unknown", "status": "enabled"}, "connman.service": {"name": "connman.service", "source": "systemd", "state": "stopped", "status": "not-found"}, "console-getty.service": {"name": "console-getty.service", "source": "systemd", "state": "inactive", "status": "disabled"}, "container-getty@.service": {"name": "container-getty@.service", "source": "systemd", "state": "unknown", "status": "static"}, "cryptdisks-early.service": {"name": "cryptdisks-early.service", "source": "systemd", "state": "inactive", "status": "masked"}, "cryptdisks.service": {"name": "cryptdisks.service", "source": "systemd", "state": "inactive", "status": "masked"}, "dbus": {"name": "dbus", "source": "sysv", "state": "running"}, "dbus-org.freedesktop.hostname1.service": {"name": "dbus-org.freedesktop.hostname1.service", "source": "systemd", "state": "inactive", "status": "static"}, "dbus-org.freedesktop.locale1.service": {"name": "dbus-org.freedesktop.locale1.service", "source": "systemd", "state": "inactive", "status": "static"}, "dbus-org.freedesktop.login1.service": {"name": "dbus-org.freedesktop.login1.service", "source": "systemd", "state": "active", "status": "static"}, "dbus-org.freedesktop.resolve1.service": {"name": "dbus-org.freedesktop.resolve1.service", "source": "systemd", "state": "active", "status": "enabled"}, "dbus-org.freedesktop.timedate1.service": {"name": "dbus-org.freedesktop.timedate1.service", "source": "systemd", "state": "inactive", "status": "static"}, "dbus-org.freedesktop.timesync1.service": {"name": "dbus-org.freedesktop.timesync1.service", "source": "systemd", "state": "active", "status": "enabled"}, "dbus.service": {"name": "dbus.service", "source": "systemd", "state": "running", "status": "static"}, "debug-shell.service": {"name": "debug-shell.service", "source": "systemd", "state": "inactive", "status": "disabled"}, "display-manager.service": {"name": "display-manager.service", "source": "systemd", "state": "stopped", "status": "not-found"}, "e2scrub@.service": {"name": "e2scrub@.service", "source": "systemd", "state": "unknown", "status": "static"}, "e2scrub_all.service": {"name": "e2scrub_all.service", "source": "systemd", "state": "stopped", "status": "static"}, "e2scrub_fail@.service": {"name": "e2scrub_fail@.service", "source": "systemd", "state": "unknown", "status": "static"}, "e2scrub_reap.service": {"name": "e2scrub_reap.service", "source": "systemd", "state": "stopped", "status": "enabled"}, "emergency.service": {"name": "emergency.service", "source": "systemd", "state": "stopped", "status": "static"}, "fstrim.service": {"name": "fstrim.service", "source": "systemd", "state": "stopped", "status": "static"}, "getty-static.service": {"name": "getty-static.service", "source": "systemd", "state": "stopped", "status": "static"}, "getty@.service": {"name": "getty@.service", "source": "systemd", "state": "unknown", "status": "enabled"}, "getty@tty1.service": {"name": "getty@tty1.service", "source": "systemd", "state": "stopped", "status": "failed"}, "hwclock.service": {"name": "hwclock.service", "source": "systemd", "state": "inactive", "status": "masked"}, "hwclock.sh": {"name": "hwclock.sh", "source": "sysv", "state": "stopped"}, "initrd-cleanup.service": {"name": "initrd-cleanup.service", "source": "systemd", "state": "inactive", "status": "static"}, "initrd-parse-etc.service": {"name": "initrd-parse-etc.service", "source": "systemd", "state": "inactive", "status": "static"}, "initrd-switch-root.service": {"name": "initrd-switch-root.service", "source": "systemd", "state": "inactive", "status": "static"}, "initrd-udevadm-cleanup-db.service": {"name": "initrd-udevadm-cleanup-db.service", "source": "systemd", "state": "inactive", "status": "static"}, "kmod-static-nodes.service": {"name": "kmod-static-nodes.service", "source": "systemd", "state": "stopped", "status": "static"}, "kmod.service": {"name": "kmod.service", "source": "systemd", "state": "active", "status": "static"}, "modprobe@.service": {"name": "modprobe@.service", "source": "systemd", "state": "unknown", "status": "static"}, "modprobe@chromeos_pstore.service": {"name": "modprobe@chromeos_pstore.service", "source": "systemd", "state": "stopped", "status": "inactive"}, "modprobe@drm.service": {"name": "modprobe@drm.service", "source": "systemd", "state": "stopped", "status": "inactive"}, "modprobe@efi_pstore.service": {"name": "modprobe@efi_pstore.service", "source": "systemd", "state": "stopped", "status": "inactive"}, "modprobe@pstore_blk.service": {"name": "modprobe@pstore_blk.service", "source": "systemd", "state": "stopped", "status": "inactive"}, "modprobe@pstore_zone.service": {"name": "modprobe@pstore_zone.service", "source": "systemd", "state": "stopped", "status": "inactive"}, "modprobe@ramoops.service": {"name": "modprobe@ramoops.service", "source": "systemd", "state": "stopped", "status": "inactive"}, "motd-news.service": {"name": "motd-news.service", "source": "systemd", "state": "stopped", "status": "static"}, "networkd-dispatcher.service": {"name": "networkd-dispatcher.service", "source": "systemd", "state": "running", "status": "enabled"}, "ondemand.service": {"name": "ondemand.service", "source": "systemd", "state": "stopped", "status": "enabled"}, "plymouth-quit-wait.service": {"name": "plymouth-quit-wait.service", "source": "systemd", "state": "stopped", "status": "not-found"}, "plymouth-start.service": {"name": "plymouth-start.service", "source": "systemd", "state": "stopped", "status": "not-found"}, "procps": {"name": "procps", "source": "sysv", "state": "running"}, "procps.service": {"name": "procps.service", "source": "systemd", "state": "active", "status": "static"}, "quotaon.service": {"name": "quotaon.service", "source": "systemd", "state": "inactive", "status": "static"}, "rc-local.service": {"name": "rc-local.service", "source": "systemd", "state": "stopped", "status": "static"}, "rc.service": {"name": "rc.service", "source": "systemd", "state": "inactive", "status": "masked"}, "rcS.service": {"name": "rcS.service", "source": "systemd", "state": "inactive", "status": "masked"}, "rescue.service": {"name": "rescue.service", "source": "systemd", "state": "stopped", "status": "static"}, "serial-getty@.service": {"name": "serial-getty@.service", "source": "systemd", "state": "unknown", "status": "indirect"}, "serial-getty@ttyS0.service": {"name": "serial-getty@ttyS0.service", "source": "systemd", "state": "stopped", "status": "inactive"}, "ssh": {"name": "ssh", "source": "sysv", "state": "running"}, "ssh.service": {"name": "ssh.service", "source": "systemd", "state": "running", "status": "enabled"}, "ssh@.service": {"name": "ssh@.service", "source": "systemd", "state": "unknown", "status": "static"}, "sshd.service": {"name": "sshd.service", "source": "systemd", "state": "active", "status": "enabled"}, "sudo.service": {"name": "sudo.service", "source": "systemd", "state": "inactive", "status": "masked"}, "syslog.service": {"name": "syslog.service", "source": "systemd", "state": "stopped", "status": "not-found"}, "system-update-cleanup.service": {"name": "system-update-cleanup.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-ask-password-console.service": {"name": "systemd-ask-password-console.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-ask-password-wall.service": {"name": "systemd-ask-password-wall.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-backlight@.service": {"name": "systemd-backlight@.service", "source": "systemd", "state": "unknown", "status": "static"}, "systemd-binfmt.service": {"name": "systemd-binfmt.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-bless-boot.service": {"name": "systemd-bless-boot.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-boot-check-no-failures.service": {"name": "systemd-boot-check-no-failures.service", "source": "systemd", "state": "inactive", "status": "disabled"}, "systemd-boot-system-token.service": {"name": "systemd-boot-system-token.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-exit.service": {"name": "systemd-exit.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-fsck-root.service": {"name": "systemd-fsck-root.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-fsck@.service": {"name": "systemd-fsck@.service", "source": "systemd", "state": "unknown", "status": "static"}, "systemd-fsckd.service": {"name": "systemd-fsckd.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-halt.service": {"name": "systemd-halt.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-hibernate-resume@.service": {"name": "systemd-hibernate-resume@.service", "source": "systemd", "state": "unknown", "status": "static"}, "systemd-hibernate.service": {"name": "systemd-hibernate.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-hostnamed.service": {"name": "systemd-hostnamed.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-hybrid-sleep.service": {"name": "systemd-hybrid-sleep.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-initctl.service": {"name": "systemd-initctl.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-journal-flush.service": {"name": "systemd-journal-flush.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-journald.service": {"name": "systemd-journald.service", "source": "systemd", "state": "running", "status": "static"}, "systemd-journald@.service": {"name": "systemd-journald@.service", "source": "systemd", "state": "unknown", "status": "static"}, "systemd-kexec.service": {"name": "systemd-kexec.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-localed.service": {"name": "systemd-localed.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-logind.service": {"name": "systemd-logind.service", "source": "systemd", "state": "running", "status": "static"}, "systemd-machine-id-commit.service": {"name": "systemd-machine-id-commit.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-modules-load.service": {"name": "systemd-modules-load.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-network-generator.service": {"name": "systemd-network-generator.service", "source": "systemd", "state": "inactive", "status": "disabled"}, "systemd-networkd-wait-online.service": {"name": "systemd-networkd-wait-online.service", "source": "systemd", "state": "inactive", "status": "disabled"}, "systemd-networkd.service": {"name": "systemd-networkd.service", "source": "systemd", "state": "stopped", "status": "disabled"}, "systemd-poweroff.service": {"name": "systemd-poweroff.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-pstore.service": {"name": "systemd-pstore.service", "source": "systemd", "state": "stopped", "status": "enabled"}, "systemd-quotacheck.service": {"name": "systemd-quotacheck.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-random-seed.service": {"name": "systemd-random-seed.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-reboot.service": {"name": "systemd-reboot.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-remount-fs.service": {"name": "systemd-remount-fs.service", "source": "systemd", "state": "stopped", "status": "enabled-runtime"}, "systemd-resolved.service": {"name": "systemd-resolved.service", "source": "systemd", "state": "running", "status": "enabled"}, "systemd-rfkill.service": {"name": "systemd-rfkill.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-suspend-then-hibernate.service": {"name": "systemd-suspend-then-hibernate.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-suspend.service": {"name": "systemd-suspend.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-sysctl.service": {"name": "systemd-sysctl.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-sysusers.service": {"name": "systemd-sysusers.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-time-wait-sync.service": {"name": "systemd-time-wait-sync.service", "source": "systemd", "state": "inactive", "status": "disabled"}, "systemd-timedated.service": {"name": "systemd-timedated.service", "source": "systemd", "state": "inactive", "status": "static"}, "systemd-timesyncd.service": {"name": "systemd-timesyncd.service", "source": "systemd", "state": "running", "status": "enabled"}, "systemd-tmpfiles-clean.service": {"name": "systemd-tmpfiles-clean.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-tmpfiles-setup-dev.service": {"name": "systemd-tmpfiles-setup-dev.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-tmpfiles-setup.service": {"name": "systemd-tmpfiles-setup.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-udevd.service": {"name": "systemd-udevd.service", "source": "systemd", "state": "stopped", "status": "masked"}, "systemd-update-done.service": {"name": "systemd-update-done.service", "source": "systemd", "state": "stopped", "status": "not-found"}, "systemd-update-utmp-runlevel.service": {"name": "systemd-update-utmp-runlevel.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-update-utmp.service": {"name": "systemd-update-utmp.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-user-sessions.service": {"name": "systemd-user-sessions.service", "source": "systemd", "state": "stopped", "status": "static"}, "systemd-vconsole-setup.service": {"name": "systemd-vconsole-setup.service", "source": "systemd", "state": "stopped", "status": "not-found"}, "systemd-volatile-root.service": {"name": "systemd-volatile-root.service", "source": "systemd", "state": "inactive", "status": "static"}, "udev.service": {"name": "udev.service", "source": "systemd", "state": "inactive", "status": "masked"}, "user-runtime-dir@.service": {"name": "user-runtime-dir@.service", "source": "systemd", "state": "unknown", "status": "static"}, "user-runtime-dir@0.service": {"name": "user-runtime-dir@0.service", "source": "systemd", "state": "stopped", "status": "active"}, "user@.service": {"name": "user@.service", "source": "systemd", "state": "unknown", "status": "static"}, "user@0.service": {"name": "user@0.service", "source": "systemd", "state": "running", "status": "active"}, "x11-common": {"name": "x11-common", "source": "sysv", "state": "stopped"}, "x11-common.service": {"name": "x11-common.service", "source": "systemd", "state": "inactive", "status": "masked"}}}, "changed": false}

TASK [confluent.platform.common : Stop Service before Removing Confluent Packages] ***
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "ansible_facts.services[service_name + '.service'] is defined", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Remove Confluent Packages - Red Hat] *********
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "ansible_os_family == \"RedHat\"", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.common : Remove Confluent Packages - Debian] **********
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "confluent_packages_removed|length > 0", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : Install the Kafka Controller Packages] ***
skipping: [kafka-controller-1] => (item=confluent-common)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-common", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-ce-kafka-http-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-ce-kafka-http-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-server-rest)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server-rest", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-telemetry)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-telemetry", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-rebalancer)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-rebalancer", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-security)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-security", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-common)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-common", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-2] => (item=confluent-ce-kafka-http-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-ce-kafka-http-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-server-rest)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server-rest", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-telemetry)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-telemetry", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-rebalancer)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-rebalancer", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-security)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-security", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-common)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-common", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-ce-kafka-http-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-ce-kafka-http-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-server-rest)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server-rest", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-telemetry)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-telemetry", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3] => (item=confluent-rebalancer)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-rebalancer", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-security)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-security", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3-migrated] => (item=confluent-common)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ansible_os_family == \"RedHat\"", "item": "confluent-common", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => (item=confluent-ce-kafka-http-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ansible_os_family == \"RedHat\"", "item": "confluent-ce-kafka-http-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => (item=confluent-server-rest)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ansible_os_family == \"RedHat\"", "item": "confluent-server-rest", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => (item=confluent-telemetry)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ansible_os_family == \"RedHat\"", "item": "confluent-telemetry", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => (item=confluent-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ansible_os_family == \"RedHat\"", "item": "confluent-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => (item=confluent-rebalancer)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ansible_os_family == \"RedHat\"", "item": "confluent-rebalancer", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-common)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-common", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => (item=confluent-security)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "ansible_os_family == \"RedHat\"", "item": "confluent-security", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-broker-1] => (item=confluent-ce-kafka-http-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-ce-kafka-http-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-server-rest)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server-rest", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-telemetry)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-telemetry", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-rebalancer)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-rebalancer", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-security)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-security", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.kafka_controller : Install the Kafka Controller Packages] ***
skipping: [kafka-controller-1] => (item=confluent-common)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-common", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-ce-kafka-http-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-ce-kafka-http-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-server-rest)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server-rest", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-telemetry)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-telemetry", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-rebalancer)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-rebalancer", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=confluent-security)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-security", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-common)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-common", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-ce-kafka-http-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-ce-kafka-http-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-server-rest)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server-rest", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-telemetry)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-telemetry", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-rebalancer)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-rebalancer", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=confluent-security)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-security", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3] => (item=confluent-common)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-common", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-ce-kafka-http-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-ce-kafka-http-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-server-rest)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server-rest", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3] => (item=confluent-telemetry)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-telemetry", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-rebalancer)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-rebalancer", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=confluent-security)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-security", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-broker-1] => (item=confluent-common)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-common", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-ce-kafka-http-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-ce-kafka-http-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-server-rest)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server-rest", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-telemetry)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-telemetry", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-server)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-server", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-rebalancer)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-rebalancer", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=confluent-security)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "confluent-security", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "msg": "All items skipped"}
changed: [kafka-controller-3-migrated] => (item=confluent-common) => {"ansible_loop_var": "item", "attempts": 1, "cache_update_time": 1729175360, "cache_updated": false, "changed": true, "item": "confluent-common", "stderr": "debconf: delaying package configuration, since apt-utils is not installed\n", "stderr_lines": ["debconf: delaying package configuration, since apt-utils is not installed"], "stdout": "Reading package lists...\nBuilding dependency tree...\nReading state information...\nThe following additional packages will be installed:\n  confluent-kafka-rest confluent-metadata-service confluent-rest-utils\nThe following NEW packages will be installed:\n  confluent-ce-kafka-http-server confluent-common confluent-kafka-rest\n  confluent-metadata-service confluent-rebalancer confluent-rest-utils\n  confluent-security confluent-server confluent-server-rest\n  confluent-telemetry\n0 upgraded, 10 newly installed, 0 to remove and 0 not upgraded.\nNeed to get 982 MB of archives.\nAfter this operation, 1080 MB of additional disk space will be used.\nGet:1 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-common all 7.6.0-1 [124 kB]\nGet:2 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-rest-utils all 7.6.3-1 [37.2 MB]\nGet:3 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-ce-kafka-http-server all 7.6.0-1 [39.0 MB]\nGet:4 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-kafka-rest all 7.6.3-1 [58.3 MB]\nGet:5 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-metadata-service all 7.6.3-1 [60.5 MB]\nGet:6 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-telemetry all 7.6.0-1 [15.9 MB]\nGet:7 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-rebalancer all 7.6.0-1 [102 MB]\nGet:8 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-security all 7.6.0-1 [452 MB]\nGet:9 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-server-rest all 7.6.0-1 [16.3 MB]\nGet:10 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-server all 7.6.0-1 [200 MB]\nFetched 982 MB in 12s (81.0 MB/s)\nSelecting previously unselected package confluent-common.\r\n(Reading database ... \r(Reading database ... 5%\r(Reading database ... 10%\r(Reading database ... 15%\r(Reading database ... 20%\r(Reading database ... 25%\r(Reading database ... 30%\r(Reading database ... 35%\r(Reading database ... 40%\r(Reading database ... 45%\r(Reading database ... 50%\r(Reading database ... 55%\r(Reading database ... 60%\r(Reading database ... 65%\r(Reading database ... 70%\r(Reading database ... 75%\r(Reading database ... 80%\r(Reading database ... 85%\r(Reading database ... 90%\r(Reading database ... 95%\r(Reading database ... 100%\r(Reading database ... 39070 files and directories currently installed.)\r\nPreparing to unpack .../0-confluent-common_7.6.0-1_all.deb ...\r\nUnpacking confluent-common (7.6.0-1) ...\r\nSelecting previously unselected package confluent-rest-utils.\r\nPreparing to unpack .../1-confluent-rest-utils_7.6.3-1_all.deb ...\r\nUnpacking confluent-rest-utils (7.6.3-1) ...\r\nSelecting previously unselected package confluent-ce-kafka-http-server.\r\nPreparing to unpack .../2-confluent-ce-kafka-http-server_7.6.0-1_all.deb ...\r\nUnpacking confluent-ce-kafka-http-server (7.6.0-1) ...\r\nSelecting previously unselected package confluent-kafka-rest.\r\nPreparing to unpack .../3-confluent-kafka-rest_7.6.3-1_all.deb ...\r\nUnpacking confluent-kafka-rest (7.6.3-1) ...\r\nSelecting previously unselected package confluent-metadata-service.\r\nPreparing to unpack .../4-confluent-metadata-service_7.6.3-1_all.deb ...\r\nUnpacking confluent-metadata-service (7.6.3-1) ...\r\nSelecting previously unselected package confluent-telemetry.\r\nPreparing to unpack .../5-confluent-telemetry_7.6.0-1_all.deb ...\r\nUnpacking confluent-telemetry (7.6.0-1) ...\r\nSelecting previously unselected package confluent-rebalancer.\r\nPreparing to unpack .../6-confluent-rebalancer_7.6.0-1_all.deb ...\r\nUnpacking confluent-rebalancer (7.6.0-1) ...\r\nSelecting previously unselected package confluent-security.\r\nPreparing to unpack .../7-confluent-security_7.6.0-1_all.deb ...\r\nUnpacking confluent-security (7.6.0-1) ...\r\nSelecting previously unselected package confluent-server-rest.\r\nPreparing to unpack .../8-confluent-server-rest_7.6.0-1_all.deb ...\r\nUnpacking confluent-server-rest (7.6.0-1) ...\r\nSelecting previously unselected package confluent-server.\r\nPreparing to unpack .../9-confluent-server_7.6.0-1_all.deb ...\r\nUnpacking confluent-server (7.6.0-1) ...\r\nSetting up confluent-common (7.6.0-1) ...\r\nSetting up confluent-telemetry (7.6.0-1) ...\r\nSetting up confluent-rest-utils (7.6.3-1) ...\r\nSetting up confluent-rebalancer (7.6.0-1) ...\r\nSetting up confluent-metadata-service (7.6.3-1) ...\r\nCreating directory /var/lib/confluent/metadata-service with owner cp-metadata-service:confluent\r\nCreating directory /var/log/confluent with owner cp-metadata-service:confluent\r\nCreating directory /var/log/confluent/metadata-service with owner cp-metadata-service:confluent\r\nSetting up confluent-kafka-rest (7.6.3-1) ...\r\nNotice: Not creating existing directory /var/log/confluent, ensure proper permissions for user cp-kafka-rest group confluent\r\nNotice: If you are planning to use the provided systemd service units for\r\nNotice: confluent-kafka-rest, make sure that read-write permissions\r\nNotice: for user cp-kafka-rest and group confluent are set up according to the\r\nNotice: following commands:\r\nchown cp-kafka-rest:confluent /var/log/confluent && chmod u+wx,g+wx,o= /var/log/confluent\r\n\r\nSetting up confluent-security (7.6.0-1) ...\r\nSetting up confluent-ce-kafka-http-server (7.6.0-1) ...\r\nCreating directory /var/lib/confluent/ce-kafka-http-server with owner cp-ce-kafka-http-server:confluent\r\nNotice: Not creating existing directory /var/log/confluent, ensure proper permissions for user cp-ce-kafka-http-server group confluent\r\nCreating directory /var/log/confluent/ce-kafka-http-server with owner cp-ce-kafka-http-server:confluent\r\nNotice: If you are planning to use the provided systemd service units for\r\nNotice: ce-kafka-http-server, make sure that read-write permissions\r\nNotice: for user cp-ce-kafka-http-server and group confluent are set up according to the\r\nNotice: following commands:\r\nchown cp-ce-kafka-http-server:confluent /var/log/confluent && chmod u+wx,g+wx,o= /var/log/confluent\r\n\r\nSetting up confluent-server-rest (7.6.0-1) ...\r\nCreating directory /var/lib/confluent/ce-kafka-rest with owner cp-ce-kafka-rest:confluent\r\nNotice: Not creating existing directory /var/log/confluent, ensure proper permissions for user cp-ce-kafka-rest group confluent\r\nCreating directory /var/log/confluent/ce-kafka-rest with owner cp-ce-kafka-rest:confluent\r\nNotice: If you are planning to use the provided systemd service units for\r\nNotice: ce-kafka-rest, make sure that read-write permissions\r\nNotice: for user cp-ce-kafka-rest and group confluent are set up according to the\r\nNotice: following commands:\r\nchown cp-ce-kafka-rest:confluent /var/log/confluent && chmod u+wx,g+wx,o= /var/log/confluent\r\n\r\nSetting up confluent-server (7.6.0-1) ...\r\nCreating directory /var/log/kafka with owner cp-kafka:confluent\r\nNotice: Not creating existing directory /var/log/confluent, ensure proper permissions for user cp-kafka group confluent\r\nCreating directory /var/lib/kafka with owner cp-kafka:confluent\r\nCreating directory /var/lib/zookeeper with owner cp-kafka:confluent\r\nNotice: If you are planning to use the provided systemd service units for\r\nNotice: Kafka, ZooKeeper or Connect, make sure that read-write permissions\r\nNotice: for user cp-kafka and group confluent are set up according to the\r\nNotice: following commands:\r\nchown cp-kafka:confluent /var/log/confluent && chmod u+wx,g+wx,o= /var/log/confluent\r\n\r\n", "stdout_lines": ["Reading package lists...", "Building dependency tree...", "Reading state information...", "The following additional packages will be installed:", "  confluent-kafka-rest confluent-metadata-service confluent-rest-utils", "The following NEW packages will be installed:", "  confluent-ce-kafka-http-server confluent-common confluent-kafka-rest", "  confluent-metadata-service confluent-rebalancer confluent-rest-utils", "  confluent-security confluent-server confluent-server-rest", "  confluent-telemetry", "0 upgraded, 10 newly installed, 0 to remove and 0 not upgraded.", "Need to get 982 MB of archives.", "After this operation, 1080 MB of additional disk space will be used.", "Get:1 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-common all 7.6.0-1 [124 kB]", "Get:2 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-rest-utils all 7.6.3-1 [37.2 MB]", "Get:3 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-ce-kafka-http-server all 7.6.0-1 [39.0 MB]", "Get:4 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-kafka-rest all 7.6.3-1 [58.3 MB]", "Get:5 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-metadata-service all 7.6.3-1 [60.5 MB]", "Get:6 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-telemetry all 7.6.0-1 [15.9 MB]", "Get:7 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-rebalancer all 7.6.0-1 [102 MB]", "Get:8 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-security all 7.6.0-1 [452 MB]", "Get:9 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-server-rest all 7.6.0-1 [16.3 MB]", "Get:10 https://packages.confluent.io/deb/7.6 stable/main amd64 confluent-server all 7.6.0-1 [200 MB]", "Fetched 982 MB in 12s (81.0 MB/s)", "Selecting previously unselected package confluent-common.", "(Reading database ... ", "(Reading database ... 5%", "(Reading database ... 10%", "(Reading database ... 15%", "(Reading database ... 20%", "(Reading database ... 25%", "(Reading database ... 30%", "(Reading database ... 35%", "(Reading database ... 40%", "(Reading database ... 45%", "(Reading database ... 50%", "(Reading database ... 55%", "(Reading database ... 60%", "(Reading database ... 65%", "(Reading database ... 70%", "(Reading database ... 75%", "(Reading database ... 80%", "(Reading database ... 85%", "(Reading database ... 90%", "(Reading database ... 95%", "(Reading database ... 100%", "(Reading database ... 39070 files and directories currently installed.)", "Preparing to unpack .../0-confluent-common_7.6.0-1_all.deb ...", "Unpacking confluent-common (7.6.0-1) ...", "Selecting previously unselected package confluent-rest-utils.", "Preparing to unpack .../1-confluent-rest-utils_7.6.3-1_all.deb ...", "Unpacking confluent-rest-utils (7.6.3-1) ...", "Selecting previously unselected package confluent-ce-kafka-http-server.", "Preparing to unpack .../2-confluent-ce-kafka-http-server_7.6.0-1_all.deb ...", "Unpacking confluent-ce-kafka-http-server (7.6.0-1) ...", "Selecting previously unselected package confluent-kafka-rest.", "Preparing to unpack .../3-confluent-kafka-rest_7.6.3-1_all.deb ...", "Unpacking confluent-kafka-rest (7.6.3-1) ...", "Selecting previously unselected package confluent-metadata-service.", "Preparing to unpack .../4-confluent-metadata-service_7.6.3-1_all.deb ...", "Unpacking confluent-metadata-service (7.6.3-1) ...", "Selecting previously unselected package confluent-telemetry.", "Preparing to unpack .../5-confluent-telemetry_7.6.0-1_all.deb ...", "Unpacking confluent-telemetry (7.6.0-1) ...", "Selecting previously unselected package confluent-rebalancer.", "Preparing to unpack .../6-confluent-rebalancer_7.6.0-1_all.deb ...", "Unpacking confluent-rebalancer (7.6.0-1) ...", "Selecting previously unselected package confluent-security.", "Preparing to unpack .../7-confluent-security_7.6.0-1_all.deb ...", "Unpacking confluent-security (7.6.0-1) ...", "Selecting previously unselected package confluent-server-rest.", "Preparing to unpack .../8-confluent-server-rest_7.6.0-1_all.deb ...", "Unpacking confluent-server-rest (7.6.0-1) ...", "Selecting previously unselected package confluent-server.", "Preparing to unpack .../9-confluent-server_7.6.0-1_all.deb ...", "Unpacking confluent-server (7.6.0-1) ...", "Setting up confluent-common (7.6.0-1) ...", "Setting up confluent-telemetry (7.6.0-1) ...", "Setting up confluent-rest-utils (7.6.3-1) ...", "Setting up confluent-rebalancer (7.6.0-1) ...", "Setting up confluent-metadata-service (7.6.3-1) ...", "Creating directory /var/lib/confluent/metadata-service with owner cp-metadata-service:confluent", "Creating directory /var/log/confluent with owner cp-metadata-service:confluent", "Creating directory /var/log/confluent/metadata-service with owner cp-metadata-service:confluent", "Setting up confluent-kafka-rest (7.6.3-1) ...", "Notice: Not creating existing directory /var/log/confluent, ensure proper permissions for user cp-kafka-rest group confluent", "Notice: If you are planning to use the provided systemd service units for", "Notice: confluent-kafka-rest, make sure that read-write permissions", "Notice: for user cp-kafka-rest and group confluent are set up according to the", "Notice: following commands:", "chown cp-kafka-rest:confluent /var/log/confluent && chmod u+wx,g+wx,o= /var/log/confluent", "", "Setting up confluent-security (7.6.0-1) ...", "Setting up confluent-ce-kafka-http-server (7.6.0-1) ...", "Creating directory /var/lib/confluent/ce-kafka-http-server with owner cp-ce-kafka-http-server:confluent", "Notice: Not creating existing directory /var/log/confluent, ensure proper permissions for user cp-ce-kafka-http-server group confluent", "Creating directory /var/log/confluent/ce-kafka-http-server with owner cp-ce-kafka-http-server:confluent", "Notice: If you are planning to use the provided systemd service units for", "Notice: ce-kafka-http-server, make sure that read-write permissions", "Notice: for user cp-ce-kafka-http-server and group confluent are set up according to the", "Notice: following commands:", "chown cp-ce-kafka-http-server:confluent /var/log/confluent && chmod u+wx,g+wx,o= /var/log/confluent", "", "Setting up confluent-server-rest (7.6.0-1) ...", "Creating directory /var/lib/confluent/ce-kafka-rest with owner cp-ce-kafka-rest:confluent", "Notice: Not creating existing directory /var/log/confluent, ensure proper permissions for user cp-ce-kafka-rest group confluent", "Creating directory /var/log/confluent/ce-kafka-rest with owner cp-ce-kafka-rest:confluent", "Notice: If you are planning to use the provided systemd service units for", "Notice: ce-kafka-rest, make sure that read-write permissions", "Notice: for user cp-ce-kafka-rest and group confluent are set up according to the", "Notice: following commands:", "chown cp-ce-kafka-rest:confluent /var/log/confluent && chmod u+wx,g+wx,o= /var/log/confluent", "", "Setting up confluent-server (7.6.0-1) ...", "Creating directory /var/log/kafka with owner cp-kafka:confluent", "Notice: Not creating existing directory /var/log/confluent, ensure proper permissions for user cp-kafka group confluent", "Creating directory /var/lib/kafka with owner cp-kafka:confluent", "Creating directory /var/lib/zookeeper with owner cp-kafka:confluent", "Notice: If you are planning to use the provided systemd service units for", "Notice: Kafka, ZooKeeper or Connect, make sure that read-write permissions", "Notice: for user cp-kafka and group confluent are set up according to the", "Notice: following commands:", "chown cp-kafka:confluent /var/log/confluent && chmod u+wx,g+wx,o= /var/log/confluent", ""]}
ok: [kafka-controller-3-migrated] => (item=confluent-ce-kafka-http-server) => {"ansible_loop_var": "item", "attempts": 1, "cache_update_time": 1729175360, "cache_updated": false, "changed": false, "item": "confluent-ce-kafka-http-server"}
ok: [kafka-controller-3-migrated] => (item=confluent-server-rest) => {"ansible_loop_var": "item", "attempts": 1, "cache_update_time": 1729175360, "cache_updated": false, "changed": false, "item": "confluent-server-rest"}
ok: [kafka-controller-3-migrated] => (item=confluent-telemetry) => {"ansible_loop_var": "item", "attempts": 1, "cache_update_time": 1729175360, "cache_updated": false, "changed": false, "item": "confluent-telemetry"}
ok: [kafka-controller-3-migrated] => (item=confluent-server) => {"ansible_loop_var": "item", "attempts": 1, "cache_update_time": 1729175360, "cache_updated": false, "changed": false, "item": "confluent-server"}
ok: [kafka-controller-3-migrated] => (item=confluent-rebalancer) => {"ansible_loop_var": "item", "attempts": 1, "cache_update_time": 1729175360, "cache_updated": false, "changed": false, "item": "confluent-rebalancer"}
ok: [kafka-controller-3-migrated] => (item=confluent-security) => {"ansible_loop_var": "item", "attempts": 1, "cache_update_time": 1729175360, "cache_updated": false, "changed": false, "item": "confluent-security"}

TASK [confluent.platform.kafka_controller : Kafka Controller group] ************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
ok: [kafka-controller-3-migrated] => {"changed": false, "gid": 107, "name": "confluent", "state": "present", "system": false}

TASK [confluent.platform.kafka_controller : Check if Kafka Controller User Exists] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"getent_passwd": {"cp-kafka": ["x", "110", "107", "", "/var/run/kafka", "/usr/sbin/nologin"]}}, "changed": false, "failed_when_result": false}

TASK [confluent.platform.kafka_controller : Create Kafka Controller user] ******
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "(getent_passwd|default({}))[kafka_controller_user] is not defined", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : Copy Kafka broker's Service to Create kafka Controller's service] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "checksum": "157e7e63c9889fdc07900ab5e28fb7bda4aeba97", "dest": "/lib/systemd/system/confluent-kcontroller.service", "gid": 0, "group": "root", "md5sum": "a988e0bcdc1f25a78cf30bdf5012c15c", "mode": "0644", "owner": "root", "size": 337, "src": "/lib/systemd/system/confluent-server.service", "state": "file", "uid": 0}

TASK [include_role : ssl] ******************************************************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "kafka_controller_listeners | confluent.platform.ssl_required(kafka_controller_ssl_enabled) or mds_broker_listener.ssl_enabled|bool or mds_tls_enabled|bool\n", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : include_tasks] *********************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "rbac_enabled|bool", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [Configure Kerberos] ******************************************************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "'GSSAPI' in kafka_controller_sasl_enabled_mechanisms or mds_broker_listener.sasl_protocol =='kerberos' or ( kraft_migration|bool and zookeeper_client_authentication_type == 'kerberos' )", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [Copy Custom Kafka Files] *************************************************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "kafka_controller_copy_files | length > 0", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : Set Permissions on /var/lib/controller] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "gid": 107, "group": "confluent", "mode": "0750", "owner": "cp-kafka", "path": "/var/lib/controller/", "size": 4096, "state": "directory", "uid": 110}

TASK [confluent.platform.kafka_controller : Set Permissions on Data Dirs] ******
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "gid": 107, "group": "confluent", "mode": "0750", "owner": "cp-kafka", "path": "/var/lib/controller/data", "size": 4096, "state": "directory", "uid": 110}

TASK [confluent.platform.kafka_controller : Set Permissions on Data Dir files] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
ok: [kafka-controller-3-migrated] => {"changed": false, "cmd": ["chown", "-R", "cp-kafka:confluent", "/var/lib/controller/data"], "delta": "0:00:00.004008", "end": "2024-10-17 16:32:13.962393", "msg": "", "rc": 0, "start": "2024-10-17 16:32:13.958385", "stderr": "", "stderr_lines": [], "stdout": "", "stdout_lines": []}

TASK [confluent.platform.kafka_controller : Create Kafka Controller Config directory] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "gid": 107, "group": "confluent", "mode": "0750", "owner": "cp-kafka", "path": "/etc/controller", "size": 4096, "state": "directory", "uid": 110}

TASK [confluent.platform.kafka_controller : Create Kafka Controller Config] ****
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "checksum": "98278be405f6290914c0685676565a3888506f50", "dest": "/etc/controller/server.properties", "gid": 107, "group": "confluent", "md5sum": "cda2cfe252b01257cec8ca065f46da44", "mode": "0640", "owner": "cp-kafka", "size": 1492, "src": "/root/.ansible/tmp/ansible-tmp-1729175534.497828-433676-217596846283310/.source.properties", "state": "file", "uid": 110}

TASK [confluent.platform.kafka_controller : Create Kafka Controller Client Config] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "checksum": "4b7d247adde0942f626638b0e5f5989fd330bf19", "dest": "/etc/controller/client.properties", "gid": 107, "group": "confluent", "md5sum": "03a40b3e98373013ef01fe0223cfbadd", "mode": "0640", "owner": "cp-kafka", "size": 239, "src": "/root/.ansible/tmp/ansible-tmp-1729175535.6125765-433727-144670964231267/.source.properties", "state": "file", "uid": 110}

TASK [confluent.platform.kafka_controller : Include Kraft Cluster Data] ********
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_controller/tasks/get_meta_properties.yml for kafka-controller-3-migrated

TASK [confluent.platform.kafka_controller : Check if Data Directories are Formatted] ***
changed: [kafka-controller-3-migrated] => {"changed": true, "cmd": "/usr/bin/kafka-storage info -c /etc/controller/server.properties", "delta": "0:00:01.913117", "end": "2024-10-17 16:32:18.541548", "failed_when_result": false, "msg": "non-zero return code", "rc": 1, "start": "2024-10-17 16:32:16.628431", "stderr": "", "stderr_lines": [], "stdout": "Found log directory:\n  /var/lib/controller/data\n\nFound problem:\n  /var/lib/controller/data is not formatted.", "stdout_lines": ["Found log directory:", "  /var/lib/controller/data", "", "Found problem:", "  /var/lib/controller/data is not formatted."]}

TASK [confluent.platform.kafka_controller : Generate Cluster ID for New Clusters] ***
changed: [kafka-controller-3-migrated] => {"changed": true, "cmd": "/usr/bin/kafka-storage random-uuid", "delta": "0:00:01.149893", "end": "2024-10-17 16:32:20.016989", "msg": "", "rc": 0, "start": "2024-10-17 16:32:18.867096", "stderr": "", "stderr_lines": [], "stdout": "pu_iMmrJQCSMcHIJQ7KghQ", "stdout_lines": ["pu_iMmrJQCSMcHIJQ7KghQ"]}

TASK [confluent.platform.kafka_controller : Output Debug Message - Overridden Cluster ID Task] ***
ok: [kafka-controller-3-migrated] => {
    "msg": "Using overridden kafka_cluster_id: gKP1yNTvTvqf4ICEYzpYsg"
}

TASK [confluent.platform.kafka_controller : Extract ClusterId from meta.properties on ZK Broker] ***
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "kraft_migration | bool and formatted.rc == 1", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : Set ClusterId Variable (for use in Formatting)] ***
ok: [kafka-controller-3-migrated] => {"ansible_facts": {"clusterid": "gKP1yNTvTvqf4ICEYzpYsg"}, "changed": false}

TASK [confluent.platform.kafka_controller : Format Data Directory] *************
changed: [kafka-controller-3-migrated] => {"changed": true, "cmd": "/usr/bin/kafka-storage format -t=gKP1yNTvTvqf4ICEYzpYsg -c /etc/controller/server.properties --ignore-formatted", "delta": "0:00:01.982856", "end": "2024-10-17 16:32:22.564701", "msg": "", "rc": 0, "start": "2024-10-17 16:32:20.581845", "stderr": "", "stderr_lines": [], "stdout": "Formatting /var/lib/controller/data with metadata version 3.6-IV2.", "stdout_lines": ["Formatting /var/lib/controller/data with metadata version 3.6-IV2."]}

TASK [confluent.platform.kafka_controller : Create Logs Directory] *************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "gid": 107, "group": "confluent", "mode": "0770", "owner": "cp-kafka", "path": "/var/log/controller", "size": 4096, "state": "directory", "uid": 110}

TASK [Update Kafka log4j Config for Log Cleanup] *******************************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
included: common for kafka-controller-3-migrated

TASK [confluent.platform.common : Replace rootLogger] **************************
ok: [kafka-controller-3-migrated] => {"changed": false, "msg": "", "rc": 0}

TASK [confluent.platform.common : Replace DailyRollingFileAppender with RollingFileAppender] ***
changed: [kafka-controller-3-migrated] => {"changed": true, "msg": "10 replacements made", "rc": 0}

TASK [confluent.platform.common : Remove Key log4j.appender.X.DatePattern] *****
changed: [kafka-controller-3-migrated] => {"backup": "", "changed": true, "found": 10, "msg": "10 line(s) removed"}

TASK [confluent.platform.common : Register Appenders] **************************
ok: [kafka-controller-3-migrated] => {"changed": false, "cmd": "grep RollingFileAppender /etc/kafka/log4j.properties | cut -d '=' -f 1 | cut -d '.' -f 3\n", "delta": "0:00:00.005363", "end": "2024-10-17 16:32:24.831589", "msg": "", "rc": 0, "start": "2024-10-17 16:32:24.826226", "stderr": "", "stderr_lines": [], "stdout": "kafkaAppender\nstateChangeAppender\nrequestAppender\ncleanerAppender\ncontrollerAppender\nauthorizerAppender\nmetadataServiceAppender\nauditLogAppender\ndataBalancerAppender\nzkAuditAppender", "stdout_lines": ["kafkaAppender", "stateChangeAppender", "requestAppender", "cleanerAppender", "controllerAppender", "authorizerAppender", "metadataServiceAppender", "auditLogAppender", "dataBalancerAppender", "zkAuditAppender"]}

TASK [confluent.platform.common : Add Max Size Properties] *********************
changed: [kafka-controller-3-migrated] => (item=['kafkaAppender', 'Append=true']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["kafkaAppender", "Append=true"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['kafkaAppender', 'MaxBackupIndex=10']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["kafkaAppender", "MaxBackupIndex=10"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['kafkaAppender', 'MaxFileSize=100MB']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["kafkaAppender", "MaxFileSize=100MB"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['stateChangeAppender', 'Append=true']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["stateChangeAppender", "Append=true"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['stateChangeAppender', 'MaxBackupIndex=10']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["stateChangeAppender", "MaxBackupIndex=10"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['stateChangeAppender', 'MaxFileSize=100MB']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["stateChangeAppender", "MaxFileSize=100MB"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['requestAppender', 'Append=true']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["requestAppender", "Append=true"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['requestAppender', 'MaxBackupIndex=10']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["requestAppender", "MaxBackupIndex=10"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['requestAppender', 'MaxFileSize=100MB']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["requestAppender", "MaxFileSize=100MB"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['cleanerAppender', 'Append=true']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["cleanerAppender", "Append=true"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['cleanerAppender', 'MaxBackupIndex=10']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["cleanerAppender", "MaxBackupIndex=10"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['cleanerAppender', 'MaxFileSize=100MB']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["cleanerAppender", "MaxFileSize=100MB"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['controllerAppender', 'Append=true']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["controllerAppender", "Append=true"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['controllerAppender', 'MaxBackupIndex=10']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["controllerAppender", "MaxBackupIndex=10"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['controllerAppender', 'MaxFileSize=100MB']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["controllerAppender", "MaxFileSize=100MB"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['authorizerAppender', 'Append=true']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["authorizerAppender", "Append=true"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['authorizerAppender', 'MaxBackupIndex=10']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["authorizerAppender", "MaxBackupIndex=10"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['authorizerAppender', 'MaxFileSize=100MB']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["authorizerAppender", "MaxFileSize=100MB"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['metadataServiceAppender', 'Append=true']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["metadataServiceAppender", "Append=true"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['metadataServiceAppender', 'MaxBackupIndex=10']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["metadataServiceAppender", "MaxBackupIndex=10"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['metadataServiceAppender', 'MaxFileSize=100MB']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["metadataServiceAppender", "MaxFileSize=100MB"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['auditLogAppender', 'Append=true']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["auditLogAppender", "Append=true"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['auditLogAppender', 'MaxBackupIndex=10']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["auditLogAppender", "MaxBackupIndex=10"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['auditLogAppender', 'MaxFileSize=100MB']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["auditLogAppender", "MaxFileSize=100MB"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['dataBalancerAppender', 'Append=true']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["dataBalancerAppender", "Append=true"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['dataBalancerAppender', 'MaxBackupIndex=10']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["dataBalancerAppender", "MaxBackupIndex=10"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['dataBalancerAppender', 'MaxFileSize=100MB']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["dataBalancerAppender", "MaxFileSize=100MB"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['zkAuditAppender', 'Append=true']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["zkAuditAppender", "Append=true"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['zkAuditAppender', 'MaxBackupIndex=10']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["zkAuditAppender", "MaxBackupIndex=10"], "msg": "line added"}
changed: [kafka-controller-3-migrated] => (item=['zkAuditAppender', 'MaxFileSize=100MB']) => {"ansible_loop_var": "item", "backup": "", "changed": true, "item": ["zkAuditAppender", "MaxFileSize=100MB"], "msg": "line added"}

TASK [confluent.platform.kafka_controller : Set Permissions on Log4j Conf] *****
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "gid": 107, "group": "confluent", "mode": "0640", "owner": "cp-kafka", "path": "/etc/kafka/log4j.properties", "size": 9770, "state": "file", "uid": 110}

TASK [confluent.platform.kafka_controller : Create logredactor rule file directory] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "(kafka_controller_custom_log4j|bool) and (logredactor_enabled|bool) and (logredactor_rule_url == '')", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : Copy logredactor rule file from control node to component node] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "(kafka_controller_custom_log4j|bool) and (logredactor_enabled|bool) and (logredactor_rule_url == '')", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [Configure logredactor] ***************************************************
skipping: [kafka-controller-1] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'kafkaAppender'})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"appenderRefs": "kafkaAppender", "logger_name": "log4j.rootLogger"}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-2] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'kafkaAppender'})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"appenderRefs": "kafkaAppender", "logger_name": "log4j.rootLogger"}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'kafkaAppender'})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"appenderRefs": "kafkaAppender", "logger_name": "log4j.rootLogger"}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3-migrated] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'kafkaAppender'})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "(kafka_controller_custom_log4j|bool) and (logredactor_enabled|bool)", "item": {"appenderRefs": "kafkaAppender", "logger_name": "log4j.rootLogger"}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-broker-1] => (item={'logger_name': 'log4j.rootLogger', 'appenderRefs': 'kafkaAppender'})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"appenderRefs": "kafkaAppender", "logger_name": "log4j.rootLogger"}, "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "msg": "All items skipped"}

TASK [confluent.platform.kafka_controller : Restart kafka Controller] **********
skipping: [kafka-controller-1] => {"false_condition": "inventory_hostname == 'kafka-controller-3-migrated'"}
skipping: [kafka-controller-2] => {"false_condition": "inventory_hostname == 'kafka-controller-3-migrated'"}
skipping: [kafka-controller-3] => {"false_condition": "inventory_hostname == 'kafka-controller-3-migrated'"}
skipping: [kafka-controller-3-migrated] => {"false_condition": "(kafka_controller_custom_log4j|bool) and (logredactor_enabled|bool) and (not kafka_controller_skip_restarts|bool)"}
skipping: [kafka-broker-1] => {"false_condition": "inventory_hostname == 'kafka-controller-3-migrated'"}

TASK [confluent.platform.kafka_controller : Create Kafka Controller Jolokia Config] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "kafka_controller_jolokia_enabled|bool", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : Create Kafka Controller Jaas Config] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "'GSSAPI' in kafka_controller_sasl_enabled_mechanisms or ( kraft_migration|bool and zookeeper_client_authentication_type in ['kerberos', 'digest'])", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : Deploy JMX Exporter Config File] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "kafka_controller_jmxexporter_enabled|bool", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : Create Service Override Directory] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "gid": 107, "group": "confluent", "mode": "0640", "owner": "cp-kafka", "path": "/etc/systemd/system/confluent-kcontroller.service.d", "size": 4096, "state": "directory", "uid": 110}

TASK [confluent.platform.kafka_controller : Write Service Overrides] ***********
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "checksum": "4f692e4d83428ed46e6949273e01a05518b0cc98", "dest": "/etc/systemd/system/confluent-kcontroller.service.d/override.conf", "gid": 0, "group": "root", "md5sum": "8541b9e49cd65ccf07ac84aabe2e4b6e", "mode": "0640", "owner": "root", "size": 531, "src": "/root/.ansible/tmp/ansible-tmp-1729175555.0751019-435077-96100848230970/.source.conf", "state": "file", "uid": 0}

TASK [confluent.platform.kafka_controller : Create sysctl directory on Debian distributions] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "ansible_distribution == \"Debian\"", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : Tune virtual memory settings] ******
skipping: [kafka-controller-1] => (item={'key': 'vm.swappiness', 'value': 1})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.swappiness", "value": 1}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item={'key': 'vm.dirty_background_ratio', 'value': 5})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.dirty_background_ratio", "value": 5}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item={'key': 'vm.dirty_ratio', 'value': 80})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.dirty_ratio", "value": 80}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item={'key': 'vm.max_map_count', 'value': 262144})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.max_map_count", "value": 262144}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item={'key': 'vm.swappiness', 'value': 1})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.swappiness", "value": 1}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item={'key': 'vm.dirty_background_ratio', 'value': 5})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.dirty_background_ratio", "value": 5}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-2] => (item={'key': 'vm.dirty_ratio', 'value': 80})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.dirty_ratio", "value": 80}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item={'key': 'vm.max_map_count', 'value': 262144})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.max_map_count", "value": 262144}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item={'key': 'vm.swappiness', 'value': 1})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.swappiness", "value": 1}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item={'key': 'vm.dirty_background_ratio', 'value': 5})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.dirty_background_ratio", "value": 5}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item={'key': 'vm.dirty_ratio', 'value': 80})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.dirty_ratio", "value": 80}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3] => (item={'key': 'vm.max_map_count', 'value': 262144})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.max_map_count", "value": 262144}, "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-broker-1] => (item={'key': 'vm.swappiness', 'value': 1})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.swappiness", "value": 1}, "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item={'key': 'vm.dirty_background_ratio', 'value': 5})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.dirty_background_ratio", "value": 5}, "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item={'key': 'vm.dirty_ratio', 'value': 80})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.dirty_ratio", "value": 80}, "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item={'key': 'vm.max_map_count', 'value': 262144})  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": {"key": "vm.max_map_count", "value": 262144}, "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "msg": "All items skipped"}
changed: [kafka-controller-3-migrated] => (item={'key': 'vm.swappiness', 'value': 1}) => {"ansible_loop_var": "item", "changed": true, "item": {"key": "vm.swappiness", "value": 1}}
changed: [kafka-controller-3-migrated] => (item={'key': 'vm.dirty_background_ratio', 'value': 5}) => {"ansible_loop_var": "item", "changed": true, "item": {"key": "vm.dirty_background_ratio", "value": 5}}
changed: [kafka-controller-3-migrated] => (item={'key': 'vm.dirty_ratio', 'value': 80}) => {"ansible_loop_var": "item", "changed": true, "item": {"key": "vm.dirty_ratio", "value": 80}}
changed: [kafka-controller-3-migrated] => (item={'key': 'vm.max_map_count', 'value': 262144}) => {"ansible_loop_var": "item", "changed": true, "item": {"key": "vm.max_map_count", "value": 262144}}

TASK [confluent.platform.kafka_controller : Certs were Updated - Trigger Restart] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "certs_updated|bool", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : meta] ******************************
skipping: [kafka-controller-1] => {"msg": "flush_handlers", "skip_reason": "flush_handlers conditional evaluated to False, not running handlers for kafka-controller-1"}

TASK [confluent.platform.kafka_controller : meta] ******************************
skipping: [kafka-controller-2] => {"msg": "flush_handlers", "skip_reason": "flush_handlers conditional evaluated to False, not running handlers for kafka-controller-2"}

TASK [confluent.platform.kafka_controller : meta] ******************************
skipping: [kafka-controller-3] => {"msg": "flush_handlers", "skip_reason": "flush_handlers conditional evaluated to False, not running handlers for kafka-controller-3"}

TASK [confluent.platform.kafka_controller : meta] ******************************

TASK [confluent.platform.kafka_controller : meta] ******************************
skipping: [kafka-broker-1] => {"msg": "flush_handlers", "skip_reason": "flush_handlers conditional evaluated to False, not running handlers for kafka-broker-1"}

RUNNING HANDLER [confluent.platform.kafka_controller : restart Kafka Controller] ***
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_controller/tasks/restart_and_wait.yml for kafka-controller-3-migrated

RUNNING HANDLER [confluent.platform.kafka_controller : Restart Kafka] **********
changed: [kafka-controller-3-migrated] => {"changed": true, "name": "confluent-kcontroller", "state": "started", "status": {"ActiveEnterTimestampMonotonic": "0", "ActiveExitTimestampMonotonic": "0", "ActiveState": "inactive", "After": "system.slice systemd-journald.socket sysinit.target network.target confluent-zookeeper.target basic.target", "AllowIsolate": "no", "AllowedCPUs": "", "AllowedMemoryNodes": "", "AmbientCapabilities": "", "AssertResult": "no", "AssertTimestampMonotonic": "0", "Before": "shutdown.target", "BlockIOAccounting": "no", "BlockIOWeight": "[not set]", "CPUAccounting": "no", "CPUAffinity": "", "CPUAffinityFromNUMA": "no", "CPUQuotaPerSecUSec": "infinity", "CPUQuotaPeriodUSec": "infinity", "CPUSchedulingPolicy": "0", "CPUSchedulingPriority": "0", "CPUSchedulingResetOnFork": "no", "CPUShares": "[not set]", "CPUUsageNSec": "[not set]", "CPUWeight": "[not set]", "CacheDirectoryMode": "0755", "CanIsolate": "no", "CanReload": "no", "CanStart": "yes", "CanStop": "yes", "CapabilityBoundingSet": "cap_chown cap_dac_override cap_dac_read_search cap_fowner cap_fsetid cap_kill cap_setgid cap_setuid cap_setpcap cap_linux_immutable cap_net_bind_service cap_net_broadcast cap_net_admin cap_net_raw cap_ipc_lock cap_ipc_owner cap_sys_module cap_sys_rawio cap_sys_chroot cap_sys_ptrace cap_sys_pacct cap_sys_admin cap_sys_boot cap_sys_nice cap_sys_resource cap_sys_time cap_sys_tty_config cap_mknod cap_lease cap_audit_write cap_audit_control cap_setfcap cap_mac_override cap_mac_admin cap_syslog cap_wake_alarm cap_block_suspend cap_audit_read 0x26 0x27 0x28", "CleanResult": "success", "CollectMode": "inactive", "ConditionResult": "no", "ConditionTimestampMonotonic": "0", "ConfigurationDirectoryMode": "0755", "Conflicts": "shutdown.target", "ControlPID": "0", "DefaultDependencies": "yes", "DefaultMemoryLow": "0", "DefaultMemoryMin": "0", "Delegate": "no", "Description": "Apache Kafka - broker", "DevicePolicy": "auto", "Documentation": "http://docs.confluent.io/", "DropInPaths": "/etc/systemd/system/confluent-kcontroller.service.d/override.conf", "DynamicUser": "no", "EffectiveCPUs": "", "EffectiveMemoryNodes": "", "Environment": "[unprintable] KAFKA_LOG4J_OPTS=-Dlog4j.configuration=file:/etc/kafka/log4j.properties LOG_DIR=/var/log/controller", "ExecMainCode": "0", "ExecMainExitTimestampMonotonic": "0", "ExecMainPID": "0", "ExecMainStartTimestampMonotonic": "0", "ExecMainStatus": "0", "ExecStart": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "ExecStartEx": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; flags= ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "FailureAction": "none", "FileDescriptorStoreMax": "0", "FinalKillSignal": "9", "FragmentPath": "/lib/systemd/system/confluent-kcontroller.service", "GID": "[not set]", "Group": "confluent", "GuessMainPID": "yes", "IOAccounting": "no", "IOReadBytes": "18446744073709551615", "IOReadOperations": "18446744073709551615", "IOSchedulingClass": "0", "IOSchedulingPriority": "0", "IOWeight": "[not set]", "IOWriteBytes": "18446744073709551615", "IOWriteOperations": "18446744073709551615", "IPAccounting": "no", "IPEgressBytes": "[no data]", "IPEgressPackets": "[no data]", "IPIngressBytes": "[no data]", "IPIngressPackets": "[no data]", "Id": "confluent-kcontroller.service", "IgnoreOnIsolate": "no", "IgnoreSIGPIPE": "yes", "InactiveEnterTimestampMonotonic": "0", "InactiveExitTimestampMonotonic": "0", "JobRunningTimeoutUSec": "infinity", "JobTimeoutAction": "none", "JobTimeoutUSec": "infinity", "KeyringMode": "private", "KillMode": "control-group", "KillSignal": "15", "LimitAS": "infinity", "LimitASSoft": "infinity", "LimitCORE": "infinity", "LimitCORESoft": "infinity", "LimitCPU": "infinity", "LimitCPUSoft": "infinity", "LimitDATA": "infinity", "LimitDATASoft": "infinity", "LimitFSIZE": "infinity", "LimitFSIZESoft": "infinity", "LimitLOCKS": "infinity", "LimitLOCKSSoft": "infinity", "LimitMEMLOCK": "8388608", "LimitMEMLOCKSoft": "8388608", "LimitMSGQUEUE": "819200", "LimitMSGQUEUESoft": "819200", "LimitNICE": "0", "LimitNICESoft": "0", "LimitNOFILE": "1000000", "LimitNOFILESoft": "1000000", "LimitNPROC": "infinity", "LimitNPROCSoft": "infinity", "LimitRSS": "infinity", "LimitRSSSoft": "infinity", "LimitRTPRIO": "0", "LimitRTPRIOSoft": "0", "LimitRTTIME": "infinity", "LimitRTTIMESoft": "infinity", "LimitSIGPENDING": "128316", "LimitSIGPENDINGSoft": "128316", "LimitSTACK": "infinity", "LimitSTACKSoft": "8388608", "LoadState": "loaded", "LockPersonality": "no", "LogLevelMax": "-1", "LogRateLimitBurst": "0", "LogRateLimitIntervalUSec": "0", "LogsDirectoryMode": "0755", "MainPID": "0", "MemoryAccounting": "yes", "MemoryCurrent": "[not set]", "MemoryDenyWriteExecute": "no", "MemoryHigh": "infinity", "MemoryLimit": "infinity", "MemoryLow": "0", "MemoryMax": "infinity", "MemoryMin": "0", "MemorySwapMax": "infinity", "MountAPIVFS": "no", "MountFlags": "", "NFileDescriptorStore": "0", "NRestarts": "0", "NUMAMask": "", "NUMAPolicy": "n/a", "Names": "confluent-kcontroller.service", "NeedDaemonReload": "no", "Nice": "0", "NoNewPrivileges": "no", "NonBlocking": "no", "NotifyAccess": "none", "OOMPolicy": "stop", "OOMScoreAdjust": "0", "OnFailureJobMode": "replace", "Perpetual": "no", "PrivateDevices": "no", "PrivateMounts": "no", "PrivateNetwork": "no", "PrivateTmp": "no", "PrivateUsers": "no", "ProtectControlGroups": "no", "ProtectHome": "no", "ProtectHostname": "no", "ProtectKernelLogs": "no", "ProtectKernelModules": "no", "ProtectKernelTunables": "no", "ProtectSystem": "no", "RefuseManualStart": "no", "RefuseManualStop": "no", "ReloadResult": "success", "RemainAfterExit": "no", "RemoveIPC": "no", "Requires": "sysinit.target system.slice", "Restart": "no", "RestartKillSignal": "15", "RestartUSec": "100ms", "RestrictNamespaces": "no", "RestrictRealtime": "no", "RestrictSUIDSGID": "no", "Result": "success", "RootDirectoryStartOnly": "no", "RuntimeDirectoryMode": "0755", "RuntimeDirectoryPreserve": "no", "RuntimeMaxUSec": "infinity", "SameProcessGroup": "no", "SecureBits": "0", "SendSIGHUP": "no", "SendSIGKILL": "yes", "Slice": "system.slice", "StandardError": "inherit", "StandardInput": "null", "StandardInputData": "", "StandardOutput": "journal", "StartLimitAction": "none", "StartLimitBurst": "5", "StartLimitIntervalUSec": "10s", "StartupBlockIOWeight": "[not set]", "StartupCPUShares": "[not set]", "StartupCPUWeight": "[not set]", "StartupIOWeight": "[not set]", "StateChangeTimestampMonotonic": "0", "StateDirectoryMode": "0755", "StatusErrno": "0", "StopWhenUnneeded": "no", "SubState": "dead", "SuccessAction": "none", "SyslogFacility": "3", "SyslogLevel": "6", "SyslogLevelPrefix": "yes", "SyslogPriority": "30", "SystemCallErrorNumber": "0", "TTYReset": "no", "TTYVHangup": "no", "TTYVTDisallocate": "no", "TasksAccounting": "yes", "TasksCurrent": "[not set]", "TasksMax": "38494", "TimeoutAbortUSec": "3min", "TimeoutCleanUSec": "infinity", "TimeoutStartUSec": "1min 30s", "TimeoutStopUSec": "3min", "TimerSlackNSec": "50000", "Transient": "no", "Type": "simple", "UID": "[not set]", "UMask": "0022", "UnitFilePreset": "enabled", "UnitFileState": "disabled", "User": "cp-kafka", "UtmpMode": "init", "WatchdogSignal": "6", "WatchdogTimestampMonotonic": "0", "WatchdogUSec": "0"}}

RUNNING HANDLER [confluent.platform.kafka_controller : Startup Delay] **********
ok: [kafka-controller-3-migrated] => {"changed": false, "elapsed": 20, "match_groupdict": {}, "match_groups": [], "path": null, "port": null, "search_regex": null, "state": "started"}

TASK [confluent.platform.kafka_controller : Encrypt secrets] *******************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "kafka_controller_secrets_protection_enabled|bool or kafka_controller_client_secrets_protection_enabled|bool", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}

TASK [confluent.platform.kafka_controller : meta] ******************************
skipping: [kafka-controller-1] => {"msg": "flush_handlers", "skip_reason": "flush_handlers conditional evaluated to False, not running handlers for kafka-controller-1"}

TASK [confluent.platform.kafka_controller : meta] ******************************
skipping: [kafka-controller-2] => {"msg": "flush_handlers", "skip_reason": "flush_handlers conditional evaluated to False, not running handlers for kafka-controller-2"}

TASK [confluent.platform.kafka_controller : meta] ******************************
skipping: [kafka-controller-3] => {"msg": "flush_handlers", "skip_reason": "flush_handlers conditional evaluated to False, not running handlers for kafka-controller-3"}

TASK [confluent.platform.kafka_controller : meta] ******************************

TASK [confluent.platform.kafka_controller : meta] ******************************
skipping: [kafka-broker-1] => {"msg": "flush_handlers", "skip_reason": "flush_handlers conditional evaluated to False, not running handlers for kafka-broker-1"}

TASK [confluent.platform.kafka_controller : Kafka Started] *********************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-3-migrated] => {"changed": true, "enabled": true, "name": "confluent-kcontroller", "state": "started", "status": {"ActiveEnterTimestamp": "Thu 2024-10-17 16:32:37 CEST", "ActiveEnterTimestampMonotonic": "28526172406", "ActiveExitTimestampMonotonic": "0", "ActiveState": "active", "After": "sysinit.target basic.target network.target confluent-zookeeper.target systemd-journald.socket system.slice", "AllowIsolate": "no", "AllowedCPUs": "", "AllowedMemoryNodes": "", "AmbientCapabilities": "", "AssertResult": "yes", "AssertTimestamp": "Thu 2024-10-17 16:32:37 CEST", "AssertTimestampMonotonic": "28526164205", "Before": "shutdown.target", "BlockIOAccounting": "no", "BlockIOWeight": "[not set]", "CPUAccounting": "no", "CPUAffinity": "", "CPUAffinityFromNUMA": "no", "CPUQuotaPerSecUSec": "infinity", "CPUQuotaPeriodUSec": "infinity", "CPUSchedulingPolicy": "0", "CPUSchedulingPriority": "0", "CPUSchedulingResetOnFork": "no", "CPUShares": "[not set]", "CPUUsageNSec": "[not set]", "CPUWeight": "[not set]", "CacheDirectoryMode": "0755", "CanIsolate": "no", "CanReload": "no", "CanStart": "yes", "CanStop": "yes", "CapabilityBoundingSet": "cap_chown cap_dac_override cap_dac_read_search cap_fowner cap_fsetid cap_kill cap_setgid cap_setuid cap_setpcap cap_linux_immutable cap_net_bind_service cap_net_broadcast cap_net_admin cap_net_raw cap_ipc_lock cap_ipc_owner cap_sys_module cap_sys_rawio cap_sys_chroot cap_sys_ptrace cap_sys_pacct cap_sys_admin cap_sys_boot cap_sys_nice cap_sys_resource cap_sys_time cap_sys_tty_config cap_mknod cap_lease cap_audit_write cap_audit_control cap_setfcap cap_mac_override cap_mac_admin cap_syslog cap_wake_alarm cap_block_suspend cap_audit_read 0x26 0x27 0x28", "CleanResult": "success", "CollectMode": "inactive", "ConditionResult": "yes", "ConditionTimestamp": "Thu 2024-10-17 16:32:37 CEST", "ConditionTimestampMonotonic": "28526164204", "ConfigurationDirectoryMode": "0755", "Conflicts": "shutdown.target", "ControlGroup": "/docker/cff3151f3d6ba2ef7d36d878b20495fef547788113839d123d3270a702ca6f68/system.slice/confluent-kcontroller.service", "ControlPID": "0", "DefaultDependencies": "yes", "DefaultMemoryLow": "0", "DefaultMemoryMin": "0", "Delegate": "no", "Description": "Apache Kafka - broker", "DevicePolicy": "auto", "Documentation": "http://docs.confluent.io/", "DropInPaths": "/etc/systemd/system/confluent-kcontroller.service.d/override.conf", "DynamicUser": "no", "EffectiveCPUs": "", "EffectiveMemoryNodes": "", "Environment": "[unprintable] KAFKA_LOG4J_OPTS=-Dlog4j.configuration=file:/etc/kafka/log4j.properties LOG_DIR=/var/log/controller", "ExecMainCode": "0", "ExecMainExitTimestampMonotonic": "0", "ExecMainPID": "6566", "ExecMainStartTimestamp": "Thu 2024-10-17 16:32:37 CEST", "ExecMainStartTimestampMonotonic": "28526172145", "ExecMainStatus": "0", "ExecStart": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; ignore_errors=no ; start_time=[Thu 2024-10-17 16:32:37 CEST] ; stop_time=[n/a] ; pid=6566 ; code=(null) ; status=0/0 }", "ExecStartEx": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; flags= ; start_time=[Thu 2024-10-17 16:32:37 CEST] ; stop_time=[n/a] ; pid=6566 ; code=(null) ; status=0/0 }", "FailureAction": "none", "FileDescriptorStoreMax": "0", "FinalKillSignal": "9", "FragmentPath": "/lib/systemd/system/confluent-kcontroller.service", "GID": "107", "Group": "confluent", "GuessMainPID": "yes", "IOAccounting": "no", "IOReadBytes": "18446744073709551615", "IOReadOperations": "18446744073709551615", "IOSchedulingClass": "0", "IOSchedulingPriority": "0", "IOWeight": "[not set]", "IOWriteBytes": "18446744073709551615", "IOWriteOperations": "18446744073709551615", "IPAccounting": "no", "IPEgressBytes": "[no data]", "IPEgressPackets": "[no data]", "IPIngressBytes": "[no data]", "IPIngressPackets": "[no data]", "Id": "confluent-kcontroller.service", "IgnoreOnIsolate": "no", "IgnoreSIGPIPE": "yes", "InactiveEnterTimestampMonotonic": "0", "InactiveExitTimestamp": "Thu 2024-10-17 16:32:37 CEST", "InactiveExitTimestampMonotonic": "28526172406", "InvocationID": "6191c9ba272046cc95153441dfb057fc", "JobRunningTimeoutUSec": "infinity", "JobTimeoutAction": "none", "JobTimeoutUSec": "infinity", "KeyringMode": "private", "KillMode": "control-group", "KillSignal": "15", "LimitAS": "infinity", "LimitASSoft": "infinity", "LimitCORE": "infinity", "LimitCORESoft": "infinity", "LimitCPU": "infinity", "LimitCPUSoft": "infinity", "LimitDATA": "infinity", "LimitDATASoft": "infinity", "LimitFSIZE": "infinity", "LimitFSIZESoft": "infinity", "LimitLOCKS": "infinity", "LimitLOCKSSoft": "infinity", "LimitMEMLOCK": "8388608", "LimitMEMLOCKSoft": "8388608", "LimitMSGQUEUE": "819200", "LimitMSGQUEUESoft": "819200", "LimitNICE": "0", "LimitNICESoft": "0", "LimitNOFILE": "1000000", "LimitNOFILESoft": "1000000", "LimitNPROC": "infinity", "LimitNPROCSoft": "infinity", "LimitRSS": "infinity", "LimitRSSSoft": "infinity", "LimitRTPRIO": "0", "LimitRTPRIOSoft": "0", "LimitRTTIME": "infinity", "LimitRTTIMESoft": "infinity", "LimitSIGPENDING": "128316", "LimitSIGPENDINGSoft": "128316", "LimitSTACK": "infinity", "LimitSTACKSoft": "8388608", "LoadState": "loaded", "LockPersonality": "no", "LogLevelMax": "-1", "LogRateLimitBurst": "0", "LogRateLimitIntervalUSec": "0", "LogsDirectoryMode": "0755", "MainPID": "6566", "MemoryAccounting": "yes", "MemoryCurrent": "340983808", "MemoryDenyWriteExecute": "no", "MemoryHigh": "infinity", "MemoryLimit": "infinity", "MemoryLow": "0", "MemoryMax": "infinity", "MemoryMin": "0", "MemorySwapMax": "infinity", "MountAPIVFS": "no", "MountFlags": "", "NFileDescriptorStore": "0", "NRestarts": "0", "NUMAMask": "", "NUMAPolicy": "n/a", "Names": "confluent-kcontroller.service", "NeedDaemonReload": "no", "Nice": "0", "NoNewPrivileges": "no", "NonBlocking": "no", "NotifyAccess": "none", "OOMPolicy": "stop", "OOMScoreAdjust": "0", "OnFailureJobMode": "replace", "Perpetual": "no", "PrivateDevices": "no", "PrivateMounts": "no", "PrivateNetwork": "no", "PrivateTmp": "no", "PrivateUsers": "no", "ProtectControlGroups": "no", "ProtectHome": "no", "ProtectHostname": "no", "ProtectKernelLogs": "no", "ProtectKernelModules": "no", "ProtectKernelTunables": "no", "ProtectSystem": "no", "RefuseManualStart": "no", "RefuseManualStop": "no", "ReloadResult": "success", "RemainAfterExit": "no", "RemoveIPC": "no", "Requires": "sysinit.target system.slice", "Restart": "no", "RestartKillSignal": "15", "RestartUSec": "100ms", "RestrictNamespaces": "no", "RestrictRealtime": "no", "RestrictSUIDSGID": "no", "Result": "success", "RootDirectoryStartOnly": "no", "RuntimeDirectoryMode": "0755", "RuntimeDirectoryPreserve": "no", "RuntimeMaxUSec": "infinity", "SameProcessGroup": "no", "SecureBits": "0", "SendSIGHUP": "no", "SendSIGKILL": "yes", "Slice": "system.slice", "StandardError": "inherit", "StandardInput": "null", "StandardInputData": "", "StandardOutput": "journal", "StartLimitAction": "none", "StartLimitBurst": "5", "StartLimitIntervalUSec": "10s", "StartupBlockIOWeight": "[not set]", "StartupCPUShares": "[not set]", "StartupCPUWeight": "[not set]", "StartupIOWeight": "[not set]", "StateChangeTimestamp": "Thu 2024-10-17 16:32:37 CEST", "StateChangeTimestampMonotonic": "28526172406", "StateDirectoryMode": "0755", "StatusErrno": "0", "StopWhenUnneeded": "no", "SubState": "running", "SuccessAction": "none", "SyslogFacility": "3", "SyslogLevel": "6", "SyslogLevelPrefix": "yes", "SyslogPriority": "30", "SystemCallErrorNumber": "0", "TTYReset": "no", "TTYVHangup": "no", "TTYVTDisallocate": "no", "TasksAccounting": "yes", "TasksCurrent": "81", "TasksMax": "38494", "TimeoutAbortUSec": "3min", "TimeoutCleanUSec": "infinity", "TimeoutStartUSec": "1min 30s", "TimeoutStopUSec": "3min", "TimerSlackNSec": "50000", "Transient": "no", "Type": "simple", "UID": "110", "UMask": "0022", "UnitFilePreset": "enabled", "UnitFileState": "disabled", "User": "cp-kafka", "UtmpMode": "init", "WatchdogSignal": "6", "WatchdogTimestampMonotonic": "0", "WatchdogUSec": "0"}}

TASK [confluent.platform.kafka_controller : Wait for Controller health checks to complete] ***
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "skip_reason": "Conditional result was False"}
included: /home/ubuntu/.ansible/collections/ansible_collections/confluent/platform/roles/kafka_controller/tasks/health_check.yml for kafka-controller-3-migrated

TASK [confluent.platform.kafka_controller : Check Kafka Metadata Quorum] *******
ok: [kafka-controller-3-migrated] => {"changed": false, "cmd": "/usr/bin/kafka-metadata-quorum --bootstrap-server kafka-controller-3-migrated:9093  --command-config /etc/controller/client.properties describe --replication\n", "delta": "0:00:01.620915", "end": "2024-10-17 16:33:01.285444", "msg": "", "rc": 0, "start": "2024-10-17 16:32:59.664529", "stderr": "", "stderr_lines": [], "stdout": "NodeId\tLogEndOffset\tLag\tLastFetchTimestamp\tLastCaughtUpTimestamp\tStatus  \t\n9991  \t3667        \t0  \t1729175580931     \t1729175580931        \tLeader  \t\n9992  \t3667        \t0  \t1729175580568     \t1729175580568        \tFollower\t\n9993  \t3667        \t0  \t1729175580568     \t1729175580568        \tFollower\t\n1     \t3667        \t0  \t1729175580563     \t1729175580563        \tObserver\t", "stdout_lines": ["NodeId\tLogEndOffset\tLag\tLastFetchTimestamp\tLastCaughtUpTimestamp\tStatus  \t", "9991  \t3667        \t0  \t1729175580931     \t1729175580931        \tLeader  \t", "9992  \t3667        \t0  \t1729175580568     \t1729175580568        \tFollower\t", "9993  \t3667        \t0  \t1729175580568     \t1729175580568        \tFollower\t", "1     \t3667        \t0  \t1729175580563     \t1729175580563        \tObserver\t"]}

TASK [confluent.platform.kafka_controller : Register LogEndOffset] *************
ok: [kafka-controller-3-migrated] => {"changed": false, "cmd": "/usr/bin/kafka-metadata-quorum --bootstrap-server kafka-controller-3-migrated:9093  --command-config /etc/controller/client.properties describe --replication |  grep -v Observer | awk '{print $2}'\n", "delta": "0:00:01.527193", "end": "2024-10-17 16:33:03.149702", "msg": "", "rc": 0, "start": "2024-10-17 16:33:01.622509", "stderr": "", "stderr_lines": [], "stdout": "LogEndOffset\n3671\n3671\n3671", "stdout_lines": ["LogEndOffset", "3671", "3671", "3671"]}

TASK [confluent.platform.kafka_controller : Check LogEndOffset values] *********
[WARNING]: conditional statements should not include jinja2 templating
delimiters such as {{ }} or {% %}. Found: {{ item|int > 0 and
LEO.stdout_lines[1:]|max|int - item|int < 1000 }}
ok: [kafka-controller-3-migrated] => (item=3671) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "3671",
    "msg": "All assertions passed"
}
ok: [kafka-controller-3-migrated] => (item=3671) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "3671",
    "msg": "All assertions passed"
}
ok: [kafka-controller-3-migrated] => (item=3671) => {
    "ansible_loop_var": "item",
    "changed": false,
    "item": "3671",
    "msg": "All assertions passed"
}

TASK [confluent.platform.kafka_controller : Remove confluent.use.controller.listener config from Client Properties] ***
ok: [kafka-controller-3-migrated] => {"backup": "", "changed": false, "found": 1, "msg": "1 line(s) removed"}

TASK [confluent.platform.kafka_controller : Delete temporary keys/certs when keystore and trustore is provided] ***
skipping: [kafka-controller-1] => (item=/var/ssl/private/ca.crt)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/ca.crt", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=/var/ssl/private/kafka_controller.crt)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/kafka_controller.crt", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => (item=/var/ssl/private/kafka_controller.key)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/kafka_controller.key", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=/var/ssl/private/ca.crt)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/ca.crt", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=/var/ssl/private/kafka_controller.crt)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/kafka_controller.crt", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => (item=/var/ssl/private/kafka_controller.key)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/kafka_controller.key", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=/var/ssl/private/ca.crt)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/ca.crt", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=/var/ssl/private/kafka_controller.crt)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/kafka_controller.crt", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => (item=/var/ssl/private/kafka_controller.key)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/kafka_controller.key", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-1] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-2] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-controller-3-migrated] => (item=/var/ssl/private/ca.crt)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "(ssl_provided_keystore_and_truststore | bool)", "item": "/var/ssl/private/ca.crt", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => (item=/var/ssl/private/kafka_controller.crt)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "(ssl_provided_keystore_and_truststore | bool)", "item": "/var/ssl/private/kafka_controller.crt", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => (item=/var/ssl/private/kafka_controller.key)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "(ssl_provided_keystore_and_truststore | bool)", "item": "/var/ssl/private/kafka_controller.key", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "msg": "All items skipped"}
skipping: [kafka-broker-1] => (item=/var/ssl/private/ca.crt)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/ca.crt", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=/var/ssl/private/kafka_controller.crt)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/kafka_controller.crt", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => (item=/var/ssl/private/kafka_controller.key)  => {"ansible_loop_var": "item", "changed": false, "false_condition": "inventory_hostname == 'kafka-controller-3-migrated'", "item": "/var/ssl/private/kafka_controller.key", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "msg": "All items skipped"}

TASK [verify kafka-controller-3-migrated has the same ClusterId] ***************
ok: [kafka-controller-1 -> kafka-controller-3-migrated(localhost)] => {"changed": false, "content": "IwojVGh1IE9jdCAxNyAxNjozMjoyMiBDRVNUIDIwMjQKbm9kZS5pZD05OTkzCnZlcnNpb249MQpjbHVzdGVyLmlkPWdLUDF5TlR2VHZxZjRJQ0VZenBZc2cK", "encoding": "base64", "source": "/var/lib/controller/data/meta.properties"}

TASK [Compare ClusterId from new and existing controllers] *********************
ok: [kafka-controller-1] => {
    "changed": false,
    "msg": "Cluster ID matches successfully between the new and existing controllers"
}
ok: [kafka-controller-2] => {
    "changed": false,
    "msg": "Cluster ID matches successfully between the new and existing controllers"
}
ok: [kafka-controller-3] => {
    "changed": false,
    "msg": "Cluster ID matches successfully between the new and existing controllers"
}
ok: [kafka-controller-3-migrated] => {
    "changed": false,
    "msg": "Cluster ID matches successfully between the new and existing controllers"
}
ok: [kafka-broker-1] => {
    "changed": false,
    "msg": "Cluster ID matches successfully between the new and existing controllers"
}

TASK [Update Controller Quorum Voters Configuration] ***************************
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname in ['kafka-controller-1', 'kafka-controller-2']", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "inventory_hostname in ['kafka-controller-1', 'kafka-controller-2']", "skip_reason": "Conditional result was False"}
skipping: [kafka-broker-1] => {"changed": false, "false_condition": "inventory_hostname in ['kafka-controller-1', 'kafka-controller-2']", "skip_reason": "Conditional result was False"}
changed: [kafka-controller-1] => {"backup": "", "changed": true, "msg": "line replaced"}
changed: [kafka-controller-2] => {"backup": "", "changed": true, "msg": "line replaced"}

TASK [Update Configuration for Broker] *****************************************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
changed: [kafka-broker-1] => {"backup": "", "changed": true, "msg": "line replaced"}

TASK [Restart Kafka Controllers] ***********************************************
changed: [kafka-controller-1] => (item=kafka-controller-1) => {"ansible_loop_var": "item", "changed": true, "item": "kafka-controller-1", "name": "confluent-kcontroller", "state": "started", "status": {"ActiveEnterTimestamp": "Thu 2024-10-17 16:12:16 CEST", "ActiveEnterTimestampMonotonic": "27305121168", "ActiveExitTimestampMonotonic": "0", "ActiveState": "active", "After": "network.target confluent-zookeeper.target basic.target system.slice sysinit.target systemd-journald.socket", "AllowIsolate": "no", "AllowedCPUs": "", "AllowedMemoryNodes": "", "AmbientCapabilities": "", "AssertResult": "yes", "AssertTimestamp": "Thu 2024-10-17 16:12:16 CEST", "AssertTimestampMonotonic": "27305119909", "Before": "multi-user.target shutdown.target", "BlockIOAccounting": "no", "BlockIOWeight": "[not set]", "CPUAccounting": "no", "CPUAffinity": "", "CPUAffinityFromNUMA": "no", "CPUQuotaPerSecUSec": "infinity", "CPUQuotaPeriodUSec": "infinity", "CPUSchedulingPolicy": "0", "CPUSchedulingPriority": "0", "CPUSchedulingResetOnFork": "no", "CPUShares": "[not set]", "CPUUsageNSec": "[not set]", "CPUWeight": "[not set]", "CacheDirectoryMode": "0755", "CanIsolate": "no", "CanReload": "no", "CanStart": "yes", "CanStop": "yes", "CapabilityBoundingSet": "cap_chown cap_dac_override cap_dac_read_search cap_fowner cap_fsetid cap_kill cap_setgid cap_setuid cap_setpcap cap_linux_immutable cap_net_bind_service cap_net_broadcast cap_net_admin cap_net_raw cap_ipc_lock cap_ipc_owner cap_sys_module cap_sys_rawio cap_sys_chroot cap_sys_ptrace cap_sys_pacct cap_sys_admin cap_sys_boot cap_sys_nice cap_sys_resource cap_sys_time cap_sys_tty_config cap_mknod cap_lease cap_audit_write cap_audit_control cap_setfcap cap_mac_override cap_mac_admin cap_syslog cap_wake_alarm cap_block_suspend cap_audit_read 0x26 0x27 0x28", "CleanResult": "success", "CollectMode": "inactive", "ConditionResult": "yes", "ConditionTimestamp": "Thu 2024-10-17 16:12:16 CEST", "ConditionTimestampMonotonic": "27305119908", "ConfigurationDirectoryMode": "0755", "Conflicts": "shutdown.target", "ControlGroup": "/docker/f6958d130d226b931235b17fdf4a00de205ccb416a52612a265b098847e24662/system.slice/confluent-kcontroller.service", "ControlPID": "0", "DefaultDependencies": "yes", "DefaultMemoryLow": "0", "DefaultMemoryMin": "0", "Delegate": "no", "Description": "Apache Kafka - broker", "DevicePolicy": "auto", "Documentation": "http://docs.confluent.io/", "DropInPaths": "/etc/systemd/system/confluent-kcontroller.service.d/override.conf", "DynamicUser": "no", "EffectiveCPUs": "", "EffectiveMemoryNodes": "", "Environment": "[unprintable] KAFKA_LOG4J_OPTS=-Dlog4j.configuration=file:/etc/kafka/log4j.properties LOG_DIR=/var/log/controller", "ExecMainCode": "0", "ExecMainExitTimestampMonotonic": "0", "ExecMainPID": "6655", "ExecMainStartTimestamp": "Thu 2024-10-17 16:12:16 CEST", "ExecMainStartTimestampMonotonic": "27305120927", "ExecMainStatus": "0", "ExecStart": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "ExecStartEx": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; flags= ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "FailureAction": "none", "FileDescriptorStoreMax": "0", "FinalKillSignal": "9", "FragmentPath": "/lib/systemd/system/confluent-kcontroller.service", "GID": "107", "Group": "confluent", "GuessMainPID": "yes", "IOAccounting": "no", "IOReadBytes": "18446744073709551615", "IOReadOperations": "18446744073709551615", "IOSchedulingClass": "0", "IOSchedulingPriority": "0", "IOWeight": "[not set]", "IOWriteBytes": "18446744073709551615", "IOWriteOperations": "18446744073709551615", "IPAccounting": "no", "IPEgressBytes": "[no data]", "IPEgressPackets": "[no data]", "IPIngressBytes": "[no data]", "IPIngressPackets": "[no data]", "Id": "confluent-kcontroller.service", "IgnoreOnIsolate": "no", "IgnoreSIGPIPE": "yes", "InactiveEnterTimestampMonotonic": "0", "InactiveExitTimestamp": "Thu 2024-10-17 16:12:16 CEST", "InactiveExitTimestampMonotonic": "27305121168", "InvocationID": "30b70a7ed8bc4b76a07ef0f4ce7a4c0f", "JobRunningTimeoutUSec": "infinity", "JobTimeoutAction": "none", "JobTimeoutUSec": "infinity", "KeyringMode": "private", "KillMode": "control-group", "KillSignal": "15", "LimitAS": "infinity", "LimitASSoft": "infinity", "LimitCORE": "infinity", "LimitCORESoft": "infinity", "LimitCPU": "infinity", "LimitCPUSoft": "infinity", "LimitDATA": "infinity", "LimitDATASoft": "infinity", "LimitFSIZE": "infinity", "LimitFSIZESoft": "infinity", "LimitLOCKS": "infinity", "LimitLOCKSSoft": "infinity", "LimitMEMLOCK": "8388608", "LimitMEMLOCKSoft": "8388608", "LimitMSGQUEUE": "819200", "LimitMSGQUEUESoft": "819200", "LimitNICE": "0", "LimitNICESoft": "0", "LimitNOFILE": "1000000", "LimitNOFILESoft": "1000000", "LimitNPROC": "infinity", "LimitNPROCSoft": "infinity", "LimitRSS": "infinity", "LimitRSSSoft": "infinity", "LimitRTPRIO": "0", "LimitRTPRIOSoft": "0", "LimitRTTIME": "infinity", "LimitRTTIMESoft": "infinity", "LimitSIGPENDING": "128316", "LimitSIGPENDINGSoft": "128316", "LimitSTACK": "infinity", "LimitSTACKSoft": "8388608", "LoadState": "loaded", "LockPersonality": "no", "LogLevelMax": "-1", "LogRateLimitBurst": "0", "LogRateLimitIntervalUSec": "0", "LogsDirectoryMode": "0755", "MainPID": "6655", "MemoryAccounting": "yes", "MemoryCurrent": "475107328", "MemoryDenyWriteExecute": "no", "MemoryHigh": "infinity", "MemoryLimit": "infinity", "MemoryLow": "0", "MemoryMax": "infinity", "MemoryMin": "0", "MemorySwapMax": "infinity", "MountAPIVFS": "no", "MountFlags": "", "NFileDescriptorStore": "0", "NRestarts": "0", "NUMAMask": "", "NUMAPolicy": "n/a", "Names": "confluent-kcontroller.service", "NeedDaemonReload": "no", "Nice": "0", "NoNewPrivileges": "no", "NonBlocking": "no", "NotifyAccess": "none", "OOMPolicy": "stop", "OOMScoreAdjust": "0", "OnFailureJobMode": "replace", "Perpetual": "no", "PrivateDevices": "no", "PrivateMounts": "no", "PrivateNetwork": "no", "PrivateTmp": "no", "PrivateUsers": "no", "ProtectControlGroups": "no", "ProtectHome": "no", "ProtectHostname": "no", "ProtectKernelLogs": "no", "ProtectKernelModules": "no", "ProtectKernelTunables": "no", "ProtectSystem": "no", "RefuseManualStart": "no", "RefuseManualStop": "no", "ReloadResult": "success", "RemainAfterExit": "no", "RemoveIPC": "no", "Requires": "sysinit.target system.slice", "Restart": "no", "RestartKillSignal": "15", "RestartUSec": "100ms", "RestrictNamespaces": "no", "RestrictRealtime": "no", "RestrictSUIDSGID": "no", "Result": "success", "RootDirectoryStartOnly": "no", "RuntimeDirectoryMode": "0755", "RuntimeDirectoryPreserve": "no", "RuntimeMaxUSec": "infinity", "SameProcessGroup": "no", "SecureBits": "0", "SendSIGHUP": "no", "SendSIGKILL": "yes", "Slice": "system.slice", "StandardError": "inherit", "StandardInput": "null", "StandardInputData": "", "StandardOutput": "journal", "StartLimitAction": "none", "StartLimitBurst": "5", "StartLimitIntervalUSec": "10s", "StartupBlockIOWeight": "[not set]", "StartupCPUShares": "[not set]", "StartupCPUWeight": "[not set]", "StartupIOWeight": "[not set]", "StateChangeTimestamp": "Thu 2024-10-17 16:12:16 CEST", "StateChangeTimestampMonotonic": "27305121168", "StateDirectoryMode": "0755", "StatusErrno": "0", "StopWhenUnneeded": "no", "SubState": "running", "SuccessAction": "none", "SyslogFacility": "3", "SyslogLevel": "6", "SyslogLevelPrefix": "yes", "SyslogPriority": "30", "SystemCallErrorNumber": "0", "TTYReset": "no", "TTYVHangup": "no", "TTYVTDisallocate": "no", "TasksAccounting": "yes", "TasksCurrent": "83", "TasksMax": "38494", "TimeoutAbortUSec": "3min", "TimeoutCleanUSec": "infinity", "TimeoutStartUSec": "1min 30s", "TimeoutStopUSec": "3min", "TimerSlackNSec": "50000", "Transient": "no", "Type": "simple", "UID": "110", "UMask": "0022", "UnitFilePreset": "enabled", "UnitFileState": "enabled", "User": "cp-kafka", "UtmpMode": "init", "WantedBy": "multi-user.target", "WatchdogSignal": "6", "WatchdogTimestampMonotonic": "0", "WatchdogUSec": "0"}}
changed: [kafka-controller-1 -> kafka-controller-2(localhost)] => (item=kafka-controller-2) => {"ansible_loop_var": "item", "changed": true, "item": "kafka-controller-2", "name": "confluent-kcontroller", "state": "started", "status": {"ActiveEnterTimestamp": "Thu 2024-10-17 16:12:16 CEST", "ActiveEnterTimestampMonotonic": "27305110593", "ActiveExitTimestampMonotonic": "0", "ActiveState": "active", "After": "system.slice sysinit.target confluent-zookeeper.target systemd-journald.socket basic.target network.target", "AllowIsolate": "no", "AllowedCPUs": "", "AllowedMemoryNodes": "", "AmbientCapabilities": "", "AssertResult": "yes", "AssertTimestamp": "Thu 2024-10-17 16:12:16 CEST", "AssertTimestampMonotonic": "27305109267", "Before": "shutdown.target multi-user.target", "BlockIOAccounting": "no", "BlockIOWeight": "[not set]", "CPUAccounting": "no", "CPUAffinity": "", "CPUAffinityFromNUMA": "no", "CPUQuotaPerSecUSec": "infinity", "CPUQuotaPeriodUSec": "infinity", "CPUSchedulingPolicy": "0", "CPUSchedulingPriority": "0", "CPUSchedulingResetOnFork": "no", "CPUShares": "[not set]", "CPUUsageNSec": "[not set]", "CPUWeight": "[not set]", "CacheDirectoryMode": "0755", "CanIsolate": "no", "CanReload": "no", "CanStart": "yes", "CanStop": "yes", "CapabilityBoundingSet": "cap_chown cap_dac_override cap_dac_read_search cap_fowner cap_fsetid cap_kill cap_setgid cap_setuid cap_setpcap cap_linux_immutable cap_net_bind_service cap_net_broadcast cap_net_admin cap_net_raw cap_ipc_lock cap_ipc_owner cap_sys_module cap_sys_rawio cap_sys_chroot cap_sys_ptrace cap_sys_pacct cap_sys_admin cap_sys_boot cap_sys_nice cap_sys_resource cap_sys_time cap_sys_tty_config cap_mknod cap_lease cap_audit_write cap_audit_control cap_setfcap cap_mac_override cap_mac_admin cap_syslog cap_wake_alarm cap_block_suspend cap_audit_read 0x26 0x27 0x28", "CleanResult": "success", "CollectMode": "inactive", "ConditionResult": "yes", "ConditionTimestamp": "Thu 2024-10-17 16:12:16 CEST", "ConditionTimestampMonotonic": "27305109266", "ConfigurationDirectoryMode": "0755", "Conflicts": "shutdown.target", "ControlGroup": "/docker/ff9ec7f85107178d83389f2cf510079f64a84566d9dd526722b95a1e6c5f9433/system.slice/confluent-kcontroller.service", "ControlPID": "0", "DefaultDependencies": "yes", "DefaultMemoryLow": "0", "DefaultMemoryMin": "0", "Delegate": "no", "Description": "Apache Kafka - broker", "DevicePolicy": "auto", "Documentation": "http://docs.confluent.io/", "DropInPaths": "/etc/systemd/system/confluent-kcontroller.service.d/override.conf", "DynamicUser": "no", "EffectiveCPUs": "", "EffectiveMemoryNodes": "", "Environment": "[unprintable] KAFKA_LOG4J_OPTS=-Dlog4j.configuration=file:/etc/kafka/log4j.properties LOG_DIR=/var/log/controller", "ExecMainCode": "0", "ExecMainExitTimestampMonotonic": "0", "ExecMainPID": "6618", "ExecMainStartTimestamp": "Thu 2024-10-17 16:12:16 CEST", "ExecMainStartTimestampMonotonic": "27305110358", "ExecMainStatus": "0", "ExecStart": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "ExecStartEx": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; flags= ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "FailureAction": "none", "FileDescriptorStoreMax": "0", "FinalKillSignal": "9", "FragmentPath": "/lib/systemd/system/confluent-kcontroller.service", "GID": "107", "Group": "confluent", "GuessMainPID": "yes", "IOAccounting": "no", "IOReadBytes": "18446744073709551615", "IOReadOperations": "18446744073709551615", "IOSchedulingClass": "0", "IOSchedulingPriority": "0", "IOWeight": "[not set]", "IOWriteBytes": "18446744073709551615", "IOWriteOperations": "18446744073709551615", "IPAccounting": "no", "IPEgressBytes": "[no data]", "IPEgressPackets": "[no data]", "IPIngressBytes": "[no data]", "IPIngressPackets": "[no data]", "Id": "confluent-kcontroller.service", "IgnoreOnIsolate": "no", "IgnoreSIGPIPE": "yes", "InactiveEnterTimestampMonotonic": "0", "InactiveExitTimestamp": "Thu 2024-10-17 16:12:16 CEST", "InactiveExitTimestampMonotonic": "27305110593", "InvocationID": "22fa59831bb64320b0cefe5cd83b42bf", "JobRunningTimeoutUSec": "infinity", "JobTimeoutAction": "none", "JobTimeoutUSec": "infinity", "KeyringMode": "private", "KillMode": "control-group", "KillSignal": "15", "LimitAS": "infinity", "LimitASSoft": "infinity", "LimitCORE": "infinity", "LimitCORESoft": "infinity", "LimitCPU": "infinity", "LimitCPUSoft": "infinity", "LimitDATA": "infinity", "LimitDATASoft": "infinity", "LimitFSIZE": "infinity", "LimitFSIZESoft": "infinity", "LimitLOCKS": "infinity", "LimitLOCKSSoft": "infinity", "LimitMEMLOCK": "8388608", "LimitMEMLOCKSoft": "8388608", "LimitMSGQUEUE": "819200", "LimitMSGQUEUESoft": "819200", "LimitNICE": "0", "LimitNICESoft": "0", "LimitNOFILE": "1000000", "LimitNOFILESoft": "1000000", "LimitNPROC": "infinity", "LimitNPROCSoft": "infinity", "LimitRSS": "infinity", "LimitRSSSoft": "infinity", "LimitRTPRIO": "0", "LimitRTPRIOSoft": "0", "LimitRTTIME": "infinity", "LimitRTTIMESoft": "infinity", "LimitSIGPENDING": "128316", "LimitSIGPENDINGSoft": "128316", "LimitSTACK": "infinity", "LimitSTACKSoft": "8388608", "LoadState": "loaded", "LockPersonality": "no", "LogLevelMax": "-1", "LogRateLimitBurst": "0", "LogRateLimitIntervalUSec": "0", "LogsDirectoryMode": "0755", "MainPID": "6618", "MemoryAccounting": "yes", "MemoryCurrent": "381198336", "MemoryDenyWriteExecute": "no", "MemoryHigh": "infinity", "MemoryLimit": "infinity", "MemoryLow": "0", "MemoryMax": "infinity", "MemoryMin": "0", "MemorySwapMax": "infinity", "MountAPIVFS": "no", "MountFlags": "", "NFileDescriptorStore": "0", "NRestarts": "0", "NUMAMask": "", "NUMAPolicy": "n/a", "Names": "confluent-kcontroller.service", "NeedDaemonReload": "no", "Nice": "0", "NoNewPrivileges": "no", "NonBlocking": "no", "NotifyAccess": "none", "OOMPolicy": "stop", "OOMScoreAdjust": "0", "OnFailureJobMode": "replace", "Perpetual": "no", "PrivateDevices": "no", "PrivateMounts": "no", "PrivateNetwork": "no", "PrivateTmp": "no", "PrivateUsers": "no", "ProtectControlGroups": "no", "ProtectHome": "no", "ProtectHostname": "no", "ProtectKernelLogs": "no", "ProtectKernelModules": "no", "ProtectKernelTunables": "no", "ProtectSystem": "no", "RefuseManualStart": "no", "RefuseManualStop": "no", "ReloadResult": "success", "RemainAfterExit": "no", "RemoveIPC": "no", "Requires": "sysinit.target system.slice", "Restart": "no", "RestartKillSignal": "15", "RestartUSec": "100ms", "RestrictNamespaces": "no", "RestrictRealtime": "no", "RestrictSUIDSGID": "no", "Result": "success", "RootDirectoryStartOnly": "no", "RuntimeDirectoryMode": "0755", "RuntimeDirectoryPreserve": "no", "RuntimeMaxUSec": "infinity", "SameProcessGroup": "no", "SecureBits": "0", "SendSIGHUP": "no", "SendSIGKILL": "yes", "Slice": "system.slice", "StandardError": "inherit", "StandardInput": "null", "StandardInputData": "", "StandardOutput": "journal", "StartLimitAction": "none", "StartLimitBurst": "5", "StartLimitIntervalUSec": "10s", "StartupBlockIOWeight": "[not set]", "StartupCPUShares": "[not set]", "StartupCPUWeight": "[not set]", "StartupIOWeight": "[not set]", "StateChangeTimestamp": "Thu 2024-10-17 16:12:16 CEST", "StateChangeTimestampMonotonic": "27305110593", "StateDirectoryMode": "0755", "StatusErrno": "0", "StopWhenUnneeded": "no", "SubState": "running", "SuccessAction": "none", "SyslogFacility": "3", "SyslogLevel": "6", "SyslogLevelPrefix": "yes", "SyslogPriority": "30", "SystemCallErrorNumber": "0", "TTYReset": "no", "TTYVHangup": "no", "TTYVTDisallocate": "no", "TasksAccounting": "yes", "TasksCurrent": "82", "TasksMax": "38494", "TimeoutAbortUSec": "3min", "TimeoutCleanUSec": "infinity", "TimeoutStartUSec": "1min 30s", "TimeoutStopUSec": "3min", "TimerSlackNSec": "50000", "Transient": "no", "Type": "simple", "UID": "110", "UMask": "0022", "UnitFilePreset": "enabled", "UnitFileState": "enabled", "User": "cp-kafka", "UtmpMode": "init", "WantedBy": "multi-user.target", "WatchdogSignal": "6", "WatchdogTimestampMonotonic": "0", "WatchdogUSec": "0"}}
changed: [kafka-controller-1 -> kafka-controller-3-migrated(localhost)] => (item=kafka-controller-3-migrated) => {"ansible_loop_var": "item", "changed": true, "item": "kafka-controller-3-migrated", "name": "confluent-kcontroller", "state": "started", "status": {"ActiveEnterTimestamp": "Thu 2024-10-17 16:32:37 CEST", "ActiveEnterTimestampMonotonic": "28526172406", "ActiveExitTimestampMonotonic": "0", "ActiveState": "active", "After": "system.slice basic.target sysinit.target confluent-zookeeper.target network.target systemd-journald.socket", "AllowIsolate": "no", "AllowedCPUs": "", "AllowedMemoryNodes": "", "AmbientCapabilities": "", "AssertResult": "yes", "AssertTimestamp": "Thu 2024-10-17 16:32:37 CEST", "AssertTimestampMonotonic": "28526164205", "Before": "shutdown.target multi-user.target", "BlockIOAccounting": "no", "BlockIOWeight": "[not set]", "CPUAccounting": "no", "CPUAffinity": "", "CPUAffinityFromNUMA": "no", "CPUQuotaPerSecUSec": "infinity", "CPUQuotaPeriodUSec": "infinity", "CPUSchedulingPolicy": "0", "CPUSchedulingPriority": "0", "CPUSchedulingResetOnFork": "no", "CPUShares": "[not set]", "CPUUsageNSec": "[not set]", "CPUWeight": "[not set]", "CacheDirectoryMode": "0755", "CanIsolate": "no", "CanReload": "no", "CanStart": "yes", "CanStop": "yes", "CapabilityBoundingSet": "cap_chown cap_dac_override cap_dac_read_search cap_fowner cap_fsetid cap_kill cap_setgid cap_setuid cap_setpcap cap_linux_immutable cap_net_bind_service cap_net_broadcast cap_net_admin cap_net_raw cap_ipc_lock cap_ipc_owner cap_sys_module cap_sys_rawio cap_sys_chroot cap_sys_ptrace cap_sys_pacct cap_sys_admin cap_sys_boot cap_sys_nice cap_sys_resource cap_sys_time cap_sys_tty_config cap_mknod cap_lease cap_audit_write cap_audit_control cap_setfcap cap_mac_override cap_mac_admin cap_syslog cap_wake_alarm cap_block_suspend cap_audit_read 0x26 0x27 0x28", "CleanResult": "success", "CollectMode": "inactive", "ConditionResult": "yes", "ConditionTimestamp": "Thu 2024-10-17 16:32:37 CEST", "ConditionTimestampMonotonic": "28526164204", "ConfigurationDirectoryMode": "0755", "Conflicts": "shutdown.target", "ControlGroup": "/docker/cff3151f3d6ba2ef7d36d878b20495fef547788113839d123d3270a702ca6f68/system.slice/confluent-kcontroller.service", "ControlPID": "0", "DefaultDependencies": "yes", "DefaultMemoryLow": "0", "DefaultMemoryMin": "0", "Delegate": "no", "Description": "Apache Kafka - broker", "DevicePolicy": "auto", "Documentation": "http://docs.confluent.io/", "DropInPaths": "/etc/systemd/system/confluent-kcontroller.service.d/override.conf", "DynamicUser": "no", "EffectiveCPUs": "", "EffectiveMemoryNodes": "", "Environment": "[unprintable] KAFKA_LOG4J_OPTS=-Dlog4j.configuration=file:/etc/kafka/log4j.properties LOG_DIR=/var/log/controller", "ExecMainCode": "0", "ExecMainExitTimestampMonotonic": "0", "ExecMainPID": "6566", "ExecMainStartTimestamp": "Thu 2024-10-17 16:32:37 CEST", "ExecMainStartTimestampMonotonic": "28526172145", "ExecMainStatus": "0", "ExecStart": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "ExecStartEx": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/controller/server.properties ; flags= ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "FailureAction": "none", "FileDescriptorStoreMax": "0", "FinalKillSignal": "9", "FragmentPath": "/lib/systemd/system/confluent-kcontroller.service", "GID": "107", "Group": "confluent", "GuessMainPID": "yes", "IOAccounting": "no", "IOReadBytes": "18446744073709551615", "IOReadOperations": "18446744073709551615", "IOSchedulingClass": "0", "IOSchedulingPriority": "0", "IOWeight": "[not set]", "IOWriteBytes": "18446744073709551615", "IOWriteOperations": "18446744073709551615", "IPAccounting": "no", "IPEgressBytes": "[no data]", "IPEgressPackets": "[no data]", "IPIngressBytes": "[no data]", "IPIngressPackets": "[no data]", "Id": "confluent-kcontroller.service", "IgnoreOnIsolate": "no", "IgnoreSIGPIPE": "yes", "InactiveEnterTimestampMonotonic": "0", "InactiveExitTimestamp": "Thu 2024-10-17 16:32:37 CEST", "InactiveExitTimestampMonotonic": "28526172406", "InvocationID": "6191c9ba272046cc95153441dfb057fc", "JobRunningTimeoutUSec": "infinity", "JobTimeoutAction": "none", "JobTimeoutUSec": "infinity", "KeyringMode": "private", "KillMode": "control-group", "KillSignal": "15", "LimitAS": "infinity", "LimitASSoft": "infinity", "LimitCORE": "infinity", "LimitCORESoft": "infinity", "LimitCPU": "infinity", "LimitCPUSoft": "infinity", "LimitDATA": "infinity", "LimitDATASoft": "infinity", "LimitFSIZE": "infinity", "LimitFSIZESoft": "infinity", "LimitLOCKS": "infinity", "LimitLOCKSSoft": "infinity", "LimitMEMLOCK": "8388608", "LimitMEMLOCKSoft": "8388608", "LimitMSGQUEUE": "819200", "LimitMSGQUEUESoft": "819200", "LimitNICE": "0", "LimitNICESoft": "0", "LimitNOFILE": "1000000", "LimitNOFILESoft": "1000000", "LimitNPROC": "infinity", "LimitNPROCSoft": "infinity", "LimitRSS": "infinity", "LimitRSSSoft": "infinity", "LimitRTPRIO": "0", "LimitRTPRIOSoft": "0", "LimitRTTIME": "infinity", "LimitRTTIMESoft": "infinity", "LimitSIGPENDING": "128316", "LimitSIGPENDINGSoft": "128316", "LimitSTACK": "infinity", "LimitSTACKSoft": "8388608", "LoadState": "loaded", "LockPersonality": "no", "LogLevelMax": "-1", "LogRateLimitBurst": "0", "LogRateLimitIntervalUSec": "0", "LogsDirectoryMode": "0755", "MainPID": "6566", "MemoryAccounting": "yes", "MemoryCurrent": "347451392", "MemoryDenyWriteExecute": "no", "MemoryHigh": "infinity", "MemoryLimit": "infinity", "MemoryLow": "0", "MemoryMax": "infinity", "MemoryMin": "0", "MemorySwapMax": "infinity", "MountAPIVFS": "no", "MountFlags": "", "NFileDescriptorStore": "0", "NRestarts": "0", "NUMAMask": "", "NUMAPolicy": "n/a", "Names": "confluent-kcontroller.service", "NeedDaemonReload": "no", "Nice": "0", "NoNewPrivileges": "no", "NonBlocking": "no", "NotifyAccess": "none", "OOMPolicy": "stop", "OOMScoreAdjust": "0", "OnFailureJobMode": "replace", "Perpetual": "no", "PrivateDevices": "no", "PrivateMounts": "no", "PrivateNetwork": "no", "PrivateTmp": "no", "PrivateUsers": "no", "ProtectControlGroups": "no", "ProtectHome": "no", "ProtectHostname": "no", "ProtectKernelLogs": "no", "ProtectKernelModules": "no", "ProtectKernelTunables": "no", "ProtectSystem": "no", "RefuseManualStart": "no", "RefuseManualStop": "no", "ReloadResult": "success", "RemainAfterExit": "no", "RemoveIPC": "no", "Requires": "sysinit.target system.slice", "Restart": "no", "RestartKillSignal": "15", "RestartUSec": "100ms", "RestrictNamespaces": "no", "RestrictRealtime": "no", "RestrictSUIDSGID": "no", "Result": "success", "RootDirectoryStartOnly": "no", "RuntimeDirectoryMode": "0755", "RuntimeDirectoryPreserve": "no", "RuntimeMaxUSec": "infinity", "SameProcessGroup": "no", "SecureBits": "0", "SendSIGHUP": "no", "SendSIGKILL": "yes", "Slice": "system.slice", "StandardError": "inherit", "StandardInput": "null", "StandardInputData": "", "StandardOutput": "journal", "StartLimitAction": "none", "StartLimitBurst": "5", "StartLimitIntervalUSec": "10s", "StartupBlockIOWeight": "[not set]", "StartupCPUShares": "[not set]", "StartupCPUWeight": "[not set]", "StartupIOWeight": "[not set]", "StateChangeTimestamp": "Thu 2024-10-17 16:32:37 CEST", "StateChangeTimestampMonotonic": "28526172406", "StateDirectoryMode": "0755", "StatusErrno": "0", "StopWhenUnneeded": "no", "SubState": "running", "SuccessAction": "none", "SyslogFacility": "3", "SyslogLevel": "6", "SyslogLevelPrefix": "yes", "SyslogPriority": "30", "SystemCallErrorNumber": "0", "TTYReset": "no", "TTYVHangup": "no", "TTYVTDisallocate": "no", "TasksAccounting": "yes", "TasksCurrent": "81", "TasksMax": "38494", "TimeoutAbortUSec": "3min", "TimeoutCleanUSec": "infinity", "TimeoutStartUSec": "1min 30s", "TimeoutStopUSec": "3min", "TimerSlackNSec": "50000", "Transient": "no", "Type": "simple", "UID": "110", "UMask": "0022", "UnitFilePreset": "enabled", "UnitFileState": "enabled", "User": "cp-kafka", "UtmpMode": "init", "WantedBy": "multi-user.target", "WatchdogSignal": "6", "WatchdogTimestampMonotonic": "0", "WatchdogUSec": "0"}}

TASK [Startup Delay for Kafka Controllers] *************************************
ok: [kafka-controller-1] => (item=kafka-controller-1) => {"ansible_loop_var": "item", "changed": false, "elapsed": 20, "item": "kafka-controller-1", "match_groupdict": {}, "match_groups": [], "path": null, "port": null, "search_regex": null, "state": "started"}
ok: [kafka-controller-1 -> kafka-controller-2(localhost)] => (item=kafka-controller-2) => {"ansible_loop_var": "item", "changed": false, "elapsed": 20, "item": "kafka-controller-2", "match_groupdict": {}, "match_groups": [], "path": null, "port": null, "search_regex": null, "state": "started"}
ok: [kafka-controller-1 -> kafka-controller-3-migrated(localhost)] => (item=kafka-controller-3-migrated) => {"ansible_loop_var": "item", "changed": false, "elapsed": 20, "item": "kafka-controller-3-migrated", "match_groupdict": {}, "match_groups": [], "path": null, "port": null, "search_regex": null, "state": "started"}

TASK [Restart Kafka Broker] ****************************************************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
changed: [kafka-broker-1] => {"changed": true, "name": "confluent-server", "state": "started", "status": {"ActiveEnterTimestamp": "Thu 2024-10-17 16:14:31 CEST", "ActiveEnterTimestampMonotonic": "27440090889", "ActiveExitTimestampMonotonic": "0", "ActiveState": "active", "After": "basic.target systemd-journald.socket sysinit.target system.slice confluent-zookeeper.target network.target", "AllowIsolate": "no", "AllowedCPUs": "", "AllowedMemoryNodes": "", "AmbientCapabilities": "", "AssertResult": "yes", "AssertTimestamp": "Thu 2024-10-17 16:14:31 CEST", "AssertTimestampMonotonic": "27440078227", "Before": "multi-user.target shutdown.target", "BlockIOAccounting": "no", "BlockIOWeight": "[not set]", "CPUAccounting": "no", "CPUAffinity": "", "CPUAffinityFromNUMA": "no", "CPUQuotaPerSecUSec": "infinity", "CPUQuotaPeriodUSec": "infinity", "CPUSchedulingPolicy": "0", "CPUSchedulingPriority": "0", "CPUSchedulingResetOnFork": "no", "CPUShares": "[not set]", "CPUUsageNSec": "[not set]", "CPUWeight": "[not set]", "CacheDirectoryMode": "0755", "CanIsolate": "no", "CanReload": "no", "CanStart": "yes", "CanStop": "yes", "CapabilityBoundingSet": "cap_chown cap_dac_override cap_dac_read_search cap_fowner cap_fsetid cap_kill cap_setgid cap_setuid cap_setpcap cap_linux_immutable cap_net_bind_service cap_net_broadcast cap_net_admin cap_net_raw cap_ipc_lock cap_ipc_owner cap_sys_module cap_sys_rawio cap_sys_chroot cap_sys_ptrace cap_sys_pacct cap_sys_admin cap_sys_boot cap_sys_nice cap_sys_resource cap_sys_time cap_sys_tty_config cap_mknod cap_lease cap_audit_write cap_audit_control cap_setfcap cap_mac_override cap_mac_admin cap_syslog cap_wake_alarm cap_block_suspend cap_audit_read 0x26 0x27 0x28", "CleanResult": "success", "CollectMode": "inactive", "ConditionResult": "yes", "ConditionTimestamp": "Thu 2024-10-17 16:14:31 CEST", "ConditionTimestampMonotonic": "27440078226", "ConfigurationDirectoryMode": "0755", "Conflicts": "shutdown.target", "ControlGroup": "/docker/06ae2d1dfd2ac24c1206ea41282dec31c11d78000a879fc26a4c0727e4d37bfc/system.slice/confluent-server.service", "ControlPID": "0", "DefaultDependencies": "yes", "DefaultMemoryLow": "0", "DefaultMemoryMin": "0", "Delegate": "no", "Description": "Apache Kafka - broker", "DevicePolicy": "auto", "Documentation": "http://docs.confluent.io/", "DropInPaths": "/etc/systemd/system/confluent-server.service.d/override.conf", "DynamicUser": "no", "EffectiveCPUs": "", "EffectiveMemoryNodes": "", "Environment": "[unprintable] KAFKA_LOG4J_OPTS=-Dlog4j.configuration=file:/etc/kafka/log4j.properties LOG_DIR=/var/log/kafka", "ExecMainCode": "0", "ExecMainExitTimestampMonotonic": "0", "ExecMainPID": "6356", "ExecMainStartTimestamp": "Thu 2024-10-17 16:14:31 CEST", "ExecMainStartTimestampMonotonic": "27440090685", "ExecMainStatus": "0", "ExecStart": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/kafka/server.properties ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "ExecStartEx": "{ path=/usr/bin/kafka-server-start ; argv[]=/usr/bin/kafka-server-start /etc/kafka/server.properties ; flags= ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }", "FailureAction": "none", "FileDescriptorStoreMax": "0", "FinalKillSignal": "9", "FragmentPath": "/lib/systemd/system/confluent-server.service", "GID": "107", "Group": "confluent", "GuessMainPID": "yes", "IOAccounting": "no", "IOReadBytes": "18446744073709551615", "IOReadOperations": "18446744073709551615", "IOSchedulingClass": "0", "IOSchedulingPriority": "0", "IOWeight": "[not set]", "IOWriteBytes": "18446744073709551615", "IOWriteOperations": "18446744073709551615", "IPAccounting": "no", "IPEgressBytes": "[no data]", "IPEgressPackets": "[no data]", "IPIngressBytes": "[no data]", "IPIngressPackets": "[no data]", "Id": "confluent-server.service", "IgnoreOnIsolate": "no", "IgnoreSIGPIPE": "yes", "InactiveEnterTimestampMonotonic": "0", "InactiveExitTimestamp": "Thu 2024-10-17 16:14:31 CEST", "InactiveExitTimestampMonotonic": "27440090889", "InvocationID": "431a12c36fcf4cf0b6d141a952a58470", "JobRunningTimeoutUSec": "infinity", "JobTimeoutAction": "none", "JobTimeoutUSec": "infinity", "KeyringMode": "private", "KillMode": "control-group", "KillSignal": "15", "LimitAS": "infinity", "LimitASSoft": "infinity", "LimitCORE": "infinity", "LimitCORESoft": "infinity", "LimitCPU": "infinity", "LimitCPUSoft": "infinity", "LimitDATA": "infinity", "LimitDATASoft": "infinity", "LimitFSIZE": "infinity", "LimitFSIZESoft": "infinity", "LimitLOCKS": "infinity", "LimitLOCKSSoft": "infinity", "LimitMEMLOCK": "8388608", "LimitMEMLOCKSoft": "8388608", "LimitMSGQUEUE": "819200", "LimitMSGQUEUESoft": "819200", "LimitNICE": "0", "LimitNICESoft": "0", "LimitNOFILE": "1000000", "LimitNOFILESoft": "1000000", "LimitNPROC": "infinity", "LimitNPROCSoft": "infinity", "LimitRSS": "infinity", "LimitRSSSoft": "infinity", "LimitRTPRIO": "0", "LimitRTPRIOSoft": "0", "LimitRTTIME": "infinity", "LimitRTTIMESoft": "infinity", "LimitSIGPENDING": "128316", "LimitSIGPENDINGSoft": "128316", "LimitSTACK": "infinity", "LimitSTACKSoft": "8388608", "LoadState": "loaded", "LockPersonality": "no", "LogLevelMax": "-1", "LogRateLimitBurst": "0", "LogRateLimitIntervalUSec": "0", "LogsDirectoryMode": "0755", "MainPID": "6356", "MemoryAccounting": "yes", "MemoryCurrent": "1464500224", "MemoryDenyWriteExecute": "no", "MemoryHigh": "infinity", "MemoryLimit": "infinity", "MemoryLow": "0", "MemoryMax": "infinity", "MemoryMin": "0", "MemorySwapMax": "infinity", "MountAPIVFS": "no", "MountFlags": "", "NFileDescriptorStore": "0", "NRestarts": "0", "NUMAMask": "", "NUMAPolicy": "n/a", "Names": "confluent-server.service", "NeedDaemonReload": "no", "Nice": "0", "NoNewPrivileges": "no", "NonBlocking": "no", "NotifyAccess": "none", "OOMPolicy": "stop", "OOMScoreAdjust": "0", "OnFailureJobMode": "replace", "Perpetual": "no", "PrivateDevices": "no", "PrivateMounts": "no", "PrivateNetwork": "no", "PrivateTmp": "no", "PrivateUsers": "no", "ProtectControlGroups": "no", "ProtectHome": "no", "ProtectHostname": "no", "ProtectKernelLogs": "no", "ProtectKernelModules": "no", "ProtectKernelTunables": "no", "ProtectSystem": "no", "RefuseManualStart": "no", "RefuseManualStop": "no", "ReloadResult": "success", "RemainAfterExit": "no", "RemoveIPC": "no", "Requires": "sysinit.target system.slice", "Restart": "no", "RestartKillSignal": "15", "RestartUSec": "100ms", "RestrictNamespaces": "no", "RestrictRealtime": "no", "RestrictSUIDSGID": "no", "Result": "success", "RootDirectoryStartOnly": "no", "RuntimeDirectoryMode": "0755", "RuntimeDirectoryPreserve": "no", "RuntimeMaxUSec": "infinity", "SameProcessGroup": "no", "SecureBits": "0", "SendSIGHUP": "no", "SendSIGKILL": "yes", "Slice": "system.slice", "StandardError": "inherit", "StandardInput": "null", "StandardInputData": "", "StandardOutput": "journal", "StartLimitAction": "none", "StartLimitBurst": "5", "StartLimitIntervalUSec": "10s", "StartupBlockIOWeight": "[not set]", "StartupCPUShares": "[not set]", "StartupCPUWeight": "[not set]", "StartupIOWeight": "[not set]", "StateChangeTimestamp": "Thu 2024-10-17 16:14:31 CEST", "StateChangeTimestampMonotonic": "27440090889", "StateDirectoryMode": "0755", "StatusErrno": "0", "StopWhenUnneeded": "no", "SubState": "running", "SuccessAction": "none", "SyslogFacility": "3", "SyslogLevel": "6", "SyslogLevelPrefix": "yes", "SyslogPriority": "30", "SystemCallErrorNumber": "0", "TTYReset": "no", "TTYVHangup": "no", "TTYVTDisallocate": "no", "TasksAccounting": "yes", "TasksCurrent": "151", "TasksMax": "38494", "TimeoutAbortUSec": "3min", "TimeoutCleanUSec": "infinity", "TimeoutStartUSec": "1min 30s", "TimeoutStopUSec": "3min", "TimerSlackNSec": "50000", "Transient": "no", "Type": "simple", "UID": "110", "UMask": "0022", "UnitFilePreset": "enabled", "UnitFileState": "enabled", "User": "cp-kafka", "UtmpMode": "init", "WantedBy": "multi-user.target", "WatchdogSignal": "6", "WatchdogTimestampMonotonic": "0", "WatchdogUSec": "0"}}

TASK [Startup Delay for Kafka Broker] ******************************************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
ok: [kafka-broker-1] => {"changed": false, "elapsed": 20, "match_groupdict": {}, "match_groups": [], "path": null, "port": null, "search_regex": null, "state": "started"}

TASK [Verify Metadata Synchronization] *****************************************
skipping: [kafka-controller-1] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-2] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
skipping: [kafka-controller-3-migrated] => {"changed": false, "false_condition": "inventory_hostname == 'kafka-broker-1'", "skip_reason": "Conditional result was False"}
changed: [kafka-broker-1] => {"changed": true, "cmd": ["kafka-metadata-quorum", "--bootstrap-server", "kafka-broker-1:9092", "describe", "--status"], "delta": "0:00:01.634487", "end": "2024-10-17 16:34:47.270354", "msg": "", "rc": 0, "start": "2024-10-17 16:34:45.635867", "stderr": "", "stderr_lines": [], "stdout": "ClusterId:              gKP1yNTvTvqf4ICEYzpYsg\nLeaderId:               9991\nLeaderEpoch:            5\nHighWatermark:          5342\nMaxFollowerLag:         0\nMaxFollowerLagTimeMs:   0\nCurrentVoters:          [9991,9992,9993]\nCurrentObservers:       [1]", "stdout_lines": ["ClusterId:              gKP1yNTvTvqf4ICEYzpYsg", "LeaderId:               9991", "LeaderEpoch:            5", "HighWatermark:          5342", "MaxFollowerLag:         0", "MaxFollowerLagTimeMs:   0", "CurrentVoters:          [9991,9992,9993]", "CurrentObservers:       [1]"]}

TASK [Display Metadata Synchronization Output Nicely] **************************
skipping: [kafka-controller-1] => {"false_condition": "metadata_status is defined and inventory_hostname == 'kafka-broker-1'"}
skipping: [kafka-controller-2] => {"false_condition": "metadata_status is defined and inventory_hostname == 'kafka-broker-1'"}
skipping: [kafka-controller-3] => {"false_condition": "metadata_status is defined and inventory_hostname == 'kafka-broker-1'"}
skipping: [kafka-controller-3-migrated] => {"false_condition": "metadata_status is defined and inventory_hostname == 'kafka-broker-1'"}
ok: [kafka-broker-1] => {
    "msg": "ClusterId:              gKP1yNTvTvqf4ICEYzpYsg\nLeaderId:               9991\nLeaderEpoch:            5\nHighWatermark:          5342\nMaxFollowerLag:         0\nMaxFollowerLagTimeMs:   0\nCurrentVoters:          [9991,9992,9993]\nCurrentObservers:       [1]"
}

TASK [Log Quorum Status and Replica (After Migration)] *************************
changed: [kafka-controller-1 -> kafka-broker-1(localhost)] => {"changed": true, "cmd": "kafka-metadata-quorum --bootstrap-server kafka-controller-1:9093 describe --status \n", "delta": "0:00:01.635054", "end": "2024-10-17 16:34:49.295676", "msg": "", "rc": 0, "start": "2024-10-17 16:34:47.660622", "stderr": "", "stderr_lines": [], "stdout": "ClusterId:              gKP1yNTvTvqf4ICEYzpYsg\nLeaderId:               9991\nLeaderEpoch:            5\nHighWatermark:          5346\nMaxFollowerLag:         0\nMaxFollowerLagTimeMs:   0\nCurrentVoters:          [9991,9992,9993]\nCurrentObservers:       [1]", "stdout_lines": ["ClusterId:              gKP1yNTvTvqf4ICEYzpYsg", "LeaderId:               9991", "LeaderEpoch:            5", "HighWatermark:          5346", "MaxFollowerLag:         0", "MaxFollowerLagTimeMs:   0", "CurrentVoters:          [9991,9992,9993]", "CurrentObservers:       [1]"]}

TASK [Save Quorum Status and Replica Before Migration to Localhost in One Task] ***
changed: [kafka-controller-2 -> localhost] => {"changed": true, "checksum": "1853ce09cc705bf5514100b2c8657876918f5ca4", "dest": "./quorum_status_after_migration.log", "gid": 0, "group": "root", "md5sum": "43294072c34eacc0c7bc78b6f96b69e0", "mode": "0644", "owner": "root", "size": 251, "src": "/home/ubuntu/.ansible/tmp/ansible-tmp-1729175689.3719938-437331-199781479709008/.source.log", "state": "file", "uid": 0}
ok: [kafka-controller-1 -> localhost] => {"changed": false, "checksum": "1853ce09cc705bf5514100b2c8657876918f5ca4", "dest": "./quorum_status_after_migration.log", "gid": 0, "group": "root", "md5sum": "43294072c34eacc0c7bc78b6f96b69e0", "mode": "0644", "owner": "root", "size": 251, "src": "/home/ubuntu/.ansible/tmp/ansible-tmp-1729175689.3583071-437330-239198484466654/.source.log", "state": "file", "uid": 0}
ok: [kafka-controller-3-migrated -> localhost] => {"changed": false, "checksum": "1853ce09cc705bf5514100b2c8657876918f5ca4", "dest": "./quorum_status_after_migration.log", "gid": 0, "group": "root", "md5sum": "43294072c34eacc0c7bc78b6f96b69e0", "mode": "0644", "owner": "root", "size": 251, "src": "/home/ubuntu/.ansible/tmp/ansible-tmp-1729175689.4159844-437383-929928767339/.source.log", "state": "file", "uid": 0}
ok: [kafka-controller-3 -> localhost] => {"changed": false, "checksum": "1853ce09cc705bf5514100b2c8657876918f5ca4", "dest": "./quorum_status_after_migration.log", "gid": 0, "group": "root", "md5sum": "43294072c34eacc0c7bc78b6f96b69e0", "mode": "0644", "owner": "root", "size": 251, "src": "/home/ubuntu/.ansible/tmp/ansible-tmp-1729175689.3841753-437344-175352004667751/.source.log", "state": "file", "uid": 0}
ok: [kafka-broker-1 -> localhost] => {"changed": false, "checksum": "1853ce09cc705bf5514100b2c8657876918f5ca4", "dest": "./quorum_status_after_migration.log", "gid": 0, "group": "root", "md5sum": "43294072c34eacc0c7bc78b6f96b69e0", "mode": "0644", "owner": "root", "size": 251, "src": "/home/ubuntu/.ansible/tmp/ansible-tmp-1729175689.4268172-437397-10139037964509/.source.log", "state": "file", "uid": 0}

PLAY RECAP *********************************************************************
kafka-broker-1             : ok=10   changed=3    unreachable=0    failed=0    skipped=43   rescued=0    ignored=0   
kafka-controller-1         : ok=12   changed=4    unreachable=0    failed=0    skipped=47   rescued=0    ignored=0   
kafka-controller-2         : ok=6    changed=3    unreachable=0    failed=0    skipped=47   rescued=0    ignored=0   
kafka-controller-3         : ok=6    changed=1    unreachable=0    failed=0    skipped=47   rescued=0    ignored=0   
kafka-controller-3-migrated : ok=77   changed=31   unreachable=0    failed=0    skipped=60   rescued=0    ignored=0   

Migration Playbook ran successfully!</pre>
</details>


## Cleanup
To stop all services:
```bash
docker-compose down
```


