public without sharing class HIPEligibleLetterCtrl {
    public String logoUrl { get; set; }
    public String accountName { get; set; }
    public String todayDate { get; set; }
    public String accountAddress { get; set; }

    public HIPEligibleLetterCtrl() {
        logoUrl = getLogoUrl();
        accountName = getAccountName();
        accountAddress = getAccountAddress();
        todayDate = Datetime.now().format('M/d/yy');
    }

    @AuraEnabled(cacheable=true)
    public static String getLogoUrl() {
        try {
            buildertek__ConfirmationSiteURL__c sitesUrl = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
            String baseUrl = '';
            if (sitesUrl != null && !String.isBlank(sitesUrl.buildertek__Sites_URL__c)) {
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

    private static String getAccountName() {
        try {
            String recordId = ApexPages.currentPage().getParameters().get('id');
            if (String.isBlank(recordId)) {
                recordId = ApexPages.currentPage().getParameters().get('recordId');
            }
            if (String.isBlank(recordId)) {
                return null;
            }
            Account acct = [
                SELECT Name
                FROM Account
                WHERE Id = :recordId
                LIMIT 1
            ];
            return acct.Name;
        } catch (Exception e) {
            return null;
        }
    }

    private static String getAccountAddress() {
        try {
            String recordId = ApexPages.currentPage().getParameters().get('id');
            if (String.isBlank(recordId)) {
                recordId = ApexPages.currentPage().getParameters().get('recordId');
            }
            if (String.isBlank(recordId)) {
                return null;
            }
            Account acct = [
                SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode
                FROM Account
                WHERE Id = :recordId
                LIMIT 1
            ];
            List<String> lines = new List<String>();
            if (String.isNotBlank(acct.BillingStreet)) {
                lines.add(acct.BillingStreet);
            }
            String cityStateZip = '';
            if (String.isNotBlank(acct.BillingCity)) {
                cityStateZip += acct.BillingCity;
            }
            if (String.isNotBlank(acct.BillingState)) {
                cityStateZip += (cityStateZip == '' ? '' : ' ') + acct.BillingState;
            }
            if (String.isNotBlank(acct.BillingPostalCode)) {
                cityStateZip += (cityStateZip == '' ? '' : ' ') + acct.BillingPostalCode;
            }
            if (cityStateZip != '') {
                lines.add(cityStateZip);
            }
            return lines.isEmpty() ? null : String.join(lines, '\n');
        } catch (Exception e) {
            return null;
        }
    }
}
