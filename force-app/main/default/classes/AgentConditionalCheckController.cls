public with sharing class AgentConditionalCheckController {
    
    @AuraEnabled(cacheable=true)
    public static boolean isAccount() {
        return (Type.forName('Account') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isContact() {
        return (Type.forName('Contact') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isLead() {
        return (Type.forName('Lead') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isOpportunity() {
        return (Type.forName('Opportunity') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isCampaign() {
        return (Type.forName('Campaign') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isCase() {
        return (Type.forName('Case') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isTask() {
        return (Type.forName('Task') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isEvent() {
        return (Type.forName('Event') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isUser() {
        return (Type.forName('User') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isOrder() {
        return (Type.forName('Order') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isAsset() {
        return (Type.forName('Asset') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isContract() {
        return (Type.forName('Contract') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isPricebook2() {
        return (Type.forName('Pricebook2') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isProduct2() {
        return (Type.forName('Product2') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isCampaignMember() {
        return (Type.forName('CampaignMember') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isActiveScratchOrg() {
        return (Type.forName('ActiveScratchOrg') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isRecommendation() {
        return (Type.forName('Recommendation') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isPackageVersion() {
        return (Type.forName('sfLma__Package_Version__c') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isPackage() {
        return (Type.forName('sfLma__Package__c') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isLicense() {
        return (Type.forName('sfLma__License__c') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isContentVersion() {
        return (Type.forName('ContentVersion') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isSignupRequest() {
        return (Type.forName('SignupRequest') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isLMA() {
        return (Type.forName('sfLma__License__c') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isFmaParameter() {
        return (Type.forName('sfFma__FeatureParameter__c') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isActivity() {
        return (Type.forName('Activity') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isAddress() {
        return (Type.forName('Address') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isDigitalWallet() {
        return (Type.forName('DigitalWallet') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isEmployee() {
        return (Type.forName('Employee') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isLocation() {
        return (Type.forName('Location') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isPayment() {
        return (Type.forName('Payment') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isRefund() {
        return (Type.forName('Refund') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isWorkStep() {
        return (Type.forName('WorkStep') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isSeller() {
        return (Type.forName('Seller') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isScorecard() {
        return (Type.forName('Scorecard') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isProblemIncident() {
        return (Type.forName('ProblemIncident') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isPartyConsent() {
        return (Type.forName('PartyConsent') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isPaymentLineInvoice() {
        return (Type.forName('PaymentLineInvoice') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isApiAnomalyEventStore() {
      return (Type.forName('ApiAnomalyEventStore') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isAuthorizationForm() {
      return (Type.forName('AuthorizationForm') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isCreditMemo() {
      return (Type.forName('CreditMemo') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isCreditMemoInvApplication() {
      return (Type.forName('CreditMemoInvApplication') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isCreditMemoLine() {
      return (Type.forName('CreditMemoLine') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isWorkStepTemplate() {
      return (Type.forName('WorkStepTemplate') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isWorkPlanTemplateEntry() {
      return (Type.forName('WorkPlanTemplateEntry') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isWorkPlanTemplate() {
      return (Type.forName('WorkPlanTemplate') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isWorkPlan() {
      return (Type.forName('WorkPlan') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isSessionHijackingEventStore() {
      return (Type.forName('SessionHijackingEventStore') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isRefundLinePayment() {
      return (Type.forName('RefundLinePayment') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isMessagingEndUser() {
      return (Type.forName('MessagingEndUser') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isMessagingSession() {
      return (Type.forName('MessagingSession') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isFlowOrchestrationInstance() {
      return (Type.forName('FlowOrchestrationInstance') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isFlowOrchestrationLog() {
      return (Type.forName('FlowOrchestrationLog') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isFlowOrchestrationStageInstance() {
      return (Type.forName('FlowOrchestrationStageInstance') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isFlowOrchestrationStepInstance() {
      return (Type.forName('FlowOrchestrationStepInstance') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isFlowOrchestrationWorkItem() {
      return (Type.forName('FlowOrchestrationWorkItem') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isUserProvisioningRequest() {
      return (Type.forName('UserProvisioningRequest') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isSocialPersona() {
      return (Type.forName('SocialPersona') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isSvcCatalogRequest() {
      return (Type.forName('SvcCatalogRequest') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isSvcCatalogReqRelatedItem() {
      return (Type.forName('SvcCatalogReqRelatedItem') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isDevopsRequestInfo() {
      return (Type.forName('DevopsRequestInfo') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isPrivacyRTBFRequest() {
      return (Type.forName('PrivacyRTBFRequest') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isGuestUserAnomalyEventStore() {
      return (Type.forName('GuestUserAnomalyEventStore') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isFinanceTransaction() {
      return (Type.forName('FinanceTransaction') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isFinanceBalanceSnapshot() {
      return (Type.forName('FinanceBalanceSnapshot') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isDataDetectPolicy() {
      return (Type.forName('DataDetectPolicy') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isDataDetPlcyDataSrchExps() {
      return (Type.forName('DataDetPlcyDataSrchExps') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isDataDetPlcySstvDataCatg() {
      return (Type.forName('DataDetPlcySstvDataCatg') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isDataDetectPolicySnapshot() {
      return (Type.forName('DataDetectPolicySnapshot') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isDataUseLegalBasis() {
      return (Type.forName('DataUseLegalBasis') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isDataUsePurpose() {
      return (Type.forName('DataUsePurpose') != null);
    }

    @AuraEnabled(cacheable=true)
    public static boolean isProductConsumptionSchedule() {
      return (Type.forName('ProductConsumptionSchedule') != null);
    }
}