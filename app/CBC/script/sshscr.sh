#!/bin/bash

# Replace with your remote server IP and script path
REMOTE_SERVER="hostip"
REMOTE_SCRIPT_PATH="ssh_path"

#chmod +x REMOTE_SCRIPT_PATH

#curl --insecure --user root:password -T $REMOTE_SCRIPT_PATH sftp://$REMOTE_SERVER/tmp/

scp -r $REMOTE_SCRIPT_PATH $REMOTE_SERVER:/tmp/
# SSH into the remote server and execute the script
sshpass -p 'novell@123' ssh $REMOTE_SERVER /tmp/create_agent.sh
