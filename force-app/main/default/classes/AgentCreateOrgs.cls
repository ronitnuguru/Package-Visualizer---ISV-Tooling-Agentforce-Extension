@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentCreateOrgs {
    
    @InvocableMethod(label='Create Orgs via ISV Agent' description='Display a custom list of orgs available for ISVs to spin up' category='ISV Agent')
    global static List<CreateOrgsAgentResponse> findOrgs(List<CreateOrgsAgentRequest> req){
        String className = 'AgentGenAiPromptTemplateController'; String methodName = 'singleFreeText'; String promptTemplateName = 'ISV_Agent_Create_Orgs_Prompt'; String objectInput = 'Org_Request'; String result;
        try { 
            String namespacedClass = 'pkgviz.'+className; Callable callableInstance = (Callable) Type.forName(className).newInstance(); Map<String, Object> payload = new Map<String, Object> { 'recordId' => req[0].orgRequest, 'objectInput' => objectInput, 'promptTemplateName' => promptTemplateName  };  result = (String) callableInstance.call(methodName, payload); List<OrgAgent> orgsList = (List<OrgAgent>) JSON.deserialize(result, List<OrgAgent>.class); List<CreateOrgsAgentResponse> orgsResponseList = new List<CreateOrgsAgentResponse>(); CreateOrgsAgentResponse orgsResponse = new CreateOrgsAgentResponse(orgsList); orgsResponseList.add(orgsResponse); return orgsResponseList;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class CreateOrgsAgentRequest {
        @InvocableVariable(label='Org Request'description='Type of org being requested' required=true) global String orgRequest;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class CreateOrgsAgentResponse {
        @InvocableVariable(label='Org Response'description='List of orgs available for ISVs to spin up' required=true) global List<OrgAgent> orgs;
        global CreateOrgsAgentResponse(List<OrgAgent> orgs){ this.orgs = orgs; }
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class OrgAgent {
        @InvocableVariable global String name; @InvocableVariable global String description; @InvocableVariable global String purpose; @InvocableVariable global String trialTemplateId; @InvocableVariable global String edition; @InvocableVariable global String icon;
        global OrgAgent(String orgName, String description, String orgPurpose, String trialTemplateId, String edition, String icon){
            this.name = orgName; this.description = description; this.purpose = orgPurpose; this.trialTemplateId = trialTemplateId; this.edition = edition; this.icon = icon;
        }
    }
}