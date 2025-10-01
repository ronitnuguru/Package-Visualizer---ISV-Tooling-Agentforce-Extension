import { api } from 'lwc';
import LightningModal from 'lightning/modal';


export default class AgentCreateOrgsModal extends LightningModal  {
    @api content;
    @api label;

    agentPrompt;
    parsedContent;

    connectedCallback(){
        this.parsedContent = JSON.parse(this.content);

        this.promptCurrentTime = new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', hour12: true });
        this.agentPrompt = `Please enter the details below to create ${this.parsedContent.name} Org`;
    }

    handleClose(){
        this.close();
    }

}
