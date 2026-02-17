name: n8n-manager
description: Manage n8n automation workflows. Create, list, activate, and execute n8n workflows via the n8n REST API. Use this when the user wants to set up automations, create workflow integrations, or trigger n8n workflow executions.
metadata:
  openclaw:
    emoji: "\U0001F504"
    requires:
      bins: ["curl", "jq"]

---

# n8n Workflow Manager

Manage n8n automation workflows via the REST API at n8n.aakashe.org.

## Actions

### List Workflows
List all workflows in n8n with their IDs, names, and active status.
```bash
{baseDir}/scripts/list-workflows.sh
```

### Create Workflow
Create a new n8n workflow. Pass workflow JSON via stdin or --file.
```bash
echo '{"name":"My Workflow","nodes":[...],"connections":{}}' | {baseDir}/scripts/create-workflow.sh --name "My Workflow"
{baseDir}/scripts/create-workflow.sh --name "My Workflow" --file /path/to/workflow.json
```

### Execute Workflow
Execute an existing workflow by ID.
```bash
{baseDir}/scripts/execute-workflow.sh --id <workflow_id>
```

### Activate Workflow
Activate or deactivate a workflow by ID.
```bash
{baseDir}/scripts/activate-workflow.sh --id <workflow_id> --active true
{baseDir}/scripts/activate-workflow.sh --id <workflow_id> --active false
```
