@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentLimitsController {

    @InvocableMethod(label='Get Org Limits via ISV Agent' description='Display a custom list of limits from the current Salesforce org' category='ISV Agent')
    global static List<AgentLimitsResponse> getOrgLimits(List<AgentLimitsRequest> limitsReq) {
        List<AgentLimitsResponse> responses = new List<AgentLimitsResponse>();
        for (AgentLimitsRequest request : limitsReq) {
            try {
                HTTPRequest req = new HTTPRequest(); 
                req.setEndpoint(Package2Interface.getBaseURL('limits')); 
                req.setMethod('GET');
                req.setHeader('Authorization', 'Bearer ' + Package2Interface.getSessionId());
                req.setHeader('Content-Type', 'application/json');
                Http h = new Http();
                HttpResponse res = h.send(req);
                if (res.getStatusCode() == 200) {
                    String result = res.getBody(); List<AgentOrgLimit> limitsList = parseLimitsResponse(result); AgentLimitsResponse response = new AgentLimitsResponse(limitsList); responses.add(response);
                } else { AgentLimitsResponse response = new AgentLimitsResponse(new List<AgentOrgLimit>()); responses.add(response); }
            } catch (Exception e) { AgentLimitsResponse response = new AgentLimitsResponse(new List<AgentOrgLimit>()); responses.add(response); }
        } return responses;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class AgentLimitsRequest {
        @InvocableVariable(label='Limits Request' description='Request to get limits from the current Salesforce org' required=true)
        global String limitsRequest;
    }
    
    @JsonAccess(serializable='always' deserializable='always')
    global class AgentLimitsResponse {
        @InvocableVariable(label='Limits Response' description='List of limits from the current Salesforce org' required=true)
        global List<AgentOrgLimit> result;

        global AgentLimitsResponse(List<AgentOrgLimit> jsonResult){
            this.result = jsonResult;
        }
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class AgentOrgLimit {
        @InvocableVariable
        global String name;

        @InvocableVariable
        global Integer max;

        @InvocableVariable
        global Integer remaining;

        @InvocableVariable
        global String type;

        @InvocableVariable
        global String description;

        @InvocableVariable
        global String status;

        global AgentOrgLimit(String limitName, Integer maxValue, Integer remainingValue, String limitType, String limitDescription, String limitStatus){
            this.name = limitName; this.max = maxValue; this.remaining = remainingValue; this.type = limitType; this.description = limitDescription; this.status = limitStatus;
        }
    }

    public static List<AgentOrgLimit> parseLimitsResponse(String jsonResponse) {
        List<AgentOrgLimit> limitsList = new List<AgentOrgLimit>();
        try {
            Map<String, Object> limitsMap = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
            for (String limitName : limitsMap.keySet()) {
                Map<String, Object> limitData = (Map<String, Object>) limitsMap.get(limitName);
                Integer maxValue = (Integer) limitData.get('Max');
                Integer remainingValue = (Integer) limitData.get('Remaining');
                String limitType = (String) limitData.get('Type');
                String description = limitName; // Use limit name as description
                String status = remainingValue > 0 ? 'Available' : 'Exhausted';
                AgentOrgLimit limitObj = new AgentOrgLimit(limitName, maxValue, remainingValue, limitType, description, status);
                limitsList.add(limitObj);
            }
        } catch (Exception e) { System.debug('Error parsing limits response: ' + e.getMessage());} return limitsList;
    }
}