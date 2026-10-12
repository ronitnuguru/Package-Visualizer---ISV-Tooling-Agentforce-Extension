/*******************************************************************************************
 * @Name         DeepWikiMcpControllerTest
 * @Date         06/16/2026
 * @Description  Covers the DeepWiki MCP Callable bridge: the 3-step Streamable HTTP
 *               exchange (initialize / initialized / tools/call), SSE and plain-JSON
 *               response parsing, MCP error surfacing, and unsupported-action handling.
 *******************************************************************************************/
@IsTest
private class DeepWikiMcpControllerTest {
  private static final String REPO = 'facebook/react';
  private static final String SESSION = 'sess-1868a90c';
  private static final String DOC_TEXT = 'React is a JavaScript library...';

  // Branches on the JSON-RPC method in the request body to drive the full MCP
  // handshake. useSse toggles whether tools/call returns text/event-stream or
  // application/json. errorMode injects a tool-level error response.
  private class McpMock implements HttpCalloutMock {
    Boolean useSse;
    Boolean errorMode;
    McpMock(Boolean useSse, Boolean errorMode) {
      this.useSse = useSse;
      this.errorMode = errorMode;
    }
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      String body = req.getBody();
      if (body.contains('"method":"initialize"')) {
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('Mcp-Session-Id', SESSION);
        res.setBody(
          '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18"}}'
        );
        return res;
      }
      if (body.contains('notifications/initialized')) {
        res.setStatusCode(202);
        return res;
      }
      // tools/call
      String resultJson = errorMode
        ? '{"jsonrpc":"2.0","id":2,"result":{"isError":true,"content":[{"type":"text","text":"Repository not found"}]}}'
        : '{"jsonrpc":"2.0","id":2,"result":{"structuredContent":{"result":"' +
          DOC_TEXT +
          '"},"content":[{"type":"text","text":"' +
          DOC_TEXT +
          '"}]}}';
      if (useSse) {
        res.setHeader('Content-Type', 'text/event-stream');
        res.setBody('event: message\ndata: ' + resultJson + '\n\n');
      } else {
        res.setHeader('Content-Type', 'application/json');
        res.setBody(resultJson);
      }
      res.setStatusCode(200);
      return res;
    }
  }

  private static DeepWikiMcpController.McpResult invoke() {
    DeepWikiMcpController ctrl = new DeepWikiMcpController();
    Map<String, Object> args = new Map<String, Object>{
      'toolName' => 'read_wiki_contents',
      'inputs' => new Map<String, Object>{ 'repoName' => REPO }
    };
    String responseJson = (String) ctrl.call('callTool', args);
    return (DeepWikiMcpController.McpResult) JSON.deserialize(
      responseJson,
      DeepWikiMcpController.McpResult.class
    );
  }

  @IsTest
  static void testReadWikiContentsSse() {
    DeepWikiMcpController.httpMock = new McpMock(true, false);
    Test.startTest();
    DeepWikiMcpController.McpResult r = invoke();
    Test.stopTest();
    Assert.isTrue(r.success, 'SSE tool call should succeed');
    Assert.areEqual('read_wiki_contents', r.toolName);
    Assert.areEqual(DOC_TEXT, r.result);
    Assert.isNull(r.error);
  }

  @IsTest
  static void testReadWikiContentsJson() {
    DeepWikiMcpController.httpMock = new McpMock(false, false);
    Test.startTest();
    DeepWikiMcpController.McpResult r = invoke();
    Test.stopTest();
    Assert.isTrue(r.success, 'application/json tool call should succeed');
    Assert.areEqual(DOC_TEXT, r.result);
  }

  @IsTest
  static void testToolReturnsError() {
    DeepWikiMcpController.httpMock = new McpMock(true, true);
    Test.startTest();
    DeepWikiMcpController.McpResult r = invoke();
    Test.stopTest();
    Assert.isFalse(r.success, 'isError result must map to success=false');
    Assert.areEqual('Repository not found', r.error);
  }

  @IsTest
  static void testUnsupportedAction() {
    DeepWikiMcpController ctrl = new DeepWikiMcpController();
    Boolean threw = false;
    try {
      ctrl.call('nope', new Map<String, Object>());
    } catch (IllegalArgumentException e) {
      threw = true;
    }
    Assert.isTrue(threw, 'Unsupported action must throw IllegalArgumentException');
  }
}
