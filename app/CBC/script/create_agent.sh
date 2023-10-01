#!/bin/bash -e

docker stop bridge-agent && docker rm bridge-agent

ENV_FILE=".env"
AGENT_CONTAINER="bridge-agent"
SCRIPT_HEADER="#!/bin/bash -e
#
#    © Copyright 2014 - 2022 Micro Focus or one of its affiliates.
#
#    The only warranties for products and services of Micro Focus and its affiliates
#    and licensors (\"Micro Focus\") are as may be set forth in the express warranty
#    statements accompanying such products and services. Nothing herein should be
#    construed as constituting an additional warranty. Micro Focus shall not be
#    liable for technical or editorial errors or omissions contained herein.
#    The information contained herein is subject to change without notice.
#
"

echo "Starting agent"
add_bootstrapPassword()
{
  echo  "BOOTSTRAP_PWD=""$bootstrapPassword" >> $ENV_FILE
}

add_bootstrapUser()
{
  echo "BOOTSTRAP_USER=""$bootstrapUser" >> $ENV_FILE
}
add_username()
{
   dbusername=$(head /dev/urandom | tr -dc a-z | head -c 9 | base64 | base64 -d)
   echo "DBA_USER=""$dbusername" >> $ENV_FILE
}

add_password()
{
   dbpassword=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 9 | base64 | base64 -d)
   echo "DB_PASSWORD=""$dbpassword" >> $ENV_FILE
}

add_crypto_values()
{

  if [ "${doHaMode}" == "false" ]; then
      echo "version older than 1.8.4"
  else
      echo "1.8.4 or newer version"
  fi

  if [ -z "$(grep '^KEY=' "$ENV_FILE")" ]; then
      if [ -f "${PWD}/conf/key.temp" ]; then
        rm -f "${PWD}/conf/key.temp"
      fi
    if [ "${doHaMode}" == "false" ]; then
        echo "handling pre HA image"
        $container_mgr run --name agent-crypto-key \
          -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
          --env-file .env \
          129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
          crypto key /conf/bridge-agent.yml
        cryptoKey=$($container_mgr logs agent-crypto-key | tail -n 1)
        echo "KEY=""$cryptoKey" >> $ENV_FILE
    else
      $container_mgr run --name agent-crypto-key \
        -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
        --env-file .env \
        129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
        java -jar /bridge-agent.jar crypto key /conf/bridge-agent.yml

      cat "${PWD}/conf/key.temp" >> $ENV_FILE
      echo "" >> $ENV_FILE
      if [ -f "${PWD}/conf/key.temp" ]; then
        rm -f "${PWD}/conf/key.temp"
      fi
    fi
      $container_mgr container rm agent-crypto-key
  fi

  if [ -z "$(grep '^IV=' "$ENV_FILE")" ]; then
      if [ -f "${PWD}/conf/iv.temp" ]; then
        rm -f "${PWD}/conf/iv.temp"
      fi
    if [ "${doHaMode}" == "false" ]; then
      echo "handling pre HA image"
      $container_mgr run --name agent-crypto-iv \
        -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
        --env-file .env \
        129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
        crypto iv /conf/bridge-agent.yml
        cryptoIV=$($container_mgr logs agent-crypto-iv 2> /dev/null | tail -n 1)
        echo "IV=""$cryptoIV" >> $ENV_FILE
        echo "" >> $ENV_FILE
    else
      $container_mgr run --name agent-crypto-iv \
        -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
        --env-file .env \
        129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
        java -jar /bridge-agent.jar crypto iv /conf/bridge-agent.yml
        cat "${PWD}/conf/iv.temp" >> $ENV_FILE
        echo "" >> $ENV_FILE
        if [ -f "${PWD}/conf/iv.temp" ]; then
          rm -f "${PWD}/conf/iv.temp"
        fi
    fi
      $container_mgr container rm agent-crypto-iv
  fi
}

read_var() {
    VAR=$(grep "$1" "$2" | xargs)
    IFS="=" read -ra VAR <<< "$VAR"
    echo "${VAR[1]}"
}

