public without sharing class ProjectPreviewEmailController {
    
    @AuraEnabled(cacheable=true)
    public static User getEmailSignature() {
        User usr = [SELECT Id, Name, Email, Signature FROM User WHERE Id = :UserInfo.getUserId()];
        return usr;
    }

    @AuraEnabled
    public static List<OrgWideEmailAddress> getOrgWideEmailAddresses() {
        List<OrgWideEmailAddress> emailaddresList = [SELECT Id, Address, DisplayName FROM OrgWideEmailAddress WHERE IsAllowAllProfiles = true ORDER BY DisplayName ASC];
        return emailaddresList;
    }

    @AuraEnabled
    public static List<ContentVersion> getRelatedFiles(String recordId) {
        List<ContentDocumentLink> fileLinks = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :recordId];

        Set<Id> documentIds = new Set<Id>();
        for(ContentDocumentLink link : fileLinks) {
            documentIds.add(link.ContentDocumentId);
        }

        List<ContentVersion> relatedFiles = [
            SELECT Id, VersionData, ContentDocumentId, Title, ContentSize, FileType, FileExtension 
            FROM ContentVersion 
            WHERE ContentDocumentId IN :documentIds
        ];

        return relatedFiles;
    }

    @AuraEnabled
    public static Map<String, String> getEmailBody(String recordId, String vfApiName) {
        if (String.isBlank(vfApiName)) {
            return new Map<String, String>();
        }
        Map<String, String> templateMap = new Map<String, String>{
            'ProjectImprovementProgramPhotoRelease' => 'Project_Improvement_Program_Photo_Release',
            'NoticeToProceed' => 'Notice_To_Proceed'
        };
        String resolvedTemplateApiName = templateMap.containsKey(vfApiName) ? templateMap.get(vfApiName) : vfApiName;

        List<EmailTemplate> templates = [
            SELECT Id, Subject, Body, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :resolvedTemplateApiName
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            return new Map<String, String>();
        }
        EmailTemplate template = templates[0];

        String body = template.HtmlValue;
        if (String.isBlank(body)) {
            body = template.Body;
        }
        String subject = template.Subject;

        if (String.isNotBlank(body) && body.contains('{!URL}')) {
            String baseUrl = getConfirmationSiteUrl();
            String safeRecordId = String.isBlank(recordId) ? '' : recordId;
            String linkText = 'Click here';
            String link = '<a href="' + baseUrl + '/apex/emailTemplateId?id=' + safeRecordId
                + '&isPreview=true&senderId=' + UserInfo.getUserId()
                + '&sendDate=' + Date.today() + '">' + linkText + '</a>';
            body = body.replace('{!URL}', link);
        }

        body = applyOrganizationMergeFields(body);

        Map<String, String> result = new Map<String, String>();
        result.put('subject', subject);
        result.put('htmlBody', body);

        return result;
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
            '{!$Organization.Name}' => safeValue(orgInfo.Name),
            '{!$Organization.Street}' => safeValue(orgInfo.Street),
            '{!$Organization.City}' => safeValue(orgInfo.City),
            '{!$Organization.State}' => safeValue(orgInfo.State),
            '{!$Organization.PostalCode}' => safeValue(orgInfo.PostalCode),
            '{!$Organization.Phone}' => safeValue(orgInfo.Phone)
        };

        for (String token : values.keySet()) {
            body = body.replace(token, values.get(token));
        }

        return body;
    }

    public static String safeValue(String value) {
        return value == null ? '' : value;
    }

    @AuraEnabled
    public static EmailResult sendEmail(String emailData) {
        DataWrap data = (DataWrap) JSON.deserialize(emailData, DataWrap.class);

        if (data == null) {
            return new EmailResult(false, 'Invalid email request');
        }

        if (data.templateId == 'NoticeToProceed') {
            return sendNoticeToProceedEmail(data);
        }

        if (data.toEmails == null || data.toEmails.isEmpty()) {
            return new EmailResult(false, 'At least one recipient is required');
        }

        List<String> toAddresses = new List<String>();
        List<String> ccAddresses = new List<String>();
        List<String> bccAddresses = new List<String>();

        toAddresses.addAll(data.toEmails);
        if (data.ccEmails != null) {
            ccAddresses.addAll(data.ccEmails);
        }
        if (data.bccEmails != null) {
            bccAddresses.addAll(data.bccEmails);
        }

        String subject = data.subject;
        if (data.includeRefId && String.isNotBlank(data.recordId)) {
            subject = subject + '[ref:' + data.recordId + ']';
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(toAddresses);
        if (!ccAddresses.isEmpty()) {
            mail.setCcAddresses(ccAddresses);
        }
        if (!bccAddresses.isEmpty()) {
            mail.setBccAddresses(bccAddresses);
        }
        if (String.isNotBlank(data.fromAddress)) {
            mail.setOrgWideEmailAddressId(data.fromAddress);
        }
        mail.setSubject(subject);
        mail.setHtmlBody(data.htmlBody);
        mail.setUseSignature(data.useEmailSignature);
        mail.setSaveAsActivity(data.saveAsActivity);
        if (isValidIdFormat(data.recordId)) {
            mail.setWhatId((Id) data.recordId);
        }

        List<Messaging.EmailFileAttachment> attachmentList = new List<Messaging.EmailFileAttachment>();
        if (data.fileIds != null && !data.fileIds.isEmpty()) {
            List<ContentVersion> files = [
                SELECT Title, VersionData, ContentSize, FileType, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId IN :data.fileIds AND IsLatest = true
            ];

            Integer totalSize = 0;
            for (ContentVersion file : files) {
                totalSize += file.ContentSize;
            }

            if (totalSize > 25 * 1024 * 1024) {
                return new EmailResult(false, 'Total attachment size exceeds 25MB limit');
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
        }

        if (!attachmentList.isEmpty()) {
            mail.setFileAttachments(attachmentList);
        }

        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        if (!results.isEmpty() && results[0].isSuccess()) {
            return new EmailResult(true, 'Email sent successfully');
        }

        String errorMsg = 'Failed to send email';
        if (!results.isEmpty() && !results[0].getErrors().isEmpty()) {
            errorMsg = results[0].getErrors()[0].getMessage();
        }
        return new EmailResult(false, errorMsg);
    }

    public static EmailResult sendNoticeToProceedEmail(DataWrap data) {
        if (String.isBlank(data.recordId)) {
            return new EmailResult(false, 'Record Id is required');
        }

        if (isNtpAlreadySubmitted((Id) data.recordId)) {
            return new EmailResult(false, 'Notice To Proceed already completed');
        }

        // Check which signatures are already on the record
        NtpSignatureState sigState = getNtpSignatureState((Id) data.recordId);

        // Determine who needs to sign next (in order: Owner → Contractor → Program Rep)
        Boolean needsOwner      = !sigState.ownerSigned;
        Boolean needsContractor = sigState.ownerSigned && !sigState.contractorSigned;
        Boolean needsProgramRep = sigState.ownerSigned && sigState.contractorSigned && !sigState.programRepSigned;

        if (!needsOwner && !needsContractor && !needsProgramRep) {
            return new EmailResult(false, 'Notice To Proceed already completed');
        }

        List<Contact> recipients = new List<Contact>();
        String roleParam = '';

        if (needsOwner) {
            if (data.ntpOwnerContactIds == null || data.ntpOwnerContactIds.isEmpty()) {
                return new EmailResult(false, 'At least one Property Owner recipient is required');
            }
            recipients = [SELECT Id, Name, Email FROM Contact WHERE Id IN :data.ntpOwnerContactIds];
            if (recipients.isEmpty()) {
                return new EmailResult(false, 'No valid Property Owner recipients found');
            }
            roleParam = 'isPropertyOwner';
        } else if (needsContractor) {
            if (data.ntpContractorContactIds == null || data.ntpContractorContactIds.isEmpty()) {
                return new EmailResult(false, 'At least one Contractor Representative recipient is required');
            }
            recipients = [SELECT Id, Name, Email FROM Contact WHERE Id IN :data.ntpContractorContactIds];
            if (recipients.isEmpty()) {
                return new EmailResult(false, 'No valid Contractor Representative recipients found');
            }
            roleParam = 'isContractorRep';
        } else if (needsProgramRep) {
            if (data.ntpProgramRepContactIds == null || data.ntpProgramRepContactIds.isEmpty()) {
                return new EmailResult(false, 'At least one Program Representative recipient is required');
            }
            recipients = [SELECT Id, Name, Email FROM Contact WHERE Id IN :data.ntpProgramRepContactIds];
            if (recipients.isEmpty()) {
                return new EmailResult(false, 'No valid Program Representative recipients found');
            }
            roleParam = 'isProgramRep';
        }

        String subject = data.subject;
        if (data.includeRefId && String.isNotBlank(data.recordId)) {
            subject = subject + '[ref:' + data.recordId + ']';
        }

        List<Messaging.EmailFileAttachment> attachmentList = new List<Messaging.EmailFileAttachment>();
        if (data.fileIds != null && !data.fileIds.isEmpty()) {
            List<ContentVersion> files = [
                SELECT Title, VersionData, ContentSize, FileType, FileExtension
                FROM ContentVersion WHERE ContentDocumentId IN :data.fileIds AND IsLatest = true
            ];
            Integer totalSize = 0;
            for (ContentVersion file : files) { totalSize += file.ContentSize; }
            if (totalSize > 25 * 1024 * 1024) {
                return new EmailResult(false, 'Total attachment size exceeds 25MB limit');
            }
            for (ContentVersion file : files) {
                Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                String extension = String.isNotBlank(file.FileExtension)
                    ? file.FileExtension : (file.FileType != null ? file.FileType.toLowerCase() : '');
                attachment.setFileName(extension != '' ? file.Title + '.' + extension : file.Title);
                attachment.setBody(file.VersionData);
                attachmentList.add(attachment);
            }
        }

        // ── Fetch template fresh and build the link explicitly ──────────────
        // This guarantees params are injected regardless of whether the email
        // template uses {!URL} or a hardcoded link (same pattern as sendContractorRepEmail).
        List<EmailTemplate> templates = [
            SELECT Subject, HtmlValue, Body
            FROM EmailTemplate WHERE DeveloperName = 'Notice_To_Proceed' LIMIT 1
        ];
        String roleBody = '';
        if (!templates.isEmpty()) {
            EmailTemplate tmpl = templates[0];
            roleBody = String.isNotBlank(tmpl.HtmlValue) ? tmpl.HtmlValue : (tmpl.Body != null ? tmpl.Body : '');
            if (String.isNotBlank(tmpl.Subject) && String.isBlank(subject)) {
                subject = tmpl.Subject;
            }
        }
        if (String.isBlank(roleBody)) {
            // Fallback to client-supplied body if template not found
            roleBody = data.htmlBody != null ? data.htmlBody : '';
        }

        // Build the full role link with ALL next-signer params embedded
        String link = buildNtpRoleLink(
            data.recordId, roleParam,
            data.ntpContractorContactIds, data.ntpContractorEmails,
            data.ntpProgramRepContactIds, data.ntpProgramRepEmails,
            data.fromAddress, data.fileIds
        );
        String linkMarkup = '<a href="' + link + '">Click here</a>';

        if (roleBody.contains('{!URL}')) {
            roleBody = roleBody.replace('{!URL}', linkMarkup);
        } else {
            // Template has a hardcoded link — update it in-place
            roleBody = applyNtpParamsToBody(
                roleBody, data.recordId, roleParam,
                data.ntpContractorContactIds, data.ntpContractorEmails,
                data.ntpProgramRepContactIds, data.ntpProgramRepEmails,
                data.fromAddress, data.fileIds
            );
        }
        roleBody = applyOrganizationMergeFieldsStatic(roleBody);
        // ── End link building ───────────────────────────────────────────────

        List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
        List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();

        for (Contact recipient : recipients) {
            if (recipient == null || String.isBlank(recipient.Email)) { continue; }
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ recipient.Email });
            if (String.isNotBlank(data.fromAddress)) { mail.setOrgWideEmailAddressId(data.fromAddress); }
            mail.setSubject(subject);
            mail.setHtmlBody(applyContactName(roleBody, recipient.Name, data.contactNameToken, data.lastSelectedContactName));
            mail.setUseSignature(data.useEmailSignature);
            mail.setSaveAsActivity(data.saveAsActivity);
            if (isValidIdFormat(data.recordId)) { mail.setWhatId((Id) data.recordId); }
            if (!attachmentList.isEmpty()) { mail.setFileAttachments(attachmentList); }
            batch.add(mail);
            if (batch.size() == 10) { results.addAll(Messaging.sendEmail(batch)); batch.clear(); }
        }

        if (!batch.isEmpty()) { results.addAll(Messaging.sendEmail(batch)); }

        if (results.isEmpty()) { return new EmailResult(false, 'No valid recipients found'); }
        for (Messaging.SendEmailResult result : results) {
            if (!result.isSuccess()) {
                if (result.getErrors() != null && !result.getErrors().isEmpty()) {
                    return new EmailResult(false, result.getErrors()[0].getMessage());
                }
                return new EmailResult(false, 'Failed to send email');
            }
        }
        return new EmailResult(true, 'Email sent successfully');
    }

    /**
     * Builds a full NTP VF page link with the role param AND all next-signer
     * contact IDs/emails embedded in the URL so the LWC can chain emails.
     */
    public static String buildNtpRoleLink(
        String recordId,
        String roleParam,
        List<String> contractorContactIds,
        List<String> contractorEmails,
        List<String> programRepContactIds,
        List<String> programRepEmails,
        String fromAddressId,
        List<String> fileIds
    ) {
        String baseUrl = getConfirmationSiteUrl();
        String link = baseUrl + '/apex/NoticeToProceed?recordId=' + (String.isBlank(recordId) ? '' : recordId)
            + '&isPreview=false';
        if (String.isNotBlank(roleParam)) {
            link += '&' + roleParam + '=true';
        }
        String contractorIdsValue = joinIds(contractorContactIds);
        if (String.isNotBlank(contractorIdsValue)) {
            link += '&contractorRepContactIds=' + EncodingUtil.urlEncode(contractorIdsValue, 'UTF-8');
        }
        String contractorEmailsValue = joinIds(contractorEmails);
        if (String.isNotBlank(contractorEmailsValue)) {
            link += '&contractorRepEmails=' + EncodingUtil.urlEncode(contractorEmailsValue, 'UTF-8');
        }
        String programIdsValue = joinIds(programRepContactIds);
        if (String.isNotBlank(programIdsValue)) {
            link += '&programRepContactIds=' + EncodingUtil.urlEncode(programIdsValue, 'UTF-8');
        }
        String programEmailsValue = joinIds(programRepEmails);
        if (String.isNotBlank(programEmailsValue)) {
            link += '&programRepEmails=' + EncodingUtil.urlEncode(programEmailsValue, 'UTF-8');
        }
        if (String.isNotBlank(fromAddressId)) {
            link += '&fromAddressId=' + EncodingUtil.urlEncode(fromAddressId, 'UTF-8');
        }
        String fileIdsValue = joinIds(fileIds);
        if (String.isNotBlank(fileIdsValue)) {
            link += '&fileIds=' + EncodingUtil.urlEncode(fileIdsValue, 'UTF-8');
        }
        return link;
    }

    public static String applyOrganizationMergeFieldsStatic(String body) {
        if (String.isBlank(body)) { return body; }
        Organization orgInfo = [SELECT Name, Street, City, State, PostalCode, Phone FROM Organization LIMIT 1];
        Map<String, String> values = new Map<String, String>{
            '{!$Organization.Name}'       => safeValue(orgInfo.Name),
            '{!$Organization.Street}'     => safeValue(orgInfo.Street),
            '{!$Organization.City}'       => safeValue(orgInfo.City),
            '{!$Organization.State}'      => safeValue(orgInfo.State),
            '{!$Organization.PostalCode}' => safeValue(orgInfo.PostalCode),
            '{!$Organization.Phone}'      => safeValue(orgInfo.Phone)
        };
        for (String token : values.keySet()) { body = body.replace(token, values.get(token)); }
        return body;
    }



    /**
     * Injects the role param and next-signer contact IDs into any URL in the
     * email body that contains '/apex/NoticeToProceed' — mirrors
     * applyFinalInspectionParamsToBody exactly.
     */
    public static String applyNtpParamsToBody(
        String body,
        String recordId,
        String roleParam,
        List<String> contractorContactIds,
        List<String> contractorEmails,
        List<String> programRepContactIds,
        List<String> programRepEmails,
        String fromAddressId,
        List<String> fileIds
    ) {
        if (String.isBlank(body)) { return body; }

        Pattern pat = Pattern.compile('(?i)href="([^"]+)"');
        Matcher mat = pat.matcher(body);
        List<String> parts = new List<String>();
        String token = '/apex/NoticeToProceed';
        Integer lastIndex = 0;

        while (mat.find()) {
            parts.add(body.substring(lastIndex, mat.start()));
            String url = mat.group(1);
            String updatedUrl = url;
            if (String.isNotBlank(url) && url.contains(token)) {
                updatedUrl = addOrReplaceUrlParam(updatedUrl, 'recordId', recordId);
                updatedUrl = addOrReplaceUrlParam(updatedUrl, 'isPreview', 'false');
                if (String.isNotBlank(roleParam)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, roleParam, 'true');
                }
                String contractorIdsValue = joinIds(contractorContactIds);
                if (String.isNotBlank(contractorIdsValue)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'contractorRepContactIds', contractorIdsValue);
                }
                String contractorEmailsValue = joinIds(contractorEmails);
                if (String.isNotBlank(contractorEmailsValue)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'contractorRepEmails', contractorEmailsValue);
                }
                String programRepIdsValue = joinIds(programRepContactIds);
                if (String.isNotBlank(programRepIdsValue)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'programRepContactIds', programRepIdsValue);
                }
                String programRepEmailsValue = joinIds(programRepEmails);
                if (String.isNotBlank(programRepEmailsValue)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'programRepEmails', programRepEmailsValue);
                }
                if (String.isNotBlank(fromAddressId)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'fromAddressId', fromAddressId);
                }
                String fileIdsValue = joinIds(fileIds);
                if (String.isNotBlank(fileIdsValue)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'fileIds', fileIdsValue);
                }
            }
            parts.add('href="' + updatedUrl + '"');
            lastIndex = mat.end();
        }
        parts.add(body.substring(lastIndex));
        return String.join(parts, '');
    }

    public class NtpSignatureState {
        public Boolean ownerSigned { get; set; }
        public Boolean contractorSigned { get; set; }
        public Boolean programRepSigned { get; set; }
        public NtpSignatureState(Boolean ownerSigned, Boolean contractorSigned, Boolean programRepSigned) {
            this.ownerSigned = ownerSigned;
            this.contractorSigned = contractorSigned;
            this.programRepSigned = programRepSigned;
        }
    }

    public static NtpSignatureState getNtpSignatureState(Id recordId) {
        if (recordId == null) { return new NtpSignatureState(false, false, false); }
        Map<String, Schema.SObjectField> fieldMap = buildertek__Project__c.SObjectType.getDescribe().fields.getMap();
        List<String> queryFields = new List<String>{ 'Id' };
        if (fieldMap.containsKey('NTP_Property_Owner_Sign_Id__c'))  { queryFields.add('NTP_Property_Owner_Sign_Id__c'); }
        if (fieldMap.containsKey('NTP_Contractor_Rep_Sign_Id__c'))  { queryFields.add('NTP_Contractor_Rep_Sign_Id__c'); }
        if (fieldMap.containsKey('NTP_Program_Rep_Sign_Id__c'))     { queryFields.add('NTP_Program_Rep_Sign_Id__c'); }
        if (queryFields.size() == 1) { return new NtpSignatureState(false, false, false); }
        SObject rec = Database.query('SELECT ' + String.join(queryFields, ',') + ' FROM buildertek__Project__c WHERE Id = :recordId LIMIT 1');
        Boolean ownerSigned      = fieldMap.containsKey('NTP_Property_Owner_Sign_Id__c')  && String.isNotBlank((String) rec.get('NTP_Property_Owner_Sign_Id__c'));
        Boolean contractorSigned = fieldMap.containsKey('NTP_Contractor_Rep_Sign_Id__c')  && String.isNotBlank((String) rec.get('NTP_Contractor_Rep_Sign_Id__c'));
        Boolean programRepSigned = fieldMap.containsKey('NTP_Program_Rep_Sign_Id__c')     && String.isNotBlank((String) rec.get('NTP_Program_Rep_Sign_Id__c'));
        return new NtpSignatureState(ownerSigned, contractorSigned, programRepSigned);
    }

    public static Boolean isNtpAlreadySubmitted(Id recordId) {
        if (recordId == null) { return false; }
        for (ContentDocumentLink link : [
            SELECT ContentDocument.Title, ContentDocument.FileType
            FROM ContentDocumentLink WHERE LinkedEntityId = :recordId
        ]) {
            if (link.ContentDocument != null
                && link.ContentDocument.FileType == 'PDF'
                && link.ContentDocument.Title != null
                && link.ContentDocument.Title.startsWith('Notice To Proceed ')) {
                return true;
            }
        }
        return false;
    }






    public static String addOrReplaceUrlParam(String url, String key, String value) {
        if (String.isBlank(url) || String.isBlank(key)) {
            return url;
        }
        String encodedKey = EncodingUtil.urlEncode(key, 'UTF-8');
        String encodedValue = value == null ? '' : EncodingUtil.urlEncode(value, 'UTF-8');
        Pattern pattern = Pattern.compile('([?&])' + encodedKey + '=[^&]*');
        Matcher matcher = pattern.matcher(url);
        if (matcher.find()) {
            return matcher.replaceAll('$1' + encodedKey + '=' + encodedValue);
        }
        String separator = url.contains('?') ? '&' : '?';
        return url + separator + encodedKey + '=' + encodedValue;
    }

    public static String joinIds(List<String> ids) {
        if (ids == null || ids.isEmpty()) {
            return '';
        }
        List<String> cleaned = new List<String>();
        for (String idVal : ids) {
            if (String.isNotBlank(idVal)) {
                cleaned.add(idVal);
            }
        }
        return cleaned.isEmpty() ? '' : String.join(cleaned, ',');
    }

    public static String applyContactName(String body, String contactName, String token, String lastSelectedName) {
        if (String.isBlank(body) || String.isBlank(contactName)) {
            return body;
        }

        String updatedBody = body;
        if (String.isNotBlank(token) && updatedBody.contains(token)) {
            updatedBody = updatedBody.replace(token, contactName);
        } else if (String.isNotBlank(lastSelectedName) && updatedBody.contains(lastSelectedName)) {
            updatedBody = updatedBody.replace(lastSelectedName, contactName);
        } else if (updatedBody.contains('{!ContactName}')) {
            updatedBody = updatedBody.replace('{!ContactName}', contactName);
        }

        return updatedBody;
    }

    @AuraEnabled
    public static Map<String, String> saveSignature(String recordId, String signatureBase64Data) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(signatureBase64Data)) {
            return result;
        }

        ContentVersion conVer = new ContentVersion();
        conVer.ContentLocation = 'S';
        conVer.PathOnClient = 'PathStoneSignature.png';
        conVer.Title = 'PathStone Signature';
        conVer.VersionData = EncodingUtil.base64Decode(signatureBase64Data);
        conVer.IsMajorVersion = true;
        insert conVer;

        Id conDocId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :conVer.Id
        ].ContentDocumentId;

        Id safeRecordId = isValidIdFormat(recordId) ? (Id) recordId : null;
        if (safeRecordId != null) {
            ContentDocumentLink conDocLink = new ContentDocumentLink();
            conDocLink.LinkedEntityId = safeRecordId;
            conDocLink.ContentDocumentId = conDocId;
            conDocLink.ShareType = 'I';
            insert conDocLink;
        }

        ContentDistribution cd = new ContentDistribution();
        cd.Name = 'PathStone Signature';
        cd.ContentVersionId = conVer.Id;
        cd.PreferencesAllowViewInBrowser = true;
        cd.PreferencesNotifyOnVisit = false;
        Database.SaveResult cdResult = Database.insert(cd, false);
        if (cdResult.isSuccess()) {
            cd = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :cdResult.getId()];
            if (String.isNotBlank(cd.ContentDownloadUrl)) {
                result.put('imgUrl', cd.ContentDownloadUrl);
            }
        }

        result.put('cvId', conVer.Id);
        return result;
    }

    public static Boolean isValidIdFormat(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        Boolean isValid = Pattern.matches('^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$', value);
        return isValid;
    }

    public class EmailResult {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String errorMessage;
        public EmailResult(Boolean isSuccess, String errorMessage) {
            this.isSuccess = isSuccess;
            this.errorMessage = errorMessage;
        }
    }

    public class DataWrap {
        public String recordId;
        public Boolean includeRefId;
        public String templateId;
        public String fromAddress;
        public List<String> toContactIds;
        public List<String> toEmails;
        public List<String> ccEmails;
        public List<String> bccEmails;
        // Notice To Proceed-specific
        public List<String> ntpOwnerContactIds;
        public List<String> ntpOwnerEmails;
        public List<String> ntpContractorContactIds;
        public List<String> ntpContractorEmails;
        public List<String> ntpProgramRepContactIds;
        public List<String> ntpProgramRepEmails;
        public String subject;
        public String htmlBody;
        public String contactNameToken;
        public String lastSelectedContactName;
        public Boolean useEmailSignature;
        public Boolean saveAsActivity;
        public List<String> fileIds;
    }

}