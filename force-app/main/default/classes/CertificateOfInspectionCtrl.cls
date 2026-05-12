public without sharing class CertificateOfInspectionCtrl {

    public static final List<String> HOMSITE_REP_SIGN_ID_FIELDS = new List<String>{
        'COI_Homsite_Rep_Sign_Id__c',
        'COI_Homesite_Rep_Sign_Id__c'
    };

    public static final List<String> HOMSITE_REP_SIGN_DATE_FIELDS = new List<String>{
        'COI_Homsite_Rep_Sign_Date__c',
        'COI_Homesite_Rep_Sign_Date__c'
    };

    public class CertificateData {
        @AuraEnabled public String inspectionDate { get; set; }
        @AuraEnabled public String contractor { get; set; }
        @AuraEnabled public String projectAddress { get; set; }
        @AuraEnabled public String contractorSignDate { get; set; }
        @AuraEnabled public String homeownerSignDate { get; set; }
        @AuraEnabled public String homsiteRepSignDate { get; set; }
        @AuraEnabled public String codeEnforcementSignDate { get; set; }
        @AuraEnabled public Boolean contractorSigned { get; set; }
        @AuraEnabled public Boolean homeownerSigned { get; set; }
        @AuraEnabled public Boolean homsiteRepSigned { get; set; }
        @AuraEnabled public Boolean codeEnforcementSigned { get; set; }
        @AuraEnabled public String contractorSignatureUrl { get; set; }
        @AuraEnabled public String homeownerSignatureUrl { get; set; }
        @AuraEnabled public String homsiteRepSignatureUrl { get; set; }
        @AuraEnabled public String codeEnforcementSignatureUrl { get; set; }
        @AuraEnabled public Boolean isSubmitted { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static String getLogoUrl() {
        try {
            buildertek__ConfirmationSiteURL__c sitesUrl = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
            String baseUrl = '';
            if (sitesUrl != null && !String.isBlank(sitesUrl.buildertek__Sites_URL__c)) {
                baseUrl = normalizeBaseUrl(sitesUrl.buildertek__Sites_URL__c);
            } else {
                baseUrl = normalizeBaseUrl(URL.getOrgDomainUrl().toExternalForm());
            }

            List<Document> logoDocs = [SELECT Id FROM Document WHERE DeveloperName = 'Company_Logo' LIMIT 1];
            if (logoDocs.isEmpty()) {
                logoDocs = [SELECT Id FROM Document WHERE Name = 'BuildettekLogo' LIMIT 1];
            }
            if (!logoDocs.isEmpty()) {
                return baseUrl + '/servlet/servlet.FileDownload?file=' + logoDocs[0].Id;
            }
            return baseUrl + '/resource/buildertek__Company_Logo';
        } catch (Exception e) {
            return '/resource/buildertek__Company_Logo';
        }
    }

    @AuraEnabled(cacheable=true)
    public static CertificateData getCertificateData(Id recordId) {
        return getCertificateDataInternal(recordId, false);
    }

    public static CertificateData getCertificateDataInternal(Id recordId, Boolean skipSignatureDml) {
        CertificateData data = new CertificateData();
        data.inspectionDate = '';
        data.contractor = '';
        data.projectAddress = '';
        data.contractorSigned = false;
        data.homeownerSigned = false;
        data.homsiteRepSigned = false;
        data.codeEnforcementSigned = false;
        data.isSubmitted = false;
        if (recordId == null) {
            return data;
        }

        try {
            Map<String, Schema.SObjectField> inspectionFieldMap = buildertek__Inspection__c.SObjectType.getDescribe().fields.getMap();
            List<String> inspectionQueryFields = new List<String>{
                'Id',
                'buildertek__Inspection_Date__c',
                'buildertek__Project__c',
                'buildertek__Property_Street__c',
                'buildertek__Property_City__c',
                'buildertek__Property_State__c',
                'buildertek__Property_Zip__c'
            };

            if (inspectionFieldMap.containsKey('buildertek__Responsible_Contractor__c')) {
                inspectionQueryFields.add('buildertek__Responsible_Contractor__r.Name');
            }

            List<String> signatureFields = new List<String>{
                'COI_Contractor_Sign_Id__c',
                'COI_Homeowner_Sign_Id__c',
                'COI_Code_Enforcement_Sign_Id__c',
                'COI_Contractor_Sign_Date__c',
                'COI_Homeowner_Sign_Date__c',
                'COI_Code_Enforcement_Sign_Date__c'
            };
            for (String signatureField : signatureFields) {
                if (inspectionFieldMap.containsKey(signatureField)) {
                    inspectionQueryFields.add(signatureField);
                }
            }
            addExistingFields(inspectionQueryFields, inspectionFieldMap, HOMSITE_REP_SIGN_ID_FIELDS);
            addExistingFields(inspectionQueryFields, inspectionFieldMap, HOMSITE_REP_SIGN_DATE_FIELDS);

            SObject inspectionRecord = Database.query(
                'SELECT ' + String.join(inspectionQueryFields, ',')
                + ' FROM buildertek__Inspection__c WHERE Id = :recordId LIMIT 1'
            );

            Object inspectionDateValue = inspectionRecord.get('buildertek__Inspection_Date__c');
            data.inspectionDate = formatDateValue(inspectionDateValue);
            if (String.isBlank(data.inspectionDate)) {
                data.inspectionDate = formatDateValue(Date.today());
            }

            SObject contractorRef = inspectionRecord.getSObject('buildertek__Responsible_Contractor__r');
            if (contractorRef != null) {
                data.contractor = safe((String) contractorRef.get('Name'));
            }

            String inspectionAddress = formatAddressParts(
                safe((String) inspectionRecord.get('buildertek__Property_Street__c')),
                safe((String) inspectionRecord.get('buildertek__Property_City__c')),
                safe((String) inspectionRecord.get('buildertek__Property_State__c')),
                safe((String) inspectionRecord.get('buildertek__Property_Zip__c')),
                ''
            );

            Id projectId = (Id) inspectionRecord.get('buildertek__Project__c');
            SObject projectRecord = getProjectRecord(projectId);

            if (String.isBlank(data.contractor) && projectRecord != null) {
                data.contractor = firstAvailableValue(projectRecord, new List<String>{
                    'General_Contractor__r.Name',
                    'buildertek__General_Contractor__r.Name',
                    'General_Contractor__c',
                    'buildertek__General_Contractor__c',
                    'Contractor__c',
                    'buildertek__Contractor__c'
                });
            }

            if (String.isNotBlank(inspectionAddress)) {
                data.projectAddress = inspectionAddress;
            } else if (projectRecord != null) {
                data.projectAddress = formatAddressParts(
                    firstAvailableValue(projectRecord, new List<String>{ 'buildertek__Address__c' }),
                    firstAvailableValue(projectRecord, new List<String>{ 'buildertek__City_Text__c' }),
                    firstAvailableValue(projectRecord, new List<String>{ 'buildertek__State__c' }),
                    firstAvailableValue(projectRecord, new List<String>{ 'buildertek__Zip__c' }),
                    firstAvailableValue(projectRecord, new List<String>{ 'buildertek__Country__c' })
                );
            }

            String contractorSignId = inspectionFieldMap.containsKey('COI_Contractor_Sign_Id__c')
                ? (String) inspectionRecord.get('COI_Contractor_Sign_Id__c')
                : null;
            String homeownerSignId = inspectionFieldMap.containsKey('COI_Homeowner_Sign_Id__c')
                ? (String) inspectionRecord.get('COI_Homeowner_Sign_Id__c')
                : null;
            String homsiteRepSignId = firstExistingStringValue(inspectionRecord, HOMSITE_REP_SIGN_ID_FIELDS);
            String codeEnforcementSignId = inspectionFieldMap.containsKey('COI_Code_Enforcement_Sign_Id__c')
                ? (String) inspectionRecord.get('COI_Code_Enforcement_Sign_Id__c')
                : null;

            data.contractorSigned = String.isNotBlank(contractorSignId);
            data.homeownerSigned = String.isNotBlank(homeownerSignId);
            data.homsiteRepSigned = String.isNotBlank(homsiteRepSignId);
            data.codeEnforcementSigned = String.isNotBlank(codeEnforcementSignId);
            data.contractorSignDate = inspectionFieldMap.containsKey('COI_Contractor_Sign_Date__c')
                ? formatPdfDateValue(inspectionRecord.get('COI_Contractor_Sign_Date__c'))
                : '';
            data.homeownerSignDate = inspectionFieldMap.containsKey('COI_Homeowner_Sign_Date__c')
                ? formatPdfDateValue(inspectionRecord.get('COI_Homeowner_Sign_Date__c'))
                : '';
            data.homsiteRepSignDate = formatPdfDateValue(firstExistingObjectValue(inspectionRecord, HOMSITE_REP_SIGN_DATE_FIELDS));
            data.codeEnforcementSignDate = inspectionFieldMap.containsKey('COI_Code_Enforcement_Sign_Date__c')
                ? formatPdfDateValue(inspectionRecord.get('COI_Code_Enforcement_Sign_Date__c'))
                : '';

            if (!skipSignatureDml) {
                String contractorVersionId = resolveContentVersionId(contractorSignId);
                if (String.isNotBlank(contractorVersionId)) {
                    data.contractorSignatureUrl = getOrCreateDistributionUrl((Id) contractorVersionId);
                }

                String homeownerVersionId = resolveContentVersionId(homeownerSignId);
                if (String.isNotBlank(homeownerVersionId)) {
                    data.homeownerSignatureUrl = getOrCreateDistributionUrl((Id) homeownerVersionId);
                }

                String homsiteRepVersionId = resolveContentVersionId(homsiteRepSignId);
                if (String.isNotBlank(homsiteRepVersionId)) {
                    data.homsiteRepSignatureUrl = getOrCreateDistributionUrl((Id) homsiteRepVersionId);
                }

                String codeEnforcementVersionId = resolveContentVersionId(codeEnforcementSignId);
                if (String.isNotBlank(codeEnforcementVersionId)) {
                    data.codeEnforcementSignatureUrl = getOrCreateDistributionUrl((Id) codeEnforcementVersionId);
                }
            }

            data.isSubmitted = isPdfAlreadySaved(recordId);
        } catch (Exception e) {
            // Return partial/empty data safely.
        }

        return data;
    }

    public static SObject getProjectRecord(Id projectId) {
        if (projectId == null) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap = buildertek__Project__c.SObjectType.getDescribe().fields.getMap();
        List<String> queryFields = new List<String>{
            'Id',
            'buildertek__Address__c',
            'buildertek__City_Text__c',
            'buildertek__State__c',
            'buildertek__Zip__c',
            'buildertek__Country__c'
        };
        List<String> optionalFields = new List<String>{
            'General_Contractor__r.Name',
            'buildertek__General_Contractor__r.Name',
            'General_Contractor__c',
            'buildertek__General_Contractor__c',
            'Contractor__c',
            'buildertek__Contractor__c'
        };
        for (String optionalField : optionalFields) {
            if (isQueryableField(fieldMap, optionalField)) {
                queryFields.add(optionalField);
            }
        }

        return Database.query(
            'SELECT ' + String.join(queryFields, ',')
            + ' FROM buildertek__Project__c WHERE Id = :projectId LIMIT 1'
        );
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
            cv.Title = 'Certificate Of Inspection ' + safeLabel;
            cv.PathOnClient = 'CertificateOfInspection' + fileToken + '.png';
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
                // Do not block signature save if linking fails.
            }

            ContentDistribution cd = new ContentDistribution();
            cd.Name = 'Certificate Of Inspection ' + safeLabel;
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
        String contractorImgUrl,
        String homeownerImgUrl,
        String homsiteRepImgUrl,
        String codeEnforcementImgUrl,
        String contractorSignatureId,
        String homeownerSignatureId,
        String homsiteRepSignatureId,
        String codeEnforcementSignatureId,
        String currentSignerRole,
        List<String> homeownerContactIds,
        List<String> homeownerEmails,
        List<String> homsiteRepContactIds,
        List<String> homsiteRepEmails,
        List<String> codeEnforcementContactIds,
        List<String> codeEnforcementEmails,
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

            Map<String, Schema.SObjectField> fieldMap = buildertek__Inspection__c.SObjectType.getDescribe().fields.getMap();
            SObject inspectionRecord = Database.query(
                'SELECT Id'
                + (fieldMap.containsKey('COI_Contractor_Sign_Id__c') ? ', COI_Contractor_Sign_Id__c' : '')
                + (fieldMap.containsKey('COI_Homeowner_Sign_Id__c') ? ', COI_Homeowner_Sign_Id__c' : '')
                + joinExistingFieldSelects(fieldMap, HOMSITE_REP_SIGN_ID_FIELDS)
                + (fieldMap.containsKey('COI_Code_Enforcement_Sign_Id__c') ? ', COI_Code_Enforcement_Sign_Id__c' : '')
                + ' FROM buildertek__Inspection__c WHERE Id = :recordId LIMIT 1'
            );

            String resolvedContractorUrl = resolveImgUrl(
                contractorImgUrl,
                contractorSignatureId,
                fieldMap.containsKey('COI_Contractor_Sign_Id__c') ? (String) inspectionRecord.get('COI_Contractor_Sign_Id__c') : null
            );
            String resolvedHomeownerUrl = resolveImgUrl(
                homeownerImgUrl,
                homeownerSignatureId,
                fieldMap.containsKey('COI_Homeowner_Sign_Id__c') ? (String) inspectionRecord.get('COI_Homeowner_Sign_Id__c') : null
            );
            String resolvedHomsiteRepUrl = resolveImgUrl(
                homsiteRepImgUrl,
                homsiteRepSignatureId,
                firstExistingStringValue(inspectionRecord, HOMSITE_REP_SIGN_ID_FIELDS)
            );
            String resolvedCodeEnforcementUrl = resolveImgUrl(
                codeEnforcementImgUrl,
                codeEnforcementSignatureId,
                fieldMap.containsKey('COI_Code_Enforcement_Sign_Id__c') ? (String) inspectionRecord.get('COI_Code_Enforcement_Sign_Id__c') : null
            );

            if (String.isBlank(resolvedContractorUrl)
                || String.isBlank(resolvedHomeownerUrl)
                || String.isBlank(resolvedHomsiteRepUrl)
                || String.isBlank(resolvedCodeEnforcementUrl)) {
                sendChainEmail(
                    recordId,
                    senderId,
                    sendDate,
                    currentSignerRole,
                    homeownerContactIds,
                    homeownerEmails,
                    homsiteRepContactIds,
                    homsiteRepEmails,
                    codeEnforcementContactIds,
                    codeEnforcementEmails,
                    fromAddressId,
                    fileIds
                );
                return 'Missing Signatures';
            }

            PageReference pdfPage = Page.CertificateOfInspectionAsPDF;
            pdfPage.getParameters().put('recordId', recordId);
            pdfPage.getParameters().put('senderId', senderId);
            pdfPage.getParameters().put('sendDate', sendDate);
            pdfPage.getParameters().put('contractorImgUrl', resolvedContractorUrl);
            pdfPage.getParameters().put('homeownerImgUrl', resolvedHomeownerUrl);
            pdfPage.getParameters().put('homsiteRepImgUrl', resolvedHomsiteRepUrl);
            pdfPage.getParameters().put('codeEnforcementImgUrl', resolvedCodeEnforcementUrl);

            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('Test PDF');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            ContentVersion pdfCv = new ContentVersion();
            pdfCv.Title = 'Certificate Of Inspection ' + System.now().format('MM-dd-yyyy') + '.pdf';
            pdfCv.PathOnClient = 'CertificateOfInspection.pdf';
            pdfCv.VersionData = pdfBlob;
            pdfCv.IsMajorVersion = true;
            insert pdfCv;

            Id pdfDocId = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :pdfCv.Id
                LIMIT 1
            ].ContentDocumentId;
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

    public static void sendChainEmail(
        Id recordId,
        String senderId,
        String sendDate,
        String currentSignerRole,
        List<String> homeownerContactIds,
        List<String> homeownerEmails,
        List<String> homsiteRepContactIds,
        List<String> homsiteRepEmails,
        List<String> codeEnforcementContactIds,
        List<String> codeEnforcementEmails,
        String fromAddressId,
        List<String> fileIds
    ) {
        if (String.isBlank(currentSignerRole)) {
            return;
        }

        List<String> nextContactIds = new List<String>();
        List<String> nextEmails = new List<String>();
        String nextRole = '';

        if (currentSignerRole == 'isContractor') {
            nextContactIds = homeownerContactIds;
            nextEmails = homeownerEmails;
            nextRole = 'isHomeowner';
        } else if (currentSignerRole == 'isHomeowner') {
            nextContactIds = homsiteRepContactIds;
            nextEmails = homsiteRepEmails;
            nextRole = 'isHomsiteRep';
        } else if (currentSignerRole == 'isHomsiteRep') {
            nextContactIds = codeEnforcementContactIds;
            nextEmails = codeEnforcementEmails;
            nextRole = 'isCodeEnforcement';
        } else {
            return;
        }

        List<Contact> contacts = new List<Contact>();
        if (nextContactIds != null && !nextContactIds.isEmpty()) {
            try {
                contacts = [SELECT Id, Name, Email FROM Contact WHERE Id IN :nextContactIds];
            } catch (Exception e) {
                contacts = new List<Contact>();
            }
        }

        Set<String> sentEmails = new Set<String>();
        List<String> toSendEmails = new List<String>();
        List<String> toSendNames = new List<String>();

        for (Contact contactRec : contacts) {
            if (contactRec == null || String.isBlank(contactRec.Email)) {
                continue;
            }
            String normalizedEmail = contactRec.Email.trim().toLowerCase();
            if (sentEmails.contains(normalizedEmail)) {
                continue;
            }
            sentEmails.add(normalizedEmail);
            toSendEmails.add(contactRec.Email.trim());
            toSendNames.add(contactRec.Name);
        }

        if (nextEmails != null) {
            for (String emailVal : nextEmails) {
                if (String.isBlank(emailVal)) {
                    continue;
                }
                String trimmed = emailVal.trim();
                String normalizedEmail = trimmed.toLowerCase();
                if (sentEmails.contains(normalizedEmail)) {
                    continue;
                }
                sentEmails.add(normalizedEmail);
                toSendEmails.add(trimmed);
                toSendNames.add('');
            }
        }

        if (toSendEmails.isEmpty()) {
            return;
        }

        List<EmailTemplate> templates = [
            SELECT Subject, HtmlValue, Body
            FROM EmailTemplate
            WHERE DeveloperName = 'Certificate_Of_Inspection'
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            return;
        }

        EmailTemplate tmpl = templates[0];
        String bodyBase = String.isNotBlank(tmpl.HtmlValue) ? tmpl.HtmlValue : (tmpl.Body != null ? tmpl.Body : '');
        String subject = String.isNotBlank(tmpl.Subject) ? tmpl.Subject : 'Certificate Of Inspection';

        String link = buildCertificateLink(recordId, senderId, sendDate, false, nextRole);
        link = appendLinkRecipients(
            link,
            homeownerContactIds,
            homeownerEmails,
            homsiteRepContactIds,
            homsiteRepEmails,
            codeEnforcementContactIds,
            codeEnforcementEmails,
            fromAddressId,
            fileIds
        );

        String bodyWithLink = replaceTemplateLink(bodyBase, link);
        bodyWithLink = applyOrganizationMergeFieldsStatic(bodyWithLink);
        List<Messaging.EmailFileAttachment> attachmentList = buildAttachments(fileIds);
        if (attachmentList == null) {
            attachmentList = new List<Messaging.EmailFileAttachment>();
        }

        List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
        for (Integer index = 0; index < toSendEmails.size(); index++) {
            String recipEmail = toSendEmails[index];
            String recipName = toSendNames[index];
            if (String.isBlank(recipEmail)) {
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ recipEmail });
            if (String.isNotBlank(fromAddressId)) {
                mail.setOrgWideEmailAddressId(fromAddressId);
            }
            mail.setSubject(subject);
            mail.setHtmlBody(replaceContactName(bodyWithLink, recipName));
            if (recordId != null) {
                mail.setWhatId(recordId);
            }
            if (!attachmentList.isEmpty()) {
                mail.setFileAttachments(attachmentList);
            }
            batch.add(mail);
            if (batch.size() == 10) {
                Messaging.sendEmail(batch);
                batch.clear();
            }
        }
        if (!batch.isEmpty()) {
            Messaging.sendEmail(batch);
        }
    }

    public static String appendLinkRecipients(
        String link,
        List<String> homeownerContactIds,
        List<String> homeownerEmails,
        List<String> homsiteRepContactIds,
        List<String> homsiteRepEmails,
        List<String> codeEnforcementContactIds,
        List<String> codeEnforcementEmails,
        String fromAddressId,
        List<String> fileIds
    ) {
        String updatedLink = link;
        updatedLink = addJoinedParam(updatedLink, 'homeownerContactIds', homeownerContactIds);
        updatedLink = addJoinedParam(updatedLink, 'homeownerEmails', homeownerEmails);
        updatedLink = addJoinedParam(updatedLink, 'homsiteRepContactIds', homsiteRepContactIds);
        updatedLink = addJoinedParam(updatedLink, 'homsiteRepEmails', homsiteRepEmails);
        updatedLink = addJoinedParam(updatedLink, 'codeEnforcementContactIds', codeEnforcementContactIds);
        updatedLink = addJoinedParam(updatedLink, 'codeEnforcementEmails', codeEnforcementEmails);
        updatedLink = addJoinedParam(updatedLink, 'fileIds', fileIds);
        if (String.isNotBlank(fromAddressId)) {
            updatedLink = addOrReplaceUrlParam(updatedLink, 'fromAddressId', fromAddressId);
        }
        return updatedLink;
    }

    public static String addJoinedParam(String link, String key, List<String> values) {
        List<String> cleanedValues = new List<String>();
        if (values != null) {
            for (String value : values) {
                if (String.isNotBlank(value)) {
                    cleanedValues.add(value.trim());
                }
            }
        }
        if (cleanedValues.isEmpty()) {
            return link;
        }
        return addOrReplaceUrlParam(link, key, String.join(cleanedValues, ','));
    }

    public static String replaceTemplateLink(String body, String link) {
        String linkMarkup = '<a href="' + link + '">Click here</a>';
        if (String.isBlank(body)) {
            return linkMarkup;
        }
        if (body.contains('{!URL}')) {
            return body.replace('{!URL}', linkMarkup);
        }

        String token = '/apex/CertificateOfInspection';
        Integer tokenPos = body.indexOf(token);
        if (tokenPos < 0) {
            return body + '<br/><br/>' + linkMarkup;
        }

        Integer hrefStart = body.lastIndexOf('href="', tokenPos);
        if (hrefStart < 0) {
            return body;
        }

        Integer urlStart = hrefStart + 6;
        Integer urlEnd = body.indexOf('"', urlStart);
        if (urlEnd < 0) {
            return body;
        }
        return body.substring(0, urlStart) + link + body.substring(urlEnd);
    }

    public static String replaceContactName(String body, String contactName) {
        if (String.isBlank(body) || String.isBlank(contactName)) {
            return body;
        }
        body = body.replace('{!ContactName}', contactName);
        body = body.replace('{!Contact.Name}', contactName);
        body = body.replace('{!contact.name}', contactName);
        return body;
    }

    public static String buildCertificateLink(Id recordId, String senderId, String sendDate, Boolean isPreview, String roleParam) {
        String baseUrl = getConfirmationSiteUrl();
        String link = baseUrl + '/apex/CertificateOfInspection?recordId=' + String.valueOf(recordId)
            + '&isPreview=' + String.valueOf(isPreview);
        if (String.isNotBlank(senderId)) {
            link += '&senderId=' + EncodingUtil.urlEncode(senderId, 'UTF-8');
        }
        if (String.isNotBlank(sendDate)) {
            link += '&sendDate=' + EncodingUtil.urlEncode(sendDate, 'UTF-8');
        }
        if (String.isNotBlank(roleParam)) {
            link += '&' + roleParam + '=true';
        }
        return link;
    }

    public static String resolveImgUrl(String providedUrl, String providedSignId, String storedSignId) {
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

    public static void updateSignatureFields(Id recordId, String signatureLabel, Id contentVersionId) {
        if (recordId == null || contentVersionId == null) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = buildertek__Inspection__c.SObjectType.getDescribe().fields.getMap();
        buildertek__Inspection__c inspectionRecord = new buildertek__Inspection__c(Id = recordId);
        Boolean shouldUpdate = false;

        if (signatureLabel == 'Contractor') {
            if (fieldMap.containsKey('COI_Contractor_Sign_Id__c')) {
                inspectionRecord.put('COI_Contractor_Sign_Id__c', contentVersionId);
                shouldUpdate = true;
            }
            if (fieldMap.containsKey('COI_Contractor_Sign_Date__c')) {
                inspectionRecord.put('COI_Contractor_Sign_Date__c', Date.today());
                shouldUpdate = true;
            }
        } else if (signatureLabel == 'Homeowner') {
            if (fieldMap.containsKey('COI_Homeowner_Sign_Id__c')) {
                inspectionRecord.put('COI_Homeowner_Sign_Id__c', contentVersionId);
                shouldUpdate = true;
            }
            if (fieldMap.containsKey('COI_Homeowner_Sign_Date__c')) {
                inspectionRecord.put('COI_Homeowner_Sign_Date__c', Date.today());
                shouldUpdate = true;
            }
        } else if (signatureLabel == 'Homsite Representative') {
            shouldUpdate = putFirstExistingField(inspectionRecord, fieldMap, HOMSITE_REP_SIGN_ID_FIELDS, contentVersionId) || shouldUpdate;
            shouldUpdate = putFirstExistingField(inspectionRecord, fieldMap, HOMSITE_REP_SIGN_DATE_FIELDS, Date.today()) || shouldUpdate;
        } else if (signatureLabel == 'Code Enforcement') {
            if (fieldMap.containsKey('COI_Code_Enforcement_Sign_Id__c')) {
                inspectionRecord.put('COI_Code_Enforcement_Sign_Id__c', contentVersionId);
                shouldUpdate = true;
            }
            if (fieldMap.containsKey('COI_Code_Enforcement_Sign_Date__c')) {
                inspectionRecord.put('COI_Code_Enforcement_Sign_Date__c', Date.today());
                shouldUpdate = true;
            }
        }

        if (shouldUpdate) {
            update inspectionRecord;
        }
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
        cd.Name = 'Certificate Of Inspection Signature';
        cd.ContentVersionId = contentVersionId;
        cd.PreferencesAllowViewInBrowser = true;
        cd.PreferencesNotifyOnVisit = false;
        Database.SaveResult saveResult = Database.insert(cd, false);
        if (saveResult.isSuccess()) {
            ContentDistribution savedCd = [
                SELECT ContentDownloadUrl
                FROM ContentDistribution
                WHERE Id = :saveResult.getId()
                LIMIT 1
            ];
            return String.isNotBlank(savedCd.ContentDownloadUrl) ? savedCd.ContentDownloadUrl : fallbackUrl;
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

        List<ContentVersion> byVersion = [SELECT Id FROM ContentVersion WHERE Id = :idVal LIMIT 1];
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
                && link.ContentDocument.Title.startsWith('Certificate Of Inspection ')) {
                return true;
            }
        }
        return false;
    }

    public static void cleanupSignatureFile(String signatureId) {
        if (String.isBlank(signatureId)) {
            return;
        }
        List<ContentVersion> versions = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :signatureId
            LIMIT 1
        ];
        if (!versions.isEmpty()) {
            Database.delete(versions[0].ContentDocumentId, false);
        }
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
        for (ContentVersion fileRec : files) {
            totalSize += fileRec.ContentSize;
        }
        if (totalSize > 25 * 1024 * 1024) {
            return null;
        }

        for (ContentVersion fileRec : files) {
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            String extension = String.isNotBlank(fileRec.FileExtension)
                ? fileRec.FileExtension
                : (fileRec.FileType != null ? fileRec.FileType.toLowerCase() : '');
            attachment.setFileName(extension != '' ? fileRec.Title + '.' + extension : fileRec.Title);
            attachment.setBody(fileRec.VersionData);
            attachmentList.add(attachment);
        }
        return attachmentList;
    }

    public static String applyOrganizationMergeFieldsStatic(String body) {
        if (String.isBlank(body)) {
            return body;
        }
        try {
            Organization orgInfo = [SELECT Name, Street, City, State, PostalCode, Phone FROM Organization LIMIT 1];
            Map<String, String> tokens = new Map<String, String>{
                '{!$Organization.Name}' => safe(orgInfo.Name),
                '{!$Organization.Street}' => safe(orgInfo.Street),
                '{!$Organization.City}' => safe(orgInfo.City),
                '{!$Organization.State}' => safe(orgInfo.State),
                '{!$Organization.PostalCode}' => safe(orgInfo.PostalCode),
                '{!$Organization.Phone}' => safe(orgInfo.Phone)
            };
            for (String token : tokens.keySet()) {
                body = body.replace(token, tokens.get(token));
            }
        } catch (Exception e) {
            // Non-critical.
        }
        return body;
    }

    public static String firstAvailableValue(SObject source, List<String> candidates) {
        Object value = firstAvailableObject(source, candidates);
        return value == null ? '' : String.valueOf(value);
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
            return Datetime.newInstance(onlyDate, Time.newInstance(0, 0, 0, 0)).format('MM-dd-yyyy');
        }
        if (dateValue instanceof Datetime) {
            return ((Datetime) dateValue).format('MM-dd-yyyy');
        }
        return String.valueOf(dateValue);
    }

    public static String formatPdfDateValue(Object dateValue) {
        if (dateValue == null) {
            return '';
        }
        if (dateValue instanceof Date) {
            Date onlyDate = (Date) dateValue;
            return Datetime.newInstance(onlyDate, Time.newInstance(0, 0, 0, 0)).format('MM-dd-yyyy');
        }
        if (dateValue instanceof Datetime) {
            return ((Datetime) dateValue).format('MM-dd-yyyy');
        }
        return String.valueOf(dateValue);
    }

    public static String formatAddressParts(String street, String city, String state, String zip, String country) {
        String cityState = joinNonBlank(new List<String>{ city, state }, ' ');
        String firstPart = joinNonBlank(new List<String>{ street, cityState }, ', ');
        String zipPart = String.isNotBlank(zip) ? ' - ' + zip : '';
        String countryPart = String.isNotBlank(country) ? ', ' + country : '';
        return (firstPart + zipPart + countryPart).trim();
    }

    public static String joinNonBlank(List<String> parts, String separator) {
        List<String> cleaned = new List<String>();
        for (String part : parts) {
            if (String.isNotBlank(part)) {
                cleaned.add(part);
            }
        }
        return String.join(cleaned, separator);
    }

    public static String getConfirmationSiteUrl() {
        buildertek__ConfirmationSiteURL__c settings = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
        if (settings != null && String.isNotBlank(settings.buildertek__Sites_URL__c)) {
            return normalizeBaseUrl(settings.buildertek__Sites_URL__c);
        }
        return normalizeBaseUrl(URL.getOrgDomainUrl().toExternalForm());
    }

    public static String addOrReplaceUrlParam(String url, String key, String value) {
        if (String.isBlank(url) || String.isBlank(key)) {
            return url;
        }

        String encodedKey = EncodingUtil.urlEncode(key, 'UTF-8');
        String encodedValue = EncodingUtil.urlEncode(value == null ? '' : value, 'UTF-8');
        Pattern pattern = Pattern.compile('([?&])' + encodedKey + '=[^&]*');
        Matcher matcher = pattern.matcher(url);
        if (matcher.find()) {
            return matcher.replaceFirst('$1' + encodedKey + '=' + encodedValue);
        }

        String separator = url.contains('?') ? '&' : '?';
        return url + separator + encodedKey + '=' + encodedValue;
    }

    public static void addExistingFields(List<String> queryFields, Map<String, Schema.SObjectField> fieldMap, List<String> candidates) {
        if (queryFields == null || fieldMap == null || candidates == null) {
            return;
        }
        for (String candidate : candidates) {
            if (fieldMap.containsKey(candidate) && !queryFields.contains(candidate)) {
                queryFields.add(candidate);
            }
        }
    }

    public static String joinExistingFieldSelects(Map<String, Schema.SObjectField> fieldMap, List<String> candidates) {
        if (fieldMap == null || candidates == null) {
            return '';
        }
        String selectClause = '';
        for (String candidate : candidates) {
            if (fieldMap.containsKey(candidate)) {
                selectClause += ', ' + candidate;
            }
        }
        return selectClause;
    }

    public static String firstExistingStringValue(SObject source, List<String> candidates) {
        if (source == null || candidates == null) {
            return null;
        }
        for (String candidate : candidates) {
            try {
                Object value = source.get(candidate);
                if (value != null) {
                    return String.valueOf(value);
                }
            } catch (Exception e) {
                // Skip fields not present in this SObject context.
            }
        }
        return null;
    }

    public static Object firstExistingObjectValue(SObject source, List<String> candidates) {
        if (source == null || candidates == null) {
            return null;
        }
        for (String candidate : candidates) {
            try {
                Object value = source.get(candidate);
                if (value != null) {
                    return value;
                }
            } catch (Exception e) {
                // Skip fields not present in this SObject context.
            }
        }
        return null;
    }

    public static Boolean putFirstExistingField(
        SObject target,
        Map<String, Schema.SObjectField> fieldMap,
        List<String> candidates,
        Object value
    ) {
        if (target == null || fieldMap == null || candidates == null) {
            return false;
        }
        for (String candidate : candidates) {
            if (fieldMap.containsKey(candidate)) {
                target.put(candidate, value);
                return true;
            }
        }
        return false;
    }

    public static String normalizeBaseUrl(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.endsWith('/') ? value.substring(0, value.length() - 1) : value;
    }

    public static Boolean isValidIdFormat(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        return Pattern.matches('^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$', value);
    }

    public static String safe(String input) {
        return input == null ? '' : input;
    }

    public String isPreview { get; set; }
    public String recordId { get; set; }
    public String senderId { get; set; }
    public String sendDate { get; set; }

    public CertificateData vfCertificateData { get; set; }
    public String vfRecordId { get; set; }
    public String vfContractorImgUrl { get; set; }
    public String vfHomeownerImgUrl { get; set; }
    public String vfHomsiteRepImgUrl { get; set; }
    public String vfCodeEnforcementImgUrl { get; set; }
    public String logoUrl { get; set; }
    public String currentRecordDate { get; set; }

    public CertificateOfInspectionCtrl() {
        isPreview = ApexPages.currentPage().getParameters().get('isPreview');
        recordId = ApexPages.currentPage().getParameters().get('Id');
        if (recordId == null) {
            recordId = ApexPages.currentPage().getParameters().get('id');
        }
        if (recordId == null) {
            recordId = ApexPages.currentPage().getParameters().get('recordId');
        }
        senderId = ApexPages.currentPage().getParameters().get('senderId');
        sendDate = ApexPages.currentPage().getParameters().get('sendDate');
    }

    public void initPdf() {
        vfRecordId = ApexPages.currentPage().getParameters().get('recordId');
        if (String.isBlank(vfRecordId)) {
            vfRecordId = recordId;
        }
        vfContractorImgUrl = ApexPages.currentPage().getParameters().get('contractorImgUrl');
        vfHomeownerImgUrl = ApexPages.currentPage().getParameters().get('homeownerImgUrl');
        vfHomsiteRepImgUrl = ApexPages.currentPage().getParameters().get('homsiteRepImgUrl');
        vfCodeEnforcementImgUrl = ApexPages.currentPage().getParameters().get('codeEnforcementImgUrl');

        vfCertificateData = getCertificateDataInternal((Id) vfRecordId, true);
        if (vfCertificateData == null) {
            vfCertificateData = new CertificateData();
        }
        logoUrl = getLogoUrl();
        String pdfDateParam = ApexPages.currentPage().getParameters().get('sendDate');
        if (String.isBlank(pdfDateParam)) {
            pdfDateParam = sendDate;
        }
        currentRecordDate = String.isNotBlank(pdfDateParam)
            ? formatDisplayDate(pdfDateParam)
            : (String.isNotBlank(vfCertificateData.inspectionDate) ? vfCertificateData.inspectionDate : DateTime.now().format('MM-dd-yyyy'));
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