public without sharing class IneligibleHIPletterAsPDFCtrl {
    public String logoUrl { get; set; }
    public String accountName { get; set; }
    public String todayDate { get; set; }
    public String accountAddress { get; set; }
    public String denialReasonsHtml { get; set; }
    public String incomeUpperLimit { get; set; }

    public IneligibleHIPletterAsPDFCtrl() {
        String recordId;

        logoUrl = getLogoUrl();
        todayDate = getFormattedDateFromPageParameters();
        accountName = null;
        accountAddress = null;
        denialReasonsHtml = '';
        incomeUpperLimit = '';

        recordId = getRecordIdFromPageParameters();
        if (String.isNotBlank(recordId)) {
            loadAccountData(recordId);
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getLogoUrl() {
        try {
            buildertek__ConfirmationSiteURL__c sitesUrl;
            String baseUrl;
            List<Document> logoDocuments;

            sitesUrl = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
            if (sitesUrl != null && String.isNotBlank(sitesUrl.buildertek__Sites_URL__c)) {
                baseUrl = sitesUrl.buildertek__Sites_URL__c;
            } else {
                baseUrl = URL.getOrgDomainUrl().toExternalForm();
            }

            logoDocuments = [SELECT Id FROM Document WHERE DeveloperName = 'Company_Logo' LIMIT 1];
            if (logoDocuments.isEmpty()) {
                logoDocuments = [SELECT Id FROM Document WHERE Name = 'BuildettekLogo' LIMIT 1];
            }

            if (logoDocuments.isEmpty()) {
                return null;
            }

            return baseUrl + '/servlet/servlet.FileDownload?file=' + logoDocuments[0].Id;
        } catch (Exception e) {
            return null;
        }
    }

    public String getRecordIdFromPageParameters() {
        String recordId;

        recordId = ApexPages.currentPage().getParameters().get('id');
        if (String.isBlank(recordId)) {
            recordId = ApexPages.currentPage().getParameters().get('recordId');
        }

        return recordId;
    }

    public String getFormattedDateFromPageParameters() {
        return Datetime.now().format('M/d/yy');
    }

    public void loadAccountData(String recordId) {
        try {
            Account accountRecord;

            accountRecord = [
                SELECT Name,
                       BillingStreet,
                       BillingCity,
                       BillingState,
                       BillingPostalCode,
                       BillingCountry,
                       Denial_Reasons_List__c,
                       Income_Upper_Limit__c
                FROM Account
                WHERE Id = :recordId
                LIMIT 1
            ];

            accountName = accountRecord.Name;
            accountAddress = buildAccountAddress(accountRecord);

            if (String.isNotBlank(accountRecord.Denial_Reasons_List__c)) {
                denialReasonsHtml = accountRecord.Denial_Reasons_List__c;
            } else {
                denialReasonsHtml = '';
            }

            incomeUpperLimit = formatIncomeUpperLimit(accountRecord.Income_Upper_Limit__c);
        } catch (Exception e) {
            accountName = null;
            accountAddress = null;
            denialReasonsHtml = '';
            incomeUpperLimit = '';
        }
    }

    public String buildAccountAddress(Account accountRecord) {
        List<String> addressLines;
        String cityStatePostalLine;

        if (accountRecord == null) {
            return null;
        }

        addressLines = new List<String>();
        if (String.isNotBlank(accountRecord.BillingStreet)) {
            addressLines.add(accountRecord.BillingStreet);
        }

        cityStatePostalLine = '';
        if (String.isNotBlank(accountRecord.BillingCity)) {
            cityStatePostalLine = accountRecord.BillingCity;
        }
        if (String.isNotBlank(accountRecord.BillingState)) {
            if (String.isNotBlank(cityStatePostalLine)) {
                cityStatePostalLine = cityStatePostalLine + ' ' + accountRecord.BillingState;
            } else {
                cityStatePostalLine = accountRecord.BillingState;
            }
        }
        if (String.isNotBlank(accountRecord.BillingPostalCode)) {
            if (String.isNotBlank(cityStatePostalLine)) {
                cityStatePostalLine = cityStatePostalLine + ' ' + accountRecord.BillingPostalCode;
            } else {
                cityStatePostalLine = accountRecord.BillingPostalCode;
            }
        }
        if (String.isNotBlank(cityStatePostalLine)) {
            addressLines.add(cityStatePostalLine);
        }

        if (addressLines.isEmpty()) {
            return null;
        }

        return String.join(addressLines, '\n');
    }

    public String formatIncomeUpperLimit(Decimal incomeUpperLimitValue) {
        if (incomeUpperLimitValue == null) {
            return '';
        }

        return '$' + String.valueOf(incomeUpperLimitValue.format());
    }
}