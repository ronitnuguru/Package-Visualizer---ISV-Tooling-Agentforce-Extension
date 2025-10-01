@isTest
private class AgentGenAiControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Setup any test data if needed
    }
    
    @isTest
    static void testUnsupportedAction() {
        AgentGenAiController controller = new AgentGenAiController();
        
        Map<String, Object> args = new Map<String, Object>();
        args.put('testParam', 'testValue');
        
        Test.startTest();
        try {
            Object result = controller.call('unsupportedAction', args);
            System.assert(false, 'Should have thrown an exception for unsupported action');
        } catch (IllegalArgumentException e) {
            Test.stopTest();
            System.assert(e.getMessage().contains('Unsupported action'), 'Should throw exception for unsupported action');
        }
    }
}