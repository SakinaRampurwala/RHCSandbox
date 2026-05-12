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
        @AuraEnabled public String homeownerSignatureUrl { get; set; }
        @AuraEnabled public String representativeSignatureUrl { get; set; }
        @AuraEnabled public Boolean homeownerSigned { get; set; }
        @AuraEnabled public Boolean representativeSigned { get; set; }
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
        return getFinalInspectionData(recordId, false);
    }

    public static FinalInspectionData getFinalInspectionData(Id recordId, Boolean skipSignatureDml) {
        FinalInspectionData data = new FinalInspectionData();
        data.isFinalInspectionSubmitted = false;
        if (recordId == null) {
            return data;
        }

        try {
            Map<String, Schema.SObjectField> fieldMap = buildertek__Inspection__c.SObjectType.getDescribe().fields.getMap();
            List<String> queryFields = new List<String>{ 'Id' };

            List<String> optionalFields = new List<String>{
                'buildertek__Project__c',
                'buildertek__Inspection_Date__c',
                'buildertek__Property_Street__c',
                'buildertek__Property_City__c',
                'buildertek__Property_State__c',
                'buildertek__Property_Zip__c',
                'FI_Homeowner_Sign_Id__c',
                'FI_Homeowner_Sign_Date__c',
                'FI_Representative_Sign_Id__c',
                'FI_Representative_Sign_Date__c'
            };

            for (String optionalField : optionalFields) {
                if (isQueryableField(fieldMap, optionalField)) {
                    queryFields.add(optionalField);
                }
            }

            String soql = 'SELECT ' + String.join(queryFields, ',') + ' FROM buildertek__Inspection__c WHERE Id = :recordId LIMIT 1';
            SObject recordSObj = Database.query(soql);

            Id projectId = fieldMap.containsKey('buildertek__Project__c')
                ? (Id) recordSObj.get('buildertek__Project__c')
                : null;
            SObject projectRecord = getRelatedProjectRecord(projectId);
            SObject customerRef = projectRecord != null ? projectRecord.getSObject('buildertek__Customer__r') : null;
            data.homeownerName = customerRef != null ? safe((String) customerRef.get('Name')) : '';

            String billingStreet = customerRef != null ? safe((String) customerRef.get('BillingStreet')) : '';
            String billingCity = customerRef != null ? safe((String) customerRef.get('BillingCity')) : '';
            String billingState = customerRef != null ? safe((String) customerRef.get('BillingState')) : '';
            String billingPostal = customerRef != null ? safe((String) customerRef.get('BillingPostalCode')) : '';
            String billingCountry = customerRef != null ? safe((String) customerRef.get('BillingCountry')) : '';
            if (String.isBlank(billingStreet) && String.isBlank(billingCity) && String.isBlank(billingState)
                && String.isBlank(billingPostal) && String.isBlank(billingCountry)) {
                data.homeownerStreet = projectRecord != null ? safe((String) projectRecord.get('buildertek__Address__c')) : '';
                data.homeownerCity = projectRecord != null ? safe((String) projectRecord.get('buildertek__City_Text__c')) : '';
                data.homeownerState = projectRecord != null ? safe((String) projectRecord.get('buildertek__State__c')) : '';
                data.homeownerPostal = projectRecord != null ? safe((String) projectRecord.get('buildertek__Zip__c')) : '';
                data.homeownerCountry = projectRecord != null ? safe((String) projectRecord.get('buildertek__Country__c')) : '';
            } else {
                data.homeownerStreet = billingStreet;
                data.homeownerCity = billingCity;
                data.homeownerState = billingState;
                data.homeownerPostal = billingPostal;
                data.homeownerCountry = billingCountry;
            }

            Object inspectionDate = fieldMap.containsKey('buildertek__Inspection_Date__c')
                ? recordSObj.get('buildertek__Inspection_Date__c')
                : null;
            data.finalInspectionDate = formatDateValue(inspectionDate);

            String homeownerSignId = fieldMap.containsKey('FI_Homeowner_Sign_Id__c')
                ? (String) recordSObj.get('FI_Homeowner_Sign_Id__c')
                : null;
            String representativeSignId = fieldMap.containsKey('FI_Representative_Sign_Id__c')
                ? (String) recordSObj.get('FI_Representative_Sign_Id__c')
                : null;

            data.homeownerSigned = String.isNotBlank(homeownerSignId);
            data.representativeSigned = String.isNotBlank(representativeSignId);

            String homeownerVersionId = resolveContentVersionId(homeownerSignId);
            if (String.isNotBlank(homeownerVersionId) && !skipSignatureDml) {
                data.homeownerSignatureUrl = getOrCreateDistributionUrl((Id) homeownerVersionId);
            }

            String representativeVersionId = resolveContentVersionId(representativeSignId);
            if (String.isNotBlank(representativeVersionId) && !skipSignatureDml) {
                data.representativeSignatureUrl = getOrCreateDistributionUrl((Id) representativeVersionId);
            }

            data.isFinalInspectionSubmitted = isPdfAlreadySaved(recordId);
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
            updateSignatureFields(recordId, signatureLabel, cv.Id);

            try {
                Id contentDocId = [
                    SELECT ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :cv.Id
                    LIMIT 1
                ].ContentDocumentId;
                if (recordId != null && contentDocId != null) {
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.ContentDocumentId = contentDocId;
                    cdl.LinkedEntityId = recordId;
                    cdl.ShareType = 'V';
                    cdl.Visibility = 'AllUsers';
                    Database.insert(cdl, false);
                }
            } catch (Exception e) {
                // Do not block signature save if linking fails
            }

            ContentDistribution cd = new ContentDistribution();
            cd.Name = 'Final Inspection ' + safeLabel;
            cd.ContentVersionId = cv.Id;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesNotifyOnVisit = false;
            Database.SaveResult cdResult = Database.insert(cd, false);

            Map<String, String> result = new Map<String, String>();
            String fallbackUrl = buildVersionDownloadUrl(cv.Id);
            if (cdResult.isSuccess()) {
                ContentDistribution savedCd = [
                    SELECT ContentDownloadUrl
                    FROM ContentDistribution
                    WHERE Id = :cdResult.getId()
                    LIMIT 1
                ];
                result.put('imgUrl', String.isNotBlank(savedCd.ContentDownloadUrl) ? savedCd.ContentDownloadUrl : fallbackUrl);
            } else {
                result.put('imgUrl', fallbackUrl);
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
            if (recordId == null) {
                throw new AuraHandledException('Record Id is required.');
            }

            if (isFinalInspectionAlreadySubmitted(recordId)) {
                return 'Already Submitted';
            }

            SignatureBundle resolved = resolveSignatureBundle(
                recordId,
                homeownerImgUrl,
                representativeImgUrl,
                homeownerSignatureId,
                representativeSignatureId
            );

            if (String.isBlank(resolved.homeownerImgUrl) || String.isBlank(resolved.representativeImgUrl)) {
                return 'Missing Signatures';
            }

            PageReference pdfPage = Page.FinalInspectionFormAsPDF;
            pdfPage.getParameters().put('recordId', recordId);
            pdfPage.getParameters().put('senderId', senderId);
            pdfPage.getParameters().put('sendDate', sendDate);
            pdfPage.getParameters().put('homeownerImgUrl', resolved.homeownerImgUrl);
            pdfPage.getParameters().put('representativeImgUrl', resolved.representativeImgUrl);

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
            pdfCdl.Visibility = 'AllUsers';
            insert pdfCdl;

            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class SignatureBundle {
        public String homeownerImgUrl { get; set; }
        public String representativeImgUrl { get; set; }
        public String homeownerSignatureId { get; set; }
        public String representativeSignatureId { get; set; }
    }

    public class SignatureInfo {
        public String contentVersionId { get; set; }
        public String imgUrl { get; set; }
    }

    public class SignatureFieldValues {
        public String homeownerSignId { get; set; }
        public String representativeSignId { get; set; }
    }

    public static SignatureBundle resolveSignatureBundle(
        Id recordId,
        String homeownerImgUrl,
        String representativeImgUrl,
        String homeownerSignatureId,
        String representativeSignatureId
    ) {
        SignatureBundle bundle = new SignatureBundle();
        bundle.homeownerImgUrl = homeownerImgUrl;
        bundle.representativeImgUrl = representativeImgUrl;
        bundle.homeownerSignatureId = homeownerSignatureId;
        bundle.representativeSignatureId = representativeSignatureId;

        SignatureFieldValues fieldValues = getSignatureFieldValues(recordId);
        if (String.isBlank(bundle.homeownerSignatureId) && fieldValues != null) {
            bundle.homeownerSignatureId = fieldValues.homeownerSignId;
        }
        if (String.isBlank(bundle.representativeSignatureId) && fieldValues != null) {
            bundle.representativeSignatureId = fieldValues.representativeSignId;
        }

        String resolvedHomeownerVersionId = resolveContentVersionId(bundle.homeownerSignatureId);
        if (String.isNotBlank(resolvedHomeownerVersionId)) {
            bundle.homeownerSignatureId = resolvedHomeownerVersionId;
        }

        if (String.isBlank(bundle.homeownerImgUrl)
            && String.isNotBlank(bundle.homeownerSignatureId)
            && isValidIdFormat(bundle.homeownerSignatureId)) {
            bundle.homeownerImgUrl = getOrCreateDistributionUrl((Id) bundle.homeownerSignatureId);
        }
        String resolvedRepresentativeVersionId = resolveContentVersionId(bundle.representativeSignatureId);
        if (String.isNotBlank(resolvedRepresentativeVersionId)) {
            bundle.representativeSignatureId = resolvedRepresentativeVersionId;
        }

        if (String.isBlank(bundle.representativeImgUrl)
            && String.isNotBlank(bundle.representativeSignatureId)
            && isValidIdFormat(bundle.representativeSignatureId)) {
            bundle.representativeImgUrl = getOrCreateDistributionUrl((Id) bundle.representativeSignatureId);
        }

        return bundle;
    }

    public static SignatureFieldValues getSignatureFieldValues(Id recordId) {
        SignatureFieldValues values = new SignatureFieldValues();
        if (recordId == null) {
            return values;
        }

        Map<String, Schema.SObjectField> fieldMap = buildertek__Inspection__c.SObjectType.getDescribe().fields.getMap();
        List<String> queryFields = new List<String>{ 'Id' };
        if (fieldMap.containsKey('FI_Homeowner_Sign_Id__c')) {
            queryFields.add('FI_Homeowner_Sign_Id__c');
        }
        if (fieldMap.containsKey('FI_Representative_Sign_Id__c')) {
            queryFields.add('FI_Representative_Sign_Id__c');
        }

        if (queryFields.size() == 1) {
            return values;
        }

        SObject recordSObj = Database.query(
            'SELECT ' + String.join(queryFields, ',') + ' FROM buildertek__Inspection__c WHERE Id = :recordId LIMIT 1'
        );
        values.homeownerSignId = fieldMap.containsKey('FI_Homeowner_Sign_Id__c')
            ? (String) recordSObj.get('FI_Homeowner_Sign_Id__c')
            : null;
        values.representativeSignId = fieldMap.containsKey('FI_Representative_Sign_Id__c')
            ? (String) recordSObj.get('FI_Representative_Sign_Id__c')
            : null;
        return values;
    }

    public static Map<String, SignatureInfo> getFinalInspectionSignatures(Id recordId) {
        Map<String, SignatureInfo> results = new Map<String, SignatureInfo>();
        if (recordId == null) {
            return results;
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ];
        if (links.isEmpty()) {
            return results;
        }

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            docIds.add(link.ContentDocumentId);
        }

        Set<String> titles = new Set<String>{
            'Final Inspection Homeowner Signature',
            'Final Inspection Program Representative Signature'
        };

        List<ContentVersion> versions = [
            SELECT Id, Title, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
            AND Title IN :titles
            ORDER BY CreatedDate DESC
        ];

        Map<String, String> titleToVersion = new Map<String, String>();
        for (ContentVersion version : versions) {
            if (!titleToVersion.containsKey(version.Title)) {
                titleToVersion.put(version.Title, version.Id);
            }
        }

        Set<Id> versionIds = new Set<Id>();
        for (String versionId : titleToVersion.values()) {
            versionIds.add((Id) versionId);
        }

        Map<Id, String> versionToUrl = new Map<Id, String>();
        if (!versionIds.isEmpty()) {
            for (ContentDistribution cd : [
                SELECT ContentVersionId, ContentDownloadUrl
                FROM ContentDistribution
                WHERE ContentVersionId IN :versionIds
                ORDER BY CreatedDate DESC
            ]) {
                if (!versionToUrl.containsKey(cd.ContentVersionId) && String.isNotBlank(cd.ContentDownloadUrl)) {
                    versionToUrl.put(cd.ContentVersionId, cd.ContentDownloadUrl);
                }
            }
        }

        for (String title : titleToVersion.keySet()) {
            Id versionId = (Id) titleToVersion.get(title);
            SignatureInfo info = new SignatureInfo();
            info.contentVersionId = versionId;
            if (versionToUrl.containsKey(versionId)) {
                info.imgUrl = versionToUrl.get(versionId);
            }

            if (title == 'Final Inspection Homeowner Signature') {
                results.put('Homeowner', info);
            } else if (title == 'Final Inspection Program Representative Signature') {
                results.put('Program Representative', info);
            }
        }

        return results;
    }

    public static String getOrCreateDistributionUrl(Id contentVersionId) {
        if (contentVersionId == null) {
            return '';
        }

        String fallbackUrl = buildVersionDownloadUrl(contentVersionId);

        List<ContentDistribution> existing = [
            SELECT ContentDownloadUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :contentVersionId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!existing.isEmpty() && String.isNotBlank(existing[0].ContentDownloadUrl)) {
            return existing[0].ContentDownloadUrl;
        }

        ContentDistribution cd = new ContentDistribution();
        cd.Name = 'Final Inspection Signature';
        cd.ContentVersionId = contentVersionId;
        cd.PreferencesAllowViewInBrowser = true;
        cd.PreferencesNotifyOnVisit = false;
        Database.SaveResult sr = Database.insert(cd, false);
        if (sr.isSuccess()) {
            ContentDistribution saved = [
                SELECT ContentDownloadUrl
                FROM ContentDistribution
                WHERE Id = :sr.getId()
                LIMIT 1
            ];
            return String.isNotBlank(saved.ContentDownloadUrl) ? saved.ContentDownloadUrl : fallbackUrl;
        }

        return fallbackUrl;
    }

    public static String buildVersionDownloadUrl(Id contentVersionId) {
        if (contentVersionId == null) {
            return '';
        }
        String baseUrl = getConfirmationSiteUrl();
        if (String.isBlank(baseUrl)) {
            baseUrl = URL.getOrgDomainUrl().toExternalForm();
        }
        return baseUrl + '/sfc/servlet.shepherd/version/download/' + contentVersionId;
    }

    public static String resolveContentVersionId(String idVal) {
        if (String.isBlank(idVal) || !isValidIdFormat(idVal)) {
            return null;
        }

        List<ContentVersion> byVersion = [
            SELECT Id
            FROM ContentVersion
            WHERE Id = :idVal
            LIMIT 1
        ];
        if (!byVersion.isEmpty()) {
            return byVersion[0].Id;
        }

        List<ContentVersion> byDocument = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId = :idVal
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!byDocument.isEmpty()) {
            return byDocument[0].Id;
        }

        return null;
    }

    public static Boolean isFinalInspectionAlreadySubmitted(Id recordId) {
        if (recordId == null) {
            return false;
        }

        return isPdfAlreadySaved(recordId);
    }

    public static Boolean isPdfAlreadySaved(Id recordId) {
        if (recordId == null) {
            return false;
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title, ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ];

        for (ContentDocumentLink link : links) {
            if (link.ContentDocument != null
                && link.ContentDocument.FileType == 'PDF'
                && link.ContentDocument.Title != null
                && link.ContentDocument.Title.startsWith('Final Inspection ')) {
                return true;
            }
        }

        return false;
    }

    public static void cleanupSignatureFile(String signatureId) {
        if (String.isBlank(signatureId)) {
            return;
        }

        List<ContentVersion> versions = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :signatureId LIMIT 1];
        if (!versions.isEmpty()) {
            Database.delete(versions[0].ContentDocumentId, false);
        }
    }

    public static Object firstAvailableObject(SObject source, List<String> candidates) {
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

    public static SObject getRelatedProjectRecord(Id projectId) {
        if (projectId == null) {
            return null;
        }

        Map<String, Schema.SObjectField> projectFieldMap = buildertek__Project__c.SObjectType.getDescribe().fields.getMap();
        List<String> queryFields = new List<String>{ 'Id' };
        List<String> candidateFields = new List<String>{
            'buildertek__Address__c',
            'buildertek__City_Text__c',
            'buildertek__State__c',
            'buildertek__Zip__c',
            'buildertek__Country__c',
            'buildertek__Customer__r.Name',
            'buildertek__Customer__r.BillingStreet',
            'buildertek__Customer__r.BillingCity',
            'buildertek__Customer__r.BillingState',
            'buildertek__Customer__r.BillingPostalCode',
            'buildertek__Customer__r.BillingCountry'
        };

        for (String fieldPath : candidateFields) {
            if (isQueryableField(projectFieldMap, fieldPath)) {
                queryFields.add(fieldPath);
            }
        }

        List<SObject> records = Database.query(
            'SELECT ' + String.join(queryFields, ',') + ' FROM buildertek__Project__c WHERE Id = :projectId LIMIT 1'
        );
        return records.isEmpty() ? null : records[0];
    }

    public static Boolean isQueryableField(Map<String, Schema.SObjectField> fieldMap, String fieldPath) {
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

    public static String formatDateValue(Object dateValue) {
        if (dateValue == null) {
            return '';
        }

        if (dateValue instanceof Date) {
            Date onlyDate = (Date) dateValue;
            return DateTime.newInstance(onlyDate, Time.newInstance(0, 0, 0, 0)).format('MM-dd-yyyy');
        }
        if (dateValue instanceof Datetime) {
            return ((Datetime) dateValue).format('MM-dd-yyyy');
        }
        return String.valueOf(dateValue);
    }

    public static String safe(String input) {
        return input == null ? '' : input;
    }

    public static void updateSignatureFields(Id recordId, String signatureLabel, Id contentVersionId) {
        if (recordId == null || contentVersionId == null) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = buildertek__Inspection__c.SObjectType.getDescribe().fields.getMap();
        buildertek__Inspection__c inspectionRecord = new buildertek__Inspection__c(Id = recordId);
        Boolean shouldUpdate = false;

        if (signatureLabel == 'Homeowner') {
            if (fieldMap.containsKey('FI_Homeowner_Sign_Id__c')) {
                inspectionRecord.put('FI_Homeowner_Sign_Id__c', contentVersionId);
                shouldUpdate = true;
            }
            if (fieldMap.containsKey('FI_Homeowner_Sign_Date__c')) {
                inspectionRecord.put('FI_Homeowner_Sign_Date__c', Date.today());
                shouldUpdate = true;
            }
        } else if (signatureLabel == 'Program Representative') {
            if (fieldMap.containsKey('FI_Representative_Sign_Id__c')) {
                inspectionRecord.put('FI_Representative_Sign_Id__c', contentVersionId);
                shouldUpdate = true;
            }
            if (fieldMap.containsKey('FI_Representative_Sign_Date__c')) {
                inspectionRecord.put('FI_Representative_Sign_Date__c', Date.today());
                shouldUpdate = true;
            }
        }

        if (shouldUpdate) {
            update inspectionRecord;
        }
    }

    @AuraEnabled
    public static String sendCompanyContactEmail(
        Id recordId,
        List<String> companyContactIds,
        List<String> companyEmails,
        String senderId,
        String sendDate,
        String fromAddressId,
        List<String> fileIds
    ) {
        if (recordId == null) {
            return 'Record Id is required';
        }

        List<Contact> contacts = new List<Contact>();
        if (companyContactIds != null && !companyContactIds.isEmpty()) {
            try {
                contacts = [
                    SELECT Id, Name, Email
                    FROM Contact
                    WHERE Id IN :companyContactIds
                ];
            } catch (Exception e) {
                contacts = new List<Contact>();
            }
        }

        List<String> emails = new List<String>();
        if (companyEmails != null) {
            for (String emailVal : companyEmails) {
                if (String.isNotBlank(emailVal)) {
                    emails.add(emailVal.trim());
                }
            }
        }

        if (contacts.isEmpty() && emails.isEmpty()) {
            return 'No program representative recipients found';
        }

        EmailTemplate template = [
            SELECT Subject, Body, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = 'Final_Inspection_Form'
            LIMIT 1
        ];

        String subject = template.Subject;
        String body = String.isNotBlank(template.HtmlValue) ? template.HtmlValue : template.Body;
        if (String.isBlank(body)) {
            body = '';
        }

        String link = buildFinalInspectionLink(recordId, senderId, sendDate, false, false, true);
        String linkMarkup = '<a href="' + link + '">Click here</a>';
        if (body.contains('{!URL}')) {
            body = body.replace('{!URL}', linkMarkup);
        }

        body = applyOrganizationMergeFields(body);

        List<Messaging.EmailFileAttachment> attachmentList = buildAttachments(fileIds);
        if (attachmentList == null) {
            return 'Total attachment size exceeds 25MB limit';
        }

        List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
        List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();

        if (!contacts.isEmpty()) {
            for (Contact contact : contacts) {
                if (contact == null || String.isBlank(contact.Email)) {
                    continue;
                }
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ contact.Email });
                applyOrgWideFromAddress(mail, fromAddressId);
                mail.setSubject(subject);
                mail.setHtmlBody(applyContactName(body, contact.Name));
                if (isValidIdFormat(String.valueOf(recordId))) {
                    mail.setWhatId(recordId);
                }
                if (!attachmentList.isEmpty()) {
                    mail.setFileAttachments(attachmentList);
                }

                batch.add(mail);
                if (batch.size() == 10) {
                    results.addAll(Messaging.sendEmail(batch));
                    batch.clear();
                }
            }
        } else {
            for (String emailVal : emails) {
                if (String.isBlank(emailVal)) {
                    continue;
                }
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ emailVal });
                applyOrgWideFromAddress(mail, fromAddressId);
                mail.setSubject(subject);
                mail.setHtmlBody(body);
                if (isValidIdFormat(String.valueOf(recordId))) {
                    mail.setWhatId(recordId);
                }
                if (!attachmentList.isEmpty()) {
                    mail.setFileAttachments(attachmentList);
                }

                batch.add(mail);
                if (batch.size() == 10) {
                    results.addAll(Messaging.sendEmail(batch));
                    batch.clear();
                }
            }
        }

        if (!batch.isEmpty()) {
            results.addAll(Messaging.sendEmail(batch));
        }

        if (results.isEmpty()) {
            return 'No valid program representative recipients found';
        }

        for (Messaging.SendEmailResult result : results) {
            if (!result.isSuccess()) {
                if (result.getErrors() != null && !result.getErrors().isEmpty()) {
                    return result.getErrors()[0].getMessage();
                }
                return 'Failed to send email';
            }
        }

        return 'Success';
    }

    public static String buildFinalInspectionLink(Id recordId, String senderId, String sendDate, Boolean isPreview, Boolean isVendor, Boolean isCompany) {
        String baseUrl = getConfirmationSiteUrl();
        String safeRecordId = recordId == null ? '' : String.valueOf(recordId);
        String link = baseUrl + '/apex/FinalInspectionForm?recordId=' + safeRecordId
            + '&isPreview=' + String.valueOf(isPreview);
        if (String.isNotBlank(senderId)) {
            link += '&senderId=' + EncodingUtil.urlEncode(senderId, 'UTF-8');
        }
        if (String.isNotBlank(sendDate)) {
            link += '&sendDate=' + EncodingUtil.urlEncode(sendDate, 'UTF-8');
        }
        link += '&isVendor=' + String.valueOf(isVendor);
        link += '&isCompany=' + String.valueOf(isCompany);
        return link;
    }

    public static List<Messaging.EmailFileAttachment> buildAttachments(List<String> fileIds) {
        List<Messaging.EmailFileAttachment> attachmentList = new List<Messaging.EmailFileAttachment>();
        if (fileIds == null || fileIds.isEmpty()) {
            return attachmentList;
        }

        List<ContentVersion> files = [
            SELECT Title, VersionData, ContentSize, FileType, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :fileIds AND IsLatest = true
        ];

        Integer totalSize = 0;
        for (ContentVersion file : files) {
            totalSize += file.ContentSize;
        }
        if (totalSize > 25 * 1024 * 1024) {
            return null;
        }

        for (ContentVersion file : files) {
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            String extension = String.isNotBlank(file.FileExtension)
                ? file.FileExtension
                : (file.FileType != null ? file.FileType.toLowerCase() : '');
            attachment.setFileName(extension != '' ? file.Title + '.' + extension : file.Title);
            attachment.setBody(file.VersionData);
            attachmentList.add(attachment);
        }

        return attachmentList;
    }

    public static void applyOrgWideFromAddress(Messaging.SingleEmailMessage mail, String fromAddressId) {
        if (String.isNotBlank(fromAddressId)) {
            mail.setOrgWideEmailAddressId(fromAddressId);
        }
    }

    public static String applyContactName(String body, String contactName) {
        if (String.isBlank(body) || String.isBlank(contactName)) {
            return body;
        }
        if (body.contains('{!ContactName}')) {
            return body.replace('{!ContactName}', contactName);
        }
        return body;
    }

    public static String getConfirmationSiteUrl() {
        buildertek__ConfirmationSiteURL__c settings = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
        if (settings != null && String.isNotBlank(settings.buildertek__Sites_URL__c)) {
            return settings.buildertek__Sites_URL__c;
        }
        return URL.getOrgDomainUrl().toExternalForm();
    }

    public static String applyOrganizationMergeFields(String body) {
        if (String.isBlank(body)) {
            return body;
        }

        Organization orgInfo = [SELECT Name, Street, City, State, PostalCode, Phone FROM Organization LIMIT 1];
        Map<String, String> values = new Map<String, String>{
            '{!$Organization.Name}' => safe(orgInfo.Name),
            '{!$Organization.Street}' => safe(orgInfo.Street),
            '{!$Organization.City}' => safe(orgInfo.City),
            '{!$Organization.State}' => safe(orgInfo.State),
            '{!$Organization.PostalCode}' => safe(orgInfo.PostalCode),
            '{!$Organization.Phone}' => safe(orgInfo.Phone)
        };

        for (String token : values.keySet()) {
            body = body.replace(token, values.get(token));
        }

        return body;
    }

    public static Boolean isValidIdFormat(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        return Pattern.matches('^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$', value);
    }

    public String isPreview { get; set; }
    public String recordId { get; set; }
    public String senderId { get; set; }
    public String sendDate { get; set; }

    public FinalInspectionData vfInspectionData { get; set; }
    public String vfRecordId { get; set; }
    public String vfHomeownerImgUrl { get; set; }
    public String vfRepresentativeImgUrl { get; set; }
    public String vfHomeownerAddress { get; set; }
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
        if (String.isBlank(vfRecordId)) {
            vfRecordId = ApexPages.currentPage().getParameters().get('Id');
        }
        if (String.isBlank(vfRecordId)) {
            vfRecordId = recordId;
        }
        vfHomeownerImgUrl = ApexPages.currentPage().getParameters().get('homeownerImgUrl');
        vfRepresentativeImgUrl = ApexPages.currentPage().getParameters().get('representativeImgUrl');

        Id currentInspectionId = isValidIdFormat(vfRecordId) ? (Id) vfRecordId : null;
        vfInspectionData = getFinalInspectionData(currentInspectionId, true);
        if (vfInspectionData == null) {
            vfInspectionData = new FinalInspectionData();
        }

        SignatureBundle resolved = resolveSignatureBundle(
            currentInspectionId,
            vfHomeownerImgUrl,
            vfRepresentativeImgUrl,
            null,
            null
        );
        if (String.isBlank(vfHomeownerImgUrl)) {
            vfHomeownerImgUrl = resolved.homeownerImgUrl;
        }
        if (String.isBlank(vfRepresentativeImgUrl)) {
            vfRepresentativeImgUrl = resolved.representativeImgUrl;
        }

        vfHomeownerAddress = buildDisplayAddress(
            vfInspectionData.homeownerStreet,
            vfInspectionData.homeownerCity,
            vfInspectionData.homeownerState,
            vfInspectionData.homeownerPostal,
            vfInspectionData.homeownerCountry
        );

        logoUrl = getLogoUrl();
        String pdfDateParam = ApexPages.currentPage().getParameters().get('sendDate');
        if (String.isBlank(pdfDateParam)) {
            pdfDateParam = sendDate;
        }
        currentRecordDate = String.isNotBlank(pdfDateParam)
            ? formatDisplayDate(pdfDateParam)
            : (String.isNotBlank(vfInspectionData.finalInspectionDate) ? vfInspectionData.finalInspectionDate : System.now().format('MM-dd-yyyy'));
    }

    public static String buildDisplayAddress(String street, String city, String state, String postal, String country) {
        String safeStreet = safe(street);
        String safeCity = safe(city);
        String safeState = safe(state);
        String safePostal = safe(postal);
        String safeCountry = safe(country);

        List<String> cityStateParts = new List<String>();
        if (String.isNotBlank(safeCity)) {
            cityStateParts.add(safeCity);
        }
        if (String.isNotBlank(safeState)) {
            cityStateParts.add(safeState);
        }
        String cityState = String.join(cityStateParts, ' ');

        List<String> firstParts = new List<String>();
        if (String.isNotBlank(safeStreet)) {
            firstParts.add(safeStreet);
        }
        if (String.isNotBlank(cityState)) {
            firstParts.add(cityState);
        }
        String firstPart = String.join(firstParts, ', ');

        String zipPart = String.isNotBlank(safePostal) ? ' - ' + safePostal : '';
        String countryPart = String.isNotBlank(safeCountry) ? ', ' + safeCountry : '';
        return (firstPart + zipPart + countryPart).trim();
    }

    public static String formatDisplayDate(String rawDate) {
        if (String.isBlank(rawDate)) {
            return DateTime.now().format('MM-dd-yyyy');
        }

        String cleanedValue = rawDate.contains(' ') ? rawDate.substringBefore(' ') : rawDate;
        try {
            if (cleanedValue.contains('-')) {
                List<String> dashParts = cleanedValue.split('-');
                if (dashParts.size() == 3 && dashParts[0].length() == 4) {
                    Date parsedIsoDate = Date.newInstance(
                        Integer.valueOf(dashParts[0]),
                        Integer.valueOf(dashParts[1]),
                        Integer.valueOf(dashParts[2])
                    );
                    return DateTime.newInstance(parsedIsoDate, Time.newInstance(0, 0, 0, 0)).format('MM-dd-yyyy');
                }
                if (dashParts.size() == 3) {
                    Date parsedDashDate = Date.newInstance(
                        Integer.valueOf(dashParts[2]),
                        Integer.valueOf(dashParts[0]),
                        Integer.valueOf(dashParts[1])
                    );
                    return DateTime.newInstance(parsedDashDate, Time.newInstance(0, 0, 0, 0)).format('MM-dd-yyyy');
                }
            }

            if (cleanedValue.contains('/')) {
                List<String> slashParts = cleanedValue.split('/');
                if (slashParts.size() == 3) {
                    Date parsedSlashDate = Date.newInstance(
                        Integer.valueOf(slashParts[2]),
                        Integer.valueOf(slashParts[0]),
                        Integer.valueOf(slashParts[1])
                    );
                    return DateTime.newInstance(parsedSlashDate, Time.newInstance(0, 0, 0, 0)).format('MM-dd-yyyy');
                }
            }
        } catch (Exception e) {
            return rawDate;
        }

        return rawDate;
    }
}