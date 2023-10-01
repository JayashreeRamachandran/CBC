#!/bin/bash

# Replace with your remote server IP and script path
REMOTE_SERVER="10.71.33.161"
REMOTE_SCRIPT_PATH="C:\Users\JR\ILM_CBC\CBC\script\generate_agent.sh"

chmod +x REMOTE_SCRIPT_PATH

curl --insecure --user root:novell@123 -T $REMOTE_SCRIPT_PATH sftp://$REMOTE_SERVER/tmp/

#scp -r $REMOTE_SCRIPT_PATH $REMOTE_SERVER:/tmp/
# SSH into the remote server and execute the script
sshpass -p 'novell@123' ssh $REMOTE_SERVER /tmp/create_agent.sh
