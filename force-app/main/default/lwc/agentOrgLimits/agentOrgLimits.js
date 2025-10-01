import { LightningElement, api } from 'lwc';

export default class AgentOrgLimits extends LightningElement {

    @api value;

    limitsData;

    updateLimits(event){
        this.limitsData = event.detail;
    }
}