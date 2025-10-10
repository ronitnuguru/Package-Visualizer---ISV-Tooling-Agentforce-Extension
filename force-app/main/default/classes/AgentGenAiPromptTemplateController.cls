@NamespaceAccessible
public with sharing class AgentGenAiPromptTemplateController implements Callable {
    
    public Object call(String action, Map<String, Object> args) {
        // Create input
        ConnectApi.EinsteinPromptTemplateGenerationsInput promptGenerationsInput = new ConnectApi.EinsteinPromptTemplateGenerationsInput(); 
        promptGenerationsInput.isPreview = false; 
        
        Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>(); 
        Map<String, String> recipientEntityRecordIdMap = new Map<String, String>(); 
        ConnectApi.WrappedValue recipientEntityWrappedValue = new ConnectApi.WrappedValue(); 
        ConnectApi.WrappedValue strWrappedValue = new ConnectApi.WrappedValue();
        
        if (action == 'recordSummary') {
            String objectValue = 'Input:' + (String) args.get('objectInput'); 
            recipientEntityRecordIdMap.put('id', (String) args.get('recordId')); 
            recipientEntityWrappedValue.value = recipientEntityRecordIdMap; 
            valueMap.put(objectValue, recipientEntityWrappedValue);
        } else if (action == 'singleFreeText') {
            String objectValue = 'Input:' + (String) args.get('objectInput'); 
            strWrappedValue.value = (String) args.get('recordId'); 
            valueMap.put(objectValue, strWrappedValue); 
        }
        
        promptGenerationsInput.inputParams = valueMap; 
        promptGenerationsInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput(); 
        promptGenerationsInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        //promptGenerationsInput.citationMode = 'post_generation';
        
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationsOutput = 
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    (String) args.get('promptTemplateName'), 
                    promptGenerationsInput
                ); 
            ConnectApi.EinsteinLLMGenerationItemOutput response = generationsOutput.generations[0]; 
            return response.text;
        } catch (Exception e) { 
            System.debug(e.getMessage()); 
            throw new AuraHandledException(e.getMessage()); 
        }
    }
}