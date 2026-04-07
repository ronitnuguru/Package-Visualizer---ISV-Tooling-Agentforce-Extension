/*******************************************************************************************
* @Name         AgentGenAiPromptTemplateController
* @Date         04/03/2026
* @Description  Callable controller for invoking GenAI Prompt Templates via ConnectApi.
*               Supports both record-based summaries and free-text generation.
*******************************************************************************************/
@NamespaceAccessible
public with sharing class AgentGenAiPromptTemplateController implements Callable {

    /**************************************************************************************
    * @Description  Callable interface implementation for dynamic invocation from
    *               PackageVisualizerCtrl.invokeGenAiPromptTemplate()
    * @Param        action - Method to invoke ('recordSummary' or 'singleFreeText')
    * @Param        args - Map containing recordId, objectInput, promptTemplateName
    * @Return       String - AI-generated response text
    **************************************************************************************/
    public Object call(String action, Map<String, Object> args) {
        try {
            // Create input configuration
            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.isPreview = false;

            Map<String, ConnectApi.WrappedValue> valueMap =
                new Map<String, ConnectApi.WrappedValue>();

            if (action == 'recordSummary') {
            // For record-based inputs (e.g., License summary)
            String objectValue = 'Input:' + (String) args.get('objectInput');
            Map<String, String> recordIdMap = new Map<String, String>{
                'id' => (String) args.get('recordId')
            };
            ConnectApi.WrappedValue recordValue = new ConnectApi.WrappedValue();
            recordValue.value = recordIdMap;
            valueMap.put(objectValue, recordValue);

        } else if (action == 'singleFreeText') {
            // For free-text inputs (e.g., error JSON, scratch org files)
            String objectValue = 'Input:' + (String) args.get('objectInput');
            ConnectApi.WrappedValue textValue = new ConnectApi.WrappedValue();
            textValue.value = (String) args.get('recordId');  // recordId contains text data
            valueMap.put(objectValue, textValue);
        }

        promptInput.inputParams = valueMap;

        // Configure additional settings
        promptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        promptInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';
        promptInput.additionalConfig.maxTokens = 2000;
        promptInput.additionalConfig.temperature = 0.7;

        // Execute prompt template
        try {
            String templateName = (String) args.get('promptTemplateName');

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    templateName,
                    promptInput
                );

            if (result.generations == null || result.generations.isEmpty()) {
                throw new AuraHandledException('No response generated from AI model');
            }

            return result.generations[0].text;
        } catch (ConnectApi.ConnectApiException e) {
            throw new AuraHandledException('AI service error: ' + e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException('Error executing prompt template: ' + e.getMessage());
        }
        } catch (Exception outerEx) {
            throw new AuraHandledException('Failed to process request: ' + outerEx.getMessage());
        }
    }
}
