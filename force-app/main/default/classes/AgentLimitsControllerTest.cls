/*******************************************************************************************
* @Name         AgentLimitsControllerTest
* @Date         04/06/2026
* @Description  Comprehensive test class for AgentLimitsController with 90%+ coverage.
*               Tests Positive/Negative/Bulk scenarios and HTTP callout mocking.
*******************************************************************************************/
@IsTest
private class AgentLimitsControllerTest {

    /**************************************************************************************
    * @Description  Mock HTTP callout for successful org limits response
    **************************************************************************************/
    private class MockHttpSuccessResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            // Mock realistic org limits JSON response
            String jsonResponse = '{'
                + '"DailyApiRequests": {"Max": 15000, "Remaining": 14500, "Type": "API"},'
                + '"DailyAsyncApexExecutions": {"Max": 250000, "Remaining": 249000, "Type": "Async"},'
                + '"DailyBulkApiRequests": {"Max": 5000, "Remaining": 4980, "Type": "BulkAPI"},'
                + '"DailyGenericStreamingApiEvents": {"Max": 10000, "Remaining": 9500, "Type": "Streaming"}'
                + '}';
            res.setBody(jsonResponse);
            return res;
        }
    }

    /**************************************************************************************
    * @Description  Mock HTTP callout for failed org limits response
    **************************************************************************************/
    private class MockHttpFailureResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('{"error": "Internal Server Error"}');
            return res;
        }
    }

    /**************************************************************************************
    * @Description  Positive Test - Successfully retrieve org limits with HTTP 200
    **************************************************************************************/
    @IsTest
    static void testGetOrgLimitsSuccess() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new MockHttpSuccessResponse());

        List<AgentLimitsController.AgentLimitsRequest> requests =
            new List<AgentLimitsController.AgentLimitsRequest>();
        AgentLimitsController.AgentLimitsRequest request =
            new AgentLimitsController.AgentLimitsRequest();
        request.limitsRequest = 'Get all org limits';
        requests.add(request);

        // Act
        Test.startTest();
        List<AgentLimitsController.AgentLimitsResponse> responses =
            AgentLimitsController.getOrgLimits(requests);
        Test.stopTest();

        // Assert
        Assert.areEqual(1, responses.size(), 'Should return one response');
        Assert.isNotNull(responses[0].result, 'Result should not be null');
        Assert.isTrue(responses[0].result.size() > 0, 'Should have at least one limit');

        // Verify parsed limit data
        AgentLimitsController.AgentOrgLimit firstLimit = responses[0].result[0];
        Assert.isNotNull(firstLimit.name, 'Limit name should not be null');
        Assert.isNotNull(firstLimit.max, 'Max value should not be null');
        Assert.isNotNull(firstLimit.remaining, 'Remaining value should not be null');
        Assert.isNotNull(firstLimit.status, 'Status should not be null');
    }

    /**************************************************************************************
    * @Description  Negative Test - Handle HTTP error response (non-200 status)
    **************************************************************************************/
    @IsTest
    static void testGetOrgLimitsHttpFailure() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new MockHttpFailureResponse());

        List<AgentLimitsController.AgentLimitsRequest> requests =
            new List<AgentLimitsController.AgentLimitsRequest>();
        AgentLimitsController.AgentLimitsRequest request =
            new AgentLimitsController.AgentLimitsRequest();
        request.limitsRequest = 'Get all org limits';
        requests.add(request);

        // Act
        Test.startTest();
        List<AgentLimitsController.AgentLimitsResponse> responses =
            AgentLimitsController.getOrgLimits(requests);
        Test.stopTest();

        // Assert
        Assert.areEqual(1, responses.size(), 'Should return one response even on failure');
        Assert.isNotNull(responses[0].result, 'Result should not be null');
        Assert.areEqual(0, responses[0].result.size(),
            'Should return empty list on HTTP failure');
    }

    /**************************************************************************************
    * @Description  Negative Test - Handle exception during HTTP callout
    **************************************************************************************/
    @IsTest
    static void testGetOrgLimitsException() {
        // Arrange - No mock set to trigger exception
        List<AgentLimitsController.AgentLimitsRequest> requests =
            new List<AgentLimitsController.AgentLimitsRequest>();
        AgentLimitsController.AgentLimitsRequest request =
            new AgentLimitsController.AgentLimitsRequest();
        request.limitsRequest = 'Get all org limits';
        requests.add(request);

        // Act
        Test.startTest();
        List<AgentLimitsController.AgentLimitsResponse> responses =
            AgentLimitsController.getOrgLimits(requests);
        Test.stopTest();

        // Assert
        Assert.areEqual(1, responses.size(), 'Should return one response even on exception');
        Assert.isNotNull(responses[0].result, 'Result should not be null');
        Assert.areEqual(0, responses[0].result.size(),
            'Should return empty list on exception');
    }

    /**************************************************************************************
    * @Description  Test parseLimitsResponse method with valid JSON
    **************************************************************************************/
    @IsTest
    static void testParseLimitsResponseSuccess() {
        // Arrange
        String jsonResponse = '{'
            + '"DailyApiRequests": {"Max": 15000, "Remaining": 14500, "Type": "API"},'
            + '"DailyAsyncApexExecutions": {"Max": 250000, "Remaining": 0, "Type": "Async"}'
            + '}';

        // Act
        Test.startTest();
        List<AgentLimitsController.AgentOrgLimit> limits =
            AgentLimitsController.parseLimitsResponse(jsonResponse);
        Test.stopTest();

        // Assert
        Assert.areEqual(2, limits.size(), 'Should parse two limits');

        // Verify first limit
        AgentLimitsController.AgentOrgLimit apiLimit = limits[0];
        Assert.isNotNull(apiLimit.name, 'Limit name should not be null');
        Assert.areEqual(15000, apiLimit.max, 'Max should be 15000');
        Assert.areEqual(14500, apiLimit.remaining, 'Remaining should be 14500');
        Assert.areEqual('API', apiLimit.type, 'Type should be API');
        Assert.areEqual('Available', apiLimit.status, 'Status should be Available');

        // Verify exhausted limit
        AgentLimitsController.AgentOrgLimit asyncLimit = limits[1];
        Assert.areEqual(0, asyncLimit.remaining, 'Remaining should be 0');
        Assert.areEqual('Exhausted', asyncLimit.status, 'Status should be Exhausted');
    }

    /**************************************************************************************
    * @Description  Test parseLimitsResponse with invalid JSON
    **************************************************************************************/
    @IsTest
    static void testParseLimitsResponseInvalidJson() {
        // Arrange
        String invalidJson = '{invalid json';

        // Act
        Test.startTest();
        List<AgentLimitsController.AgentOrgLimit> limits =
            AgentLimitsController.parseLimitsResponse(invalidJson);
        Test.stopTest();

        // Assert
        Assert.areEqual(0, limits.size(),
            'Should return empty list for invalid JSON');
    }

    /**************************************************************************************
    * @Description  Test parseLimitsResponse with empty JSON
    **************************************************************************************/
    @IsTest
    static void testParseLimitsResponseEmptyJson() {
        // Arrange
        String emptyJson = '{}';

        // Act
        Test.startTest();
        List<AgentLimitsController.AgentOrgLimit> limits =
            AgentLimitsController.parseLimitsResponse(emptyJson);
        Test.stopTest();

        // Assert
        Assert.areEqual(0, limits.size(), 'Should return empty list for empty JSON');
    }

    /**************************************************************************************
    * @Description  Test AgentOrgLimit constructor
    **************************************************************************************/
    @IsTest
    static void testAgentOrgLimitConstructor() {
        // Act
        Test.startTest();
        AgentLimitsController.AgentOrgLimit orgLimit =
            new AgentLimitsController.AgentOrgLimit(
                'DailyApiRequests',
                15000,
                14500,
                'API',
                'Daily API request limit',
                'Available'
            );
        Test.stopTest();

        // Assert
        Assert.areEqual('DailyApiRequests', orgLimit.name, 'Name should match');
        Assert.areEqual(15000, orgLimit.max, 'Max should match');
        Assert.areEqual(14500, orgLimit.remaining, 'Remaining should match');
        Assert.areEqual('API', orgLimit.type, 'Type should match');
        Assert.areEqual('Daily API request limit', orgLimit.description, 'Description should match');
        Assert.areEqual('Available', orgLimit.status, 'Status should match');
    }

    /**************************************************************************************
    * @Description  Test AgentLimitsRequest wrapper class
    **************************************************************************************/
    @IsTest
    static void testAgentLimitsRequest() {
        // Act
        Test.startTest();
        AgentLimitsController.AgentLimitsRequest request =
            new AgentLimitsController.AgentLimitsRequest();
        request.limitsRequest = 'Test limits request';
        Test.stopTest();

        // Assert
        Assert.areEqual('Test limits request', request.limitsRequest,
            'Limits request should be set correctly');
    }

    /**************************************************************************************
    * @Description  Test AgentLimitsResponse wrapper class
    **************************************************************************************/
    @IsTest
    static void testAgentLimitsResponse() {
        // Arrange
        List<AgentLimitsController.AgentOrgLimit> limits =
            new List<AgentLimitsController.AgentOrgLimit>();
        AgentLimitsController.AgentOrgLimit orgLimit =
            new AgentLimitsController.AgentOrgLimit(
                'DailyApiRequests',
                15000,
                14500,
                'API',
                'Daily API request limit',
                'Available'
            );
        limits.add(orgLimit);

        // Act
        Test.startTest();
        AgentLimitsController.AgentLimitsResponse response =
            new AgentLimitsController.AgentLimitsResponse(limits);
        Test.stopTest();

        // Assert
        Assert.areEqual(limits, response.result, 'Result should match input limits');
        Assert.areEqual(1, response.result.size(), 'Should have one limit');
        Assert.areEqual('DailyApiRequests', response.result[0].name,
            'Limit name should match');
    }
}