initial_setup()
{
   # Remove possible existing containers, don't exit on error.
   # This avoids name collisions. Containers must be removed individually because
   # podman will exit on first non-existing container. This is generally only
   # needed during development and testing.
   set +e
   $container_mgr container rm agent-crypto-iv &> /dev/null
   $container_mgr container rm agent-crypto-key &> /dev/null
   $container_mgr container rm agent-db-init &> /dev/null
   $container_mgr container rm agent-credential &> /dev/null
   $container_mgr container rm bridge-agent-import &> /dev/null
   $container_mgr stop bridge-agent &> /dev/null
   $container_mgr container rm bridge-agent &> /dev/null
   set -e

   if [ "$do_upgrade" == "n" ] && [ -f $ENV_FILE ]; then
     rm $ENV_FILE
   fi


   if [ ! -f $ENV_FILE ]; then
       > $ENV_FILE
       add_username
       add_password
       add_bootstrapUser
       add_bootstrapPassword
       echo "KEYSTORE_PWD=changeme" >> $ENV_FILE
       chmod 0600 $ENV_FILE
   else
       if [ -z "$(grep '^DBA_USER=' "$ENV_FILE")" ]; then
          add_username
       else
         dbusername=$(read_var "DBA_USER" $ENV_FILE)
       fi

       if [ -z "$(grep '^DB_PASSWORD=' $ENV_FILE)" ]; then
           add_password
       else
         dbpassword=$(read_var "DB_PASSWORD" "$ENV_FILE")
       fi

       if [ -z "$(grep '^BOOTSTRAP_USER=' "$ENV_FILE")" ]; then
         add_bootstrapUser
       fi

       if [ -z "$(grep '^BOOTSTRAP_PWD=' "$ENV_FILE")" ]; then
         add_bootstrapPassword
       fi

       if [ -z "$(grep '^KEYSTORE_PWD=' "$ENV_FILE")" ]; then
         echo "KEYSTORE_PWD=changeme" >> $ENV_FILE
       fi
   fi
   add_crypto_values
}

check_required_dep()
{
    if [ -z "$(which "$1")" ]; then
        echo "[" "$1" "] - a required dependency was not found"
        missing_dependencies="yes"
    fi
}

check_for_container_mgr()
{
    if [ -z "$(which "$1")" ]; then
        missing_dependencies="yes"
    fi
}

check_docker_version()
{
    supported_docker_ver="19.03"

    mod_name="docker"

    mod_exe=$(which $mod_name)
    mod_ver=$($mod_exe -v | awk '{print $3}')
    mod_ver=$(echo "${mod_ver//,}")

    if [ "$mod_ver" \> $supported_docker_ver ] || [ "$mod_ver" = $supported_docker_ver ]
    then
        echo "Using docker version: $mod_ver"
    else
        echo "Your version of $mod_exe must be $supported_docker_ver or higher"
        echo "Please upgrade it and continue the Cloud Bridge Agent installation"
        exit 1
    fi
}

check_podman_version()
{
    supported_podman_ver="1.6.4"

    mod_name="podman"

    mod_exe=$(which $mod_name)
    mod_ver=$($mod_exe -v | awk '{print $3}')
    mod_ver=$(echo "${mod_ver//,}")

    if [ "$mod_ver" \> $supported_podman_ver ] || [ "$mod_ver" = $supported_podman_ver ]
    then
        echo "Using podman version: $mod_ver"
    else
        echo "Your version of $mod_exe must be supported_podman_ver or higher"
        echo "Please upgrade it and continue the Cloud Bridge Agent installation"
        exit 1
    fi
}

exitWithImageVersionError()
{
    echo "The agent image version must be 1.8.1 or greater."
    exit 1
}

