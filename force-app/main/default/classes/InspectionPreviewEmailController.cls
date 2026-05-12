public without sharing class InspectionPreviewEmailController {

    @AuraEnabled(cacheable=true)
    public static User getEmailSignature() {
        return [SELECT Id, Name, Email, Signature FROM User WHERE Id = :UserInfo.getUserId()];
    }

    @AuraEnabled
    public static List<OrgWideEmailAddress> getOrgWideEmailAddresses() {
        return [
            SELECT Id, Address, DisplayName
            FROM OrgWideEmailAddress
            WHERE IsAllowAllProfiles = true
            ORDER BY DisplayName ASC
        ];
    }

    @AuraEnabled
    public static List<ContentVersion> getRelatedFiles(String recordId) {
        List<ContentDocumentLink> fileLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ];

        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : fileLinks) {
            documentIds.add(link.ContentDocumentId);
        }
        if (documentIds.isEmpty()) {
            return new List<ContentVersion>();
        }

        return [
            SELECT Id, VersionData, ContentDocumentId, Title, ContentSize, FileType, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds
        ];
    }

    @AuraEnabled
    public static Map<String, String> getEmailBody(String recordId, String vfApiName) {
        if (String.isBlank(vfApiName)) {
            return new Map<String, String>();
        }

        Map<String, String> templateMap = new Map<String, String>{
            'CertificateOfInspection' => 'Certificate_Of_Inspection',
            'FinalInspectionForm' => 'Final_Inspection_Form'
        };
        String resolvedTemplateApiName = templateMap.containsKey(vfApiName)
            ? templateMap.get(vfApiName)
            : vfApiName;

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
        String body = String.isNotBlank(template.HtmlValue) ? template.HtmlValue : template.Body;
        String subject = template.Subject;

        if (String.isNotBlank(body) && body.contains('{!URL}')) {
            String baseUrl = getConfirmationSiteUrl();
            String safeRecordId = String.isBlank(recordId) ? '' : recordId;
            String pageName = String.isBlank(vfApiName) ? 'CertificateOfInspection' : vfApiName;
            String link = baseUrl + '/apex/' + pageName + '?id=' + safeRecordId
                + '&isPreview=true&senderId=' + UserInfo.getUserId()
                + '&sendDate=' + Date.today();
            body = body.replace('{!URL}', '<a href="' + link + '">Click here</a>');
        }

        body = applyOrganizationMergeFields(body);

        Map<String, String> result = new Map<String, String>();
        result.put('subject', String.isBlank(subject) ? 'Certificate Of Inspection' : subject);
        result.put('htmlBody', body);
        return result;
    }

    @AuraEnabled
    public static EmailResult sendEmail(String emailData) {
        DataWrap data = (DataWrap) JSON.deserialize(emailData, DataWrap.class);
        if (data == null) {
            return new EmailResult(false, 'Invalid email request');
        }
        if (data.templateId == 'FinalInspectionForm') {
            return sendFinalInspectionEmail(data);
        }
        if (data.templateId != 'CertificateOfInspection') {
            return new EmailResult(false, 'Unsupported template');
        }
        return sendCertificateOfInspectionEmail(data);
    }

    public static EmailResult sendFinalInspectionEmail(DataWrap data) {
        if (String.isBlank(data.recordId) || !isValidIdFormat(data.recordId)) {
            return new EmailResult(false, 'Record Id is required');
        }

        Id inspectionId = (Id) data.recordId;
        if (isFinalInspectionAlreadySubmitted(inspectionId)) {
            return new EmailResult(false, 'Final Inspection already completed');
        }

        FinalInspectionSignatureState sigState = getFinalInspectionSignatureState(inspectionId);
        Boolean needsHomeowner = !sigState.homeownerSigned;
        Boolean needsRepresentative = sigState.homeownerSigned && !sigState.representativeSigned;

        if (!needsHomeowner && !needsRepresentative) {
            return new EmailResult(false, 'Final Inspection already completed');
        }

        List<Contact> recipients = new List<Contact>();
        Boolean isVendor = false;
        Boolean isCompany = false;

        if (needsHomeowner) {
            if (data.vendorContactIds == null || data.vendorContactIds.isEmpty()) {
                return new EmailResult(false, 'At least one homeowner recipient is required');
            }
            recipients = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id IN :data.vendorContactIds
            ];
            if (recipients.isEmpty()) {
                return new EmailResult(false, 'No valid homeowner recipients found');
            }
            isVendor = true;
        } else if (needsRepresentative) {
            if (data.companyContactIds == null || data.companyContactIds.isEmpty()) {
                return new EmailResult(false, 'At least one program representative contact is required');
            }
            recipients = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id IN :data.companyContactIds
            ];
            if (recipients.isEmpty()) {
                return new EmailResult(false, 'No valid program representative recipients found');
            }
            isCompany = true;
        }

        String subject = String.isBlank(data.subject) ? 'Final Inspection Form' : data.subject;
        List<Messaging.EmailFileAttachment> attachmentList = buildAttachments(data.fileIds);
        if (attachmentList == null) {
            return new EmailResult(false, 'Total attachment size exceeds 25MB limit');
        }

        String roleBody = applyFinalInspectionParamsToBody(
            data.htmlBody == null ? '' : data.htmlBody,
            data.recordId,
            isVendor,
            isCompany,
            data.companyContactIds,
            data.companyEmails,
            data.fromAddress,
            data.fileIds
        );

        List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
        List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();

        for (Contact recipient : recipients) {
            if (recipient == null || String.isBlank(recipient.Email)) {
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ recipient.Email });
            if (String.isNotBlank(data.fromAddress)) {
                mail.setOrgWideEmailAddressId(data.fromAddress);
            }
            mail.setSubject(subject);
            mail.setHtmlBody(applyContactName(roleBody, recipient.Name, data.contactNameToken, data.lastSelectedContactName));
            mail.setUseSignature(data.useEmailSignature == true);
            mail.setSaveAsActivity(data.saveAsActivity == true);
            mail.setWhatId(inspectionId);
            if (!attachmentList.isEmpty()) {
                mail.setFileAttachments(attachmentList);
            }

            batch.add(mail);
            if (batch.size() == 10) {
                results.addAll(Messaging.sendEmail(batch));
                batch.clear();
            }
        }

        if (!batch.isEmpty()) {
            results.addAll(Messaging.sendEmail(batch));
        }

        if (results.isEmpty()) {
            return new EmailResult(false, 'No valid recipients found');
        }

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

    public static EmailResult sendCertificateOfInspectionEmail(DataWrap data) {
        if (String.isBlank(data.recordId) || !isValidIdFormat(data.recordId)) {
            return new EmailResult(false, 'Record Id is required');
        }
        if (!hasRecipients(data.contractorContactIds, data.contractorEmails)) {
            return new EmailResult(false, 'Please select at least one Contractor recipient');
        }
        if (!hasRecipients(data.homeownerContactIds, data.homeownerEmails)) {
            return new EmailResult(false, 'Please select at least one Homeowner recipient');
        }
        if (!hasRecipients(data.homsiteRepContactIds, data.homsiteRepEmails)) {
            return new EmailResult(false, 'Please select at least one Homsite Representative recipient');
        }
        if (!hasRecipients(data.codeEnforcementContactIds, data.codeEnforcementEmails)) {
            return new EmailResult(false, 'Please select at least one Code Enforcement recipient');
        }

        String subject = String.isBlank(data.subject) ? 'Certificate Of Inspection' : data.subject;
        return sendRoleEmail(
            (Id) data.recordId,
            data.contractorContactIds,
            data.contractorEmails,
            subject,
            data.htmlBody,
            data.fromAddress,
            data.useEmailSignature,
            data.saveAsActivity,
            data.fileIds,
            'isContractor',
            data.homeownerContactIds,
            data.homeownerEmails,
            data.homsiteRepContactIds,
            data.homsiteRepEmails,
            data.codeEnforcementContactIds,
            data.codeEnforcementEmails
        );
    }

    public static EmailResult sendRoleEmail(
        Id recordId,
        List<String> recipientContactIds,
        List<String> recipientEmails,
        String subject,
        String htmlBody,
        String fromAddressId,
        Boolean useEmailSignature,
        Boolean saveAsActivity,
        List<String> fileIds,
        String roleParam,
        List<String> homeownerContactIds,
        List<String> homeownerEmails,
        List<String> homsiteRepContactIds,
        List<String> homsiteRepEmails,
        List<String> codeEnforcementContactIds,
        List<String> codeEnforcementEmails
    ) {
        List<Contact> contacts = new List<Contact>();
        if (recipientContactIds != null && !recipientContactIds.isEmpty()) {
            try {
                contacts = [
                    SELECT Id, Name, Email
                    FROM Contact
                    WHERE Id IN :recipientContactIds
                ];
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

        if (recipientEmails != null) {
            for (String emailVal : recipientEmails) {
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
            return new EmailResult(false, 'No valid recipients found');
        }

        List<Messaging.EmailFileAttachment> attachmentList = buildAttachments(fileIds);
        if (attachmentList == null) {
            return new EmailResult(false, 'Total attachment size exceeds 25MB limit');
        }

        String link = buildCertificateLink(recordId, UserInfo.getUserId(), String.valueOf(Date.today()), false, roleParam);
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

        String bodyWithLink = replaceCertificateLink(htmlBody, link);
        bodyWithLink = applyOrganizationMergeFields(bodyWithLink);
        if (String.isBlank(bodyWithLink)) {
            bodyWithLink = '<a href="' + link + '">Click here</a>';
        }

        List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
        List<Messaging.SendEmailResult> results = new List<Messaging.SendEmailResult>();

        for (Integer index = 0; index < toSendEmails.size(); index++) {
            String recipientEmail = toSendEmails[index];
            String recipientName = toSendNames[index];
            if (String.isBlank(recipientEmail)) {
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ recipientEmail });
            if (String.isNotBlank(fromAddressId)) {
                mail.setOrgWideEmailAddressId(fromAddressId);
            }
            mail.setSubject(subject);
            mail.setHtmlBody(replaceContactName(bodyWithLink, recipientName));
            mail.setUseSignature(useEmailSignature == true);
            mail.setSaveAsActivity(saveAsActivity == true);
            if (recordId != null) {
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

        if (!batch.isEmpty()) {
            results.addAll(Messaging.sendEmail(batch));
        }

        if (results.isEmpty()) {
            return new EmailResult(false, 'No valid recipients found');
        }

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

    public static Boolean hasRecipients(List<String> contactIds, List<String> emails) {
        return (contactIds != null && !contactIds.isEmpty()) || (emails != null && !emails.isEmpty());
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

    public static String replaceCertificateLink(String body, String link) {
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

    public static String applyContactName(String body, String contactName, String token, String lastSelectedName) {
        if (String.isBlank(body) || String.isBlank(contactName)) {
            return body;
        }

        String updatedBody = body;
        if (String.isNotBlank(token) && updatedBody.contains(token)) {
            updatedBody = updatedBody.replace(token, contactName);
        } else if (String.isNotBlank(lastSelectedName) && updatedBody.contains(lastSelectedName)) {
            updatedBody = updatedBody.replace(lastSelectedName, contactName);
        } else {
            updatedBody = replaceContactName(updatedBody, contactName);
        }
        return updatedBody;
    }

    public static String applyFinalInspectionParamsToBody(
        String body,
        String recordId,
        Boolean isVendor,
        Boolean isCompany,
        List<String> companyContactIds,
        List<String> companyEmails,
        String fromAddressId,
        List<String> fileIds
    ) {
        if (String.isBlank(body)) {
            return body;
        }

        Pattern pattern = Pattern.compile('(?i)href="([^"]+)"');
        Matcher matcher = pattern.matcher(body);
        List<String> parts = new List<String>();
        Integer lastIndex = 0;

        while (matcher.find()) {
            parts.add(body.substring(lastIndex, matcher.start()));
            String url = matcher.group(1);
            String updatedUrl = url;
            if (String.isNotBlank(url) && url.contains('/apex/FinalInspectionForm')) {
                updatedUrl = addOrReplaceUrlParam(updatedUrl, 'recordId', recordId);
                updatedUrl = addOrReplaceUrlParam(updatedUrl, 'isPreview', 'false');
                updatedUrl = addOrReplaceUrlParam(updatedUrl, 'isVendor', String.valueOf(isVendor));
                updatedUrl = addOrReplaceUrlParam(updatedUrl, 'isCompany', String.valueOf(isCompany));
                updatedUrl = addJoinedParam(updatedUrl, 'companyContactIds', companyContactIds);
                updatedUrl = addJoinedParam(updatedUrl, 'companyEmails', companyEmails);
                updatedUrl = addJoinedParam(updatedUrl, 'fileIds', fileIds);
                if (String.isNotBlank(fromAddressId)) {
                    updatedUrl = addOrReplaceUrlParam(updatedUrl, 'fromAddressId', fromAddressId);
                }
            }
            parts.add('href="' + updatedUrl + '"');
            lastIndex = matcher.end();
        }

        parts.add(body.substring(lastIndex));
        return String.join(parts, '');
    }

    public class FinalInspectionSignatureState {
        public Boolean homeownerSigned { get; set; }
        public Boolean representativeSigned { get; set; }

        public FinalInspectionSignatureState(Boolean homeownerSigned, Boolean representativeSigned) {
            this.homeownerSigned = homeownerSigned;
            this.representativeSigned = representativeSigned;
        }
    }

    public static FinalInspectionSignatureState getFinalInspectionSignatureState(Id recordId) {
        if (recordId == null) {
            return new FinalInspectionSignatureState(false, false);
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
            return new FinalInspectionSignatureState(false, false);
        }

        SObject recordSObj = Database.query(
            'SELECT ' + String.join(queryFields, ',') + ' FROM buildertek__Inspection__c WHERE Id = :recordId LIMIT 1'
        );

        String homeownerSignId = fieldMap.containsKey('FI_Homeowner_Sign_Id__c')
            ? (String) recordSObj.get('FI_Homeowner_Sign_Id__c')
            : null;
        String representativeSignId = fieldMap.containsKey('FI_Representative_Sign_Id__c')
            ? (String) recordSObj.get('FI_Representative_Sign_Id__c')
            : null;

        return new FinalInspectionSignatureState(
            String.isNotBlank(homeownerSignId),
            String.isNotBlank(representativeSignId)
        );
    }

    public static Boolean isFinalInspectionAlreadySubmitted(Id recordId) {
        if (recordId == null) {
            return false;
        }

        for (ContentDocumentLink link : [
            SELECT ContentDocument.Title, ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ]) {
            if (link.ContentDocument != null
                && link.ContentDocument.FileType == 'PDF'
                && link.ContentDocument.Title != null
                && link.ContentDocument.Title.startsWith('Final Inspection ')) {
                return true;
            }
        }
        return false;
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

    public static String getConfirmationSiteUrl() {
        buildertek__ConfirmationSiteURL__c settings = buildertek__ConfirmationSiteURL__c.getOrgDefaults();
        if (settings != null && String.isNotBlank(settings.buildertek__Sites_URL__c)) {
            return normalizeBaseUrl(settings.buildertek__Sites_URL__c);
        }
        return normalizeBaseUrl(URL.getOrgDomainUrl().toExternalForm());
    }

    public static String normalizeBaseUrl(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.endsWith('/') ? value.substring(0, value.length() - 1) : value;
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

    public static Boolean isValidIdFormat(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        return Pattern.matches('^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$', value);
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
        public String templateId;
        public String fromAddress;
        public List<String> contractorContactIds;
        public List<String> contractorEmails;
        public List<String> homeownerContactIds;
        public List<String> homeownerEmails;
        public List<String> homsiteRepContactIds;
        public List<String> homsiteRepEmails;
        public List<String> codeEnforcementContactIds;
        public List<String> codeEnforcementEmails;
        public List<String> vendorContactIds;
        public List<String> vendorEmails;
        public List<String> companyContactIds;
        public List<String> companyEmails;
        public String subject;
        public String htmlBody;
        public String contactNameToken;
        public String lastSelectedContactName;
        public Boolean useEmailSignature;
        public Boolean saveAsActivity;
        public List<String> fileIds;
    }
}