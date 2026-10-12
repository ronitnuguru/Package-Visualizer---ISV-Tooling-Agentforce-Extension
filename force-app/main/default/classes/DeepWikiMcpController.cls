/*******************************************************************************************
 * @Name         DeepWikiMcpController
 * @Date         06/16/2026
 * @Description  Callable bridge (invoked from the base package via Type.forName) that calls
 *               the DeepWiki MCP server over HTTP using the DeepWiki Named Credential.
 *               Uses the MCP Streamable HTTP transport (JSON-RPC 2.0): initialize ->
 *               notifications/initialized -> tools/call. One generic 'callTool' action
 *               serves every DeepWiki tool so new tools need no new callout code.
 *******************************************************************************************/
@NamespaceAccessible
public with sharing class DeepWikiMcpController implements Callable {
  @TestVisible
  private static HttpCalloutMock httpMock;

  private static final String ENDPOINT = 'callout:pkgviz__DeepWiki';
  private static final String PROTOCOL_VERSION = '2025-06-18';

  public Object call(String action, Map<String, Object> args) {
    if (action == 'callTool') {
      return callTool(
        (String) args.get('toolName'),
        (Map<String, Object>) args.get('inputs')
      );
    }
    throw new IllegalArgumentException('Unsupported action: ' + action);
  }

  /**************************************************************************************
   * @Description  Generic MCP tool invocation. Returns a serialized McpResult JSON
   * string so the LWC has a stable contract (success / result / error).
   **************************************************************************************/
  private String callTool(String toolName, Map<String, Object> inputs) {
    McpResult dto = new McpResult();
    dto.toolName = toolName;
    try {
      String sessionId = initSession();
      Map<String, Object> params = new Map<String, Object>{
        'name' => toolName,
        'arguments' => (inputs == null ? new Map<String, Object>() : inputs)
      };
      String rpcJson = sendRpc('tools/call', 2, params, sessionId);
      dto.result = extractToolResult(rpcJson);
      dto.success = true;
    } catch (Exception e) {
      dto.success = false;
      dto.error = e.getMessage();
    }
    return JSON.serialize(dto);
  }

  /**************************************************************************************
   * @Description  MCP handshake: initialize (capture Mcp-Session-Id) then send the
   * initialized notification. Returns the session id (may be null if not issued).
   **************************************************************************************/
  private String initSession() {
    Map<String, Object> initParams = new Map<String, Object>{
      'protocolVersion' => PROTOCOL_VERSION,
      'capabilities' => new Map<String, Object>(),
      'clientInfo' => new Map<String, Object>{
        'name' => 'PackageVisualizer',
        'version' => '1.0'
      }
    };
    HttpResponse initRes = post(buildBody('initialize', 1, initParams), null);
    if (initRes.getStatusCode() < 200 || initRes.getStatusCode() >= 300) {
      throw new CalloutException(
        'MCP initialize failed: ' + initRes.getStatusCode()
      );
    }
    String sessionId = initRes.getHeader('Mcp-Session-Id');
    if (String.isBlank(sessionId)) {
      sessionId = initRes.getHeader('mcp-session-id');
    }

    // initialized notification (no id => server replies 202 with no body)
    post(
      JSON.serialize(
        new Map<String, Object>{
          'jsonrpc' => '2.0',
          'method' => 'notifications/initialized'
        }
      ),
      sessionId
    );
    return sessionId;
  }

  /**************************************************************************************
   * @Description  Sends one JSON-RPC request and returns the JSON-RPC payload as a
   * String, transparently handling both application/json and text/event-stream (SSE)
   * response bodies.
   **************************************************************************************/
  private String sendRpc(
    String method,
    Integer id,
    Map<String, Object> params,
    String sessionId
  ) {
    HttpResponse res = post(buildBody(method, id, params), sessionId);
    if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
      throw new CalloutException(
        'MCP ' + method + ' failed: ' + res.getStatusCode()
      );
    }
    String body = res.getBody();
    String contentType = res.getHeader('Content-Type');
    if (
      (contentType != null &&
      contentType.containsIgnoreCase('text/event-stream')) ||
      (body != null && body.startsWith('event:'))
    ) {
      return parseSse(body);
    }
    return body;
  }

  /**************************************************************************************
   * @Description  Issues the HTTP POST against the DeepWiki Named Credential with the
   * headers the MCP Streamable HTTP transport requires.
   **************************************************************************************/
  private HttpResponse post(String body, String sessionId) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(ENDPOINT);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('Accept', 'application/json, text/event-stream');
    req.setHeader('MCP-Protocol-Version', PROTOCOL_VERSION);
    if (String.isNotBlank(sessionId)) {
      req.setHeader('Mcp-Session-Id', sessionId);
    }
    req.setTimeout(120000);
    req.setBody(body);
    return (httpMock != null) ? httpMock.respond(req) : new Http().send(req);
  }

  private String buildBody(String method, Integer id, Map<String, Object> params) {
    return JSON.serialize(
      new Map<String, Object>{
        'jsonrpc' => '2.0',
        'id' => id,
        'method' => method,
        'params' => params
      }
    );
  }

  /**************************************************************************************
   * @Description  Collects the data: lines of an SSE body and returns the concatenated
   * JSON payload (the JSON-RPC response carried by the stream).
   **************************************************************************************/
  private String parseSse(String body) {
    if (String.isBlank(body)) {
      return body;
    }
    // Walk the body line-by-line with indexOf/substring. Do NOT use
    // String.split('\n') here: Apex compiles the argument as a regex and runs
    // the regex engine over the whole string, which throws "Regex too
    // complicated" on large SSE bodies (e.g. a full wiki document).
    List<String> dataParts = new List<String>();
    Integer pos = 0;
    Integer len = body.length();
    while (pos <= len) {
      Integer nl = body.indexOf('\n', pos);
      Integer lineEnd = (nl == -1) ? len : nl;
      String line = body.substring(pos, lineEnd).trim();
      if (line.startsWith('data:')) {
        dataParts.add(line.substring(5).trim());
      }
      if (nl == -1) {
        break;
      }
      pos = nl + 1;
    }
    return dataParts.isEmpty() ? body : String.join(dataParts, '');
  }

  /**************************************************************************************
   * @Description  Pulls the tool result text out of a JSON-RPC response: prefers
   * result.structuredContent.result, falls back to result.content[0].text. Throws on a
   * JSON-RPC error or result.isError == true.
   **************************************************************************************/
  @SuppressWarnings('PMD.ApexDoc')
  private String extractToolResult(String rpcJson) {
    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(
      rpcJson
    );
    if (root.containsKey('error')) {
      Object err = root.get('error');
      if (err instanceof Map<String, Object>) {
        Object msg = ((Map<String, Object>) err).get('message');
        throw new CalloutException(
          msg == null ? 'MCP returned an error' : String.valueOf(msg)
        );
      }
      throw new CalloutException(String.valueOf(err));
    }

    Map<String, Object> result = (Map<String, Object>) root.get('result');
    if (result == null) {
      throw new CalloutException('MCP response had no result');
    }
    if (result.get('isError') == true) {
      throw new CalloutException(textFromContent(result));
    }

    Object structured = result.get('structuredContent');
    if (structured instanceof Map<String, Object>) {
      Object structuredResult = ((Map<String, Object>) structured).get('result');
      if (structuredResult != null) {
        return String.valueOf(structuredResult);
      }
    }
    return textFromContent(result);
  }

  /**************************************************************************************
   * @Description  Concatenates the text fields of an MCP result.content[] array.
   **************************************************************************************/
  private String textFromContent(Map<String, Object> result) {
    Object content = result.get('content');
    if (content instanceof List<Object>) {
      List<String> parts = new List<String>();
      for (Object item : (List<Object>) content) {
        if (item instanceof Map<String, Object>) {
          Object text = ((Map<String, Object>) item).get('text');
          if (text != null) {
            parts.add(String.valueOf(text));
          }
        }
      }
      if (!parts.isEmpty()) {
        return String.join(parts, '\n');
      }
    }
    return '';
  }

  @NamespaceAccessible
  public class McpResult {
    public Boolean success;
    public String toolName;
    public String result;
    public String error;
  }
}
