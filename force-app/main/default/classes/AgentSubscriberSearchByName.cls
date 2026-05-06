@JsonAccess(serializable='always' deserializable='always')
global with sharing class AgentSubscriberSearchByName {

    @TestVisible private static List<ObjectWrappers.PackageSubscriberWrapper> mockSubscribers;

    private static final Integer MAX_PRODUCTIONS     = 5;
    private static final Integer MAX_SANDBOXES       = 5;
    private static final Integer MAX_ORPHANS         = 5;
    private static final String  QUERY_LIMIT         = '50';
    private static final Integer MIN_SEARCH_LENGTH   = 3;

    @InvocableMethod(
        label='Search Subscribers by Org Name'
        description='Finds subscriber orgs whose OrgName contains the search term. Groups results by production org with nested sandboxes.'
        category='ISV Agent'
        callout=true
    )
    global static List<SearchResponse> search(List<SearchRequest> requests) {
        List<SearchResponse> responses = new List<SearchResponse>();
        for (SearchRequest req : requests) {
            AgentSubscriberWrappers.SearchResult r = resolve(req == null ? null : req.orgName);
            SearchResponse resp = new SearchResponse();
            resp.resultJson = JSON.serialize(r, true);
            responses.add(resp);
        }
        return responses;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class SearchRequest {
        @InvocableVariable(
            label='Org Name'
            description='Full or partial organization name. Minimum 3 characters. Matches via contains (LIKE %value%).'
            required=true
        )
        global String orgName;
    }

    @JsonAccess(serializable='always' deserializable='always')
    global class SearchResponse {
        @InvocableVariable(
            label='Search Result JSON'
            description='JSON serialization of the SearchResult. Feed this into the Slack search prompt template.'
        )
        global String resultJson;
    }

    private static AgentSubscriberWrappers.SearchResult resolve(String rawName) {
        AgentSubscriberWrappers.SearchResult r = new AgentSubscriberWrappers.SearchResult();
        String term = (rawName == null) ? '' : rawName.trim();
        r.searchTerm = term;

        if (String.isBlank(term)) {
            r.errorMessage = 'I need an org name to search for. Try a company name or partial name (3+ characters).';
            return r;
        }
        if (term.length() < MIN_SEARCH_LENGTH) {
            r.errorMessage = 'Search term "' + term + '" is too short — use at least ' + MIN_SEARCH_LENGTH + ' characters to narrow results.';
            return r;
        }

        List<ObjectWrappers.PackageSubscriberWrapper> rows = queryByOrgName(term);
        if (rows == null || rows.isEmpty()) {
            r.errorMessage = 'No subscribers found with org name containing "' + term + '".';
            return r;
        }

        groupByProduction(rows, r);
        return r;
    }

    private static List<ObjectWrappers.PackageSubscriberWrapper> queryByOrgName(String term) {
        if (mockSubscribers != null) return mockSubscribers;
        // Same SEARCH (LIKE %value%) pattern used in AgentSubscriberLookup.prefixSearch.
        ObjectWrappers.FilterWrapper fw = new ObjectWrappers.FilterWrapper();
        fw.fieldName = 'OrgName';
        fw.value     = term;
        fw.dataType  = 'SEARCH';
        return Package2Interface.get2GPPackageSubscriberList(
            new List<ObjectWrappers.FilterWrapper>{ fw },
            'SystemModstamp',
            'DESC',
            QUERY_LIMIT,
            '0'
        );
    }

    private static void groupByProduction(List<ObjectWrappers.PackageSubscriberWrapper> rows,
                                          AgentSubscriberWrappers.SearchResult r) {
        Map<String, AgentSubscriberWrappers.ProductionGroup> groups =
            new Map<String, AgentSubscriberWrappers.ProductionGroup>();
        List<String> productionOrder = new List<String>();
        List<ObjectWrappers.PackageSubscriberWrapper> sandboxRows = new List<ObjectWrappers.PackageSubscriberWrapper>();

        // First pass: seed productions (parentOrg is blank).
        for (ObjectWrappers.PackageSubscriberWrapper row : rows) {
            if (String.isBlank(row.parentOrg)) {
                if (!groups.containsKey(row.orgKey)) {
                    AgentSubscriberWrappers.ProductionGroup g = new AgentSubscriberWrappers.ProductionGroup();
                    g.production = toMatch(row);
                    g.sandboxes  = new List<AgentSubscriberWrappers.SubscriberMatch>();
                    groups.put(row.orgKey, g);
                    productionOrder.add(row.orgKey);
                }
            } else {
                sandboxRows.add(row);
            }
        }

        // Second pass: attach sandboxes to their parent; collect orphans.
        List<AgentSubscriberWrappers.SubscriberMatch> orphans = new List<AgentSubscriberWrappers.SubscriberMatch>();
        for (ObjectWrappers.PackageSubscriberWrapper row : sandboxRows) {
            AgentSubscriberWrappers.ProductionGroup g = groups.get(row.parentOrg);
            if (g == null) {
                orphans.add(toMatch(row));
            } else if (g.sandboxes.size() < MAX_SANDBOXES) {
                g.sandboxes.add(toMatch(row));
            }
        }

        // Truncate productions to MAX_PRODUCTIONS (preserving encounter order = SystemModstamp DESC).
        List<AgentSubscriberWrappers.ProductionGroup> productionList = new List<AgentSubscriberWrappers.ProductionGroup>();
        for (Integer i = 0; i < productionOrder.size() && i < MAX_PRODUCTIONS; i++) {
            productionList.add(groups.get(productionOrder[i]));
        }
        r.productions = productionList;

        if (!orphans.isEmpty()) {
            List<AgentSubscriberWrappers.SubscriberMatch> cappedOrphans = new List<AgentSubscriberWrappers.SubscriberMatch>();
            for (Integer i = 0; i < orphans.size() && i < MAX_ORPHANS; i++) {
                cappedOrphans.add(orphans[i]);
            }
            r.orphanSandboxes = cappedOrphans;
        }
    }

    private static AgentSubscriberWrappers.SubscriberMatch toMatch(ObjectWrappers.PackageSubscriberWrapper row) {
        AgentSubscriberWrappers.SubscriberMatch m = new AgentSubscriberWrappers.SubscriberMatch();
        m.orgKey       = row.orgKey;
        m.orgName      = row.orgName;
        m.orgType      = row.orgType;
        m.orgStatus    = row.orgStatus;
        m.parentOrgKey = row.parentOrg;
        // Deliberately not running resolveVersionInfo here — that would be N callouts per search.
        // Installed version is not shown for search results per design; user picks an OrgKey, then
        // the existing AgentSubscriberLookup flow fills in the full detail.
        return m;
    }
}
