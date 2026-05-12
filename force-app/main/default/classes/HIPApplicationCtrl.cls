public without sharing class HIPApplicationCtrl {
    public String isPreview { get; set; }
    public String recordId { get; set; }
    public String senderId { get; set; }
    public String sendDate { get; set; }
    public String logoUrl { get; set; }

    public HIPApplicationCtrl() {
        Map<String, String> params = ApexPages.currentPage().getParameters();
        isPreview = params.get('isPreview');
        recordId = params.get('id');
        if (String.isBlank(recordId)) {
            recordId = params.get('recordId');
        }
        senderId = params.get('senderId');
        sendDate = params.get('sendDate');
        logoUrl = getLogoUrl();
    }

    @AuraEnabled(cacheable=true)
    public static String getLogoUrl() {
        try {
            buildertek__ConfirmationSiteURL__c sitesUrl = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
            String baseUrl = '';
            if (sitesUrl != null && String.isNotBlank(sitesUrl.buildertek__Sites_URL__c)) {
                baseUrl = sitesUrl.buildertek__Sites_URL__c;
            } else {
                baseUrl = URL.getOrgDomainUrl().toExternalForm();
            }

            List<Document> logoDocs = [SELECT Id FROM Document WHERE DeveloperName = 'Company_Logo' LIMIT 1];
            if (logoDocs.isEmpty()) {
                logoDocs = [SELECT Id FROM Document WHERE Name = 'BuildettekLogo' LIMIT 1];
            }
            if (logoDocs.isEmpty()) {
                return null;
            }
            return baseUrl + '/servlet/servlet.FileDownload?file=' + logoDocs[0].Id;
        } catch (Exception e) {
            return null;
        }
    }
}
