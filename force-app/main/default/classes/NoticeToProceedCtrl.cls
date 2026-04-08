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
        // Signature state
        @AuraEnabled public Boolean propertyOwnerSigned { get; set; }
        @AuraEnabled public Boolean contractorRepSigned { get; set; }
        @AuraEnabled public Boolean programRepSigned { get; set; }
        @AuraEnabled public String propertyOwnerSignatureUrl { get; set; }
        @AuraEnabled public String contractorRepSignatureUrl { get; set; }
        @AuraEnabled public String programRepSignatureUrl { get; set; }
        @AuraEnabled public Boolean isSubmitted { get; set; }
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
        return getNoticeDataInternal(recordId, false);
    }

    public static NoticeData getNoticeDataInternal(Id recordId, Boolean skipSignatureDml) {
        NoticeData data = new NoticeData();
        data.isSubmitted = false;
        data.propertyOwnerSigned = false;
        data.contractorRepSigned = false;
        data.programRepSigned = false;
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
                'General_Contractor__r.Phone',
                'buildertek__General_Contractor__r.Phone',
                'General_Contractor__r.BillingStreet',
                'buildertek__General_Contractor__r.BillingStreet',
                'General_Contractor__r.BillingCity',
                'buildertek__General_Contractor__r.BillingCity',
                'General_Contractor__r.BillingState',
                'buildertek__General_Contractor__r.BillingState',
                'General_Contractor__r.BillingPostalCode',
                'buildertek__General_Contractor__r.BillingPostalCode',
                'General_Contractor__r.BillingCountry',
                'buildertek__General_Contractor__r.BillingCountry',
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
                'buildertek__Contract_Dated__c',
                // Signature ID and Date fields
                'NTP_Property_Owner_Sign_Id__c',
                'NTP_Property_Owner_Sign_Date__c',
                'NTP_Contractor_Rep_Sign_Id__c',
                'NTP_Contractor_Rep_Sign_Date__c',
                'NTP_Program_Rep_Sign_Id__c',
                'NTP_Program_Rep_Sign_Date__c'
            };

            for (String optionalField : optionalFields) {
                if (isQueryableField(fieldMap, optionalField)) {
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
            data.telephone = firstAvailableValue(recordSObj, new List<String>{
                'General_Contractor__r.Phone',
                'buildertek__General_Contractor__r.Phone',
                'General_Contractor_Phone__c',
                'buildertek__General_Contractor_Phone__c',
                'Contractor_Phone__c',
                'buildertek__Contractor_Phone__c'
            });

            String billingStreet = firstAvailableValue(recordSObj, new List<String>{
                'General_Contractor__r.BillingStreet',
                'buildertek__General_Contractor__r.BillingStreet'
            });
            String billingCity = firstAvailableValue(recordSObj, new List<String>{
                'General_Contractor__r.BillingCity',
                'buildertek__General_Contractor__r.BillingCity'
            });
            String billingState = firstAvailableValue(recordSObj, new List<String>{
                'General_Contractor__r.BillingState',
                'buildertek__General_Contractor__r.BillingState'
            });
            String billingPostal = firstAvailableValue(recordSObj, new List<String>{
                'General_Contractor__r.BillingPostalCode',
                'buildertek__General_Contractor__r.BillingPostalCode'
            });
            String billingCountry = firstAvailableValue(recordSObj, new List<String>{
                'General_Contractor__r.BillingCountry',
                'buildertek__General_Contractor__r.BillingCountry'
            });

            String cityStatePostal = joinNonBlank(new List<String>{billingCity, billingState, billingPostal}, ' ');
            String relationshipAddress = joinNonBlank(new List<String>{billingStreet, cityStatePostal, billingCountry}, ', ');

            data.contractorAddress = String.isNotBlank(relationshipAddress)
                ? relationshipAddress
                : firstAvailableValue(recordSObj, new List<String>{
                    'General_Contractor_Address__c',
                    'buildertek__General_Contractor_Address__c',
                    'Contractor_Address__c',
                    'buildertek__Contractor_Address__c'
                });

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

            // --- Signatures ---
            String ownerSignId = fieldMap.containsKey('NTP_Property_Owner_Sign_Id__c')
                ? (String) recordSObj.get('NTP_Property_Owner_Sign_Id__c') : null;
            String contractorSignId = fieldMap.containsKey('NTP_Contractor_Rep_Sign_Id__c')
                ? (String) recordSObj.get('NTP_Contractor_Rep_Sign_Id__c') : null;
            String programSignId = fieldMap.containsKey('NTP_Program_Rep_Sign_Id__c')
                ? (String) recordSObj.get('NTP_Program_Rep_Sign_Id__c') : null;

            data.propertyOwnerSigned = String.isNotBlank(ownerSignId);
            data.contractorRepSigned = String.isNotBlank(contractorSignId);
            data.programRepSigned = String.isNotBlank(programSignId);

            if (!skipSignatureDml) {
                String ownerVersionId = resolveContentVersionId(ownerSignId);
                if (String.isNotBlank(ownerVersionId)) {
                    data.propertyOwnerSignatureUrl = getOrCreateDistributionUrl((Id) ownerVersionId);
                }
                String contractorVersionId = resolveContentVersionId(contractorSignId);
                if (String.isNotBlank(contractorVersionId)) {
                    data.contractorRepSignatureUrl = getOrCreateDistributionUrl((Id) contractorVersionId);
                }
                String programVersionId = resolveContentVersionId(programSignId);
                if (String.isNotBlank(programVersionId)) {
                    data.programRepSignatureUrl = getOrCreateDistributionUrl((Id) programVersionId);
                }
            }

            data.isSubmitted = isPdfAlreadySaved(recordId);
        } catch (Exception e) {
            // Return partial/empty data safely.
        }

        return data;
    }

    @AuraEnabled
    public static Map<String, String> saveSignature(Id recordId, String signatureBody, String signatureLabel) {
        try {
            ContentVersion cv = new ContentVersion();
            String safeLabel = String.isBlank(signatureLabel) ? 'Signature' : signatureLabel + ' Signature';
            String fileToken = safeLabel.replaceAll('[^A-Za-z0-9]+', '');
            if (String.isBlank(fileToken)) { fileToken = 'Signature'; }
            cv.Title = 'Notice To Proceed ' + safeLabel;
            cv.PathOnClient = 'NoticeToProceed' + fileToken + '.png';
            cv.VersionData = EncodingUtil.base64Decode(signatureBody);
            cv.IsMajorVersion = true;
            insert cv;

            updateSignatureFields(recordId, signatureLabel, cv.Id);

            try {
                Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
                if (recordId != null && contentDocId != null) {
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.ContentDocumentId = contentDocId;
                    cdl.LinkedEntityId = recordId;
                    cdl.ShareType = 'V';
                    cdl.Visibility = 'AllUsers';
                    Database.insert(cdl, false);
                }
            } catch (Exception e) { /* Do not block if linking fails */ }

            ContentDistribution cd = new ContentDistribution();
            cd.Name = 'Notice To Proceed ' + safeLabel;
            cd.ContentVersionId = cv.Id;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesNotifyOnVisit = false;
            Database.SaveResult cdResult = Database.insert(cd, false);

            Map<String, String> result = new Map<String, String>();
            String fallbackUrl = buildVersionDownloadUrl(cv.Id);
            if (cdResult.isSuccess()) {
                ContentDistribution savedCd = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :cdResult.getId() LIMIT 1];
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
        String propertyOwnerImgUrl,
        String contractorRepImgUrl,
        String programRepImgUrl,
        String propertyOwnerSignatureId,
        String contractorRepSignatureId,
        String programRepSignatureId,
        // Chain email params — passed from LWC URL params
        // Apex uses these to send the next signer email when Missing Signatures
        String currentSignerRole,
        List<String> contractorRepContactIds,
        List<String> contractorRepEmails,
        List<String> programRepContactIds,
        List<String> programRepEmails,
        String fromAddressId,
        List<String> fileIds
    ) {
        try {
            if (recordId == null) {
                throw new AuraHandledException('Record Id is required.');
            }

            if (isPdfAlreadySaved(recordId)) {
                return 'Already Submitted';
            }

            // Resolve URLs from stored sign IDs if not provided
            Map<String, Schema.SObjectField> fieldMap = buildertek__Project__c.SObjectType.getDescribe().fields.getMap();
            SObject rec = Database.query(
                'SELECT Id' +
                (fieldMap.containsKey('NTP_Property_Owner_Sign_Id__c') ? ', NTP_Property_Owner_Sign_Id__c' : '') +
                (fieldMap.containsKey('NTP_Contractor_Rep_Sign_Id__c') ? ', NTP_Contractor_Rep_Sign_Id__c' : '') +
                (fieldMap.containsKey('NTP_Program_Rep_Sign_Id__c') ? ', NTP_Program_Rep_Sign_Id__c' : '') +
                ' FROM buildertek__Project__c WHERE Id = :recordId LIMIT 1'
            );

            String ownerUrl     = resolveImgUrl(propertyOwnerImgUrl, propertyOwnerSignatureId,
                fieldMap.containsKey('NTP_Property_Owner_Sign_Id__c') ? (String) rec.get('NTP_Property_Owner_Sign_Id__c') : null);
            String contractorUrl = resolveImgUrl(contractorRepImgUrl, contractorRepSignatureId,
                fieldMap.containsKey('NTP_Contractor_Rep_Sign_Id__c') ? (String) rec.get('NTP_Contractor_Rep_Sign_Id__c') : null);
            String programUrl   = resolveImgUrl(programRepImgUrl, programRepSignatureId,
                fieldMap.containsKey('NTP_Program_Rep_Sign_Id__c') ? (String) rec.get('NTP_Program_Rep_Sign_Id__c') : null);

            if (String.isBlank(ownerUrl) || String.isBlank(contractorUrl) || String.isBlank(programUrl)) {
                // Not all signatures present yet — send email to the next signer from Apex
                sendChainEmail(
                    recordId, senderId, sendDate,
                    currentSignerRole,
                    contractorRepContactIds, contractorRepEmails,
                    programRepContactIds, programRepEmails,
                    fromAddressId, fileIds
                );
                return 'Missing Signatures';
            }

            PageReference pdfPage = Page.NoticeToProceedAsPDF;
            pdfPage.getParameters().put('recordId', recordId);
            pdfPage.getParameters().put('senderId', senderId);
            pdfPage.getParameters().put('sendDate', sendDate);
            pdfPage.getParameters().put('propertyOwnerImgUrl', ownerUrl);
            pdfPage.getParameters().put('contractorRepImgUrl', contractorUrl);
            pdfPage.getParameters().put('programRepImgUrl', programUrl);

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
            pdfCdl.Visibility = 'AllUsers';
            insert pdfCdl;

            cleanupSignatureFile(propertyOwnerSignatureId);
            cleanupSignatureFile(contractorRepSignatureId);
            cleanupSignatureFile(programRepSignatureId);
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Called by savePdf when Missing Signatures.
     * Determines the next signer based on currentSignerRole and sends them the email.
     * This is fully server-side — no URL param chaining needed from LWC.
     */
    private static void sendChainEmail(
        Id recordId,
        String senderId,
        String sendDate,
        String currentSignerRole,
        List<String> contractorRepContactIds,
        List<String> contractorRepEmails,
        List<String> programRepContactIds,
        List<String> programRepEmails,
        String fromAddressId,
        List<String> fileIds
    ) {
        if (String.isBlank(currentSignerRole)) { return; }

        List<String> nextContactIds = new List<String>();
        List<String> nextEmails     = new List<String>();
        String nextRole = '';

        if (currentSignerRole == 'isPropertyOwner') {
            // Property Owner just signed → notify Contractor Rep
            nextContactIds = contractorRepContactIds;
            nextEmails     = contractorRepEmails;
            nextRole       = 'isContractorRep';
        } else if (currentSignerRole == 'isContractorRep') {
            // Contractor Rep just signed → notify Program Rep
            nextContactIds = programRepContactIds;
            nextEmails     = programRepEmails;
            nextRole       = 'isProgramRep';
        } else {
            // Program Rep is last — no further chain needed
            return;
        }

        // Resolve contacts
        List<Contact> contacts = new List<Contact>();
        if (nextContactIds != null && !nextContactIds.isEmpty()) {
            try {
                contacts = [SELECT Id, Name, Email FROM Contact WHERE Id IN :nextContactIds];
            } catch (Exception e) { contacts = new List<Contact>(); }
        }

        // Build clean email list (deduplicate contacts vs raw emails)
        Set<String> sentEmails = new Set<String>();
        List<String> toSendEmails  = new List<String>();
        List<String> toSendNames   = new List<String>();

        for (Contact c : contacts) {
            if (c != null && String.isNotBlank(c.Email)) {
                toSendEmails.add(c.Email);
                toSendNames.add(c.Name);
                sentEmails.add(c.Email.toLowerCase());
            }
        }
        if (nextEmails != null) {
            for (String e : nextEmails) {
                if (String.isNotBlank(e) && !sentEmails.contains(e.toLowerCase())) {
                    toSendEmails.add(e.trim());
                    toSendNames.add('');
                    sentEmails.add(e.toLowerCase());
                }
            }
        }

        if (toSendEmails.isEmpty()) { return; }

        // Fetch template
        List<EmailTemplate> templates = [
            SELECT Subject, HtmlValue, Body
            FROM EmailTemplate WHERE DeveloperName = 'Notice_To_Proceed' LIMIT 1
        ];
        if (templates.isEmpty()) { return; }
        EmailTemplate tmpl = templates[0];
        String bodyBase = String.isNotBlank(tmpl.HtmlValue) ? tmpl.HtmlValue : (tmpl.Body != null ? tmpl.Body : '');
        String subject  = tmpl.Subject != null ? tmpl.Subject : 'Notice To Proceed';

        // Build link: for Contractor Rep include programRepContactIds so they can chain to Program Rep
        String link = buildNtpLink(recordId, senderId, sendDate, false, nextRole);
        if (nextRole == 'isContractorRep') {
            // Embed program rep IDs in Contractor Rep's link for further chaining
            if (programRepContactIds != null && !programRepContactIds.isEmpty()) {
                link += '&programRepContactIds=' + EncodingUtil.urlEncode(String.join(programRepContactIds, ','), 'UTF-8');
            }
            if (programRepEmails != null && !programRepEmails.isEmpty()) {
                List<String> clean = new List<String>();
                for (String e : programRepEmails) { if (String.isNotBlank(e)) clean.add(e.trim()); }
                if (!clean.isEmpty()) {
                    link += '&programRepEmails=' + EncodingUtil.urlEncode(String.join(clean, ','), 'UTF-8');
                }
            }
        }
        if (String.isNotBlank(fromAddressId)) {
            link += '&fromAddressId=' + EncodingUtil.urlEncode(fromAddressId, 'UTF-8');
        }
        if (fileIds != null && !fileIds.isEmpty()) {
            List<String> cleanIds = new List<String>();
            for (String fid : fileIds) { if (String.isNotBlank(fid)) cleanIds.add(fid); }
            if (!cleanIds.isEmpty()) {
                link += '&fileIds=' + EncodingUtil.urlEncode(String.join(cleanIds, ','), 'UTF-8');
            }
        }

        String linkMarkup = '<a href="' + link + '">Click here</a>';
        String bodyWithLink = String.isNotBlank(bodyBase) && bodyBase.contains('{!URL}')
            ? bodyBase.replace('{!URL}', linkMarkup) : bodyBase;
        bodyWithLink = applyOrganizationMergeFieldsStatic(bodyWithLink);

        // Fetch attachments
        List<Messaging.EmailFileAttachment> attachmentList = buildNtpAttachments(fileIds);
        if (attachmentList == null) { attachmentList = new List<Messaging.EmailFileAttachment>(); }

        List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < toSendEmails.size(); i++) {
            String recipEmail = toSendEmails[i];
            String recipName  = toSendNames[i];
            if (String.isBlank(recipEmail)) { continue; }

            String body = String.isNotBlank(recipName)
                ? replaceContactName(bodyWithLink, recipName) : bodyWithLink;

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ recipEmail });
            if (String.isNotBlank(fromAddressId)) { mail.setOrgWideEmailAddressId(fromAddressId); }
            mail.setSubject(subject);
            mail.setHtmlBody(body);
            if (isValidIdFormat(String.valueOf(recordId))) { mail.setWhatId(recordId); }
            if (!attachmentList.isEmpty()) { mail.setFileAttachments(attachmentList); }
            batch.add(mail);
            if (batch.size() == 10) { Messaging.sendEmail(batch); batch.clear(); }
        }
        if (!batch.isEmpty()) { Messaging.sendEmail(batch); }
    }




    // ── Private helpers ──────────────────────────────────────────────────────

    private static String applyOrganizationMergeFieldsStatic(String body) {
        if (String.isBlank(body)) { return body; }
        try {
            Organization orgInfo = [SELECT Name, Street, City, State, PostalCode, Phone FROM Organization LIMIT 1];
            Map<String, String> tokens = new Map<String, String>{
                '{!$Organization.Name}'       => safeVal(orgInfo.Name),
                '{!$Organization.Street}'     => safeVal(orgInfo.Street),
                '{!$Organization.City}'       => safeVal(orgInfo.City),
                '{!$Organization.State}'      => safeVal(orgInfo.State),
                '{!$Organization.PostalCode}' => safeVal(orgInfo.PostalCode),
                '{!$Organization.Phone}'      => safeVal(orgInfo.Phone)
            };
            for (String token : tokens.keySet()) { body = body.replace(token, tokens.get(token)); }
        } catch (Exception e) { /* non-critical */ }
        return body;
    }

    private static String safeVal(String s) { return s == null ? '' : s; }



    private static String resolveImgUrl(String providedUrl, String providedSignId, String storedSignId) {
        if (String.isNotBlank(providedUrl)) {
            return providedUrl;
        }
        String signId = String.isNotBlank(providedSignId) ? providedSignId : storedSignId;
        String versionId = resolveContentVersionId(signId);
        if (String.isNotBlank(versionId) && isValidIdFormat(versionId)) {
            return getOrCreateDistributionUrl((Id) versionId);
        }
        return '';
    }

    private static void updateSignatureFields(Id recordId, String signatureLabel, Id contentVersionId) {
        if (recordId == null || contentVersionId == null) { return; }
        Map<String, Schema.SObjectField> fieldMap = buildertek__Project__c.SObjectType.getDescribe().fields.getMap();
        buildertek__Project__c proj = new buildertek__Project__c(Id = recordId);
        Boolean shouldUpdate = false;

        if (signatureLabel == 'Property Owner') {
            if (fieldMap.containsKey('NTP_Property_Owner_Sign_Id__c')) {
                proj.put('NTP_Property_Owner_Sign_Id__c', contentVersionId);
                shouldUpdate = true;
            }
            if (fieldMap.containsKey('NTP_Property_Owner_Sign_Date__c')) {
                proj.put('NTP_Property_Owner_Sign_Date__c', Date.today());
                shouldUpdate = true;
            }
        } else if (signatureLabel == 'Contractor Representative') {
            if (fieldMap.containsKey('NTP_Contractor_Rep_Sign_Id__c')) {
                proj.put('NTP_Contractor_Rep_Sign_Id__c', contentVersionId);
                shouldUpdate = true;
            }
            if (fieldMap.containsKey('NTP_Contractor_Rep_Sign_Date__c')) {
                proj.put('NTP_Contractor_Rep_Sign_Date__c', Date.today());
                shouldUpdate = true;
            }
        } else if (signatureLabel == 'Home Improvement Program Representative') {
            if (fieldMap.containsKey('NTP_Program_Rep_Sign_Id__c')) {
                proj.put('NTP_Program_Rep_Sign_Id__c', contentVersionId);
                shouldUpdate = true;
            }
            if (fieldMap.containsKey('NTP_Program_Rep_Sign_Date__c')) {
                proj.put('NTP_Program_Rep_Sign_Date__c', Date.today());
                shouldUpdate = true;
            }
        }

        if (shouldUpdate) { update proj; }
    }

    private static String getOrCreateDistributionUrl(Id contentVersionId) {
        if (contentVersionId == null) { return ''; }
        String fallbackUrl = buildVersionDownloadUrl(contentVersionId);
        List<ContentDistribution> existing = [
            SELECT ContentDownloadUrl FROM ContentDistribution
            WHERE ContentVersionId = :contentVersionId ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (!existing.isEmpty() && String.isNotBlank(existing[0].ContentDownloadUrl)) {
            return existing[0].ContentDownloadUrl;
        }
        ContentDistribution cd = new ContentDistribution();
        cd.Name = 'Notice To Proceed Signature';
        cd.ContentVersionId = contentVersionId;
        cd.PreferencesAllowViewInBrowser = true;
        cd.PreferencesNotifyOnVisit = false;
        Database.SaveResult sr = Database.insert(cd, false);
        if (sr.isSuccess()) {
            ContentDistribution saved = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :sr.getId() LIMIT 1];
            return String.isNotBlank(saved.ContentDownloadUrl) ? saved.ContentDownloadUrl : fallbackUrl;
        }
        return fallbackUrl;
    }

    private static String buildVersionDownloadUrl(Id contentVersionId) {
        if (contentVersionId == null) { return ''; }
        String baseUrl = getConfirmationSiteUrl();
        if (String.isBlank(baseUrl)) { baseUrl = URL.getOrgDomainUrl().toExternalForm(); }
        return baseUrl + '/sfc/servlet.shepherd/version/download/' + contentVersionId;
    }

    private static String resolveContentVersionId(String idVal) {
        if (String.isBlank(idVal) || !isValidIdFormat(idVal)) { return null; }
        List<ContentVersion> byVersion = [SELECT Id FROM ContentVersion WHERE Id = :idVal LIMIT 1];
        if (!byVersion.isEmpty()) { return byVersion[0].Id; }
        List<ContentVersion> byDocument = [SELECT Id FROM ContentVersion WHERE ContentDocumentId = :idVal ORDER BY CreatedDate DESC LIMIT 1];
        if (!byDocument.isEmpty()) { return byDocument[0].Id; }
        return null;
    }

    private static Boolean isPdfAlreadySaved(Id recordId) {
        if (recordId == null) { return false; }
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title, ContentDocument.FileType
            FROM ContentDocumentLink WHERE LinkedEntityId = :recordId
        ];
        for (ContentDocumentLink link : links) {
            if (link.ContentDocument != null
                && link.ContentDocument.FileType == 'PDF'
                && link.ContentDocument.Title != null
                && link.ContentDocument.Title.startsWith('Notice To Proceed ')) {
                return true;
            }
        }
        return false;
    }

    private static void cleanupSignatureFile(String signatureId) {
        if (String.isBlank(signatureId)) { return; }
        List<ContentVersion> versions = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :signatureId LIMIT 1];
        if (!versions.isEmpty()) { Database.delete(versions[0].ContentDocumentId, false); }
    }

    private static String firstAvailableValue(SObject source, List<String> candidates) {
        Object value = firstAvailableObject(source, candidates);
        return value == null ? '' : String.valueOf(value);
    }

    private static Object firstAvailableObject(SObject source, List<String> candidates) {
        if (source == null || candidates == null) { return null; }
        Map<String, Object> values = source.getPopulatedFieldsAsMap();
        for (String apiName : candidates) {
            if (apiName != null && apiName.contains('.')) {
                List<String> parts = apiName.split('\\.');
                if (parts.size() == 2) {
                    SObject parentObj = source.getSObject(parts[0]);
                    if (parentObj != null) {
                        Object nestedValue = parentObj.get(parts[1]);
                        if (nestedValue != null) { return nestedValue; }
                    }
                }
                continue;
            }
            if (values.containsKey(apiName)) { return values.get(apiName); }
        }
        return null;
    }

    private static Boolean isQueryableField(Map<String, Schema.SObjectField> fieldMap, String fieldPath) {
        if (String.isBlank(fieldPath)) { return false; }
        if (!fieldPath.contains('.')) { return fieldMap.containsKey(fieldPath); }
        List<String> parts = fieldPath.split('\\.');
        if (parts.size() != 2) { return false; }
        String relationshipToken = parts[0];
        if (relationshipToken.endsWith('__r')) {
            String lookupField = relationshipToken.substring(0, relationshipToken.length() - 3) + '__c';
            return fieldMap.containsKey(lookupField);
        }
        return true;
    }

    private static String formatDateValue(Object dateValue) {
        if (dateValue == null) { return ''; }
        if (dateValue instanceof Date) { return ((Date) dateValue).format(); }
        if (dateValue instanceof Datetime) { return ((Datetime) dateValue).format('MM-dd-yyyy'); }
        return String.valueOf(dateValue);
    }

    private static String safe(String input) { return input == null ? '' : input; }

    private static String joinNonBlank(List<String> parts, String separator) {
        List<String> cleaned = new List<String>();
        for (String part : parts) {
            if (String.isNotBlank(part)) { cleaned.add(part); }
        }
        return String.join(cleaned, separator);
    }

    private static String getConfirmationSiteUrl() {
        buildertek__ConfirmationSiteURL__c settings = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
        if (settings != null && String.isNotBlank(settings.buildertek__Sites_URL__c)) {
            return settings.buildertek__Sites_URL__c;
        }
        return URL.getOrgDomainUrl().toExternalForm();
    }

    private static Boolean isValidIdFormat(String value) {
        if (String.isBlank(value)) { return false; }
        return Pattern.matches('^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$', value);
    }

    // ── Chain emails (called from LWC after Missing Signatures result) ────────

    /**
     * Called by the LWC (from Property Owner's browser) after they sign and
     * savePdf returns 'Missing Signatures'. Sends the form link to the
     * Contractor Representative with isContractorRep=true.
     * Mirrors FinalInspectionFormCtrl.sendCompanyContactEmail exactly.
     */
    @AuraEnabled
    public static String sendContractorRepEmail(
        Id recordId,
        List<String> contractorRepContactIds,
        List<String> contractorRepEmails,
        List<String> programRepContactIds,
        List<String> programRepEmails,
        String senderId,
        String sendDate,
        String fromAddressId,
        List<String> fileIds
    ) {
        if (recordId == null) { return 'Record Id is required'; }

        List<Contact> contacts = new List<Contact>();
        if (contractorRepContactIds != null && !contractorRepContactIds.isEmpty()) {
            try {
                contacts = [SELECT Id, Name, Email FROM Contact WHERE Id IN :contractorRepContactIds];
            } catch (Exception e) { contacts = new List<Contact>(); }
        }

        List<String> emails = new List<String>();
        if (contractorRepEmails != null) {
            for (String e : contractorRepEmails) { if (String.isNotBlank(e)) { emails.add(e.trim()); } }
        }

        if (contacts.isEmpty() && emails.isEmpty()) {
            return 'No contractor representative recipients found';
        }

        EmailTemplate template = [SELECT Subject, Body, HtmlValue FROM EmailTemplate WHERE DeveloperName = 'Notice_To_Proceed' LIMIT 1];
        String subject = template.Subject;
        String body = String.isNotBlank(template.HtmlValue) ? template.HtmlValue : template.Body;
        if (String.isBlank(body)) { body = ''; }

        String link = buildNtpLink(recordId, senderId, sendDate, false, 'isContractorRep');
        // Embed program rep contact IDs in the URL so Contractor Rep's LWC can chain to Program Rep
        if (programRepContactIds != null && !programRepContactIds.isEmpty()) {
            String programRepIdsValue = String.join(programRepContactIds, ',');
            link += '&programRepContactIds=' + EncodingUtil.urlEncode(programRepIdsValue, 'UTF-8');
        }
        if (programRepEmails != null && !programRepEmails.isEmpty()) {
            List<String> nonBlankEmails = new List<String>();
            for (String e : programRepEmails) { if (String.isNotBlank(e)) nonBlankEmails.add(e); }
            if (!nonBlankEmails.isEmpty()) {
                link += '&programRepEmails=' + EncodingUtil.urlEncode(String.join(nonBlankEmails, ','), 'UTF-8');
            }
        }
        String linkMarkup = '<a href="' + link + '">Click here</a>';
        if (body.contains('{!URL}')) { body = body.replace('{!URL}', linkMarkup); }
        body = applyOrganizationMergeFields(body);

        List<Messaging.EmailFileAttachment> attachmentList = buildNtpAttachments(fileIds);
        if (attachmentList == null) { return 'Total attachment size exceeds 25MB limit'; }

        List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
        List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();

        if (!contacts.isEmpty()) {
            for (Contact c : contacts) {
                if (c == null || String.isBlank(c.Email)) { continue; }
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ c.Email });
                if (String.isNotBlank(fromAddressId)) { mail.setOrgWideEmailAddressId(fromAddressId); }
                mail.setSubject(subject);
                mail.setHtmlBody(replaceContactName(body, c.Name));
                if (isValidIdFormat(String.valueOf(recordId))) { mail.setWhatId(recordId); }
                if (!attachmentList.isEmpty()) { mail.setFileAttachments(attachmentList); }
                batch.add(mail);
                if (batch.size() == 10) { results.addAll(Messaging.sendEmail(batch)); batch.clear(); }
            }
        } else {
            for (String emailVal : emails) {
                if (String.isBlank(emailVal)) { continue; }
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ emailVal });
                if (String.isNotBlank(fromAddressId)) { mail.setOrgWideEmailAddressId(fromAddressId); }
                mail.setSubject(subject);
                mail.setHtmlBody(body);
                if (isValidIdFormat(String.valueOf(recordId))) { mail.setWhatId(recordId); }
                if (!attachmentList.isEmpty()) { mail.setFileAttachments(attachmentList); }
                batch.add(mail);
                if (batch.size() == 10) { results.addAll(Messaging.sendEmail(batch)); batch.clear(); }
            }
        }
        if (!batch.isEmpty()) { results.addAll(Messaging.sendEmail(batch)); }
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

    /**
     * Called by the LWC (from Contractor Rep's browser) after they sign and
     * savePdf returns 'Missing Signatures'. Sends the form link to the
     * Home Improvement Program Representative with isProgramRep=true.
     */
    @AuraEnabled
    public static String sendProgramRepEmail(
        Id recordId,
        List<String> programRepContactIds,
        List<String> programRepEmails,
        String senderId,
        String sendDate,
        String fromAddressId,
        List<String> fileIds
    ) {
        if (recordId == null) { return 'Record Id is required'; }

        List<Contact> contacts = new List<Contact>();
        if (programRepContactIds != null && !programRepContactIds.isEmpty()) {
            try {
                contacts = [SELECT Id, Name, Email FROM Contact WHERE Id IN :programRepContactIds];
            } catch (Exception e) { contacts = new List<Contact>(); }
        }

        List<String> emails = new List<String>();
        if (programRepEmails != null) {
            for (String e : programRepEmails) { if (String.isNotBlank(e)) { emails.add(e.trim()); } }
        }

        if (contacts.isEmpty() && emails.isEmpty()) {
            return 'No program representative recipients found';
        }

        EmailTemplate template = [SELECT Subject, Body, HtmlValue FROM EmailTemplate WHERE DeveloperName = 'Notice_To_Proceed' LIMIT 1];
        String subject = template.Subject;
        String body = String.isNotBlank(template.HtmlValue) ? template.HtmlValue : template.Body;
        if (String.isBlank(body)) { body = ''; }

        String link = buildNtpLink(recordId, senderId, sendDate, false, 'isProgramRep');
        String linkMarkup = '<a href="' + link + '">Click here</a>';
        if (body.contains('{!URL}')) { body = body.replace('{!URL}', linkMarkup); }
        body = applyOrganizationMergeFields(body);

        List<Messaging.EmailFileAttachment> attachmentList = buildNtpAttachments(fileIds);
        if (attachmentList == null) { return 'Total attachment size exceeds 25MB limit'; }

        List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
        List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();

        if (!contacts.isEmpty()) {
            for (Contact c : contacts) {
                if (c == null || String.isBlank(c.Email)) { continue; }
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ c.Email });
                if (String.isNotBlank(fromAddressId)) { mail.setOrgWideEmailAddressId(fromAddressId); }
                mail.setSubject(subject);
                mail.setHtmlBody(replaceContactName(body, c.Name));
                if (isValidIdFormat(String.valueOf(recordId))) { mail.setWhatId(recordId); }
                if (!attachmentList.isEmpty()) { mail.setFileAttachments(attachmentList); }
                batch.add(mail);
                if (batch.size() == 10) { results.addAll(Messaging.sendEmail(batch)); batch.clear(); }
            }
        } else {
            for (String emailVal : emails) {
                if (String.isBlank(emailVal)) { continue; }
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ emailVal });
                if (String.isNotBlank(fromAddressId)) { mail.setOrgWideEmailAddressId(fromAddressId); }
                mail.setSubject(subject);
                mail.setHtmlBody(body);
                if (isValidIdFormat(String.valueOf(recordId))) { mail.setWhatId(recordId); }
                if (!attachmentList.isEmpty()) { mail.setFileAttachments(attachmentList); }
                batch.add(mail);
                if (batch.size() == 10) { results.addAll(Messaging.sendEmail(batch)); batch.clear(); }
            }
        }
        if (!batch.isEmpty()) { results.addAll(Messaging.sendEmail(batch)); }
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

    private static String replaceContactName(String body, String contactName) {
        if (String.isBlank(body) || String.isBlank(contactName)) { return body; }
        // Replace all common contact name tokens used in email templates
        body = body.replace('{!ContactName}', contactName);
        body = body.replace('{!Contact.Name}', contactName);
        body = body.replace('{!contact.name}', contactName);
        return body;
    }

    private static String buildNtpLink(Id recordId, String senderId, String sendDate, Boolean isPreview, String roleParam) {
        String baseUrl = getConfirmationSiteUrl();
        String link = baseUrl + '/apex/NoticeToProceed?recordId=' + String.valueOf(recordId)
            + '&isPreview=' + String.valueOf(isPreview);
        if (String.isNotBlank(senderId)) { link += '&senderId=' + EncodingUtil.urlEncode(senderId, 'UTF-8'); }
        if (String.isNotBlank(sendDate)) { link += '&sendDate=' + EncodingUtil.urlEncode(sendDate, 'UTF-8'); }
        if (String.isNotBlank(roleParam)) { link += '&' + roleParam + '=true'; }
        return link;
    }

    private static List<Messaging.EmailFileAttachment> buildNtpAttachments(List<String> fileIds) {
        List<Messaging.EmailFileAttachment> attachmentList = new List<Messaging.EmailFileAttachment>();
        if (fileIds == null || fileIds.isEmpty()) { return attachmentList; }
        List<ContentVersion> files = [
            SELECT Title, VersionData, ContentSize, FileType, FileExtension
            FROM ContentVersion WHERE ContentDocumentId IN :fileIds AND IsLatest = true
        ];
        Integer totalSize = 0;
        for (ContentVersion file : files) { totalSize += file.ContentSize; }
        if (totalSize > 25 * 1024 * 1024) { return null; }
        for (ContentVersion file : files) {
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            String extension = String.isNotBlank(file.FileExtension)
                ? file.FileExtension : (file.FileType != null ? file.FileType.toLowerCase() : '');
            attachment.setFileName(extension != '' ? file.Title + '.' + extension : file.Title);
            attachment.setBody(file.VersionData);
            attachmentList.add(attachment);
        }
        return attachmentList;
    }

    private static String applyOrganizationMergeFields(String body) {
        if (String.isBlank(body)) { return body; }
        Organization orgInfo = [SELECT Name, Street, City, State, PostalCode, Phone FROM Organization LIMIT 1];
        Map<String, String> values = new Map<String, String>{
            '{!$Organization.Name}' => safe(orgInfo.Name),
            '{!$Organization.Street}' => safe(orgInfo.Street),
            '{!$Organization.City}' => safe(orgInfo.City),
            '{!$Organization.State}' => safe(orgInfo.State),
            '{!$Organization.PostalCode}' => safe(orgInfo.PostalCode),
            '{!$Organization.Phone}' => safe(orgInfo.Phone)
        };
        for (String token : values.keySet()) { body = body.replace(token, values.get(token)); }
        return body;
    }

    // ── Visualforce controller properties & methods ───────────────────────────


    public String isPreview { get; set; }
    public String recordId { get; set; }
    public String senderId { get; set; }
    public String sendDate { get; set; }

    public NoticeData vfNoticeData { get; set; }
    public String vfRecordId { get; set; }
    public String vfPropertyOwnerImgUrl { get; set; }
    public String vfContractorRepImgUrl { get; set; }
    public String vfProgramRepImgUrl { get; set; }
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
        vfPropertyOwnerImgUrl = ApexPages.currentPage().getParameters().get('propertyOwnerImgUrl');
        vfContractorRepImgUrl = ApexPages.currentPage().getParameters().get('contractorRepImgUrl');
        vfProgramRepImgUrl    = ApexPages.currentPage().getParameters().get('programRepImgUrl');

        vfNoticeData = getNoticeDataInternal((Id) vfRecordId, true);
        if (vfNoticeData == null) {
            vfNoticeData = new NoticeData();
        }
        logoUrl = getLogoUrl();
        currentRecordDate = System.now().format('MM-dd-yyyy');
    }
}