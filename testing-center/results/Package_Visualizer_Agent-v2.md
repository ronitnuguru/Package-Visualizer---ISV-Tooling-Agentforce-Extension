# Package Visualizer Agent — Version 2 Validation

## Published Version

- Agent: `Package_Visualizer_Agent`
- Bot Definition ID: `0XxRh0000000ExRKAU`
- Bot Version ID: `0X9Rh0000000GKvKAM`
- Version: `2`
- Status after publish: `Inactive`
- Previously active version: `1`
- Target org: `PkgViz`
- Published: 2026-07-28

Version 2 was published from the local
`Package_Visualizer_Agent` AgentScript authoring bundle. It was not activated,
so Version 1 remains available to current users.

## Validation Results

- AgentScript compilation: PASS
- Pre-publish safety review: PASS
  - BLOCK findings: 0
  - WARN findings: 0
- Backing Apex targets present in `PkgViz`: PASS
  - `AgentforcePushJobDiagnosisAction`
  - `AgentforcePushRequestComparisonAction`
- Focused Apex deployment tests:
  - Diagnostic and comparison suites: 16 of 16 passed
  - Final comparison and compatibility suite: 7 of 7 passed
- Salesforce Code Analyzer:
  - Critical findings: 0
  - High findings: 0

## Live Multi-Turn Acceptance

Preview session:
`ee52eed3-5b3e-4f65-bf18-8d0036c5427d`

1. Diagnosed failed PackagePushJob `0DXRh0000004hTPOAY`.
2. Persisted authoritative PackagePushRequest `0DVRh0000003sNFOAY`.
3. Set `pending_follow_up` to `SIBLING_COMPARISON`.
4. Routed the same-session utterance `Yes.` to
   `Compare Push Request Failures`.
5. Invoked the comparison using only `selectedPushJobId`; Apex rehydrated the
   owning request.
6. Returned comparison state `READY`.

Observed comparison:

- Scanned jobs: 58
- Failed jobs: 50
- Succeeded jobs: 8
- Scanned error rows: 1,060
- Job scan truncated: no
- Error scan truncated: no
- Exact failure signatures returned: yes
- Deterministically normalized similar-failure families returned: yes
- Similarity method:
  `DETERMINISTIC_VOLATILE_TOKEN_NORMALIZATION`

The trace confirmed:

- `active_push_job_id = 0DXRh0000004hTPOAY`
- `active_push_request_id = 0DVRh0000003sNFOAY`
- `comparison_state = READY`
- `pending_follow_up` was cleared after comparison
- No `REQUIRED_FIELD_MISSING` error occurred

## Generated Runtime Metadata

The publish saved the Version 2 runtime metadata under:

- `force-app/main/default/bots/Package_Visualizer_Agent`
- `force-app/main/default/genAiPlannerBundles/Package_Visualizer_Agent_v2`
