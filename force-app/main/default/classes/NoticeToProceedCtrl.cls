public without sharing class NoticeToProceedCtrl {

    public class NoticeData {
        @AuraEnabled public String projectLocation { get; set; }
        @AuraEnabled public String propertyOwner { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String contractor { get; set; }
        @AuraEnabled public String telephone { get; set; }
        @AuraEnabled public String contractorAddress { get; set; }
        @AuraEnabled public String contractDated { get; set; }
        @AuraEnabled public String projectedStartDate { get; set; }
        @AuraEnabled public String projectedCompletionDate { get; set; }
        @AuraEnabled public String organizationName { get; set; }
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
    public static NoticeData getNoticeData(Id recordId) {
        NoticeData data = new NoticeData();
        if (recordId == null) {
            return data;
        }

        try {
            Map<String, Schema.SObjectField> fieldMap = buildertek__Project__c.SObjectType.getDescribe().fields.getMap();
            List<String> queryFields = new List<String>{
                'Id',
                'buildertek__Address__c',
                'buildertek__City_Text__c',
                'buildertek__State__c',
                'buildertek__Zip__c',
                'buildertek__Country__c',
                'buildertek__Customer__r.Name'
            };

            List<String> optionalFields = new List<String>{
                'Case_No__c',
                'buildertek__Case_No__c',
                'General_Contractor__r.Name',
                'buildertek__General_Contractor__r.Name',
                'General_Contractor__c',
                'buildertek__General_Contractor__c',
                'Contractor__c',
                'buildertek__Contractor__c',
                'General_Contractor_Phone__c',
                'buildertek__General_Contractor_Phone__c',
                'Contractor_Phone__c',
                'buildertek__Contractor_Phone__c',
                'General_Contractor_Address__c',
                'buildertek__General_Contractor_Address__c',
                'Contractor_Address__c',
                'buildertek__Contractor_Address__c',
                'buildertek__Project_Start_Date__c',
                'buildertek__Project_Completion_Date__c',
                'Projected_Start_Date__c',
                'buildertek__Projected_Start_Date__c',
                'Projected_Completion_Date__c',
                'buildertek__Projected_Completion_Date__c',
                'buildertek__Contract_Date__c',
                'Contract_Dated__c',
                'buildertek__Contract_Dated__c'
            };

            for (String optionalField : optionalFields) {
                if ((optionalField != null && optionalField.contains('.')) || fieldMap.containsKey(optionalField)) {
                    queryFields.add(optionalField);
                }
            }

            String soql = 'SELECT ' + String.join(queryFields, ',') + ' FROM buildertek__Project__c WHERE Id = :recordId LIMIT 1';
            SObject recordSObj = Database.query(soql);

            String address = (String) recordSObj.get('buildertek__Address__c');
            String city = (String) recordSObj.get('buildertek__City_Text__c');
            String state = (String) recordSObj.get('buildertek__State__c');
            String zip = (String) recordSObj.get('buildertek__Zip__c');
            String country = (String) recordSObj.get('buildertek__Country__c');

            data.projectLocation =
                safe(address) + ', ' +
                safe(city) + (String.isBlank(city) || String.isBlank(state) ? '' : ' ') + safe(state) +
                (String.isBlank(zip) ? '' : ' - ' + zip) +
                (String.isBlank(country) ? '' : ', ' + country);

            SObject customerRef = recordSObj.getSObject('buildertek__Customer__r');
            data.propertyOwner = customerRef != null ? safe((String) customerRef.get('Name')) : '';

            data.caseNumber = firstAvailableValue(recordSObj, new List<String>{'Case_No__c', 'buildertek__Case_No__c'});
            data.contractor = firstAvailableValue(recordSObj, new List<String>{
                'General_Contractor__r.Name',
                'buildertek__General_Contractor__r.Name',
                'General_Contractor__c',
                'buildertek__General_Contractor__c',
                'Contractor__c',
                'buildertek__Contractor__c'
            });
            data.telephone = firstAvailableValue(recordSObj, new List<String>{'General_Contractor_Phone__c', 'buildertek__General_Contractor_Phone__c', 'Contractor_Phone__c', 'buildertek__Contractor_Phone__c'});
            data.contractorAddress = firstAvailableValue(recordSObj, new List<String>{'General_Contractor_Address__c', 'buildertek__General_Contractor_Address__c', 'Contractor_Address__c', 'buildertek__Contractor_Address__c'});

            Object contractDate = firstAvailableObject(recordSObj, new List<String>{
                'buildertek__Contract_Date__c',
                'Contract_Dated__c',
                'buildertek__Contract_Dated__c'
            });
            data.contractDated = formatDateValue(contractDate);

            Object startDate = firstAvailableObject(recordSObj, new List<String>{
                'buildertek__Project_Start_Date__c',
                'Projected_Start_Date__c',
                'buildertek__Projected_Start_Date__c'
            });
            data.projectedStartDate = formatDateValue(startDate);

            Object completionDate = firstAvailableObject(recordSObj, new List<String>{
                'buildertek__Project_Completion_Date__c',
                'Projected_Completion_Date__c',
                'buildertek__Projected_Completion_Date__c'
            });
            data.projectedCompletionDate = formatDateValue(completionDate);

            data.organizationName = [SELECT Name FROM Organization LIMIT 1].Name;
        } catch (Exception e) {
            // Return partial/empty data safely to avoid blocking preview rendering.
        }

        return data;
    }

    @AuraEnabled
    public static Map<String, String> saveSignature(Id recordId, String signatureBody) {
        try {
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Notice To Proceed Signature';
            cv.PathOnClient = 'NoticeToProceedSignature.png';
            cv.VersionData = EncodingUtil.base64Decode(signatureBody);
            cv.IsMajorVersion = true;
            insert cv;

            ContentDistribution cd = new ContentDistribution();
            cd.Name = 'Notice To Proceed Signature';
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
    public static String savePdf(Id recordId, String senderId, String sendDate, String imgUrl, String signerName, String signatureId) {
        try {
            PageReference pdfPage = Page.NoticeToProceedAsPDF;
            pdfPage.getParameters().put('recordId', recordId);
            pdfPage.getParameters().put('senderId', senderId);
            pdfPage.getParameters().put('sendDate', sendDate);
            pdfPage.getParameters().put('imgUrl', imgUrl);
            pdfPage.getParameters().put('signerName', signerName);

            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Test PDF');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            ContentVersion pdfCv = new ContentVersion();
            pdfCv.Title = 'Notice To Proceed ' + System.now().format('MM-dd-yyyy') + '.pdf';
            pdfCv.PathOnClient = 'NoticeToProceed.pdf';
            pdfCv.VersionData = pdfBlob;
            pdfCv.IsMajorVersion = true;
            insert pdfCv;

            Id pdfDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :pdfCv.Id LIMIT 1].ContentDocumentId;
            ContentDocumentLink pdfCdl = new ContentDocumentLink();
            pdfCdl.ContentDocumentId = pdfDocId;
            pdfCdl.LinkedEntityId = recordId;
            pdfCdl.ShareType = 'V';
            insert pdfCdl;

            buildertek__Project__c proj = new buildertek__Project__c(Id = recordId);
            proj.Notice_To_Proceed_Submitted__c = true;
            proj.Notice_To_Proceed_Submitted_Date__c = Date.today();
            update proj;

            cleanupSignatureFile(signatureId);
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
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

    private static String firstAvailableValue(SObject source, List<String> candidates) {
        Object value = firstAvailableObject(source, candidates);
        return value == null ? '' : String.valueOf(value);
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

    public NoticeData vfNoticeData { get; set; }
    public String vfRecordId { get; set; }
    public String vfImgUrl { get; set; }
    public String vfSignerName { get; set; }
    public String logoUrl { get; set; }
    public String currentRecordDate { get; set; }

    public NoticeToProceedCtrl() {
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
        vfImgUrl = ApexPages.currentPage().getParameters().get('imgUrl');
        vfSignerName = ApexPages.currentPage().getParameters().get('signerName');

        vfNoticeData = getNoticeData(vfRecordId);
        if (vfNoticeData == null) {
            vfNoticeData = new NoticeData();
        }
        logoUrl = getLogoUrl();
        currentRecordDate = System.now().format('MM-dd-yyyy');
    }
}
