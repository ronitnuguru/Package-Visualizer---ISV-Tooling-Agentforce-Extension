/** Processes one 200-org chunk using the immutable prepared snapshot. Never dispatches. */
public with sharing class HeadlessPushStageQueueable implements Queueable, Database.AllowsCallouts {
  private String manifestId;
  private String digest;
  private Integer offset;
  private HeadlessPushGateway boundary;
  /** Creates a bounded staging work item. */
  public HeadlessPushStageQueueable(
    String manifestId,
    String digest,
    Integer offset
  ) {
    this(manifestId, digest, offset, new HeadlessPushGateway());
  }
  @TestVisible
  private HeadlessPushStageQueueable(
    String manifestId,
    String digest,
    Integer offset,
    HeadlessPushGateway boundary
  ) {
    this.manifestId = manifestId;
    this.digest = digest;
    this.offset = offset;
    this.boundary = boundary;
  }
  /** Invokes the same production chunk path used by direct isolated tests. */
  public void execute(QueueableContext context) {
    System.attachFinalizer(new StagingFinalizer(manifestId, offset, boundary));
    HeadlessPushService.stage(manifestId, digest, offset, boundary);
  }
  private class StagingFinalizer implements Finalizer {
    private String manifestId;
    private Integer offset;
    private HeadlessPushGateway boundary;
    private StagingFinalizer(
      String manifestId,
      Integer offset,
      HeadlessPushGateway boundary
    ) {
      this.manifestId = manifestId;
      this.offset = offset;
      this.boundary = boundary;
    }
    public void execute(FinalizerContext context) {
      if (context.getResult() != ParentJobResult.SUCCESS) {
        boundary.saveFile(
          'push-staging-reconciliation-' + manifestId + '-' + offset + '.json',
          JSON.serialize(
            new Map<String, Object>{
              'manifestVersionId' => manifestId,
              'offset' => offset,
              'state' => 'RECONCILIATION_REQUIRED',
              'message' => 'The staging transaction failed; inspect the request and its jobs before retrying.'
            }
          )
        );
      }
    }
  }
}
