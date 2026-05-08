@NamespaceAccessible
public with sharing class AgentGenAiController implements Callable {
    
    public Object call(String action, Map<String, Object> args) {
        if (action == 'createGeneration') {
            aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request(); 
            request.modelName = (String) args.get('modelName'); 
            aiplatform.ModelsAPI_GenerationRequest body = new aiplatform.ModelsAPI_GenerationRequest(); 
            request.body = body; 
            body.prompt = (String) args.get('prompt'); 
            String modelsApiResponse = '';
            
            try { 
                aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI(); 
                aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(request); 
                modelsApiResponse = response.Code200.generation.generatedText;
            } catch(aiplatform.ModelsAPI.createGenerations_ResponseException e) { 
                System.debug('Response code: ' + e.responseCode); 
                System.debug('The following exception occurred: ' + e); 
                modelsApiResponse = 'Unable to get a valid response. Error code: ' + e.responseCode; 
                throw new AuraHandledException(modelsApiResponse); 
            } 
            
            return modelsApiResponse;
        } else if (action == 'createChatGeneration') {
            aiplatform.ModelsAPI.createChatGenerations_Request request = new aiplatform.ModelsAPI.createChatGenerations_Request(); 
            request.modelName = (String) args.get('modelName'); 
            aiplatform.ModelsAPI_ChatGenerationsRequest body = new aiplatform.ModelsAPI_ChatGenerationsRequest();
            request.body = body;
            
            List<aiplatform.ModelsAPI_ChatMessageRequest> messagesList = new List<aiplatform.ModelsAPI_ChatMessageRequest>();

            String systemPrompt = (String) args.get('systemPrompt');
            if (String.isNotBlank(systemPrompt)) {
                aiplatform.ModelsAPI_ChatMessageRequest systemMessage = new aiplatform.ModelsAPI_ChatMessageRequest();
                systemMessage.content = systemPrompt;
                systemMessage.role = 'system';
                messagesList.add(systemMessage);
            }

            aiplatform.ModelsAPI_ChatMessageRequest userMessageRequest = new aiplatform.ModelsAPI_ChatMessageRequest();
            userMessageRequest.content = (String) args.get('userPrompt');
            userMessageRequest.role = 'user';
            messagesList.add(userMessageRequest);
            body.messages = messagesList;
            request.body = body;
            
            String response = '';
            try { 
                aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI(); 
                aiplatform.ModelsAPI.createChatGenerations_Response apiResponse = modelsAPI.createChatGenerations(request);
                if (apiResponse?.Code200?.generationDetails?.generations != null && 
                    !apiResponse.Code200.generationDetails.generations.isEmpty()) { 
                    response = apiResponse.Code200.generationDetails.generations[0].content;
                } else { 
                    response = 'No content generated'; 
                }
            } catch (aiplatform.ModelsAPI.createChatGenerations_ResponseException e) { 
                System.debug('Response code: ' + e.responseCode); 
                System.debug('The following exception occurred: ' + e); 
                response = 'Unable to get a valid response. Error code: ' + e.responseCode; 
            } 
            
            return response;
        } 
        
        throw new IllegalArgumentException('Unsupported action: ' + action);
    }
}