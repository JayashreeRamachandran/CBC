import os
import subprocess
import paramiko

from django.http import HttpResponse
from django.shortcuts import render
import requests
from ILM_CBC import settings
from confluent_kafka.admin import AdminClient, NewTopic


def update_agent(dict):
    print("All the details of the agent")
    print(dict)
    script_path = os.path.join(settings.BASE_DIR, 'CBC/script', 'create_agent.sh')
    try:
        with open(script_path, 'r') as script_file:
            script_content = script_file.read()
    except FileNotFoundError:
        script_content = "File not found"
    print(script_path)

    updated_content = script_content.replace('Agent_ID', dict['agentId'])
    updated_content = updated_content.replace('Tenant_ID', dict['tenantId'])
    updated_content = updated_content.replace('command_topic', dict['commandTopic'])
    updated_content = updated_content.replace('response_topic', dict['responseTopic'])

    script_path = os.path.join(settings.BASE_DIR, 'CBC/script', 'generate_agent.sh')

    with open(script_path, 'w') as file:
        file.write(updated_content)

dict = {}


def run_script(request):
    # Remote server details
    print(dict)
    hostname = dict['hostip']
    username = dict['hostname']
    password = dict['password']
    remote_script_path = '/tmp/remote_script.sh'

    # Local script file to send
    local_script_path = os.path.join(settings.BASE_DIR, 'CBC/script', 'generate_agent.sh')
    print(local_script_path)
    try:
        item = []
        # Create an SSH client
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        # Connect to the remote server with username and password
        client.connect(hostname, username=username, password=password)
        # Open an SFTP session to send the script file
        sftp = client.open_sftp()
        # Upload the local script file to the remote server
        sftp.put(local_script_path, remote_script_path)
        # Close the SFTP session
        sftp.close()
        stdin, stdout, stderr = client.exec_command(f'bash {remote_script_path}')
        print(stdout.read().decode('utf-8'))
        dict['success'] = True
    except Exception as e:
        print(f"An error occurred: {str(e)}")
        dict['success'] = False
    item.append(dict)
    return render(request, 'base.html', {"items": item})

# def run_script(request):
#     script_filename = 'sshscript.sh'
#     script_path = os.path.join(settings.BASE_DIR, 'CBC/script', script_filename)
#     # Open and read the script file
#     # with open(script_path, 'rb') as script_file:
#     #   response = HttpResponse(script_file.read(), content_type='application/javascript')
#     # Set the content type and content-disposition header for download
#     # response['Content-Type'] = 'application/javascript'
#     # response['Content-Disposition'] = f'attachment; filename="{script_filename}"'
#     # return response
#     try:
#         result = subprocess.run(['bash', script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
#         if result.returncode == 0:
#             return HttpResponse(f'Script executed successfully.{str(result.stdout)}')
#         else:
#             print("Script encountered an error:")
#             return HttpResponse(f'Script executed successfully.{str(result.stderr)}')
#     except Exception as e:
#         return HttpResponse(f'Error executing script: {str(e)}')

# def run_script(request):
#     # SSH connection parameters
#     host = '10.71.33.161'
#     username = 'root'
#     # private_key_path = 'C:/Users/JR/.ssh/id_rsa'  # Optional, if using key-based authentication
#     password = "novell@123"
#     # Create an SSH client
#     ssh = paramiko.SSHClient()
#     #ssh.load_system_host_keys()
#     # Automatically add the server's host key (this is insecure, see notes below)
#     #ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
#
#     try:
#         # Connect to the server
#         #if private_key_path:
#             #ssh.connect(host, username=username, password=password, key_filename=private_key_path)
#         #else:
#         password = 'novell@123'  # Use password-based authentication
#         ssh.connect(host, username=username, password=password)
#
#         # Execute the script (replace 'your_script.sh' with the actual script file)
#         command = "sshpass -p 'novell@123' scp -r r'C://Users//JR//ILM_CBC//CBC//script//generate_agent.sh' root@10.71.33.161:/tmp/"
#         stdin, stdout, stderr = ssh.exec_command(command)
#
#         # Capture the script's output
#         script_output = stdout.read().decode('utf-8')
#
#         # Print the output or handle it as needed
#         return HttpResponse(script_output)
#
#     except Exception as e:
#         return HttpResponse(f"Error: {e}")
#     finally:
#         # Close the SSH connection
#         ssh.close()


def getAgents() -> {}:
    url = 'https://10.71.36.236:10443/api/v1/list'
    headers = {
        'Authorization': f'Basic {str("Y2JhZG1pbjpub2d1ZXNzaW5n")}'
    }
    response = requests.get(url, headers=headers, verify=False)
    print("Agent get response")
    if response.status_code == 200:
        print(response.json())
        return response.json()
    else:
        return None


def listagents(request):
    items = getAgents()
    return render(request, 'base.html', {"items": items['registered']})


def createAgent(request):
    # Kafka broker configuration
    kafka_broker = "10.71.36.236:33093"
    admin = AdminClient({'bootstrap.servers': kafka_broker})
    if request.method == 'POST':
        item = []
        agentid = request.POST.get('agentid')
        tenantid = request.POST.get('tenantid')
        hostip = request.POST.get('hostip')
        password = request.POST.get('password')
        hostname = request.POST.get('hostname')
        # List Kafka topics
        topics = admin.list_topics().topics
        topic_list = list(topics.keys())
        if str(agentid).__add__("_command") not in topic_list and str(agentid).__add__("_response") not in topic_list:
            create_topics = [
                NewTopic(topic=str(agentid).__add__("_command"), num_partitions=1, replication_factor=1),
                NewTopic(topic=str(agentid).__add__("_response"), num_partitions=1, replication_factor=1),
            ]
            admin.create_topics(create_topics)
        code = addAgent(agentid, tenantid)
        cba = verifyAgent(str(agentid))
        cba['hostip'] = hostip
        cba['password'] = password
        cba['hostname'] = hostname
        if code == 200:
            update_agent(cba)
            global dict
            dict = cba
        else:
            raise TypeError("Agent Creation is not successful")
        item.append(cba)
        return render(request, 'base.html', {"items": item})
    return render(request, 'agent_create.html')


def verifyAgent(agentid) -> {}:
    agents = getAgents()
    for agent in agents['registered']:
        if agent['agentId'].find(agentid) == 0:
            return agent
    return {}


def addAgent(agentid, tenantid) -> str:
    headers = {
        'Authorization': f'Basic {str("Y2JhZG1pbjpub2d1ZXNzaW5n")}'
    }
    if len(verifyAgent(agentid)) != 0:
        url = "https://10.71.36.236:10443/api/v1/delete/$agentid?force=true"
        url = url.replace('$agentid', str(agentid).__add__("_agent"))
        requests.delete(url, headers=headers, verify=False)
    create_url = "https://10.71.36.236:10443/api/v1/add"
    json = {"name": str(agentid), "uniqueId": str(agentid),
            "tenantId": str(tenantid), "description": "t1's cb", "commandTopic": str(agentid).__add__("_command"),
            "responseTopic": str(agentid).__add__("_response"), "kafkaPropertyList": {
            "kafkaProperties": [{
                "key": "bootstrap.servers",
                "value": "10.71.36.236:33093"
            }
            ]
        }}
    response = requests.post(create_url, headers=headers, json=json, verify=False)
    return response.status_code
