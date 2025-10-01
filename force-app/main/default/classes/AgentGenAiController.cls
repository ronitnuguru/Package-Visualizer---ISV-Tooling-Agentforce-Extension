global with sharing class AgentGenAiController implements Callable {
    
    global Object call(String action, Map<String, Object> args) {
        if (action == 'createGeneration') {
            // Create generations request
            aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
            // Specify model
            request.modelName = (String) args.get('modelName');
            // Create request body
            aiplatform.ModelsAPI_GenerationRequest body = new aiplatform.ModelsAPI_GenerationRequest();
            request.body = body;
            // Add prompt to body
            body.prompt = (String) args.get('prompt');
            String modelsApiResponse = '';
            try {
                // Make request
                aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
                aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(request);

                // Add response to return value
                modelsApiResponse = response.Code200.generation.generatedText;
            // Handle error
            } catch(aiplatform.ModelsAPI.createGenerations_ResponseException e) {
                System.debug('Response code: ' + e.responseCode);
                System.debug('The following exception occurred: ' + e);
                // Add error to the return value
                modelsApiResponse = 'Unable to get a valid response. Error code: ' + e.responseCode;
                throw new AuraHandledException(modelsApiResponse);
            }
            // Return response
            return modelsApiResponse;
        } 
        else if (action == 'createChatGeneration'){
            // Create chat generations request
            aiplatform.ModelsAPI.createChatGenerations_Request request = new aiplatform.ModelsAPI.createChatGenerations_Request();
            // Specify model
            request.modelName = (String) args.get('modelName');
            // Create request body
            aiplatform.ModelsAPI_ChatGenerationsRequest body = new aiplatform.ModelsAPI_ChatGenerationsRequest();
            request.body = body;

            // Create a list to hold chat messages
            List<aiplatform.ModelsAPI_ChatMessageRequest> messagesList = new List<aiplatform.ModelsAPI_ChatMessageRequest>();

            // Add system message
            aiplatform.ModelsAPI_ChatMessageRequest systemMessageRequest = new aiplatform.ModelsAPI_ChatMessageRequest();
            systemMessageRequest.content = (String) args.get('systemPrompt');
            systemMessageRequest.role = 'system';
            messagesList.add(systemMessageRequest);

            // Add user message
            aiplatform.ModelsAPI_ChatMessageRequest userMessageRequest = new aiplatform.ModelsAPI_ChatMessageRequest();
            userMessageRequest.content = (String) args.get('userPrompt');
            userMessageRequest.role = 'user';
            messagesList.add(userMessageRequest);

            // Set the messages in the request body
            body.messages = messagesList;

            // Set the request body and model name
            request.body = body;

            String response = '';

            try {
                // Call the API and get the response
                aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
                aiplatform.ModelsAPI.createChatGenerations_Response apiResponse = modelsAPI.createChatGenerations(request);
    
                // Check that we have a non-null response
                if (
                    apiResponse?.Code200?.generationDetails?.generations != null &&
                    !apiResponse.Code200.generationDetails.generations.isEmpty()
                ) {
                    // Set the variable from the response
                    response = apiResponse.Code200.generationDetails.generations[0]
                        .content;
                } else {
                    // Handle the case where response is null
                    response = 'No content generated';
                }
    
            // Handle error
            } catch (aiplatform.ModelsAPI.createChatGenerations_ResponseException e) {
                System.debug('Response code: ' + e.responseCode);
                System.debug('The following exception occurred: ' + e);

                // Add error to the output
                response = 'Unable to get a valid response. Error code: ' + e.responseCode;
            }
            return response;
        }
        throw new IllegalArgumentException('Unsupported action: ' + action);
    }
}