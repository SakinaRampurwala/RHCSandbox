public without sharing class FinalInspectionFormCtrl {

    public class FinalInspectionData {
        @AuraEnabled public String homeownerName { get; set; }
        @AuraEnabled public String homeownerStreet { get; set; }
        @AuraEnabled public String homeownerCity { get; set; }
        @AuraEnabled public String homeownerState { get; set; }
        @AuraEnabled public String homeownerPostal { get; set; }
        @AuraEnabled public String homeownerCountry { get; set; }
        @AuraEnabled public String finalInspectionDate { get; set; }
        @AuraEnabled public Boolean isFinalInspectionSubmitted { get; set; }
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

    @AuraEnabled(cacheable=true)
    public static FinalInspectionData getFinalInspectionData(Id recordId) {
        FinalInspectionData data = new FinalInspectionData();
        data.isFinalInspectionSubmitted = false;
        if (recordId == null) {
            return data;
        }

        try {
            Map<String, Schema.SObjectField> fieldMap = buildertek__Project__c.SObjectType.getDescribe().fields.getMap();
            List<String> queryFields = new List<String>{
                'Id',
                'buildertek__Customer__r.Name',
                'buildertek__Customer__r.BillingStreet',
                'buildertek__Customer__r.BillingCity',
                'buildertek__Customer__r.BillingState',
                'buildertek__Customer__r.BillingPostalCode',
                'buildertek__Customer__r.BillingCountry'
            };

            List<String> optionalFields = new List<String>{
                'buildertek__Project_Completion_Date__c',
                'Final_Inspection_Date__c',
                'buildertek__Final_Inspection_Date__c',
                'Final_Inspection_Submitted__c',
                'buildertek__Final_Inspection_Submitted__c'
            };

            for (String optionalField : optionalFields) {
                if (isQueryableField(fieldMap, optionalField)) {
                    queryFields.add(optionalField);
                }
            }

            String soql = 'SELECT ' + String.join(queryFields, ',') + ' FROM buildertek__Project__c WHERE Id = :recordId LIMIT 1';
            SObject recordSObj = Database.query(soql);

            SObject customerRef = recordSObj.getSObject('buildertek__Customer__r');
            data.homeownerName = customerRef != null ? safe((String) customerRef.get('Name')) : '';

            String billingStreet = customerRef != null ? (String) customerRef.get('BillingStreet') : null;
            String billingCity = customerRef != null ? (String) customerRef.get('BillingCity') : null;
            String billingState = customerRef != null ? (String) customerRef.get('BillingState') : null;
            String billingPostal = customerRef != null ? (String) customerRef.get('BillingPostalCode') : null;
            String billingCountry = customerRef != null ? (String) customerRef.get('BillingCountry') : null;

            data.homeownerStreet = billingStreet;
            data.homeownerCity = billingCity;
            data.homeownerState = billingState;
            data.homeownerPostal = billingPostal;
            data.homeownerCountry = billingCountry;

            Object inspectionDate = firstAvailableObject(recordSObj, new List<String>{
                'Final_Inspection_Date__c',
                'buildertek__Final_Inspection_Date__c',
                'buildertek__Project_Completion_Date__c'
            });
            data.finalInspectionDate = formatDateValue(inspectionDate);

            Object submittedValue = firstAvailableObject(recordSObj, new List<String>{
                'Final_Inspection_Submitted__c',
                'buildertek__Final_Inspection_Submitted__c'
            });
            data.isFinalInspectionSubmitted = submittedValue instanceof Boolean ? (Boolean) submittedValue : false;
        } catch (Exception e) {
            // Return partial/empty data safely to avoid blocking preview rendering.
        }

        return data;
    }

    @AuraEnabled
    public static Map<String, String> saveSignature(Id recordId, String signatureBody, String signatureLabel) {
        try {
            ContentVersion cv = new ContentVersion();
            String safeLabel = String.isBlank(signatureLabel) ? 'Signature' : signatureLabel + ' Signature';
            String fileToken = safeLabel.replaceAll('[^A-Za-z0-9]+', '');
            if (String.isBlank(fileToken)) {
                fileToken = 'Signature';
            }
            cv.Title = 'Final Inspection ' + safeLabel;
            cv.PathOnClient = 'FinalInspection' + fileToken + '.png';
            cv.VersionData = EncodingUtil.base64Decode(signatureBody);
            cv.IsMajorVersion = true;
            insert cv;

            ContentDistribution cd = new ContentDistribution();
            cd.Name = 'Final Inspection ' + safeLabel;
            cd.ContentVersionId = cv.Id;
            cd.PreferencesAllowViewInBrowser = true;
            Database.SaveResult cdResult = Database.insert(cd, false);

            Map<String, String> result = new Map<String, String>();
            if (cdResult.isSuccess()) {
                ContentDistribution savedCd = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :cdResult.getId() LIMIT 1];
                result.put('imgUrl', savedCd.ContentDownloadUrl);
            } else {
                result.put('imgUrl', '');
            }
            result.put('cvId', cv.Id);
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving signature: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String savePdf(
        Id recordId,
        String senderId,
        String sendDate,
        String homeownerImgUrl,
        String representativeImgUrl,
        String homeownerSignatureId,
        String representativeSignatureId
    ) {
        try {
            PageReference pdfPage = Page.FinalInspectionFormAsPDF;
            pdfPage.getParameters().put('recordId', recordId);
            pdfPage.getParameters().put('senderId', senderId);
            pdfPage.getParameters().put('sendDate', sendDate);
            pdfPage.getParameters().put('homeownerImgUrl', homeownerImgUrl);
            pdfPage.getParameters().put('representativeImgUrl', representativeImgUrl);

            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Test PDF');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            ContentVersion pdfCv = new ContentVersion();
            pdfCv.Title = 'Final Inspection ' + System.now().format('MM-dd-yyyy') + '.pdf';
            pdfCv.PathOnClient = 'FinalInspection.pdf';
            pdfCv.VersionData = pdfBlob;
            pdfCv.IsMajorVersion = true;
            insert pdfCv;

            Id pdfDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :pdfCv.Id LIMIT 1].ContentDocumentId;
            ContentDocumentLink pdfCdl = new ContentDocumentLink();
            pdfCdl.ContentDocumentId = pdfDocId;
            pdfCdl.LinkedEntityId = recordId;
            pdfCdl.ShareType = 'V';
            insert pdfCdl;

            updateFinalInspectionFields(recordId);

            cleanupSignatureFile(homeownerSignatureId);
            cleanupSignatureFile(representativeSignatureId);
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static void updateFinalInspectionFields(Id recordId) {
        if (recordId == null) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = buildertek__Project__c.SObjectType.getDescribe().fields.getMap();
        buildertek__Project__c proj = new buildertek__Project__c(Id = recordId);
        Boolean shouldUpdate = false;

        shouldUpdate = setFirstAvailableField(proj, fieldMap, new List<String>{
            'Final_Inspection_Submitted__c',
            'buildertek__Final_Inspection_Submitted__c'
        }, true) || shouldUpdate;

        shouldUpdate = setFirstAvailableField(proj, fieldMap, new List<String>{
            'Final_Inspection_Submitted_Date__c',
            'buildertek__Final_Inspection_Submitted_Date__c'
        }, Date.today()) || shouldUpdate;

        if (shouldUpdate) {
            update proj;
        }
    }

    private static Boolean setFirstAvailableField(SObject target, Map<String, Schema.SObjectField> fieldMap, List<String> candidates, Object value) {
        if (target == null || fieldMap == null || candidates == null) {
            return false;
        }
        for (String apiName : candidates) {
            if (fieldMap.containsKey(apiName)) {
                target.put(apiName, value);
                return true;
            }
        }
        return false;
    }

    private static void cleanupSignatureFile(String signatureId) {
        if (String.isBlank(signatureId)) {
            return;
        }

        List<ContentVersion> versions = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :signatureId LIMIT 1];
        if (!versions.isEmpty()) {
            Database.delete(versions[0].ContentDocumentId, false);
        }
    }

    private static Object firstAvailableObject(SObject source, List<String> candidates) {
        if (source == null || candidates == null) {
            return null;
        }

        Map<String, Object> values = source.getPopulatedFieldsAsMap();
        for (String apiName : candidates) {
            if (apiName != null && apiName.contains('.')) {
                List<String> parts = apiName.split('\\.');
                if (parts.size() == 2) {
                    SObject parentObj = source.getSObject(parts[0]);
                    if (parentObj != null) {
                        Object nestedValue = parentObj.get(parts[1]);
                        if (nestedValue != null) {
                            return nestedValue;
                        }
                    }
                }
                continue;
            }
            if (values.containsKey(apiName)) {
                return values.get(apiName);
            }
        }
        return null;
    }

    private static Boolean isQueryableField(Map<String, Schema.SObjectField> fieldMap, String fieldPath) {
        if (String.isBlank(fieldPath)) {
            return false;
        }
        if (!fieldPath.contains('.')) {
            return fieldMap.containsKey(fieldPath);
        }

        List<String> parts = fieldPath.split('\\.');
        if (parts.size() != 2) {
            return false;
        }

        String relationshipToken = parts[0];
        if (relationshipToken.endsWith('__r')) {
            String lookupField = relationshipToken.substring(0, relationshipToken.length() - 3) + '__c';
            return fieldMap.containsKey(lookupField);
        }

        return true;
    }

    private static String formatDateValue(Object dateValue) {
        if (dateValue == null) {
            return '';
        }

        if (dateValue instanceof Date) {
            return ((Date) dateValue).format();
        }
        if (dateValue instanceof Datetime) {
            return ((Datetime) dateValue).format('MM-dd-yyyy');
        }
        return String.valueOf(dateValue);
    }

    private static String safe(String input) {
        return input == null ? '' : input;
    }

    public String isPreview { get; set; }
    public String recordId { get; set; }
    public String senderId { get; set; }
    public String sendDate { get; set; }

    public FinalInspectionData vfInspectionData { get; set; }
    public String vfRecordId { get; set; }
    public String vfHomeownerImgUrl { get; set; }
    public String vfRepresentativeImgUrl { get; set; }
    public String logoUrl { get; set; }
    public String currentRecordDate { get; set; }

    public FinalInspectionFormCtrl() {
        isPreview = ApexPages.currentPage().getParameters().get('isPreview');
        recordId = ApexPages.currentPage().getParameters().get('Id');
        if (recordId == null) {
            recordId = ApexPages.currentPage().getParameters().get('recordId');
        }
        senderId = ApexPages.currentPage().getParameters().get('senderId');
        sendDate = ApexPages.currentPage().getParameters().get('sendDate');
    }

    public void initPdf() {
        vfRecordId = ApexPages.currentPage().getParameters().get('recordId');
        vfHomeownerImgUrl = ApexPages.currentPage().getParameters().get('homeownerImgUrl');
        vfRepresentativeImgUrl = ApexPages.currentPage().getParameters().get('representativeImgUrl');

        vfInspectionData = getFinalInspectionData(vfRecordId);
        if (vfInspectionData == null) {
            vfInspectionData = new FinalInspectionData();
        }
        logoUrl = getLogoUrl();
        currentRecordDate = System.now().format('MM-dd-yyyy');
    }
}
