import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import agentCreateOrgsModal from 'c/agentCreateOrgsModal';

const actions = [
    { label: 'Create', name: 'create' }
];

const columns = [
    { label: 'Name', fieldName: 'name', iconName: "standard:default" },
    { label: 'Purpose', fieldName: 'purpose', iconName: "standard:catalog"},
    { type: "action", typeAttributes: { rowActions: actions, menuAlignment: "auto" }}
];

export default class AgentIsvOrgTypes extends LightningModal  {

    @api value;

    data = [];
    columns = columns;

    listState = true;
    tableState = false;

    handleTableView(){
        this.tableState = true;
        this.listState = false;
    }

    handleListView(){
        this.tableState = false;
        this.listState = true;
    }

    async handleCreateOrgModal(event){
        const orgName = event.currentTarget.dataset.id;
        const selectedOrg = this.value.find(org => org.name === orgName);
        this.openModal(JSON.stringify(selectedOrg));
    }

    handleRowAction(event){
        const action = event.detail.action;
        const row = event.detail.row;

        if(action.name === 'create'){
            this.openModal(JSON.stringify(row));
        }
    }

    async openModal(details){
        const result = await agentCreateOrgsModal.open({
            label: 'ISV Agent',
            size: 'medium',
            content: details
        });  
    }
}