check_agent_image_version()
{
    #agent must be 1.8.1 or higher
    #parse this: <image name>:<image tag> where image tag is like 1.8.1-<SNAPSHOT|<build number>>

    #remember current IFS (Internal Field Separator) value
    old_ifs="$IFS"
    # Set colon as delimiter
    IFS=':'

    #split agentImage into an array based on colon delimiter
    read -ra fullImageArray <<< "129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871"
    fullImageArrayLength=${#fullImageArray[@]}
    if [[ ${fullImageArrayLength} -ne 2 ]]; then
        echo "The agent image name and tag is an invalid format: 129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871"
        exit 1
    fi

    #set period as delimiter
    IFS='.'
    read -ra versionarray <<< "${fullImageArray[1]}"

    versionLength=${#versionarray[@]}

    if [[ ${versionLength} -lt 3  ]] || [[ ${versionLength} -gt 4 ]]; then
        echo "The agent image tag is an invalid format: ""${fullImageArray[-1]}"
        exit 1
    fi

    majorValue=${versionarray[0]}
    minorValue=${versionarray[1]}

    #set dash as delimeter
    IFS='-'
    read -ra patcharray <<< "${versionarray[2]}"
    patchValue=patcharray[0]

    #restore old IFS value so later script parsing works correctly
    IFS="$old_ifs"

    #check that version is 1.8.1 or greater
    if [[ ${majorValue} -lt 1  ]]; then
        exitWithImageVersionError
    fi

    if [[ ${majorValue} -eq 1  ]]; then
        if [[ ${minorValue} -lt 8 ]]; then
            exitWithImageVersionError
        fi
        if [[ ${minorValue} -eq 8 ]]; then
            if [[ ${patchValue} -lt 1 ]]; then
                exitWithImageVersionError
            fi
        fi
        # forward looking. handle 1.9.0 versions
        if [[ ${minorValue} -eq 9 ]]; then
            if [[ ${patchValue} -lt 0 ]]; then
                exitWithImageVersionError
            fi
        fi
    fi
}

check_for_upgrade()
{
  $container_mgr ps -a > temp.out
  if grep -q " bridge-agent" temp.out; then
    echo "have_bridge_agent_container"
    have_bridge_agent_container="yes"
  fi

  if grep -q "agent_agent_1" temp.out; then
    echo "have_agent_agent_1_container"
    have_agent_agent_1_container="yes"
  fi

  rm temp.out

  if [ "${have_agent_agent_1_container}" == "yes" ] || [ "${have_bridge_agent_container}" == "yes" ]; then
    echo
    echo "A previous version of the cloud bridge agent was detected. If you"
    echo "choose to upgrade this version, stored LDAP credentials and"
    echo "agent administrator users will be preserved. If you choose not to"
    echo "upgrade then stored LDAP credentials and agent administrator users"
    echo "will be deleted and will need to be recreated after the installation."
    echo
    while true; do
      read -rp "Do you want to upgrade the previous version of the Cloud Bridge agent? <y,n> " do_upgrade
      if [[ "${do_upgrade}" == "y" || "${do_upgrade}" == "n" ]]; then
        break;
      fi
    done
    #confirm the no upgrade choice
    if [ "$do_upgrade" == "n" ]; then
      while true; do
        read -rp "All stored LDAP credentials and agent administrator users will be deleted. Continue? <y,n> " do_continue
        if [ "$do_continue" == "n" ]; then
          exit 0;
        elif [ "$do_continue" == "y" ]; then
          break;
        fi
      done
    fi
  else
    do_upgrade="n"
  fi
}

#Start execution here
# Validating required dependencies awk and wget
set +v

check_required_dep "awk"
check_required_dep "wget"

if [[ $missing_dependencies == "yes" ]]; then
    echo "The script failed because there were missing dependencies."
    echo "Please install the missing components and try again."
    exit 1
fi

check_agent_image_version

## begin ha section
instanceWeight=""



releaseVersion=${versionarray[2]}
releaseDigit=$(echo "$releaseVersion" | cut -d '-' -f1)

doHaMode=false

if [[ ${releaseDigit} -gt 3 ]] || [[ ${minorValue} -gt 8 ]]; then
    echo "CBA version enabled for HA"

  ## begin siteWeight
    doHaModesite=false
    haModeSite=-1

    if [ $haModeSite -lt 0 ]; then
      while [[ $doHaModesite == false ]]; do
          echo "This CBA site role?: "
          echo "    0) *Primary"
          echo "    1) Secondary"
          echo "    2) Backup"
        haModeSite=0
        if [[ -z "$haModeSite" ]]; then
              haModeSite=0
              echo "CBA site role: PRIMARY"
              siteWeight="PRIMARY"
              doHaModesite=true
        fi
        if [[ $haModeSite =~ ^[+-]?[0-9]+$ ]]; then
            if [ "$haModeSite" -eq 0 ]; then
              haModeSite=0
              echo "CBA site role: PRIMARY"
              siteWeight="PRIMARY"
              doHaModesite=true
            elif [ "$haModeSite" -eq 1 ]; then
              haModeSite=1
              echo "CBA site role: SECONDARY"
              siteWeight="SECONDARY"
              doHaModesite=true
            elif [ "$haModeSite" -eq 2 ]; then
              haModeSite=2
              echo "CBA site role: BACKUP"
              siteWeight="BACKUP"
              doHaModesite=true
            else
              echo "Input out of scope. Try again."
              haModeSite=-1
              doHaModesite=false
            fi
        else
            echo "Input not a number. Try again"
            haModeSite=-1
            doHaModesite=false
        fi

      done
    fi
    ## end instanceWeight
         ## begin instanceWeight
        doHaMode=false
        haMode=-1

        if [ $haMode -lt 0 ]; then
          while [[ $doHaMode == false ]]; do
            echo "This CBA-HA instance role?: "
            echo "    0) *Primary"
            echo "    1) Secondary"
            echo "    2) Backup"
            haMode=0
            if [[ -z "$haMode" ]]; then
                  haMode=0
                  echo "CBA instance role: PRIMARY"
                  instanceWeight="PRIMARY"
                  doHaMode=true
            fi
            if [[ $haMode =~ ^[+-]?[0-9]+$ ]]; then
                if [ "$haMode" -eq 0 ]; then
                  haMode=0
                  echo "CBA instance role: PRIMARY"
                  instanceWeight="PRIMARY"
                  doHaMode=true
                elif [ "$haMode" -eq 1 ]; then
                  haMode=1
                  echo "CBA instance role: SECONDARY"
                  instanceWeight="SECONDARY"
                  doHaMode=true
                elif [ "$haMode" -eq 2 ]; then
                  haMode=2
                  echo "CBA instance role: BACKUP"
                  instanceWeight="BACKUP"
                  doHaMode=true
                else
                  echo "Input out of scope. Try again."
                  haMode=-1
                  doHaMode=false
                fi
            else
                echo "Input not a number. Try again"
                haMode=-1
                doHaMode=false
            fi

          done
        fi
        echo ""
        ## end instanceWeight
    echo ""
    instanceIdString=""
    hostname=$(hostname)
    instanceIdDef=$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 5)

    echo "Enter the instanceId (name) of this CBA, or just hit enter to accept the default"
    echo ""
    if [ -f agent/conf/bridge-agent.yml ]; then
      hasAgent=$(grep -c instanceId agent/conf/bridge-agent.yml)
      if [[ ${hasAgent} -gt 0 ]]; then
        echo "existing instanceId: $(grep instanceId agent/conf/bridge-agent.yml | cut -d ' ' -f 2-)"
      fi
    fi

    if [[ ${hasAgent} -lt 1 ]]; then
      echo "instanceId: (""$hostname"-"$instanceIdDef"")"
    else
      echo "instanceId: ($(grep instanceId agent/conf/bridge-agent.yml | cut -d ' ' -f 2-))"
    fi
    instanceId=""
    if [[ -z "$instanceId" ]]; then
      if [[ ${hasAgent} -gt 0 ]]; then
        instanceIdString=$(grep instanceId agent/conf/bridge-agent.yml | cut -d ' ' -f 2-)
      else
        instanceIdString=$hostname-$instanceIdDef
      fi
    else
        instanceIdString=$instanceId
    fi

  if [ "${doHaMode}" == "false" ]; then
    echo "managing pre HA image"
  else
    echo "handling HA image"
    echo "instanceWeight: " $instanceWeight
    echo "siteWeight: " "$siteWeight"
    echo "instanceId: " "$instanceIdString"
  fi
fi

## end ha section

# Validating docker/podman versions
# in doc https://www.netiq.com/documentation/advanced-authentication-63/repo-agent-installation-guide/data/agent_install_and_uninstall_procedure.html
missing_dependencies="no"

check_for_container_mgr "podman"
container_mgr=""
podman_volume_option=""
if [[ $missing_dependencies == "no" ]]; then
    echo "podman found, will use it."
    container_mgr="podman"
    podman_volume_option=":Z"
    check_podman_version
else
  missing_dependencies="no"
  check_for_container_mgr "docker"
  if [[ $missing_dependencies == "yes" ]]; then
      echo "The script failed because a container manager could not be found."
      echo "Please install docker or podman and try again."
      exit 1
  else
    echo "docker found, will use it."
    container_mgr="docker"
    check_docker_version
  fi
fi

echo "check for previous download"
if [[ -f agent/bridge.tar.gz ]]; then
    echo "previous download found. removing..."
    rm -f agent/bridge.tar.gz
    echo "previous download removed"
fi

have_bridge_agent_container="no"
have_agent_agent_1_container="no"
do_upgrade="n"

check_for_upgrade

#set error handling
set -euo pipefail

[ ! -d agent ] && mkdir agent
cd agent

needToSetAdminCreds="true"

if [ "${do_upgrade}" == "y" ]; then
  #backup .env file
  if [ ! -f .env.bak ]; then
    cp .env .env.bak
  fi
  #check if we need agent admin user name or password
  if [ ! -z "$(grep '^BOOTSTRAP_PWD=' "$ENV_FILE")" ]; then
       if [ -z "$(grep '^BOOTSTRAP_USER=' "$ENV_FILE")" ]; then
         bootstrapUser="cbadmin"
       fi
       needToSetAdminCreds="false"
  fi
fi

if [ "${needToSetAdminCreds}" == "true" ]; then
  # get the username for the agent admin user (cbadmin)
  bootstrapUser="cbadmin"  #default value for pre agent version 1.7.0
  tempUserName="cbadmin"
  if [ "${tempUserName}" != "" ]; then
    bootstrapUser=$tempUserName;
  fi
  echo "Agent administrator username: ""$bootstrapUser"
  bootstrapPassword="noguessing"
  # get the password for the agent admin user
  # while true; do
  #     read -s -rp "Enter the password for the agent administrator user: " bootstrapPassword
  #     echo
  #     read -s -rp "Reenter password to confirm: " bootstrapPassword2
  #     echo
  #     [ "$bootstrapPassword" = "$bootstrapPassword2" ] && break || echo "Passwords do not match. Try again."
  # done
fi

if [[ "True" == "True" ]]; then
  #wget --continue https://microfocus-cloudbridgeagent.s3.us-east-2.amazonaws.com/dev/bridge-h2-1.10.0-871.tar.gz -O bridge.tar.gz
  $container_mgr load --input /tmp/bridge.tar.gz
else
  echo "Will attempt to pull from 129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871"
fi

mkdir -p conf
mkdir -p log
mkdir -p bridgelib

#preserve any custom settings from h2.yml
if [ -f conf/h2.yml ]; then
  if [ "${do_upgrade}" == "y" ]; then
    echo "moving existing h2.yml file";
    mv conf/h2.yml conf/bridge-agent.yml
  else
cat <<'EOF' > conf/bridge-agent.yml
kafkaClientProperties: /conf/DataCenter.json

encryptionKey: ${KEY}
encryptionIv: ${IV}
bootstrapUser: ${BOOTSTRAP_USER}
bootstrapPassword: ${BOOTSTRAP_PWD}

database:
  driverClass: org.h2.Driver
  url: jdbc:h2:/data/h2.bridge
  user: ${DBA_USER}
  password: ${DB_PASSWORD}
  properties:
    charSet: UTF-8
    hibernate.dialect: org.hibernate.dialect.H2Dialect
    foreign_keys: true
  maxWaitForConnection: 1s
  validationQuery: "/* Cloud Bridge Health Check */ SELECT 1"
  minSize: 8
  maxSize: 32
  checkConnectionWhileIdle: false

# Change default ports
server:
  applicationConnectors:
    - type: http
      port: 8080
  #  - type: https
  #    port: 8443
  #    keyStorePath: /conf/bridge.keystore
  #    keyStorePassword: ${KEYSTORE_PWD}
  adminConnectors:
    - type: http
      port: 8081
#  - type: https
#    port: 8444
#    keyStorePath: /conf/bridge.keystore
#    keyStorePassword: ${KEYSTORE_PWD}

  requestLog:
    appenders:
      - type: console

swagger:
  resourcePackage: com.netiq.daas.remote.resources
  uriPrefix: /api
  title: "Cloud Bridge Agent API"
  version: v1
  description: "REST API endpoints for the Cloud Bridge Agent"
  schemes:
    - http
    - https

logging:
  level: INFO
  loggers:
    com.netiq.daas: INFO
    com.netiq.daas.bridgeclient: DEBUG
    com.netiq.daas.bridgeclient.util: DEBUG
    com.netiq.daas.daaservice.RemoteService: DEBUG
    com.netiq.daas.daaservice.util.ServiceView: DEBUG
    com.netiq.daas.remote: DEBUG
    com.netiq.daas.remoteloaders: DEBUG
    org.apache.kafka: ERROR
    org.glassfish.jersey: ERROR
    org.hibernate: ERROR
    org.reflections: ERROR
    com.netiq.daas.remote.ManagedAgent: INFO
  appenders:
    - type: console
      threshold: ALL
      logFormat: "%-5p [%d{yyyy-MM-dd HH:mm:ss.SSS}] [%c] %m%n"

    - type: file
      threshold: ALL
      logFormat: "%-5p [%d{yyyy-MM-dd HH:mm:ss.SSS}] [%c] %m%n"
      currentLogFilename: /log/bridge-agent.log
      archivedLogFilenamePattern: /log/bridge-agent-%i.log.gz
      archivedFileCount: 7
      timeZone: UTC
      maxFileSize: 10MB
EOF
  fi
else
cat <<'EOF' > conf/bridge-agent.yml
kafkaClientProperties: /conf/DataCenter.json

encryptionKey: ${KEY}
encryptionIv: ${IV}
bootstrapUser: ${BOOTSTRAP_USER}
bootstrapPassword: ${BOOTSTRAP_PWD}

database:
  driverClass: org.h2.Driver
  url: jdbc:h2:/data/h2.bridge
  user: ${DBA_USER}
  password: ${DB_PASSWORD}
  properties:
    charSet: UTF-8
    hibernate.dialect: org.hibernate.dialect.H2Dialect
    foreign_keys: true
  maxWaitForConnection: 1s
  validationQuery: "/* Cloud Bridge Health Check */ SELECT 1"
  minSize: 8
  maxSize: 32
  checkConnectionWhileIdle: false

# Change default ports
server:
  applicationConnectors:
    - type: http
      port: 8080
  #  - type: https
  #    port: 8443
  #    keyStorePath: /conf/bridge.keystore
  #    keyStorePassword: ${KEYSTORE_PWD}
  adminConnectors:
    - type: http
      port: 8081
#  - type: https
#    port: 8444
#    keyStorePath: /conf/bridge.keystore
#    keyStorePassword: ${KEYSTORE_PWD}

  requestLog:
    appenders:
      - type: console

swagger:
  resourcePackage: com.netiq.daas.remote.resources
  uriPrefix: /api
  title: "Cloud Bridge Agent API"
  version: v1
  description: "REST API endpoints for the Cloud Bridge Agent"
  schemes:
    - http
    - https

logging:
  level: INFO
  loggers:
    com.netiq.daas: INFO
    com.netiq.daas.bridgeclient: DEBUG
    com.netiq.daas.bridgeclient.util: DEBUG
    com.netiq.daas.daaservice.RemoteService: DEBUG
    com.netiq.daas.daaservice.util.ServiceView: DEBUG
    com.netiq.daas.remote: DEBUG
    com.netiq.daas.remoteloaders: DEBUG
    org.apache.kafka: ERROR
    org.glassfish.jersey: ERROR
    org.hibernate: ERROR
    org.reflections: ERROR
    com.netiq.daas.remote.ManagedAgent: INFO
  appenders:
    - type: console
      threshold: ALL
      logFormat: "%-5p [%d{yyyy-MM-dd HH:mm:ss.SSS}] [%c] %m%n"

    - type: file
      threshold: ALL
      logFormat: "%-5p [%d{yyyy-MM-dd HH:mm:ss.SSS}] [%c] %m%n"
      currentLogFilename: /log/bridge-agent.log
      archivedLogFilenamePattern: /log/bridge-agent-%i.log.gz
      archivedFileCount: 7
      timeZone: UTC
      maxFileSize: 10MB
EOF
fi

initial_setup

    if [ "${doHaMode}" == "false" ]; then
      echo "handling pre HA image"
    else
    {
      echo "instanceWeight: "$instanceWeight;
      echo "siteWeight: ""$siteWeight"
      echo "instanceId: ""$instanceIdString"
    } >> conf/bridge-agent.yml
    fi

cat <<'EOF' >  conf/DataCenter.json
{
    "name": "Agent_ID",
    "uniqueId": "Agent_ID",
    "tenantId": "Tenant_ID",
    "description": "t1's cb",
    "commandTopic": "command_topic",
    "responseTopic": "response_topic",
    "kafkaPropertyList": {
        "kafkaProperties": [{
                "key": "bootstrap.servers",
                "value": "10.71.36.236:33093"
            }
        ]
    }
}
EOF

cat <<EOF > start.sh
${SCRIPT_HEADER}
${container_mgr} start ${AGENT_CONTAINER}
EOF

chmod 770 start.sh

cat <<EOF > stop.sh
${SCRIPT_HEADER}
${container_mgr} stop ${AGENT_CONTAINER}
EOF

chmod 770 stop.sh

cat <<EOF > remove.sh
${SCRIPT_HEADER}
${container_mgr} container rm ${AGENT_CONTAINER}
EOF

chmod 770 remove.sh

cat <<EOF > create.sh
${SCRIPT_HEADER}
${container_mgr} run -d --name ${AGENT_CONTAINER} \\
  --restart always \\
  --log-opt max-size=25m --log-opt max-file=10 \\
  -v data:/data${podman_volume_option} \\
  -v "${PWD}/conf:/conf${podman_volume_option}" \\
  -v "${PWD}/log:/log${podman_volume_option}" \\
  -v "${PWD}/bridgelib:/bridgelib${podman_volume_option}" \\
  --env-file "${PWD}/.env" \\
  -p "8080:8080" -p "8081:8081" \\
  129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871
EOF

chmod 770 create.sh

#do upgrade tasks here (migrate the database to embedded H2)
if [ "${do_upgrade}" == "y" ]; then
  if [ "${have_agent_agent_1_container}" == "yes" ]; then
    echo "Migrating from external database to embedded database"
    docker-compose exec db psql --dbname bridge --username "${dbusername}" -c "\copy (SELECT * FROM credential) to 'cred_export.csv' with csv header;"
    $container_mgr cp agent_db_1:cred_export.csv conf/cred_export.csv

    #bring the old agent down
    docker-compose down

    #create delete credentials script
    cat <<EOF > conf/delete.sql
DElETE FROM credential;
EOF
    #create csv import script
    cat <<EOF > conf/import.sql
INSERT INTO credential (uniqueid,username,password,credential_position) SELECT uniqueid,username,password,credential_position FROM CSVREAD('/conf/cred_export.csv');
EOF

    #initialize the new database
  if [ "${doHaMode}" == "false" ]; then
    echo "handling pre HA image"
    $container_mgr run --name agent-db-init \
      -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
      --env-file .env \
      129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
      db migrate /conf/bridge-agent.yml
  else
    $container_mgr run --name agent-db-init \
      -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
      --env-file .env \
      129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
      java -jar /bridge-agent.jar db migrate /conf/bridge-agent.yml
  fi

    $container_mgr container rm agent-db-init

    #clear the credential table in case the script gets run multiple times
  if [ "${doHaMode}" == "false" ]; then
    echo "handling pre HA image"
    $container_mgr run --name bridge-agent-clear-credentials --entrypoint 'java' \
      -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
      --env-file .env   -p "8080:8080" -p "8081:8081" \
      129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
      -cp bridge-agent.jar org.h2.tools.RunScript -script /conf/delete.sql -url "jdbc:h2:/data/h2.bridge" -user "$dbusername" -password "$dbpassword"
  else
    $container_mgr run --name bridge-agent-clear-credentials --entrypoint 'java' \
      -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
      --env-file .env   -p "8080:8080" -p "8081:8081" \
      129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
      java -jar /bridge-agent.jar -cp bridge-agent.jar org.h2.tools.RunScript -script /conf/delete.sql -url "jdbc:h2:/data/h2.bridge" -user "$dbusername" -password "$dbpassword"
  fi

    $container_mgr container rm bridge-agent-clear-credentials

    #import the csv file
    echo "Importing credentials."
  if [ "${doHaMode}" == "false" ]; then
    echo "handling pre HA image"
    $container_mgr run --name bridge-agent-import --entrypoint 'java' \
      -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
      --env-file .env   -p "8080:8080" -p "8081:8081" \
      129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
      -cp bridge-agent.jar org.h2.tools.RunScript -script /conf/import.sql -url "jdbc:h2:/data/h2.bridge" -user "$dbusername" -password "$dbpassword"
  else
    $container_mgr run --name bridge-agent-import --entrypoint 'java' \
      -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
      --env-file .env   -p "8080:8080" -p "8081:8081" \
      129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
      java -jar /bridge-agent.jar -cp bridge-agent.jar org.h2.tools.RunScript -script /conf/import.sql -url "jdbc:h2:/data/h2.bridge" -user "$dbusername" -password "$dbpassword"
  fi

    $container_mgr container rm bridge-agent-import
  else
      echo "upgrade: apply agent database updates"
      #"migrate" the database
      if [ "${doHaMode}" == "false" ]; then
        echo "handling pre HA image"
        $container_mgr run --name agent-db-init \
        -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
        --env-file .env \
        129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
        db migrate /conf/bridge-agent.yml
      else
        $container_mgr run --name agent-db-init \
        -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
        --env-file .env \
        129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
        java -jar /bridge-agent.jar db migrate /conf/bridge-agent.yml
      fi
      $container_mgr container rm agent-db-init
  fi
else
  #not an upgrade, remove the data volume so it will be recreated
  set +e #don't know if the volume is there or not so allow an error
  $container_mgr volume rm data &> /dev/null
  set -e

  if [ "${have_agent_agent_1_container}" == "yes" ]; then
    docker-compose down &> /dev/null
  fi

    #initialize the new database
    if [ "${doHaMode}" == "false" ]; then
      echo "handling pre HA image"
      $container_mgr run --name agent-db-init \
        -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
        --env-file .env \
        129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
        db migrate /conf/bridge-agent.yml
    else
      $container_mgr run --name agent-db-init \
        -v data:/data${podman_volume_option} -v "${PWD}/conf:/conf${podman_volume_option}" \
        --env-file .env \
        129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871 \
        java -jar /bridge-agent.jar db migrate /conf/bridge-agent.yml
    fi

  $container_mgr container rm agent-db-init
fi

#start the agent
if [ "${doHaMode}" == "false" ]; then
  echo "is an older version. copy the h2 file"
  cp conf/bridge-agent.yml conf/h2.yml
fi

#start the agent
$container_mgr run -d --name $AGENT_CONTAINER \
  --restart always \
  --log-opt max-size=25m --log-opt max-file=10 \
  -v data:/data${podman_volume_option} \
  -v "${PWD}/conf:/conf${podman_volume_option}" \
  -v "${PWD}/log:/log${podman_volume_option}" \
  -v "${PWD}/bridgelib:/bridgelib${podman_volume_option}" \
  --env-file .env \
  -p "8080:8080" -p "8081:8081" \
  129732931952.dkr.ecr.us-east-2.amazonaws.com/igaas/bridge-agent-h2:1.10.0-871


if [ "${do_upgrade}" == "y" ]; then
    echo "upgrade complete"
else
    echo "installation complete"
fi

echo "Creating Credentials"
HOST_IP=`hostname -I | awk '{print $1}'`

sleep 40

drivers=("azure" "salesforce" "workday" "active"  "service" "dtd" "scim" "soap" "rest" "ldap" "jdbc" "jms" )
for driver in "${drivers[@]}"
do
        driverID=Agent_ID"_"$driver
        curl --location "http://$HOST_IP:8080/api/v1/credential" \
--header 'Content-Type: application/json' \
--header 'Authorization: Basic Y2JhZG1pbjpub2d1ZXNzaW5n' \
--data '{
  "credentials": [
    {
      "password": "novell",
      "externalId": "'$driverID'",
      "username": "driver",
      "description": "unique id for driver '$driver'",
      "ordinal": 0
    }
  ]
}
'
        curl --location "http://$HOST_IP:8080/api/v1/credential" \
--header 'Content-Type: application/json' \
--header 'Authorization: Basic Y2JhZG1pbjpub2d1ZXNzaW5n' \
--data '{
  "credentials": [
    {
      "password": "novell",
      "externalId": "'$driverID'",
      "username": "remote",
      "description": "unique id for driver '$driver'",
      "ordinal": 1
    }
]
}
'
done
echo "Successfully created credentials!!"

docker cp /tmp/docker cp daas-rl-connector-1.0.0-20230720.215421-14.jar bridge-agent:/bridgelib