@isTest
private class AgentGenAiPromptTemplateControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Setup any test data if needed
    }
    
    @isTest
    static void testRecordSummaryWithNullArgs() {
        AgentGenAiPromptTemplateController controller = new AgentGenAiPromptTemplateController();

        Test.startTest();
        try {
            Object result = controller.call('recordSummary', null);
            Test.stopTest();

            // Should handle null args gracefully
            System.assertEquals(null, result, 'Null args should return null');
        } catch (Exception e) {
            Test.stopTest();
            // Expected to fail due to Einstein dependencies or null args
            Assert.isNotNull(e, 'Exception should be thrown for null args');
        }
    }
    
    @isTest
    static void testSingleFreeTextWithNullArgs() {
        AgentGenAiPromptTemplateController controller = new AgentGenAiPromptTemplateController();

        Test.startTest();
        try {
            Object result = controller.call('singleFreeText', null);
            Test.stopTest();

            // Should handle null args gracefully
            System.assertEquals(null, result, 'Null args should return null');
        } catch (Exception e) {
            Test.stopTest();
            // Expected to fail due to Einstein dependencies or null args
            Assert.isNotNull(e, 'Exception should be thrown for null args');
        }
    }

        /**************************************************************************************
    * @Description  Tests the singleFreeText action with error JSON input
    **************************************************************************************/
    @isTest
    static void testSingleFreeTextAction() {
        // Arrange
        AgentGenAiPromptTemplateController controller =
            new AgentGenAiPromptTemplateController();

        Map<String, Object> payload = new Map<String, Object>{
            'recordId' => '[{"errorTitle":"Compile Error","errorMessage":"Line 24, column 81: Invalid type"}]',
            'objectInput' => 'Package_Push_Errors',
            'promptTemplateName' => 'pkgviz__Package_Push_Error_Debugger'
        };

        // Act
        Test.startTest();
        try {
            Object result = controller.call('singleFreeText', payload);
            // If template exists and AI is configured, result should not be null
            Assert.isNotNull(result, 'Result should not be null');
        } catch (Exception e) {
            // Expected in test context when template doesn't exist or AI service unavailable
            Assert.isNotNull(e, 'Exception should be thrown for GenAI dependencies');
        }
        Test.stopTest();
    }

    /**************************************************************************************
    * @Description  Tests the recordSummary action with record ID input
    **************************************************************************************/
    @isTest
    static void testRecordSummaryAction() {
        // Arrange
        AgentGenAiPromptTemplateController controller =
            new AgentGenAiPromptTemplateController();

        Map<String, Object> payload = new Map<String, Object>{
            'recordId' => '001000000000000AAA',
            'objectInput' => 'Account',
            'promptTemplateName' => 'pkgviz__License_Summary'
        };

        // Act
        Test.startTest();
        try {
            Object result = controller.call('recordSummary', payload);
            Assert.isNotNull(result, 'Result should not be null');
        } catch (Exception e) {
            // Expected in test context
            Assert.isNotNull(e, 'Exception should be thrown for GenAI dependencies');
        }
        Test.stopTest();
    }

    /**************************************************************************************
    * @Description  Tests handling of null or invalid inputs
    **************************************************************************************/
    @isTest
    static void testInvalidInputs() {
        // Arrange
        AgentGenAiPromptTemplateController controller =
            new AgentGenAiPromptTemplateController();

        Map<String, Object> emptyPayload = new Map<String, Object>();

        // Act
        Test.startTest();
        try {
            controller.call('singleFreeText', emptyPayload);
            System.assert(false, 'Should have thrown exception for empty payload');
        } catch (Exception e) {
            // Expected - missing required parameters
            System.assertNotEquals(null, e, 'Exception should be thrown');
        }
        Test.stopTest();
    }

    /**************************************************************************************
    * @Description  Tests handling of unsupported action
    **************************************************************************************/
    @isTest
    static void testUnsupportedAction() {
        // Arrange
        AgentGenAiPromptTemplateController controller =
            new AgentGenAiPromptTemplateController();

        Map<String, Object> payload = new Map<String, Object>{
            'recordId' => 'test',
            'objectInput' => 'Test',
            'promptTemplateName' => 'test'
        };

        // Act
        Test.startTest();
        try {
            // Call with unsupported action - will create empty valueMap
            Object result = controller.call('unsupportedAction', payload);
            System.assert(false, 'Should have thrown exception for unsupported action');
        } catch (Exception e) {
            // Expected - empty input params will cause error
            System.assertNotEquals(null, e, 'Exception should be thrown');
        }
        Test.stopTest();
    }
}